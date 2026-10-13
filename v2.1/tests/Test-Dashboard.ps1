#requires -Version 5.1
# Test generatora bez dostepu do SharePoint: JSON, CSV fallback, katalog nadrzedny i ZIP.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$generator = Join-Path (Split-Path -Parent $PSScriptRoot) 'New-SPSEDashboard.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('SPSE_DASH_TEST_'+[guid]::NewGuid().ToString('N'))
$old = Join-Path $root 'SP2019_Audit_OLDER'
$new = Join-Path $root 'SP2019_Audit_NEWER'
function Assert-Contains([string]$File,[string]$Needle) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Missing file: $File" }
    $text = [IO.File]::ReadAllText($File)
    if (-not $text.Contains($Needle)) { throw "Missing expected text '$Needle' in $File" }
}
try {
    New-Item -ItemType Directory -Path $old,$new -Force | Out-Null
    $inventory = @{
        Metadata=@{AuditVersion='TEST'; Collector='FAKE'; SQLInstancesDiscovered=0}
        Risks=@(); Errors=@()
        Farm=@([pscustomobject]@{BuildVersion='16.0.1'})
        FarmServers=@([pscustomobject]@{Name='synthetic-old';Role='WebFrontEnd'})
    }
    $inventory | ConvertTo-Json -Depth 8 | Out-File -LiteralPath (Join-Path $old 'FullInventory.json') -Encoding UTF8
    (Get-Item -LiteralPath (Join-Path $old 'FullInventory.json')).LastWriteTime = (Get-Date).AddDays(-2)
    @([pscustomobject]@{Name='synthetic-new';Role='Application'}) | Export-Csv -LiteralPath (Join-Path $new 'FarmServers.csv') -Delimiter ';' -Encoding UTF8 -NoTypeInformation
    @([pscustomobject]@{FarmId='SYNTHETIC';BuildVersion='16.0.1'}) | Export-Csv -LiteralPath (Join-Path $new 'Farm.csv') -Delimiter ';' -Encoding UTF8 -NoTypeInformation
    @([pscustomobject]@{Priority='UNKNOWN';Code='TEST';Object='NONE';Observation='fake';Recommendation='review'}) | Export-Csv -LiteralPath (Join-Path $new 'MigrationRisks.csv') -Delimiter ';' -Encoding UTF8 -NoTypeInformation
    & $generator -InputPath $old
    Assert-Contains (Join-Path $old 'SPSE_Readiness_Report.html') 'synthetic-old'
    & $generator -InputPath $new
    Assert-Contains (Join-Path $new 'SPSE_Readiness_Report.html') 'CSV_FALLBACK'
    Assert-Contains (Join-Path $new 'SPSE_Readiness_Report.html') 'synthetic-new'
    $parentOut = Join-Path $root 'PARENT.html'
    & $generator -InputPath $root -OutputPath $parentOut
    Assert-Contains $parentOut 'synthetic-new'
    $zip = Join-Path $root 'archive.zip'
    Compress-Archive -Path (Join-Path $new '*.csv') -DestinationPath $zip -Force
    & $generator -InputPath $zip
    Assert-Contains (Join-Path $root 'archive_Dashboard.html') 'CSV_FALLBACK'
    Write-Host 'PASS: JSON / CSV / parent / ZIP' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
