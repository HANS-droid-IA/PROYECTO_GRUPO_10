# Ejecuta la misma consulta CQL en las dos sedes de Cassandra (Lima y Arequipa).
# Cada sede responde con SUS datos (CONSISTENCY LOCAL_ONE: no pide nada a la otra sede).
# La contraseña se lee de ..\..\.env (CASS_ADMIN_PASSWORD); no se escribe en pantalla.
#
# Uso (PowerShell, desde esta carpeta):
#   powershell -ExecutionPolicy Bypass -File .\consultar_sedes.ps1
#       -> demostración: tablas de ambas sedes
#   powershell -ExecutionPolicy Bypass -File .\consultar_sedes.ps1 "SELECT * FROM hubs LIMIT 5;"
#       -> tu propia consulta en ambas sedes
#   powershell -ExecutionPolicy Bypass -File .\consultar_sedes.ps1 "SELECT * FROM hubs;" -Sede lima
#       -> solo una sede (lima | arequipa)
param([string]$Consulta = '', [ValidateSet('ambas', 'lima', 'arequipa')][string]$Sede = 'ambas')

$env_file = Join-Path $PSScriptRoot '..\..\.env'
$clave = ((Select-String -Path $env_file -Pattern '^CASS_ADMIN_PASSWORD=').Line -split '=', 2)[1]
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$sedes = [ordered]@{ lima = 'olva_cassandra'; arequipa = 'olva_cassandra_arequipa' }
if ($Sede -ne 'ambas') { $sedes = [ordered]@{ $Sede = $sedes[$Sede] } }

if (-not $Consulta) {
    $Consulta = "SELECT data_center AS sede FROM system.local; " +
                "DESCRIBE TABLES; " +
                "SELECT * FROM olva_tracking.hubs LIMIT 5; " +
                "SELECT nro_tracking, fecha_hora, tipo_evento, hub FROM olva_tracking.eventos_por_envio WHERE nro_tracking = 'OLV2600000004'; " +
                "SELECT * FROM olva_sede_arequipa.operaciones_locales LIMIT 3;"
}

foreach ($s in $sedes.Keys) {
    Write-Host ''
    Write-Host ('=' * 90) -ForegroundColor Cyan
    Write-Host ("  SEDE {0}   (nodo {1})" -f $s.ToUpper(), $sedes[$s]) -ForegroundColor Cyan
    Write-Host ('=' * 90) -ForegroundColor Cyan
    $cql = 'CONSISTENCY LOCAL_ONE; ' + ($Consulta -replace '\s*[\r\n]+\s*', ' ')
    docker exec $sedes[$s] cqlsh -u olva_admin -p $clave -k olva_tracking -e $cql 2>&1 |
        ForEach-Object { "$_" } |
        Where-Object { $_ -notmatch 'RemoteException|Warning: Using a password|Recommendation: use the credentials|^Consistency level set|NativeCommandError|^At line|^\s*\+ |CategoryInfo|FullyQualifiedErrorId|^\s*$' } |
        ForEach-Object { $_ -replace '^<stdin>:\d+:', 'ERROR: ' }
}
