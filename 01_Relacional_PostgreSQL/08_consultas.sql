-- =====================================================================
-- 08 - Consultas SQL representativas (preguntas de negocio)
-- Fecha de corte de la simulación: 2026-10-07 18:00 (-05)
-- Estructura para el informe: Problema -> SQL -> Resultado -> Interpretación
-- =====================================================================
\pset footer off
SET search_path = operacion, maestro, public;

-- ---------------------------------------------------------------------
\echo '=== C01. Línea de tiempo (tracking) de un envío con tiempo entre escaneos ==='
-- Problema: atención al cliente necesita reconstruir el recorrido completo de un envío
-- y detectar en qué tramo se demoró. Técnica: JOINs + función de ventana LAG.
-- ---------------------------------------------------------------------
SELECT ev.fecha_hora::TIMESTAMP(0)                       AS fecha_hora,
       ev.tipo_evento,
       h.codigo                                          AS hub,
       c.nombre                                          AS ciudad,
       d.codigo_manifiesto                               AS manifiesto,
       COALESCE(d.nro_vuelo, v.placa)                    AS transporte,
       ev.fecha_hora - LAG(ev.fecha_hora) OVER (ORDER BY ev.fecha_hora, ev.id_evento) AS desde_evento_anterior
  FROM evento_tracking ev
  JOIN envio e      ON e.id_envio = ev.id_envio
  JOIN hub h        ON h.id_hub = ev.id_hub
  JOIN ciudad c     ON c.id_ciudad = h.id_ciudad
  LEFT JOIN despacho d ON d.id_despacho = ev.id_despacho
  LEFT JOIN vehiculo v ON v.id_vehiculo = d.id_vehiculo
 WHERE e.nro_tracking = 'OLV2600001112'
 ORDER BY ev.fecha_hora, ev.id_evento;

-- ---------------------------------------------------------------------
\echo '=== C02. Cumplimiento de SLA por servicio y mes ==='
-- Problema: la gerencia necesita saber qué servicio incumple su promesa de entrega.
-- Técnica: agregación condicional (FILTER) y DATE_TRUNC.
-- ---------------------------------------------------------------------
SELECT to_char(date_trunc('month', e.fecha_registro), 'YYYY-MM')              AS mes,
       ts.codigo                                                              AS servicio,
       COUNT(*)                                                               AS entregados,
       ROUND(100.0 * COUNT(*) FILTER (WHERE e.fecha_entrega <= e.fecha_compromiso) / COUNT(*), 1) AS pct_a_tiempo,
       ROUND(AVG(EXTRACT(EPOCH FROM e.fecha_entrega - e.fecha_registro) / 3600)::NUMERIC, 1)     AS horas_prom
  FROM envio e
  JOIN tipo_servicio ts USING (id_servicio)
 WHERE e.estado_actual = 'ENTREGADO'
 GROUP BY 1, 2
 ORDER BY 1, 2;

-- ---------------------------------------------------------------------
\echo '=== C03. Cuellos de botella: permanencia en hubs por franja horaria (función de tabla) ==='
-- Problema: ¿en qué hub y en qué franja horaria los paquetes se quedan más tiempo?
-- Técnica: función de tabla con LATERAL + PERCENTILE_CONT.
-- ---------------------------------------------------------------------
SELECT * FROM fn_cuellos_botella('2026-04-01', '2026-10-08', 12) LIMIT 10;

-- ---------------------------------------------------------------------
\echo '=== C04. Impacto del cuello de botella del Hub Central en el SLA ==='
-- Problema: cuantificar cuánto empeora el cumplimiento cuando el envío pasa más de 12 h en HC-LIM.
-- Técnica: vista materializada + CTE + DISTINCT ON.
-- ---------------------------------------------------------------------
WITH paso_hc AS (
    SELECT DISTINCT ON (id_envio) id_envio, horas_permanencia
      FROM mv_permanencia_hub
     WHERE id_hub = (SELECT id_hub FROM hub WHERE codigo = 'HC-LIM')
     ORDER BY id_envio, llegada
)
SELECT ts.modalidad,
       CASE WHEN p.horas_permanencia > 12 THEN 'Más de 12 h en HC' ELSE 'Hasta 12 h en HC' END AS permanencia_hc,
       COUNT(*)                                                                            AS envios,
       ROUND(AVG(p.horas_permanencia), 1)                                                  AS horas_hc_prom,
       ROUND(100.0 * AVG((e.fecha_entrega <= e.fecha_compromiso)::INT), 1)                 AS pct_a_tiempo
  FROM paso_hc p
  JOIN envio e USING (id_envio)
  JOIN tipo_servicio ts USING (id_servicio)
 WHERE e.estado_actual = 'ENTREGADO'
 GROUP BY 1, 2
 ORDER BY 1, 2;

