SET search_path = operacion, maestro, public;

WITH llegadas AS (
    SELECT EXTRACT(HOUR FROM fecha_hora)::INT AS hora, COUNT(*) AS n,
           COUNT(DISTINCT fecha_hora::DATE)  AS dias
      FROM evento_tracking
     WHERE tipo_evento = 'LLEGADA_HUB' AND id_hub = (SELECT id_hub FROM hub WHERE codigo = 'HC-LIM')
     GROUP BY 1
)
SELECT g.hora,
       COALESCE(ROUND(l.n::NUMERIC / NULLIF(l.dias, 0), 1), 0)                          AS llegadas_prom_por_dia,
       h.capacidad_hora,
       COALESCE(ROUND(100.0 * l.n / NULLIF(l.dias, 0) / h.capacidad_hora, 1), 0)         AS pct_capacidad,
       repeat('#', COALESCE((l.n / NULLIF(l.dias, 0) / 10)::INT, 0))                     AS grafico
  FROM generate_series(0, 23) AS g(hora)
  LEFT JOIN llegadas l ON l.hora = g.hora
  CROSS JOIN (SELECT capacidad_hora FROM hub WHERE codigo = 'HC-LIM') h
 ORDER BY g.hora;
