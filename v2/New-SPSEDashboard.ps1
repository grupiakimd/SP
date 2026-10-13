#requires -Version 5.1
<#
.SYNOPSIS
  Tworzy samodzielny interaktywny raport HTML z danych audytu SP2019 -> SE.
.DESCRIPTION
  Nie laczy sie z farma ani SQL. Czyta wyeksportowany FullInventory.json z
  katalogu, pliku JSON lub archiwum ZIP poprzedniego przebiegu audytu.
.PARAMETER InputPath
  Katalog pojedynczego audytu, plik FullInventory.json lub archiwum ZIP audytu.
.PARAMETER OutputPath
  Docelowy plik HTML. Domyslnie w katalogu audytu lub obok ZIP.
.EXAMPLE
  .\New-SPSEDashboard.ps1 -InputPath 'C:\SP_Audit\SP2019_Audit_SERVER_20261013_083000'
.EXAMPLE
  .\New-SPSEDashboard.ps1 -InputPath 'C:\SP_Audit\SP2019_Audit_SERVER_20261013_083000.zip'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [string]$OutputPath
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$tempDir = $null
try {
    $p = (Resolve-Path -LiteralPath $InputPath -ErrorAction Stop).ProviderPath
    if (Test-Path -LiteralPath $p -PathType Container) {
        $jsonFile = Join-Path $p 'FullInventory.json'
        if (-not (Test-Path -LiteralPath $jsonFile -PathType Leaf)) {
            throw 'Nie znaleziono FullInventory.json w katalogu. Wskaz folder konkretnego przebiegu audytu.'
        }
        if (-not $OutputPath) { $OutputPath = Join-Path $p 'SPSE_Readiness_Report.html' }
    } elseif ([IO.Path]::GetExtension($p) -ieq '.json') {
        $jsonFile = $p
        if (-not $OutputPath) { $OutputPath = Join-Path (Split-Path -Parent $p) 'SPSE_Readiness_Report.html' }
    } elseif ([IO.Path]::GetExtension($p) -ieq '.zip') {
        $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('SPSE_AUDIT_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        Expand-Archive -LiteralPath $p -DestinationPath $tempDir -Force
        $found = @(Get-ChildItem -LiteralPath $tempDir -Recurse -File -Filter 'FullInventory.json')
        if ($found.Count -ne 1) {
            throw ('Archiwum musi zawierac dokladnie jeden FullInventory.json (znaleziono: {0}).' -f $found.Count)
        }
        $jsonFile = $found[0].FullName
        if (-not $OutputPath) {
            $OutputPath = Join-Path (Split-Path -Parent $p) (([IO.Path]::GetFileNameWithoutExtension($p)) + '_Dashboard.html')
        }
    } else { throw 'InputPath: podaj katalog audytu, FullInventory.json lub archiwum ZIP.' }

    $templateFile = Join-Path $PSScriptRoot 'dashboard_template.html'
    if (-not (Test-Path -LiteralPath $templateFile -PathType Leaf)) { throw 'Brak dashboard_template.html obok New-SPSEDashboard.ps1.' }
    $json = [IO.File]::ReadAllText($jsonFile)
    if (-not $json.TrimStart().StartsWith('{') -or $json -notmatch '"Metadata"') {
        throw 'FullInventory.json nie wyglada na wynik audytu. Sprawdz plik i sprobuj ponownie.'
    }
    # Zapobiega zamknieciu tagu <script> przez wartosci z audytu (URL, tytuly witryn itp.).
    # Zachowujemy poprawny JSON bez polegania na zewnetrznym CDN ani fetch(file://).
    $safeJson = $json.Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e')
    $safeJson = $safeJson.Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
    $template = [IO.File]::ReadAllText($templateFile)
    if (-not $template.Contains('__INVENTORY_JSON__')) { throw 'Szablon HTML nie zawiera znacznika danych.' }
    $html = $template.Replace('__INVENTORY_JSON__',$safeJson)
    $outParent = Split-Path -Parent $OutputPath
    if ($outParent -and -not (Test-Path -LiteralPath $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }
    [IO.File]::WriteAllText($OutputPath,$html,(New-Object System.Text.UTF8Encoding($true)))
    $file = Get-Item -LiteralPath $OutputPath
    Write-Host ("[HTML] Raport: {0} ({1:N1} MB)" -f $file.FullName, ($file.Length/1MB)) -ForegroundColor Green
} finally {
    if ($tempDir -and (Test-Path -LiteralPath $tempDir)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
