@echo off
rem Inicia el portal web: http://localhost:5000
cd /d "%~dp0"
start "" http://localhost:5000
G:\Herramientas\Python312\python.exe app.py
