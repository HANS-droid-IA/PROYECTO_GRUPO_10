"""
Arma las transcripciones de consola (MongoDB y sedes) a partir de las salidas REALES
guardadas en las carpetas evidencias/ de 04_NoSQL_MongoDB y 05_NoSQL_Cassandra.
Solo selecciona fragmentos y antepone el comando ejecutado; no modifica resultados.
"""
import pathlib
import re

RAIZ = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent / 'salidas'
OUT.mkdir(exist_ok=True)
MG = RAIZ / '04_NoSQL_MongoDB' / 'evidencias'
MGD = RAIZ / '04_NoSQL_MongoDB' / 'distribuido' / 'evidencias'
CSD = RAIZ / '05_NoSQL_Cassandra' / 'distribuido' / 'evidencias'


def leer(p):
    return p.read_text(encoding='utf-8').splitlines()


def secciones(lineas, *claves):
    """Devuelve las secciones '=== CLAVE...' pedidas, completas, en el orden dado."""
    idx = [i for i, l in enumerate(lineas) if l.startswith('=== ')] + [len(lineas)]
    out = []
    for c in claves:
        for a, b in zip(idx, idx[1:]):
            if lineas[a].startswith('=== ' + c):
                bloque = lineas[a:b]
                while bloque and not bloque[-1].strip():
                    bloque.pop()
                out += bloque + ['']
    return out


def guardar(nombre, lineas):
    texto = re.sub(r'\n{3,}', '\n\n', '\n'.join(lineas)).strip('\n') + '\n'
    (OUT / f'{nombre}.txt').write_text(texto, encoding='utf-8')
    print(nombre, len(texto.splitlines()), 'líneas')


P_MG = 'olva_admin@mongosh:olva_tracking> '
P_MS = 'olva_admin@mongos:olva_sedes> '

guardar('mg_carga', [P_MG + "mongoimport --db olva_tracking --collection <hubs|clientes|envios> --file datos/<coleccion>.json --numInsertionWorkers 4"]
        + leer(MG / '02_carga_masiva.txt')[:3] + ['', P_MG + "load('02_indices.js')"] + leer(MG / '02_carga_masiva.txt')[4:])

crud = leer(MG / '03_operaciones_crud.txt')
guardar('mg_crud_1', [P_MG + "load('03_operaciones_crud.js')   // lecturas"] + secciones(crud, 'R1.', 'R4.'))
guardar('mg_crud_1b', [P_MG + "load('03_operaciones_crud.js')   // lecturas con índice"] + secciones(crud, 'R2.', 'R3.'))
guardar('mg_crud_2', [P_MG + "load('03_operaciones_crud.js')   // escrituras"] + secciones(crud, 'C2.', 'U1.', 'U3.', 'B1.', 'B2.'))

agg = leer(MG / '04_agregaciones.txt')
a2 = secciones(agg, 'A2.')
a2 = a2[:3] + [l for l in a2[3:] if re.match(r'^(0|1|6|7|13|14|19|20|21|22) ', l)] + ['(24 documentos; se muestran 10 franjas horarias)', '']
guardar('mg_agregaciones', [P_MG + "load('04_agregaciones.js')"] + secciones(agg, 'A1.') + a2 + secciones(agg, 'A4.'))

seg = leer(MG / '05_seguridad.txt')
usuarios = seg[seg.index('=== Usuarios ==='):]
corte = next(i for i, l in enumerate(usuarios) if l.startswith('=== Conectado como u_operador_mongo'))
fin = [l for l in usuarios[corte:] if l.strip()]
guardar('mg_seguridad', [P_MG + "load('05_seguridad.js')"] + usuarios[:corte])
guardar('mg_seguridad_b', ['u_operador_mongo / u_analista_mongo -> mongosh --file 06_pruebas_seguridad.js'] + fin[:-1]
        + ['', '-- conexión de u_analista_mongo con una contraseña incorrecta:', fin[-1]])

ds = leer(MGD / '02_consultas_sedes.txt')
guardar('mg_sedes', [P_MS + "load('02_consultas_sedes.js')"] + secciones(ds, 'D1.', 'Q1.', 'Q2.', 'Q4.'))
guardar('mg_transacciones', [P_MS + "load('02_consultas_sedes.js')   // transacciones distribuidas"]
        + secciones(ds, 'T1.', 'T2.', 'T3.'))
caida = [l for l in leer(MGD / '03_sede_caida.txt') if not l.startswith('>>')]
guardar('mg_caida', ['-- se detiene el servidor de la sede Arequipa (shard sede_arequipa)'] + caida)
dep = leer(MGD / '01_despliegue.txt')
i = next(k for k, l in enumerate(dep) if l.startswith('=== 1.'))
j = next(k for k, l in enumerate(dep) if l.startswith('Clave de fragmentación'))
guardar('mg_zonas', [P_MS + "load('01_configurar_sedes.js')"] + [l for l in dep[i:j + 1] if not l.startswith('{')])

c1 = leer(CSD / '01_despliegue.txt')
top = [l.replace('= olva_cassandra_arequipa (', '= nodo olva_cassandra_arequipa (').replace('= olva_cassandra (', '= nodo olva_cassandra (') for l in c1[:2]]
st = c1[c1.index('>> 1. Topología del clúster: dos centros de datos') + 1: c1.index('>> 2. Replicación en ambas sedes y keyspace local de Arequipa')]
rep_ini = next(k for k, l in enumerate(c1) if l.lstrip().startswith('keyspace_name'))
rep = c1[rep_ini: rep_ini + 6]
c2 = leer(CSD / '02_pruebas_sedes.txt')
ge = c2[c2.index('>> 4. ¿Qué nodos guardan un envío? (una réplica por sede)') + 1:
        c2.index('>> 5. La misma consulta respondida por cada sede (cada una tiene la copia completa)')]
guardar('cq_sedes', top + ['', 'olva_admin@sede-lima$ nodetool status'] + st
        + ['', 'olva_admin@cqlsh (Lima)> SELECT keyspace_name, replication FROM system_schema.keyspaces WHERE ...;'] + rep
        + ['', 'olva_admin@sede-lima$ nodetool getendpoints ...'] + ge)
c3 = [re.sub(r'^<stdin>:\d+:', '', l) for l in leer(CSD / '03_sede_caida.txt')
      if not l.startswith(('>>', 'Consistency level set', 'This node does not have', '--- hints'))]
guardar('cq_caida', ['-- se detiene el nodo de la sede Lima (dc_lima); las consultas se hacen en la sede Arequipa'] + c3)
