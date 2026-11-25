"""
Puntos 12.3, 12.4 y 15: cuenta el volumen generado, calcula la justificación matemática del volumen
a partir de la tasa de operación simulada y resume los hallazgos de los resultados MapReduce.
Lee data/masivo/*.csv y outputs/*.csv; escribe outputs/volumen_datos.txt y outputs/hallazgos.txt.
Uso: python 06_BigData_Hadoop/04_volumen_y_hallazgos.py
"""
import csv
import os
from collections import Counter
from datetime import datetime

BASE = os.path.dirname(os.path.abspath(__file__))
DATOS = os.path.join(BASE, 'data', 'masivo')
OUT = os.path.join(BASE, 'outputs')


def filas(nombre):
    with open(os.path.join(DATOS, nombre + '.csv'), encoding='utf-8') as f:
        return sum(1 for _ in f) - 1


def leer(nombre):
    with open(os.path.join(OUT, nombre + '.csv'), encoding='utf-8') as f:
        return list(csv.DictReader(f))


# ------------------------------------------------------------------ 12.3 / 12.4 volumen
tablas = sorted(f[:-4] for f in os.listdir(DATOS) if f.endswith('.csv'))
conteo = {t: filas(t) for t in tablas}
total = sum(conteo.values())
bytes_total = sum(os.path.getsize(os.path.join(DATOS, t + '.csv')) for t in tablas)

fechas = Counter()
with open(os.path.join(DATOS, 'envio.csv'), encoding='utf-8') as f:
    for r in csv.DictReader(f):
        fechas[r['fecha_registro'][:10]] += 1
dias = len(fechas)
d0, d1 = min(fechas), max(fechas)
envios = conteo['envio']
eventos = conteo['evento_tracking']
agencias = 0
with open(os.path.join(DATOS, 'hub.csv'), encoding='utf-8') as f:
    agencias = sum(1 for r in csv.DictReader(f) if r['tipo'] == 'AGENCIA')
tasa_dia = envios / dias
pico = max(fechas.values())
ev_por_envio = eventos / envios
reg_por_envio = total / envios

lin = []
p = lin.append
p('VOLUMEN DE DATOS GENERADO (12.3)')
p('=' * 60)
for t in sorted(conteo, key=conteo.get, reverse=True):
    p(f'{t:<18}{conteo[t]:>12,}')
p('-' * 30)
p(f'{"TOTAL REGISTROS":<18}{total:>12,}')
p(f'Tamaño en disco: {bytes_total / 1024 ** 2:,.1f} MB   (en HDFS x2 por replicación = {2 * bytes_total / 1024 ** 2:,.1f} MB)')
p('')
p('JUSTIFICACIÓN MATEMÁTICA DEL VOLUMEN (12.4)')
p('=' * 60)
p(f'Periodo simulado: {d0} a {d1} = {dias} días de operación')
p(f'Red simulada: {agencias} agencias de admisión/entrega + hubs de clasificación')
p(f'Tasa de admisión  λ = envíos / días = {envios:,} / {dias} = {tasa_dia:,.0f} envíos/día '
  f'(pico diario observado: {pico:,})')
p(f'Por agencia: {tasa_dia:,.0f} / {agencias} = {tasa_dia / agencias:,.1f} envíos/agencia/día '
  f'≈ {tasa_dia / agencias / 12:,.1f} por hora en un turno de 12 h')
p(f'Eventos de tracking por envío  e = {eventos:,} / {envios:,} = {ev_por_envio:.2f}')
p(f'   (admisión + salida/llegada en cada tramo + clasificación en cada hub + reparto/entrega)')
p(f'Eventos esperados  E = λ · días · e = {tasa_dia:,.0f} · {dias} · {ev_por_envio:.2f} = '
  f'{tasa_dia * dias * ev_por_envio:,.0f}')
p(f'Registros totales por envío (paquetes, comprobante, despachos, intentos, incidencias, ...): '
  f'{reg_por_envio:.2f}')
p(f'Registros totales  R = {envios:,} · {reg_por_envio:.2f} = {total:,}')
anual = tasa_dia * 365
p(f'Proyección a 1 año con la misma tasa: {anual:,.0f} envíos -> {anual * ev_por_envio:,.0f} eventos '
  f'-> {anual * reg_por_envio:,.0f} registros')
p(f'Rango exigido: mínimo 500 000; esperado 1 a 5 millones -> evento_tracking = {eventos:,} '
  f'({"cumple" if 1_000_000 <= eventos <= 5_000_000 else "revisar"})')

