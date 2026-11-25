# HITO 1 — Definición del problema, objetivos y requerimientos

**Curso:** Base de Datos II (100000SI46)
**Tema asignado:** 15. Trazabilidad de paquetería y courier aéreo/terrestre — escaneo en hubs logísticos, estados de entrega y optimización de cuellos de botella.
**Empresa de referencia:** Olva Courier (Perú).

> **Nota de autoría y datos.** El proyecto se modela sobre la operación pública de Olva Courier: red nacional de agencias, transporte aéreo y terrestre, y seguimiento del envío por número de tracking. **Todos los registros son sintéticos.** Los generó el grupo con un simulador propio (`01_Relacional_PostgreSQL/generador/generar_datos.py`). Ninguna cifra corresponde a datos internos de la empresa. Ciudades, códigos UBIGEO y la geografía de rutas (por ejemplo, que Iquitos no tiene acceso por carretera) son reales; volúmenes, clientes, tiempos y tarifas son simulados.

> Este documento desarrolla los capítulos 1 a 4 del *Formato Único de Informe*. La numeración coincide con la plantilla oficial.

---

## 1. RESUMEN EJECUTIVO (borrador)

Una empresa de courier nacional mueve cada día miles de envíos entre agencias, hubs regionales y un hub central. El movimiento es por vía aérea y terrestre. Cada envío genera entre 8 y 14 escaneos a lo largo de su recorrido. Sin una solución de datos adecuada, la empresa no puede responder a tiempo dónde está un paquete, qué hub retrasa la red ni qué envíos van a incumplir su promesa de entrega.

El proyecto construye una solución integral de datos con varias tecnologías:

- **PostgreSQL:** núcleo transaccional normalizado, con reglas de negocio en procedimientos, seguridad por roles y por fila, y respaldo.
- **Oracle:** implementación comparativa del núcleo.
- **BD distribuida de 3 nodos (Lima, Norte, Sur):** fragmentos horizontales y verticales.
- **MongoDB:** incidencias y pruebas de entrega, que son datos semiestructurados.
- **Cassandra:** la serie temporal de escaneos.
- **Hadoop/MapReduce:** procesar millones de eventos e identificar cuellos de botella en los hubs.

**Resultados del avance actual** (sobre ~30 mil envíos y ~315 mil eventos simulados):

- El cumplimiento global del plazo es de **91,4 %**.
- El **Hub Central Lima es el principal cuello de botella**:
  - el 37 % de los paquetes permanece más de 12 h;
  - a las 20:00 recibe **110 % de su capacidad horaria**;
  - cuando un envío aéreo pasa más de 12 h en este hub, su cumplimiento cae de 88,7 % a 81,0 %.

*(Se completará con los resultados de MongoDB, Cassandra y Hadoop en los avances 2 y 3.)*

---

## 2. INTRODUCCIÓN

### 2.1 Contexto del proyecto

Olva Courier es una empresa peruana de mensajería y paquetería con cobertura nacional. Atiende a personas y a empresas, en especial comercio electrónico, mediante una red de agencias de admisión y reparto. Los envíos se consolidan en hubs y viajan entre ciudades por carretera o en bodegas de vuelos comerciales.

El crecimiento del comercio electrónico en el Perú aumenta el volumen de envíos de Lima a provincias. También aumenta la exigencia del cliente: quiere conocer en tiempo real el estado de su paquete y recibirlo en el plazo ofrecido.

Para el proyecto se modeló la siguiente red:

| Elemento | Cantidad | Detalle |
|---|---|---|
| Macro-regiones | 5 | Lima, Centro, Norte, Oriente, Sur |
| Ciudades | 17 | Códigos UBIGEO reales |
| Hub central | 1 | HC-LIM, ubicado en Callao |
| Hubs regionales | 8 | Trujillo, Chiclayo, Piura, Huancayo, Iquitos, Arequipa, Cusco, Juliaca |
| Agencias | 29 | Puntos de admisión y reparto |
| Rutas | 98 | Aéreas y terrestres, con distancia y tiempo estimado |
| Servicios | 4 | Express Aéreo (48 h), Sobre Aéreo (48 h), Estándar Terrestre (72 h), Económico Terrestre (120 h) |

*Tabla 1. Red logística modelada. Fuente: elaboración propia.*

### 2.2 Problemática y elemento diferenciador

**Problemática.** La información operativa de un courier está fragmentada entre agencias, hubs y medios de transporte. Esto genera cuatro problemas:

