# =====================================================================
# Genera los documentos JSON de MongoDB a partir de los CSV del modelo
# relacional (01_Relacional_PostgreSQL/datos). Mismo dataset que PostgreSQL.
#
#   datos/envios.json   -> 1 documento por envío ("expediente" del envío) con
#                          paquetes, tracking, intentos, incidencias, comprobante
#                          y prueba de entrega EMBEBIDOS
#   datos/hubs.json     -> red logística con ubicación GeoJSON
#   datos/clientes.json -> clientes con contacto como subdocumento
#
# Formato: Extended JSON (una línea por documento) para mongoimport.
# Uso: python generar_documentos.py
# =====================================================================
import csv, json, random, pathlib
from collections import defaultdict
from datetime import datetime, timezone

RAIZ = pathlib.Path(__file__).resolve().parent
SRC = RAIZ.parent / '01_Relacional_PostgreSQL' / 'datos'
OUT = RAIZ / 'datos'
OUT.mkdir(exist_ok=True)
random.seed(2026)


def leer(nombre):
    with open(SRC / f'{nombre}.csv', encoding='utf-8', newline='') as f:
        return list(csv.DictReader(f))


def fecha(v):
    """'2026-04-01 08:05:45-05' -> {"$date": "2026-04-01T13:05:45Z"} (UTC)."""
    if not v:
        return None
    d = datetime.fromisoformat(v).astimezone(timezone.utc)
    return {'$date': d.strftime('%Y-%m-%dT%H:%M:%SZ')}


def num(v):
    return float(v) if v not in ('', None) else None


def limpio(d):
    """Quita claves vacías: en un documento los atributos opcionales simplemente no existen."""
    return {k: v for k, v in d.items() if v not in (None, '', [], {})}


region = {r['id_region']: r for r in leer('region')}
ciudad = {r['id_ciudad']: r for r in leer('ciudad')}
hub = {r['id_hub']: r for r in leer('hub')}
servicio = {r['id_servicio']: r for r in leer('tipo_servicio')}
cliente = {r['id_cliente']: r for r in leer('cliente')}
destinatario = {r['id_destinatario']: r for r in leer('destinatario')}
empleado = {r['id_empleado']: r for r in leer('empleado')}


def lugar(id_hub):
    h = hub[id_hub]
    c = ciudad[h['id_ciudad']]
    return {'hub': h['codigo'], 'nombre': h['nombre'], 'ciudad': c['nombre'],
            'region': region[c['id_region']]['nombre'], 'nodo': region[c['id_region']]['nodo']}


# --- agrupar las tablas hijas por envío -------------------------------
paquetes, eventos, intentos, incidencias, comprobantes = (defaultdict(list) for _ in range(5))
for r in leer('paquete'):
    paquetes[r['id_envio']].append(limpio({
        'bulto': int(r['nro_bulto']), 'peso_kg': num(r['peso_kg']),
        'dimensiones_cm': {'largo': num(r['largo_cm']), 'ancho': num(r['ancho_cm']), 'alto': num(r['alto_cm'])},
        'descripcion': r['descripcion'], 'fragil': True if r['fragil'] == 't' else None}))
for r in leer('evento_tracking'):
    eventos[r['id_envio']].append((r['fecha_hora'], int(r['id_evento']), limpio({
        'fecha_hora': fecha(r['fecha_hora']), 'evento': r['tipo_evento'],
        'hub': hub[r['id_hub']]['codigo'], 'ciudad': ciudad[hub[r['id_hub']]['id_ciudad']]['nombre'],
        'despacho': int(r['id_despacho']) if r['id_despacho'] else None,
        'observacion': r['observacion']})))
for r in leer('intento_entrega'):
    intentos[r['id_envio']].append(limpio({
        'nro': int(r['nro_intento']), 'fecha_hora': fecha(r['fecha_hora']), 'resultado': r['resultado'],
        'courier': f"{empleado[r['id_courier']]['nombres']} {empleado[r['id_courier']]['apellidos']}",
        'receptor': limpio({'nombre': r['receptor_nombre'], 'documento': r['receptor_documento']})}))
for r in leer('incidencia'):
    incidencias[r['id_envio']].append(limpio({
        'tipo': r['tipo'], 'hub': hub[r['id_hub']]['codigo'] if r['id_hub'] else None, 'fecha_reporte': fecha(r['fecha_reporte']),
        'descripcion': r['descripcion'], 'estado': r['estado'], 'fecha_cierre': fecha(r['fecha_cierre'])}))
for r in leer('comprobante'):
    comprobantes[r['id_envio']] = limpio({
        'tipo': r['tipo'], 'serie': r['serie'], 'numero': int(r['numero']), 'fecha_emision': fecha(r['fecha_emision']),
        'subtotal': num(r['subtotal']), 'igv': num(r['igv']), 'total': num(r['total']), 'metodo_pago': r['metodo_pago']})

