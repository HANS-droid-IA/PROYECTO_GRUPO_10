# AVANCE 1 (PC1) — Modelo ER, modelo relacional, implementación en PostgreSQL y comparativa con Oracle

> Capítulos 5 a 8 del *Formato Único de Informe*. Todas las cifras provienen de ejecuciones reales. Las salidas completas están en `01_Relacional_PostgreSQL/evidencias/` y `02_Oracle/evidencias/`; sirven de base para las capturas de pantalla del informe.

---

## 5. DISEÑO DE LA BASE DE DATOS RELACIONAL

### 5.1 Identificación de entidades, atributos y relaciones

| Entidad | Descripción | Atributos clave |
|---|---|---|
| REGION | Macro-región y nodo de BD que la administra | id_region, codigo, nombre, nodo |
| CIUDAD | Ciudad con cobertura (UBIGEO INEI) | id_ciudad, ubigeo, tiene_aeropuerto, acceso_terrestre |
| HUB | Nodo logístico: hub central, hub regional o agencia. Jerarquía recursiva | id_hub, codigo, tipo, id_hub_padre, capacidad_hora |
| TIPO_SERVICIO | Servicio contratable (modalidad y SLA) | id_servicio, modalidad, sla_horas, peso_max_kg |
| TARIFA | Precio por servicio y par de regiones, con vigencia | precio_base, precio_kg_adicional, vigente_desde/hasta |
| RUTA | Tramo entre dos hubs por una modalidad | id_hub_origen, id_hub_destino, modalidad, distancia_km, tiempo_estimado_horas |
| VEHICULO | Unidad propia (camión, furgoneta, moto) | placa, tipo, capacidad_kg, id_hub_base |
| EMPLEADO | Personal por hub y cargo | dni, cargo, id_hub |
| CLIENTE | Remitente: persona (DNI/CE) o empresa (RUC) | tipo_cliente, tipo_documento, nro_documento |
| DESTINATARIO | Persona que recibe | nombre, documento, teléfono |
| ENVIO | Unidad de servicio con tracking | nro_tracking, fechas de registro, compromiso y entrega, estado_actual, monto_total |
| PAQUETE | Bulto físico de un envío | nro_bulto, peso_kg, dimensiones, fragil |
| COMPROBANTE | Boleta o factura del envío | serie, numero, subtotal, igv, total |
| DESPACHO | Manifiesto: consolidación de envíos en un tramo | codigo_manifiesto, id_ruta, vehículo **o** vuelo, salida programada/real, llegada |
| DESPACHO_ENVIO | Asociación N:M despacho–envío | (id_despacho, id_envio), fecha_carga |
| EVENTO_TRACKING | **Escaneo** (elemento diferenciador) | tipo_evento, id_hub, id_empleado, id_despacho, fecha_hora |
| INTENTO_ENTREGA | Visita del courier (máx. 3) | nro_intento, resultado, receptor |
| INCIDENCIA | Daño, pérdida, retraso o dirección incorrecta | tipo, estado, fecha_reporte, fecha_cierre |

*Tabla 7. Entidades del modelo. Fuente: elaboración propia.*

**Relaciones principales:**
- Una REGION agrupa ciudades (1:N); una CIUDAD ubica hubs (1:N).
- Un HUB depende de otro HUB (relación recursiva 1:N: agencia → hub regional → hub central).
- Un CLIENTE remite envíos (1:N); un ENVIO contiene paquetes (1:N, dependencia de existencia) y tiene exactamente un COMPROBANTE (1:1).
- ENVIO y DESPACHO se relacionan N:M (un envío viaja en varios tramos y un despacho lleva muchos envíos). Se resuelve con DESPACHO_ENVIO.
- Un ENVIO genera muchos EVENTO_TRACKING, cada uno en un HUB, opcionalmente asociado a un DESPACHO y a un EMPLEADO.

### 5.2 Modelo conceptual: Diagrama Entidad-Relación (DER)

El DER está en `07_Documentacion/diagramas/modelo_ER.mmd`, en formato Mermaid.

**Para la figura del informe:**
- Pegar el archivo en <https://mermaid.live> y exportar como PNG/SVG.
- O usar DBeaver: conectar a `olva_courier`, clic derecho sobre los schemas `maestro` y `operacion` → *View Diagram*. Genera el diagrama desde la base real.

*Figura 1. DER del sistema de trazabilidad. Fuente: elaboración propia.*

### 5.3 Modelo lógico relacional

Notación: **subrayado = PK**, *cursiva = FK*.

