-- =====================================================================
-- 11.3  Consultas CQL representativas (cada una lee UNA partición)
-- =====================================================================
USE olva_tracking;
PAGING OFF;
TRACING OFF;

-- ---------------------------------------------------------------------
-- Q1. Historial (tracking) de un envío: una partición, ya ordenada por fecha
SELECT fecha_hora, tipo_evento, hub, ciudad
  FROM eventos_por_envio
 WHERE nro_tracking = 'OLV2600000001';

-- ---------------------------------------------------------------------
-- Q2. Escaneos del Hub Central el 06/10 entre las 20:00 y las 21:00 (hora Lima)
--     rango sobre la columna de clustering dentro de la partición (hub, dia)
SELECT fecha_hora, tipo_evento, nro_tracking, servicio
  FROM eventos_por_hub_dia
 WHERE hub = 'HC-LIM' AND dia = '2026-10-06'
   AND fecha_hora >= '2026-10-07 01:00:00+0000' AND fecha_hora < '2026-10-07 02:00:00+0000'
 LIMIT 12;

SELECT COUNT(*) AS escaneos_20h
  FROM eventos_por_hub_dia
 WHERE hub = 'HC-LIM' AND dia = '2026-10-06'
   AND fecha_hora >= '2026-10-07 01:00:00+0000' AND fecha_hora < '2026-10-07 02:00:00+0000';

-- ---------------------------------------------------------------------
-- Q3. Saturación horaria del Hub Central (capacidad 50 envíos/h)
SELECT capacidad_hora FROM hubs WHERE hub = 'HC-LIM';
SELECT hora, llegadas, salidas, escaneos
  FROM escaneos_hub_hora
 WHERE hub = 'HC-LIM' AND dia = '2026-10-06'
   AND hora >= 18;

-- picos sobre capacidad en varios días: IN sobre la clave de partición
SELECT dia, hora, llegadas
  FROM escaneos_hub_hora
 WHERE hub = 'HC-LIM' AND dia IN ('2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04', '2026-10-05', '2026-10-06')
   AND hora = 20;

-- ---------------------------------------------------------------------
-- Q4. Portal del cliente: sus 8 envíos más recientes (orden DESC ya almacenado)
SELECT fecha_registro, nro_tracking, servicio, destino, estado, monto_total
  FROM envios_por_cliente
 WHERE id_cliente = 141
 LIMIT 8;

-- ---------------------------------------------------------------------
-- Q5. Estado actual de un envío y actualización por escaneo (UPSERT)
SELECT * FROM estado_envio WHERE nro_tracking = 'OLV2600029865';

--   un escaneo nuevo: en Cassandra INSERT y UPDATE sobrescriben (último timestamp gana)
UPDATE estado_envio
   SET estado = 'EN_REPARTO', ultimo_evento = 'EN_REPARTO', fecha_ultimo_evento = toTimestamp(now())
 WHERE nro_tracking = 'OLV2600029865';

--   transacción ligera (LWT, Paxos): solo cambia si el estado esperado coincide
UPDATE estado_envio SET estado = 'ENTREGADO', ultimo_evento = 'ENTREGA'
 WHERE nro_tracking = 'OLV2600029865' IF estado = 'EN_HUB';
UPDATE estado_envio SET estado = 'ENTREGADO', ultimo_evento = 'ENTREGA'
 WHERE nro_tracking = 'OLV2600029865' IF estado = 'EN_REPARTO';
SELECT nro_tracking, estado, ultimo_evento, ultimo_hub FROM estado_envio WHERE nro_tracking = 'OLV2600029865';

--   consulta por índice secundario (aceptable: tabla pequeña y baja cardinalidad)
SELECT nro_tracking, ultimo_hub, fecha_compromiso FROM estado_envio WHERE estado = 'EN_TRANSITO' LIMIT 5;

