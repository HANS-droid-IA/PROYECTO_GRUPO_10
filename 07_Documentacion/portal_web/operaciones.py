"""
Operaciones dinámicas del portal: registrar un envío y avanzar su recorrido.

Flujo (igual que en la arquitectura del proyecto):
  1) La operación se escribe en PostgreSQL, la fuente de verdad, usando sus procedimientos almacenados
     (sp_registrar_envio, sp_registrar_escaneo, sp_registrar_intento_entrega) y sus triggers.
  2) replicar() lee el estado completo del envío en PostgreSQL y lo propaga a Oracle, MongoDB,
     Cassandra y HDFS. Cada destino informa si quedó sincronizado y cuánto tardó.
"""
import datetime
import heapq
import json
import random
import time

import conexiones as cx

UTC = datetime.timezone.utc


# ------------------------------------------------------------------ catálogos para el formulario
def catalogos():
    with cx._pg() as c, c.cursor() as cur:
        cur.execute('''SELECT id_cliente, nombre_razon_social, tipo_cliente FROM maestro.cliente
                        ORDER BY nombre_razon_social LIMIT 300''')
        clientes = [{'id': r[0], 'nombre': r[1], 'tipo': r[2]} for r in cur.fetchall()]
        cur.execute('SELECT id_servicio, codigo, nombre, modalidad, sla_horas FROM maestro.tipo_servicio ORDER BY 1')
        servicios = [dict(zip(['id', 'codigo', 'nombre', 'modalidad', 'sla_horas'], r)) for r in cur.fetchall()]
        cur.execute('''SELECT h.id_hub, h.codigo, h.nombre, c.nombre, c.acceso_terrestre
                         FROM maestro.hub h JOIN maestro.ciudad c USING (id_ciudad)
                        WHERE h.tipo = 'AGENCIA' AND h.activo ORDER BY c.nombre, h.nombre''')
        agencias = [dict(zip(['id', 'codigo', 'nombre', 'ciudad', 'terrestre'], r)) for r in cur.fetchall()]
    return {'clientes': clientes, 'servicios': servicios, 'agencias': agencias}


def _empleado(cur, hub, cargos):
    cur.execute('''SELECT id_empleado FROM maestro.empleado WHERE id_hub = %s AND activo
                   ORDER BY array_position(%s::text[], cargo::text) NULLS LAST, id_empleado LIMIT 1''', (hub, cargos))
    r = cur.fetchone()
    return r[0] if r else None


# ------------------------------------------------------------------ 1) registrar envío en PostgreSQL
def registrar_envio(d):
    paquetes = [{'peso': float(d['peso']), 'largo': float(d.get('largo') or 30), 'ancho': float(d.get('ancho') or 20),
                 'alto': float(d.get('alto') or 15), 'descripcion': d.get('descripcion') or 'Paquete',
                 'fragil': bool(d.get('fragil'))}]
    with cx._pg() as c, c.cursor() as cur:
        emp = _empleado(cur, int(d['origen']), ['ATENCION', 'SUPERVISOR'])
        cur.execute('CALL operacion.sp_registrar_envio(%s, %s, %s, %s, %s, %s::smallint, %s, %s, %s::jsonb, %s, %s, NULL)',
                    (int(d['cliente']), d['dest_nombre'], d.get('dest_documento') or None,
                     d.get('dest_telefono') or None, d['direccion'], int(d['servicio']), int(d['origen']),
                     int(d['destino']), json.dumps(paquetes), d.get('metodo_pago') or 'EFECTIVO', emp))
        tracking = cur.fetchone()[0]
    return tracking


# ------------------------------------------------------------------ 2) avanzar el recorrido en PostgreSQL
def _ruta(cur, desde, hasta, modalidad):
    """Camino más corto por la red de rutas (Dijkstra): horas de viaje + 8 h de espera por transbordo."""
    cur.execute('SELECT id_ruta, id_hub_origen, id_hub_destino, modalidad, tiempo_estimado_horas FROM maestro.ruta '
                'WHERE activa')
    grafo = {}
    for rid, o, dd, mod, h in cur.fetchall():
        if modalidad == 'TERRESTRE' and mod == 'AEREO':
            continue
        grafo.setdefault(o, []).append((dd, rid, float(h) + 8))
    cola, visto = [(0, desde, [])], set()
    while cola:
        costo, nodo, camino = heapq.heappop(cola)
        if nodo == hasta:
            return camino
        if nodo in visto:
            continue
        visto.add(nodo)
        for sig, rid, w in grafo.get(nodo, []):
            if sig not in visto:
                heapq.heappush(cola, (costo + w, sig, camino + [(rid, nodo, sig)]))
    raise ValueError('No hay ruta disponible entre la agencia de origen y la de destino')


