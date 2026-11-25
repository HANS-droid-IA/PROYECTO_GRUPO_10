-- =====================================================================
-- 02 - Funciones almacenadas (PL/pgSQL)
-- =====================================================================

-- ---------------------------------------------------------------------
-- F1. Calcula la tarifa de un envío según servicio, regiones y peso.
--     Regla: precio_base + ceil(peso - 1 kg) * precio_kg_adicional
--     usando la tarifa vigente a la fecha indicada.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION maestro.fn_calcular_tarifa(
    p_id_servicio        SMALLINT,
    p_id_region_origen   SMALLINT,
    p_id_region_destino  SMALLINT,
    p_peso_kg            NUMERIC,
    p_fecha              DATE DEFAULT CURRENT_DATE
) RETURNS NUMERIC(10,2)
LANGUAGE plpgsql STABLE AS
$$
DECLARE
    v_tarifa   maestro.tarifa%ROWTYPE;
    v_peso_max NUMERIC;
BEGIN
    IF p_peso_kg IS NULL OR p_peso_kg <= 0 THEN
        RAISE EXCEPTION 'El peso debe ser mayor a cero (recibido: %)', p_peso_kg;
    END IF;

    SELECT peso_max_kg INTO v_peso_max FROM maestro.tipo_servicio WHERE id_servicio = p_id_servicio;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Servicio % no existe', p_id_servicio;
    END IF;
    IF p_peso_kg > v_peso_max THEN
        RAISE EXCEPTION 'Peso % kg excede el máximo del servicio (% kg)', p_peso_kg, v_peso_max;
    END IF;

    SELECT * INTO v_tarifa
      FROM maestro.tarifa
     WHERE id_servicio = p_id_servicio
       AND id_region_origen = p_id_region_origen
       AND id_region_destino = p_id_region_destino
       AND vigente_desde <= p_fecha
       AND (vigente_hasta IS NULL OR vigente_hasta > p_fecha)
     ORDER BY vigente_desde DESC
     LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay tarifa vigente para servicio %, regiones % -> % al %',
              p_id_servicio, p_id_region_origen, p_id_region_destino, p_fecha;
    END IF;

    RETURN ROUND(v_tarifa.precio_base + GREATEST(0, CEIL(p_peso_kg - 1)) * v_tarifa.precio_kg_adicional, 2);
END;
$$;
COMMENT ON FUNCTION maestro.fn_calcular_tarifa IS 'Tarifa vigente = base + kg adicionales (redondeo hacia arriba)';

-- ---------------------------------------------------------------------
-- F2. Estado del envío respecto al SLA (acuerdo de nivel de servicio).
--     p_corte permite evaluar "como si fuera" otra fecha (simulación).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION operacion.fn_estado_sla(
    p_id_envio  BIGINT,
    p_corte     TIMESTAMPTZ DEFAULT now()
) RETURNS VARCHAR
LANGUAGE plpgsql STABLE AS
$$
DECLARE
    v_e operacion.envio%ROWTYPE;
BEGIN
    SELECT * INTO v_e FROM operacion.envio WHERE id_envio = p_id_envio;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    IF v_e.estado_actual = 'ENTREGADO' THEN
        RETURN CASE WHEN v_e.fecha_entrega <= v_e.fecha_compromiso THEN 'ENTREGADO_A_TIEMPO'
                    ELSE 'ENTREGADO_CON_RETRASO' END;
    ELSIF v_e.estado_actual = 'DEVUELTO' THEN
        RETURN 'DEVUELTO';
    ELSIF p_corte > v_e.fecha_compromiso THEN
        RETURN 'VENCIDO';
    ELSIF v_e.fecha_compromiso - p_corte <= INTERVAL '6 hours' THEN
        RETURN 'EN_RIESGO';
    END IF;
    RETURN 'EN_PLAZO';
END;
$$;

