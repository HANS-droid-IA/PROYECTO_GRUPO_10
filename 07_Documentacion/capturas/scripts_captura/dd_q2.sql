SET enable_partitionwise_join = on;
SET enable_partitionwise_aggregate = on;

-- envío de ejemplo: originado en el NORTE, entregado en el SUR (sus eventos están en 3 nodos)
SELECT e.nro_tracking AS trk_ejemplo
  FROM global.envio e
 WHERE e.nodo = 'NORTE' AND e.estado_actual = 'ENTREGADO'
   AND maestro.fn_nodo_hub(e.id_hub_destino) = 'SUR'
 ORDER BY e.id_envio LIMIT 1 \gset

\echo 'Q2. OPTIMIZACIÓN - agregación distribuida (partitionwise aggregate):'
\echo '    cada nodo calcula su GROUP BY y solo viaja el resumen'
EXPLAIN (VERBOSE, COSTS OFF)
SELECT nodo, estado_actual, COUNT(*), SUM(monto_total) FROM global.envio GROUP BY nodo, estado_actual;
SELECT nodo, estado_actual, COUNT(*) AS envios, SUM(monto_total) AS ingresos
  FROM global.envio GROUP BY nodo, estado_actual ORDER BY nodo, envios DESC;
