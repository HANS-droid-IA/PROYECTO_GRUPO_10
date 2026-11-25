#!/usr/bin/env python3
"""
Genera el informe (apartados 1 a 9 del Formato Único de Informe) en Word.
Formato: A4, Arial 11, interlineado 1,5, texto justificado, márgenes de 2,5 cm,
títulos con estilos jerárquicos, numeración de páginas, índice de contenidos,
de figuras y de tablas (campos de Word que se actualizan con F9 / automáticamente).
Las figuras son diagramas propios y capturas reales de DBeaver, psql y SQL*Plus.
"""
import os
from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor
from PIL import Image

BASE = os.path.dirname(os.path.abspath(__file__))
DOC_DIR = os.path.normpath(os.path.join(BASE, '..'))
DIAG = os.path.join(DOC_DIR, 'diagramas')
CAP = os.path.join(DOC_DIR, 'capturas')
DBV = os.path.join(CAP, 'dbeaver')
TMP = os.path.join(BASE, '_img')
os.makedirs(TMP, exist_ok=True)
SALIDA = os.path.join(BASE, 'Informe_BDII_Trazabilidad_Olva_Courier.docx')

doc = Document()

# ------------------------------------------------------------------ estilos
st = doc.styles['Normal']
st.font.name = 'Arial'
st.font.size = Pt(11)
st.element.rPr.rFonts.set(qn('w:eastAsia'), 'Arial')
for attr in ('w:asciiTheme', 'w:hAnsiTheme', 'w:eastAsiaTheme', 'w:cstheme'):
    st.element.rPr.rFonts.attrib.pop(qn(attr), None)
pf = st.paragraph_format
pf.line_spacing = 1.5
pf.space_after = Pt(4)
pf.space_before = Pt(0)
pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY

for nivel, tam in ((1, 13), (2, 11.5)):
    h = doc.styles[f'Heading {nivel}']
    h.font.name = 'Arial'
    h.font.size = Pt(tam)
    h.font.bold = True
    h.font.color.rgb = RGBColor(0x1F, 0x3A, 0x5F)
    h.element.rPr.rFonts.set(qn('w:eastAsia'), 'Arial')
    rf = h.element.rPr.rFonts
    rf.set(qn('w:ascii'), 'Arial'); rf.set(qn('w:hAnsi'), 'Arial')
    for attr in ('w:asciiTheme', 'w:hAnsiTheme', 'w:eastAsiaTheme', 'w:cstheme'):
        rf.attrib.pop(qn(attr), None)
    h.paragraph_format.space_before = Pt(8 if nivel == 1 else 4)
    h.paragraph_format.space_after = Pt(4)
    h.paragraph_format.line_spacing = 1.15
    h.paragraph_format.keep_with_next = True

cap = doc.styles['Caption']
cap.font.name = 'Arial'
cap.font.size = Pt(9.5)
cap.font.bold = True
cap.font.italic = False
cap.font.color.rgb = RGBColor(0x1F, 0x3A, 0x5F)
cap.paragraph_format.space_before = Pt(4)
cap.paragraph_format.space_after = Pt(2)
cap.paragraph_format.line_spacing = 1.0
cap.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER

sec = doc.sections[0]
sec.page_height, sec.page_width = Cm(29.7), Cm(21.0)
for m in ('left_margin', 'right_margin', 'top_margin', 'bottom_margin'):
    setattr(sec, m, Cm(2.5))
ANCHO = 16.0  # cm útiles


# ------------------------------------------------------------------ utilidades
def campo(parrafo, instr, texto=''):
    """Inserta un campo de Word (TOC, SEQ, PAGE...)."""
    r = parrafo.add_run()
    b = OxmlElement('w:fldChar'); b.set(qn('w:fldCharType'), 'begin'); r._r.append(b)
    r2 = parrafo.add_run()
    i = OxmlElement('w:instrText'); i.set(qn('xml:space'), 'preserve'); i.text = f' {instr} '; r2._r.append(i)
    r3 = parrafo.add_run()
    s = OxmlElement('w:fldChar'); s.set(qn('w:fldCharType'), 'separate'); r3._r.append(s)
    r4 = parrafo.add_run(texto)
    r5 = parrafo.add_run()
    e = OxmlElement('w:fldChar'); e.set(qn('w:fldCharType'), 'end'); r5._r.append(e)
    return r4


def runs(p, texto, size=None):
    """Texto con **negrita** y `código` en línea."""
    import re
    for parte in re.split(r'(\*\*.+?\*\*|`.+?`)', texto):
        if not parte:
            continue
        if parte.startswith('**'):
            r = p.add_run(parte[2:-2]); r.bold = True
        elif parte.startswith('`'):
            r = p.add_run(parte[1:-1]); r.font.name = 'Consolas'; r.font.size = Pt(9.5)
        else:
            r = p.add_run(parte)
        if size and not parte.startswith('`'):
            r.font.size = Pt(size)
    return p


def P(texto, size=None, after=None, align=None):
    p = doc.add_paragraph()
    runs(p, texto, size)
    if after is not None:
        p.paragraph_format.space_after = Pt(after)
    if align:
        p.alignment = align
    return p


def H1(t):
    return doc.add_heading(t, level=1)


def H2(t):
    return doc.add_heading(t, level=2)


def bullets(items, size=None):
    for it in items:
        p = doc.add_paragraph(style='List Bullet')
        p.paragraph_format.line_spacing = 1.3
        p.paragraph_format.space_after = Pt(1)
        runs(p, it, size)


def sombrear(celda, color):
    tcPr = celda._tc.get_or_add_tcPr()
    sh = OxmlElement('w:shd'); sh.set(qn('w:val'), 'clear'); sh.set(qn('w:color'), 'auto'); sh.set(qn('w:fill'), color)
    tcPr.append(sh)


def titulo_tabla(texto):
    p = doc.add_paragraph(style='Caption')
    p.add_run('Tabla ')
    campo(p, 'SEQ Tabla \\* ARABIC', '1')
    p.add_run(f'. {texto}')
    p.paragraph_format.keep_with_next = True


def fuente(texto='Elaboración propia.'):
    p = doc.add_paragraph()
    r = p.add_run('Fuente: ' + texto); r.italic = True; r.font.size = Pt(8.5)
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    p.paragraph_format.space_after = Pt(6); p.paragraph_format.line_spacing = 1.0