def _crear_despacho(cur, id_ruta, origen, destino):
    cur.execute('SELECT modalidad FROM maestro.ruta WHERE id_ruta = %s', (id_ruta,))
    modalidad = cur.fetchone()[0]
    vehiculo = vuelo = None
    if modalidad == 'AEREO':
        vuelo = random.choice(['LA', 'H2', 'JA']) + str(random.randint(1000, 2999))
    else:
        cur.execute('''SELECT id_vehiculo FROM maestro.vehiculo WHERE activo AND id_hub_base IN (%s, %s)
                       ORDER BY id_vehiculo LIMIT 1''', (origen, destino))
        vehiculo = cur.fetchone()[0]
    codigo = f'WEB{datetime.datetime.now():%y%m%d%H%M%S}{random.randint(10, 99)}'
    cur.execute('''INSERT INTO operacion.despacho (codigo_manifiesto, id_ruta, id_vehiculo, nro_vuelo,
                   fecha_salida_prog, fecha_salida_real, estado)
                   VALUES (%s, %s, %s, %s, clock_timestamp(), clock_timestamp(), 'EN_RUTA') RETURNING id_despacho''',
                (codigo, id_ruta, vehiculo, vuelo))
    return cur.fetchone()[0]


def avanzar(tracking):
    """Registra el siguiente escaneo lógico del envío y devuelve una descripción del paso."""
    with cx._pg() as c, c.cursor() as cur:
        cur.execute('''SELECT e.id_envio, e.estado_actual, e.id_hub_destino, s.modalidad, d.nombre, d.nro_documento
                         FROM operacion.envio e JOIN maestro.tipo_servicio s USING (id_servicio)
                         JOIN operacion.destinatario d USING (id_destinatario) WHERE e.nro_tracking = %s''', (tracking,))
        fila = cur.fetchone()
        if not fila:
            raise ValueError(f'El envío {tracking} no existe')
        id_envio, estado, destino, modalidad, receptor, doc = fila
        if estado in ('ENTREGADO', 'DEVUELTO'):
            raise ValueError(f'El envío ya terminó su recorrido ({estado})')
        cur.execute('''SELECT t.tipo_evento, t.id_hub, t.id_despacho, h.tipo FROM operacion.evento_tracking t
                         JOIN maestro.hub h USING (id_hub) WHERE t.id_envio = %s
                        ORDER BY t.fecha_hora DESC, t.id_evento DESC LIMIT 1''', (id_envio,))
        ultimo, hub, despacho, tipo_hub = cur.fetchone()

        def escaneo(evento, en_hub, desp=None, obs=None):
            emp = _empleado(cur, en_hub, ['OPERARIO_HUB', 'ATENCION', 'CONDUCTOR', 'SUPERVISOR'])
            cur.execute('CALL operacion.sp_registrar_escaneo(%s, %s, %s, %s, %s, %s)',
                        (tracking, evento, en_hub, emp, desp, obs))

        def codigo(h):
            cur.execute('SELECT codigo FROM maestro.hub WHERE id_hub = %s', (h,))
            return cur.fetchone()[0]

        if ultimo in ('ADMISION', 'CLASIFICACION') or (ultimo == 'LLEGADA_HUB' and tipo_hub == 'AGENCIA'
                                                       and hub != destino):
            rid, o, dd = _ruta(cur, hub, destino, modalidad)[0]
            desp = _crear_despacho(cur, rid, o, dd)
            cur.execute('INSERT INTO operacion.despacho_envio VALUES (%s, %s, clock_timestamp())', (desp, id_envio))
            escaneo('SALIDA_HUB', o, desp, 'Salida registrada desde el portal web')
            paso = f'SALIDA_HUB de {codigo(o)} hacia {codigo(dd)} (manifiesto {desp})'
        elif ultimo == 'SALIDA_HUB':
            cur.execute('SELECT r.id_hub_destino FROM operacion.despacho d JOIN maestro.ruta r USING (id_ruta) '
                        'WHERE d.id_despacho = %s', (despacho,))
            llegada = cur.fetchone()[0]
            cur.execute('''UPDATE operacion.despacho SET estado = 'ARRIBADO', fecha_llegada_real = clock_timestamp()
                           WHERE id_despacho = %s''', (despacho,))
            escaneo('LLEGADA_HUB', llegada, despacho)
            paso = f'LLEGADA_HUB a {codigo(llegada)}'
        elif ultimo == 'LLEGADA_HUB' and hub == destino:
            escaneo('EN_REPARTO', destino, obs='Salida a reparto')
            paso = f'EN_REPARTO desde {codigo(destino)}'
        elif ultimo == 'LLEGADA_HUB':
            escaneo('CLASIFICACION', hub, obs='Clasificación en hub')
            paso = f'CLASIFICACION en {codigo(hub)}'
        elif ultimo == 'EN_REPARTO':
            courier = _empleado(cur, destino, ['COURIER'])
            cur.execute('CALL operacion.sp_registrar_intento_entrega(%s, %s, %s, %s, %s)',
                        (tracking, courier, 'ENTREGADO', receptor, doc or '00000000'))
            paso = f'ENTREGA al destinatario {receptor}'
        else:
            raise ValueError(f'No hay un paso automático después de {ultimo}')
    return paso


