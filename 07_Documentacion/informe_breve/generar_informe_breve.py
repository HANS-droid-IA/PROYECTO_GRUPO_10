"""
Informe breve (máx. 15 páginas, sin capturas) de las bases de datos del proyecto y su implementación.
Todas las cifras provienen de las ejecuciones reales documentadas en el informe principal.
Uso: python generar_informe_breve.py   ->   Informe_Breve_BDII_Olva_Courier.docx
"""
import pathlib

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

SALIDA = pathlib.Path(__file__).with_name('Informe_Breve_BDII_Olva_Courier.docx')
AZUL = RGBColor(0x0F, 0x2B, 0x4C)

doc = Document()
sec = doc.sections[0]
sec.page_width, sec.page_height = Cm(21), Cm(29.7)
for lado in ('left_margin', 'right_margin'):
    setattr(sec, lado, Cm(2.5))
sec.top_margin = sec.bottom_margin = Cm(2.2)

normal = doc.styles['Normal']
normal.font.name = 'Arial'
normal.font.size = Pt(11)
normal.element.rPr.rFonts.set(qn('w:eastAsia'), 'Arial')
normal.paragraph_format.space_after = Pt(5)
normal.paragraph_format.line_spacing = 1.25
for nivel, tam in ((1, 14), (2, 11.5)):
    st = doc.styles[f'Heading {nivel}']
    st.font.name, st.font.size, st.font.bold, st.font.color.rgb = 'Arial', Pt(tam), True, AZUL
    st.element.rPr.rFonts.set(qn('w:eastAsia'), 'Arial')
    st.paragraph_format.space_before = Pt(12 if nivel == 1 else 8)
    st.paragraph_format.space_after = Pt(4)
    st.paragraph_format.keep_with_next = True

# número de página en el pie
pie = sec.footer.paragraphs[0]
pie.alignment = WD_ALIGN_PARAGRAPH.CENTER
for tipo, texto in (('begin', None), (None, 'PAGE'), ('end', None)):
    r = pie.add_run()
    if tipo:
        fc = OxmlElement('w:fldChar'); fc.set(qn('w:fldCharType'), tipo); r._r.append(fc)
    else:
        it = OxmlElement('w:instrText'); it.text = texto; r._r.append(it)
for r in pie.runs:
    r.font.size = Pt(9)


def texto(p, t):
    """Escribe t en el párrafo p admitiendo **negrita** y `código`."""
    import re
    for parte in re.split(r'(\*\*[^*]+\*\*|`[^`]+`)', t):
        if not parte:
            continue
        if parte.startswith('**'):
            p.add_run(parte[2:-2]).bold = True
        elif parte.startswith('`'):
            r = p.add_run(parte[1:-1]); r.font.name = 'Consolas'; r.font.size = Pt(9.5)
        else:
            p.add_run(parte)
    return p


def H1(t):
    doc.add_heading(t, level=1)


def H2(t):
    doc.add_heading(t, level=2)


def P(t):
    p = texto(doc.add_paragraph(), t)
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY


def V(*items):
    for t in items:
        p = texto(doc.add_paragraph(style='List Bullet'), t)
        p.paragraph_format.space_after = Pt(2)
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY


def T(cab, filas, anchos):
    tb = doc.add_table(rows=1, cols=len(cab))
    tb.style = 'Table Grid'
    tb.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, c in enumerate(cab):
        cel = tb.rows[0].cells[i]
        cel.text = ''
        r = cel.paragraphs[0].add_run(c); r.bold = True; r.font.size = Pt(9)
        sh = OxmlElement('w:shd'); sh.set(qn('w:val'), 'clear'); sh.set(qn('w:fill'), 'D9E2F3')
        cel._tc.get_or_add_tcPr().append(sh)
    for fila in filas:
        celdas = tb.add_row().cells
        for i, v in enumerate(fila):
            celdas[i].text = ''
            texto(celdas[i].paragraphs[0], v)
            for r in celdas[i].paragraphs[0].runs:
                r.font.size = Pt(9)
    for fila in tb.rows:
        for i, w in enumerate(anchos):
            fila.cells[i].width = Cm(w)
        for c in fila.cells:
            c.paragraphs[0].paragraph_format.space_after = Pt(1)
            c.paragraphs[0].paragraph_format.line_spacing = 1.0
    trpr = tb.rows[0]._tr.get_or_add_trPr()
    th = OxmlElement('w:tblHeader'); trpr.append(th)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


