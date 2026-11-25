SET SESSION AUTHORIZATION u_op_sur;
\echo '--- u_op_sur: lectura de columnas permitidas'
SELECT nro_tracking, estado_actual, peso_total_kg FROM operacion.envio ORDER BY id_envio LIMIT 3;
\echo '--- u_op_sur: columna monto_total (sin privilegio de columna)'
SELECT nro_tracking, monto_total FROM operacion.envio LIMIT 1;
\echo '--- u_op_sur: INSERT directo en evento_tracking (solo se permite vía procedimiento)'
INSERT INTO operacion.evento_tracking (id_envio, tipo_evento, id_hub, fecha_hora) VALUES (1, 'CLASIFICACION', 1, now());
\echo '--- u_op_sur: UPDATE directo del estado de un envío'
UPDATE operacion.envio SET estado_actual = 'ENTREGADO' WHERE id_envio = 1;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION u_analista;
\echo '--- u_analista: vista analítica permitida'
SELECT modalidad, COUNT(*) AS envios, ROUND(AVG(monto_total), 2) AS ticket_prom FROM operacion.vw_envio_analitico GROUP BY 1;
\echo '--- u_analista: datos personales de clientes (denegado)'
SELECT nro_documento FROM maestro.cliente LIMIT 1;
\echo '--- u_analista: procedimiento de escritura (denegado)'
CALL operacion.sp_registrar_escaneo('OLV2600000001', 'CLASIFICACION', 1, 1);
RESET SESSION AUTHORIZATION;
