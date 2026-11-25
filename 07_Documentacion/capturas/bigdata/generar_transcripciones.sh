#!/bin/bash
# Ejecuta comandos REALES sobre Hadoop (Ubuntu/WSL), PostgreSQL, MongoDB y Cassandra y guarda cada
# transcripción (indicador + comando + salida) en salidas/<id>.txt para fotografiarla con fotografiar_consola.ps1.
# Las salidas de procesos largos (generación masiva y ejecución MapReduce) se toman de sus registros reales
# en 06_BigData_Hadoop/outputs. Ninguna contraseña aparece en las transcripciones.
# Uso (Git Bash): bash 07_Documentacion/capturas/bigdata/generar_transcripciones.sh
set -eo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")"
RAIZ=/g/PROYECTO_GRUPO_10
BD=$RAIZ/06_BigData_Hadoop
set -a; . $RAIZ/.env; set +a
mkdir -p salidas
H="wsl.exe -d Ubuntu-22.04 -u hadoop -e bash -lc"
P='hadoop@Hans:~$ '

# -- hd: comandos en Ubuntu (usuario hadoop); cada línea "cmd" se muestra con su salida real
hd() {  # $1 = id, resto = comandos
    local id=$1; shift
    : > salidas/$id.txt
    for c in "$@"; do
        echo "$P$c" >> salidas/$id.txt
        $H "cd ~; $c" 2>&1 | sed 's/\r$//' >> salidas/$id.txt
        echo >> salidas/$id.txt
    done
    echo "$id: $(wc -l < salidas/$id.txt) líneas"
}

hd hd_instalacion \
  'java -version 2>&1 | head -1' \
  'hadoop version | head -4' \
  'ls -l /opt | grep hadoop' \
  'hdfs getconf -confKey fs.defaultFS; hdfs getconf -confKey dfs.replication; hdfs getconf -confKey dfs.blocksize' \
  'hdfs getconf -namenodes; hdfs getconf -confKey yarn.resourcemanager.webapp.address'

hd hd_estado 'hadoop_cluster status'

hd hd_carga \
  'hdfs dfs -ls /olva' \
  'hdfs dfs -du -h /olva/raw' \
  'hdfs dfs -count -h /olva/raw'

hd hd_bloques \
  "hdfs fsck /olva/raw/evento_tracking -files -blocks -locations 2>/dev/null | grep -E 'evento_tracking.csv|blk_|Status|Total blocks|Average block replication|Number of data-nodes' | sed -E 's/DatanodeInfoWithStorage\[([0-9.:]+),DS-[0-9a-f-]+,DISK\]/\1/g; s/BP-[0-9.-]+://'"

hd hd_resultados_hora \
  'hdfs dfs -ls /olva/resultados/permanencia_hub' \
  "hdfs dfs -cat /olva/resultados/permanencia_hub/part-r-00000 | grep '^HORA,HC-LIM' | sort -t, -k4 -nr | head -8" \
  "hdfs dfs -cat /olva/resultados/permanencia_hub/part-r-00000 | grep '^DIA,HC-LIM'"

hd hd_resultados_mes \
  "hdfs dfs -cat /olva/resultados/permanencia_hub/part-r-00000 | grep '^MES,HR-AQP'" \
  "hdfs dfs -cat /olva/resultados/permanencia_hub/part-r-00000 | grep '^HORA,' | sort -t, -k4 -nr | head -6"

hd hd_resultados_sla \
  "hdfs dfs -cat /olva/resultados/cumplimiento_sla/part-r-00000 | grep '^SERVICIO,'" \
  "hdfs dfs -cat /olva/resultados/cumplimiento_sla/part-r-00000 | grep '^SERVICIO_RUTA' | awk -F, '\$5>=500' | sort -t, -k6 -n | head -5" \
  "hdfs dfs -cat /olva/resultados/cumplimiento_sla/part-r-00000 | grep '^MES,'"