# ===================================================================== portada
for _ in range(5):
    doc.add_paragraph()
for t, tam, neg in (('UNIVERSIDAD', 12, False), ('BASE DE DATOS II – PROYECTO FINAL', 13, True), ('', 10, False),
                    ('Trazabilidad de paquetería y courier aéreo/terrestre', 18, True),
                    ('Caso de estudio: Olva Courier (Perú)', 13, False), ('', 10, False),
                    ('INFORME BREVE DE LAS BASES DE DATOS Y SU IMPLEMENTACIÓN', 12, True), ('', 10, False),
                    ('PostgreSQL · Oracle · Base distribuida · MongoDB · Apache Cassandra · Apache Hadoop', 11, False)):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(t); r.font.size = Pt(tam); r.bold = neg; r.font.color.rgb = AZUL
for _ in range(6):
    doc.add_paragraph()
p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.add_run('Grupo 10\nAlvarado Canchihuaman, Hans Piero (U24306153)\nSayas Reginaldo, Zinedine Claver (U24319637)\n\n'
          'Docente: America Ingrid Acuña Gomez\nLima, noviembre de 2026').font.size = Pt(11)
doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)

# ===================================================================== 1
H1('1. Introducción')
P('El proyecto resuelve la **falta de trazabilidad unificada** de un courier nacional que mueve envíos por vía aérea y '
  'terrestre entre agencias, hubs regionales y un hub central. Se tomó como referencia la operación pública de Olva '
  'Courier; todos los registros son **sintéticos**, generados por un simulador propio en Python con semilla fija, y no '
  'corresponden a información interna de la empresa.')
P('La red modelada tiene 5 macrorregiones, 17 ciudades con código de ubigeo real, 1 hub central (Callao), 8 hubs '
  'regionales, 29 agencias, 98 rutas y 4 servicios: Express Aéreo y Sobre Aéreo (48 h), Estándar Terrestre (72 h) y '
  'Económico Terrestre (120 h). El periodo simulado va del 1 de abril al 7 de octubre de 2026.')
P('**Objetivo:** diseñar e implementar una solución de bases de datos que permita seguir cada envío, identificar los '
  'cuellos de botella de la red y evaluar el cumplimiento de los plazos de entrega (SLA). La solución combina cinco '
  'tecnologías; cada una se usa para el tipo de dato que mejor maneja.')

H1('2. Arquitectura general de la solución')
T(['Tecnología', 'Rol', 'Datos que gestiona', 'Volumen'],
  [['PostgreSQL 16', 'Base transaccional, fuente de verdad', 'Clientes, tarifas, rutas, envíos, despachos, eventos, comprobantes', '29 966 envíos · 315 101 eventos'],
   ['Oracle (26ai Free)', 'Implementación parcial y comparativa', 'Núcleo relacional (8 tablas)', '1 000 envíos'],
   ['PostgreSQL distribuido', 'Datos repartidos por sede', 'Fragmentos de envíos, paquetes, eventos y clientes', '3 nodos: Lima, Norte, Sur'],
   ['MongoDB 7', 'Expediente documental del envío', 'Envío con paquetes, tracking, intentos y prueba de entrega embebidos', '29 966 documentos · 2 sedes'],
   ['Apache Cassandra 4.1', 'Bitácora de escaneos y estado en línea', '8 tablas diseñadas por consulta', 'Réplica en 2 centros de datos'],
   ['Apache Hadoop 3.3.6', 'Almacenamiento y análisis masivo', 'Conjunto masivo de eventos y envíos', '5 640 511 registros'],
   ['Portal web (Flask)', 'Acceso de clientes y operación', 'Ninguno propio: usa los cinco motores', '8 secciones']],
  [3.0, 3.6, 5.6, 3.8])
P('**Por qué no un solo motor.** La operación diaria necesita transacciones cortas y consistentes (ACID, claves '
  'foráneas): eso lo resuelve PostgreSQL. El expediente de cada envío tiene forma variable y se consulta completo: se '
  'adapta mejor a un documento (MongoDB). Los escaneos son una serie de tiempo de escritura masiva que debe seguir '
  'disponible aunque falle una sede (Cassandra). El análisis histórico recorre millones de filas y no debe competir con '
  'la operación (Hadoop). Todos comparten las mismas claves (número de tracking, código de hub y de servicio), lo que '
  'permite integrarlos.')

