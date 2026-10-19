#requires -Version 5.1
<#
.SYNOPSIS
  One command: collect SP2010/2013 workflow definitions and build offline HTML+MD.
.DESCRIPTION
  READ ONLY. Writes PRIVATE inventory + dashboard and separate pseudonymized Markdown.
.EXAMPLE
  .\Invoke-SPWorkflowMigrationAudit.ps1 -WebUrl 'https://portal/sites/workflows'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WebUrl,
    [string]$OutputRoot='C:\SP_Workflow_Migration',
    [ValidateRange(1,10000)][int]$MaxLists=1500,
    [ValidateRange(1,10000)][int]$MaxMarkupFiles=1500,
    [ValidateRange(16384,8388608)][int]$MaxMarkupBytes=1048576,
    [ValidateRange(1,2000)][int]$Max2013Definitions=500
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$collector=Join-Path $PSScriptRoot 'Collect-SPWorkflowDefinitions.ps1'
$report=Join-Path $PSScriptRoot 'New-SPWorkflowMigrationReport.ps1'
foreach($f in @($collector,$report)){
    if(-not(Test-Path -LiteralPath $f -PathType Leaf)){throw ('Missing script in v2.5: '+$f)}
}
New-Item -ItemType Directory -Path $OutputRoot -Force|Out-Null
$start=Get-Date
$collectArgs=@{
    WebUrl=$WebUrl
    OutputRoot=$OutputRoot
    MaxLists=$MaxLists
    MaxMarkupFiles=$MaxMarkupFiles
    MaxMarkupBytes=$MaxMarkupBytes
    Max2013Definitions=$Max2013Definitions
    ErrorAction='Stop'
}
& $collector @collectArgs
$matches=@(Get-ChildItem -LiteralPath $OutputRoot -Recurse -File -Filter 'WorkflowDefinitions_PRIVATE.json' |
    Where-Object {$_.LastWriteTime -ge $start.AddMinutes(-1)} |
    Sort-Object LastWriteTime -Descending)
if($matches.Count -eq 0){throw 'No new private inventory found; see collector output/errors.'}
$source=$matches[0].FullName
& $report -InputPath $source -ErrorAction Stop
$out=Split-Path -Parent $source
foreach($name in @('WorkflowMigration_Dashboard.html','WorkflowMigration_SHAREABLE.md')){
    if(-not (Test-Path -LiteralPath (Join-Path $out $name) -PathType Leaf)){
        throw ('Expected report missing: '+$name)
    }
}
Write-Host 'COMPLETED: v2.5 workflow migration audit (HTML + MD)' -ForegroundColor Green
Write-Host ('Output folder: '+$out)
Write-Warning 'PRIVATE JSON and HTML contain real infrastructure names. Only reviewed MD may be shared.'
