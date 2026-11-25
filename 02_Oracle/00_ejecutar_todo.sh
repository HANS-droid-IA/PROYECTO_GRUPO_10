#!/bin/bash
# Ejecuta la implementación Oracle completa y guarda las evidencias.
# Uso (desde la raíz del proyecto):
#   docker exec olva_oracle bash /proyecto/02_Oracle/00_ejecutar_todo.sh
cd /proyecto/02_Oracle
APP="olva/${APP_USER_PASSWORD}@//localhost:1521/FREEPDB1"
SYS="system/${ORACLE_PASSWORD}@//localhost:1521/FREEPDB1"
EV=evidencias
mkdir -p $EV

echo ">> 01_ddl.sql";                 sqlplus -s "$APP" @01_ddl.sql                 < /dev/null > $EV/01_ddl_resultado.txt 2>&1
echo ">> 02_datos.sql";               sqlplus -s "$APP" @02_datos.sql               < /dev/null > $EV/02_datos_resultado.txt 2>&1
echo ">> 03_plsql.sql";               sqlplus -s "$APP" @03_plsql.sql               < /dev/null > $EV/03_plsql_resultado.txt 2>&1
echo ">> 04_consultas_y_pruebas.sql"; sqlplus -s "$APP" @04_consultas_y_pruebas.sql < /dev/null > $EV/04_consultas_y_pruebas_resultado.txt 2>&1
echo ">> 05_seguridad.sql";           sqlplus -s "$SYS" @05_seguridad.sql           < /dev/null > $EV/05_seguridad_resultado.txt 2>&1
echo ">> 06_pruebas_seguridad.sql"
{
    sqlplus -s /nolog @06_pruebas_seguridad.sql < /dev/null
    echo "=== Estado de la cuenta tras 3 intentos fallidos (consultado como SYSTEM) ==="
    echo "SELECT username, account_status FROM dba_users WHERE username = 'U_ANALISTA_ORA';
          ALTER USER u_analista_ora ACCOUNT UNLOCK;
          SELECT username, account_status AS estado_tras_unlock FROM dba_users WHERE username = 'U_ANALISTA_ORA';" | sqlplus -s "$SYS"
} > $EV/06_pruebas_seguridad_resultado.txt 2>&1
echo ">> 07_backup_datapump.sh";      bash 07_backup_datapump.sh > $EV/07_backup_datapump_log.txt 2>&1
echo ">> Listo. Evidencias en 02_Oracle/$EV"
