// =====================================================================
// 10.5  Administración de usuarios, roles y seguridad en MongoDB
//   - Autenticación SCRAM-SHA-256 (el contenedor arranca con usuario root)
//   - Vistas que ocultan datos personales (MongoDB no tiene permisos por campo:
//     se concede acceso a la VISTA y no a la colección)
//   - Roles personalizados con privilegios mínimos + usuarios que los heredan
// La contraseña de los usuarios de la aplicación se recibe por variable de
// entorno (MONGO_APP_PASSWORD); no se escribe en el script.
// =====================================================================
load('/scripts/utils.js');
const clave = process.env.MONGO_APP_PASSWORD;
if (!clave) { print('Falta la variable MONGO_APP_PASSWORD'); quit(1); }
db = db.getSiblingDB('olva_tracking');

titulo('Vistas de solo lectura');
['vw_tracking_publico', 'vw_envios_analitica'].forEach(v => db.getCollection(v).drop());
db.createView('vw_tracking_publico', 'envios', [
    { $project: { _id: 1, estado_actual: 1, servicio: '$servicio.nombre', origen: '$origen.ciudad', destino: '$destino.ciudad',
                  registro: '$fechas.registro', compromiso: '$fechas.compromiso', entrega: '$fechas.entrega',
                  ultimo_evento: { $last: '$tracking' } } }]);
db.createView('vw_envios_analitica', 'envios', [
    { $project: { destinatario: 0, 'cliente.documento': 0, 'cliente.nombre': 0, prueba_entrega: 0, 'intentos_entrega.receptor': 0,
                  'intentos_entrega.courier': 0 } }]);
print('Creadas: vw_tracking_publico, vw_envios_analitica');

titulo('Roles personalizados');
['rol_tracking_web', 'rol_operador_hub', 'rol_analista'].forEach(r => { if (db.getRole(r)) db.dropRole(r); });
db.createRole({ role: 'rol_tracking_web', roles: [],
    privileges: [{ resource: { db: 'olva_tracking', collection: 'vw_tracking_publico' }, actions: ['find'] }] });
db.createRole({ role: 'rol_operador_hub', roles: [],
    privileges: [{ resource: { db: 'olva_tracking', collection: 'envios' }, actions: ['find', 'update'] },
                 { resource: { db: 'olva_tracking', collection: 'hubs' }, actions: ['find'] }] });
db.createRole({ role: 'rol_analista', roles: [],
    privileges: [{ resource: { db: 'olva_tracking', collection: 'vw_envios_analitica' }, actions: ['find'] },
                 { resource: { db: 'olva_tracking', collection: 'hubs' }, actions: ['find'] }] });

titulo('Usuarios');
['u_tracking_web', 'u_operador_mongo', 'u_analista_mongo'].forEach(u => { if (db.getUser(u)) db.dropUser(u); });
db.createUser({ user: 'u_tracking_web', pwd: clave, roles: ['rol_tracking_web'], mechanisms: ['SCRAM-SHA-256'] });
db.createUser({ user: 'u_operador_mongo', pwd: clave, roles: ['rol_operador_hub'], mechanisms: ['SCRAM-SHA-256'] });
db.createUser({ user: 'u_analista_mongo', pwd: clave, roles: ['rol_analista'], mechanisms: ['SCRAM-SHA-256'],
                customData: { area: 'Planeamiento', vigencia: '2026-12-31' } });

tabla(db.getUsers().users.map(u => ({ usuario: u.user, base: u.db, roles: u.roles.map(r => r.role), mecanismo: u.mechanisms })));
const rs = db.getRoles({ showPrivileges: true });
tabla((Array.isArray(rs) ? rs : rs.roles).map(r => ({ rol: r.role,
    privilegios: r.privileges.map(p => p.resource.collection + ':' + p.actions.join('/')) })));
