SET search_path = operacion, maestro, public;

SELECT to_char(date_trunc('month', e.fecha_registro), 'YYYY-MM')              AS mes,
       ts.codigo                                                              AS servicio,
       COUNT(*)                                                               AS entregados,
       ROUND(100.0 * COUNT(*) FILTER (WHERE e.fecha_entrega <= e.fecha_compromiso) / COUNT(*), 1) AS pct_a_tiempo,
       ROUND(AVG(EXTRACT(EPOCH FROM e.fecha_entrega - e.fecha_registro) / 3600)::NUMERIC, 1)     AS horas_prom
  FROM envio e
  JOIN tipo_servicio ts USING (id_servicio)
 WHERE e.estado_actual = 'ENTREGADO'
 GROUP BY 1, 2
 ORDER BY 1, 2;
