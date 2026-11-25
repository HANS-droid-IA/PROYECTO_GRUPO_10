// =====================================================================
// 10.2 / 10.3  Modelo documental: base olva_tracking y sus colecciones
//   envios   : expediente completo del envío (paquetes, tracking, intentos,
//              incidencias, comprobante y prueba de entrega EMBEBIDOS)
//   hubs     : red logística con ubicación GeoJSON (referenciada por código)
//   clientes : datos de contacto (referenciado desde envios.cliente.id)
// Cada colección valida su estructura con $jsonSchema.
// =====================================================================
load('/scripts/utils.js');
db = db.getSiblingDB('olva_tracking');
db.dropDatabase();

titulo('Colección envios con validación $jsonSchema');
db.createCollection('envios', {
    validationLevel: 'strict',
    validationAction: 'error',
    validator: { $jsonSchema: {
        bsonType: 'object',
        required: ['_id', 'servicio', 'cliente', 'origen', 'destino', 'fechas', 'estado_actual', 'monto_total', 'paquetes', 'tracking'],
        properties: {
            _id: { bsonType: 'string', pattern: '^OLV[0-9]{10}$', description: 'número de tracking' },
            servicio: { bsonType: 'object', required: ['codigo', 'modalidad', 'sla_horas'],
                        properties: { modalidad: { enum: ['AEREO', 'TERRESTRE'] } } },
            estado_actual: { enum: ['ADMITIDO', 'EN_TRANSITO', 'EN_HUB', 'EN_REPARTO', 'INTENTO_FALLIDO', 'ENTREGADO', 'DEVUELTO'] },
            fechas: { bsonType: 'object', required: ['registro', 'compromiso'],
                      properties: { registro: { bsonType: 'date' }, compromiso: { bsonType: 'date' }, entrega: { bsonType: 'date' } } },
            peso_total_kg: { bsonType: 'double', minimum: 0 },
            monto_total: { bsonType: ['double', 'int'], minimum: 0 },
            paquetes: { bsonType: 'array', minItems: 1,
                        items: { bsonType: 'object', required: ['bulto', 'peso_kg'] } },
            tracking: { bsonType: 'array',
                        items: { bsonType: 'object', required: ['fecha_hora', 'evento', 'hub'],
                                 properties: { evento: { enum: ['ADMISION', 'SALIDA_HUB', 'LLEGADA_HUB', 'CLASIFICACION',
                                                                 'EN_REPARTO', 'INTENTO_FALLIDO', 'ENTREGA', 'DEVOLUCION'] } } } },
            prueba_entrega: { bsonType: 'object',
                              properties: { ubicacion: { bsonType: 'object', required: ['type', 'coordinates'] } } }
        }
    } }
});

titulo('Colección hubs');
db.createCollection('hubs', { validator: { $jsonSchema: {
    bsonType: 'object', required: ['_id', 'nombre', 'tipo', 'capacidad_hora', 'ubicacion'],
    properties: { tipo: { enum: ['HUB_CENTRAL', 'HUB_REGIONAL', 'AGENCIA'] },
                  capacidad_hora: { bsonType: 'int', minimum: 1 } } } } });

titulo('Colección clientes');
db.createCollection('clientes', { validator: { $jsonSchema: {
    bsonType: 'object', required: ['_id', 'tipo', 'documento', 'nombre'],
    properties: { tipo: { enum: ['EMPRESA', 'PERSONA'] } } } } });

tabla(db.getCollectionInfos().map(c => ({ coleccion: c.name, validacion: c.options.validationLevel || 'strict',
                                          con_jsonSchema: !!c.options.validator })));
