#!/bin/bash
# Instala Apache Hadoop 3.3.6 en Ubuntu 22.04 (WSL) en modo pseudo-distribuido:
#   NameNode, 2 DataNodes, ResourceManager, NodeManager y JobHistory Server en la misma máquina.
# Requisitos previos (los instala este script si faltan): OpenJDK 11.
# El paquete se descarga de la web oficial de Apache y se verifica su SHA-512.
# Uso (PowerShell): wsl -d Ubuntu-22.04 -u root -- bash /mnt/g/PROYECTO_GRUPO_10/06_BigData_Hadoop/hadoop_nativo/instalar_hadoop.sh
set -eo pipefail
VERSION=3.3.6
URL=https://archive.apache.org/dist/hadoop/common/hadoop-$VERSION/hadoop-$VERSION.tar.gz
AQUI="$(cd "$(dirname "$0")" && pwd)"
JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

echo "== Java 11 =="
[ -x $JAVA_HOME/bin/java ] || { apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-11-jdk-headless; }
$JAVA_HOME/bin/java -version 2>&1 | head -1

echo "== Usuario de servicio 'hadoop' =="
id hadoop >/dev/null 2>&1 || useradd -m -s /bin/bash hadoop

echo "== Apache Hadoop $VERSION =="
cd /opt
if [ ! -d /opt/hadoop-$VERSION ]; then
    [ -f hadoop-$VERSION.tar.gz ] || curl -sSfLO "$URL"
    [ -f hadoop-$VERSION.tar.gz.sha512 ] || curl -sSfLO "$URL.sha512"
    # el .sha512 oficial de 3.3.6 nombra al archivo candidato (RC1): se compara solo el valor del hash
    [ "$(grep -oE '[0-9a-f]{128}' hadoop-$VERSION.tar.gz.sha512)" = "$(sha512sum hadoop-$VERSION.tar.gz | cut -d' ' -f1)" ] \
        || { echo "SHA-512 no coincide: descarga corrupta"; exit 1; }
    echo "SHA-512 verificado"
    tar -xzf hadoop-$VERSION.tar.gz
fi
ln -sfn /opt/hadoop-$VERSION /opt/hadoop
chown -R hadoop:hadoop /opt/hadoop-$VERSION

echo "== Configuración (core, hdfs, mapred, yarn) =="
cp "$AQUI"/conf/*.xml /opt/hadoop/etc/hadoop/
sed -i '/^export JAVA_HOME=/d; /^export HADOOP_HEAPSIZE_MAX=/d' /opt/hadoop/etc/hadoop/hadoop-env.sh
cat >> /opt/hadoop/etc/hadoop/hadoop-env.sh <<EOF
export JAVA_HOME=$JAVA_HOME
export HADOOP_HEAPSIZE_MAX=512m
EOF
# Segundo DataNode: misma configuración con otro directorio de datos y otros puertos
rm -rf /opt/hadoop/etc/hadoop-datanode2
cp -r /opt/hadoop/etc/hadoop /opt/hadoop/etc/hadoop-datanode2
sed -i 's#</configuration>#  <property><name>dfs.datanode.address</name><value>0.0.0.0:9876</value></property>\n  <property><name>dfs.datanode.http.address</name><value>0.0.0.0:9874</value></property>\n  <property><name>dfs.datanode.ipc.address</name><value>0.0.0.0:9877</value></property>\n</configuration>#; s#datanode1</value>#datanode2</value>#' \
    /opt/hadoop/etc/hadoop-datanode2/hdfs-site.xml
chown -R hadoop:hadoop /opt/hadoop/etc

cat > /etc/profile.d/hadoop.sh <<EOF
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=/opt/hadoop
export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop
export PATH=\$PATH:/opt/hadoop/bin:/opt/hadoop/sbin
EOF
# comandos disponibles en el PATH (envoltorios: Hadoop ubica libexec/ a partir de su propia ruta)
for b in hadoop hdfs yarn mapred; do
    rm -f /usr/local/bin/$b
    printf '#!/bin/bash\nexec /opt/hadoop/bin/%s "$@"\n' $b > /usr/local/bin/$b
    chmod 755 /usr/local/bin/$b
done
install -m 755 "$AQUI/hadoop_cluster.sh" /usr/local/bin/hadoop_cluster

echo "== Formato del NameNode (solo la primera vez) =="
if [ ! -d /home/hadoop/hadoop_data/namenode/current ]; then
    su - hadoop -c "mkdir -p ~/hadoop_data && JAVA_HOME=$JAVA_HOME /opt/hadoop/bin/hdfs namenode -format -nonInteractive -clusterId olva-courier" 2>&1 | grep -E 'successfully formatted|ERROR'
fi
/opt/hadoop/bin/hadoop version | head -1
echo "Instalación completa. Iniciar con: hadoop_cluster start"
