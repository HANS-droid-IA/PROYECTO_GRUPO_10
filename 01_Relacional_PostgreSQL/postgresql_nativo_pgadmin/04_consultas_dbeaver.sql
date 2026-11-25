-- =====================================================================
-- CONSULTAS PARA PRACTICAR EN DBEAVER / pgAdmin - Olva Courier
-- Sirven para olva_courier (Docker, puerto 5440) y olva_courier_pg (Windows, 5432)
-- Ejecutar una consulta: cursor dentro de ella y Ctrl+Enter
-- Ejecutar todo el archivo: Alt+X
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. CONSULTAS BÁSICAS (SELECT, WHERE, ORDER BY, LIMIT)
-- ---------------------------------------------------------------------

-- 1.1 Ver 20 envíos
SELECT nro_tracking, estado_actual, fecha_registro, peso_total_kg, monto_total
FROM operacion.envio
ORDER BY fecha_registro DESC
LIMIT 20;

-- 1.2 Hubs y agencias de la red
SELECT codigo, nombre, tipo, capacidad_hora
FROM maestro.hub
ORDER BY tipo, codigo;

-- 1.3 Servicios que ofrece Olva y su SLA
SELECT codigo, nombre, modalidad, sla_horas, peso_max_kg
FROM maestro.tipo_servicio;

-- 1.4 Envíos entregados que pesan más de 20 kg
SELECT nro_tracking, peso_total_kg, monto_total
FROM operacion.envio
WHERE estado_actual = 'ENTREGADO' AND peso_total_kg > 20
ORDER BY peso_total_kg DESC;

-- ---------------------------------------------------------------------
-- 2. AGRUPACIONES (COUNT, SUM, AVG, GROUP BY, HAVING)
-- ---------------------------------------------------------------------

-- 2.1 Cantidad de envíos por estado
SELECT estado_actual, COUNT(*) AS cantidad
FROM operacion.envio
GROUP BY estado_actual
ORDER BY cantidad DESC;

-- 2.2 Ingresos por tipo de servicio
SELECT s.nombre AS servicio, COUNT(*) AS envios,
       SUM(e.monto_total) AS ingresos, ROUND(AVG(e.monto_total), 2) AS ticket_promedio
FROM operacion.envio e
JOIN maestro.tipo_servicio s ON s.id_servicio = e.id_servicio
GROUP BY s.nombre
ORDER BY ingresos DESC;

-- 2.3 Ciudades destino con más de 1000 envíos
SELECT c.nombre AS ciudad_destino, COUNT(*) AS envios
FROM operacion.envio e
JOIN maestro.hub h    ON h.id_hub = e.id_hub_destino
JOIN maestro.ciudad c ON c.id_ciudad = h.id_ciudad
GROUP BY c.nombre
HAVING COUNT(*) > 1000
ORDER BY envios DESC;

-- ---------------------------------------------------------------------
-- 3. JOINS (varias tablas)
-- ---------------------------------------------------------------------

-- 3.1 Envío con su cliente, destinatario, origen y destino
SELECT e.nro_tracking, cl.nombre_razon_social AS cliente, d.nombre AS destinatario,
       ho.nombre AS origen, hd.nombre AS destino, e.estado_actual
FROM operacion.envio e
JOIN maestro.cliente cl       ON cl.id_cliente = e.id_cliente
JOIN operacion.destinatario d ON d.id_destinatario = e.id_destinatario
JOIN maestro.hub ho           ON ho.id_hub = e.id_hub_origen
JOIN maestro.hub hd           ON hd.id_hub = e.id_hub_destino
LIMIT 20;

-- 3.2 Historial (tracking) de UN envío: cambia el número si quieres
SELECT t.fecha_hora, t.tipo_evento, h.nombre AS lugar, t.observacion
FROM operacion.evento_tracking t
JOIN maestro.hub h ON h.id_hub = t.id_hub
WHERE t.id_envio = (SELECT id_envio FROM operacion.envio WHERE nro_tracking = 'OLV2600000001')
ORDER BY t.fecha_hora;

-- 3.3 Paquetes de un envío
SELECT p.nro_bulto, p.peso_kg, p.largo_cm, p.ancho_cm, p.alto_cm, p.descripcion, p.fragil
FROM operacion.paquete p
JOIN operacion.envio e ON e.id_envio = p.id_envio
WHERE e.nro_tracking = 'OLV2600000001';

-- ---------------------------------------------------------------------
-- 4. CONSULTAS AVANZADAS (subconsultas, CTE, funciones de ventana)
-- ---------------------------------------------------------------------

-- 4.1 Top 10 clientes que más facturan (con ranking)
SELECT cl.nombre_razon_social, SUM(e.monto_total) AS facturado,
       RANK() OVER (ORDER BY SUM(e.monto_total) DESC) AS puesto
FROM operacion.envio e
JOIN maestro.cliente cl ON cl.id_cliente = e.id_cliente
GROUP BY cl.nombre_razon_social
ORDER BY facturado DESC
LIMIT 10;

-- 4.2 Tiempo entre escaneos de un envío (LAG)
SELECT t.fecha_hora, t.tipo_evento, h.codigo AS hub,
       t.fecha_hora - LAG(t.fecha_hora) OVER (ORDER BY t.fecha_hora) AS tiempo_desde_anterior
