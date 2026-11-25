-- 6.5 Consultas representativas y pruebas de funciones, procedimientos y seguridad
-- Uso: psql -h localhost -p 5432 -U postgres -f 02_consultas_y_pruebas.sql
\connect olva_courier_pg


-- #####################################################################
-- 6.5 CONSULTAS SQL REPRESENTATIVAS
-- #####################################################################
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


-- #####################################################################
-- PRUEBAS 7.1 / 7.2 FUNCIONES, PROCEDIMIENTOS Y TRIGGERS
-- #####################################################################
-- =====================================================================
-- 09 - Pruebas de funciones, procedimientos y triggers
-- Simula el ciclo completo de un envío Lima (Miraflores) -> Lima (Surco)
-- y casos de error controlados. Todo corre dentro de una transacción que
-- se revierte al final para no alterar los datos de prueba.
-- =====================================================================
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
\pset footer off
SET search_path = operacion, maestro, public;
SET client_min_messages = notice;

BEGIN;

-- Datos de apoyo (IDs obtenidos por código, no "quemados")
SELECT id_hub AS ag_mir FROM hub WHERE codigo = 'AG-LIM-MIR' \gset
SELECT id_hub AS ag_sur FROM hub WHERE codigo = 'AG-LIM-SUR' \gset
SELECT id_hub AS ag_iqt FROM hub WHERE codigo = 'AG-IQT-01' \gset
SELECT id_hub AS hc     FROM hub WHERE codigo = 'HC-LIM' \gset
SELECT MIN(id_empleado) AS emp_atencion FROM empleado WHERE id_hub = :ag_mir AND cargo = 'ATENCION' \gset
SELECT MIN(id_empleado) AS emp_operario FROM empleado WHERE id_hub = :hc AND cargo = 'OPERARIO_HUB' \gset
SELECT MIN(id_empleado) AS emp_courier  FROM empleado WHERE id_hub = :ag_sur AND cargo = 'COURIER' \gset
SELECT MIN(id_vehiculo) AS veh_mir FROM vehiculo WHERE id_hub_base = :ag_mir AND tipo = 'FURGONETA' \gset
SELECT MIN(id_vehiculo) AS veh_hc  FROM vehiculo WHERE id_hub_base = :hc AND tipo = 'FURGONETA' \gset
SELECT id_ruta AS ruta_mir_hc FROM ruta WHERE id_hub_origen = :ag_mir AND id_hub_destino = :hc AND modalidad = 'TERRESTRE' \gset
SELECT id_ruta AS ruta_hc_sur FROM ruta WHERE id_hub_origen = :hc AND id_hub_destino = :ag_sur AND modalidad = 'TERRESTRE' \gset
SELECT MIN(id_cliente) AS cliente FROM cliente WHERE tipo_cliente = 'EMPRESA' \gset

\echo '=== F1. fn_calcular_tarifa ==='
SELECT ts.codigo AS servicio, r1.nombre AS origen, r2.nombre AS destino, p.peso,
       fn_calcular_tarifa(ts.id_servicio, r1.id_region, r2.id_region, p.peso) AS tarifa_soles
  FROM tipo_servicio ts
  CROSS JOIN (VALUES (0.4), (2.5), (12.0)) p(peso)
  JOIN region r1 ON r1.codigo = 'LIM'
  JOIN region r2 ON r2.codigo = 'ORI'
 WHERE p.peso <= ts.peso_max_kg
 ORDER BY 1, 4;

\echo '--- F1 error esperado: peso mayor al permitido para SOBRE_AEREO (0.5 kg)'
SELECT fn_calcular_tarifa(2::SMALLINT, 1::SMALLINT, 4::SMALLINT, 3.0);

\echo '=== P1. sp_registrar_envio: envío empresarial Lima (Miraflores) -> Lima (Surco) ==='
CALL sp_registrar_envio(:cliente, 'Ana Torres Ríos', '45871236', '987654321', 'Av. Primavera 1450, Surco',
                        3::SMALLINT, :ag_mir, :ag_sur,
                        '[{"peso": 2.3, "largo": 40, "ancho": 30, "alto": 20, "descripcion": "Repuestos"},
                          {"peso": 0.8, "largo": 25, "ancho": 20, "alto": 10, "descripcion": "Accesorios", "fragil": true}]',
                        'CREDITO', :emp_atencion, NULL);
SELECT MAX(nro_tracking) AS trk FROM envio \gset
SELECT nro_tracking, estado_actual, peso_total_kg, monto_total, fecha_compromiso::TIMESTAMP(0)
  FROM envio WHERE nro_tracking = :'trk';
SELECT c.tipo, c.serie, c.numero, c.subtotal, c.igv, c.total
  FROM comprobante c JOIN envio e USING (id_envio) WHERE e.nro_tracking = :'trk';

\echo '--- P1 error esperado: servicio TERRESTRE hacia Iquitos (sin acceso por carretera)'
CALL sp_registrar_envio(:cliente, 'Luis Ríos', NULL, '912345678', 'Calle Próspero 300', 3::SMALLINT, :ag_mir, :ag_iqt,
                        '[{"peso": 1, "largo": 20, "ancho": 20, "alto": 20}]', 'TARJETA', :emp_atencion, NULL);

