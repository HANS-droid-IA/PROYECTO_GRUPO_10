\set ON_ERROR_ROLLBACK on
BEGIN;

SET search_path = operacion, maestro, public;
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

\o NUL
CALL sp_registrar_envio(:cliente, 'Ana Torres Ríos', '45871236', '987654321', 'Av. Primavera 1450, Surco',
     3::SMALLINT, :ag_mir, :ag_sur, '[{"peso": 2.3, "largo": 40, "ancho": 30, "alto": 20, "descripcion": "Repuestos"}]',
     'CREDITO', :emp_atencion, NULL);
\o
SELECT MAX(nro_tracking) AS trk FROM envio \gset
INSERT INTO despacho (codigo_manifiesto, id_ruta, id_vehiculo, fecha_salida_prog, fecha_salida_real, estado)
VALUES ('MF-PRUEBA-001', :ruta_mir_hc, :veh_mir, now(), clock_timestamp(), 'EN_RUTA') RETURNING id_despacho AS desp1 \gset
INSERT INTO despacho_envio SELECT :desp1, id_envio, now() FROM envio WHERE nro_tracking = :'trk';
\echo '=== P2 sp_registrar_escaneo / P4 sp_cerrar_despacho / P3 sp_registrar_intento_entrega ==='
\echo '--- Error controlado: transición inválida (ENTREGA de un envío recién admitido)'
CALL sp_registrar_escaneo(:'trk', 'ENTREGA', :ag_sur, :emp_courier);
\o NUL
CALL sp_registrar_escaneo(:'trk', 'SALIDA_HUB', :ag_mir, :emp_atencion, :desp1, 'Carga a furgoneta');
CALL sp_cerrar_despacho(:desp1, clock_timestamp(), :emp_operario, NULL);
CALL sp_registrar_escaneo(:'trk', 'CLASIFICACION', :hc, :emp_operario, NULL, 'Clasificado a ruta Surco');
INSERT INTO despacho (codigo_manifiesto, id_ruta, id_vehiculo, fecha_salida_prog, fecha_salida_real, estado)
VALUES ('MF-PRUEBA-002', :ruta_hc_sur, :veh_hc, now(), clock_timestamp(), 'EN_RUTA') RETURNING id_despacho AS desp2 \gset
INSERT INTO despacho_envio SELECT :desp2, id_envio, now() FROM envio WHERE nro_tracking = :'trk';
CALL sp_registrar_escaneo(:'trk', 'SALIDA_HUB', :hc, :emp_operario, :desp2);
CALL sp_cerrar_despacho(:desp2, clock_timestamp(), :emp_courier, NULL);
CALL sp_registrar_escaneo(:'trk', 'EN_REPARTO', :ag_sur, :emp_courier);
CALL sp_registrar_intento_entrega(:'trk', :emp_courier, 'AUSENTE');
CALL sp_registrar_escaneo(:'trk', 'EN_REPARTO', :ag_sur, :emp_courier, NULL, 'Segunda visita');
CALL sp_registrar_intento_entrega(:'trk', :emp_courier, 'ENTREGADO', 'Ana Torres Ríos', '45871236');
\o
\echo '=== Línea de tiempo generada por los procedimientos ==='
SELECT ev.tipo_evento, h.codigo AS hub, ev.observacion FROM evento_tracking ev JOIN hub h USING (id_hub) JOIN envio e USING (id_envio)
 WHERE e.nro_tracking = :'trk' ORDER BY ev.fecha_hora, ev.id_evento;
SELECT nro_tracking, estado_actual, fn_estado_sla(id_envio) AS estado_sla FROM envio WHERE nro_tracking = :'trk';
\echo '=== Triggers: bitácora de auditoría (auditoria.log_estado_envio) ==='
SELECT l.estado_anterior, l.estado_nuevo, l.usuario_bd FROM auditoria.log_estado_envio l JOIN envio e USING (id_envio)
 WHERE e.nro_tracking = :'trk' ORDER BY l.id_log;
ROLLBACK;