# ===================================================================== 3
H1('3. Modelo relacional e implementación en PostgreSQL')
H2('3.1 Modelo de datos')
P('El modelo tiene **18 entidades de negocio** más tablas de auditoría y seguridad, normalizadas hasta **3FN**. Los '
  'catálogos son región, ciudad, hub (jerarquía recursiva agencia → hub regional → hub central), tipo de servicio, '
  'tarifa, ruta, vehículo, empleado y cliente; la operación comprende destinatario, envío, paquete (entidad débil), '
  'comprobante, despacho, despacho_envio, evento_tracking, intento_entrega e incidencia. Se aceptaron dos '
  'desnormalizaciones controladas: `estado_actual` y `fecha_entrega` del envío (actualizados por trigger porque se '
  'consultan en cada rastreo) y `monto_total` (hecho histórico que no se recalcula si cambia la tarifa).')
H2('3.2 Implementación')
V('**Base olva_courier** (PostgreSQL 16, UTF8, zona America/Lima) organizada en cuatro esquemas: `maestro` (9 '
  'catálogos), `operacion` (9 tablas transaccionales), `auditoria` y `seguridad`.',
  '**Integridad:** 20 tablas, 30 claves foráneas, claves primarias por identidad y restricciones CHECK de dominio '
  '(expresiones regulares para tracking, DNI, RUC, placa y serie) y de negocio.',
  '**Carga:** 18 archivos CSV del simulador, que calcula rutas con Dijkstra, consolida envíos en despachos con capacidad '
  'y horario y aplica congestión en los hubs.',
  '**Consultas:** 13 consultas de negocio con JOIN, funciones de ventana (LAG, LEAD, RANK), ROLLUP, LATERAL, CTE, '
  'vista materializada e índice parcial; se ejecutan juntas en 1,5 s.')
H2('3.3 Programación almacenada')
T(['Objeto', 'Función'],
  [['`fn_calcular_tarifa`', 'Tarifa vigente: precio base + kilos adicionales según servicio y regiones'],
   ['`fn_estado_sla`', 'Clasifica el envío: a tiempo, con retraso, en plazo, en riesgo, vencido o devuelto'],
   ['`fn_permanencia_hub`, `fn_cuellos_botella`', 'Permanencia en hubs con LEAD() en una sola pasada'],
   ['`sp_registrar_envio`', 'Registra destinatario, envío, paquetes (JSONB), comprobante y admisión en una transacción'],
   ['`sp_registrar_escaneo`', 'Máquina de estados del envío con bloqueo FOR UPDATE'],
   ['`sp_registrar_intento_entrega`, `sp_cerrar_despacho`', 'Entrega (máx. 3 intentos, devolución) y cierre de manifiestos'],
   ['3 triggers', 'Estado del envío por evento, auditoría de cambios de estado y validación de despachos']],
  [6.0, 10.0])
H2('3.4 Seguridad y respaldo')
V('**5 roles de grupo** (administrador, operador de hub, atención al cliente, facturación y analista) y **7 usuarios**; '
  'se revocaron los privilegios de PUBLIC.',
  '**4 medidas de control:** permisos por columna (el operador no ve montos), escritura solo mediante procedimientos '
  'SECURITY DEFINER, vistas sin datos personales para el analista y **Row Level Security** sobre envíos y eventos.',
  '**Respaldo verificado:** lógico con `pg_dump` (7,7 MB), de roles con `pg_dumpall --globals-only` y físico con '
  '`pg_basebackup` (28 MB); se simuló el borrado de 1 904 incidencias y se recuperaron con `pg_restore` selectivo.')
P('**Resultado principal:** el cumplimiento global del plazo es **91,4 %**. El Hub Central Lima recibe a las 20:00 '
  '54,8 envíos por hora frente a una capacidad de 50 (110 %); cuando un envío aéreo permanece más de 12 h en ese hub, su '
  'cumplimiento cae de 88,7 % a 81,0 %.')

# ===================================================================== 4
H1('4. Implementación parcial en Oracle')
P('En la base conectable `FREEPDB1` (esquema OLVA) se implementaron **8 tablas de negocio** (región, ciudad, hub, '
  'tipo de servicio, tarifa, cliente, envío y evento_tracking) y una bitácora de errores, con PK, FK (incluida la '
  'recursiva de hub), UNIQUE y CHECK con `REGEXP_LIKE`. La lógica se agrupó en el paquete `pkg_tracking` '
  '(tarifa, estado del SLA y registro de escaneos), un trigger de estado y un procedimiento con '
  '`PRAGMA AUTONOMOUS_TRANSACTION`. La seguridad usa PROFILE (bloqueo por intentos fallidos) y el respaldo, Data Pump.')
