// Sitio web de envíos: navegación por secciones, seguimiento con mapa, cotizador, cuenta del cliente,
// agencias y panel de operaciones. Usa las utilidades de app.js ($, esc, fmt, MOTORES, ...).
const NOMBRE_EVENTO = {
  ADMISION: 'Recibido en agencia', SALIDA_HUB: 'Salió hacia el siguiente punto', LLEGADA_HUB: 'Llegó a',
  CLASIFICACION: 'Clasificado en', EN_REPARTO: 'Salió a reparto', INTENTO_FALLIDO: 'Intento de entrega fallido',
  ENTREGA: 'Entregado', DEVOLUCION: 'Devuelto al remitente',
};
const NOMBRE_ESTADO = {
  REGISTRADO: 'Registrado', ADMITIDO: 'Admitido', EN_TRANSITO: 'En tránsito', EN_HUB: 'En centro de distribución',
  EN_REPARTO: 'En reparto', INTENTO_FALLIDO: 'Intento fallido', ENTREGADO: 'Entregado', DEVUELTO: 'Devuelto',
};
const SLA_TXT = {
  ENTREGADO_A_TIEMPO: ['Entregado a tiempo', 'ok'], ENTREGADO_CON_RETRASO: ['Entregado con retraso', 'warn'],
  EN_PLAZO: ['Dentro del plazo', 'ok'], EN_RIESGO: ['En riesgo de retraso', 'warn'], VENCIDO: ['Plazo vencido', 'bad'],
  DEVUELTO: ['Devuelto', 'bad'],
};
const ICONO = { EXPRESS_AEREO: '✈️', SOBRE_AEREO: '✉️', ESTANDAR_TERRESTRE: '🚚', ECONOMICO_TERRESTRE: '📦' };
const soles = (v) => 'S/ ' + Number(v).toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fecha = (v) => (v ? new Date(String(v).replace(' ', 'T').replace(/-05(:00)?$/, '-05:00'))
  .toLocaleString('es-PE', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—');
const json = (url, op) => fetch(url, op).then((r) => r.json()).catch((e) => ({ ok: false, error: e.message }));
let CATALOGO = null;
const cargados = {};

// ---------------------------------------------------------------- navegación
function ir() {
  const [, vista = 'inicio', arg] = location.hash.split('/');
  const v = document.getElementById('v-' + vista) ? vista : 'inicio';
  document.querySelectorAll('.vista').forEach((s) => { s.hidden = s.id !== 'v-' + v; });
  document.querySelectorAll('#menu a').forEach((a) => a.classList.toggle('activo', a.dataset.v === v));
  $('#menu').classList.remove('abierto');
  window.scrollTo({ top: 0 });
  const primera = !cargados[v];
  cargados[v] = true;
  if (v === 'inicio' && primera) iniciarInicio();
  if (v === 'rastrear') { if (arg) { $('#trk-rastrear').value = arg; mostrarSeguimiento(arg); } }
  if (v === 'enviar' && primera) { cargarCatalogos().then(precioVivo); cargarRecientes(); }
  if (v === 'enviar' && arg) abrir(arg);
  if (v === 'cotizar' && primera) iniciarCotizador();
  if (v === 'cuenta' && primera) iniciarCuenta();
  if (v === 'cuenta' && arg) { $('#doc-cuenta').value = arg; verCuenta(); }
  if (v === 'agencias') iniciarAgencias(primera);
  if (v === 'operaciones' && primera) iniciarOperaciones();
  if (v === 'bases' && primera) { cargarTodo(); rastrear($('#tracking').value); }
}
window.addEventListener('hashchange', ir);
$('#menu-btn').addEventListener('click', () => $('#menu').classList.toggle('abierto'));
document.querySelectorAll('form[data-rastreo]').forEach((f) => f.addEventListener('submit', (e) => {
  e.preventDefault();
  const v = $('input', f).value.trim().toUpperCase();
  if (v) location.hash = '#/rastrear/' + v;
}));

async function catalogo() {
  if (!CATALOGO) CATALOGO = await json('/api/catalogos');
  return CATALOGO;
}
const opcionesAgencias = (ags) => ags.map((a) => `<option value="${a.id}">${esc(a.ciudad)} – ${esc(a.nombre)}</option>`).join('');

// ---------------------------------------------------------------- inicio
async function iniciarInicio() {
  const [op, cat] = await Promise.all([json('/api/operaciones'), catalogo()]);
  if (op.total) {
    $('#cifras').innerHTML = [
      [fmt(op.total), 'envíos gestionados'], [op.ciudades, 'ciudades'], [op.agencias, 'agencias'],
      [op.cumplimiento + ' %', 'entregas a tiempo'],
    ].map(([n, t]) => `<div><b>${n}</b><span>${t}</span></div>`).join('');
  }
  $('#servicios-inicio').innerHTML = cat.servicios.map((s) => `
    <article class="servicio"><div class="ico">${ICONO[s.codigo] || '📦'}</div><h3>${esc(s.nombre)}</h3>
      <p>${s.modalidad === 'AEREO' ? 'Vía aérea' : 'Vía terrestre'} · entrega en ${s.sla_horas} h</p>
      <a href="#/cotizar" class="enlace">Cotizar →</a></article>`).join('');
}

// ---------------------------------------------------------------- seguimiento con mapa
let mapaRuta = null;
async function mostrarSeguimiento(trk) {
  const caja = $('#seguimiento');
  caja.innerHTML = '<div class="panel nota">Buscando el envío…</div>';
  const r = await json('/api/seguimiento/' + encodeURIComponent(trk));
  if (!r.ok) { caja.innerHTML = `<div class="panel"><p class="err">${esc(r.error)}</p></div>`; return; }
  const e = r.envio;
  const [slaTxt, slaCls] = SLA_TXT[e.sla] || [e.sla, ''];
  const pasos = r.pasos.map((p, i) => `<div class="${i < r.progreso ? 'hecho' : ''} ${i === r.progreso ? 'actual' : ''}">${NOMBRE_ESTADO[p]}</div>`).join('');
  const ubic = r.ubicacion_actual;
  const eventos = [...r.eventos].reverse().map((ev, i) => `
    <li class="${i === 0 ? 'ultimo' : ''}"><time>${fecha(ev.fecha_hora)}</time>
      <b>${NOMBRE_EVENTO[ev.evento] || ev.evento}${['LLEGADA_HUB', 'CLASIFICACION'].includes(ev.evento) ? ' ' + esc(ev.nombre_hub) : ''}</b>
      <span>${esc(ev.ciudad || '')} · ${esc(ev.hub)}${ev.observacion ? ' · ' + esc(ev.observacion) : ''}</span></li>`).join('');
  const fuentes = Object.entries(r.fuentes).map(([k, v]) => `<span class="fuente f-${v.toLowerCase()}">${v}: ${k}</span>`).join('');
  caja.innerHTML = `
    <div class="panel seg-cab">
      <div><small>Envío</small><div class="trk-grande">${e.tracking}</div>
        <div class="chips"><span class="chip ${e.estado}">${NOMBRE_ESTADO[e.estado] || e.estado}</span>
          <span class="sla ${slaCls}">${slaTxt}</span></div></div>
      <div class="seg-ruta"><div><small>Origen</small><b>${esc(r.origen?.ciudad)}</b><span>${esc(r.origen?.nombre)}</span></div>
        <div class="flecha">${e.modalidad === 'AEREO' ? '✈️' : '🚚'}</div>
        <div><small>Destino</small><b>${esc(r.destino?.ciudad)}</b><span>${esc(r.destino?.nombre)}</span></div></div>
      <div class="seg-fechas"><div><small>Registrado</small><b>${fecha(e.registro)}</b></div>
        <div><small>${e.entrega ? 'Entregado' : 'Entrega comprometida'}</small><b>${fecha(e.entrega || e.compromiso)}</b></div></div>
      <div class="pasos ancho">${pasos}</div>
    </div>
    <div class="seg-cuerpo">
      <div class="panel"><h3 class="h3p">📍 ${e.estado === 'ENTREGADO' ? 'Entregado en' : 'Ubicación actual'}: ${esc(ubic?.nombre_hub || '—')} (${esc(ubic?.ciudad || '')})</h3>
        <div id="mapa-ruta" class="mapa"></div>
        ${r.en_linea ? `<p class="nota">Estado en línea (Cassandra): ${esc(r.en_linea.ultimo_evento)} en ${esc(r.en_linea.ultimo_hub)} · ${fecha(r.en_linea.fecha)}</p>` : ''}</div>
      <div class="panel"><h3 class="h3p">Historial del envío</h3><ol class="historial">${eventos}</ol></div>
    </div>
    <div class="dos-col">
      <div class="panel"><h3 class="h3p">Detalle</h3><dl class="detalle">
        <dt>Servicio</dt><dd>${esc(e.servicio)}</dd><dt>Remitente</dt><dd>${esc(e.remitente)}</dd>
        <dt>Destinatario</dt><dd>${esc(e.destinatario)}</dd><dt>Dirección</dt><dd>${esc(e.direccion)}</dd>
        <dt>Peso</dt><dd>${e.peso} kg · ${r.paquetes.length} bulto(s)</dd>
        <dt>Contenido</dt><dd>${r.paquetes.map((p) => esc(p.descripcion) + (p.fragil ? ' (frágil)' : '')).join(', ')}</dd>
        ${r.comprobante ? `<dt>Comprobante</dt><dd>${r.comprobante.tipo} ${r.comprobante.serie}-${r.comprobante.numero} · ${soles(r.comprobante.total)} · ${esc(r.comprobante.metodo_pago)}</dd>` : ''}
      </dl></div>
      <div class="panel"><h3 class="h3p">Entrega</h3>${r.prueba_entrega ? `<dl class="detalle">
        <dt>Recibió</dt><dd>${esc(r.prueba_entrega.receptor?.nombre)}</dd>
        <dt>Fecha</dt><dd>${fecha(r.prueba_entrega.fecha_hora)}</dd>
        <dt>Firma digital</dt><dd>${r.prueba_entrega.firma_digital ? 'Sí' : 'No'}</dd>
        <dt>GPS</dt><dd>${r.prueba_entrega.ubicacion.coordinates.slice().reverse().join(', ')}</dd></dl>`
        : `<p class="nota">${r.intentos.length ? r.intentos.length + ' intento(s) de entrega registrados.' : 'Aún no se ha entregado.'}</p>`}
        <h3 class="h3p">Origen de cada dato</h3><div class="fuentes">${fuentes}</div></div>
    </div>`;
  dibujarRuta(r);
}

function dibujarRuta(r) {
  if (!window.L) { $('#mapa-ruta').innerHTML = '<p class="nota">El mapa necesita conexión a internet.</p>'; return; }
  if (mapaRuta) mapaRuta.remove();
  mapaRuta = L.map('mapa-ruta', { scrollWheelZoom: false });
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '© OpenStreetMap', maxZoom: 18 }).addTo(mapaRuta);
  const puntos = [];
  r.eventos.forEach((ev) => {
    if (ev.lat == null) return;
    const ultimoPunto = puntos[puntos.length - 1];
    if (!ultimoPunto || ultimoPunto[0] !== ev.lat || ultimoPunto[1] !== ev.lon) puntos.push([ev.lat, ev.lon]);
  });
  const destino = r.destino ? [r.destino.lat, r.destino.lon] : null;
  if (destino && r.envio.estado !== 'ENTREGADO') {
    L.polyline([puntos[puntos.length - 1], destino], { color: '#8c9bb5', dashArray: '6 6', weight: 3 }).addTo(mapaRuta);
    L.circleMarker(destino, { radius: 7, color: '#1f8a4c', fillOpacity: 0.9 }).addTo(mapaRuta).bindTooltip('Destino: ' + r.destino.nombre);
  }
  L.polyline(puntos, { color: '#0b5cad', weight: 4 }).addTo(mapaRuta);
  puntos.forEach((p, i) => L.circleMarker(p, { radius: 5, color: '#0b5cad', fillOpacity: 1 }).addTo(mapaRuta));
  const u = r.ubicacion_actual;
  if (u) L.marker([u.lat, u.lon]).addTo(mapaRuta).bindPopup(`<b>${esc(u.nombre_hub)}</b><br>${esc(u.ciudad)}`).openPopup();
  const limites = L.latLngBounds([...puntos, ...(destino ? [destino] : [])]);
  mapaRuta.fitBounds(limites.pad(0.3), { maxZoom: 12 });
}

