# =====================================================================
# Genera los CSV de carga para Cassandra a partir de los CSV del modelo
# relacional (01_Relacional_PostgreSQL/datos). Mismo dataset que PostgreSQL.
#
# En Cassandra se DESNORMALIZA: el mismo escaneo se escribe en varias tablas,
# cada una diseñada para responder UNA consulta con una sola partición.
#   eventos_por_envio.csv    -> historial de un tracking
#   eventos_por_hub_dia.csv  -> qué pasó por un hub en un día (rango horario)
#   escaneos_hub_hora.csv    -> llegadas/salidas por hub, día y hora (saturación)
#   envios_por_cliente.csv   -> últimos envíos de un cliente (portal web)
#   estado_envio.csv         -> último estado de cada envío (consulta por clave)
#   hubs.csv                 -> capacidad de cada hub
# Las fechas se guardan en UTC; el día y la hora de partición son hora de Lima.
# Uso: python generar_csv_cassandra.py
# =====================================================================
import csv, pathlib
from collections import defaultdict, Counter
from datetime import datetime, timezone, timedelta

RAIZ = pathlib.Path(__file__).resolve().parent
SRC = RAIZ.parent / '01_Relacional_PostgreSQL' / 'datos'
OUT = RAIZ / 'datos'
OUT.mkdir(exist_ok=True)
LIMA = timezone(timedelta(hours=-5))


def leer(nombre):
    with open(SRC / f'{nombre}.csv', encoding='utf-8', newline='') as f:
        return list(csv.DictReader(f))


def escribir(nombre, cabecera, filas):
    with open(OUT / f'{nombre}.csv', 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(cabecera)
        w.writerows(filas)
    print(f'{nombre}.csv: {len(filas)} filas')


def ts(v):
    """Texto con zona -> datetime con zona (o None)."""
    return datetime.fromisoformat(v) if v else None


def utc(d):
    return d.astimezone(timezone.utc).strftime('%Y-%m-%d %H:%M:%S+0000') if d else ''


ciudad = {r['id_ciudad']: r['nombre'] for r in leer('ciudad')}
hubs = leer('hub')
hub = {r['id_hub']: r for r in hubs}
servicio = {r['id_servicio']: r['codigo'] for r in leer('tipo_servicio')}
envios = leer('envio')
env = {e['id_envio']: e for e in envios}

evp, evh, ultimo = [], [], {}
cont = Counter()
for r in leer('evento_tracking'):
    e, h = env[r['id_envio']], hub[r['id_hub']]
    f = ts(r['fecha_hora'])
    local = f.astimezone(LIMA)
    evp.append([e['nro_tracking'], utc(f), r['id_evento'], r['tipo_evento'], h['codigo'], ciudad[h['id_ciudad']],
                r['id_despacho'], r['observacion']])
    evh.append([h['codigo'], local.strftime('%Y-%m-%d'), utc(f), r['id_evento'], e['nro_tracking'], r['tipo_evento'],
                servicio[e['id_servicio']]])
    clave = (h['codigo'], local.strftime('%Y-%m-%d'), local.hour)
    cont[clave + ('LLEGADA',)] += r['tipo_evento'] in ('LLEGADA_HUB', 'ADMISION')
    cont[clave + ('SALIDA',)] += r['tipo_evento'] == 'SALIDA_HUB'
    cont[clave + ('TOTAL',)] += 1
    u = ultimo.get(r['id_envio'])
    if u is None or (f, int(r['id_evento'])) > (u[0], u[1]):
        ultimo[r['id_envio']] = (f, int(r['id_evento']), r['tipo_evento'], h['codigo'])

escribir('eventos_por_envio',
         ['nro_tracking', 'fecha_hora', 'id_evento', 'tipo_evento', 'hub', 'ciudad', 'id_despacho', 'observacion'], evp)
escribir('eventos_por_hub_dia',
         ['hub', 'dia', 'fecha_hora', 'id_evento', 'nro_tracking', 'tipo_evento', 'servicio'], evh)

claves = sorted({k[:3] for k in cont})
escribir('escaneos_hub_hora', ['hub', 'dia', 'hora', 'llegadas', 'salidas', 'escaneos'],
         [[h, d, hr, cont[(h, d, hr, 'LLEGADA')], cont[(h, d, hr, 'SALIDA')], cont[(h, d, hr, 'TOTAL')]] for h, d, hr in claves])

escribir('envios_por_cliente',
         ['id_cliente', 'fecha_registro', 'nro_tracking', 'servicio', 'origen', 'destino', 'estado', 'monto_total'],
         [[e['id_cliente'], utc(ts(e['fecha_registro'])), e['nro_tracking'], servicio[e['id_servicio']],
           hub[e['id_hub_origen']]['codigo'], hub[e['id_hub_destino']]['codigo'], e['estado_actual'], e['monto_total']]
          for e in envios])

escribir('estado_envio',
         ['nro_tracking', 'estado', 'ultimo_evento', 'ultimo_hub', 'fecha_ultimo_evento', 'fecha_compromiso', 'servicio', 'destino'],
         [[e['nro_tracking'], e['estado_actual'], ultimo[e['id_envio']][2], ultimo[e['id_envio']][3],
           utc(ultimo[e['id_envio']][0]), utc(ts(e['fecha_compromiso'])), servicio[e['id_servicio']],
           ciudad[hub[e['id_hub_destino']]['id_ciudad']]] for e in envios])

escribir('hubs', ['hub', 'nombre', 'tipo', 'ciudad', 'capacidad_hora'],
         [[h['codigo'], h['nombre'], h['tipo'], ciudad[h['id_ciudad']], h['capacidad_hora']] for h in hubs])
