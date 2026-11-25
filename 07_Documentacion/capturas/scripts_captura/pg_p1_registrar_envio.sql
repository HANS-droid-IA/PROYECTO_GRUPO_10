\set ON_ERROR_ROLLBACK on
BEGIN;

SET search_path = operacion, maestro, public;
SELECT id_hub AS ag_mir FROM hub WHERE codigo = 'AG-LIM-MIR' \gset
SELECT id_hub AS ag_sur FROM hub WHERE codigo = 'AG-LIM-SUR' \gset
SELECT id_hub AS ag_iqt FROM hub WHERE codigo = 'AG-IQT-01' \gset
SELECT id_hub AS hc     FROM hub WHERE codigo = 'HC-LIM' \gset
SELECT MIN(id_empleado) AS emp_atencion FROM empleado WHERE id_hub = :ag_mir AND cargo = 'ATENCION' \gset
SELECT MIN(id_empleado) AS emp_operario FROM empleado WHERE id_hub = :hc AND cargo = 'OPERARIO_HUB' \gset
SELECT MIN(id_empleado) AS emp_courier  FROM empleado WHERE id_hub = :ag_sur AND cargo = 'COURIER' \gset
SELECT MIN(id_vehiculo) AS veh_mir FROM vehiculo WHERE id_hub_base = :ag_mir AND tipo = 'FURGONETA' \gset
SELECT MIN(id_vehiculo) AS veh_hc  FROM vehiculo WHERE id_hub_base = :hc AND tipo = 'FURGONETA' \gset
SELECT id_ruta AS ruta_mir_hc FROM ruta WHERE id_hub_origen = :ag_mir AND id_hub_destino = :hc AND modalidad = 'TERRESTRE' \gset
SELECT id_ruta AS ruta_hc_sur FROM ruta WHERE id_hub_origen = :hc AND id_hub_destino = :ag_sur AND modalidad = 'TERRESTRE' \gset
SELECT MIN(id_cliente) AS cliente FROM cliente WHERE tipo_cliente = 'EMPRESA' \gset

\echo '=== P1 CALL operacion.sp_registrar_envio (empresa, Miraflores -> Surco, 2 bultos en JSONB) ==='
CALL sp_registrar_envio(:cliente, 'Ana Torres Ríos', '45871236', '987654321', 'Av. Primavera 1450, Surco',
     3::SMALLINT, :ag_mir, :ag_sur,
     '[{"peso": 2.3, "largo": 40, "ancho": 30, "alto": 20, "descripcion": "Repuestos"},
       {"peso": 0.8, "largo": 25, "ancho": 20, "alto": 10, "descripcion": "Accesorios", "fragil": true}]',
     'CREDITO', :emp_atencion, NULL);
SELECT e.nro_tracking, e.estado_actual, e.peso_total_kg, e.monto_total, c.tipo, c.serie, c.numero, c.subtotal, c.igv, c.total
  FROM envio e JOIN comprobante c USING (id_envio) WHERE e.nro_tracking = (SELECT MAX(nro_tracking) FROM envio);
SELECT nro_bulto, peso_kg, descripcion, fragil FROM paquete WHERE id_envio = (SELECT MAX(id_envio) FROM envio);
\echo '--- Error controlado: servicio terrestre hacia Iquitos (ciudad sin acceso por carretera)'
CALL sp_registrar_envio(:cliente, 'Luis Ríos', NULL, '912345678', 'Calle Próspero 300', 3::SMALLINT, :ag_mir, :ag_iqt,
     '[{"peso": 1, "largo": 20, "ancho": 20, "alto": 20}]', 'TARJETA', :emp_atencion, NULL);
ROLLBACK;
\echo '>> Transacción revertida (prueba repetible).'
