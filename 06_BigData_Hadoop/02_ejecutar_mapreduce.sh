#!/bin/bash
# Ejecuta en YARN los 3 jobs MapReduce (Driver pe.olva.bigdata.OlvaBigDataDriver) y descarga los resultados
# a 06_BigData_Hadoop/outputs/ (permanencia_hub.csv, cumplimiento_sla.csv, log del job).
# Uso (Git Bash, en la raíz del proyecto): bash 06_BigData_Hadoop/02_ejecutar_mapreduce.sh
set -eo pipefail
cd "$(dirname "$0")"
. ./entorno_hadoop.sh
mkdir -p outputs
inicio=$(date +%s)
$HX hadoop jar $HP/mapreduce/olva-bigdata.jar /olva/raw /olva/resultados 2>&1 | tee outputs/log_mapreduce.txt \
  | grep -E 'Running job|Job job_.* completed|Map input records|Map output records|Reduce input groups|Reduce output records|OLVA|ENVIOS_LEIDOS|ESTANCIAS|EVENTOS_HUB|Resultados en|Falló'
echo "Tiempo total: $(( $(date +%s) - inicio )) s" | tee -a outputs/log_mapreduce.txt

CAB_P='dimension,hub,valor,estancias,permanencia_promedio_h,pct_mayor_12h'
CAB_S='dimension,clave,detalle,envios,entregados,pct_cumplimiento_sla,retraso_promedio_h,ingresos_soles'
{ echo "$CAB_P"; $HX hdfs dfs -cat '/olva/resultados/permanencia_hub/part-r-*'; } > outputs/permanencia_hub.csv
{ echo "$CAB_S"; $HX hdfs dfs -cat '/olva/resultados/cumplimiento_sla/part-r-*'; } > outputs/cumplimiento_sla.csv
$HX hdfs dfs -ls -R /olva/resultados > outputs/hdfs_resultados_ls.txt
wc -l outputs/permanencia_hub.csv outputs/cumplimiento_sla.csv