def tabla(titulo, filas, anchos, fuente_txt='Elaboración propia.', size=8.5):
    titulo_tabla(titulo)
    t = doc.add_table(rows=len(filas), cols=len(filas[0]))
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    for i, fila in enumerate(filas):
        for j, val in enumerate(fila):
            c = t.cell(i, j)
            c.width = Cm(anchos[j])
            c.paragraphs[0].text = ''
            p = c.paragraphs[0]
            p.paragraph_format.line_spacing = 1.0
            p.paragraph_format.space_after = Pt(0)
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            runs(p, str(val), size)
            if i == 0:
                for r in p.runs:
                    r.bold = True
                sombrear(c, 'DCE6F2')
    # repetir encabezado
    trPr = t.rows[0]._tr.get_or_add_trPr()
    th = OxmlElement('w:tblHeader'); th.set(qn('w:val'), 'true'); trPr.append(th)
    fuente(fuente_txt)
    return t


def codigo(texto, size=8):
    t = doc.add_table(rows=1, cols=1)
    t.style = 'Table Grid'
    c = t.cell(0, 0)
    c.width = Cm(ANCHO)
    sombrear(c, 'F4F6F8')
    c.paragraphs[0].text = ''
    lineas = texto.strip('\n').split('\n')
    for k, l in enumerate(lineas):
        p = c.paragraphs[0] if k == 0 else c.add_paragraph()
        p.paragraph_format.line_spacing = 1.0
        p.paragraph_format.space_after = Pt(0)
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        r = p.add_run(l if l else ' ')
        r.font.name = 'Consolas'; r.font.size = Pt(size)
        r._element.rPr.rFonts.set(qn('w:eastAsia'), 'Consolas')
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def preparar(ruta, max_px=2400):
    """Copia la imagen reducida (para no inflar el .docx)."""
    im = Image.open(ruta)
    if im.mode in ('RGBA', 'P'):
        fondo = Image.new('RGB', im.size, 'white')
        fondo.paste(im, mask=im.split()[-1] if im.mode == 'RGBA' else None)
        im = fondo
    if max(im.size) > max_px:
        im.thumbnail((max_px, max_px), Image.LANCZOS)
    destino = os.path.join(TMP, os.path.splitext(os.path.basename(ruta))[0] + '.png')
    im.save(destino, optimize=True)
    return destino, im.size


def figura(ruta, titulo, fuente_txt, interpretacion=None, ancho=11.0, alto_max=None, recorte=None):
    if recorte:
        im = Image.open(ruta).crop(recorte)
        ruta2 = os.path.join(TMP, 'rec_' + os.path.basename(ruta)); im.save(ruta2); ruta = ruta2
    archivo, (w, h) = preparar(ruta)
    if alto_max and ancho * h / w > alto_max:
        ancho = alto_max * w / h
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.keep_with_next = True; p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing = 1.0
    p.add_run().add_picture(archivo, width=Cm(ancho))
    c = doc.add_paragraph(style='Caption')
    c.add_run('Figura ')
    campo(c, 'SEQ Figura \\* ARABIC', '1')
    c.add_run(f'. {titulo}')
    c.paragraph_format.keep_with_next = True
    fuente(fuente_txt)
    if interpretacion:
        p = doc.add_paragraph()
        r = p.add_run('Interpretación técnica: '); r.bold = True; r.font.size = Pt(9.5)
        r2 = p.add_run(interpretacion); r2.font.size = Pt(9.5)
        p.paragraph_format.line_spacing = 1.15
        p.paragraph_format.space_after = Pt(6)


def salto():
    doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)


# ================================================================== PORTADA
for _ in range(2):
    doc.add_paragraph()
def centro(texto, tam, negrita=False, after=6, color=None):
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(texto); r.font.size = Pt(tam); r.bold = negrita
    if color:
        r.font.color.rgb = color
    p.paragraph_format.space_after = Pt(after)
    return p
centro('[NOMBRE DE LA UNIVERSIDAD]', 14, True)
centro('Facultad de Ingeniería', 12)
centro('Curso: Base de Datos II (100000SI46)', 12, after=30)
centro('PROYECTO FINAL', 13, True, after=6, color=RGBColor(0x1F, 0x3A, 0x5F))
centro('Solución de datos relacional y distribuida para la trazabilidad de paquetería y courier aéreo/terrestre', 15, True, after=6, color=RGBColor(0x1F, 0x3A, 0x5F))
centro('Caso de estudio: Olva Courier (Perú)', 12, after=4)
centro('Informe de avance: apartados 1 al 9', 11, after=36)
p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = p.add_run('Integrantes:'); r.bold = True
for i in range(1, 6):
    centro(f'[Apellidos y nombres del integrante {i}]', 11, after=0)
doc.add_paragraph()
centro('Docente: [Nombre del docente]', 11, after=2)
centro('Sección: [Código de sección]', 11, after=2)
centro('Lima, octubre de 2026', 11, after=2)

# ================================================================== ÍNDICES (nueva sección con numeración)
nueva = doc.add_section(WD_SECTION.NEW_PAGE)
pie = nueva.footer; pie.is_linked_to_previous = False
pp = pie.paragraphs[0]; pp.alignment = WD_ALIGN_PARAGRAPH.CENTER
campo(pp, 'PAGE', '2')
doc.sections[0].footer.is_linked_to_previous = False

def cab_indice(t):
    p = P(f'**{t}**', after=1); p.paragraph_format.line_spacing = 1.0; p.paragraph_format.space_before = Pt(4)
cab_indice('ÍNDICE DE CONTENIDOS')
p = doc.add_paragraph(); campo(p, 'TOC \\o "1-2" \\h \\z \\u', 'Actualice el índice con clic derecho > Actualizar campo.')
cab_indice('ÍNDICE DE FIGURAS')
p = doc.add_paragraph(); campo(p, 'TOC \\h \\z \\c "Figura"', 'Actualice el índice de figuras.')
cab_indice('ÍNDICE DE TABLAS')
p = doc.add_paragraph(); campo(p, 'TOC \\h \\z \\c "Tabla"', 'Actualice el índice de tablas.')

# ================================================================== 1
H1('1. RESUMEN EJECUTIVO').paragraph_format.page_break_before = True
P('El proyecto aborda la falta de trazabilidad unificada en una empresa de courier nacional que moviliza envíos por vía aérea y terrestre entre agencias, hubs regionales y un hub central. Se tomó como referencia la operación pública de **Olva Courier**: red de agencias, servicios aéreos y terrestres y seguimiento por número de tracking. Los registros utilizados son **sintéticos**; los generó el grupo con un simulador propio y no corresponden a información interna de la empresa.')
P('La solución implementada comprende tres componentes. Primero, una base de datos relacional en **PostgreSQL 16** (20 tablas, 30 claves foráneas, 4 funciones, 4 procedimientos, 3 triggers, seguridad por roles y por fila, y respaldo verificado). Segundo, una implementación parcial en **Oracle AI Database 26ai Free** (8 tablas de negocio con paquete PL/SQL y perfiles de seguridad). Tercero, una **base de datos distribuida de tres nodos PostgreSQL** (Lima, Norte y Sur) con fragmentación horizontal, vertical y derivada, consultas distribuidas, protocolo 2PC y pruebas de concurrencia. MongoDB, Cassandra y Hadoop forman parte del alcance académico del curso, pero no se incluyen en este avance.')
P('Sobre 29 966 envíos y 315 101 eventos de escaneo, el cumplimiento global del plazo es de **91,4 %**. El análisis identificó al **Hub Central Lima** como principal cuello de botella. A las 20:00 recibe 54,8 envíos/h frente a una capacidad de 50 envíos/h. Cuando un envío aéreo permanece más de 12 h en ese hub, su cumplimiento cae de 88,7 % a 81,0 %. Este resultado permite recomendar el ajuste del horario de corte del despacho troncal y el refuerzo del turno nocturno.')

