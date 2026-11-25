# HITO 2 + AVANCE 2 (PC2) — Base de datos distribuida

> Capítulo 9 del *Formato Único de Informe*. La propuesta (Hito 2) y la implementación (Avance 2) se presentan juntas. La capa NoSQL (MongoDB y Cassandra) del Avance 2 se desarrollará por separado.
> Las evidencias completas están en `03_BD_Distribuida/evidencias/`. El despliegue completo (3 nodos, migración, pruebas) se ejecuta en ~40 s:
>
> ```
> docker compose --profile distribuida up -d
> docker exec olva_pg_lima bash /proyecto/03_BD_Distribuida/00_desplegar.sh
> ```

---

## 9. DISEÑO DE BASE DE DATOS DISTRIBUIDA

### 9.1 Justificación técnica de la distribución

La operación de un courier nacional está **geográficamente distribuida por naturaleza**:

1. **Localidad de los datos.** Un envío se admite y se factura en su agencia de origen. Cada escaneo ocurre físicamente en un hub concreto. El operario de Arequipa trabaja casi siempre con datos de Arequipa, así que guardarlos en un nodo del Sur evita que cada escaneo viaje hasta Lima.
2. **Autonomía y disponibilidad.** Si se cae el enlace con Lima, el nodo Sur debe seguir registrando escaneos y entregas de sus agencias. Por eso cada nodo tiene sus fragmentos y una **réplica completa de los catálogos**: hubs, rutas, tarifas y servicios.
3. **Reparto de carga.** Los escaneos son la tabla de mayor crecimiento (~10,5 por envío). Fragmentarlos por el lugar donde ocurren reparte la escritura: el 38,5 % de los eventos ya no se escribe en Lima.
4. **Privacidad y cumplimiento.** Los datos tributarios del cliente (tipo y número de documento) se concentran en un solo nodo controlado, Lima/facturación. Los nodos regionales solo reciben lo necesario para el reparto (nombre y contacto).

### 9.2 Arquitectura propuesta

Son 3 nodos o sedes lógicas, cada uno en un contenedor PostgreSQL 16 independiente. La comunicación es con **postgres_fdw**, y el esquema global usa **tablas particionadas cuyas particiones son locales o remotas** (*foreign partitions*).

| Nodo | Contenedor / puerto | BD | Regiones que administra | Rol |
|---|---|---|---|---|
| **LIMA** | `olva_pg_lima` :5432 | `olva_lima` | Lima, Centro | Nodo de datos + **coordinador** (esquema global, 2PC, VF1 fiscal) |
| **NORTE** | `olva_pg_norte` :5433 | `olva_norte` | Norte, Oriente | Nodo de datos |
| **SUR** | `olva_pg_sur` :5434 | `olva_sur` | Sur | Nodo de datos |

*Tabla 17. Nodos de la BD distribuida. Fuente: elaboración propia.*

El diagrama está en `07_Documentacion/diagramas/arquitectura_distribuida.mmd`.

*Figura 2. Arquitectura distribuida de 3 nodos. Fuente: elaboración propia.*

**Capas de la arquitectura:**
- **Esquema global** (`olva_lima.global`): `envio`, `paquete`, `evento_tracking`, `cliente_contacto` y la vista `cliente`. La aplicación consulta estas relaciones sin saber dónde está cada fila: **transparencia de ubicación y de fragmentación**.
- **Esquema de fragmentación:** cada relación global es `PARTITION BY LIST (nodo)`.
- **Esquema de asignación:** la partición `LIMA` es una tabla local; `NORTE` y `SUR` son `FOREIGN TABLE` sobre `srv_norte` y `srv_sur`. Se puede consultar en `global.catalogo_fragmentos`.
- **Esquemas locales:** los tres nodos se crean con el **mismo script** (`01_ddl_nodo_regional.sql`, parámetro `nodo`). El diseño es homogéneo.

### 9.3 Fragmentación horizontal

**Predicados simples** sobre la relación `REGION.nodo`:
- p₁: nodo = 'LIMA' (regiones Lima y Centro)
- p₂: nodo = 'NORTE' (Norte y Oriente)
- p₃: nodo = 'SUR' (Sur)

