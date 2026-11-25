-- =====================================================================
-- 04 - Consultas básicas, consultas propias de Oracle y pruebas PL/SQL
-- =====================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100
SET TRIMSPOOL ON
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

PROMPT === O3. [ORACLE] Red logística jerárquica con CONNECT BY (PG: WITH RECURSIVE) ===
SELECT LPAD(' ', 2 * (LEVEL - 1)) || codigo AS red,
       tipo, LEVEL AS nivel,
       SYS_CONNECT_BY_PATH(codigo, '/') AS ruta_jerarquica
  FROM hub
 WHERE LEVEL <= 2 OR codigo LIKE 'AG-AQP%' OR codigo LIKE 'AG-TCQ%'
 START WITH id_hub_padre IS NULL
CONNECT BY PRIOR id_hub = id_hub_padre
 ORDER SIBLINGS BY codigo;

PROMPT === O4. [ORACLE] Agencias por hub con LISTAGG (PG: STRING_AGG) ===
SELECT p.codigo AS hub, COUNT(*) AS n_agencias,
       LISTAGG(h.codigo, ', ') WITHIN GROUP (ORDER BY h.codigo) AS agencias
  FROM hub h JOIN hub p ON p.id_hub = h.id_hub_padre
 WHERE h.tipo = 'AGENCIA'
 GROUP BY p.codigo ORDER BY n_agencias DESC;

PROMPT === O5. Top 5 clientes por facturación: FETCH FIRST (estándar) vs ROWNUM (clásico Oracle) ===
SELECT c.nombre_razon_social, COUNT(*) AS envios, SUM(e.monto_total) AS facturado
  FROM envio e JOIN cliente c ON c.id_cliente = e.id_cliente
 GROUP BY c.nombre_razon_social
 ORDER BY facturado DESC
 FETCH FIRST 5 ROWS ONLY;

SELECT * FROM (
    SELECT c.nombre_razon_social, SUM(e.monto_total) AS facturado
      FROM envio e JOIN cliente c ON c.id_cliente = e.id_cliente
     GROUP BY c.nombre_razon_social ORDER BY facturado DESC
) WHERE ROWNUM <= 5;

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

PROMPT === O8. [ORACLE] La cadena vacía es NULL (en PostgreSQL '' y NULL son distintos) ===
SELECT CASE WHEN '' IS NULL THEN 'En Oracle: '''' IS NULL = TRUE' ELSE 'distinto' END AS resultado FROM dual;
SELECT NVL(NULL, 'NVL') AS nvl_oracle, COALESCE(NULL, 'COALESCE') AS coalesce_estandar FROM dual;

PROMPT === O9. [ORACLE] MERGE: upsert de tarifa (PG: INSERT ... ON CONFLICT DO UPDATE) ===
MERGE INTO tarifa t
USING (SELECT 1 AS id_servicio, 1 AS ro, 4 AS rd, 34.00 AS base, 7.00 AS kg, DATE '2026-11-01' AS desde FROM dual) s
   ON (t.id_servicio = s.id_servicio AND t.id_region_origen = s.ro AND t.id_region_destino = s.rd AND t.vigente_desde = s.desde)
 WHEN MATCHED THEN UPDATE SET t.precio_base = s.base, t.precio_kg_adicional = s.kg
 WHEN NOT MATCHED THEN INSERT (id_servicio, id_region_origen, id_region_destino, precio_base, precio_kg_adicional, vigente_desde)
                       VALUES (s.id_servicio, s.ro, s.rd, s.base, s.kg, s.desde);
SELECT pkg_tracking.fn_calcular_tarifa(1, 1, 4, 2.5, DATE '2026-10-15') AS tarifa_octubre,
       pkg_tracking.fn_calcular_tarifa(1, 1, 4, 2.5, DATE '2026-11-15') AS tarifa_noviembre
  FROM dual;
ROLLBACK;

PROMPT === P1. Prueba del paquete + trigger: nuevo envío y escaneos ===
INSERT INTO envio (nro_tracking, id_cliente, id_servicio, id_hub_origen, id_hub_destino, fecha_compromiso, peso_total_kg, monto_total)
VALUES ('OLV2699999999', (SELECT MIN(id_cliente) FROM cliente), 1,
        (SELECT id_hub FROM hub WHERE codigo = 'AG-LIM-MIR'), (SELECT id_hub FROM hub WHERE codigo = 'AG-AQP-01'),
        SYSTIMESTAMP + INTERVAL '2' DAY, 2.5, pkg_tracking.fn_calcular_tarifa(1, 1, 5, 2.5));
EXEC pkg_tracking.sp_registrar_escaneo('OLV2699999999', 'ADMISION', 10, 'Admisión en agencia');
SELECT nro_tracking, estado_actual, monto_total FROM envio WHERE nro_tracking = 'OLV2699999999';

PROMPT --- error esperado: transición inválida (ENTREGA desde ADMITIDO)
EXEC pkg_tracking.sp_registrar_escaneo('OLV2699999999', 'ENTREGA', 10);
PROMPT --- error esperado: tracking inexistente
EXEC pkg_tracking.sp_registrar_escaneo('OLV0000000000', 'ADMISION', 10);
PROMPT --- error esperado: peso excede el máximo del servicio
SELECT pkg_tracking.fn_calcular_tarifa(2, 1, 4, 3) FROM dual;

PROMPT === P2. [ORACLE] Transacción autónoma: se hace ROLLBACK, pero el log de errores persiste ===
ROLLBACK;
SELECT COUNT(*) AS envio_prueba_tras_rollback FROM envio WHERE nro_tracking = 'OLV2699999999';
SELECT origen, mensaje FROM log_error ORDER BY id_log;