// ---------------------------------------------------------------- enviar: precio en vivo
async function precioVivo() {
  const f = $('#form-envio');
  if (!f.origen.value || !f.destino.value) return;
  if (f.origen.value === f.destino.value) { $('#precio-vivo').innerHTML = '<span class="err">Elige agencias distintas.</span>'; return; }
  const r = await json(`/api/cotizar?origen=${f.origen.value}&destino=${f.destino.value}&peso=${f.peso.value || 1}`);
  if (!r.ok) { $('#precio-vivo').innerHTML = `<span class="err">${esc(r.error)}</span>`; return; }
  const s = r.servicios.find((x) => String(x.id) === f.servicio.value);
  $('#precio-vivo').innerHTML = s.disponible
    ? `Precio: <b>${soles(s.precio)}</b> · entrega estimada <b>${fecha(s.entrega_estimada)}</b> <small>(fn_calcular_tarifa)</small>`
    : `<span class="err">${esc(s.nombre)} no disponible: ${esc(s.motivo)}</span>`;
}
['origen', 'destino', 'servicio', 'peso'].forEach((n) => $('#form-envio').elements[n].addEventListener('change', precioVivo));

// ---------------------------------------------------------------- cotizador
async function iniciarCotizador() {
  const cat = await catalogo();
  const f = $('#form-cotizar');
  f.origen.innerHTML = f.destino.innerHTML = opcionesAgencias(cat.agencias);
  f.origen.value = (cat.agencias.find((a) => a.codigo === 'AG-LIM-MIR') || cat.agencias[0]).id;
  f.destino.value = (cat.agencias.find((a) => a.codigo === 'AG-AQP-01') || cat.agencias[1]).id;
  f.addEventListener('submit', (e) => { e.preventDefault(); cotizarAhora(); });
  cotizarAhora();
}
async function cotizarAhora() {
  const f = $('#form-cotizar');
  const r = await json(`/api/cotizar?origen=${f.origen.value}&destino=${f.destino.value}&peso=${f.peso.value}`);
  if (!r.ok) { $('#cotizacion').innerHTML = `<p class="err">${esc(r.error)}</p>`; return; }
  const disp = r.servicios.filter((s) => s.disponible);
  const barato = Math.min(...disp.map((s) => s.precio));
  const rapido = Math.min(...disp.map((s) => s.sla_horas));
  $('#cotizacion').innerHTML = `<p class="nota">${esc(r.origen.ciudad)} → ${esc(r.destino.ciudad)} · ${r.peso} kg</p>
    <div class="cotiz">${r.servicios.map((s) => `
      <article class="opcion ${s.disponible ? '' : 'no'}">
        <div class="ico">${ICONO[s.codigo] || '📦'}</div><h3>${esc(s.nombre)}</h3>
        ${s.disponible ? `<div class="precio">${soles(s.precio)}</div>
          <p>Entrega en ${s.sla_horas} h<br>Llega: <b>${fecha(s.entrega_estimada)}</b></p>
          <div class="chips">${s.precio === barato ? '<span class="sla ok">Más económico</span>' : ''}
            ${s.sla_horas === rapido ? '<span class="sla">Más rápido</span>' : ''}</div>
          <a class="boton-link" href="#/enviar" data-elegir="${s.id}">Enviar con este servicio</a>`
          : `<p class="err">${esc(s.motivo)}</p>`}
      </article>`).join('')}</div>`;
  document.querySelectorAll('[data-elegir]').forEach((a) => a.addEventListener('click', async () => {
    await cargarCatalogos();
    const fe = $('#form-envio');
    fe.servicio.value = a.dataset.elegir; fe.origen.value = f.origen.value; fe.destino.value = f.destino.value;
    fe.peso.value = f.peso.value; cargados.enviar = true; cargarRecientes(); precioVivo();
  }));
}

