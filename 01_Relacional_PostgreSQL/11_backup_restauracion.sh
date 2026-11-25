#!/bin/bash
# =====================================================================
# 11 - Backup y restauración de olva_courier
#   1) Respaldo lógico completo (pg_dump formato custom, comprimido)
#   2) Respaldo de objetos globales (roles/usuarios) con pg_dumpall
#   3) Respaldo físico en caliente (pg_basebackup)
#   4) Simulación de incidente: borrado accidental de incidencias
#   5) Restauración selectiva de la tabla afectada en producción
#   6) Restauración completa en una BD nueva y verificación de conteos
# Uso: docker exec olva_pg_lima bash /proyecto/01_Relacional_PostgreSQL/11_backup_restauracion.sh
# =====================================================================
set -e
export PGUSER="${POSTGRES_USER:-olva_admin}"
DIR=/proyecto/01_Relacional_PostgreSQL/backups
FECHA=$(date +%Y%m%d_%H%M)
DUMP="$DIR/olva_courier_$FECHA.dump"
PSQL="psql -X -q -t -A"
mkdir -p "$DIR"

conteos() {  # $1 = base de datos
    $PSQL -d "$1" -c "SELECT string_agg(relname || '=' || n, ' ' ORDER BY relname) FROM (
        SELECT c.relname, (xpath('/row/n/text()', query_to_xml('SELECT COUNT(*) AS n FROM ' || n.nspname || '.' || c.relname, false, true, '')))[1]::TEXT AS n
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname IN ('maestro','operacion') AND c.relkind = 'r') t;"
}

echo "== [1] Respaldo lógico: pg_dump -Fc =="
time pg_dump -d olva_courier -Fc -Z 6 -f "$DUMP"
ls -lh "$DUMP" | awk '{print "Archivo:", $9, "Tamaño:", $5}'
pg_restore -l "$DUMP" | grep -c "TABLE DATA" | xargs echo "Tablas con datos en el respaldo:"

echo
echo "== [2] Respaldo de roles y usuarios: pg_dumpall --globals-only =="
pg_dumpall --globals-only -f "$DIR/globales_$FECHA.sql"
grep -c "CREATE ROLE" "$DIR/globales_$FECHA.sql" | xargs echo "Roles respaldados:"

echo
echo "== [3] Respaldo físico en caliente: pg_basebackup =="
rm -rf "$DIR/base_$FECHA"
pg_basebackup -D "$DIR/base_$FECHA" -Ft -z -X fetch --checkpoint=fast -l "backup_olva_$FECHA"
ls -lh "$DIR/base_$FECHA" | tail -n +2 | awk '{print "  ", $9, $5}'

echo
echo "== Conteos ANTES del incidente =="
ANTES=$(conteos olva_courier); echo "$ANTES" | tr ' ' '\n' | grep -E "incidencia|envio=|evento"

echo
echo "== [4] INCIDENTE simulado: un operador borra por error todas las incidencias =="
$PSQL -d olva_courier -c "DELETE FROM operacion.incidencia;" ; echo "DELETE ejecutado"
$PSQL -d olva_courier -c "SELECT 'incidencia (después del DELETE) = ' || COUNT(*) FROM operacion.incidencia;"

echo
echo "== [5] Restauración selectiva de operacion.incidencia desde el respaldo =="
pg_restore -d olva_courier --data-only --schema=operacion --table=incidencia "$DUMP"
$PSQL -d olva_courier -c "SELECT 'incidencia (restaurada) = ' || COUNT(*) FROM operacion.incidencia;"

echo
echo "== [6] Restauración completa en una BD nueva: olva_courier_restore =="
$PSQL -d postgres -c "DROP DATABASE IF EXISTS olva_courier_restore;"
$PSQL -d postgres -c "CREATE DATABASE olva_courier_restore TEMPLATE template0;"
time pg_restore -d olva_courier_restore --jobs=4 --exit-on-error "$DUMP"
DESPUES=$(conteos olva_courier_restore)

echo
echo "== Verificación de integridad (conteo por tabla: original vs restaurada) =="
paste <(echo "$ANTES" | tr ' ' '\n') <(echo "$DESPUES" | tr ' ' '\n') | \
    awk -F'\t' '{split($1,a,"="); split($2,b,"="); printf "  %-18s %10s %10s  %s\n", a[1], a[2], b[2], (a[2]==b[2] ? "OK" : "DIFERENTE")}'
if [ "$ANTES" == "$DESPUES" ]; then echo "RESULTADO: restauración exitosa, todas las tablas coinciden"; else echo "RESULTADO: hay diferencias"; exit 1; fi

$PSQL -d olva_courier_restore -c "SELECT 'Objetos restaurados -> funciones/procedimientos: ' || COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('maestro','operacion','auditoria','seguridad');"
$PSQL -d olva_courier_restore -c "SELECT 'Objetos restaurados -> triggers: ' || COUNT(*) FROM pg_trigger WHERE NOT tgisinternal;"
$PSQL -d olva_courier_restore -c "SELECT 'Objetos restaurados -> políticas RLS: ' || COUNT(*) FROM pg_policies;"
