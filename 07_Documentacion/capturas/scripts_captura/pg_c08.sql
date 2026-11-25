SET search_path = operacion, maestro, public;

WITH intentos AS (
    SELECT c.nombre AS ciudad, i.*
      FROM intento_entrega i
      JOIN envio e USING (id_envio)
      JOIN hub h ON h.id_hub = e.id_hub_destino
      JOIN ciudad c ON c.id_ciudad = h.id_ciudad
), motivos AS (
    SELECT ciudad, resultado, COUNT(*) AS n
      FROM intentos WHERE resultado <> 'ENTREGADO' GROUP BY 1, 2
)
SELECT i.ciudad,
       COUNT(DISTINCT i.id_envio)                                                         AS envios_en_reparto,
       ROUND(100.0 * COUNT(*) FILTER (WHERE nro_intento = 1 AND resultado = 'ENTREGADO')
             / COUNT(DISTINCT i.id_envio), 1)                                             AS pct_primer_intento,
       ROUND(COUNT(*)::NUMERIC / COUNT(DISTINCT i.id_envio), 2)                           AS intentos_por_envio,
       (SELECT STRING_AGG(m.resultado || ':' || m.n, ', ' ORDER BY m.n DESC)
          FROM motivos m WHERE m.ciudad = i.ciudad)                                       AS motivos_falla
  FROM intentos i
 GROUP BY i.ciudad
 ORDER BY pct_primer_intento
 LIMIT 10;
