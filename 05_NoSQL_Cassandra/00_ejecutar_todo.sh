#!/bin/bash
# =====================================================================
# Cassandra - Olva Courier: crea el keyspace olva_tracking, carga los datos,
# ejecuta las consultas CQL y la seguridad, y guarda evidencias.
# Uso (desde la raíz del proyecto, con el contenedor encendido):
#   python 05_NoSQL_Cassandra/generar_csv_cassandra.py
#   docker exec -e CASS_ADMIN_PASSWORD=<CONTRASEÑA_CONFIGURADA> -e CASS_APP_PASSWORD=<CONTRASEÑA_CONFIGURADA> \
#               olva_cassandra bash /scripts/00_ejecutar_todo.sh
# =====================================================================
set -e
cd /scripts
mkdir -p evidencias
: "${CASS_ADMIN_PASSWORD:?Falta CASS_ADMIN_PASSWORD}" "${CASS_APP_PASSWORD:?Falta CASS_APP_PASSWORD}"
silencio() { grep -v -e 'Using a password on the command line' -e 'credentials file to securely'; }
cql() { cqlsh --request-timeout=120 -u "$1" -p "$2" "${@:3}" 2>&1 | silencio || true; }

echo ">> Esperando a Cassandra"
until cqlsh -u olva_admin -p "$CASS_ADMIN_PASSWORD" -e 'SELECT now() FROM system.local' >/dev/null 2>&1 \
   || cqlsh -u cassandra -p cassandra -e 'SELECT now() FROM system.local' >/dev/null 2>&1; do sleep 5; done

# Primera vez: el único usuario es cassandra/cassandra -> se crea el administrador del proyecto
if ! cqlsh -u olva_admin -p "$CASS_ADMIN_PASSWORD" -e 'SELECT now() FROM system.local' >/dev/null 2>&1; then
    echo ">> Creando el superusuario olva_admin"
    cql cassandra cassandra -e "CREATE ROLE IF NOT EXISTS olva_admin WITH SUPERUSER = true AND LOGIN = true AND PASSWORD = '$CASS_ADMIN_PASSWORD';"
fi
ADMIN=(olva_admin "$CASS_ADMIN_PASSWORD")

echo ">> 01 Keyspace y tablas"
cql "${ADMIN[@]}" -f 01_keyspace_tablas.cql | tee evidencias/01_keyspace_tablas.txt
cql "${ADMIN[@]}" -e "DESCRIBE TABLE olva_tracking.eventos_por_hub_dia" | tee -a evidencias/01_keyspace_tablas.txt

echo ">> 02 Carga masiva (COPY FROM)"
cql "${ADMIN[@]}" -f 02_carga_masiva.cql | grep -v '^Processed:' | tee evidencias/02_carga_masiva.txt
cql "${ADMIN[@]}" -e "
SELECT COUNT(*) AS eventos_por_envio   FROM olva_tracking.eventos_por_envio;
SELECT COUNT(*) AS eventos_por_hub_dia FROM olva_tracking.eventos_por_hub_dia;
SELECT COUNT(*) AS escaneos_hub_hora   FROM olva_tracking.escaneos_hub_hora;
SELECT COUNT(*) AS envios_por_cliente  FROM olva_tracking.envios_por_cliente;
SELECT COUNT(*) AS estado_envio        FROM olva_tracking.estado_envio;" | tee -a evidencias/02_carga_masiva.txt
nodetool flush olva_tracking
nodetool tablestats olva_tracking | grep -E 'Table|Space used \(live\)|Number of partitions|Compacted partition maximum bytes' \
    | tee -a evidencias/02_carga_masiva.txt

echo ">> 03 Consultas CQL"
cql "${ADMIN[@]}" -f 03_consultas.cql | tee evidencias/03_consultas.txt

echo ">> 04 Seguridad"
sed "s/__CLAVE_APP__/$CASS_APP_PASSWORD/g" 04_seguridad.cql > /tmp/seguridad.cql
cql "${ADMIN[@]}" -f /tmp/seguridad.cql | tee evidencias/04_seguridad.txt
rm -f /tmp/seguridad.cql
# Cassandra guarda en caché roles y permisos (roles_validity / permissions_validity):
# se espera a que caduque para que los usuarios recreados vean sus permisos nuevos
sleep 15
for u in u_analista_cass u_operador_cass u_portal_web; do
    echo "=== Conectado como $u ==="
    cql "$u" "$CASS_APP_PASSWORD" -f 05_pruebas_seguridad.cql
done | tee -a evidencias/04_seguridad.txt
echo "=== Superusuario por defecto (cassandra) deshabilitado ===" | tee -a evidencias/04_seguridad.txt
cql cassandra cassandra -e 'SELECT now() FROM system.local' | tail -1 | tee -a evidencias/04_seguridad.txt
echo "=== Contraseña incorrecta ===" | tee -a evidencias/04_seguridad.txt
cql u_analista_cass incorrecta -e 'SELECT now() FROM system.local' | tail -1 | tee -a evidencias/04_seguridad.txt
echo ">> Cassandra lista"
