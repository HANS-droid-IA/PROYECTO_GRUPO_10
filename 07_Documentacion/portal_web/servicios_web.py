"""
Servicios del sitio web de envíos. Cada función usa la base de datos que mejor responde a esa pregunta:
  - cotizar        -> PostgreSQL  (función maestro.fn_calcular_tarifa y reglas de plazo)
  - seguimiento    -> PostgreSQL  (envío, eventos, fn_estado_sla) + MongoDB (hubs con GeoJSON, prueba de
                      entrega) + Cassandra (estado en línea)
  - agencias       -> MongoDB     (colección hubs, índice 2dsphere: agencias más cercanas)
  - mi_cuenta      -> MongoDB     (cliente por documento, índice único) + Cassandra (envios_por_cliente)
  - operaciones    -> PostgreSQL  (resumen operativo) + Hadoop/HDFS (indicadores MapReduce)
  - actividad_hub  -> Cassandra   (escaneos_hub_hora y eventos_por_hub_dia)
"""
import datetime

import conexiones as cx

LIMA = datetime.timezone(datetime.timedelta(hours=-5))
ESTADOS_ORDEN = ['REGISTRADO', 'ADMITIDO', 'EN_TRANSITO', 'EN_HUB', 'EN_REPARTO', 'ENTREGADO']


def _hubs_geo():
    """código de hub -> datos y coordenadas (MongoDB, colección hubs)."""
    return {h['_id']: {'codigo': h['_id'], 'nombre': h['nombre'], 'tipo': h['tipo'], 'ciudad': h.get('ciudad'),
                       'region': h.get('region'), 'direccion': h.get('direccion'),
                       'capacidad_hora': h.get('capacidad_hora'),
                       'lon': h['ubicacion']['coordinates'][0], 'lat': h['ubicacion']['coordinates'][1]}
            for h in cx._mongo().hubs.find({})}


def _compromiso(desde, sla_h):
    """Misma regla que sp_registrar_envio: vence a las 20:00 del día alcanzado; domingo pasa a lunes."""
    t = desde + datetime.timedelta(hours=sla_h)
    c = t.replace(hour=20, minute=0, second=0, microsecond=0)
    if t > c:
        c += datetime.timedelta(days=1)
    if c.isoweekday() == 7:
        c += datetime.timedelta(days=1)
    return c


# ------------------------------------------------------------------ cotizador (PostgreSQL)
def cotizar(origen, destino, peso):
    peso = float(peso)
    ahora = datetime.datetime.now(LIMA)
    with cx._pg() as c, c.cursor() as cur:
        cur.execute('''SELECT h.id_hub, h.codigo, h.nombre, c.nombre, c.id_region, c.acceso_terrestre, c.tiene_aeropuerto
                         FROM maestro.hub h JOIN maestro.ciudad c USING (id_ciudad) WHERE h.id_hub IN (%s, %s)''',
                    (origen, destino))
        ag = {r[0]: dict(zip(['id', 'codigo', 'nombre', 'ciudad', 'region', 'terrestre', 'aeropuerto'], r))
              for r in cur.fetchall()}
        o, d = ag[int(origen)], ag[int(destino)]
        cur.execute('SELECT id_servicio, codigo, nombre, modalidad, sla_horas, peso_max_kg FROM maestro.tipo_servicio '
                    'ORDER BY sla_horas, id_servicio')
        res = []
        for sid, cod, nom, mod, sla, pmax in cur.fetchall():
            fila = {'id': sid, 'codigo': cod, 'nombre': nom, 'modalidad': mod, 'peso_max': float(pmax)}
            motivo = None
            if mod == 'TERRESTRE' and not (o['terrestre'] and d['terrestre']):
                motivo = 'Destino sin acceso terrestre'
            elif peso > float(pmax):
                motivo = f'Supera el peso máximo ({float(pmax):g} kg)'
            if motivo:
                fila.update(disponible=False, motivo=motivo)
            else:
                cur.execute('SELECT maestro.fn_calcular_tarifa(%s::smallint, %s::smallint, %s::smallint, %s::numeric)',
                            (sid, o['region'], d['region'], peso))
                sla_real = 48 if o['ciudad'] == d['ciudad'] else sla
                fila.update(disponible=True, precio=float(cur.fetchone()[0]), sla_horas=sla_real,
                            entrega_estimada=cx._json(_compromiso(ahora, sla_real)))
            res.append(fila)
    return {'origen': o, 'destino': d, 'peso': peso, 'servicios': res}


