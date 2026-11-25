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
