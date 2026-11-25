// =====================================================================
// 10.5  Pruebas de seguridad: se ejecuta conectado como cada usuario.
// Imprime qué operaciones se permiten y cuáles se rechazan.
// =====================================================================
db = db.getSiblingDB('olva_tracking');
const yo = db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers[0].user;
print('\n=== Conectado como ' + yo + ' ===');

function intentar(desc, fn) {
    try {
        const r = fn();
        print('  PERMITIDO  ' + desc + (r !== undefined ? '  -> ' + r : ''));
    } catch (e) {
        print('  DENEGADO   ' + desc + '  -> ' + (e.codeName || e.message));
    }
}

intentar('leer vista vw_tracking_publico', () => JSON.stringify(db.vw_tracking_publico.findOne({ _id: 'OLV2600000001' }, { estado_actual: 1, destino: 1 })));
intentar('leer colección envios', () => db.envios.findOne({}, { _id: 1 })._id);
intentar('leer vista vw_envios_analitica', () => db.vw_envios_analitica.countDocuments({ estado_actual: 'ENTREGADO' }) + ' entregados');
intentar('ver datos personales en la vista analítica', () => {
    const d = db.vw_envios_analitica.findOne({}, { destinatario: 1, 'cliente.nombre': 1 });
    if (!d) throw new Error('sin acceso');
    return d.destinatario ? 'VISIBLE' : 'campos ocultos por la vista';
});
intentar('actualizar estado de un envío', () => db.envios.updateOne({ _id: 'OLV2600000001' }, { $set: { estado_actual: 'ENTREGADO' } }).matchedCount + ' doc');
intentar('insertar un envío', () => db.envios.insertOne({ _id: 'OLV2600000000' }).insertedId);
intentar('borrar envíos', () => db.envios.deleteMany({}).deletedCount);
intentar('leer clientes (datos personales)', () => db.clientes.findOne({}, { nombre: 1 }).nombre);
intentar('eliminar la colección envios', () => db.envios.drop());
