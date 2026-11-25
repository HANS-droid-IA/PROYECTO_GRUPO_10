# Contenido de los puntos 10 y 11 (lo ejecuta agregar_puntos_10_11.py).
# Marcado en línea: **negrita** y `código`. Todas las cifras provienen de ejecuciones reales.

FUENTE_COMPASS = 'elaboración propia a partir de MongoDB Compass sobre la base olva_tracking.'
FUENTE_MONGOSH = 'elaboración propia a partir de la ejecución en mongosh.'
FUENTE_MONGOS = 'elaboración propia a partir de la ejecución en mongosh conectado al enrutador mongos.'
FUENTE_CQLSH = 'elaboración propia a partir de la ejecución en cqlsh sobre el keyspace olva_tracking.'
FUENTE_NODETOOL = 'elaboración propia a partir de la ejecución de nodetool y cqlsh en ambas sedes.'

# =====================================================================
H1('10. SOLUCIÓN NOSQL – MONGODB')
TXT('PostgreSQL y Oracle conservan el núcleo transaccional del negocio (clientes, tarifas, despachos y facturación), donde la '
    'consistencia ACID y las claves foráneas son indispensables. Sin embargo, dos tipos de información del proyecto no encajan '
    'bien en tablas rígidas: el **expediente completo de cada envío**, que cambia de forma de un envío a otro, y la **bitácora '
    'masiva de escaneos**, que crece sin parar. Para el primero se incorporó MongoDB (punto 10) y para el segundo Apache '
    'Cassandra (punto 11). Ambos motores trabajan con los mismos 29 966 envíos y 315 101 eventos usados en PostgreSQL, de modo '
    'que los resultados son comparables.')

H2('10.1 Justificación técnica de uso')
TXT('En el modelo relacional, mostrar el seguimiento de un envío obliga a reunir seis tablas (envio, paquete, evento_tracking, '
    'intento_entrega, incidencia y comprobante) mediante JOIN. Además, los atributos de cada envío son variables: un envío '
    'puede tener uno o tres intentos de entrega, cero o varias incidencias, y solo los envíos entregados tienen prueba de '
    'entrega con receptor, firma, foto y coordenadas GPS. En PostgreSQL esto se resuelve con tablas hijas y columnas que '
    'quedan vacías; en MongoDB cada envío es **un solo documento JSON/BSON** que guarda todo su expediente y que se lee en una '
    'sola operación.')
VIN('**Lectura del expediente sin JOIN:** el tracking de un envío (Figura 14) se obtiene leyendo un documento por su clave '
    '`_id`, en lugar de combinar seis tablas.',
    '**Esquema flexible pero controlado:** cada documento tiene solo los campos que le corresponden (por ejemplo, '
    '`prueba_entrega` solo existe si el envío se entregó), y una regla `$jsonSchema` impide guardar documentos mal formados.',
    '**Arreglos y subdocumentos nativos:** los escaneos, paquetes e intentos se guardan como arreglos dentro del envío y se '
    'actualizan de forma atómica con `$push` y `$set`.',
    '**Consultas geoespaciales y de texto:** la ubicación GPS de la entrega se indexa con `2dsphere` y el nombre del cliente '
    'con un índice de texto.',
    '**Distribución por sedes integrada en el motor:** MongoDB reparte los documentos entre sedes (sharding por zonas) con '
    'transacciones distribuidas nativas, sin la configuración manual de tablas foráneas y 2PC que exigió PostgreSQL en el punto 9.')
TXT('**¿Por qué no basta con PostgreSQL y Oracle?** PostgreSQL ofrece el tipo JSONB, pero el expediente seguiría dependiendo '
    'de tablas relacionales para sus relaciones y de una distribución diseñada a mano (fragmentos, postgres_fdw y 2PC). En '
    'Oracle, el particionamiento y la distribución entre sedes forman parte de opciones de licencia adicionales, y la edición '
    'Free usada en el laboratorio está limitada en almacenamiento y recursos. Cargar en estos motores el volumen de documentos '
    'variables y de escaneos encarecería la solución y saturaría sus recursos transaccionales. Por eso la arquitectura asigna '
    'a cada motor el dato que mejor maneja:')
