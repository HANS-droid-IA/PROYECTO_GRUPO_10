#!/bin/bash
# Compila el código MapReduce (Java 8, igual que el clúster Hadoop 3.3.6) y genera olva-bigdata.jar
# Requiere un JDK (javac/jar) en el equipo; las librerías de Hadoop se copian del contenedor NameNode.
# Uso (Git Bash): bash 06_BigData_Hadoop/mapreduce/compilar.sh
set -eo pipefail
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1
JDK_BIN="${JDK_BIN:-/c/Program Files/Java/jdk-26.0.1/bin}"
mkdir -p lib build
for j in common/hadoop-common-3.3.6.jar mapreduce/hadoop-mapreduce-client-core-3.3.6.jar \
         common/lib/hadoop-annotations-3.3.6.jar common/lib/commons-logging-1.1.3.jar; do
    [ -f "lib/$(basename "$j")" ] || docker cp "olva_namenode:/opt/hadoop/share/hadoop/$j" lib/
done
rm -rf build/*
CP="$(ls lib/*.jar | tr '\n' ';')"
"$JDK_BIN/javac.exe" --release 8 -encoding UTF-8 -Xlint:-options -cp "$CP" -d build src/pe/olva/bigdata/*.java
"$JDK_BIN/jar.exe" cfe olva-bigdata.jar pe.olva.bigdata.OlvaBigDataDriver -C build .
echo "Generado: $(pwd)/olva-bigdata.jar"
"$JDK_BIN/jar.exe" tf olva-bigdata.jar | grep '\.class$'
