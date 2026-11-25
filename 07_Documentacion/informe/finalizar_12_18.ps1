# Paso Word del informe con los puntos 12 a 18: actualiza SOLO los números de página del índice
# (UpdatePageNumbers no reconstruye las entradas), guarda el .docx y exporta el PDF sin actualizar
# ningún otro campo.
param([Parameter(Mandatory)][string]$Docx)
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$word.Options.UpdateFieldsAtPrint = $false
$word.Options.UpdateLinksAtPrint = $false
try {
    $d = $word.Documents.Open($Docx, $false, $false)
    $d.Repaginate()
    $toc = $d.TablesOfContents.Item(1)
    $antes = $toc.Range.Paragraphs.Count
    $toc.UpdatePageNumbers()
    "ENTRADAS_INDICE antes=$antes despues=$($toc.Range.Paragraphs.Count)"
    $d.Save()
    $pdf = [IO.Path]::ChangeExtension($Docx, '.pdf')
    $d.ExportAsFixedFormat($pdf, 17)
    "PAGINAS=$($d.ComputeStatistics(2))"
    $d.Close(0)
} finally { $word.Quit() }
