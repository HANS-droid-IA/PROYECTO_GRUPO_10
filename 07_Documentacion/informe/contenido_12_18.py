# Contenido de los puntos 12 a 18 (lo ejecuta agregar_puntos_12_18.py).
# Marcado en línea: **negrita** y `código`. Todas las cifras provienen de ejecuciones reales
# (06_BigData_Hadoop/outputs y 07_Documentacion/capturas/bigdata).

F_HADOOP = 'elaboración propia a partir de la ejecución en Ubuntu 22.04 (WSL2) sobre Apache Hadoop 3.3.6.'
F_WEB_HDFS = 'elaboración propia a partir de la consola web del NameNode (http://localhost:9870).'
F_WEB_YARN = 'elaboración propia a partir de la consola web del ResourceManager (http://localhost:8088).'
F_WEB_JH = 'elaboración propia a partir de la consola web del JobHistory Server (http://localhost:19888).'
F_BASH = 'elaboración propia a partir de la ejecución de los scripts del proyecto.'

# =====================================================================
H1('12. GENERACIÓN Y GESTIÓN DE DATOS MASIVOS')
TXT('Los puntos anteriores trabajaron con una base operativa de 29 966 envíos y 315 101 eventos, suficiente para validar '
    'el modelo, la programación y la distribución. Para el análisis Big Data se necesitaba un volumen de otro orden, que '
    'represente meses de operación de toda la red y que no quepa cómodamente en una consulta transaccional. Este punto '
    'describe cómo se generó ese volumen, cuánto se generó y por qué esa cantidad es coherente con la operación simulada.')

H2('12.1 Origen de la fuente de datos')
TXT('La fuente es **híbrida**: la estructura de la red es pública y las transacciones son **sintéticas**. Ningún registro '
    'corresponde a datos internos reales de Olva Courier.')
VIN('**Componente público (catálogos):** ciudades con cobertura, códigos de ubigeo del INEI, coordenadas, existencia de '
    'aeropuerto o acceso terrestre, tipos de servicio aéreos y terrestres y estados de seguimiento, tomados de la '
    'información pública del courier y del Estado peruano.',
    '**Componente sintético (transacciones):** clientes, destinatarios, envíos, paquetes, comprobantes, despachos, '
    'eventos de tracking, intentos de entrega e incidencias, producidos por el simulador del proyecto '
    '(`01_Relacional_PostgreSQL/generador/generar_datos.py`).',
    '**Por qué un simulador propio y no Faker:** Faker produce registros aislados (nombres, direcciones) sin relación '
    'temporal entre sí. El análisis necesita **secuencias coherentes**: un paquete no puede salir de un hub antes de '
    'llegar, cada despacho tiene horario y capacidad, y los cuellos de botella deben reflejarse en los tiempos. Por eso '
    'se usó un simulador de eventos discretos escrito con la biblioteca estándar de Python 3.12 (`random` con semilla '
    'fija 2026), que garantiza que cada ejecución produce exactamente los mismos datos.',
    '**Mismo generador que la base operativa:** el conjunto masivo se genera con el mismo código que llenó PostgreSQL; '
    'solo cambia la cantidad de envíos. Así los resultados de Hadoop son comparables con los de los demás motores.')

H2('12.2 Proceso y script de generación de datos')
TXT('Para cada envío el simulador ejecuta la misma secuencia que una operación real:')
VIN('**1. Demanda:** reparte los envíos entre los 190 días del periodo (1 de abril al 7 de octubre de 2026) con '
    'estacionalidad semanal (lunes alto, domingo bajo), una campaña de Fiestas Patrias en julio y una tendencia creciente.',
    '**2. Ruta:** elige remitente, agencia de origen y destino, y calcula el camino agencia → hub → … → hub → agencia con '
    'el algoritmo de Dijkstra sobre las 98 rutas de la red.',
    '**3. Trayecto:** consolida el paquete en despachos con horarios fijos de salida y capacidad, simula retrasos de '
    'salida y llegada y el tiempo de clasificación en cada hub, que se multiplica en los **cuellos de botella '
    'inyectados** (Hub Central Lima de 18:00 a 02:00, Hub Arequipa en agosto y septiembre, lunes y campaña de julio).',
    '**4. Entrega:** simula hasta tres intentos de entrega, devoluciones, incidencias y reclamos por retraso; descarta '
    'todo evento posterior a la fecha de corte (envíos "en vuelo").')
TXT('Para el modo Big Data se añadieron dos opciones al generador sin alterar la base operativa (se comprobó que con '
    '30 000 envíos produce archivos idénticos byte a byte a los cargados en PostgreSQL): la variable `OLVA_OUT` indica la '
    'carpeta de salida y el factor `ESCALA_CAP` aumenta la capacidad de los despachos en la misma proporción que el '
    'volumen, como ocurriría si la empresa ampliara su flota y sus vuelos. Sin ese ajuste, diez veces más envíos con la '
    'misma flota generarían retrasos irreales.')
CODIGO('''N_ENVIOS = int(sys.argv[1]) if len(sys.argv) > 1 else 30000
OUT = os.environ.get('OLVA_OUT') or os.path.join(..., '..', 'datos')
# con más envíos que la base (30 000) la flota y los vuelos crecen en proporción
ESCALA_CAP = max(1.0, N_ENVIOS / 30000)
...
def despacho_para(r, ready):
    cap = CAPACIDAD[tipo_tramo(r)]          # p. ej. troncal terrestre 250, troncal aéreo 70
    cap = int(cap * ESCALA_CAP)             # 300 000 envíos -> capacidad x10

$ OLVA_OUT=../../06_BigData_Hadoop/data/masivo python generar_datos.py 300000''')
FIGURA('gen_masivo', 'Generación del conjunto masivo: 300 000 envíos solicitados y filas producidas por tabla',
       F_BASH, 'La generación tardó 162 segundos y produjo 18 archivos CSV. Se solicitaron 300 000 envíos y quedaron '
       '299 667, porque el simulador descarta los registrados en la última media hora antes del corte. La tabla '
       'principal, `evento_tracking`, alcanza 3 152 417 filas.', ancho_cm=12.5)

H2('12.3 Volumen de datos generado')
TXT('El conjunto masivo suma **5 640 511 registros** en 18 tablas y ocupa 340,2 MB en CSV (680,3 MB en HDFS por la '
    'replicación doble). La Tabla 1 resume el volumen por tabla y lo compara con la base operativa.')
TABLA(['Tabla', 'Base operativa (PostgreSQL)', 'Conjunto masivo (Hadoop)', 'Factor'],
      [['evento_tracking', '315 101', '**3 152 417**', '10,0'],
       ['despacho_envio', '82 894', '829 869', '10,0'],
       ['paquete', '40 714', '407 806', '10,0'],
       ['intento_entrega', '33 557', '334 847', '10,0'],
       ['envio', '29 966', '299 667', '10,0'],
       ['comprobante', '29 966', '299 667', '10,0'],
       ['destinatario', '26 413', '263 513', '10,0'],
       ['despacho', '22 729', '30 185', '1,3'],
       ['incidencia', '1 904', '18 852', '9,9'],
       ['catálogos (cliente, empleado, vehículo, tarifa, ruta, hub, ciudad, región, servicio)', '3 688', '3 688', '1,0'],
       ['**Total**', '**586 932**', '**5 640 511**', '**9,6**']],
      [6.0, 3.4, 3.4, 1.6],
      fuente='elaboración propia a partir del conteo de los archivos CSV generados (04_volumen_y_hallazgos.py).')
