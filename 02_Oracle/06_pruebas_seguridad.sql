-- =====================================================================
-- 06 - Pruebas de seguridad Oracle (se conecta con cada usuario)
-- =====================================================================
SET LINESIZE 200
SET PAGESIZE 100

PROMPT === Analista: lectura permitida ===
CONNECT u_analista_ora/"<CONTRASENA_CONFIGURADA>"@//localhost:1521/FREEPDB1
SELECT SYS_CONTEXT('USERENV', 'SESSION_USER') AS usuario, COUNT(*) AS envios_visibles FROM olva.envio;
PROMPT --- error esperado: el analista no tiene acceso a CLIENTE (ORA-00942)
SELECT COUNT(*) FROM olva.cliente;
PROMPT --- error esperado: el analista no puede modificar (ORA-01031)
UPDATE olva.envio SET estado_actual = 'ENTREGADO' WHERE ROWNUM = 1;
PROMPT --- error esperado: sin cuota en USERS no puede crear tablas (ORA-01031 / ORA-01950)
CREATE TABLE prueba (x NUMBER);

PROMPT === Operador: escribe solo vía paquete ===
CONNECT u_operador_ora/"<CONTRASENA_CONFIGURADA>"@//localhost:1521/FREEPDB1
PROMPT --- error esperado: INSERT directo en evento_tracking (ORA-01031 / ORA-00942)
INSERT INTO olva.evento_tracking (id_envio, tipo_evento, id_hub, fecha_hora) VALUES (1, 'CLASIFICACION', 1, SYSTIMESTAMP);
PROMPT --- error esperado: la regla de negocio del paquete rechaza la transición (ORA-20010)
EXEC olva.pkg_tracking.sp_registrar_escaneo('OLV2600000001', 'CLASIFICACION', 1);

PROMPT === Perfil: 3 intentos fallidos bloquean la cuenta ===
CONNECT u_analista_ora/"clave_incorrecta"@//localhost:1521/FREEPDB1
CONNECT u_analista_ora/"clave_incorrecta"@//localhost:1521/FREEPDB1
CONNECT u_analista_ora/"clave_incorrecta"@//localhost:1521/FREEPDB1
CONNECT u_analista_ora/"<CONTRASENA_CONFIGURADA>"@//localhost:1521/FREEPDB1
