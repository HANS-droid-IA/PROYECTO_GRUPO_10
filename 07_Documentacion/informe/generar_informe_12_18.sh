#!/bin/bash
# Genera el informe con los puntos 12 a 18 a partir del informe con los puntos 10 y 11 (sin modificarlo):
#   1) inserta el contenido (agregar_puntos_12_18.py + contenido_12_18.py) y las entradas del índice
#   2) Word exporta a PDF (sin actualizar campos)  3) se escriben en el índice las páginas reales leídas
#      del PDF y se repite hasta que no cambie nada  4) verifica que las páginas 1 a 50 no cambiaron
# Requiere las imágenes de 07_Documentacion/capturas/bigdata/final (armar_final.py).
# Uso (Git Bash): bash 07_Documentacion/informe/generar_informe_12_18.sh
set -eo pipefail
cd "$(dirname "$0")"
PY=/g/Herramientas/Python312/python.exe
export PYTHONIOENCODING=utf-8
BASE=Informe_BDII_Trazabilidad_10_11.docx
NUEVO=Informe_BDII_Trazabilidad_12_18.docx
DOCX_WIN="$(cygpath -w "$PWD/$NUEVO")"

$PY agregar_puntos_12_18.py "$BASE" "$NUEVO"
for intento in 1 2 3 4; do
    powershell -NoProfile -ExecutionPolicy Bypass -File finalizar_10_11.ps1 -Modo pdf -Docx "$DOCX_WIN" | tail -1
    r=$($PY paginar_indice.py "$NUEVO" "${NUEVO%.docx}.pdf"); echo "$r"
    case "$r" in *"cambiadas=0 "*) break ;; esac
done
$PY - <<'EOF'
import pymupdf
a = pymupdf.open('Informe_BDII_Trazabilidad_10_11.pdf')
b = pymupdf.open('Informe_BDII_Trazabilidad_12_18.pdf')
print('Páginas:', a.page_count, '->', b.page_count)
# el índice crece una página: la página k del informe anterior (k >= 3) es la k+1 del nuevo
iguales = [k + 1 for k in range(2, 49) if a[k].get_text().split() == b[k + 1].get_text().split()]
print(f'Páginas 3 a 49 del informe anterior idénticas en el nuevo: {len(iguales)} de 47')
EOF
