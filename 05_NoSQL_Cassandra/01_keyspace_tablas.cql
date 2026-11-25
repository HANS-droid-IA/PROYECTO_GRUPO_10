-- =====================================================================
-- 11.2  Modelo de datos CQL - keyspace olva_tracking
-- Diseño ORIENTADO A CONSULTAS: primero se definen las consultas y luego
-- una tabla por consulta. La clave de partición decide en qué nodo vive el
-- dato; las columnas de clustering ordenan las filas dentro de la partición.
--
--  Consulta                                         Tabla                 Partición            Clustering
--  Q1 Historial de un tracking                      eventos_por_envio     nro_tracking         fecha_hora ASC
--  Q2 Escaneos de un hub en un día / rango horario  eventos_por_hub_dia   (hub, dia)           fecha_hora DESC
--  Q3 Saturación de un hub por hora                 escaneos_hub_hora     (hub, dia)           hora ASC
--  Q4 Últimos envíos de un cliente                  envios_por_cliente    id_cliente           fecha_registro DESC
--  Q5 Estado actual de un envío                     estado_envio          nro_tracking         -
--  Q6 Contador en línea de escaneos                 contador_escaneos     (hub, dia)           tipo_evento
--  Q7 Alertas temporales de SLA (expiran solas)     alertas_sla           hub                  fecha_alerta DESC
-- =====================================================================

-- Replicación por centro de datos. En el laboratorio hay 1 nodo (dc_lima, RF=1);
-- en producción se usaría {'dc_lima': 3, 'dc_norte': 2, 'dc_sur': 2}.
DROP KEYSPACE IF EXISTS olva_tracking;
CREATE KEYSPACE olva_tracking
  WITH replication = {'class': 'NetworkTopologyStrategy', 'dc_lima': 1}
  AND durable_writes = true;

USE olva_tracking;

-- Q1: SELECT * FROM eventos_por_envio WHERE nro_tracking = ?
CREATE TABLE eventos_por_envio (
    nro_tracking  text,
    fecha_hora    timestamp,
    id_evento     bigint,
    tipo_evento   text,
    hub           text,
    ciudad        text,
    id_despacho   bigint,
    observacion   text,
    PRIMARY KEY ((nro_tracking), fecha_hora, id_evento)
) WITH CLUSTERING ORDER BY (fecha_hora ASC, id_evento ASC)
  AND comment = 'Q1 - línea de tiempo de un envío';

-- Q2: SELECT * FROM eventos_por_hub_dia WHERE hub = ? AND dia = ? [AND fecha_hora >= ? AND fecha_hora < ?]
-- Partición compuesta (hub, dia): limita el tamaño de la partición a un día por hub
-- (el Hub Central recibe miles de escaneos diarios: sin "dia" la partición crecería sin fin).
CREATE TABLE eventos_por_hub_dia (
    hub           text,
    dia           date,
    fecha_hora    timestamp,
    id_evento     bigint,
    nro_tracking  text,
    tipo_evento   text,
    servicio      text,
    PRIMARY KEY ((hub, dia), fecha_hora, id_evento)
) WITH CLUSTERING ORDER BY (fecha_hora DESC, id_evento ASC)
  AND compaction = {'class': 'TimeWindowCompactionStrategy', 'compaction_window_unit': 'DAYS', 'compaction_window_size': 1}
  AND comment = 'Q2 - escaneos por hub y día (serie de tiempo)';

-- Q3: SELECT hora, llegadas FROM escaneos_hub_hora WHERE hub = ? AND dia = ?
CREATE TABLE escaneos_hub_hora (
    hub       text,
    dia       date,
    hora      int,
    llegadas  int,
    salidas   int,
    escaneos  int,
    PRIMARY KEY ((hub, dia), hora)
) WITH CLUSTERING ORDER BY (hora ASC)
  AND comment = 'Q3 - agregado horario por hub (pre-calculado por el proceso de carga)';

-- Q4: SELECT * FROM envios_por_cliente WHERE id_cliente = ? LIMIT 10
CREATE TABLE envios_por_cliente (
    id_cliente      int,
    fecha_registro  timestamp,
    nro_tracking    text,
    servicio        text,
    origen          text,
    destino         text,
    estado          text,
    monto_total     decimal,
    PRIMARY KEY ((id_cliente), fecha_registro, nro_tracking)
) WITH CLUSTERING ORDER BY (fecha_registro DESC, nro_tracking ASC)
  AND comment = 'Q4 - últimos envíos de un cliente';

-- Q5: SELECT * FROM estado_envio WHERE nro_tracking = ?
CREATE TABLE estado_envio (
    nro_tracking         text PRIMARY KEY,
    estado               text,
    ultimo_evento        text,
    ultimo_hub           text,
    fecha_ultimo_evento  timestamp,
    fecha_compromiso     timestamp,
    servicio             text,
    destino              text
) WITH comment = 'Q5 - último estado (se sobrescribe con cada escaneo: upsert)';

-- Q6: contador distribuido (solo admite UPDATE ... SET c = c + n)
CREATE TABLE contador_escaneos (
    hub          text,
    dia          date,
    tipo_evento  text,
    total        counter,
    PRIMARY KEY ((hub, dia), tipo_evento)
) WITH comment = 'Q6 - contador en tiempo real';

-- Q7: alertas que caducan solas a las 48 h (TTL por defecto de la tabla)
CREATE TABLE alertas_sla (
    hub           text,
    fecha_alerta  timestamp,
    nro_tracking  text,
    nivel         text,
    mensaje       text,
    PRIMARY KEY ((hub), fecha_alerta, nro_tracking)
) WITH CLUSTERING ORDER BY (fecha_alerta DESC, nro_tracking ASC)
  AND default_time_to_live = 172800
  AND comment = 'Q7 - alertas temporales de SLA (TTL 48 h)';

-- tabla de referencia pequeña
CREATE TABLE hubs (
    hub             text PRIMARY KEY,
    nombre          text,
    tipo            text,
    ciudad          text,
    capacidad_hora  int
);

-- índice secundario (uso puntual, baja cardinalidad dentro de la tabla de estados)
CREATE INDEX ix_estado_envio_estado ON estado_envio (estado);

DESCRIBE TABLES;
