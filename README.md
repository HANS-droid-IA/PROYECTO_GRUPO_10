# PROYECTO_GRUPO_10 — Trazabilidad de paquetería y courier aéreo/terrestre

**Curso:** Base de Datos II — Proyecto Final · **Grupo:** 10 · **Caso de estudio:** Olva Courier (Perú)

Solución integral de bases de datos para el seguimiento de envíos aéreos y terrestres: registro transaccional,
base distribuida por sedes, expediente documental, bitácora de escaneos, análisis Big Data e integración en un
portal web. Permite rastrear cada envío, detectar cuellos de botella en la red logística y medir el
cumplimiento de los plazos de entrega (SLA).

> Los datos son **sintéticos**: los genera un simulador propio (Python, semilla fija) sobre la estructura pública
> de la operación de Olva Courier. Ningún registro corresponde a información interna de la empresa.

---

## 1. Estructura del repositorio

```
/PROYECTO_GRUPO_10
├── /01_Relacional_PostgreSQL   Scripts DDL, DML, funciones, SP, triggers, vistas, seguridad, consultas y backups
├── /02_Oracle                  Scripts de comparación e implementación parcial (PL/SQL, PROFILE, Data Pump)
├── /03_BD_Distribuida          Arquitectura de 3 nodos, fragmentación, consultas distribuidas, 2PC y concurrencia
├── /04_NoSQL_MongoDB           Colecciones, validación, índices, CRUD, agregaciones, documentos JSON y 2 sedes
├── /05_NoSQL_Cassandra         Scripts CQL, diseño de tablas por consulta, seguridad y 2 centros de datos
├── /06_BigData_Hadoop          Generador de datos masivos, Mapper, Reducer, Driver, HDFS, integración y outputs
├── /07_Documentacion           Informe final (PDF/Word), informe breve, diagramas, capturas y portal web
└── README.md                   Instrucciones de despliegue y guía de ejecución (este archivo)
```

| Carpeta | Contenido principal |
|---|---|
| `01_Relacional_PostgreSQL` | `generador/generar_datos.py` (simulador), `datos/` (18 CSV), scripts `00`–`11`: DDL de 20 tablas en 4 esquemas, 4 funciones, 4 procedimientos, 3 triggers, vistas, 5 roles + RLS, 13 consultas, pruebas y backup/restauración; `postgresql_nativo_pgadmin/` (versión autocontenida para el PostgreSQL de Windows y pgAdmin) |
| `02_Oracle` | 8 tablas del núcleo, paquete `pkg_tracking`, trigger, transacción autónoma, PROFILE, pruebas y respaldo con Data Pump |
| `03_BD_Distribuida` | Nodos LIMA / NORTE / SUR con `postgres_fdw`, fragmentación horizontal, derivada y vertical, verificación de corrección, consultas distribuidas, 2PC y concurrencia |
| `04_NoSQL_MongoDB` | Base `olva_tracking` (`envios`, `hubs`, `clientes`), `$jsonSchema`, 12 índices, CRUD, agregaciones, roles; `distribuido/`: sharding por zonas en sedes Lima y Arequipa |
| `05_NoSQL_Cassandra` | Keyspace `olva_tracking` con 8 tablas diseñadas por consulta, carga `COPY`, LWT, BATCH, contadores, TTL, roles; `distribuido/`: centros de datos `dc_lima` y `dc_arequipa` |
| `06_BigData_Hadoop` | `hadoop_nativo/` (instalación y configuración del clúster), `mapreduce/src` (Mapper, Reducer, Combiner y Driver en Java), scripts `00`–`04` (carga HDFS, MapReduce, integración, volumen y hallazgos), `integracion/`, `outputs/` |
| `07_Documentacion` | `informe/` (informe final PDF y Word, puntos 1–18), `informe_breve/`, `diagramas/`, `capturas/`, `portal_web/` (sitio Flask conectado a las 5 bases), `referencias/` (guía y formato del curso) |