# ================================================================== 2
H1('2. INTRODUCCIÓN')
H2('2.1 Contexto del proyecto')
P('Olva Courier es una empresa peruana de mensajería y paquetería con cobertura nacional que atiende a personas y empresas, en especial al comercio electrónico. Los envíos se admiten en agencias, se consolidan en hubs y viajan entre ciudades por carretera o en vuelos comerciales hasta la agencia de destino, donde se reparten. Para el proyecto se modeló una red de 5 macro-regiones, 17 ciudades con código UBIGEO real, 1 hub central (Callao), 8 hubs regionales, 29 agencias, 98 rutas y 4 servicios: Express Aéreo (48 h), Sobre Aéreo (48 h), Estándar Terrestre (72 h) y Económico Terrestre (120 h).')
H2('2.2 Problemática y elemento diferenciador')
P('La información operativa se encuentra dispersa entre agencias, hubs y medios de transporte. Esto impide reconstruir con rapidez el recorrido de un envío, detectar los hubs y las franjas horarias donde se acumulan paquetes y anticipar el incumplimiento del plazo comprometido. El **elemento diferenciador es la trazabilidad por eventos**: cada escaneo (`ADMISION`, `SALIDA_HUB`, `LLEGADA_HUB`, `CLASIFICACION`, `EN_REPARTO`, `INTENTO_FALLIDO`, `ENTREGA`, `DEVOLUCION`) registra el hub, la fecha y hora, el responsable y el manifiesto de transporte. En promedio se generan 10,5 eventos por envío, y su ubicación geográfica justifica la distribución de los datos por sede.')
H2('2.3 Justificación técnica y de negocio')
P('Desde el negocio, la solución permite medir el cumplimiento del servicio, dimensionar horarios y personal en los hubs críticos y emitir alertas de envíos en riesgo. Desde lo técnico, PostgreSQL aporta integridad referencial, transacciones ACID, programación almacenada, seguridad por fila y la extensión `postgres_fdw` para integrar nodos remotos. Oracle permite contrastar arquitectura, sintaxis y programación con un motor comercial. La distribución responde a que los escaneos ocurren físicamente en cada sede: almacenarlos cerca de su origen reduce la dependencia del nodo central y reparte la carga de escritura.')
H2('2.4 Alcance')
P('Se implementó el ciclo de vida completo del envío: registro y tarificación, consolidación en despachos, escaneos, reparto con un máximo de tres intentos, devolución, incidencias y comprobante. Se incluyen 13 consultas de negocio, 4 funciones, 4 procedimientos, 3 triggers, 2 vistas y 1 vista materializada; 5 roles, 7 usuarios y 4 políticas de seguridad por fila; respaldo lógico y físico; 8 tablas en Oracle; y 3 nodos distribuidos con 2PC y pruebas de concurrencia. El periodo simulado va del 1 de abril al 7 de octubre de 2026.')
H2('2.5 Limitaciones y restricciones')
P('Los datos son sintéticos y los cuellos de botella se programaron en el simulador para validar que la solución los detecta. Los tres nodos distribuidos son instancias PostgreSQL independientes en un mismo equipo (16 GB de RAM), por lo que no se mide la latencia real de una red amplia. Oracle Free limita los recursos (2 hilos de CPU, 2 GB de RAM y 12 GB de datos), por lo que se implementó un subconjunto del modelo. Las tablas de comprobante, despacho, destinatario e incidencia permanecen centralizadas en esta fase.')

# ================================================================== 3
H1('3. OBJETIVOS')
H2('3.1 Objetivo general')
P('Diseñar e implementar una solución de bases de datos relacionales y distribuidas para la trazabilidad de envíos aéreos y terrestres de un courier nacional, que permita identificar cuellos de botella en la red logística y evaluar el cumplimiento de los plazos de entrega.')
H2('3.2 Objetivos específicos')
tabla('Objetivos específicos y evidencia', [
    ['N.°', 'Objetivo específico', 'Evidencia de cumplimiento'],
    ['OE1', 'Diseñar un modelo relacional normalizado (3FN) del ciclo de vida del envío.', 'DER (Figura 1), modelo lógico y normalización (punto 5).'],
    ['OE2', 'Implementar el modelo en PostgreSQL con restricciones, programación almacenada, seguridad y respaldo.', '20 tablas, 13 consultas, 4 funciones, 4 procedimientos, RLS y restauración verificada (puntos 6 y 7).'],
    ['OE3', 'Implementar un subconjunto del modelo en Oracle y compararlo con PostgreSQL.', '8 tablas, paquete PL/SQL, PROFILE y Data Pump (punto 8).'],
    ['OE4', 'Diseñar e implementar una base de datos distribuida con fragmentación horizontal y vertical, 2PC y control de concurrencia.', 'Tres nodos, reglas de corrección al 100 %, planes de ejecución distribuidos y pruebas 2PC (punto 9).'],
], [1.2, 8.3, 6.5])

