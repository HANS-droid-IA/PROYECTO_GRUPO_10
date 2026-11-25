\echo '=== Servidores remotos definidos con postgres_fdw (sin credenciales) ==='
SELECT s.srvname AS servidor, w.fdwname AS wrapper, array_to_string(s.srvoptions[1:3], ' ') AS opciones_conexion
  FROM pg_foreign_server s JOIN pg_foreign_data_wrapper w ON w.oid = s.srvfdw ORDER BY 1;
\echo '=== Esquema de asignación: fragmentos de cada relación global ==='
SELECT * FROM global.catalogo_fragmentos;