VIN('**PostgreSQL:** núcleo transaccional con integridad referencial (clientes, tarifas, rutas, despachos, comprobantes), '
    'funciones, procedimientos, seguridad RLS y la base distribuida de tres nodos.',
    '**Oracle:** implementación parcial y comparativa del modelo relacional (PL/SQL, PROFILE, Data Pump).',
    '**MongoDB:** expediente documental de cada envío para consultas de seguimiento, atención al cliente y análisis, '
    'repartido entre las sedes Lima y Arequipa.',
    '**Apache Cassandra:** bitácora masiva de escaneos (serie de tiempo) y estados en línea, replicada en ambas sedes para '
    'seguir operando aunque una de ellas falle.')

H2('10.2 Modelo de datos documental')
TXT('La base `olva_tracking` tiene tres colecciones. La colección principal, `envios`, aplica el patrón de **incrustación** '
    '(embedding): todo lo que pertenece a un envío y se consulta junto se guarda dentro del mismo documento. Los datos '
    'compartidos por muchos envíos se **referencian**: los hubs y los clientes viven en sus propias colecciones y se unen con '
    '`$lookup` solo cuando se necesitan.')
VIN('**envios** (29 966 documentos, 2,6 kB en promedio): `_id` = número de tracking; subdocumentos `servicio`, `cliente`, '
    '`destinatario`, `origen`, `destino`, `fechas` y `comprobante`; arreglos `paquetes`, `tracking` (315 101 eventos en total), '
    '`intentos_entrega` e `incidencias`; y `prueba_entrega` con un punto GeoJSON.',
    '**hubs** (38 documentos): red logística con capacidad por hora y ubicación GeoJSON; se referencia por su código.',
    '**clientes** (3 000 documentos): documento de identidad y datos de contacto como subdocumento.')
FIGURA('compass_documento', 'Documento de un envío en MongoDB Compass: subdocumentos y arreglos incrustados',
       FUENTE_COMPASS, ancho_cm=15, interp=
       'El envío OLV2600000001 reúne en un único documento su origen (subdocumento con hub, ciudad, región y nodo), sus '
       'paquetes y sus 11 escaneos de tracking (arreglo). En PostgreSQL la misma información exige combinar seis tablas.')
TXT('Estructura resumida del mismo documento (los campos se muestran abreviados):')
CODIGO('{ "_id": "OLV2600000001",\n'
       '  "servicio": { "codigo": "ESTANDAR_TERRESTRE", "sla_horas": 72 },\n'
       '  "origen":  { "hub": "AG-LIM-SUR", "ciudad": "Lima", "nodo": "LIMA" },\n'
       '  "destino": { "hub": "AG-CUZ-02", "ciudad": "Cusco", "nodo": "SUR" },\n'
       '  "estado_actual": "ENTREGADO", "monto_total": 23.0,\n'
       '  "paquetes": [ { "bulto": 1, "peso_kg": 2.01 } ],\n'
       '  "tracking": [\n'
       '    { "fecha_hora": ISODate("2026-04-01T13:05:45Z"), "evento": "ADMISION" },\n'
       '    ... 11 eventos ... ],\n'
       '  "intentos_entrega": [ { "nro": 1, "resultado": "ENTREGADO" } ],\n'
       '  "prueba_entrega": { "firma_digital": true,\n'
       '    "ubicacion": { "type": "Point", "coordinates": [-71.99, -13.53] } } }')
TXT('**Distribución en dos sedes.** Para comparar con la base distribuida del punto 9, la colección `envios` también se '
    'desplegó en un clúster de dos sedes con **fragmentación horizontal automática (sharding por zonas)**. Un servidor de '
    'configuración guarda el mapa de qué rango de datos pertenece a cada sede; un enrutador (`mongos`) es la única puerta de '
    'entrada y envía cada consulta a la sede que corresponde; y cada sede guarda solo su fragmento. La clave de fragmentación '
    'es `{ origen.nodo, _id }`:')
VIN('**Sede Lima (sede_lima, zona ZONA_LIMA):** envíos con origen en el nodo LIMA (Lima y Centro): 23 638 documentos '
    '(57,8 MB). Guarda además las colecciones no fragmentadas `hubs` y `clientes`.',
    '**Sede Arequipa (sede_arequipa, zona ZONA_PROVINCIAS):** envíos con origen en provincias, nodos NORTE y SUR: 6 328 '
    'documentos (16,6 MB).')
