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


EXIT