T(['Concepto', 'PostgreSQL / PL/pgSQL', 'Oracle / PL/SQL'],
  [['Organización', 'Funciones y procedimientos en esquemas', 'PACKAGE con especificación y cuerpo'],
   ['Errores', 'RAISE EXCEPTION ... USING ERRCODE', 'RAISE_APPLICATION_ERROR(-20010, ...)'],
   ['Transacción autónoma', 'No nativa', 'PRAGMA AUTONOMOUS_TRANSACTION'],
   ['Jerarquía / upsert', 'WITH RECURSIVE, ON CONFLICT', 'CONNECT BY, MERGE'],
   ['Cadena vacía', "'' es distinto de NULL", "'' se interpreta como NULL"],
   ['Seguridad', 'Roles, RLS, GRANT por columna', 'Usuarios = esquemas, PROFILE, VPD'],
   ['Respaldo', 'pg_dump, pg_basebackup', 'Data Pump, RMAN']],
  [3.4, 6.3, 6.3])
P('El modelo resultó portable: tablas, restricciones e indicadores coinciden en ambos motores. PostgreSQL destacó por '
  'JSONB, RLS, índices parciales y `postgres_fdw`, que habilitó la base distribuida; Oracle, por sus paquetes, '
  'transacciones autónomas y herramientas empresariales de respaldo.')

# ===================================================================== 5
H1('5. Base de datos distribuida')
P('Cada escaneo ocurre en una sede física; distribuir por sede permite escribir localmente (el 38,5 % de los eventos '
  'deja de escribirse en Lima). Se implementaron **tres nodos PostgreSQL**: LIMA (regiones Lima y Centro, además '
  'coordinador), NORTE (Norte y Oriente) y SUR. El coordinador usa `postgres_fdw` para ver las tablas remotas como '
  'particiones de un esquema global.')
T(['Fragmento', 'Definición', 'Ubicación'],
  [['HF1 envío', 'Horizontal: nodo del hub de origen', 'LIMA / NORTE / SUR'],
   ['HF2 paquete', 'Derivada del envío (mantiene local la FK)', 'Mismo nodo que el envío'],
   ['HF3 evento_tracking', 'Horizontal: nodo del hub donde ocurre el escaneo', 'LIMA / NORTE / SUR'],
   ['VF1 cliente_fiscal', 'Vertical: datos tributarios', 'Solo LIMA'],
   ['VF2 cliente_contacto', 'Vertical + horizontal por ciudad', 'LIMA / NORTE / SUR'],
   ['Catálogos', 'Región, ciudad, hub, servicio, tarifa, ruta', 'Réplica total en los 3 nodos']],
  [4.0, 7.0, 5.0])
V('**Corrección verificada:** completitud (29 966 envíos y 315 101 eventos en origen y fragmentos), disyunción (0 '
  'claves repetidas) y reconstrucción (0 filas distintas con EXCEPT en ambos sentidos).',
  '**Consultas distribuidas:** la consulta global se poda a los fragmentos necesarios y se envía a cada nodo la '
  'selección, el JOIN y la agregación, con lecturas asíncronas.',
  '**Transacciones 2PC:** como `postgres_fdw` confirma los nodos uno a uno, se implementó el protocolo de dos fases con '
  '`PREPARE TRANSACTION`, `COMMIT PREPARED` y `ROLLBACK PREPARED`, probado con confirmación y con fallo de un nodo; '
  'además se probó el control de concurrencia con bloqueos.')

# ===================================================================== 6
H1('6. Solución NoSQL – MongoDB')
P('MongoDB guarda el **expediente completo de cada envío** en un solo documento, para responder el seguimiento sin '
  'reunir seis tablas. La base `olva_tracking` tiene tres colecciones:')
V('**envios** (29 966 documentos, 2,6 kB promedio): `_id` = número de tracking; subdocumentos de servicio, cliente, '
  'destinatario, origen, destino, fechas y comprobante; arreglos de paquetes, tracking (315 101 eventos embebidos), '
  'intentos e incidencias; y prueba de entrega con punto GeoJSON.',
  '**hubs** (38 documentos) con ubicación GeoJSON, y **clientes** (3 000) con documento de identidad.')
