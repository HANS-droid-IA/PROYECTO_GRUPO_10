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
