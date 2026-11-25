-- =====================================================================
-- 07 - Seguridad: roles, usuarios, privilegios (GRANT/REVOKE) y
--      políticas de acceso por fila (Row Level Security)
-- =====================================================================
-- Modelo RBAC: los permisos se otorgan a ROLES de grupo (NOLOGIN) y los
-- USUARIOS (LOGIN) heredan permisos al ser miembros de un rol.
--
--   rol_admin_olva        administración completa de la BD
--   rol_operador_hub      escaneos y despachos; solo ve envíos de su nodo (RLS)
--   rol_atencion_cliente  registra envíos, consulta tracking, gestiona incidencias
--   rol_facturacion       consulta comprobantes y montos
--   rol_analista          solo lectura sobre vistas analíticas (sin datos personales)
-- =====================================================================
-- NOTA: contraseñas de prueba solo para el entorno local de desarrollo.

-- 1) Roles de grupo -----------------------------------------------------
DO $$
DECLARE r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['rol_admin_olva', 'rol_operador_hub', 'rol_atencion_cliente', 'rol_facturacion', 'rol_analista']
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END $$;

-- 2) Usuarios -----------------------------------------------------------
DO $$
DECLARE u RECORD;
BEGIN
    FOR u IN SELECT * FROM (VALUES
        ('u_admin_bd',    '<CONTRASENA_CONFIGURADA>', 'rol_admin_olva'),
        ('u_op_lima',     '<CONTRASENA_CONFIGURADA>',    'rol_operador_hub'),
        ('u_op_norte',    '<CONTRASENA_CONFIGURADA>',    'rol_operador_hub'),
        ('u_op_sur',      '<CONTRASENA_CONFIGURADA>',    'rol_operador_hub'),
        ('u_atencion',    '<CONTRASENA_CONFIGURADA>',    'rol_atencion_cliente'),
        ('u_facturacion', '<CONTRASENA_CONFIGURADA>',   'rol_facturacion'),
        ('u_analista',    '<CONTRASENA_CONFIGURADA>',    'rol_analista')) AS t(usuario, clave, rol)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = u.usuario) THEN
            EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', u.usuario, u.clave);
        END IF;
        EXECUTE format('GRANT %I TO %I', u.rol, u.usuario);
    END LOOP;
END $$;

-- políticas de cuenta: límite de conexiones y vigencia para el analista externo
ALTER ROLE u_analista CONNECTION LIMIT 3 VALID UNTIL '2026-12-31';
ALTER ROLE u_op_lima  CONNECTION LIMIT 10;
ALTER ROLE u_op_norte CONNECTION LIMIT 10;
ALTER ROLE u_op_sur   CONNECTION LIMIT 10;
ALTER ROLE rol_admin_olva CREATEROLE;

-- 3) Endurecimiento: nadie hereda privilegios por defecto ---------------
REVOKE ALL ON DATABASE olva_courier FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA maestro, operacion FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA operacion FROM PUBLIC;
GRANT CONNECT ON DATABASE olva_courier
      TO rol_admin_olva, rol_operador_hub, rol_atencion_cliente, rol_facturacion, rol_analista;

-- 4) Administrador ------------------------------------------------------
GRANT USAGE, CREATE ON SCHEMA maestro, operacion, auditoria, seguridad TO rol_admin_olva;
GRANT ALL ON ALL TABLES    IN SCHEMA maestro, operacion, auditoria, seguridad TO rol_admin_olva;
GRANT ALL ON ALL SEQUENCES IN SCHEMA maestro, operacion, auditoria TO rol_admin_olva;
GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA maestro, operacion TO rol_admin_olva;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA operacion TO rol_admin_olva;
ALTER ROLE rol_admin_olva BYPASSRLS;

-- 5) Operador de hub ----------------------------------------------------
GRANT USAGE ON SCHEMA maestro, operacion TO rol_operador_hub;
GRANT SELECT ON maestro.region, maestro.ciudad, maestro.hub, maestro.ruta, maestro.vehiculo,
               maestro.tipo_servicio TO rol_operador_hub;
GRANT SELECT (id_empleado, nombres, apellidos, cargo, id_hub) ON maestro.empleado TO rol_operador_hub;
-- solo columnas operativas del envío: no ve montos ni valor declarado
GRANT SELECT (id_envio, nro_tracking, id_servicio, id_hub_origen, id_hub_destino, direccion_entrega,
              fecha_registro, fecha_compromiso, estado_actual, peso_total_kg, fecha_entrega)
      ON operacion.envio TO rol_operador_hub;
GRANT SELECT ON operacion.paquete, operacion.despacho, operacion.despacho_envio, operacion.evento_tracking
      TO rol_operador_hub;
-- las escrituras SOLO a través de procedimientos (SECURITY DEFINER)
GRANT EXECUTE ON PROCEDURE operacion.sp_registrar_escaneo, operacion.sp_cerrar_despacho,
                           operacion.sp_registrar_intento_entrega TO rol_operador_hub;
GRANT EXECUTE ON FUNCTION operacion.fn_estado_sla, operacion.fn_permanencia_hub TO rol_operador_hub;

-- 6) Atención al cliente ------------------------------------------------
GRANT USAGE ON SCHEMA maestro, operacion TO rol_atencion_cliente;
GRANT SELECT ON maestro.region, maestro.ciudad, maestro.hub, maestro.tipo_servicio, maestro.tarifa,
               maestro.cliente TO rol_atencion_cliente;
