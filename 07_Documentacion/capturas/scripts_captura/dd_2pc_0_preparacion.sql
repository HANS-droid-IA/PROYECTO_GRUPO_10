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