TXT('Los despachos solo crecen 1,3 veces porque, al ampliar la capacidad, cada manifiesto lleva más paquetes: el '
    'número de salidas lo fijan los horarios, no el volumen. La tabla `evento_tracking` (3,15 millones de filas) está '
    'dentro del rango esperado por la guía (de 1 a 5 millones) y es la que procesa MapReduce.')

H2('12.4 Justificación matemática del volumen')
TXT('El volumen no es arbitrario: resulta de una tasa de operación realista multiplicada por el periodo simulado y por '
    'la cantidad de eventos que genera cada envío.')
VIN('**Tasa de admisión:** λ = 299 667 envíos / 190 días = **1 577 envíos por día** (pico diario de 3 013 en la '
    'campaña de julio).',
    '**Carga por agencia:** 1 577 / 29 agencias = 54,4 envíos por agencia al día, unos **4,5 por hora** en un turno de '
    '12 horas: una carga plausible para una agencia de courier.',
    '**Eventos por envío:** e = 3 152 417 / 299 667 = **10,52** (admisión, salida y llegada en cada tramo, clasificación '
    'en cada hub, salida a reparto y entrega).',
    '**Eventos esperados:** E = λ · días · e = 1 577 · 190 · 10,52 = **3 152 417**, exactamente las filas generadas.',
    '**Registros totales:** R = envíos · 18,82 registros por envío = 299 667 · 18,82 = **5 640 511**.',
    '**Proyección anual:** con la misma tasa, un año completo produciría 575 676 envíos, 6 055 959 eventos y '
    '10,8 millones de registros; es decir, el volumen crecería por encima de lo que conviene analizar dentro de la base '
    'transaccional.')
FIGURA('gen_volumen', 'Cálculo de la justificación matemática del volumen a partir de los archivos generados',
       F_BASH, 'El script `04_volumen_y_hallazgos.py` cuenta las filas reales y aplica las fórmulas, de modo que la '
       'justificación se recalcula si se regenera el conjunto. La comprobación final indica que `evento_tracking` '
       'cumple el rango exigido.', ancho_cm=14.5)
TXT('**Validación de coherencia:** que el volumen sea diez veces mayor no debe cambiar el comportamiento de la red. Se '
    'comparó la base operativa con el conjunto masivo: el cumplimiento del plazo de entrega es 91,40 % frente a '
    '91,43 %, y los eventos por envío son 10,52 en ambos casos. El conjunto masivo, por tanto, representa la misma '
    'operación a mayor escala.')

# =====================================================================
H1('13. PROCESAMIENTO CON HADOOP – HDFS Y MAPREDUCE')
H2('13.1 Justificación del uso de Hadoop en la solución Big Data')
TXT('La pregunta de negocio es analítica: **¿en qué hubs, horas y meses se acumulan los paquetes y cómo afecta eso al '
    'cumplimiento del plazo?** Responderla exige recorrer **toda** la historia de eventos, agruparla por envío para '
    'reconstruir cuánto tiempo pasó cada paquete en cada hub, y después agregar millones de estancias. Ninguno de los '
    'motores ya implementados está pensado para ese trabajo:')
VIN('**PostgreSQL y Oracle** atienden la operación diaria (admisiones, escaneos, facturación). Un recorrido completo '
    'de 3,15 millones de eventos con ordenamientos y agrupaciones compite por CPU, memoria y E/S con las transacciones, '
    'y crecer obligaría a comprar un servidor más grande (escalado vertical).',
    '**Apache Cassandra** está modelada por consulta: responde muy rápido "los eventos de un envío" o "los escaneos de '
    'un hub en un día", pero una agregación sobre toda la tabla requiere `ALLOW FILTERING` y recorre todas las '
    'particiones, justo lo que su diseño evita.',
    '**MongoDB** resuelve el expediente de cada envío; sus agregaciones funcionan bien sobre decenas de miles de '
    'documentos, pero ejecutar análisis masivos sobre la base que consulta el portal afecta su tiempo de respuesta.')
TXT('Hadoop separa el análisis de la operación y aporta lo que ese trabajo necesita:')
VIN('**HDFS** guarda archivos grandes divididos en bloques de 64 MB y replicados en dos DataNodes: si un nodo falla, '
    'los datos siguen disponibles, y el almacenamiento crece agregando nodos baratos (escalado horizontal).',
    '**MapReduce sobre YARN** lleva el cálculo hasta donde están los bloques (localidad de datos) y lo reparte en '
    'tareas paralelas; el mismo código procesa 30 mil o 30 millones de envíos.',
    '**Procesamiento por lotes desacoplado:** el análisis se ejecuta sobre una copia de los datos en HDFS, sin cargar '
    'las bases transaccionales; solo los indicadores finales (458 filas) vuelven a ellas.')
TXT('**¿Por qué no basta con PostgreSQL y Oracle?** Porque llevarían en el mismo servidor la operación en línea y el '
    'análisis histórico, que tienen necesidades opuestas: transacciones cortas y consistentes frente a recorridos '
    'completos de millones de filas. Separarlos protege la operación y permite que el análisis crezca de forma '
    'independiente.')

H2('13.2 Arquitectura del clúster')
TXT('Se instaló **Apache Hadoop 3.3.6** en el equipo del proyecto, sobre **Ubuntu 22.04 LTS** ejecutándose en WSL2 '
    '(Subsistema de Windows para Linux) y **OpenJDK 11**, la versión de Java soportada por Hadoop 3.3. El paquete se '
    'descargó del archivo oficial de Apache y se verificó su huella SHA-512 antes de instalarlo en `/opt/hadoop`. El '
    'clúster funciona en modo **pseudo-distribuido**: cada componente es un proceso independiente, con sus propios '
    'puertos y directorios, como en un clúster real, pero en una sola máquina (Figura 44).')
FIGURA('05_cluster_hadoop', 'Arquitectura del clúster Apache Hadoop instalado: HDFS (NameNode y dos DataNodes) y YARN '
       '(ResourceManager, NodeManager y JobHistory)', 'elaboración propia.')
TABLA(['Componente', 'Rol', 'Puertos', 'Configuración principal'],
      [['NameNode', 'Maestro de HDFS: guarda el árbol de directorios y la ubicación de cada bloque', '9000 (RPC), 9870 (web)', '`fs.defaultFS = hdfs://localhost:9000`'],
       ['DataNode 1 y DataNode 2', 'Trabajadores de HDFS: almacenan los bloques y sus réplicas', '9866 / 9876 (datos)', '`dfs.replication = 2`, `dfs.blocksize = 64 MB`'],
       ['ResourceManager', 'Maestro de YARN: asigna contenedores de memoria y CPU a cada job', '8032 (RPC), 8088 (web)', 'Planificador Capacity, cola `default`'],
       ['NodeManager', 'Trabajador de YARN: ejecuta las tareas map y reduce', '8042 (web)', '4 096 MB y 6 vCores; map 512 MB, reduce 768 MB'],
       ['JobHistory Server', 'Conserva el historial, los contadores y los registros de cada job', '10020, 19888 (web)', 'Agregación de registros activada']],
      [3.0, 5.6, 3.2, 4.6], fuente='elaboración propia a partir de los archivos de configuración de hadoop_nativo/conf.')
TXT('La instalación y la operación quedaron automatizadas en `06_BigData_Hadoop/hadoop_nativo`: `instalar_hadoop.sh` '
    '(descarga, verificación, configuración y formato del NameNode), `iniciar_hadoop.bat` y `detener_hadoop.bat` '
    '(arranque y parada desde Windows) y `hadoop_cluster status` (estado de los procesos).')
