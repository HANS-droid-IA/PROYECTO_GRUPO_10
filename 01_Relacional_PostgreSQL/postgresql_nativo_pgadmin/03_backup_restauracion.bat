@echo off
rem =====================================================================
rem 7.5 Backup y restauracion de olva_courier_pg (PostgreSQL en Windows)
rem   1) Respaldo logico completo con pg_dump (formato custom, comprimido)
rem   2) Respaldo de roles y usuarios con pg_dumpall --globals-only
rem   3) Incidente simulado: borrado accidental de las incidencias
rem   4) Restauracion selectiva de la tabla afectada
rem   5) Restauracion completa en una BD nueva y comparacion de conteos
rem Para no escribir la contrasena en cada paso, ejecuta antes en esta
rem ventana:  set PGPASSWORD=<CONTRASENA_CONFIGURADA>
rem =====================================================================
chcp 65001 >nul
cd /d "%~dp0"
set PGCLIENTENCODING=UTF8
set "PATH=%PATH%;C:\Program Files\PostgreSQL\18\bin;C:\Program Files\PostgreSQL\17\bin;C:\Program Files\PostgreSQL\16\bin"
set PUERTO=5432
set USUARIO=postgres
set /p PUERTO=Puerto de PostgreSQL [5432]:
set /p USUARIO=Usuario administrador [postgres]:
set "CON=-h localhost -p %PUERTO% -U %USUARIO%"
set "PSQL=psql -X -q -t -A %CON%"
if not exist backups mkdir backups
set DUMP=backups\olva_courier_pg.dump
set "CONTEO=SELECT 'envio=' || (SELECT COUNT(*) FROM operacion.envio) || '  evento_tracking=' || (SELECT COUNT(*) FROM operacion.evento_tracking) || '  incidencia=' || (SELECT COUNT(*) FROM operacion.incidencia) || '  comprobante=' || (SELECT COUNT(*) FROM operacion.comprobante)"

echo == [1] Respaldo logico: pg_dump -Fc ==
pg_dump %CON% -d olva_courier_pg -Fc -Z 6 -f %DUMP% || goto error
for %%A in (%DUMP%) do echo Archivo: %%~fA  Tamano: %%~zA bytes

echo.
echo == [2] Respaldo de roles y usuarios: pg_dumpall --globals-only ==
pg_dumpall %CON% --globals-only --no-role-passwords -f backups\globales.sql || goto error
echo Archivo: backups\globales.sql

echo.
echo == Conteos ANTES del incidente ==
%PSQL% -d olva_courier_pg -c "%CONTEO%"

echo.
echo == [3] INCIDENTE simulado: se borran por error todas las incidencias ==
%PSQL% -d olva_courier_pg -c "DELETE FROM operacion.incidencia;"
%PSQL% -d olva_courier_pg -c "SELECT 'incidencia despues del DELETE = ' || COUNT(*) FROM operacion.incidencia;"

echo.
echo == [4] Restauracion selectiva de operacion.incidencia ==
pg_restore %CON% -d olva_courier_pg --data-only --schema=operacion --table=incidencia %DUMP% || goto error
%PSQL% -d olva_courier_pg -c "SELECT 'incidencia restaurada = ' || COUNT(*) FROM operacion.incidencia;"

echo.
echo == [5] Restauracion completa en una BD nueva: olva_courier_pg_restore ==
%PSQL% -d postgres -c "DROP DATABASE IF EXISTS olva_courier_pg_restore WITH (FORCE);"
%PSQL% -d postgres -c "CREATE DATABASE olva_courier_pg_restore TEMPLATE template0;"
pg_restore %CON% -d olva_courier_pg_restore --jobs=4 --exit-on-error %DUMP% || goto error
echo Original:   & %PSQL% -d olva_courier_pg -c "%CONTEO%"
echo Restaurada: & %PSQL% -d olva_courier_pg_restore -c "%CONTEO%"
echo.
echo RESULTADO: si ambas lineas coinciden, la restauracion fue exitosa.
pause
exit /b 0

:error
echo ERROR en el proceso de backup/restauracion.
pause
exit /b 1
