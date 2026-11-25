-- =====================================================================
-- BD Distribuida - 01: esquema de un nodo regional (NORTE o SUR)
-- Uso:  psql -v nodo=NORTE -d olva_norte -f 01_ddl_nodo_regional.sql
--       psql -v nodo=SUR   -d olva_sur   -f 01_ddl_nodo_regional.sql
-- ---------------------------------------------------------------------
-- Contenido de cada nodo regional:
--   maestro.*   : catálogos REPLICADOS (copia completa en todos los nodos)
--   operacion.envio            : fragmento horizontal primario (nodo de la agencia de ORIGEN)
--   operacion.paquete          : fragmento horizontal DERIVADO de envio (co-localizado)
--   operacion.evento_tracking  : fragmento horizontal primario (nodo del HUB donde se escanea)
--   operacion.cliente_contacto : fragmento VERTICAL de cliente (datos de contacto),
--                                a su vez horizontal por ciudad del cliente (fragmentación mixta)
-- Cada fragmento tiene un CHECK con su predicado de fragmentación: el nodo
-- rechaza filas que no le pertenecen (integridad de la fragmentación).
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP SCHEMA IF EXISTS operacion CASCADE;
DROP SCHEMA IF EXISTS maestro CASCADE;
CREATE SCHEMA maestro;
CREATE SCHEMA operacion;

-- ---------------------------------------------------------------- réplicas
CREATE TABLE maestro.region (
    id_region SMALLINT PRIMARY KEY, codigo VARCHAR(5) NOT NULL UNIQUE, nombre VARCHAR(40) NOT NULL,
    nodo VARCHAR(10) NOT NULL);
CREATE TABLE maestro.ciudad (
    id_ciudad INTEGER PRIMARY KEY, nombre VARCHAR(60) NOT NULL, departamento VARCHAR(40) NOT NULL,
    id_region SMALLINT NOT NULL REFERENCES maestro.region, ubigeo CHAR(6) NOT NULL UNIQUE,
    tiene_aeropuerto BOOLEAN NOT NULL, acceso_terrestre BOOLEAN NOT NULL, latitud NUMERIC(9,6), longitud NUMERIC(9,6));
CREATE TABLE maestro.hub (
    id_hub INTEGER PRIMARY KEY, codigo VARCHAR(12) NOT NULL UNIQUE, nombre VARCHAR(80) NOT NULL,
    tipo VARCHAR(15) NOT NULL, id_ciudad INTEGER NOT NULL REFERENCES maestro.ciudad, id_hub_padre INTEGER,
    capacidad_hora INTEGER NOT NULL, direccion VARCHAR(150), activo BOOLEAN NOT NULL);
CREATE TABLE maestro.tipo_servicio (
    id_servicio SMALLINT PRIMARY KEY, codigo VARCHAR(20) NOT NULL UNIQUE, nombre VARCHAR(60) NOT NULL,
    modalidad VARCHAR(10) NOT NULL, sla_horas SMALLINT NOT NULL, peso_max_kg NUMERIC(6,2) NOT NULL);
CREATE TABLE maestro.tarifa (
    id_tarifa INTEGER PRIMARY KEY, id_servicio SMALLINT NOT NULL REFERENCES maestro.tipo_servicio,
    id_region_origen SMALLINT NOT NULL, id_region_destino SMALLINT NOT NULL, precio_base NUMERIC(8,2) NOT NULL,
    precio_kg_adicional NUMERIC(8,2) NOT NULL, vigente_desde DATE NOT NULL, vigente_hasta DATE);
CREATE TABLE maestro.ruta (
    id_ruta INTEGER PRIMARY KEY, id_hub_origen INTEGER NOT NULL REFERENCES maestro.hub,
    id_hub_destino INTEGER NOT NULL REFERENCES maestro.hub, modalidad VARCHAR(10) NOT NULL,
    distancia_km NUMERIC(7,1) NOT NULL, tiempo_estimado_horas NUMERIC(5,1) NOT NULL, activa BOOLEAN NOT NULL);

-- función local: nodo al que pertenece un hub (usa la réplica del catálogo)
CREATE FUNCTION maestro.fn_nodo_hub(p_id_hub INTEGER) RETURNS VARCHAR LANGUAGE sql STABLE AS
$$ SELECT r.nodo FROM maestro.hub h JOIN maestro.ciudad c USING (id_ciudad) JOIN maestro.region r USING (id_region)
    WHERE h.id_hub = p_id_hub $$;

-- ---------------------------------------------------------------- fragmentos
CREATE TABLE operacion.cliente_contacto (
    id_cliente           INTEGER      PRIMARY KEY,
    nombre_razon_social  VARCHAR(120) NOT NULL,
    email                VARCHAR(120),
    telefono             VARCHAR(15),
    direccion            VARCHAR(150),
    id_ciudad            INTEGER      NOT NULL REFERENCES maestro.ciudad,
    nodo                 VARCHAR(10)  NOT NULL CHECK (nodo = :'nodo')
);