FIGURA('hd_instalacion', 'Versión de Java y de Hadoop instaladas y parámetros efectivos del clúster', F_HADOOP,
       'Las consultas `hdfs getconf` confirman la configuración que realmente usa el clúster: sistema de archivos '
       '`hdfs://localhost:9000`, replicación 2 y bloques de 67 108 864 bytes (64 MB).', ancho_cm=15.5)
FIGURA('hd_estado', 'Estado del clúster: seis procesos Java de Hadoop, dos DataNodes vivos y el NodeManager en ejecución',
       F_HADOOP, '`jps` muestra los seis demonios (NameNode, dos DataNode, ResourceManager, NodeManager y '
       'JobHistoryServer). HDFS informa dos DataNodes vivos y YARN un NodeManager en estado `RUNNING`.', ancho_cm=13)
FIGURA('hd_web_resumen', 'Consola web del NameNode: resumen del sistema de archivos HDFS', F_WEB_HDFS,
       'El NameNode está activo, sin modo seguro, con 2 nodos vivos y 0 muertos, y 0 bloques con menos réplicas de '
       'las configuradas. HDFS ocupa 728,99 MB con los datos del proyecto replicados.', ancho_cm=14)
FIGURA('hd_web_datanodes', 'Consola web del NameNode: los dos DataNodes en servicio', F_WEB_HDFS,
       'Cada DataNode guarda 44 bloques y 364,5 MB: al tener replicación 2, los dos nodos poseen una copia completa '
       'de los datos, por lo que la pérdida de uno no interrumpe el acceso.', ancho_cm=14)
FIGURA('hd_web_yarn_nodos', 'Consola web del ResourceManager: nodo de procesamiento disponible para YARN', F_WEB_YARN,
       ancho_cm=15.5)

H2('13.3 Almacenamiento y organización en HDFS')
TXT('Los datos se organizan en HDFS por **zonas**, según su etapa en el flujo (script `01_cargar_hdfs.sh`):')
VIN('`/olva/raw/<tabla>/`: zona cruda. Un directorio por tabla masiva (eventos, envíos, paquetes, intentos, '
    'despachos, incidencias, comprobantes, destinatarios) con el CSV tal como salió del generador.',
    '`/olva/raw/catalogos/`: catálogos pequeños (hubs, ciudades, regiones, servicios, rutas y tarifas). MapReduce los '
    'distribuye a cada tarea mediante la **caché distribuida**.',
    '`/olva/operacional/<fecha>/`: extracciones diarias desde PostgreSQL (punto 14).',
    '`/olva/resultados/` y `/olva/resultados_operacional/`: indicadores calculados por MapReduce.')
FIGURA('hd_carga', 'Zonas de datos en HDFS y tamaño de cada tabla del conjunto masivo', F_HADOOP,
       'La primera columna de `hdfs dfs -du` es el tamaño lógico y la segunda el espacio realmente ocupado: el doble, '
       'por la replicación. `evento_tracking` ocupa 180,9 MB y 361,9 MB replicados.', ancho_cm=13)
FIGURA('hd_bloques', 'División de evento_tracking en bloques de 64 MB y ubicación de sus réplicas', F_HADOOP,
       'El archivo de 189 725 133 bytes se dividió en 3 bloques (64 MB, 64 MB y 53 MB). Cada bloque tiene dos réplicas '
       'vivas, una en cada DataNode (puertos 9866 y 9876), y el estado general es `HEALTHY`. Los tres bloques permiten '
       'que tres tareas map lean el archivo en paralelo.', ancho_cm=15.5)
FIGURA('hd_web_raw', 'Explorador de HDFS: zona /olva/raw con un directorio por tabla', F_WEB_HDFS, ancho_cm=14)

H2('13.4 Procesamiento mediante algoritmo MapReduce')
TXT('El análisis se programó en Java 8 contra la API de Hadoop 3.3.6 y se empaquetó en `olva-bigdata.jar` '
    '(`06_BigData_Hadoop/mapreduce`). Un **Driver** encadena tres jobs:')
VIN('**Job 1 – permanencia por envío:** el **Mapper** lee cada evento y, si es una llegada o salida de hub, lo emite '
    'con la clave del envío. El **Reducer** recibe todos los eventos de un mismo envío, los ordena por fecha y empareja '
    'cada llegada con la siguiente salida del mismo hub: la diferencia es la **estancia**. Cada estancia se emite en '
    'tres dimensiones: hora de llegada, mes y día de la semana.',
    '**Job 2 – indicadores de permanencia:** suma, por hub y dimensión, el número de estancias, las horas acumuladas y '
    'las estancias de más de 12 horas. Un **Combiner** hace sumas parciales en cada tarea map para enviar menos datos '
    'por la red.',
    '**Job 3 – cumplimiento del SLA:** el Mapper une cada envío con los catálogos de hubs, ciudades, regiones y '
    'servicios dentro de la propia tarea (**map-side join**, sin una segunda pasada) y calcula si se entregó a tiempo; '
    'el Reducer obtiene el porcentaje de cumplimiento, el retraso promedio y los ingresos por servicio, ruta, mes y '
    'agencia.')
TXT('A continuación se presenta el código fuente completo del Mapper, el Reducer y el Driver. Las demás clases '
    '(`AgregadoMapper`, `SumaCombiner`, `AgregadoReducer`, `SlaMapper`, `SlaReducer` y `Util`) están en la misma '
    'carpeta del proyecto.')
SUBT('PermanenciaMapper.java (Mapper del Job 1)')
CODIGO_ARCHIVO('06_BigData_Hadoop/mapreduce/src/pe/olva/bigdata/PermanenciaMapper.java')
SUBT('PermanenciaReducer.java (Reducer del Job 1)')
CODIGO_ARCHIVO('06_BigData_Hadoop/mapreduce/src/pe/olva/bigdata/PermanenciaReducer.java')
SUBT('OlvaBigDataDriver.java (Driver que configura y encadena los tres jobs)')
CODIGO_ARCHIVO('06_BigData_Hadoop/mapreduce/src/pe/olva/bigdata/OlvaBigDataDriver.java')
TXT('**Compilación y ejecución.** `compilar.sh` compila con `javac --release 8` (el bytecode que ejecuta el clúster) '
    'y genera el JAR; `02_ejecutar_mapreduce.sh` lanza el Driver y descarga los resultados:')
CODIGO('''$ bash 06_BigData_Hadoop/mapreduce/compilar.sh
hadoop@Hans:~$ hadoop jar /mnt/g/PROYECTO_GRUPO_10/06_BigData_Hadoop/mapreduce/olva-bigdata.jar \\
               /olva/raw /olva/resultados''')
FIGURA('hd_mapreduce_1', 'Ejecución del Job 1 en YARN: 3 152 418 líneas leídas y 525 751 estancias reconstruidas',
       F_HADOOP, 'Los contadores muestran el embudo del job: de 3 152 418 líneas, el Mapper emite 1 648 464 eventos de hub, '
       'agrupados en 298 686 envíos; el Reducer reconstruye 525 751 estancias en hubs de clasificación (contador propio '
       '`ESTANCIAS_EN_HUB`) y las emite en tres dimensiones (1 577 253 registros).', ancho_cm=15.5)
FIGURA('hd_mapreduce_2', 'Ejecución de los Jobs 2 y 3: 318 indicadores de permanencia y 140 de cumplimiento del SLA',
       F_HADOOP, 'El Job 2 reduce 1 577 253 registros a 318 indicadores, y el Job 3 procesa los 299 667 envíos y produce '
       '140 indicadores. La cadena completa tardó 99 segundos.', ancho_cm=12)
