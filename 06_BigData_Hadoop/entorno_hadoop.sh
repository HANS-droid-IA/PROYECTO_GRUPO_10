#!/bin/bash
# Define cómo se ejecutan los comandos de Hadoop desde Git Bash (Windows).
#   HADOOP_MODO=nativo (por defecto): Apache Hadoop 3.3.6 instalado en Ubuntu 22.04 (WSL)
#   HADOOP_MODO=docker              : clúster del perfil "hadoop" de docker-compose
# HX = prefijo para ejecutar un comando de Hadoop (hdfs, hadoop, bash -c ...) en el clúster
# HP = ruta de la carpeta 06_BigData_Hadoop vista desde el clúster
export MSYS_NO_PATHCONV=1
if [ "${HADOOP_MODO:-nativo}" = docker ]; then
    HX="docker exec -i olva_namenode"
    HP=/proyecto
else
    HX="wsl.exe -d Ubuntu-22.04 -u hadoop -e"
    HP=/mnt/g/PROYECTO_GRUPO_10/06_BigData_Hadoop
fi
