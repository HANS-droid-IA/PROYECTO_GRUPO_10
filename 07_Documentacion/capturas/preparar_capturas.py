#!/usr/bin/env python3
"""
Prepara los scripts de las capturas de evidencia (una ventana de consola por figura)
y el manifiesto que usa tomar_capturas.ps1. Los scripts se derivan de los scripts
reales del proyecto (08_consultas.sql, 06_transaccion_2pc.sql, etc.).
Ningún script de captura muestra contraseñas.
"""
import json
import os
import re

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
OUT = os.path.join(RAIZ, '07_Documentacion', 'capturas', 'scripts_captura')
os.makedirs(OUT, exist_ok=True)
CAPS = []


def w(nombre, contenido):
    open(os.path.join(OUT, nombre), 'w', encoding='utf-8', newline='\n').write(contenido.strip() + '\n')


def cap(cid, titulo, tipo, **kw):
    CAPS.append(dict(id=cid, titulo=titulo, tipo=tipo, **kw))


PSQL_HDR = ""

# ------------------------------------------------------------------ PostgreSQL: estructura
w('pg01_conexion.sql', PSQL_HDR + r"""
\conninfo
SELECT version();
SELECT current_database() AS base_de_datos, current_user AS usuario,
       current_setting('TimeZone') AS zona_horaria, pg_encoding_to_char(encoding) AS codificacion,
       pg_size_pretty(pg_database_size(current_database())) AS tamano
  FROM pg_database WHERE datname = current_database();
""")
cap('PG01', 'Conexión al servidor PostgreSQL y datos de la base olva_courier', 'psql', db='olva_courier', file='pg01_conexion.sql')

w('pg02_schemas_tablas.sql', PSQL_HDR + r"""
SELECT n.nspname AS schema, COUNT(c.oid) FILTER (WHERE c.relkind = 'r') AS tablas,
       COUNT(c.oid) FILTER (WHERE c.relkind IN ('v', 'm')) AS vistas, obj_description(n.oid) AS descripcion
  FROM pg_namespace n LEFT JOIN pg_class c ON c.relnamespace = n.oid
 WHERE n.nspname IN ('maestro', 'operacion', 'auditoria', 'seguridad')
 GROUP BY n.oid, n.nspname ORDER BY 1;
\dt maestro.*
\dt operacion.*
""")
cap('PG02', 'Schemas y tablas creadas en olva_courier', 'psql', db='olva_courier', file='pg02_schemas_tablas.sql')

w('pg03_estructura_despacho.sql', PSQL_HDR + r"\d operacion.despacho")
cap('PG03', 'Estructura de la tabla operacion.despacho: columnas, PK, FK, CHECK, índices y trigger', 'psql', db='olva_courier', file='pg03_estructura_despacho.sql')

w('pg04_restricciones_envio.sql', PSQL_HDR + r"""
SELECT conname AS restriccion,
       CASE contype WHEN 'p' THEN 'PRIMARY KEY' WHEN 'f' THEN 'FOREIGN KEY' WHEN 'u' THEN 'UNIQUE' WHEN 'c' THEN 'CHECK' END AS tipo,
       pg_get_constraintdef(oid) AS definicion
  FROM pg_constraint WHERE conrelid = 'operacion.envio'::regclass
 ORDER BY contype DESC, conname;
""")
cap('PG04', 'Restricciones implementadas en la tabla operacion.envio', 'psql', db='olva_courier', file='pg04_restricciones_envio.sql')

tablas = ['maestro.region', 'maestro.ciudad', 'maestro.hub', 'maestro.tipo_servicio', 'maestro.tarifa', 'maestro.ruta',
          'maestro.vehiculo', 'maestro.empleado', 'maestro.cliente', 'operacion.destinatario', 'operacion.envio',
          'operacion.paquete', 'operacion.comprobante', 'operacion.despacho', 'operacion.despacho_envio',
          'operacion.evento_tracking', 'operacion.intento_entrega', 'operacion.incidencia']
w('pg05_validacion_carga.sql', PSQL_HDR + "SELECT tabla, filas FROM (\n" + "\nUNION ALL ".join(
    f"SELECT {i} AS o, '{t}' AS tabla, COUNT(*) AS filas FROM {t}" for i, t in enumerate(tablas)) + "\n) x ORDER BY o;")
cap('PG05', 'Validación del poblamiento: número de registros por tabla', 'psql', db='olva_courier', file='pg05_validacion_carga.sql')

