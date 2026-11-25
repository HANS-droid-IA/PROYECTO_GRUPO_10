"""
Ejecuta consultas reales en Cassandra (cqlsh) y arma transcripciones tipo sesión
(prompt + sentencia + resultado) para las capturas del informe (puntos 10 y 11).
Las salidas de MongoDB se toman de las evidencias reales de 04_NoSQL_MongoDB.
Las contraseñas se leen de .env y nunca se escriben en las transcripciones.
Uso: python generar_transcripciones.py   -> salidas/*.txt
"""
import pathlib
import re
import subprocess

RAIZ = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent / 'salidas'
OUT.mkdir(exist_ok=True)
ENV = dict(l.split('=', 1) for l in (RAIZ / '.env').read_text(encoding='utf-8').splitlines() if '=' in l)
RUIDO = ('Using a password on the command line', 'credentials file to securely')


def cql(sentencia, usuario='olva_admin', clave=None, nodo='olva_cassandra', consistencia=None):
    clave = clave or ENV['CASS_ADMIN_PASSWORD']
    texto = (f'CONSISTENCY {consistencia}; ' if consistencia else '') + sentencia
    r = subprocess.run(['docker', 'exec', nodo, 'cqlsh', '--request-timeout=60', '-u', usuario, '-p', clave,
                        '-k', 'olva_tracking', '-e', texto], capture_output=True, text=True, encoding='utf-8')
    salida = (r.stdout + r.stderr).splitlines()
    salida = [l for l in salida if not any(x in l for x in RUIDO) and not l.startswith('Consistency level set')]
    salida = [re.sub(r'^<stdin>:\d+:', '', l) for l in salida]
    while salida and not salida[0].strip():
        salida.pop(0)
    return salida


def sesion(nombre, pasos):
    lineas = []
    for paso in pasos:
        usuario = paso.get('usuario', 'olva_admin')
        sede = paso.get('sede', 'Lima')
        prompt = f'{usuario}@cqlsh:olva_tracking ({sede})> '
        if 'nota' in paso:
            lineas += ['', '-- ' + paso['nota']]
            continue
        if paso.get('consistencia'):
            lineas.append(prompt + f'CONSISTENCY {paso["consistencia"]};')
        for i, l in enumerate(paso['cql'].strip().splitlines()):
            lineas.append((prompt if i == 0 else ' ' * len(prompt)) + l.strip())
        clave = ENV['CASS_APP_PASSWORD'] if usuario != 'olva_admin' else None
        nodo = 'olva_cassandra_arequipa' if sede == 'Arequipa' else 'olva_cassandra'
        res = cql(paso['cql'], usuario, clave, nodo, paso.get('consistencia'))
        lineas += res if res else ['']
        if res and res[-1].strip():
            lineas.append('')
    (OUT / f'{nombre}.txt').write_text('\n'.join(lineas).rstrip() + '\n', encoding='utf-8')
    print(f'{nombre}.txt: {len(lineas)} líneas')


# 11.2 Modelo CQL
sesion('cq_modelo', [
    {'cql': 'DESCRIBE TABLES;'},
    {'cql': 'DESCRIBE TABLE eventos_por_hub_dia;'},
])

# 11.3 Consultas (1/2): lectura por partición
sesion('cq_consultas_1', [
    {'nota': 'Q1. Historial de un envío: una sola partición, ya ordenada por fecha'},
    {'cql': "SELECT fecha_hora, tipo_evento, hub, ciudad FROM eventos_por_envio WHERE nro_tracking = 'OLV2600000001';"},
    {'nota': 'Q2. Escaneos del Hub Central el 06/10 entre 20:00 y 21:00 (rango sobre la clave de clustering)'},
    {'cql': "SELECT fecha_hora, tipo_evento, nro_tracking, servicio FROM eventos_por_hub_dia\n"
            "WHERE hub = 'HC-LIM' AND dia = '2026-10-06'\n"
            "AND fecha_hora >= '2026-10-07 01:00:00+0000' AND fecha_hora < '2026-10-07 02:00:00+0000' LIMIT 5;"},
])
sesion('cq_consultas_1b', [
    {'nota': 'Q3. Saturación horaria del Hub Central (capacidad: 50 envíos por hora)'},
    {'cql': "SELECT hora, llegadas, salidas, escaneos FROM escaneos_hub_hora\n"
            "WHERE hub = 'HC-LIM' AND dia = '2026-10-06' AND hora >= 18;"},
    {'nota': 'Q4. Portal del cliente: sus envíos más recientes (orden DESC almacenado)'},
    {'cql': "SELECT fecha_registro, nro_tracking, servicio, estado, monto_total FROM envios_por_cliente\n"
            "WHERE id_cliente = 141 LIMIT 4;"},
])

