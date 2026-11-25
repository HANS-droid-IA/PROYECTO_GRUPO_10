"""
Conexión a las cinco bases de datos del proyecto Olva Courier.
Las credenciales se leen del archivo .env de la raíz del proyecto (nunca se escriben en el código).
Cada función devuelve como máximo 20 registros, listos para convertir a JSON.
"""
import datetime
import decimal
import os
import pathlib
import time

RAIZ = pathlib.Path(__file__).resolve().parents[2]
LIMITE = 20


def _leer_env():
    env = {}
    for linea in (RAIZ / '.env').read_text(encoding='utf-8').splitlines():
        linea = linea.strip()
        if linea and not linea.startswith('#') and '=' in linea:
            k, v = linea.split('=', 1)
            env[k.strip()] = v.strip()
    return env


ENV = _leer_env()


def _json(v):
    """Convierte tipos de las bases (fechas, decimales, ObjectId...) a algo que JSON entiende."""
    if isinstance(v, (datetime.datetime, datetime.date)):
        return v.isoformat(sep=' ') if isinstance(v, datetime.datetime) else v.isoformat()
    if isinstance(v, decimal.Decimal):
        return float(v)
    if isinstance(v, (list, tuple)):
        return [_json(x) for x in v]
    if isinstance(v, dict):
        return {k: _json(x) for k, x in v.items()}
    if v is None or isinstance(v, (str, int, float, bool)):
        return v
    return str(v)


def _filas(columnas, filas):
    return [{c: _json(v) for c, v in zip(columnas, f)} for f in filas]


# ------------------------------------------------------------------ PostgreSQL
def _pg():
    import psycopg
    return psycopg.connect(host='127.0.0.1', port=5440, dbname='olva_courier', user=ENV['PG_USER'],
                           password=ENV['PG_PASSWORD'], connect_timeout=4)


SQL_PG = '''
SELECT e.nro_tracking, s.codigo AS servicio, ho.codigo AS hub_origen, hd.codigo AS hub_destino,
       e.estado_actual, e.fecha_registro, e.peso_total_kg, e.monto_total
  FROM operacion.envio e
  JOIN maestro.tipo_servicio s ON s.id_servicio = e.id_servicio
  JOIN maestro.hub ho ON ho.id_hub = e.id_hub_origen
  JOIN maestro.hub hd ON hd.id_hub = e.id_hub_destino
 {filtro}
 ORDER BY e.id_envio DESC
 LIMIT {limite}'''


def postgresql():
    with _pg() as c, c.cursor() as cur:
        cur.execute(SQL_PG.format(filtro='', limite=LIMITE))
        filas = _filas([d.name for d in cur.description], cur.fetchall())
        cur.execute('SELECT count(*) FROM operacion.envio')
        total = cur.fetchone()[0]
    return {'descripcion': 'Base transaccional · esquema operacion.envio (con JOIN a maestro.hub y maestro.tipo_servicio)',
            'total': total, 'filas': filas}


# ------------------------------------------------------------------ Oracle
def _ora():
    import oracledb
    return oracledb.connect(user='olva', password=ENV['ORACLE_APP_PASSWORD'], dsn='127.0.0.1:1521/FREEPDB1',
                            tcp_connect_timeout=4)


SQL_ORA = '''
SELECT e.nro_tracking, s.codigo AS servicio, ho.codigo AS hub_origen, hd.codigo AS hub_destino,
       e.estado_actual, e.fecha_registro, e.peso_total_kg, e.monto_total
  FROM envio e
  JOIN tipo_servicio s ON s.id_servicio = e.id_servicio
  JOIN hub ho ON ho.id_hub = e.id_hub_origen
  JOIN hub hd ON hd.id_hub = e.id_hub_destino
 {filtro}
 ORDER BY e.id_envio DESC
 FETCH FIRST {limite} ROWS ONLY'''


def oracle():
    with _ora() as c, c.cursor() as cur:
        cur.execute(SQL_ORA.format(filtro='', limite=LIMITE))
        filas = _filas([d[0].lower() for d in cur.description], cur.fetchall())
        cur.execute('SELECT COUNT(*) FROM envio')
        total = cur.fetchone()[0]
    return {'descripcion': 'Implementación parcial (esquema OLVA, PDB FREEPDB1) · tabla ENVIO', 'total': total,
            'filas': filas}


# ------------------------------------------------------------------ MongoDB
_mongo_cliente = None