- maestro.region(**id_region**, codigo, nombre, nodo)
- maestro.ciudad(**id_ciudad**, nombre, departamento, *id_region*, ubigeo, tiene_aeropuerto, acceso_terrestre, latitud, longitud)
- maestro.hub(**id_hub**, codigo, nombre, tipo, *id_ciudad*, *id_hub_padre*, capacidad_hora, direccion, activo)
- maestro.tipo_servicio(**id_servicio**, codigo, nombre, modalidad, sla_horas, peso_max_kg)
- maestro.tarifa(**id_tarifa**, *id_servicio*, *id_region_origen*, *id_region_destino*, precio_base, precio_kg_adicional, vigente_desde, vigente_hasta)
- maestro.ruta(**id_ruta**, *id_hub_origen*, *id_hub_destino*, modalidad, distancia_km, tiempo_estimado_horas, activa)
- maestro.vehiculo(**id_vehiculo**, placa, tipo, capacidad_kg, *id_hub_base*, activo)
- maestro.empleado(**id_empleado**, dni, nombres, apellidos, cargo, *id_hub*, fecha_ingreso, activo)
- maestro.cliente(**id_cliente**, tipo_cliente, tipo_documento, nro_documento, nombre_razon_social, email, telefono, direccion, *id_ciudad*, fecha_registro)
- operacion.destinatario(**id_destinatario**, nombre, tipo_documento, nro_documento, telefono)
- operacion.envio(**id_envio**, nro_tracking, *id_cliente*, *id_destinatario*, *id_servicio*, *id_hub_origen*, *id_hub_destino*, direccion_entrega, fecha_registro, fecha_compromiso, estado_actual, peso_total_kg, valor_declarado, monto_total, fecha_entrega)
- operacion.paquete(**id_paquete**, *id_envio*, nro_bulto, peso_kg, largo_cm, ancho_cm, alto_cm, descripcion, fragil)
- operacion.comprobante(**id_comprobante**, *id_envio*, tipo, serie, numero, fecha_emision, subtotal, igv, total, metodo_pago)
- operacion.despacho(**id_despacho**, codigo_manifiesto, *id_ruta*, *id_vehiculo*, nro_vuelo, fecha_salida_prog, fecha_salida_real, fecha_llegada_real, estado)
- operacion.despacho_envio(***id_despacho***, ***id_envio***, fecha_carga)
- operacion.evento_tracking(**id_evento**, *id_envio*, tipo_evento, *id_hub*, *id_empleado*, *id_despacho*, fecha_hora, observacion)
- operacion.intento_entrega(**id_intento**, *id_envio*, nro_intento, fecha_hora, *id_courier*, resultado, receptor_nombre, receptor_documento)
- operacion.incidencia(**id_incidencia**, *id_envio*, tipo, *id_hub*, fecha_reporte, descripcion, estado, fecha_cierre)
- auditoria.log_estado_envio(**id_log**, id_envio, estado_anterior, estado_nuevo, fecha_cambio, usuario_bd)
- seguridad.usuario_nodo(**usuario**, nodo)

**Total: 20 tablas.** 18 son de negocio, más una de auditoría y una de seguridad.

### 5.4 Normalización

**Primera Forma Normal (1FN): atributos atómicos y sin grupos repetitivos.**
- Un envío puede tener varios bultos. En lugar de columnas `peso_bulto1`, `peso_bulto2`… o un arreglo, se creó la tabla **PAQUETE** con una fila por bulto (`UNIQUE(id_envio, nro_bulto)`).
- El historial de estados no se guarda como una lista dentro del envío: cada escaneo es una fila de **EVENTO_TRACKING**.
- Las ubicaciones se separan en ciudad → región en lugar de un texto "Arequipa, Sur".

**Segunda Forma Normal (2FN): sin dependencias parciales de una clave compuesta.**
- La única clave compuesta de negocio es **DESPACHO_ENVIO(id_despacho, id_envio)**. Su único atributo no clave, `fecha_carga`, depende de la combinación completa (cuándo se cargó *ese* envío en *ese* manifiesto).
- Los datos del despacho (ruta, vehículo, horas) dependen solo de `id_despacho`, así que viven en DESPACHO. Los datos del envío dependen solo de `id_envio`, así que viven en ENVIO.
- Lo mismo ocurre con TARIFA: su candidata compuesta `(id_servicio, id_region_origen, id_region_destino, vigente_desde)` determina el precio completo. El nombre del servicio, que depende solo de `id_servicio`, está en TIPO_SERVICIO.

**Tercera Forma Normal (3FN): sin dependencias transitivas.**
- `envio → id_hub_origen → id_ciudad → id_region → nodo`. Ciudad, región y nodo **no** se guardan en ENVIO; se obtienen por JOIN.
- `despacho → id_ruta → (id_hub_origen, id_hub_destino, modalidad)`. Origen, destino y modalidad no se repiten en DESPACHO.
- `envio → id_cliente → tipo_cliente`. El tipo de cliente determina el tipo de comprobante; no se duplica en ENVIO.
- El destinatario es una entidad propia. Así se evita repetir nombre y teléfono en cada envío; el 12 % de los envíos reutiliza un destinatario.

