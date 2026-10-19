#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$root=Split-Path -Parent $PSScriptRoot
$paths=@(
    'v2.5\Collect-SPWorkflowDefinitions.ps1',
    'v2.5\New-SPWorkflowMigrationReport.ps1',
    'v2.5\Invoke-SPWorkflowMigrationAudit.ps1'
)
foreach($p in $paths){
    $path=Join-Path $root $p
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if(@($errors).Count -gt 0){
        throw ('Parse errors in '+$p+': '+(@($errors|ForEach-Object {$_.Message}) -join '; '))
    }
}
$collection=Get-Content (Join-Path $root $paths[0]) -Raw
foreach($needle in @('DtdProcessing','MaxMarkupBytes','Workflow2013','Inspect-Markup',
                      'BaseTemplateId','Workflow2010Markup','DefinitionLinked=$false',
                      'WorkflowDefinitions_PRIVATE.json')){
    if(-not $collection.Contains($needle)){throw ('Missing required collector guard: '+$needle)}
}
foreach($mutation in @('StartWorkflowOnListItem','Start-SPWorkflow','Register-SPWorkflowService',
                        'Remove-SPWorkflow','SPUtility.SendEmail','Update-SPListItem','Set-SPWebApplication')){
    if($collection.Contains($mutation)){throw ('Unsafe API call pattern: '+$mutation)}
}
$folder=Join-Path ([IO.Path]::GetTempPath()) ('SPWF_V25_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $folder -Force|Out-Null
try{
    $fixture=[ordered]@{
        Schema='SP-WF-DEFINITIONS-v2.5'
        WebUrl='https://private-domain.example/sites/sensitive'
        Coverage=[ordered]@{
            Workflow2010='OK';Workflow2010Markup='OK';Workflow2013='FAILED'
            ListsScanned=519;ListsTotal=519;ListsTruncated=$false
            MarkupFilesTruncated=$false;Definitions2013Truncated=$false
        }
        Associations2010=@(
            [pscustomobject]@{
                Scope='LIST';Name='SECRET-WORKFLOW';Owner='SENSITIVE-LIST'
                Enabled=$true;AutoStartCreate=$true;AutoStartChange=$false
                IsDeclarative=$true;DefinitionLinked=$false;LinkEvidence='NOT_RESOLVED'
            },
            [pscustomobject]@{
                Scope='LIST';Name='OLD-WORKFLOW';Owner='SENSITIVE-LIST'
                Enabled=$false;AutoStartCreate=$false;AutoStartChange=$false
                IsDeclarative=$true;DefinitionLinked=$false;LinkEvidence='NOT_RESOLVED'
            }
        )
        MarkupArtifacts2010=@(
            [pscustomobject]@{
                Path='/sites/private/Workflows/SecretA.xoml';Extension='.xoml'
                Parse='OK';Elements=7;Categories=@('EMAIL')
                SignatureHash='aa123';ActionHints=@('SendEmail')
            },
            [pscustomobject]@{
                Path='/sites/private/Workflows/SecretB.xoml';Extension='.xoml'
                Parse='OK';Elements=7;Categories=@('EMAIL')
                SignatureHash='aa123';ActionHints=@('SendEmail')
            }
        )
        Subscriptions2013=@();Definitions2013=@()
        Errors=@([pscustomobject]@{Section='Workflow2013';Type='InvalidOperationException';
            Message='SECRET DOMAIN username@corp.example /sites/private'})
    }
    $json=Join-Path $folder 'WorkflowDefinitions_PRIVATE.json'
    $fixture|ConvertTo-Json -Depth 15 | Out-File -LiteralPath $json -Encoding UTF8
    & (Join-Path $root $paths[1]) -InputPath $folder
    $mdFile=Join-Path $folder 'WorkflowMigration_SHAREABLE.md'
    $htmlFile=Join-Path $folder 'WorkflowMigration_Dashboard.html'
    if(-not (Test-Path $mdFile) -or -not(Test-Path $htmlFile)){throw 'Missing files.'}
    $md=Get-Content $mdFile -Raw -Encoding UTF8
    $html=Get-Content $htmlFile -Raw -Encoding UTF8
    foreach($secret in @('SECRET-WORKFLOW','SENSITIVE-LIST','OLD-WORKFLOW',
                         'SecretA.xoml','private-domain.example','username@corp.example',
                         '/sites/private')){
        if($md.IndexOf($secret,[StringComparison]::OrdinalIgnoreCase) -ge 0){
            throw ('Shareable data leak: '+$secret)
        }
    }
    foreach($expected in @('FAMILY-001','EMAIL','2010','2013','CZESCIOWA')){
        if(-not $md.Contains($expected)){throw ('Expected MD item missing: '+$expected)}
    }
    if(-not $html.Contains('SECRET-WORKFLOW') -or -not $html.Contains('SecretA.xoml')){
        throw 'Admin HTML must show private workflow names.'
    }
    Write-Host 'PASS: v2.5 PowerShell parsing, no modifying APIs, XML grouping, HTML and pseudonymized MD.' -ForegroundColor Green
}finally{
    Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
}
