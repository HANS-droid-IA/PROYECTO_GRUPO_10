#!/usr/bin/env python3
"""
Renderiza los diagramas Mermaid (*.mmd) de esta carpeta a SVG (vectorial) y PNG
de alta resolución, usando Chrome/Edge en modo headless y Mermaid desde CDN.
Uso: python renderizar_diagramas.py [archivo.mmd ...]
"""
import html
import os
import re
import subprocess
import sys
import tempfile

BASE = os.path.dirname(os.path.abspath(__file__))
BROWSERS = [r'C:\Program Files\Google\Chrome\Application\chrome.exe',
            r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe']
BROWSER = next(b for b in BROWSERS if os.path.exists(b))
ESCALA = 2.5  # factor de píxeles para el PNG

PLANTILLA = """<!doctype html><html><head><meta charset="utf-8">
<style>html,body{{margin:0;padding:0;background:#ffffff}} #d{{display:inline-block;padding:24px}}</style></head>
<body><div id="d"></div>
<script type="module">
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
mermaid.initialize({{startOnLoad:false, theme:'base', securityLevel:'loose',
  themeVariables:{{fontFamily:'Arial', fontSize:'16px', primaryColor:'#eef3fb', primaryBorderColor:'#3d5a8a',
    primaryTextColor:'#1b2433', lineColor:'#4a4f57', clusterBkg:'#f8f9fb', clusterBorder:'#8c9bb5',
    edgeLabelBackground:'#ffffff', tertiaryColor:'#ffffff'}},
  flowchart:{{useMaxWidth:false, htmlLabels:true, curve:'basis', nodeSpacing:40, rankSpacing:55, wrappingWidth:420}},
  er:{{useMaxWidth:false, fontSize:14}},
  themeCSS:'.nodeLabel, .label div {{ max-width: 460px !important; white-space: nowrap !important; }}'}});
const src = {src};
const {{svg}} = await mermaid.render('g', src);
const d = document.getElementById('d');
d.innerHTML = svg;
const r = d.getBoundingClientRect();
document.title = 'DIM:' + Math.ceil(r.width) + 'x' + Math.ceil(r.height);
</script></body></html>"""


def chrome(args):
    return subprocess.run([BROWSER, '--headless=new', '--disable-gpu', '--hide-scrollbars',
                           '--virtual-time-budget=20000', '--run-all-compositor-stages-before-draw'] + args,
                          capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)


def render(mmd):
    nombre = os.path.splitext(os.path.basename(mmd))[0]
    src = open(mmd, encoding='utf-8').read()
    src = '\n'.join(l for l in src.splitlines() if not l.strip().startswith('%%'))
    pagina = PLANTILLA.format(src=repr(src).replace('</', '<\\/'))
    tmp = os.path.join(tempfile.gettempdir(), f'render_{nombre}.html')
    open(tmp, 'w', encoding='utf-8').write(pagina)
    url = 'file:///' + tmp.replace('\\', '/')
    dom = chrome(['--window-size=6000,6000', '--dump-dom', url]).stdout
    m = re.search(r'<title>DIM:(\d+)x(\d+)</title>', dom)
    if not m:
        print(f'ERROR al renderizar {nombre}:', dom[:500])
        return
    w, h = int(m.group(1)), int(m.group(2))
    svg = re.search(r'(<svg.*?</svg>)', dom, re.S).group(1)
    open(os.path.join(BASE, f'{nombre}.svg'), 'w', encoding='utf-8').write(
        '<?xml version="1.0" encoding="UTF-8"?>\n' + svg)
    png = os.path.join(BASE, f'{nombre}.png')
    chrome([f'--window-size={w},{h}', f'--force-device-scale-factor={ESCALA}', f'--screenshot={png}', url])
    print(f'{nombre}: {w}x{h} px CSS -> {int(w * ESCALA)}x{int(h * ESCALA)} PNG')


archivos = sys.argv[1:] or sorted(os.path.join(BASE, f) for f in os.listdir(BASE) if f.endswith('.mmd'))
for f in archivos:
    render(f)
