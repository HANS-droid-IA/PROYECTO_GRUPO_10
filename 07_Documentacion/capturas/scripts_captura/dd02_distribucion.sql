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
