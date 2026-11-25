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
