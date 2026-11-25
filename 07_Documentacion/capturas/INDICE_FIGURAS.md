# Índice de figuras: diagramas técnicos y capturas de ejecución

**Diagramas (figuras 1 a 4).** Son diseños ilustrativos elaborados por el grupo. Están en `07_Documentacion/diagramas/` como PNG de alta resolución y como fuente editable (`.mmd` Mermaid o `.svg`). El diagrama ER se genera automáticamente desde el catálogo real de PostgreSQL con `generar_er_desde_catalogo.sql`, por lo que coincide con las tablas implementadas.

**Capturas (figuras 5 en adelante).** Son ejecuciones reales:

- psql 18 conectado al servidor PostgreSQL 16.15 (puerto 5440).
- SQL\*Plus conectado a Oracle 26ai Free (servicio FREEPDB1).

Cómo se produjeron:

- La salida textual completa de cada ejecución está en `capturas/salidas/<id>.txt`.
- Cuando la salida no cabe en una pantalla, la captura se divide en partes (`_p1`, `_p2`).
- Se regeneran con `tomar_capturas.ps1`, a partir de los scripts definidos en `preparar_capturas.py`.
- Ninguna captura muestra contraseñas.

**Fuente sugerida para todas las capturas:**

> Fuente: elaboración propia a partir de la ejecución en psql / SQL\*Plus.

---

## Diagramas técnicos

| Figura | Archivo | Título | Apartado |
|---|---|---|---|
| 1 | `diagramas/01_modelo_ER.png` (fuente `.mmd`) | Diagrama Entidad-Relación del sistema de trazabilidad (18 entidades, 30 relaciones) | 5.2 |
| 2 | `diagramas/02_arquitectura_postgresql.png` (fuente `.mmd`) | Arquitectura de PostgreSQL: clientes, servidor, base olva_courier, schemas y programación | 6.2 |
| 3 | `diagramas/03_arquitectura_oracle.png` (fuente `.mmd`) | Arquitectura de Oracle: clientes, listener, instancia, PDB FREEPDB1 y esquema OLVA | 8.2 |
| 4 | `diagramas/04_arquitectura_distribuida.png` (fuente `.svg`) | Arquitectura de la base de datos distribuida de tres nodos | 9.2 |

**Nota sobre la Figura 3.** No se configuraron *database links*: Oracle se implementó como servidor independiente para la comparación (punto 8). La distribución de datos (punto 9) se implementó y verificó con PostgreSQL y `postgres_fdw`.

---

## 1. Conexión y creación de la base de datos PostgreSQL (6.1–6.2)

| Fig. | Archivo | Título | Interpretación técnica |
|---|---|---|---|
| 5 | PG01.png | Conexión al servidor PostgreSQL y datos de la base olva_courier | `\conninfo` confirma la conexión a `olva_courier` en el puerto 5440 con autenticación por contraseña. El servidor es PostgreSQL 16.15. La base usa UTF8, zona horaria America/Lima y ocupa 115 MB |
| 6 | PG02.png | Schemas y tablas creadas en olva_courier | Existen los cuatro schemas del diseño. `maestro` y `operacion` contienen 9 tablas cada uno; `auditoria` y `seguridad`, una cada uno. `operacion` tiene además 3 vistas |

## 2. Creación de tablas y restricciones (6.3)

| Fig. | Archivo | Título | Interpretación técnica |
|---|---|---|---|
| 7 | PG03.png | Estructura de la tabla operacion.despacho | Muestra tipos, IDENTITY, la PK, FK hacia ruta y vehiculo, CHECK de negocio (`ck_despacho_transporte`, `ck_despacho_estado`), índices, tablas que la referencian y el trigger `trg_validar_despacho` |
| 8 | PG04.png | Restricciones implementadas en la tabla operacion.envio | Lista PK, UNIQUE del tracking, 6 FK y los CHECK de dominio y de negocio (por ejemplo, ENTREGADO ⇔ fecha de entrega) leídos del catálogo con `pg_get_constraintdef` |

## 3. Poblamiento y consultas SQL (6.4–6.5)

