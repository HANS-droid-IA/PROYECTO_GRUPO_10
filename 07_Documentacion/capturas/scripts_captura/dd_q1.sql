SET enable_partitionwise_join = on;
SET enable_partitionwise_aggregate = on;

-- envío de ejemplo: originado en el NORTE, entregado en el SUR (sus eventos están en 3 nodos)
SELECT e.nro_tracking AS trk_ejemplo
  FROM global.envio e
 WHERE e.nodo = 'NORTE' AND e.estado_actual = 'ENTREGADO'
   AND maestro.fn_nodo_hub(e.id_hub_destino) = 'SUR'
 ORDER BY e.id_envio LIMIT 1 \gset

\echo 'Q1. LOCALIZACIÓN (poda de fragmentos): envíos del Sur retrasados en setiembre'
\echo '    σ(nodo=SUR ∧ mes=09 ∧ entrega>compromiso)(envio) -> solo envio_sur'
EXPLAIN (VERBOSE, COSTS OFF)
SELECT COUNT(*) FROM global.envio
 WHERE nodo = 'SUR' AND fecha_registro >= '2026-09-01' AND fecha_registro < '2026-10-01'
   AND fecha_entrega > fecha_compromiso;
SELECT COUNT(*) AS envios_sur_retrasados_setiembre FROM global.envio
 WHERE nodo = 'SUR' AND fecha_registro >= '2026-09-01' AND fecha_registro < '2026-10-01'
   AND fecha_entrega > fecha_compromiso;
