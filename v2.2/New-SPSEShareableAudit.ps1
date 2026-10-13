#requires -Version 5.1
<#
.SYNOPSIS
  Tworzy jeden pseudonimizowany raport Markdown do analizy migracji SP2019 -> SE.
.DESCRIPTION
  Tylko ODCZYT danych lokalnych z FullInventory.json lub CSV.
  SCHEMAT ZAMKNIETY: zadna nieznana kolumna nie jest kopiowana do raportu.
  Nie wysyla nic do internetu. Brak eksportu mapy prawdziwych nazw.
  To pseudonimizacja, a nie gwarancja anonimowosci.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [string]$OutputPath,
    [ValidateRange(10,10000)][int]$MaxRowsPerSection = 500
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$names=@('Farm','FarmServers','OSInventory','ServerDisks','SPBinaryVersions',
    'WebApplications','WebAppZones','AlternateAccessMappings','ManagedPaths',
    'ContentDatabases','SPDatabases','SQLInstances','SQLDatabases','SQLBackupHistory',
    'SQLBackupAuditStatus','ServiceApplications','ServiceAppProxies','ServiceAppProxyGroups',
    'ServiceInstances','ManagedAccounts','ServiceAppPools','SolutionsWSP','FarmFeatures',
    'TimerJobs','DisabledTimerJobs','HealthRules','HealthReports','SearchApplications',
    'SearchTopologies','SearchComponents','CrawlSources','SiteCollections','MySites',
    'Webs','Lists','WebFeatures','SiteFeatures','WorkflowAssociations','WindowsServices',
    'Certificates','IISBindings')
