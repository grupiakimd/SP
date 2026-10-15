#requires -Version 5.1
<#
.SYNOPSIS
  SharePoint SE Dashboard v2.1 — raport HTML z JSON lub awaryjnie CSV.
.DESCRIPTION
  Dziala offline i tylko odczytuje wyniki audytu. InputPath moze wskazywac:
  - katalog konkretnego przebiegu audytu,
  - katalog nadrzedny z wieloma przebiegami (wybierze najnowszy),
  - FullInventory.json,
  - ZIP z przebiegu audytu,
  - katalog zawierajacy jedynie pliki CSV.
  Przy niekompletnych danych oznacza raport jako NIEPELNY zamiast udawac sukces.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [string]$OutputPath
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$tempDir = $null
$csvSections = @(
    'Farm','FarmServers','OSInventory','ServerDisks','WindowsServices','Certificates','IISBindings','SPBinaryVersions',
    'WebApplications','WebAppZones','AlternateAccessMappings','ManagedPaths',
    'ContentDatabases','SPDatabases','SQLInstances','SQLDatabases','SQLBackupHistory','SQLBackupAuditStatus',
    'ServiceApplications','ServiceAppProxies','ServiceAppProxyGroups','ServiceInstances',
    'ManagedAccounts','ServiceAppPools','SolutionsWSP','FarmFeatures',
    'TimerJobs','DisabledTimerJobs','HealthRules','HealthReports','SearchApplications','SearchTopologies',
    'SearchComponents','CrawlSources','SiteCollections','MySites','Webs','Lists',
    'WebFeatures','SiteFeatures','WorkflowAssociations'
)

function Get-AuditCandidates([string]$Root) {
    $folders = @($Root) + @(Get-ChildItem -LiteralPath $Root -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($folder in $folders) {
        $j = Join-Path $folder 'FullInventory.json'
        $c = Join-Path $folder 'Farm.csv'
        $d = Join-Path $folder 'SPDatabases.csv'
        $e = Join-Path $folder 'MigrationRisks.csv'
        if (Test-Path -LiteralPath $j -PathType Leaf) {
            [pscustomobject]@{ Folder=$folder; Mode='JSON'; Stamp=(Get-Item -LiteralPath $j).LastWriteTime }
        } elseif ((Test-Path -LiteralPath $c -PathType Leaf) -or (Test-Path -LiteralPath $d -PathType Leaf) -or (Test-Path -LiteralPath $e -PathType Leaf)) {
            $files = @(Get-ChildItem -LiteralPath $folder -File -Filter '*.csv')
            $stamp = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
            [pscustomobject]@{ Folder=$folder; Mode='CSV'; Stamp=$stamp }
        }
    }
}

function Read-CsvRows([string]$Folder,[string]$File) {
    $path = Join-Path $Folder $File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    try {
        $rows = @(Import-Csv -LiteralPath $path -Delimiter ';' -Encoding UTF8 -ErrorAction Stop)
        if ($rows.Count -gt 0 -and $rows[0].PSObject.Properties['BRAK_DANYCH']) { return @() }
        return $rows
    } catch {
        Write-Warning ("Nie mozna odczytac {0}: {1}" -f $path,$_.Exception.Message)
        return @()
    }
}

function Build-FromCsv([string]$Folder) {
    $metadataPath = Join-Path $Folder 'AuditMetadata.json'
    $meta = [ordered]@{
        AuditVersion='2.1.0-CSV-RECOVERY'; Collector='UNKNOWN'; SQLInstancesDiscovered=0
        ReadinessScore='NOT_SCORED_INCOMPLETE_EVIDENCE'; DatasetSource='CSV_FALLBACK'
        DataCompleteness='INCOMPLETE_CSV_ONLY'; Finished=(Get-Date).ToString('s')
    }
    if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
        try {
            $old = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            foreach ($prop in $old.PSObject.Properties) { $meta[$prop.Name]=$prop.Value }
        } catch { Write-Warning ('Nie mozna odczytac AuditMetadata.json: ' + $_.Exception.Message) }
    }
    # Nie zastepujemy niepelnego wyniku falszywym "OK" ani wynikiem 100/100.
    $meta['ReadinessScore'] = 'NOT_SCORED_INCOMPLETE_EVIDENCE'
    $meta['DatasetSource'] = 'CSV_FALLBACK'
    $meta['DataCompleteness'] = 'INCOMPLETE_CSV_ONLY'
    $risks = @(Read-CsvRows $Folder 'MigrationRisks.csv')
    $errors = @(Read-CsvRows $Folder 'CollectionErrors.csv')
    $errors += [pscustomobject]@{
        Section='Dashboard'; Time=(Get-Date).ToString('s')
        Message='Raport odtworzony z CSV — brak kompletnego FullInventory.json; nalezy zweryfikowac kompletnosc audytu.'
    }
    $dataset = [ordered]@{ Metadata=$meta; Risks=$risks; Errors=$errors }
    $count = 0
    foreach ($section in $csvSections) {
        $rows = @(Read-CsvRows $Folder ($section+'.csv'))
        $dataset[$section] = $rows
        $count += $rows.Count
    }
    if ($count -eq 0 -and $risks.Count -eq 0) {
        throw ('Nie znaleziono rzeczywistych danych w plikach CSV w katalogu: ' + $Folder)
    }
    return ($dataset | ConvertTo-Json -Depth 12 -Compress)
}

