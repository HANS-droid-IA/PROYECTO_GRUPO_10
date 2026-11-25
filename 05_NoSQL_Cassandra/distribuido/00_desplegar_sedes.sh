#!/bin/bash
# =====================================================================
# Cassandra con 2 sedes (dc_lima y dc_arequipa): despliegue y pruebas.
# Se ejecuta en Git Bash desde la raíz del proyecto, con ambos nodos encendidos
# y el keyspace olva_tracking ya cargado (05_NoSQL_Cassandra/00_ejecutar_todo.sh):
#   docker compose --profile nosql --profile sedes_cassandra up -d
#   bash 05_NoSQL_Cassandra/distribuido/00_desplegar_sedes.sh
# La contraseña de olva_admin se toma de .env (CASS_ADMIN_PASSWORD).
# =====================================================================
set -eo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")"
mkdir -p evidencias
P=$(grep '^CASS_ADMIN_PASSWORD=' ../../.env | cut -d= -f2-)
LIMA=olva_cassandra; AQP=olva_cassandra_arequipa
ev() { tee -a "evidencias/$1"; }
# cqlsh contra el nodo de una sede (el coordinador de la consulta es ese nodo)
cql() { local nodo=$1; shift
        docker exec "$nodo" cqlsh --request-timeout=60 -u olva_admin -p "$P" "$@" 2>&1 \
          | grep -v -e 'password on the command line' -e 'credentials file to securely' || true; }
ip() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"; }
: > evidencias/01_despliegue.txt; : > evidencias/02_pruebas_sedes.txt; : > evidencias/03_sede_caida.txt
echo "Sede Lima     = $LIMA ($(ip $LIMA), dc_lima)"         | ev 01_despliegue.txt
echo "Sede Arequipa = $AQP ($(ip $AQP), dc_arequipa)"       | ev 01_despliegue.txt

echo ">> 1. Topología del clúster: dos centros de datos" | ev 01_despliegue.txt
docker exec $LIMA nodetool status | ev 01_despliegue.txt

echo ">> 2. Replicación en ambas sedes y keyspace local de Arequipa" | ev 01_despliegue.txt
docker cp 01_replicar_sedes.cql $LIMA:/tmp/01_replicar_sedes.cql
cql $LIMA -f /tmp/01_replicar_sedes.cql | ev 01_despliegue.txt

echo ">> 3. nodetool rebuild: la sede Arequipa copia los datos existentes desde Lima" | ev 01_despliegue.txt
inicio=$(date +%s)
docker exec $AQP nodetool rebuild -- dc_lima
echo "rebuild terminado en $(( $(date +%s) - inicio )) s" | ev 01_despliegue.txt
docker exec $LIMA nodetool status olva_tracking | ev 01_despliegue.txt
for n in $LIMA $AQP; do
  echo "--- $n: tablas de olva_tracking en disco" | ev 01_despliegue.txt
  docker exec $n nodetool flush olva_tracking
  docker exec $n nodetool tablestats olva_tracking.eventos_por_envio olva_tracking.eventos_por_hub_dia \
    | grep -E 'Table:|Number of partitions|Space used \(live\)' | ev 01_despliegue.txt
done

echo ">> 4. ¿Qué nodos guardan un envío? (una réplica por sede)" | ev 02_pruebas_sedes.txt
echo "nodetool getendpoints olva_tracking eventos_por_envio OLV2600000001:" | ev 02_pruebas_sedes.txt
docker exec $LIMA nodetool getendpoints olva_tracking eventos_por_envio OLV2600000001 \
  | sed "s/$(ip $LIMA)/& (sede Lima)/; s/$(ip $AQP)/& (sede Arequipa)/" | ev 02_pruebas_sedes.txt
echo "nodetool getendpoints olva_sede_arequipa operaciones_locales 'HR-AQP:2026-10-07':" | ev 02_pruebas_sedes.txt
docker exec $LIMA nodetool getendpoints olva_sede_arequipa operaciones_locales 'HR-AQP:2026-10-07' \
  | sed "s/$(ip $LIMA)/& (sede Lima)/; s/$(ip $AQP)/& (sede Arequipa)/" | ev 02_pruebas_sedes.txt

echo ">> 5. La misma consulta respondida por cada sede (cada una tiene la copia completa)" | ev 02_pruebas_sedes.txt
for n in $LIMA $AQP; do
  echo "--- coordinador: $n (CONSISTENCY LOCAL_ONE)" | ev 02_pruebas_sedes.txt
  cql $n -e "CONSISTENCY LOCAL_ONE;
    SELECT hora, llegadas, salidas FROM olva_tracking.escaneos_hub_hora WHERE hub = 'HC-LIM' AND dia = '2026-10-06' AND hora >= 20;
    SELECT COUNT(*) AS eventos_del_envio FROM olva_tracking.eventos_por_envio WHERE nro_tracking = 'OLV2600000001';" | ev 02_pruebas_sedes.txt
done

echo ">> 6. Escritura en Arequipa, lectura en Lima (replicación entre sedes)" | ev 02_pruebas_sedes.txt
cql $AQP -e "CONSISTENCY LOCAL_ONE;
  INSERT INTO olva_tracking.alertas_sla (hub, fecha_alerta, nro_tracking, nivel, mensaje)
  VALUES ('HR-AQP', '2026-10-07 23:00:00+0000', 'OLV2600029836', 'AVISO', 'Registrada en la sede Arequipa');" | ev 02_pruebas_sedes.txt