1. **Falta de trazabilidad unificada.** Atención al cliente no puede reconstruir rápido el recorrido de un envío ni explicar un retraso.
2. **Cuellos de botella invisibles.** Los paquetes se acumulan en ciertos hubs y franjas horarias, por ejemplo en la recepción nocturna del hub central. Pierden el corte de despacho (camión de las 23:30, vuelos de 08:00 y 17:30) y esperan hasta 24 h más.
3. **Incumplimiento del plazo comprometido (SLA)** sin alertas tempranas.
4. **Volumen creciente de eventos.** Cada envío genera ~10,5 escaneos en promedio. Con miles de envíos al día, el histórico supera lo que una sola base relacional analiza con comodidad.

**Elemento diferenciador: trazabilidad por eventos más distribución geográfica.** Cada escaneo es un evento con marca de tiempo, lugar (hub), responsable y manifiesto de transporte:

- `ADMISION`
- `SALIDA_HUB`
- `LLEGADA_HUB`
- `CLASIFICACION`
- `EN_REPARTO`
- `INTENTO_FALLIDO`
- `ENTREGA`
- `DEVOLUCION`

Este flujo de eventos es lo que justifica la arquitectura. Requiere un modelo transaccional consistente (PostgreSQL) y una distribución por sede, porque los escaneos ocurren físicamente en Lima, el Norte o el Sur. También requiere un almacén de series temporales con alta tasa de escritura (Cassandra) y un procesamiento masivo del histórico (Hadoop).

### 2.3 Justificación técnica y de negocio

**Negocio:**
- Reducir los envíos que incumplen el plazo.
- Dimensionar personal y horarios de corte en los hubs críticos.
- Anticipar reclamos con alertas de envíos estancados.
- Mejorar la entrega al primer intento, que hoy es ~85 %.

**Técnica:** cada tipo de dato tiene un patrón de acceso distinto, y por eso conviene usar varias tecnologías.

| Tipo de dato | Necesidad | Tecnología |
|---|---|---|
| Transacciones (envío, comprobante, despacho) | Consistencia ACID, integridad referencial | PostgreSQL / Oracle |
| Operación por sede | Autonomía local, menor latencia, tolerancia a fallas regionales | BD distribuida |
| Incidencias y pruebas de entrega | Estructura variable (fotos, firmas, comentarios) | MongoDB |
| Escaneos (serie temporal) | Escrituras masivas, consulta por tracking o por hub-día | Cassandra |
| Histórico de eventos | Análisis por lotes de millones de registros | Hadoop / MapReduce |

*Tabla 2. Correspondencia entre datos y tecnologías. Fuente: elaboración propia.*

### 2.4 Alcance

**Incluye:**
- Ciclo de vida completo del envío: registro y tarificación, consolidación en despachos, escaneos en hubs, reparto con hasta 3 intentos, devolución, incidencias y comprobante.
- Red nacional simulada de 38 nodos logísticos.
- Datos sintéticos de **abril a octubre de 2026**: ~30 mil envíos en la BD relacional y 1–5 millones de eventos para Hadoop (Avance 3).
- Implementación de los seis componentes del curso con evidencias de ejecución.

**No incluye:**
- Desarrollo de aplicaciones web o móviles: la interacción se demuestra con SQL, procedimientos y scripts.
- Integración con sistemas reales de la empresa ni con SUNAT.
- Envíos internacionales.

### 2.5 Limitaciones y restricciones

- Datos 100 % sintéticos. Los patrones (por ejemplo, la congestión nocturna del hub central) se **inyectan** en el simulador de forma documentada. Los hallazgos validan la solución técnica, no la operación real de la empresa.
- La infraestructura corre en una sola laptop (16 GB de RAM) con Docker. Los "nodos" distribuidos son contenedores en la misma máquina, así que no se mide la latencia real de una WAN.
- Se usa Oracle AI Database Free (23ai/26ai), con límites de CPU, RAM y almacenamiento. Por eso solo se implementa un subconjunto del modelo.
- La muestra relacional (~30 mil envíos) es menor al volumen real de un courier nacional. Las capacidades de hub se escalaron a esa muestra.

---

## 3. OBJETIVOS

### 3.1 Objetivo general

Diseñar e implementar una solución integral de datos para la trazabilidad de envíos aéreos y terrestres de un courier nacional (caso Olva Courier). La solución integra bases de datos relacionales, distribuidas, NoSQL y procesamiento Big Data, y su meta es identificar cuellos de botella en la red logística y mejorar el cumplimiento de los plazos de entrega.

### 3.2 Objetivos específicos