# ------------------------------------------------------------------ PostgreSQL: consultas C01-C13
src = open(os.path.join(RAIZ, '01_Relacional_PostgreSQL', '08_consultas.sql'), encoding='utf-8').read()
bloques = re.split(r"(?m)^-- -{60,}\n(?=\\echo '=== C)", src)
for b in bloques[1:]:
    m = re.match(r"\\echo '=== (C\d\d)\. (.*?) ===", b)
    cid, titulo = m.group(1), m.group(2).rstrip(" =")
    cuerpo = b.split('\n', 1)[1]
    cuerpo = re.sub(r'(?m)^-- -{60,}\s*$', '', cuerpo)
    cuerpo = re.sub(r'(?m)^-- (Problema|Técnica|y detectar|\(clientes|\(clientes grandes|Técnica:).*\n', '', cuerpo)
    w(f'pg_{cid.lower()}.sql', PSQL_HDR + "SET search_path = operacion, maestro, public;\n" + cuerpo)
    cap(f'PG_{cid}', f'Consulta {cid}: {titulo}', 'psql', db='olva_courier', file=f'pg_{cid.lower()}.sql', echo=True)

# ------------------------------------------------------------------ PostgreSQL: programación
APOYO = r"""
SET search_path = operacion, maestro, public;
SELECT id_hub AS ag_mir FROM hub WHERE codigo = 'AG-LIM-MIR' \gset
SELECT id_hub AS ag_sur FROM hub WHERE codigo = 'AG-LIM-SUR' \gset
SELECT id_hub AS ag_iqt FROM hub WHERE codigo = 'AG-IQT-01' \gset
SELECT id_hub AS hc     FROM hub WHERE codigo = 'HC-LIM' \gset
SELECT MIN(id_empleado) AS emp_atencion FROM empleado WHERE id_hub = :ag_mir AND cargo = 'ATENCION' \gset
SELECT MIN(id_empleado) AS emp_operario FROM empleado WHERE id_hub = :hc AND cargo = 'OPERARIO_HUB' \gset
SELECT MIN(id_empleado) AS emp_courier  FROM empleado WHERE id_hub = :ag_sur AND cargo = 'COURIER' \gset
SELECT MIN(id_vehiculo) AS veh_mir FROM vehiculo WHERE id_hub_base = :ag_mir AND tipo = 'FURGONETA' \gset
SELECT MIN(id_vehiculo) AS veh_hc  FROM vehiculo WHERE id_hub_base = :hc AND tipo = 'FURGONETA' \gset
SELECT id_ruta AS ruta_mir_hc FROM ruta WHERE id_hub_origen = :ag_mir AND id_hub_destino = :hc AND modalidad = 'TERRESTRE' \gset
SELECT id_ruta AS ruta_hc_sur FROM ruta WHERE id_hub_origen = :hc AND id_hub_destino = :ag_sur AND modalidad = 'TERRESTRE' \gset
SELECT MIN(id_cliente) AS cliente FROM cliente WHERE tipo_cliente = 'EMPRESA' \gset
"""
w('pg_f1_tarifa.sql', PSQL_HDR + r"""
SET search_path = operacion, maestro, public;
\echo '=== F1 maestro.fn_calcular_tarifa: tarifas Lima -> Oriente por servicio y peso ==='
SELECT ts.codigo AS servicio, r1.nombre AS origen, r2.nombre AS destino, p.peso AS peso_kg,
       fn_calcular_tarifa(ts.id_servicio, r1.id_region, r2.id_region, p.peso) AS tarifa_soles
  FROM tipo_servicio ts CROSS JOIN (VALUES (0.4), (2.5), (12.0)) p(peso)
  JOIN region r1 ON r1.codigo = 'LIM' JOIN region r2 ON r2.codigo = 'ORI'
 WHERE p.peso <= ts.peso_max_kg ORDER BY 1, 4;
\echo '=== F2 operacion.fn_estado_sla: clasificación de los envíos al corte 2026-10-07 18:00 ==='
SELECT fn_estado_sla(id_envio, '2026-10-07 18:00-05') AS estado_sla, COUNT(*) AS envios
  FROM envio GROUP BY 1 ORDER BY 2 DESC;
\echo '--- Error controlado: peso mayor al permitido para SOBRE_AEREO (máx. 0,5 kg)'
SELECT fn_calcular_tarifa(2::SMALLINT, 1::SMALLINT, 4::SMALLINT, 3.0);
""")
cap('PG_F1', 'Ejecución de las funciones fn_calcular_tarifa y fn_estado_sla', 'psql', db='olva_courier', file='pg_f1_tarifa.sql')