Los minitérminos son mutuamente excluyentes y cubren el dominio, por lo que la fragmentación es completa y disjunta.

**HF1. Fragmentación primaria de ENVIO por nodo de la agencia de origen.**
```
ENVIO_i = σ nodo(hub_origen) = i (ENVIO),   i ∈ {LIMA, NORTE, SUR}
```
- *Criterio:* el envío "pertenece" a la sede que lo admite y factura. Ahí se consulta y se corrige con más frecuencia.
- *Integridad del predicado:* cada fragmento tiene `CHECK (maestro.fn_nodo_hub(id_hub_origen) = nodo)`. Al intentar insertar en el nodo SUR un envío de Lima, se rechaza con `violates check constraint "ck_predicado_fragmento"` (evidencia 04).

**HF2. Fragmentación derivada de PAQUETE.**
```
PAQUETE_i = PAQUETE ⋉ ENVIO_i
```
- Cada bulto vive en el mismo nodo que su envío. Eso permite mantener la **FK local** `paquete → envio` y ejecutar el JOIN dentro del nodo (ver Q3).

**HF3. Fragmentación primaria de EVENTO_TRACKING por nodo del hub donde ocurre el escaneo.**
```
EVENTO_i = σ nodo(id_hub) = i (EVENTO_TRACKING)
```
- *Criterio:* **localidad de escritura**. El escaneo se registra en el nodo de la sede física. Un envío Iquitos → Arequipa deja sus eventos en NORTE, LIMA y SUR (ver Q4).

**Distribución resultante** (evidencia `04_verificacion_resultado.txt`):

| Relación | LIMA | NORTE | SUR | Total |
|---|---:|---:|---:|---:|
| envio | 23 638 (78,9 %) | 3 166 (10,6 %) | 3 162 (10,6 %) | 29 966 |
| paquete | 32 216 | 4 235 | 4 263 | 40 714 |
| evento_tracking | 193 666 (61,5 %) | 68 442 (21,7 %) | 52 993 (16,8 %) | 315 101 |
| cliente_contacto | 1 749 | 742 | 509 | 3 000 |

*Tabla 18. Distribución de filas por nodo. Fuente: evidencia 04.*

**Análisis.** Fragmentar por **origen** concentra el 79 % de los envíos en Lima, porque Lima es el gran emisor (e-commerce). Fragmentar los eventos por **ubicación** reparte mejor la carga de escritura, ya que los destinos están más distribuidos. Por eso se combinaron ambos criterios.

### 9.4 Fragmentación vertical

**VF de CLIENTE.** Se basa en la afinidad de atributos según las aplicaciones que los usan:

| Atributo | A1 Facturación / SUNAT | A2 Reparto en sede | A3 Atención al cliente |
|---|:-:|:-:|:-:|
| id_cliente (clave) | ✔ | ✔ | ✔ |
| tipo_cliente, tipo_documento, nro_documento, fecha_registro | ✔ | | ✔ |
| nombre_razon_social, email, telefono, direccion, id_ciudad | | ✔ | ✔ |

*Tabla 19. Matriz de uso de atributos. Fuente: elaboración propia.*

```
VF1 = CLIENTE_FISCAL   = π id_cliente, tipo_cliente, tipo_documento, nro_documento, fecha_registro (CLIENTE)  → solo nodo LIMA
VF2 = CLIENTE_CONTACTO = π id_cliente, nombre_razon_social, email, telefono, direccion, id_ciudad (CLIENTE)
```

- **VF2 se fragmenta además horizontalmente** según el nodo de la ciudad del cliente. Es una **fragmentación mixta**: cada sede tiene los contactos de sus clientes, que son también los remitentes de sus envíos. Así la FK `envio.id_cliente → cliente_contacto` es local en todos los nodos.
- Ambos fragmentos repiten la clave `id_cliente`, que es la condición para reconstruir por JOIN:
  ```
  CLIENTE = VF1 ⋈ id_cliente (VF2_LIMA ∪ VF2_NORTE ∪ VF2_SUR)
  ```
  Implementado como la vista `global.cliente`.

