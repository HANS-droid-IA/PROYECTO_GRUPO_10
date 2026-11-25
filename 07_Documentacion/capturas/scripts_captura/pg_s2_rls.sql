\echo '=== Misma consulta, distinto usuario: Row Level Security por nodo ==='
SET SESSION AUTHORIZATION u_op_lima;
SELECT session_user AS usuario, seguridad.fn_mi_nodo() AS nodo, COUNT(*) AS envios_visibles FROM operacion.envio;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION u_op_norte;
SELECT session_user AS usuario, seguridad.fn_mi_nodo() AS nodo, COUNT(*) AS envios_visibles FROM operacion.envio;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION u_op_sur;
SELECT session_user AS usuario, seguridad.fn_mi_nodo() AS nodo, COUNT(*) AS envios_visibles FROM operacion.envio;
RESET SESSION AUTHORIZATION;
SELECT current_user AS usuario, 'propietario' AS nodo, COUNT(*) AS envios_visibles FROM operacion.envio;
