SELECT conname AS restriccion,
       CASE contype WHEN 'p' THEN 'PRIMARY KEY' WHEN 'f' THEN 'FOREIGN KEY' WHEN 'u' THEN 'UNIQUE' WHEN 'c' THEN 'CHECK' END AS tipo,
       pg_get_constraintdef(oid) AS definicion
  FROM pg_constraint WHERE conrelid = 'operacion.envio'::regclass
 ORDER BY contype DESC, conname;
