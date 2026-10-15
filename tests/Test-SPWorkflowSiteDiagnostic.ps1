#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$file=Join-Path $root 'v2.4.1\Invoke-SPWorkflowSiteDiagnostic.ps1'
$tokens=$null; $errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
if(@($errors).Count -gt 0){throw ('PowerShell parse error: '+(@($errors|ForEach-Object {$_.Message}) -join '; '))}
$s=Get-Content -LiteralPath $file -Encoding UTF8 -Raw
foreach($needle in @('-WebUrl','EnumerateSubscriptions()','SiteLegacy','ContentTypeLegacy','ListTruncated','WorkflowSite_SHAREABLE.md','Workflow2013Status')){
    if(-not $s.Contains($needle)){throw ('Missing site workflow diagnostic: '+$needle)}
}
if($s.Contains('Parameter(Mandatory=$true)][string]$ListTitle')){throw 'Unexpected required ListTitle'}
foreach($bad in @('StartWorkflowOnListItem','Start-SPWorkflow','Register-SPWorkflowService','Set-SPWebApplication','New-SPListItem','SPUtility.SendEmail','Enable-SPFeature','Stop-Service','Restart-Service')){
    if($s.Contains($bad)){throw ('Potential mutation operation: '+$bad)}
}
Write-Host 'PASS: v2.4.1 site workflow PowerShell parser and static checks.' -ForegroundColor Green