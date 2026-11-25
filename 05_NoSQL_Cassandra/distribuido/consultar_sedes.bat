@echo off
rem Doble clic: muestra las tablas de las dos sedes de Cassandra y deja la ventana abierta.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0consultar_sedes.ps1" %*
pause
