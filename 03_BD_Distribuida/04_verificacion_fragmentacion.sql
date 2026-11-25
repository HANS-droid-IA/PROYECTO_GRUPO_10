-- =====================================================================
-- BD Distribuida - 04: verificación de las reglas de corrección de la
-- fragmentación (completitud, reconstrucción y disyunción)
-- =====================================================================
\pset footer off

\echo '=== Catálogo de fragmentos (esquema de asignación) ==='
SELECT * FROM global.catalogo_fragmentos;

\echo '=== Distribución de filas por nodo ==='
SELECT 'envio' AS tabla, nodo, COUNT(*) AS filas FROM global.envio GROUP BY nodo
UNION ALL SELECT 'paquete', nodo, COUNT(*) FROM global.paquete GROUP BY nodo
UNION ALL SELECT 'evento_tracking', nodo, COUNT(*) FROM global.evento_tracking GROUP BY nodo
UNION ALL SELECT 'cliente_contacto', nodo, COUNT(*) FROM global.cliente_contacto GROUP BY nodo
ORDER BY 1, 2;

\echo '=== 1) COMPLETITUD: cada fila del origen está en algún fragmento ==='
SELECT 'envio' AS tabla, (SELECT COUNT(*) FROM origen.envio) AS origen, (SELECT COUNT(*) FROM global.envio) AS fragmentos
UNION ALL SELECT 'paquete', (SELECT COUNT(*) FROM origen.paquete), (SELECT COUNT(*) FROM global.paquete)
UNION ALL SELECT 'evento_tracking', (SELECT COUNT(*) FROM origen.evento_tracking), (SELECT COUNT(*) FROM global.evento_tracking)
UNION ALL SELECT 'cliente (VF1 fiscal)', (SELECT COUNT(*) FROM origen.cliente), (SELECT COUNT(*) FROM operacion.cliente_fiscal)
UNION ALL SELECT 'cliente (VF2 contacto)', (SELECT COUNT(*) FROM origen.cliente), (SELECT COUNT(*) FROM global.cliente_contacto);

\echo '=== 2) DISYUNCIÓN: ninguna clave aparece en más de un fragmento ==='
SELECT 'envio' AS tabla, COUNT(*) AS claves_duplicadas
  FROM (SELECT id_envio FROM global.envio GROUP BY id_envio HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'evento_tracking', COUNT(*) FROM (SELECT id_evento FROM global.evento_tracking GROUP BY id_evento HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'cliente_contacto', COUNT(*) FROM (SELECT id_cliente FROM global.cliente_contacto GROUP BY id_cliente HAVING COUNT(*) > 1) d;

\echo '=== 3) RECONSTRUCCIÓN horizontal: (frag_LIMA ∪ frag_NORTE ∪ frag_SUR) = envio original ==='
SELECT COUNT(*) AS filas_diferentes
  FROM (
    (SELECT id_envio, nro_tracking, estado_actual, monto_total, fecha_entrega FROM origen.envio
     EXCEPT
     SELECT id_envio, nro_tracking, estado_actual, monto_total, fecha_entrega FROM global.envio)
    UNION ALL
    (SELECT id_envio, nro_tracking, estado_actual, monto_total, fecha_entrega FROM global.envio
     EXCEPT
     SELECT id_envio, nro_tracking, estado_actual, monto_total, fecha_entrega FROM origen.envio)
  ) dif;

\echo '=== 3) RECONSTRUCCIÓN vertical: cliente_fiscal ⋈ cliente_contacto = cliente original ==='
SELECT COUNT(*) AS filas_diferentes
  FROM (
    (SELECT id_cliente, tipo_cliente, nro_documento, nombre_razon_social, email, id_ciudad FROM origen.cliente
     EXCEPT
     SELECT id_cliente, tipo_cliente, nro_documento, nombre_razon_social, email, id_ciudad FROM global.cliente)
    UNION ALL
    (SELECT id_cliente, tipo_cliente, nro_documento, nombre_razon_social, email, id_ciudad FROM global.cliente
     EXCEPT
     SELECT id_cliente, tipo_cliente, nro_documento, nombre_razon_social, email, id_ciudad FROM origen.cliente)
  ) dif;

\echo '=== Integridad del predicado: un nodo rechaza filas que no le pertenecen ==='
\echo '--- error esperado: insertar en el fragmento SUR un envío cuyo origen es Lima'
\set ON_ERROR_STOP off
INSERT INTO global.envio_sur
SELECT id_envio + 9000000, 'OLV9' || SUBSTRING(nro_tracking FROM 5), id_cliente, id_destinatario, id_servicio, id_hub_origen,
       id_hub_destino, direccion_entrega, fecha_registro, fecha_compromiso, estado_actual, peso_total_kg, valor_declarado,
       monto_total, fecha_entrega, 'SUR'
  FROM global.envio WHERE nodo = 'LIMA' LIMIT 1;