# ------------------------------------------------------------------ lectura completa desde PostgreSQL
def _estado_pg(tracking):
    with cx._pg() as c, c.cursor() as cur:
        cur.execute('''SELECT e.id_envio, e.nro_tracking, e.id_cliente, cl.tipo_cliente, cl.nro_documento,
                              cl.nombre_razon_social, cl.tipo_documento, cl.email, cl.telefono, cl.id_ciudad,
                              cl.fecha_registro, d.nombre, d.nro_documento, d.telefono, e.direccion_entrega,
                              e.id_servicio, s.codigo, s.nombre, s.modalidad, s.sla_horas,
                              e.id_hub_origen, e.id_hub_destino, e.fecha_registro, e.fecha_compromiso,
                              e.estado_actual, e.peso_total_kg, e.valor_declarado, e.monto_total, e.fecha_entrega
                         FROM operacion.envio e JOIN maestro.cliente cl USING (id_cliente)
                         JOIN operacion.destinatario d USING (id_destinatario)
                         JOIN maestro.tipo_servicio s USING (id_servicio) WHERE e.nro_tracking = %s''', (tracking,))
        r = cur.fetchone()
        if not r:
            raise ValueError(f'El envío {tracking} no existe')
        k = ['id_envio', 'tracking', 'id_cliente', 'cli_tipo', 'cli_doc', 'cli_nombre', 'cli_tipo_doc', 'cli_email',
             'cli_tel', 'cli_ciudad', 'cli_fecha', 'dest_nombre', 'dest_doc', 'dest_tel', 'direccion', 'id_servicio',
             'serv_codigo', 'serv_nombre', 'modalidad', 'sla', 'hub_o', 'hub_d', 'f_registro', 'f_compromiso',
             'estado', 'peso', 'valor', 'monto', 'f_entrega']
        e = dict(zip(k, r))

        def lugar(h):
            cur.execute('''SELECT h.codigo, h.nombre, c.nombre, rg.nombre, rg.nodo, c.latitud, c.longitud
                             FROM maestro.hub h JOIN maestro.ciudad c USING (id_ciudad)
                             JOIN maestro.region rg USING (id_region) WHERE h.id_hub = %s''', (h,))
            x = cur.fetchone()
            return {'hub': x[0], 'nombre': x[1], 'ciudad': x[2], 'region': x[3], 'nodo': x[4],
                    'lat': float(x[5]), 'lon': float(x[6])}
        e['origen'], e['destino'] = lugar(e['hub_o']), lugar(e['hub_d'])
        cur.execute('''SELECT nro_bulto, peso_kg, largo_cm, ancho_cm, alto_cm, descripcion, fragil
                         FROM operacion.paquete WHERE id_envio = %s ORDER BY nro_bulto''', (e['id_envio'],))
        e['paquetes'] = cur.fetchall()
        cur.execute('''SELECT tipo, serie, numero, fecha_emision, subtotal, igv, total, metodo_pago
                         FROM operacion.comprobante WHERE id_envio = %s''', (e['id_envio'],))
        e['comprobante'] = cur.fetchone()
        cur.execute('''SELECT t.id_evento, t.tipo_evento, t.id_hub, h.codigo, c.nombre, t.id_despacho, t.fecha_hora,
                              t.observacion
                         FROM operacion.evento_tracking t JOIN maestro.hub h USING (id_hub)
                         JOIN maestro.ciudad c USING (id_ciudad) WHERE t.id_envio = %s
                        ORDER BY t.fecha_hora, t.id_evento''', (e['id_envio'],))
        e['eventos'] = [dict(zip(['id', 'tipo', 'id_hub', 'hub', 'ciudad', 'despacho', 'fecha', 'obs'], x))
                        for x in cur.fetchall()]
        cur.execute('''SELECT i.nro_intento, i.fecha_hora, i.resultado, em.nombres || ' ' || em.apellidos,
                              i.receptor_nombre, i.receptor_documento
                         FROM operacion.intento_entrega i JOIN maestro.empleado em ON em.id_empleado = i.id_courier
                        WHERE i.id_envio = %s ORDER BY i.nro_intento''', (e['id_envio'],))
        e['intentos'] = cur.fetchall()
    return e


