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

EXIT
