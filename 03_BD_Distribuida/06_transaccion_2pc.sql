-- =====================================================================
-- BD Distribuida - 06: Transacción distribuida con Two-Phase Commit (2PC)
-- ---------------------------------------------------------------------
-- ESCENARIO DE NEGOCIO: arriba al Hub Regional Arequipa (nodo SUR) el
-- manifiesto MF-DEMO-2PC que viene del Hub Central. Transporta:
--   * OLV2699990001 originado en Lima     -> su registro vive en el nodo LIMA
--   * OLV2699990002 originado en Trujillo -> su registro vive en el nodo NORTE
-- El arribo es UNA operación de negocio que escribe en TRES nodos:
--   SUR   : INSERT de los eventos LLEGADA_HUB (el escaneo ocurre en Arequipa)
--   LIMA  : UPDATE estado del envío 1 -> EN_HUB
--   NORTE : UPDATE estado del envío 2 -> EN_HUB
-- Debe ser atómica: o se registra en los 3 nodos o en ninguno.
--
-- postgres_fdw NO implementa 2PC (confirma los nodos remotos uno a uno), por
-- eso el coordinador (Lima) orquesta el protocolo manualmente con
-- PREPARE TRANSACTION / COMMIT PREPARED / ROLLBACK PREPARED.
--   Fase 1 (votación): cada participante ejecuta su parte y hace PREPARE.
--                      PREPARE exitoso = voto SÍ (cambios persistidos en disco,
--                      bloqueos retenidos). Error = voto NO.
--   Fase 2 (decisión): si todos votan SÍ -> COMMIT PREPARED en todos;
--                      si alguno vota NO -> ROLLBACK PREPARED en los preparados.
-- El coordinador registra su decisión en global.log_2pc ANTES de la fase 2.
-- =====================================================================
\pset footer off
\set c_lima  'dbname=olva_lima'
\set c_norte 'host=pg_norte dbname=olva_norte'
\set c_sur   'host=pg_sur dbname=olva_sur'

-- ------------------------------------------------------------------ preparación
\echo '=== Preparación del escenario (limpieza idempotente + datos de demostración) ==='
\set ON_ERROR_STOP on
\connect :c_norte
SELECT COUNT(*) AS _n FROM (SELECT gid FROM pg_prepared_xacts WHERE gid LIKE 'gtx_%') x \gset
\if :_n
  SELECT 'ROLLBACK PREPARED ' || quote_literal(gid) FROM pg_prepared_xacts WHERE gid LIKE 'gtx_%' \gexec
\endif
DELETE FROM operacion.envio WHERE id_envio >= 990000;
\connect :c_sur
SELECT COUNT(*) AS _n FROM (SELECT gid FROM pg_prepared_xacts WHERE gid LIKE 'gtx_%') x \gset
\if :_n
  SELECT 'ROLLBACK PREPARED ' || quote_literal(gid) FROM pg_prepared_xacts WHERE gid LIKE 'gtx_%' \gexec
\endif
DELETE FROM operacion.evento_tracking WHERE id_evento >= 9900000;
\connect :c_lima
SELECT COUNT(*) AS _n FROM (SELECT gid FROM pg_prepared_xacts WHERE gid LIKE 'gtx_%') x \gset
\if :_n
  SELECT 'ROLLBACK PREPARED ' || quote_literal(gid) FROM pg_prepared_xacts WHERE gid LIKE 'gtx_%' \gexec
\endif
DELETE FROM operacion.evento_tracking WHERE id_evento >= 9900000;
DELETE FROM operacion.envio WHERE id_envio >= 990000;
DROP TABLE IF EXISTS global.log_2pc;
CREATE TABLE global.log_2pc (
    id         SERIAL PRIMARY KEY,
    gid        TEXT NOT NULL,
    fase       TEXT NOT NULL,
    detalle    TEXT,
    registrado TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

SELECT id_hub AS hub_mir FROM maestro.hub WHERE codigo = 'AG-LIM-MIR' \gset
SELECT id_hub AS hub_tru FROM maestro.hub WHERE codigo = 'AG-TRU-01' \gset
SELECT id_hub AS hub_aqp FROM maestro.hub WHERE codigo = 'HR-AQP' \gset
SELECT id_hub AS hub_hc  FROM maestro.hub WHERE codigo = 'HC-LIM' \gset
SELECT id_hub AS ag_aqp  FROM maestro.hub WHERE codigo = 'AG-AQP-01' \gset
SELECT MIN(id_cliente) AS cli_lima  FROM global.cliente_contacto WHERE nodo = 'LIMA' \gset
SELECT MIN(id_cliente) AS cli_norte FROM global.cliente_contacto WHERE nodo = 'NORTE' \gset

-- envíos en tránsito (se insertan vía tabla global: el particionamiento los enruta)
INSERT INTO global.envio VALUES
 (990001, 'OLV2699990001', :cli_lima,  1, 1, :hub_mir, :ag_aqp, 'Av. Ejército 101, Arequipa',
  now() - INTERVAL '20 hours', now() + INTERVAL '1 day', 'EN_TRANSITO', 2.0, 0, 39.00, NULL, 'LIMA'),
 (990002, 'OLV2699990002', :cli_norte, 1, 1, :hub_tru, :ag_aqp, 'Calle Mercaderes 220, Arequipa',
  now() - INTERVAL '30 hours', now() + INTERVAL '1 day', 'EN_TRANSITO', 3.5, 0, 45.50, NULL, 'NORTE');
INSERT INTO global.evento_tracking VALUES
 (9900001, 990001, 'SALIDA_HUB', :hub_hc, NULL, 990001, now() - INTERVAL '4 hours', 'Manifiesto MF-DEMO-2PC', 'LIMA'),
 (9900002, 990002, 'SALIDA_HUB', :hub_hc, NULL, 990001, now() - INTERVAL '4 hours', 'Manifiesto MF-DEMO-2PC', 'LIMA');

SELECT e.nro_tracking, e.nodo AS nodo_del_envio, e.estado_actual FROM global.envio e WHERE id_envio >= 990000 ORDER BY 1;

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
