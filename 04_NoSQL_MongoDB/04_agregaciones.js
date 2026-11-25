// =====================================================================
// 10.4 / 10.6  Pipelines de agregación (responden las preguntas de negocio)
// =====================================================================
load('/scripts/utils.js');
db = db.getSiblingDB('olva_tracking');
const TZ = 'America/Lima';

// ---------------------------------------------------------------------
titulo('A1. Cumplimiento de SLA por servicio ($match, $group, $cond, $project)');
tabla(db.envios.aggregate([
    { $match: { 'fechas.entrega': { $exists: true } } },
    { $group: { _id: '$servicio.nombre',
                entregados: { $sum: 1 },
                a_tiempo: { $sum: { $cond: [{ $lte: ['$fechas.entrega', '$fechas.compromiso'] }, 1, 0] } },
                horas_prom: { $avg: { $dateDiff: { startDate: '$fechas.registro', endDate: '$fechas.entrega', unit: 'minute' } } } } },
    { $project: { _id: 0, servicio: '$_id', entregados: 1,
                  pct_sla: { $round: [{ $multiply: [{ $divide: ['$a_tiempo', '$entregados'] }, 100] }, 1] },
                  horas_promedio: { $round: [{ $divide: ['$horas_prom', 60] }, 1] } } },
    { $sort: { pct_sla: 1 } }
]).toArray());

// ---------------------------------------------------------------------
titulo('A2. Cuello de botella: permanencia en el Hub Central por hora de llegada ($unwind, $setWindowFields, $dateDiff)');
tabla(db.envios.aggregate([
    { $match: { 'tracking.hub': 'HC-LIM' } },
    { $unwind: '$tracking' },
    // solo llegadas y salidas del Hub Central (entre ellas hay un escaneo de CLASIFICACION)
    { $match: { 'tracking.hub': 'HC-LIM', 'tracking.evento': { $in: ['LLEGADA_HUB', 'SALIDA_HUB'] } } },
    { $setWindowFields: { partitionBy: '$_id', sortBy: { 'tracking.fecha_hora': 1 },
                          output: { siguiente: { $shift: { output: '$tracking', by: 1 } } } } },
    { $match: { 'tracking.hub': 'HC-LIM', 'tracking.evento': 'LLEGADA_HUB', 'siguiente.evento': 'SALIDA_HUB' } },
    { $project: { hora: { $hour: { date: '$tracking.fecha_hora', timezone: TZ } },
                  horas: { $divide: [{ $dateDiff: { startDate: '$tracking.fecha_hora', endDate: '$siguiente.fecha_hora', unit: 'minute' } }, 60] } } },
    { $group: { _id: '$hora', envios: { $sum: 1 }, permanencia_prom_h: { $avg: '$horas' }, max_h: { $max: '$horas' },
                mas_de_12h: { $sum: { $cond: [{ $gt: ['$horas', 12] }, 1, 0] } } } },
    { $project: { _id: 0, hora_llegada: '$_id', envios: 1, permanencia_prom_h: { $round: ['$permanencia_prom_h', 1] },
                  max_h: { $round: ['$max_h', 1] }, mas_de_12h: 1 } },
    { $sort: { hora_llegada: 1 } }
], { allowDiskUse: true }).toArray().map(x => ({ hora_llegada: x.hora_llegada, envios: x.envios, permanencia_prom_h: x.permanencia_prom_h,
                                                  max_h: x.max_h, mas_de_12h: x.mas_de_12h })));

// ---------------------------------------------------------------------
titulo('A3. Efectividad del primer intento de entrega por ciudad y motivos de falla ($unwind, $push, $slice)');
tabla(db.envios.aggregate([
    { $match: { 'intentos_entrega.0': { $exists: true } } },
    { $project: { ciudad: '$destino.ciudad', primero: { $first: '$intentos_entrega' } } },
    { $group: { _id: { ciudad: '$ciudad', resultado: '$primero.resultado' }, n: { $sum: 1 } } },
    { $sort: { n: -1 } },
    { $group: { _id: '$_id.ciudad', total: { $sum: '$n' },
                exito: { $sum: { $cond: [{ $eq: ['$_id.resultado', 'ENTREGADO'] }, '$n', 0] } },
                fallas: { $push: { $cond: [{ $ne: ['$_id.resultado', 'ENTREGADO'] }, { $concat: ['$_id.resultado', ':', { $toString: '$n' }] }, '$$REMOVE'] } } } },
    { $project: { _id: 0, ciudad: '$_id', primeros_intentos: '$total',
                  pct_exito: { $round: [{ $multiply: [{ $divide: ['$exito', '$total'] }, 100] }, 1] },
                  motivos_falla: { $slice: ['$fallas', 3] } } },
    { $sort: { pct_exito: 1 } },
    { $limit: 10 }
]).toArray());