**Desnormalizaciones controladas.** Son decisiones conscientes, cada una con su mecanismo de consistencia:

| Atributo | Derivable de | Motivo | Cómo se mantiene consistente |
|---|---|---|---|
| `envio.estado_actual` | Último evento de `evento_tracking` | Se consulta en cada tracking y en el índice parcial de envíos vivos. Recalcularlo exigiría ordenar ~10 eventos por envío | Trigger `trg_evento_actualiza_estado` + auditoría |
| `envio.fecha_entrega` | Evento `ENTREGA` | Base de todos los KPIs de SLA | Mismo trigger + `CHECK (estado='ENTREGADO') = (fecha_entrega IS NOT NULL)` |
| `envio.peso_total_kg`, `monto_total` | Suma de paquetes / tarifa vigente | La tarifa cambia con el tiempo; el monto cobrado es un **hecho histórico** que no debe recalcularse | Calculados una sola vez en `sp_registrar_envio` |

*Tabla 8. Desnormalizaciones justificadas. Fuente: elaboración propia.*

---

## 6. IMPLEMENTACIÓN EN POSTGRESQL

### 6.1 Estructura de funcionamiento y creación de la base de datos

- **Entorno:** Docker Compose, contenedor `olva_pg_lima` (PostgreSQL 16.15), zona horaria `America/Lima`.
- **Creación reproducible con un solo comando:**

  ```
  docker exec olva_pg_lima bash /proyecto/01_Relacional_PostgreSQL/00_crear_bd.sh
  ```

  El script recrea `olva_courier` (UTF8) y ejecuta en orden:

| Script | Contenido |
|---|---|
| `01_ddl_esquemas_tablas.sql` | Schemas, 20 tablas, restricciones, 16 índices |
| `02_funciones.sql` | 4 funciones PL/pgSQL |
| `03_procedimientos.sql` | 4 procedimientos |
| `04_carga_datos.sql` | Carga masiva con COPY y sincronización de secuencias |
| `05_triggers.sql` | 3 triggers |
| `06_vistas.sql` | 2 vistas y 1 vista materializada |
| `07_seguridad_roles.sql` | Roles, usuarios, GRANT/REVOKE, RLS |

Tiempo total de creación y carga: ~25 s. Tamaño de la BD: **115 MB**.

### 6.2 Arquitectura de schemas

| Schema | Propósito | Tablas |
|---|---|---|
| `maestro` | Catálogos y datos de referencia, que cambian poco | region, ciudad, hub, tipo_servicio, tarifa, ruta, vehiculo, empleado, cliente |
| `operacion` | Transacciones del ciclo de vida del envío, de alto volumen | destinatario, envio, paquete, comprobante, despacho, despacho_envio, evento_tracking, intento_entrega, incidencia |
| `auditoria` | Bitácora escrita solo por triggers | log_estado_envio |
| `seguridad` | Soporte de políticas RLS | usuario_nodo |

*Tabla 9. Schemas. Fuente: elaboración propia.*

Separar schemas permite otorgar privilegios por bloque, por ejemplo `GRANT USAGE ON SCHEMA maestro`. También separa los catálogos, que se replicarán en todos los nodos, de los datos operativos, que se fragmentarán (Avance 2).

### 6.3 Tablas, claves primarias, claves foráneas y restricciones

- **PK:** `GENERATED BY DEFAULT AS IDENTITY` (estándar SQL, en lugar de `serial`). La PK de `despacho_envio` es compuesta.
- **FK:** 30 claves foráneas. `paquete` usa `ON DELETE CASCADE` porque es una entidad débil.
- **UNIQUE:** `nro_tracking`; `(tipo_documento, nro_documento)`; `(serie, numero)`; `placa`; `ubigeo`; `(id_envio, nro_bulto)`; `(id_envio, nro_intento)`; entre otras.
- **CHECK de dominio:** listas cerradas de estados, tipos y modalidades; formatos con expresiones regulares (`^OLV[0-9]{10}$`, DNI de 8 dígitos, RUC `^(10|20)[0-9]{9}$`, placa `ABC-123`, serie `^[BF][0-9]{3}$`, email).
- **CHECK de reglas de negocio:**

| Restricción | Regla |
|---|---|
| `ck_hub_jerarquia` | Solo el hub central no tiene padre |
| `ck_ciudad_accesible` | Toda ciudad tiene aeropuerto o carretera |
| `ck_cliente_empresa_ruc` | Una empresa siempre tiene RUC 20… |
| `ck_despacho_transporte` | Un despacho tiene vehículo **o** vuelo, nunca ambos: `(id_vehiculo IS NULL) <> (nro_vuelo IS NULL)` |
| `ck_despacho_estado` | Coherencia entre estado y fechas reales |
| `ck_envio_entregado` | ENTREGADO ⇔ tiene fecha de entrega |
| `ck_comprobante_total` | subtotal + IGV = total (±0,01) |
| `ck_comprobante_serie_tipo` | Serie F para factura, B para boleta |
| `ck_intento_receptor` | Entregado ⇔ hay receptor |
| `ck_evento_despacho` | Un movimiento físico (salida o llegada) siempre tiene manifiesto |