# ================================================================== 4
H1('4. DESCRIPCIÓN DEL PROBLEMA Y REQUERIMIENTOS')
H2('4.1 Descripción del escenario operativo')
P('El cliente entrega uno o más bultos en una agencia; se calculan la tarifa (servicio, regiones y peso) y la fecha de compromiso (20:00 del día que alcanza el SLA; si cae domingo, pasa al lunes) y se emite boleta o factura con IGV de 18 %. Los envíos se consolidan en **despachos** (manifiestos) con horarios fijos: furgoneta a las 13:00 y 19:30, camión troncal a las 23:30, vuelos a las 08:00 y 17:30, y distribución a las 06:00 y 14:30. En cada hub el paquete se clasifica y espera el siguiente despacho. En la agencia de destino sale a reparto con un máximo de tres intentos. Daños, pérdidas, direcciones incorrectas y retrasos generan incidencias.')
H2('4.2 Actores e interfaces involucradas')
tabla('Actores, operaciones e interfaces', [
    ['Actor', 'Responsabilidad', 'Operaciones permitidas', 'Interfaz / rol de BD'],
    ['Atención en agencia', 'Admisión, tarificación e incidencias', 'Registrar envíos (procedimiento), consultar tracking', 'DBeaver / `rol_atencion_cliente`'],
    ['Operario de hub y courier', 'Escaneos, despachos y entregas', 'Ejecutar procedimientos; ver solo envíos de su nodo', 'psql / `rol_operador_hub`'],
    ['Facturación', 'Comprobantes e ingresos', 'Lectura de comprobantes y envíos', '`rol_facturacion`'],
    ['Analista / gerencia', 'Indicadores y cuellos de botella', 'Lectura de vistas analíticas', 'DBeaver / `rol_analista`'],
    ['Administrador de BD', 'Administración, respaldo, Oracle y nodos', 'Todas', 'DBeaver, psql, SQL*Plus / `rol_admin_olva`'],
], [3.2, 3.8, 5.0, 4.0])
H2('4.3 Requerimientos funcionales de datos')
tabla('Requerimientos funcionales', [
    ['Código', 'Requerimiento', 'Implementación'],
    ['RF01', 'Registrar envíos con tarifa, paquetes y comprobante en una transacción', '`sp_registrar_envio`, `fn_calcular_tarifa`'],
    ['RF02', 'Registrar escaneos validando la secuencia de estados', '`sp_registrar_escaneo` + trigger de estado'],
    ['RF03', 'Consolidar envíos en despachos con vehículo o vuelo', '`despacho`, `despacho_envio`, `trg_validar_despacho`'],
    ['RF04', 'Registrar intentos de entrega, devoluciones e incidencias', '`sp_registrar_intento_entrega`, `sp_cerrar_despacho`'],
    ['RF05', 'Consultar la línea de tiempo de un envío y su estado de plazo', 'C01, `vw_tracking_publico`, `fn_estado_sla`'],
    ['RF06', 'Medir la permanencia en hubs por franja horaria', '`fn_cuellos_botella`, `mv_permanencia_hub`'],
    ['RF07', 'Auditar los cambios de estado', '`auditoria.log_estado_envio` (trigger)'],
], [1.6, 8.0, 6.4])
H2('4.4 Requerimientos no funcionales')
bullets([
    '**Integridad:** PK, 30 FK, UNIQUE y CHECK de negocio; reglas entre tablas en triggers.',
    '**Seguridad:** mínimo privilegio, permisos por columna, seguridad por fila y escritura solo mediante procedimientos.',
    '**Rendimiento:** índices por patrón de acceso e índice parcial de envíos vivos. Medido: las 13 consultas se ejecutan en 1,5 s y el tracking de un envío en 12 ms.',
    '**Disponibilidad y escalabilidad:** fragmentos por sede y réplica de catálogos en cada nodo.',
    '**Recuperación:** respaldo lógico y físico con restauración verificada tabla por tabla.',
])
H2('4.5 Preguntas de negocio a responder')
bullets([
    'PN1. ¿Qué porcentaje de envíos se entrega a tiempo por servicio y mes? (C02)',
    'PN2. ¿En qué hubs y franjas horarias se acumulan los paquetes? (C03, C13)',
    'PN3. ¿Cuánto afecta al plazo la permanencia prolongada en el Hub Central? (C04)',
    'PN4. ¿Qué corredores y clientes concentran los ingresos y con qué puntualidad? (C06, C07)',
    'PN5. ¿Qué envíos están vencidos, en riesgo o estancados? (C09, C12)',
])

# ================================================================== 5
H1('5. DISEÑO DE LA BASE DE DATOS RELACIONAL')
H2('5.1 Identificación de entidades, atributos y relaciones')
P('El modelo tiene 18 entidades de negocio organizadas en dos grupos. Los **catálogos** son `region`, `ciudad`, `hub` (jerarquía recursiva agencia → hub regional → hub central), `tipo_servicio`, `tarifa`, `ruta`, `vehiculo`, `empleado` y `cliente`. La **operación** comprende `destinatario`, `envio`, `paquete` (entidad débil), `comprobante` (1:1 con envío), `despacho`, `despacho_envio` (resuelve la relación N:M entre despacho y envío), `evento_tracking`, `intento_entrega` e `incidencia`. Las principales reglas de negocio son: un despacho usa vehículo o vuelo, nunca ambos; un envío entregado tiene fecha de entrega; y el total del comprobante es igual al subtotal más el IGV.')
H2('5.2 Modelo conceptual: Diagrama Entidad-Relación (DER)')
figura(os.path.join(DIAG, '01_modelo_ER.png'),
       'Diagrama Entidad-Relación de olva_courier',
       'elaboración propia; generado desde el catálogo de PostgreSQL (fuente editable 01_modelo_ER.mmd).',
       'Las 18 entidades muestran sus atributos con tipo, PK, FK y UK, y las 30 relaciones con su cardinalidad. Al derivarse del catálogo real, el diagrama coincide con las tablas implementadas.',
       ancho=12.5)
H2('5.3 Modelo lógico relacional')
P('Cada entidad del DER corresponde a una tabla. Ejemplos (PK en negrita, FK en cursiva en el DER): envio(**id_envio**, nro_tracking, id_cliente, id_destinatario, id_servicio, id_hub_origen, id_hub_destino, fechas, estado_actual, monto_total); despacho_envio(**id_despacho, id_envio**, fecha_carga); evento_tracking(**id_evento**, id_envio, tipo_evento, id_hub, id_empleado, id_despacho, fecha_hora).')
H2('5.4 Normalización')
P('**1FN:** los bultos de un envío se registran como filas de `paquete` (sin columnas repetidas) y cada escaneo es una fila de `evento_tracking`. **2FN:** en `despacho_envio`, `fecha_carga` depende de la clave compuesta completa; los datos del viaje dependen solo de `id_despacho` y residen en `despacho`. **3FN:** se eliminaron las dependencias transitivas `envio → hub → ciudad → región` y `despacho → ruta → modalidad`: esos atributos se obtienen mediante JOIN. Se mantienen tres **desnormalizaciones controladas**:')
bullets([
    '`estado_actual` y `fecha_entrega`, actualizados por un trigger en cada escaneo, porque se consultan en cada tracking.',
    '`monto_total`, que es un hecho histórico: no debe recalcularse si cambia la tarifa.',
])