# ------------------------------------------------------------------ seguimiento (PG + MongoDB + Cassandra)
def seguimiento(tracking):
    tracking = tracking.strip().upper()
    fuentes = {}
    with cx._pg() as c, c.cursor() as cur:
        cur.execute('''SELECT e.id_envio, e.nro_tracking, e.estado_actual, operacion.fn_estado_sla(e.id_envio),
                              s.nombre, s.modalidad, ho.codigo, hd.codigo, e.fecha_registro, e.fecha_compromiso,
                              e.fecha_entrega, e.peso_total_kg, e.monto_total, cl.nombre_razon_social,
                              d.nombre, e.direccion_entrega
                         FROM operacion.envio e JOIN maestro.tipo_servicio s USING (id_servicio)
                         JOIN maestro.hub ho ON ho.id_hub = e.id_hub_origen
                         JOIN maestro.hub hd ON hd.id_hub = e.id_hub_destino
                         JOIN maestro.cliente cl USING (id_cliente)
                         JOIN operacion.destinatario d USING (id_destinatario)
                        WHERE e.nro_tracking = %s''', (tracking,))
        r = cur.fetchone()
        if not r:
            return None
        k = ['id_envio', 'tracking', 'estado', 'sla', 'servicio', 'modalidad', 'origen', 'destino', 'registro',
             'compromiso', 'entrega', 'peso', 'monto', 'remitente', 'destinatario', 'direccion']
        env = dict(zip(k, r))
        cur.execute('''SELECT t.fecha_hora, t.tipo_evento, h.codigo, t.observacion FROM operacion.evento_tracking t
                         JOIN maestro.hub h USING (id_hub) WHERE t.id_envio = %s ORDER BY t.fecha_hora, t.id_evento''',
                    (env['id_envio'],))
        eventos = [dict(zip(['fecha_hora', 'evento', 'hub', 'observacion'], x)) for x in cur.fetchall()]
        cur.execute('''SELECT nro_bulto, peso_kg, largo_cm, ancho_cm, alto_cm, descripcion, fragil
                         FROM operacion.paquete WHERE id_envio = %s ORDER BY nro_bulto''', (env['id_envio'],))
        paquetes = [dict(zip(['bulto', 'peso', 'largo', 'ancho', 'alto', 'descripcion', 'fragil'], x))
                    for x in cur.fetchall()]
        cur.execute('SELECT tipo, serie, numero, total, metodo_pago FROM operacion.comprobante WHERE id_envio = %s',
                    (env['id_envio'],))
        cp = cur.fetchone()
        cur.execute('''SELECT nro_intento, fecha_hora, resultado FROM operacion.intento_entrega
                        WHERE id_envio = %s ORDER BY nro_intento''', (env['id_envio'],))
        intentos = [dict(zip(['nro', 'fecha_hora', 'resultado'], x)) for x in cur.fetchall()]
    fuentes['envio, eventos, paquetes y comprobante'] = 'PostgreSQL'
    hubs = _hubs_geo()
    fuentes['ubicación de hubs (GeoJSON)'] = 'MongoDB'
    for ev in eventos:
        h = hubs.get(ev['hub'], {})
        ev.update(ciudad=h.get('ciudad'), nombre_hub=h.get('nombre'), lat=h.get('lat'), lon=h.get('lon'))
    doc = cx._mongo().envios.find_one({'_id': tracking}, {'prueba_entrega': 1})
    pod = (doc or {}).get('prueba_entrega')
    if pod:
        fuentes['prueba de entrega'] = 'MongoDB'
        if isinstance(pod.get('fecha_hora'), datetime.datetime) and pod['fecha_hora'].tzinfo is None:
            # pymongo devuelve las fechas en UTC sin zona: se pasan a hora de Lima
            pod['fecha_hora'] = pod['fecha_hora'].replace(tzinfo=datetime.timezone.utc).astimezone(LIMA)
    en_linea = None
    try:
        x = cx._cass().execute('SELECT estado, ultimo_evento, ultimo_hub, fecha_ultimo_evento FROM estado_envio '
                               'WHERE nro_tracking = %s', (tracking,)).one()
        if x:
            en_linea = {'estado': x.estado, 'ultimo_evento': x.ultimo_evento, 'ultimo_hub': x.ultimo_hub,
                        'fecha': cx._lima(x.fecha_ultimo_evento)}
            fuentes['estado en línea'] = 'Cassandra'
    except Exception:
        pass
    estado_base = 'EN_REPARTO' if env['estado'] == 'INTENTO_FALLIDO' else env['estado']
    progreso = ESTADOS_ORDEN.index(estado_base) if estado_base in ESTADOS_ORDEN else 5
    ultimo = eventos[-1] if eventos else None
    return cx._json({
        'envio': env, 'eventos': eventos, 'paquetes': paquetes, 'intentos': intentos,
        'comprobante': dict(zip(['tipo', 'serie', 'numero', 'total', 'metodo_pago'], cp)) if cp else None,
        'origen': hubs.get(env['origen']), 'destino': hubs.get(env['destino']),
        'ubicacion_actual': ultimo and {k: ultimo[k] for k in ('hub', 'nombre_hub', 'ciudad', 'lat', 'lon')},
        'progreso': progreso, 'pasos': ESTADOS_ORDEN, 'prueba_entrega': pod, 'en_linea': en_linea,
        'fuentes': fuentes})