*Tabla 10. Restricciones de negocio. Fuente: `01_ddl_esquemas_tablas.sql`.*

- **Índices:** 16 índices B-tree sobre FKs y patrones de acceso. Destaca el **índice parcial** `ix_envio_estado_activo ... WHERE estado_actual NOT IN ('ENTREGADO','DEVUELTO')`: indexa solo los ~426 envíos vivos y no los ~30 mil.

### 6.4 Estrategia de inserción y poblamiento de datos

1. **Generador propio** en Python 3.12, sin dependencias externas y con semilla fija (2026) para reproducibilidad: `generador/generar_datos.py`. No es una lista aleatoria de filas: **simula la operación**.
   - Volumen diario con estacionalidad semanal (domingo al 25 %), campaña de Fiestas Patrias (×1,45 del 10 al 27 de julio) y tendencia de +0,2 %/día.
   - Clientes con distribución de Pareto: pocas empresas concentran muchos envíos.
   - Camino de cada envío calculado con **Dijkstra** sobre la red de 98 rutas.
   - Consolidación en despachos con horarios fijos y **capacidad**; por ejemplo, los vuelos a Iquitos admiten 25 envíos.
   - Tiempos de clasificación log-normales con **congestión inyectada**: Hub Central ×2,4 entre 18:00 y 02:00 y ×1,3 los lunes; Arequipa ×1,9 en agosto y setiembre (déficit de personal simulado).
   - Demoras y bloqueos de vía; reparto sin domingos; 86 % de éxito por intento; pérdidas (0,15 %) y daños (0,6 %).
2. **Salida:** 18 archivos CSV (~36 MB).
3. **Carga** con `COPY` dentro de una transacción, **antes** de crear los triggers: el estado ya viene consistente, como en una migración de histórico. Luego se sincronizan las secuencias IDENTITY con `setval` y se ejecuta `ANALYZE`.

| Tabla | Filas |
|---|---:|
| evento_tracking | 315 101 |
| despacho_envio | 82 894 |
| paquete | 40 714 |
| intento_entrega | 33 557 |
| envio / comprobante | 29 966 c/u |
| destinatario | 26 413 |
| despacho | 22 729 |
| cliente | 3 000 |
| incidencia | 1 904 |
| catálogos (región, ciudad, hub, servicio, tarifa, ruta, vehículo, empleado) | 5 / 17 / 38 / 4 / 100 / 98 / 141 / 285 |

*Tabla 11. Volumen cargado. Fuente: `evidencias/00_generador_salida.txt`.*

### 6.5 Consultas SQL representativas

Las 13 consultas están en `08_consultas.sql` y su salida en `evidencias/08_consultas_resultado.txt`. El conjunto completo corre en **1,5 s**. Para el informe, cada consulta sigue la estructura *Problema → SQL → Captura → Interpretación*.

| N.° | Problema de negocio | Técnicas SQL | Resultado e interpretación |
|---|---|---|---|
| C01 | Reconstruir el recorrido de un envío y ver en qué tramo se demoró | JOIN ×5, LEFT JOIN, `LAG()` | El envío OLV2600001112 (Arequipa → Lima) muestra 11 escaneos. La mayor espera es en HC-LIM (13 h entre clasificación y salida), que coincide con el cuello de botella |
| C02 | Cumplimiento de SLA por servicio y mes | `FILTER`, `DATE_TRUNC` | Económico ~99 %, Estándar ~91–93 %, aéreos ~85–90 %. Julio (campaña) es el peor mes de Express (85,8 %) |
| C03 | Ranking de hubs y franjas horarias por permanencia | Función de tabla, `LEAD()`, `PERCENTILE_CONT` | **HC-LIM entre 18 y 24 h**: 14 270 llegadas, permanencia media de 14,5 h y P90 de 27,1 h. Es el cuello de botella principal |
| C04 | Impacto de la permanencia en HC sobre el SLA | Vista materializada, `DISTINCT ON` | Aéreo: 88,7 % → **81,0 %** cuando pasa más de 12 h en HC. Terrestre: 96,1 % → 91,3 % |
| C05 | Rutas con salidas o viajes tardíos | Auto-JOIN de hub, `HAVING` | Las troncales terrestres a Cusco y Juliaca se desvían +1,2 a +1,5 h; ~12 % de las salidas HC → Juliaca se demoran más de 1 h |
| C06 | Corredores más rentables | `ROLLUP`, `GROUPING()` | Lima origina el 69 % de los ingresos (S/ 561 845 de S/ 812 292). El ticket hacia Oriente es el más alto (~S/ 39) por ser solo aéreo |
| C07 | Top 10 clientes empresariales | CTE, `RANK()`, `SUM() OVER ()` | Los 3 primeros concentran el 9,5 % de la facturación empresarial. *Textil Los Andes* (Cusco) tiene solo 80,7 % de puntualidad: cuenta en riesgo |
| C08 | Entrega al primer intento y motivos | Agregación condicional, `STRING_AGG` | Tacna (83,5 %) e Iquitos (84,0 %) son las más bajas. El motivo principal es destinatario AUSENTE |
| C09 | Alerta de envíos vencidos o en riesgo | `fn_estado_sla`, índice parcial | Lista de envíos vivos vencidos: casos de pérdida pendientes de cierre |
| C10 | Incidencias por hub y tiempo de resolución | LEFT JOIN, `FILTER` | HC-LIM concentra 52 de 126 daños (41 %). Los reclamos por retraso se resuelven en ~2,4 días |
| C11 | Productividad de couriers | `DENSE_RANK() OVER (PARTITION BY)` | ~3,3 a 3,6 entregas por día por courier en Lima; sirve para dimensionar personal |
| C12 | Envíos estancados más de 48 h | `CROSS JOIN LATERAL`, `EXISTS` | Todos los estancados tienen incidencia de pérdida registrada: el control funciona |
| C13 | Ocupación horaria de HC vs capacidad | `generate_series`, LEFT JOIN | **A las 20:00 llegan 54,8 envíos/h, el 110 % de la capacidad (50/h)**. A las 14:00, el 67 % |

