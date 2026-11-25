SET search_path = operacion, maestro, public;

SELECT * FROM fn_cuellos_botella('2026-04-01', '2026-10-08', 12) LIMIT 10;