# ------------------------------------------------------------------ agencias (MongoDB geoespacial)
def agencias(lat=None, lon=None):
    db = cx._mongo()
    if lat is not None and lon is not None:
        pipeline = [{'$geoNear': {'near': {'type': 'Point', 'coordinates': [float(lon), float(lat)]},
                                  'distanceField': 'distancia_m', 'spherical': True, 'key': 'ubicacion'}}]
        docs = list(db.hubs.aggregate(pipeline))
    else:
        docs = list(db.hubs.find({}).sort([('ciudad', 1), ('_id', 1)]))
    return [{'codigo': h['_id'], 'nombre': h['nombre'], 'tipo': h['tipo'], 'ciudad': h.get('ciudad'),
             'direccion': h.get('direccion'), 'region': h.get('region'), 'capacidad_hora': h.get('capacidad_hora'),
             'lon': h['ubicacion']['coordinates'][0], 'lat': h['ubicacion']['coordinates'][1],
             'distancia_km': round(h['distancia_m'] / 1000, 1) if 'distancia_m' in h else None} for h in docs]


# ------------------------------------------------------------------ mi cuenta (MongoDB + Cassandra)
def mi_cuenta(documento):
    cli = cx._mongo().clientes.find_one({'documento.numero': documento.strip()})
    if not cli:
        return None
    filas = cx._cass().execute('SELECT fecha_registro, nro_tracking, origen, destino, servicio, estado, monto_total '
                               'FROM envios_por_cliente WHERE id_cliente = %s LIMIT 50', (int(cli['_id']),))
    envios = [{k: cx._json(cx._lima(v)) for k, v in f._asdict().items()} for f in filas]
    resumen = {}
    for e in envios:
        resumen[e['estado']] = resumen.get(e['estado'], 0) + 1
    return {'cliente': cx._json({'id': cli['_id'], 'tipo': cli['tipo'], 'documento': cli['documento'],
                                 'nombre': cli['nombre'], 'contacto': cli.get('contacto', {})}),
            'envios': envios, 'resumen': resumen, 'gasto_total': round(sum(float(e['monto_total']) for e in envios), 2)}


def documentos_ejemplo():
    """Clientes con más envíos, para probar 'Mi cuenta' (MongoDB)."""
    top = cx._mongo().envios.aggregate([{'$group': {'_id': '$cliente.id', 'n': {'$sum': 1}}},
                                        {'$sort': {'n': -1}}, {'$limit': 3}])
    ids = [t['_id'] for t in top]
    return [{'documento': c['documento']['numero'], 'nombre': c['nombre']}
            for c in cx._mongo().clientes.find({'_id': {'$in': ids}})]