*Tabla 12. Consultas representativas. Fuente: `evidencias/08_consultas_resultado.txt`.*

---

## 7. PROGRAMACIÓN Y ADMINISTRACIÓN DE LA BASE DE DATOS

### 7.1 Funciones almacenadas (PL/pgSQL)

| Función | Tipo | Propósito |
|---|---|---|
| `maestro.fn_calcular_tarifa(servicio, reg_origen, reg_destino, peso, fecha)` | Escalar, `STABLE` | Tarifa vigente a la fecha: base + ⌈peso − 1⌉ × precio por kg adicional. Valida peso > 0 y que no exceda el máximo del servicio |
| `operacion.fn_estado_sla(id_envio, corte)` | Escalar | ENTREGADO_A_TIEMPO / CON_RETRASO / DEVUELTO / VENCIDO / EN_RIESGO (< 6 h) / EN_PLAZO |
| `operacion.fn_permanencia_hub(id_envio, id_hub, corte)` | SQL | Intervalo entre la llegada y la salida de un envío en un hub |
| `operacion.fn_cuellos_botella(desde, hasta, umbral_h)` | **Función de tabla** | Ranking de hubs por franja: envíos, permanencia media, P90 y % sobre el umbral. Usa una sola pasada con `LEAD()` |

*Evidencia:* `09_pruebas_procedimientos_resultado.txt`. Ejemplos: Express Lima → Oriente de 12 kg = S/ 103,50; un sobre de 3 kg se rechaza con *"Peso 3.0 kg excede el máximo del servicio (0.50 kg)"*.

### 7.2 Procedimientos almacenados (PL/pgSQL)

| Procedimiento | Reglas que implementa |
|---|---|
| `sp_registrar_envio` | Una sola transacción: valida cliente, servicio y agencias; **rechaza servicios terrestres hacia ciudades sin carretera** (Iquitos); calcula peso, tarifa y compromiso (20:00 del día del SLA, sin domingos); inserta destinatario, envío, paquetes (JSONB), comprobante con numeración correlativa por serie (`pg_advisory_xact_lock`) y evento ADMISION |
| `sp_registrar_escaneo` | **Máquina de estados**: solo permite transiciones válidas (p. ej. EN_TRANSITO → solo LLEGADA_HUB). Valida que el hub coincida con la ruta del despacho y que el reparto empiece en la agencia destino. Impide escaneos con fecha anterior al último. Usa `SELECT … FOR UPDATE` para serializar escaneos concurrentes del mismo envío |
| `sp_registrar_intento_entrega` | Numera los intentos (máx. 3); exige receptor si se entrega; abre una incidencia automática si la dirección es errada; registra DEVOLUCION si el destinatario rechaza o fallan 3 intentos |
| `sp_cerrar_despacho` | Marca el manifiesto como ARRIBADO y registra en bloque la LLEGADA_HUB de todos sus envíos en tránsito |

**Triggers:**
- `trg_evento_actualiza_estado`: sincroniza `estado_actual` y `fecha_entrega`.
- `trg_log_estado_envio`: auditoría con `session_user`.
- `trg_validar_despacho`: valida reglas entre tablas. La modalidad de la ruta exige vuelo o vehículo, y el vehículo debe pertenecer a un extremo de la ruta.

