#!/usr/bin/env python3
"""
Generador de datos de prueba - Proyecto Final BD II
Caso: Trazabilidad de paquetería y courier aéreo/terrestre (Olva Courier)

Los datos son SINTÉTICOS. Se modelan sobre la estructura pública de la operación
(ciudades con cobertura, agencias, hubs, servicios aéreos/terrestres y estados de
tracking), pero ningún registro corresponde a datos internos reales de la empresa.

Simulación:
  1. Catálogos: regiones, ciudades (ubigeo INEI), hubs/agencias, servicios, tarifas,
     rutas, vehículos y empleados.
  2. Clientes (personas y empresas) y destinatarios.
  3. Para cada envío se calcula el camino agencia -> hub -> ... -> hub -> agencia
     (Dijkstra sobre la red de rutas) y se simula cada tramo:
       - consolidación en despachos (manifiestos) con horarios fijos de salida y capacidad,
       - tiempos de clasificación en hub con congestión (cuellos de botella inyectados),
       - retrasos de salida/llegada, reparto, intentos de entrega, devoluciones e incidencias.
  4. Todo evento posterior a la fecha de corte se descarta (envíos "en vuelo").

Uso:  python generar_datos.py [n_envios]      (por defecto 30000)
Salida: ../datos/*.csv   (o la carpeta indicada en la variable de entorno OLVA_OUT)
Big Data: OLVA_OUT=../../06_BigData_Hadoop/data/masivo python generar_datos.py 300000
"""
import csv
import heapq
import math
import os
import random
import sys
from collections import defaultdict
from datetime import datetime, timedelta

SEED = 2026
N_ENVIOS = int(sys.argv[1]) if len(sys.argv) > 1 else 30000
FECHA_INI = datetime(2026, 4, 1)
CORTE = datetime(2026, 10, 7, 18, 0)          # "ahora" de la simulación
OUT = os.environ.get('OLVA_OUT') or os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'datos'))
# Con volúmenes mayores a la base (30 000) la flota y los vuelos crecen en proporción: la capacidad
# de cada despacho se escala para que la red opere igual que en la muestra base (modo Big Data).
ESCALA_CAP = max(1.0, N_ENVIOS / 30000)

rnd = random.Random(SEED)


def ts(d):
    return d.strftime('%Y-%m-%d %H:%M:%S') + '-05' if d else ''


# ------------------------------------------------------------------ catálogos
REGIONES = [  # id, codigo, nombre, nodo
    (1, 'LIM', 'Lima', 'LIMA'), (2, 'CEN', 'Centro', 'LIMA'),
    (3, 'NOR', 'Norte', 'NORTE'), (4, 'ORI', 'Oriente', 'NORTE'),
    (5, 'SUR', 'Sur', 'SUR'),
]
NODO_REGION = {r[0]: r[3] for r in REGIONES}

# id, nombre, departamento, region, ubigeo, aeropuerto, acceso_terrestre, lat, lon, demanda
CIUDADES = [
    (1, 'Lima', 'Lima', 1, '150101', True, True, -12.046400, -77.042800, 40),
    (2, 'Callao', 'Callao', 1, '070101', True, True, -12.056600, -77.118100, 6),
    (3, 'Ica', 'Ica', 1, '110101', False, True, -14.067800, -75.728600, 4),
    (4, 'Huancayo', 'Junín', 2, '120101', True, True, -12.065100, -75.204900, 5),
    (5, 'Ayacucho', 'Ayacucho', 2, '050101', True, True, -13.163100, -74.223600, 2),
    (6, 'Trujillo', 'La Libertad', 3, '130101', True, True, -8.111600, -79.028800, 7),
    (7, 'Chiclayo', 'Lambayeque', 3, '140101', True, True, -6.771400, -79.840900, 6),
    (8, 'Piura', 'Piura', 3, '200101', True, True, -5.194500, -80.632800, 6),
    (9, 'Cajamarca', 'Cajamarca', 3, '060101', True, True, -7.163800, -78.500300, 3),
    (10, 'Iquitos', 'Loreto', 4, '160101', True, False, -3.743700, -73.251600, 4),
    (11, 'Pucallpa', 'Ucayali', 4, '250101', True, True, -8.379100, -74.553900, 3),
    (12, 'Tarapoto', 'San Martín', 4, '220901', True, True, -6.482500, -76.365300, 3),
    (13, 'Arequipa', 'Arequipa', 5, '040101', True, True, -16.409000, -71.537500, 8),
    (14, 'Cusco', 'Cusco', 5, '080101', True, True, -13.532000, -71.967500, 6),
    (15, 'Tacna', 'Tacna', 5, '230101', True, True, -18.014600, -70.253600, 3),
    (16, 'Puno', 'Puno', 5, '210101', False, True, -15.840200, -70.021900, 2),
    (17, 'Juliaca', 'Puno', 5, '211101', True, True, -15.499700, -70.133300, 3),
]
CIUDAD = {c[0]: c for c in CIUDADES}