sleep 2
cql $LIMA -e "CONSISTENCY LOCAL_ONE;
  SELECT hub, nro_tracking, nivel, mensaje FROM olva_tracking.alertas_sla WHERE hub = 'HR-AQP';" | ev 02_pruebas_sedes.txt

echo ">> 7. Dato local: se escribe en Arequipa y NO existe réplica en Lima" | ev 02_pruebas_sedes.txt
cql $AQP -e "CONSISTENCY LOCAL_ONE;
  INSERT INTO olva_sede_arequipa.operaciones_locales (hub, dia, fecha_hora, operacion, detalle)
  VALUES ('HR-AQP', '2026-10-07', '2026-10-07 22:00:00+0000', 'TURNO', 'Cierre de turno noche, 3 operarios');
  SELECT * FROM olva_sede_arequipa.operaciones_locales WHERE hub = 'HR-AQP' AND dia = '2026-10-07';" | ev 02_pruebas_sedes.txt
echo "--- leído desde Lima con LOCAL_ONE (Lima no tiene réplica de este keyspace):" | ev 02_pruebas_sedes.txt
cql $LIMA -e "CONSISTENCY LOCAL_ONE;
  SELECT * FROM olva_sede_arequipa.operaciones_locales WHERE hub = 'HR-AQP' AND dia = '2026-10-07';" | ev 02_pruebas_sedes.txt
echo "--- leído desde Lima con ONE (el coordinador de Lima lo pide a la sede Arequipa):" | ev 02_pruebas_sedes.txt
cql $LIMA -e "CONSISTENCY ONE;
  SELECT * FROM olva_sede_arequipa.operaciones_locales WHERE hub = 'HR-AQP' AND dia = '2026-10-07';" | ev 02_pruebas_sedes.txt

echo ">> 8. Niveles de consistencia entre sedes" | ev 02_pruebas_sedes.txt
cql $LIMA -e "CONSISTENCY EACH_QUORUM;
  INSERT INTO olva_tracking.alertas_sla (hub, fecha_alerta, nro_tracking, nivel, mensaje)
  VALUES ('HC-LIM', '2026-10-07 23:05:00+0000', 'OLV2600029865', 'CRITICO', 'Confirmada en las dos sedes (EACH_QUORUM)');
  CONSISTENCY ALL;
  SELECT nro_tracking, nivel, mensaje FROM olva_tracking.alertas_sla WHERE hub = 'HC-LIM';" | ev 02_pruebas_sedes.txt

echo ">> 9. Caída de la sede Lima" | ev 03_sede_caida.txt
trap 'docker start olva_cassandra >/dev/null 2>&1' EXIT          # Lima se vuelve a encender pase lo que pase
docker stop $LIMA >/dev/null
echo "$LIMA DETENIDO" | ev 03_sede_caida.txt
until docker exec $AQP nodetool status 2>/dev/null | grep -q '^DN'; do sleep 2; done
docker exec $AQP nodetool status | grep -E 'Datacenter|^UN|^DN' | ev 03_sede_caida.txt
echo "--- la sede Arequipa sigue atendiendo (inicio de sesión + lectura + escritura locales):" | ev 03_sede_caida.txt
cql $AQP -e "CONSISTENCY LOCAL_ONE;
  SELECT fecha_hora, tipo_evento, hub FROM olva_tracking.eventos_por_envio WHERE nro_tracking = 'OLV2600000001' LIMIT 3;
  INSERT INTO olva_tracking.alertas_sla (hub, fecha_alerta, nro_tracking, nivel, mensaje)
  VALUES ('HR-AQP', '2026-10-07 23:10:00+0000', 'OLV2600029839', 'AVISO', 'Escrita con la sede Lima caída');" | ev 03_sede_caida.txt
echo "--- operaciones que exigen a las dos sedes fallan:" | ev 03_sede_caida.txt
cql $AQP -e "CONSISTENCY ALL; SELECT COUNT(*) FROM olva_tracking.alertas_sla WHERE hub = 'HR-AQP';" | ev 03_sede_caida.txt
cql $AQP -e "CONSISTENCY EACH_QUORUM;
  INSERT INTO olva_tracking.alertas_sla (hub, fecha_alerta, nro_tracking, nivel, mensaje)
  VALUES ('HR-AQP', '2026-10-07 23:11:00+0000', 'OLV2600029839', 'AVISO', 'no debería guardarse');" | ev 03_sede_caida.txt
echo "--- hints guardados en Arequipa para entregar a Lima cuando vuelva:" | ev 03_sede_caida.txt
docker exec $AQP nodetool listpendinghints 2>&1 | ev 03_sede_caida.txt

docker start $LIMA >/dev/null
echo "$LIMA ENCENDIDO de nuevo, esperando que vuelva al anillo..." | ev 03_sede_caida.txt
until docker exec $AQP nodetool status 2>/dev/null | grep -c '^UN' | grep -q 2; do sleep 5; done
until cql $LIMA -e "SELECT now() FROM system.local" | grep -q now; do sleep 5; done
sleep 15
echo "--- lo escrito en Arequipa durante la caída ya está en Lima (hinted handoff):" | ev 03_sede_caida.txt
cql $LIMA -e "CONSISTENCY LOCAL_ONE;
  SELECT nro_tracking, nivel, mensaje FROM olva_tracking.alertas_sla WHERE hub = 'HR-AQP';" | ev 03_sede_caida.txt
echo ">> Cassandra con 2 sedes lista"
