#requires -Version 5.1
<#
.SYNOPSIS
  Merge read-only SharePoint audit and locally collected SQL audit into new HTML and MD.
.DESCRIPTION
  Never modifies the source audit files or the SharePoint/SQL farm.
  Requires the other three scripts in the same folder:
  New-SPSEDashboard.ps1, dashboard_template.html, New-SPSEShareableAudit.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SharePointAuditPath,
    [Parameter(Mandatory=$true)][string]$SqlAuditPath,
    [string]$OutputRoot,
    [string]$SqlInstanceAlias
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
function Find-Inventory([string]$Path,[string]$Name) {
    $item=Get-Item -LiteralPath $Path -ErrorAction Stop
    if(-not $item.PSIsContainer) {
        if($item.Name -ne $Name){throw ("Wskaz plik {0}, nie {1}" -f $Name,$item.Name)}
        return $item.FullName
    }
    $found=@(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Filter $Name -ErrorAction Stop |
        Where-Object { $_.FullName -notmatch '(?i)[\\/]Merged_[^\\/]+[\\/]' } |
        Sort-Object LastWriteTime -Descending)
    if($found.Count -eq 0){throw ("Nie znaleziono {0} pod {1}" -f $Name,$item.FullName)}
    return $found[0].FullName
}
function Prop($obj,[string]$name) {
    if($null -eq $obj){return $null}
    $p=$obj.PSObject.Properties[$name]
    if($null -eq $p){return $null}
    return $p.Value
}
function Put($obj,[string]$name,$value){
    $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
}
$spFile=Find-Inventory $SharePointAuditPath 'FullInventory.json'
$sqlFile=Find-Inventory $SqlAuditPath 'SQLInventory.json'
Write-Host ("SP source: {0}" -f $spFile)
Write-Host ("SQL source: {0}" -f $sqlFile)
if($spFile -eq $sqlFile){throw 'Bledne pliki wejsciowe.'}
$sp=Get-Content -LiteralPath $spFile -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
$sql=Get-Content -LiteralPath $sqlFile -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
if(-not $sp.PSObject.Properties['Metadata'] -or
   -not $sql.PSObject.Properties['Schema'] -or
   $sql.Schema -ne 'SPSE-SQL-LOCAL-v1'){
    throw 'Niepoprawny format wejscia. Wymagane FullInventory.json i SQLInventory.json v2.3.'
}
if(@($sql.SQLInstances).Count -eq 0){throw 'Lokalny raport SQL nie zawiera informacji o instancji.'}
$sourceSQL=[string](Prop $sql.SQLInstances[0] 'ConnectionName')
if(-not $sourceSQL){throw 'Nie mozna ustalic instancji SQL z lokalnego raportu.'}
$referenceSQL=if($SqlInstanceAlias){$SqlInstanceAlias}else{$sourceSQL}
$knownSPNames=@(@($sp.SPDatabases)+@($sp.ContentDatabases) |
    ForEach-Object { [string](Prop $_ 'SqlServer') } | Where-Object { $_ } | Sort-Object -Unique)