\echo '=== T3. trg_validar_despacho ==='
\echo '--- error esperado: despacho terrestre con un vehículo que no pertenece a la ruta'
INSERT INTO despacho (codigo_manifiesto, id_ruta, id_vehiculo, fecha_salida_prog, estado)
SELECT 'MF-PRUEBA-ERR', :ruta_mir_hc, MIN(id_vehiculo), now(), 'PROGRAMADO'
  FROM vehiculo WHERE id_hub_base = (SELECT id_hub FROM hub WHERE codigo = 'HR-CUZ');

\echo '--- despacho válido Miraflores -> Hub Central (furgoneta de la agencia)'
INSERT INTO despacho (codigo_manifiesto, id_ruta, id_vehiculo, fecha_salida_prog, fecha_salida_real, estado)
VALUES ('MF-PRUEBA-001', :ruta_mir_hc, :veh_mir, now(), clock_timestamp(), 'EN_RUTA')
RETURNING id_despacho AS desp1 \gset
INSERT INTO despacho_envio SELECT :desp1, id_envio, now() FROM envio WHERE nro_tracking = :'trk';

\echo '=== P2. sp_registrar_escaneo + máquina de estados ==='
\echo '--- error esperado: ENTREGA de un envío que recién fue admitido'
CALL sp_registrar_escaneo(:'trk', 'ENTREGA', :ag_sur, :emp_courier);
\echo '--- salida de la agencia de origen'
CALL sp_registrar_escaneo(:'trk', 'SALIDA_HUB', :ag_mir, :emp_atencion, :desp1, 'Carga a furgoneta');

\echo '=== P4. sp_cerrar_despacho: arribo al Hub Central y llegada masiva de envíos ==='
CALL sp_cerrar_despacho(:desp1, clock_timestamp(), :emp_operario, NULL);
CALL sp_registrar_escaneo(:'trk', 'CLASIFICACION', :hc, :emp_operario, NULL, 'Clasificado a ruta Surco');

INSERT INTO despacho (codigo_manifiesto, id_ruta, id_vehiculo, fecha_salida_prog, fecha_salida_real, estado)
VALUES ('MF-PRUEBA-002', :ruta_hc_sur, :veh_hc, now(), clock_timestamp(), 'EN_RUTA')
RETURNING id_despacho AS desp2 \gset
INSERT INTO despacho_envio SELECT :desp2, id_envio, now() FROM envio WHERE nro_tracking = :'trk';
CALL sp_registrar_escaneo(:'trk', 'SALIDA_HUB', :hc, :emp_operario, :desp2);
CALL sp_cerrar_despacho(:desp2, clock_timestamp(), :emp_courier, NULL);
CALL sp_registrar_escaneo(:'trk', 'EN_REPARTO', :ag_sur, :emp_courier);

\echo '=== P3. sp_registrar_intento_entrega ==='
\echo '--- intento 1: destinatario ausente'
CALL sp_registrar_intento_entrega(:'trk', :emp_courier, 'AUSENTE');
CALL sp_registrar_escaneo(:'trk', 'EN_REPARTO', :ag_sur, :emp_courier, NULL, 'Segunda visita');
\echo '--- error esperado: entrega sin nombre del receptor'
CALL sp_registrar_intento_entrega(:'trk', :emp_courier, 'ENTREGADO');
\echo '--- intento 2: entregado'
CALL sp_registrar_intento_entrega(:'trk', :emp_courier, 'ENTREGADO', 'Ana Torres Ríos', '45871236');

\echo '=== Resultado: línea de tiempo del envío de prueba ==='
SELECT ev.fecha_hora::TIME(0) AS hora, ev.tipo_evento, h.codigo AS hub, ev.observacion
  FROM evento_tracking ev JOIN hub h USING (id_hub) JOIN envio e USING (id_envio)
 WHERE e.nro_tracking = :'trk' ORDER BY ev.fecha_hora, ev.id_evento;

SELECT nro_tracking, estado_actual, fecha_entrega IS NOT NULL AS tiene_fecha_entrega,
       fn_estado_sla(id_envio) AS estado_sla
  FROM envio WHERE nro_tracking = :'trk';

\echo '=== T1 + T2. Bitácora de auditoría generada automáticamente por triggers ==='
SELECT l.estado_anterior, l.estado_nuevo, l.usuario_bd
  FROM auditoria.log_estado_envio l JOIN envio e USING (id_envio)
 WHERE e.nro_tracking = :'trk' ORDER BY l.id_log;

\echo '=== F3. fn_permanencia_hub del envío en el Hub Central ==='
SELECT fn_permanencia_hub(e.id_envio, :hc) AS permanencia_en_hc FROM envio e WHERE nro_tracking = :'trk';

ROLLBACK;
\echo '>> Transacción revertida: los datos de prueba no se modificaron.'