$D=@{};$risk=@();$errors=@();$meta=$null;$mode='CSV_RECOVERY'
$i=Get-Item -LiteralPath $InputPath -ErrorAction Stop
if ($i.PSIsContainer) {
    $possible=@(Get-ChildItem -LiteralPath $i.FullName -Recurse -File -ErrorAction Stop |
        Where-Object { $_.Name -eq 'FullInventory.json' -or $_.Name -in @('MigrationRisks.csv','CollectionErrors.csv') -or
            ($_.Extension -ieq '.csv' -and ($_.BaseName -in $names)) } |
        Sort-Object LastWriteTime -Descending)
    if ($possible.Count -eq 0){throw 'Nie znaleziono plikow audytu w katalogu.'}
    $root=$possible[0].DirectoryName
} elseif ($i.Extension -in @('.json','.csv')) {$root=$i.DirectoryName}
else {throw 'InputPath musi byc folderem audytu albo plikiem JSON/CSV.'}
$json=Join-Path $root 'FullInventory.json'
if(Test-Path -LiteralPath $json -PathType Leaf) {
    try {
        $o=Get-Content -LiteralPath $json -Encoding UTF8 -Raw | ConvertFrom-Json -ErrorAction Stop
        if(-not $o.PSObject.Properties['Metadata']){throw 'Niepelny JSON'}
        foreach($p in $o.PSObject.Properties) {
            if($p.Name -in $names){$D[$p.Name]=@($p.Value | Where-Object {$null -ne $_})}
        }
        $risk=@($o.Risks | Where-Object {$null -ne $_})
        $errors=@($o.Errors | Where-Object {$null -ne $_})
        $meta=$o.Metadata
        $mode='JSON'
    } catch {Write-Warning 'Niepoprawny FullInventory.json: proba odzyskania z CSV; nie wyswietlam surowego bledu.'}
}
if($mode -ne 'JSON') {
    foreach($n in $names+@('MigrationRisks','CollectionErrors')) {
        $file=Join-Path $root ($n+'.csv')
        if(-not (Test-Path -LiteralPath $file -PathType Leaf)){continue}
        try{
            $r=@(Import-Csv -LiteralPath $file -Encoding UTF8 -Delimiter ';' -ErrorAction Stop |
                Where-Object {-not $_.PSObject.Properties['BRAK_DANYCH']})
            if($n -eq 'MigrationRisks'){$risk=$r}
            elseif($n -eq 'CollectionErrors'){$errors=$r}
            else{$D[$n]=$r}
        }catch{Write-Warning ('Pominieto uszkodzony CSV: '+$n)}
    }
    $metaFile=Join-Path $root 'AuditMetadata.json'
    if(Test-Path -LiteralPath $metaFile){try{$meta=Get-Content -LiteralPath $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop}catch{}}
    if($D.Count -eq 0 -and $risk.Count -eq 0){throw 'Brak danych do udostepnienia.'}
}
function F($r,[string]$key) {
    if($null -eq $r){return $null}
    $p=$r.PSObject.Properties[$key]
    if($null -ne $p){return $p.Value}
    return $null
}
function Get-AuditSectionRows([string]$name){if($D.ContainsKey($name)){return @($D[$name])};return @()}
$map=@{}
function Alias([string]$type,$v) {
    $s=([string]$v).Trim().ToLowerInvariant()
    if(-not $s){return 'UNKNOWN'}
    if($type -eq 'SERVER'){$s=($s -split '[\\,]')[0];$s=($s -split '\.')[0]}
    if(-not $script:map.ContainsKey($type)){$script:map[$type]=@{}}
    if(-not $script:map[$type].ContainsKey($s)){
        $script:map[$type][$s]='{0}-{1:D3}' -f $type,($script:map[$type].Count+1)
    }
    return $script:map[$type][$s]
}
function B($v) {
    switch -regex ([string]$v) {
        '^(?i:true|1|yes)$' {return 'YES'}
        '^(?i:false|0|no)$' {return 'NO'}
    }
    return 'UNKNOWN'
}
function N($v) {
    if($null -eq $v -or [string]$v -eq ''){return '—'}
    $num=0.0
    if([double]::TryParse(([string]$v).Replace(',','.'),[Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,[ref]$num) -and
        -not [double]::IsNaN($num) -and -not [double]::IsInfinity($num) -and
        [math]::Abs($num) -lt 1e15) {
        return $num.ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)
    }
    return 'UNKNOWN'
}
function V($v){
    $s=[string]$v
    if($s -match '^\d{1,5}(\.\d{1,6}){1,4}$'){return $s}
    return 'UNKNOWN'
}
function DT($v){
    if(-not $v){return '—'}
    try{
        $t=[datetime]::Parse([string]$v,[Globalization.CultureInfo]::InvariantCulture)
        if($t.Year -ge 1990 -and $t.Year -le 2100){return $t.ToString('yyyy-MM-dd')}
    }catch{}
    return 'UNKNOWN'
}
function E($v,[string[]]$allow){
    foreach($x in $allow){if(([string]$v) -ieq $x){return $x.ToUpperInvariant()}}
    return 'OTHER_OR_UNKNOWN'
}
function Role($v){return E $v @('WebFrontEnd','Application','DistributedCache','Search','Custom','SingleServerFarm','WebFrontEndWithDistributedCache','ApplicationWithSearch')}
function Status($v){return E $v @('Online','Offline','Disabled','Enabled','Provisioning','Unprovisioning','Running','Stopped','Started','Starting','Stopping','Error','Failed','Warning','OK','Active','Inactive','Idle','Pending','Success','Succeeded','UpgradeRequired')}
function Kind($v){
    $s=[string]$v
    foreach($name in @('Search','User Profile','Managed Metadata','Secure Store','Business Data Connectivity','State Service','Usage','Access Services','PerformancePoint','InfoPath','Subscription Settings','App Management')){
        if($s -match [regex]::Escape($name)){return $name.ToUpperInvariant().Replace(' ','_')}
    }
    return 'OTHER_OR_CUSTOM'
}
function SiteTemplate($v){
    $s=[string]$v
    if($s -match '^(?i:STS|SPS|SPSPERS|SPSMSITEHOST|BLOG|ENTERWIKI|SRCH|BLANKINTERNET|GROUP)(#\d+)?$'){return $s.ToUpperInvariant()}
    return 'CUSTOM_OR_UNKNOWN'
}
function OsFamily($v){
    $s=[string]$v
    if($s -match '(?i)Windows Server (2012 R2|2016|2019|2022|2025)'){return 'WINDOWS SERVER '+$Matches[1].ToUpperInvariant()}
    return 'OTHER_OR_UNKNOWN'
}
function TxtRow([object[]]$a){return '| '+(($a|ForEach-Object{[string]$_}) -join ' | ')+' |'}
function Tbl([string]$title,[string[]]$head,[object[]]$arr,[int]$total){
    [void]$script:md.Add('### '+$title)
    [void]$script:md.Add(('Wszystkich: **{0}**, widocznych: **{1}**.' -f $total,$arr.Count))
    if($arr.Count -eq 0){[void]$script:md.Add('_Brak danych lub etap nie byl uruchomiony._');[void]$script:md.Add('');return}
    [void]$script:md.Add((TxtRow $head))
    [void]$script:md.Add((TxtRow @($head|ForEach-Object{'---'})))
    foreach($line in $arr){[void]$script:md.Add([string]$line)}
    if($total -gt $arr.Count){[void]$script:md.Add(('_Pominieto {0} wierszy wskutek limitu; liczby zbiorcze obejmuja calosc._' -f ($total-$arr.Count)))}
    [void]$script:md.Add('')
}
# Generate table lines before passing between PowerShell functions.
# Strings are intentionally used instead of nested arrays, which PowerShell pipelines may flatten.
function Get-AuditTableLines([object[]]$Rows) {
    foreach ($record in @($Rows | Select-Object -Get-AuditTableLines $MaxRowsPerSection)) {
        Write-Output (TxtRow ([object[]]$record))
    }
}
$md=New-Object 'System.Collections.Generic.List[string]'
[void]$md.Add('# SharePoint 2019 -> SE — raport pseudonimizowany')
[void]$md.Add('')
[void]$md.Add('**PRZED WYSLANIEM PRZEJRZYJ RECZNIE.** To nie jest gwarancja anonimowosci ani automatyczna zgoda na publikacje.')
[void]$md.Add('')
[void]$md.Add('- Dane: '+$mode+'; CSV_RECOVERY oznacza mozliwe braki danych.')
[void]$md.Add('- SharePoint build: '+(V (F $meta 'FarmBuild')))
[void]$md.Add('- DeepWebScan: '+(B (F $meta 'DeepWebScan'))+'; osiagnieto limit: '+(B (F $meta 'DeepWebLimitReached')))
[void]$md.Add('- SQL requested: '+(B (F $meta 'SQLRequested'))+'; Remote OS: '+(B (F $meta 'RemoteOSRequested')))
[void]$md.Add('- Bledy kolektora: '+$errors.Count+' (tresc bledow nie jest udostepniana).')
[void]$md.Add('')
[void]$md.Add('## Stan zebrania danych')
$summary=@()
foreach($name in $names){$summary+= , @($name,@(Get-AuditSectionRows $name).Count)}
Tbl 'Sekcje i liczba rekordow' @('Sekcja','Rekordy') (Get-AuditTableLines $summary) $summary.Count
[void]$md.Add('## Ryzyka migracyjne')
$codes=@('CONTENT_DB_UPGRADE','RBS','SITE_LIMIT','SP_DATABASE_UPGRADE_PENDING','SP_DATABASE_BUILD_TOO_OLD','REMOVED_SERVICE','INFOPATH','CUSTOM_WSP','TIMER_FAILURE','DEEP_SCAN_TRUNCATED','LEGACY_WORKFLOWS','WORKFLOW_NOT_SCANNED','OS_NOT_REACHABLE','CERT_EXPIRY','LARGE_DATABASE_300GB','SQL_DB_NOT_ONLINE','FILESTREAM','FULL_BACKUP_NOT_IN_MSDB','FULL_BACKUP_OLD','SQL_NOT_AUDITED','C2WTS','CLASSIC_AUTH','BASIC_AUTH','SP2019_SUPPORT_ENDED','SP_PATCH_MISMATCH','MANUAL_DEPENDENCIES','SE_TEST_REQUIRED')
$list=@()
foreach($r in $risk){
    $c=[string](F $r 'Code')
    if($c -cnotin $codes){$c='OTHER_RISK'}
    $list+= , @((E (F $r 'Priority') @('HIGH','MEDIUM','LOW','UNKNOWN')),$c)
}
Tbl 'Kody ryzyk (bez surowych opisow i obiektow)' @('Waga','Kod') (Get-AuditTableLines $list) $list.Count
[void]$md.Add('## Infrastruktura')
$a=@(Get-AuditSectionRows 'FarmServers');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'SERVER' (F $r 'Name')),(Role (F $r 'Role')),(Status (F $r 'Status')),(V (F $r 'BuildVersion')))}
Tbl 'Farm Servers' @('Serwer','MinRole','Status','Build') $t $a.Count
$a=@(Get-AuditSectionRows 'OSInventory');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'SERVER' (F $r 'Computer')),(OsFamily (F $r 'OS')),(N (F $r 'PhysicalRAM_GB')),(N (F $r 'LogicalCPU')))}
Tbl 'OS i parametry VM' @('Serwer','OS','RAM GB','CPU logical') $t $a.Count
$a=@(Get-AuditSectionRows 'ServerDisks');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'SERVER' (F $r 'Computer')),(N (F $r 'CapacityGB')),(N (F $r 'FreeGB')),(N (F $r 'FreePct')))}
Tbl 'Dyski (bez liter)' @('Serwer','Capacity GB','Free GB','Free %') $t $a.Count
$a=@(Get-AuditSectionRows 'SPBinaryVersions');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'SERVER' (F $r 'Computer')),(V (F $r 'FileVersion')))}
Tbl 'Binaria SharePoint' @('Serwer','Build') $t $a.Count
[void]$md.Add('## SharePoint i SQL')
$a=@(Get-AuditSectionRows 'WebApplications');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'WEBAPP' (F $r 'Url')),(B (F $r 'UseClaimsAuthentication')),(B (F $r 'AllowAnonymous')),(N (F $r 'ContentDatabaseCount')))}
Tbl 'Web Applications' @('Web App','Claims','Anonymous','Bazy') $t $a.Count
$a=@(Get-AuditSectionRows 'ContentDatabases');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'DB' (F $r 'Name')),(Alias 'SERVER' (F $r 'SqlServer')),(Alias 'WEBAPP' (F $r 'WebApplication')),(N (F $r 'SiteCollections')),(N (F $r 'MaximumSiteCount')),(B (F $r 'NeedsUpgrade')),(B (F $r 'RBS_Enabled')),(V (F $r 'BuildVersion')))}
Tbl 'Content Databases' @('DB','SQL node','Web App','Sites','Max','Upgrade','RBS','Build') $t $a.Count
$a=@(Get-AuditSectionRows 'SPDatabases');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'DB' (F $r 'Name')),(Alias 'SERVER' (F $r 'SqlServer')),(Kind (F $r 'Type')),(B (F $r 'NeedsUpgrade')),(V (F $r 'BuildVersion')))}
Tbl 'SP Databases' @('DB','SQL node','Typ','Upgrade','Build') $t $a.Count
$a=@(Get-AuditSectionRows 'SQLInstances');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'SQL' (F $r 'ConnectionName')),(Alias 'SERVER' (F $r 'ServerName')),(V (F $r 'ProductVersion')),(B (F $r 'HADR')),(B (F $r 'Clustered')))}
Tbl 'SQL Instances' @('Instancja','Serwer','Build','HADR','Cluster') $t $a.Count
$a=@(Get-AuditSectionRows 'SQLDatabases');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'DB' (F $r 'Name')),(Alias 'SQL' (F $r 'SQLInstance')),(B (F $r 'IsSharePointDB')),(E (F $r 'State') @('ONLINE','OFFLINE','RESTORING','RECOVERING','RECOVERY_PENDING','SUSPECT','EMERGENCY')),(E (F $r 'RecoveryModel') @('FULL','SIMPLE','BULK_LOGGED')),(N (F $r 'CompatibilityLevel')),(N (F $r 'DataAllocatedMB')),(N (F $r 'LogAllocatedMB')),(N (F $r 'TotalAllocatedMB')),(N (F $r 'FileStreamFiles')))}
Tbl 'SQL Databases' @('DB','SQL','SP','Status','Recovery','Compatibility','Data MB','Log MB','Total MB','FILESTREAM') $t $a.Count
$a=@(Get-AuditSectionRows 'SQLBackupHistory');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'DB' (F $r 'Name')),(Alias 'SQL' (F $r 'SQLInstance')),(E (F $r 'Type') @('D','I','L')),(DT (F $r 'LastBackupTime')),(B (F $r 'CopyOnly')),(N (F $r 'BackupSizeMB')))}
Tbl 'Backup SQL' @('DB','SQL','Typ','Ostatnia data','CopyOnly','MB') $t $a.Count
$a=@(Get-AuditSectionRows 'SQLBackupAuditStatus');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'SQL' (F $r 'SQLInstance')),(E (F $r 'Access') @('OK','FAILED')),(N (F $r 'Rows')))}
Tbl 'Backup msdb access' @('SQL','Stan','Rekordy') $t $a.Count
$a=@(Get-AuditSectionRows 'SiteCollections');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'SITE' (F $r 'Url')),(Alias 'DB' (F $r 'ContentDB')),(SiteTemplate (F $r 'Template')),(N (F $r 'StorageMB')),(DT (F $r 'LastContentModified')))}
Tbl 'Site Collections' @('Site','DB','Template','Storage MB','Ostatnia zmiana') $t $a.Count
[void]$md.Add('## Rozszerzenia, Search i workflow')
$a=@(Get-AuditSectionRows 'ServiceApplications');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'SERVICE' (F $r 'Name')),(Kind (F $r 'Type')),(Status (F $r 'Status')))}
Tbl 'Service Applications' @('Usluga','Typ','Stan') $t $a.Count
$a=@(Get-AuditSectionRows 'SearchComponents');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'SERVER' (F $r 'Server')),(Alias 'SERVICE' (F $r 'SearchApplication')),(Kind (F $r 'Type')))}
Tbl 'Search Components' @('Server','Search App','Typ') $t $a.Count
$a=@(Get-AuditSectionRows 'SolutionsWSP');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'WSP' (F $r 'Name')),(B (F $r 'Deployed')),(B (F $r 'ContainsGlobalAssembly')),(Status (F $r 'DeploymentState')))}
Tbl 'Rozwiazania WSP' @('WSP','Deployed','GAC','Stan') $t $a.Count
$a=@(Get-AuditSectionRows 'WorkflowAssociations');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'WEB' (F $r 'Web')),(Alias 'WORKFLOW' (F $r 'Name')),(B (F $r 'Enabled')))}
Tbl 'Workflow Associations' @('Web','Workflow','Enabled') $t $a.Count
$a=@(Get-AuditSectionRows 'WebAppZones');$t=@()
foreach($r in (Get-AuditTableLines $a)){$t+= , @((Alias 'WEBAPP' (F $r 'WebApplication')),(E (F $r 'Zone') @('Default','Internet','Intranet','Extranet','Custom')),(B (F $r 'UseSSL')),(B (F $r 'Anonymous')),(B (F $r 'DisableKerberos')))}
Tbl 'Strefy Web Apps' @('Web App','Zone','SSL','Anonymous','DisableKerberos') $t $a.Count
[void]$md.Add('## Dodatkowe liczniki')
foreach($name in @('ManagedAccounts','ServiceInstances','ServiceAppProxies','ServiceAppProxyGroups','ServiceAppPools','SearchApplications','SearchTopologies','CrawlSources','FarmFeatures','SiteFeatures','WebFeatures','TimerJobs','DisabledTimerJobs','HealthRules','HealthReports','IISBindings','Certificates','WindowsServices','Webs','Lists','MySites','ManagedPaths','AlternateAccessMappings')){
    [void]$md.Add(('- {0}: **{1}** rekordow' -f $name,@(Get-AuditSectionRows $name).Count))
}
[void]$md.Add('')
[void]$md.Add('## Ograniczenia')
[void]$md.Add('- Nazwy serwerow, kont, baz, domeny, URL, GUID, bindingi IIS, teksty Health Analyzer i surowe bledy nie sa kopiowane.')
[void]$md.Add('- Identyfikatory dzialaja tylko w tym eksporcie. Nie tworzymy pliku z mapowaniem nazw.')
[void]$md.Add('- Rozmiary, liczebnosci i wersje sa rzeczywiste i moga pozostawac informacja poufna.')
[void]$md.Add('- Zero rekordow moze znaczyc brak uprawnien lub pominiety skan, a nie brak ryzyka.')
[void]$md.Add('- Test-SPContentDatabase oraz testy funkcjonalne wymagaja osobnego uruchomienia na farmie SE.')
[void]$md.Add('')
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$defaultName='SP_Audit_SHAREABLE_'+$stamp+'.md'
if(-not $OutputPath){
    $OutputPath=Join-Path (Split-Path -Parent $root) $defaultName
} elseif(Test-Path -LiteralPath $OutputPath -PathType Container) {
    $OutputPath=Join-Path $OutputPath $defaultName
} elseif(-not [IO.Path]::GetExtension($OutputPath)) {
    # A file path without extension becomes a .md file. Existing directories were handled above.
    $OutputPath+='.md'
} elseif([IO.Path]::GetExtension($OutputPath) -ine '.md') {
    throw 'OutputPath musi wskazywac folder albo plik z rozszerzeniem .md.'
}
$OutputPath=[IO.Path]::GetFullPath($OutputPath)
$body=$md -join [Environment]::NewLine
# Extra check: fail closed on obvious raw identifiers, URLs and personal data.
$forbidden=@('(?i)https?://','(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}',
             '(?i)\\\\[a-z0-9._-]+\\','(?i)\b[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}\b')
foreach($p in $forbidden){if($body -match $p){throw 'Walidacja bezpieczenstwa nieudana. Nic nie zapisano.'}}
$dir=Split-Path -Parent $OutputPath
if(-not (Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
$tempOutput=Join-Path $dir ('SPSE_tmp_'+[guid]::NewGuid().ToString('N')+'.tmp')
try {
    [IO.File]::WriteAllText($tempOutput,$body,(New-Object System.Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $tempOutput -Destination $OutputPath -Force -ErrorAction Stop
} finally {
    if(Test-Path -LiteralPath $tempOutput){Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue}
}
Write-Host ('[RAPORT DO PRZEGLADU] '+$OutputPath) -ForegroundColor Green
Write-Warning 'Pseudonimizowany != anonimowy. Przed udostepnieniem obowiazkowo przejrzyj caly plik.'