w('pg_f2_cuellos.sql', PSQL_HDR + r"""
SET search_path = operacion, maestro, public;
\echo '=== F4 operacion.fn_cuellos_botella(desde, hasta, umbral_horas): función de tabla ==='
SELECT * FROM fn_cuellos_botella('2026-04-01', '2026-10-08', 12) LIMIT 8;
\echo '=== F3 operacion.fn_permanencia_hub: permanencia del envío OLV2600001112 en cada hub ==='
SELECT h.codigo AS hub, fn_permanencia_hub(e.id_envio, h.id_hub, '2026-10-07 18:00-05') AS permanencia
  FROM envio e CROSS JOIN hub h
 WHERE e.nro_tracking = 'OLV2600001112' AND h.codigo IN ('AG-AQP-01', 'HR-AQP', 'HC-LIM', 'AG-LIM-MIR');
""")
cap('PG_F2', 'Ejecución de las funciones fn_cuellos_botella y fn_permanencia_hub', 'psql', db='olva_courier', file='pg_f2_cuellos.sql')

w('pg_p1_registrar_envio.sql', PSQL_HDR + r"""
\set ON_ERROR_ROLLBACK on
BEGIN;
""" + APOYO + r"""
\echo '=== P1 CALL operacion.sp_registrar_envio (empresa, Miraflores -> Surco, 2 bultos en JSONB) ==='
CALL sp_registrar_envio(:cliente, 'Ana Torres Ríos', '45871236', '987654321', 'Av. Primavera 1450, Surco',
     3::SMALLINT, :ag_mir, :ag_sur,
     '[{"peso": 2.3, "largo": 40, "ancho": 30, "alto": 20, "descripcion": "Repuestos"},
       {"peso": 0.8, "largo": 25, "ancho": 20, "alto": 10, "descripcion": "Accesorios", "fragil": true}]',
     'CREDITO', :emp_atencion, NULL);
SELECT e.nro_tracking, e.estado_actual, e.peso_total_kg, e.monto_total, c.tipo, c.serie, c.numero, c.subtotal, c.igv, c.total
  FROM envio e JOIN comprobante c USING (id_envio) WHERE e.nro_tracking = (SELECT MAX(nro_tracking) FROM envio);
SELECT nro_bulto, peso_kg, descripcion, fragil FROM paquete WHERE id_envio = (SELECT MAX(id_envio) FROM envio);
\echo '--- Error controlado: servicio terrestre hacia Iquitos (ciudad sin acceso por carretera)'
CALL sp_registrar_envio(:cliente, 'Luis Ríos', NULL, '912345678', 'Calle Próspero 300', 3::SMALLINT, :ag_mir, :ag_iqt,
     '[{"peso": 1, "largo": 20, "ancho": 20, "alto": 20}]', 'TARJETA', :emp_atencion, NULL);
ROLLBACK;
\echo '>> Transacción revertida (prueba repetible).'
""")
cap('PG_P1', 'Ejecución del procedimiento sp_registrar_envio y validación de destino sin carretera', 'psql', db='olva_courier', file='pg_p1_registrar_envio.sql', quiet=True)

