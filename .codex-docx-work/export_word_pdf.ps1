$inputDoc = 'C:\Users\ADMIN\Documents\GitHub\KLTN\23520840_23520838_DeCuongKLTN_DieuChinhTienDo.docx'
$outputPdf = 'C:\Users\ADMIN\Documents\GitHub\KLTN\.codex-docx-work\final-render\outline.pdf'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPdf) | Out-Null
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
    $doc = $word.Documents.Open($inputDoc, $false, $true)
    $doc.ExportAsFixedFormat($outputPdf, 17)
    $doc.Close($false)
}
finally {
    $word.Quit()
}
Write-Output $outputPdf
