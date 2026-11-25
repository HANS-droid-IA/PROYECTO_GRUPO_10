# =====================================================================
# Toma las capturas de evidencia definidas en manifiesto.json.
# 1) Ejecuta cada prueba UNA vez (psql, SQL*Plus o script) y guarda su salida real en salidas\<id>.txt
# 2) Muestra esa salida en una ventana de consola (conhost) dimensionada al contenido
# 3) Fotografía la ventana (captura de pantalla) y la guarda en <id>.png
#    (si la salida no cabe en pantalla, se divide en partes: <id>_p1.png, <id>_p2.png ...)
# Las contraseñas se leen de .env y nunca se muestran en pantalla.
# Uso:  powershell -ExecutionPolicy Bypass -File tomar_capturas.ps1 [-SoloLista PG01,PG02]
# =====================================================================
param([string]$SoloLista)
$Solo = if ($SoloLista) { $SoloLista -split ',' } else { @() }
$ErrorActionPreference = 'Stop'
$Raiz = (Resolve-Path "$PSScriptRoot\..\..").Path
$Cap  = $PSScriptRoot
$Out  = Join-Path $Cap 'salidas'; New-Item -ItemType Directory -Force $Out | Out-Null
$Tmp  = Join-Path $env:TEMP 'olva_capturas'; New-Item -ItemType Directory -Force $Tmp | Out-Null
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$PSQL = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'

# credenciales desde .env (no se imprimen)
$cfg = @{}; Get-Content "$Raiz\.env" | Where-Object { $_ -match '^\s*([A-Z_]+)=(.*)$' } | ForEach-Object { $cfg[$Matches[1]] = $Matches[2].Trim() }

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[W]::SetProcessDPIAware() | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$MaxCols = 172; $MaxLines = 46

function Ejecutar($c) {
    # devuelve la salida real (texto) de la prueba
    $f = "/proyecto/07_Documentacion/capturas/scripts_captura/$($c.file)"
    switch ($c.tipo) {
        'psql' {
            $env:PGPASSWORD = $cfg.PG_PASSWORD; $env:PGCLIENTENCODING = 'UTF8'
            $args_ = @('-X', '-P', 'pager=off', '-P', 'footer=off', '-h', 'localhost', '-p', '5440', '-U', $cfg.PG_USER, '-d', $c.db, '-v', 'ON_ERROR_STOP=0', '-f', (Join-Path "$Cap\scripts_captura" $c.file))
            if ($c.echo)  { $args_ = @('-e') + $args_ }
            if ($c.quiet) { $args_ = @('-q') + $args_ }
            $cmd = "`"$PSQL`" " + ($args_ | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
            $hdr = "$($cfg.PG_USER)@localhost:5440/$($c.db)> psql -h localhost -p 5440 -U $($cfg.PG_USER) -d $($c.db) -f $($c.file)"
        }
        'sqlplus' {
            $pw = if ($c.usuario -eq 'system') { '$ORACLE_PASSWORD' } else { '$APP_USER_PASSWORD' }
            $s = if ($c.banner) { '' } else { '-s ' }
            $cmd = "docker exec olva_oracle bash -c `"sqlplus $s$($c.usuario)/$pw@//localhost:1521/FREEPDB1 @$f`""
            $hdr = "SQL> -- sqlplus $($c.usuario)@//localhost:1521/FREEPDB1 @$($c.file)"
        }
        default {
            $cmd = "docker exec -e PGPASSWORD=$($cfg.PG_PASSWORD) -e PGUSER=$($cfg.PG_USER) $($c.contenedor) $($c.comando)"
            $hdr = $c.encabezado
        }
    }
    $bat = Join-Path $Tmp "run_$($c.id).cmd"
    [IO.File]::WriteAllText($bat, "@echo off`r`nchcp 65001 >nul`r`nset PGCLIENTENCODING=UTF8`r`nset LC_MESSAGES=C`r`nset LANG=C`r`n$cmd`r`n", $utf8)
    $txt = Join-Path $Out "$($c.id).txt"
    cmd.exe /c "`"$bat`" > `"$txt`" 2>&1"
    $lineas = [IO.File]::ReadAllLines($txt, $utf8) | Where-Object { $_ -notmatch '^(SET|RESET)$' }
    # recortar líneas en blanco iniciales y finales
    while ($lineas.Count -gt 0 -and $lineas[0].Trim() -eq '') { $lineas = $lineas[1..($lineas.Count-1)] }
    while ($lineas.Count -gt 0 -and $lineas[-1].Trim() -eq '') { $lineas = $lineas[0..($lineas.Count-2)] }
    [IO.File]::WriteAllLines($txt, [string[]](@($hdr, '') + $lineas), $utf8)
    return @($hdr, [string[]]$lineas)
}