# Hubs: codigo, nombre, tipo, ciudad, padre(codigo), capacidad de clasificación (envíos/hora, escala de la muestra)
HUBS_DEF = [
    ('HC-LIM', 'Hub Central Lima', 'HUB_CENTRAL', 2, None, 50),
    ('HR-TRU', 'Hub Regional Trujillo', 'HUB_REGIONAL', 6, 'HC-LIM', 15),
    ('HR-CIX', 'Hub Regional Chiclayo', 'HUB_REGIONAL', 7, 'HC-LIM', 15),
    ('HR-PIU', 'Hub Regional Piura', 'HUB_REGIONAL', 8, 'HC-LIM', 12),
    ('HR-HYO', 'Hub Regional Huancayo', 'HUB_REGIONAL', 4, 'HC-LIM', 12),
    ('HR-IQT', 'Hub Regional Iquitos', 'HUB_REGIONAL', 10, 'HC-LIM', 8),
    ('HR-AQP', 'Hub Regional Arequipa', 'HUB_REGIONAL', 13, 'HC-LIM', 18),
    ('HR-CUZ', 'Hub Regional Cusco', 'HUB_REGIONAL', 14, 'HC-LIM', 14),
    ('HR-JUL', 'Hub Regional Juliaca', 'HUB_REGIONAL', 17, 'HC-LIM', 10),
    # Agencias (puntos de admisión y reparto)
    ('AG-LIM-MIR', 'Agencia Miraflores', 'AGENCIA', 1, 'HC-LIM', 15),
    ('AG-LIM-SIS', 'Agencia San Isidro', 'AGENCIA', 1, 'HC-LIM', 15),
    ('AG-LIM-OLI', 'Agencia Los Olivos', 'AGENCIA', 1, 'HC-LIM', 15),
    ('AG-LIM-SJL', 'Agencia San Juan de Lurigancho', 'AGENCIA', 1, 'HC-LIM', 15),
    ('AG-LIM-SUR', 'Agencia Santiago de Surco', 'AGENCIA', 1, 'HC-LIM', 15),
    ('AG-LIM-ATE', 'Agencia Ate', 'AGENCIA', 1, 'HC-LIM', 12),
    ('AG-CAL-01', 'Agencia Callao', 'AGENCIA', 2, 'HC-LIM', 12),
    ('AG-ICA-01', 'Agencia Ica', 'AGENCIA', 3, 'HC-LIM', 10),
    ('AG-PCL-01', 'Agencia Pucallpa', 'AGENCIA', 11, 'HC-LIM', 8),
    ('AG-HYO-01', 'Agencia Huancayo Centro', 'AGENCIA', 4, 'HR-HYO', 10),
    ('AG-HYO-02', 'Agencia El Tambo', 'AGENCIA', 4, 'HR-HYO', 8),
    ('AG-AYA-01', 'Agencia Ayacucho', 'AGENCIA', 5, 'HR-HYO', 8),
    ('AG-TRU-01', 'Agencia Trujillo Centro', 'AGENCIA', 6, 'HR-TRU', 10),
    ('AG-TRU-02', 'Agencia Trujillo La Esperanza', 'AGENCIA', 6, 'HR-TRU', 8),
    ('AG-CAJ-01', 'Agencia Cajamarca', 'AGENCIA', 9, 'HR-TRU', 8),
    ('AG-CIX-01', 'Agencia Chiclayo Centro', 'AGENCIA', 7, 'HR-CIX', 10),
    ('AG-CIX-02', 'Agencia José Leonardo Ortiz', 'AGENCIA', 7, 'HR-CIX', 8),
    ('AG-TPP-01', 'Agencia Tarapoto', 'AGENCIA', 12, 'HR-CIX', 8),
    ('AG-PIU-01', 'Agencia Piura Centro', 'AGENCIA', 8, 'HR-PIU', 10),
    ('AG-PIU-02', 'Agencia Castilla', 'AGENCIA', 8, 'HR-PIU', 8),
    ('AG-IQT-01', 'Agencia Iquitos', 'AGENCIA', 10, 'HR-IQT', 8),
    ('AG-AQP-01', 'Agencia Arequipa Centro', 'AGENCIA', 13, 'HR-AQP', 10),
    ('AG-AQP-02', 'Agencia Cayma', 'AGENCIA', 13, 'HR-AQP', 8),
    ('AG-AQP-03', 'Agencia Paucarpata', 'AGENCIA', 13, 'HR-AQP', 8),
    ('AG-TCQ-01', 'Agencia Tacna', 'AGENCIA', 15, 'HR-AQP', 8),
    ('AG-CUZ-01', 'Agencia Cusco Centro', 'AGENCIA', 14, 'HR-CUZ', 10),
    ('AG-CUZ-02', 'Agencia Wanchaq', 'AGENCIA', 14, 'HR-CUZ', 8),
    ('AG-JUL-01', 'Agencia Juliaca', 'AGENCIA', 17, 'HR-JUL', 8),
    ('AG-PUN-01', 'Agencia Puno', 'AGENCIA', 16, 'HR-JUL', 8),
]
HUB_ID = {h[0]: i + 1 for i, h in enumerate(HUBS_DEF)}
HUB = {HUB_ID[h[0]]: {'id': HUB_ID[h[0]], 'codigo': h[0], 'nombre': h[1], 'tipo': h[2], 'ciudad': h[3],
                       'padre': HUB_ID[h[4]] if h[4] else None, 'cap': h[5]} for h in HUBS_DEF}
AGENCIAS = [h for h in HUB.values() if h['tipo'] == 'AGENCIA']
HC = HUB_ID['HC-LIM']


def region_hub(hid):
    return CIUDAD[HUB[hid]['ciudad']][3]


def nodo_hub(hid):
    return NODO_REGION[region_hub(hid)]


# id, codigo, nombre, modalidad, sla_horas, peso_max, base, kg_adic, recargo_interregional
SERVICIOS = [
    (1, 'EXPRESS_AEREO', 'Express Aéreo', 'AEREO', 48, 30, 18.00, 6.50, 8.00),
    (2, 'SOBRE_AEREO', 'Sobre / Documentos Aéreo', 'AEREO', 48, 0.5, 12.00, 0.00, 5.00),
    (3, 'ESTANDAR_TERRESTRE', 'Estándar Terrestre', 'TERRESTRE', 72, 50, 12.00, 2.50, 6.00),
    (4, 'ECONOMICO_TERRESTRE', 'Económico Terrestre', 'TERRESTRE', 120, 100, 9.00, 1.80, 4.00),
]
SERV = {s[0]: s for s in SERVICIOS}

