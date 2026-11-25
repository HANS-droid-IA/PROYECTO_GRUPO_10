#!/bin/bash
# Genera el informe con los puntos 10 y 11 a partir del informe original (sin modificarlo):
#   1) inserta el contenido y las entradas del índice   2) Word exporta a PDF
#   3) copia al .docx los números de página que calculó Word   4) exporta el PDF final
#   5) verifica que las páginas originales no cambiaron
# Uso (Git Bash): bash 07_Documentacion/informe/generar_informe_10_11.sh
set -eo pipefail
cd "$(dirname "$0")"
PY=/g/Herramientas/Python312/python.exe
export PYTHONIOENCODING=utf-8
ORIG=Informe_BDII_Trazabilidad_Olva_Courier.docx
NUEVO=Informe_BDII_Trazabilidad_10_11.docx
DOCX_WIN="$(cygpath -w "$PWD/$NUEVO")"
TMP_WIN="$(cygpath -w "$TEMP")"

$PY agregar_puntos_10_11.py "$ORIG" "$NUEVO"
powershell -ExecutionPolicy Bypass -File finalizar_10_11.ps1 -Modo pdf -Docx "$DOCX_WIN" >/dev/null
$PY - <<'EOF'
import pymupdf, docx, re, json, os
from docx.oxml.ns import qn
texto = pymupdf.open('Informe_BDII_Trazabilidad_10_11.pdf')[1].get_text()
pag = {m.group(1).strip(): int(m.group(2)) for m in
       (re.match(r'^((?:10|11)(?:\.\d)?\.? .+?) \.{3,}\s*(\d+)\s*$', l.strip()) for l in texto.splitlines()) if m}
d = docx.Document('Informe_BDII_Trazabilidad_10_11.docx'); res = {}
for p in d.paragraphs:
    h = p._p.find(qn('w:hyperlink')) if p.style.name.startswith('toc') else None
    if h is not None and h.get(qn('w:anchor')).startswith('_Toc991'):
        res[h.get(qn('w:anchor'))] = pag[p.text.split('\t')[0].strip()]
json.dump(res, open(os.path.join(os.environ['TEMP'], 'paginas.json'), 'w'))
EOF
$PY fijar_paginas_indice.py "$NUEVO" "$TMP_WIN\\paginas.json"
powershell -ExecutionPolicy Bypass -File finalizar_10_11.ps1 -Modo pdf -Docx "$DOCX_WIN"
$PY - <<'EOF'
import pymupdf, os
base = pymupdf.open(os.path.join(os.environ['TEMP'], 'original_sin_cambios.pdf'))
n = pymupdf.open('Informe_BDII_Trazabilidad_10_11.pdf')
print('Páginas:', base.page_count, '->', n.page_count)
print('Páginas originales que cambiaron:', [i + 1 for i in range(base.page_count) if base[i].get_text().split() != n[i].get_text().split()],
      '(esperado: 2 = índice, 26-27 = inicio del punto 10)')
EOF