FIGURA('mg_zonas', 'Registro de las dos sedes y de las zonas de la clave de fragmentación', FUENTE_MONGOS,
       'Cada sede es dueña de una zona: los valores de origen.nodo menores que NORTE (LIMA) van a la sede Lima y los demás '
       '(NORTE y SUR) a la sede Arequipa. Al ser rangos definidos antes de la carga, cada documento se escribió directamente '
       'en su sede.', ancho_cm=12)

H2('10.3 Colecciones e índices')
TXT('La Figura 16 muestra las tres colecciones y las dos vistas de solo lectura de `olva_tracking`. La colección `envios` '
    'ocupa 78 MB de datos sin comprimir y solo 21,9 MB en disco gracias a la compresión del motor de almacenamiento.')
FIGURA('compass_colecciones', 'Colecciones y vistas de la base olva_tracking en MongoDB Compass', FUENTE_COMPASS)
TXT('Los índices se crearon después de la carga masiva (así cada índice se construye una sola vez) y cada uno responde a una '
    'consulta concreta del negocio:')
VIN('`ix_estado_compromiso` {estado_actual, fechas.compromiso}: envíos vivos con plazo vencido (alertas de SLA).',
    '`ix_cliente_fecha` {cliente.id, fechas.registro -1}: últimos envíos de un cliente en el portal web.',
    '`ix_tracking_hub_fecha` {tracking.hub, tracking.fecha_hora}: índice multiclave sobre el arreglo de escaneos, para saber '
    'qué envíos pasaron por un hub.',
    '`ix_destino_modalidad`, `ix_incidencia_tipo` (disperso: solo indexa envíos con incidencias) e `ix_pod_geo` (2dsphere) '
    'sobre la ubicación GPS de la entrega.',
    'En `hubs`: `ix_hub_geo` (2dsphere). En `clientes`: `ux_cliente_documento` (único) y `tx_cliente_nombre` (texto en español).')
FIGURA('compass_indices', 'Índices de la colección envios en MongoDB Compass', FUENTE_COMPASS,
       'Compass muestra el tipo, el tamaño y el uso de cada índice: el compuesto ix_estado_compromiso, el multiclave '
       'ix_tracking_hub_fecha, el disperso ix_incidencia_tipo y el geoespacial ix_pod_geo.')
TXT('La flexibilidad no significa ausencia de reglas. La colección `envios` se creó con un validador `$jsonSchema` en modo '
    'estricto que exige los campos obligatorios, el formato del número de tracking (`^OLV[0-9]{10}$`), los estados permitidos '
    'y los tipos de evento válidos.')
FIGURA('compass_validacion', 'Regla de validación $jsonSchema de la colección envios', FUENTE_COMPASS)

H2('10.4 Operaciones CRUD avanzadas e inserción masiva')
TXT('**Inserción masiva.** Los documentos se generaron en formato Extended JSON a partir de los mismos CSV de PostgreSQL y '
    'se cargaron con `mongoimport` usando cuatro hilos de inserción: 29 966 envíos en 9,5 s. Después se crearon los 12 '
    'índices de las tres colecciones.')
FIGURA('mg_carga', 'Carga masiva con mongoimport y creación de índices', FUENTE_MONGOSH)
TXT('Se ejecutaron 13 operaciones representativas; las principales son:')
VIN('**R1 – Lectura del expediente:** `findOne({ _id })` devuelve el envío con sus 11 escaneos y su prueba de entrega, sin JOIN.',
    '**R2 – Envíos vencidos:** `find()` con `$nin` y `$lt` sobre la fecha de compromiso; el plan es IXSCAN y examina solo los '
    '50 documentos que devuelve.',
    '**R3 – Consulta sobre un arreglo:** `$elemMatch` encuentra envíos con incidencias de pérdida o daño aún abiertas.',
    '**R4 – Consulta geoespacial:** `$geoNear` y `$geoWithin` hallan 613 entregas a menos de 2 km del Hub Regional Arequipa.',
    '**C2 – Validación:** un `insertOne` con estado inválido es rechazado por `$jsonSchema` ("Document failed validation").',
    '**U1 – Escaneo atómico:** `updateOne` con `$push` agrega un evento al arreglo y con `$set` cambia el estado en una sola operación.',
    '**U3 – Actualización selectiva en arreglos:** `arrayFilters` modifica solo las incidencias de RETRASO no cerradas dentro de cada envío (7 envíos).',
    '**B1 y B2 – Escritura masiva:** `insertMany` inserta 5 000 documentos en 117 ms y `bulkWrite` combina actualización, '
    'borrado e inserción en un solo viaje al servidor.')
