-- 3 consultas de demostración (cada una por clave de partición)
-- 1) Recorrido completo de un envío
SELECT fecha_hora, tipo_evento, hub, ciudad FROM olva_tracking.eventos_por_envio WHERE nro_tracking = 'OLV2600000004';
-- 2) Escaneos por hora en el Hub Central Lima (noche del 27/06/2026)
SELECT hora, escaneos, llegadas, salidas FROM olva_tracking.escaneos_hub_hora WHERE hub = 'HC-LIM' AND dia = '2026-06-27' AND hora >= 18;
-- 3) Indicador de Hadoop guardado en Cassandra: permanencia mensual del Hub Arequipa
SELECT valor AS mes, estancias, permanencia_promedio_h, pct_mayor_12h FROM olva_tracking.kpi_permanencia_hub WHERE hub = 'HR-AQP' AND dimension = 'MES';
