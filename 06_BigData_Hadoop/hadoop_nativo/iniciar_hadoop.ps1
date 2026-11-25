# Inicia Apache Hadoop (Ubuntu 22.04 en WSL) y lo deja corriendo en segundo plano.
# WSL apaga la distribución cuando no queda ninguna sesión abierta; por eso se deja una sesión oculta
# ("sleep infinity") que mantiene vivos a NameNode, DataNodes, ResourceManager, NodeManager y JobHistory.
# Uso: powershell -ExecutionPolicy Bypass -File iniciar_hadoop.ps1   (o doble clic en iniciar_hadoop.bat)
$distro = 'Ubuntu-22.04'
$activo = Get-CimInstance Win32_Process -Filter "Name='wsl.exe'" |
    Where-Object { $_.CommandLine -like '*hadoop_cluster start*' }
if ($activo) {
    Write-Host 'Hadoop ya está iniciado.' -ForegroundColor Yellow
} else {
    Start-Process -WindowStyle Hidden -FilePath wsl.exe `
        -ArgumentList "-d $distro -u hadoop -e bash -c `"hadoop_cluster start > /tmp/hadoop_inicio.log 2>&1; exec sleep infinity`""
    Write-Host 'Iniciando Hadoop...' -ForegroundColor Cyan
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 3
        $log = wsl.exe -d $distro -u hadoop -e cat /tmp/hadoop_inicio.log 2>$null
        if ($log -match 'Web: HDFS') { break }
    }
}
wsl.exe -d $distro -u hadoop -e hadoop_cluster status
