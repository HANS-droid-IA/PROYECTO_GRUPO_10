# Detiene Apache Hadoop (Ubuntu en WSL) y cierra la sesión oculta que lo mantenía activo.
# Uso: powershell -ExecutionPolicy Bypass -File detener_hadoop.ps1   (o doble clic en detener_hadoop.bat)
$distro = 'Ubuntu-22.04'
wsl.exe -d $distro -u hadoop -e hadoop_cluster stop
Get-CimInstance Win32_Process -Filter "Name='wsl.exe'" |
    Where-Object { $_.CommandLine -like '*hadoop_cluster start*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Write-Host 'Hadoop detenido.' -ForegroundColor Cyan