FIGURA('hd_web_yarn_apps', 'Consola de YARN: los seis jobs ejecutados terminaron con estado SUCCEEDED', F_WEB_YARN,
       'Los jobs 1 a 3 corresponden al análisis del conjunto masivo y los jobs 4 a 6 al reproceso de la base operativa '
       'extraída de PostgreSQL (punto 14).', ancho_cm=15.5)
FIGURA('hd_web_job', 'JobHistory: resumen del Job 1 (tres tareas map y cuatro reduce, 26 segundos)', F_WEB_JH, ancho_cm=15.5)
FIGURA('hd_web_contadores', 'JobHistory: contadores del framework y contadores propios del grupo OLVA del Job 1',
       F_WEB_JH, 'Los contadores propios (`ESTANCIAS_EN_HUB` y `EVENTOS_HUB_LEIDOS`) permiten auditar el resultado: los '
       '1 648 464 eventos leídos por el Mapper coinciden con los que recibe el Reducer.', ancho_cm=13)

H2('13.5 Respuesta a la Pregunta Analítica Principal')
TXT('**Pregunta:** "Utilizando Hadoop/MapReduce, procese el conjunto de datos masivo generado por su proyecto y '
    'determine un patrón, indicador o comportamiento relevante para la toma de decisiones."')
TXT('**Respuesta:** procesados los 3 152 417 eventos y 299 667 envíos, el patrón más relevante es que **la permanencia '
    'de los paquetes se concentra en la franja nocturna del Hub Central Lima (HC-LIM)**. A las 20:00 llega el 35,8 % de '
    'todos sus paquetes (102 570 de 286 604 estancias) y permanecen en promedio **14,57 horas**; lo que llega entre '
    'las 18:00 y las 02:00 permanece 14,44 h, frente a 10,09 h de lo que llega entre las 08:00 y las 18:00 '
    '(**43 % más**).')
FIGURA('hd_resultados_hora', 'Permanencia en el Hub Central Lima por hora de llegada y por día de la semana',
       F_HADOOP, 'Cada línea es: dimensión, hub, hora, estancias, horas promedio y porcentaje de estancias de más de '
       '12 horas. Las franjas de las 20:00 y las 14:00 concentran el volumen; el lunes tiene la mayor permanencia '
       '(13,65 h) por el acumulado del fin de semana.', ancho_cm=15)
TXT('El mismo análisis revela otros dos comportamientos:')
VIN('**Estacionalidad en Arequipa:** el Hub Regional Arequipa pasa de 10,35 h de permanencia promedio entre abril y '
    'junio a 12,44 h en agosto y septiembre (**+20 %**), y las estancias de más de 12 horas suben del 32,31 % al '
    '46,10 %.',
    '**Impacto en el plazo de entrega:** los servicios aéreos son los que menos cumplen (Sobre Aéreo 86,68 % y Express '
    'Aéreo 86,88 %) porque prometen 24 a 48 horas y cualquier noche en el Hub Central consume ese margen; el Económico '
    'Terrestre cumple el 98,84 %. Las rutas con peor cumplimiento son las del servicio Estándar Terrestre que salen '
    'del Sur hacia el Oriente (39,80 %), el Norte (41,29 %) y el Centro (41,78 %), porque todas atraviesan el Hub '
    'Central.')
FIGURA('hd_resultados_mes', 'Permanencia mensual del Hub Regional Arequipa y franjas con más llegadas de toda la red',
       F_HADOOP, 'Agosto (12,49 h) y septiembre (12,39 h) destacan sobre el resto de meses. En toda la red, la franja '
       'HC-LIM de las 20:00 tiene casi diez veces más llegadas que la siguiente franja de otro hub (HR-HYO a las 20:00).',
       ancho_cm=14.5)
FIGURA('hd_resultados_sla', 'Cumplimiento del SLA por servicio, rutas con menor cumplimiento y evolución mensual',
       F_HADOOP, 'Formato: dimensión, clave, detalle, envíos, entregados, % de cumplimiento, retraso promedio de los '
       'tardíos en horas e ingresos en soles. Julio es el mes de mayor volumen (60 694 envíos) y aun así mantiene un '
       '91,28 % de cumplimiento.', ancho_cm=15.5)
FIGURA('hd_web_resultados', 'Explorador de HDFS: archivo de resultados permanencia_hub replicado en los dos DataNodes',
       F_WEB_HDFS, ancho_cm=14)

H2('13.6 Interpretación analítica y conclusiones del análisis Big Data')
VIN('**El cuello de botella es de horario, no de capacidad total.** El Hub Central no está saturado todo el día: entre '
    'las 10:00 y las 12:00 la permanencia baja a 6–7 h. El problema es que los despachos de las agencias de Lima '
    '(19:30) y de provincias (20:00) llegan juntos y esperan a la salida troncal de las 23:30 o a la del día siguiente.',
    '**La noche en el Hub Central explica la mayor parte de los incumplimientos aéreos.** Un paquete aéreo que llega a '
    'las 20:00 y espera 14,6 h pierde la salida de la mañana; por eso el servicio más caro cumple menos que el más '
    'barato.',
    '**Arequipa necesita un refuerzo estacional,** no permanente: fuera de agosto y septiembre su permanencia es '
    'similar a la de otros hubs regionales.',
    '**El resultado es reproducible y verificable.** La base operativa de 30 mil envíos, procesada con el mismo JAR, '
    'da los mismos porcentajes por servicio (por ejemplo, Estándar Terrestre 91,88 % en ambos conjuntos), lo que '
    'confirma que el patrón no depende del tamaño de la muestra.',
    '**Hadoop redujo el problema a un tamaño manejable:** 3,15 millones de eventos (180,9 MB) se convirtieron en 458 '
    'indicadores de unos pocos kilobytes, que ya se pueden consultar en línea desde las bases operacionales.')

# =====================================================================
H1('14. INTEGRACIÓN DE LA SOLUCIÓN')
H2('14.1 Flujo de datos e integración arquitectónica end-to-end')
TXT('La solución se organiza en tres capas (Figura 62). La **capa operacional** registra la actividad en línea: '
    'PostgreSQL es la fuente de verdad transaccional, Oracle guarda la implementación comparativa, MongoDB el '
    'expediente de cada envío y Cassandra la bitácora de escaneos. La **capa Big Data** recibe copias de los datos en '
    'HDFS y los procesa con MapReduce. La **capa de consumo** devuelve los indicadores a los motores que usan los '
    'usuarios.')
FIGURA('06_integracion_end_to_end', 'Flujo de datos end-to-end entre PostgreSQL, Oracle, MongoDB, Cassandra y Hadoop',
       'elaboración propia.')
TXT('El script `03_integracion_end_to_end.sh` automatiza el flujo en cuatro pasos, que se ejecutan con un solo comando '
    '(`00_ejecutar_todo.sh` ejecuta además la generación, la compilación y la carga):')
VIN('**① Extracción:** exporta de PostgreSQL los catálogos (`maestro.*`), los envíos y los eventos con `COPY ... TO '
    'STDOUT` y los escribe directamente en HDFS (`/olva/operacional/<fecha>`), sin archivos intermedios.',
    '**② Procesamiento:** ejecuta el mismo JAR MapReduce sobre lo extraído.',
    '**③ Carga:** publica los indicadores del conjunto masivo en PostgreSQL (esquema `analitica`), MongoDB '
    '(colección `kpi_bigdata`) y Cassandra (tablas `kpi_permanencia_hub` y `kpi_cumplimiento_sla`). La carga es '
    'idempotente: puede repetirse sin duplicar datos.',
    '**④ Verificación:** consulta el mismo indicador en los tres motores y comprueba que coincide.')
