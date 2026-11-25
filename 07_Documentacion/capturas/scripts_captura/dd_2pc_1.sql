\pset footer off
\set c_lima  'dbname=olva_lima'
\set c_norte 'host=pg_norte dbname=olva_norte'
\set c_sur   'host=pg_sur dbname=olva_sur'
SELECT id_hub AS hub_aqp FROM maestro.hub WHERE codigo = 'HR-AQP' \gset
\set ON_ERROR_STOP off
-- =================================================================== CASO 1
\echo ''
\echo '================ CASO 1: 2PC exitoso (todos votan SÍ) ================'
\set gid 'gtx_arribo_001'
INSERT INTO global.log_2pc (gid, fase, detalle) VALUES (:'gid', 'INICIO', 'Arribo MF-DEMO-2PC a HR-AQP; participantes: SUR, LIMA, NORTE');

\echo '--- FASE 1 en SUR: insertar eventos de llegada y PREPARE'
\connect :c_sur
BEGIN;
INSERT INTO operacion.evento_tracking VALUES
 (9900011, 990001, 'LLEGADA_HUB', :hub_aqp, NULL, 990001, now(), 'Arribo MF-DEMO-2PC', 'SUR'),
 (9900012, 990002, 'LLEGADA_HUB', :hub_aqp, NULL, 990001, now(), 'Arribo MF-DEMO-2PC', 'SUR');
PREPARE TRANSACTION 'gtx_arribo_001_sur';
SELECT COUNT(*) AS voto_sur FROM pg_prepared_xacts WHERE gid = 'gtx_arribo_001_sur' \gset

\echo '--- FASE 1 en LIMA: actualizar estado del envío 1 (solo si está EN_TRANSITO) y PREPARE'
\connect :c_lima
BEGIN;
DO $$ BEGIN
  UPDATE operacion.envio SET estado_actual = 'EN_HUB' WHERE id_envio = 990001 AND estado_actual = 'EN_TRANSITO';
  IF NOT FOUND THEN RAISE EXCEPTION 'LIMA vota NO: el envío 990001 no está EN_TRANSITO'; END IF;
END $$;
PREPARE TRANSACTION 'gtx_arribo_001_lima';
SELECT COUNT(*) AS voto_lima FROM pg_prepared_xacts WHERE gid = 'gtx_arribo_001_lima' \gset

\echo '--- FASE 1 en NORTE: actualizar estado del envío 2 y PREPARE'
\connect :c_norte
BEGIN;
DO $$ BEGIN
  UPDATE operacion.envio SET estado_actual = 'EN_HUB' WHERE id_envio = 990002 AND estado_actual = 'EN_TRANSITO';
  IF NOT FOUND THEN RAISE EXCEPTION 'NORTE vota NO: el envío 990002 no está EN_TRANSITO'; END IF;
END $$;
PREPARE TRANSACTION 'gtx_arribo_001_norte';
SELECT COUNT(*) AS voto_norte FROM pg_prepared_xacts WHERE gid = 'gtx_arribo_001_norte' \gset

\echo '--- Estado intermedio: transacciones preparadas (en duda) en cada nodo'
\connect :c_sur
SELECT 'SUR' AS nodo, gid, prepared::TIMESTAMP(0) AS preparada FROM pg_prepared_xacts;
\connect :c_norte
SELECT 'NORTE' AS nodo, gid, prepared::TIMESTAMP(0) AS preparada FROM pg_prepared_xacts;
\connect :c_lima
SELECT 'LIMA' AS nodo, gid, prepared::TIMESTAMP(0) AS preparada FROM pg_prepared_xacts;
\echo '--- Mientras están preparadas, los cambios NO son visibles para nadie:'
SELECT nro_tracking, nodo, estado_actual FROM global.envio WHERE id_envio >= 990000 ORDER BY 1;

SELECT (:voto_sur + :voto_lima + :voto_norte) = 3 AS todos_si \gset
\echo 'Votos -> SUR=' :voto_sur ' LIMA=' :voto_lima ' NORTE=' :voto_norte
\if :todos_si
  INSERT INTO global.log_2pc (gid, fase, detalle) VALUES (:'gid', 'DECISION', 'COMMIT (3/3 votos SÍ)');
  \echo '--- FASE 2: decisión COMMIT -> COMMIT PREPARED en cada nodo'
  \connect :c_sur
  COMMIT PREPARED 'gtx_arribo_001_sur';
  \connect :c_lima
  COMMIT PREPARED 'gtx_arribo_001_lima';
  \connect :c_norte
  COMMIT PREPARED 'gtx_arribo_001_norte';
\else
  \echo '--- FASE 2: decisión ROLLBACK'
\endif
\connect :c_lima
INSERT INTO global.log_2pc (gid, fase, detalle) VALUES (:'gid', 'FIN', 'Confirmado en SUR, LIMA, NORTE');
\echo '--- Resultado global tras el COMMIT:'
SELECT nro_tracking, nodo AS nodo_envio, estado_actual FROM global.envio WHERE id_envio >= 990000 ORDER BY 1;
SELECT id_envio, tipo_evento, nodo AS nodo_evento, observacion FROM global.evento_tracking WHERE id_evento >= 9900000 ORDER BY id_evento;
