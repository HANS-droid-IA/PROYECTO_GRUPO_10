#!/bin/bash
# =====================================================================
# Flujo de integración end-to-end de la solución (punto 14):
#
#   [PostgreSQL transaccional] --extracción CSV--> [HDFS /olva/operacional/<fecha>]
#                                                        |
#                                     [YARN: MapReduce (mismo jar del análisis masivo)]
#                                                        |
#   [HDFS /olva/resultados]  --carga KPI-->  PostgreSQL (esquema analitica)
#                                            MongoDB    (colección kpi_bigdata)
#                                            Cassandra  (tablas kpi_* replicadas en las 2 sedes)
#
# Paso 1-2: ingesta incremental desde la base operativa y reproceso con el mismo código MapReduce.
# Paso 3  : publicación de los indicadores del conjunto masivo en los tres motores de consumo.
# Requiere: Hadoop iniciado (hadoop_nativo/iniciar_hadoop.bat) + olva_pg_lima + olva_mongo + olva_cassandra encendidos y el jar compilado.
# Uso (Git Bash, en la raíz del proyecto): bash 06_BigData_Hadoop/03_integracion_end_to_end.sh
# =====================================================================
set -eo pipefail
cd "$(dirname "$0")"
. ./entorno_hadoop.sh
set -a; . ../.env; set +a
PG="docker exec -i olva_pg_lima psql -U $PG_USER -d olva_courier -v ON_ERROR_STOP=1"
FECHA=$(date +%Y%m%d)
DESTINO=/olva/operacional/$FECHA
mkdir -p outputs/integracion
titulo() { echo; echo "================ $* ================"; }

titulo "1) EXTRACCIÓN: PostgreSQL (olva_courier) -> HDFS $DESTINO"
$HX hdfs dfs -rm -r -f -skipTrash "$DESTINO" >/dev/null
$HX hdfs dfs -mkdir -p "$DESTINO/catalogos" "$DESTINO/envio" "$DESTINO/evento_tracking"
exportar() {   # $1 = tabla PostgreSQL, $2 = ruta HDFS destino
    $PG -c "COPY (SELECT * FROM $1) TO STDOUT WITH (FORMAT csv, HEADER)" \
        | $HX hdfs dfs -put -f - "$2"
    echo "  $1 -> $2 ($($HX hdfs dfs -cat "$2" | wc -l) líneas)"
}
for t in hub ciudad region tipo_servicio; do exportar "maestro.$t" "$DESTINO/catalogos/$t.csv"; done
exportar operacion.envio "$DESTINO/envio/envio.csv"
exportar operacion.evento_tracking "$DESTINO/evento_tracking/evento_tracking.csv"

titulo "2) PROCESAMIENTO: MapReduce sobre los datos operacionales extraídos"
$HX hadoop jar $HP/mapreduce/olva-bigdata.jar "$DESTINO" /olva/resultados_operacional 2>&1 \
    | grep -E 'Job job_.* completed|ENVIOS_LEIDOS|ESTANCIAS_EN_HUB|Falló' | tee outputs/integracion/log_operacional.txt
$HX hdfs dfs -cat '/olva/resultados_operacional/cumplimiento_sla/part-r-*' \
    | grep '^SERVICIO,' > outputs/integracion/sla_operacional_por_servicio.csv
echo "  SLA por servicio (base operativa, 30 mil envíos):"; sed 's/^/    /' outputs/integracion/sla_operacional_por_servicio.csv

titulo "3) CARGA DE INDICADORES (conjunto masivo, /olva/resultados) en los motores de consumo"
for f in permanencia_hub cumplimiento_sla; do
    [ -s "outputs/$f.csv" ] || { echo "Falta outputs/$f.csv: ejecute antes 02_ejecutar_mapreduce.sh"; exit 1; }
done

echo "-- 3a) PostgreSQL: esquema analitica"
$PG -q -f - < integracion/01_postgresql_analitica.sql
$PG -c "\copy analitica.kpi_permanencia_hub (dimension, codigo_hub, valor, estancias, permanencia_promedio_h, pct_mayor_12h) FROM STDIN WITH (FORMAT csv, HEADER)" < outputs/permanencia_hub.csv
$PG -c "\copy analitica.kpi_cumplimiento_sla (dimension, clave, detalle, envios, entregados, pct_cumplimiento_sla, retraso_promedio_h, ingresos_soles) FROM STDIN WITH (FORMAT csv, HEADER)" < outputs/cumplimiento_sla.csv
$PG -c "SELECT codigo, hora_llegada, estancias, permanencia_promedio_h, pct_mayor_12h, pct_llegadas_del_hub
        FROM analitica.vw_franjas_criticas WHERE codigo = 'HC-LIM' AND ranking_volumen <= 3 ORDER BY ranking_volumen;" \
    | tee outputs/integracion/postgresql_franjas_criticas.txt

echo "-- 3b) MongoDB: colección olva_tracking.kpi_bigdata"
docker exec olva_mongo mkdir -p /tmp/kpi
docker cp outputs/permanencia_hub.csv olva_mongo:/tmp/kpi/ >/dev/null
docker cp outputs/cumplimiento_sla.csv olva_mongo:/tmp/kpi/ >/dev/null
docker cp integracion/02_mongodb_kpi.js olva_mongo:/tmp/ >/dev/null
docker exec olva_mongo mongosh -u "$MONGO_USER" -p "$MONGO_PASSWORD" --authenticationDatabase admin --quiet \
    olva_tracking /tmp/02_mongodb_kpi.js | tee outputs/integracion/mongodb_kpi.txt

echo "-- 3c) Cassandra: tablas kpi_permanencia_hub y kpi_cumplimiento_sla"
docker exec olva_cassandra mkdir -p /tmp/kpi
docker cp outputs/permanencia_hub.csv olva_cassandra:/tmp/kpi/ >/dev/null
docker cp outputs/cumplimiento_sla.csv olva_cassandra:/tmp/kpi/ >/dev/null
docker cp integracion/03_cassandra_kpi.cql olva_cassandra:/tmp/ >/dev/null
docker exec olva_cassandra cqlsh -u olva_admin -p "$CASS_ADMIN_PASSWORD" -f /tmp/03_cassandra_kpi.cql 2>&1 \
    | grep -vE 'Warning: Using a password|Recommendation|^$' | tee outputs/integracion/cassandra_kpi.txt

titulo "4) VERIFICACIÓN: el mismo indicador en los tres motores"
echo -n "PostgreSQL : "; $PG -tAc "SELECT estancias||' estancias, '||permanencia_promedio_h||' h' FROM analitica.kpi_permanencia_hub WHERE dimension='HORA' AND codigo_hub='HC-LIM' AND valor='20'"
echo -n "MongoDB    : "; docker exec olva_mongo mongosh -u "$MONGO_USER" -p "$MONGO_PASSWORD" --authenticationDatabase admin --quiet olva_tracking \
    --eval "const d=db.kpi_bigdata.findOne({_id:'PERMANENCIA|HORA|HC-LIM|20'}); print(d.estancias+' estancias, '+d.permanencia_promedio_h+' h')"
echo -n "Cassandra  : "; docker exec olva_cassandra cqlsh -u olva_admin -p "$CASS_ADMIN_PASSWORD" -e \
    "SELECT estancias, permanencia_promedio_h FROM olva_tracking.kpi_permanencia_hub WHERE hub='HC-LIM' AND dimension='HORA' AND valor='20';" 2>/dev/null \
    | awk 'NR==4{gsub(/ /,""); split($0,a,"|"); print a[1]" estancias, "a[2]" h"}'
echo; echo "Flujo end-to-end completado."
