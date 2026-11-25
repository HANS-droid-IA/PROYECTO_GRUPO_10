#!/bin/bash
# Muestra el estado del clúster Hadoop y los datos/resultados del proyecto en HDFS (para la exposición).
# Uso: wsl -d Ubuntu-22.04 -u hadoop -- bash /mnt/g/PROYECTO_GRUPO_10/06_BigData_Hadoop/hadoop_nativo/mostrar_hadoop.sh
clear
echo "================ APACHE HADOOP - Olva Courier ================"
hadoop version | head -1
echo
hadoop_cluster status
echo
echo "================ Datos masivos en HDFS (/olva/raw) ================"
hdfs dfs -du -h /olva/raw
echo
echo "================ Resultados de MapReduce (/olva/resultados) ================"
hdfs dfs -ls /olva/resultados
echo
echo "Hub Central Lima - llegadas a las 20:00 (dimension,hub,hora,estancias,horas_promedio,%>12h):"
hdfs dfs -cat /olva/resultados/permanencia_hub/part-r-00000 | grep '^HORA,HC-LIM,20'
echo
echo "Comandos para probar:  hdfs dfs -ls /olva   |   hdfs dfs -cat /olva/resultados/cumplimiento_sla/part-r-00000"
exec bash