// ---------------------------------------------------------------- mi cuenta
async function iniciarCuenta() {
  const ej = await json('/api/cuenta-ejemplos');
  if (Array.isArray(ej)) {
    $('#ejemplos-cuenta').innerHTML = 'Prueba con: ' + ej.map((c) => `<a class="trk" data-doc="${c.documento}">${c.documento}</a> (${esc(c.nombre)})`).join(' · ');
    document.querySelectorAll('[data-doc]').forEach((a) => a.addEventListener('click', () => { $('#doc-cuenta').value = a.dataset.doc; verCuenta(); }));
  }
  $('#form-cuenta').addEventListener('submit', (e) => { e.preventDefault(); verCuenta(); });
}
async function verCuenta() {
  const doc = $('#doc-cuenta').value.trim();
  $('#cuenta').innerHTML = '<div class="panel nota">Consultando…</div>';
  const r = await json('/api/cuenta/' + encodeURIComponent(doc));
  if (!r.ok) { $('#cuenta').innerHTML = `<div class="panel"><p class="err">${esc(r.error)}</p></div>`; return; }
  const c = r.cliente;
  const resumen = Object.entries(r.resumen).map(([k, n]) => `<div><b>${n}</b><span>${NOMBRE_ESTADO[k] || k}</span></div>`).join('');
  $('#cuenta').innerHTML = `
    <div class="panel perfil"><div class="avatar">${esc(c.nombre[0])}</div>
      <div><h2>${esc(c.nombre)}</h2><p>${c.tipo === 'EMPRESA' ? 'Empresa' : 'Persona'} · ${esc(c.documento.tipo)} ${esc(c.documento.numero)}
        ${c.contacto?.email ? ' · ' + esc(c.contacto.email) : ''}${c.contacto?.ciudad ? ' · ' + esc(c.contacto.ciudad) : ''}</p></div>
      <div class="mini-kpis"><div><b>${r.envios.length}</b><span>envíos</span></div><div><b>${soles(r.gasto_total)}</b><span>facturado</span></div>${resumen}</div></div>
    <div class="panel"><h3 class="h3p">Historial de envíos <small>(Cassandra · envios_por_cliente, del más reciente al más antiguo)</small></h3>
      <div class="tabla-scroll"><table><thead><tr><th>Tracking</th><th>Fecha</th><th>Origen</th><th>Destino</th><th>Servicio</th><th>Estado</th><th>Monto</th></tr></thead>
      <tbody>${r.envios.map((e) => `<tr><td><a class="trk-seg" href="#/rastrear/${e.nro_tracking}">${e.nro_tracking}</a></td>
        <td>${fecha(e.fecha_registro)}</td><td>${esc(e.origen)}</td><td>${esc(e.destino)}</td><td>${esc(e.servicio)}</td>
        <td><span class="chip ${e.estado}">${NOMBRE_ESTADO[e.estado] || e.estado}</span></td><td class="num">${soles(e.monto_total)}</td></tr>`).join('')}</tbody></table></div></div>`;
}

