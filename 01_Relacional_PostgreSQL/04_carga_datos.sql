-- =====================================================================
-- 04 - Poblamiento de datos de prueba (DML masivo con COPY)
-- Fuente: CSV sintéticos generados por generador/generar_datos.py
-- Se ejecuta ANTES de crear los triggers: los CSV ya traen el estado
-- final consistente de cada envío (equivale a migrar un histórico).
-- =====================================================================
\set ON_ERROR_STOP on
\timing on
SET datestyle = 'ISO, YMD';

BEGIN;
COPY maestro.region          FROM '/proyecto/01_Relacional_PostgreSQL/datos/region.csv'          WITH (FORMAT csv, HEADER true);
COPY maestro.ciudad          FROM '/proyecto/01_Relacional_PostgreSQL/datos/ciudad.csv'          WITH (FORMAT csv, HEADER true);
COPY maestro.hub             FROM '/proyecto/01_Relacional_PostgreSQL/datos/hub.csv'             WITH (FORMAT csv, HEADER true);
COPY maestro.tipo_servicio   FROM '/proyecto/01_Relacional_PostgreSQL/datos/tipo_servicio.csv'   WITH (FORMAT csv, HEADER true);
COPY maestro.tarifa          FROM '/proyecto/01_Relacional_PostgreSQL/datos/tarifa.csv'          WITH (FORMAT csv, HEADER true);
COPY maestro.ruta            FROM '/proyecto/01_Relacional_PostgreSQL/datos/ruta.csv'            WITH (FORMAT csv, HEADER true);
COPY maestro.vehiculo        FROM '/proyecto/01_Relacional_PostgreSQL/datos/vehiculo.csv'        WITH (FORMAT csv, HEADER true);
COPY maestro.empleado        FROM '/proyecto/01_Relacional_PostgreSQL/datos/empleado.csv'        WITH (FORMAT csv, HEADER true);
COPY maestro.cliente         FROM '/proyecto/01_Relacional_PostgreSQL/datos/cliente.csv'         WITH (FORMAT csv, HEADER true);
COPY operacion.destinatario  FROM '/proyecto/01_Relacional_PostgreSQL/datos/destinatario.csv'    WITH (FORMAT csv, HEADER true);
COPY operacion.envio         FROM '/proyecto/01_Relacional_PostgreSQL/datos/envio.csv'           WITH (FORMAT csv, HEADER true);
COPY operacion.paquete       FROM '/proyecto/01_Relacional_PostgreSQL/datos/paquete.csv'         WITH (FORMAT csv, HEADER true);
COPY operacion.comprobante   FROM '/proyecto/01_Relacional_PostgreSQL/datos/comprobante.csv'     WITH (FORMAT csv, HEADER true);
COPY operacion.despacho      FROM '/proyecto/01_Relacional_PostgreSQL/datos/despacho.csv'        WITH (FORMAT csv, HEADER true);
COPY operacion.despacho_envio FROM '/proyecto/01_Relacional_PostgreSQL/datos/despacho_envio.csv' WITH (FORMAT csv, HEADER true);
COPY operacion.evento_tracking FROM '/proyecto/01_Relacional_PostgreSQL/datos/evento_tracking.csv' WITH (FORMAT csv, HEADER true);
COPY operacion.intento_entrega FROM '/proyecto/01_Relacional_PostgreSQL/datos/intento_entrega.csv' WITH (FORMAT csv, HEADER true);
COPY operacion.incidencia    FROM '/proyecto/01_Relacional_PostgreSQL/datos/incidencia.csv'      WITH (FORMAT csv, HEADER true);
COMMIT;

-- Sincronizar las secuencias IDENTITY con los IDs cargados
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT n.nspname AS esquema, c.relname AS tabla, a.attname AS columna
          FROM pg_attribute a
          JOIN pg_class c ON c.oid = a.attrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE a.attidentity = 'd' AND n.nspname IN ('maestro', 'operacion')
    LOOP
        EXECUTE format('SELECT setval(pg_get_serial_sequence(%L, %L), COALESCE((SELECT MAX(%I) FROM %I.%I), 0) + 1, false)',
                       r.esquema || '.' || r.tabla, r.columna, r.columna, r.esquema, r.tabla);
    END LOOP;
END $$;

ANALYZE;

-- Resumen de la carga
SELECT 'maestro.' || relname AS tabla, n_live_tup AS filas
  FROM pg_stat_user_tables WHERE schemaname = 'maestro'
UNION ALL
SELECT 'operacion.' || relname, n_live_tup
  FROM pg_stat_user_tables WHERE schemaname = 'operacion'
ORDER BY 1;
