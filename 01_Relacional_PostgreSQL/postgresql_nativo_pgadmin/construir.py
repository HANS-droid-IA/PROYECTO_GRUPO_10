# Une los scripts de 01_Relacional_PostgreSQL en una sola base de datos autocontenida
# (puntos 5 a 7 del informe) lista para el PostgreSQL instalado en Windows.
# Los comandos de psql se escriben con el marcador BSL, que se convierte en "\" al guardar.
import re, pathlib
SRC = pathlib.Path(__file__).resolve().parent.parent
DST = pathlib.Path(__file__).resolve().parent
BD = 'olva_courier_pg'
BS = chr(92)


def leer(n):
    return (SRC / n).read_text(encoding='utf-8')


def seccion(titulo):
    linea = '-- ' + '#' * 69
    return f"\n\n{linea}\n-- {titulo}\n{linea}\n"


def guardar(nombre, texto):
    (DST / nombre).write_text(texto.replace('BSL', BS), encoding='utf-8')


carga = re.sub(r"^COPY (\S+)\s+FROM '/proyecto/01_Relacional_PostgreSQL/(datos/[^']+)'",
               lambda m: f"BSLcopy {m.group(1)} FROM '../{m.group(2)}'",
               leer('04_carga_datos.sql'), flags=re.M)
assert '/proyecto' not in carga
seg = leer('07_seguridad_roles.sql').replace('DATABASE olva_courier', f'DATABASE {BD}')

cab = f"""-- =====================================================================
-- BASE DE DATOS POSTGRESQL - Trazabilidad de paquetería (caso Olva Courier)
-- Proyecto Final BD II - puntos 5, 6 y 7 del informe
-- Base de datos: {BD}      Motor: PostgreSQL 16 o superior
--
-- Ejecutar con psql DESDE ESTA CARPETA (usa ../datos/*.csv con rutas relativas):
--     psql -h localhost -p 5432 -U postgres -f 01_olva_courier_postgresql.sql
-- o con doble clic en 00_INSTALAR.bat
--
-- Contenido:
--   6.1  Creación de la base de datos
--   6.2  Arquitectura de schemas (maestro, operacion, auditoria, seguridad)
--   6.3  Tablas, PK, FK, CHECK, UNIQUE, NOT NULL e índices
--   7.1  Funciones almacenadas (PL/pgSQL)
--   7.2  Procedimientos almacenados (PL/pgSQL)
--   6.4  Poblamiento masivo de datos (BSLcopy desde CSV)
--   7.x  Triggers y vistas (apoyo a la programación de la BD)
--   7.3  Seguridad: roles, usuarios, GRANT/REVOKE
--   7.4  Políticas de acceso: privilegios por columna y Row Level Security
--   (6.5 consultas -> 02_consultas_y_pruebas.sql | 7.5 backup -> 03_backup_restauracion.bat)
-- =====================================================================
BSLset ON_ERROR_STOP on
BSLencoding UTF8
SET client_min_messages = warning;
"""

resumen = f"""BSLecho '>> Base de datos {BD} creada correctamente'
SELECT 'tablas' AS objeto, COUNT(*) AS cantidad FROM information_schema.tables WHERE table_schema IN ('maestro','operacion','auditoria','seguridad') AND table_type = 'BASE TABLE'
UNION ALL SELECT 'funciones', COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('maestro','operacion') AND p.prokind = 'f' AND p.prorettype <> 'trigger'::regtype
UNION ALL SELECT 'procedimientos', COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('maestro','operacion') AND p.prokind = 'p'
UNION ALL SELECT 'triggers', COUNT(*) FROM pg_trigger WHERE NOT tgisinternal
UNION ALL SELECT 'vistas', COUNT(*) FROM pg_views WHERE schemaname IN ('maestro','operacion')
UNION ALL SELECT 'vistas materializadas', COUNT(*) FROM pg_matviews
UNION ALL SELECT 'políticas RLS', COUNT(*) FROM pg_policies
UNION ALL SELECT 'envíos', COUNT(*) FROM operacion.envio
UNION ALL SELECT 'eventos de tracking', COUNT(*) FROM operacion.evento_tracking;
"""

guardar('01_olva_courier_postgresql.sql', ''.join([
    cab,
    seccion('6.1 CREACIÓN DE LA BASE DE DATOS'),
    f"DROP DATABASE IF EXISTS {BD} WITH (FORCE);\n"
    f"CREATE DATABASE {BD} ENCODING 'UTF8' TEMPLATE template0;\n"
    f"ALTER DATABASE {BD} SET timezone TO 'America/Lima';\n"
    f"BSLconnect {BD}\nSET client_min_messages = warning;\n",
    seccion('6.2 / 6.3 SCHEMAS, TABLAS, PK, FK, RESTRICCIONES E ÍNDICES'), leer('01_ddl_esquemas_tablas.sql'),
    seccion('7.1 FUNCIONES ALMACENADAS (PL/pgSQL)'), leer('02_funciones.sql'),
    seccion('7.2 PROCEDIMIENTOS ALMACENADOS (PL/pgSQL)'), leer('03_procedimientos.sql'),
    seccion('6.4 POBLAMIENTO DE DATOS'), carga,
    seccion('7.x TRIGGERS'), leer('05_triggers.sql'),
    seccion('7.x VISTAS Y VISTA MATERIALIZADA'), leer('06_vistas.sql'),
    seccion('7.3 / 7.4 SEGURIDAD, ROLES, PRIVILEGIOS Y RLS'), seg,
    seccion('RESUMEN FINAL'), resumen,
]))

guardar('02_consultas_y_pruebas.sql', ''.join([
    "-- 6.5 Consultas representativas y pruebas de funciones, procedimientos y seguridad\n",
    "-- Uso: psql -h localhost -p 5432 -U postgres -f 02_consultas_y_pruebas.sql\n",
    f"BSLconnect {BD}\n",
    seccion('6.5 CONSULTAS SQL REPRESENTATIVAS'), leer('08_consultas.sql'),
    seccion('PRUEBAS 7.1 / 7.2 FUNCIONES, PROCEDIMIENTOS Y TRIGGERS'), leer('09_pruebas_procedimientos.sql'),
    seccion('PRUEBAS 7.3 / 7.4 SEGURIDAD'), leer('10_pruebas_seguridad.sql'),
]))
print('ok')