H2('6.1 Implementación')
V('**Validación $jsonSchema** estricta: campos obligatorios, estados permitidos y tipos de fecha.',
  '**12 índices:** compuestos (estado + compromiso, cliente + fecha), multikey sobre el arreglo de tracking, '
  'geoespaciales `2dsphere` (prueba de entrega y hubs), de texto (nombre del cliente), único (documento) y disperso '
  '(incidencias).',
  '**Operaciones:** carga masiva con `mongoimport`, CRUD con `$push` y `$set` atómicos y agregaciones con `$lookup`, '
  '`$group`, `$bucket` y `$setWindowFields`; confirmaron, por ejemplo, que 10 344 llegadas a las 20:00 al Hub Central '
  'permanecen 14,6 h en promedio.',
  '**Seguridad:** 3 roles (portal web, operador de hub y analista), usuarios con SCRAM-SHA-256 y 2 vistas sin datos '
  'personales.')
H2('6.2 Distribución en dos sedes')
P('Con **sharding por zonas** sobre la clave `{origen.nodo, _id}`, la sede **Lima** guarda 23 638 envíos y la sede '
  '**Arequipa** 6 328 (nodos Norte y Sur). Las consultas filtradas por sede se resuelven en un solo shard '
  '(`SINGLE_SHARD`); las globales combinan ambos (`SHARD_MERGE`). Se probaron transacciones distribuidas (confirmación, '
  'cancelación y traslado de un documento entre sedes al cambiar su clave) y el comportamiento ante la caída de una sede.')

# ===================================================================== 7
H1('7. Solución NoSQL – Apache Cassandra')
P('Cassandra guarda la **bitácora de escaneos** y el estado en línea, una serie de tiempo de escritura intensiva que '
  'debe seguir disponible aunque falle una sede. El keyspace `olva_tracking` tiene **8 tablas diseñadas por consulta** '
  '(cada una responde una pregunta concreta por su clave de partición):')
T(['Tabla', 'Clave primaria', 'Pregunta que responde'],
  [['eventos_por_envio', '((nro_tracking), fecha_hora, id_evento)', 'Recorrido completo de un envío'],
   ['eventos_por_hub_dia', '((hub, dia), fecha_hora, id_evento)', 'Qué pasó en un hub un día'],
   ['escaneos_hub_hora', '((hub, dia), hora)', 'Escaneos, llegadas y salidas por hora'],
   ['envios_por_cliente', '((id_cliente), fecha_registro, nro_tracking)', 'Historial de un cliente'],
   ['estado_envio', '(nro_tracking)', 'Estado actual del envío'],
   ['contador_escaneos', '((hub, dia), tipo_evento)', 'Contadores por tipo de evento'],
   ['alertas_sla', 'partición por día (TTL 48 h)', 'Alertas que expiran solas'],
   ['hubs', '(hub)', 'Catálogo de la red']],
  [3.6, 6.4, 6.0])
V('**Carga masiva** con `COPY FROM` (unas 45 000 filas por segundo).',
  '**Operaciones propias del motor:** transacciones ligeras (LWT, `IF NOT EXISTS`), BATCH para escribir el mismo evento '
  'en varias tablas, contadores y TTL.',
  '**Seguridad:** autenticación y autorización activadas, superusuario propio (el rol por defecto deshabilitado) y 3 '
  'roles (analista, operador de hub y portal del cliente).',
  '**Dos sedes:** centros de datos `dc_lima` y `dc_arequipa` con réplica 1 + 1 (copia completa en cada sede) y un '
  'keyspace local solo en Arequipa. Se probaron los niveles de consistencia `LOCAL_ONE`, `ONE`, `EACH_QUORUM` y `ALL`: '
  'cada sede responde sola con `LOCAL_ONE`, y tras la caída de Lima la sede Arequipa siguió atendiendo y sincronizó al '
  'volver (hinted handoff).')

# ===================================================================== 8
H1('8. Big Data con Apache Hadoop')
H2('8.1 Datos masivos')
P('Con el mismo simulador se generó un conjunto masivo de **299 667 envíos**, **3 152 417 eventos** y **5 640 511 '
  'registros** (340 MB). La justificación es directa: 1 577 envíos por día (unos 4,5 por hora en cada una de las 29 '
  'agencias) × 190 días × 10,52 eventos por envío = 3 152 417 eventos. El conjunto masivo conserva el comportamiento de la '
  'base operativa: 91,43 % de cumplimiento frente a 91,40 %, y 10,52 eventos por envío en ambos.')
