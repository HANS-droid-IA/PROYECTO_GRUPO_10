"""
Agrega los puntos 10 (MongoDB) y 11 (Apache Cassandra) al informe existente SIN modificar
el resto: inserta el contenido antes de "Conclusiones:" copiando el formato de los párrafos
del propio documento (títulos, cuerpo, viñetas, código, figuras, fuente e interpretación) y
añade sus entradas al índice. Las capturas son reales (07_Documentacion/capturas/nosql/final).
Uso: python agregar_puntos_10_11.py <entrada.docx> <salida.docx>
"""
import copy
import re
import sys
import pathlib

import docx
from docx.oxml.ns import qn
from docx.shared import Cm
from PIL import Image

ENTRADA, SALIDA = sys.argv[1], sys.argv[2]
IMG = pathlib.Path(__file__).resolve().parents[1] / 'capturas' / 'nosql' / 'final'

doc = docx.Document(ENTRADA)
P = doc.paragraphs


def buscar(inicio, estilo=None):
    for p in P:
        if p.text.strip().startswith(inicio) and (estilo is None or p.style.name == estilo):
            return p
    raise LookupError(inicio)


T_H1 = buscar('9. DISEÑO DE BASE DE DATOS DISTRIBUIDA', 'Normal')._p
T_H2 = buscar('9.7 Manejo de transacciones', 'Normal')._p
T_BODY = buscar('Como postgres_fdw confirma')._p
T_INTERP = buscar('Interpretación técnica: Cada rama Async')._p
T_CAPTION = buscar('Figura 13.')._p
T_FUENTE = buscar('Fuente: elaboración propia a partir de la ejecución en psql desde el coordinador')._p
T_IMAGEN = T_CAPTION.getprevious()
T_BULLET = buscar('El proyecto logró diseñar e implementar')._p
T_TOC1 = buscar('9. DISEÑO DE BASE DE DATOS DISTRIBUIDA', 'toc 1')._p
T_TOC2 = buscar('9.7 Manejo de transacciones', 'toc 2')._p
T_CODIGO = next(t._tbl for t in doc.tables if t.cell(0, 0).text.startswith('CREATE SERVER'))
ANCLA = buscar('Conclusiones:')._p
assert T_IMAGEN.find('.//' + qn('w:drawing')) is not None

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
nuevos = []                      # elementos a insertar antes de "Conclusiones:"
toc = []                         # (nivel, texto, marcador)
estado = {'fig': 13, 'bm_id': 9000, 'toc': 991000, 'docpr': 900}


def limpiar(p, conservar_ppr=True):
    """Copia un párrafo plantilla y quita todo excepto sus propiedades de párrafo."""
    q = copy.deepcopy(p)
    for hijo in list(q):
        if not (conservar_ppr and hijo.tag == qn('w:pPr')):
            q.remove(hijo)
    return q


def rpr(base=None, negrita=False, codigo=False, tam=None):
    r = docx.oxml.parse_xml(f'<w:rPr xmlns:w="{W}"/>') if base is None else copy.deepcopy(base)
    for t in ('w:b', 'w:bCs'):
        for e in r.findall(qn(t)):
            r.remove(e)
    orden = []
    if codigo:
        orden.append(f'<w:rFonts xmlns:w="{W}" w:ascii="Consolas" w:hAnsi="Consolas"/>')
    if negrita:
        orden += [f'<w:b xmlns:w="{W}"/>', f'<w:bCs xmlns:w="{W}"/>']
    for x in reversed(orden):
        r.insert(0, docx.oxml.parse_xml(x))
    if tam or codigo:
        for e in r.findall(qn('w:sz')) + r.findall(qn('w:szCs')):
            r.remove(e)
        v = tam or 19
        r.append(docx.oxml.parse_xml(f'<w:sz xmlns:w="{W}" w:val="{v}"/>'))
        r.append(docx.oxml.parse_xml(f'<w:szCs xmlns:w="{W}" w:val="{v}"/>'))
    if r.find(qn('w:lang')) is None:
        r.append(docx.oxml.parse_xml(f'<w:lang xmlns:w="{W}" w:val="es-PE"/>'))
    return r


def run(texto, **kw):
    r = docx.oxml.parse_xml(f'<w:r xmlns:w="{W}"/>')
    r.append(rpr(**kw))
    t = docx.oxml.parse_xml(f'<w:t xmlns:w="{W}" xml:space="preserve"/>')
    t.text = texto
    r.append(t)
    return r