# ================================================================== 6
H1('6. IMPLEMENTACIÓN EN POSTGRESQL')
H2('6.1 Estructura de funcionamiento y creación de la base de datos')
P('Se utilizó **PostgreSQL 16.15**, administrado con **DBeaver 26.2** y **psql**, en el puerto 5440. La base `olva_courier` (UTF8, zona horaria America/Lima, 115 MB) se crea y puebla con un script que ejecuta, en orden, los archivos de DDL, funciones, procedimientos, carga, triggers, vistas y seguridad. El proceso completo tarda unos 23 s (`CREATE DATABASE` con codificación UTF8 y `CREATE SCHEMA` para cada schema).')
H2('6.2 Arquitectura de schemas')
P('`maestro` contiene los catálogos (9 tablas), `operacion` las transacciones (9 tablas), `auditoria` la bitácora generada por triggers y `seguridad` el soporte de las políticas RLS.')
figura(os.path.join(DIAG, '02_arquitectura_postgresql.png'),
       'Arquitectura de PostgreSQL',
       'elaboración propia (fuente editable 02_arquitectura_postgresql.mmd).', None, ancho=9.5, alto_max=7.5)
H2('6.3 Creación de tablas, PK, FK y restricciones')
P('Las PK usan `GENERATED BY DEFAULT AS IDENTITY`; hay 30 FK, índices sobre los patrones de acceso y CHECK de dominio (expresiones regulares para tracking, DNI, RUC, placa y serie) y de negocio. Fragmento representativo:')
codigo("""CREATE TABLE operacion.despacho (
    id_despacho        BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    codigo_manifiesto  VARCHAR(20) NOT NULL UNIQUE,
    id_ruta            INTEGER     NOT NULL REFERENCES maestro.ruta (id_ruta),
    id_vehiculo        INTEGER     REFERENCES maestro.vehiculo (id_vehiculo),
    nro_vuelo          VARCHAR(8)  CHECK (nro_vuelo ~ '^[A-Z0-9]{2}[0-9]{3,4}$'),
    fecha_salida_prog  TIMESTAMPTZ NOT NULL,  fecha_salida_real TIMESTAMPTZ,  fecha_llegada_real TIMESTAMPTZ,
    estado VARCHAR(10) NOT NULL CHECK (estado IN ('PROGRAMADO','EN_RUTA','ARRIBADO','CANCELADO')),
    -- vehículo propio (terrestre) o vuelo comercial (aéreo), nunca ambos
    CONSTRAINT ck_despacho_transporte CHECK ((id_vehiculo IS NULL) <> (nro_vuelo IS NULL)));
CREATE INDEX ix_envio_estado_activo ON operacion.envio (estado_actual, fecha_compromiso)
    WHERE estado_actual NOT IN ('ENTREGADO','DEVUELTO');   -- índice parcial""")
H2('6.4 Estrategia de inserción y poblamiento de datos')
P('Los datos provienen de un simulador en Python, con semilla fija, que recorre cada envío por la red. El simulador calcula la ruta más corta con el algoritmo de Dijkstra, consolida los envíos en despachos con capacidad y horarios, y aplica tiempos de clasificación con congestión. Se generaron 18 archivos CSV que se cargan con `COPY` dentro de una transacción; luego se sincronizan las secuencias IDENTITY y se ejecuta `ANALYZE`. Volumen validado: 29 966 envíos, 315 101 eventos, 40 714 paquetes, 22 729 despachos, 33 557 intentos, 3 000 clientes y 1 904 incidencias.')
H2('6.5 Consultas SQL representativas')
P('Se implementaron 13 consultas (script `08_consultas.sql`). En conjunto se ejecutan en 1,5 s. Las Figuras 3 y 4 muestran dos de ellas ejecutadas en DBeaver. El código completo y las salidas de las demás forman parte de los anexos digitales del repositorio.')
tabla('Consultas de negocio y resultados', [
    ['N.°', 'Problema de negocio', 'Técnica SQL', 'Resultado'],
    ['C01', 'Recorrido de un envío y demoras', 'JOIN, LAG()', '11 escaneos; 13 h de espera en HC-LIM'],
    ['C02', 'Cumplimiento de SLA por servicio y mes', 'FILTER, DATE_TRUNC', 'Económico ~99 %; aéreos 85–91 %'],
    ['C03', 'Hubs y franjas con más permanencia', 'Función de tabla, LEAD(), percentil', 'HC-LIM 18–24 h: 14,5 h promedio'],
    ['C04', 'Efecto de más de 12 h en HC sobre el SLA', 'Vista materializada, DISTINCT ON', 'Aéreo 88,7 % → 81,0 %'],
    ['C05', 'Rutas con salidas o viajes tardíos', 'Auto-JOIN, HAVING', 'Troncales a Cusco y Juliaca +1,2 a +1,5 h'],
    ['C06', 'Ingresos por corredor origen-destino', 'ROLLUP, GROUPING()', 'Lima origina el 69 % de S/ 812 292'],
    ['C07', 'Top 10 clientes empresariales', 'CTE, RANK(), SUM() OVER', 'Textil Los Andes: 80,7 % puntual'],
    ['C08', 'Entrega al primer intento', 'Agregación condicional, STRING_AGG', 'Tacna 83,5 %; motivo principal AUSENTE'],
    ['C09', 'Envíos vencidos o en riesgo', 'Función + índice parcial', 'Lista operativa de alertas'],
    ['C10', 'Incidencias por hub', 'LEFT JOIN, FILTER', 'HC-LIM: 41 % de los daños'],
    ['C11', 'Productividad de couriers', 'DENSE_RANK() OVER PARTITION', '3,3–3,6 entregas/día'],
    ['C12', 'Envíos sin escaneo más de 48 h', 'LATERAL, EXISTS', 'Todos con incidencia de pérdida'],
    ['C13', 'Ocupación horaria del Hub Central', 'generate_series', '20:00 → 110 % de capacidad'],
], [1.2, 5.6, 4.5, 4.7], size=8)
figura(os.path.join(DBV, 'DB01_pg_c01_tracking.png'),
       'Consulta C01 en DBeaver: línea de tiempo de un envío',
       'elaboración propia a partir de la ejecución en DBeaver sobre PostgreSQL.',
       'La función LAG() calcula el tiempo entre escaneos. El envío pasó 13 h 11 min en HC-LIM entre su clasificación y su salida, lo que responde a RF05 y evidencia el cuello de botella.')
figura(os.path.join(DBV, 'DB03_pg_c04_impacto_sla.png'),
       'Consulta C04 en DBeaver: impacto del Hub Central en el SLA',
       'elaboración propia a partir de la ejecución en DBeaver sobre PostgreSQL.',
       'Con más de 12 h en el Hub Central, el cumplimiento aéreo baja de 88,7 % a 81,0 % y el terrestre de 96,1 % a 91,3 % (PN3).')

