SET DEFINE OFF
SET SERVEROUTPUT ON
SET LINESIZE 165
SET PAGESIZE 200
SET FEEDBACK OFF
SET TRIMOUT ON
ALTER SESSION SET TIME_ZONE = 'America/Lima';
ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD HH24:MI';
COLUMN servicio FORMAT A20
COLUMN codigo FORMAT A12
COLUMN ruta_jerarquica FORMAT A45
COLUMN red FORMAT A40
COLUMN agencias FORMAT A90
COLUMN nombre_razon_social FORMAT A36
COLUMN tipo_evento FORMAT A16
COLUMN hub FORMAT A11
COLUMN observacion FORMAT A30
COLUMN estado_sla FORMAT A22
COLUMN mensaje FORMAT A80
COLUMN origen FORMAT A36
COLUMN resultado FORMAT A40
PROMPT === O1. Envíos por estado (consulta básica) ===
SELECT estado_actual, COUNT(*) AS envios, ROUND(AVG(monto_total), 2) AS ticket_prom
  FROM envio GROUP BY estado_actual ORDER BY envios DESC;

PROMPT === O2. Cumplimiento de SLA por servicio (JOIN + CASE) ===
SELECT s.codigo AS servicio, COUNT(*) AS entregados,
       ROUND(100 * AVG(CASE WHEN e.fecha_entrega <= e.fecha_compromiso THEN 1 ELSE 0 END), 1) AS pct_a_tiempo,
       ROUND(AVG(EXTRACT(DAY FROM (e.fecha_entrega - e.fecha_registro)) * 24
               + EXTRACT(HOUR FROM (e.fecha_entrega - e.fecha_registro))), 1) AS horas_prom
  FROM envio e JOIN tipo_servicio s ON s.id_servicio = e.id_servicio
 WHERE e.estado_actual = 'ENTREGADO'
 GROUP BY s.codigo ORDER BY s.codigo;


EXIT
