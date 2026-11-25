-- =====================================================================
-- 03 - Procedimientos almacenados (PL/pgSQL)
-- Todos son SECURITY DEFINER: los usuarios operativos NO escriben
-- directamente en las tablas, solo ejecutan procedimientos que validan
-- las reglas del negocio (principio de mínimo privilegio).
-- =====================================================================

-- ---------------------------------------------------------------------
-- P1. Registrar (admitir) un envío en agencia.
--     - valida cliente, servicio, hubs (deben ser agencias) y accesibilidad
--       del destino (p.ej. Iquitos no tiene acceso terrestre),
--     - calcula peso, tarifa y fecha compromiso (SLA),
--     - inserta destinatario, envío, paquetes, comprobante y evento ADMISION
--       en UNA sola transacción.
--     p_paquetes: '[{"peso":1.2,"largo":30,"ancho":20,"alto":10,"descripcion":"Ropa","fragil":false}, ...]'
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE operacion.sp_registrar_envio(
    p_id_cliente        INTEGER,
    p_dest_nombre       VARCHAR,
    p_dest_documento    VARCHAR,
    p_dest_telefono     VARCHAR,
    p_direccion         VARCHAR,
    p_id_servicio       SMALLINT,
    p_id_agencia_origen INTEGER,
    p_id_agencia_destino INTEGER,
    p_paquetes          JSONB,
    p_metodo_pago       VARCHAR,
    p_id_empleado       INTEGER,
    INOUT p_nro_tracking CHAR(13) DEFAULT NULL
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = operacion, maestro, pg_temp AS
$$
DECLARE
    v_cli        maestro.cliente%ROWTYPE;
    v_serv       maestro.tipo_servicio%ROWTYPE;
    v_ag_o       RECORD;
    v_ag_d       RECORD;
    v_peso       NUMERIC(7,2);
    v_monto      NUMERIC(10,2);
    v_id_dest    INTEGER;
    v_id_envio   BIGINT;
    v_serie      CHAR(4);
    v_numero     INTEGER;
    v_ahora      TIMESTAMPTZ := clock_timestamp();
    v_sla        INTEGER;
    v_compromiso TIMESTAMPTZ;
    v_paq        JSONB;
    v_n          SMALLINT := 0;
BEGIN
    SELECT * INTO v_cli FROM maestro.cliente WHERE id_cliente = p_id_cliente;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cliente % no existe', p_id_cliente; END IF;

    SELECT * INTO v_serv FROM maestro.tipo_servicio WHERE id_servicio = p_id_servicio;
    IF NOT FOUND THEN RAISE EXCEPTION 'Servicio % no existe', p_id_servicio; END IF;

    SELECT h.id_hub, h.tipo, h.id_ciudad, c.id_region, c.acceso_terrestre INTO v_ag_o
      FROM maestro.hub h JOIN maestro.ciudad c USING (id_ciudad) WHERE h.id_hub = p_id_agencia_origen;
    SELECT h.id_hub, h.tipo, h.id_ciudad, c.id_region, c.acceso_terrestre INTO v_ag_d
      FROM maestro.hub h JOIN maestro.ciudad c USING (id_ciudad) WHERE h.id_hub = p_id_agencia_destino;
    IF v_ag_o.id_hub IS NULL OR v_ag_d.id_hub IS NULL OR v_ag_o.tipo <> 'AGENCIA' OR v_ag_d.tipo <> 'AGENCIA' THEN
        RAISE EXCEPTION 'Origen y destino deben ser agencias válidas';
    END IF;
    IF v_serv.modalidad = 'TERRESTRE' AND NOT (v_ag_o.acceso_terrestre AND v_ag_d.acceso_terrestre) THEN
        RAISE EXCEPTION 'El servicio % no está disponible: el destino no tiene acceso terrestre', v_serv.codigo;
    END IF;

    IF p_paquetes IS NULL OR jsonb_typeof(p_paquetes) <> 'array' OR jsonb_array_length(p_paquetes) = 0 THEN
        RAISE EXCEPTION 'Debe registrar al menos un paquete';
    END IF;
    SELECT SUM((x->>'peso')::NUMERIC) INTO v_peso FROM jsonb_array_elements(p_paquetes) x;

    v_monto := maestro.fn_calcular_tarifa(p_id_servicio, v_ag_o.id_region, v_ag_d.id_region, v_peso, v_ahora::DATE);
    v_sla   := CASE WHEN v_ag_o.id_ciudad = v_ag_d.id_ciudad THEN 48 ELSE v_serv.sla_horas END;
    -- el compromiso vence a las 20:00 del día que alcanza el SLA (domingo -> lunes)
    v_compromiso := date_trunc('day', v_ahora + make_interval(hours => v_sla)) + INTERVAL '20 hours';
    IF v_ahora + make_interval(hours => v_sla) > v_compromiso THEN
        v_compromiso := v_compromiso + INTERVAL '1 day';
    END IF;
    IF EXTRACT(ISODOW FROM v_compromiso) = 7 THEN
        v_compromiso := v_compromiso + INTERVAL '1 day';
    END IF;

    INSERT INTO operacion.destinatario (nombre, tipo_documento, nro_documento, telefono)
    VALUES (p_dest_nombre, CASE WHEN p_dest_documento IS NOT NULL THEN 'DNI' END, p_dest_documento, p_dest_telefono)
    RETURNING id_destinatario INTO v_id_dest;

    IF p_nro_tracking IS NULL THEN
        SELECT 'OLV' || LPAD((COALESCE(MAX(SUBSTRING(nro_tracking FROM 4)::BIGINT), 2600000000) + 1)::TEXT, 10, '0')
          INTO p_nro_tracking FROM operacion.envio;
    END IF;

    INSERT INTO operacion.envio (nro_tracking, id_cliente, id_destinatario, id_servicio, id_hub_origen, id_hub_destino,
                                 direccion_entrega, fecha_registro, fecha_compromiso, estado_actual,
                                 peso_total_kg, monto_total)
    VALUES (p_nro_tracking, p_id_cliente, v_id_dest, p_id_servicio, p_id_agencia_origen, p_id_agencia_destino,
            p_direccion, v_ahora, v_compromiso, 'REGISTRADO', v_peso, v_monto)
    RETURNING id_envio INTO v_id_envio;

    FOR v_paq IN SELECT * FROM jsonb_array_elements(p_paquetes) LOOP
        v_n := v_n + 1;
        INSERT INTO operacion.paquete (id_envio, nro_bulto, peso_kg, largo_cm, ancho_cm, alto_cm, descripcion, fragil)
        VALUES (v_id_envio, v_n, (v_paq->>'peso')::NUMERIC, (v_paq->>'largo')::NUMERIC, (v_paq->>'ancho')::NUMERIC,
                (v_paq->>'alto')::NUMERIC, COALESCE(v_paq->>'descripcion', 'Sin descripción'),
                COALESCE((v_paq->>'fragil')::BOOLEAN, FALSE));
    END LOOP;

    -- comprobante: FACTURA para empresas, BOLETA para personas; serie por agencia
    v_serie := CASE WHEN v_cli.tipo_cliente = 'EMPRESA' THEN 'F' ELSE 'B' END || LPAD(p_id_agencia_origen::TEXT, 3, '0');
    PERFORM pg_advisory_xact_lock(hashtext(v_serie));          -- numeración correlativa sin huecos por serie
    SELECT COALESCE(MAX(numero), 0) + 1 INTO v_numero FROM operacion.comprobante WHERE serie = v_serie;
    INSERT INTO operacion.comprobante (id_envio, tipo, serie, numero, fecha_emision, subtotal, igv, total, metodo_pago)
    VALUES (v_id_envio, CASE WHEN LEFT(v_serie, 1) = 'F' THEN 'FACTURA' ELSE 'BOLETA' END, v_serie, v_numero, v_ahora,
            ROUND(v_monto / 1.18, 2), v_monto - ROUND(v_monto / 1.18, 2), v_monto, p_metodo_pago);

    INSERT INTO operacion.evento_tracking (id_envio, tipo_evento, id_hub, id_empleado, fecha_hora, observacion)
    VALUES (v_id_envio, 'ADMISION', p_id_agencia_origen, p_id_empleado, v_ahora, 'Admisión en agencia');

    RAISE NOTICE 'Envío % registrado: % kg, S/ %, compromiso %', p_nro_tracking, v_peso, v_monto, v_compromiso;
END;
$$;

-- ---------------------------------------------------------------------
-- P2. Registrar un escaneo (evento de trazabilidad) validando la máquina
--     de estados del envío. Evita, por ejemplo, registrar una LLEGADA_HUB
--     de un envío que nunca salió, o escanear un envío ya entregado.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE operacion.sp_registrar_escaneo(
    p_nro_tracking  CHAR(13),
    p_tipo_evento   VARCHAR,
    p_id_hub        INTEGER,
    p_id_empleado   INTEGER,
    p_id_despacho   BIGINT DEFAULT NULL,
    p_observacion   VARCHAR DEFAULT NULL,
    p_fecha_hora    TIMESTAMPTZ DEFAULT NULL
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = operacion, maestro, pg_temp AS
$$
DECLARE
    v_envio      operacion.envio%ROWTYPE;
    v_permitidos TEXT[];
    v_ultimo     TIMESTAMPTZ;
    v_ruta       RECORD;
BEGIN
    -- FOR UPDATE: serializa escaneos concurrentes del mismo envío
    SELECT * INTO v_envio FROM operacion.envio WHERE nro_tracking = p_nro_tracking FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tracking % no existe', p_nro_tracking USING ERRCODE = 'no_data_found';
    END IF;

    v_permitidos := CASE v_envio.estado_actual
        WHEN 'REGISTRADO'      THEN ARRAY['ADMISION']
        WHEN 'ADMITIDO'        THEN ARRAY['SALIDA_HUB']
        WHEN 'EN_HUB'          THEN ARRAY['CLASIFICACION', 'SALIDA_HUB', 'EN_REPARTO']
        WHEN 'EN_TRANSITO'     THEN ARRAY['LLEGADA_HUB']
        WHEN 'EN_REPARTO'      THEN ARRAY['ENTREGA', 'INTENTO_FALLIDO']
        WHEN 'INTENTO_FALLIDO' THEN ARRAY['EN_REPARTO', 'DEVOLUCION']
        ELSE ARRAY[]::TEXT[] END;

    IF NOT (p_tipo_evento = ANY (v_permitidos)) THEN
        RAISE EXCEPTION 'Transición inválida: envío % en estado % no admite evento %',
              p_nro_tracking, v_envio.estado_actual, p_tipo_evento
              USING HINT = 'Eventos permitidos: ' || array_to_string(v_permitidos, ', ');
    END IF;

    IF p_tipo_evento IN ('SALIDA_HUB', 'LLEGADA_HUB') THEN
        SELECT r.id_hub_origen, r.id_hub_destino INTO v_ruta
          FROM operacion.despacho d JOIN maestro.ruta r USING (id_ruta) WHERE d.id_despacho = p_id_despacho;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El evento % requiere un despacho válido', p_tipo_evento;
        END IF;
        IF (p_tipo_evento = 'SALIDA_HUB' AND v_ruta.id_hub_origen <> p_id_hub) OR
           (p_tipo_evento = 'LLEGADA_HUB' AND v_ruta.id_hub_destino <> p_id_hub) THEN
            RAISE EXCEPTION 'El hub % no corresponde a la ruta del despacho %', p_id_hub, p_id_despacho;
        END IF;
    END IF;

    IF p_tipo_evento = 'EN_REPARTO' AND p_id_hub <> v_envio.id_hub_destino THEN
        RAISE EXCEPTION 'El reparto solo puede iniciarse en la agencia destino (%)', v_envio.id_hub_destino;
    END IF;

    SELECT MAX(fecha_hora) INTO v_ultimo FROM operacion.evento_tracking WHERE id_envio = v_envio.id_envio;
    IF COALESCE(p_fecha_hora, clock_timestamp()) < v_ultimo THEN
        RAISE EXCEPTION 'La fecha del escaneo (%) es anterior al último evento (%)', p_fecha_hora, v_ultimo;
    END IF;

    INSERT INTO operacion.evento_tracking (id_envio, tipo_evento, id_hub, id_empleado, id_despacho, fecha_hora, observacion)
    VALUES (v_envio.id_envio, p_tipo_evento, p_id_hub, p_id_empleado, p_id_despacho,
            COALESCE(p_fecha_hora, clock_timestamp()), p_observacion);
    -- el trigger trg_evento_actualiza_estado sincroniza envio.estado_actual
END;
$$;

-- ---------------------------------------------------------------------
-- P3. Registrar un intento de entrega.
--     - numera el intento (máx. 3),
--     - ENTREGADO: exige receptor, cierra el envío,
--     - DIRECCION_ERRADA: abre incidencia automáticamente,
--     - RECHAZADO o 3er intento fallido: genera DEVOLUCION.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE operacion.sp_registrar_intento_entrega(
    p_nro_tracking        CHAR(13),
    p_id_courier          INTEGER,
    p_resultado           VARCHAR,
    p_receptor_nombre     VARCHAR DEFAULT NULL,
    p_receptor_documento  VARCHAR DEFAULT NULL,
    p_fecha_hora          TIMESTAMPTZ DEFAULT NULL
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = operacion, maestro, pg_temp AS
$$
DECLARE
    v_envio    operacion.envio%ROWTYPE;
    v_intento  SMALLINT;
    v_t        TIMESTAMPTZ := COALESCE(p_fecha_hora, clock_timestamp());
BEGIN
    SELECT * INTO v_envio FROM operacion.envio WHERE nro_tracking = p_nro_tracking FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Tracking % no existe', p_nro_tracking; END IF;
    IF v_envio.estado_actual <> 'EN_REPARTO' THEN
        RAISE EXCEPTION 'El envío % no está en reparto (estado %)', p_nro_tracking, v_envio.estado_actual;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM maestro.empleado WHERE id_empleado = p_id_courier AND cargo = 'COURIER'
                      AND id_hub = v_envio.id_hub_destino AND activo) THEN
        RAISE EXCEPTION 'El empleado % no es courier activo de la agencia destino', p_id_courier;
    END IF;

    SELECT COALESCE(MAX(nro_intento), 0) + 1 INTO v_intento FROM operacion.intento_entrega WHERE id_envio = v_envio.id_envio;
    IF v_intento > 3 THEN RAISE EXCEPTION 'Se superó el máximo de 3 intentos'; END IF;

    IF p_resultado = 'ENTREGADO' THEN
        IF p_receptor_nombre IS NULL THEN RAISE EXCEPTION 'La entrega exige nombre del receptor'; END IF;
        INSERT INTO operacion.intento_entrega (id_envio, nro_intento, fecha_hora, id_courier, resultado, receptor_nombre, receptor_documento)
        VALUES (v_envio.id_envio, v_intento, v_t, p_id_courier, p_resultado, p_receptor_nombre, p_receptor_documento);
        CALL operacion.sp_registrar_escaneo(p_nro_tracking, 'ENTREGA', v_envio.id_hub_destino, p_id_courier,
                                            NULL, 'Recibido por ' || p_receptor_nombre, v_t);
        RETURN;   -- el trigger registra estado ENTREGADO y fecha_entrega
    END IF;

    INSERT INTO operacion.intento_entrega (id_envio, nro_intento, fecha_hora, id_courier, resultado)
    VALUES (v_envio.id_envio, v_intento, v_t, p_id_courier, p_resultado);
    CALL operacion.sp_registrar_escaneo(p_nro_tracking, 'INTENTO_FALLIDO', v_envio.id_hub_destino, p_id_courier,
                                        NULL, initcap(replace(p_resultado, '_', ' ')), v_t);

    IF p_resultado = 'DIRECCION_ERRADA' THEN
        INSERT INTO operacion.incidencia (id_envio, tipo, id_hub, fecha_reporte, descripcion)
        VALUES (v_envio.id_envio, 'DIRECCION_INCORRECTA', v_envio.id_hub_destino, v_t,
                'Dirección de entrega no ubicada por el courier (intento ' || v_intento || ')');
    END IF;

    IF p_resultado = 'RECHAZADO' OR v_intento = 3 THEN
        CALL operacion.sp_registrar_escaneo(p_nro_tracking, 'DEVOLUCION', v_envio.id_hub_destino, p_id_courier,
                                            NULL, CASE WHEN p_resultado = 'RECHAZADO' THEN 'Rechazado por destinatario'
                                                       ELSE 'Tres intentos fallidos' END, v_t + INTERVAL '1 minute');
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- P4. Cerrar (arribar) un despacho: marca el manifiesto como ARRIBADO y
--     registra en bloque la LLEGADA_HUB de todos los envíos que transporta.
--     Devuelve la cantidad de envíos procesados.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE operacion.sp_cerrar_despacho(
    p_id_despacho   BIGINT,
    p_fecha_llegada TIMESTAMPTZ,
    p_id_empleado   INTEGER,
    INOUT p_envios_procesados INTEGER DEFAULT 0
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = operacion, maestro, pg_temp AS
$$
DECLARE
    v_desp  operacion.despacho%ROWTYPE;
    v_hub   INTEGER;
    v_trk   CHAR(13);
BEGIN
    SELECT * INTO v_desp FROM operacion.despacho WHERE id_despacho = p_id_despacho FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Despacho % no existe', p_id_despacho; END IF;
    IF v_desp.estado <> 'EN_RUTA' THEN
        RAISE EXCEPTION 'Solo se puede cerrar un despacho EN_RUTA (actual: %)', v_desp.estado;
    END IF;
    IF p_fecha_llegada <= v_desp.fecha_salida_real THEN
        RAISE EXCEPTION 'La llegada debe ser posterior a la salida (%)', v_desp.fecha_salida_real;
    END IF;

    SELECT id_hub_destino INTO v_hub FROM maestro.ruta WHERE id_ruta = v_desp.id_ruta;

    UPDATE operacion.despacho
       SET estado = 'ARRIBADO', fecha_llegada_real = p_fecha_llegada
     WHERE id_despacho = p_id_despacho;

    p_envios_procesados := 0;
    FOR v_trk IN
        SELECT e.nro_tracking
          FROM operacion.despacho_envio de JOIN operacion.envio e USING (id_envio)
         WHERE de.id_despacho = p_id_despacho AND e.estado_actual = 'EN_TRANSITO'
         ORDER BY e.id_envio
    LOOP
        CALL operacion.sp_registrar_escaneo(v_trk, 'LLEGADA_HUB', v_hub, p_id_empleado, p_id_despacho,
                                            'Arribo de manifiesto ' || v_desp.codigo_manifiesto, p_fecha_llegada);
        p_envios_procesados := p_envios_procesados + 1;
    END LOOP;
END;
$$;
