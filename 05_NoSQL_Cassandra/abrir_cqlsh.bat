@echo off
rem Abre la consola de Cassandra (cqlsh) como olva_admin: primero muestra la
rem demostracion y luego queda abierta para escribir consultas CQL.
rem La contrasena se lee de ..\.env (CASS_ADMIN_PASSWORD).
chcp 65001 >nul
mode con: cols=150 lines=50
title Cassandra - cqlsh (olva_tracking)
for /f "tokens=1,* delims==" %%a in ('findstr /b "CASS_ADMIN_PASSWORD=" "%~dp0..\.env"') do set "CLAVE=%%b"
docker exec olva_cassandra cqlsh -u olva_admin -p %CLAVE% -f /scripts/06_demo_exposicion.cql 2>nul
echo.
echo ===== Consola interactiva: escribe consultas CQL terminadas en ; (EXIT para salir) =====
docker exec -it olva_cassandra cqlsh -u olva_admin -p %CLAVE% -k olva_tracking 2>nul