-- ---------------------------------------------------------------------
\echo '=== C05. Puntualidad de despachos por ruta (salida real vs programada) ==='
-- Problema: identificar las rutas cuyos camiones o vuelos salen sistemáticamente tarde.
-- Técnica: JOIN múltiple a la misma tabla (hub origen/destino) + HAVING.
-- ---------------------------------------------------------------------
SELECT ho.codigo || ' -> ' || hd.codigo                                                AS ruta,
       r.modalidad,
       COUNT(*)                                                                         AS despachos,
       ROUND(AVG(EXTRACT(EPOCH FROM d.fecha_salida_real - d.fecha_salida_prog) / 60)::NUMERIC, 1) AS demora_salida_min,
       ROUND(100.0 * AVG((d.fecha_salida_real - d.fecha_salida_prog > INTERVAL '60 minutes')::INT), 1) AS pct_demora_mayor_1h,
       ROUND(AVG(EXTRACT(EPOCH FROM d.fecha_llegada_real - d.fecha_salida_real) / 3600 - r.tiempo_estimado_horas)::NUMERIC, 2) AS desvio_viaje_h
  FROM despacho d
  JOIN ruta r ON r.id_ruta = d.id_ruta
  JOIN hub ho ON ho.id_hub = r.id_hub_origen
  JOIN hub hd ON hd.id_hub = r.id_hub_destino
 WHERE d.estado = 'ARRIBADO' AND ho.tipo <> 'AGENCIA' AND hd.tipo <> 'AGENCIA'
 GROUP BY 1, 2
HAVING COUNT(*) >= 30
 ORDER BY desvio_viaje_h DESC
 LIMIT 10;

-- ---------------------------------------------------------------------
\echo '=== C06. Matriz de ingresos región origen x destino con subtotales (ROLLUP) ==='
-- Problema: finanzas quiere conocer los corredores más rentables.
-- Técnica: GROUP BY ROLLUP + GROUPING().
-- ---------------------------------------------------------------------
SELECT CASE WHEN GROUPING(ro.nombre) = 1 THEN '** TOTAL **' ELSE ro.nombre END   AS region_origen,
       CASE WHEN GROUPING(rd.nombre) = 1 THEN '(subtotal)'  ELSE rd.nombre END   AS region_destino,
       COUNT(*)                                                                  AS envios,
       SUM(e.monto_total)                                                        AS ingresos_soles,
       ROUND(AVG(e.monto_total), 2)                                              AS ticket_prom
  FROM envio e
  JOIN hub ho ON ho.id_hub = e.id_hub_origen  JOIN ciudad co ON co.id_ciudad = ho.id_ciudad JOIN region ro ON ro.id_region = co.id_region
  JOIN hub hd ON hd.id_hub = e.id_hub_destino JOIN ciudad cd ON cd.id_ciudad = hd.id_ciudad JOIN region rd ON rd.id_region = cd.id_region
 GROUP BY ROLLUP (ro.nombre, rd.nombre)
 ORDER BY GROUPING(ro.nombre), ro.nombre, GROUPING(rd.nombre), ingresos_soles DESC;

-- ---------------------------------------------------------------------
\echo '=== C07. Top 10 clientes empresariales: facturación, participación y puntualidad ==='
-- Problema: el área comercial necesita priorizar cuentas clave y detectar riesgo de fuga
-- (clientes grandes con mala puntualidad). Técnica: CTE + RANK + ventana SUM() OVER ().
-- ---------------------------------------------------------------------
WITH por_cliente AS (
    SELECT c.id_cliente, c.nombre_razon_social, ci.nombre AS ciudad,
           COUNT(*)                                                           AS envios,
           SUM(e.monto_total)                                                 AS facturado,
           ROUND(100.0 * AVG((e.fecha_entrega <= e.fecha_compromiso)::INT)
                 FILTER (WHERE e.estado_actual = 'ENTREGADO'), 1)             AS pct_a_tiempo
      FROM envio e
      JOIN cliente c USING (id_cliente)
      JOIN ciudad ci ON ci.id_ciudad = c.id_ciudad
     WHERE c.tipo_cliente = 'EMPRESA'
     GROUP BY 1, 2, 3
)
SELECT RANK() OVER (ORDER BY facturado DESC)                         AS puesto,
       nombre_razon_social, ciudad, envios, facturado,
       ROUND(100.0 * facturado / SUM(facturado) OVER (), 2)          AS pct_facturacion_empresas,
       pct_a_tiempo
  FROM por_cliente
 ORDER BY facturado DESC
 LIMIT 10;

