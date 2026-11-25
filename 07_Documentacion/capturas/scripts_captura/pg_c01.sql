SET search_path = operacion, maestro, public;

SELECT ev.fecha_hora::TIMESTAMP(0)                       AS fecha_hora,
       ev.tipo_evento,
       h.codigo                                          AS hub,
       c.nombre                                          AS ciudad,
       d.codigo_manifiesto                               AS manifiesto,
       COALESCE(d.nro_vuelo, v.placa)                    AS transporte,
       ev.fecha_hora - LAG(ev.fecha_hora) OVER (ORDER BY ev.fecha_hora, ev.id_evento) AS desde_evento_anterior
  FROM evento_tracking ev
  JOIN envio e      ON e.id_envio = ev.id_envio
  JOIN hub h        ON h.id_hub = ev.id_hub
  JOIN ciudad c     ON c.id_ciudad = h.id_ciudad
  LEFT JOIN despacho d ON d.id_despacho = ev.id_despacho
  LEFT JOIN vehiculo v ON v.id_vehiculo = d.id_vehiculo
 WHERE e.nro_tracking = 'OLV2600001112'
 ORDER BY ev.fecha_hora, ev.id_evento;