FIGURA('int_extraccion', 'Pasos 1 y 2 del flujo: extracción de PostgreSQL a HDFS y reproceso con MapReduce', F_BASH,
       'Se exportaron 29 966 envíos y 315 101 eventos (más la línea de cabecera de cada archivo) y se reprocesaron en '
       'tres jobs. El cumplimiento por servicio de la base operativa coincide con el del conjunto masivo.',
       ancho_cm=15.5)
FIGURA('int_verificacion', 'Paso 4 del flujo: el mismo indicador leído desde PostgreSQL, MongoDB y Cassandra', F_BASH,
       'Los tres motores devuelven 102 570 estancias y 14,57 h para el Hub Central a las 20:00: la integración no '
       'pierde ni altera datos.', ancho_cm=12)

H2('14.2 Mecanismo de coexistencia entre PostgreSQL, Oracle, MongoDB, Cassandra y Hadoop')
TXT('Los cinco motores no compiten por los mismos datos: cada uno es **dueño** de un tipo de información y los demás '
    'reciben copias derivadas. Las reglas de coexistencia son:')
VIN('**Una sola fuente de verdad:** los datos transaccionales nacen y se corrigen solo en PostgreSQL. MongoDB, '
    'Cassandra y Hadoop reciben copias transformadas (documentos JSON, filas CQL o archivos CSV) y nunca las devuelven '
    'modificadas.',
    '**Claves comunes:** el número de tracking (`OLV26…`), el código de hub (`HC-LIM`, `HR-AQP`) y el código de '
    'servicio son iguales en todos los motores; por eso un indicador de Hadoop se puede unir con el maestro de hubs de '
    'PostgreSQL (vista `analitica.vw_franjas_criticas`) o leer junto al expediente en MongoDB.',
    '**Flujo en un solo sentido por tipo de dato:** operación → copias de consulta (MongoDB, Cassandra) → análisis '
    '(Hadoop) → indicadores (de vuelta a PostgreSQL, MongoDB y Cassandra). Los indicadores se reemplazan completos en '
    'cada ejecución, de modo que no hay conflictos de escritura.',
    '**Consistencia adecuada a cada uso:** ACID y 2PC en PostgreSQL para el dinero y los estados; consistencia '
    'ajustable (`LOCAL_ONE`, `EACH_QUORUM`) en Cassandra para los escaneos; y consistencia eventual de los indicadores, '
    'que se actualizan por lotes.',
    '**Oracle** coexiste como réplica parcial del núcleo relacional, para comparación y respaldo con Data Pump; no '
    'participa en el flujo Big Data.',
    '**Seguridad por motor:** cada carga respeta los roles existentes. El rol `rol_analista` de PostgreSQL y el de '
    'MongoDB obtuvieron permiso de lectura sobre los indicadores, y en Cassandra los indicadores viven en el keyspace '
    '`olva_tracking`, replicado en las dos sedes.')
FIGURA('pg_analitica', 'PostgreSQL: esquema analitica con los indicadores de Hadoop unidos al maestro de hubs', 'elaboración '
       'propia a partir de la ejecución en psql sobre la base olva_courier.',
       'La vista `vw_franjas_criticas` muestra la franja de mayor volumen de cada hub. Solo en el Hub Central la '
       'franja crítica supera las 12 horas de permanencia promedio (14,57 h).', ancho_cm=13.5)
FIGURA('mg_kpi', 'MongoDB: colección kpi_bigdata con 458 indicadores calculados por Hadoop', 'elaboración propia a '
       'partir de la ejecución en mongosh sobre la base olva_tracking.', ancho_cm=13.5)
FIGURA('cq_kpi', 'Cassandra: indicadores por hub (una partición por hub) y cumplimiento por servicio', 'elaboración '
       'propia a partir de la ejecución en cqlsh sobre el keyspace olva_tracking.',
       'La tabla `kpi_permanencia_hub` usa el hub como clave de partición: el panel de cada hub lee su información en una '
       'sola consulta, en cualquiera de las dos sedes.', ancho_cm=13.5)

H2('14.3 Tabla obligatoria de justificación tecnológica')
TABLA(['Tecnología', 'Rol en la solución', 'Datos que gestiona', 'Justificación técnica', 'Evidencia'],
      [['**PostgreSQL 16**', 'Base transaccional principal y fuente de verdad', 'Clientes, tarifas, rutas, envíos, '
        'despachos, comprobantes, auditoría; indicadores en `analitica`', 'ACID, integridad referencial (30 FK), '
        'PL/pgSQL, RBAC y RLS, respaldo verificado', 'Puntos 6 y 7; Fig. 65'],
       ['**PostgreSQL distribuido (postgres_fdw)**', 'Base distribuida en sedes Lima, Norte y Sur',
        'Fragmentos horizontales y verticales de envíos, eventos y clientes', 'Localidad de datos por sede, poda de '
        'fragmentos, 2PC para transacciones entre nodos', 'Punto 9'],
       ['**Oracle**', 'Implementación parcial y comparativa', '8 tablas del núcleo relacional', 'Contraste de '
        'PL/SQL frente a PL/pgSQL, PROFILE de seguridad, Data Pump', 'Punto 8'],
       ['**MongoDB 7**', 'Expediente documental del envío', '29 966 documentos con paquetes, tracking, intentos, '
        'incidencias y prueba de entrega; `kpi_bigdata`', 'Esquema flexible validado, lectura sin JOIN, índices '
        'geoespaciales, sharding por zonas', 'Punto 10; Fig. 66'],
       ['**Apache Cassandra 4.1**', 'Bitácora de escaneos y estados en línea', '8 tablas por consulta; indicadores '
        '`kpi_*` por hub', 'Escrituras masivas, alta disponibilidad, réplica en 2 centros de datos', 'Punto 11; Fig. 67'],
       ['**Apache Hadoop 3.3.6 (HDFS + MapReduce)**', 'Almacenamiento y procesamiento masivo por lotes',
        '5,64 millones de registros (3,15 millones de eventos)', 'Escalado horizontal, replicación de bloques, '
        'localidad de datos, análisis sin cargar la operación', 'Puntos 12 y 13; Fig. 42–61'],
       ['**Python 3.12 / Java 8 / Bash**', 'Generación, procesamiento e integración', 'Simulador, MapReduce y '
        'scripts de flujo', 'Datos reproducibles (semilla fija), API nativa de Hadoop, automatización', 'Puntos 12–14'],
       ['**Portal web (Python Flask + JavaScript)**', 'Capa de presentación para clientes y operación',
        'Ninguno propio: lee y escribe en los 5 motores', 'Un único punto de acceso; cada pantalla consulta el motor '
        'más adecuado; registro y réplica de envíos', 'Punto 14.4; Fig. 68–75']],
      [2.9, 2.9, 3.6, 4.1, 2.3],
      fuente='elaboración propia.')


H2('14.4 Portal web de envíos integrado con las cinco bases de datos')
TXT('Para demostrar la integración desde el punto de vista del usuario se desarrolló un **sitio web de envíos** '
    '(carpeta `07_Documentacion/portal_web`), construido con Python 3.12 y Flask en el servidor y HTML, CSS y JavaScript en el '
    'navegador. El sitio ofrece los servicios de un courier (rastrear, enviar, cotizar, consultar el historial del '
    'cliente, ubicar agencias y supervisar la operación) y cada pantalla consulta en vivo el motor que mejor responde a '
    'esa necesidad, siguiendo el reparto de funciones definido en el punto 14.2.')
