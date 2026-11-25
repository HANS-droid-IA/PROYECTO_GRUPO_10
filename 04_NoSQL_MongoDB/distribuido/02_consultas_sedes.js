// =====================================================================
// MongoDB con 2 sedes: verificación y consultas distribuidas
//   - distribución real de documentos y fragmentos (chunks) por sede
//   - consulta dirigida a UNA sede vs consulta a TODAS las sedes (explain)
//   - agregación global que combina las dos sedes
//   - transacción distribuida entre sedes (commit y abort) y traslado de un
//     documento de una sede a otra al cambiar su clave de fragmentación
// =====================================================================
load('/scripts/utils.js');
db = db.getSiblingDB('olva_sedes');

// ---------------------------------------------------------------------
titulo('D1. Documentos por sede (lo que guarda físicamente cada shard)');
tabla(db.envios.aggregate([{ $collStats: { count: {}, storageStats: {} } }]).toArray()
    .map(s => ({ sede: s.shard, documentos: s.count, datos_MB: +(s.storageStats.size / 1048576).toFixed(1) })));
const total = db.envios.countDocuments();
print('Total en el clúster (vista global a través de mongos): ' + total);

titulo('D2. Envíos por nodo de origen y sede asignada (reconstrucción)');
tabla(db.envios.aggregate([{ $group: { _id: '$origen.nodo', envios: { $sum: 1 } } }, { $sort: { _id: 1 } }]).toArray()
    .map(x => ({ nodo_origen: x._id, sede: SEDE_DE_NODO[x._id], envios: x.envios })));

titulo('D3. Fragmentos (chunks) por sede y zona');
const uuid = db.getSiblingDB('config').collections.findOne({ _id: 'olva_sedes.envios' }).uuid;
tabla(db.getSiblingDB('config').chunks.aggregate([{ $match: { uuid } },
    { $group: { _id: '$shard', chunks: { $sum: 1 } } }, { $sort: { _id: 1 } }]).toArray()
    .map(c => ({ sede: c._id, fragmentos: c.chunks })));

// ---------------------------------------------------------------------
function plan(cursorOExplain) {
    const e = cursorOExplain.explain('executionStats');
    const ganador = e.queryPlanner.winningPlan;
    const sedes = (ganador.shards || []).map(s => s.shardName);
    const porSede = (e.executionStats.executionStages.shards || []).map(s => s.shardName + '=' + s.nReturned).join(', ');
    return { etapa: ganador.stage, sedes_consultadas: sedes.join(', '), devueltos_por_sede: porSede,
             total: e.executionStats.nReturned };
}

titulo('Q1. Consulta CON la clave de fragmentación -> va a UNA sola sede');
print("db.envios.find({ 'origen.nodo': 'SUR', estado_actual: 'EN_HUB' })");
tabla([plan(db.envios.find({ 'origen.nodo': 'SUR', estado_actual: 'EN_HUB' }))]);

titulo('Q2. Consulta SIN la clave de fragmentación -> mongos pregunta a TODAS las sedes');
print("db.envios.find({ estado_actual: 'EN_HUB' })");
tabla([plan(db.envios.find({ estado_actual: 'EN_HUB' }))]);

titulo('Q3. Búsqueda por tracking: sin nodo (todas las sedes) vs con nodo (una sede)');
const ej = db.envios.findOne({ 'origen.nodo': 'NORTE' }, { _id: 1 })._id;
tabla([{ consulta: `{ _id: '${ej}' }`, ...plan(db.envios.find({ _id: ej })) },
       { consulta: `{ 'origen.nodo': 'NORTE', _id: '${ej}' }`, ...plan(db.envios.find({ 'origen.nodo': 'NORTE', _id: ej })) }]);

// ---------------------------------------------------------------------
titulo('Q4. Agregación global: SLA por sede (cada sede calcula su parte y mongos combina)');
tabla(db.envios.aggregate([
    { $match: { 'fechas.entrega': { $exists: true } } },
    { $group: { _id: '$origen.nodo', entregados: { $sum: 1 },
                a_tiempo: { $sum: { $cond: [{ $lte: ['$fechas.entrega', '$fechas.compromiso'] }, 1, 0] } },
                ingresos: { $sum: '$monto_total' } } },
    { $sort: { _id: 1 } }
]).toArray().map(x => ({ nodo_origen: x._id, sede: SEDE_DE_NODO[x._id], entregados: x.entregados,
                         pct_sla: +(100 * x.a_tiempo / x.entregados).toFixed(1), ingresos_S: x.ingresos })));
const ex = db.envios.explain().aggregate([{ $group: { _id: '$origen.nodo', n: { $sum: 1 } } }]);
print('Plan: ' + (ex.splitPipeline ? 'pipeline dividido -> shardsPart en ' + Object.keys(ex.shards).join(' y ')
      + ', mergerPart en ' + ex.mergeType : JSON.stringify(Object.keys(ex))));

// ---------------------------------------------------------------------
titulo('T1. Transacción distribuida: un envío en cada sede, confirmada (COMMIT)');
const nuevo = (id, nodo, ciudad) => ({ _id: id, origen: { nodo, ciudad }, estado_actual: 'ADMITIDO', monto_total: 20,
                                       fechas: { registro: new Date() }, tracking: [] });
let s = db.getMongo().startSession();
let e = s.getDatabase('olva_sedes').envios;
s.startTransaction({ readConcern: { level: 'snapshot' }, writeConcern: { w: 'majority' } });
e.insertOne(nuevo('OLV2690000001', 'LIMA', 'Lima'));
e.insertOne(nuevo('OLV2690000002', 'SUR', 'Arequipa'));
s.commitTransaction(); s.endSession();
tabla(db.envios.find({ _id: { $in: ['OLV2690000001', 'OLV2690000002'] } }, { 'origen.nodo': 1 }).toArray()
    .map(d => ({ tracking: d._id, nodo: d.origen.nodo, sede: SEDE_DE_NODO[d.origen.nodo] })));

titulo('T2. Transacción distribuida cancelada (ABORT): no queda nada en ninguna sede');
s = db.getMongo().startSession(); e = s.getDatabase('olva_sedes').envios;
s.startTransaction();
e.insertOne(nuevo('OLV2690000003', 'LIMA', 'Lima'));
e.insertOne(nuevo('OLV2690000004', 'NORTE', 'Trujillo'));
print('Dentro de la transacción se ven: ' + e.countDocuments({ _id: /^OLV26900000(03|04)$/ }));
s.abortTransaction(); s.endSession();
print('Después del ABORT existen: ' + db.envios.countDocuments({ _id: /^OLV26900000(03|04)$/ }));

titulo('T3. Traslado entre sedes: cambiar la clave de fragmentación mueve el documento de shard');
s = db.getMongo().startSession(); e = s.getDatabase('olva_sedes').envios;
s.startTransaction();
e.updateOne({ _id: 'OLV2690000001', 'origen.nodo': 'LIMA' }, { $set: { 'origen.nodo': 'SUR', 'origen.ciudad': 'Arequipa' } });
s.commitTransaction(); s.endSession();
tabla([{ tracking: 'OLV2690000001', ...plan(db.envios.find({ 'origen.nodo': 'SUR', _id: 'OLV2690000001' })) }]);

print('\nLimpieza de los documentos de prueba: ' +
      db.envios.deleteMany({ _id: /^OLV2690/ }).deletedCount + ' eliminados');
