SET search_path = operacion, maestro, public;

SELECT ho.codigo || ' -> ' || hd.codigo                                                AS ruta,
       r.modalidad,
       COUNT(*)                                                                         AS despachos,
       ROUND(AVG(EXTRACT(EPOCH FROM d.fecha_salida_real - d.fecha_salida_prog) / 60)::NUMERIC, 1) AS demora_salida_min,
       ROUND(100.0 * AVG((d.fecha_salida_real - d.fecha_salida_prog > INTERVAL '60 minutes')::INT), 1) AS pct_demora_mayor_1h,
       ROUND(AVG(EXTRACT(EPOCH FROM d.fecha_llegada_real - d.fecha_salida_real) / 3600 - r.tiempo_estimado_horas)::NUMERIC, 2) AS desvio_viaje_h
  FROM despacho d
  JOIN ruta r ON r.id_ruta = d.id_ruta
  JOIN hub ho ON ho.id_hub = r.id_hub_origen
  JOIN hub hd ON hd.id_hub = r.id_hub_destino
 WHERE d.estado = 'ARRIBADO' AND ho.tipo <> 'AGENCIA' AND hd.tipo <> 'AGENCIA'
 GROUP BY 1, 2
HAVING COUNT(*) >= 30
 ORDER BY desvio_viaje_h DESC
 LIMIT 10;
