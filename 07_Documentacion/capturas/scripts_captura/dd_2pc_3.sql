\pset footer off
\set c_lima  'dbname=olva_lima'
\set c_norte 'host=pg_norte dbname=olva_norte'
\set c_sur   'host=pg_sur dbname=olva_sur'
SELECT id_hub AS hub_aqp FROM maestro.hub WHERE codigo = 'HR-AQP' \gset
\set ON_ERROR_STOP off
-- =================================================================== CASO 3
\echo ''
\echo '================ CASO 3: falla del coordinador -> transacción EN DUDA ================'
\echo 'NORTE prepara la salida del envío 2 hacia la agencia, pero el coordinador cae antes de la fase 2.'
\set gid 'gtx_salida_003'
INSERT INTO global.log_2pc (gid, fase, detalle) VALUES (:'gid', 'INICIO', 'Salida a reparto; participante NORTE');
\connect :c_norte
BEGIN;
UPDATE operacion.envio SET estado_actual = 'EN_TRANSITO' WHERE id_envio = 990002;
PREPARE TRANSACTION 'gtx_salida_003_norte';
\echo '>>> (el coordinador se desconecta aquí: no envía COMMIT ni ROLLBACK)'

\connect :c_norte
\echo '--- La transacción sigue preparada aunque la sesión que la creó ya no existe:'
SELECT gid, prepared::TIMESTAMP(0) AS preparada, owner, database FROM pg_prepared_xacts;
\echo '--- Y retiene sus bloqueos: otra transacción que toca el envío queda bloqueada (lock_timeout 3 s)'
SET lock_timeout = '3s';
UPDATE operacion.envio SET direccion_entrega = direccion_entrega || ' (ref. puerta verde)' WHERE id_envio = 990002;
RESET lock_timeout;

\echo '--- RECUPERACIÓN: el coordinador reinicia, lee su bitácora y resuelve las transacciones en duda'
\connect :c_lima
SELECT gid, fase, detalle FROM global.log_2pc WHERE gid = 'gtx_salida_003' ORDER BY id;
\echo 'No hay registro DECISION -> regla de recuperación: abortar (presumed abort)'
INSERT INTO global.log_2pc (gid, fase, detalle) VALUES (:'gid', 'DECISION', 'ROLLBACK por recuperación (sin decisión registrada)');
\connect :c_norte
ROLLBACK PREPARED 'gtx_salida_003_norte';
SELECT COUNT(*) AS transacciones_en_duda FROM pg_prepared_xacts;
UPDATE operacion.envio SET direccion_entrega = direccion_entrega || ' (ref. puerta verde)' WHERE id_envio = 990002;
SELECT nro_tracking, estado_actual, direccion_entrega FROM operacion.envio WHERE id_envio = 990002;

\connect :c_lima
\echo ''
\echo '=== Bitácora del coordinador (global.log_2pc) ==='
SELECT id, gid, fase, detalle FROM global.log_2pc ORDER BY id;
