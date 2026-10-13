#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Join-Path ([IO.Path]::GetTempPath()) ('SPSE_PRIVACY_TEST_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $fixture=[ordered]@{
        Metadata=[ordered]@{FarmBuild='16.0.10399.20000';SQLRequested=$true;DeepWebScan=$true}
        Risks=@([pscustomobject]@{
            Priority='HIGH';Code='RBS';Object='SECRET_CONTENT_DB';
            Observation='Kontakt: alice@example.org, adres https://intranet.corp.example.local';
            Recommendation='Password=not-a-real-password'
        })
        Errors=@([pscustomobject]@{
            Section='SQL';Message='C:\secret\alice@example.org password=fake'
        })
        FarmServers=@([pscustomobject]@{Name='SP-APP01.corp.example.local';Role='Application';Status='Online';BuildVersion='16.0.10399.20000'})
        OSInventory=@([pscustomobject]@{Computer='SP-APP01.corp.example.local';OS='Microsoft Windows Server 2019 Datacenter';PhysicalRAM_GB=32;LogicalCPU=8;Domain='corp.example.local'})
        WebApplications=@([pscustomobject]@{Url='https://intranet.corp.example.local';UseClaimsAuthentication=$true;AllowAnonymous=$false;ContentDatabaseCount=1})
        ContentDatabases=@([pscustomobject]@{Name='SECRET_CONTENT_DB';SqlServer='SQL-01.corp.example.local';WebApplication='https://intranet.corp.example.local';SiteCollections=2;MaximumSiteCount=500;NeedsUpgrade=$false;RBS_Enabled=$true;BuildVersion='16.0.10399.20000'})
        SQLDatabases=@([pscustomobject]@{Name='SECRET_CONTENT_DB';SQLInstance='SQL-01.corp.example.local';IsSharePointDB=$true;State='ONLINE';RecoveryModel='FULL';CompatibilityLevel=150;DataAllocatedMB=50100;LogAllocatedMB=1200;TotalAllocatedMB=51300;FileStreamFiles=0})
        SiteCollections=@([pscustomobject]@{Url='https://intranet.corp.example.local/sites/hr';ContentDB='SECRET_CONTENT_DB';Template='STS#0';StorageMB=700;Owner='corp\alice';LastContentModified='2026-10-01'})
        SolutionsWSP=@([pscustomobject]@{Name='secret-payroll.wsp';Deployed=$true;ContainsGlobalAssembly=$true;DeploymentState='Deployed'})
        HealthReports=@([pscustomobject]@{Title='Secret HR issue';Explanation='bob@example.org';Remedy='token=secret'})
    }
    $fixture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $root 'FullInventory.json') -Encoding UTF8
    $out=Join-Path $root 'Shareable_Audit.md'
    & (Join-Path $PSScriptRoot '..\v2.2\New-SPSEShareableAudit.ps1') -InputPath $root -OutputPath $out
    if(-not (Test-Path -LiteralPath $out)){throw 'Nie utworzono raportu.'}
    $md=Get-Content -LiteralPath $out -Raw -Encoding UTF8
    foreach($secret in @('SECRET_CONTENT_DB','corp.example.local','alice@example.org','bob@example.org',
                         'secret-payroll.wsp','corp\alice','SP-APP01','SQL-01','https://',
                         'not-a-real-password','token=secret','Secret HR issue')){
        if($md.IndexOf($secret,[System.StringComparison]::OrdinalIgnoreCase) -ge 0){
            throw ('Wykrtyo wyciek: '+$secret)
        }
    }
    foreach($expected in @('DB-001','WEBAPP-001','SERVER-001','51300','RBS','WSP-001')){
        if($md.IndexOf($expected,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){
            throw ('Brak oczekiwanej danej technicznej: '+$expected)
        }
    }
    Write-Host 'PASS: pseudonimizacja i zachowanie zaleznosci dzialaja na fikcyjnych danych.' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}