FIGURA('mg_crud_1', 'Lecturas: expediente de un envío (R1) y consulta geoespacial (R4)', FUENTE_MONGOSH)
FIGURA('mg_crud_1b', 'Lecturas con índice (R2) y sobre arreglos con $elemMatch (R3)', FUENTE_MONGOSH,
       'El plan de R2 es IXSCAN: examina exactamente los 50 documentos que devuelve, en lugar de recorrer los 29 966.')
FIGURA('mg_crud_2', 'Escrituras: validación, $push/$set, arrayFilters, insertMany y bulkWrite', FUENTE_MONGOSH,
       'Todas las escrituras de prueba se revierten al final del script, de modo que la colección conserva los 29 966 envíos.')
TXT('**Pipelines de agregación.** Responden las preguntas de negocio del proyecto directamente sobre los documentos:')
VIN('**A1 – SLA por servicio** ($match, $group, $cond): Sobre / Documentos Aéreo 86,6 %, Express Aéreo 86,9 %, Estándar '
    'Terrestre 91,9 % y Económico Terrestre 98,9 %.',
    '**A2 – Permanencia en el Hub Central** ($unwind, $setWindowFields con $shift, $dateDiff): los 10 344 envíos que llegan a '
    'las 20:00 permanecen en promedio 14,6 h y 3 665 superan las 12 h.',
    '**A4 – Ocupación del Hub Central** ($lookup a hubs): a las 20:00 llegan en promedio 54,8 envíos por hora frente a una '
    'capacidad de 50, una ocupación de **110 %**, el mismo cuello de botella identificado en PostgreSQL.',
    '**A3, A5 y A6:** efectividad del primer intento por ciudad, los 10 clientes con mayor facturación ($lookup a clientes) y '
    'un tablero operativo en una sola consulta ($facet, $bucket, $sortByCount).')
FIGURA('compass_agregacion', 'Pipeline de agregación del SLA por servicio en MongoDB Compass', FUENTE_COMPASS)
FIGURA('mg_agregaciones', 'Agregaciones A1, A2 y A4: SLA, permanencia y ocupación del Hub Central', FUENTE_MONGOSH,
       'La franja de las 20:00 concentra la mayor cantidad de llegadas, la mayor permanencia y una ocupación del 110 % de la '
       'capacidad: confirma con un motor distinto el hallazgo principal del proyecto.')

H2('10.5 Administración de usuarios, roles y seguridad en MongoDB')
TXT('La autenticación usa el mecanismo SCRAM-SHA-256. Como MongoDB no permite conceder permisos por campo, los datos '
    'personales se protegen con **vistas**: se concede acceso a la vista y no a la colección. Se definieron roles '
    'personalizados con privilegios mínimos y un usuario por rol; las contraseñas se reciben por variable de entorno y no se '
    'escriben en los scripts (<CONTRASEÑA_CONFIGURADA>).')
VIN('**rol_tracking_web → u_tracking_web:** solo `find` sobre `vw_tracking_publico` (estado y último evento, sin datos personales).',
    '**rol_operador_hub → u_operador_mongo:** `find` y `update` sobre `envios` y `find` sobre `hubs`; no puede insertar, '
    'borrar ni leer clientes.',
    '**rol_analista → u_analista_mongo:** solo `find` sobre `vw_envios_analitica`, que oculta destinatario, documento y '
    'nombre del cliente, receptor y courier.')
CODIGO("db.createView('vw_envios_analitica', 'envios', [ { $project: {\n"
       "    destinatario: 0, 'cliente.documento': 0, 'cliente.nombre': 0,\n"
       "    prueba_entrega: 0, 'intentos_entrega.receptor': 0 } } ]);\n"
       "db.createRole({ role: 'rol_analista', roles: [], privileges: [\n"
       "  { resource: { db: 'olva_tracking', collection: 'vw_envios_analitica' },\n"
       "    actions: ['find'] },\n"
       "  { resource: { db: 'olva_tracking', collection: 'hubs' }, actions: ['find'] } ] });\n"
       "db.createUser({ user: 'u_analista_mongo', pwd: <CONTRASEÑA_CONFIGURADA>,\n"
       "                roles: ['rol_analista'], mechanisms: ['SCRAM-SHA-256'] });")
