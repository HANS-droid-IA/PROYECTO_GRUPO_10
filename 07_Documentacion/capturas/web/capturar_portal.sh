#!/bin/bash
# Captura (Chrome sin interfaz) cada sección del sitio web en ejecución (http://127.0.0.1:5000).
# Requiere el portal iniciado (07_Documentacion/portal_web/iniciar_portal.bat) y las cinco bases encendidas.
cd "$(dirname "$0")"
CH="/c/Program Files/Google/Chrome/Application/chrome.exe"
DEST=../bigdata/final
cap() {  # $1 nombre  $2 ruta  $3 alto
    "$CH" --headless=new --disable-gpu --hide-scrollbars --window-size=1400,$3 --force-device-scale-factor=1.5 \
        --virtual-time-budget=15000 --run-all-compositor-stages-before-draw \
        --screenshot="$(cygpath -w "$PWD/$DEST/$1.png")" "http://127.0.0.1:5000/$2" 2>/dev/null
    echo "$1 <- $2"
}
cap web_inicio      '#/inicio' 1080
cap web_rastrear    '#/rastrear/OLV2600029967' 1560
cap web_enviar      '#/enviar/OLV2600029969' 860
cap web_cotizar     '#/cotizar' 640
cap web_cuenta      '#/cuenta/20466632531' 1020
cap web_agencias    '#/agencias' 760
cap web_operaciones '#/operaciones' 1640
cap web_bases       '#/bases' 1250
# recorta el espacio vacío bajo el pie de página (fondo #f4f6fa / blanco), sin tocar el contenido
/g/Herramientas/Python312/python.exe - "$DEST" <<'PY'
import sys, pathlib
from PIL import Image, ImageChops
for f in sorted(pathlib.Path(sys.argv[1]).glob('web_*.png')):
    im = Image.open(f).convert('RGB')
    fondo = Image.new('RGB', im.size, (244, 246, 250))
    caja = ImageChops.difference(im, fondo).point(lambda v: 255 if v > 12 else 0).getbbox()
    if caja and caja[3] < im.size[1] - 10:
        im = im.crop((0, 0, im.size[0], min(im.size[1], caja[3] + 30)))
        im.save(f)
    print(f.name, im.size)
PY
