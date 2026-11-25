-- =====================================================================
-- 05 - Seguridad en Oracle (se ejecuta como SYSTEM en FREEPDB1)
-- Diferencias con PostgreSQL:
--   * En Oracle USUARIO = ESQUEMA; los roles NO pueden ser dueños de objetos.
--   * PROFILE: políticas de contraseña/recursos (intentos fallidos, expiración)
--     que en PostgreSQL no existen de forma nativa (solo VALID UNTIL).
--   * Privilegio de sistema CREATE SESSION obligatorio para conectarse
--     (en PG: GRANT CONNECT ON DATABASE).
--   * Cuotas por TABLESPACE.
-- =====================================================================
SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 100
COLUMN grantee FORMAT A20
COLUMN privilege FORMAT A12
COLUMN table_name FORMAT A16
COLUMN granted_role FORMAT A20
COLUMN profile FORMAT A18
COLUMN resource_name FORMAT A26
COLUMN limit FORMAT A10
COLUMN username FORMAT A16
COLUMN account_status FORMAT A16

-- limpieza idempotente
BEGIN
    FOR u IN (SELECT username FROM dba_users WHERE username IN ('U_ANALISTA_ORA', 'U_OPERADOR_ORA')) LOOP
        EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
    END LOOP;
    FOR r IN (SELECT role FROM dba_roles WHERE role IN ('ROL_ANALISTA_ORA', 'ROL_OPERADOR_ORA')) LOOP
        EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
    END LOOP;
    FOR p IN (SELECT DISTINCT profile FROM dba_profiles WHERE profile = 'PRF_OLVA_USUARIOS') LOOP
        EXECUTE IMMEDIATE 'DROP PROFILE ' || p.profile || ' CASCADE';
    END LOOP;
END;
/

-- Perfil con política de contraseñas y recursos
CREATE PROFILE prf_olva_usuarios LIMIT
    FAILED_LOGIN_ATTEMPTS 3
    PASSWORD_LOCK_TIME    1/24        -- bloqueo de 1 hora
    PASSWORD_LIFE_TIME    90
    SESSIONS_PER_USER     3
    IDLE_TIME             30;

-- Roles
CREATE ROLE rol_analista_ora;
CREATE ROLE rol_operador_ora;

GRANT CREATE SESSION TO rol_analista_ora, rol_operador_ora;
GRANT SELECT ON olva.region        TO rol_analista_ora;
GRANT SELECT ON olva.ciudad        TO rol_analista_ora;
GRANT SELECT ON olva.hub           TO rol_analista_ora;
GRANT SELECT ON olva.tipo_servicio TO rol_analista_ora;
GRANT SELECT ON olva.envio         TO rol_analista_ora;
GRANT SELECT ON olva.evento_tracking TO rol_analista_ora;

GRANT SELECT ON olva.hub      TO rol_operador_ora;
GRANT SELECT ON olva.envio    TO rol_operador_ora;
-- el operador escribe solo vía paquete (no tiene INSERT sobre las tablas)
GRANT EXECUTE ON olva.pkg_tracking TO rol_operador_ora;

-- Usuarios (contraseñas de prueba, entorno local)
CREATE USER u_analista_ora IDENTIFIED BY "<CONTRASENA_CONFIGURADA>" PROFILE prf_olva_usuarios
    DEFAULT TABLESPACE users QUOTA 0 ON users;
CREATE USER u_operador_ora IDENTIFIED BY "<CONTRASENA_CONFIGURADA>" PROFILE prf_olva_usuarios
    DEFAULT TABLESPACE users QUOTA 0 ON users;
GRANT rol_analista_ora TO u_analista_ora;
GRANT rol_operador_ora TO u_operador_ora;

PROMPT === Usuarios y perfil asignado ===
SELECT username, account_status, profile FROM dba_users
 WHERE username IN ('OLVA', 'U_ANALISTA_ORA', 'U_OPERADOR_ORA') ORDER BY username;

PROMPT === Límites del perfil ===
SELECT profile, resource_name, limit FROM dba_profiles
 WHERE profile = 'PRF_OLVA_USUARIOS' AND limit <> 'DEFAULT' ORDER BY resource_name;

PROMPT === Roles otorgados ===
SELECT grantee, granted_role FROM dba_role_privs
 WHERE grantee IN ('U_ANALISTA_ORA', 'U_OPERADOR_ORA') ORDER BY grantee;

PROMPT === Privilegios de objeto por rol ===
SELECT grantee, table_name, privilege FROM dba_tab_privs
 WHERE grantee IN ('ROL_ANALISTA_ORA', 'ROL_OPERADOR_ORA') ORDER BY grantee, table_name;
