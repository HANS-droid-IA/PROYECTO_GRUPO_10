SET search_path = operacion, maestro, public;

SELECT i.tipo,
       COALESCE(h.codigo, '(reclamo cliente)')                                  AS hub,
       COUNT(*)                                                                 AS incidencias,
       COUNT(*) FILTER (WHERE i.estado <> 'CERRADA')                            AS pendientes,
       ROUND(AVG(EXTRACT(EPOCH FROM i.fecha_cierre - i.fecha_reporte) / 86400)::NUMERIC, 1) AS dias_resolucion_prom
  FROM incidencia i
  LEFT JOIN hub h ON h.id_hub = i.id_hub
 WHERE i.tipo IN ('DANO', 'PERDIDA', 'RETRASO')
 GROUP BY 1, 2
 ORDER BY 1, 3 DESC;
