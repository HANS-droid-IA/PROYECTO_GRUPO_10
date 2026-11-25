#!/bin/bash
# =====================================================================
# MongoDB - Olva Courier: crea la base olva_tracking, carga los documentos,
# crea índices, ejecuta CRUD, agregaciones y seguridad, y guarda evidencias.
# Uso (desde la raíz del proyecto, con el contenedor encendido):
#   python 04_NoSQL_MongoDB/generar_documentos.py
#   docker exec -e MONGO_APP_PASSWORD=<CONTRASEÑA_CONFIGURADA> olva_mongo bash /scripts/00_ejecutar_todo.sh
# Las credenciales del administrador vienen del propio contenedor
# (MONGO_INITDB_ROOT_USERNAME / MONGO_INITDB_ROOT_PASSWORD).
# =====================================================================
set -e
cd /scripts
mkdir -p evidencias
ADMIN=(--quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin)

echo ">> 01 Colecciones con validación"
mongosh "${ADMIN[@]}" --file 01_crear_colecciones.js | tee evidencias/01_colecciones.txt

echo ">> Carga masiva con mongoimport"
{
for c in hubs clientes envios; do
    inicio=$(date +%s.%N)
    mongoimport -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin \
        --db olva_tracking --collection "$c" --file "datos/$c.json" --numInsertionWorkers 4 --quiet
    fin=$(date +%s.%N)
    printf "mongoimport %-9s %6s documentos  %5.1f s\n" "$c" "$(wc -l < datos/$c.json)" "$(awk "BEGIN{print $fin - $inicio}")"
done
} | tee evidencias/02_carga_masiva.txt

echo ">> 02 Índices"
mongosh "${ADMIN[@]}" --file 02_indices.js | tee -a evidencias/02_carga_masiva.txt

echo ">> 03 Operaciones CRUD"
mongosh "${ADMIN[@]}" --file 03_operaciones_crud.js | tee evidencias/03_operaciones_crud.txt

echo ">> 04 Agregaciones"
mongosh "${ADMIN[@]}" --file 04_agregaciones.js | tee evidencias/04_agregaciones.txt

echo ">> 05 Seguridad"
mongosh "${ADMIN[@]}" --file 05_seguridad.js | tee evidencias/05_seguridad.txt
for u in u_tracking_web u_operador_mongo u_analista_mongo; do
    mongosh --quiet -u "$u" -p "$MONGO_APP_PASSWORD" --authenticationDatabase olva_tracking --file 06_pruebas_seguridad.js
done | tee -a evidencias/05_seguridad.txt
echo "--- conexión con contraseña incorrecta"
mongosh --quiet -u u_analista_mongo -p incorrecta --authenticationDatabase olva_tracking --eval 'db.runCommand({ping:1})' 2>&1 \
    | head -1 | tee -a evidencias/05_seguridad.txt || true
echo ">> MongoDB listo"
