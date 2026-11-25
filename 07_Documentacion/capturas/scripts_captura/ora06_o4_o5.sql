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


EXIT
