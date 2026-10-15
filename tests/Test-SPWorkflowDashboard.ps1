#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repo=Split-Path -Parent $PSScriptRoot
$script=Join-Path $repo 'v2.4.2\New-SPWorkflowDashboard.ps1'
$tokens=$null;$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$parseErrors)
if(@($parseErrors).Count -gt 0){
    throw ('PowerShell parse errors: '+(@($parseErrors|ForEach-Object {$_.Message}) -join '; '))
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('SPSE_WF_HTML_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force|Out-Null
try{
    $fixture=[ordered]@{
        Version='2.4.1'
        Date='2026-10-15T14:00:00'
        WebUrl='https://internal.example.invalid/sites/test'
        ListTotal=2
        ListScanned=2
        ListTruncated=$false
        LegacyStatus='OK'
        Workflow2013Status='OK'
        SiteLegacy=@([pscustomobject]@{Name='Test Site Workflow';Enabled=$true;AutoStartCreate=$true;AutoStartChange=$false})
        ContentTypeLegacy=@()
        Lists=@(
            [pscustomobject]@{
                Id='11111111-1111-1111-1111-111111111111'
                Title='<script>alert(1)</script> INCIDENTS'
                Hidden=$false
                Legacy=@([pscustomobject]@{Name='Notify';Enabled=$true;AutoStartCreate=$true;AutoStartChange=$true})
                Workflow2013=@([pscustomobject]@{Name='Review';Enabled=$true;Scope='LIST';EventTypes=@('ItemAdded')})
            },
            [pscustomobject]@{
                Id='22222222-2222-2222-2222-222222222222';Title='No Workflow'
                Hidden=$false;Legacy=@();Workflow2013=@()
            }
        )
        Workflow2013=@([pscustomobject]@{Name='Review';Enabled=$true;Scope='LIST';EventTypes=@('ItemAdded')})
        Unmatched2013Count=0
        SMTP=[ordered]@{ServerConfigured=$true;FromConfigured=$true;Server='secret-host'}
        WorkflowManager=[ordered]@{Available=$true;Status='Online'}
        TimerService='Running'
        TimerJobs=@()
        Errors=@()
    }
    $fixture|ConvertTo-Json -Depth 12|Out-File -LiteralPath (Join-Path $root 'WorkflowSite_PRIVATE.json') -Encoding UTF8
    & $script -InputPath $root
    $target=Join-Path $root 'WorkflowSite_Dashboard.html'
    if(-not(Test-Path -LiteralPath $target -PathType Leaf)){throw 'Missing generated HTML'}
    $html=Get-Content -LiteralPath $target -Raw -Encoding UTF8
    foreach($needle in @('SharePoint · audyt Workflow','Workflow 2010','Workflow 2013',
        'Review','2010','INCIDENTS','id="listrows"','document.getElementById','ItemAdded')){
        if(-not $html.Contains($needle)){throw ('Expected HTML item missing: '+$needle)}
    }
    if($html.Contains('<script>alert(1)</script>') -or -not $html.Contains('&lt;script&gt;')){
        throw 'Unsafe HTML interpolation — unescaped dynamic list title'
    }
    if($html.Contains('secret-host')){throw 'SMTP host should not be shown in dashboard summary'}
    if($html -match 'https?://[^"]+\.js' -or $html -match '<link rel="stylesheet"'){
        throw 'Unexpected external dashboard dependencies'
    }
    Write-Host 'PASS: offline workflow dashboard, counts, searchable table and HTML escaping.' -ForegroundColor Green
}finally{
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
