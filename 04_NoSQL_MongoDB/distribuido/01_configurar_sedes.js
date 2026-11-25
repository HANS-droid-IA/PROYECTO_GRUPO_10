// =====================================================================
// MongoDB con 2 sedes: sharding por ZONAS (fragmentación horizontal por región)
//   sede_lima      -> envíos con origen en el nodo LIMA (Lima + Centro)
//   sede_arequipa  -> envíos con origen en provincias (nodos NORTE y SUR)
// Equivale a la fragmentación horizontal HF1 de PostgreSQL (envío por origen),
// pero aquí la hace el propio motor: el router mongos decide a qué sede va
// cada documento según la clave de fragmentación (shard key).
// Se ejecuta en el router mongos como administrador.
// =====================================================================
load('/scripts/utils.js');
const admin = db.getSiblingDB('admin');

titulo('1. Registro de las sedes (shards) en el clúster');
const existentes = admin.runCommand({ listShards: 1 }).shards.map(s => s._id);
// addShard con "name" explícito (el helper sh.addShard() de mongosh no acepta nombre)
if (!existentes.includes('sede_lima'))
    printjson(admin.runCommand({ addShard: 'rs_lima/olva_mongo_lima:27018', name: 'sede_lima' }));
if (!existentes.includes('sede_arequipa'))
    printjson(admin.runCommand({ addShard: 'rs_arequipa/olva_mongo_arequipa:27018', name: 'sede_arequipa' }));
tabla(admin.runCommand({ listShards: 1 }).shards.map(s => ({ sede: s._id, servidor: s.host, estado: s.state === 1 ? 'activo' : s.state })));

titulo('2. Zonas geográficas: cada sede es dueña de una zona');
sh.addShardToZone('sede_lima', 'ZONA_LIMA');
sh.addShardToZone('sede_arequipa', 'ZONA_PROVINCIAS');

titulo('3. Base olva_sedes y colección fragmentada envios');
db = db.getSiblingDB('olva_sedes');
db.dropDatabase();
sh.enableSharding('olva_sedes', 'sede_lima');          // catálogos sin fragmentar viven en Lima
// se quitan rangos de una ejecución anterior (el script se puede repetir)
db.getSiblingDB('config').tags.find({ ns: 'olva_sedes.envios' }).forEach(t =>
    sh.removeRangeFromZone('olva_sedes.envios', t.min, t.max));
// rangos de la clave { origen.nodo, _id } por zona. Cubren TODO el espacio de claves, sin huecos,
// y se definen antes de crear la colección: MongoDB crea los fragmentos iniciales ya en su sede.
//   ZONA_LIMA        : origen.nodo <  'NORTE'   (LIMA)
//   ZONA_PROVINCIAS  : origen.nodo >= 'NORTE'   (NORTE, SUR)
sh.updateZoneKeyRange('olva_sedes.envios', { 'origen.nodo': MinKey, _id: MinKey },
                      { 'origen.nodo': 'NORTE', _id: MinKey }, 'ZONA_LIMA');
sh.updateZoneKeyRange('olva_sedes.envios', { 'origen.nodo': 'NORTE', _id: MinKey },
                      { 'origen.nodo': MaxKey, _id: MaxKey }, 'ZONA_PROVINCIAS');
sh.shardCollection('olva_sedes.envios', { 'origen.nodo': 1, _id: 1 });

const limite = v => (v === MinKey || (v && v._bsontype === 'MinKey')) ? '(inicio)'
                  : (v === MaxKey || (v && v._bsontype === 'MaxKey')) ? '(fin)' : v;
tabla(db.getSiblingDB('config').tags.find({ ns: 'olva_sedes.envios' }).sort({ min: 1 }).toArray()
    .map(t => ({ zona: t.tag, nodo_desde: limite(t.min['origen.nodo']), nodo_hasta_sin_incluir: limite(t.max['origen.nodo']),
                 nodos: t.tag === 'ZONA_LIMA' ? 'LIMA' : 'NORTE, SUR' })));
print('Clave de fragmentación (shard key): { "origen.nodo": 1, "_id": 1 }');

// Vistas por sede (para ver en Compass los envíos de cada sede como una "tabla")
const dbSedes = db.getSiblingDB('olva_sedes');
for (const [vista, filtro] of [['envios_sede_lima', { 'origen.nodo': 'LIMA' }],
                               ['envios_sede_arequipa', { 'origen.nodo': { $in: ['NORTE', 'SUR'] } }]]) {
    if (!dbSedes.getCollectionNames().includes(vista)) dbSedes.createView(vista, 'envios', [{ $match: filtro }]);
}
print('Vistas por sede: envios_sede_lima, envios_sede_arequipa');
