-- =====================================================================
-- 11.4  Pruebas de acceso: se ejecuta conectado como cada usuario.
-- Las operaciones no permitidas devuelven "Unauthorized".
-- =====================================================================
USE olva_tracking;
SELECT nro_tracking, estado FROM estado_envio WHERE nro_tracking = 'OLV2600000001';
SELECT fecha_registro, nro_tracking, estado FROM envios_por_cliente WHERE id_cliente = 141 LIMIT 2;
UPDATE estado_envio SET estado = 'EN_HUB' WHERE nro_tracking = 'OLV2600029865';
INSERT INTO hubs (hub, nombre, tipo, ciudad, capacidad_hora) VALUES ('HC-TEST', 'Hub prueba', 'HUB_CENTRAL', 'Lima', 10);
DROP TABLE alertas_sla;
