#requires -Version 5.1
<#
.SYNOPSIS
  One-time unattended SharePoint 2019 -> SE full audit runner.
.DESCRIPTION
  Must run on an existing SharePoint 2019 APP/WFE under an account with farm/SQL
  and remote inventory permissions. No network downloads or automatic uploads.
  Keeps confidential raw logs/results local. Read-only against the farm.
.EXITCODES
  0 = outputs present, no collector errors recorded
  2 = outputs present, but collector reported incomplete sections/errors
  1 = fatal error, missing outputs or lock conflict
#>
[CmdletBinding()]
param(
    [string]$OutputRoot = 'C:\temp\sprawdzenie\SP_Audit',
    [ValidateRange(1,1000000)][int]$MaxWebs = 5000,
    [switch]$SkipRemoteWinRM
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$projectDir = Split-Path -Parent $PSScriptRoot
$auditScript = Join-Path $projectDir 'Invoke-SP2019ReadinessAudit.ps1'
$needed = @(
    'Invoke-SP2019ReadinessAudit.ps1',
    'New-SPSEDashboard.ps1',
    'New-SPSEShareableAudit.ps1',
    'dashboard_template.html'
)
foreach ($name in $needed) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectDir $name) -PathType Leaf)) {
        throw ("Brak pliku {0} w katalogu {1}. Skopiuj wszystkie 4 pliki v2.2.1." -f $name,$projectDir)
    }
}
if (-not [Environment]::Is64BitProcess) {
    throw 'Wymagany jest 64-bit Windows PowerShell 5.1.'
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).ProviderPath
$logDir = Join-Path $OutputRoot '_logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$started = Get-Date
$log = Join-Path $logDir ("NightAudit_{0}.log" -f $started.ToString('yyyyMMdd_HHmmss'))
$lockPath = Join-Path $OutputRoot '.spse-audit-running.lock'

$exitCode = 1
$transcribing = $false
$lock = $null
try {
    # Prevent a second, possibly manual, run in the same OutputRoot.
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate,
                            [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

    Start-Transcript -LiteralPath $log -Force -ErrorAction Stop | Out-Null
    $transcribing = $true
    Write-Host ('AUDIT START: ' + $started.ToString('s'))
    Write-Host ('RUN AS: ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
    Write-Host ("MaxWebs={0}, RemoteWinRM={1}, OutputRoot={2}" -f
                $MaxWebs, (-not [bool]$SkipRemoteWinRM), $OutputRoot)

    $invokeArgs = @{
        OutputRoot = $OutputRoot
        DeepWebScan = $true
        MaxWebs = $MaxWebs
        RemoteWinRM = (-not [bool]$SkipRemoteWinRM)
        ShareableReport = $true
    }
    & $auditScript @invokeArgs

    $run = Get-ChildItem -LiteralPath $OutputRoot -Directory -Filter 'SP2019_Audit_*' |
        Where-Object { $_.Name -like ("SP2019_Audit_{0}_*" -f $env:COMPUTERNAME) -and
                       $_.CreationTime -ge $started.AddMinutes(-1) } |
        Sort-Object CreationTime -Descending |
        Select-Object -First 1
    if ($null -eq $run) { throw 'Audyt nie utworzyl nowego katalogu przebiegu.' }

    $statusPath = Join-Path $run.FullName 'AuditStatus.txt'
    $htmlPath = Join-Path $run.FullName 'SPSE_Readiness_Report.html'
    if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) {
        throw 'Brak AuditStatus.txt. Sprawdz dziennik uruchomienia.'
    }
    $status = Get-Content -LiteralPath $statusPath -Encoding UTF8 -Raw
    $reportExists = Test-Path -LiteralPath $htmlPath -PathType Leaf
    $mdExists = ($status -match 'ShareableMarkdown:\s*OK')
    $jsonExists = Test-Path -LiteralPath (Join-Path $run.FullName 'FullInventory.json') -PathType Leaf

    $errorCount = -1
    $m = [regex]::Match($status, 'CollectionErrors:\s*(\d+)')
    if ($m.Success) { $errorCount = [int]$m.Groups[1].Value }
    Write-Host ("OUTPUT: {0}" -f $run.FullName)
    Write-Host ("HTML={0} JSON={1} MD={2} CollectionErrors={3}" -f
                $reportExists, $jsonExists, $mdExists, $errorCount)

    if (-not $reportExists -or -not $mdExists) {
        throw 'Brak HTML lub MD: wyniku nie mozna uznac za kompletny.'
    }
    if ($errorCount -ne 0 -or -not $jsonExists) {
        Write-Warning 'PARTIAL: nie wszystkie sekcje zebrano. Sprawdz CollectionErrors.csv oraz AuditStatus.txt.'
        $exitCode = 2
    } else {
        $exitCode = 0
        Write-Host 'SUCCESS: raporty utworzone bez zgloszonych bledow kolektora.' -ForegroundColor Green
    }
} catch {
    $exitCode = 1
    Write-Error -Message ('FATAL: ' + $_.Exception.Message) -ErrorAction Continue
} finally {
    Write-Host ("AUDIT END: {0}; exit code: {1}; log: {2}" -f
                (Get-Date).ToString('s'), $exitCode, $log)
    if ($transcribing) {
        try { Stop-Transcript | Out-Null } catch {}
    }
    if ($null -ne $lock) {
        $lock.Dispose()
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
}
exit $exitCode