---

## 2. Arquitectura de la solución

| Tecnología | Rol | Volumen |
|---|---|---|
| **PostgreSQL 16** | Base transaccional, fuente de verdad | 29 966 envíos · 315 101 eventos |
| **Oracle (26ai Free)** | Implementación parcial y comparativa | 8 tablas · 1 000 envíos |
| **PostgreSQL distribuido** | Datos repartidos por sede (Lima, Norte, Sur) | 3 nodos · 2PC |
| **MongoDB 7** | Expediente documental del envío | 29 966 documentos · 2 sedes |
| **Apache Cassandra 4.1** | Bitácora de escaneos y estado en línea | 8 tablas · 2 centros de datos |
| **Apache Hadoop 3.3.6** | Almacenamiento y análisis masivo (HDFS + MapReduce) | 5 640 511 registros |
| **Portal web (Flask)** | Rastreo, envíos, cotizador, agencias y operaciones sobre las 5 bases | 8 secciones |

Todas las bases comparten las mismas claves (número de tracking, código de hub y de servicio). PostgreSQL es la
fuente de verdad; MongoDB, Cassandra y Hadoop reciben copias transformadas, y los indicadores de Hadoop vuelven a
PostgreSQL (esquema `analitica`), MongoDB (`kpi_bigdata`) y Cassandra (`kpi_*`).

---

## 3. Requisitos

- Windows 10/11 con **Docker Desktop** (WSL2) y unos 8 GB de RAM asignados.
- **Python 3.12** con: `python -m pip install -r 07_Documentacion/portal_web/requirements.txt`
- **Ubuntu 22.04 en WSL** para Apache Hadoop (lo instala `06_BigData_Hadoop/hadoop_nativo/instalar_hadoop.sh`).
- Un JDK (11 o superior) para compilar el código MapReduce.
- Opcionales: DBeaver, pgAdmin 4 y MongoDB Compass.

> El repositorio está pensado para clonarse en `G:\PROYECTO_GRUPO_10` (algunas rutas de WSL usan
> `/mnt/g/PROYECTO_GRUPO_10`). En otra ubicación, ajuste esas rutas.

## 4. Configuración de credenciales

Las contraseñas **no se publican**. Copie la plantilla y complete sus valores locales:

```bash
copy .env.example .env
```

En los scripts de seguridad las contraseñas de prueba aparecen como `<CONTRASENA_CONFIGURADA>`: reemplácelas por las
que defina antes de ejecutarlos.

---

## 5. Guía de despliegue y ejecución

Los servicios de `docker-compose.yml` están agrupados en perfiles para no saturar la RAM.

