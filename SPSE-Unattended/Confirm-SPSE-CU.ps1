#requires -Version 5.1
<#
  SPSEAPP2 ONLY. Offline, local-only reconciliation of KB5002927 state.
  No installer execution, no reboot, no remoting, no farm/SQL writes.
  Default is read-only. -Apply explicitly confirms before editing progress.json.
#>
[CmdletBinding()]
param([switch]$Apply)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$server = [string]$env:COMPUTERNAME
if ($server -ine 'SPSEAPP2' -or (Get-CimInstance Win32_ComputerSystem).Name -ine 'SPSEAPP2') {
    throw 'BLOKADA: ten skrypt uzgadniania stanu przeznaczony jest TYLKO dla SPSEAPP2.'
}
if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess) {
    throw 'Wymagany Windows PowerShell 5.1 x64.'
}
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Uruchom Windows PowerShell jako lokalny administrator.'
}
$root = Join-Path $env:ProgramData 'SPSE-Unattended\SPSEAPP2'
$statePath = Join-Path $root 'progress.json'
$reportPath = Join-Path $root 'CU-Weryfikacja.html'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "Brak lokalnego stanu: $statePath" }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if ($state.Server -ine 'SPSEAPP2') { throw 'Niezgodna nazwa serwera w progress.json.' }
$completed = @($state.Completed)
$requiredSteps = @('WindowsFeatures','VCRedist','SqlAlias','Prerequisites','InstallCore','InstallPolishLP')
$missingSteps = @($requiredSteps | Where-Object { $_ -notin $completed })
$already = ('InstallCU' -in $completed)
$errorText = [string]$state.LastError
$properFailureState = $already -or $errorText -match '(?i)(kodem|code)\s*-1\b'
$dll = Join-Path $env:CommonProgramFiles 'microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.dll'
$version = if (Test-Path -LiteralPath $dll -PathType Leaf) { (Get-Item -LiteralPath $dll).VersionInfo.FileVersion } else { '' }
$expected = '16.0.20326.20190'
$pending = $false
foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
                   'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
    if (Test-Path -LiteralPath $key) { $pending = $true }
}
$sessionManager=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
if ($null -ne $sessionManager) {
    $p = $sessionManager.PSObject.Properties['PendingFileRenameOperations']
    if ($null -ne $p -and $null -ne $p.Value -and @($p.Value).Length -gt 0) { $pending = $true }
}
$events = @()
try {
    $events = @(Get-WinEvent -FilterHashtable @{
        LogName = 'Application'; ProviderName = 'MsiInstaller'; Id = 1022;
        StartTime = (Get-Date).AddDays(-14)
    } -ErrorAction Stop | Where-Object { $_.Message -match '(?i)KB5002927' })
} catch {
    Write-Warning "Nie udalo sie odczytac zdarzen MSI 1022: $($_.Exception.Message)"
}
$products = @(
    [pscustomobject]@{Name='SharePoint Core';Pattern='(?i)SharePoint Server Subscription Edition Core'},
    [pscustomobject]@{Name='English Language Pack 1033';Pattern='(?i)SharePoint Server Subscription Edition 1033 Language Pack'},
    [pscustomobject]@{Name='Polish Language Pack 1045';Pattern='(?i)SharePoint Server Subscription Edition 1045 Language Pack'}
)
$evidence = foreach ($product in $products) {
    $matches = @($events | Where-Object { $_.Message -match $product.Pattern } | Sort-Object TimeCreated -Descending)
    $found = $matches.Length -gt 0
    [pscustomobject]@{Produkt=$product.Name;MSI_1022_KB5002927=$found;Czas=$(if($found){$matches[0].TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')}else{'BRAK'});EventRecordId=$(if($found){$matches[0].RecordId}else{''})}
}
$msiOk = @($evidence | Where-Object { -not $_.MSI_1022_KB5002927 }).Length -eq 0
$eligible = ($version -eq $expected) -and (-not $pending) -and $msiOk -and ($missingSteps.Length -eq 0) -and $properFailureState

Write-Host "`nSPSEAPP2 | lokalna weryfikacja KB5002927 | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "DLL: $version (oczekiwana $expected)"
Write-Host "Oczekujacy restart: $pending"
Write-Host "Wczesniejsze etapy kompletne: $($missingSteps.Length -eq 0)"
Write-Host "InstallCU w stanie: $already"
Write-Host "Poprzedni blad: $errorText"
$evidence | Format-Table -AutoSize
Write-Host "Kryteria bezpiecznego uzgodnienia: $eligible" -ForegroundColor $(if($eligible){'Green'}else{'Yellow'})

$rows = @(
    [pscustomobject]@{Kontrola='Serwer';Wynik=$server},
    [pscustomobject]@{Kontrola='Wersja DLL';Wynik=$version},
    [pscustomobject]@{Kontrola='Docelowy build';Wynik=$expected},
    [pscustomobject]@{Kontrola='Oczekujacy restart';Wynik=$pending},
    [pscustomobject]@{Kontrola='Brakujace wczesniejsze etapy';Wynik=($missingSteps -join ', ')},
    [pscustomobject]@{Kontrola='Aktualnie oznaczony InstallCU';Wynik=$already},
    [pscustomobject]@{Kontrola='Poprzedni blad';Wynik=$errorText},
    [pscustomobject]@{Kontrola='MSI 1022 dla 3 produktow';Wynik=$msiOk},
    [pscustomobject]@{Kontrola='Wszystkie kryteria spelnione';Wynik=$eligible}
)
$frag = ($rows | ConvertTo-Html -Fragment) + ($evidence | ConvertTo-Html -Fragment)
$html=@"
<!doctype html><html><head><meta charset="utf-8"><style>body{font:15px Segoe UI,Arial;margin:2rem auto;max-width:1100px;color:#19334f;background:#eef3f9}main{background:white;padding:2rem;border-radius:12px}table{border-collapse:collapse;width:100%;margin:1.3rem 0}td,th{border:1px solid #dce4ee;padding:.7rem;text-align:left}th{background:#e8eff9}</style></head><body><main><h1>SharePoint SE: weryfikacja KB5002927</h1><p>SPSEAPP2 | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | bez wykonywania CU, PSConfig i operacji zdalnych</p>$frag</main></body></html>
"@
[IO.File]::WriteAllText($reportPath,$html,[Text.UTF8Encoding]::new($false))
Write-Host "Raport HTML: $reportPath" -ForegroundColor Green

if (-not $Apply) {
    Write-Host 'AUDYT: nie zmieniono progress.json. Aby uzgodnic po weryfikacji, uruchom z -Apply.' -ForegroundColor Yellow
    return
}
if ($already) { Write-Host 'InstallCU juz oznaczony; nie ma czego uzgadniac.' -ForegroundColor Green; return }
if (-not $eligible) { throw 'ZABLOKOWANO: nie wszystkie warunki sa spelnione. Nie zmieniono progress.json.' }
$confirm = Read-Host 'Aby zmienic TYLKO lokalny progress.json, wpisz: POTWIERDZ CU SPSEAPP2'
if ($confirm -cne 'POTWIERDZ CU SPSEAPP2') { throw 'Anulowano bez zmiany stanu.' }
$backup = Join-Path $root ('progress.before-cu-reconciliation-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Copy-Item -LiteralPath $statePath -Destination $backup -ErrorAction Stop
$state.Completed = @($completed) + @('InstallCU')
$state.LastError = ''
$state | Add-Member -MemberType NoteProperty -Name 'CUReconciliation' -Value ([pscustomobject]@{
    When=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss');Method='Microsoft.SharePoint.dll + restart clear + MsiInstaller 1022 Core/1033/1045';
    OriginalExitCode=-1;OriginalLastError=$errorText;EventRecordIds=@($evidence | ForEach-Object EventRecordId)
}) -Force
$tmp="$statePath.new"
$state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp -Encoding UTF8
Move-Item -LiteralPath $tmp -Destination $statePath -Force
Write-Host "UZGODNIONO: InstallCU, bez reinstalacji. Kopia stanu: $backup" -ForegroundColor Green
Write-Host 'Mozesz uruchomic oryginalny instalator z -Resume, zeby wygenerowal raport koncowy.' -ForegroundColor Green
