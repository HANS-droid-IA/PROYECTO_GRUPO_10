"""
Portal web Olva Courier: muestra los 20 registros más recientes de cada base de datos del proyecto
(PostgreSQL, Oracle, MongoDB, Apache Cassandra y Hadoop/HDFS), rastrea un mismo envío en todas a la vez y
permite REGISTRAR envíos y AVANZAR su recorrido: cada operación se escribe en PostgreSQL y se replica
a las otras cuatro bases.
Uso:  python app.py   ->   http://localhost:5000
"""
import re
import threading

from flask import Flask, abort, jsonify, render_template, request

import conexiones
import operaciones
import servicios_web

app = Flask(__name__)
app.json.ensure_ascii = False
app.json.sort_keys = False
ESCRITURA = threading.Lock()          # una operación de escritura a la vez (evita escaneos cruzados)
PATRON = re.compile(r'(?i)OLV\d{10}')


def _error(e, codigo=400):
    msg = str(e).split('\n')[0]
    msg = re.sub(r'^(CONTEXT|ERROR):\s*', '', msg)
    return jsonify({'ok': False, 'error': msg[:300]}), codigo


@app.get('/')
def inicio():
    return render_template('index.html', motores=list(conexiones.MOTORES))


@app.get('/api/catalogos')
def catalogos():
    return jsonify(operaciones.catalogos())


@app.get('/api/envios/recientes')
def recientes():
    return jsonify(operaciones.recientes())


@app.post('/api/envios')
def registrar():
    d = request.get_json(force=True)
    faltan = [k for k in ('cliente', 'servicio', 'origen', 'destino', 'peso', 'dest_nombre', 'direccion') if not d.get(k)]
    if faltan:
        return _error('Faltan datos: ' + ', '.join(faltan))
    if str(d['origen']) == str(d['destino']):
        return _error('La agencia de origen y la de destino deben ser distintas')
    try:
        if not 0 < float(d['peso']) <= 50:
            return _error('El peso debe estar entre 0,1 y 50 kg')
    except ValueError:
        return _error('El peso debe ser un número')
    with ESCRITURA:
        try:
            tracking = operaciones.registrar_envio(d)
        except Exception as e:                     # p. ej. reglas del procedimiento almacenado
            return _error(e)
        r = operaciones.replicar(tracking)
    r.update(ok=True, paso=f'Envío {tracking} registrado en PostgreSQL (sp_registrar_envio) con evento ADMISION')
    return jsonify(r)


@app.post('/api/envios/<tracking>/avanzar')
def avanzar(tracking):
    if not PATRON.fullmatch(tracking):
        abort(404)
    with ESCRITURA:
        try:
            paso = operaciones.avanzar(tracking.upper())
        except Exception as e:
            return _error(e)
        r = operaciones.replicar(tracking.upper())
    r.update(ok=True, paso=paso)
    return jsonify(r)


@app.get('/api/cotizar')
def cotizar():
    a = request.args
    if not (a.get('origen') and a.get('destino') and a.get('peso')):
        return _error('Indica agencia de origen, de destino y el peso')
    if a['origen'] == a['destino']:
        return _error('La agencia de origen y la de destino deben ser distintas')
    try:
        return jsonify({'ok': True, **servicios_web.cotizar(int(a['origen']), int(a['destino']), float(a['peso']))})
    except Exception as e:
        return _error(e)


@app.get('/api/seguimiento/<tracking>')
def seguimiento(tracking):
    if not PATRON.fullmatch(tracking.strip()):
        return _error('El número de tracking tiene el formato OLV + 10 dígitos (ej. OLV2600000004)')
    r = servicios_web.seguimiento(tracking)
    return jsonify({'ok': True, **r}) if r else _error(f'No existe un envío con el número {tracking.upper()}', 404)


@app.get('/api/agencias')
def agencias():
    lat, lon = request.args.get('lat'), request.args.get('lon')
    return jsonify(servicios_web.agencias(lat, lon))


@app.get('/api/cuenta/<documento>')
def cuenta(documento):
    if not re.fullmatch(r'\d{8,12}', documento):
        return _error('Ingresa un DNI (8 dígitos) o RUC (11 dígitos)')
    r = servicios_web.mi_cuenta(documento)
    return jsonify({'ok': True, **r}) if r else _error('No hay un cliente registrado con ese documento', 404)


@app.get('/api/cuenta-ejemplos')
def cuenta_ejemplos():
    return jsonify(servicios_web.documentos_ejemplo())


@app.get('/api/operaciones')
def operaciones_resumen():
    return jsonify(servicios_web.operaciones())


@app.get('/api/hub/<hub>/actividad')
def actividad(hub):
    dia = request.args.get('dia', '2026-06-27')
    try:
        return jsonify({'ok': True, **servicios_web.actividad_hub(hub.upper(), dia)})
    except Exception as e:
        return _error(e)


@app.get('/api/hadoop/kpi')
def hadoop_kpi():
    try:
        return jsonify({'ok': True, 'filas': conexiones.hadoop_kpi()})
    except Exception as e:
        return jsonify({'ok': False, 'error': f'{type(e).__name__}: {e}'[:300]})


@app.get('/api/<motor>')
def datos_motor(motor):
    if motor not in conexiones.MOTORES:
        abort(404)
    return jsonify(conexiones.consultar(motor))


@app.get('/api/rastreo/<tracking>')
def rastreo(tracking):
    if not PATRON.fullmatch(tracking.strip()):
        return jsonify({'error': 'El número de tracking tiene el formato OLV + 10 dígitos (ej. OLV2600000004)'}), 400
    return jsonify(conexiones.rastrear(tracking))


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False, threaded=True)
