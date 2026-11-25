// =====================================================================
// 10.3  Índices (se crean DESPUÉS de la carga masiva: la carga es más rápida
//       sin índices y luego cada índice se construye una sola vez)
// =====================================================================
load('/scripts/utils.js');
db = db.getSiblingDB('olva_tracking');

titulo('Documentos cargados con mongoimport');
tabla(['envios', 'hubs', 'clientes'].map(c => {
    const s = db.getCollection(c).stats();
    return { coleccion: c, documentos: s.count, tamano_prom_bytes: s.avgObjSize,
             datos_MB: +(s.size / 1048576).toFixed(1) };
}));
const totEventos = db.envios.aggregate([{ $group: { _id: null, n: { $sum: { $size: '$tracking' } } } }]).next().n;
print('Eventos de tracking embebidos en envios: ' + totEventos);

titulo('Creación de índices');
// _id ya es el número de tracking (índice único automático)
db.envios.createIndex({ estado_actual: 1, 'fechas.compromiso': 1 }, { name: 'ix_estado_compromiso' });     // envíos vivos en riesgo
db.envios.createIndex({ 'cliente.id': 1, 'fechas.registro': -1 }, { name: 'ix_cliente_fecha' });          // portal del cliente
db.envios.createIndex({ 'tracking.hub': 1, 'tracking.fecha_hora': 1 }, { name: 'ix_tracking_hub_fecha' }); // multikey sobre el arreglo
db.envios.createIndex({ 'destino.ciudad': 1, 'servicio.modalidad': 1 }, { name: 'ix_destino_modalidad' });
db.envios.createIndex({ 'incidencias.tipo': 1 }, { name: 'ix_incidencia_tipo', sparse: true });            // solo envíos con incidencia
db.envios.createIndex({ 'prueba_entrega.ubicacion': '2dsphere' }, { name: 'ix_pod_geo' });                // geoespacial
db.hubs.createIndex({ ubicacion: '2dsphere' }, { name: 'ix_hub_geo' });
db.clientes.createIndex({ 'documento.numero': 1 }, { name: 'ux_cliente_documento', unique: true });
db.clientes.createIndex({ nombre: 'text' }, { name: 'tx_cliente_nombre', default_language: 'spanish' });  // búsqueda de texto

const filas = [];
['envios', 'hubs', 'clientes'].forEach(c => db.getCollection(c).getIndexes().forEach(i => filas.push({
    coleccion: c, indice: i.name, claves: JSON.stringify(i.key),
    propiedades: [i.unique ? 'unique' : '', i.sparse ? 'sparse' : '', i['2dsphereIndexVersion'] ? '2dsphere' : '']
                 .filter(Boolean).join(' ') })));
tabla(filas);