def runs_marcados(p, texto, tam=None, negrita_base=False):
    """**negrita** y `codigo` en línea."""
    for parte in re.split(r'(\*\*[^*]+\*\*|`[^`]+`)', texto):
        if not parte:
            continue
        if parte.startswith('**'):
            p.append(run(parte[2:-2], negrita=True, tam=tam))
        elif parte.startswith('`'):
            p.append(run(parte[1:-1], codigo=True, tam=tam))
        else:
            p.append(run(parte, negrita=negrita_base, tam=tam))


def marcador(p, texto_run):
    estado['bm_id'] += 1
    estado['toc'] += 1
    nombre = f'_Toc{estado["toc"]}'
    p.append(docx.oxml.parse_xml(f'<w:bookmarkStart xmlns:w="{W}" w:id="{estado["bm_id"]}" w:name="{nombre}"/>'))
    p.append(texto_run)
    p.append(docx.oxml.parse_xml(f'<w:bookmarkEnd xmlns:w="{W}" w:id="{estado["bm_id"]}"/>'))
    return nombre


def H1(texto):
    p = limpiar(T_H1)
    base = T_H1.find(qn('w:r')).find(qn('w:rPr'))
    r = docx.oxml.parse_xml(f'<w:r xmlns:w="{W}"/>'); r.append(copy.deepcopy(base))
    t = docx.oxml.parse_xml(f'<w:t xmlns:w="{W}"/>'); t.text = texto; r.append(t)
    toc.append((1, texto, marcador(p, r)))
    nuevos.append(p)


def H2(texto):
    p = limpiar(T_H2)
    base = T_H2.find(qn('w:r')).find(qn('w:rPr'))
    r = docx.oxml.parse_xml(f'<w:r xmlns:w="{W}"/>'); r.append(copy.deepcopy(base))
    t = docx.oxml.parse_xml(f'<w:t xmlns:w="{W}"/>'); t.text = texto; r.append(t)
    toc.append((2, texto, marcador(p, r)))
    nuevos.append(p)


def TXT(texto):
    p = limpiar(T_BODY)
    runs_marcados(p, texto)
    nuevos.append(p)


def VIN(*items):
    for texto in items:
        p = limpiar(T_BULLET)
        runs_marcados(p, texto)
        nuevos.append(p)


def INTERP(texto):
    p = limpiar(T_INTERP)
    p.append(run('Interpretación técnica: ', negrita=True, tam=19))
    runs_marcados(p, texto, tam=19)
    nuevos.append(p)


def CODIGO(texto):
    tbl = copy.deepcopy(T_CODIGO)
    tc = tbl.find('.//' + qn('w:tc'))
    pars = tc.findall(qn('w:p'))
    plantilla = pars[0]
    base_rpr = plantilla.find('.//' + qn('w:r')).find(qn('w:rPr'))
    for x in pars:
        tc.remove(x)
    for linea in texto.strip('\n').split('\n'):
        p = limpiar(plantilla)
        r = docx.oxml.parse_xml(f'<w:r xmlns:w="{W}"/>'); r.append(copy.deepcopy(base_rpr))
        t = docx.oxml.parse_xml(f'<w:t xmlns:w="{W}" xml:space="preserve"/>'); t.text = linea
        r.append(t); p.append(r); tc.append(p)
    nuevos.append(tbl)
    # párrafo vacío tras la tabla (como en el resto del documento)
    vacio = limpiar(T_BODY)
    nuevos.append(vacio)