-- ---------------------------------------------------------------------
-- F3. Tiempo de permanencia de un envío en un hub (llegada -> salida).
--     Si aún no sale, mide hasta p_corte. Base del análisis de cuellos de botella.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION operacion.fn_permanencia_hub(
    p_id_envio  BIGINT,
    p_id_hub    INTEGER,
    p_corte     TIMESTAMPTZ DEFAULT now()
) RETURNS INTERVAL
LANGUAGE sql STABLE AS
$$
    WITH llegada AS (
        SELECT MIN(fecha_hora) AS t
          FROM operacion.evento_tracking
         WHERE id_envio = p_id_envio AND id_hub = p_id_hub
           AND tipo_evento IN ('LLEGADA_HUB', 'ADMISION')
    )
    SELECT COALESCE(
               (SELECT MIN(e.fecha_hora)
                  FROM operacion.evento_tracking e
                 WHERE e.id_envio = p_id_envio AND e.id_hub = p_id_hub
                   AND e.tipo_evento IN ('SALIDA_HUB', 'EN_REPARTO')
                   AND e.fecha_hora >= l.t),
               p_corte) - l.t
      FROM llegada l
     WHERE l.t IS NOT NULL;
$$;

-- ---------------------------------------------------------------------
-- F4. Función de tabla: ranking de cuellos de botella por hub y franja horaria
--     (función de ventana LEAD: una sola lectura de los eventos)
--     de llegada. Devuelve permanencia promedio, P90 y % de envíos que
--     superan el umbral (horas) en el periodo indicado.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION operacion.fn_cuellos_botella(
    p_desde         TIMESTAMPTZ,
    p_hasta         TIMESTAMPTZ,
    p_umbral_horas  NUMERIC DEFAULT 12
) RETURNS TABLE (
    hub                   VARCHAR,
    franja_llegada        TEXT,
    envios                BIGINT,
    permanencia_prom_h    NUMERIC,
    permanencia_p90_h     NUMERIC,
    pct_sobre_umbral      NUMERIC
)
LANGUAGE sql STABLE AS
$$
    WITH movimientos AS (
        SELECT id_envio, id_hub, tipo_evento, fecha_hora,
               LEAD(tipo_evento) OVER w AS sig_tipo,
               LEAD(id_hub)      OVER w AS sig_hub,
               LEAD(fecha_hora)  OVER w AS sig_fecha
          FROM operacion.evento_tracking
         WHERE tipo_evento IN ('LLEGADA_HUB', 'SALIDA_HUB')
           AND fecha_hora >= p_desde AND fecha_hora < p_hasta + INTERVAL '7 days'
        WINDOW w AS (PARTITION BY id_envio ORDER BY fecha_hora, id_evento)
    ), estancias AS (
        SELECT id_hub, fecha_hora AS llegada,
               EXTRACT(EPOCH FROM sig_fecha - fecha_hora) / 3600.0 AS horas
          FROM movimientos
         WHERE tipo_evento = 'LLEGADA_HUB' AND sig_tipo = 'SALIDA_HUB' AND sig_hub = id_hub
           AND fecha_hora < p_hasta
    )
    SELECT h.codigo,
           CASE WHEN EXTRACT(HOUR FROM e.llegada) < 6  THEN '00-06'
                WHEN EXTRACT(HOUR FROM e.llegada) < 12 THEN '06-12'
                WHEN EXTRACT(HOUR FROM e.llegada) < 18 THEN '12-18'
                ELSE '18-24' END,
           COUNT(*),
           ROUND(AVG(e.horas)::NUMERIC, 2),
           ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY e.horas)::NUMERIC, 2),
           ROUND(100.0 * COUNT(*) FILTER (WHERE e.horas > p_umbral_horas) / COUNT(*), 1)
      FROM estancias e
      JOIN maestro.hub h ON h.id_hub = e.id_hub
     WHERE h.tipo <> 'AGENCIA'
     GROUP BY 1, 2
     ORDER BY 4 DESC;
$$;
COMMENT ON FUNCTION operacion.fn_cuellos_botella IS 'Ranking de permanencia en hubs por franja horaria de llegada';
