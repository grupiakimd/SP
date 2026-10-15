#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repoRoot=Split-Path -Parent $PSScriptRoot
$files=@('v2.3\Collect-SPSESqlLocal.ps1','v2.3\Merge-SPSEAudit.ps1',
    'v2.3\New-SPSEDashboard.ps1','v2.3\New-SPSEShareableAudit.ps1')
foreach($file in $files){
    $full=Join-Path $repoRoot $file
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($full,[ref]$tokens,[ref]$errors)
    if(@($errors).Count -gt 0){throw ("Parse error in {0}: {1}" -f $file,(@($errors|ForEach-Object {$_.Message}) -join '; '))}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('SPSE_SQL_MERGE_TEST_'+[guid]::NewGuid().ToString('N'))
$spDir=Join-Path $root 'sp';$sqlDir=Join-Path $root 'sql';$out=Join-Path $root 'output'
New-Item -ItemType Directory -Path $spDir,$sqlDir,$out -Force|Out-Null
try{
    $sp=[ordered]@{
        Metadata=[ordered]@{
            FarmBuild='16.0.10399.20000';Started='2026-10-15T09:00:00';Collector='FAKE-APP'
            Sources='test-only';AuditVersion='test';SQLRequested=$true
            SQLInstancesDiscovered=1;RemoteOSRequested=$true;DeepWebScan=$true
            DeepScannedWebs=2;DeepWebLimitReached=$false
        }
        Risks=@();Errors=@([pscustomobject]@{Section='SQLInventory';Message='Remote SQL error from synthetic test'})
        FarmServers=@([pscustomobject]@{Name='FAKE-APP';Role='Application';Status='Online';BuildVersion='16.0.10399.20000'})
        WebApplications=@([pscustomobject]@{Url='https://private.invalid';UseClaimsAuthentication=$true;AllowAnonymous=$false;ContentDatabaseCount=1})
        ContentDatabases=@([pscustomobject]@{Name='PRIVATE_DB';SqlServer='FAKE-SQL';WebApplication='https://private.invalid';SiteCollections=1;MaximumSiteCount=500;BuildVersion='16.0.10399.20000'})
        SPDatabases=@([pscustomobject]@{Name='PRIVATE_DB';SqlServer='FAKE-SQL';Type='ContentDatabase';BuildVersion='16.0.10399.20000'})
        SiteCollections=@([pscustomobject]@{Url='https://private.invalid/sites/main';ContentDB='PRIVATE_DB';Template='STS';StorageMB=200})
        SQLInstances=@();SQLDatabases=@();SQLBackupHistory=@();SQLBackupAuditStatus=@()
        OSInventory=@();ServerDisks=@()
    }
    $sp|ConvertTo-Json -Depth 12|Out-File -LiteralPath (Join-Path $spDir 'FullInventory.json') -Encoding UTF8
    $sql=[ordered]@{
        Schema='SPSE-SQL-LOCAL-v1'
        Metadata=[ordered]@{
            Source='LOCAL_SQL_SHARED_MEMORY';ExecutedAt='2026-10-15T10:00:00'
            FinishedAt='2026-10-15T10:05:00';Host='FAKE-SQL';SQLStatus='OK'
        }
        SQLInstances=@([pscustomobject]@{ConnectionName='FAKE-SQL';ServerName='FAKE-SQL';ProductVersion='15.0.4000.0';HADR=0;Clustered=0})
        SQLDatabases=@([pscustomobject]@{Name='PRIVATE_DB';State='ONLINE';RecoveryModel='FULL';
            CompatibilityLevel=150;DataAllocatedMB=51200;LogAllocatedMB=1000;TotalAllocatedMB=52200;FileStreamFiles=0})
        SQLBackupHistory=@([pscustomobject]@{Name='PRIVATE_DB';Type='D';LastBackupTime='2026-10-14T20:00:00';BackupSizeMB=900;CopyOnly=$false})
        SQLBackupAuditStatus=@([pscustomobject]@{Access='OK';Rows=1})
        SQLSettings=@([pscustomobject]@{SettingName='max server memory (MB)';ValueInUse=24576})
        SQLStorage=@([pscustomobject]@{DatabaseName='PRIVATE_DB';FileType='ROWS';AllocatedMB=51200;
            GrowthValue=1024;GrowthIsPercent=$false;State='ONLINE'})
        OSInventory=@([pscustomobject]@{Computer='FAKE-SQL';OS='Windows Server 2019';PhysicalRAM_GB=32;LogicalCPU=8})
        ServerDisks=@([pscustomobject]@{Computer='FAKE-SQL';CapacityGB=500;FreeGB=100;FreePct=20})
        Errors=@()
    }
    $sql|ConvertTo-Json -Depth 12|Out-File -LiteralPath (Join-Path $sqlDir 'SQLInventory.json') -Encoding UTF8
    & (Join-Path $repoRoot 'v2.3\Merge-SPSEAudit.ps1') -SharePointAuditPath $spDir -SqlAuditPath $sqlDir -OutputRoot $out -SqlInstanceAlias 'FAKE-SQL'
    $merged=@(Get-ChildItem -LiteralPath $out -Directory -Filter 'Merged_*')
    if($merged.Count -ne 1){throw 'Missing unique merged output folder.'}
    $folder=$merged[0].FullName
    foreach($f in @('FullInventory.json','SPSE_Readiness_Report_MERGED.html','SP_Audit_SHAREABLE_MERGED.md','MergeStatus.txt')){
        if(-not (Test-Path -LiteralPath (Join-Path $folder $f) -PathType Leaf)){throw ('Missing output '+$f)}
    }
    $result=Get-Content -LiteralPath (Join-Path $folder 'FullInventory.json') -Raw|ConvertFrom-Json
    if($result.SQLDatabases[0].TotalAllocatedMB -ne 52200){throw 'SQL data not merged'}
    if($result.SQLSettings[0].ValueInUse -ne 24576){throw 'SQL settings not merged'}
    if(-not $result.Metadata.SQLAuditMerged){throw 'Missing provenance'}
    $html=Get-Content -LiteralPath (Join-Path $folder 'SPSE_Readiness_Report_MERGED.html') -Raw
    if($html -notmatch 'SQLStorage' -or $html -notmatch 'LOCAL_SQL_SHARED_MEMORY'){throw 'HTML does not show SQL local source'}
    $md=Get-Content -LiteralPath (Join-Path $folder 'SP_Audit_SHAREABLE_MERGED.md') -Raw
    if($md -match 'PRIVATE_DB|private\.invalid|FAKE-SQL' -or $md -notmatch '52200' -or $md -notmatch '24576'){
        throw 'Markdown privacy or completeness regression'
    }
    Write-Host 'PASS: offline SQL merge, dashboard, anonymized Markdown and provenance' -ForegroundColor Green
}finally{
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
