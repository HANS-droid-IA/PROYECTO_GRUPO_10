@echo off
rem Ejecuta las 3 consultas de demostracion en Cassandra y deja cqlsh abierto.
chcp 65001 >nul
for /f "tokens=1,* delims==" %%a in ('findstr /b "CASS_ADMIN_PASSWORD=" "%~dp0..\.env"') do set "CLAVE=%%b"
docker cp "%~dp0tres_consultas.cql" olva_cassandra:/tmp/tres_consultas.cql >nul
echo ===== Consultas =====
type "%~dp0tres_consultas.cql"
echo.
echo ===== Resultados =====
docker exec olva_cassandra cqlsh -u olva_admin -p %CLAVE% -f /tmp/tres_consultas.cql 2>nul
echo.
echo ===== Consola interactiva (EXIT para salir) =====
docker exec -it olva_cassandra cqlsh -u olva_admin -p %CLAVE% -k olva_tracking 2>nul