**Evidencia** (`09_pruebas_procedimientos_resultado.txt`):
- Se simula el ciclo completo de un envío Miraflores → Surco: 10 eventos, un intento fallido y la entrega, con resultado ENTREGADO_A_TIEMPO.
- La auditoría registra los 10 cambios de estado.
- Se prueban **5 errores controlados**: peso excedido, terrestre a Iquitos, vehículo ajeno a la ruta, transición inválida y entrega sin receptor.
- Todo corre dentro de `BEGIN … ROLLBACK`, así que los datos de prueba no cambian.

### 7.3 Seguridad y gestión de accesos

**Modelo RBAC.** Los permisos se otorgan a roles de grupo `NOLOGIN` y los usuarios los heredan:

| Rol | Usuarios | Privilegios |
|---|---|---|
| `rol_admin_olva` | u_admin_bd | ALL en schemas; `CREATEROLE`; `BYPASSRLS` |
| `rol_operador_hub` | u_op_lima, u_op_norte, u_op_sur | SELECT de catálogos; **SELECT por columnas** de envío (sin montos); EXECUTE solo de procedimientos de escaneo, despacho y entrega |
| `rol_atencion_cliente` | u_atencion | Vista de tracking; INSERT/UPDATE parcial de cliente e incidencias; EXECUTE `sp_registrar_envio` |
| `rol_facturacion` | u_facturacion | SELECT de comprobantes, envíos y clientes |
| `rol_analista` | u_analista | SELECT de vistas analíticas (sin datos personales); EXECUTE `fn_cuellos_botella` |

*Tabla 13. Roles y privilegios. Fuente: `07_seguridad_roles.sql`.*

**Endurecimiento:**
- `REVOKE ALL ON DATABASE … FROM PUBLIC`.
- `REVOKE ALL ON SCHEMA public`.
- Se revoca EXECUTE por defecto de funciones y procedimientos.
- Límite de conexiones para los operadores.
- `VALID UNTIL '2026-12-31'` para el analista externo.

### 7.4 Políticas de seguridad y control de accesos

1. **Escritura solo vía procedimientos.** Los procedimientos son `SECURITY DEFINER` con `search_path` fijo. Los operadores **no** tienen INSERT ni UPDATE sobre las tablas, así que toda escritura pasa por las validaciones del negocio.
2. **Row Level Security (RLS)** sobre `envio` y `evento_tracking`. Cada operador ve solo los envíos que salen de su nodo o llegan a él, según la tabla `seguridad.usuario_nodo`:
   - u_op_lima ve 27 023 envíos;
   - u_op_norte ve 11 347;
   - u_op_sur ve 8 658;
   - el administrador ve los 29 966.
3. **Privilegios por columna:** el operador no puede leer `monto_total` (*permission denied*).
4. **Vistas como frontera de datos personales:** el analista lee `vw_envio_analitico` pero no `maestro.cliente`.
5. **REVOKE en vivo:** se retira el acceso del analista a la vista (falla) y se restituye (29 966 filas).

*Evidencia:* `10_pruebas_seguridad_resultado.txt`, con 7 accesos denegados esperados.

### 7.5 Backup y restauración

Script: `11_backup_restauracion.sh`. Evidencia: `11_backup_restauracion_log.txt`.

| Paso | Herramienta | Resultado |
|---|---|---|
| 1. Respaldo lógico completo | `pg_dump -Fc -Z 6` | Archivo `.dump` de 7,7 MB en 4 s (20 tablas con datos) |
| 2. Respaldo de roles | `pg_dumpall --globals-only` | 13 roles y usuarios |
| 3. Respaldo **físico** en caliente | `pg_basebackup -Ft -z` | `base.tar.gz` de 28 MB + `backup_manifest` |
| 4. Incidente simulado | `DELETE FROM operacion.incidencia` | 1 904 → 0 filas |
| 5. Restauración **selectiva** | `pg_restore --data-only --table=incidencia` | 1 904 filas recuperadas |
| 6. Restauración **completa** en BD nueva | `pg_restore --jobs=4` | 2 s; **18/18 tablas con conteo idéntico**, 13 funciones y procedimientos, 3 triggers y 4 políticas RLS restaurados |

*Tabla 14. Estrategia de respaldo. Fuente: elaboración propia.*

**Estrategia propuesta para producción:**
- `pg_basebackup` semanal con archivado continuo de WAL, para recuperación a un punto en el tiempo (PITR).
- `pg_dump` diario para restauraciones selectivas.
- Copias fuera del servidor.

**Lección aprendida.** La primera restauración tardó ~6 min porque la vista materializada, escrita con `LATERAL`, se refrescaba sin estadísticas y elegía un mal plan. Al reescribirla con funciones de ventana (`LEAD`), una sola pasada sobre los eventos, la restauración bajó a 2 s.

---

## 8. IMPLEMENTACIÓN PARCIAL Y COMPARACIÓN CON ORACLE

### 8.1 Cuadro comparativo de arquitecturas: PostgreSQL vs. Oracle vs. SQL Server

