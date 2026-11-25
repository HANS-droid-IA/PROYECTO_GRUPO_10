#!/bin/bash
# Captura (Chrome sin interfaz) las consolas web reales del clúster Hadoop en ejecución.
# Uso: bash capturar_web.sh   (requiere Hadoop iniciado: hadoop_nativo/iniciar_hadoop.bat)
cd "$(dirname "$0")"
CH="/c/Program Files/Google/Chrome/Application/chrome.exe"
J1=$(curl -s 'http://localhost:19888/ws/v1/history/mapreduce/jobs' | grep -oE 'job_[0-9]+_0001' | head -1)
cap() {  # $1 nombre  $2 url  $3 alto
    "$CH" --headless=new --disable-gpu --hide-scrollbars --window-size=${4:-1500},${3:-950} --force-device-scale-factor=1.5 \
        --virtual-time-budget=9000 --run-all-compositor-stages-before-draw \
        --screenshot="$(cygpath -w "$PWD/web/$1.png")" "$2" 2>/dev/null
    echo "$1 <- $2"
}
cap hd_web_resumen      'http://localhost:9870/dfshealth.html#tab-overview' 1250
cap hd_web_datanodes    'http://localhost:9870/dfshealth.html#tab-datanode' 1300
cap hd_web_raw          'http://localhost:9870/explorer.html#/olva/raw' 760
cap hd_web_resultados   'http://localhost:9870/explorer.html#/olva/resultados/permanencia_hub' 600
cap hd_web_yarn_apps    'http://localhost:8088/cluster/apps' 1100 1850
cap hd_web_yarn_nodos   'http://localhost:8088/cluster/nodes' 560 1850
cap hd_web_job          "http://localhost:19888/jobhistory/job/$J1" 900
cap hd_web_contadores   "http://localhost:19888/jobhistory/jobcounters/$J1" 2200 1300