# -- ejecución MapReduce: extracto fiel del registro real (outputs/log_mapreduce.txt)
{
  echo "${P}hadoop jar /mnt/g/PROYECTO_GRUPO_10/06_BigData_Hadoop/mapreduce/olva-bigdata.jar /olva/raw /olva/resultados"
  grep -E 'Connecting to ResourceManager|Total input files|number of splits|Submitting tokens|Submitted application|Running job|map [0-9]+% reduce [0-9]+%|completed successfully|Launched map tasks|Launched reduce tasks|Map input records|Map output records|Reduce input groups|Reduce output records|^\s+OLVA$|ESTANCIAS_EN_HUB|EVENTOS_HUB_LEIDOS|ENVIOS_LEIDOS|Resultados en' $BD/outputs/log_mapreduce.txt \
    | sed -E 's/^[0-9-]+ [0-9:,]+ INFO [a-z.]+\.[A-Za-z]+: //' | awk 'length($0)<=150'
  grep -E '^Tiempo total' $BD/outputs/log_mapreduce.txt
} > salidas/hd_mapreduce_full.txt
# se divide en dos capturas para que quepan en pantalla
total=$(wc -l < salidas/hd_mapreduce_full.txt)
mitad=$(( $(grep -n 'Connecting to ResourceManager' salidas/hd_mapreduce_full.txt | sed -n 2p | cut -d: -f1) - 1 ))   # corte al iniciar el job 2
head -n $mitad salidas/hd_mapreduce_full.txt > salidas/hd_mapreduce_1.txt
tail -n +$(( mitad + 1 )) salidas/hd_mapreduce_full.txt > salidas/hd_mapreduce_2.txt
rm salidas/hd_mapreduce_full.txt
echo "hd_mapreduce_1/2: $total líneas"

# -- generación masiva (salida real registrada al generar los datos) y volumen
{
  echo '$ cd 01_Relacional_PostgreSQL/generador'
  echo '$ OLVA_OUT=../../06_BigData_Hadoop/data/masivo python generar_datos.py 300000'
  cat $BD/outputs/log_generacion.txt
} > salidas/gen_masivo.txt
{
  echo '$ python 06_BigData_Hadoop/04_volumen_y_hallazgos.py'
  sed -n '/JUSTIFICACIÓN/,$p' $BD/outputs/volumen_datos.txt
} > salidas/gen_volumen.txt

# -- integración end-to-end (registro real de 03_integracion_end_to_end.sh)
{
  echo '$ bash 06_BigData_Hadoop/03_integracion_end_to_end.sh'
  sed -n '/1) EXTRACCIÓN/,/3) CARGA/p' $BD/outputs/log_ejecutar_todo.txt | grep -v '3) CARGA' \
    | sed -E 's/^[0-9-]+ [0-9:,]+ INFO mapreduce.Job: /  /'
} | awk 'NF || p {print} {p=NF}' > salidas/int_extraccion.txt
{
  sed -n '/4) VERIFICACIÓN/,/completado/p' $BD/outputs/log_ejecutar_todo.txt
} > salidas/int_verificacion.txt

# -- PostgreSQL: esquema analitica
PGQ() { docker exec -i olva_pg_lima psql -U "$PG_USER" -d olva_courier -P pager=off "$@"; }
{
  echo 'olva_courier=# \dt analitica.*'
  PGQ -c '\dt analitica.*'
  echo "olva_courier=# SELECT codigo, hora_llegada, estancias, permanencia_promedio_h, pct_mayor_12h,"
  echo "olva_courier-#        pct_llegadas_del_hub FROM analitica.vw_franjas_criticas"
  echo "olva_courier-#  WHERE ranking_volumen = 1 ORDER BY estancias DESC LIMIT 8;"
  PGQ -c "SELECT codigo, hora_llegada, estancias, permanencia_promedio_h, pct_mayor_12h, pct_llegadas_del_hub
          FROM analitica.vw_franjas_criticas WHERE ranking_volumen = 1 ORDER BY estancias DESC LIMIT 8;"
  echo "olva_courier=# SELECT clave AS servicio, envios, pct_cumplimiento_sla, retraso_promedio_h, ingresos_soles"
  echo "olva_courier-#   FROM analitica.kpi_cumplimiento_sla WHERE dimension = 'SERVICIO' ORDER BY 3;"
  PGQ -c "SELECT clave AS servicio, envios, pct_cumplimiento_sla, retraso_promedio_h, ingresos_soles
          FROM analitica.kpi_cumplimiento_sla WHERE dimension = 'SERVICIO' ORDER BY 3;"
} > salidas/pg_analitica.txt