# 11.3 Consultas (2/2): escritura (upsert, LWT, BATCH, TTL) y lo que Cassandra rechaza
TRK = 'OLV2600029865'
sesion('cq_consultas_2', [
    {'nota': 'Q5. Estado actual y transacción ligera (LWT): solo cambia si el estado esperado coincide'},
    {'cql': f"SELECT nro_tracking, estado, ultimo_evento, ultimo_hub FROM estado_envio WHERE nro_tracking = '{TRK}';"},
    {'cql': f"UPDATE estado_envio SET estado = 'ENTREGADO' WHERE nro_tracking = '{TRK}' IF estado = 'EN_REPARTO';"},
    {'cql': f"UPDATE estado_envio SET estado = 'EN_REPARTO', ultimo_evento = 'EN_REPARTO'\nWHERE nro_tracking = '{TRK}' IF estado = 'EN_HUB';"},
])
sesion('cq_consultas_2b', [
    {'nota': 'Q6. BATCH: el mismo escaneo se escribe de forma atómica en las dos tablas desnormalizadas'},
    {'cql': "BEGIN BATCH\n"
            f"INSERT INTO eventos_por_envio (nro_tracking, fecha_hora, id_evento, tipo_evento, hub, ciudad) VALUES ('{TRK}', '2026-10-07 22:50:00+0000', 900000001, 'SALIDA_HUB', 'HC-LIM', 'Callao');\n"
            f"INSERT INTO eventos_por_hub_dia (hub, dia, fecha_hora, id_evento, nro_tracking, tipo_evento, servicio) VALUES ('HC-LIM', '2026-10-07', '2026-10-07 22:50:00+0000', 900000001, '{TRK}', 'SALIDA_HUB', 'ECONOMICO_TERRESTRE');\n"
            "APPLY BATCH;"},
    {'cql': f"SELECT fecha_hora, tipo_evento, hub FROM eventos_por_envio WHERE nro_tracking = '{TRK}' AND fecha_hora >= '2026-10-07 22:00:00+0000';"},
])
sesion('cq_consultas_2c', [
    {'nota': 'Q7. Datos con caducidad (TTL): la alerta se borra sola al vencer'},
    {'cql': f"INSERT INTO alertas_sla (hub, fecha_alerta, nro_tracking, nivel, mensaje)\nVALUES ('HC-LIM', toTimestamp(now()), '{TRK}', 'AVISO', 'Compromiso vence en 1 h') USING TTL 3600;"},
    {'cql': "SELECT nro_tracking, nivel, mensaje, TTL(mensaje) AS segundos_restantes FROM alertas_sla WHERE hub = 'HC-LIM' LIMIT 2;"},
    {'nota': 'Q8. Lo que Cassandra rechaza por diseño: filtrar sin la clave de partición'},
    {'cql': "SELECT * FROM eventos_por_envio WHERE tipo_evento = 'DEVOLUCION' LIMIT 5;"},
])
# se deshacen los cambios de prueba (no forman parte de la transcripción)
cql(f"DELETE FROM eventos_por_envio WHERE nro_tracking = '{TRK}' AND fecha_hora = '2026-10-07 22:50:00+0000' AND id_evento = 900000001;")
cql("DELETE FROM eventos_por_hub_dia WHERE hub = 'HC-LIM' AND dia = '2026-10-07' AND fecha_hora = '2026-10-07 22:50:00+0000' AND id_evento = 900000001;")
cql(f"UPDATE estado_envio SET estado = 'EN_HUB', ultimo_evento = 'CLASIFICACION' WHERE nro_tracking = '{TRK}';")

# 11.4 Seguridad
sesion('cq_seguridad', [
    {'cql': 'LIST ROLES;'},
    {'cql': 'LIST ALL PERMISSIONS OF rol_operador_hub;'},
])
sesion('cq_seguridad_b', [
    {'nota': 'Conectado como u_analista_cass (rol_analista: solo lectura)'},
    {'usuario': 'u_analista_cass', 'cql': "SELECT nro_tracking, estado FROM estado_envio WHERE nro_tracking = 'OLV2600000001';"},
    {'usuario': 'u_analista_cass', 'cql': "UPDATE estado_envio SET estado = 'ENTREGADO' WHERE nro_tracking = 'OLV2600000001';"},
    {'nota': 'Conectado como u_portal_web (rol_portal_cliente: solo 2 tablas)'},
    {'usuario': 'u_portal_web', 'cql': "SELECT nro_tracking, estado FROM estado_envio WHERE nro_tracking = 'OLV2600000001';"},
    {'usuario': 'u_portal_web', 'cql': "DROP TABLE alertas_sla;"},
])