TABLA(['Sección', 'Qué ofrece', 'Motor que la atiende y cómo'],
      [['Inicio', 'Buscador de tracking, servicios, accesos y cifras de la red', 'PostgreSQL: conteos y cumplimiento'],
       ['Rastrear', 'Estado, plazo, mapa del recorrido, historial, detalle y prueba de entrega',
        'PostgreSQL (envío, eventos, `fn_estado_sla`), MongoDB (hubs GeoJSON y prueba de entrega), Cassandra '
        '(`estado_envio` en línea)'],
       ['Enviar', 'Registro con precio en vivo y avance escaneo a escaneo hasta la entrega',
        'PostgreSQL (`sp_registrar_envio`, `sp_registrar_escaneo`, `sp_registrar_intento_entrega`) y réplica a '
        'Oracle, MongoDB, Cassandra y HDFS'],
       ['Cotizar', 'Precio, plazo y fecha estimada de los 4 servicios', 'PostgreSQL (`maestro.fn_calcular_tarifa`)'],
       ['Mi cuenta', 'Perfil e historial de envíos por DNI o RUC',
        'MongoDB (`clientes`, índice único por documento) y Cassandra (`envios_por_cliente`, una partición por '
        'cliente)'],
       ['Agencias', 'Mapa de la red y agencias más cercanas',
        'MongoDB (`hubs`, `$geoNear` sobre el índice `2dsphere`)'],
       ['Operaciones', 'Indicadores, gráficos y actividad de un hub por hora',
        'PostgreSQL (resumen), Hadoop/HDFS (indicadores MapReduce) y Cassandra (`escaneos_hub_hora`, '
        '`eventos_por_hub_dia`)'],
       ['Bases de datos', 'Estado de las cinco conexiones, 20 registros recientes de cada una y rastreo cruzado',
        'Las cinco, por la clave común `nro_tracking`']],
      [2.4, 5.6, 7.8], fuente='elaboración propia a partir del código de 07_Documentacion/portal_web.')
TXT('**Escritura y réplica.** Cuando un usuario registra un envío, el portal llama al procedimiento '
    '`sp_registrar_envio` de PostgreSQL, que valida las reglas del negocio, calcula la tarifa y el plazo, emite el '
    'comprobante y registra la admisión en una sola transacción. A continuación, el módulo `operaciones.py` lee el envío '
    'completo desde PostgreSQL y lo propaga: en Oracle inserta el envío y los eventos (su trigger actualiza el estado), '
    'en MongoDB reemplaza el documento del expediente, en Cassandra escribe las tablas de estado, eventos por envío, por '
    'hub y por cliente, y en HDFS crea el archivo `/olva/operacional/web/<tracking>.csv` mediante WebHDFS. Cada avance '
    'del envío (salida, llegada, clasificación, reparto y entrega) sigue el mismo camino: primero PostgreSQL, a través '
    'de sus procedimientos y triggers, y después la réplica, que informa en pantalla el resultado y el tiempo de cada '
    'motor. La ruta del paquete se calcula con el algoritmo de Dijkstra sobre la tabla `maestro.ruta`.')
CODIGO('''POST /api/envios                   -> sp_registrar_envio -> replicar(tracking)
POST /api/envios/<trk>/avanzar      -> sp_registrar_escaneo o sp_registrar_intento_entrega
                                       -> replicar(tracking)
GET  /api/seguimiento/<trk>         -> PostgreSQL + MongoDB (hubs, POD) + Cassandra (estado)
GET  /api/cotizar                   -> maestro.fn_calcular_tarifa (PostgreSQL)
GET  /api/cuenta/<documento>        -> MongoDB clientes + Cassandra envios_por_cliente
GET  /api/agencias?lat=&lon=        -> MongoDB $geoNear (índice 2dsphere)
GET  /api/operaciones               -> PostgreSQL + HDFS /olva/resultados (MapReduce)
GET  /api/hub/<hub>/actividad       -> Cassandra escaneos_hub_hora, eventos_por_hub_dia''')
TXT('Las credenciales de conexión se leen del archivo de configuración local del proyecto y no se incluyen en el '
    'código. Las figuras 68 a 75 muestran cada sección del sitio en funcionamiento.')
F_WEB = 'elaboración propia a partir del portal web en ejecución (http://localhost:5000).'
FIGURA('web_inicio', 'Portal web: página de inicio con buscador de envíos, servicios y accesos', F_WEB,
       'Las cifras de la cabecera (envíos gestionados, ciudades, agencias y porcentaje de entregas a tiempo) se '
       'calculan en el momento sobre PostgreSQL.', ancho_cm=15.5)
FIGURA('web_rastrear', 'Portal web: seguimiento de un envío con mapa del recorrido, historial y prueba de entrega',
       F_WEB, 'El recorrido Lima → Hub Central → Hub Arequipa → agencia se dibuja con las coordenadas GeoJSON de MongoDB; '
       'el estado y el plazo (`fn_estado_sla`) vienen de PostgreSQL y la línea de estado en línea de Cassandra. La '
       'sección "Origen de cada dato" indica qué motor aportó cada parte.', ancho_cm=15.5, alto_max_cm=20)
FIGURA('web_enviar', 'Portal web: registro de un envío y sincronización en las cinco bases', F_WEB,
       'Tras registrar el envío, el panel "Envío en curso" muestra el resultado de la réplica en cada motor con su '
       'tiempo de respuesta; los botones registran el siguiente escaneo o completan el recorrido.', ancho_cm=15.5)
FIGURA('web_cotizar', 'Portal web: cotizador de los cuatro servicios con precio, plazo y fecha estimada', F_WEB,
       'El Sobre Aéreo aparece no disponible porque el peso supera su máximo de 0,5 kg: es la misma validación que '
       'aplica la función de tarifa de PostgreSQL.', ancho_cm=15.5)
FIGURA('web_cuenta', 'Portal web: perfil del cliente (MongoDB) e historial de envíos (Cassandra)', F_WEB,
       'El historial se lee de una sola partición de `envios_por_cliente`, ya ordenado del envío más reciente al más '
       'antiguo por la clave de clustering.', ancho_cm=15.5)
FIGURA('web_agencias', 'Portal web: red de agencias y hubs en el mapa con búsqueda de la más cercana', F_WEB,
       'La búsqueda usa `$geoNear` sobre el índice `2dsphere` de la colección `hubs` y ordena las agencias por '
       'distancia.', ancho_cm=15.5)
FIGURA('web_operaciones', 'Portal web: panel de operaciones con indicadores de PostgreSQL, Hadoop y Cassandra', F_WEB,
       'El cumplimiento por servicio y las llegadas por hora al Hub Central provienen de los resultados de MapReduce '
       'en HDFS; la actividad de un hub en un día se consulta en Cassandra por su clave de partición (hub, día).',
       ancho_cm=15.5, alto_max_cm=20)
FIGURA('web_bases', 'Portal web: estado de las cinco conexiones, rastreo cruzado y registros de cada base', F_WEB,
       'Las cinco tarjetas confirman la conexión y el tiempo de respuesta de cada motor; el rastreo cruzado encuentra '
       'el mismo número de tracking en PostgreSQL, Oracle, MongoDB, Cassandra y HDFS.', ancho_cm=15.5)