# ================================================================== 7
H1('7. PROGRAMACIÓN Y ADMINISTRACIÓN DE LA BASE DE DATOS')
H2('7.1 Funciones almacenadas (PL/pgSQL)')
P('Se implementaron cuatro funciones: `fn_calcular_tarifa` (tarifa vigente: base + kilos adicionales), `fn_estado_sla` (a tiempo, con retraso, vencido, en riesgo o en plazo), `fn_permanencia_hub` y la función de tabla `fn_cuellos_botella`. Esta última usa `LEAD()` para resolver en una sola pasada la permanencia por hub y franja horaria. Por ejemplo, la tarifa Lima → Oriente varía entre S/ 19,00 y S/ 103,50 según el servicio y el peso, y un sobre de 3 kg se rechaza con un error controlado.')
H2('7.2 Procedimientos almacenados (PL/pgSQL)')
P('Hay cuatro procedimientos. `sp_registrar_envio` registra destinatario, envío, paquetes en JSONB, comprobante correlativo y evento ADMISION en una sola transacción, y rechaza servicios terrestres hacia ciudades sin carretera. `sp_registrar_escaneo` implementa la máquina de estados y bloquea el envío con `FOR UPDATE`. `sp_registrar_intento_entrega` controla el máximo de tres intentos y la devolución. `sp_cerrar_despacho` registra en bloque la llegada de un manifiesto. Extracto de la validación de estados:')
codigo("""v_permitidos := CASE v_envio.estado_actual
    WHEN 'ADMITIDO' THEN ARRAY['SALIDA_HUB']   WHEN 'EN_TRANSITO' THEN ARRAY['LLEGADA_HUB']
    WHEN 'EN_HUB' THEN ARRAY['CLASIFICACION','SALIDA_HUB','EN_REPARTO']  ... END;
IF NOT (p_tipo_evento = ANY (v_permitidos)) THEN
    RAISE EXCEPTION 'Transición inválida: envío % en estado % no admite evento %',
          p_nro_tracking, v_envio.estado_actual, p_tipo_evento;
END IF;
-- prueba (09_pruebas_procedimientos.sql):  CALL sp_registrar_escaneo(:'trk', 'ENTREGA', :ag_sur, :emp_courier);""")
figura(os.path.join(CAP, 'PG_P2.png'),
       'Ciclo de un envío con procedimientos y triggers (psql)',
       'elaboración propia a partir de la ejecución en psql.',
       'La transición inválida se rechaza con un error controlado. Los procedimientos generan 10 eventos hasta ENTREGADO_A_TIEMPO y el trigger de auditoría registra cada cambio de estado. La prueba se ejecuta dentro de BEGIN…ROLLBACK.',
       ancho=12.0, alto_max=6.5)
H2('7.3 Seguridad y gestión de accesos')
P('Los privilegios se otorgan a cinco roles de grupo (`rol_admin_olva`, `rol_operador_hub`, `rol_atencion_cliente`, `rol_facturacion`, `rol_analista`) y siete usuarios los heredan. Se revocaron los privilegios de `PUBLIC` sobre la base, el schema `public` y las funciones. Las contraseñas no se documentan; en los scripts se representan como `<CONTRASEÑA_CONFIGURADA>`.')
codigo("""CREATE ROLE rol_operador_hub NOLOGIN;
CREATE ROLE u_op_sur LOGIN PASSWORD '<CONTRASEÑA_CONFIGURADA>' CONNECTION LIMIT 10;
GRANT rol_operador_hub TO u_op_sur;
GRANT SELECT (id_envio, nro_tracking, estado_actual, peso_total_kg) ON operacion.envio TO rol_operador_hub;
GRANT EXECUTE ON PROCEDURE operacion.sp_registrar_escaneo TO rol_operador_hub;
REVOKE ALL ON DATABASE olva_courier FROM PUBLIC;""")
H2('7.4 Políticas de seguridad y control de accesos')
P('Se aplicaron cuatro medidas. Primero, permisos por columna: el operador no lee `monto_total`. Segundo, escritura solo mediante procedimientos `SECURITY DEFINER` con `search_path` fijo. Tercero, vistas sin datos personales para el analista. Cuarto, **Row Level Security** sobre `envio` y `evento_tracking`. Con RLS, la misma consulta devuelve 27 023 envíos a u_op_lima, 11 347 a u_op_norte y 8 658 a u_op_sur, frente a 29 966 del propietario. Las pruebas registraron siete accesos denegados esperados.')
H2('7.5 Backup y restauración')
P('Se realizó un respaldo lógico con `pg_dump -Fc` (7,7 MB), un respaldo de roles con `pg_dumpall --globals-only` y un respaldo físico en caliente con `pg_basebackup` (28 MB). Luego se simuló el borrado de las 1 904 incidencias y se recuperaron con una restauración selectiva (`pg_restore --data-only --table=incidencia`). Finalmente, se restauró la base completa en `olva_courier_restore` con `pg_restore --jobs=4`.')
figura(os.path.join(CAP, 'PG_B1_p2.png'),
       'Verificación de la restauración completa (psql)',
       'elaboración propia a partir de la ejecución de pg_restore y psql.',
       'Las 18 tablas coinciden fila por fila. Se restauraron 13 funciones y procedimientos, 3 triggers y 4 políticas RLS.',
       ancho=11.0, alto_max=5.0)

