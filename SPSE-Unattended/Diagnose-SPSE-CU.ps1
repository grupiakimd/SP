#requires -Version 5.1
<#
 Read-only diagnostics of SharePoint SE CU. Reads local MSI/MSP logs and MSI events,
 checks installed DLL version, writes a LOCAL HTML report. No patch launch, no restart,
 no SQL, no farm or AD actions, no remote calls, no uploads.
#>
[CmdletBinding()]
param([int]$Days = 5)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$allow = @('SPSEAPP2','SPSEWFE1','SPSEWFE2','SPSEAPP1')
$machine = [string]$env:COMPUTERNAME
if ($machine -notin $allow -or (Get-CimInstance Win32_ComputerSystem).Name -ine $machine) {
    throw "Zatrzymano: nieoczekiwany komputer $machine. Brak zmian."
}
if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess) {
    throw 'Wymagany 64-bitowy Windows PowerShell 5.1.'
}
if ($Days -lt 1 -or $Days -gt 14) { throw 'Days musi byc z zakresu 1..14.' }
$since = (Get-Date).AddDays(-$Days)
$reportDirectory = Join-Path $env:ProgramData "SPSE-Unattended\$machine"
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$report = Join-Path $reportDirectory 'Diagnostyka-CU.html'
function Html([object]$s) { return [System.Net.WebUtility]::HtmlEncode([string]$s) }
function Add-Row([string]$a,[object]$b) { return '<tr><th>'+(Html $a)+'</th><td>'+(Html $b)+'</td></tr>' }

$dll = Join-Path $env:CommonProgramFiles 'microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.dll'
$dllVersion='BRAK'; $dllModified='BRAK'
if (Test-Path -LiteralPath $dll -PathType Leaf) {
    $f=Get-Item -LiteralPath $dll
    $dllVersion=$f.VersionInfo.FileVersion
    $dllModified=$f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
}
$target = '16.0.20326.20190'
$reboot = $false
foreach($p in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
  if (Test-Path -LiteralPath $p) { $reboot=$true }
}
$pending = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
if ($null -ne $pending) {
    $prop=$pending.PSObject.Properties['PendingFileRenameOperations']
    if ($null -ne $prop -and $null -ne $prop.Value -and @($prop.Value).Count -gt 0) { $reboot=$true }
}

$rootDirs = @($env:TEMP, $env:TMP, (Join-Path $env:WINDIR 'Temp'))
foreach($p in @($env:TEMP,$env:TMP)) {
    if ($p -match '\\[0-9]+$') { $rootDirs += (Split-Path -Path $p -Parent) }
}
$rootDirs=@($rootDirs | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Sort-Object -Unique)
# Do not scan the whole C: volume; only per-user/system temp locations.
$logFiles = @()
foreach($r in $rootDirs) {
    $matches = @(Get-ChildItem -LiteralPath $r -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $since -and $_.Name -match '(?i)(MSPLOG|opatch|sharepoint|5002927|sts-x-none|wssmui)' -and $_.Extension -match '(?i)\.(log|txt)$' })
    $logFiles += $matches
}
$logFiles = @($logFiles | Sort-Object FullName -Unique | Sort-Object LastWriteTime -Descending | Select-Object -First 18)

$patterns = '(?i)(return value 3|mainenginethread is returning|error\s+(?:[1-9][0-9]{2,4}|0x[0-9a-f]+)|0x800[0-9a-f]{5}|failed|failure|access is denied|odmowa dostepu|hr=80070005|rollback|error code)'
$logRows = @()
foreach($file in $logFiles) {
    $all=@()
    try { $all=@(Get-Content -LiteralPath $file.FullName -Tail 3500 -ErrorAction Stop) } catch { $all=@("Nie mozna odczytac: $($_.Exception.Message)") }
    $hits=@()
    for($i=0;$i -lt $all.Count;$i++) {
        if ($all[$i] -match $patterns) {
            $start=[Math]::Max(0,$i-1)
            $end=[Math]::Min($all.Count-1,$i+1)
            $hits += "[linia fragmentu $($i+1)] " + (($all[$start..$end] -join "`n").Trim())
        }
        if ($hits.Count -ge 24) { break }
    }
    $excerpt = if ($hits.Count) { $hits -join "`n---`n" } else { '(Nie znaleziono fraz bledow w ostatnich 3500 liniach)' }
    $logRows += '<tr><td>'+(Html $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))+'</td><td>'+(Html $file.FullName)+'</td><td><pre>'+(Html $excerpt)+'</pre></td></tr>'
}
if (-not $logRows.Count) { $logRows=@('<tr><td colspan="3">Brak logow z ostatnich '+(Html $Days)+' dni w przeszukanych katalogach TEMP. Mozliwe sa logi pod innym profilem uzytkownika.</td></tr>') }