FIGURA('mg_seguridad', 'Usuarios, roles y privilegios creados en olva_tracking', FUENTE_MONGOSH, ancho_cm=13)
FIGURA('mg_seguridad_b', 'Pruebas de acceso por usuario y rechazo de una contraseña incorrecta', FUENTE_MONGOSH,
       'Cada usuario solo ejecuta lo que su rol permite: el operador lee y actualiza envíos pero no inserta ni borra; el '
       'analista lee la vista analítica con los campos personales ocultos; todo lo demás devuelve Unauthorized.', ancho_cm=13)

H2('10.6 Resultados y evidencias de ejecución')
VIN('**Carga:** 29 966 envíos, 38 hubs y 3 000 clientes; 315 101 escaneos incrustados; 12 índices.',
    '**Consultas:** el tracking completo se lee en un documento; las consultas filtradas usan índices (IXSCAN) y las '
    'agregaciones reproducen los resultados de PostgreSQL (SLA por servicio y 110 % de ocupación del Hub Central a las 20:00).',
    '**Seguridad:** tres roles de privilegio mínimo, vistas sin datos personales y rechazo verificado de accesos no permitidos.')
TXT('En el clúster de dos sedes se comprobó el reparto real de los datos y el enrutamiento de las consultas:')
FIGURA('mg_sedes', 'Documentos por sede, consultas dirigidas y agregación global por sede', FUENTE_MONGOS,
       'La sede Lima guarda 23 638 envíos y la sede Arequipa 6 328. La consulta con la clave de fragmentación (origen.nodo = '
       'SUR) se resuelve como SINGLE_SHARD en una sola sede; sin ella, el enrutador consulta ambas sedes (SHARD_MERGE). En la '
       'agregación, cada sede calcula su parte y mongos combina: SLA de 93,4 % en Lima frente a 83,9 % en Norte y 83,6 % en Sur.',
       ancho_cm=13)
FIGURA('compass_explain_sede', 'Plan de ejecución de una consulta dirigida a la sede Arequipa (SINGLE_SHARD)',
       'elaboración propia a partir de MongoDB Compass conectado al clúster de dos sedes.',
       'Con origen.nodo = SUR, el enrutador consulta solo la sede Arequipa y examina únicamente sus 3 162 documentos usando el '
       'índice de la clave de fragmentación.', ancho_cm=13)
FIGURA('compass_explain_merge', 'Plan de ejecución de una consulta que necesita ambas sedes (SHARD_MERGE)',
       'elaboración propia a partir de MongoDB Compass conectado al clúster de dos sedes.',
       'Sin la clave de fragmentación, cada sede filtra en paralelo con su índice (64 envíos en Arequipa y 196 en Lima) y el '
       'enrutador une los 260 resultados.', ancho_cm=13)
FIGURA('mg_transacciones', 'Transacciones distribuidas entre sedes y traslado de un documento', FUENTE_MONGOS,
       'Una transacción que escribe en ambas sedes se confirma completa (COMMIT) o no deja nada (ABORT). Al cambiar '
       'origen.nodo de LIMA a SUR, MongoDB trasladó el documento a la sede Arequipa. A diferencia del 2PC manual del punto 9.7, '
       'el motor coordina el compromiso en dos fases de forma interna.', ancho_cm=12)
FIGURA('mg_caida', 'Comportamiento ante la caída de la sede Arequipa', FUENTE_MONGOS,
       'Con la sede Arequipa detenida, la sede Lima sigue respondiendo y aceptando envíos nuevos, pero los datos de Arequipa no '
       'están disponibles hasta que vuelve. En la fragmentación cada sede guarda solo su parte; la alta disponibilidad se '
       'obtiene en producción con un conjunto de tres réplicas por sede.')

# =====================================================================
H1('11. SOLUCIÓN NOSQL – APACHE CASSANDRA')
TXT('Cada escaneo de un envío en un hub o agencia genera un evento que nunca se modifica, solo se agrega. Con 315 101 eventos '
    'en seis meses y picos de 145 llegadas por hora en el Hub Central, la bitácora de tracking es una **serie de tiempo de '
    'escritura intensiva** que se consulta siempre por envío o por hub y día. Apache Cassandra almacena esta bitácora y el '
    'estado en línea de cada envío, replicados en las dos sedes.')