| Aspecto | PostgreSQL 16 | Oracle Database (23ai/26ai) | SQL Server |
|---|---|---|---|
| Modelo de procesos | Multiproceso: *postmaster* + un proceso *backend* por conexión + procesos de fondo (checkpointer, background writer, WAL writer, autovacuum) | Instancia = SGA + procesos de fondo (DBWn, LGWR, CKPT, SMON, PMON, ARCn) + procesos servidor dedicados o compartidos | Un solo proceso multihilo; planificador propio (SQLOS) |
| Memoria compartida | `shared_buffers`, más la caché de páginas del sistema operativo (doble buffer) | **SGA**: buffer cache, shared pool (library y dictionary cache), redo log buffer, large/java pool | Buffer pool, plan cache, `max server memory` |
| Memoria por sesión | `work_mem` (por operación de ordenamiento o hash), `maintenance_work_mem` | **PGA** (sort/hash area), gestión automática | Memory grants por consulta |
| Almacenamiento lógico | Cluster → bases de datos → schemas → tablas | Base de datos (CDB/PDB) → **tablespaces** → segmentos → extensiones → bloques | Base de datos → filegroups → archivos |
| Almacenamiento físico | Un archivo por tabla o índice (segmentos de 1 GB), páginas de 8 KB, TOAST para valores grandes; tablespace = directorio | Datafiles por tablespace; bloques de 8 KB por defecto; control files | `.mdf`/`.ndf` (datos) y `.ldf` (log); páginas de 8 KB, extents de 64 KB |
| Registro de transacciones | WAL (`pg_wal`) | Redo logs en línea + archivados (ARCHIVELOG) | Transaction log (`.ldf`) |
| Control de concurrencia (MVCC) | Versiones de fila en la propia tabla (xmin/xmax); requiere **VACUUM** | Lectura consistente reconstruida desde **UNDO** | Por defecto, bloqueos; versionado opcional (RCSI/Snapshot) en tempdb |
| Motor de ejecución / optimizador | Planificador basado en costos; GEQO para muchos JOINs; consultas paralelas; sin *hints* nativos | Optimizador basado en costos con *hints*, planes adaptativos, SQL Plan Management | Optimizador basado en costos, Query Store, *hints* |
| Lenguaje procedural | PL/pgSQL (+ PL/Python, PL/Perl…) | PL/SQL con **paquetes** | T-SQL |
| Respaldo | `pg_dump`/`pg_restore` (lógico), `pg_basebackup` + WAL (físico, PITR) | **RMAN** (físico), **Data Pump** expdp/impdp (lógico), Flashback | `BACKUP DATABASE` full/diferencial/log |
| Licencia | Open source (PostgreSQL License) | Comercial; edición *Free* limitada (2 hilos de CPU, 2 GB de RAM, 12 GB de datos de usuario) | Comercial; Express gratuita limitada |

*Tabla 15. Comparación de arquitecturas. Fuente: elaboración propia con base en la documentación oficial de cada motor.*

### 8.2 Implementación parcial en Oracle

- **Entorno:** contenedor `olva_oracle` con *Oracle AI Database 26ai Free* (23.26), PDB `FREEPDB1`, esquema `OLVA`.
- **Ejecución:**

  ```
  docker exec olva_oracle bash /proyecto/02_Oracle/00_ejecutar_todo.sh
  ```

- **8 tablas** (el mínimo era 3): región, ciudad, hub, tipo_servicio, tarifa, cliente, envío, evento_tracking, más `log_error`.
- **Restricciones:** PK, FK (incluida la recursiva de hub), UNIQUE y CHECK con `REGEXP_LIKE`.
- **Datos idénticos** a PostgreSQL: los genera `generar_inserts_oracle.py` desde los mismos CSV. Son 1 000 envíos, 483 clientes y 10 627 eventos.
- **Consultas básicas:**
  - envíos por estado;
  - SLA por servicio: Económico 99,5 %, Estándar 94,1 %, Express 86,8 %, Sobre 88,1 %. Son resultados coherentes con PostgreSQL sobre la muestra.
  - top-N y línea de tiempo con `LAG`.
- **PL/SQL:**
  - paquete `pkg_tracking` con `fn_calcular_tarifa`, `fn_estado_sla` y `sp_registrar_escaneo`;
  - trigger `trg_evento_actualiza_estado`;
  - procedimiento autónomo `sp_log_error`.
- **Seguridad:**
  - `PROFILE` con 3 intentos fallidos (la cuenta queda **LOCKED(TIMED)**), vida de contraseña y sesiones por usuario;
  - roles `rol_analista_ora` y `rol_operador_ora`;
  - cuota 0 en el tablespace USERS;
  - el operador escribe solo vía `EXECUTE` del paquete.