$events=@()
try {
    $events=@(Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='MsiInstaller';StartTime=$since} -ErrorAction Stop |
        Sort-Object TimeCreated -Descending | Select-Object -First 35)
} catch { $events=@() }
$eventRows=@()
foreach($evt in $events) {
  $m=[string]$evt.Message
  if ($m.Length -gt 1800) { $m=$m.Substring(0,1800)+' ...' }
  $eventRows += '<tr><td>'+(Html $evt.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))+'</td><td>'+(Html $evt.Id)+'</td><td><pre>'+(Html $m)+'</pre></td></tr>'
}
if (-not $eventRows.Count) { $eventRows=@('<tr><td colspan="3">Brak zdarzen MsiInstaller w podanym okresie.</td></tr>') }

$progressPath = Join-Path $reportDirectory 'progress.json'
$progressNote='BRAK'
if (Test-Path -LiteralPath $progressPath) {
    try {
        $progress=Get-Content -LiteralPath $progressPath -Raw | ConvertFrom-Json
        $progressNote='Zakonczone: '+(@($progress.Completed) -join ', ')+'; ostatni blad: '+[string]$progress.LastError
    } catch { $progressNote='Nie mozna odczytac progress.json' }
}
$summary = @(
    (Add-Row 'Serwer (lokalnie)' $machine),
    (Add-Row 'Godzina audytu' (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
    (Add-Row 'Zadana aktualizacja' "KB5002927 / build $target"),
    (Add-Row 'Wersja pliku Microsoft.SharePoint.dll' $dllVersion),
    (Add-Row 'Data pliku DLL' $dllModified),
    (Add-Row 'Oczekujacy restart (wybrane wskazniki)' $reboot),
    (Add-Row 'Stan skryptu' $progressNote),
    (Add-Row 'Przeszukane lokalne TEMP' ($rootDirs -join ' | ')),
    (Add-Row 'Znalezione logi' $logFiles.Count)
) -join "`n"
$html=@"
<!doctype html><html lang="pl"><head><meta charset="utf-8"><title>SPSE — diagnostyka KB5002927</title>
<style>body{font:14px Segoe UI,Arial,sans-serif;margin:2rem auto;max-width:1300px;color:#193042;background:#f1f5f8}
main{padding:2rem;background:#fff;border:1px solid #d4dce6;border-radius:12px} h1,h2{color:#18364a}
table{border-collapse:collapse;width:100%;margin-bottom:2rem;table-layout:fixed} th,td{padding:9px;border:1px solid #dce3eb;text-align:left;vertical-align:top;overflow-wrap:anywhere}
th{background:#e8eff5}pre{white-space:pre-wrap;max-height:380px;overflow:auto;font-size:12px}
small{color:#566779}</style></head><body><main>
<h1>Diagnostyka aktualizacji KB5002927 — $(Html $machine)</h1>
<p>Raport lokalny, tylko odczyt systemu i zapis tego pliku HTML. <b>Nie uruchamiano instalatorow ani PSConfig.</b></p>
<h2>Stan</h2><table>$summary</table>
<p><b>Uwaga:</b> wersja jednego pliku DLL jest informacja pomocnicza. Sama nie potwierdza instalacji wszystkich pakietow CU.</p>
<h2>Logi instalatora MSI / MSP</h2><table><thead><tr><th style="width:13%">Czas</th><th style="width:32%">Plik</th><th>Wykryte fragmenty</th></tr></thead><tbody>$($logRows -join "`n")</tbody></table>
<h2>Dziennik Application / MsiInstaller</h2><table><thead><tr><th style="width:15%">Czas</th><th style="width:7%">Event ID</th><th>Zdarzenie</th></tr></thead><tbody>$($eventRows -join "`n")</tbody></table>
<small>Nie publikuj tego raportu w publicznym repozytorium — moze zawierac nazwy serwerow i sciezki.</small>
</main></body></html>
"@
[IO.File]::WriteAllText($report,$html,[Text.UTF8Encoding]::new($false))
Write-Host "Serwer: $machine" -ForegroundColor Cyan
Write-Host "SharePoint DLL: $dllVersion; oczekiwany build CU: $target" -ForegroundColor Cyan
Write-Host "Znaleziono logow: $($logFiles.Count), zdarzen MSI: $($events.Count)" -ForegroundColor Cyan
Write-Host "Raport HTML: $report" -ForegroundColor Green
Write-Warning 'Nie ponawiaj instalacji CU tylko na podstawie kodu -1; sprawdz raport.'