# ------------------------------------------------------------------ 3) réplica a los demás motores
def _tz(v):
    """Fecha con zona -> texto para TO_TIMESTAMP_TZ de Oracle."""
    return v.strftime('%Y-%m-%d %H:%M:%S %z')[:-2] + ':' + v.strftime('%z')[-2:] if v else None


F_TZ = "TO_TIMESTAMP_TZ(:{}, 'YYYY-MM-DD HH24:MI:SS TZH:TZM')"


def _a_oracle(e):
    with cx._ora() as c, c.cursor() as cur:
        cur.execute('SELECT COUNT(*) FROM cliente WHERE id_cliente = :1', [e['id_cliente']])
        if cur.fetchone()[0] == 0:                    # Oracle guarda solo una parte de los clientes
            cur.execute('''INSERT INTO cliente (id_cliente, tipo_cliente, tipo_documento, nro_documento,
                           nombre_razon_social, email, telefono, id_ciudad, fecha_registro)
                           VALUES (:1, :2, :3, :4, :5, :6, :7, :8, :9)''',
                        [e['id_cliente'], e['cli_tipo'], e['cli_tipo_doc'], e['cli_doc'], e['cli_nombre'],
                         e['cli_email'], e['cli_tel'], e['cli_ciudad'], e['cli_fecha']])
        cur.execute('SELECT COUNT(*) FROM envio WHERE id_envio = :1', [e['id_envio']])
        if cur.fetchone()[0] == 0:
            cur.execute(f'''INSERT INTO envio (id_envio, nro_tracking, id_cliente, id_servicio, id_hub_origen,
                           id_hub_destino, fecha_registro, fecha_compromiso, estado_actual, peso_total_kg, monto_total)
                           VALUES (:1, :2, :3, :4, :5, :6, {F_TZ.format(7)}, {F_TZ.format(8)}, 'REGISTRADO', :9, :10)''',
                        [e['id_envio'], e['tracking'], e['id_cliente'], e['id_servicio'], e['hub_o'], e['hub_d'],
                         _tz(e['f_registro']), _tz(e['f_compromiso']), e['peso'], e['monto']])
        cur.execute('SELECT id_evento FROM evento_tracking WHERE id_envio = :1', [e['id_envio']])
        existentes = {r[0] for r in cur.fetchall()}
        nuevos = 0
        for ev in e['eventos']:                       # el trigger de Oracle actualiza el estado del envío
            if ev['id'] not in existentes:
                cur.execute(f'''INSERT INTO evento_tracking (id_evento, id_envio, tipo_evento, id_hub, fecha_hora,
                               observacion) VALUES (:1, :2, :3, :4, {F_TZ.format(5)}, :6)''',
                            [ev['id'], e['id_envio'], ev['tipo'], ev['id_hub'], _tz(ev['fecha']), ev['obs']])
                nuevos += 1
        c.commit()
        cur.execute('SELECT estado_actual FROM envio WHERE id_envio = :1', [e['id_envio']])
        return f'estado {cur.fetchone()[0]} · {nuevos} evento(s) nuevo(s)'


