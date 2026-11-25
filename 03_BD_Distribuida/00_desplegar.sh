#!/bin/bash
# =====================================================================
# Despliega la BD distribuida de 3 nodos y genera las evidencias.
# Requisitos: perfil "distribuida" levantado y olva_courier creada (Avance 1).
#   docker compose --profile distribuida up -d
#   docker exec olva_pg_lima bash /proyecto/03_BD_Distribuida/00_desplegar.sh
# =====================================================================
set -e
cd /proyecto/03_BD_Distribuida
export PGUSER="${POSTGRES_USER:-olva_admin}" PGPASSWORD="$POSTGRES_PASSWORD"
PSQL="psql -X -q -v ON_ERROR_STOP=1"
EV=evidencias; mkdir -p $EV

echo ">> Nodo LIMA: recreando olva_lima"
$PSQL -d postgres -c "DROP DATABASE IF EXISTS olva_lima WITH (FORCE);"
$PSQL -d postgres -c "CREATE DATABASE olva_lima TEMPLATE template0;"
for db in olva_lima; do $PSQL -d postgres -c "ALTER DATABASE $db SET timezone TO 'America/Lima';"; done
$PSQL -h pg_norte -d olva_norte -c "ALTER DATABASE olva_norte SET timezone TO 'America/Lima';"
$PSQL -h pg_sur   -d olva_sur   -c "ALTER DATABASE olva_sur SET timezone TO 'America/Lima';"

echo ">> 01 Esquema de nodo en NORTE, SUR y LIMA"
{
  $PSQL -h pg_norte -d olva_norte -v nodo=NORTE -f 01_ddl_nodo_regional.sql
  $PSQL -h pg_sur   -d olva_sur   -v nodo=SUR   -f 01_ddl_nodo_regional.sql
  $PSQL             -d olva_lima  -v nodo=LIMA  -f 01_ddl_nodo_regional.sql
} > $EV/01_ddl_nodos_log.txt 2>&1

echo ">> 02 Coordinador Lima (postgres_fdw + esquema global)"
$PSQL -d olva_lima -v usuario="$PGUSER" -v clave="$PGPASSWORD" -f 02_coordinador_lima.sql > $EV/02_coordinador_log.txt 2>&1

echo ">> 03 Migración de la BD centralizada a los fragmentos"
$PSQL -d olva_lima -f 03_migracion_fragmentos.sql > $EV/03_migracion_log.txt 2>&1

echo ">> 04 Verificación de la fragmentación"
psql -X -d olva_lima -f 04_verificacion_fragmentacion.sql > $EV/04_verificacion_resultado.txt 2>&1

echo ">> 05 Consultas distribuidas (descomposición, localización, optimización)"
psql -X -d olva_lima -f 05_consultas_distribuidas.sql > $EV/05_consultas_distribuidas_resultado.txt 2>&1

echo ">> 06 Transacción distribuida con 2PC"
psql -X -d olva_lima -f 06_transaccion_2pc.sql > $EV/06_transaccion_2pc_resultado.txt 2>&1

echo ">> 07 Control de concurrencia"
bash 07_concurrencia.sh > $EV/07_concurrencia_resultado.txt 2>&1

echo ">> Listo. Evidencias en 03_BD_Distribuida/$EV"