# ------------------------------------------------------------------ rutas
# tramos agencia <-> hub padre fuera de la misma ciudad: (km, horas)
TRAMO_AGENCIA = {
    'AG-ICA-01': (305, 5.0), 'AG-PCL-01': (780, 18.0), 'AG-AYA-01': (255, 7.0),
    'AG-CAJ-01': (300, 6.0), 'AG-TPP-01': (640, 12.0), 'AG-TCQ-01': (370, 6.0),
    'AG-PUN-01': (45, 1.0),
}
# hub regional <-> hub central: terrestre (km,h) / aereo (km,h incl. manipuleo)
TRONCALES = {
    'HR-TRU': ((560, 9.0), (490, 2.5)), 'HR-CIX': ((770, 12.0), (660, 2.8)),
    'HR-PIU': ((980, 15.0), (860, 3.0)), 'HR-HYO': ((300, 7.0), (170, 2.2)),
    'HR-IQT': (None, (1010, 3.3)), 'HR-AQP': ((1010, 16.0), (770, 3.0)),
    'HR-CUZ': ((1100, 21.0), (580, 3.0)), 'HR-JUL': ((1290, 22.0), (850, 3.2)),
}
# hub regional <-> hub regional (terrestre, misma macro-región)
INTER_REGIONAL = [('HR-TRU', 'HR-CIX', 210, 4.0), ('HR-CIX', 'HR-PIU', 210, 3.5),
                  ('HR-AQP', 'HR-JUL', 280, 5.0), ('HR-AQP', 'HR-CUZ', 510, 10.0),
                  ('HR-CUZ', 'HR-JUL', 340, 7.0)]

RUTAS = []          # dicts
RUTA_IDX = {}       # (o, d, modalidad) -> ruta


def add_ruta(o, d, mod, km, h):
    for a, b in ((o, d), (d, o)):
        r = {'id': len(RUTAS) + 1, 'o': a, 'd': b, 'mod': mod, 'km': km, 'h': h}
        RUTAS.append(r)
        RUTA_IDX[(a, b, mod)] = r


for ag in AGENCIAS:
    km, h = TRAMO_AGENCIA.get(ag['codigo'], (12, 0.8))
    add_ruta(ag['id'], ag['padre'], 'TERRESTRE', km, h)
for code, (ter, aer) in TRONCALES.items():
    if ter:
        add_ruta(HUB_ID[code], HC, 'TERRESTRE', *ter)
    add_ruta(HUB_ID[code], HC, 'AEREO', *aer)
for a, b, km, h in INTER_REGIONAL:
    add_ruta(HUB_ID[a], HUB_ID[b], 'TERRESTRE', km, h)

ESPERA_HUB = 8.0  # penalización por cada transbordo en hub (h) para Dijkstra


def camino_hubs(o, d, aereo):
    """Dijkstra entre hubs (no agencias). Devuelve lista de rutas."""
    if o == d:
        return []
    dist, prev, pq = {o: 0}, {}, [(0, o)]
    while pq:
        c, u = heapq.heappop(pq)
        if u == d:
            break
        if c > dist.get(u, 1e9):
            continue
        for (a, b, mod), r in RUTA_IDX.items():
            if a != u or HUB[b]['tipo'] == 'AGENCIA':
                continue
            if mod == 'AEREO' and not aereo:
                continue
            nc = c + r['h'] + ESPERA_HUB
            if nc < dist.get(b, 1e9):
                dist[b], prev[b] = nc, r
                heapq.heappush(pq, (nc, b))
    if d not in prev:
        return None
    path, x = [], d
    while x != o:
        r = prev[x]
        path.append(r)
        x = r['o']
    return path[::-1]


def camino(ag_o, ag_d, aereo):
    p = [RUTA_IDX[(ag_o, HUB[ag_o]['padre'], 'TERRESTRE')]]
    mid = camino_hubs(HUB[ag_o]['padre'], HUB[ag_d]['padre'], aereo)
    if mid is None:
        return None
    p += mid
    p.append(RUTA_IDX[(HUB[ag_d]['padre'], ag_d, 'TERRESTRE')])
    return p


# ------------------------------------------------------------------ nombres
NOMBRES = ['José', 'Luis', 'Carlos', 'Juan', 'Jorge', 'Miguel', 'Pedro', 'César', 'Víctor', 'Raúl',
           'Rosa', 'María', 'Ana', 'Carmen', 'Lucía', 'Patricia', 'Elena', 'Sofía', 'Gabriela',
           'Diana', 'Fernando', 'Ricardo', 'Andrés', 'Diego', 'Renzo', 'Kevin', 'Jhon', 'Milagros',
           'Rocío', 'Karina', 'Yesenia', 'Flor', 'Edwin', 'Wilmer', 'Percy', 'Giancarlo', 'Valeria',
           'Camila', 'Daniela', 'Alejandro', 'Sebastián', 'Mariela', 'Liliana', 'Hugo', 'Óscar']
APELLIDOS = ['Quispe', 'Flores', 'Sánchez', 'Rodríguez', 'García', 'Mamani', 'Huamán', 'Rojas',
             'Chávez', 'Díaz', 'Torres', 'Vásquez', 'Ramírez', 'Mendoza', 'Ramos', 'Castillo',
             'Gonzales', 'Espinoza', 'Cruz', 'Gutiérrez', 'Pérez', 'López', 'Condori', 'Vargas',
             'Salazar', 'Ccama', 'Paredes', 'Cárdenas', 'Romero', 'Ríos', 'Aguilar', 'Silva',
             'Alvarado', 'Medina', 'Cabrera', 'Villanueva', 'Navarro', 'Palomino', 'Ticona', 'Apaza']
EMP_PREF = ['Comercial', 'Inversiones', 'Distribuidora', 'Importaciones', 'Corporación', 'Textil',
            'Agroexportadora', 'Tecnología', 'Negociaciones', 'Servicios Generales', 'Representaciones']
