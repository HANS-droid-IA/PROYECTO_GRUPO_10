"""
Escribe en el índice el número de página de cada entrada (resultado guardado de los campos
PAGEREF), usando las páginas que calculó Word (JSON de finalizar_10_11.ps1 -Modo paginas).
Verifica además que las entradas originales sigan apuntando a la misma página.
Uso: python fijar_paginas_indice.py <informe.docx> <paginas.json>
"""
import json
import re
import sys

import docx
from docx.oxml.ns import qn

ruta, paginas = sys.argv[1], json.load(open(sys.argv[2], encoding='utf-8-sig'))
doc = docx.Document(ruta)
cambios, distintas = 0, []
for p in doc.paragraphs:
    if not p.style.name.startswith('toc'):
        continue
    h = p._p.find(qn('w:hyperlink'))
    if h is None:
        continue
    nombre = h.get(qn('w:anchor'))
    if nombre not in paginas:
        continue
    # el resultado del campo PAGEREF son los w:t posteriores al fldChar "separate" de ese campo
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
        t = r.find(qn('w:t'))
        if en_resultado and t is not None:
            ts.append(t)
    nueva = str(paginas[nombre])
    actual = ''.join(t.text for t in ts)
    if nombre.startswith('_Toc991'):                       # entradas de los puntos 10 y 11
        ts[0].text = nueva
        for t in ts[1:]:
            t.text = ''
        cambios += 1
    elif actual != nueva:
        distintas.append((p.text.split('\t')[0], actual, nueva))
doc.save(ruta)
print(f'Entradas nuevas con número de página: {cambios}')
print('Entradas originales con página distinta:', distintas or 'ninguna')