| Fig. | Archivo | Título | Interpretación técnica |
|---|---|---|---|
| 9 | PG05.png | Validación del poblamiento: registros por tabla | Conteo exacto de las 18 tablas: 29 966 envíos, 315 101 eventos, 40 714 paquetes, entre otras. Coincide con la salida del generador |
| 10 | PG_C01.png | C01: línea de tiempo de un envío | 11 escaneos del envío OLV2600001112. `LAG()` calcula el tiempo entre eventos; la mayor espera ocurre en HC-LIM |
| 11 | PG_C02.png | C02: cumplimiento de SLA por servicio y mes | Agregación con `FILTER`: el Económico ronda el 99 % y los aéreos entre 85 % y 91 %; julio es el peor mes del Express |
| 12 | PG_C03.png | C03: cuellos de botella por hub y franja | La función de tabla ubica a HC-LIM entre 18 y 24 h como el mayor cuello de botella: 14,5 h promedio y P90 de 27,1 h |
| 13 | PG_C04.png | C04: impacto del Hub Central en el SLA | Cuando la permanencia en HC supera 12 h, el cumplimiento aéreo baja de 88,7 % a 81,0 % y el terrestre de 96,1 % a 91,3 % |
| 14 | PG_C05.png | C05: puntualidad de despachos por ruta | Las troncales terrestres a Cusco y Juliaca presentan el mayor desvío de viaje (+1,2 a +1,5 h) |
| 15–16 | PG_C06_p1/p2.png | C06: matriz de ingresos con ROLLUP | Subtotales por región de origen y total general. Lima origina S/ 561 844,80 de S/ 812 292,40 (69 %) |
| 17 | PG_C07.png | C07: top 10 clientes empresariales | `RANK()` y participación con `SUM() OVER ()`. Textil Los Andes presenta la menor puntualidad (80,7 %) |
| 18 | PG_C08.png | C08: entrega al primer intento por ciudad | Tacna (83,5 %) e Iquitos (84,0 %) tienen la menor efectividad; el motivo principal es AUSENTE |
| 19 | PG_C09.png | C09: envíos vencidos o en riesgo | Usa `fn_estado_sla` y el índice parcial de envíos vivos para listar los casos que requieren acción |
| 20–21 | PG_C10_p1/p2.png | C10: incidencias por tipo y hub | HC-LIM concentra 52 de 126 daños (41 %); los reclamos por retraso se resuelven en ~2,4 días |
| 22 | PG_C11.png | C11: productividad de couriers | `DENSE_RANK()` particionado por agencia: entre 3,3 y 3,6 entregas diarias por courier |
| 23 | PG_C12.png | C12: envíos estancados más de 48 h | `LATERAL` obtiene el último escaneo. Todos los envíos estancados tienen incidencia de pérdida registrada |
| 24 | PG_C13.png | C13: ocupación horaria del Hub Central | A las 20:00 llegan 54,8 envíos/h frente a una capacidad de 50/h (109,6 %) |

## 4. Funciones y procedimientos (7.1–7.2)

| Fig. | Archivo | Título | Interpretación técnica |
|---|---|---|---|
| 25 | PG_F1.png | Funciones fn_calcular_tarifa y fn_estado_sla | Tarifas calculadas por servicio y peso; distribución de envíos por estado de SLA. El peso excedido se rechaza con un error controlado |
| 26 | PG_F2.png | Funciones fn_cuellos_botella y fn_permanencia_hub | La función de tabla devuelve el ranking por hub y franja; la escalar devuelve la permanencia por hub de un envío |
| 27 | PG_P1.png | Procedimiento sp_registrar_envio | Registra el envío, sus paquetes (JSONB) y el comprobante (subtotal + IGV = total) en una transacción. Rechaza el servicio terrestre hacia Iquitos. Al final hace ROLLBACK |
| 28 | PG_P2.png | Ciclo completo de un envío con procedimientos y triggers | La máquina de estados rechaza una transición inválida. Los procedimientos generan 10 eventos hasta ENTREGADO_A_TIEMPO y la auditoría registra cada cambio de estado |