w('pg_p2_ciclo_envio.sql', PSQL_HDR + r"""
\set ON_ERROR_ROLLBACK on
BEGIN;
""" + APOYO + r"""
\o NUL
CALL sp_registrar_envio(:cliente, 'Ana Torres Ríos', '45871236', '987654321', 'Av. Primavera 1450, Surco',
     3::SMALLINT, :ag_mir, :ag_sur, '[{"peso": 2.3, "largo": 40, "ancho": 30, "alto": 20, "descripcion": "Repuestos"}]',
     'CREDITO', :emp_atencion, NULL);
\o
SELECT MAX(nro_tracking) AS trk FROM envio \gset
INSERT INTO despacho (codigo_manifiesto, id_ruta, id_vehiculo, fecha_salida_prog, fecha_salida_real, estado)
VALUES ('MF-PRUEBA-001', :ruta_mir_hc, :veh_mir, now(), clock_timestamp(), 'EN_RUTA') RETURNING id_despacho AS desp1 \gset
INSERT INTO despacho_envio SELECT :desp1, id_envio, now() FROM envio WHERE nro_tracking = :'trk';
\echo '=== P2 sp_registrar_escaneo / P4 sp_cerrar_despacho / P3 sp_registrar_intento_entrega ==='
\echo '--- Error controlado: transición inválida (ENTREGA de un envío recién admitido)'
CALL sp_registrar_escaneo(:'trk', 'ENTREGA', :ag_sur, :emp_courier);
\o NUL
CALL sp_registrar_escaneo(:'trk', 'SALIDA_HUB', :ag_mir, :emp_atencion, :desp1, 'Carga a furgoneta');
CALL sp_cerrar_despacho(:desp1, clock_timestamp(), :emp_operario, NULL);
CALL sp_registrar_escaneo(:'trk', 'CLASIFICACION', :hc, :emp_operario, NULL, 'Clasificado a ruta Surco');
INSERT INTO despacho (codigo_manifiesto, id_ruta, id_vehiculo, fecha_salida_prog, fecha_salida_real, estado)
VALUES ('MF-PRUEBA-002', :ruta_hc_sur, :veh_hc, now(), clock_timestamp(), 'EN_RUTA') RETURNING id_despacho AS desp2 \gset
INSERT INTO despacho_envio SELECT :desp2, id_envio, now() FROM envio WHERE nro_tracking = :'trk';
CALL sp_registrar_escaneo(:'trk', 'SALIDA_HUB', :hc, :emp_operario, :desp2);
CALL sp_cerrar_despacho(:desp2, clock_timestamp(), :emp_courier, NULL);
CALL sp_registrar_escaneo(:'trk', 'EN_REPARTO', :ag_sur, :emp_courier);
CALL sp_registrar_intento_entrega(:'trk', :emp_courier, 'AUSENTE');
CALL sp_registrar_escaneo(:'trk', 'EN_REPARTO', :ag_sur, :emp_courier, NULL, 'Segunda visita');
CALL sp_registrar_intento_entrega(:'trk', :emp_courier, 'ENTREGADO', 'Ana Torres Ríos', '45871236');
\o
\echo '=== Línea de tiempo generada por los procedimientos ==='
SELECT ev.tipo_evento, h.codigo AS hub, ev.observacion FROM evento_tracking ev JOIN hub h USING (id_hub) JOIN envio e USING (id_envio)
 WHERE e.nro_tracking = :'trk' ORDER BY ev.fecha_hora, ev.id_evento;
SELECT nro_tracking, estado_actual, fn_estado_sla(id_envio) AS estado_sla FROM envio WHERE nro_tracking = :'trk';
\echo '=== Triggers: bitácora de auditoría (auditoria.log_estado_envio) ==='
SELECT l.estado_anterior, l.estado_nuevo, l.usuario_bd FROM auditoria.log_estado_envio l JOIN envio e USING (id_envio)
 WHERE e.nro_tracking = :'trk' ORDER BY l.id_log;
ROLLBACK;
""")
cap('PG_P2', 'Ciclo completo de un envío mediante procedimientos almacenados y auditoría generada por triggers', 'psql', db='olva_courier', file='pg_p2_ciclo_envio.sql', quiet=True)

# ------------------------------------------------------------------ PostgreSQL: seguridad
w('pg_s1_roles.sql', PSQL_HDR + r"""
\echo '=== Usuarios, rol heredado y atributos de cuenta ==='
SELECT u.rolname AS usuario, STRING_AGG(g.rolname, ', ') AS rol, u.rolconnlimit AS limite_conexiones,
       u.rolvaliduntil::DATE AS vigencia, u.rolbypassrls AS bypass_rls
  FROM pg_roles u JOIN pg_auth_members m ON m.member = u.oid JOIN pg_roles g ON g.oid = m.roleid
 WHERE u.rolname LIKE 'u\_%' GROUP BY u.rolname, u.rolconnlimit, u.rolvaliduntil, u.rolbypassrls ORDER BY 1;
\echo '=== Privilegios otorgados por rol y schema (GRANT) ==='
SELECT grantee AS rol, table_schema AS schema, STRING_AGG(DISTINCT privilege_type, ', ') AS privilegios, COUNT(DISTINCT table_name) AS objetos
  FROM information_schema.role_table_grants WHERE grantee LIKE 'rol_%' GROUP BY 1, 2 ORDER BY 1, 2;
\echo '=== Políticas de seguridad por fila (RLS) ==='
SELECT tablename AS tabla, policyname AS politica, roles, cmd FROM pg_policies ORDER BY 1, 2;
""")
cap('PG_S1', 'Roles, usuarios, privilegios y políticas RLS configurados', 'psql', db='olva_courier', file='pg_s1_roles.sql')