// ---------------------------------------------------------------------
titulo('A4. Ocupación del Hub Central vs su capacidad por hora del día ($lookup a hubs)');
tabla(db.envios.aggregate([
    { $unwind: '$tracking' },
    { $match: { 'tracking.hub': 'HC-LIM', 'tracking.evento': 'LLEGADA_HUB' } },
    { $group: { _id: { dia: { $dateToString: { format: '%Y-%m-%d', date: '$tracking.fecha_hora', timezone: TZ } },
                       hora: { $hour: { date: '$tracking.fecha_hora', timezone: TZ } } },
                llegadas: { $sum: 1 } } },
    { $group: { _id: '$_id.hora', llegadas_prom: { $avg: '$llegadas' }, pico: { $max: '$llegadas' } } },
    { $lookup: { from: 'hubs', pipeline: [{ $match: { _id: 'HC-LIM' } }, { $project: { capacidad_hora: 1 } }], as: 'hub' } },
    { $project: { _id: 0, hora: '$_id', llegadas_prom: { $round: ['$llegadas_prom', 1] }, pico: 1,
                  capacidad: { $first: '$hub.capacidad_hora' },
                  ocupacion_pct: { $round: [{ $multiply: [{ $divide: ['$llegadas_prom', { $first: '$hub.capacidad_hora' }] }, 100] }, 0] } } },
    { $match: { llegadas_prom: { $gte: 5 } } },
    { $sort: { hora: 1 } }
], { allowDiskUse: true }).toArray().map(x => ({ hora: x.hora, llegadas_prom: x.llegadas_prom, pico: x.pico, capacidad: x.capacidad, ocupacion_pct: x.ocupacion_pct })));

// ---------------------------------------------------------------------
titulo('A5. Top 10 clientes empresariales por facturación con su contacto ($lookup a clientes)');
tabla(db.envios.aggregate([
    { $match: { 'cliente.tipo': 'EMPRESA' } },
    { $group: { _id: '$cliente.id', envios: { $sum: 1 }, facturado: { $sum: '$monto_total' },
                con_incidencia: { $sum: { $cond: [{ $gt: [{ $size: { $ifNull: ['$incidencias', []] } }, 0] }, 1, 0] } } } },
    { $sort: { facturado: -1 } },
    { $limit: 10 },
    { $lookup: { from: 'clientes', localField: '_id', foreignField: '_id', as: 'c' } },
    { $unwind: '$c' },
    { $project: { _id: 0, cliente: '$c.nombre', email: '$c.contacto.email', envios: 1,
                  facturado_S: { $round: ['$facturado', 2] }, con_incidencia: 1 } }
]).toArray().map(x => ({ cliente: x.cliente, email: x.email, envios: x.envios, facturado_S: x.facturado_S, con_incidencia: x.con_incidencia })));

// ---------------------------------------------------------------------
titulo('A6. Tablero operativo en una sola consulta ($facet, $bucket, $sortByCount)');
const tablero = db.envios.aggregate([
    { $facet: {
        por_estado: [{ $sortByCount: '$estado_actual' }],
        por_modalidad: [{ $group: { _id: '$servicio.modalidad', envios: { $sum: 1 }, ingresos: { $sum: '$monto_total' } } }],
        por_peso: [{ $bucket: { groupBy: '$peso_total_kg', boundaries: [0, 1, 5, 10, 30, 1000], default: 'otros',
                                output: { envios: { $sum: 1 }, tarifa_prom: { $avg: '$monto_total' } } } }],
        incidencias: [{ $unwind: '$incidencias' }, { $sortByCount: '$incidencias.tipo' }]
    } }
]).next();
print('-- Envíos por estado');   tabla(tablero.por_estado.map(x => ({ estado: x._id, envios: x.count })));
print('-- Por modalidad');       tabla(tablero.por_modalidad.map(x => ({ modalidad: x._id, envios: x.envios, ingresos_S: x.ingresos })));
print('-- Por rango de peso');   tabla(tablero.por_peso.map(x => ({ desde_kg: x._id, envios: x.envios, tarifa_prom_S: x.tarifa_prom })));
print('-- Incidencias por tipo'); tabla(tablero.incidencias.map(x => ({ tipo: x._id, casos: x.count })));
