SELECT n.nspname AS schema, COUNT(c.oid) FILTER (WHERE c.relkind = 'r') AS tablas,
       COUNT(c.oid) FILTER (WHERE c.relkind IN ('v', 'm')) AS vistas, obj_description(n.oid) AS descripcion
  FROM pg_namespace n LEFT JOIN pg_class c ON c.relnamespace = n.oid
 WHERE n.nspname IN ('maestro', 'operacion', 'auditoria', 'seguridad')
 GROUP BY n.oid, n.nspname ORDER BY 1;
\dt maestro.*
\dt operacion.*