w('pg_s2_rls.sql', PSQL_HDR + r"""
\echo '=== Misma consulta, distinto usuario: Row Level Security por nodo ==='
SET SESSION AUTHORIZATION u_op_lima;
SELECT session_user AS usuario, seguridad.fn_mi_nodo() AS nodo, COUNT(*) AS envios_visibles FROM operacion.envio;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION u_op_norte;
SELECT session_user AS usuario, seguridad.fn_mi_nodo() AS nodo, COUNT(*) AS envios_visibles FROM operacion.envio;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION u_op_sur;
SELECT session_user AS usuario, seguridad.fn_mi_nodo() AS nodo, COUNT(*) AS envios_visibles FROM operacion.envio;
RESET SESSION AUTHORIZATION;
SELECT current_user AS usuario, 'propietario' AS nodo, COUNT(*) AS envios_visibles FROM operacion.envio;
""")
cap('PG_S2', 'Row Level Security: cada operador ve solo los envíos de su nodo', 'psql', db='olva_courier', file='pg_s2_rls.sql', quiet=True)

w('pg_s3_denegados.sql', PSQL_HDR + r"""
SET SESSION AUTHORIZATION u_op_sur;
\echo '--- u_op_sur: lectura de columnas permitidas'
SELECT nro_tracking, estado_actual, peso_total_kg FROM operacion.envio ORDER BY id_envio LIMIT 3;
\echo '--- u_op_sur: columna monto_total (sin privilegio de columna)'
SELECT nro_tracking, monto_total FROM operacion.envio LIMIT 1;
\echo '--- u_op_sur: INSERT directo en evento_tracking (solo se permite vía procedimiento)'
INSERT INTO operacion.evento_tracking (id_envio, tipo_evento, id_hub, fecha_hora) VALUES (1, 'CLASIFICACION', 1, now());
\echo '--- u_op_sur: UPDATE directo del estado de un envío'
UPDATE operacion.envio SET estado_actual = 'ENTREGADO' WHERE id_envio = 1;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION u_analista;
\echo '--- u_analista: vista analítica permitida'
SELECT modalidad, COUNT(*) AS envios, ROUND(AVG(monto_total), 2) AS ticket_prom FROM operacion.vw_envio_analitico GROUP BY 1;
\echo '--- u_analista: datos personales de clientes (denegado)'
SELECT nro_documento FROM maestro.cliente LIMIT 1;
\echo '--- u_analista: procedimiento de escritura (denegado)'
CALL operacion.sp_registrar_escaneo('OLV2600000001', 'CLASIFICACION', 1, 1);
RESET SESSION AUTHORIZATION;
""")
cap('PG_S3', 'Privilegios por columna y escritura solo mediante procedimientos: accesos denegados', 'psql', db='olva_courier', file='pg_s3_denegados.sql', quiet=True)

cap('PG_B1', 'Respaldo lógico y físico, incidente simulado y restauración verificada', 'bash',
    contenedor='olva_pg_lima', comando='bash /proyecto/01_Relacional_PostgreSQL/11_backup_restauracion.sh',
    encabezado='postgres@servidor-lima:~$ ./11_backup_restauracion.sh')

# ------------------------------------------------------------------ Oracle
ORA_HDR = "SET LINESIZE 165\nSET PAGESIZE 200\nSET FEEDBACK OFF\nSET TRIMOUT ON\nALTER SESSION SET TIME_ZONE = 'America/Lima';\nALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD HH24:MI';\n"
w('ora01_conexion.sql', "SET LINESIZE 165\nSET PAGESIZE 100\nCOLUMN banner_full FORMAT A100\nCOLUMN usuario FORMAT A10\nCOLUMN contenedor FORMAT A12\nCOLUMN servicio FORMAT A12\nCOLUMN host FORMAT A20\n"
  "SELECT banner_full FROM v$version;\n"
  "SELECT USER AS usuario, SYS_CONTEXT('USERENV','CON_NAME') AS contenedor, SYS_CONTEXT('USERENV','SERVICE_NAME') AS servicio,\n"
  "       SYS_CONTEXT('USERENV','DB_NAME') AS bd, TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI') AS fecha FROM dual;\nEXIT\n")
cap('ORA01', 'Conexión a Oracle con SQL*Plus al servicio FREEPDB1 (esquema OLVA)', 'sqlplus', usuario='olva', file='ora01_conexion.sql', banner=True)