-- ---------------------------------------------------------------------
-- Q6. BATCH registrado: un escaneo se escribe atómicamente en las tablas desnormalizadas
BEGIN BATCH
  INSERT INTO eventos_por_envio (nro_tracking, fecha_hora, id_evento, tipo_evento, hub, ciudad)
       VALUES ('OLV2600029865', '2026-10-07 22:50:00+0000', 900000001, 'SALIDA_HUB', 'HC-LIM', 'Callao');
  INSERT INTO eventos_por_hub_dia (hub, dia, fecha_hora, id_evento, nro_tracking, tipo_evento, servicio)
       VALUES ('HC-LIM', '2026-10-07', '2026-10-07 22:50:00+0000', 900000001, 'OLV2600029865', 'SALIDA_HUB', 'ECONOMICO_TERRESTRE');
APPLY BATCH;

--   contador en línea: solo UPDATE con incremento
UPDATE contador_escaneos SET total = total + 1 WHERE hub = 'HC-LIM' AND dia = '2026-10-07' AND tipo_evento = 'LLEGADA_HUB';
UPDATE contador_escaneos SET total = total + 3 WHERE hub = 'HC-LIM' AND dia = '2026-10-07' AND tipo_evento = 'LLEGADA_HUB';
UPDATE contador_escaneos SET total = total + 2 WHERE hub = 'HC-LIM' AND dia = '2026-10-07' AND tipo_evento = 'SALIDA_HUB';
SELECT * FROM contador_escaneos WHERE hub = 'HC-LIM' AND dia = '2026-10-07';

-- ---------------------------------------------------------------------
-- Q7. Datos con caducidad (TTL): la alerta desaparece sola
INSERT INTO alertas_sla (hub, fecha_alerta, nro_tracking, nivel, mensaje)
     VALUES ('HC-LIM', toTimestamp(now()), 'OLV2600029215', 'CRITICO', 'Permanencia > 12 h en Hub Central');
INSERT INTO alertas_sla (hub, fecha_alerta, nro_tracking, nivel, mensaje)
     VALUES ('HC-LIM', toTimestamp(now()), 'OLV2600028788', 'AVISO', 'Compromiso vence en 2 h') USING TTL 3600;
SELECT nro_tracking, nivel, mensaje, TTL(mensaje) AS segundos_restantes, WRITETIME(mensaje) AS escrito_us
  FROM alertas_sla WHERE hub = 'HC-LIM';

-- ---------------------------------------------------------------------
-- Q8. Funciones de agregación dentro de UNA partición
SELECT COUNT(*) AS eventos, MIN(fecha_hora) AS primero, MAX(fecha_hora) AS ultimo
  FROM eventos_por_hub_dia WHERE hub = 'HC-LIM' AND dia = '2026-10-06';
SELECT SUM(llegadas) AS llegadas_dia, MAX(llegadas) AS pico_hora, AVG(llegadas) AS prom_hora
  FROM escaneos_hub_hora WHERE hub = 'HC-LIM' AND dia = '2026-10-06';

-- ---------------------------------------------------------------------
-- Q9. Lo que Cassandra NO hace (por diseño): filtrar sin la clave de partición.
--     Se rechaza porque obligaría a leer todos los nodos.
SELECT * FROM eventos_por_envio WHERE tipo_evento = 'DEVOLUCION' LIMIT 5;

-- limpieza de los cambios de prueba
DELETE FROM eventos_por_envio WHERE nro_tracking = 'OLV2600029865' AND fecha_hora = '2026-10-07 22:50:00+0000' AND id_evento = 900000001;
DELETE FROM eventos_por_hub_dia WHERE hub = 'HC-LIM' AND dia = '2026-10-07' AND fecha_hora = '2026-10-07 22:50:00+0000' AND id_evento = 900000001;
INSERT INTO estado_envio (nro_tracking, estado, ultimo_evento, ultimo_hub, fecha_ultimo_evento, fecha_compromiso, servicio, destino)
     VALUES ('OLV2600029865', 'EN_HUB', 'CLASIFICACION', 'HC-LIM', '2026-10-07 22:30:30+0000', '2026-10-13 01:00:00+0000', 'ECONOMICO_TERRESTRE', 'Arequipa');
TRUNCATE contador_escaneos;