```bash
# 0) (opcional) regenerar los datos sintéticos (semilla fija = mismos resultados)
python 01_Relacional_PostgreSQL/generador/generar_datos.py
python 02_Oracle/generar_inserts_oracle.py

# 1) Relacional: PostgreSQL + Oracle
docker compose --profile relacional up -d
docker exec olva_pg_lima bash /proyecto/01_Relacional_PostgreSQL/00_crear_bd.sh
docker exec olva_pg_lima psql -U olva_admin -d olva_courier -f /proyecto/01_Relacional_PostgreSQL/08_consultas.sql
docker exec olva_pg_lima bash /proyecto/01_Relacional_PostgreSQL/11_backup_restauracion.sh
docker exec olva_oracle  bash /proyecto/02_Oracle/00_ejecutar_todo.sh

# 2) Base de datos distribuida (3 nodos)
docker compose --profile distribuida up -d
docker exec olva_pg_lima bash /proyecto/03_BD_Distribuida/00_desplegar.sh

# 3) NoSQL: MongoDB y Cassandra
docker compose --profile nosql up -d
python 04_NoSQL_MongoDB/generar_documentos.py
python 05_NoSQL_Cassandra/generar_csv_cassandra.py
docker exec -e MONGO_APP_PASSWORD=<CONTRASENA_CONFIGURADA> olva_mongo bash /scripts/00_ejecutar_todo.sh
docker exec -e CASS_ADMIN_PASSWORD=<CONTRASENA_CONFIGURADA> -e CASS_APP_PASSWORD=<CONTRASENA_CONFIGURADA> olva_cassandra bash /scripts/00_ejecutar_todo.sh

# 3b) MongoDB y Cassandra con 2 sedes (Lima y Arequipa)
docker compose --profile sedes_mongo up -d
bash 04_NoSQL_MongoDB/distribuido/00_desplegar_sedes.sh
docker compose --profile nosql --profile sedes_cassandra up -d
bash 05_NoSQL_Cassandra/distribuido/00_desplegar_sedes.sh

# 4) Big Data: Apache Hadoop 3.3.6 en Ubuntu (WSL)
wsl -d Ubuntu-22.04 -u root -- bash /mnt/g/PROYECTO_GRUPO_10/06_BigData_Hadoop/hadoop_nativo/instalar_hadoop.sh   # solo la 1.ª vez
06_BigData_Hadoop\hadoop_nativo\iniciar_hadoop.bat
bash 06_BigData_Hadoop/00_ejecutar_todo.sh     # genera 300 000 envíos, compila, carga HDFS, MapReduce e integración

# 5) Portal web
07_Documentacion\portal_web\iniciar_portal.bat   # http://localhost:5000

# Detener
docker compose --profile relacional --profile distribuida --profile nosql stop
06_BigData_Hadoop\hadoop_nativo\detener_hadoop.bat
```

> En Git Bash, anteponga `MSYS_NO_PATHCONV=1` a los comandos `docker exec` para que no se alteren las rutas
> `/proyecto/...`. En PowerShell o CMD no hace falta.

### Conexiones

| Servicio | Host:Puerto | Detalle |
|---|---|---|
| PostgreSQL Lima | localhost:5440 | `olva_courier` (centralizada) y `olva_lima` (nodo Lima + coordinador) |
| PostgreSQL Norte / Sur | localhost:5433 / 5434 | `olva_norte` / `olva_sur` |
| Oracle | localhost:1521 | servicio `FREEPDB1`, usuario `olva` |
| MongoDB | localhost:27017 | base `olva_tracking` (authSource `admin`) |
| MongoDB 2 sedes (mongos) | localhost:27020 | base `olva_sedes`, shards `sede_lima` y `sede_arequipa` |
| Cassandra Lima / Arequipa | localhost:9042 / 9043 | keyspace `olva_tracking` |
| HDFS / YARN / JobHistory | localhost:9870 / 8088 / 19888 | consolas web de Hadoop |
| Portal web | localhost:5000 | sitio de envíos conectado a las 5 bases |

---

## 6. Resultados principales

| Indicador | Valor |
|---|---|
| Cumplimiento global del plazo de entrega | **91,4 %** |
| Ocupación del Hub Central Lima a las 20:00 | 110 % de su capacidad |
| Llegadas al Hub Central a las 20:00 (Hadoop, 3,15 M eventos) | 35,8 %, con 14,57 h de permanencia promedio |
| Permanencia nocturna frente a diurna | +43 % |
| Hub Arequipa en agosto y septiembre | +20 % de permanencia |
| Cumplimiento de los servicios aéreos | 86,7 % (Económico Terrestre: 98,8 %) |
| Procesamiento MapReduce de 3,15 M eventos | ≈ 99 segundos |

El análisis completo, con diagramas, código y evidencias, está en
`07_Documentacion/informe/Informe_BDII_Trazabilidad_12_18.pdf` (informe final) y en
`07_Documentacion/informe_breve/` (resumen de 8 páginas).

---

## 7. Integrantes — Grupo 10

| Integrante | Código |
|---|---|
| Alvarado Canchihuaman, Hans Piero | U24306153 |
| Sayas Reginaldo, Zinedine Claver | U24319637 |

**Docente:** America Ingrid Acuña Gomez