-- ---------------------------------------------------------------------
\echo '=== C08. Efectividad de entrega al primer intento por ciudad y motivos de falla ==='
-- Problema: las visitas fallidas encarecen la última milla; ¿dónde ocurren y por qué?
-- Técnica: agregación condicional + STRING_AGG ordenado.
-- ---------------------------------------------------------------------
WITH intentos AS (
    SELECT c.nombre AS ciudad, i.*
      FROM intento_entrega i
      JOIN envio e USING (id_envio)
      JOIN hub h ON h.id_hub = e.id_hub_destino
      JOIN ciudad c ON c.id_ciudad = h.id_ciudad
), motivos AS (
    SELECT ciudad, resultado, COUNT(*) AS n
      FROM intentos WHERE resultado <> 'ENTREGADO' GROUP BY 1, 2
)
SELECT i.ciudad,
       COUNT(DISTINCT i.id_envio)                                                         AS envios_en_reparto,
       ROUND(100.0 * COUNT(*) FILTER (WHERE nro_intento = 1 AND resultado = 'ENTREGADO')
             / COUNT(DISTINCT i.id_envio), 1)                                             AS pct_primer_intento,
       ROUND(COUNT(*)::NUMERIC / COUNT(DISTINCT i.id_envio), 2)                           AS intentos_por_envio,
       (SELECT STRING_AGG(m.resultado || ':' || m.n, ', ' ORDER BY m.n DESC)
          FROM motivos m WHERE m.ciudad = i.ciudad)                                       AS motivos_falla
  FROM intentos i
 GROUP BY i.ciudad
 ORDER BY pct_primer_intento
 LIMIT 10;

-- ---------------------------------------------------------------------
\echo '=== C09. Alerta operativa: envíos vivos vencidos o en riesgo al corte ==='
-- Problema: el centro de control debe actuar sobre envíos que van a incumplir.
-- Técnica: función almacenada fn_estado_sla + índice parcial de envíos vivos.
-- ---------------------------------------------------------------------
SELECT e.nro_tracking, ts.codigo AS servicio, ho.codigo AS origen, hd.codigo AS destino,
       e.estado_actual, e.fecha_compromiso::TIMESTAMP(0) AS compromiso,
       fn_estado_sla(e.id_envio, '2026-10-07 18:00-05') AS estado_sla,
       (SELECT h.codigo FROM evento_tracking x JOIN hub h USING (id_hub)
         WHERE x.id_envio = e.id_envio ORDER BY x.fecha_hora DESC LIMIT 1) AS ultima_ubicacion
  FROM envio e
  JOIN tipo_servicio ts USING (id_servicio)
  JOIN hub ho ON ho.id_hub = e.id_hub_origen
  JOIN hub hd ON hd.id_hub = e.id_hub_destino
 WHERE e.estado_actual NOT IN ('ENTREGADO', 'DEVUELTO')
   AND fn_estado_sla(e.id_envio, '2026-10-07 18:00-05') IN ('VENCIDO', 'EN_RIESGO')
 ORDER BY e.fecha_compromiso
 LIMIT 15;

-- ---------------------------------------------------------------------
\echo '=== C10. Incidencias por tipo y hub: volumen, abiertas y tiempo medio de resolución ==='
-- Problema: calidad necesita saber qué hubs generan más daños/pérdidas y cuánto tarda en cerrarlas.
-- Técnica: LEFT JOIN + agregación condicional + intervalos.
-- ---------------------------------------------------------------------
SELECT i.tipo,
       COALESCE(h.codigo, '(reclamo cliente)')                                  AS hub,
       COUNT(*)                                                                 AS incidencias,
       COUNT(*) FILTER (WHERE i.estado <> 'CERRADA')                            AS pendientes,
       ROUND(AVG(EXTRACT(EPOCH FROM i.fecha_cierre - i.fecha_reporte) / 86400)::NUMERIC, 1) AS dias_resolucion_prom
  FROM incidencia i
  LEFT JOIN hub h ON h.id_hub = i.id_hub
 WHERE i.tipo IN ('DANO', 'PERDIDA', 'RETRASO')
 GROUP BY 1, 2
 ORDER BY 1, 3 DESC;