# =====================================================================
H1('15. RESULTADOS')
H2('15.1 Logros alcanzados por módulo')
VIN('**Modelo relacional y PostgreSQL:** 20 tablas en tres esquemas, 30 claves foráneas, funciones, procedimientos, '
    'triggers de auditoría, roles con RLS y respaldos físicos y lógicos verificados; 29 966 envíos y 315 101 eventos '
    'cargados. Ahora también aloja el esquema `analitica` con 458 indicadores.',
    '**Oracle:** 8 tablas del núcleo implementadas con PL/SQL, PROFILE y Data Pump, comparadas con PostgreSQL.',
    '**Base distribuida:** tres nodos (Lima, Norte y Sur) con fragmentación horizontal y vertical, consultas '
    'distribuidas y transacciones 2PC.',
    '**MongoDB:** 29 966 expedientes en la colección `envios`, validación `$jsonSchema`, 12 índices, 2 vistas, 3 roles '
    'y dos sedes con sharding por zonas (23 638 envíos en Lima y 6 328 en Arequipa).',
    '**Cassandra:** 8 tablas diseñadas por consulta, carga masiva con `COPY`, operaciones LWT, BATCH, contadores y '
    'TTL, roles y réplica en dos centros de datos.',
    '**Big Data:** 5 640 511 registros generados y justificados, clúster Hadoop instalado (NameNode, 2 DataNodes, '
    'ResourceManager, NodeManager, JobHistory), 3 jobs MapReduce en 99 segundos y 458 indicadores integrados en tres '
    'motores.',
    '**Portal web:** sitio de envíos con 8 secciones conectado a los cinco motores; registra envíos y los lleva hasta '
    'la entrega con los procedimientos de PostgreSQL y los replica en Oracle, MongoDB, Cassandra y HDFS en menos de '
    'un segundo por motor.')
H2('15.2 Consultas y análisis más relevantes')
TABLA(['Motor', 'Consulta o análisis', 'Resultado'],
      [['PostgreSQL', 'Cumplimiento global del SLA sobre la base operativa', '91,4 % de 28 858 envíos entregados'],
       ['PostgreSQL', '`analitica.vw_franjas_criticas` (indicadores de Hadoop unidos a `maestro.hub`)',
        'HC-LIM 20:00: 35,79 % de sus llegadas, 14,57 h de permanencia'],
       ['MongoDB', 'Agregación de permanencia en el Hub Central por hora (`$setWindowFields`)',
        '10 344 llegadas a las 20:00 con 14,6 h de permanencia'],
       ['MongoDB', 'Plan de ejecución por sede (`explain`)', '`SINGLE_SHARD`: Lima o Arequipa responden solas'],
       ['Cassandra', 'Tracking de un envío por clave de partición', 'Una sola partición, ordenada por fecha'],
       ['Cassandra', 'Consulta con `LOCAL_ONE` sobre el keyspace local de Arequipa desde Lima',
        'Rechazada: el dato no sale de su sede'],
       ['Hadoop', 'Job 1 + Job 2: permanencia por hub, hora, mes y día', '525 751 estancias → 318 indicadores'],
       ['Hadoop', 'Job 3: cumplimiento del SLA por servicio y ruta', '299 667 envíos → 140 indicadores']],
      [2.4, 7.4, 6.0], fuente='elaboración propia a partir de los resultados de los puntos 6 a 14.')
H2('15.3 Hallazgos y patrones descubiertos')
VIN('**Saturación nocturna del Hub Central Lima:** el 35,8 % de sus llegadas ocurre a las 20:00 y la permanencia '
    'nocturna es 43 % mayor que la diurna (14,44 h frente a 10,09 h).',
    '**Efecto lunes:** el Hub Central tiene 13,65 h de permanencia promedio los lunes, frente a 12,15 h los martes.',
    '**Estacionalidad en Arequipa:** +20 % de permanencia en agosto y septiembre; las estancias de más de 12 h pasan '
    'del 32,31 % al 46,10 %.',
    '**Servicios aéreos con menor cumplimiento:** Sobre Aéreo 86,68 % y Express Aéreo 86,88 %, frente a 98,84 % del '
    'Económico Terrestre.',
    '**Rutas críticas:** Estándar Terrestre Sur → Oriente (39,80 %), Sur → Norte (41,29 %) y Sur → Centro (41,78 %).',
    '**Volumen e ingresos:** S/ 8 109 554,40 procesados; julio es el mes de mayor volumen (60 694 envíos) y mantiene '
    '91,28 % de cumplimiento.')
H2('15.4 Ventajas operativas de cada tecnología implementada')
VIN('**PostgreSQL:** integridad garantizada para el dinero y los estados, lógica de negocio dentro de la base y '
    'seguridad por filas.',
    '**PostgreSQL distribuido:** cada sede consulta sus datos en local y las transacciones entre sedes se confirman o '
    'cancelan juntas (2PC).',
    '**Oracle:** referencia comparativa y herramientas empresariales de respaldo (Data Pump).',
    '**MongoDB:** el seguimiento de un envío se responde leyendo un solo documento, y la distribución por sedes la '
    'gestiona el propio motor.',
    '**Cassandra:** acepta escrituras masivas de escaneos y sigue respondiendo aunque caiga una sede.',
    '**Hadoop:** analiza toda la historia sin afectar a la operación y escala agregando nodos; el mismo código sirve '
    'para 30 mil o 300 mil envíos.')
H2('15.5 Limitaciones identificadas en la arquitectura')
VIN('**Clúster en una sola máquina:** Hadoop funciona en modo pseudo-distribuido; los dos DataNodes replican los '
    'bloques, pero comparten el mismo disco y equipo, por lo que no protegen ante una falla del hardware.',
    '**Seguridad de Hadoop básica:** no se configuró Kerberos y los permisos de HDFS están desactivados; es aceptable '
    'en laboratorio, no en producción.',
    '**Procesamiento por lotes:** MapReduce tarda alrededor de 100 segundos y escribe en disco entre fases; no sirve '
    'para indicadores en tiempo real.',
    '**Integración por exportación completa:** el flujo vuelve a extraer todas las tablas en cada ejecución y se lanza '
    'manualmente; todavía no hay captura incremental de cambios ni un programador de tareas.',
    '**Datos sintéticos:** los patrones descubiertos reproducen los cuellos de botella inyectados en el simulador; '
    'validan el método de análisis, pero las cifras deben recalcularse con datos reales.',
    '**Oracle parcial:** solo implementa 8 tablas y no participa en el flujo Big Data.',
    '**Portal web de demostración:** la sección "Mi cuenta" identifica al cliente solo por su documento, sin '
    'contraseña, y la réplica entre motores es síncrona y sin cola de mensajes; en producción se requeriría '
    'autenticación y un mecanismo de réplica asíncrono con reintentos.')

