-- =====================================================================
-- Integración Hadoop -> PostgreSQL: esquema "analitica" con los indicadores calculados por MapReduce.
-- PostgreSQL es la base transaccional (origen de los datos); aquí recibe de vuelta los KPI para que
-- los reportes y el personal de gestión los consulten con SQL junto a los maestros (hubs, servicios).
-- Lo ejecuta 06_BigData_Hadoop/03_integracion_end_to_end.sh (la carga usa \copy desde los CSV).
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS analitica;

DROP TABLE IF EXISTS analitica.kpi_permanencia_hub CASCADE;
CREATE TABLE analitica.kpi_permanencia_hub (
    dimension              VARCHAR(10)   NOT NULL CHECK (dimension IN ('HORA', 'MES', 'DIA')),
    codigo_hub             VARCHAR(12)   NOT NULL,
    valor                  VARCHAR(15)   NOT NULL,
    estancias              INTEGER       NOT NULL CHECK (estancias > 0),
    permanencia_promedio_h NUMERIC(8, 2) NOT NULL,
    pct_mayor_12h          NUMERIC(5, 2) NOT NULL,
    fuente                 VARCHAR(60)   NOT NULL DEFAULT 'hdfs:/olva/resultados/permanencia_hub',
    fecha_carga            TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (dimension, codigo_hub, valor)
);

DROP TABLE IF EXISTS analitica.kpi_cumplimiento_sla CASCADE;
CREATE TABLE analitica.kpi_cumplimiento_sla (
    dimension            VARCHAR(16)    NOT NULL,
    clave                VARCHAR(30)    NOT NULL,
    detalle              VARCHAR(40)    NOT NULL,
    envios               INTEGER        NOT NULL,
    entregados           INTEGER        NOT NULL,
    pct_cumplimiento_sla NUMERIC(5, 2)  NOT NULL,
    retraso_promedio_h   NUMERIC(8, 2)  NOT NULL,
    ingresos_soles       NUMERIC(14, 2) NOT NULL,
    fuente               VARCHAR(60)    NOT NULL DEFAULT 'hdfs:/olva/resultados/cumplimiento_sla',
    fecha_carga          TIMESTAMPTZ    NOT NULL DEFAULT now(),
    PRIMARY KEY (dimension, clave, detalle)
);

-- Vista de decisión: franjas horarias críticas por hub, enlazadas con el maestro de hubs
CREATE OR REPLACE VIEW analitica.vw_franjas_criticas AS
SELECT h.codigo, h.nombre, h.tipo, h.capacidad_hora,
       k.valor AS hora_llegada, k.estancias, k.permanencia_promedio_h, k.pct_mayor_12h,
       round(100.0 * k.estancias / sum(k.estancias) OVER (PARTITION BY k.codigo_hub), 2) AS pct_llegadas_del_hub,
       rank() OVER (PARTITION BY k.codigo_hub ORDER BY k.estancias DESC) AS ranking_volumen
FROM analitica.kpi_permanencia_hub k
JOIN maestro.hub h ON h.codigo = k.codigo_hub
WHERE k.dimension = 'HORA';

GRANT USAGE ON SCHEMA analitica TO rol_analista, rol_admin_olva;
GRANT SELECT ON ALL TABLES IN SCHEMA analitica TO rol_analista;
GRANT ALL ON ALL TABLES IN SCHEMA analitica TO rol_admin_olva;
