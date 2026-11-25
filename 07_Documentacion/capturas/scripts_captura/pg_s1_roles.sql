\echo '=== Usuarios, rol heredado y atributos de cuenta ==='
SELECT u.rolname AS usuario, STRING_AGG(g.rolname, ', ') AS rol, u.rolconnlimit AS limite_conexiones,
       u.rolvaliduntil::DATE AS vigencia, u.rolbypassrls AS bypass_rls
  FROM pg_roles u JOIN pg_auth_members m ON m.member = u.oid JOIN pg_roles g ON g.oid = m.roleid
 WHERE u.rolname LIKE 'u\_%' GROUP BY u.rolname, u.rolconnlimit, u.rolvaliduntil, u.rolbypassrls ORDER BY 1;
\echo '=== Privilegios otorgados por rol y schema (GRANT) ==='
SELECT grantee AS rol, table_schema AS schema, STRING_AGG(DISTINCT privilege_type, ', ') AS privilegios, COUNT(DISTINCT table_name) AS objetos
  FROM information_schema.role_table_grants WHERE grantee LIKE 'rol_%' GROUP BY 1, 2 ORDER BY 1, 2;
\echo '=== Políticas de seguridad por fila (RLS) ==='
SELECT tablename AS tabla, policyname AS politica, roles, cmd FROM pg_policies ORDER BY 1, 2;