- **Respaldo Data Pump:**
  - `expdp` del esquema: 9 tablas en un `.dmp` de 1,6 MB;
  - `DROP TABLE evento_tracking` simulado;
  - `impdp TABLES=evento_tracking` recupera 10 627 filas, 9 constraints, 3 índices y el trigger;
  - recompilación del paquete, que el DROP había dejado INVALID.

### 8.3 Comparación de sintaxis y programación: PL/pgSQL vs. PL/SQL

| Característica | PostgreSQL | Oracle | Demostrado en |
|---|---|---|---|
| Autoincremento | `GENERATED BY DEFAULT AS IDENTITY` | `GENERATED BY DEFAULT ON NULL AS IDENTITY` | DDL |
| Tipos | `VARCHAR`, `INTEGER`, `NUMERIC`, `TIMESTAMPTZ` | `VARCHAR2`, `NUMBER`, `TIMESTAMP WITH TIME ZONE` | DDL |
| Booleano | `BOOLEAN` desde siempre | `BOOLEAN` en SQL solo desde 23ai (antes `NUMBER(1)`/`CHAR(1)`) | ciudad, hub |
| Regex en CHECK | `col ~ '^…$'` | `REGEXP_LIKE(col, '^…$')` | DDL |
| `DROP … IF EXISTS` | Sí | Solo desde 23ai | DDL |
| Cadena vacía | `''` ≠ `NULL` | **`''` IS NULL = TRUE** | O8 |
| Top-N | `LIMIT n` / `FETCH FIRST` | `FETCH FIRST n ROWS ONLY` / `ROWNUM` | O5 |
| Concatenar grupo | `STRING_AGG(x, ', ' ORDER BY x)` | `LISTAGG(x, ', ') WITHIN GROUP (ORDER BY x)` | O4 |
| Jerarquías | `WITH RECURSIVE` | `CONNECT BY PRIOR … START WITH`, `LEVEL`, `SYS_CONNECT_BY_PATH` | O3 |
| Upsert | `INSERT … ON CONFLICT DO UPDATE` | `MERGE INTO … USING … WHEN MATCHED / NOT MATCHED` | O9 |
| Tabla dummy | No hace falta (`SELECT 1`) | `FROM dual` (opcional desde 23ai) | O7 |
| Organización del código | Funciones y procedimientos sueltos en schemas | **PACKAGE** (especificación + cuerpo), con excepciones propias | `pkg_tracking` |
| Invocar procedimiento | `CALL sp(...)` | `EXEC sp(...)` / `BEGIN sp(...); END;` | P1 |
| Errores | `RAISE EXCEPTION '…' USING ERRCODE` | `RAISE_APPLICATION_ERROR(-20xxx, '…')`, `PRAGMA EXCEPTION_INIT` | Pruebas |
| Triggers | Función trigger separada + `CREATE TRIGGER … EXECUTE FUNCTION` | Cuerpo PL/SQL dentro del trigger, con `:NEW`/`:OLD` | Triggers |
| Transacción autónoma | No nativa (requiere dblink) | `PRAGMA AUTONOMOUS_TRANSACTION`: el log persiste aunque se haga ROLLBACK | P2 |
| Derechos de ejecución | Por defecto **invoker**; `SECURITY DEFINER` explícito | Por defecto **definer**; `AUTHID CURRENT_USER` explícito | Procedimientos |
| Usuario y esquema | Independientes (un usuario usa varios schemas) | **Usuario = esquema** | Seguridad |
| Políticas de contraseña | Solo `VALID UNTIL` | `PROFILE` (intentos, bloqueo, expiración, sesiones) | Seguridad |
| Seguridad por fila | RLS (`CREATE POLICY`) | VPD (`DBMS_RLS`) | — |

*Tabla 16. Diferencias de sintaxis y programación. Fuente: evidencias de `02_Oracle` y `01_Relacional_PostgreSQL`.*

### 8.4 Conclusiones del análisis comparativo relacional

1. El **modelo relacional es portable**: las 8 tablas se implementaron con las mismas restricciones y los KPIs coinciden sobre los mismos datos. Las diferencias están en tipos, sintaxis y herramientas, no en el diseño.
2. **Oracle aporta funcionalidades empresariales nativas** que en PostgreSQL requieren extensiones o diseño adicional: paquetes, transacciones autónomas, perfiles de contraseña, RMAN/Flashback y `CONNECT BY`.
3. **PostgreSQL es más flexible y sin costo de licencia**: tipos ricos (JSONB, que se usó para los paquetes), RLS integrada, índices parciales y extensiones como `postgres_fdw`, que es la base de la BD distribuida del Avance 2. Por eso se eligió como motor principal.
4. **Dos trampas observadas en la práctica:**
   - en Oracle, `''` es NULL, lo que afecta las validaciones de texto vacío;
   - en Oracle, un `DROP` invalida en cascada los objetos PL/SQL dependientes, que deben recompilarse (se vio con Data Pump).