def _a_mongo(e):
    def lugar(x):
        return {k: x[k] for k in ('hub', 'nombre', 'ciudad', 'region', 'nodo')}
    doc = {
        '_id': e['tracking'], 'id_envio': e['id_envio'],
        'servicio': {'codigo': e['serv_codigo'], 'nombre': e['serv_nombre'], 'modalidad': e['modalidad'],
                     'sla_horas': int(e['sla'])},
        'cliente': {'id': e['id_cliente'], 'tipo': e['cli_tipo'], 'documento': e['cli_doc'], 'nombre': e['cli_nombre']},
        'destinatario': {k: v for k, v in {'nombre': e['dest_nombre'], 'documento': e['dest_doc'],
                                            'telefono': e['dest_tel'], 'direccion': e['direccion']}.items() if v},
        'origen': lugar(e['origen']), 'destino': lugar(e['destino']),
        'fechas': {k: v for k, v in {'registro': e['f_registro'], 'compromiso': e['f_compromiso'],
                                      'entrega': e['f_entrega']}.items() if v},
        'estado_actual': e['estado'], 'peso_total_kg': float(e['peso']), 'valor_declarado': float(e['valor']),
        'monto_total': float(e['monto']),
        'paquetes': [{'bulto': p[0], 'peso_kg': float(p[1]),
                      'dimensiones_cm': {'largo': float(p[2]), 'ancho': float(p[3]), 'alto': float(p[4])},
                      'descripcion': p[5], **({'fragil': True} if p[6] else {})} for p in e['paquetes']],
        'tracking': [{k: v for k, v in {'fecha_hora': ev['fecha'], 'evento': ev['tipo'], 'hub': ev['hub'],
                                         'ciudad': ev['ciudad'], 'despacho': ev['despacho'],
                                         'observacion': ev['obs']}.items() if v is not None} for ev in e['eventos']],
        'intentos_entrega': [{'nro': i[0], 'fecha_hora': i[1], 'resultado': i[2], 'courier': i[3],
                              'receptor': {'nombre': i[4], 'documento': i[5]}} for i in e['intentos']],
        'origen_registro': 'portal_web',
    }
    if e['comprobante']:
        cp = e['comprobante']
        doc['comprobante'] = {'tipo': cp[0], 'serie': cp[1], 'numero': cp[2], 'fecha_emision': cp[3],
                              'subtotal': float(cp[4]), 'igv': float(cp[5]), 'total': float(cp[6]),
                              'metodo_pago': cp[7]}
    ok = [i for i in e['intentos'] if i[2] == 'ENTREGADO']
    if ok:
        doc['prueba_entrega'] = {'receptor': {'nombre': ok[-1][4], 'documento': ok[-1][5]}, 'fecha_hora': ok[-1][1],
                                 'ubicacion': {'type': 'Point',
                                               'coordinates': [e['destino']['lon'], e['destino']['lat']]},
                                 'firma_digital': True, 'foto': f"pod/{e['tracking']}.jpg"}
    cx._mongo().envios.replace_one({'_id': e['tracking']}, doc, upsert=True)
    return f'documento con {len(doc["tracking"])} evento(s) embebido(s)'