H2('8.2 Clúster e implementación')
V('**Instalación:** Apache Hadoop 3.3.6 (paquete oficial verificado con SHA-512) sobre Ubuntu 22.04 y OpenJDK 11, en '
  'modo pseudo-distribuido con **NameNode, 2 DataNodes, ResourceManager, NodeManager y JobHistory Server**.',
  '**HDFS:** bloques de 64 MB y replicación 2, organizado por zonas: `/olva/raw` (datos crudos), '
  '`/olva/raw/catalogos` (caché distribuida), `/olva/operacional/<fecha>` (extracciones de PostgreSQL) y '
  '`/olva/resultados` (indicadores).',
  '**MapReduce en Java:** un Driver encadena tres jobs. Job 1: el Mapper agrupa las llegadas y salidas por envío y el '
  'Reducer reconstruye cada estancia en un hub (525 751 estancias). Job 2: agrega permanencia por hub, hora, mes y día '
  'con un Combiner (318 indicadores). Job 3: cumplimiento del SLA por servicio y ruta con map-side join (140 '
  'indicadores). La cadena completa tarda unos 99 segundos.')
H2('8.3 Respuesta a la pregunta analítica')
P('El patrón más relevante es la **saturación nocturna del Hub Central Lima**: a las 20:00 llega el 35,8 % de sus '
  'paquetes y permanecen 14,57 h en promedio; lo que llega de noche permanece un 43 % más que lo que llega de día. '
  'Además, el Hub Arequipa aumenta su permanencia un 20 % en agosto y septiembre, los servicios aéreos cumplen solo el '
  '86,7 % (frente al 98,8 % del Económico Terrestre) y las rutas Estándar Terrestre del Sur hacia el Oriente, el Norte '
  'y el Centro cumplen apenas entre 39,8 % y 41,8 %.')

# ===================================================================== 9
H1('9. Integración y portal web')
H2('9.1 Flujo de datos y coexistencia')
V('**Una sola fuente de verdad:** los datos transaccionales nacen en PostgreSQL; MongoDB, Cassandra y Hadoop reciben '
  'copias transformadas.',
  '**Flujo automatizado:** se extraen los datos de PostgreSQL directamente a HDFS, se procesan con el mismo código '
  'MapReduce y los 458 indicadores resultantes se cargan en PostgreSQL (esquema `analitica`), MongoDB (colección '
  '`kpi_bigdata`) y Cassandra (tablas `kpi_*`). Una verificación final confirma que los tres motores devuelven el mismo '
  'valor (102 570 estancias y 14,57 h para el Hub Central a las 20:00).',
  '**Claves comunes:** número de tracking, código de hub y de servicio, idénticos en los cinco motores.',
  '**Consistencia según el uso:** ACID y 2PC para dinero y estados; consistencia ajustable en Cassandra; consistencia '
  'eventual para los indicadores, que se reemplazan en cada lote.')
H2('9.2 Portal web de envíos')
P('Para demostrar la integración se desarrolló un sitio web (Python Flask y JavaScript) con 8 secciones; cada una '
  'consulta el motor más adecuado:')
T(['Sección', 'Qué hace', 'Motor'],
  [['Rastrear', 'Estado, plazo, mapa del recorrido e historial', 'PostgreSQL + MongoDB + Cassandra'],
   ['Enviar', 'Registra el envío y lo mueve hasta la entrega', 'PostgreSQL → réplica en los otros 4'],
   ['Cotizar', 'Precio y plazo de los 4 servicios', 'PostgreSQL (fn_calcular_tarifa)'],
   ['Mi cuenta', 'Perfil e historial por DNI o RUC', 'MongoDB + Cassandra'],
   ['Agencias', 'Mapa y agencias más cercanas', 'MongoDB ($geoNear, 2dsphere)'],
   ['Operaciones', 'Indicadores y actividad por hub', 'PostgreSQL + Hadoop + Cassandra'],
   ['Bases de datos', 'Estado de las conexiones y rastreo cruzado', 'Los cinco motores']],
  [3.0, 7.0, 6.0])
