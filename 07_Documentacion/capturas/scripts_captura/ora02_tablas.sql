SET LINESIZE 165
SET PAGESIZE 200
SET FEEDBACK OFF
SET TRIMOUT ON
ALTER SESSION SET TIME_ZONE = 'America/Lima';
ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD HH24:MI';
COLUMN tabla FORMAT A18
COLUMN tipo FORMAT A12
COLUMN restricciones FORMAT A60
PROMPT === Tablas del esquema OLVA, registros y restricciones por tipo ===
SELECT t.table_name AS tabla,
       TO_NUMBER(EXTRACTVALUE(XMLTYPE(DBMS_XMLGEN.GETXML('SELECT COUNT(*) c FROM ' || t.table_name)), '/ROWSET/ROW/C')) AS filas,
       r.restricciones
  FROM user_tables t
  LEFT JOIN (SELECT table_name, LISTAGG(tipo || ':' || n, ' ') WITHIN GROUP (ORDER BY tipo) AS restricciones
               FROM (SELECT table_name, DECODE(constraint_type, 'P', 'PK', 'R', 'FK', 'U', 'UK', 'C', 'CHECK') AS tipo, COUNT(*) AS n
                       FROM user_constraints WHERE constraint_name NOT LIKE 'SYS%' GROUP BY table_name, constraint_type)
              GROUP BY table_name) r ON r.table_name = t.table_name
 ORDER BY t.table_name;
PROMPT
PROMPT === Objetos PL/SQL ===
COLUMN object_name FORMAT A30
SELECT object_name, object_type, status FROM user_objects WHERE object_type IN ('PACKAGE','PACKAGE BODY','PROCEDURE','TRIGGER') ORDER BY 2, 1;
EXIT