### 9.5 Esquema de localización y asignación de datos

| Relación / fragmento | LIMA | NORTE | SUR | Tipo de asignación |
|---|:-:|:-:|:-:|---|
| region, ciudad, hub, tipo_servicio, tarifa, ruta | ✔ | ✔ | ✔ | **Replicación total** (cambian poco, se leen en cada operación) |
| ENVIO_i, PAQUETE_i, EVENTO_i, CLIENTE_CONTACTO_i | i = LIMA | i = NORTE | i = SUR | **Particionada** (sin réplica) |
| CLIENTE_FISCAL (VF1) | ✔ | | | **Centralizada** |
| comprobante, despacho, destinatario, incidencia, intento_entrega | ✔ (en `olva_courier`) | | | Centralizada en la sede principal en esta fase |
| global.log_2pc (bitácora del coordinador) | ✔ | | | Centralizada |

*Tabla 20. Esquema de asignación. Fuente: elaboración propia.*

**Corrección de la fragmentación** (evidencia 04), verificada contra la BD centralizada original vía `srv_origen`:

| Regla | Prueba | Resultado |
|---|---|---|
| Completitud | Conteo origen = Σ fragmentos (envío, paquete, evento, VF1, VF2) | 29 966 = 29 966; 40 714 = 40 714; 315 101 = 315 101; 3 000 = 3 000 ✔ |
| Disyunción | Claves repetidas entre fragmentos | 0 en envío, evento y cliente_contacto ✔ |
| Reconstrucción horizontal | `origen EXCEPT global` ∪ `global EXCEPT origen` | 0 filas distintas ✔ |
| Reconstrucción vertical | `cliente original` vs `VF1 ⋈ VF2` | 0 filas distintas ✔ |

*Tabla 21. Verificación de la fragmentación. Fuente: evidencia 04.*

**Migración** (`03_migracion_fragmentos.sql`): el particionamiento **enruta automáticamente** cada fila a su nodo, con inserciones remotas por lotes (`batch_size 1000`). Envíos: 2,3 s; eventos: 10,9 s.

### 9.6 Procesamiento y optimización de consultas distribuidas

El procesamiento se divide en tres etapas. Evidencia: `05_consultas_distribuidas_resultado.txt`, con `EXPLAIN VERBOSE` real.

1. **Descomposición:** la consulta SQL sobre relaciones globales se normaliza y se traduce a álgebra relacional.
2. **Localización de datos:** cada relación global se reemplaza por la unión de sus fragmentos y se **eliminan los fragmentos cuyo predicado contradice el filtro**. PostgreSQL lo hace con la **poda de particiones**.
3. **Optimización global:** se decide qué operaciones se ejecutan en cada nodo para minimizar la transferencia. postgres_fdw **empuja** selecciones, proyecciones, JOINs y agregaciones al nodo remoto (*Remote SQL*) y consulta los nodos **en paralelo** (`Async Foreign Scan`).

| Consulta | Álgebra / estrategia | Plan obtenido | Resultado |
|---|---|---|---|
| **Q1** Envíos del Sur retrasados en setiembre | `σ nodo=SUR ∧ mes ∧ retraso (ENVIO_LIMA ∪ ENVIO_NORTE ∪ ENVIO_SUR)` → se eliminan LIMA y NORTE | Solo `Foreign Scan on envio_sur`. El filtro completo viaja en el *Remote SQL* y solo vuelve el conteo | 107 envíos |
| **Q2** Envíos e ingresos por nodo y estado | γ sobre la unión = unión de γ por fragmento (*partitionwise aggregate*) | `HashAggregate` local en LIMA + `Async Foreign Scan … Aggregate on (envio_norte)` con `GROUP BY` remoto. Viajan ~7 filas por nodo en lugar de ~3 000 | 20 grupos |
| **Q3** Bultos frágiles en NORTE y SUR | JOIN co-localizado: `ENVIO_i ⋈ PAQUETE_i` por la fragmentación derivada | **Join pushdown**: `Relations: Aggregate on ((envio_norte) INNER JOIN (paquete_norte))`. El JOIN y la agregación se ejecutan dentro de cada nodo | NORTE 666, SUR 638 |
| **Q4** Tracking de un envío Iquitos → Arequipa | JOIN **no** co-localizado: el envío está en NORTE y sus eventos en los 3 nodos | Nested Loop: el envío se busca en los 3 fragmentos en paralelo; los eventos se piden con `WHERE id_envio = $1` a cada nodo | 14 eventos: 5 en NORTE, 3 en LIMA, 6 en SUR |
| **Q5** Empresas del Sur (reconstrucción vertical) | `VF1 ⋈ σ nodo=SUR (VF2)` | Foreign Scan solo sobre `cliente_contacto_sur` con filtro remoto + Hash Join local con `cliente_fiscal` | Clientes con RUC y teléfono reconstruidos |
| **Q6** Costo de la distribución | Global vs. localizada | 64,7 ms (3 nodos) vs. 30,5 ms (solo LIMA) | Localizar la consulta reduce el tiempo a la mitad |