# =====================================================================
H1('16. CONCLUSIONES')
VIN('**Vinculada al OE1 (modelo relacional normalizado):** se diseñó un modelo de 20 tablas normalizado que representa '
    'el ciclo de vida completo del envío. El mismo modelo soportó la base operativa (29 966 envíos y 315 101 eventos) y '
    'el conjunto masivo (299 667 envíos y 3 152 417 eventos) sin cambios de estructura, lo que demuestra que es '
    'correcto y escalable.',
    '**Vinculada al OE2 (implementación en PostgreSQL):** la implementación en PostgreSQL 16 integró 20 tablas, 30 '
    'claves foráneas, restricciones de negocio, funciones, procedimientos, triggers de auditoría, RBAC, RLS y '
    'respaldos físicos y lógicos verificados. Sobre ella se determinó un cumplimiento global del SLA del 91,4 % y se '
    'identificó al Hub Central Lima como el principal cuello de botella por saturación horaria.',
    '**Vinculada al OE3 (Oracle y comparación):** la implementación parcial en Oracle 26ai (8 tablas) permitió '
    'contrastar ambas arquitecturas; PostgreSQL destacó por características nativas como JSONB, RLS, índices parciales '
    'y la extensión postgres_fdw, que luego hizo posible la base distribuida.',
    '**Vinculada al OE4 (base distribuida):** la distribución en tres nodos (Lima, Norte y Sur) con fragmentación '
    'horizontal y vertical mediante postgres_fdw optimizó las consultas con poda de fragmentos y ejecución remota '
    'asíncrona, y el protocolo 2PC garantizó la atomicidad de las transacciones entre nodos. MongoDB y Cassandra '
    'extendieron el mismo principio a dos sedes: 23 638 envíos en Lima y 6 328 en Arequipa respondidos por una sola '
    'sede, y la bitácora de escaneos disponible aunque una sede falle.',
    '**Vinculada al objetivo general (identificar cuellos de botella):** el análisis con Hadoop sobre 3 152 417 '
    'eventos, ejecutado en 99 segundos, cuantificó el cuello de botella: el 35,8 % de las llegadas al Hub Central '
    'ocurre a las 20:00, con 14,57 h de permanencia promedio, un 43 % más que en el turno diurno; además, el Hub '
    'Arequipa aumenta su permanencia un 20 % en agosto y septiembre.',
    '**Vinculada al objetivo general (evaluar el cumplimiento de los plazos):** el cumplimiento del SLA varía del '
    '86,68 % (Sobre Aéreo) al 98,84 % (Económico Terrestre) y cae al 39,80 % en la ruta Estándar Terrestre Sur → '
    'Oriente. La integración end-to-end dejó estos 458 indicadores disponibles, con el mismo valor, en PostgreSQL, '
    'MongoDB y Cassandra para la toma de decisiones.')

H1('17. RECOMENDACIONES')
VIN('**Escalonar la llegada nocturna al Hub Central Lima (gestión operativa):** adelantar parte de los despachos de las '
    'agencias de Lima de las 19:30 a las 17:00 y reforzar la clasificación entre las 18:00 y las 02:00. El indicador '
    'objetivo es bajar la permanencia de la franja de las 20:00 de 14,57 h a menos de 12 h, lo que debería elevar el '
    'cumplimiento de los servicios aéreos por encima del 90 %.',
    '**Plan de personal estacional en Arequipa (gestión):** programar personal adicional en el Hub Regional Arequipa '
    'para agosto y septiembre, cuando la permanencia sube un 20 %, y medir el efecto con el mismo indicador mensual.',
    '**Revisar la promesa de plazo en las rutas críticas (negocio):** para Estándar Terrestre desde el Sur hacia el '
    'Oriente, el Norte y el Centro (40–42 % de cumplimiento), ajustar el plazo comprometido o crear una ruta troncal que '
    'no pase por el Hub Central.',
    '**Automatizar e incrementalizar la integración (arquitectura):** programar el flujo cada noche (cron o Apache '
    'Airflow) y reemplazar la exportación completa por captura de cambios (CDC, por ejemplo con Debezium), de modo que '
    'HDFS reciba solo los eventos nuevos.',
    '**Llevar Hadoop a un clúster real y seguro (arquitectura):** distribuir los DataNodes en máquinas distintas, '
    'activar Kerberos y los permisos de HDFS, y evaluar Apache Spark sobre el mismo HDFS para obtener los indicadores en '
    'minutos en lugar de lotes nocturnos.',
    '**Tablero de gestión sobre el esquema analitica (gestión):** publicar los indicadores de `analitica` en un tablero '
    'para supervisores y jefes de hub, con alertas cuando una franja supere las 12 horas de permanencia.')

H1('18. REFERENCIAS BIBLIOGRÁFICAS')
TXT('**Bibliografía base**')
REF('Dean, J., & Ghemawat, S. (2008). MapReduce: Simplified data processing on large clusters. *Communications of the '
    'ACM, 51*(1), 107–113. https://doi.org/10.1145/1327452.1327492')
REF('Elmasri, R., & Navathe, S. B. (2016). *Fundamentals of database systems* (7th ed.). Pearson.')
REF('Lakshman, A., & Malik, P. (2010). Cassandra: A decentralized structured storage system. *ACM SIGOPS Operating '
    'Systems Review, 44*(2), 35–40. https://doi.org/10.1145/1773912.1773922')
REF('Özsu, M. T., & Valduriez, P. (2020). *Principles of distributed database systems* (4th ed.). Springer. '
    'https://doi.org/10.1007/978-3-030-26253-2')
REF('Sadalage, P. J., & Fowler, M. (2012). *NoSQL distilled: A brief guide to the emerging world of polyglot '
    'persistence*. Addison-Wesley.')
REF('Shvachko, K., Kuang, H., Radia, S., & Chansler, R. (2010). The Hadoop distributed file system. En *2010 IEEE 26th '
    'Symposium on Mass Storage Systems and Technologies (MSST)* (pp. 1–10). IEEE. https://doi.org/10.1109/MSST.2010.5496972')
REF('Silberschatz, A., Korth, H. F., & Sudarshan, S. (2020). *Database system concepts* (7th ed.). McGraw-Hill.')
REF('White, T. (2015). *Hadoop: The definitive guide* (4th ed.). O\'Reilly Media.')
TXT('**Documentación oficial de los motores y herramientas**')
REF('Apache Software Foundation. (2023a). *Apache Hadoop 3.3.6 documentation*. https://hadoop.apache.org/docs/r3.3.6/')
REF('Apache Software Foundation. (2023b). *HDFS architecture*. https://hadoop.apache.org/docs/r3.3.6/hadoop-project-dist/hadoop-hdfs/HdfsDesign.html')
REF('Apache Software Foundation. (2023c). *MapReduce tutorial*. https://hadoop.apache.org/docs/r3.3.6/hadoop-mapreduce-client/hadoop-mapreduce-client-core/MapReduceTutorial.html')
REF('Apache Software Foundation. (2023d). *Apache Cassandra 4.1 documentation*. https://cassandra.apache.org/doc/4.1/')
REF('Microsoft. (2025). *Windows Subsystem for Linux documentation*. https://learn.microsoft.com/windows/wsl/')
REF('MongoDB, Inc. (2024). *MongoDB manual (version 7.0)*. https://www.mongodb.com/docs/v7.0/')
REF('Oracle Corporation. (2025). *Oracle Database documentation*. https://docs.oracle.com/en/database/')
REF('PostgreSQL Global Development Group. (2024). *PostgreSQL 16 documentation*. https://www.postgresql.org/docs/16/')
REF('Python Software Foundation. (2023). *Python 3.12 documentation*. https://docs.python.org/3.12/')
TXT('**Fuentes de datos y herramientas de apoyo**')
REF('Instituto Nacional de Estadística e Informática. (s. f.). *Códigos de ubicación geográfica (ubigeo)*. '
    'https://www.inei.gob.pe/')
REF('Olva Courier. (s. f.). *Olva Courier: cobertura y servicios* [Sitio web]. https://www.olvacourier.com/')
REF('Anthropic. (2026). *Claude* (Opus 5.5) [Modelo de lenguaje de gran tamaño]. https://claude.ai/ — usado como '
    'asistente para la programación de scripts, la verificación de resultados y la redacción técnica; todas las cifras '
    'del informe provienen de ejecuciones reales del proyecto.')
