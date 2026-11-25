# Base de datos PostgreSQL — Olva Courier (puntos 5 a 7)

Base de datos `olva_courier_pg` autocontenida para el PostgreSQL instalado en Windows (16 o superior). No usa Docker.

| Archivo | Qué contiene | Punto del informe |
|---|---|---|
| `00_INSTALAR.bat` | Doble clic: pide puerto, usuario y contraseña, y crea la BD completa | — |
| `01_olva_courier_postgresql.sql` | Creación de la BD, 4 schemas, 20 tablas (PK, FK, CHECK, UNIQUE, índices), 4 funciones, 4 procedimientos, carga de datos, 3 triggers, vistas, roles, usuarios, GRANT/REVOKE y RLS | 6.1–6.4, 7.1–7.4 |
| `02_consultas_y_pruebas.sql` | 13 consultas representativas y pruebas de funciones, procedimientos y seguridad | 6.5, 7.1–7.4 |
| `03_backup_restauracion.bat` | pg_dump, pg_dumpall, incidente simulado, restauración selectiva y completa | 7.5 |
| `datos/` | 18 CSV sintéticos (29 966 envíos, 315 101 eventos) | 6.4 |
| `construir.py` | Regenera los .sql a partir de `01_Relacional_PostgreSQL` | — |

Ejecución manual (cmd, desde esta carpeta):

```
psql -h localhost -p 5432 -U postgres -f 01_olva_courier_postgresql.sql
psql -h localhost -p 5432 -U postgres -f 02_consultas_y_pruebas.sql
```

Los usuarios de prueba que crea el punto 7.3 (`u_admin_bd`, `u_op_lima`, etc.) tienen contraseñas solo para el entorno local; en el informe se muestran como `<CONTRASEÑA_CONFIGURADA>`.
