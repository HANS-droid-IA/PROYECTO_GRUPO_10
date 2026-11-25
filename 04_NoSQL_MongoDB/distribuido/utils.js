// Utilidades de presentación para mongosh (igual que ../utils.js)
function titulo(t) { print('\n=== ' + t + ' ==='); }

function valor(v) {
    if (v === null || v === undefined) return '';
    if (v instanceof Date) return v.toISOString().replace('T', ' ').substring(0, 19);
    if (Array.isArray(v)) return v.map(valor).join(', ');
    if (typeof v === 'object') return JSON.stringify(v);
    if (typeof v === 'number' && !Number.isInteger(v)) return v.toFixed(2);
    return String(v);
}

function tabla(filas) {
    if (!filas.length) { print('(0 documentos)'); return; }
    const cols = [];
    filas.forEach(f => Object.keys(f).forEach(k => { if (!cols.includes(k)) cols.push(k); }));
    const celdas = filas.map(f => cols.map(c => valor(f[c])));
    const ancho = cols.map((c, i) => Math.min(60, Math.max(c.length, ...celdas.map(r => r[i].length))));
    const linea = r => r.map((v, i) => v.substring(0, ancho[i]).padEnd(ancho[i])).join(' | ');
    print(linea(cols));
    print(ancho.map(a => '-'.repeat(a)).join('-+-'));
    celdas.forEach(r => print(linea(r)));
    print('(' + filas.length + ' fila' + (filas.length === 1 ? ')' : 's)'));
}

// sede a la que pertenece cada nodo de origen
const SEDE_DE_NODO = { LIMA: 'sede_lima', NORTE: 'sede_arequipa', SUR: 'sede_arequipa' };