w('ora02_tablas.sql', ORA_HDR + """COLUMN tabla FORMAT A18
COLUMN tipo FORMAT A12
COLUMN restricciones FORMAT A60
PROMPT === Tablas del esquema OLVA, registros y restricciones por tipo ===
SELECT t.table_name AS tabla,
       TO_NUMBER(EXTRACTVALUE(XMLTYPE(DBMS_XMLGEN.GETXML('SELECT COUNT(*) c FROM ' || t.table_name)), '/ROWSET/ROW/C')) AS filas,
       r.restricciones
  FROM user_tables t
  LEFT JOIN (SELECT table_name, LISTAGG(tipo || ':' || n, ' ') WITHIN GROUP (ORDER BY tipo) AS restricciones
               FROM (SELECT table_name, DECODE(constraint_type, 'P', 'PK', 'R', 'FK', 'U', 'UK', 'C', 'CHECK') AS tipo, COUNT(*) AS n
                       FROM user_constraints WHERE constraint_name NOT LIKE 'SYS%' GROUP BY table_name, constraint_type)
              GROUP BY table_name) r ON r.table_name = t.table_name
 ORDER BY t.table_name;
PROMPT
PROMPT === Objetos PL/SQL ===
COLUMN object_name FORMAT A30
SELECT object_name, object_type, status FROM user_objects WHERE object_type IN ('PACKAGE','PACKAGE BODY','PROCEDURE','TRIGGER') ORDER BY 2, 1;
EXIT
""")
cap('ORA02', 'Tablas, volumen de datos, restricciones y objetos PL/SQL del esquema OLVA', 'sqlplus', usuario='olva', file='ora02_tablas.sql')

w('ora03_desc_envio.sql', ORA_HDR + """COLUMN constraint_name FORMAT A22
COLUMN t FORMAT A2
COLUMN condicion FORMAT A110
PROMPT === DESCRIBE envio ===
DESC envio
PROMPT === Restricciones de ENVIO ===
SELECT constraint_name, constraint_type AS t, SUBSTR(search_condition_vc, 1, 110) AS condicion
  FROM user_constraints WHERE table_name = 'ENVIO' ORDER BY constraint_type DESC, constraint_name;
EXIT
""")
cap('ORA03', 'Estructura y restricciones de la tabla ENVIO en Oracle', 'sqlplus', usuario='olva', file='ora03_desc_envio.sql')

osrc = open(os.path.join(RAIZ, '02_Oracle', '04_consultas_y_pruebas.sql'), encoding='utf-8').read()
cols = '\n'.join(l for l in osrc.splitlines() if l.startswith('COLUMN'))
def oblock(a, b):
    i = osrc.index(f'PROMPT === {a}')
    j = osrc.index(f'PROMPT === {b}') if b else len(osrc)
    return osrc[i:j]
grupos = [('ora04_o1_o2.sql', 'O1', 'O3', 'ORA04', 'Consultas básicas en Oracle: envíos por estado y cumplimiento de SLA por servicio'),
          ('ora05_o3.sql', 'O3', 'O4', 'ORA05', 'Consulta jerárquica CONNECT BY sobre la red logística (exclusiva de Oracle)'),
          ('ora06_o4_o5.sql', 'O4', 'O6', 'ORA06', 'LISTAGG y Top-N con FETCH FIRST y ROWNUM'),
          ('ora07_o6_o7.sql', 'O6', 'O8', 'ORA07', 'Funciones analíticas (LAG) y funciones del paquete pkg_tracking invocadas desde SQL'),
          ('ora08_o8_o9.sql', 'O8', 'P1', 'ORA08', 'Cadena vacía como NULL y MERGE (upsert) en Oracle'),
          ('ora09_p1_p2.sql', 'P1', None, 'ORA09', 'Paquete PL/SQL, trigger y transacción autónoma: errores controlados y bitácora persistente')]
for f, a, b, cid, tit in grupos:
    w(f, "SET DEFINE OFF\nSET SERVEROUTPUT ON\n" + ORA_HDR + cols + "\n" + oblock(a, b) + "\nEXIT\n")
    cap(cid, tit, 'sqlplus', usuario='olva', file=f)

