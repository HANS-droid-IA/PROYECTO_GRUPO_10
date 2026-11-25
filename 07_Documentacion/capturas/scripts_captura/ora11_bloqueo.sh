#!/bin/bash
# Pruebas de acceso con cada usuario y bloqueo de cuenta por PROFILE (sin mostrar contraseñas)
cd /proyecto/02_Oracle
sqlplus -s /nolog @06_pruebas_seguridad.sql < /dev/null 2>&1 | grep -v '^Help'
sqlplus -s "system/${ORACLE_PASSWORD}@//localhost:1521/FREEPDB1" <<'SQL'
SET LINESIZE 120
COLUMN username FORMAT A16
COLUMN account_status FORMAT A16
PROMPT === Estado de la cuenta tras 3 intentos fallidos (consultado como SYSTEM) ===
SELECT username, account_status FROM dba_users WHERE username = 'U_ANALISTA_ORA';
ALTER USER u_analista_ora ACCOUNT UNLOCK;
SELECT username, account_status FROM dba_users WHERE username = 'U_ANALISTA_ORA';
SQL
