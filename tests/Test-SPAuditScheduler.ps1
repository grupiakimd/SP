#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repoRoot=Split-Path -Parent $PSScriptRoot
$files=@(
    'v2.2\Invoke-SP2019ReadinessAudit.ps1',
    'v2.2\New-SPSEDashboard.ps1',
    'v2.2\New-SPSEShareableAudit.ps1',
    'v2.2\scheduler\Run-SPAudit-Night.ps1',
    'v2.2\scheduler\Register-SPAuditTask.ps1'
)
foreach($rel in $files){
    $full=Join-Path $repoRoot $rel
    if(-not (Test-Path -LiteralPath $full -PathType Leaf)){throw ('Missing: '+$rel)}
    $tokens=$null;$parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($full,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -gt 0){
        $msg=@($parseErrors|ForEach-Object {$_.Message}) -join '; '
        throw ('PowerShell parse errors: '+$rel+' | '+$msg)
    }
    Write-Host ('PARSE OK: '+$rel)
}
$reg=Get-Content -LiteralPath (Join-Path $repoRoot 'v2.2\scheduler\Register-SPAuditTask.ps1') -Raw
$run=Get-Content -LiteralPath (Join-Path $repoRoot 'v2.2\scheduler\Run-SPAudit-Night.ps1') -Raw
if($reg -notmatch 'New-ScheduledTaskTrigger\s+-Once\s+-At'){throw 'Expected a one-time trigger.'}
if($reg -notmatch 'Get-Credential'){throw 'Expected interactive account credential prompt.'}
if($reg -notmatch 'Register-ScheduledTask\s+@params'){throw 'Expected explicit scheduled task registration.'}
if($reg -match '(?i)Invoke-WebRequest|Invoke-RestMethod|gh\s+auth'){throw 'Unexpected remote download in scheduler.'}
if($run -notmatch 'ShareableReport\s*=\s*\$true'){throw 'Expected MD report.'}
if($run -notmatch 'DeepWebScan\s*=\s*\$true'){throw 'Expected deep scan.'}
if($run -notmatch 'Start-Transcript'){throw 'Expected local transcript.'}
Write-Host 'PASS: scheduler parse and safe one-time configuration checks.'
