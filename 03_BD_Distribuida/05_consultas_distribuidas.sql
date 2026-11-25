-- =====================================================================
-- BD Distribuida - 05: procesamiento de consultas distribuidas
--   DESCOMPOSICIÓN : la consulta global se traduce a álgebra sobre relaciones globales
--   LOCALIZACIÓN   : las relaciones globales se reemplazan por sus fragmentos y se
--                    eliminan los fragmentos cuyo predicado contradice el filtro
--                    (poda de particiones)
--   OPTIMIZACIÓN   : se empujan selecciones, proyecciones, joins y agregaciones a los
--                    nodos (Remote SQL) para minimizar los datos transferidos
-- Se muestra el plan (EXPLAIN VERBOSE) y luego el resultado real de cada consulta.
-- =====================================================================
\pset footer off
SET enable_partitionwise_join = on;
SET enable_partitionwise_aggregate = on;

-- envío de ejemplo: originado en el NORTE, entregado en el SUR (sus eventos están en 3 nodos)
SELECT e.nro_tracking AS trk_ejemplo
  FROM global.envio e
 WHERE e.nodo = 'NORTE' AND e.estado_actual = 'ENTREGADO'
   AND maestro.fn_nodo_hub(e.id_hub_destino) = 'SUR'
 ORDER BY e.id_envio LIMIT 1 \gset

\echo '================================================================='
\echo 'Q1. LOCALIZACIÓN (poda de fragmentos): envíos del Sur retrasados en setiembre'
\echo '    σ(nodo=SUR ∧ mes=09 ∧ entrega>compromiso)(envio) -> solo envio_sur'
\echo '================================================================='
EXPLAIN (VERBOSE, COSTS OFF)
SELECT COUNT(*) FROM global.envio
 WHERE nodo = 'SUR' AND fecha_registro >= '2026-09-01' AND fecha_registro < '2026-10-01'
   AND fecha_entrega > fecha_compromiso;
SELECT COUNT(*) AS envios_sur_retrasados_setiembre FROM global.envio
 WHERE nodo = 'SUR' AND fecha_registro >= '2026-09-01' AND fecha_registro < '2026-10-01'
   AND fecha_entrega > fecha_compromiso;

\echo '================================================================='
\echo 'Q2. OPTIMIZACIÓN - agregación distribuida (partitionwise aggregate):'
\echo '    cada nodo calcula su GROUP BY y solo viaja el resumen'
\echo '================================================================='
EXPLAIN (VERBOSE, COSTS OFF)
SELECT nodo, estado_actual, COUNT(*), SUM(monto_total) FROM global.envio GROUP BY nodo, estado_actual;
SELECT nodo, estado_actual, COUNT(*) AS envios, SUM(monto_total) AS ingresos
  FROM global.envio GROUP BY nodo, estado_actual ORDER BY nodo, envios DESC;

\echo '================================================================='
\echo 'Q3. JOIN co-localizado (fragmentación derivada): envio ⋈ paquete se ejecuta'
\echo '    DENTRO de cada nodo (partitionwise join + join pushdown)'
\echo '================================================================='
EXPLAIN (VERBOSE, COSTS OFF)
SELECT e.nodo, COUNT(p.id_paquete) AS bultos, ROUND(AVG(p.peso_kg), 2) AS peso_prom
  FROM global.envio e JOIN global.paquete p ON p.id_envio = e.id_envio AND p.nodo = e.nodo
 WHERE e.nodo IN ('NORTE', 'SUR') AND p.fragil
 GROUP BY e.nodo;
SELECT e.nodo, COUNT(p.id_paquete) AS bultos_fragiles, ROUND(AVG(p.peso_kg), 2) AS peso_prom
  FROM global.envio e JOIN global.paquete p ON p.id_envio = e.id_envio AND p.nodo = e.nodo
 WHERE e.nodo IN ('NORTE', 'SUR') AND p.fragil
 GROUP BY e.nodo ORDER BY 1;

\echo '================================================================='
\echo 'Q4. JOIN NO co-localizado: tracking de un envío (envío en un nodo, eventos'
\echo '    repartidos en los 3). Se ejecuta en paralelo asíncrono en los nodos.'
\echo '================================================================='
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

\echo '================================================================='
\echo 'Q5. Reconstrucción vertical: cliente = cliente_fiscal (Lima) ⋈ cliente_contacto (nodo del cliente)'
\echo '================================================================='
EXPLAIN (VERBOSE, COSTS OFF)
SELECT * FROM global.cliente WHERE nodo = 'SUR' AND tipo_cliente = 'EMPRESA';
SELECT id_cliente, tipo_documento, nro_documento, nombre_razon_social, telefono, nodo
  FROM global.cliente WHERE nodo = 'SUR' AND tipo_cliente = 'EMPRESA' ORDER BY id_cliente LIMIT 5;

\echo '================================================================='
\echo 'Q6. Costo de la distribución: misma consulta global vs. local'
\echo '================================================================='
\timing on
SELECT COUNT(*) AS eventos_globales FROM global.evento_tracking WHERE tipo_evento = 'LLEGADA_HUB';
SELECT COUNT(*) AS eventos_solo_lima FROM global.evento_tracking WHERE tipo_evento = 'LLEGADA_HUB' AND nodo = 'LIMA';
\timing off
