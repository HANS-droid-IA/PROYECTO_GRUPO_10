SET search_path = operacion, maestro, public;
\echo '=== F1 maestro.fn_calcular_tarifa: tarifas Lima -> Oriente por servicio y peso ==='
SELECT ts.codigo AS servicio, r1.nombre AS origen, r2.nombre AS destino, p.peso AS peso_kg,
       fn_calcular_tarifa(ts.id_servicio, r1.id_region, r2.id_region, p.peso) AS tarifa_soles
  FROM tipo_servicio ts CROSS JOIN (VALUES (0.4), (2.5), (12.0)) p(peso)
  JOIN region r1 ON r1.codigo = 'LIM' JOIN region r2 ON r2.codigo = 'ORI'
 WHERE p.peso <= ts.peso_max_kg ORDER BY 1, 4;
\echo '=== F2 operacion.fn_estado_sla: clasificación de los envíos al corte 2026-10-07 18:00 ==='
SELECT fn_estado_sla(id_envio, '2026-10-07 18:00-05') AS estado_sla, COUNT(*) AS envios
  FROM envio GROUP BY 1 ORDER BY 2 DESC;
\echo '--- Error controlado: peso mayor al permitido para SOBRE_AEREO (máx. 0,5 kg)'
SELECT fn_calcular_tarifa(2::SMALLINT, 1::SMALLINT, 4::SMALLINT, 3.0);
