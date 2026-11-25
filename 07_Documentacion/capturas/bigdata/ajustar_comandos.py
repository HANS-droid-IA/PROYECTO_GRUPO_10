"""
Parte en varias líneas los comandos muy largos de las transcripciones (como se escribirían en bash con "\"
o en cqlsh con líneas de continuación) para que las capturas sean legibles. No modifica ninguna salida.
Uso: python ajustar_comandos.py   (lo llama generar_transcripciones.sh)
"""
import pathlib

S = pathlib.Path(__file__).with_name('salidas')

CORTES = {
    'hd_bloques.txt': {
        "hadoop@Hans:~$ hdfs fsck /olva/raw/evento_tracking -files -blocks -locations 2>/dev/null | grep": [
            "hadoop@Hans:~$ hdfs fsck /olva/raw/evento_tracking -files -blocks -locations 2>/dev/null \\",
            "> | grep -E 'evento_tracking.csv|blk_|Status|Total blocks|Average block replication|Number of data-nodes' \\",
            "> | sed -E 's/DatanodeInfoWithStorage\\[([0-9.:]+),DS-[0-9a-f-]+,DISK\\]/\\1/g; s/BP-[0-9.-]+://'",
        ],
    },
    'cq_kpi.txt': {
        "olva_admin@cqlsh:olva_tracking> SELECT valor AS hora": [
            "olva_admin@cqlsh:olva_tracking> SELECT valor AS hora, estancias, permanencia_promedio_h, pct_mayor_12h",
            "                            ...   FROM kpi_permanencia_hub",
            "                            ...  WHERE hub = 'HC-LIM' AND dimension = 'HORA' AND valor >= '18';",
        ],
        "olva_admin@cqlsh:olva_tracking> SELECT clave AS servicio": [
            "olva_admin@cqlsh:olva_tracking> SELECT clave AS servicio, envios, pct_cumplimiento_sla, retraso_promedio_h",
            "                            ...   FROM kpi_cumplimiento_sla WHERE dimension = 'SERVICIO';",
        ],
    },
}

for archivo, reglas in CORTES.items():
    ruta = S / archivo
    salida = []
    for linea in ruta.read_text(encoding='utf-8').split('\n'):
        for inicio, partes in reglas.items():
            if linea.startswith(inicio):
                salida.extend(partes)
                break
        else:
            salida.append(linea.replace('\t', '    '))
    ruta.write_text('\n'.join(salida), encoding='utf-8')
    print(f'{archivo}: comandos partidos')