| N.° | Objetivo específico | Módulo | Indicador de logro |
|---|---|---|---|
| OE1 | Diseñar e implementar en PostgreSQL un modelo relacional normalizado (3FN) del ciclo de vida del envío, con reglas de negocio en procedimientos, triggers, seguridad por roles y respaldo | Relacional | ≥ 15 tablas con PK/FK/CHECK; ≥ 10 consultas; ≥ 2 funciones y ≥ 2 procedimientos; restauración verificada al 100 % |
| OE2 | Implementar un subconjunto del modelo en Oracle y comparar arquitectura, sintaxis y programación con PostgreSQL | Relacional | ≥ 3 tablas; paquete PL/SQL; ≥ 5 diferencias demostradas |
| OE3 | Diseñar e implementar una BD distribuida de al menos 3 nodos con fragmentación horizontal y vertical, procesamiento distribuido de consultas, 2PC y control de concurrencia | Distribuidas | Completitud, disyunción y reconstrucción = 100 %; 2PC con commit, abort y recuperación |
| OE4 | Modelar en MongoDB las incidencias y pruebas de entrega como documentos | NoSQL | ≥ 5 operaciones, incluidos pipelines de agregación |
| OE5 | Modelar en Cassandra la serie temporal de escaneos, con tablas diseñadas según las consultas | NoSQL | ≥ 5 consultas CQL por partición |
| OE6 | Generar y procesar en Hadoop/HDFS un conjunto masivo de eventos (1–5 millones) con MapReduce para obtener un indicador de cuellos de botella | Big Data | Job MapReduce ejecutado y ranking de hubs por permanencia |

*Tabla 3. Objetivos específicos e indicadores. Fuente: elaboración propia.*

---

## 4. DESCRIPCIÓN DEL PROBLEMA Y REQUERIMIENTOS

### 4.1 Descripción del escenario operativo

Recorrido típico de un envío de Lima (Miraflores) a Arequipa:

1. **Admisión en agencia.** El cliente entrega uno o más bultos. Se pesan y se cotiza según servicio, regiones y peso. Se emite boleta o factura y se genera el número de tracking (`OLV##########`). La fecha de compromiso vence a las 20:00 del día alcanzado por el SLA; si cae domingo, pasa al lunes. → evento `ADMISION`.
2. **Consolidación agencia → hub.** Los envíos se cargan en un **despacho** (manifiesto) en furgoneta, con salidas a las 13:00 y 19:30. → `SALIDA_HUB` en la agencia y `LLEGADA_HUB` en el Hub Central.
3. **Clasificación en el hub.** Se clasifica por ruta → `CLASIFICACION`. El tiempo depende de la congestión del hub.
4. **Troncal.** El envío viaja en camión (salida 23:30) o en un vuelo (08:00 o 17:30) hasta el hub regional. Los vuelos tienen capacidad de bodega limitada.
5. **Distribución.** Del hub regional pasa a la agencia destino (salidas 06:00 y 14:30).
6. **Reparto.** El courier sale a reparto → `EN_REPARTO`. Hay hasta 3 intentos (`INTENTO_FALLIDO` / `ENTREGA`). Si el destinatario lo rechaza o fallan los 3 intentos → `DEVOLUCION`.
7. **Incidencias.** Daños, pérdidas, dirección incorrecta o reclamos por retraso abren una incidencia hasta su cierre.

### 4.2 Actores e interfaces involucradas

| Actor | Interacción con los datos | Rol de BD |
|---|---|---|
| Cliente (persona / empresa) | Registra envíos, consulta tracking, presenta reclamos | (vía atención) |
| Personal de atención en agencia | Admisión, tarificación, comprobante, incidencias | `rol_atencion_cliente` |
| Operario de hub | Escaneos de llegada, clasificación y salida; cierre de despachos | `rol_operador_hub` (solo ve su nodo por RLS) |
| Conductor / aerolínea | Ejecuta el despacho (vehículo propio o número de vuelo) | — |
| Courier | Reparto e intentos de entrega | `rol_operador_hub` |
| Facturación | Comprobantes e ingresos | `rol_facturacion` |
| Analista / gerencia | KPIs, cuellos de botella, SLA | `rol_analista` (solo vistas, sin datos personales) |
| DBA | Administración, respaldo y restauración | `rol_admin_olva` |

*Tabla 4. Actores. Fuente: elaboración propia.*

**Interfaces:** procedimientos almacenados (API de escritura), vistas (API de lectura), postgres_fdw (entre nodos) y archivos CSV/HDFS (carga masiva y Big Data).