# ================================================================== 8
H1('8. IMPLEMENTACIÓN PARCIAL Y COMPARACIÓN CON ORACLE')
H2('8.1 Cuadro comparativo de arquitecturas')
tabla('Comparación de arquitecturas', [
    ['Aspecto', 'PostgreSQL 16', 'Oracle 26ai', 'SQL Server'],
    ['Procesos', 'Un proceso por conexión + procesos de fondo', 'Instancia: SGA + DBWn, LGWR, CKPT, SMON, PMON', 'Un proceso multihilo (SQLOS)'],
    ['Memoria', 'shared_buffers; work_mem por operación', 'SGA (buffer cache, shared pool); PGA por sesión', 'Buffer pool, plan cache'],
    ['Almacenamiento', 'Archivo por tabla; páginas de 8 KB; TOAST', 'Tablespaces, datafiles, segmentos y bloques', 'Archivos .mdf/.ldf; páginas de 8 KB'],
    ['Transacciones / MVCC', 'Versiones en la tabla; VACUUM; WAL', 'UNDO para lectura consistente; redo log', 'Bloqueos; versionado opcional en tempdb'],
    ['Ejecución', 'Optimizador por costos, sin hints nativos', 'Optimizador por costos con hints y planes adaptativos', 'Optimizador por costos, Query Store'],
    ['Seguridad', 'Roles, RLS, GRANT por columna', 'Usuarios = esquemas, PROFILE, VPD', 'Logins, usuarios, RLS'],
    ['Administración', 'pg_dump, pg_basebackup', 'RMAN, Data Pump, Flashback', 'BACKUP DATABASE'],
], [2.7, 4.3, 4.6, 4.4], fuente_txt='elaboración propia con base en la documentación oficial de cada motor.', size=8)
H2('8.2 Implementación parcial en Oracle')
P('En la base conectable `FREEPDB1` (esquema `OLVA`) se implementaron 8 tablas de negocio (`region`, `ciudad`, `hub`, `tipo_servicio`, `tarifa`, `cliente`, `envio`, `evento_tracking`) y la tabla `log_error`. Las tablas tienen PK, FK (incluida la recursiva de `hub`), UNIQUE y CHECK con `REGEXP_LIKE`. Los tipos se adaptaron a `NUMBER`, `VARCHAR2`, `TIMESTAMP WITH TIME ZONE` y `BOOLEAN`. Se cargaron 1 000 envíos, 483 clientes y 10 627 eventos, idénticos a los de PostgreSQL. La seguridad se implementó con el PROFILE `prf_olva_usuarios`: con 3 intentos fallidos la cuenta queda LOCKED(TIMED). Data Pump (`expdp`/`impdp`) recuperó una tabla eliminada con sus 10 627 filas.')
figura(os.path.join(DIAG, '03_arquitectura_oracle.png'),
       'Arquitectura de la implementación en Oracle',
       'elaboración propia (fuente editable 03_arquitectura_oracle.mmd).',
       'No se configuraron enlaces de base de datos (database links): Oracle opera como servidor independiente para la comparación.',
       ancho=11.0)
figura(os.path.join(DBV, 'DB06_ora_connect_by.png'),
       'Consulta CONNECT BY en DBeaver sobre Oracle',
       'elaboración propia a partir de la ejecución en DBeaver sobre Oracle FREEPDB1.',
       'LEVEL y SYS_CONNECT_BY_PATH reconstruyen la red hub central → hub regional → agencia, una sintaxis propia de Oracle que en PostgreSQL equivale a WITH RECURSIVE. El navegador muestra las tablas del esquema OLVA.')
H2('8.3 Comparación de sintaxis y programación: PL/pgSQL vs. PL/SQL')
tabla('Diferencias PL/pgSQL y PL/SQL', [
    ['Concepto', 'PostgreSQL / PL/pgSQL', 'Oracle / PL/SQL'],
    ['Organización', 'Funciones y procedimientos en schemas', 'PACKAGE con especificación y cuerpo (`pkg_tracking`)'],
    ['Errores', '`RAISE EXCEPTION ... USING ERRCODE`', '`RAISE_APPLICATION_ERROR(-20010, ...)`'],
    ['Transacción autónoma', 'No nativa', '`PRAGMA AUTONOMOUS_TRANSACTION` (log persiste tras ROLLBACK)'],
    ['Trigger', 'Función trigger + `CREATE TRIGGER ... EXECUTE FUNCTION`', 'Cuerpo dentro del trigger con `:NEW`'],
    ['Invocación', '`CALL sp(...)`', '`EXEC sp(...)` o bloque `BEGIN ... END;`'],
    ['Cadena vacía', "`''` distinto de NULL", "`''` IS NULL"],
    ['Agregación de texto / Top-N', '`STRING_AGG`, `LIMIT`', '`LISTAGG ... WITHIN GROUP`, `FETCH FIRST`, `ROWNUM`'],
    ['Upsert / jerarquía', '`ON CONFLICT`, `WITH RECURSIVE`', '`MERGE`, `CONNECT BY`'],
], [3.3, 6.0, 6.7], size=8)
figura(os.path.join(DBV, 'DB07_ora_sla_paquete.png'),
       'SLA y paquete pkg_tracking en DBeaver sobre Oracle',
       'elaboración propia a partir de la ejecución en DBeaver sobre Oracle FREEPDB1.',
       'Los porcentajes (Económico 99,5 %, Estándar 94,1 %, Express 86,8 % y Sobre 88,1 %) son coherentes con PostgreSQL sobre la muestra. La función del paquete calcula la tarifa respetando el peso máximo del servicio.')
H2('8.4 Conclusiones del análisis comparativo relacional')
P('El modelo resultó portable: las tablas, las restricciones y los indicadores coinciden entre ambos motores. Las diferencias se concentran en tipos, sintaxis y herramientas. Oracle ofrece de forma nativa paquetes, transacciones autónomas, perfiles de contraseña y RMAN. PostgreSQL ofrece JSONB, RLS, índices parciales y `postgres_fdw`, base de la distribución, por lo que se eligió como motor principal. La adaptación exigió reescribir `~` como `REGEXP_LIKE`, `IDENTITY` como `ON NULL AS IDENTITY` y recompilar el paquete tras un DROP, que invalida los objetos dependientes.')

# ================================================================== 9
H1('9. DISEÑO DE BASE DE DATOS DISTRIBUIDA')
H2('9.1 Justificación técnica de la distribución')
P('Cada escaneo ocurre en una sede física y cada envío se factura en su agencia. Distribuir por sede permite escribir localmente (el 38,5 % de los eventos deja de escribirse en Lima), operar cada sede con sus fragmentos y una réplica de catálogos, y concentrar los datos tributarios en un único nodo. A cambio, las consultas globales tienen costo de red y las transacciones entre nodos requieren coordinación.')
H2('9.2 Arquitectura propuesta')
P('Se implementaron y verificaron tres nodos PostgreSQL 16 independientes: **LIMA** (puerto 5440, `olva_lima`, regiones Lima y Centro, además coordinador), **NORTE** (5433, `olva_norte`, Norte y Oriente) y **SUR** (5434, `olva_sur`). El coordinador define con `postgres_fdw` los servidores `srv_norte` y `srv_sur`, y un schema `global` con tablas particionadas por `LIST (nodo)`. En cada una, la partición LIMA es local y las particiones NORTE y SUR son tablas foráneas remotas.')
figura(os.path.join(DIAG, '04_arquitectura_distribuida.png'),
       'Arquitectura de la base de datos distribuida',
       'elaboración propia (fuente editable 04_arquitectura_distribuida.svg).', None, ancho=12.0)
codigo("""CREATE SERVER srv_norte FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'pg_norte', port '5432', dbname 'olva_norte', async_capable 'true', batch_size '1000');
CREATE USER MAPPING FOR CURRENT_USER SERVER srv_norte
    OPTIONS (user '<USUARIO_CONFIGURADO>', password '<CONTRASEÑA_CONFIGURADA>');
CREATE TABLE global.envio (LIKE operacion.envio) PARTITION BY LIST (nodo);
ALTER TABLE global.envio ATTACH PARTITION operacion.envio FOR VALUES IN ('LIMA');
CREATE FOREIGN TABLE global.envio_norte PARTITION OF global.envio FOR VALUES IN ('NORTE')
    SERVER srv_norte OPTIONS (schema_name 'operacion', table_name 'envio');""")
