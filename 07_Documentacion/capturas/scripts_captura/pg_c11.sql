SET search_path = operacion, maestro, public;

WITH prod AS (
    SELECT emp.id_hub, emp.nombres || ' ' || emp.apellidos AS courier,
           COUNT(*) FILTER (WHERE i.resultado = 'ENTREGADO')              AS entregas,
           COUNT(DISTINCT i.fecha_hora::DATE)                             AS dias_trabajados
      FROM intento_entrega i
      JOIN empleado emp ON emp.id_empleado = i.id_courier
     GROUP BY 1, 2
)
SELECT * FROM (
    SELECT h.codigo AS agencia, p.courier, p.entregas, p.dias_trabajados,
           ROUND(p.entregas::NUMERIC / NULLIF(p.dias_trabajados, 0), 2)            AS entregas_por_dia,
           DENSE_RANK() OVER (PARTITION BY p.id_hub ORDER BY p.entregas DESC)       AS rank_agencia
      FROM prod p JOIN hub h ON h.id_hub = p.id_hub
) t
 WHERE agencia LIKE 'AG-LIM%'
 ORDER BY agencia, rank_agencia;