w('ora10_seguridad.sql', ORA_HDR + """COLUMN username FORMAT A16
COLUMN account_status FORMAT A16
COLUMN profile FORMAT A18
COLUMN resource_name FORMAT A24
COLUMN limit FORMAT A8
COLUMN grantee FORMAT A18
COLUMN granted_role FORMAT A18
COLUMN table_name FORMAT A16
COLUMN privilege FORMAT A10
PROMPT === Usuarios y perfil ===
SELECT username, account_status, profile FROM dba_users WHERE username IN ('OLVA','U_ANALISTA_ORA','U_OPERADOR_ORA') ORDER BY 1;
PROMPT === Límites del PROFILE prf_olva_usuarios ===
SELECT resource_name, limit FROM dba_profiles WHERE profile = 'PRF_OLVA_USUARIOS' AND limit <> 'DEFAULT' ORDER BY 1;
PROMPT === Roles y privilegios de objeto ===
SELECT grantee, granted_role FROM dba_role_privs WHERE grantee IN ('U_ANALISTA_ORA','U_OPERADOR_ORA') ORDER BY 1;
SELECT grantee, table_name, privilege FROM dba_tab_privs WHERE grantee IN ('ROL_ANALISTA_ORA','ROL_OPERADOR_ORA') ORDER BY 1, 2;
EXIT
""")
cap('ORA10', 'Seguridad en Oracle: usuarios, PROFILE, roles y privilegios', 'sqlplus', usuario='system', file='ora10_seguridad.sql')

w('ora11_bloqueo.sh', """#!/bin/bash
# Pruebas de acceso con cada usuario y bloqueo de cuenta por PROFILE (sin mostrar contraseñas)
cd /proyecto/02_Oracle
sqlplus -s /nolog @06_pruebas_seguridad.sql < /dev/null 2>&1 | grep -v '^Help'
sqlplus -s "system/${ORACLE_PASSWORD}@//localhost:1521/FREEPDB1" <<'SQL'
SET LINESIZE 120
COLUMN username FORMAT A16
COLUMN account_status FORMAT A16
PROMPT === Estado de la cuenta tras 3 intentos fallidos (consultado como SYSTEM) ===
SELECT username, account_status FROM dba_users WHERE username = 'U_ANALISTA_ORA';
ALTER USER u_analista_ora ACCOUNT UNLOCK;
SELECT username, account_status FROM dba_users WHERE username = 'U_ANALISTA_ORA';
SQL
""")
cap('ORA11', 'Pruebas de acceso en Oracle y bloqueo de cuenta por PROFILE', 'bash', contenedor='olva_oracle',
    comando='bash /proyecto/07_Documentacion/capturas/scripts_captura/ora11_bloqueo.sh',
    encabezado='SQL*Plus> @06_pruebas_seguridad.sql')
cap('ORA12', 'Respaldo con Data Pump (expdp), DROP simulado y restauración (impdp)', 'bash', contenedor='olva_oracle',
    comando='bash /proyecto/02_Oracle/07_backup_datapump.sh', encabezado='oracle@servidor-oracle:~$ ./07_backup_datapump.sh')

# ------------------------------------------------------------------ BD distribuida
w('dd01_fdw_catalogo.sql', PSQL_HDR + r"""
\echo '=== Servidores remotos definidos con postgres_fdw (sin credenciales) ==='
SELECT s.srvname AS servidor, w.fdwname AS wrapper, array_to_string(s.srvoptions[1:3], ' ') AS opciones_conexion
  FROM pg_foreign_server s JOIN pg_foreign_data_wrapper w ON w.oid = s.srvfdw ORDER BY 1;
\echo '=== Esquema de asignación: fragmentos de cada relación global ==='
SELECT * FROM global.catalogo_fragmentos;
""")
cap('DD01', 'Servidores postgres_fdw y catálogo de fragmentos en el coordinador Lima', 'psql', db='olva_lima', file='dd01_fdw_catalogo.sql')

vsrc = open(os.path.join(RAIZ, '03_BD_Distribuida', '04_verificacion_fragmentacion.sql'), encoding='utf-8').read()
def vblock(a, b):
    i = vsrc.index(a); j = vsrc.index(b) if b else len(vsrc)
    return vsrc[i:j]
w('dd02_distribucion.sql', PSQL_HDR + vblock("\\echo '=== Distribución", "\\echo '=== 2)"))
cap('DD02', 'Distribución de filas por nodo y regla de completitud', 'psql', db='olva_lima', file='dd02_distribucion.sql')
w('dd03_reconstruccion.sql', PSQL_HDR + vblock("\\echo '=== 2)", "\\echo '=== Integridad"))
cap('DD03', 'Reglas de disyunción y reconstrucción (fragmentación horizontal y vertical)', 'psql', db='olva_lima', file='dd03_reconstruccion.sql')
w('dd04_predicado.sql', PSQL_HDR + vblock("\\echo '=== Integridad", None))
cap('DD04', 'Integridad del predicado: el nodo SUR rechaza un envío que no le pertenece', 'psql', db='olva_lima', file='dd04_predicado.sql')

