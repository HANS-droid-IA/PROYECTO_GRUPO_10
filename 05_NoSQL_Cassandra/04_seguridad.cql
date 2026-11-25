-- =====================================================================
-- 11.4  Administración de usuarios y control de accesos en Cassandra
--   Requiere authenticator: PasswordAuthenticator y authorizer: CassandraAuthorizer
--   (activados en docker-compose.yml). Se ejecuta como olva_admin.
--   La contraseña real reemplaza a __CLAVE_APP__ al ejecutar 00_ejecutar_todo.sh;
--   no se guarda en este archivo.
-- =====================================================================

-- La tabla de roles debe replicarse en el centro de datos (si se pierde, nadie entra)
ALTER KEYSPACE system_auth
  WITH replication = {'class': 'NetworkTopologyStrategy', 'dc_lima': 1};

-- Roles de grupo (sin LOGIN): agrupan permisos
DROP ROLE IF EXISTS rol_analista;
DROP ROLE IF EXISTS rol_operador_hub;
DROP ROLE IF EXISTS rol_portal_cliente;
CREATE ROLE rol_analista;
CREATE ROLE rol_operador_hub;
CREATE ROLE rol_portal_cliente;

-- Analista: solo lectura de todo el keyspace
GRANT SELECT ON KEYSPACE olva_tracking TO rol_analista;

-- Operador de hub: registra escaneos (MODIFY = INSERT/UPDATE/DELETE) y consulta
GRANT SELECT ON KEYSPACE olva_tracking TO rol_operador_hub;
GRANT MODIFY ON TABLE olva_tracking.eventos_por_envio   TO rol_operador_hub;
GRANT MODIFY ON TABLE olva_tracking.eventos_por_hub_dia TO rol_operador_hub;
GRANT MODIFY ON TABLE olva_tracking.estado_envio        TO rol_operador_hub;
GRANT MODIFY ON TABLE olva_tracking.contador_escaneos   TO rol_operador_hub;

-- Portal web del cliente: solo las dos tablas que necesita
GRANT SELECT ON TABLE olva_tracking.envios_por_cliente TO rol_portal_cliente;
GRANT SELECT ON TABLE olva_tracking.eventos_por_envio  TO rol_portal_cliente;

-- Usuarios (LOGIN) que heredan un rol
DROP ROLE IF EXISTS u_analista_cass;
DROP ROLE IF EXISTS u_operador_cass;
DROP ROLE IF EXISTS u_portal_web;
CREATE ROLE u_analista_cass WITH LOGIN = true AND PASSWORD = '__CLAVE_APP__';
CREATE ROLE u_operador_cass WITH LOGIN = true AND PASSWORD = '__CLAVE_APP__';
CREATE ROLE u_portal_web    WITH LOGIN = true AND PASSWORD = '__CLAVE_APP__';
GRANT rol_analista       TO u_analista_cass;
GRANT rol_operador_hub   TO u_operador_cass;
GRANT rol_portal_cliente TO u_portal_web;

-- El superusuario por defecto "cassandra" queda deshabilitado (buena práctica)
ALTER ROLE cassandra WITH LOGIN = false;

LIST ROLES;
LIST ALL PERMISSIONS OF rol_operador_hub;
LIST ALL PERMISSIONS OF rol_portal_cliente;