H2('9.3 Fragmentación horizontal')
P('Se usan los predicados nodo = LIMA, nodo = NORTE y nodo = SUR, que son excluyentes y completos. **HF1:** `ENVIO_i = σ nodo(hub_origen)=i (ENVIO)`. **HF2 (derivada):** `PAQUETE_i = PAQUETE ⋉ ENVIO_i`, lo que mantiene local la FK. **HF3:** `EVENTO_i = σ nodo(hub)=i (EVENTO_TRACKING)`. Cada fragmento valida su predicado con un CHECK, y el nodo SUR rechaza un envío originado en Lima. La reconstrucción del conjunto global es la unión de los fragmentos (`SELECT … FROM global.envio`).')
H2('9.4 Fragmentación vertical')
P('La relación cliente se divide según el uso de sus atributos. **VF1** `cliente_fiscal` (id_cliente, tipo_cliente, tipo_documento, nro_documento, fecha_registro) reside solo en Lima, para facturación. **VF2** `cliente_contacto` (id_cliente, nombre, email, teléfono, dirección, ciudad) se fragmenta además por ciudad del cliente, lo que constituye una fragmentación mixta. La reconstrucción `CLIENTE = VF1 ⋈ VF2` por `id_cliente` está implementada como la vista `global.cliente`.')
H2('9.5 Esquema de localización y asignación de datos')
tabla('Esquema de asignación de fragmentos', [
    ['Fragmento', 'Atributos / predicado', 'Nodo', 'Réplica', 'Acceso'],
    ['HF1 envio_i', 'Todos; nodo del hub de origen', 'LIMA / NORTE / SUR', 'No', 'Partición local o foreign table'],
    ['HF2 paquete_i', 'Todos; derivado de envio', 'Mismo nodo del envío', 'No', 'Partición; JOIN local'],
    ['HF3 evento_tracking_i', 'Todos; nodo del hub del escaneo', 'LIMA / NORTE / SUR', 'No', 'Partición local o foreign table'],
    ['VF1 cliente_fiscal', 'Identificación tributaria', 'LIMA', 'No', 'Tabla local'],
    ['VF2 cliente_contacto_i', 'Contacto; ciudad del cliente', 'LIMA / NORTE / SUR', 'No', 'Partición; vista global.cliente'],
    ['Catálogos', 'region, ciudad, hub, servicio, tarifa, ruta', 'Los tres nodos', 'Total', 'Tablas locales'],
], [3.3, 4.6, 3.0, 1.5, 3.6], size=8)
P('Se verificaron las reglas de corrección contra la base original: **completitud** (29 966 envíos y 315 101 eventos en origen y en fragmentos), **disyunción** (0 claves repetidas) y **reconstrucción** (0 filas distintas, comprobado con EXCEPT en ambos sentidos).')
figura(os.path.join(DBV, 'DB08_dist_catalogo_fragmentos.png'),
       'Catálogo de fragmentos y filas por nodo en DBeaver',
       'elaboración propia a partir de la ejecución en DBeaver sobre olva_lima.',
       'Cada relación global tiene una partición local LIMA y particiones remotas en srv_norte y srv_sur. Los conteos de las particiones remotas se obtienen en vivo desde cada nodo.')
H2('9.6 Procesamiento y optimización de consultas distribuidas')
P('La consulta global se **descompone** en álgebra relacional, se **localiza** podando los fragmentos cuyo predicado contradice el filtro y se **optimiza** enviando a cada nodo selección, JOIN y agregación (*Remote SQL*) con lecturas asíncronas. Q1 (`nodo = SUR`) solo accede a `envio_sur`; Q2 ejecuta el `GROUP BY` en cada nodo; Q3 resuelve envío ⋈ paquete dentro de cada nodo gracias a la fragmentación derivada. Una consulta global tardó 64 ms frente a 26 ms la localizada en Lima. Consultado directamente, el nodo NORTE almacena 3 167 envíos, 4 235 paquetes y 68 442 eventos de su fragmento. Oracle no participa de la distribución.')
figura(os.path.join(DBV, 'DB09_dist_explain_join_pushdown.png'),
       'Plan EXPLAIN de la consulta Q3 en DBeaver',
       'elaboración propia a partir de EXPLAIN VERBOSE ejecutado en DBeaver.',
       'Cada rama Async Foreign Scan ejecuta el JOIN y la agregación en NORTE y SUR (Remote SQL); solo viaja el resumen.', ancho=9.5)
H2('9.7 Manejo de transacciones distribuidas (Protocolo 2PC)')
P('Como `postgres_fdw` confirma los nodos uno a uno, el 2PC se **implementó y probó** explícitamente con `PREPARE TRANSACTION`, `COMMIT PREPARED` y `ROLLBACK PREPARED`. Escenario: el arribo de un manifiesto al Hub Arequipa escribe eventos en SUR y actualiza envíos de LIMA y NORTE. En la fase 1 cada participante prepara (voto SÍ) o falla (voto NO); en la fase 2 el coordinador registra la decisión en `global.log_2pc` y confirma o revierte. Casos probados: (1) tres votos SÍ y confirmación; (2) LIMA vota NO y se revierte SUR; (3) caída del coordinador: la transacción queda en duda reteniendo bloqueos y se resuelve con *presumed abort*.')
figura(os.path.join(CAP, 'DD_2PC1.png'),
       'Protocolo 2PC, caso 1: confirmación global (psql)',
       'elaboración propia a partir de la ejecución en psql desde el coordinador Lima.',
       'pg_prepared_xacts muestra una transacción preparada por nodo. Los cambios no son visibles hasta COMMIT PREPARED; después, ambos envíos quedan EN_HUB y los eventos residen en SUR.',
       ancho=10.0, alto_max=4.6)
H2('9.8 Control de concurrencia y bloqueo distribuido')
P('Pruebas reales con sesiones simultáneas: (a) **bloqueo de fila:** una sesión esperó 3,0 s el `SELECT … FOR UPDATE` de otra (ShareLock no otorgado en `pg_locks`); (b) **actualización perdida:** en READ COMMITTED el valor final fue 150 y en REPEATABLE READ se abortó la segunda transacción (valor 200); (c) **interbloqueo local:** detectado y resuelto con una víctima; (d) **interbloqueo distribuido** NORTE ↔ SUR: ningún detector local vio el ciclo y se resolvió por `statement_timeout`. Se recomienda un orden global de acceso a los nodos.')

doc.save(SALIDA)
print('Generado:', SALIDA)