def _mongo():
    global _mongo_cliente
    if _mongo_cliente is None:
        from pymongo import MongoClient
        _mongo_cliente = MongoClient('127.0.0.1', 27017, username=ENV['MONGO_USER'],
                                     password=ENV['MONGO_PASSWORD'], authSource='admin',
                                     serverSelectionTimeoutMS=4000)
    return _mongo_cliente['olva_tracking']


PROY_MONGO = {'_id': 1, 'servicio.codigo': 1, 'cliente.nombre': 1, 'origen.ciudad': 1, 'destino.ciudad': 1,
              'estado_actual': 1, 'monto_total': 1, 'tracking': 1}


def _doc_mongo(d):
    return {'nro_tracking': d['_id'], 'servicio': d.get('servicio', {}).get('codigo'),
            'cliente': d.get('cliente', {}).get('nombre'), 'origen': d.get('origen', {}).get('ciudad'),
            'destino': d.get('destino', {}).get('ciudad'), 'estado_actual': d.get('estado_actual'),
            'monto_total': d.get('monto_total'), 'eventos_embebidos': len(d.get('tracking', []))}


def mongodb():
    db = _mongo()
    docs = db.envios.find({}, PROY_MONGO).sort('_id', -1).limit(LIMITE)
    return {'descripcion': 'Base documental olva_tracking · colección envios (expediente con tracking embebido)',
            'total': db.envios.estimated_document_count(), 'filas': [_json(_doc_mongo(d)) for d in docs]}


# ------------------------------------------------------------------ Cassandra
_cass_sesion = None


def _cass():
    global _cass_sesion
    if _cass_sesion is None:
        from cassandra.auth import PlainTextAuthProvider
        from cassandra.cluster import Cluster, ExecutionProfile, EXEC_PROFILE_DEFAULT
        from cassandra.policies import DCAwareRoundRobinPolicy
        from cassandra import ConsistencyLevel
        from cassandra.io.asyncioreactor import AsyncioConnection   # reactor puro Python (sin extensiones C)
        perfil = ExecutionProfile(load_balancing_policy=DCAwareRoundRobinPolicy(local_dc='dc_lima'),
                                  consistency_level=ConsistencyLevel.LOCAL_ONE, request_timeout=8)
        cluster = Cluster(['127.0.0.1'], port=9042, protocol_version=5,
                          auth_provider=PlainTextAuthProvider('olva_admin', ENV['CASS_ADMIN_PASSWORD']),
                          execution_profiles={EXEC_PROFILE_DEFAULT: perfil}, connect_timeout=5,
                          connection_class=AsyncioConnection)
        _cass_sesion = cluster.connect('olva_tracking')
    return _cass_sesion


def _ultimos_trackings():
    """Los 20 envíos más recientes según PostgreSQL (la fuente de verdad)."""
    with _pg() as c, c.cursor() as cur:
        cur.execute('SELECT nro_tracking FROM operacion.envio ORDER BY id_envio DESC LIMIT %s', (LIMITE,))
        return [r[0] for r in cur.fetchall()]


def _lima(v):
    """Cassandra devuelve las fechas en UTC sin zona: se muestran en hora de Lima (UTC-5)."""
    if isinstance(v, datetime.datetime):
        return (v - datetime.timedelta(hours=5)).strftime('%Y-%m-%d %H:%M:%S') + '-05'
    return v


def cassandra():
    s = _cass()
    trackings = _ultimos_trackings()
    marcas = ', '.join(['%s'] * len(trackings))
    filas = s.execute('SELECT nro_tracking, servicio, destino, estado, ultimo_evento, ultimo_hub, '
                      f'fecha_ultimo_evento FROM estado_envio WHERE nro_tracking IN ({marcas})', trackings)
    filas = sorted(({k: _json(_lima(v)) for k, v in f._asdict().items()} for f in filas),
                   key=lambda f: f['nro_tracking'], reverse=True)
    return {'descripcion': 'Base columnar olva_tracking (datacenter dc_lima) · tabla estado_envio, '
                           'leída por clave de partición (nro_tracking)', 'total': None, 'filas': filas}


# ------------------------------------------------------------------ Hadoop (HDFS vía WebHDFS)
WEBHDFS = 'http://127.0.0.1:9870/webhdfs/v1'
COLS_ENVIO = ['id_envio', 'nro_tracking', 'id_cliente', 'id_destinatario', 'id_servicio', 'id_hub_origen',
              'id_hub_destino', 'direccion_entrega', 'fecha_registro', 'fecha_compromiso', 'estado_actual',
              'peso_total_kg', 'valor_declarado', 'monto_total', 'fecha_entrega']
