-- =====================================================================
-- Integración Hadoop -> Cassandra: tablas de consulta rápida por hub para el panel operativo.
-- Se replican en las dos sedes (dc_lima y dc_arequipa) porque viven en el keyspace olva_tracking.
-- Lo ejecuta 03_integracion_end_to_end.sh (los CSV se copian a /tmp/kpi/ del nodo).
-- =====================================================================
USE olva_tracking;

-- "¿Cómo se comporta MI hub por hora, mes y día?"  -> una partición por hub
CREATE TABLE IF NOT EXISTS kpi_permanencia_hub (
    hub                    text,
    dimension              text,
    valor                  text,
    estancias              int,
    permanencia_promedio_h double,
    pct_mayor_12h          double,
    PRIMARY KEY ((hub), dimension, valor)
) WITH comment = 'KPI de permanencia calculados con Hadoop MapReduce';

-- "¿Cuál es el cumplimiento del SLA por servicio / ruta / mes / agencia?" -> una partición por dimensión
CREATE TABLE IF NOT EXISTS kpi_cumplimiento_sla (
    dimension            text,
    clave                text,
    detalle              text,
    envios               int,
    entregados           int,
    pct_cumplimiento_sla double,
    retraso_promedio_h   double,
    ingresos_soles       double,
    PRIMARY KEY ((dimension), clave, detalle)
) WITH comment = 'KPI de cumplimiento de SLA calculados con Hadoop MapReduce';

TRUNCATE kpi_permanencia_hub;
TRUNCATE kpi_cumplimiento_sla;

COPY kpi_permanencia_hub (dimension, hub, valor, estancias, permanencia_promedio_h, pct_mayor_12h)
  FROM '/tmp/kpi/permanencia_hub.csv' WITH HEADER = true;
COPY kpi_cumplimiento_sla (dimension, clave, detalle, envios, entregados, pct_cumplimiento_sla,
                           retraso_promedio_h, ingresos_soles)
  FROM '/tmp/kpi/cumplimiento_sla.csv' WITH HEADER = true;

-- Consulta del panel: comportamiento del Hub Central por hora de llegada
SELECT valor AS hora, estancias, permanencia_promedio_h, pct_mayor_12h
  FROM kpi_permanencia_hub WHERE hub = 'HC-LIM' AND dimension = 'HORA';

SELECT clave AS servicio, envios, pct_cumplimiento_sla, retraso_promedio_h
  FROM kpi_cumplimiento_sla WHERE dimension = 'SERVICIO';
