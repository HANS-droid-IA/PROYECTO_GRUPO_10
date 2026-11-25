SET enable_partitionwise_join = on;
SET enable_partitionwise_aggregate = on;

-- envío de ejemplo: originado en el NORTE, entregado en el SUR (sus eventos están en 3 nodos)
SELECT e.nro_tracking AS trk_ejemplo
  FROM global.envio e
 WHERE e.nodo = 'NORTE' AND e.estado_actual = 'ENTREGADO'
   AND maestro.fn_nodo_hub(e.id_hub_destino) = 'SUR'
 ORDER BY e.id_envio LIMIT 1 \gset

\echo 'Q3. JOIN co-localizado (fragmentación derivada): envio ⋈ paquete se ejecuta'
\echo '    DENTRO de cada nodo (partitionwise join + join pushdown)'
EXPLAIN (VERBOSE, COSTS OFF)
SELECT e.nodo, COUNT(p.id_paquete) AS bultos, ROUND(AVG(p.peso_kg), 2) AS peso_prom
  FROM global.envio e JOIN global.paquete p ON p.id_envio = e.id_envio AND p.nodo = e.nodo
 WHERE e.nodo IN ('NORTE', 'SUR') AND p.fragil
 GROUP BY e.nodo;
SELECT e.nodo, COUNT(p.id_paquete) AS bultos_fragiles, ROUND(AVG(p.peso_kg), 2) AS peso_prom
  FROM global.envio e JOIN global.paquete p ON p.id_envio = e.id_envio AND p.nodo = e.nodo
 WHERE e.nodo IN ('NORTE', 'SUR') AND p.fragil
 GROUP BY e.nodo ORDER BY 1;
