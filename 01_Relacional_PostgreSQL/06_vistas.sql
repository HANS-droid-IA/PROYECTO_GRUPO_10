-- =====================================================================
-- 06 - Vistas (capa de consumo por perfil de usuario)
-- =====================================================================

-- Vista de tracking público: lo que atención al cliente / web muestra.
-- No expone montos, documentos ni datos del remitente.
CREATE OR REPLACE VIEW operacion.vw_tracking_publico AS
SELECT e.nro_tracking,
       ts.nombre                AS servicio,
       co.nombre                AS ciudad_origen,
       cd.nombre                AS ciudad_destino,
       e.estado_actual,
       e.fecha_registro,
       e.fecha_compromiso,
       e.fecha_entrega,
       ev.tipo_evento           AS ultimo_evento,
       h.nombre                 AS ultimo_lugar,
       ev.fecha_hora            AS fecha_ultimo_evento
  FROM operacion.envio e
  JOIN maestro.tipo_servicio ts ON ts.id_servicio = e.id_servicio
  JOIN maestro.hub ho ON ho.id_hub = e.id_hub_origen
  JOIN maestro.ciudad co ON co.id_ciudad = ho.id_ciudad
  JOIN maestro.hub hd ON hd.id_hub = e.id_hub_destino
  JOIN maestro.ciudad cd ON cd.id_ciudad = hd.id_ciudad
  LEFT JOIN LATERAL (
        SELECT x.tipo_evento, x.id_hub, x.fecha_hora
          FROM operacion.evento_tracking x
         WHERE x.id_envio = e.id_envio
         ORDER BY x.fecha_hora DESC, x.id_evento DESC
         LIMIT 1) ev ON TRUE
  LEFT JOIN maestro.hub h ON h.id_hub = ev.id_hub;

-- Vista analítica de envíos: una fila por envío con dimensiones de negocio
-- (para el rol analista; sin datos personales).
CREATE OR REPLACE VIEW operacion.vw_envio_analitico AS
SELECT e.id_envio,
       e.fecha_registro::DATE                         AS fecha,
       ts.codigo                                      AS servicio,
       ts.modalidad,
       ro.nombre                                      AS region_origen,
       rd.nombre                                      AS region_destino,
       ro.nodo                                        AS nodo_origen,
       co.nombre                                      AS ciudad_origen,
       cd.nombre                                      AS ciudad_destino,
       c.tipo_cliente,
       e.peso_total_kg,
       e.monto_total,
       e.estado_actual,
       e.fecha_compromiso,
       e.fecha_entrega,
       ROUND(EXTRACT(EPOCH FROM e.fecha_entrega - e.fecha_registro) / 3600.0, 1) AS horas_entrega,
       (e.fecha_entrega <= e.fecha_compromiso)       AS a_tiempo
  FROM operacion.envio e
  JOIN maestro.cliente c        ON c.id_cliente = e.id_cliente
  JOIN maestro.tipo_servicio ts ON ts.id_servicio = e.id_servicio
  JOIN maestro.hub ho           ON ho.id_hub = e.id_hub_origen
  JOIN maestro.ciudad co        ON co.id_ciudad = ho.id_ciudad
  JOIN maestro.region ro        ON ro.id_region = co.id_region
  JOIN maestro.hub hd           ON hd.id_hub = e.id_hub_destino
  JOIN maestro.ciudad cd        ON cd.id_ciudad = hd.id_ciudad
  JOIN maestro.region rd        ON rd.id_region = cd.id_region;

-- Vista materializada: permanencia de cada envío en cada hub (llegada -> salida).
-- Es costosa de calcular sobre ~300 mil eventos, por eso se materializa
-- y se refresca periódicamente (p.ej. cada hora con pg_cron o un job externo).
DROP MATERIALIZED VIEW IF EXISTS operacion.mv_permanencia_hub;
CREATE MATERIALIZED VIEW operacion.mv_permanencia_hub AS
-- Una sola pasada con función de ventana: para cada LLEGADA_HUB se toma el
-- siguiente movimiento físico del envío; si es SALIDA_HUB del mismo hub, la
-- diferencia es el tiempo de permanencia (incluye clasificación y espera de despacho).
WITH movimientos AS (
    SELECT id_envio, id_hub, tipo_evento, fecha_hora,
           LEAD(tipo_evento) OVER w AS sig_tipo,
           LEAD(id_hub)      OVER w AS sig_hub,
           LEAD(fecha_hora)  OVER w AS sig_fecha
      FROM operacion.evento_tracking
     WHERE tipo_evento IN ('LLEGADA_HUB', 'SALIDA_HUB')
    WINDOW w AS (PARTITION BY id_envio ORDER BY fecha_hora, id_evento)
)
SELECT id_envio,
       id_hub,
       fecha_hora                                                   AS llegada,
       sig_fecha                                                    AS salida,
       ROUND(EXTRACT(EPOCH FROM sig_fecha - fecha_hora) / 3600.0, 2) AS horas_permanencia
  FROM movimientos
 WHERE tipo_evento = 'LLEGADA_HUB' AND sig_tipo = 'SALIDA_HUB' AND sig_hub = id_hub;

CREATE UNIQUE INDEX ux_mv_permanencia ON operacion.mv_permanencia_hub (id_envio, id_hub, llegada);
CREATE INDEX ix_mv_permanencia_hub ON operacion.mv_permanencia_hub (id_hub, llegada);
