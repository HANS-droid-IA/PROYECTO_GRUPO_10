@echo off
rem =====================================================================
rem Crea la base de datos olva_courier_pg en el PostgreSQL de Windows
rem (puntos 5 a 7: tablas, datos, funciones, procedimientos, triggers,
rem vistas y seguridad). psql pedira la contrasena del usuario indicado.
rem =====================================================================
chcp 65001 >nul
cd /d "%~dp0"
set PGCLIENTENCODING=UTF8
set "PATH=%PATH%;C:\Program Files\PostgreSQL\18\bin;C:\Program Files\PostgreSQL\17\bin;C:\Program Files\PostgreSQL\16\bin"

set PUERTO=5432
set USUARIO=postgres
set /p PUERTO=Puerto de PostgreSQL [5432]:
set /p USUARIO=Usuario administrador [postgres]:

echo.
echo Creando olva_courier_pg en localhost:%PUERTO% (tarda 1-2 minutos)...
psql -X -h localhost -p %PUERTO% -U %USUARIO% -d postgres -f 01_olva_courier_postgresql.sql
if errorlevel 1 (
    echo.
    echo ERROR: revisa el mensaje de arriba.
) else (
    echo.
    echo LISTO. En DBeaver crea una conexion PostgreSQL a localhost:%PUERTO%, base olva_courier_pg.
)
pause