H2('11.1 Justificación técnica de uso')
TXT('Cassandra es una base de datos de **columnas anchas** (wide-column): cada tabla se organiza en particiones definidas por '
    'una clave de partición, y dentro de cada partición las filas quedan ordenadas en disco por las columnas de clustering. '
    'Este modelo es idóneo para la bitácora de tracking por cuatro razones:')
VIN('**Escritura masiva y secuencial:** cada escritura se agrega al commit log y a una tabla en memoria, sin bloqueos ni '
    'lectura previa. En el proyecto, la carga alcanzó unas 45 000 filas por segundo (315 101 eventos en 5,7 s).',
    '**Lecturas por partición ya ordenadas:** el historial de un envío o los escaneos de un hub en un día están en una sola '
    'partición y en orden cronológico; no se necesita ORDER BY ni JOIN.',
    '**Arquitectura sin servidor central:** todos los nodos son iguales; cualquiera coordina una consulta y los datos se '
    'replican entre centros de datos. Si una sede queda aislada, la otra sigue leyendo y escribiendo.',
    '**Consistencia ajustable y datos que caducan:** cada consulta elige su nivel de consistencia (LOCAL_ONE, EACH_QUORUM, '
    'ALL), y las alertas temporales se borran solas con TTL.')
TXT('**¿Por qué no en PostgreSQL u Oracle?** En el modelo relacional, cada escaneo inserta una fila, actualiza varios índices '
    'B-tree, genera registros WAL o redo y, en el procedimiento `sp_registrar_escaneo`, bloquea el envío con FOR UPDATE. Con '
    'volúmenes crecientes esto exige escalar verticalmente un servidor cada vez más costoso. Cassandra escala horizontalmente '
    'agregando nodos y conserva la disponibilidad ante la caída de una sede. **Frente a MongoDB**, la diferencia es el '
    'propósito: MongoDB guarda el expediente de cada envío repartido entre sedes, mientras Cassandra guarda la bitácora de '
    'escaneos **copiada en ambas sedes**, porque el registro de eventos no puede detenerse aunque una sede falle.')

H2('11.2 Modelo de datos CQL')
TXT('En Cassandra el diseño es **orientado a consultas**: primero se definen las consultas y luego una tabla para cada una. '
    'Por eso el mismo escaneo se guarda a propósito en dos tablas (`eventos_por_envio` y `eventos_por_hub_dia`); esta '
    'desnormalización es la práctica correcta en el modelo, ya que no existen JOIN. El keyspace `olva_tracking` usa la '
    'estrategia NetworkTopologyStrategy, que define cuántas réplicas guarda cada centro de datos (sede).')
CODIGO("CREATE KEYSPACE olva_tracking\n"
       "  WITH replication = {'class': 'NetworkTopologyStrategy',\n"
       "                      'dc_lima': 1, 'dc_arequipa': 1};\n\n"
       "CREATE TABLE eventos_por_hub_dia (\n"
       "    hub text, dia date, fecha_hora timestamp, id_evento bigint,\n"
       "    nro_tracking text, tipo_evento text, servicio text,\n"
       "    PRIMARY KEY ((hub, dia), fecha_hora, id_evento)\n"
       ") WITH CLUSTERING ORDER BY (fecha_hora DESC, id_evento ASC)\n"
       "  AND compaction = {'class': 'TimeWindowCompactionStrategy',\n"
       "                    'compaction_window_unit': 'DAYS'};")
TXT('Tablas del keyspace, con su consulta, su clave de partición (PK) y sus columnas de clustering (CK):')
VIN('**eventos_por_envio** – historial de un envío. PK: `nro_tracking`; CK: `fecha_hora ASC, id_evento`. 315 101 filas.',
    '**eventos_por_hub_dia** – escaneos de un hub en un día. PK compuesta: `(hub, dia)`, que limita cada partición a un día '
    'por hub (máximo 61 kB); CK: `fecha_hora DESC, id_evento`. Usa compactación por ventanas de tiempo. 315 101 filas.',
    '**escaneos_hub_hora** – saturación por hora. PK: `(hub, dia)`; CK: `hora`. Agregado precalculado de llegadas y salidas '
    '(69 309 filas).',
    '**envios_por_cliente** – portal del cliente. PK: `id_cliente`; CK: `fecha_registro DESC, nro_tracking`. 29 966 filas.',
    '**estado_envio** – último estado de un envío. PK: `nro_tracking` (sin clustering); se sobrescribe en cada escaneo '
    '(upsert). Tiene un índice secundario sobre `estado`.',
    '**contador_escaneos** – contadores en línea (tipo counter). PK: `(hub, dia)`; CK: `tipo_evento`.',
    '**alertas_sla** – alertas temporales. PK: `hub`; CK: `fecha_alerta DESC`; caducan solas a las 48 h '
    '(default_time_to_live = 172 800 s).',
    '**hubs** – capacidad por hora de cada hub (tabla de referencia).')