def _a_cassandra(e):
    s = cx._cass()
    ult = e['eventos'][-1]
    s.execute('''INSERT INTO estado_envio (nro_tracking, destino, estado, fecha_compromiso, fecha_ultimo_evento,
                 servicio, ultimo_evento, ultimo_hub) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)''',
              (e['tracking'], e['destino']['ciudad'], e['estado'], e['f_compromiso'], ult['fecha'], e['serv_codigo'],
               ult['tipo'], ult['hub']))
    s.execute('''INSERT INTO envios_por_cliente (id_cliente, fecha_registro, nro_tracking, destino, estado,
                 monto_total, origen, servicio) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)''',
              (e['id_cliente'], e['f_registro'], e['tracking'], e['destino']['hub'], e['estado'], e['monto'],
               e['origen']['hub'], e['serv_codigo']))
    for ev in e['eventos']:                            # INSERT en Cassandra es upsert: se puede repetir
        s.execute('''INSERT INTO eventos_por_envio (nro_tracking, fecha_hora, id_evento, ciudad, hub, id_despacho,
                     observacion, tipo_evento) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)''',
                  (e['tracking'], ev['fecha'], ev['id'], ev['ciudad'], ev['hub'], ev['despacho'], ev['obs'], ev['tipo']))
        s.execute('''INSERT INTO eventos_por_hub_dia (hub, dia, fecha_hora, id_evento, nro_tracking, servicio,
                     tipo_evento) VALUES (%s, %s, %s, %s, %s, %s, %s)''',
                  (ev['hub'], ev['fecha'].astimezone(datetime.timezone(datetime.timedelta(hours=-5))).date(),
                   ev['fecha'], ev['id'], e['tracking'], e['serv_codigo'], ev['tipo']))
    return f'estado {e["estado"]} · {len(e["eventos"])} evento(s) en 3 tablas'


def _a_hdfs(e):
    import requests

    def ts(v):
        return v.astimezone(datetime.timezone(datetime.timedelta(hours=-5))).strftime('%Y-%m-%d %H:%M:%S-05') if v else ''
    lineas = ['tipo,id,nro_tracking,detalle,hub,fecha_hora',
              f"ENVIO,{e['id_envio']},{e['tracking']},{e['serv_codigo']}|{e['estado']}|{e['monto']},"
              f"{e['origen']['hub']}>{e['destino']['hub']},{ts(e['f_registro'])}"]
    lineas += [f"EVENTO,{ev['id']},{e['tracking']},{ev['tipo']},{ev['hub']},{ts(ev['fecha'])}" for ev in e['eventos']]
    ruta = f'/olva/operacional/web/{e["tracking"]}.csv'
    r = requests.put(cx.WEBHDFS + ruta, params={'op': 'CREATE', 'overwrite': 'true', 'user.name': 'hadoop',
                                                'noredirect': 'true'}, timeout=5)
    r.raise_for_status()
    url = 'http://127.0.0.1:' + r.json()['Location'].split('://', 1)[1].split(':', 1)[1]
    requests.put(url, data='\n'.join(lineas).encode('utf-8') + b'\n', timeout=10).raise_for_status()
    return f'{ruta} ({len(lineas) - 1} líneas, replicación 2)'


DESTINOS = {'oracle': _a_oracle, 'mongodb': _a_mongo, 'cassandra': _a_cassandra, 'hadoop': _a_hdfs}


def replicar(tracking):
    t0 = time.perf_counter()
    e = _estado_pg(tracking)
    res = {'postgresql': {'ok': True, 'detalle': f'estado {e["estado"]} · {len(e["eventos"])} evento(s)',
                          'ms': round((time.perf_counter() - t0) * 1000)}}
    for nombre, fn in DESTINOS.items():
        t1 = time.perf_counter()
        try:
            res[nombre] = {'ok': True, 'detalle': fn(e)}
        except Exception as ex:                       # un destino caído no impide sincronizar los demás
            res[nombre] = {'ok': False, 'detalle': f'{type(ex).__name__}: {ex}'[:250]}
        res[nombre]['ms'] = round((time.perf_counter() - t1) * 1000)
    return {'tracking': tracking, 'estado': e['estado'], 'sincronizacion': res,
            'eventos': [{'tipo': ev['tipo'], 'hub': ev['hub'], 'fecha_hora': cx._json(ev['fecha'])} for ev in e['eventos']]}


def recientes(n=8):
    with cx._pg() as c, c.cursor() as cur:
        cur.execute('''SELECT e.nro_tracking, e.estado_actual, ho.codigo, hd.codigo, e.fecha_registro
                         FROM operacion.envio e JOIN maestro.hub ho ON ho.id_hub = e.id_hub_origen
                         JOIN maestro.hub hd ON hd.id_hub = e.id_hub_destino
                        WHERE e.fecha_registro > '2026-10-08' ORDER BY e.id_envio DESC LIMIT %s''', (n,))
        return [dict(zip(['nro_tracking', 'estado', 'origen', 'destino', 'fecha_registro'], map(cx._json, r)))
                for r in cur.fetchall()]
