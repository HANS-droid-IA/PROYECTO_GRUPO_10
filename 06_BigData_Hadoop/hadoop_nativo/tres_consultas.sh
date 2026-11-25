#!/bin/bash
# 3 consultas de demostración sobre HDFS (resultados de MapReduce y datos del portal web)
c() { echo; echo -e "\e[1;33mhadoop@Hans:~\$ $1\e[0m"; bash -c "$1"; }
clear
echo "===== 3 consultas en Hadoop (HDFS) ====="
c "hdfs dfs -cat /olva/resultados/permanencia_hub/part-r-00000 | grep '^HORA,HC-LIM' | sort -t, -k4 -nr | head -5"
c "hdfs dfs -cat /olva/resultados/cumplimiento_sla/part-r-00000 | grep '^SERVICIO,'"
c "hdfs dfs -du -h /olva/raw"
echo
exec bash