# -- MongoDB: colección kpi_bigdata
MQ='db.kpi_bigdata.countDocuments();
db.kpi_bigdata.aggregate([{$group: {_id: "$indicador", documentos: {$sum: 1}}}]).toArray();
db.kpi_bigdata.find({indicador: "permanencia_hub", dimension: "MES", hub: "HR-AQP"},
    {_id: 0, valor: 1, estancias: 1, permanencia_promedio_h: 1, pct_mayor_12h: 1}).sort({valor: 1}).toArray();'
{
  echo 'olva_tracking> db.kpi_bigdata.countDocuments()'
  docker exec olva_mongo mongosh -u "$MONGO_USER" -p "$MONGO_PASSWORD" --authenticationDatabase admin --quiet olva_tracking \
      --eval 'print(db.kpi_bigdata.countDocuments())'
  echo 'olva_tracking> db.kpi_bigdata.aggregate([{ $group: { _id: "$indicador", documentos: { $sum: 1 } } }])'
  docker exec olva_mongo mongosh -u "$MONGO_USER" -p "$MONGO_PASSWORD" --authenticationDatabase admin --quiet olva_tracking \
      --eval 'printjson(db.kpi_bigdata.aggregate([{$group: {_id: "$indicador", documentos: {$sum: 1}}}, {$sort: {_id: 1}}]).toArray())'
  echo 'olva_tracking> db.kpi_bigdata.find({ indicador: "permanencia_hub", dimension: "MES", hub: "HR-AQP" },'
  echo '...   { _id: 0, valor: 1, estancias: 1, permanencia_promedio_h: 1, pct_mayor_12h: 1 }).sort({ valor: 1 })'
  docker exec olva_mongo mongosh -u "$MONGO_USER" -p "$MONGO_PASSWORD" --authenticationDatabase admin --quiet olva_tracking \
      --eval 'db.kpi_bigdata.find({indicador: "permanencia_hub", dimension: "MES", hub: "HR-AQP"}, {_id: 0, valor: 1, estancias: 1, permanencia_promedio_h: 1, pct_mayor_12h: 1}).sort({valor: 1}).forEach(d => print(JSON.stringify(d)))'
} > salidas/mg_kpi.txt

# -- Cassandra: tablas kpi_*
CQ() { docker exec olva_cassandra cqlsh -u olva_admin -p "$CASS_ADMIN_PASSWORD" -k olva_tracking -e "$1" 2>&1 \
        | grep -vE 'Warning: Using a password|Recommendation: use the credentials|^$'; }
{
  q1="SELECT valor AS hora, estancias, permanencia_promedio_h, pct_mayor_12h FROM kpi_permanencia_hub WHERE hub = 'HC-LIM' AND dimension = 'HORA' AND valor >= '18';"
  echo "olva_admin@cqlsh:olva_tracking> $q1"; CQ "$q1"; echo
  q2="SELECT clave AS servicio, envios, pct_cumplimiento_sla, retraso_promedio_h FROM kpi_cumplimiento_sla WHERE dimension = 'SERVICIO';"
  echo "olva_admin@cqlsh:olva_tracking> $q2"; CQ "$q2"
} > salidas/cq_kpi.txt

ls -la salidas

# comandos largos en varias líneas y tabuladores como espacios
/g/Herramientas/Python312/python.exe ajustar_comandos.py
sed -i "s/	/    /g" salidas/*.txt
