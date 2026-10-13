#requires -Version 5.1
<#
.SYNOPSIS
  Installs a ONE-TIME off-hours SharePoint migration readiness audit task.
.DESCRIPTION
  Run interactively as a local administrator on a SharePoint 2019 APP/WFE.
  Prompts for the scheduled-task account password via Get-Credential.
  Does not store passwords in a file or commit them to GitHub.
  Defaults to the next 22:00 in the SERVER LOCAL timezone.
  A missed trigger will NOT run later during business hours automatically.
.EXAMPLE
  .\Register-SPAuditTask.ps1
.EXAMPLE
  .\Register-SPAuditTask.ps1 -At '2026-10-14 22:00' -MaxWebs 5000
.EXAMPLE
  .\Register-SPAuditTask.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
    [string]$TaskName = 'SharePoint SE Full Audit',
    [datetime]$At,
    [string]$OutputRoot = 'C:\temp\sprawdzenie\SP_Audit',
    [ValidateRange(1,1000000)][int]$MaxWebs = 5000,
    [ValidateRange(1,24)][int]$MaxRunHours = 8,
    [switch]$SkipRemoteWinRM,
    [switch]$ReplaceExisting,
    [pscredential]$Credential
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not [Environment]::Is64BitProcess) {
    throw 'Uruchom Windows PowerShell 5.1 w wersji 64-bit.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Uruchom PowerShell jako administrator na serwerze SharePoint APP/WFE.'
}
Import-Module ScheduledTasks -ErrorAction Stop

$parentDir = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $PSScriptRoot 'Run-SPAudit-Night.ps1'
$required = @(
    $launcher,
    (Join-Path $parentDir 'Invoke-SP2019ReadinessAudit.ps1'),
    (Join-Path $parentDir 'New-SPSEDashboard.ps1'),
    (Join-Path $parentDir 'New-SPSEShareableAudit.ps1'),
    (Join-Path $parentDir 'dashboard_template.html')
)
foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw ("Brak wymaganego pliku: {0}. Zachowaj strukture v2.2/scheduler." -f $file)
    }
}
if ($launcher.Contains('"') -or $OutputRoot.Contains('"') -or
    $launcher.Contains([char]10) -or $OutputRoot.Contains([char]10)) {
    throw 'Niedozwolony znak w sciezce.'
}

if (-not $PSBoundParameters.ContainsKey('At')) {
    $At = (Get-Date).Date.AddHours(22)
    if ($At -le (Get-Date).AddMinutes(1)) { $At = $At.AddDays(1) }
} elseif ($At -le (Get-Date).AddMinutes(1)) {
    throw 'Podana data uruchomienia musi byc w przyszlosci.'
}

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -ne $existing -and -not $ReplaceExisting) {
    throw ("Zadanie '{0}' juz istnieje. Uzyj -ReplaceExisting tylko jesli chcesz je swiadomie zastapic." -f $TaskName)
}

$exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -OutputRoot "{1}" -MaxWebs {2}' -f
              $launcher,$OutputRoot,$MaxWebs)
if ($SkipRemoteWinRM) { $arguments += ' -SkipRemoteWinRM' }

$action = New-ScheduledTaskAction -Execute $exe -Argument $arguments -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Once -At $At
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours $MaxRunHours) -Priority 7 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Write-Host ('Task: {0}; time (server local): {1}; max runtime: {2} h.' -f
            $TaskName,$At.ToString('yyyy-MM-dd HH:mm:ss'),$MaxRunHours)
Write-Host ('Action: {0} {1}' -f $exe,$arguments)
Write-Warning 'Jednorazowy audyt produkcji moze obciazyc SQL/SharePoint. Sprawdz okna backupowe i obciazenie przed rejestracja.'

if (-not $PSCmdlet.ShouldProcess($TaskName, ('Register one-time full SharePoint audit at '+$At.ToString('s')))) {
    return
}

if ($null -eq $Credential) {
    $Credential = Get-Credential -UserName $identity.Name -Message 'Konto z dostepem do SharePoint, SQL, WinRM i prawem Log on as batch job'
}
if ($null -eq $Credential) { throw 'Nie podano konta zadania.' }
if ($Credential.UserName -match '^(?i:NT AUTHORITY\\(SYSTEM|LOCALSERVICE|NETWORKSERVICE))$') {
    throw 'Nie uzywaj konta SYSTEM/LOCAL SERVICE/NETWORK SERVICE.'
}

$password = $null
try {
    # Password exists in memory only during registration; Windows Task Scheduler stores
    # the logon secret securely as managed by Windows. Never log or export it.
    $password = $Credential.GetNetworkCredential().Password
    $params = @{
        TaskName = $TaskName
        Action = $action
        Trigger = $trigger
        Settings = $settings
        User = $Credential.UserName
        Password = $password
        RunLevel = 'Highest'
        Description = 'One-time read-only SharePoint 2019 to SE readiness audit; offline local HTML/CSV/JSON/MD reports.'
        ErrorAction = 'Stop'
    }
    if ($ReplaceExisting) { $params['Force'] = $true }
    Register-ScheduledTask @params | Out-Null
} finally {
    $password = $null
    $Credential = $null
}
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
Write-Host ('REGISTERED: {0} / state: {1}' -f $task.TaskName,$task.State) -ForegroundColor Green
Write-Host ('NEXT RUN: {0}; account: {1}' -f $At.ToString('yyyy-MM-dd HH:mm:ss'),$task.Principal.UserId)
Write-Host 'Po uruchomieniu sprawdz Get-ScheduledTaskInfo, AuditStatus.txt oraz lokalny log NightAudit_*.log.'
