SET search_path = operacion, maestro, public;

WITH paso_hc AS (
    SELECT DISTINCT ON (id_envio) id_envio, horas_permanencia
      FROM mv_permanencia_hub
     WHERE id_hub = (SELECT id_hub FROM hub WHERE codigo = 'HC-LIM')
     ORDER BY id_envio, llegada
)
SELECT ts.modalidad,
       CASE WHEN p.horas_permanencia > 12 THEN 'Más de 12 h en HC' ELSE 'Hasta 12 h en HC' END AS permanencia_hc,
       COUNT(*)                                                                            AS envios,
       ROUND(AVG(p.horas_permanencia), 1)                                                  AS horas_hc_prom,
       ROUND(100.0 * AVG((e.fecha_entrega <= e.fecha_compromiso)::INT), 1)                 AS pct_a_tiempo
  FROM paso_hc p
  JOIN envio e USING (id_envio)
  JOIN tipo_servicio ts USING (id_servicio)
 WHERE e.estado_actual = 'ENTREGADO'
 GROUP BY 1, 2
 ORDER BY 1, 2;
