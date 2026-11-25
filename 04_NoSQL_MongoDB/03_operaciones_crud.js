// =====================================================================
// 10.4  Operaciones CRUD avanzadas e inserción masiva
//   Las operaciones de escritura usan un envío de prueba y se revierten al final:
//   la colección queda igual que después de la carga.
// =====================================================================
load('/scripts/utils.js');
db = db.getSiblingDB('olva_tracking');

// ---------------------------------------------------------------------
titulo('R1. Consulta de tracking: un solo documento trae todo el expediente (sin JOIN)');
const e = db.envios.findOne({ _id: 'OLV2600000001' },
    { estado_actual: 1, 'servicio.nombre': 1, 'origen.ciudad': 1, 'destino.ciudad': 1, tracking: 1, prueba_entrega: 1 });
print('Envío ' + e._id + ' | ' + e.servicio.nombre + ' | ' + e.origen.ciudad + ' -> ' + e.destino.ciudad + ' | estado ' + e.estado_actual);
tabla(e.tracking.map(t => ({ fecha_hora_utc: t.fecha_hora, evento: t.evento, hub: t.hub, ciudad: t.ciudad })));
print('Prueba de entrega: ' + valor(e.prueba_entrega.receptor) + ' en ' + valor(e.prueba_entrega.ubicacion.coordinates));

// ---------------------------------------------------------------------
titulo('R2. Envíos vivos con compromiso vencido al corte (usa ix_estado_compromiso)');
const filtroRiesgo = { estado_actual: { $nin: ['ENTREGADO', 'DEVUELTO'] }, 'fechas.compromiso': { $lt: CORTE } };
tabla(db.envios.find(filtroRiesgo, { estado_actual: 1, 'servicio.codigo': 1, 'destino.ciudad': 1, 'fechas.compromiso': 1 })
    .sort({ 'fechas.compromiso': 1 }).limit(10).toArray()
    .map(d => ({ tracking: d._id, estado: d.estado_actual, servicio: d.servicio.codigo, destino: d.destino.ciudad,
                 compromiso: d.fechas.compromiso })));
print('Total vencidos: ' + db.envios.countDocuments(filtroRiesgo));
const plan = db.envios.find(filtroRiesgo).explain('executionStats');
const etapa = JSON.stringify(plan.queryPlanner.winningPlan).match(/"stage":"(IXSCAN|COLLSCAN)"/)[1];
print('Plan de ejecución: ' + etapa + ' | documentos examinados: ' + plan.executionStats.totalDocsExamined +
      ' | devueltos: ' + plan.executionStats.nReturned);

// ---------------------------------------------------------------------
titulo('R3. Consulta sobre arreglo embebido: envíos con incidencia de PERDIDA o DANO aún abierta ($elemMatch)');
tabla(db.envios.find({ incidencias: { $elemMatch: { tipo: { $in: ['PERDIDA', 'DANO'] }, estado: { $ne: 'CERRADA' } } } },
                     { 'incidencias.$': 1, 'cliente.nombre': 1 }).limit(8).toArray()
    .map(d => ({ tracking: d._id, cliente: d.cliente.nombre, incidencia: d.incidencias[0].tipo,
                 estado: d.incidencias[0].estado, reportada: d.incidencias[0].fecha_reporte })));

// ---------------------------------------------------------------------
titulo('R4. Consulta geoespacial: entregas a menos de 2 km del Hub Regional Arequipa ($geoNear / $geoWithin)');
const hubAqp = db.hubs.findOne({ _id: 'HR-AQP' });
tabla(db.envios.aggregate([
    { $geoNear: { near: hubAqp.ubicacion, key: 'prueba_entrega.ubicacion', distanceField: 'metros', maxDistance: 2000, spherical: true } },
    { $limit: 5 }]).toArray()
    .map(d => ({ tracking: d._id, agencia: d.destino.hub, receptor: d.prueba_entrega.receptor.nombre,
                 lon_lat: d.prueba_entrega.ubicacion.coordinates.map(c => c.toFixed(5)).join(', '), distancia_m: Math.round(d.metros) })));
print('Entregas dentro del radio: ' + db.envios.countDocuments({ 'prueba_entrega.ubicacion':
      { $geoWithin: { $centerSphere: [hubAqp.ubicacion.coordinates, 2 / 6378.1] } } }));

// ---------------------------------------------------------------------
titulo('R5. Búsqueda de texto en clientes ($text)');
tabla(db.clientes.find({ $text: { $search: 'agroexportadora andes' } }, { score: { $meta: 'textScore' }, nombre: 1, 'contacto.email': 1 })
    .sort({ score: { $meta: 'textScore' } }).limit(5).toArray()
    .map(c => ({ id: c._id, nombre: c.nombre, email: c.contacto.email, relevancia: c.score })));

