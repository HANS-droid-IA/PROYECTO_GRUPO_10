SET search_path = operacion, maestro, public;

SELECT CASE WHEN GROUPING(ro.nombre) = 1 THEN '** TOTAL **' ELSE ro.nombre END   AS region_origen,
       CASE WHEN GROUPING(rd.nombre) = 1 THEN '(subtotal)'  ELSE rd.nombre END   AS region_destino,
       COUNT(*)                                                                  AS envios,
       SUM(e.monto_total)                                                        AS ingresos_soles,
       ROUND(AVG(e.monto_total), 2)                                              AS ticket_prom
  FROM envio e
  JOIN hub ho ON ho.id_hub = e.id_hub_origen  JOIN ciudad co ON co.id_ciudad = ho.id_ciudad JOIN region ro ON ro.id_region = co.id_region
  JOIN hub hd ON hd.id_hub = e.id_hub_destino JOIN ciudad cd ON cd.id_ciudad = hd.id_ciudad JOIN region rd ON rd.id_region = cd.id_region
 GROUP BY ROLLUP (ro.nombre, rd.nombre)
 ORDER BY GROUPING(ro.nombre), ro.nombre, GROUPING(rd.nombre), ingresos_soles DESC;
