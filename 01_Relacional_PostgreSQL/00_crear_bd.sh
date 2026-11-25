#!/bin/bash
# Crea y puebla la BD olva_courier ejecutando los scripts en orden.
# Uso (desde la raíz del proyecto):
#   docker exec olva_pg_lima bash /proyecto/01_Relacional_PostgreSQL/00_crear_bd.sh
set -e
cd /proyecto/01_Relacional_PostgreSQL
export PGUSER="${POSTGRES_USER:-olva_admin}"
PSQL="psql -v ON_ERROR_STOP=1 -X -q"

echo ">> Recreando base de datos olva_courier"
$PSQL -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'olva_courier' AND pid <> pg_backend_pid();" >/dev/null
$PSQL -d postgres -c "DROP DATABASE IF EXISTS olva_courier;"
$PSQL -d postgres -c "CREATE DATABASE olva_courier ENCODING 'UTF8' TEMPLATE template0;"
$PSQL -d postgres -c "ALTER DATABASE olva_courier SET timezone TO 'America/Lima';"

for f in 01_ddl_esquemas_tablas.sql 02_funciones.sql 03_procedimientos.sql 04_carga_datos.sql \
         05_triggers.sql 06_vistas.sql 07_seguridad_roles.sql; do
    echo ">> Ejecutando $f"
    $PSQL -d olva_courier -f "$f"
done
echo ">> BD olva_courier lista"