FIGURA('cq_modelo', 'Tablas del keyspace olva_tracking y definición de eventos_por_hub_dia', FUENTE_CQLSH)
TXT('**Distribución en dos sedes.** El clúster `olva_cluster` tiene un nodo por sede, cada uno en su propio centro de datos: '
    '**dc_lima** (sede Lima) y **dc_arequipa** (sede Arequipa). A diferencia de PostgreSQL y MongoDB, Cassandra no fragmenta '
    'por sede sino que **replica**: con `{dc_lima: 1, dc_arequipa: 1}` cada sede guarda una copia completa del keyspace, y '
    'también de los usuarios (`system_auth`), para poder iniciar sesión aunque la otra sede no esté disponible. Al agregar la '
    'sede Arequipa, `nodetool rebuild` copió los datos existentes desde Lima en 2 s; luego ambas sedes quedaron con el mismo '
    'volumen (8,55 MB en eventos_por_envio y 6,32 MB en eventos_por_hub_dia en cada nodo). Para mostrar la localización de '
    'datos, el keyspace `olva_sede_arequipa` se replica solo en dc_arequipa: sus datos no salen de esa sede.')
FIGURA('cq_sedes', 'Centros de datos, replicación por sede y ubicación de las réplicas', FUENTE_NODETOOL,
       'nodetool status muestra los dos centros de datos activos (UN). La replicación de olva_tracking y system_auth incluye '
       'ambas sedes, y nodetool getendpoints confirma que el envío OLV2600000001 tiene una réplica en Lima y otra en Arequipa, '
       'mientras que el keyspace local solo existe en Arequipa.', ancho_cm=14)

H2('11.3 Consultas CQL representativas')
TXT('Cada consulta lee una sola partición, indicada por su clave de partición. Se ejecutaron las siguientes operaciones:')
VIN('**Q1 – Historial de un envío:** `WHERE nro_tracking = ...` devuelve los 11 escaneos ya ordenados por fecha, sin ORDER BY.',
    '**Q2 – Escaneos de un hub en una franja horaria:** rango sobre la columna de clustering `fecha_hora` dentro de la '
    'partición (HC-LIM, 2026-10-06).',
    '**Q3 – Saturación horaria:** el Hub Central recibió **84 llegadas a las 20:00** del 06/10, frente a una capacidad de 50 por hora.',
    '**Q4 – Portal del cliente:** sus envíos más recientes salen en orden descendente porque así están almacenados.',
    '**Q5 – Transacción ligera (LWT):** `UPDATE ... IF estado = ...` usa el protocolo Paxos: se rechaza ([applied] = False) '
    'si el estado no coincide y se aplica si coincide.',
    '**Q6 – BATCH:** el mismo escaneo se escribe de forma atómica en las dos tablas desnormalizadas.',
    '**Q7 – TTL:** la alerta insertada con `USING TTL 3600` muestra su tiempo de vida restante y desaparecerá sola.',
    '**Q8 – Restricción del modelo:** filtrar sin la clave de partición se rechaza (exige ALLOW FILTERING), porque obligaría '
    'a recorrer todos los nodos. Esta restricción es la que obliga a diseñar una tabla por consulta.')
FIGURA('cq_consultas_1', 'Q1 y Q2: historial de un envío y escaneos por hub y franja horaria', FUENTE_CQLSH)
FIGURA('cq_consultas_1b', 'Q3 y Q4: saturación horaria del Hub Central y portal del cliente', FUENTE_CQLSH,
       'La tabla escaneos_hub_hora responde en una sola partición la saturación del Hub Central: 84 llegadas a las 20:00 '
       'frente a una capacidad de 50, el cuello de botella detectado también en PostgreSQL y MongoDB.')
