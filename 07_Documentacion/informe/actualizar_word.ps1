# Abre el informe en Word, compacta los estilos de los índices, actualiza índices
# (contenidos, figuras, tablas) y campos, guarda, exporta a PDF e informa el número de páginas.
param([string]$Docx = "$PSScriptRoot\Informe_BDII_Trazabilidad_Olva_Courier.docx")
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
    $d = $word.Documents.Open($Docx)
    # estilos de índice: TDC 1 (-20), TDC 2 (-21), Tabla de ilustraciones (-36)
    foreach ($id in @(-20, -21, -36)) {
        $st = $d.Styles.Item($id)
        $st.Font.Name = 'Arial'
        $st.Font.Size = 7.5
        $st.ParagraphFormat.LineSpacingRule = 0      # sencillo
        $st.ParagraphFormat.SpaceAfter = 0
        $st.ParagraphFormat.SpaceBefore = 0
    }
    $d.Styles.Item(-20).Font.Bold = $true
    $d.Fields.Update() | Out-Null
    foreach ($t in $d.TablesOfContents) { $t.Update() }
    foreach ($t in $d.TablesOfFigures) { $t.Update() }
    $d.Repaginate()
    foreach ($t in $d.TablesOfContents) { $t.Update() }
    foreach ($t in $d.TablesOfFigures) { $t.Update() }
    $d.Repaginate()
    $paginas = $d.ComputeStatistics(2)   # wdStatisticPages
    $d.Save()
    $pdf = [IO.Path]::ChangeExtension($Docx, '.pdf')
    $d.ExportAsFixedFormat($pdf, 17)     # wdExportFormatPDF
    "PAGINAS=$paginas"
    foreach ($p in $d.Paragraphs) { if ($p.OutlineLevel -eq 1) { "{0,3} {1}" -f $p.Range.Information(3), $p.Range.Text.Trim() } }
    $d.Close()
} finally { $word.Quit() }
