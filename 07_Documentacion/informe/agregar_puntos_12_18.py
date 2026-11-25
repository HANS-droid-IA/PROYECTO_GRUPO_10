"""
Agrega los puntos 12 a 18 (datos masivos, Hadoop, integración, resultados, conclusiones,
recomendaciones y referencias) al informe que ya contiene los puntos 10 y 11. Copia el formato de los
párrafos del propio documento; el bloque "Conclusiones:" original se reemplaza por el punto 16, que
conserva su contenido y lo vincula a los objetivos específicos. Las capturas son reales
(07_Documentacion/capturas/bigdata/final). El resto del documento no se modifica.
Uso: python agregar_puntos_12_18.py <entrada_con_10_11.docx> <salida.docx>
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
IMG = pathlib.Path(__file__).resolve().parents[1] / 'capturas' / 'bigdata' / 'final'
RAIZ = pathlib.Path(__file__).resolve().parents[2]

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
T_TOC_ULTIMO = buscar('11.5 Resultados y evidencias', 'toc 2')._p
T_CODIGO = next(t._tbl for t in doc.tables if t.cell(0, 0).text.startswith('CREATE SERVER'))
ANCLA = buscar('Conclusiones:')._p
assert T_IMAGEN.find('.//' + qn('w:drawing')) is not None

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
nuevos = []                      # elementos a insertar antes de "Conclusiones:"
toc = []                         # (nivel, texto, marcador)
estado = {'fig': 41, 'bm_id': 9500, 'toc': 992000, 'docpr': 2000}


ORDEN_PPR = ['pStyle', 'keepNext', 'keepLines', 'pageBreakBefore', 'framePr', 'widowControl', 'numPr',
             'suppressLineNumbers', 'pBdr', 'shd', 'tabs', 'suppressAutoHyphens', 'kinsoku', 'wordWrap',
             'overflowPunct', 'topLinePunct', 'autoSpaceDE', 'autoSpaceDN', 'bidi', 'adjustRightInd',
             'snapToGrid', 'spacing', 'ind', 'contextualSpacing', 'mirrorIndents', 'suppressOverlap', 'jc',
             'textDirection', 'textAlignment', 'textboxTightWrap', 'outlineLvl', 'divId', 'cnfStyle', 'rPr',
             'sectPr', 'pPrChange']


def poner_ppr(ppr, xml):
    """Inserta un hijo en w:pPr respetando el orden del esquema (reemplaza al existente del mismo tipo)."""
    e = docx.oxml.parse_xml(xml)
    nombre = e.tag.split('}')[1]
    for viejo in ppr.findall(qn('w:' + nombre)):
        ppr.remove(viejo)
    pos = ORDEN_PPR.index(nombre)
    for i, hijo in enumerate(ppr):
        n = hijo.tag.split('}')[1]
        if n in ORDEN_PPR and ORDEN_PPR.index(n) > pos:
            hijo.addprevious(e)
            return
    ppr.append(e)


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
    poner_ppr(p.find(qn('w:pPr')), f'<w:keepNext xmlns:w="{W}"/>')
    nuevos.append(p)


def H2(texto):
    p = limpiar(T_H2)
    base = T_H2.find(qn('w:r')).find(qn('w:rPr'))
    r = docx.oxml.parse_xml(f'<w:r xmlns:w="{W}"/>'); r.append(copy.deepcopy(base))
    t = docx.oxml.parse_xml(f'<w:t xmlns:w="{W}"/>'); t.text = texto; r.append(t)
    toc.append((2, texto, marcador(p, r)))
    poner_ppr(p.find(qn('w:pPr')), f'<w:keepNext xmlns:w="{W}"/>')
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
    # código legible: Consolas 8,5 pt, interlineado sencillo y fondo gris claro (sin cortar líneas de 95 car.)
    for r in tbl.iter(qn('w:rPr')):
        for e in r.findall(qn('w:rFonts')) + r.findall(qn('w:sz')) + r.findall(qn('w:szCs')):
            r.remove(e)
        r.insert(0, docx.oxml.parse_xml(f'<w:rFonts xmlns:w="{W}" w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>'))
        ancla = r.find(qn('w:lang'))
        for x in (f'<w:sz xmlns:w="{W}" w:val="17"/>', f'<w:szCs xmlns:w="{W}" w:val="17"/>'):
            e = docx.oxml.parse_xml(x)
            if ancla is not None:
                ancla.addprevious(e)
            else:
                r.append(e)
    for pp in tbl.iter(qn('w:pPr')):
        for e in pp.findall(qn('w:ind')):
            pp.remove(e)
        poner_ppr(pp, f'<w:spacing xmlns:w="{W}" w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>')
        poner_ppr(pp, f'<w:jc xmlns:w="{W}" w:val="left"/>')
    tcpr = tbl.find('.//' + qn('w:tcPr'))
    tcpr.append(docx.oxml.parse_xml(f'<w:shd xmlns:w="{W}" w:val="clear" w:color="auto" w:fill="F2F2F2"/>'))
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


def CODIGO_ARCHIVO(ruta):
    """Código fuente completo de un archivo del proyecto, tal cual está en el repositorio."""
    CODIGO((RAIZ / ruta).read_text(encoding='utf-8').rstrip())
    tbl = nuevos[-2]                                  # el bloque largo puede continuar en la página siguiente
    for e in list(tbl.iter(qn('w:cantSplit'))):
        e.getparent().remove(e)


def SUBT(texto):
    """Subtítulo en negrita dentro de una sección (p. ej. nombre de una clase)."""
    p = limpiar(T_BODY)
    poner_ppr(p.find(qn('w:pPr')), f'<w:keepNext xmlns:w="{W}"/>')
    runs_marcados(p, texto, negrita_base=True)
    nuevos.append(p)


def TABLA(cabecera, filas, anchos_cm, fuente=None, tam=17):
    """Tabla con bordes, cabecera sombreada y texto a 8,5 pt (marcado ** y ` permitido)."""
    total = sum(anchos_cm)
    tw = [int(Cm(a).emu / 635) for a in anchos_cm]           # EMU -> twips (dxa)
    filas_xml = []

    def celda(texto, w, cab):
        sh = '<w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/>' if cab else ''
        return (f'<w:tc><w:tcPr><w:tcW w:w="{w}" w:type="dxa"/>{sh}</w:tcPr>'
                f'<w:p><w:pPr><w:spacing w:before="20" w:after="20" w:line="240" w:lineRule="auto"/>'
                f'<w:jc w:val="left"/></w:pPr></w:p></w:tc>')
    xml = (f'<w:tbl xmlns:w="{W}"><w:tblPr><w:tblW w:w="{sum(tw)}" w:type="dxa"/><w:jc w:val="center"/>'
           '<w:tblBorders>' + ''.join(f'<w:{b} w:val="single" w:sz="4" w:space="0" w:color="7F7F7F"/>'
                                      for b in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV')) +
           '</w:tblBorders><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="70" w:type="dxa"/>'
           '<w:right w:w="70" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>' +
           ''.join(f'<w:gridCol w:w="{w}"/>' for w in tw) + '</w:tblGrid>')
    for k, fila in enumerate([cabecera] + filas):
        tr = '<w:tr>' + ('<w:trPr><w:tblHeader/></w:trPr>' if k == 0 else '<w:trPr><w:cantSplit/></w:trPr>')
        tr += ''.join(celda('', w, k == 0) for w in tw) + '</w:tr>'
        xml += tr
    xml += '</w:tbl>'
    tbl = docx.oxml.parse_xml(xml)
    for k, fila in enumerate([cabecera] + filas):
        tr = tbl.findall(qn('w:tr'))[k]
        for texto, tc in zip(fila, tr.findall(qn('w:tc'))):
            p = tc.find(qn('w:p'))
            runs_marcados(p, texto, tam=tam, negrita_base=(k == 0))
    nuevos.append(tbl)
    if fuente:
        f = limpiar(T_FUENTE)
        f.append(run(f'Fuente: {fuente}', tam=17))
        nuevos.append(f)
    else:
        nuevos.append(limpiar(T_BODY))


def REF(texto):
    """Referencia APA 7 con sangría francesa (marcado *cursiva* permitido)."""
    p = limpiar(T_BODY)
    ppr = p.find(qn('w:pPr'))
    poner_ppr(ppr, f'<w:ind xmlns:w="{W}" w:left="567" w:hanging="567"/>')
    poner_ppr(ppr, f'<w:jc xmlns:w="{W}" w:val="left"/>')
    for parte in re.split(r'(\*[^*]+\*)', texto):
        if not parte:
            continue
        if parte.startswith('*'):
            r = run(parte[1:-1])
            r.find(qn('w:rPr')).insert(0, docx.oxml.parse_xml(f'<w:i xmlns:w="{W}"/>'))
            p.append(r)
        else:
            p.append(run(parte))
    nuevos.append(p)


exec(pathlib.Path(__file__).with_name('contenido_12_18.py').read_text(encoding='utf-8'))

# --- insertar el contenido antes de "Conclusiones:" y retirar el bloque original de conclusiones
#     (su contenido se conserva, ampliado y vinculado a los objetivos, en el punto 16) -------------
for e in nuevos:
    ANCLA.addprevious(e)
viejo = [ANCLA]
sig = ANCLA.getnext()
while sig is not None and sig.tag == qn('w:p') and ''.join(sig.itertext()).strip():
    viejo.append(sig)
    sig = sig.getnext()
assert len(viejo) == 6, f'se esperaban 6 párrafos de conclusiones originales, hay {len(viejo)}'
for e in viejo:
    e.getparent().remove(e)

# --- índice: nuevas entradas después de la del punto 11.5 ------------------
ultimo = T_TOC_ULTIMO
for nivel, texto, nombre in toc:
    e = copy.deepcopy(T_TOC1 if nivel == 1 else T_TOC2)
    h = e.find(qn('w:hyperlink'))
    h.set(qn('w:anchor'), nombre)
    ts = h.findall('.//' + qn('w:t'))
    ts[0].text = texto
    for t in ts[1:]:
        t.text = '0'                                 # número de página: lo actualiza Word
    for it in h.iter(qn('w:instrText')):
        it.text = re.sub(r'_Toc\d+', nombre, it.text)
    ultimo.addnext(e)
    ultimo = e

doc.save(SALIDA)
print(f'Insertados {len(nuevos)} bloques, {len(toc)} títulos, figuras 42 a {estado["fig"]} -> {SALIDA}')