# --- colección envios ------------------------------------------------
n_env = n_evt = 0
with open(OUT / 'envios.json', 'w', encoding='utf-8') as f:
    for e in leer('envio'):
        s, cl, ds = servicio[e['id_servicio']], cliente[e['id_cliente']], destinatario[e['id_destinatario']]
        trk = [x[2] for x in sorted(eventos[e['id_envio']], key=lambda x: (x[0], x[1]))]
        doc = {
            '_id': e['nro_tracking'],
            'id_envio': int(e['id_envio']),
            'servicio': {'codigo': s['codigo'], 'nombre': s['nombre'], 'modalidad': s['modalidad'], 'sla_horas': int(s['sla_horas'])},
            'cliente': limpio({'id': int(cl['id_cliente']), 'tipo': cl['tipo_cliente'], 'documento': cl['nro_documento'],
                               'nombre': cl['nombre_razon_social']}),
            'destinatario': limpio({'nombre': ds['nombre'], 'documento': ds['nro_documento'], 'telefono': ds['telefono'],
                                    'direccion': e['direccion_entrega']}),
            'origen': lugar(e['id_hub_origen']),
            'destino': lugar(e['id_hub_destino']),
            'fechas': limpio({'registro': fecha(e['fecha_registro']), 'compromiso': fecha(e['fecha_compromiso']),
                              'entrega': fecha(e['fecha_entrega'])}),
            'estado_actual': e['estado_actual'],
            'peso_total_kg': num(e['peso_total_kg']),
            'valor_declarado': num(e['valor_declarado']),
            'monto_total': num(e['monto_total']),
            'comprobante': comprobantes.get(e['id_envio']),
            'paquetes': paquetes[e['id_envio']],
            'tracking': trk,
            'intentos_entrega': sorted(intentos[e['id_envio']], key=lambda i: i['nro']),
            'incidencias': incidencias[e['id_envio']],
        }
        # prueba de entrega (POD): solo existe si el envío fue entregado; incluye GPS del courier
        ok = [i for i in doc['intentos_entrega'] if i['resultado'] == 'ENTREGADO']
        if ok:
            c = ciudad[hub[e['id_hub_destino']]['id_ciudad']]
            lon = round(float(c['longitud']) + random.uniform(-0.03, 0.03), 6)
            lat = round(float(c['latitud']) + random.uniform(-0.03, 0.03), 6)
            doc['prueba_entrega'] = {'receptor': ok[-1].get('receptor'), 'fecha_hora': ok[-1]['fecha_hora'],
                                     'ubicacion': {'type': 'Point', 'coordinates': [lon, lat]},
                                     'firma_digital': True, 'foto': f"pod/{e['nro_tracking']}.jpg"}
        f.write(json.dumps(limpio(doc), ensure_ascii=False) + '\n')
        n_env += 1
        n_evt += len(trk)

# --- colección hubs --------------------------------------------------
with open(OUT / 'hubs.json', 'w', encoding='utf-8') as f:
    for h in hub.values():
        c = ciudad[h['id_ciudad']]
        f.write(json.dumps(limpio({
            '_id': h['codigo'], 'nombre': h['nombre'], 'tipo': h['tipo'],
            'hub_padre': hub[h['id_hub_padre']]['codigo'] if h['id_hub_padre'] else None,
            'capacidad_hora': int(h['capacidad_hora']), 'direccion': h['direccion'],
            'ciudad': c['nombre'], 'departamento': c['departamento'],
            'region': region[c['id_region']]['nombre'], 'nodo': region[c['id_region']]['nodo'],
            'ubicacion': {'type': 'Point', 'coordinates': [float(c['longitud']), float(c['latitud'])]},
            'activo': h['activo'] == 't'}), ensure_ascii=False) + '\n')

# --- colección clientes ----------------------------------------------
with open(OUT / 'clientes.json', 'w', encoding='utf-8') as f:
    for c in cliente.values():
        f.write(json.dumps(limpio({
            '_id': int(c['id_cliente']), 'tipo': c['tipo_cliente'],
            'documento': {'tipo': c['tipo_documento'], 'numero': c['nro_documento']},
            'nombre': c['nombre_razon_social'],
            'contacto': limpio({'email': c['email'], 'telefono': c['telefono'], 'direccion': c['direccion'],
                                'ciudad': ciudad[c['id_ciudad']]['nombre']}),
            'fecha_registro': fecha(c['fecha_registro'] + ' 00:00:00-05')}), ensure_ascii=False) + '\n')

print(f'envios.json: {n_env} documentos con {n_evt} eventos embebidos')
print(f'hubs.json: {len(hub)} documentos | clientes.json: {len(cliente)} documentos')