try {
    $p = (Resolve-Path -LiteralPath $InputPath -ErrorAction Stop).ProviderPath
    $isZip = $false
    $selected = $null
    $jsonFile = $null
    if (Test-Path -LiteralPath $p -PathType Container) {
        $root = $p
    } elseif ([IO.Path]::GetExtension($p) -ieq '.zip') {
        $isZip = $true
        $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('SPSE_AUDIT_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        Expand-Archive -LiteralPath $p -DestinationPath $tempDir -Force
        $root = $tempDir
    } elseif ([IO.Path]::GetExtension($p) -ieq '.json') {
        $jsonFile = $p
        $root = Split-Path -Parent $p
        $selected = [pscustomobject]@{Folder=$root; Mode='JSON'; Stamp=(Get-Item -LiteralPath $p).LastWriteTime}
    } elseif ([IO.Path]::GetExtension($p) -ieq '.csv') {
        $root = Split-Path -Parent $p
    } else {
        throw 'InputPath musi wskazywac katalog audytu, plik JSON, CSV lub ZIP z audytu.'
    }
    if ($null -eq $selected) {
        $found = @(Get-AuditCandidates $root | Sort-Object Stamp -Descending)
        if ($found.Count -eq 0) {
            throw ("Nie znaleziono FullInventory.json ani CSV audytu pod: {0}. Sprawdz -OutputRoot i katalog przebiegu." -f $root)
        }
        $selected = $found[0]
        if ($found.Count -gt 1) {
            Write-Warning ("Znaleziono {0} przebiegow audytu, uzywam najnowszego: {1}" -f $found.Count,$selected.Folder)
        }
    }
    if (-not $jsonFile) { $jsonFile = Join-Path $selected.Folder 'FullInventory.json' }
    Write-Host ("[SOURCE] {0} | {1}" -f $selected.Mode,$selected.Folder) -ForegroundColor Cyan
    $json = $null
    if (Test-Path -LiteralPath $jsonFile -PathType Leaf) {
        try {
            $raw = [IO.File]::ReadAllText($jsonFile)
            $obj = $raw | ConvertFrom-Json -ErrorAction Stop
            if (-not $obj.PSObject.Properties['Metadata']) { throw 'Brak obiektu Metadata w JSON.' }
            $json = $raw
        } catch {
            Write-Warning ('Niepoprawny FullInventory.json — probuje CSV: ' + $_.Exception.Message)
        }
    }
    if (-not $json) { $json = Build-FromCsv $selected.Folder }

    $templateFile = Join-Path $PSScriptRoot 'dashboard_template.html'
    if (-not (Test-Path -LiteralPath $templateFile -PathType Leaf)) {
        throw ('Brak dashboard_template.html obok generatora: '+$PSScriptRoot)
    }
    if (-not $OutputPath) {
        if ($isZip) {
            $OutputPath = Join-Path (Split-Path -Parent $p) (([IO.Path]::GetFileNameWithoutExtension($p))+'_Dashboard.html')
        } else {
            $OutputPath = Join-Path $selected.Folder 'SPSE_Readiness_Report.html'
        }
    }
    # Ochrona przed wstrzyknieciem HTML z nazw obiektow, URL i tytulow witryn.
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
    Write-Host ("[HTML] GOTOWE: {0} ({1:N1} MB)" -f $file.FullName,($file.Length/1MB)) -ForegroundColor Green
} finally {
    if ($tempDir -and (Test-Path -LiteralPath $tempDir)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
