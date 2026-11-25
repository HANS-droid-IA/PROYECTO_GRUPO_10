# Captura la ventana principal de un proceso (por defecto DBeaver) y la guarda como PNG.
# Usa PrintWindow (PW_RENDERFULLCONTENT): obtiene la imagen de la propia ventana aunque
# otra ventana esté encima, de modo que la captura muestra solo DBeaver.
# Uso: powershell -File capturar_ventana.ps1 -Salida <ruta.png> [-Proceso dbeaver]
param([Parameter(Mandatory)][string]$Salida, [string]$Proceso = 'dbeaver')
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class WC {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[WC]::SetProcessDPIAware() | Out-Null
$p = Get-Process $Proceso | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $p.MainWindowHandle
$w = New-Object WC+RECT; [WC]::GetWindowRect($h, [ref]$w) | Out-Null            # rectángulo completo (incluye bordes invisibles)
$v = New-Object WC+RECT; [WC]::DwmGetWindowAttribute($h, 9, [ref]$v, 16) | Out-Null   # rectángulo visible
$full = New-Object System.Drawing.Bitmap ($w.R - $w.L), ($w.B - $w.T)
$g = [System.Drawing.Graphics]::FromImage($full); $hdc = $g.GetHdc()
[WC]::PrintWindow($h, $hdc, 2) | Out-Null; $g.ReleaseHdc($hdc); $g.Dispose()
# recorta los bordes invisibles para quedarse con el área visible de la ventana
$rect = New-Object System.Drawing.Rectangle ($v.L - $w.L), ($v.T - $w.T), ($v.R - $v.L), ($v.B - $v.T)
$bmp = $full.Clone($rect, $full.PixelFormat); $full.Dispose()
New-Item -ItemType Directory -Force (Split-Path $Salida) | Out-Null
$bmp.Save($Salida, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
"Guardado $Salida ($($v.R - $v.L)x$($v.B - $v.T))"
