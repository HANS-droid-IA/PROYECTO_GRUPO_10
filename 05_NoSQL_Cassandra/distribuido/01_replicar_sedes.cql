-- =====================================================================
-- Cassandra con 2 sedes: un centro de datos por sede (dc_lima y dc_arequipa)
-- A diferencia de PostgreSQL (fragmentos) y MongoDB (shards por zona),
-- Cassandra REPLICA: cada sede guarda una copia completa del keyspace y
-- responde sola, sin un servidor central (no hay coordinador ni maestro).
-- =====================================================================

-- 1) Roles y permisos replicados en ambas sedes: si una cae, en la otra se sigue iniciando sesión
ALTER KEYSPACE system_auth
  WITH replication = {'class': 'NetworkTopologyStrategy', 'dc_lima': 1, 'dc_arequipa': 1};

-- 2) Datos de tracking: una réplica en cada sede (RF total = 2)
ALTER KEYSPACE olva_tracking
  WITH replication = {'class': 'NetworkTopologyStrategy', 'dc_lima': 1, 'dc_arequipa': 1};

-- 3) Localización de datos: keyspace que vive SOLO en la sede Arequipa
--    (equivale a un fragmento local: el dato no sale de su sede)
DROP KEYSPACE IF EXISTS olva_sede_arequipa;
CREATE KEYSPACE olva_sede_arequipa
  WITH replication = {'class': 'NetworkTopologyStrategy', 'dc_arequipa': 1};
CREATE TABLE olva_sede_arequipa.operaciones_locales (
    hub          text,
    dia          date,
    fecha_hora   timestamp,
    operacion    text,
    detalle      text,
    PRIMARY KEY ((hub, dia), fecha_hora)
) WITH CLUSTERING ORDER BY (fecha_hora DESC)
  AND comment = 'Datos operativos que solo interesan a la sede Arequipa';

SELECT keyspace_name, replication FROM system_schema.keyspaces
 WHERE keyspace_name IN ('olva_tracking', 'system_auth', 'olva_sede_arequipa');
