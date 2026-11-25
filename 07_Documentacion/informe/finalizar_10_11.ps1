# Paso Word del informe con los puntos 10 y 11. NO actualiza campos (el índice se conserva tal cual):
#   -Modo paginas : abre en solo lectura y devuelve la página de cada marcador _Toc (JSON)
#   -Modo pdf     : exporta a PDF sin actualizar campos y reporta el número de páginas
param([Parameter(Mandatory)][ValidateSet('paginas', 'pdf')][string]$Modo,
      [string]$Docx = "$PSScriptRoot\Informe_BDII_Trazabilidad_10_11.docx")
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$word.Options.UpdateFieldsAtPrint = $false
$word.Options.UpdateLinksAtPrint = $false
try {
    $d = $word.Documents.Open($Docx, $false, $true)          # solo lectura
    $d.Repaginate()
    if ($Modo -eq 'paginas') {
        $res = @{}
        foreach ($b in $d.Bookmarks) { if ($b.Name -like '_Toc*') { $res[$b.Name] = $b.Range.Information(3) } }
        $res | ConvertTo-Json -Compress
    } else {
        $pdf = [IO.Path]::ChangeExtension($Docx, '.pdf')
        $d.ExportAsFixedFormat($pdf, 17)
        "PAGINAS=$($d.ComputeStatistics(2))"
    }
    $d.Close(0)
} finally { $word.Quit() }
