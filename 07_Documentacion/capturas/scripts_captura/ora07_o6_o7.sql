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
PROMPT === O6. Línea de tiempo de un envío con LAG (funciones analíticas, igual que PG) ===
SELECT TO_CHAR(ev.fecha_hora, 'DD/MM HH24:MI') AS fecha, ev.tipo_evento, h.codigo AS hub,
       CAST(ev.fecha_hora - LAG(ev.fecha_hora) OVER (ORDER BY ev.fecha_hora, ev.id_evento) AS INTERVAL DAY(1) TO SECOND(0)) AS desde_anterior
  FROM evento_tracking ev JOIN hub h ON h.id_hub = ev.id_hub
 WHERE ev.id_envio = (SELECT id_envio FROM envio WHERE nro_tracking = 'OLV2600000068')
 ORDER BY ev.fecha_hora, ev.id_evento;

PROMPT === O7. Funciones del paquete invocadas desde SQL ===
SELECT pkg_tracking.fn_calcular_tarifa(1, 1, 4, 2.5) AS express_lima_oriente_2_5kg,
       pkg_tracking.fn_calcular_tarifa(3, 1, 5, 12)  AS estandar_lima_sur_12kg
  FROM dual;
SELECT pkg_tracking.fn_estado_sla(e.id_envio) AS estado_sla, COUNT(*) AS envios
  FROM envio e GROUP BY pkg_tracking.fn_estado_sla(e.id_envio) ORDER BY envios DESC;


EXIT