-- #####################################################################
-- PRUEBAS 7.3 / 7.4 SEGURIDAD
-- #####################################################################
-- =====================================================================
-- 10 - Pruebas de seguridad: privilegios, columnas y Row Level Security
-- Se ejecuta como superusuario y cambia de identidad con SET SESSION AUTHORIZATION
-- (equivale a conectarse con cada usuario).
-- =====================================================================
\set ON_ERROR_STOP off
\pset footer off

\echo '=== Usuarios, roles heredados y atributos ==='
SELECT u.rolname AS usuario, STRING_AGG(g.rolname, ', ') AS roles, u.rolconnlimit AS limite_conexiones,
       u.rolvaliduntil::DATE AS vigencia, u.rolbypassrls AS bypass_rls
  FROM pg_roles u
  JOIN pg_auth_members m ON m.member = u.oid
  JOIN pg_roles g ON g.oid = m.roleid
 WHERE u.rolname LIKE 'u\_%'
 GROUP BY u.rolname, u.rolconnlimit, u.rolvaliduntil, u.rolbypassrls
 ORDER BY 1;

\echo '=== RLS: cada operador ve solo los envíos de su nodo ==='
SET SESSION AUTHORIZATION u_op_lima;
SELECT session_user AS usuario, seguridad.fn_mi_nodo() AS nodo, COUNT(*) AS envios_visibles FROM operacion.envio;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION u_op_norte;
SELECT session_user AS usuario, seguridad.fn_mi_nodo() AS nodo, COUNT(*) AS envios_visibles FROM operacion.envio;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION u_op_sur;
SELECT session_user AS usuario, seguridad.fn_mi_nodo() AS nodo, COUNT(*) AS envios_visibles FROM operacion.envio;
SELECT seguridad.fn_nodo_hub(id_hub) AS nodo_del_evento, COUNT(*) AS eventos_visibles
  FROM operacion.evento_tracking GROUP BY 1;
RESET SESSION AUTHORIZATION;
SELECT 'olva_admin (dueño)' AS usuario, COUNT(*) AS envios_visibles FROM operacion.envio;

\echo '=== Privilegios por columna: el operador no puede ver montos ==='
SET SESSION AUTHORIZATION u_op_sur;
SELECT nro_tracking, estado_actual, peso_total_kg FROM operacion.envio ORDER BY id_envio LIMIT 3;
\echo '--- error esperado: permission denied (columna monto_total)'
SELECT nro_tracking, monto_total FROM operacion.envio LIMIT 1;

\echo '=== Escritura solo vía procedimientos ==='
\echo '--- error esperado: INSERT directo en evento_tracking'
INSERT INTO operacion.evento_tracking (id_envio, tipo_evento, id_hub, fecha_hora) VALUES (1, 'CLASIFICACION', 1, now());
\echo '--- error esperado: UPDATE directo del estado de un envío'
UPDATE operacion.envio SET estado_actual = 'ENTREGADO' WHERE id_envio = 1;
RESET SESSION AUTHORIZATION;

\echo '=== Analista: lee vistas analíticas, no datos personales ==='
SET SESSION AUTHORIZATION u_analista;
SELECT modalidad, COUNT(*) AS envios, ROUND(AVG(monto_total), 2) AS ticket_prom
  FROM operacion.vw_envio_analitico GROUP BY 1;
\echo '--- error esperado: permission denied (tabla cliente)'
SELECT nro_documento FROM maestro.cliente LIMIT 1;
\echo '--- error esperado: permission denied (procedimiento de escritura)'
CALL operacion.sp_registrar_escaneo('OLV2600000001', 'CLASIFICACION', 1, 1);
RESET SESSION AUTHORIZATION;

\echo '=== Atención al cliente: tracking público y registro de envíos ==='
SET SESSION AUTHORIZATION u_atencion;
SELECT nro_tracking, servicio, ciudad_origen, ciudad_destino, estado_actual, ultimo_evento, ultimo_lugar
  FROM operacion.vw_tracking_publico WHERE nro_tracking = 'OLV2600001112';
\echo '--- error esperado: atención no puede ver comprobantes'
SELECT * FROM operacion.comprobante LIMIT 1;
RESET SESSION AUTHORIZATION;

\echo '=== REVOKE: se retira temporalmente el acceso del analista a la vista y se restituye ==='
REVOKE SELECT ON operacion.vw_envio_analitico FROM rol_analista;
SET SESSION AUTHORIZATION u_analista;
SELECT COUNT(*) FROM operacion.vw_envio_analitico;
RESET SESSION AUTHORIZATION;
GRANT SELECT ON operacion.vw_envio_analitico TO rol_analista;
SET SESSION AUTHORIZATION u_analista;
SELECT COUNT(*) AS filas_tras_regrant FROM operacion.vw_envio_analitico;
RESET SESSION AUTHORIZATION;

\echo '=== Políticas RLS definidas ==='
SELECT schemaname, tablename, policyname, roles, cmd FROM pg_policies ORDER BY 2, 3;
