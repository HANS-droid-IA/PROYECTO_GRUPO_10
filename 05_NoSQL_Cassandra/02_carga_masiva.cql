-- =====================================================================
-- Carga masiva con COPY FROM (cqlsh): escribe en paralelo por lotes.
-- El mismo escaneo se carga en eventos_por_envio Y en eventos_por_hub_dia
-- (desnormalización intencional: cada tabla responde una consulta).
-- =====================================================================
USE olva_tracking;

COPY hubs (hub, nombre, tipo, ciudad, capacidad_hora)
  FROM '/scripts/datos/hubs.csv' WITH HEADER = true;

COPY eventos_por_envio (nro_tracking, fecha_hora, id_evento, tipo_evento, hub, ciudad, id_despacho, observacion)
  FROM '/scripts/datos/eventos_por_envio.csv' WITH HEADER = true AND NUMPROCESSES = 4 AND CHUNKSIZE = 2000;

COPY eventos_por_hub_dia (hub, dia, fecha_hora, id_evento, nro_tracking, tipo_evento, servicio)
  FROM '/scripts/datos/eventos_por_hub_dia.csv' WITH HEADER = true AND NUMPROCESSES = 4 AND CHUNKSIZE = 2000;

COPY escaneos_hub_hora (hub, dia, hora, llegadas, salidas, escaneos)
  FROM '/scripts/datos/escaneos_hub_hora.csv' WITH HEADER = true AND NUMPROCESSES = 4;

COPY envios_por_cliente (id_cliente, fecha_registro, nro_tracking, servicio, origen, destino, estado, monto_total)
  FROM '/scripts/datos/envios_por_cliente.csv' WITH HEADER = true AND NUMPROCESSES = 4;

COPY estado_envio (nro_tracking, estado, ultimo_evento, ultimo_hub, fecha_ultimo_evento, fecha_compromiso, servicio, destino)
  FROM '/scripts/datos/estado_envio.csv' WITH HEADER = true AND NUMPROCESSES = 4;