with open(os.path.join(OUT, 'volumen_datos.txt'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(lin) + '\n')
print('\n'.join(lin))

# ------------------------------------------------------------------ 15 hallazgos
perm = leer('permanencia_hub')
sla = leer('cumplimiento_sla')
h = []
q = h.append
q('\nHALLAZGOS DEL ANÁLISIS MAPREDUCE (13.5 / 15.3)')
q('=' * 60)
hc = [r for r in perm if r['dimension'] == 'HORA' and r['hub'] == 'HC-LIM']
tot_hc = sum(int(r['estancias']) for r in hc)
nocturno = [r for r in hc if int(r['valor']) >= 18 or int(r['valor']) < 2]
diurno = [r for r in hc if 8 <= int(r['valor']) < 18]


def prom(rs):
    n = sum(int(r['estancias']) for r in rs)
    return n, sum(int(r['estancias']) * float(r['permanencia_promedio_h']) for r in rs) / n


n_noc, p_noc = prom(nocturno)
n_dia, p_dia = prom(diurno)
top = max(hc, key=lambda r: int(r['estancias']))
q(f'1) Hub Central Lima (HC-LIM): {tot_hc:,} estancias. La franja de las {top["valor"]}:00 concentra '
  f'{int(top["estancias"]):,} llegadas ({100 * int(top["estancias"]) / tot_hc:.1f} %) con '
  f'{top["permanencia_promedio_h"]} h de permanencia promedio.')
q(f'   Llegadas 18:00-02:00: {n_noc:,} estancias, {p_noc:.2f} h promedio; llegadas 08:00-18:00: '
  f'{n_dia:,} estancias, {p_dia:.2f} h -> +{100 * (p_noc / p_dia - 1):.0f} % de permanencia nocturna.')
aqp = {r['valor']: r for r in perm if r['dimension'] == 'MES' and r['hub'] == 'HR-AQP'}
base = [float(aqp[m]['permanencia_promedio_h']) for m in ('2026-04', '2026-05', '2026-06')]
crit = [float(aqp[m]['permanencia_promedio_h']) for m in ('2026-08', '2026-09')]
q(f'2) Hub Regional Arequipa: abr-jun {sum(base) / 3:.2f} h promedio vs ago-sep {sum(crit) / 2:.2f} h '
  f'(+{100 * (sum(crit) / 2 / (sum(base) / 3) - 1):.0f} %); % estancias > 12 h sube de '
  f'{aqp["2026-05"]["pct_mayor_12h"]} % a {aqp["2026-09"]["pct_mayor_12h"]} %.')
dia = {r['valor']: r for r in perm if r['dimension'] == 'DIA' and r['hub'] == 'HC-LIM'}
q(f'3) Lunes en HC-LIM: {dia["1-Lunes"]["permanencia_promedio_h"]} h promedio frente a '
  f'{dia["2-Martes"]["permanencia_promedio_h"]} h el martes (acumulado del fin de semana).')
serv = sorted((r for r in sla if r['dimension'] == 'SERVICIO'), key=lambda r: float(r['pct_cumplimiento_sla']))
q('4) Cumplimiento del SLA por servicio: ' + '; '.join(
    f'{r["clave"]} {r["pct_cumplimiento_sla"]} % (retraso medio {r["retraso_promedio_h"]} h)' for r in serv))
rutas = [r for r in sla if r['dimension'] == 'SERVICIO_RUTA' and int(r['entregados']) >= 500]
peores = sorted(rutas, key=lambda r: float(r['pct_cumplimiento_sla']))[:5]
q('5) Rutas con menor cumplimiento (>= 500 entregas): ' + '; '.join(
    f'{r["clave"]} {r["detalle"]} {r["pct_cumplimiento_sla"]} %' for r in peores))
meses = [r for r in sla if r['dimension'] == 'MES']
ing = sum(float(r['ingresos_soles']) for r in meses)
jul = next(r for r in meses if r['clave'] == '2026-07')
q(f'6) Ingresos procesados: S/ {ing:,.2f}; julio (Fiestas Patrias) {int(jul["envios"]):,} envíos, '
  f'el mes de mayor volumen, con cumplimiento {jul["pct_cumplimiento_sla"]} %.')
with open(os.path.join(OUT, 'hallazgos.txt'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(h) + '\n')
print('\n'.join(h))
