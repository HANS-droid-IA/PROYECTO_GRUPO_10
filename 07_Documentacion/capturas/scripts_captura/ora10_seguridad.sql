SET LINESIZE 165
SET PAGESIZE 200
SET FEEDBACK OFF
SET TRIMOUT ON
ALTER SESSION SET TIME_ZONE = 'America/Lima';
ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD HH24:MI';
COLUMN username FORMAT A16
COLUMN account_status FORMAT A16
COLUMN profile FORMAT A18
COLUMN resource_name FORMAT A24
COLUMN limit FORMAT A8
COLUMN grantee FORMAT A18
COLUMN granted_role FORMAT A18
COLUMN table_name FORMAT A16
COLUMN privilege FORMAT A10
PROMPT === Usuarios y perfil ===
SELECT username, account_status, profile FROM dba_users WHERE username IN ('OLVA','U_ANALISTA_ORA','U_OPERADOR_ORA') ORDER BY 1;
PROMPT === Límites del PROFILE prf_olva_usuarios ===
SELECT resource_name, limit FROM dba_profiles WHERE profile = 'PRF_OLVA_USUARIOS' AND limit <> 'DEFAULT' ORDER BY 1;
PROMPT === Roles y privilegios de objeto ===
SELECT grantee, granted_role FROM dba_role_privs WHERE grantee IN ('U_ANALISTA_ORA','U_OPERADOR_ORA') ORDER BY 1;
SELECT grantee, table_name, privilege FROM dba_tab_privs WHERE grantee IN ('ROL_ANALISTA_ORA','ROL_OPERADOR_ORA') ORDER BY 1, 2;
EXIT
