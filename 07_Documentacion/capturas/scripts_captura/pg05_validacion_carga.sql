SELECT tabla, filas FROM (
SELECT 0 AS o, 'maestro.region' AS tabla, COUNT(*) AS filas FROM maestro.region
UNION ALL SELECT 1 AS o, 'maestro.ciudad' AS tabla, COUNT(*) AS filas FROM maestro.ciudad
UNION ALL SELECT 2 AS o, 'maestro.hub' AS tabla, COUNT(*) AS filas FROM maestro.hub
UNION ALL SELECT 3 AS o, 'maestro.tipo_servicio' AS tabla, COUNT(*) AS filas FROM maestro.tipo_servicio
UNION ALL SELECT 4 AS o, 'maestro.tarifa' AS tabla, COUNT(*) AS filas FROM maestro.tarifa
UNION ALL SELECT 5 AS o, 'maestro.ruta' AS tabla, COUNT(*) AS filas FROM maestro.ruta
UNION ALL SELECT 6 AS o, 'maestro.vehiculo' AS tabla, COUNT(*) AS filas FROM maestro.vehiculo
UNION ALL SELECT 7 AS o, 'maestro.empleado' AS tabla, COUNT(*) AS filas FROM maestro.empleado
UNION ALL SELECT 8 AS o, 'maestro.cliente' AS tabla, COUNT(*) AS filas FROM maestro.cliente
UNION ALL SELECT 9 AS o, 'operacion.destinatario' AS tabla, COUNT(*) AS filas FROM operacion.destinatario
UNION ALL SELECT 10 AS o, 'operacion.envio' AS tabla, COUNT(*) AS filas FROM operacion.envio
UNION ALL SELECT 11 AS o, 'operacion.paquete' AS tabla, COUNT(*) AS filas FROM operacion.paquete
UNION ALL SELECT 12 AS o, 'operacion.comprobante' AS tabla, COUNT(*) AS filas FROM operacion.comprobante
UNION ALL SELECT 13 AS o, 'operacion.despacho' AS tabla, COUNT(*) AS filas FROM operacion.despacho
UNION ALL SELECT 14 AS o, 'operacion.despacho_envio' AS tabla, COUNT(*) AS filas FROM operacion.despacho_envio
UNION ALL SELECT 15 AS o, 'operacion.evento_tracking' AS tabla, COUNT(*) AS filas FROM operacion.evento_tracking
UNION ALL SELECT 16 AS o, 'operacion.intento_entrega' AS tabla, COUNT(*) AS filas FROM operacion.intento_entrega
UNION ALL SELECT 17 AS o, 'operacion.incidencia' AS tabla, COUNT(*) AS filas FROM operacion.incidencia
) x ORDER BY o;
