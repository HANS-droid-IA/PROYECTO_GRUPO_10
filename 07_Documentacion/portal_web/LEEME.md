# Sitio web de envíos Olva Courier (07_Documentacion/portal_web)

Sitio web completo de un courier, conectado a **las cinco bases de datos del proyecto**. Cada sección usa la
base que mejor responde a esa necesidad:

| Sección | Qué hace | Bases que usa |
|---|---|---|
| **Inicio** | Buscador de tracking, servicios, accesos y cifras de la red | PostgreSQL |
| **Rastrear** | Estado, plazo (`fn_estado_sla`), mapa del recorrido, historial, detalle y prueba de entrega | PostgreSQL + MongoDB (hubs GeoJSON, POD) + Cassandra (estado en línea) |
| **Enviar** | Registra un envío (`sp_registrar_envio`) con precio en vivo y lo mueve escaneo a escaneo | PostgreSQL → réplica en Oracle, MongoDB, Cassandra y HDFS |
| **Cotizar** | Compara los 4 servicios: precio (`fn_calcular_tarifa`), plazo y fecha estimada | PostgreSQL |
| **Mi cuenta** | Perfil del cliente por DNI/RUC e historial de envíos | MongoDB (`clientes`) + Cassandra (`envios_por_cliente`) |
| **Agencias** | Mapa de la red y agencias más cercanas (`$geoNear`, índice 2dsphere) | MongoDB |
| **Operaciones** | Indicadores, gráficos y actividad de un hub por hora | PostgreSQL + Hadoop (MapReduce) + Cassandra |
| **Bases de datos** | Estado de las 5 conexiones, 20 registros recientes de cada una y rastreo cruzado | las cinco |

Los mapas usan Leaflet y OpenStreetMap (necesitan internet); el resto funciona sin conexión externa.

## Registrar y mover envíos
- **Registrar un envío:** se guarda en PostgreSQL con `sp_registrar_envio` (tarifa, plazo, comprobante y evento
  ADMISION) y se replica al instante en Oracle, MongoDB, Cassandra y HDFS.
- **Mover el envío por la red:** "Registrar siguiente escaneo" (o "Completar recorrido") calcula la ruta
  (Dijkstra sobre `maestro.ruta`), crea los despachos y registra SALIDA_HUB, LLEGADA_HUB, CLASIFICACION,
  EN_REPARTO y ENTREGA con `sp_registrar_escaneo` y `sp_registrar_intento_entrega`. Después de cada paso,
  la página muestra si cada base quedó sincronizada y cuánto tardó.

PostgreSQL es la fuente de verdad; `operaciones.py` lee el envío completo desde PostgreSQL y lo copia a Oracle
(con su trigger de estado), MongoDB (documento con tracking embebido), Cassandra (`estado_envio`,
`eventos_por_envio`, `eventos_por_hub_dia`, `envios_por_cliente`) y HDFS (`/olva/operacional/web/<tracking>.csv`).

| Base | Conexión | Qué muestra |
|---|---|---|
| PostgreSQL | `127.0.0.1:5440/olva_courier` | `operacion.envio` con JOIN a `maestro.hub` y `maestro.tipo_servicio` |
| Oracle | `127.0.0.1:1521/FREEPDB1` (usuario `olva`) | tabla `ENVIO` |
| MongoDB | `127.0.0.1:27017/olva_tracking` | colección `envios` (expediente con tracking embebido) |
| Cassandra | `127.0.0.1:9042/olva_tracking` (dc_lima) | tabla `estado_envio` por clave de partición |
| Hadoop | WebHDFS `127.0.0.1:9870` | `/olva/operacional/<fecha>/envio/envio.csv` y el resultado MapReduce `permanencia_hub` |

Además, **Rastrear un envío** busca el mismo tracking en las cinco bases a la vez y dibuja su recorrido.

## Ejecutar
1. Encender las bases: Docker Desktop (`olva_pg_lima`, `olva_oracle`, `olva_mongo`, `olva_cassandra`) y
   Hadoop (`06_BigData_Hadoop/hadoop_nativo/iniciar_hadoop.bat`).
2. Instalar dependencias (una sola vez): `python -m pip install -r requirements.txt`
3. Doble clic en `iniciar_portal.bat`, o en VS Code: **Ejecutar y depurar → "Portal Olva Courier (Flask)"** (F5).
4. Abrir http://localhost:5000

Las credenciales se leen del archivo `.env` de la raíz del proyecto; no están en el código.

## Archivos
- `app.py`: servidor Flask y API (`/api/<motor>`, `/api/rastreo/<tracking>`, `/api/hadoop/kpi`, `POST /api/envios`, `POST /api/envios/<tracking>/avanzar`).
- `conexiones.py`: conexión y consultas a cada base.
- `operaciones.py`: registro de envíos, avance del recorrido y réplica a las cinco bases.
- `servicios_web.py`: cotizador, seguimiento, agencias, cuenta del cliente y panel de operaciones.
- `static/sitio.js`: navegación del sitio, mapas y gráficos.
- `templates/index.html`, `static/app.js`, `static/estilos.css`: interfaz.