qsrc = open(os.path.join(RAIZ, '03_BD_Distribuida', '05_consultas_distribuidas.sql'), encoding='utf-8').read()
pre = qsrc[qsrc.index('SET enable_partitionwise_join'):qsrc.index("\\echo '=====")]
qs = re.split(r"(?m)^\\echo '={50,}'\n(?=\\echo 'Q\d)", qsrc)
titulos = {'Q1': 'Localización: poda de fragmentos y filtro enviado al nodo SUR',
           'Q2': 'Agregación distribuida: GROUP BY ejecutado en cada nodo',
           'Q3': 'JOIN co-localizado ejecutado dentro de cada nodo (fragmentación derivada)',
           'Q4': 'JOIN no co-localizado: tracking de un envío con eventos en los tres nodos',
           'Q5': 'Reconstrucción vertical del cliente y costo de la distribución'}
partes = {}
for b in qs[1:]:
    q = re.match(r"\\echo '(Q\d)", b).group(1)
    partes[q] = b
partes['Q5'] = partes['Q5'] + partes.pop('Q6', '')
for q, b in partes.items():
    b = re.sub(r"(?m)^\\echo '={50,}'\n", '', b)
    w(f'dd_{q.lower()}.sql', PSQL_HDR + pre + b)
    cap(f'DD_{q}', f'Consulta distribuida {q}: {titulos[q]}', 'psql', db='olva_lima', file=f'dd_{q.lower()}.sql')

tsrc = open(os.path.join(RAIZ, '03_BD_Distribuida', '06_transaccion_2pc.sql'), encoding='utf-8').read()
i1 = tsrc.index('-- ======'+'='*50+' CASO 1') if False else tsrc.index('-- =================================================================== CASO 1')
i2 = tsrc.index('-- =================================================================== CASO 2')
i3 = tsrc.index('-- =================================================================== CASO 3')
vars_ = "\\pset footer off\n\\set c_lima  'dbname=olva_lima'\n\\set c_norte 'host=pg_norte dbname=olva_norte'\n\\set c_sur   'host=pg_sur dbname=olva_sur'\n" \
        "SELECT id_hub AS hub_aqp FROM maestro.hub WHERE codigo = 'HR-AQP' \\gset\n\\set ON_ERROR_STOP off\n"
w('dd_2pc_0_preparacion.sql', tsrc[:i1])
for n, (a, b) in enumerate([(i1, i2), (i2, i3), (i3, None)], start=1):
    w(f'dd_2pc_{n}.sql', vars_ + (tsrc[a:b] if b else tsrc[a:]))
cap('DD_2PC0', 'Preparación del escenario 2PC (no se captura)', 'prep', contenedor='olva_pg_lima',
    comando='psql -X -q -U olva_admin -d olva_lima -f /proyecto/07_Documentacion/capturas/scripts_captura/dd_2pc_0_preparacion.sql')
tit2pc = {1: 'Protocolo 2PC, caso 1: los tres nodos votan SÍ y se confirma la transacción global',
          2: 'Protocolo 2PC, caso 2: un participante vota NO y se revierte la transacción global',
          3: 'Protocolo 2PC, caso 3: caída del coordinador, transacción en duda y recuperación'}
for n in (1, 2, 3):
    cap(f'DD_2PC{n}', tit2pc[n], 'bash', contenedor='olva_pg_lima',
        comando=f'psql -X -q -U olva_admin -d olva_lima -f /proyecto/07_Documentacion/capturas/scripts_captura/dd_2pc_{n}.sql',
        encabezado=f'olva_lima (coordinador)> \\i dd_2pc_{n}.sql')
titc = {'A': 'Concurrencia A: bloqueo exclusivo de fila (SELECT ... FOR UPDATE) en el nodo SUR',
        'B': 'Concurrencia B: actualización perdida en READ COMMITTED frente a REPEATABLE READ',
        'C1': 'Concurrencia C1: interbloqueo local detectado por PostgreSQL',
        'C2': 'Concurrencia C2: interbloqueo distribuido resuelto por tiempo de espera'}
for s, t in titc.items():
    cap(f'DD_CC_{s}', t, 'bash', contenedor='olva_pg_lima',
        comando=f'bash /proyecto/03_BD_Distribuida/07_concurrencia.sh {s}',
        encabezado=f'coordinador-lima:~$ ./07_concurrencia.sh {s}')

json.dump(CAPS, open(os.path.join(RAIZ, '07_Documentacion', 'capturas', 'manifiesto.json'), 'w', encoding='utf-8'),
          ensure_ascii=False, indent=1)
print(f'{len(CAPS)} capturas definidas; scripts en {OUT}')
