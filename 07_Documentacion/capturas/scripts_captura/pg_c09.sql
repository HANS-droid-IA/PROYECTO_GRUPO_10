SET search_path = operacion, maestro, public;

SELECT e.nro_tracking, ts.codigo AS servicio, ho.codigo AS origen, hd.codigo AS destino,
       e.estado_actual, e.fecha_compromiso::TIMESTAMP(0) AS compromiso,
       fn_estado_sla(e.id_envio, '2026-10-07 18:00-05') AS estado_sla,
       (SELECT h.codigo FROM evento_tracking x JOIN hub h USING (id_hub)
         WHERE x.id_envio = e.id_envio ORDER BY x.fecha_hora DESC LIMIT 1) AS ultima_ubicacion
  FROM envio e
  JOIN tipo_servicio ts USING (id_servicio)
  JOIN hub ho ON ho.id_hub = e.id_hub_origen
  JOIN hub hd ON hd.id_hub = e.id_hub_destino
 WHERE e.estado_actual NOT IN ('ENTREGADO', 'DEVUELTO')
   AND fn_estado_sla(e.id_envio, '2026-10-07 18:00-05') IN ('VENCIDO', 'EN_RIESGO')
 ORDER BY e.fecha_compromiso
 LIMIT 15;
