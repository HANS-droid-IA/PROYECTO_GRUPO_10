-- =====================================================================
-- BD Distribuida - 03: migración de la BD centralizada a los fragmentos
-- Se ejecuta en olva_lima. Lee de olva_courier (origen) y escribe en las
-- tablas globales: el particionamiento ENRUTA cada fila a su nodo
-- (local o remoto vía postgres_fdw con inserciones por lotes).
-- =====================================================================
\set ON_ERROR_STOP on
\timing on

-- nodo de cada hub según la réplica local del catálogo
CREATE TEMP TABLE nodo_hub AS
SELECT h.id_hub, r.nodo
  FROM maestro.hub h JOIN maestro.ciudad c USING (id_ciudad) JOIN maestro.region r USING (id_region);
CREATE TEMP TABLE nodo_ciudad AS
SELECT c.id_ciudad, r.nodo FROM maestro.ciudad c JOIN maestro.region r USING (id_region);

\echo '>> VF1: cliente_fiscal (completo, solo en Lima)'
INSERT INTO operacion.cliente_fiscal
SELECT id_cliente, tipo_cliente, tipo_documento, nro_documento, fecha_registro FROM origen.cliente;

\echo '>> VF2 + HF: cliente_contacto -> nodo de la ciudad del cliente'
INSERT INTO global.cliente_contacto
SELECT c.id_cliente, c.nombre_razon_social, c.email, c.telefono, c.direccion, c.id_ciudad, n.nodo
  FROM origen.cliente c JOIN nodo_ciudad n USING (id_ciudad);

\echo '>> HF primaria: envio -> nodo de la agencia de origen'
INSERT INTO global.envio
SELECT e.id_envio, e.nro_tracking, e.id_cliente, e.id_destinatario, e.id_servicio, e.id_hub_origen, e.id_hub_destino,
       e.direccion_entrega, e.fecha_registro, e.fecha_compromiso, e.estado_actual, e.peso_total_kg, e.valor_declarado,
       e.monto_total, e.fecha_entrega, n.nodo
  FROM origen.envio e JOIN nodo_hub n ON n.id_hub = e.id_hub_origen;

\echo '>> HF derivada: paquete -> mismo nodo que su envío (semijoin con envio)'
INSERT INTO global.paquete
SELECT p.id_paquete, p.id_envio, p.nro_bulto, p.peso_kg, p.largo_cm, p.ancho_cm, p.alto_cm, p.descripcion, p.fragil, n.nodo
  FROM origen.paquete p
  JOIN origen.envio e ON e.id_envio = p.id_envio
  JOIN nodo_hub n ON n.id_hub = e.id_hub_origen;

\echo '>> HF primaria: evento_tracking -> nodo del hub donde ocurre el escaneo'
INSERT INTO global.evento_tracking
SELECT v.id_evento, v.id_envio, v.tipo_evento, v.id_hub, v.id_empleado, v.id_despacho, v.fecha_hora, v.observacion, n.nodo
  FROM origen.evento_tracking v JOIN nodo_hub n ON n.id_hub = v.id_hub;

\timing off
ANALYZE operacion.cliente_fiscal, operacion.cliente_contacto, operacion.envio, operacion.paquete, operacion.evento_tracking;
