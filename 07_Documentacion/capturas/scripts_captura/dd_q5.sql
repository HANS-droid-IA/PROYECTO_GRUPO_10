SET enable_partitionwise_join = on;
SET enable_partitionwise_aggregate = on;

-- envío de ejemplo: originado en el NORTE, entregado en el SUR (sus eventos están en 3 nodos)
SELECT e.nro_tracking AS trk_ejemplo
  FROM global.envio e
 WHERE e.nodo = 'NORTE' AND e.estado_actual = 'ENTREGADO'
   AND maestro.fn_nodo_hub(e.id_hub_destino) = 'SUR'
 ORDER BY e.id_envio LIMIT 1 \gset

\echo 'Q5. Reconstrucción vertical: cliente = cliente_fiscal (Lima) ⋈ cliente_contacto (nodo del cliente)'
EXPLAIN (VERBOSE, COSTS OFF)
SELECT * FROM global.cliente WHERE nodo = 'SUR' AND tipo_cliente = 'EMPRESA';
SELECT id_cliente, tipo_documento, nro_documento, nombre_razon_social, telefono, nodo
  FROM global.cliente WHERE nodo = 'SUR' AND tipo_cliente = 'EMPRESA' ORDER BY id_cliente LIMIT 5;

\echo 'Q6. Costo de la distribución: misma consulta global vs. local'
\timing on
SELECT COUNT(*) AS eventos_globales FROM global.evento_tracking WHERE tipo_evento = 'LLEGADA_HUB';
SELECT COUNT(*) AS eventos_solo_lima FROM global.evento_tracking WHERE tipo_evento = 'LLEGADA_HUB' AND nodo = 'LIMA';
\timing off