*Tabla 22. Procesamiento de consultas distribuidas. Fuente: evidencia 05.*

**Técnicas de optimización aplicadas:**
- Poda de particiones (localización).
- *Pushdown* de selección, proyección, JOIN y agregación.
- *Partitionwise join* y *partitionwise aggregate* (`enable_partitionwise_*`).
- Escaneo asíncrono en paralelo (`async_capable`).
- `use_remote_estimate` para que el optimizador use estadísticas remotas.
- `fetch_size`/`batch_size` para reducir viajes de red.
- **Diseño co-localizado** (fragmentación derivada) para que los JOINs frecuentes no crucen nodos.

### 9.7 Manejo de transacciones distribuidas (Protocolo 2PC)

**Problema.** postgres_fdw confirma los nodos remotos **uno a uno**, sin 2PC. Si un nodo falla a mitad del commit, la transacción global queda parcialmente aplicada. Por eso el coordinador (Lima) implementa el protocolo explícitamente con `PREPARE TRANSACTION`, `COMMIT PREPARED` y `ROLLBACK PREPARED` (`max_prepared_transactions = 10` en los tres nodos). Script: `06_transaccion_2pc.sql`.

**Escenario de negocio.** Llega al Hub Regional Arequipa el manifiesto MF-DEMO-2PC, con dos envíos. Una sola operación de negocio escribe en **3 nodos**:

| Participante | Operación local |
|---|---|
| SUR | INSERT de 2 eventos `LLEGADA_HUB` (el escaneo ocurre en Arequipa) |
| LIMA | UPDATE del envío OLV2699990001 (origen Lima) → EN_HUB |
| NORTE | UPDATE del envío OLV2699990002 (origen Trujillo) → EN_HUB |

**Protocolo:**
- **Fase 1 (votación):** cada participante ejecuta su parte y hace `PREPARE TRANSACTION 'gtx_…_<nodo>'`. Si el PREPARE tiene éxito, el voto es **SÍ**: los cambios quedan persistidos en disco y los bloqueos retenidos. Un error es un voto **NO**.
- **Fase 2 (decisión):** el coordinador **registra la decisión en `global.log_2pc`** (registro previo de la decisión) y luego envía `COMMIT PREPARED` o `ROLLBACK PREPARED` a cada participante.

| Caso | Qué ocurre | Evidencia |
|---|---|---|
| **1. Éxito** | Los 3 nodos votan SÍ. Mientras están preparadas, `pg_prepared_xacts` muestra una transacción en cada nodo y los cambios **no son visibles** (los envíos siguen EN_TRANSITO). Tras COMMIT PREPARED: ambos envíos quedan EN_HUB y los 2 eventos están en SUR | log: INICIO → DECISION COMMIT (3/3) → FIN |
| **2. Un nodo vota NO** | Se reintenta por error el mismo arribo. SUR prepara (SÍ); LIMA detecta que el envío ya no está EN_TRANSITO y aborta (NO). El coordinador decide ROLLBACK y ejecuta `ROLLBACK PREPARED` en SUR. NORTE ya no se consulta | No quedaron eventos duplicados en SUR |
| **3. Falla del coordinador (en duda)** | NORTE prepara y el coordinador "cae" antes de la fase 2. La transacción **sobrevive a la desconexión** y **retiene bloqueos**: otra actualización del mismo envío falla con `lock timeout` a los 3 s. **Recuperación:** el coordinador lee su bitácora, no encuentra DECISION y aplica *presumed abort* → `ROLLBACK PREPARED`. Ahora la actualización pendiente sí procede | `transacciones_en_duda = 0` |

