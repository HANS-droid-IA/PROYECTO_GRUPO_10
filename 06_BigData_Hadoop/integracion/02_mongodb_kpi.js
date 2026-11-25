// =====================================================================
// Integración Hadoop -> MongoDB: colección olva_tracking.kpi_bigdata
// Los indicadores se guardan como documentos (uno por hub/franja o por servicio/ruta) para que el
// portal y los paneles los lean junto al expediente del envío. Carga idempotente (upsert por _id).
// Uso: mongosh ... olva_tracking /tmp/02_mongodb_kpi.js   (los CSV se copian a /tmp/kpi/)
// =====================================================================
const fs = require('fs');

function leerCsv(ruta) {
    const lineas = fs.readFileSync(ruta, 'utf8').trim().split('\n');
    const cab = lineas.shift().split(',');
    return lineas.map(l => {
        const v = l.split(',');
        return Object.fromEntries(cab.map((c, i) => [c, isNaN(v[i]) || v[i] === '' ? v[i] : Number(v[i])]));
    });
}

const ahora = new Date();
const ops = [];
for (const r of leerCsv('/tmp/kpi/permanencia_hub.csv')) {
    ops.push({ replaceOne: { upsert: true, filter: { _id: `PERMANENCIA|${r.dimension}|${r.hub}|${r.valor}` },
        replacement: { indicador: 'permanencia_hub', dimension: r.dimension, hub: r.hub, valor: String(r.valor),
                       estancias: r.estancias, permanencia_promedio_h: r.permanencia_promedio_h,
                       pct_mayor_12h: r.pct_mayor_12h, fuente: 'hdfs:/olva/resultados/permanencia_hub',
                       fecha_carga: ahora } } });
}
for (const r of leerCsv('/tmp/kpi/cumplimiento_sla.csv')) {
    ops.push({ replaceOne: { upsert: true, filter: { _id: `SLA|${r.dimension}|${r.clave}|${r.detalle}` },
        replacement: { indicador: 'cumplimiento_sla', dimension: r.dimension, clave: String(r.clave),
                       detalle: r.detalle, envios: r.envios, entregados: r.entregados,
                       pct_cumplimiento_sla: r.pct_cumplimiento_sla, retraso_promedio_h: r.retraso_promedio_h,
                       ingresos_soles: r.ingresos_soles, fuente: 'hdfs:/olva/resultados/cumplimiento_sla',
                       fecha_carga: ahora } } });
}
const res = db.kpi_bigdata.bulkWrite(ops, { ordered: false });
db.kpi_bigdata.createIndex({ indicador: 1, dimension: 1, hub: 1 }, { name: 'ix_kpi_indicador_dim_hub' });

// el rol de analista (Avance NoSQL) también puede leer los KPI de Big Data
db.grantPrivilegesToRole('rol_analista',
    [{ resource: { db: 'olva_tracking', collection: 'kpi_bigdata' }, actions: ['find'] }]);

print(`kpi_bigdata: ${res.upsertedCount} insertados, ${res.modifiedCount} actualizados, total ${db.kpi_bigdata.countDocuments()}`);
print('Franjas del Hub Central con más llegadas (leídas desde MongoDB):');
db.kpi_bigdata.find({ indicador: 'permanencia_hub', dimension: 'HORA', hub: 'HC-LIM' },
                    { _id: 0, valor: 1, estancias: 1, permanencia_promedio_h: 1, pct_mayor_12h: 1 })
    .sort({ estancias: -1 }).limit(3).forEach(d => printjson(d));
