#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$root=Split-Path -Parent $PSScriptRoot
$file=Join-Path $root 'v2.4\Invoke-SPWorkflowDiagnostic.ps1'
if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw 'Workflow diagnostic script not found.'}
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
if(@($errors).Count -gt 0){
  throw ('PowerShell parsing errors: '+(@($errors|ForEach-Object {$_.Message}) -join '; '))
}
$s=Get-Content -LiteralPath $file -Raw -Encoding UTF8
foreach($required in @('Get-SPWeb','AutoStartCreate','AutoStartChange','Get-SPWorkflowServiceApplicationProxy',
                       'EnumerateSubscriptionsByList','GetItemWorkflows','SPTimerV4',
                       'WorkflowDiagnostic_PRIVATE.json','WorkflowDiagnostic_SHAREABLE.md')){
  if(-not $s.Contains($required)){throw ('Required check missing: '+$required)}
}
foreach($destructive in @('StartWorkflowOnListItem','Start-SPWorkflow','Register-SPWorkflowService','Set-SPWebApplication',
                        'New-SPListItem','SPUtility.SendEmail','Enable-SPFeature','Stop-Service','Restart-Service')){
  if($s.Contains($destructive)){throw ('Unexpected destructive operation: '+$destructive)}
}
Write-Host 'PASS: PowerShell 5.1 parser and read-only workflow diagnostics markers.' -ForegroundColor Green
