-- =====================================================================
-- BD Distribuida - 02: capa de coordinación en el nodo LIMA (olva_lima)
-- ---------------------------------------------------------------------
-- El nodo Lima, además de su propio fragmento (creado con 01_ddl_nodo_regional.sql
-- y nodo=LIMA), actúa como COORDINADOR / esquema global:
--   * postgres_fdw: servidores remotos srv_norte y srv_sur
--   * schema global: tablas PARTICIONADAS por LIST(nodo) cuya partición LIMA es
--     la tabla local y las particiones NORTE/SUR son FOREIGN TABLES remotas.
--     => transparencia de ubicación: la aplicación consulta global.envio sin
--        saber en qué nodo está cada fila; el optimizador poda particiones
--        (LOCALIZACIÓN) y empuja filtros/agregaciones a cada nodo (OPTIMIZACIÓN).
--   * fragmento vertical cliente_fiscal (solo en Lima) + vista de reconstrucción.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- ------------------------------------------------------------ servidores remotos
DROP SERVER IF EXISTS srv_norte  CASCADE;
DROP SERVER IF EXISTS srv_sur    CASCADE;
DROP SERVER IF EXISTS srv_origen CASCADE;

CREATE SERVER srv_norte FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'pg_norte', port '5432', dbname 'olva_norte',
             fetch_size '5000', batch_size '1000', async_capable 'true', use_remote_estimate 'true');
CREATE SERVER srv_sur FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'pg_sur', port '5432', dbname 'olva_sur',
             fetch_size '5000', batch_size '1000', async_capable 'true', use_remote_estimate 'true');
-- BD centralizada original (Avance 1), fuente de la migración a fragmentos
CREATE SERVER srv_origen FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'localhost', port '5432', dbname 'olva_courier', fetch_size '10000');

CREATE USER MAPPING FOR CURRENT_USER SERVER srv_norte  OPTIONS (user :'usuario', password :'clave');
CREATE USER MAPPING FOR CURRENT_USER SERVER srv_sur    OPTIONS (user :'usuario', password :'clave');
CREATE USER MAPPING FOR CURRENT_USER SERVER srv_origen OPTIONS (user :'usuario', password :'clave');

-- ------------------------------------------------------------ fuente de migración
DROP SCHEMA IF EXISTS origen CASCADE;
CREATE SCHEMA origen;
IMPORT FOREIGN SCHEMA operacion LIMIT TO (envio, paquete, evento_tracking) FROM SERVER srv_origen INTO origen;
CREATE FOREIGN TABLE origen.cliente (
    id_cliente INTEGER, tipo_cliente VARCHAR(8), tipo_documento VARCHAR(3), nro_documento VARCHAR(12),
    nombre_razon_social VARCHAR(120), email VARCHAR(120), telefono VARCHAR(15), direccion VARCHAR(150),
    id_ciudad INTEGER, fecha_registro DATE)
    SERVER srv_origen OPTIONS (schema_name 'maestro', table_name 'cliente');

-- ------------------------------------------------------------ fragmento vertical (solo Lima)
CREATE TABLE operacion.cliente_fiscal (
    id_cliente      INTEGER     PRIMARY KEY,
    tipo_cliente    VARCHAR(8)  NOT NULL CHECK (tipo_cliente IN ('PERSONA', 'EMPRESA')),
    tipo_documento  VARCHAR(3)  NOT NULL,
    nro_documento   VARCHAR(12) NOT NULL,
    fecha_registro  DATE        NOT NULL,
    UNIQUE (tipo_documento, nro_documento)
);
COMMENT ON TABLE operacion.cliente_fiscal IS
    'Fragmento vertical VF1 de cliente: identificación tributaria (SUNAT/facturación). Asignado solo al nodo Lima';

-- ------------------------------------------------------------ esquema global (particionado)
DROP SCHEMA IF EXISTS global CASCADE;
CREATE SCHEMA global;