P('Al registrar un envío, el portal llama a `sp_registrar_envio` y luego replica el envío completo en Oracle, MongoDB, '
  'Cassandra y HDFS; cada escaneo posterior sigue el mismo camino a través de `sp_registrar_escaneo` y '
  '`sp_registrar_intento_entrega`, y la página muestra el resultado de cada motor.')

# ===================================================================== 10
H1('10. Resultados, conclusiones y recomendaciones')
H2('10.1 Resultados principales')
T(['Indicador', 'Valor', 'Fuente'],
  [['Cumplimiento global del plazo', '91,4 %', 'PostgreSQL'],
   ['Ocupación del Hub Central a las 20:00', '110 % de su capacidad', 'PostgreSQL'],
   ['Llegadas al Hub Central a las 20:00', '35,8 %, con 14,57 h de permanencia', 'Hadoop'],
   ['Permanencia nocturna frente a diurna', '+43 %', 'Hadoop'],
   ['Hub Arequipa en agosto y septiembre', '+20 % de permanencia', 'Hadoop'],
   ['Cumplimiento de servicios aéreos', '86,7 % (Económico Terrestre: 98,8 %)', 'Hadoop'],
   ['Envíos por sede en MongoDB', 'Lima 23 638 · Arequipa 6 328', 'MongoDB'],
   ['Procesamiento de 3,15 M eventos', '≈ 99 segundos', 'Hadoop']],
  [6.5, 6.0, 3.5])
H2('10.2 Conclusiones')
V('El modelo relacional normalizado de 20 tablas soportó sin cambios la base operativa (29 966 envíos) y el conjunto '
  'masivo (299 667 envíos), lo que confirma que es correcto y escalable.',
  'PostgreSQL, con su programación almacenada, seguridad por roles y por fila y respaldos verificados, funciona como '
  'fuente de verdad; Oracle demostró que el modelo es portable y permitió contrastar ambas arquitecturas.',
  'La distribución en tres nodos, con fragmentación verificada y 2PC, y las dos sedes de MongoDB y Cassandra muestran '
  'tres formas de repartir datos: fragmentar a mano, fragmentar por zonas y replicar.',
  'Hadoop cuantificó el cuello de botella (35,8 % de las llegadas al Hub Central a las 20:00 con 14,57 h de '
  'permanencia) y su efecto en el plazo, y la integración dejó esos indicadores disponibles en tres motores y en el '
  'portal web.')
H2('10.3 Recomendaciones')
V('Escalonar la llegada nocturna al Hub Central (adelantar despachos de las 19:30 y reforzar la clasificación de 18:00 '
  'a 02:00) para bajar la permanencia de la franja de las 20:00 por debajo de 12 h.',
  'Programar personal adicional en el Hub Arequipa en agosto y septiembre, y revisar el plazo prometido en las rutas '
  'Estándar Terrestre del Sur.',
  'Automatizar la integración cada noche con captura de cambios, llevar Hadoop a un clúster de varias máquinas con '
  'Kerberos y añadir autenticación al portal web.')

H1('Referencias')
for r in ('Apache Software Foundation. (2023). Apache Hadoop 3.3.6 documentation. https://hadoop.apache.org/docs/r3.3.6/',
          'Apache Software Foundation. (2023). Apache Cassandra 4.1 documentation. https://cassandra.apache.org/doc/4.1/',
          'Dean, J., & Ghemawat, S. (2008). MapReduce: Simplified data processing on large clusters. Communications of the ACM, 51(1), 107–113.',
          'Elmasri, R., & Navathe, S. B. (2016). Fundamentals of database systems (7th ed.). Pearson.',
          'MongoDB, Inc. (2024). MongoDB manual (version 7.0). https://www.mongodb.com/docs/v7.0/',
          'Oracle Corporation. (2025). Oracle Database documentation. https://docs.oracle.com/en/database/',
          'Özsu, M. T., & Valduriez, P. (2020). Principles of distributed database systems (4th ed.). Springer.',
          'PostgreSQL Global Development Group. (2024). PostgreSQL 16 documentation. https://www.postgresql.org/docs/16/'):
    p = doc.add_paragraph(r)
    p.paragraph_format.left_indent = Cm(1)
    p.paragraph_format.first_line_indent = Cm(-1)
    p.paragraph_format.space_after = Pt(3)
    for run in p.runs:
        run.font.size = Pt(9.5)

doc.save(SALIDA)
print('Generado:', SALIDA)