def FIGURA(archivo, titulo, fuente, interp=None, ancho_cm=15.5, alto_max_cm=19.0):
    ruta = IMG / f'{archivo}.png'
    w, h = Image.open(ruta).size
    ancho = ancho_cm
    if ancho * h / w > alto_max_cm:
        ancho = alto_max_cm * w / h
    cx = int(Cm(ancho)); cy = int(cx * h / w)
    rid, _ = doc.part.get_or_add_image(str(ruta))
    p = copy.deepcopy(T_IMAGEN)
    for e in p.iter(qn('w:lastRenderedPageBreak')):
        e.getparent().remove(e)
    ns_wp = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
    ns_a = 'http://schemas.openxmlformats.org/drawingml/2006/main'
    ns_r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    ns_pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture'
    p.find(f'.//{{{ns_wp}}}extent').set('cx', str(cx)); p.find(f'.//{{{ns_wp}}}extent').set('cy', str(cy))
    p.find(f'.//{{{ns_a}}}xfrm/{{{ns_a}}}ext').set('cx', str(cx)); p.find(f'.//{{{ns_a}}}xfrm/{{{ns_a}}}ext').set('cy', str(cy))
    p.find(f'.//{{{ns_a}}}blip').set(f'{{{ns_r}}}embed', rid)
    estado['docpr'] += 1
    dp = p.find(f'.//{{{ns_wp}}}docPr'); dp.set('id', str(estado['docpr'])); dp.set('name', f'Picture {estado["docpr"]}')
    p.find(f'.//{{{ns_pic}}}cNvPr').set('name', f'{archivo}.png')
    nuevos.append(p)
    # pie de figura con el campo SEQ del documento
    estado['fig'] += 1
    c = copy.deepcopy(T_CAPTION)
    for b in c.findall(qn('w:bookmarkStart')) + c.findall(qn('w:bookmarkEnd')):
        c.remove(b)
    fin = False
    for r in list(c.findall(qn('w:r'))):
        if fin:
            c.remove(r); continue
        t = r.find(qn('w:t'))
        if t is not None and t.text.strip() == '13':
            t.text = str(estado['fig'])
        fc = r.find(qn('w:fldChar'))
        if fc is not None and fc.get(qn('w:fldCharType')) == 'end':
            fin = True
    for e in c.findall(qn('w:proofErr')):
        c.remove(e)
    r = docx.oxml.parse_xml(f'<w:r xmlns:w="{W}"><w:rPr><w:color w:val="auto"/><w:lang w:val="es-PE"/></w:rPr></w:r>')
    t = docx.oxml.parse_xml(f'<w:t xmlns:w="{W}" xml:space="preserve"/>'); t.text = f'. {titulo}'; r.append(t); c.append(r)
    nuevos.append(c)
    f = limpiar(T_FUENTE)
    f.append(run(f'Fuente: {fuente}', tam=17))
    nuevos.append(f)
    if interp:
        INTERP(interp)


exec(pathlib.Path(__file__).with_name('contenido_10_11.py').read_text(encoding='utf-8'))

# --- insertar el contenido antes de "Conclusiones:" ------------------------
for e in nuevos:
    ANCLA.addprevious(e)

# --- índice: nuevas entradas después de la del punto 9.7 --------------------
ultimo = T_TOC2
for nivel, texto, nombre in toc:
    e = copy.deepcopy(T_TOC1 if nivel == 1 else T_TOC2)
    h = e.find(qn('w:hyperlink'))
    h.set(qn('w:anchor'), nombre)
    ts = h.findall('.//' + qn('w:t'))
    ts[0].text = texto
    for t in ts[1:]:
        t.text = '0'                                 # número de página: lo calcula Word al actualizar
    for it in h.iter(qn('w:instrText')):
        it.text = re.sub(r'_Toc\d+', nombre, it.text)
    ultimo.addnext(e)
    ultimo = e

# --- el índice creció 13 líneas: las líneas en blanco de relleno que había entre el índice y
#     "1. RESUMEN EJECUTIVO" se reemplazan por un salto de página antes del resumen, para que
#     todo el documento conserve exactamente su paginación original.
resumen = next(p for p in doc.paragraphs if p.text.strip() == '1. RESUMEN EJECUTIVO')._p
previo = resumen.getprevious()
while previo is not None and previo.tag == qn('w:p') and not ''.join(previo.itertext()).strip() \
        and previo.find('.//' + qn('w:fldChar')) is None:
    anterior = previo.getprevious()
    previo.getparent().remove(previo)
    previo = anterior
# la línea vacía con estilo de índice que cerraba la lista de entradas se elimina (invisible):
# así el cierre del campo del índice sigue cabiendo en la página 2
siguiente = ultimo.getnext()
if siguiente is not None and not ''.join(siguiente.itertext()).strip() \
        and siguiente.find('.//' + qn('w:fldChar')) is None:
    siguiente.getparent().remove(siguiente)
ppr = resumen.find(qn('w:pPr'))
if ppr is None:
    ppr = docx.oxml.parse_xml(f'<w:pPr xmlns:w="{W}"/>'); resumen.insert(0, ppr)
ppr.insert(0, docx.oxml.parse_xml(f'<w:pageBreakBefore xmlns:w="{W}"/>'))

doc.save(SALIDA)
print(f'Insertados {len(nuevos)} bloques, {len(toc)} títulos, figuras 14 a {estado["fig"]} -> {SALIDA}')
