\pset footer off
\set c_lima  'dbname=olva_lima'
\set c_norte 'host=pg_norte dbname=olva_norte'
\set c_sur   'host=pg_sur dbname=olva_sur'
SELECT id_hub AS hub_aqp FROM maestro.hub WHERE codigo = 'HR-AQP' \gset
\set ON_ERROR_STOP off
-- =================================================================== CASO 2
\echo ''
\echo '================ CASO 2: un participante vota NO -> ROLLBACK global ================'
\echo 'Se reintenta por error el mismo arribo (manifiesto duplicado).'
\set gid 'gtx_arribo_002'
INSERT INTO global.log_2pc (gid, fase, detalle) VALUES (:'gid', 'INICIO', 'Reintento duplicado del arribo MF-DEMO-2PC');

\echo '--- FASE 1 en SUR: inserta eventos y PREPARE (vota SÍ)'
\connect :c_sur
BEGIN;
INSERT INTO operacion.evento_tracking VALUES
 (9900021, 990001, 'LLEGADA_HUB', :hub_aqp, NULL, 990001, now(), 'Arribo duplicado', 'SUR'),
 (9900022, 990002, 'LLEGADA_HUB', :hub_aqp, NULL, 990001, now(), 'Arribo duplicado', 'SUR');
PREPARE TRANSACTION 'gtx_arribo_002_sur';
SELECT COUNT(*) AS voto_sur FROM pg_prepared_xacts WHERE gid = 'gtx_arribo_002_sur' \gset

\echo '--- FASE 1 en LIMA: el envío ya está EN_HUB -> error -> vota NO'
\connect :c_lima
BEGIN;
DO $$ BEGIN
  UPDATE operacion.envio SET estado_actual = 'EN_HUB' WHERE id_envio = 990001 AND estado_actual = 'EN_TRANSITO';
  IF NOT FOUND THEN RAISE EXCEPTION 'LIMA vota NO: el envío 990001 no está EN_TRANSITO'; END IF;
END $$;
PREPARE TRANSACTION 'gtx_arribo_002_lima';
SELECT COUNT(*) AS voto_lima FROM pg_prepared_xacts WHERE gid = 'gtx_arribo_002_lima' \gset
\echo 'Votos -> SUR=' :voto_sur ' LIMA=' :voto_lima ' (NORTE ya no se consulta)'

SELECT (:voto_sur + :voto_lima) = 2 AS todos_si \gset
\if :todos_si
  \echo 'COMMIT'
\else
  INSERT INTO global.log_2pc (gid, fase, detalle) VALUES (:'gid', 'DECISION', 'ROLLBACK (LIMA votó NO)');
  \echo '--- FASE 2: decisión ROLLBACK -> ROLLBACK PREPARED en los nodos que votaron SÍ'
  \connect :c_sur
  ROLLBACK PREPARED 'gtx_arribo_002_sur';
  \connect :c_lima
\endif
\echo '--- Verificación: no quedaron eventos duplicados en SUR'
SELECT id_envio, tipo_evento, observacion, nodo FROM global.evento_tracking WHERE id_evento >= 9900000 ORDER BY id_evento;
