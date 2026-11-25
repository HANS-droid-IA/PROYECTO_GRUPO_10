#!/bin/bash
# =====================================================================
# 07 - Backup y restauración lógica en Oracle con Data Pump (expdp/impdp)
# Equivalente a pg_dump / pg_restore. Se ejecuta dentro del contenedor.
# =====================================================================
set -e
CONN_SYS="system/${ORACLE_PASSWORD}@//localhost:1521/FREEPDB1"
CONN_APP="olva/${APP_USER_PASSWORD}@//localhost:1521/FREEPDB1"
FECHA=$(date +%Y%m%d_%H%M)
DESTINO=/proyecto/02_Oracle/backups
mkdir -p "$DESTINO"

sql() { sqlplus -s "$1" <<EOF
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200
$2
EOF
}

echo "== Directorio de Data Pump y permisos =="
DIR=$(sql "$CONN_SYS" "SELECT directory_path FROM dba_directories WHERE directory_name = 'DATA_PUMP_DIR';" | xargs)
echo "DATA_PUMP_DIR = $DIR"
sql "$CONN_SYS" "GRANT READ, WRITE ON DIRECTORY data_pump_dir TO olva;"

echo
echo "== [1] Exportación del esquema OLVA (expdp) =="
expdp "$CONN_APP" schemas=olva directory=data_pump_dir dumpfile=olva_$FECHA.dmp logfile=exp_olva_$FECHA.log reuse_dumpfiles=y 2>&1 \
    | grep -E "exported|Job .* completed|ORA-" || true
cp "$DIR/olva_$FECHA.dmp" "$DIR/exp_olva_$FECHA.log" "$DESTINO/"
ls -lh "$DESTINO/olva_$FECHA.dmp" | awk '{print "Copia en el proyecto:", $9, $5}'

echo
echo "== Conteo ANTES del incidente =="
sql "$CONN_APP" "SELECT 'evento_tracking = ' || COUNT(*) FROM evento_tracking;"

echo
echo "== [2] INCIDENTE simulado: DROP TABLE evento_tracking =="
sql "$CONN_APP" "DROP TABLE evento_tracking CASCADE CONSTRAINTS PURGE;"
sql "$CONN_APP" "SELECT 'tablas restantes: ' || COUNT(*) FROM user_tables;"

echo
echo "== [3] Restauración de la tabla (impdp TABLES=) =="
impdp "$CONN_APP" tables=evento_tracking directory=data_pump_dir dumpfile=olva_$FECHA.dmp logfile=imp_olva_$FECHA.log 2>&1 \
    | grep -E "imported|Job .* completed|ORA-" || true

echo
echo "== Verificación después de la restauración =="
sql "$CONN_APP" "SELECT 'evento_tracking = ' || COUNT(*) FROM evento_tracking;"
sql "$CONN_APP" "SELECT 'constraints = ' || COUNT(*) FROM user_constraints WHERE table_name = 'EVENTO_TRACKING';"
sql "$CONN_APP" "SELECT 'trigger ' || trigger_name || ' = ' || status FROM user_triggers WHERE table_name = 'EVENTO_TRACKING';"
sql "$CONN_APP" "SELECT 'índices = ' || COUNT(*) FROM user_indexes WHERE table_name = 'EVENTO_TRACKING';"

echo
echo "== Recompilación de dependientes (el DROP invalidó el paquete que usa la tabla) =="
sql "$CONN_APP" "ALTER PACKAGE pkg_tracking COMPILE;"
sql "$CONN_APP" "SELECT object_name || ' ' || object_type || ' = ' || status FROM user_objects WHERE object_name = 'PKG_TRACKING';"
