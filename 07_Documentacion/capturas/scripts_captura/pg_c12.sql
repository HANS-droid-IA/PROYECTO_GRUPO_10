SET search_path = operacion, maestro, public;

SELECT e.nro_tracking, e.estado_actual, ult.hub, ult.fecha_hora::TIMESTAMP(0) AS ultimo_escaneo,
       date_trunc('hour', TIMESTAMPTZ '2026-10-07 18:00-05' - ult.fecha_hora) AS sin_movimiento,
       EXISTS (SELECT 1 FROM incidencia i WHERE i.id_envio = e.id_envio AND i.tipo = 'PERDIDA') AS tiene_incidencia_perdida
  FROM envio e
  CROSS JOIN LATERAL (
        SELECT h.codigo AS hub, x.fecha_hora
          FROM evento_tracking x JOIN hub h USING (id_hub)
         WHERE x.id_envio = e.id_envio
         ORDER BY x.fecha_hora DESC LIMIT 1) ult
 WHERE e.estado_actual NOT IN ('ENTREGADO', 'DEVUELTO')
   AND ult.fecha_hora < TIMESTAMPTZ '2026-10-07 18:00-05' - INTERVAL '48 hours'
 ORDER BY ult.fecha_hora
 LIMIT 15;
