#requires -Version 5.1
[CmdletBinding()]
param([string]$Path = (Join-Path $PSScriptRoot 'smtp-credential.xml'))
# Run this script under the SAME Windows account that will run the Scheduled Task.
# Windows DPAPI protects the secret for this Windows user on this computer.
$ErrorActionPreference='Stop'
$credential=Get-Credential -Message 'Enter SMTP username and password'
if(!$credential){throw 'Credential setup cancelled'}
$credential | Export-Clixml -LiteralPath $Path
Write-Host "Saved DPAPI-protected SMTP credential file: $Path"
Write-Host 'Grant read access only to the scheduled-task account; do not commit this file.'
