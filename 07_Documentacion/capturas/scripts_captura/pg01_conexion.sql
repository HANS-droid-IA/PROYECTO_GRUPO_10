\conninfo
SELECT version();
SELECT current_database() AS base_de_datos, current_user AS usuario,
       current_setting('TimeZone') AS zona_horaria, pg_encoding_to_char(encoding) AS codificacion,
       pg_size_pretty(pg_database_size(current_database())) AS tamano
  FROM pg_database WHERE datname = current_database();