GRANT SELECT ON operacion.vw_tracking_publico, operacion.envio, operacion.evento_tracking,
               operacion.intento_entrega TO rol_atencion_cliente;
GRANT SELECT, INSERT, UPDATE (estado, fecha_cierre, descripcion) ON operacion.incidencia TO rol_atencion_cliente;
GRANT INSERT, UPDATE (email, telefono, direccion) ON maestro.cliente TO rol_atencion_cliente;
GRANT USAGE ON SEQUENCE maestro.cliente_id_cliente_seq, operacion.incidencia_id_incidencia_seq TO rol_atencion_cliente;
GRANT EXECUTE ON PROCEDURE operacion.sp_registrar_envio TO rol_atencion_cliente;
GRANT EXECUTE ON FUNCTION maestro.fn_calcular_tarifa, operacion.fn_estado_sla TO rol_atencion_cliente;

-- 7) Facturación --------------------------------------------------------
GRANT USAGE ON SCHEMA maestro, operacion TO rol_facturacion;
GRANT SELECT ON maestro.cliente, maestro.tarifa, maestro.tipo_servicio, maestro.region,
               operacion.comprobante, operacion.envio TO rol_facturacion;

-- 8) Analista (solo lectura, sin datos personales) ----------------------
GRANT USAGE ON SCHEMA maestro, operacion TO rol_analista;
GRANT SELECT ON maestro.region, maestro.ciudad, maestro.hub, maestro.ruta, maestro.tipo_servicio,
               maestro.tarifa TO rol_analista;
GRANT SELECT ON operacion.vw_envio_analitico, operacion.mv_permanencia_hub, operacion.despacho,
               operacion.incidencia TO rol_analista;
GRANT SELECT (id_evento, id_envio, tipo_evento, id_hub, id_despacho, fecha_hora) ON operacion.evento_tracking TO rol_analista;
GRANT EXECUTE ON FUNCTION operacion.fn_cuellos_botella, operacion.fn_estado_sla TO rol_analista;

-- 9) Row Level Security: cada operador solo ve los envíos/eventos de su nodo
INSERT INTO seguridad.usuario_nodo (usuario, nodo) VALUES
    ('u_op_lima', 'LIMA'), ('u_op_norte', 'NORTE'), ('u_op_sur', 'SUR')
ON CONFLICT (usuario) DO UPDATE SET nodo = EXCLUDED.nodo;

CREATE OR REPLACE FUNCTION seguridad.fn_nodo_hub(p_id_hub INTEGER)
RETURNS VARCHAR LANGUAGE sql STABLE SECURITY DEFINER SET search_path = maestro, pg_temp AS
$$ SELECT r.nodo FROM maestro.hub h JOIN maestro.ciudad c USING (id_ciudad) JOIN maestro.region r USING (id_region)
    WHERE h.id_hub = p_id_hub $$;

CREATE OR REPLACE FUNCTION seguridad.fn_mi_nodo()
RETURNS VARCHAR LANGUAGE sql STABLE SECURITY DEFINER SET search_path = seguridad, pg_temp AS
$$ SELECT nodo FROM seguridad.usuario_nodo WHERE usuario = session_user $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA seguridad FROM PUBLIC;
GRANT USAGE ON SCHEMA seguridad TO rol_operador_hub, rol_atencion_cliente, rol_facturacion, rol_analista;
GRANT EXECUTE ON FUNCTION seguridad.fn_nodo_hub, seguridad.fn_mi_nodo
      TO rol_operador_hub, rol_atencion_cliente, rol_facturacion, rol_analista;

ALTER TABLE operacion.envio           ENABLE ROW LEVEL SECURITY;
ALTER TABLE operacion.evento_tracking ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_envio_operador_nodo ON operacion.envio;
CREATE POLICY p_envio_operador_nodo ON operacion.envio
    FOR SELECT TO rol_operador_hub
    USING (seguridad.fn_mi_nodo() IN (seguridad.fn_nodo_hub(id_hub_origen), seguridad.fn_nodo_hub(id_hub_destino)));

DROP POLICY IF EXISTS p_envio_lectura_global ON operacion.envio;
CREATE POLICY p_envio_lectura_global ON operacion.envio
    FOR SELECT TO rol_atencion_cliente, rol_facturacion
    USING (TRUE);

DROP POLICY IF EXISTS p_evento_operador_nodo ON operacion.evento_tracking;
CREATE POLICY p_evento_operador_nodo ON operacion.evento_tracking
    FOR SELECT TO rol_operador_hub
    USING (seguridad.fn_nodo_hub(id_hub) = seguridad.fn_mi_nodo());

DROP POLICY IF EXISTS p_evento_lectura_global ON operacion.evento_tracking;
CREATE POLICY p_evento_lectura_global ON operacion.evento_tracking
    FOR SELECT TO rol_atencion_cliente, rol_analista
    USING (TRUE);

-- Resumen de privilegios otorgados
SELECT grantee, table_schema, COUNT(*) AS privilegios
  FROM information_schema.role_table_grants
 WHERE grantee LIKE 'rol_%'
 GROUP BY 1, 2 ORDER BY 1, 2;