MOSTRAR_HDFS = ['nro_tracking', 'id_servicio', 'id_hub_origen', 'id_hub_destino', 'estado_actual',
                'fecha_registro', 'peso_total_kg', 'monto_total']


def _hdfs_leer(ruta, longitud=None):
    import requests
    params = {'op': 'OPEN', 'user.name': 'hadoop', 'noredirect': 'true'}
    if longitud:
        params['length'] = longitud
    r = requests.get(WEBHDFS + ruta, params=params, timeout=5)
    r.raise_for_status()
    # el NameNode responde con la URL del DataNode; su nombre de host interno se cambia por 127.0.0.1
    url = r.json()['Location']
    url = 'http://127.0.0.1:' + url.split('://', 1)[1].split(':', 1)[1]
    return requests.get(url, timeout=10).content.decode('utf-8', 'replace')


def _hdfs_envio_operacional():
    import requests
    lst = requests.get(WEBHDFS + '/olva/operacional', params={'op': 'LISTSTATUS', 'user.name': 'hadoop'},
                       timeout=5).json()['FileStatuses']['FileStatus']
    fecha = sorted(x['pathSuffix'] for x in lst if x['pathSuffix'].isdigit())[-1]   # carpetas por fecha
    return f'/olva/operacional/{fecha}/envio/envio.csv'


def _hdfs_lista(ruta):
    import requests
    r = requests.get(WEBHDFS + ruta, params={'op': 'LISTSTATUS', 'user.name': 'hadoop'}, timeout=5)
    return r.json()['FileStatuses']['FileStatus'] if r.ok else []


def _hdfs_envios_web():
    """Envíos registrados desde el portal: un CSV por envío en /olva/operacional/web."""
    filas = []
    for f in _hdfs_lista('/olva/operacional/web'):
        lineas = _hdfs_leer('/olva/operacional/web/' + f['pathSuffix']).splitlines()
        env = next((l.split(',') for l in lineas if l.startswith('ENVIO,')), None)
        ev = [l.split(',') for l in lineas if l.startswith('EVENTO,')]
        if env:
            serv, estado, monto = env[3].split('|')
            o, d = env[4].split('>')
            filas.append({'nro_tracking': env[2], 'origen_registro': 'portal web', 'servicio': serv,
                          'hub_origen': o, 'hub_destino': d, 'estado_actual': estado,
                          'fecha_registro': env[5], 'monto_total': monto, 'eventos': len(ev)})
    return sorted(filas, key=lambda f: f['nro_tracking'], reverse=True)


def hadoop():
    import csv
    import io
    import requests
    filas = _hdfs_envios_web()[:LIMITE]
    ruta = _hdfs_envio_operacional()
    if len(filas) < LIMITE:                                    # se completa con la extracción desde PostgreSQL
        st = requests.get(WEBHDFS + ruta, params={'op': 'GETFILESTATUS', 'user.name': 'hadoop'}, timeout=5).json()
        largo = st['FileStatus']['length']
        import requests as rq
        r = rq.get(WEBHDFS + ruta, params={'op': 'OPEN', 'user.name': 'hadoop', 'noredirect': 'true',
                                           'offset': max(0, largo - 8192)}, timeout=5)
        url = 'http://127.0.0.1:' + r.json()['Location'].split('://', 1)[1].split(':', 1)[1]
        lineas = rq.get(url, timeout=10).content.decode('utf-8', 'replace').splitlines()[1:]
        for f in reversed(list(csv.reader(io.StringIO('\n'.join(lineas))))):
            if len(filas) >= LIMITE:
                break
            x = dict(zip(COLS_ENVIO, f))
            filas.append({'nro_tracking': x['nro_tracking'], 'origen_registro': 'extracción PostgreSQL',
                          'servicio': x['id_servicio'], 'hub_origen': x['id_hub_origen'],
                          'hub_destino': x['id_hub_destino'], 'estado_actual': x['estado_actual'],
                          'fecha_registro': x['fecha_registro'], 'monto_total': x['monto_total'], 'eventos': ''})
    return {'descripcion': f'HDFS /olva/operacional/web (envíos del portal) y {ruta} (extracción de PostgreSQL); '
                           'los ids de servicio y hub vienen tal como están en el CSV', 'total': None, 'filas': filas}