$aliasMatched=($referenceSQL -in $knownSPNames)
if(-not $aliasMatched -and $knownSPNames.Count -gt 0){
    Write-Warning 'Identyfikator SQL rozni sie od SharePoint SqlServer. Zachowam nazwy baz i oznacze powiazanie jako niepotwierdzone. W razie aliasu podaj -SqlInstanceAlias.'
}
$expected=@{}
foreach($database in @($sp.SPDatabases)+@($sp.ContentDatabases)){
    $name=[string](Prop $database 'Name')
    if($name){$expected[$name.ToLowerInvariant()]=$true}
}
$mappedInstances=@(foreach($r in @($sql.SQLInstances)){
    $x=$r.PSObject.Copy()
    Put $x 'ConnectionName' $referenceSQL
    $x
})
$mappedDb=@(foreach($r in @($sql.SQLDatabases)){
    $x=$r.PSObject.Copy()
    $name=[string](Prop $x 'Name')
    Put $x 'SQLInstance' $referenceSQL
    Put $x 'IsSharePointDB' ($expected.ContainsKey($name.ToLowerInvariant()))
    $x
})
$mappedBackup=@(foreach($r in @($sql.SQLBackupHistory)){
    $x=$r.PSObject.Copy()
    Put $x 'SQLInstance' $referenceSQL
    $x
})
$mappedStatus=@(foreach($r in @($sql.SQLBackupAuditStatus)){
    $x=$r.PSObject.Copy()
    Put $x 'SQLInstance' $referenceSQL
    $x
})
if($mappedStatus.Count -eq 0){
    $mappedStatus=@([pscustomobject]@{SQLInstance=$referenceSQL;Access='FAILED';Rows=0})
}
# Replace ONLY the remote SQL sections. Existing source evidence remains unchanged.
foreach($pair in @(
    @{Name='SQLInstances';Data=$mappedInstances},@{Name='SQLDatabases';Data=$mappedDb},
    @{Name='SQLBackupHistory';Data=$mappedBackup},
    @{Name='SQLBackupAuditStatus';Data=$mappedStatus},
    @{Name='SQLSettings';Data=@($sql.SQLSettings)},
    @{Name='SQLStorage';Data=@($sql.SQLStorage)}
)){
    Put $sp $pair.Name $pair.Data
}
# Add locally collected OS/disk evidence without relying on remote RPC.
$hostName=[string](Prop $sql.Metadata 'Host')
$existingOs=@($sp.OSInventory | Where-Object {[string](Prop $_ 'Computer') -ine $hostName})
$existingDisks=@($sp.ServerDisks | Where-Object {[string](Prop $_ 'Computer') -ine $hostName})
Put $sp 'OSInventory' @($existingOs)+@($sql.OSInventory)
Put $sp 'ServerDisks' @($existingDisks)+@($sql.ServerDisks)
$originalErrors=@($sp.Errors)
$localIssues=@(foreach($e in @($sql.Errors)){
    [pscustomobject]@{Section=('SQL_LOCAL_'+(Prop $e 'Section'));Message=(Prop $e 'Message');
        Time=(Prop $sql.Metadata 'FinishedAt')}
})
Put $sp 'Errors' (@($originalErrors)+@($localIssues))
$risks=@($sp.Risks)
if(-not $aliasMatched -and $knownSPNames.Count -gt 0){
    $risks+= [pscustomobject]@{
        Priority='UNKNOWN';Code='SQL_INSTANCE_MAPPING_UNCONFIRMED';Object=$referenceSQL
        Observation='Sprawdz mapowanie SQL alias/FQDN i nazwe instancji z farmy SharePoint.'
        Recommendation='Uruchom scalanie ponownie z -SqlInstanceAlias jezeli instancja korzysta z aliasu.'
    }
}
foreach($db in $mappedDb | Where-Object {$_.IsSharePointDB}){
    if($db.State -ne 'ONLINE'){
        $risks+= [pscustomobject]@{Priority='HIGH';Code='SQL_DB_NOT_ONLINE';Object=$db.Name;
            Observation=('Lokalny SQL stan bazy: '+$db.State);Recommendation='Wyjasnic przed migracja.'}
    }
    if([decimal]$db.TotalAllocatedMB -gt 307200){
        $risks+= [pscustomobject]@{Priority='MEDIUM';Code='LARGE_DATABASE_300GB';Object=$db.Name;
            Observation='Rozmiar zaalokowany przekracza 300 GB.'
            Recommendation='Zaplanuj czas backup/restore i test przepustowosci.'}
    }
    if(@($mappedBackup | Where-Object { $_.Name -eq $db.Name -and $_.Type -eq 'D' }).Count -eq 0){
        $risks+= [pscustomobject]@{Priority='UNKNOWN';Code='FULL_BACKUP_NOT_IN_MSDB';Object=$db.Name;
            Observation='Brak FULL backup w msdb. Mozliwy backup zewnetrzny.'
            Recommendation='Potwierdz odtwarzalna kopie i test restore.'}
    }
}
Put $sp 'Risks' @($risks)
Put $sp.Metadata 'SQLAuditSource' 'LOCAL_SQL_SHARED_MEMORY'
Put $sp.Metadata 'SQLAuditMerged' $true
Put $sp.Metadata 'SQLAuditSourceTime' ([string]$sql.Metadata.ExecutedAt)
Put $sp.Metadata 'SQLAuditStatus' ([string]$sql.Metadata.SQLStatus)
Put $sp.Metadata 'SQLAuditOriginalRemoteErrors' (@($originalErrors | Where-Object {$_.Section -in @('SQLInventory','SQLBackupHistory')}).Count)
Put $sp.Metadata 'SQLAuditLocalErrors' (@($localIssues).Count)
Put $sp.Metadata 'SQLInstancesDiscovered' $mappedInstances.Count
Put $sp.Metadata 'SQLInstanceAliasConfirmed' $aliasMatched
Put $sp.Metadata 'ReadinessScore' 'NOT_SCORED_INCOMPLETE_EVIDENCE'
Put $sp.Metadata 'Finished' (Get-Date).ToString('s')
if(-not $OutputRoot){$OutputRoot=Split-Path -Parent $spFile}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$outDir=Join-Path $OutputRoot ('Merged_'+$stamp)
New-Item -ItemType Directory -Path $outDir -Force|Out-Null
$target=Join-Path $outDir 'FullInventory.json'
$sp | ConvertTo-Json -Depth 16 | Out-File -LiteralPath $target -Encoding UTF8 -ErrorAction Stop
$mdFile=Join-Path $outDir 'SP_Audit_SHAREABLE_MERGED.md'
$htmlFile=Join-Path $outDir 'SPSE_Readiness_Report_MERGED.html'
$dashboard=Join-Path $PSScriptRoot 'New-SPSEDashboard.ps1'
$shareable=Join-Path $PSScriptRoot 'New-SPSEShareableAudit.ps1'
foreach($f in @($dashboard,$shareable,(Join-Path $PSScriptRoot 'dashboard_template.html'))){
    if(-not (Test-Path -LiteralPath $f -PathType Leaf)){throw ('Brak skryptu lub szablonu: '+$f)}
}
& $dashboard -InputPath $target -OutputPath $htmlFile -ErrorAction Stop
if(-not (Test-Path -LiteralPath $htmlFile -PathType Leaf)){throw 'Brak scalonego raportu HTML.'}
& $shareable -InputPath $target -OutputPath $mdFile -ErrorAction Stop
if(-not (Test-Path -LiteralPath $mdFile -PathType Leaf)){throw 'Brak scalonego raportu MD.'}
@(
    'Merged SharePoint + Local SQL'
    'SQL source: LOCAL_SQL_SHARED_MEMORY'
    'SQL state: '+$sql.Metadata.SQLStatus
    'Original remote SQL errors retained: '+$sp.Metadata.SQLAuditOriginalRemoteErrors
    'Local SQL errors: '+$sp.Metadata.SQLAuditLocalErrors
    'Alias matched SharePoint: '+$aliasMatched
) | Set-Content -LiteralPath (Join-Path $outDir 'MergeStatus.txt') -Encoding UTF8
Write-Host ('[MERGED] HTML: '+$htmlFile) -ForegroundColor Green
Write-Host ('[MERGED] MD:   '+$mdFile) -ForegroundColor Green
Write-Warning 'FullInventory.json and HTML are confidential. Review pseudonymized MD manually before sharing.'
