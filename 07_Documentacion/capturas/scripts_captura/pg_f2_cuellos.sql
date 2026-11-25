SET search_path = operacion, maestro, public;
\echo '=== F4 operacion.fn_cuellos_botella(desde, hasta, umbral_horas): función de tabla ==='
SELECT * FROM fn_cuellos_botella('2026-04-01', '2026-10-08', 12) LIMIT 8;
\echo '=== F3 operacion.fn_permanencia_hub: permanencia del envío OLV2600001112 en cada hub ==='
SELECT h.codigo AS hub, fn_permanencia_hub(e.id_envio, h.id_hub, '2026-10-07 18:00-05') AS permanencia
  FROM envio e CROSS JOIN hub h
 WHERE e.nro_tracking = 'OLV2600001112' AND h.codigo IN ('AG-AQP-01', 'HR-AQP', 'HC-LIM', 'AG-LIM-MIR');