-- ---------------------------------------------------------------------
\echo '=== C11. Productividad de couriers: entregas efectivas por día trabajado, ranking por agencia ==='
-- Problema: dimensionar personal de reparto. Técnica: DENSE_RANK particionado.
-- ---------------------------------------------------------------------
WITH prod AS (
    SELECT emp.id_hub, emp.nombres || ' ' || emp.apellidos AS courier,
           COUNT(*) FILTER (WHERE i.resultado = 'ENTREGADO')              AS entregas,
           COUNT(DISTINCT i.fecha_hora::DATE)                             AS dias_trabajados
      FROM intento_entrega i
      JOIN empleado emp ON emp.id_empleado = i.id_courier
     GROUP BY 1, 2
)
SELECT * FROM (
    SELECT h.codigo AS agencia, p.courier, p.entregas, p.dias_trabajados,
           ROUND(p.entregas::NUMERIC / NULLIF(p.dias_trabajados, 0), 2)            AS entregas_por_dia,
           DENSE_RANK() OVER (PARTITION BY p.id_hub ORDER BY p.entregas DESC)       AS rank_agencia
      FROM prod p JOIN hub h ON h.id_hub = p.id_hub
) t
 WHERE agencia LIKE 'AG-LIM%'
 ORDER BY agencia, rank_agencia;

-- ---------------------------------------------------------------------
\echo '=== C12. Envíos estancados: sin escaneo en más de 48 h (posible pérdida) ==='
-- Problema: detectar paquetes "perdidos en el sistema" antes de que el cliente reclame.
-- Técnica: LATERAL para el último evento + NOT EXISTS de incidencias abiertas.
-- ---------------------------------------------------------------------
SELECT e.nro_tracking, e.estado_actual, ult.hub, ult.fecha_hora::TIMESTAMP(0) AS ultimo_escaneo,
       date_trunc('hour', TIMESTAMPTZ '2026-10-07 18:00-05' - ult.fecha_hora) AS sin_movimiento,
       EXISTS (SELECT 1 FROM incidencia i WHERE i.id_envio = e.id_envio AND i.tipo = 'PERDIDA') AS tiene_incidencia_perdida
  FROM envio e
  CROSS JOIN LATERAL (
        SELECT h.codigo AS hub, x.fecha_hora
          FROM evento_tracking x JOIN hub h USING (id_hub)
         WHERE x.id_envio = e.id_envio
         ORDER BY x.fecha_hora DESC LIMIT 1) ult
 WHERE e.estado_actual NOT IN ('ENTREGADO', 'DEVUELTO')
   AND ult.fecha_hora < TIMESTAMPTZ '2026-10-07 18:00-05' - INTERVAL '48 hours'
 ORDER BY ult.fecha_hora
 LIMIT 15;

-- ---------------------------------------------------------------------
\echo '=== C13. Ocupación horaria del Hub Central vs capacidad (picos de demanda) ==='
-- Problema: ¿a qué hora llegan más paquetes de los que el hub puede procesar?
-- Técnica: generate_series + agregación por hora del día.
-- ---------------------------------------------------------------------
WITH llegadas AS (
    SELECT EXTRACT(HOUR FROM fecha_hora)::INT AS hora, COUNT(*) AS n,
           COUNT(DISTINCT fecha_hora::DATE)  AS dias
      FROM evento_tracking
     WHERE tipo_evento = 'LLEGADA_HUB' AND id_hub = (SELECT id_hub FROM hub WHERE codigo = 'HC-LIM')
     GROUP BY 1
)
SELECT g.hora,
       COALESCE(ROUND(l.n::NUMERIC / NULLIF(l.dias, 0), 1), 0)                          AS llegadas_prom_por_dia,
       h.capacidad_hora,
       COALESCE(ROUND(100.0 * l.n / NULLIF(l.dias, 0) / h.capacidad_hora, 1), 0)         AS pct_capacidad,
       repeat('#', COALESCE((l.n / NULLIF(l.dias, 0) / 10)::INT, 0))                     AS grafico
  FROM generate_series(0, 23) AS g(hora)
  LEFT JOIN llegadas l ON l.hora = g.hora
  CROSS JOIN (SELECT capacidad_hora FROM hub WHERE codigo = 'HC-LIM') h
 ORDER BY g.hora;
