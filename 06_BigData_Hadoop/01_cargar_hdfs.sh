#!/bin/bash
# Carga el conjunto de datos masivo en HDFS con una organización por zonas:
#   /olva/raw/<tabla>/        datos crudos (CSV) tal como salen del generador / de las bases operacionales
#   /olva/raw/catalogos/      catálogos pequeños (hub, ciudad, region, tipo_servicio) para la caché distribuida
#   /olva/resultados/         salida de MapReduce (la crea el job)
# Uso (Git Bash, en la raíz del proyecto): bash 06_BigData_Hadoop/01_cargar_hdfs.sh
set -eo pipefail
. "$(dirname "$0")/entorno_hadoop.sh"
TABLAS_MASIVAS="evento_tracking envio paquete intento_entrega despacho_envio incidencia comprobante destinatario"
CATALOGOS="hub ciudad region tipo_servicio ruta tarifa"

$HX bash -c "
set -e
hdfs dfsadmin -safemode wait >/dev/null
hdfs dfs -rm -r -f -skipTrash /olva/raw >/dev/null
hdfs dfs -mkdir -p /olva/raw/catalogos /olva/resultados
for t in $TABLAS_MASIVAS; do
  hdfs dfs -mkdir -p /olva/raw/\$t
  hdfs dfs -put -f $HP/data/masivo/\$t.csv /olva/raw/\$t/
done
for c in $CATALOGOS; do hdfs dfs -put -f $HP/data/masivo/\$c.csv /olva/raw/catalogos/; done
echo '== Contenido de /olva/raw =='
hdfs dfs -du -h /olva/raw
echo '== Bloques y réplicas de evento_tracking (dfs.blocksize = 64 MB, replicación = 2) =='
hdfs fsck /olva/raw/evento_tracking -files -blocks -locations 2>/dev/null | grep -E 'evento_tracking.csv|Total blocks|Average block replication|Status|blk_' | head -12
"
