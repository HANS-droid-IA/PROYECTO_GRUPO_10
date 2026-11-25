#!/bin/bash
# =====================================================================
# MongoDB con 2 sedes (Lima y Arequipa): despliegue completo y evidencias.
# Se ejecuta en Git Bash desde la raíz del proyecto, con el clúster encendido:
#   docker compose --profile sedes_mongo up -d
#   bash 04_NoSQL_MongoDB/distribuido/00_desplegar_sedes.sh
# Requiere 04_NoSQL_MongoDB/datos/envios.json (python 04_NoSQL_MongoDB/generar_documentos.py)
# El usuario administrador se toma de .env (MONGO_USER / MONGO_PASSWORD).
# =====================================================================
set -eo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")"
mkdir -p evidencias
U=$(grep '^MONGO_USER=' ../../.env | cut -d= -f2-)
P=$(grep '^MONGO_PASSWORD=' ../../.env | cut -d= -f2-)
ev() { tee -a "evidencias/$1"; }
: > evidencias/01_despliegue.txt; : > evidencias/02_consultas_sedes.txt; : > evidencias/03_sede_caida.txt

echo ">> 1. Iniciar los conjuntos de réplicas (config server y una por sede)" | ev 01_despliegue.txt
iniciar() {  # contenedor puerto replSet [configsvr]
    docker exec "$1" mongosh --quiet --port "$2" --eval "
      if (db.hello().setName) print('$3 ya estaba iniciado');   // hello() no requiere autenticación
      else { rs.initiate({ _id: '$3', ${4:+configsvr: true,} members: [{ _id: 0, host: '$1:$2' }] }); print('$3 iniciado'); }"
    until docker exec "$1" mongosh --quiet --port "$2" --eval 'quit(db.hello().isWritablePrimary ? 0 : 1)' >/dev/null 2>&1; do sleep 2; done
}
iniciar olva_mongo_cfg 27019 rs_config si | ev 01_despliegue.txt
iniciar olva_mongo_lima 27018 rs_lima | ev 01_despliegue.txt
iniciar olva_mongo_arequipa 27018 rs_arequipa | ev 01_despliegue.txt

echo ">> 2. Administrador del clúster (excepción localhost del router, solo la primera vez)" | ev 01_despliegue.txt
until docker exec olva_mongos mongosh --quiet --eval 'db.adminCommand({ping:1})' >/dev/null 2>&1; do sleep 2; done
docker exec -e U="$U" -e P="$P" olva_mongos mongosh --quiet --eval "
  const a = db.getSiblingDB('admin');
  try { a.createUser({ user: process.env.U, pwd: process.env.P, roles: ['root'] }); print('usuario ' + process.env.U + ' creado'); }
  catch (e) { print('usuario ya existe (' + e.codeName + ')'); }" | ev 01_despliegue.txt
M() { docker exec -e P="$P" olva_mongos mongosh --quiet -u "$U" -p "$P" --authenticationDatabase admin "$@"; }

echo ">> 3. Sedes, zonas y colección fragmentada" | ev 01_despliegue.txt
M --file /scripts/01_configurar_sedes.js | ev 01_despliegue.txt

echo ">> 4. Carga a través del router: mongos envía cada documento a su sede" | ev 01_despliegue.txt
for c in envios hubs clientes; do
    inicio=$(date +%s)
    docker exec olva_mongos mongoimport --quiet -u "$U" -p "$P" --authenticationDatabase admin \
        --db olva_sedes --collection "$c" --file "/datos/$c.json" --numInsertionWorkers 4
    echo "mongoimport $c: $(wc -l < ../datos/$c.json) documentos en $(( $(date +%s) - inicio )) s" | ev 01_despliegue.txt
done
M --eval "db = db.getSiblingDB('olva_sedes');
  db.envios.createIndex({ estado_actual: 1, 'fechas.compromiso': 1 });
  db.envios.createIndex({ 'destino.ciudad': 1 });
  print('índices creados en cada sede: ' + db.envios.getIndexes().map(i => i.name).join(', '));" | ev 01_despliegue.txt
M --eval "sh.status()" | grep -E "shards|_id: 'sede|tags|olva_sedes.envios|sede_lima|sede_arequipa|chunks:|ZONA" | head -30 | ev 01_despliegue.txt

echo ">> 5. Consultas distribuidas" | ev 02_consultas_sedes.txt
M --file /scripts/02_consultas_sedes.js | ev 02_consultas_sedes.txt

echo ">> 6. Simulación de caída de la sede Arequipa" | ev 03_sede_caida.txt
trap 'docker start olva_mongo_arequipa >/dev/null 2>&1' EXIT     # la sede se vuelve a encender pase lo que pase
docker stop olva_mongo_arequipa >/dev/null
echo "olva_mongo_arequipa DETENIDO" | ev 03_sede_caida.txt
M --eval "db = db.getSiblingDB('olva_sedes');
  const intentar = (texto, fn) => { try { print(texto + ': ' + fn()); }
      catch (e) { print(texto + ': ERROR ' + (e.codeName || '') + ' - ' + e.message.split('::').pop().trim()); } };
  intentar('Consulta dirigida a la sede Lima (nodo LIMA)', () => db.envios.countDocuments({ 'origen.nodo': 'LIMA', estado_actual: 'EN_HUB' }) + ' envíos EN_HUB -> RESPONDE');
  intentar('Consulta dirigida a la sede Arequipa (nodo SUR)', () => db.envios.countDocuments({ 'origen.nodo': 'SUR', estado_actual: 'EN_HUB' }));
  intentar('Consulta global (necesita las dos sedes)', () => db.envios.countDocuments({ estado_actual: 'EN_HUB' }));
  intentar('Alta de un envío en Lima mientras Arequipa está caída', () => {
      db.envios.insertOne({ _id: 'OLV2691000001', origen: { nodo: 'LIMA' }, estado_actual: 'ADMITIDO' });
      db.envios.deleteOne({ _id: 'OLV2691000001', 'origen.nodo': 'LIMA' }); return 'insertado y borrado -> la sede Lima sigue operando'; });" \
  2>&1 | ev 03_sede_caida.txt
docker start olva_mongo_arequipa >/dev/null
until M --eval "quit(db.getSiblingDB('olva_sedes').envios.countDocuments({ estado_actual: 'EN_HUB' }) >= 0 ? 0 : 1)" >/dev/null 2>&1; do sleep 2; done
echo "olva_mongo_arequipa ENCENDIDO de nuevo" | ev 03_sede_caida.txt
M --eval "print('Consulta global después de la recuperación: ' + db.getSiblingDB('olva_sedes').envios.countDocuments({ estado_actual: 'EN_HUB' }) + ' envíos EN_HUB')" | ev 03_sede_caida.txt
echo ">> MongoDB con 2 sedes listo"
