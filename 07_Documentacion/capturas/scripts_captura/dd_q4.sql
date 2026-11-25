SET enable_partitionwise_join = on;
SET enable_partitionwise_aggregate = on;

-- envío de ejemplo: originado en el NORTE, entregado en el SUR (sus eventos están en 3 nodos)
SELECT e.nro_tracking AS trk_ejemplo
  FROM global.envio e
 WHERE e.nodo = 'NORTE' AND e.estado_actual = 'ENTREGADO'
   AND maestro.fn_nodo_hub(e.id_hub_destino) = 'SUR'
 ORDER BY e.id_envio LIMIT 1 \gset

\echo 'Q4. JOIN NO co-localizado: tracking de un envío (envío en un nodo, eventos'
\echo '    repartidos en los 3). Se ejecuta en paralelo asíncrono en los nodos.'
EXPLAIN (VERBOSE, COSTS OFF)
SELECT ev.fecha_hora, ev.tipo_evento, ev.id_hub, ev.nodo
  FROM global.envio e JOIN global.evento_tracking ev ON ev.id_envio = e.id_envio
 WHERE e.nro_tracking = :'trk_ejemplo';
SELECT ev.fecha_hora AT TIME ZONE 'America/Lima' AS fecha_hora, ev.tipo_evento, h.codigo AS hub,
       ev.nodo AS nodo_que_almacena_el_evento
  FROM global.envio e
  JOIN global.evento_tracking ev ON ev.id_envio = e.id_envio
  JOIN maestro.hub h ON h.id_hub = ev.id_hub
 WHERE e.nro_tracking = :'trk_ejemplo'
 ORDER BY ev.fecha_hora;