function Fotografiar($id, $titulo, $lineas) {
    $cols = [Math]::Min($MaxCols, [Math]::Max(100, (($lineas | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum + 2)))
    $txt = Join-Path $Tmp "$id.show.txt"
    [IO.File]::WriteAllLines($txt, [string[]]$lineas, $utf8)
    $alto = ($lineas | ForEach-Object { [Math]::Max(1, [Math]::Ceiling($_.Length / $cols)) } | Measure-Object -Sum).Sum + 2
    $marca = Join-Path $Tmp "$id.listo"; Remove-Item $marca -ErrorAction SilentlyContinue
    $bat = Join-Path $Tmp "show_$id.cmd"
    [IO.File]::WriteAllText($bat, "@echo off`r`nchcp 65001 >nul`r`nmode con: cols=$cols lines=$alto`r`ntitle $titulo`r`ntype `"$txt`"`r`necho.>`"$marca`"`r`npause >nul`r`n", $utf8)
    $p = Start-Process conhost.exe -ArgumentList "cmd.exe /c `"$bat`"" -PassThru
    $t0 = Get-Date
    while (-not (Test-Path $marca) -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep -Milliseconds 200 }
    $h = [IntPtr]::Zero
    while ($h -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30) { $w = Get-Process cmd -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq $titulo } | Select-Object -First 1; if ($w) { $h = $w.MainWindowHandle; $cmdId = $w.Id }; Start-Sleep -Milliseconds 200 }
    [W]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0040) | Out-Null   # TOPMOST, NOSIZE, SHOW, mueve a (0,0)
    [W]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 900
    $r = New-Object W+RECT; [W]::DwmGetWindowAttribute($h, 9, [ref]$r, 16) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    $png = Join-Path $Cap "$id.png"; $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
    if ($cmdId) { Stop-Process -Id $cmdId -Force -ErrorAction SilentlyContinue }; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    return $png
}

$manifiesto = Get-Content "$Cap\manifiesto.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$indice = @()
foreach ($c in $manifiesto) {
    if ($Solo -and ($Solo -notcontains $c.id)) { continue }
    if ($c.tipo -eq 'prep') { cmd.exe /c "docker exec -e PGPASSWORD=$($cfg.PG_PASSWORD) -e PGUSER=$($cfg.PG_USER) $($c.contenedor) $($c.comando) > NUL 2>&1"; Write-Host "$($c.id): preparado"; continue }
    $hdr, $lineas = Ejecutar $c
    # partir en páginas que quepan en pantalla
    $paginas = @(); $actual = @(); $usadas = 0
    foreach ($l in $lineas) {
        $n = [Math]::Max(1, [Math]::Ceiling($l.Length / $MaxCols))
        if ($usadas + $n -gt ($MaxLines - 3) -and $actual.Count -gt 0) { $paginas += ,$actual; $actual = @(); $usadas = 0 }
        $actual += $l; $usadas += $n
    }
    if ($actual.Count -gt 0) { $paginas += ,$actual }
    for ($i = 0; $i -lt $paginas.Count; $i++) {
        $sufijo = if ($paginas.Count -gt 1) { "_p$($i+1)" } else { '' }
        $cab = if ($i -eq 0) { @($hdr, '') } else { @("$hdr   (continuación, parte $($i+1) de $($paginas.Count))", '') }
        $png = Fotografiar "$($c.id)$sufijo" "$($c.id) - $($c.titulo)" ($cab + $paginas[$i])
        $indice += [pscustomobject]@{ id = "$($c.id)$sufijo"; titulo = $c.titulo; parte = if ($paginas.Count -gt 1) { "$($i+1)/$($paginas.Count)" } else { '' }; archivo = (Split-Path $png -Leaf) }
    }
    Write-Host ("{0,-10} {1} imagen(es)  {2}" -f $c.id, $paginas.Count, $c.titulo)
}
$indice | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $Cap ("indice_capturas" + $(if ($Solo) { '_parcial' } else { '' }) + ".json"))
Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue   # borra los .cmd temporales (contienen credenciales)
