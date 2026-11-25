-- Demostración rápida de Cassandra para la exposición (solo lectura)
USE olva_tracking;
PAGING OFF;

-- Tablas del keyspace (una por consulta)
DESCRIBE TABLES;

-- Q1. Historial de un envío: una sola partición, ya ordenada por fecha
SELECT fecha_hora, tipo_evento, hub, ciudad FROM eventos_por_envio WHERE nro_tracking = 'OLV2600000001';

-- Q3. Saturación del Hub Central el 06/10 desde las 18:00 (capacidad 50 por hora)
SELECT hora, llegadas, salidas, escaneos FROM escaneos_hub_hora WHERE hub = 'HC-LIM' AND dia = '2026-10-06' AND hora >= 18;

-- Q4. Últimos 5 envíos de un cliente
SELECT fecha_registro, nro_tracking, servicio, destino, estado FROM envios_por_cliente WHERE id_cliente = 141 LIMIT 5;