EMP_NUC = ['Andina', 'del Pacífico', 'Inca', 'Norteña', 'Sureña', 'Amazónica', 'Santa Rosa',
           'San Martín', 'Los Andes', 'Mistiana', 'Chimú', 'Moche', 'Wari', 'Titicaca', 'Huascarán',
           'Kallpa', 'Inti', 'Sumaq', 'Pachacútec', 'Misti', 'Selva Verde', 'Costa Azul']
EMP_SUF = ['S.A.C.', 'E.I.R.L.', 'S.A.', 'S.R.L.']
VIAS = ['Av.', 'Jr.', 'Calle', 'Psje.']
DESCRIPCIONES = ['Ropa', 'Documentos', 'Electrónicos', 'Repuestos', 'Calzado', 'Libros', 'Accesorios',
                 'Cosméticos', 'Juguetes', 'Alimentos no perecibles', 'Útiles de oficina', 'Artesanía']


def nombre_persona():
    return rnd.choice(NOMBRES), f'{rnd.choice(APELLIDOS)} {rnd.choice(APELLIDOS)}'


def direccion():
    return f'{rnd.choice(VIAS)} {rnd.choice(APELLIDOS)} {rnd.randint(100, 2999)}'


def dni():
    return f'{rnd.randint(10000000, 79999999)}'


def telefono():
    return f'9{rnd.randint(10000000, 99999999)}'


def placa():
    l = 'ABCDEFGHJKLMNPRSTUVWXYZ'
    return f'{rnd.choice(l)}{rnd.randint(0, 9)}{rnd.choice(l)}-{rnd.randint(100, 999)}'


def slug(s):
    t = str.maketrans('áéíóúñÁÉÍÓÚÑ', 'aeiounAEIOUN')
    return ''.join(ch for ch in s.translate(t).lower() if ch.isalnum() or ch == '.')


# ------------------------------------------------------------------ empleados / vehículos
EMPLEADOS = []
EMP_HUB = defaultdict(lambda: defaultdict(list))  # hub -> cargo -> [ids]
dnis_usados = set()


def add_empleado(hub, cargo):
    while True:
        d = dni()
        if d not in dnis_usados:
            dnis_usados.add(d)
            break
    n, a = nombre_persona()
    eid = len(EMPLEADOS) + 1
    EMPLEADOS.append([eid, d, n, a, cargo, hub,
                      (FECHA_INI - timedelta(days=rnd.randint(60, 3000))).date().isoformat(), 't'])
    EMP_HUB[hub][cargo].append(eid)


for h in HUB.values():
    if h['tipo'] == 'HUB_CENTRAL':
        plan = {'OPERARIO_HUB': 20, 'CONDUCTOR': 8, 'SUPERVISOR': 3}
    elif h['tipo'] == 'HUB_REGIONAL':
        plan = {'OPERARIO_HUB': 6, 'CONDUCTOR': 3, 'SUPERVISOR': 1}
    else:
        plan = {'ATENCION': 2, 'COURIER': 3, 'SUPERVISOR': 1}
    for cargo, n in plan.items():
        for _ in range(n):
            add_empleado(h['id'], cargo)

VEHICULOS = []
VEH_HUB = defaultdict(lambda: defaultdict(list))
placas = set()
for h in HUB.values():
    plan = {'HUB_CENTRAL': {'CAMION': 10, 'FURGONETA': 4}, 'HUB_REGIONAL': {'CAMION': 3, 'FURGONETA': 2},
            'AGENCIA': {'FURGONETA': 1, 'MOTO': 2}}[h['tipo']]
    for tipo, n in plan.items():
        for _ in range(n):
            p = placa()
            while p in placas:
                p = placa()
            placas.add(p)
            vid = len(VEHICULOS) + 1
            cap = {'CAMION': rnd.choice([8000, 10000, 12000]), 'FURGONETA': rnd.choice([1200, 1500]),
                   'MOTO': 40}[tipo]
            VEHICULOS.append([vid, p, tipo, cap, h['id'], 't'])
            VEH_HUB[h['id']][tipo].append(vid)

# ------------------------------------------------------------------ clientes
CLIENTES = []
CLI_PESO = []
docs = set()
agencias_por_ciudad = defaultdict(list)
for ag in AGENCIAS:
    agencias_por_ciudad[ag['ciudad']].append(ag['id'])
ciudades_ids = [c[0] for c in CIUDADES]
dem = [c[9] for c in CIUDADES]

for cid in range(1, 3001):
    empresa = cid <= 600
    if empresa:
        ciudad = 1 if rnd.random() < 0.65 else rnd.choices(ciudades_ids, dem)[0]
        while True:
            ruc = f'20{rnd.randint(100000000, 999999999)}'
            if ruc not in docs:
                docs.add(ruc)
                break
        nombre = f'{rnd.choice(EMP_PREF)} {rnd.choice(EMP_NUC)} {rnd.choice(EMP_SUF)}'
        email = f'ventas@{slug(nombre.split(" S.")[0].split(" E.")[0])[:20]}.com.pe'
        CLIENTES.append([cid, 'EMPRESA', 'RUC', ruc, nombre, email, telefono(), direccion(), ciudad,
                         (FECHA_INI - timedelta(days=rnd.randint(1, 1500))).date().isoformat()])
        CLI_PESO.append(rnd.paretovariate(1.2) * 6)
    else:
        ciudad = rnd.choices(ciudades_ids, dem)[0]
        tipo_doc = 'DNI' if rnd.random() < 0.96 else 'CE'
        while True:
            doc = dni() if tipo_doc == 'DNI' else f'{rnd.randint(100000000, 999999999)}'
            if doc not in docs:
                docs.add(doc)
                break
        n, a = nombre_persona()
        email = f'{slug(n)}.{slug(a.split()[0])}{rnd.randint(1, 999)}@correo.pe'
        reg = FECHA_INI + timedelta(days=rnd.randint(-900, 150))
        CLIENTES.append([cid, 'PERSONA', tipo_doc, doc, f'{n} {a}', email, telefono(), direccion(), ciudad,
                         reg.date().isoformat()])
        CLI_PESO.append(1.0)
