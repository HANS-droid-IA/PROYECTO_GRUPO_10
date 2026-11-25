# Distribución por sedes: PostgreSQL vs MongoDB vs Cassandra

El mismo dato de Olva Courier (29 966 envíos y 315 101 escaneos) se reparte geográficamente con tres motores distintos. Cada motor resuelve el problema a su manera.

| | PostgreSQL (`03_BD_Distribuida`) | MongoDB (`04_NoSQL_MongoDB/distribuido`) | Cassandra (`05_NoSQL_Cassandra/distribuido`) |
|---|---|---|---|
| Sedes | 3 nodos: Lima (coordinador), Norte, Sur | 2 shards: **sede_lima**, **sede_arequipa** | 2 centros de datos: **dc_lima**, **dc_arequipa** |
| Estrategia | **Fragmentación** horizontal y vertical, diseñada a mano | **Fragmentación** horizontal automática (*sharding* por zonas) | **Replicación**: cada sede guarda una copia completa |
| Criterio de reparto | `LIST` por nodo de origen (HF1), paquete derivado (HF2), evento por hub (HF3) | Clave de fragmentación `{ origen.nodo, _id }`: LIMA → sede Lima; NORTE y SUR → sede Arequipa | Todo el keyspace en las dos sedes (`dc_lima: 1, dc_arequipa: 1`); un keyspace local (`olva_sede_arequipa`) solo en Arequipa |
| Datos por sede | Cada nodo guarda solo su fragmento | Lima 23 638 envíos (57.8 MB), Arequipa 6 328 (16.6 MB) | Lima y Arequipa: los 315 101 eventos cada una (8.55 MB por tabla en cada nodo) |
| Quién enruta la consulta | El coordinador Lima con `postgres_fdw` (tablas foráneas) | El router `mongos` con los metadatos del *config server* | Cualquier nodo es coordinador; no hay servidor central |
| Consulta con la clave de reparto | Poda de particiones: solo lee el fragmento necesario | `SINGLE_SHARD`: solo pregunta a una sede | Lee la partición en la sede local (`LOCAL_ONE`) |
| Consulta sin la clave de reparto | Lee todos los fragmentos (local + remotos) | `SHARD_MERGE`: pregunta a todas las sedes y combina | Rechazada (`ALLOW FILTERING`): obliga a diseñar por consulta |
| Agregación global | El coordinador une las particiones remotas | Pipeline dividido: cada sede calcula su parte y `mongos` combina | Solo dentro de una partición; las agregaciones globales se precalculan |
| Transacción entre sedes | **2PC manual** (`PREPARE TRANSACTION` / `COMMIT PREPARED`) con bitácora en el coordinador | **Transacción distribuida nativa** (2PC interno): COMMIT y ABORT entre sedes, y traslado de un documento de sede al cambiar su clave | Sin transacciones multi-fila; **BATCH** atómico y **LWT** (Paxos) por partición |
| Consistencia | Fuerte (ACID) | Fuerte dentro de la transacción (`snapshot`, `w: majority`) | **Ajustable por consulta**: `LOCAL_ONE`, `EACH_QUORUM`, `ALL` |
| Si una sede cae | Las consultas que necesitan ese fragmento fallan | Las consultas a la sede viva **funcionan**; las que necesitan la sede caída fallan (`FailedToSatisfyReadPreference`) | La sede viva **sigue leyendo y escribiendo** (`LOCAL_ONE`); `ALL` y `EACH_QUORUM` fallan; al volver, recibe lo escrito durante la caída (*hinted handoff*) |
| Costo de agregar una sede | Crear el nodo, las tablas foráneas y las particiones, y migrar datos a mano | `addShard` y rangos de zona; el balanceador mueve los datos | Iniciar el nodo con `CASSANDRA_DC`, ajustar la replicación y ejecutar `nodetool rebuild` (6 s) |

## Resultados verificados (evidencias en cada carpeta `evidencias/`)

**MongoDB**
- La consulta `{ 'origen.nodo': 'SUR', estado_actual: 'EN_HUB' }` es `SINGLE_SHARD` y solo consulta `sede_arequipa` (34 envíos).
- La consulta `{ estado_actual: 'EN_HUB' }` es `SHARD_MERGE`: `sede_arequipa=64` y `sede_lima=196`.
- SLA por sede: Lima 93.4 %, Norte 83.9 % y Sur 83.6 %. Es un pipeline dividido y `mongos` combina los resultados.
- Transacciones:
  - Un COMMIT con un envío en cada sede deja los dos documentos.
  - Un ABORT no deja nada: se veían 2 documentos dentro de la transacción y 0 después.
  - Cambiar `origen.nodo` de LIMA a SUR movió el documento a `sede_arequipa`.
- Con la sede Arequipa detenida:
  - Lima responde (196 envíos EN_HUB) y acepta altas.
  - Las consultas a Arequipa y las globales fallan.
  - Al encenderla de nuevo, todo vuelve a responder (260).

**Cassandra**
- `nodetool getendpoints` para `OLV2600000001` devuelve dos réplicas, una en Lima (172.18.0.6) y otra en Arequipa (172.18.0.7). El keyspace local solo devuelve Arequipa.
- Las dos sedes responden la misma consulta con sus propios datos: 84 llegadas a las 20:00 y 11 eventos del envío.
- Lo escrito en Arequipa se lee en Lima.
- El dato local de Arequipa no se puede leer en Lima con `LOCAL_ONE` ("alive_replicas: 0"). Sí se lee con `ONE`, porque el coordinador de Lima se lo pide a Arequipa.
- Con Lima detenida:
  - Arequipa inicia sesión, lee y escribe con `LOCAL_ONE`.
  - `ALL` falla con "required_replicas: 2, alive_replicas: 1".
  - `EACH_QUORUM` falla con "in DC dc_lima".
  - Al volver Lima, la alerta escrita durante la caída ya estaba en Lima.

## Conclusión
- **PostgreSQL**: mantiene la consistencia ACID total. La distribución se diseña y se mantiene a mano: fragmentos, tablas foráneas y 2PC.
- **MongoDB**: fragmenta automáticamente por zona geográfica y conserva las transacciones entre sedes. Cada sede guarda solo sus documentos, así que si una cae se pierde el acceso a ese fragmento.
- **Cassandra**: no fragmenta por sede, replica. Cada sede guarda todo y sigue operando si la otra cae, a cambio de consistencia ajustable en lugar de transacciones.

Por eso en la arquitectura de Olva:
- **PostgreSQL** guarda el núcleo transaccional (clientes, tarifas, facturación).
- **MongoDB** guarda el expediente de cada envío, repartido por la sede donde se origina.
- **Cassandra** guarda la bitácora de escaneos, que debe seguir escribiéndose aunque una sede quede aislada.

## Cómo ejecutarlo
```bash
# MongoDB con 2 sedes (puerto del router: 27020)
docker compose --profile sedes_mongo up -d
bash 04_NoSQL_MongoDB/distribuido/00_desplegar_sedes.sh

# Cassandra con 2 sedes (Lima :9042, Arequipa :9043); requiere olva_tracking cargado
docker compose --profile nosql --profile sedes_cassandra up -d
bash 05_NoSQL_Cassandra/distribuido/00_desplegar_sedes.sh
```
En el laboratorio cada sede es un solo servidor. En producción cada shard de MongoDB sería un conjunto de 3 réplicas, y cada centro de datos de Cassandra tendría RF = 3.