### 4.3 Requerimientos funcionales de datos

| Código | Requerimiento | Implementación |
|---|---|---|
| RF01 | Registrar envíos con tarificación automática, validación de servicio y destino, paquetes y comprobante en una sola transacción | `sp_registrar_envio`, `fn_calcular_tarifa` |
| RF02 | Registrar cada escaneo validando la secuencia de estados del envío | `sp_registrar_escaneo` + trigger de estado |
| RF03 | Consolidar envíos en despachos por ruta, con vehículo o vuelo según la modalidad | `despacho`, `despacho_envio`, `trg_validar_despacho` |
| RF04 | Cerrar un despacho registrando la llegada masiva de sus envíos | `sp_cerrar_despacho` |
| RF05 | Registrar intentos de entrega (máx. 3), devoluciones e incidencias automáticas | `sp_registrar_intento_entrega` |
| RF06 | Consultar la línea de tiempo completa de un envío | C01, `vw_tracking_publico` |
| RF07 | Calcular el estado del SLA (a tiempo, en riesgo, vencido) | `fn_estado_sla` |
| RF08 | Medir la permanencia de envíos en cada hub y franja horaria | `fn_cuellos_botella`, `mv_permanencia_hub` |
| RF09 | Auditar todo cambio de estado de un envío | `auditoria.log_estado_envio` |
| RF10 | Gestionar incidencias semiestructuradas (fotos, comentarios, evidencias) | MongoDB (Avance 2) |
| RF11 | Almacenar y consultar escaneos por tracking y por hub-día a alta tasa | Cassandra (Avance 2) |
| RF12 | Procesar el histórico masivo de eventos para obtener indicadores | Hadoop (Avance 3) |

*Tabla 5. Requerimientos funcionales. Fuente: elaboración propia.*

### 4.4 Requerimientos no funcionales

| Tipo | Requerimiento | Cómo se atiende |
|---|---|---|
| Escalabilidad | Soportar el crecimiento de escaneos (estimado en 1–5 M/mes) sin degradar el núcleo transaccional | Fragmentación por nodo; eventos históricos en Cassandra/HDFS |
| Disponibilidad | Si cae un nodo regional, Lima y el otro nodo siguen operando sus fragmentos | Fragmentación + réplica de catálogos en cada nodo |
| Rendimiento | Tracking de un envío en < 100 ms; consultas analíticas en segundos | Índices `(id_envio, fecha_hora)`, índice parcial de envíos vivos, vista materializada; las 13 consultas corren en 1,5 s |
| Consistencia | Una operación que toca varios nodos es atómica | 2PC |
| Seguridad | Mínimo privilegio; los operadores solo ven su nodo; escritura solo vía procedimientos | RBAC, permisos por columna, RLS, `SECURITY DEFINER` |
| Recuperabilidad | Restaurar ante borrado accidental o pérdida total | `pg_dump`/`pg_restore`, `pg_basebackup`, Data Pump |
| Auditabilidad | Saber quién cambió qué estado y cuándo | Trigger de auditoría |

*Tabla 6. Requerimientos no funcionales. Fuente: elaboración propia.*

### 4.5 Preguntas de negocio a responder mediante el análisis de datos

| N.° | Pregunta | Dónde se responde |
|---|---|---|
| PN1 | ¿Qué porcentaje de envíos se entrega dentro del plazo, por servicio y por mes? | C02 (PostgreSQL), O2 (Oracle) |
| PN2 | ¿En qué hubs y franjas horarias se acumulan los paquetes (cuellos de botella)? | C03, C13; **pregunta Hadoop** (Avance 3) |
| PN3 | ¿Cuánto afecta al SLA la permanencia prolongada en el Hub Central? | C04 |
| PN4 | ¿Qué rutas tienen más retraso en salidas y viajes? | C05 |
| PN5 | ¿Qué corredores origen-destino generan más ingresos? | C06 |
| PN6 | ¿Qué clientes empresariales concentran la facturación y cómo es su puntualidad? | C07 |
| PN7 | ¿Dónde y por qué fallan las entregas al primer intento? | C08; MongoDB (Avance 2) |
| PN8 | ¿Qué envíos están en riesgo o estancados ahora mismo? | C09, C12 |

**Pregunta analítica para Hadoop (guía, sección 6):** usando MapReduce sobre millones de escaneos, ¿qué hubs y franjas horarias presentan los mayores tiempos de permanencia (llegada → salida)? ¿Cuánto mejoraría el cumplimiento si se moviera el corte de despacho o se reforzara el turno crítico?