CLI = {c[0]: c for c in CLIENTES}

# ------------------------------------------------------------------ tarifas
TARIFAS = []
TARIFA_IDX = {}
tid = 0
for s in SERVICIOS:
    for ro in REGIONES:
        for rd in REGIONES:
            tid += 1
            base = s[6] + (0 if ro[0] == rd[0] else s[8]) + (6 if rd[0] == 4 and ro[0] != 4 else 0)
            TARIFAS.append([tid, s[0], ro[0], rd[0], f'{base:.2f}', f'{s[7]:.2f}', '2026-01-01', ''])
            TARIFA_IDX[(s[0], ro[0], rd[0])] = (base, s[7])


def calcular_tarifa(serv, ro, rd, peso):
    base, kg = TARIFA_IDX[(serv, ro, rd)]
    return round(base + max(0, math.ceil(peso - 1)) * kg, 2)


# ------------------------------------------------------------------ simulación
SLOTS = {  # horarios de salida de despachos por tipo de tramo
    'AG_HUB_LOCAL': [(13, 0), (19, 30)], 'AG_HUB_PROV': [(20, 0)],
    'HUB_AG_LOCAL': [(6, 0), (14, 30)], 'HUB_AG_PROV': [(21, 0)],
    'TRONCAL_TERRESTRE': [(23, 30)], 'TRONCAL_AEREO': [(8, 0), (17, 30)],
}
CAPACIDAD = {'AG_HUB_LOCAL': 400, 'AG_HUB_PROV': 300, 'HUB_AG_LOCAL': 400, 'HUB_AG_PROV': 300,
             'TRONCAL_TERRESTRE': 250, 'TRONCAL_AEREO': 70}
AEROLINEAS = ['LA', 'H2', 'JA']


def tipo_tramo(r):
    o, d = HUB[r['o']], HUB[r['d']]
    local = r['km'] <= 50          # tramo urbano / metropolitano (p.ej. Lima -> Hub Central en Callao)
    if o['tipo'] == 'AGENCIA':
        return 'AG_HUB_LOCAL' if local else 'AG_HUB_PROV'
    if d['tipo'] == 'AGENCIA':
        return 'HUB_AG_LOCAL' if local else 'HUB_AG_PROV'
    return 'TRONCAL_AEREO' if r['mod'] == 'AEREO' else 'TRONCAL_TERRESTRE'


def next_slot(t, slots):
    day = t.replace(hour=0, minute=0, second=0, microsecond=0)
    for k in range(0, 10):
        for hh, mm in slots:
            s = day + timedelta(days=k, hours=hh, minutes=mm)
            if s >= t:
                return s
    raise RuntimeError('sin slot')


DESPACHOS = {}   # (ruta, salida_prog) -> dict
DESPACHO_LIST = []


def despacho_para(r, ready):
    tt = tipo_tramo(r)
    cap = CAPACIDAD[tt]
    if r['d'] == HUB_ID['HR-IQT'] or r['o'] == HUB_ID['HR-IQT']:
        cap = 25  # bodega de vuelo limitada a Iquitos
    cap = int(cap * ESCALA_CAP)
    t = ready
    while True:
        s = next_slot(t, SLOTS[tt])
        key = (r['id'], s)
        d = DESPACHOS.get(key)
        if d is None:
            d = crear_despacho(r, s, tt)
            DESPACHOS[key] = d
        if d['n'] < cap:
            d['n'] += 1
            return d
        t = s + timedelta(minutes=1)


def crear_despacho(r, salida_prog, tt):
    if r['mod'] == 'AEREO':
        demora = rnd.choices([rnd.uniform(0, 20), rnd.uniform(20, 90), rnd.uniform(90, 240)], [70, 22, 8])[0]
        dur = r['h'] * rnd.uniform(0.95, 1.15)
        veh, vuelo = '', f'{rnd.choice(AEROLINEAS)}{rnd.randint(1000, 2999)}'
    else:
        demora = rnd.uniform(0, 45) + (rnd.uniform(60, 180) if rnd.random() < 0.10 else 0)
        dur = r['h'] * rnd.uniform(0.9, 1.2)
        if r['h'] > 6 and rnd.random() < 0.06:
            dur += rnd.uniform(2, 8)  # bloqueo de vía / clima
        base = r['o']
        tipo_v = 'CAMION' if tt.startswith('TRONCAL') else 'FURGONETA'
        pool = VEH_HUB[base][tipo_v] or VEH_HUB[HUB[base]['padre'] or HC]['CAMION']
        veh, vuelo = rnd.choice(pool), ''
    sal = salida_prog + timedelta(minutes=demora)
    lleg = sal + timedelta(hours=dur)
    d = {'id': len(DESPACHO_LIST) + 1, 'ruta': r, 'prog': salida_prog, 'sal': sal, 'lleg': lleg,
         'veh': veh, 'vuelo': vuelo, 'n': 0}
    DESPACHO_LIST.append(d)
    return d


def factor_congestion(hid, t):
    f = 1.0
    if hid == HC:
        if t.hour >= 18 or t.hour < 2:
            f *= 2.4          # cuello de botella nocturno en Hub Central
        if t.weekday() == 0:
            f *= 1.3          # lunes: acumulado del fin de semana
    if hid == HUB_ID['HR-AQP'] and t.month in (8, 9):
        f *= 1.9              # déficit de personal simulado (ago-sep)
    if (t.month == 7 and 15 <= t.day <= 31):
        f *= 1.25             # campaña Fiestas Patrias
    return f


def inicio_reparto(t):
    day = t.replace(hour=0, minute=0, second=0, microsecond=0)
    if t <= day + timedelta(hours=8, minutes=15):
        s = day + timedelta(hours=8, minutes=30)
    elif t <= day + timedelta(hours=15, minutes=30):
        s = day + timedelta(hours=16)
    else:
        s = day + timedelta(days=1, hours=8, minutes=30)
    while s.weekday() == 6:   # domingo sin reparto
        s = (s + timedelta(days=1)).replace(hour=8, minute=30)
    return s


