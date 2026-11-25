-- Genera el Diagrama Entidad-Relación (Mermaid erDiagram) leyendo el catálogo
-- real de PostgreSQL (olva_courier): tablas, columnas, tipos, PK, FK y UNIQUE.
-- Así el diagrama coincide exactamente con las tablas implementadas.
-- Uso: psql -d olva_courier -XtA -f generar_er_desde_catalogo.sql > 01_modelo_ER.mmd
WITH tablas AS (
    SELECT c.oid, n.nspname AS esquema, c.relname AS tabla
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind = 'r' AND n.nspname IN ('maestro', 'operacion')
),
cols AS (
    SELECT t.tabla, a.attnum, a.attname AS col,
           format_type(a.atttypid, a.atttypmod) AS tipo_full,
           EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = t.oid AND k.contype = 'p' AND a.attnum = ANY (k.conkey)) AS pk,
           EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = t.oid AND k.contype = 'f' AND a.attnum = ANY (k.conkey)) AS fk,
           EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = t.oid AND k.contype = 'u' AND a.attnum = ANY (k.conkey)
                                                   AND array_length(k.conkey, 1) = 1) AS uk
      FROM tablas t JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum > 0 AND NOT a.attisdropped
),
tipos AS (
    SELECT tabla, attnum, col, pk, fk, uk,
           CASE WHEN tipo_full LIKE 'character varying%' THEN 'varchar'
                WHEN tipo_full LIKE 'timestamp with time zone%' THEN 'timestamptz'
                WHEN tipo_full LIKE 'character(%' THEN 'char'
                ELSE split_part(tipo_full, '(', 1) END AS tipo
      FROM cols
),
entidades AS (
    SELECT tabla, '    ' || upper(tabla) || ' {' || E'\n' ||
           string_agg('        ' || replace(tipo, ' ', '_') || ' ' || col ||
                      CASE WHEN pk AND fk THEN ' PK,FK' WHEN pk THEN ' PK' WHEN fk AND uk THEN ' FK,UK'
                           WHEN fk THEN ' FK' WHEN uk THEN ' UK' ELSE '' END, E'\n' ORDER BY attnum) ||
           E'\n    }' AS txt
      FROM tipos GROUP BY tabla
),
relaciones AS (
    SELECT '    ' || upper(p.relname) || ' ' ||
           CASE WHEN bool_and(a.attnotnull) THEN '||' ELSE '|o' END ||
           '--' ||
           CASE WHEN EXISTS (SELECT 1 FROM pg_constraint u WHERE u.conrelid = k.conrelid AND u.contype IN ('u', 'p')
                                AND u.conkey = k.conkey) THEN 'o|' ELSE 'o{' END ||
           ' ' || upper(c.relname) || ' : "' || string_agg(a.attname, ',') || '"' AS txt
      FROM pg_constraint k
      JOIN pg_class c ON c.oid = k.conrelid
      JOIN pg_class p ON p.oid = k.confrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = ANY (k.conkey)
     WHERE k.contype = 'f' AND n.nspname IN ('maestro', 'operacion')
     GROUP BY k.oid, k.conrelid, k.conkey, p.relname, c.relname
)
SELECT '%% Diagrama 1. Modelo Entidad-Relación de olva_courier (schemas maestro y operacion)' || E'\n' ||
       '%% Generado automáticamente desde el catálogo de PostgreSQL con generar_er_desde_catalogo.sql' || E'\n' ||
       'erDiagram' || E'\n' ||
       (SELECT string_agg(txt, E'\n' ORDER BY txt) FROM relaciones) || E'\n' ||
       (SELECT string_agg(txt, E'\n' ORDER BY tabla) FROM entidades);