## 5. Roles, privilegios y seguridad (7.3–7.4)

| Fig. | Archivo | Título | Interpretación técnica |
|---|---|---|---|
| 29 | PG_S1.png | Roles, privilegios y políticas RLS | Siete usuarios heredan permisos de cinco roles (RBAC), con límites de conexión y vigencia. Hay cuatro políticas RLS |
| 30 | PG_S2.png | Row Level Security por nodo | La misma consulta devuelve 27 023 (Lima), 11 347 (Norte), 8 658 (Sur) y 29 966 (propietario) envíos |
| 31 | PG_S3.png | Accesos denegados | El operador no lee `monto_total` ni escribe directamente en las tablas; el analista no accede a datos personales ni a procedimientos de escritura |

## 6. Respaldo y restauración (7.5)

| Fig. | Archivo | Título | Interpretación técnica |
|---|---|---|---|
| 32–33 | PG_B1_p1/p2.png | Respaldo lógico y físico y restauración verificada | `pg_dump`, `pg_dumpall` y `pg_basebackup`. Se borran las incidencias y se recuperan con `pg_restore` selectivo (1 904 filas). La restauración completa en una base nueva coincide en las 18 tablas y recupera 13 funciones y procedimientos, 3 triggers y 4 políticas |

## 7–8. Oracle (8.2–8.3)

| Fig. | Archivo | Título | Interpretación técnica |
|---|---|---|---|
| 34 | ORA01.png | Conexión con SQL\*Plus a FREEPDB1 | Banner de SQL\*Plus, versión Oracle AI Database 26ai Free 23.26 y conexión como OLVA en la PDB FREEPDB1 |
| 35 | ORA02.png | Tablas, filas, restricciones y objetos PL/SQL | 9 tablas (1 000 envíos, 10 627 eventos) con PK, FK, UK y CHECK. Paquete, procedimiento y trigger en estado VALID |
| 36–37 | ORA03_p1/p2.png | Estructura y restricciones de ENVIO | `DESC` muestra los tipos adaptados (NUMBER, VARCHAR2, TIMESTAMP WITH TIME ZONE) y los CHECK con `REGEXP_LIKE` |
| 38 | ORA04.png | Consultas básicas | Envíos por estado y SLA por servicio sobre la misma muestra de datos que PostgreSQL |
| 39 | ORA05.png | CONNECT BY | Jerarquía HC-LIM → hub regional → agencia con `LEVEL` y `SYS_CONNECT_BY_PATH` (equivale a `WITH RECURSIVE`) |
| 40 | ORA06.png | LISTAGG y Top-N | `LISTAGG … WITHIN GROUP` (equivale a `STRING_AGG`); `FETCH FIRST` y `ROWNUM` dan el mismo top 5 |
| 41 | ORA07.png | LAG y funciones del paquete | Línea de tiempo con `LAG` y llamadas a `pkg_tracking.fn_calcular_tarifa` y `fn_estado_sla` desde SQL |
| 42 | ORA08.png | Cadena vacía y MERGE | En Oracle `''` IS NULL. `MERGE` inserta una nueva tarifa vigente desde noviembre, luego se revierte |
| 43–44 | ORA09_p1/p2.png | Paquete, trigger y transacción autónoma | ORA-20010 (transición inválida), ORA-20011 y ORA-20002 son errores controlados. Tras el ROLLBACK, `log_error` conserva los registros escritos con `PRAGMA AUTONOMOUS_TRANSACTION` |
| 45 | ORA10.png | Usuarios, PROFILE, roles y privilegios | PROFILE con 3 intentos fallidos, vida de contraseña de 90 días y 3 sesiones; roles con SELECT o EXECUTE sobre el paquete |
| 46–47 | ORA11_p1/p2.png | Pruebas de acceso y bloqueo de cuenta | ORA-00942 y ORA-41900 por falta de privilegios. Tras 3 intentos fallidos la cuenta queda LOCKED(TIMED) (ORA-28000) y se desbloquea como SYSTEM |
| 48 | ORA12.png | Data Pump: exportación y restauración | `expdp` del esquema, `DROP TABLE` simulado e `impdp` que recupera 10 627 filas, 9 restricciones, 3 índices y el trigger. Luego se recompila el paquete |

