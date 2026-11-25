#!/bin/bash
# Inicia, detiene o muestra el estado de los demonios de Hadoop instalados en Ubuntu (WSL).
# Uso (PowerShell): wsl -d Ubuntu-22.04 -u hadoop -- hadoop_cluster start|stop|status
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
B=$HADOOP_HOME/bin
DN2="env HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop-datanode2 HADOOP_PID_DIR=/tmp/hadoop-dn2 HADOOP_LOG_DIR=$HADOOP_HOME/logs/datanode2"

if [ "$(id -un)" != hadoop ]; then
    exec su - hadoop -c "$0 $*"
fi

case "$1" in
start)
    $B/hdfs --daemon start namenode
    $B/hdfs --daemon start datanode
    $DN2 $B/hdfs --daemon start datanode
    $B/yarn --daemon start resourcemanager
    $B/yarn --daemon start nodemanager
    $B/mapred --daemon start historyserver
    $B/hdfs dfsadmin -safemode wait >/dev/null 2>&1
    "$0" status
    ;;
stop)
    $B/mapred --daemon stop historyserver
    $B/yarn --daemon stop nodemanager
    $B/yarn --daemon stop resourcemanager
    $DN2 $B/hdfs --daemon stop datanode
    $B/hdfs --daemon stop datanode
    $B/hdfs --daemon stop namenode
    ;;
status)
    echo "== Procesos Java de Hadoop (jps) =="
    $JAVA_HOME/bin/jps | grep -v Jps | sort -k2
    echo "== HDFS =="
    $B/hdfs dfsadmin -report 2>/dev/null | grep -E 'Live datanodes|^Name:|DFS Used%'
    echo "== YARN =="
    $B/yarn node -list 2>/dev/null | tail -n +2
    echo "Web: HDFS http://localhost:9870 | YARN http://localhost:8088 | JobHistory http://localhost:19888"
    ;;
*)
    echo "Uso: hadoop_cluster start|stop|status"; exit 2 ;;
esac