FROM operacion.evento_tracking t
JOIN maestro.hub h ON h.id_hub = t.id_hub
WHERE t.id_envio = 1
ORDER BY t.fecha_hora;

-- 4.3 Cumplimiento de SLA por servicio (CTE)
WITH entregados AS (
    SELECT s.nombre AS servicio, (e.fecha_entrega <= e.fecha_compromiso) AS a_tiempo
    FROM operacion.envio e
    JOIN maestro.tipo_servicio s ON s.id_servicio = e.id_servicio
    WHERE e.fecha_entrega IS NOT NULL
)
SELECT servicio, COUNT(*) AS entregados,
       ROUND(100.0 * AVG(a_tiempo::int), 1) AS pct_a_tiempo
FROM entregados
GROUP BY servicio
ORDER BY pct_a_tiempo;

-- 4.4 Envíos que nunca tuvieron una incidencia (NOT EXISTS)
SELECT COUNT(*) AS envios_sin_incidencia
FROM operacion.envio e
WHERE NOT EXISTS (SELECT 1 FROM operacion.incidencia i WHERE i.id_envio = e.id_envio);

-- ---------------------------------------------------------------------
-- 5. VISTAS (punto 7)
-- ---------------------------------------------------------------------

-- 5.1 Tracking público (lo que vería un cliente en la web)
SELECT * FROM operacion.vw_tracking_publico WHERE nro_tracking = 'OLV2600000001';

-- 5.2 Vista analítica: SLA por región de origen
SELECT region_origen, COUNT(*) AS envios, ROUND(100.0 * AVG(a_tiempo::int), 1) AS pct_a_tiempo
FROM operacion.vw_envio_analitico
WHERE a_tiempo IS NOT NULL
GROUP BY region_origen
ORDER BY pct_a_tiempo;

-- 5.3 Vista materializada: permanencia en hubs
SELECT * FROM operacion.mv_permanencia_hub LIMIT 20;

-- ---------------------------------------------------------------------
-- 6. FUNCIONES (punto 7.1)
-- ---------------------------------------------------------------------

-- 6.1 Calcular tarifa: servicio 1, región 1 -> región 2, 5 kg, fecha de hoy
SELECT maestro.fn_calcular_tarifa(1::smallint, 1::smallint, 2::smallint, 5.0, CURRENT_DATE) AS tarifa;

-- 6.2 Estado del SLA de un envío
SELECT operacion.fn_estado_sla(1, now()) AS estado_sla;

-- 6.3 Cuellos de botella en hubs (función de tabla)
SELECT * FROM operacion.fn_cuellos_botella('2026-09-01', '2026-10-08', 12) LIMIT 20;

-- ---------------------------------------------------------------------
-- 7. PROCEDIMIENTOS (punto 7.2) - dentro de una transacción que se deshace
--    Selecciona desde BEGIN hasta ROLLBACK y ejecuta con Alt+X
-- ---------------------------------------------------------------------
BEGIN;
DO $$
DECLARE
    v_mir  INTEGER := (SELECT id_hub FROM maestro.hub WHERE codigo = 'AG-LIM-MIR');
    v_sur  INTEGER := (SELECT id_hub FROM maestro.hub WHERE codigo = 'AG-LIM-SUR');
    v_emp  INTEGER := (SELECT MIN(id_empleado) FROM maestro.empleado WHERE id_hub = v_mir AND cargo = 'ATENCION');
    v_cli  INTEGER := (SELECT MIN(id_cliente) FROM maestro.cliente WHERE tipo_cliente = 'EMPRESA');
    v_trk  CHAR(13);
BEGIN
    CALL operacion.sp_registrar_envio(
        v_cli, 'Ana Torres Ríos', '45871236', '987654321', 'Av. Primavera 1450, Surco',
        3::SMALLINT, v_mir, v_sur,
        '[{"peso": 2.3, "largo": 40, "ancho": 30, "alto": 20, "descripcion": "Repuestos"}]',
        'CREDITO', v_emp, v_trk);
    RAISE NOTICE 'Envío registrado con tracking %', v_trk;
END $$;
SELECT nro_tracking, estado_actual, peso_total_kg, monto_total
FROM operacion.envio ORDER BY id_envio DESC LIMIT 1;
ROLLBACK;

-- ---------------------------------------------------------------------
-- 8. CATÁLOGO: ver qué objetos tiene la base
-- ---------------------------------------------------------------------

-- 8.1 Tablas y cantidad de filas
SELECT schemaname, relname AS tabla, n_live_tup AS filas
FROM pg_stat_user_tables
ORDER BY schemaname, relname;

-- 8.2 Funciones y procedimientos
SELECT n.nspname AS esquema, p.proname AS nombre,
       CASE p.prokind WHEN 'f' THEN 'función' WHEN 'p' THEN 'procedimiento' END AS tipo
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('maestro', 'operacion')
ORDER BY tipo, nombre;

-- 8.3 Ver el código de una función
SELECT pg_get_functiondef('maestro.fn_calcular_tarifa'::regproc);