## 9. Enlaces remotos

No aplica a Oracle: no se configuraron *database links*. La conectividad remota del proyecto se implementó en PostgreSQL con `postgres_fdw` (Figura 49).

## 10–11. Fragmentación horizontal, vertical y reconstrucción (9.3–9.5)

| Fig. | Archivo | Título | Interpretación técnica |
|---|---|---|---|
| 49 | DD01.png | Servidores postgres_fdw y catálogo de fragmentos | Servidores `srv_norte`, `srv_sur` y `srv_origen` (sin credenciales). Cada relación global tiene una partición local LIMA y particiones remotas NORTE y SUR |
| 50 | DD02.png | Distribución por nodo y completitud | Filas por nodo en cada fragmento. El origen coincide con la suma de los fragmentos en todas las relaciones |
| 51 | DD03.png | Disyunción y reconstrucción | 0 claves repetidas entre fragmentos y 0 filas distintas al reconstruir (horizontal por UNION, vertical por JOIN) |
| 52 | DD04.png | Integridad del predicado | El nodo SUR rechaza un envío originado en Lima: viola `ck_predicado_fragmento` |

## 12. Consultas distribuidas, 2PC y concurrencia (9.6–9.8)

| Fig. | Archivo | Título | Interpretación técnica |
|---|---|---|---|
| 53 | DD_Q1.png | Q1: localización | El plan solo accede a `envio_sur`; el filtro viaja en el *Remote SQL* |
| 54 | DD_Q2.png | Q2: agregación distribuida | `Async Foreign Scan` con `GROUP BY` ejecutado en cada nodo remoto |
| 55 | DD_Q3.png | Q3: JOIN co-localizado | *Join pushdown*: `envio ⋈ paquete` se resuelve dentro de cada nodo gracias a la fragmentación derivada |
| 56–57 | DD_Q4_p1/p2.png | Q4: JOIN no co-localizado | El tracking de un envío Iquitos → Arequipa reúne eventos almacenados en los tres nodos |
| 58 | DD_Q5.png | Q5–Q6: reconstrucción vertical y costo | Reconstrucción `cliente_fiscal ⋈ cliente_contacto_sur`. La consulta global tarda 64 ms frente a 26 ms la localizada en Lima |
| 59 | DD_2PC1.png | 2PC, caso 1: commit global | Los tres nodos preparan (`pg_prepared_xacts`); los cambios no son visibles hasta `COMMIT PREPARED` |
| 60 | DD_2PC2.png | 2PC, caso 2: un nodo vota NO | LIMA aborta, así que se ejecuta `ROLLBACK PREPARED` en SUR y no quedan eventos duplicados |
| 61 | DD_2PC3.png | 2PC, caso 3: transacción en duda | La transacción preparada retiene bloqueos (*lock timeout*). El coordinador la resuelve con *presumed abort* según su bitácora |
| 62 | DD_CC_A.png | Concurrencia A: bloqueo de fila | La sesión B espera ~3 s el bloqueo de A; `pg_locks` muestra el ShareLock no otorgado |
| 63 | DD_CC_B.png | Concurrencia B: actualización perdida | READ COMMITTED pierde una escritura (valor final 150). REPEATABLE READ la impide abortando a B (valor final 200) |
| 64 | DD_CC_C1.png | Concurrencia C1: interbloqueo local | PostgreSQL detecta el ciclo y aborta una víctima (`deadlock detected`) |
| 65–66 | DD_CC_C2_p1/p2.png | Concurrencia C2: interbloqueo distribuido | Cada nodo ve una sola espera y el contador de deadlocks del NORTE sigue en 0. Se resuelve por `statement_timeout` |

**Validación pendiente.** Las capturas se tomaron con psql y SQL\*Plus. Si la docente exige capturas de DBeaver, se pueden repetir los mismos scripts en DBeaver; los resultados son idénticos.
