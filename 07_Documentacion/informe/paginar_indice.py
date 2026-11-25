"""
Escribe en el índice el número de página real de TODAS las entradas, leyendo el PDF exportado por Word:
cada título se busca (en orden) en las páginas posteriores al índice y su página se copia en el resultado
guardado del campo PAGEREF de la entrada. No pide a Word que actualice campos (eso vacía el índice
porque los títulos del documento no usan estilos de título).
Uso: python paginar_indice.py <informe.docx> <informe.pdf>   -> imprime cuántas entradas cambiaron
"""
import re
import sys

import docx
import pymupdf
from docx.oxml.ns import qn

ruta_docx, ruta_pdf = sys.argv[1], sys.argv[2]
doc = docx.Document(ruta_docx)
pdf = pymupdf.open(ruta_pdf)


def norm(s):
    return re.sub(r'\s+', ' ', s).strip()


paginas = [[norm(l) for l in pdf[i].get_text().split('\n') if l.strip()] for i in range(pdf.page_count)]
fin_indice = max(i for i, p in enumerate(paginas) if any('ÍNDICE DE CONTENIDOS' in l for l in p))
# el índice puede ocupar varias páginas: termina donde aparece "1. RESUMEN EJECUTIVO" como título suelto
inicio = next(i for i in range(fin_indice, len(paginas)) if '1. RESUMEN EJECUTIVO' in paginas[i]
              and not any(re.search(r'\.{3,}\s*\d+$', l) for l in paginas[i]))

entradas = []
for p in doc.paragraphs:
    if p.style.name.startswith('toc'):
        h = p._p.find(qn('w:hyperlink'))
        if h is not None:
            entradas.append((p.text.split('\t')[0].strip(), h))

pagina_actual, cambios, faltan = inicio, 0, []
for titulo, h in entradas:
    t = norm(titulo)
    encontrada = None
    for i in range(pagina_actual, len(paginas)):
        lineas = paginas[i]
        dobles = [lineas[k] + ' ' + lineas[k + 1] for k in range(len(lineas) - 1)]   # título en 2 líneas
        if t in lineas or t in dobles:
            encontrada = i
            break
    if encontrada is None:
        faltan.append(titulo)
        continue
    pagina_actual = encontrada
    nueva = str(encontrada + 1)
    en_pageref, en_resultado, ts = False, False, []
    for r in h.iter(qn('w:r')):
        it = r.find(qn('w:instrText'))
        if it is not None and 'PAGEREF' in it.text:
            en_pageref = True
        fc = r.find(qn('w:fldChar'))
        if fc is not None and en_pageref:
            tipo = fc.get(qn('w:fldCharType'))
            en_resultado = tipo == 'separate'
            if tipo == 'end':
                break
        t_el = r.find(qn('w:t'))
        if en_resultado and t_el is not None:
            ts.append(t_el)
    if ''.join(x.text for x in ts) != nueva:
        ts[0].text = nueva
        for x in ts[1:]:
            x.text = ''
        cambios += 1
doc.save(ruta_docx)
print(f'entradas={len(entradas)} cambiadas={cambios} no_encontradas={faltan or "ninguna"} '
      f'indice_hasta_pagina={inicio}')