def fin_dia_habil(t):
    """El compromiso vence a las 20:00 del día alcanzado por el SLA; domingo pasa a lunes."""
    c = t.replace(hour=20, minute=0, second=0, microsecond=0)
    if t > c:
        c += timedelta(days=1)
    if c.weekday() == 6:
        c += timedelta(days=1)
    return c


def siguiente_dia_reparto(t):
    s = (t + timedelta(days=1)).replace(hour=8, minute=30, second=0, microsecond=0)
    while s.weekday() == 6:
        s += timedelta(days=1)
    return s


# volumen diario: estacionalidad semanal + campaña + tendencia
dias = []
d = FECHA_INI
while d.date() <= CORTE.date():
    w = [1.2, 1.1, 1.05, 1.0, 1.05, 0.7, 0.25][d.weekday()]
    if d.month == 7 and 10 <= d.day <= 27:
        w *= 1.45
    w *= 1 + 0.002 * (d - FECHA_INI).days
    dias.append((d, w))
    d += timedelta(days=1)
tot = sum(w for _, w in dias)
registros = []
for d, w in dias:
    n = int(round(N_ENVIOS * w / tot))
    for _ in range(n):
        h = rnd.choices(range(8, 20), [3, 6, 8, 8, 7, 6, 7, 8, 8, 7, 5, 3])[0]
        t = d + timedelta(hours=h, minutes=rnd.randint(0, 59), seconds=rnd.randint(0, 59))
        if t < CORTE - timedelta(minutes=30):
            registros.append(t)
registros.sort()

ENVIOS, PAQUETES, COMPROBANTES, DESTINATARIOS = [], [], [], []
EVENTOS, INTENTOS, INCIDENCIAS, DESP_ENVIO = [], [], [], []
serie_num = defaultdict(int)
cli_ids = [c[0] for c in CLIENTES]
dest_ciudad_w = dem


def evento(env, tipo, hub, t, emp=None, desp=None, obs=''):
    if t <= CORTE:
        EVENTOS.append([len(EVENTOS) + 1, env, tipo, hub, emp or '', desp or '', ts(t), obs])
        return True
    return False


def emp(hub, cargo):
    l = EMP_HUB[hub][cargo] or EMP_HUB[hub]['OPERARIO_HUB'] or EMP_HUB[hub]['ATENCION']
    return rnd.choice(l)


def incidencia(env, tipo, hub, t, desc, dias_cierre=None):
    if t > CORTE:
        return
    estado, cierre = 'ABIERTA', ''
    if dias_cierre is not None:
        c = t + timedelta(days=dias_cierre)
        if c <= CORTE:
            estado, cierre = 'CERRADA', ts(c)
        elif rnd.random() < 0.5:
            estado = 'EN_PROCESO'
    INCIDENCIAS.append([len(INCIDENCIAS) + 1, env, tipo, hub or '', ts(t), desc, estado, cierre])


ESTADO_EVENTO = {'ADMISION': 'ADMITIDO', 'LLEGADA_HUB': 'EN_HUB', 'CLASIFICACION': 'EN_HUB',
                 'SALIDA_HUB': 'EN_TRANSITO', 'EN_REPARTO': 'EN_REPARTO', 'INTENTO_FALLIDO': 'INTENTO_FALLIDO',
                 'ENTREGA': 'ENTREGADO', 'DEVOLUCION': 'DEVUELTO'}