// ---------------------------------------------------------------- agencias
let mapaAg = null;
let capaAg = null;
async function iniciarAgencias(primera) {
  if (primera) {
    const cat = await catalogo();
    const ciudades = [...new Map(cat.agencias.map((a) => [a.ciudad, a])).keys()];
    $('#ciudad-ref').innerHTML = ciudades.map((c) => `<option>${esc(c)}</option>`).join('');
    $('#btn-cercana').addEventListener('click', async () => {
      const todas = await json('/api/agencias');
      const ref = todas.find((a) => a.ciudad === $('#ciudad-ref').value);
      if (ref) cargarAgencias(ref.lat, ref.lon);
    });
    $('#btn-ubicacion').addEventListener('click', () => navigator.geolocation
      ? navigator.geolocation.getCurrentPosition((p) => cargarAgencias(p.coords.latitude, p.coords.longitude),
        () => alert('No se pudo obtener tu ubicación; elige una ciudad.'))
      : alert('Tu navegador no permite obtener la ubicación.'));
    await cargarAgencias();
  } else if (mapaAg) setTimeout(() => mapaAg.invalidateSize(), 50);
}
async function cargarAgencias(lat, lon) {
  const ags = await json('/api/agencias' + (lat != null ? `?lat=${lat}&lon=${lon}` : ''));
  $('#lista-agencias').innerHTML = ags.map((a, i) => `<li data-i="${i}">
    <b>${esc(a.nombre)}</b><span class="tipo ${a.tipo}">${a.tipo.replace('_', ' ')}</span>
    <small>${esc(a.direccion || '')} · ${esc(a.ciudad)}${a.distancia_km != null ? ` · <b>${a.distancia_km < 1 ? 'a menos de 1 km' : a.distancia_km + ' km'}</b>` : ''}</small></li>`).join('');
  if (!window.L) return;
  if (!mapaAg) {
    mapaAg = L.map('mapa-agencias');
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '© OpenStreetMap', maxZoom: 18 }).addTo(mapaAg);
  }
  if (capaAg) capaAg.remove();
  capaAg = L.layerGroup().addTo(mapaAg);
  const marcas = ags.map((a) => L.circleMarker([a.lat, a.lon], {
    radius: a.tipo === 'AGENCIA' ? 6 : 9, color: a.tipo === 'HUB_CENTRAL' ? '#c0392b' : a.tipo === 'HUB_REGIONAL' ? '#d9a400' : '#0b5cad',
    fillOpacity: 0.85 }).addTo(capaAg).bindPopup(`<b>${esc(a.nombre)}</b><br>${esc(a.ciudad)}<br>${esc(a.direccion || '')}`));
  document.querySelectorAll('#lista-agencias li').forEach((li) => li.addEventListener('click', () => {
    const a = ags[li.dataset.i]; mapaAg.setView([a.lat, a.lon], 13); marcas[li.dataset.i].openPopup();
  }));
  if (lat != null) { mapaAg.setView([ags[0].lat, ags[0].lon], 12); marcas[0].openPopup(); }
  else mapaAg.fitBounds(L.latLngBounds(ags.map((a) => [a.lat, a.lon])).pad(0.1));
}

