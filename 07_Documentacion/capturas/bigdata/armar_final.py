"""
Prepara las imágenes finales del informe (final/*.png): copia las capturas de consola y recorta las
capturas web reales del clúster Hadoop a la zona útil (sin cambiar su contenido).
Uso: python armar_final.py
"""
import pathlib
import shutil

from PIL import Image

B = pathlib.Path(__file__).parent
F = B / 'final'
F.mkdir(exist_ok=True)

for png in B.glob('*.png'):
    if not png.name.startswith(('contacto', 'web_prev')):
        shutil.copy(png, F / png.name)

RECORTES = {            # nombre: [(x0, y0, x1, y1), ...]  (si hay varios tramos se apilan verticalmente)
    'hd_web_resumen': [(240, 0, 2010, 1830)],
    'hd_web_datanodes': [(240, 0, 2010, 1420)],
    'hd_web_raw': [(240, 0, 2010, 1065)],
    'hd_web_resultados': [(240, 0, 2010, 660)],
    'hd_web_job': [(0, 0, 2250, 945)],
    'hd_web_yarn_nodos': [(0, 0, 2775, 800)],
    'hd_web_yarn_apps': [(0, 0, 2390, 1275)],
    'hd_web_contadores': [(0, 0, 1950, 160), (0, 1395, 1950, 2830)],
}
for nombre, tramos in RECORTES.items():
    img = Image.open(B / 'web' / f'{nombre}.png').convert('RGB')
    partes = [img.crop(t) for t in tramos]
    w = max(p.size[0] for p in partes)
    out = Image.new('RGB', (w, sum(p.size[1] for p in partes)), 'white')
    y = 0
    for p in partes:
        out.paste(p, (0, y))
        y += p.size[1]
    out.save(F / f'{nombre}.png')
    print(f'{nombre}: {out.size}')

for d in ('05_cluster_hadoop', '06_integracion_end_to_end'):
    shutil.copy(B.parents[1] / 'diagramas' / f'{d}.png', F / f'{d}.png')
print('final:', len(list(F.glob('*.png'))), 'imágenes')