// ---------------------------------------------------------------------
titulo('C1. insertOne: registro de un envío nuevo desde la web');
const ahora = new Date();
const nuevo = {
    _id: 'OLV2699999999', id_envio: 999999,
    servicio: { codigo: 'EXPRESS_AEREO', nombre: 'Express Aéreo', modalidad: 'AEREO', sla_horas: 48 },
    cliente: { id: 1, tipo: 'EMPRESA', nombre: 'Cliente de prueba' },
    destinatario: { nombre: 'Rosa Quispe', telefono: '987000111', direccion: 'Av. Ejército 710, Yanahuara' },
    origen: { hub: 'AG-LIM-MIR', ciudad: 'Lima', nodo: 'LIMA' },
    destino: { hub: 'AG-AQP-01', ciudad: 'Arequipa', nodo: 'SUR' },
    fechas: { registro: ahora, compromiso: new Date(ahora.getTime() + 48 * 3600e3) },
    estado_actual: 'ADMITIDO', peso_total_kg: 1.5, monto_total: 28.0,
    paquetes: [{ bulto: 1, peso_kg: 1.5, descripcion: 'Documentos' }],
    tracking: [{ fecha_hora: ahora, evento: 'ADMISION', hub: 'AG-LIM-MIR', ciudad: 'Lima' }]
};
printjson(db.envios.insertOne(nuevo));

titulo('C2. Validación $jsonSchema: se rechaza un documento con estado inválido');
try {
    db.envios.insertOne({ ...nuevo, _id: 'OLV2699999998', estado_actual: 'PERDIDO_EN_EL_ESPACIO' });
} catch (err) { print('Rechazado: ' + err.errorResponse.errmsg); }

titulo('U1. updateOne con $push + $set: un escaneo agrega un evento y cambia el estado en una sola operación atómica');
printjson(db.envios.updateOne({ _id: 'OLV2699999999' }, {
    $push: { tracking: { fecha_hora: new Date(ahora.getTime() + 3600e3), evento: 'SALIDA_HUB', hub: 'AG-LIM-MIR', ciudad: 'Lima' } },
    $set: { estado_actual: 'EN_TRANSITO' }, $inc: { escaneos: 1 } }));
const act = db.envios.findOne({ _id: 'OLV2699999999' }, { estado_actual: 1, tracking: 1 });
print('Estado: ' + act.estado_actual + ' | eventos: ' + act.tracking.map(t => t.evento).join(' -> '));

titulo('U2. updateMany: marca con alerta todos los envíos vivos vencidos');
printjson(db.envios.updateMany(filtroRiesgo, { $set: { alerta_sla: 'VENCIDO' } }));

titulo('U3. Actualización con arrayFilters: marca solo las incidencias de RETRASO no cerradas dentro de cada arreglo');
const abiertas = db.envios.countDocuments({ incidencias: { $elemMatch: { tipo: 'RETRASO', estado: { $ne: 'CERRADA' } } } });
print('Envíos con incidencia de retraso no cerrada: ' + abiertas);
printjson(db.envios.updateMany({ incidencias: { $elemMatch: { tipo: 'RETRASO', estado: { $ne: 'CERRADA' } } } },
    { $set: { 'incidencias.$[i].escalada_a': 'SUPERVISOR' } },
    { arrayFilters: [{ 'i.tipo': 'RETRASO', 'i.estado': { $ne: 'CERRADA' } }] }));

titulo('B1. Inserción masiva con insertMany (5000 envíos sintéticos en una colección de prueba)');
db.envios_carga_prueba.drop();
const lote = [];
for (let i = 0; i < 5000; i++) {
    lote.push({ _id: 'OLV27' + String(i).padStart(8, '0'), estado_actual: 'ADMITIDO', peso_total_kg: 0.5 + (i % 30),
                origen: { hub: 'AG-LIM-MIR' }, destino: { hub: i % 2 ? 'AG-AQP-01' : 'AG-TRU-01' },
                fechas: { registro: new Date(ahora.getTime() + i * 1000) } });
}
let t0 = Date.now();
const r = db.envios_carga_prueba.insertMany(lote, { ordered: false });
print('Insertados: ' + Object.keys(r.insertedIds).length + ' documentos en ' + (Date.now() - t0) + ' ms');

titulo('B2. bulkWrite: operaciones mixtas en un solo viaje al servidor');
printjson(db.envios_carga_prueba.bulkWrite([
    { updateMany: { filter: { 'destino.hub': 'AG-AQP-01' }, update: { $set: { estado_actual: 'EN_TRANSITO' } } } },
    { deleteMany: { filter: { peso_total_kg: { $gt: 25 } } } },
    { insertOne: { document: { _id: 'OLV2799999999', estado_actual: 'ADMITIDO' } } }
], { ordered: true }));
print('Quedan en la colección de prueba: ' + db.envios_carga_prueba.countDocuments());

// ---------------------------------------------------------------------
titulo('D1. Limpieza: se revierten los cambios de prueba (deleteOne, $unset, drop)');
printjson(db.envios.deleteOne({ _id: 'OLV2699999999' }));
printjson(db.envios.updateMany({ alerta_sla: { $exists: true } }, { $unset: { alerta_sla: '' } }));
printjson(db.envios.updateMany({ 'incidencias.escalada_a': { $exists: true } }, { $unset: { 'incidencias.$[].escalada_a': '' } }));
db.envios_carga_prueba.drop();
print('Documentos en envios: ' + db.envios.countDocuments());