// ---------------------------------------------------------------- operaciones
function barras(items, etiqueta, valor, texto, color) {
  const max = Math.max(...items.map(valor));
  return `<div class="hbarras">${items.map((x) => `<div class="hb"><span>${esc(etiqueta(x))}</span>
    <div class="hb-pista"><div style="width:${(100 * valor(x)) / max}%;background:${color || 'var(--acento)'}"></div></div>
    <b>${texto(x)}</b></div>`).join('')}</div>`;
}
async function iniciarOperaciones() {
  const [op, kpi, cat] = await Promise.all([json('/api/operaciones'), json('/api/hadoop/kpi'), catalogo()]);
  $('#kpis').innerHTML = [
    ['Envíos totales', fmt(op.total), 'PostgreSQL'], ['En curso', fmt(op.en_curso), 'sin entregar ni devolver'],
    ['Entregados a tiempo', op.cumplimiento + ' %', `de ${fmt(op.entregados)} entregados`],
    ['Ingresos', soles(op.ingresos), 'facturación total'],
  ].map(([t, v, s]) => `<div class="kpi-card"><span>${t}</span><b>${v}</b><small>${s}</small></div>`).join('');
  $('#g-estados').innerHTML = barras(op.por_estado, (x) => NOMBRE_ESTADO[x.estado] || x.estado, (x) => x.n, (x) => fmt(x.n));
  $('#g-sla').innerHTML = barras(op.sla_hadoop, (x) => x.servicio.replace('_', ' '), (x) => x.cumplimiento,
    (x) => x.cumplimiento + ' %', 'var(--ok)') + '<p class="nota">Calculado con MapReduce sobre el conjunto masivo (HDFS /olva/resultados).</p>';
  $('#g-destinos').innerHTML = barras(op.destinos, (x) => x.ciudad, (x) => x.n, (x) => fmt(x.n), 'var(--cassandra)');
  if (kpi.ok) {
    const max = Math.max(...kpi.filas.map((f) => +f.estancias));
    $('#g-hc').innerHTML = `<div class="barras">${kpi.filas.map((f) => `<div class="barra ${+f.estancias === max ? 'pico' : ''}"
      style="height:${Math.max(1, (100 * f.estancias) / max)}%" data-tip="${f.valor}:00 · ${(+f.estancias).toLocaleString('es-PE')} · ${f.permanencia_promedio_h} h"></div>`).join('')}</div>
      <div class="ejes">${kpi.filas.map((f) => `<span>${f.valor}</span>`).join('')}</div>
      <p class="nota">El pico de las 20:00 concentra el 35,8 % de las llegadas con 14,6 h de permanencia promedio.</p>`;
  }
  const f = $('#form-hub');
  const hubs = await json('/api/agencias');
  f.hub.innerHTML = hubs.filter((h) => h.tipo !== 'AGENCIA').concat(hubs.filter((h) => h.tipo === 'AGENCIA'))
    .map((h) => `<option value="${h.codigo}">${h.codigo} · ${esc(h.nombre)}</option>`).join('');
  f.hub.value = 'HC-LIM';
  f.addEventListener('submit', (e) => { e.preventDefault(); verActividad(); });
  verActividad();
}
async function verActividad() {
  const f = $('#form-hub');
  const r = await json(`/api/hub/${f.hub.value}/actividad?dia=${f.dia.value}`);
  if (!r.ok) { $('#actividad').innerHTML = `<p class="err">${esc(r.error)}</p>`; return; }
  if (!r.por_hora.length) { $('#actividad').innerHTML = '<p class="nota">Sin escaneos ese día en este hub.</p>'; return; }
  const max = Math.max(...r.por_hora.map((h) => h.escaneos));
  const porHora = Object.fromEntries(r.por_hora.map((h) => [h.hora, h]));
  $('#actividad').innerHTML = `<div class="barras">${[...Array(24).keys()].map((h) => {
    const x = porHora[h] || { escaneos: 0, llegadas: 0, salidas: 0 };
    return `<div class="barra" style="height:${Math.max(1, (100 * x.escaneos) / max)}%;background:var(--cassandra)"
      data-tip="${h}:00 · ${x.escaneos} escaneos · ${x.llegadas} llegadas · ${x.salidas} salidas"></div>`; }).join('')}</div>
    <div class="ejes">${[...Array(24).keys()].map((h) => `<span>${h}</span>`).join('')}</div>
    <h3 class="h3p">Últimos escaneos del día</h3>
    <div class="tabla-scroll"><table><thead><tr><th>Hora</th><th>Evento</th><th>Tracking</th><th>Servicio</th></tr></thead>
    <tbody>${r.ultimos_eventos.map((e) => `<tr><td>${esc(String(e.fecha_hora).slice(11, 16))}</td><td>${esc(e.tipo_evento)}</td>
      <td><a class="trk-seg" href="#/rastrear/${e.nro_tracking}">${e.nro_tracking}</a></td><td>${esc(e.servicio)}</td></tr>`).join('')}</tbody></table></div>`;
}

ir();
