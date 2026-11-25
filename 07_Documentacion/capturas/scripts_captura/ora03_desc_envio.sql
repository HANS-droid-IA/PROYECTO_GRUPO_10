SET LINESIZE 165
SET PAGESIZE 200
SET FEEDBACK OFF
SET TRIMOUT ON
ALTER SESSION SET TIME_ZONE = 'America/Lima';
ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD HH24:MI';
COLUMN constraint_name FORMAT A22
COLUMN t FORMAT A2
COLUMN condicion FORMAT A110
PROMPT === DESCRIBE envio ===
DESC envio
PROMPT === Restricciones de ENVIO ===
SELECT constraint_name, constraint_type AS t, SUBSTR(search_condition_vc, 1, 110) AS condicion
  FROM user_constraints WHERE table_name = 'ENVIO' ORDER BY constraint_type DESC, constraint_name;
EXIT