CREATE TABLE operacion.envio (
    id_envio           BIGINT        PRIMARY KEY,
    nro_tracking       CHAR(13)      NOT NULL UNIQUE,
    id_cliente         INTEGER       NOT NULL REFERENCES operacion.cliente_contacto,   -- co-localizado
    id_destinatario    INTEGER       NOT NULL,                                         -- vive en el nodo central
    id_servicio        SMALLINT      NOT NULL REFERENCES maestro.tipo_servicio,
    id_hub_origen      INTEGER       NOT NULL REFERENCES maestro.hub,
    id_hub_destino     INTEGER       NOT NULL REFERENCES maestro.hub,
    direccion_entrega  VARCHAR(150)  NOT NULL,
    fecha_registro     TIMESTAMPTZ   NOT NULL,
    fecha_compromiso   TIMESTAMPTZ   NOT NULL,
    estado_actual      VARCHAR(15)   NOT NULL CHECK (estado_actual IN ('REGISTRADO', 'ADMITIDO', 'EN_HUB', 'EN_TRANSITO',
                                     'EN_REPARTO', 'INTENTO_FALLIDO', 'ENTREGADO', 'DEVUELTO')),
    peso_total_kg      NUMERIC(7,2)  NOT NULL,
    valor_declarado    NUMERIC(10,2) NOT NULL,
    monto_total        NUMERIC(10,2) NOT NULL,
    fecha_entrega      TIMESTAMPTZ,
    nodo               VARCHAR(10)   NOT NULL CHECK (nodo = :'nodo'),
    CONSTRAINT ck_predicado_fragmento CHECK (maestro.fn_nodo_hub(id_hub_origen) = nodo)
);

CREATE TABLE operacion.paquete (
    id_paquete   BIGINT       PRIMARY KEY,
    id_envio     BIGINT       NOT NULL REFERENCES operacion.envio ON DELETE CASCADE,          -- co-localizado
    nro_bulto    SMALLINT     NOT NULL,
    peso_kg      NUMERIC(6,2) NOT NULL,
    largo_cm     NUMERIC(5,1) NOT NULL,
    ancho_cm     NUMERIC(5,1) NOT NULL,
    alto_cm      NUMERIC(5,1) NOT NULL,
    descripcion  VARCHAR(100) NOT NULL,
    fragil       BOOLEAN      NOT NULL,
    nodo         VARCHAR(10)  NOT NULL CHECK (nodo = :'nodo'),
    UNIQUE (id_envio, nro_bulto)
);

CREATE TABLE operacion.evento_tracking (
    id_evento    BIGINT       PRIMARY KEY,
    id_envio     BIGINT       NOT NULL,                 -- el envío puede residir en otro nodo: sin FK
    tipo_evento  VARCHAR(16)  NOT NULL,
    id_hub       INTEGER      NOT NULL REFERENCES maestro.hub,
    id_empleado  INTEGER,
    id_despacho  BIGINT,
    fecha_hora   TIMESTAMPTZ  NOT NULL,
    observacion  VARCHAR(200),
    nodo         VARCHAR(10)  NOT NULL CHECK (nodo = :'nodo'),
    CONSTRAINT ck_predicado_fragmento CHECK (maestro.fn_nodo_hub(id_hub) = nodo)
);

CREATE INDEX ix_envio_origen_fecha ON operacion.envio (id_hub_origen, fecha_registro);
CREATE INDEX ix_envio_estado       ON operacion.envio (estado_actual);
CREATE INDEX ix_evento_envio       ON operacion.evento_tracking (id_envio, fecha_hora);
CREATE INDEX ix_evento_hub_fecha   ON operacion.evento_tracking (id_hub, fecha_hora);

-- ---------------------------------------------------------------- replicación inicial de catálogos
-- (copia completa desde la misma fuente que el nodo central)
\copy maestro.region        FROM '/proyecto/01_Relacional_PostgreSQL/datos/region.csv'        WITH (FORMAT csv, HEADER true)
\copy maestro.ciudad        FROM '/proyecto/01_Relacional_PostgreSQL/datos/ciudad.csv'        WITH (FORMAT csv, HEADER true)
\copy maestro.hub           FROM '/proyecto/01_Relacional_PostgreSQL/datos/hub.csv'           WITH (FORMAT csv, HEADER true)
\copy maestro.tipo_servicio FROM '/proyecto/01_Relacional_PostgreSQL/datos/tipo_servicio.csv' WITH (FORMAT csv, HEADER true)
\copy maestro.tarifa        FROM '/proyecto/01_Relacional_PostgreSQL/datos/tarifa.csv'        WITH (FORMAT csv, HEADER true)
\copy maestro.ruta          FROM '/proyecto/01_Relacional_PostgreSQL/datos/ruta.csv'          WITH (FORMAT csv, HEADER true)

SELECT current_database() AS nodo_bd, :'nodo' AS nodo, COUNT(*) AS tablas
  FROM information_schema.tables WHERE table_schema IN ('maestro', 'operacion');
