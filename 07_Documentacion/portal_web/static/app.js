// Portal Olva Courier: consulta las 5 bases a través de la API Flask y dibuja tablas y rastreo cruzado.
const MOTORES = {
  postgresql: { nombre: 'PostgreSQL', color: 'var(--pg)', rol: 'Transaccional (fuente de verdad)' },
  oracle:     { nombre: 'Oracle',     color: 'var(--oracle)', rol: 'Implementación comparativa' },
  mongodb:    { nombre: 'MongoDB',    color: 'var(--mongodb)', rol: 'Expediente documental' },
  cassandra:  { nombre: 'Cassandra',  color: 'var(--cassandra)', rol: 'Estado y escaneos en línea' },
  hadoop:     { nombre: 'Hadoop HDFS', color: 'var(--hadoop)', rol: 'Big Data (lotes)' },
};
const datos = {};
let activa = 'postgresql';

const $ = (s, el = document) => el.querySelector(s);
const esc = (v) => String(v ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmt = (v) => (typeof v === 'number' ? v.toLocaleString('es-PE') : v);

function celda(col, v) {
  if (col === 'nro_tracking') return `<td><a class="trk" data-trk="${esc(v)}">${esc(v)}</a></td>`;
  if (/estado/.test(col)) return `<td><span class="chip ${esc(v)}">${esc(v)}</span></td>`;
  const num = typeof v === 'number' || /^-?\d+(\.\d+)?$/.test(String(v ?? ''));
  return `<td class="${num ? 'num' : ''}">${esc(fmt(v))}</td>`;
}

function tabla(filas) {
  if (!filas.length) return '<p class="nota">Sin registros.</p>';
  const cols = Object.keys(filas[0]);
  return `<div class="tabla-scroll"><table><thead><tr><th>#</th>${cols.map((c) => `<th>${esc(c)}</th>`).join('')}</tr></thead>
    <tbody>${filas.map((f, i) => `<tr><td class="num">${i + 1}</td>${cols.map((c) => celda(c, f[c])).join('')}</tr>`).join('')}</tbody></table></div>`;
}

function pintarTarjeta(m) {
  const t = $(`.tarjeta[data-motor="${m}"]`);
  const r = datos[m];
  t.style.setProperty('--c', MOTORES[m].color);
  $('.nombre', t).textContent = MOTORES[m].nombre;
  t.classList.remove('cargando', 'ok', 'falla');
  if (!r) return;
  t.classList.add(r.ok ? 'ok' : 'falla');
  $('.filas', t).textContent = r.ok ? r.filas.length : 0;
  $('.ms', t).textContent = r.ok ? `conectado · ${r.ms} ms` + (r.total ? ` · ${fmt(r.total)} en total` : '') : 'sin conexión';
  t.title = r.ok ? MOTORES[m].rol : r.error;
}

async function pintarContenido() {
  const r = datos[activa];
  const c = $('#contenido');
  if (!r) { c.innerHTML = '<p class="nota">Consultando…</p>'; return; }
  if (!r.ok) {
    c.innerHTML = `<div class="error-box"><b>${MOTORES[activa].nombre} no respondió.</b><br>${esc(r.error)}</div>`;
    return;
  }
  c.innerHTML = `<div class="info"><span>${esc(r.descripcion)}</span><span>${r.filas.length} registros · ${r.ms} ms</span></div>
    ${tabla(r.filas)}${activa === 'hadoop' ? '<div class="kpi" id="kpi"><p class="nota">Cargando indicadores…</p></div>' : ''}`;
  if (activa === 'hadoop') pintarKpi();
}

async function pintarKpi() {
  const r = await fetch('/api/hadoop/kpi').then((x) => x.json()).catch((e) => ({ ok: false, error: e.message }));
  const k = $('#kpi');
  if (!k) return;
  if (!r.ok) { k.innerHTML = `<p class="err">${esc(r.error)}</p>`; return; }
  const max = Math.max(...r.filas.map((f) => +f.estancias));
  k.innerHTML = `<h3>Resultado MapReduce: llegadas al Hub Central Lima por hora</h3>
    <p>Archivo /olva/resultados/permanencia_hub en HDFS. Pasa el cursor sobre una barra para ver la permanencia promedio.</p>
    <div class="barras">${r.filas.map((f) => `<div class="barra ${+f.estancias === max ? 'pico' : ''}"
      style="height:${Math.max(1, (100 * f.estancias) / max)}%"
      data-tip="${f.valor}:00 · ${(+f.estancias).toLocaleString('es-PE')} paquetes · ${f.permanencia_promedio_h} h"></div>`).join('')}</div>
    <div class="ejes">${r.filas.map((f) => `<span>${f.valor}</span>`).join('')}</div>`;
}

function dl(obj) {
  if (!obj) return '<p class="nota">No encontrado.</p>';
  return `<dl>${Object.entries(obj).map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(fmt(v))}</dd>`).join('')}</dl>`;
}

async function rastrear(trk) {
  const caja = $('#rastreo');
  caja.className = 'rastreo vacio';
  caja.textContent = `Buscando ${trk} en las cinco bases…`;
  const r = await fetch(`/api/rastreo/${encodeURIComponent(trk)}`).then((x) => x.json()).catch((e) => ({ error: e.message }));
  if (r.error) { caja.innerHTML = `<span class="err">${esc(r.error)}</span>`; return; }
  caja.className = 'rastreo';
  const res = r.resultados;
  let html = Object.keys(MOTORES).map((m) => {
    const x = res[m];
    let cuerpo;
    if (!x.ok) cuerpo = `<p class="err">${esc(x.error)}</p>`;
    else if (m === 'hadoop') cuerpo = x.datos.linea_csv
      ? `<dl><dt>archivo</dt><dd><code>${esc(x.datos.archivo_hdfs)}</code></dd><dt>línea</dt><dd><code>${esc(x.datos.linea_csv)}</code></dd></dl>`
      : '<p class="nota">No está en la extracción de HDFS.</p>';
    else {
      const ev = x.datos.eventos ? `<p class="nota">${x.datos.eventos.length} eventos de tracking</p>` : '';
      cuerpo = dl(x.datos.envio) + ev + (x.datos.nota ? `<p class="nota">${esc(x.datos.nota)}</p>` : '');
    }
    return `<div class="caja" style="--c:${MOTORES[m].color}"><h3>${MOTORES[m].nombre}<small>${x.ms} ms</small></h3>${cuerpo}</div>`;
  }).join('');
  const ev = res.postgresql.ok && res.postgresql.datos.eventos;
  if (ev && ev.length) {
    html += `<div class="linea-tiempo"><h3>Recorrido del envío ${esc(r.tracking)} (PostgreSQL · operacion.evento_tracking)</h3><ol>
      ${ev.map((e) => `<li><b>${esc(e.tipo_evento)}</b>${esc(e.hub)} · ${esc(String(e.fecha_hora).slice(0, 16))}</li>`).join('')}</ol></div>`;
  }
  caja.innerHTML = html;
}

async function cargarTodo() {
  Object.keys(MOTORES).forEach((m) => { delete datos[m]; pintarTarjeta(m); });
  pintarContenido();
  await Promise.all(Object.keys(MOTORES).map(async (m) => {
    datos[m] = await fetch(`/api/${m}`).then((x) => x.json()).catch((e) => ({ ok: false, error: e.message, filas: [] }));
    pintarTarjeta(m);
    if (m === activa) pintarContenido();
  }));
}

function activar(m) {
  activa = m;
  document.querySelectorAll('#pestanas button').forEach((b) => b.classList.toggle('activa', b.dataset.motor === m));
  pintarContenido();
}

document.querySelectorAll('#pestanas button').forEach((b) => {
  b.textContent = MOTORES[b.dataset.motor].nombre;
  b.style.setProperty('--c', MOTORES[b.dataset.motor].color);
  b.addEventListener('click', () => activar(b.dataset.motor));
});
document.querySelectorAll('.tarjeta').forEach((t) => t.addEventListener('click', () => activar(t.dataset.motor)));
document.addEventListener('click', (e) => {
  const a = e.target.closest('a.trk');
  if (a) { $('#tracking').value = a.dataset.trk; rastrear(a.dataset.trk); $('#form-rastreo').scrollIntoView({ behavior: 'smooth' }); }
});
$('#form-rastreo').addEventListener('submit', (e) => { e.preventDefault(); rastrear($('#tracking').value.trim().toUpperCase()); });
$('#btn-recargar').addEventListener('click', cargarTodo);

// la carga inicial la hace sitio.js al abrir cada sección

// ---------------------------------------------------------------- operación: registrar y mover envíos
const ESTADOS = ['ADMITIDO', 'EN_TRANSITO', 'EN_HUB', 'EN_REPARTO', 'ENTREGADO'];
let enCurso = null;
let automatico = false;

async function cargarCatalogos() {
  const c = await fetch('/api/catalogos').then((x) => x.json());
  const f = $('#form-envio');
  f.cliente.innerHTML = c.clientes.map((x) => `<option value="${x.id}">${esc(x.nombre)} (${x.tipo.toLowerCase()})</option>`).join('');
  f.servicio.innerHTML = c.servicios.map((x) => `<option value="${x.id}">${esc(x.nombre)} · ${x.sla_horas} h</option>`).join('');
  const ag = c.agencias.map((x) => `<option value="${x.id}">${esc(x.ciudad)} – ${esc(x.nombre)} (${x.codigo})</option>`).join('');
  f.origen.innerHTML = ag;
  f.destino.innerHTML = ag;
  const porCodigo = (cod) => (c.agencias.find((a) => a.codigo === cod) || {}).id;
  f.origen.value = porCodigo('AG-LIM-MIR') || c.agencias[0].id;
  f.destino.value = porCodigo('AG-CUZ-01') || c.agencias[1].id;
}

async function cargarRecientes() {
  const r = await fetch('/api/envios/recientes').then((x) => x.json()).catch(() => []);
  $('#recientes').innerHTML = r.length
    ? r.map((e) => `<li data-trk="${e.nro_tracking}"><b>${e.nro_tracking}</b><span>${e.origen} → ${e.destino}</span>
        <span class="chip ${e.estado}">${e.estado}</span></li>`).join('')
    : '<li class="nota">Todavía no hay envíos registrados desde el portal.</li>';
}

function pintarCurso(r) {
  enCurso = r.tracking;
  const terminado = ['ENTREGADO', 'DEVUELTO'].includes(r.estado);
  const idx = ESTADOS.indexOf(r.estado === 'INTENTO_FALLIDO' ? 'EN_REPARTO' : r.estado);
  const pasos = ['REGISTRADO', ...ESTADOS].map((e, i) =>
    `<div class="${i - 1 < idx ? 'hecho' : ''} ${i - 1 === idx ? 'actual' : ''}">${e.replace('_', ' ')}</div>`).join('');
  const sync = Object.keys(MOTORES).map((m) => {
    const s = r.sincronizacion[m];
    return `<div class="flash" style="--c:${MOTORES[m].color}"><b>${MOTORES[m].nombre}
      <span class="${s.ok ? 'ok-ico' : 'ko-ico'}">${s.ok ? '✔' : '✖'} ${s.ms} ms</span></b><span>${esc(s.detalle)}</span></div>`;
  }).join('');
  $('#curso').className = 'curso';
  $('#curso').innerHTML = `
    <div class="curso-cab"><span class="trk-grande">${r.tracking}</span><span class="chip ${r.estado}">${r.estado}</span></div>
    <div class="pasos">${pasos}</div>
    <div class="ultimo-paso">▶ ${esc(r.paso || 'Estado leído de PostgreSQL')}</div>
    <div class="sync">${sync}</div>
    <div class="botones">
      <button id="btn-avanzar" ${terminado ? 'disabled' : ''}>Registrar siguiente escaneo</button>
      <button id="btn-auto" class="sec" ${terminado ? 'disabled' : ''}>${automatico ? '⏸ Detener' : '⏩ Completar recorrido'}</button>
      <button id="btn-ver" class="sec">📍 Ver seguimiento</button>
    </div>`;
  $('#btn-avanzar').onclick = () => avanzar();
  $('#btn-auto').onclick = () => { automatico = !automatico; if (automatico) recorrer(); else pintarCurso(r); };
  $('#btn-ver').onclick = () => { location.hash = '#/rastrear/' + r.tracking; };
}

async function refrescarTodo(trk) {
  cargarRecientes();
  rastrear(trk);
  $('#tracking').value = trk;
  await cargarTodo();
  document.querySelectorAll(`a.trk[data-trk="${trk}"]`).forEach((a) => a.closest('tr').classList.add('nuevo'));
}

async function avanzar() {
  if (!enCurso) return;
  document.querySelectorAll('#curso button').forEach((b) => { if (b.id !== 'btn-auto') b.disabled = true; });
  const r = await fetch(`/api/envios/${enCurso}/avanzar`, { method: 'POST' }).then((x) => x.json())
    .catch((e) => ({ ok: false, error: e.message }));
  if (!r.ok) { automatico = false; $('.ultimo-paso').innerHTML = `<span class="err">${esc(r.error)}</span>`; return false; }
  pintarCurso(r);
  refrescarTodo(r.tracking);
  return !['ENTREGADO', 'DEVUELTO'].includes(r.estado);
}

async function recorrer() {
  pintarCurso({ ...(await abrir(enCurso, true)) });
  while (automatico && await avanzar()) await new Promise((ok) => setTimeout(ok, 1200));
  automatico = false;
  if (enCurso) $('#btn-auto') && ($('#btn-auto').textContent = '⏩ Completar recorrido');
}

async function abrir(trk, soloDatos = false) {
  // estado actual sin escribir nada: se usa el rastreo para leer el envío desde PostgreSQL
  const r = await fetch(`/api/rastreo/${trk}`).then((x) => x.json());
  const pg = r.resultados.postgresql;
  const estado = pg.ok && pg.datos.envio ? pg.datos.envio.estado_actual : '¿?';
  const sincronizacion = {};
  Object.keys(MOTORES).forEach((m) => {
    const x = r.resultados[m];
    const hay = x.ok && x.datos && (x.datos.envio || x.datos.linea_csv);
    sincronizacion[m] = { ok: !!hay, ms: x.ms, detalle: hay ? 'registro encontrado' : (x.error || 'no encontrado') };
  });
  const datosCurso = { tracking: trk, estado, sincronizacion, paso: 'Estado actual consultado en las cinco bases' };
  if (!soloDatos) { pintarCurso(datosCurso); rastrear(trk); $('#tracking').value = trk; }
  return datosCurso;
}

$('#form-envio').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  const datos = Object.fromEntries(new FormData(f));
  datos.fragil = f.fragil.checked;
  $('#btn-registrar').disabled = true;
  $('#msg-envio').className = 'msg';
  $('#msg-envio').textContent = 'Registrando en PostgreSQL y replicando…';
  const r = await fetch('/api/envios', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(datos) })
    .then((x) => x.json()).catch((er) => ({ ok: false, error: er.message }));
  $('#btn-registrar').disabled = false;
  if (!r.ok) { $('#msg-envio').className = 'msg err'; $('#msg-envio').textContent = r.error; return; }
  $('#msg-envio').textContent = `✔ ${r.tracking} creado y replicado en las 5 bases`;
  automatico = false;
  pintarCurso(r);
  refrescarTodo(r.tracking);
});
$('#recientes').addEventListener('click', (e) => { const li = e.target.closest('li[data-trk]'); if (li) { automatico = false; abrir(li.dataset.trk); } });

