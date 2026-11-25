# Muestra cada transcripción real (salidas\<id>.txt) en una ventana de consola y la fotografía (<id>.png).
# Uso: powershell -ExecutionPolicy Bypass -File fotografiar_consola.ps1 [-Solo id1,id2]
param([string]$Solo)
$ErrorActionPreference = 'Stop'
$Cap = $PSScriptRoot
$Tmp = Join-Path $env:TEMP 'olva_capturas_nosql'; New-Item -ItemType Directory -Force $Tmp | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W2 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[W2]::SetProcessDPIAware() | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$titulos = @{ mg = 'mongosh - olva_tracking'; cq = 'cqlsh - olva_tracking' }

$lista = Get-ChildItem "$Cap\salidas\*.txt" | Where-Object { -not $Solo -or ($Solo -split ',') -contains $_.BaseName }
foreach ($f in $lista) {
    $id = $f.BaseName
    $lineas = [IO.File]::ReadAllLines($f.FullName, $utf8)
    $titulo = $titulos[$id.Substring(0, 2)] + " ($id)"
    $cols = [Math]::Min(190, [Math]::Max(100, (($lineas | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum + 2)))
    $alto = ($lineas | ForEach-Object { [Math]::Max(1, [Math]::Ceiling($_.Length / $cols)) } | Measure-Object -Sum).Sum + 2
    $txt = Join-Path $Tmp "$id.txt"; [IO.File]::WriteAllLines($txt, $lineas, $utf8)
    $marca = Join-Path $Tmp "$id.listo"; Remove-Item $marca -ErrorAction SilentlyContinue
    $bat = Join-Path $Tmp "show_$id.cmd"
    [IO.File]::WriteAllText($bat, "@echo off`r`nchcp 65001 >nul`r`nmode con: cols=$cols lines=$alto`r`ntitle $titulo`r`ntype `"$txt`"`r`necho.>`"$marca`"`r`npause >nul`r`n", $utf8)
    $p = Start-Process conhost.exe -ArgumentList "cmd.exe /c `"$bat`"" -PassThru
    $t0 = Get-Date
    while (-not (Test-Path $marca) -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep -Milliseconds 200 }
    $h = [IntPtr]::Zero; $cmdId = $null
    while ($h -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30) {
        $w = Get-Process cmd -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq $titulo } | Select-Object -First 1
        if ($w) { $h = $w.MainWindowHandle; $cmdId = $w.Id }; Start-Sleep -Milliseconds 200 }
    [W2]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0040) | Out-Null
    [W2]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 900
    $r = New-Object W2+RECT; [W2]::DwmGetWindowAttribute($h, 9, [ref]$r, 16) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    $png = Join-Path $Cap "$id.png"; $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
    if ($cmdId) { Stop-Process -Id $cmdId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    "{0,-18} {1} columnas x {2} líneas -> {3}" -f $id, $cols, $alto, (Split-Path $png -Leaf)
}
Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