CREATE TABLE global.cliente_contacto (LIKE operacion.cliente_contacto INCLUDING DEFAULTS) PARTITION BY LIST (nodo);
CREATE TABLE global.envio            (LIKE operacion.envio            INCLUDING DEFAULTS) PARTITION BY LIST (nodo);
CREATE TABLE global.paquete          (LIKE operacion.paquete          INCLUDING DEFAULTS) PARTITION BY LIST (nodo);
CREATE TABLE global.evento_tracking  (LIKE operacion.evento_tracking  INCLUDING DEFAULTS) PARTITION BY LIST (nodo);

-- partición local (nodo Lima)
ALTER TABLE global.cliente_contacto ATTACH PARTITION operacion.cliente_contacto FOR VALUES IN ('LIMA');
ALTER TABLE global.envio            ATTACH PARTITION operacion.envio            FOR VALUES IN ('LIMA');
ALTER TABLE global.paquete          ATTACH PARTITION operacion.paquete          FOR VALUES IN ('LIMA');
ALTER TABLE global.evento_tracking  ATTACH PARTITION operacion.evento_tracking  FOR VALUES IN ('LIMA');

-- particiones remotas (foreign tables)
CREATE FOREIGN TABLE global.cliente_contacto_norte PARTITION OF global.cliente_contacto FOR VALUES IN ('NORTE')
    SERVER srv_norte OPTIONS (schema_name 'operacion', table_name 'cliente_contacto');
CREATE FOREIGN TABLE global.cliente_contacto_sur   PARTITION OF global.cliente_contacto FOR VALUES IN ('SUR')
    SERVER srv_sur   OPTIONS (schema_name 'operacion', table_name 'cliente_contacto');
CREATE FOREIGN TABLE global.envio_norte PARTITION OF global.envio FOR VALUES IN ('NORTE')
    SERVER srv_norte OPTIONS (schema_name 'operacion', table_name 'envio');
CREATE FOREIGN TABLE global.envio_sur   PARTITION OF global.envio FOR VALUES IN ('SUR')
    SERVER srv_sur   OPTIONS (schema_name 'operacion', table_name 'envio');
CREATE FOREIGN TABLE global.paquete_norte PARTITION OF global.paquete FOR VALUES IN ('NORTE')
    SERVER srv_norte OPTIONS (schema_name 'operacion', table_name 'paquete');
CREATE FOREIGN TABLE global.paquete_sur   PARTITION OF global.paquete FOR VALUES IN ('SUR')
    SERVER srv_sur   OPTIONS (schema_name 'operacion', table_name 'paquete');
CREATE FOREIGN TABLE global.evento_tracking_norte PARTITION OF global.evento_tracking FOR VALUES IN ('NORTE')
    SERVER srv_norte OPTIONS (schema_name 'operacion', table_name 'evento_tracking');
CREATE FOREIGN TABLE global.evento_tracking_sur   PARTITION OF global.evento_tracking FOR VALUES IN ('SUR')
    SERVER srv_sur   OPTIONS (schema_name 'operacion', table_name 'evento_tracking');

-- reconstrucción del cliente: VF1 (fiscal, Lima) ⋈ VF2 (contacto, distribuido)
CREATE VIEW global.cliente AS
SELECT f.id_cliente, f.tipo_cliente, f.tipo_documento, f.nro_documento,
       c.nombre_razon_social, c.email, c.telefono, c.direccion, c.id_ciudad, f.fecha_registro, c.nodo
  FROM operacion.cliente_fiscal f
  JOIN global.cliente_contacto c ON c.id_cliente = f.id_cliente;

-- catálogo de ubicación (esquema de asignación) consultable
CREATE VIEW global.catalogo_fragmentos AS
SELECT p.relname AS tabla_global, c.relname AS fragmento,
       pg_get_expr(c.relpartbound, c.oid) AS predicado,
       CASE c.relkind WHEN 'f' THEN fs.srvname ELSE 'local (olva_lima)' END AS ubicacion
  FROM pg_inherits i
  JOIN pg_class p ON p.oid = i.inhparent
  JOIN pg_class c ON c.oid = i.inhrelid
  LEFT JOIN pg_foreign_table ft ON ft.ftrelid = c.oid
  LEFT JOIN pg_foreign_server fs ON fs.oid = ft.ftserver
 WHERE p.relnamespace = 'global'::regnamespace
 ORDER BY 1, 2;

SELECT * FROM global.catalogo_fragmentos;
