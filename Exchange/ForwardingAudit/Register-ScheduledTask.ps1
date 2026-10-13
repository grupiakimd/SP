#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ScriptDirectory,[string]$TaskName='Exchange-Forwarding-Audit',[string]$At='06:00',[string]$User)
$ErrorActionPreference='Stop'
$file=Join-Path $ScriptDirectory 'Audit-ExchangeForwarding.ps1'
if(!(Test-Path $file)){throw "Missing: $file"}
if(!$User){$User=[Security.Principal.WindowsIdentity]::GetCurrent().Name}
$time=[datetime]::ParseExact($At,'HH:mm',[Globalization.CultureInfo]::InvariantCulture)
$exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$action=New-ScheduledTaskAction -Execute $exe -Argument ('-NoProfile -NonInteractive -File "{0}"' -f $file) -WorkingDirectory $ScriptDirectory
$trigger=New-ScheduledTaskTrigger -Daily -At $time
$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 3)
$cred=Get-Credential -UserName $User -Message 'Enter scheduled task service-account credentials'
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -User $cred.UserName -Password $cred.GetNetworkCredential().Password -Force | Out-Null
Write-Host "Task registered: $TaskName ($At)"