def hadoop_kpi():
    """Indicadores calculados por MapReduce: permanencia del Hub Central Lima por hora de llegada."""
    texto = _hdfs_leer('/olva/resultados/permanencia_hub/part-r-00000')
    cols = ['dimension', 'hub', 'valor', 'estancias', 'permanencia_promedio_h', 'pct_mayor_12h']
    filas = [dict(zip(cols, l.split(','))) for l in texto.splitlines() if l.startswith('HORA,HC-LIM,')]
    return filas


MOTORES = {'postgresql': postgresql, 'oracle': oracle, 'mongodb': mongodb, 'cassandra': cassandra, 'hadoop': hadoop}


def consultar(motor):
    t0 = time.perf_counter()
    try:
        r = MOTORES[motor]()
        r.update(ok=True, ms=round((time.perf_counter() - t0) * 1000))
    except Exception as e:                                             # el portal muestra el error de ese motor
        r = {'ok': False, 'error': f'{type(e).__name__}: {e}'[:300], 'filas': [],
             'ms': round((time.perf_counter() - t0) * 1000)}
    r['motor'] = motor
    return r


# ------------------------------------------------------------------ rastreo cruzado
def rastrear(tracking):
    """Busca el mismo número de tracking en todas las bases: demuestra que están conectadas por la misma clave."""
    tracking = tracking.strip().upper()
    res = {}

    def medir(nombre, fn):
        t0 = time.perf_counter()
        try:
            res[nombre] = {'ok': True, 'datos': _json(fn())}
        except Exception as e:
            res[nombre] = {'ok': False, 'error': f'{type(e).__name__}: {e}'[:300]}
        res[nombre]['ms'] = round((time.perf_counter() - t0) * 1000)

    def pg():
        with _pg() as c, c.cursor() as cur:
            cur.execute(SQL_PG.format(filtro='WHERE e.nro_tracking = %s', limite=1), (tracking,))
            r = _filas([d.name for d in cur.description], cur.fetchall())
            cur.execute('''SELECT t.fecha_hora, t.tipo_evento, h.codigo AS hub FROM operacion.evento_tracking t
                           JOIN operacion.envio e ON e.id_envio = t.id_envio JOIN maestro.hub h ON h.id_hub = t.id_hub
                           WHERE e.nro_tracking = %s ORDER BY t.fecha_hora''', (tracking,))
            ev = _filas([d.name for d in cur.description], cur.fetchall())
        return {'envio': r[0] if r else None, 'eventos': ev}

    def ora():
        with _ora() as c, c.cursor() as cur:
            cur.execute(SQL_ORA.format(filtro='WHERE e.nro_tracking = :t', limite=1), t=tracking)
            r = _filas([d[0].lower() for d in cur.description], cur.fetchall())
        return {'envio': r[0] if r else None,
                'nota': None if r else 'Oracle solo guarda los primeros 1 000 envíos (implementación parcial)'}

    def mg():
        d = _mongo().envios.find_one({'_id': tracking}, PROY_MONGO)
        return {'envio': _doc_mongo(d) if d else None,
                'eventos': [{'fecha_hora': e['fecha_hora'], 'tipo_evento': e['evento'], 'hub': e['hub']}
                            for e in (d or {}).get('tracking', [])]}

    def cq():
        s = _cass()
        est = s.execute('SELECT * FROM estado_envio WHERE nro_tracking = %s', (tracking,)).one()
        ev = s.execute('SELECT fecha_hora, tipo_evento, hub FROM eventos_por_envio WHERE nro_tracking = %s',
                       (tracking,))
        lima = lambda fila: {k: _lima(v) for k, v in fila._asdict().items()}
        return {'envio': lima(est) if est else None, 'eventos': [lima(e) for e in ev]}

    def hd():
        web = f'/olva/operacional/web/{tracking}.csv'
        if any(f['pathSuffix'] == f'{tracking}.csv' for f in _hdfs_lista('/olva/operacional/web')):
            lineas = _hdfs_leer(web).splitlines()
            return {'archivo_hdfs': web, 'linea_csv': next(l for l in lineas if l.startswith('ENVIO,')),
                    'eventos': len([l for l in lineas if l.startswith('EVENTO,')])}
        # si no, el envío extraído de PostgreSQL a HDFS por el flujo de integración (punto 14)
        ruta = _hdfs_envio_operacional()
        linea = next((l for l in _hdfs_leer(ruta).splitlines() if f',{tracking},' in l), None)
        return {'archivo_hdfs': ruta, 'linea_csv': linea}

    medir('postgresql', pg)
    medir('oracle', ora)
    medir('mongodb', mg)
    medir('cassandra', cq)
    medir('hadoop', hd)
    return {'tracking': tracking, 'resultados': res}
