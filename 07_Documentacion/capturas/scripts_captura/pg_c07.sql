SET search_path = operacion, maestro, public;

WITH por_cliente AS (
    SELECT c.id_cliente, c.nombre_razon_social, ci.nombre AS ciudad,
           COUNT(*)                                                           AS envios,
           SUM(e.monto_total)                                                 AS facturado,
           ROUND(100.0 * AVG((e.fecha_entrega <= e.fecha_compromiso)::INT)
                 FILTER (WHERE e.estado_actual = 'ENTREGADO'), 1)             AS pct_a_tiempo
      FROM envio e
      JOIN cliente c USING (id_cliente)
      JOIN ciudad ci ON ci.id_ciudad = c.id_ciudad
     WHERE c.tipo_cliente = 'EMPRESA'
     GROUP BY 1, 2, 3
)
SELECT RANK() OVER (ORDER BY facturado DESC)                         AS puesto,
       nombre_razon_social, ciudad, envios, facturado,
       ROUND(100.0 * facturado / SUM(facturado) OVER (), 2)          AS pct_facturacion_empresas,
       pct_a_tiempo
  FROM por_cliente
 ORDER BY facturado DESC
 LIMIT 10;