# ------------------------------------------------------------------ operaciones (PostgreSQL + Hadoop)
def operaciones():
    with cx._pg() as c, c.cursor() as cur:
        cur.execute('''SELECT count(*), count(*) FILTER (WHERE estado_actual = 'ENTREGADO'),
                              count(*) FILTER (WHERE estado_actual = 'ENTREGADO' AND fecha_entrega <= fecha_compromiso),
                              sum(monto_total), count(*) FILTER (WHERE estado_actual NOT IN ('ENTREGADO', 'DEVUELTO'))
                         FROM operacion.envio''')
        total, entregados, a_tiempo, ingresos, en_curso = cur.fetchone()
        cur.execute('SELECT estado_actual, count(*) FROM operacion.envio GROUP BY 1 ORDER BY 2 DESC')
        por_estado = cur.fetchall()
        cur.execute('''SELECT s.nombre, count(*), round(100.0 * count(*) FILTER (WHERE e.fecha_entrega <= e.fecha_compromiso)
                              / NULLIF(count(*) FILTER (WHERE e.estado_actual = 'ENTREGADO'), 0), 1)
                         FROM operacion.envio e JOIN maestro.tipo_servicio s USING (id_servicio) GROUP BY 1 ORDER BY 2 DESC''')
        por_servicio = cur.fetchall()
        cur.execute('''SELECT c.nombre, count(*) FROM operacion.envio e JOIN maestro.hub h ON h.id_hub = e.id_hub_destino
                         JOIN maestro.ciudad c USING (id_ciudad) GROUP BY 1 ORDER BY 2 DESC LIMIT 8''')
        destinos = cur.fetchall()
        cur.execute("SELECT count(*) FROM maestro.hub WHERE tipo = 'AGENCIA'")
        n_agencias = cur.fetchone()[0]
        cur.execute('SELECT count(DISTINCT id_ciudad) FROM maestro.hub')
        n_ciudades = cur.fetchone()[0]
    sla_masivo = []
    try:                                                          # indicadores calculados con MapReduce
        for l in cx._hdfs_leer('/olva/resultados/cumplimiento_sla/part-r-00000').splitlines():
            p = l.split(',')
            if p[0] == 'SERVICIO':
                sla_masivo.append({'servicio': p[1], 'envios': int(p[3]), 'cumplimiento': float(p[5]),
                                   'retraso_h': float(p[6])})
    except Exception:
        pass
    return cx._json({
        'total': total, 'entregados': entregados, 'en_curso': en_curso, 'ingresos': ingresos,
        'cumplimiento': round(100 * a_tiempo / entregados, 1) if entregados else None,
        'agencias': n_agencias, 'ciudades': n_ciudades,
        'por_estado': [{'estado': e, 'n': n} for e, n in por_estado],
        'por_servicio': [{'servicio': s, 'n': n, 'cumplimiento': p} for s, n, p in por_servicio],
        'destinos': [{'ciudad': c_, 'n': n} for c_, n in destinos],
        'sla_hadoop': sorted(sla_masivo, key=lambda x: x['cumplimiento'])})


# ------------------------------------------------------------------ actividad de un hub (Cassandra)
def actividad_hub(hub, dia):
    s = cx._cass()
    d = datetime.date.fromisoformat(dia)
    horas = s.execute('SELECT hora, escaneos, llegadas, salidas FROM escaneos_hub_hora WHERE hub = %s AND dia = %s',
                      (hub, d))
    eventos = s.execute('SELECT fecha_hora, tipo_evento, nro_tracking, servicio FROM eventos_por_hub_dia '
                        'WHERE hub = %s AND dia = %s LIMIT 15', (hub, d))
    return {'hub': hub, 'dia': dia,
            'por_hora': [dict(h._asdict()) for h in horas],
            'ultimos_eventos': [{k: cx._json(cx._lima(v)) for k, v in e._asdict().items()} for e in eventos]}