for i, t_reg in enumerate(registros, start=1):
    # cliente remitente y agencias
    cid = rnd.choices(cli_ids, CLI_PESO)[0]
    cli = CLI[cid]
    ag_o = rnd.choice(agencias_por_ciudad[cli[8]])
    while True:
        ciudad_d = rnd.choices(ciudades_ids, dest_ciudad_w)[0]
        ag_d = rnd.choice(agencias_por_ciudad[ciudad_d])
        if ag_d != ag_o:
            break
    local = HUB[ag_o]['ciudad'] == HUB[ag_d]['ciudad']
    sin_carretera = not CIUDAD[ciudad_d][6] or not CIUDAD[HUB[ag_o]['ciudad']][6]
    if local:
        serv = rnd.choices([3, 4], [70, 30])[0]
    elif sin_carretera:
        serv = rnd.choices([1, 2], [75, 25])[0]
    else:
        serv = rnd.choices([1, 2, 3, 4], [30, 12, 40, 18])[0]
    s = SERV[serv]
    # paquetes
    nb = 1 if serv == 2 else rnd.choices([1, 2, 3], [70, 20, 10])[0]
    peso_total = 0
    for b in range(1, nb + 1):
        if serv == 2:
            p = round(rnd.uniform(0.05, 0.5), 2)
            dims = (32.0, 24.0, 1.5)
            desc = 'Documentos'
        else:
            p = round(min(max(rnd.lognormvariate(0.6, 0.8), 0.2), s[5] / nb), 2)
            lado = max(10.0, round((p * 5000) ** (1 / 3), 1))
            dims = (round(lado * rnd.uniform(1, 1.6), 1), lado, round(lado * rnd.uniform(0.5, 1), 1))
            desc = rnd.choice(DESCRIPCIONES[0:1] + DESCRIPCIONES[2:])
        peso_total += p
        PAQUETES.append([len(PAQUETES) + 1, i, b, f'{p:.2f}', *dims, desc, 't' if rnd.random() < 0.15 else 'f'])
    peso_total = round(peso_total, 2)
    ro, rd = region_hub(ag_o), region_hub(ag_d)
    monto = calcular_tarifa(serv, ro, rd, peso_total)
    sla = 48 if local else s[4]
    compromiso = fin_dia_habil(t_reg + timedelta(hours=sla))
    # destinatario
    if DESTINATARIOS and rnd.random() < 0.12:
        dest_id = rnd.randint(1, len(DESTINATARIOS))
    else:
        n, a = nombre_persona()
        tiene_doc = rnd.random() < 0.8
        DESTINATARIOS.append([len(DESTINATARIOS) + 1, f'{n} {a}', 'DNI' if tiene_doc else '',
                              dni() if tiene_doc else '', telefono()])
        dest_id = len(DESTINATARIOS)
    tracking = f'OLV{2600000000 + i:010d}'
    valor_decl = round(rnd.uniform(50, 2500), 2) if rnd.random() < 0.4 else 0
    # comprobante
    tipo_c = 'FACTURA' if cli[1] == 'EMPRESA' else 'BOLETA'
    serie = f'{tipo_c[0]}{ag_o:03d}'
    serie_num[serie] += 1
    if cli[1] == 'EMPRESA':
        metodo = rnd.choices(['CREDITO', 'TARJETA', 'BILLETERA_DIGITAL'], [60, 30, 10])[0]
    else:
        metodo = rnd.choices(['EFECTIVO', 'TARJETA', 'BILLETERA_DIGITAL'], [40, 25, 35])[0]
    subtotal = round(monto / 1.18, 2)
    COMPROBANTES.append([i, i, tipo_c, serie, serie_num[serie], ts(t_reg), f'{subtotal:.2f}',
                         f'{monto - subtotal:.2f}', f'{monto:.2f}', metodo])

    # ---- simulación de trayecto
    n_ev0 = len(EVENTOS)
    evento(i, 'ADMISION', ag_o, t_reg, emp(ag_o, 'ATENCION'))
    ruta = camino(ag_o, ag_d, s[3] == 'AEREO')
    perdida = rnd.random() < 0.0015
    danado = rnd.random() < 0.006
    tramo_perdida = rnd.randint(1, max(1, len(ruta) - 1)) if perdida else -1
    ready = t_reg + timedelta(minutes=30)
    fin = None
    for k, r in enumerate(ruta):
        dsp = despacho_para(r, ready)
        DESP_ENVIO.append((dsp, i, ready))
        cargo_o = 'ATENCION' if HUB[r['o']]['tipo'] == 'AGENCIA' else 'OPERARIO_HUB'
        evento(i, 'SALIDA_HUB', r['o'], dsp['sal'], emp(r['o'], cargo_o), dsp['id'])
        llegada = dsp['lleg']
        cargo_d = 'ATENCION' if HUB[r['d']]['tipo'] == 'AGENCIA' else 'OPERARIO_HUB'
        evento(i, 'LLEGADA_HUB', r['d'], llegada, emp(r['d'], cargo_d), dsp['id'])
        if k == tramo_perdida:
            incidencia(i, 'PERDIDA', r['d'], llegada + timedelta(days=3),
                       'Paquete no ubicado en inventario del hub tras arribo de manifiesto', 12)
            fin = 'PERDIDO'
            break
        if HUB[r['d']]['tipo'] != 'AGENCIA':
            clas = llegada + timedelta(hours=rnd.lognormvariate(math.log(1.2), 0.45) *
                                       factor_congestion(r['d'], llegada))
            evento(i, 'CLASIFICACION', r['d'], clas, emp(r['d'], 'OPERARIO_HUB'))
            if danado and k == 1:
                incidencia(i, 'DANO', r['d'], clas, 'Embalaje dañado detectado en clasificación', rnd.randint(2, 7))
            ready = clas + timedelta(minutes=30)
        else:
            ready = llegada
    fecha_entrega = None
    if fin is None:
        t = inicio_reparto(ready)
        courier = emp(ag_d, 'COURIER')
        for intento in range(1, 4):
            if not evento(i, 'EN_REPARTO', ag_d, t, courier):
                break
            t_int = t + timedelta(minutes=rnd.randint(45, 480) if t.hour < 12 else rnd.randint(30, 200))
            res = rnd.choices(['ENTREGADO', 'AUSENTE', 'DIRECCION_ERRADA', 'RECHAZADO'], [86, 9, 3, 2])[0]
            if intento == 3 and res != 'ENTREGADO':
                res = 'AUSENTE'
            if t_int > CORTE:
                break
            if res == 'ENTREGADO':
                dd = DESTINATARIOS[dest_id - 1]
                otro = rnd.random() < 0.2
                rec_nom = f'{rnd.choice(NOMBRES)} {dd[1].split()[-2]}' if otro else dd[1]
                rec_doc = dni() if otro else (dd[3] or dni())
                INTENTOS.append([len(INTENTOS) + 1, i, intento, ts(t_int), courier, res, rec_nom, rec_doc])
                evento(i, 'ENTREGA', ag_d, t_int, courier)
                fecha_entrega = t_int
                fin = 'ENTREGADO'
                break
            INTENTOS.append([len(INTENTOS) + 1, i, intento, ts(t_int), courier, res, '', ''])
            evento(i, 'INTENTO_FALLIDO', ag_d, t_int, courier, obs=res.replace('_', ' ').capitalize())
            if res == 'DIRECCION_ERRADA':
                incidencia(i, 'DIRECCION_INCORRECTA', ag_d, t_int + timedelta(minutes=20),
                           'Dirección de entrega no ubicada por el courier', 1)
            if res == 'RECHAZADO' or intento == 3:
                tdev = siguiente_dia_reparto(t_int)
                if evento(i, 'DEVOLUCION', ag_d, tdev, emp(ag_d, 'SUPERVISOR'),
                          obs='Rechazado por destinatario' if res == 'RECHAZADO' else 'Tres intentos fallidos'):
                    fin = 'DEVUELTO'
                break
            t = siguiente_dia_reparto(t_int)
    if fecha_entrega and fecha_entrega > compromiso and rnd.random() < 0.3:
        incidencia(i, 'RETRASO', '', compromiso + timedelta(hours=rnd.randint(4, 30)),
                   'Reclamo del cliente por entrega fuera de plazo', rnd.randint(1, 4))
    ultimo = EVENTOS[-1][2] if len(EVENTOS) > n_ev0 else None
    estado = ESTADO_EVENTO.get(ultimo, 'REGISTRADO')
    ENVIOS.append([i, tracking, cid, dest_id, serv, ag_o, ag_d, direccion(), ts(t_reg), ts(compromiso),
                   estado, f'{peso_total:.2f}', f'{valor_decl:.2f}', f'{monto:.2f}', ts(fecha_entrega)])

