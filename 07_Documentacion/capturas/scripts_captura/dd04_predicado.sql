\echo '=== Integridad del predicado: un nodo rechaza filas que no le pertenecen ==='
\echo '--- error esperado: insertar en el fragmento SUR un envío cuyo origen es Lima'
\set ON_ERROR_STOP off
INSERT INTO global.envio_sur
SELECT id_envio + 9000000, 'OLV9' || SUBSTRING(nro_tracking FROM 5), id_cliente, id_destinatario, id_servicio, id_hub_origen,
       id_hub_destino, direccion_entrega, fecha_registro, fecha_compromiso, estado_actual, peso_total_kg, valor_declarado,
       monto_total, fecha_entrega, 'SUR'
  FROM global.envio WHERE nodo = 'LIMA' LIMIT 1;