*Tabla 23. Escenarios de 2PC. Fuente: evidencia 06.*

El caso 3 ilustra la **principal debilidad del 2PC: es bloqueante**. Mientras el coordinador no decide, los participantes no pueden liberar los recursos. Por eso el coordinador debe registrar la decisión **antes** de la fase 2 y tener un procedimiento de recuperación.

### 9.8 Control de concurrencia y bloqueo distribuido

Script: `07_concurrencia.sh`. Lanza sesiones psql en paralelo y una sesión monitora.

| Escenario | Mecanismo | Resultado observado |
|---|---|---|
| **A. Dos operadores escanean el mismo envío** (nodo SUR) | Bloqueo exclusivo de fila (`SELECT … FOR UPDATE`, 2PL estricto: se libera al COMMIT) | B esperó **3,0 s** hasta el COMMIT de A. El monitor muestra a B con `wait_event = transactionid`, `bloqueado_por = {pid de A}` y en `pg_locks` un `ShareLock` no otorgado |
| **B. Actualización perdida** (dos supervisores ajustan un valor leído antes) | Nivel de aislamiento | **READ COMMITTED:** valor final 150, se **perdió** el +100 de A. **REPEATABLE READ:** B recibe `could not serialize access due to concurrent update` y el valor queda en 200; la aplicación debe reintentar |
| **C1. Interbloqueo local** (un solo nodo) | Detector de interbloqueos de PostgreSQL (`deadlock_timeout` = 1 s) | `ERROR: deadlock detected`: se aborta una víctima y la otra termina |
| **C2. Interbloqueo distribuido** (T1: NORTE → SUR; T2: SUR → NORTE, desde el coordinador) | Cada nodo solo conoce su grafo de espera local | El monitor muestra **una** espera en NORTE y **una** en SUR, y ningún nodo detecta el ciclo (el contador de NORTE sigue en 0). Se resuelve por **timeout**: T2 se cancela con `statement_timeout` y T1 completa |

*Tabla 24. Escenarios de concurrencia. Fuente: evidencia 07.*

**Conclusiones de concurrencia:**
- Dentro de cada nodo, PostgreSQL combina **MVCC** (las lecturas no bloquean escrituras) con **bloqueos de fila** para las escrituras.
- Las operaciones de escaneo usan `FOR UPDATE` en `sp_registrar_escaneo` para serializar escaneos simultáneos del mismo envío.
- Para operaciones *leer-calcular-escribir* se recomienda **REPEATABLE READ con reintento**.
- En el ámbito distribuido, postgres_fdw abre las transacciones remotas en REPEATABLE READ (o SERIALIZABLE si la local lo es). Así cada consulta global ve una instantánea consistente por nodo.
- Los **interbloqueos globales no se detectan automáticamente**: se previenen con un **orden global de adquisición de recursos** (por ejemplo, siempre LIMA → NORTE → SUR) y se resuelven con `lock_timeout`/`statement_timeout` en el coordinador.

---

### Resumen del Avance 2 (componente distribuido)

| Requisito de la guía | Cumplimiento |
|---|---|
| Arquitectura con ≥ 2 nodos | 3 nodos PostgreSQL independientes + coordinador |
| Qué información se distribuye y por qué | Secciones 9.1 y 9.5 |
| Fragmentación horizontal | HF1 (envío por origen), HF2 (paquete, derivada), HF3 (evento por ubicación) |
| Fragmentación vertical | VF de cliente (fiscal / contacto), con fragmentación mixta |
| Descomposición, localización y optimización | Q1–Q6 con `EXPLAIN VERBOSE` |
| Transacción y control de concurrencia | 2PC (3 casos) + 4 escenarios de concurrencia |
