#!/bin/bash
# Big Data completo (puntos 12 a 15): genera el conjunto masivo, compila MapReduce, carga HDFS,
# ejecuta los jobs en YARN, integra los resultados en PostgreSQL/MongoDB/Cassandra y resume hallazgos.
# Requiere: Apache Hadoop iniciado (hadoop_nativo/iniciar_hadoop.bat; o HADOOP_MODO=docker con el perfil hadoop)
#           y los contenedores olva_pg_lima, olva_mongo,
#           olva_cassandra (y olva_cassandra_arequipa) encendidos.
# Uso (Git Bash, en la raíz del proyecto): bash 06_BigData_Hadoop/00_ejecutar_todo.sh [n_envios]
set -eo pipefail
cd "$(dirname "$0")"
N=${1:-300000}
PY=${PY:-/g/Herramientas/Python312/python.exe}
export PYTHONIOENCODING=utf-8

echo "== 12) Generación del conjunto masivo ($N envíos) =="
if [ ! -s data/masivo/evento_tracking.csv ]; then
    mkdir -p data/masivo
    OLVA_OUT="$(cygpath -w "$PWD/data/masivo")" $PY ../01_Relacional_PostgreSQL/generador/generar_datos.py "$N"
else
    echo "data/masivo ya existe (bórrelo para regenerar)"
fi
echo "== 13) Compilación del código MapReduce =="
bash mapreduce/compilar.sh >/dev/null && echo "mapreduce/olva-bigdata.jar compilado"
echo "== 13) Carga en HDFS =="
bash 01_cargar_hdfs.sh
echo "== 13) Ejecución MapReduce en YARN =="
bash 02_ejecutar_mapreduce.sh
echo "== 14) Integración end-to-end =="
bash 03_integracion_end_to_end.sh
echo "== 12.4 / 15) Volumen y hallazgos =="
$PY 04_volumen_y_hallazgos.py