# ------------------------------------------------------------------ despachos
DESP_ROWS = []
for d in DESPACHO_LIST:
    if d['prog'] > CORTE + timedelta(days=2):
        continue
    sal = d['sal'] if d['sal'] <= CORTE else None
    lleg = d['lleg'] if d['lleg'] <= CORTE else None
    estado = 'ARRIBADO' if lleg else ('EN_RUTA' if sal else 'PROGRAMADO')
    DESP_ROWS.append([d['id'], f"MF{d['prog']:%y%m%d}-{d['id']:06d}", d['ruta']['id'], d['veh'], d['vuelo'],
                      ts(d['prog']), ts(sal), ts(lleg), estado])
validos = {r[0] for r in DESP_ROWS}
DE_ROWS = [[d['id'], env, ts(t)] for d, env, t in DESP_ENVIO if d['id'] in validos]

# ------------------------------------------------------------------ escritura CSV
os.makedirs(OUT, exist_ok=True)


def write(nombre, header, rows):
    with open(os.path.join(OUT, f'{nombre}.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f'{nombre:<16} {len(rows):>9,} filas')


write('region', ['id_region', 'codigo', 'nombre', 'nodo'], REGIONES)
write('ciudad', ['id_ciudad', 'nombre', 'departamento', 'id_region', 'ubigeo', 'tiene_aeropuerto',
                 'acceso_terrestre', 'latitud', 'longitud'],
      [[c[0], c[1], c[2], c[3], c[4], 't' if c[5] else 'f', 't' if c[6] else 'f', c[7], c[8]] for c in CIUDADES])
write('hub', ['id_hub', 'codigo', 'nombre', 'tipo', 'id_ciudad', 'id_hub_padre', 'capacidad_hora', 'direccion', 'activo'],
      [[h['id'], h['codigo'], h['nombre'], h['tipo'], h['ciudad'], h['padre'] or '', h['cap'], direccion(), 't']
       for h in HUB.values()])
write('tipo_servicio', ['id_servicio', 'codigo', 'nombre', 'modalidad', 'sla_horas', 'peso_max_kg'],
      [s[:6] for s in SERVICIOS])
write('tarifa', ['id_tarifa', 'id_servicio', 'id_region_origen', 'id_region_destino', 'precio_base',
                 'precio_kg_adicional', 'vigente_desde', 'vigente_hasta'], TARIFAS)
write('ruta', ['id_ruta', 'id_hub_origen', 'id_hub_destino', 'modalidad', 'distancia_km', 'tiempo_estimado_horas', 'activa'],
      [[r['id'], r['o'], r['d'], r['mod'], r['km'], r['h'], 't'] for r in RUTAS])
write('vehiculo', ['id_vehiculo', 'placa', 'tipo', 'capacidad_kg', 'id_hub_base', 'activo'], VEHICULOS)
write('empleado', ['id_empleado', 'dni', 'nombres', 'apellidos', 'cargo', 'id_hub', 'fecha_ingreso', 'activo'], EMPLEADOS)
write('cliente', ['id_cliente', 'tipo_cliente', 'tipo_documento', 'nro_documento', 'nombre_razon_social', 'email',
                  'telefono', 'direccion', 'id_ciudad', 'fecha_registro'], CLIENTES)
write('destinatario', ['id_destinatario', 'nombre', 'tipo_documento', 'nro_documento', 'telefono'], DESTINATARIOS)
write('envio', ['id_envio', 'nro_tracking', 'id_cliente', 'id_destinatario', 'id_servicio', 'id_hub_origen',
                'id_hub_destino', 'direccion_entrega', 'fecha_registro', 'fecha_compromiso', 'estado_actual',
                'peso_total_kg', 'valor_declarado', 'monto_total', 'fecha_entrega'], ENVIOS)
write('paquete', ['id_paquete', 'id_envio', 'nro_bulto', 'peso_kg', 'largo_cm', 'ancho_cm', 'alto_cm',
                  'descripcion', 'fragil'], PAQUETES)
write('comprobante', ['id_comprobante', 'id_envio', 'tipo', 'serie', 'numero', 'fecha_emision', 'subtotal', 'igv',
                      'total', 'metodo_pago'], COMPROBANTES)
write('despacho', ['id_despacho', 'codigo_manifiesto', 'id_ruta', 'id_vehiculo', 'nro_vuelo', 'fecha_salida_prog',
                   'fecha_salida_real', 'fecha_llegada_real', 'estado'], DESP_ROWS)
write('despacho_envio', ['id_despacho', 'id_envio', 'fecha_carga'], DE_ROWS)
write('evento_tracking', ['id_evento', 'id_envio', 'tipo_evento', 'id_hub', 'id_empleado', 'id_despacho',
                          'fecha_hora', 'observacion'], EVENTOS)
write('intento_entrega', ['id_intento', 'id_envio', 'nro_intento', 'fecha_hora', 'id_courier', 'resultado',
                          'receptor_nombre', 'receptor_documento'], INTENTOS)
write('incidencia', ['id_incidencia', 'id_envio', 'tipo', 'id_hub', 'fecha_reporte', 'descripcion', 'estado',
                     'fecha_cierre'], INCIDENCIAS)
print(f'Datos generados en {OUT} (semilla {SEED}, corte {CORTE})')