FIGURA('cq_consultas_2', 'Q5: transacción ligera (LWT) sobre el estado de un envío', FUENTE_CQLSH)
FIGURA('cq_consultas_2b', 'Q6: BATCH atómico sobre las tablas desnormalizadas', FUENTE_CQLSH)
FIGURA('cq_consultas_2c', 'Q7 y Q8: datos con caducidad (TTL) y consulta rechazada sin clave de partición', FUENTE_CQLSH,
       'Los cambios de prueba de Q5 y Q6 se revierten al terminar, de modo que el estado de los envíos no se altera.')

H2('11.4 Administración de usuarios y control de accesos en Cassandra')
TXT('Se activaron la autenticación por contraseña (PasswordAuthenticator) y la autorización por roles (CassandraAuthorizer). '
    'Se creó el superusuario del proyecto `olva_admin` y se **deshabilitó el usuario por defecto** `cassandra`. Los permisos '
    'se otorgan a roles de grupo y los usuarios los heredan:')
CODIGO("CREATE ROLE rol_analista;\n"
       "GRANT SELECT ON KEYSPACE olva_tracking TO rol_analista;\n"
       "CREATE ROLE rol_operador_hub;\n"
       "GRANT SELECT ON KEYSPACE olva_tracking TO rol_operador_hub;\n"
       "GRANT MODIFY ON TABLE olva_tracking.eventos_por_envio TO rol_operador_hub;\n"
       "-- (y el mismo GRANT MODIFY sobre las demás tablas de escaneo)\n"
       "CREATE ROLE rol_portal_cliente;\n"
       "GRANT SELECT ON TABLE olva_tracking.envios_por_cliente TO rol_portal_cliente;\n"
       "CREATE ROLE u_analista_cass\n"
       "  WITH LOGIN = true AND PASSWORD = '<CONTRASEÑA_CONFIGURADA>';\n"
       "GRANT rol_analista TO u_analista_cass;\n"
       "ALTER ROLE cassandra WITH LOGIN = false;")
FIGURA('cq_seguridad', 'Roles del clúster y permisos del rol de operador de hub', FUENTE_CQLSH, ancho_cm=12)
FIGURA('cq_seguridad_b', 'Pruebas de acceso de los usuarios analista y portal web', FUENTE_CQLSH,
       'El analista lee pero no puede modificar (sin permiso MODIFY); el portal web solo accede a sus dos tablas y no puede '
       'leer otras ni eliminar tablas. Cassandra responde Unauthorized en cada intento no permitido.')

H2('11.5 Resultados y evidencias de ejecución')
VIN('**Carga masiva con COPY:** 315 101 filas en eventos_por_envio (5,7 s) y 315 101 en eventos_por_hub_dia (7,5 s), '
    '69 309 en escaneos_hub_hora y 29 966 en envios_por_cliente y estado_envio, sin filas rechazadas.',
    '**Consultas:** todas se resuelven en una partición; la saturación de 84 llegadas por hora del Hub Central coincide con '
    'los resultados de PostgreSQL y MongoDB.',
    '**Seguridad:** autenticación activa, usuario por defecto deshabilitado y permisos por rol verificados.',
    '**Dos sedes:** cada sede guarda la copia completa; lo escrito en Arequipa se lee en Lima, y el dato local de Arequipa '
    'no es visible desde Lima con LOCAL_ONE ("alive_replicas: 0").')
FIGURA('cq_caida', 'Caída de la sede Lima: la sede Arequipa sigue operando y luego sincroniza', FUENTE_NODETOOL,
       'Con el nodo de Lima detenido (DN), la sede Arequipa inicia sesión, lee y escribe con LOCAL_ONE. Las operaciones que '
       'exigen ambas sedes (ALL y EACH_QUORUM) fallan con Unavailable. Al volver Lima, la alerta escrita durante la caída ya '
       'estaba en su copia gracias al mecanismo de hinted handoff.')
TXT('**Comparación de la distribución en las tres soluciones.** PostgreSQL fragmenta los datos en tres nodos diseñados a '
    'mano y los une con postgres_fdw y 2PC manual; MongoDB fragmenta automáticamente por zonas, con transacciones '
    'distribuidas nativas, pero cada sede depende de sus propios datos; Cassandra replica todo en cada sede y ofrece la mayor '
    'disponibilidad, a cambio de no tener transacciones de varias filas y de elegir la consistencia en cada consulta. Esta '
    'complementariedad justifica la arquitectura: PostgreSQL para la integridad transaccional, MongoDB para el expediente '
    'flexible del envío y Cassandra para la bitácora de escaneos que debe seguir escribiéndose aunque una sede falle.')
