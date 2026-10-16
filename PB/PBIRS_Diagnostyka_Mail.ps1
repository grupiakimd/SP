#requires -Version 5.1
<#
  Power BI Report Server - diagnostyka subskrypcji e-mail
  TYLKO ODCZYT: nie wysyla poczty, nie restartuje uslug, nie zmienia konfiguracji.
  Raport HTML zawiera nazwe SMTP, adres nadawcy i wycinki logow.
  Sprawdz dane wrazliwe przed przekazaniem raportu.
#>
[CmdletBinding()]
param(
    [string]$PBIRSRoot = 'C:\Program Files\Microsoft Power BI Report Server\PBIRS',
    [ValidateRange(1,14)][int]$DaysBack = 2
)

$ErrorActionPreference = 'Stop'
$started = Get-Date
$since = $started.AddDays(-$DaysBack)
$logDir = Join-Path $PBIRSRoot 'LogFiles'
$configPath = Join-Path $PBIRSRoot 'ReportServer\RSReportServer.config'
$output = Join-Path ([Environment]::GetFolderPath('Desktop')) ("PBIRS_Poczta_Diagnoza_{0}.html" -f $started.ToString('yyyyMMdd_HHmmss'))
if (-not (Test-Path -LiteralPath (Split-Path $output -Parent))) {
    $output = Join-Path $env:TEMP ("PBIRS_Poczta_Diagnoza_{0}.html" -f $started.ToString('yyyyMMdd_HHmmss'))
}

function Html([object]$Value) {
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}
function ConfigValue([System.Xml.XmlNode]$Node, [string]$Name) {
    if ($null -eq $Node) { return '(nie znaleziono sekcji poczty)' }
    $found = $Node.SelectSingleNode($Name)
    if ($null -eq $found -or [string]::IsNullOrWhiteSpace($found.InnerText)) { return '(puste)' }
    return $found.InnerText.Trim()
}
function TcpProbe([string]$HostName, [int]$Port, [int]$TimeoutMs = 4500) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return 'TIMEOUT - polaczenie TCP nie zostalo nawiazane w 4,5 s'
        }
        $client.EndConnect($ar)
        return 'OK - port TCP osiagalny (nie potwierdza TLS, AUTH ani wyslania maila)'
    }
    catch { return 'BLAD - ' + $_.Exception.GetBaseException().Message }
    finally { $client.Dispose() }
}

$configState = 'NIE SPRAWDZONO'
$settings = [ordered]@{
    'SMTPServer' = '(brak danych)'
    'SMTPServerPort' = '(brak danych)'
    'SMTPUseSSL' = '(brak danych)'
    'SMTPAuthenticate' = '(brak danych)'
    'SendUsing' = '(brak danych)'
    'From' = '(brak danych)'
    'SendUserName' = '(ukryte celowo)'
    'SendPassword' = '(ukryte celowo)'
}
if (Test-Path -LiteralPath $configPath) {
    try {
        [xml]$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        $mailNode = $config.SelectSingleNode("//Delivery/Extension[@Name='Report Server Email']/Configuration/RSEmailDPConfiguration")
        if ($null -ne $mailNode) {
            foreach ($key in @('SMTPServer','SMTPServerPort','SMTPUseSSL','SMTPAuthenticate','SendUsing','From')) {
                $settings[$key] = ConfigValue $mailNode $key
            }
            $configState = 'ODCZYTANO ustawienia poczty'
        } else { $configState = 'PLIK JEST, ale nie znaleziono sekcji Report Server Email' }
    }
    catch { $configState = 'BLAD ODCZYTU: ' + $_.Exception.Message }
} else { $configState = 'NIE ZNALEZIONO RSReportServer.config' }

$server = [string]$settings['SMTPServer']
$rawPort = [string]$settings['SMTPServerPort']
$port = 25
if ($rawPort -match '^\d{1,5}$') { $port = [int]$rawPort }
$tcpState = 'NIE WYKONANO - brak poprawnego serwera SMTP w konfiguracji'
if ($settings['SendUsing'] -eq '1') {
    $tcpState = 'POMINIETO - konfiguracja SendUsing=1 (lokalny katalog Pickup)'
} elseif ($server -and $server -notmatch '^\(' -and $port -ge 1 -and $port -le 65535) {
    $tcpState = TcpProbe -HostName $server -Port $port
}

$matchingFiles = @()
$logErrors = @()
$logState = ''
if (Test-Path -LiteralPath $logDir) {
    try {
        $matchingFiles = @(Get-ChildItem -LiteralPath $logDir -File -ErrorAction Stop |
            Where-Object { $_.Name -match '^(ReportingServicesService|ReportServerService|RSPowerBI)_' -and $_.Extension -match '^\.(txt|log)$' -and $_.LastWriteTime -ge $since.AddHours(-12) } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 12)
        $pattern = '(?i)Failure sending mail|Mail will not be resent|System\.Net\.Mail|SMTP|email|e-mail|subscription|delivery|InnerException|AggregateException|exception|\bERROR\b|certificate|\bTLS\b|authentication failed'
        foreach ($file in $matchingFiles) {
            try {
                $hits = @(Select-String -LiteralPath $file.FullName -Pattern $pattern -Context 2,10 -Encoding UTF8 -ErrorAction Stop | Select-Object -Last 30)
                foreach ($hit in $hits) {
                    $fragment = (@($hit.Context.PreContext) + @($hit.Line) + @($hit.Context.PostContext)) -join "`r`n"
                    $logErrors += [pscustomobject]@{ File=$file.Name; Line=$hit.LineNumber; Match=$hit.Line; Fragment=$fragment }
                }
            }
            catch { $logErrors += [pscustomobject]@{ File=$file.Name; Line='-'; Match='BLAD ODCZYTU LOGU'; Fragment=$_.Exception.Message } }
        }
        $logState = "Przeszukano $($matchingFiles.Count) plikow, znaleziono $($logErrors.Count) fragmentow (limit 30 na plik)."
    }
    catch { $logState = 'BLAD ODCZYTU katalogu: ' + $_.Exception.Message }
} else { $logState = 'Nie znaleziono katalogu logow.' }

$events = @()
$eventStatus = ''
try {
    $events = @(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$since} -MaxEvents 600 -ErrorAction Stop |
        Where-Object { $_.ProviderName -match '(?i)Report|PowerBI|PBIRS' -or $_.Message -match '(?i)ReportingServices|ReportServer|Power BI Report Server' } |
        Select-Object -First 25 TimeCreated, ProviderName, Id, LevelDisplayName, Message)
    $eventStatus = "Wybrano $($events.Count) zdarzen zwiazanych z usluga spośród ostatnich 600 zdarzen Application."
}
catch { $eventStatus = 'Nie udalo sie odczytac zdarzen Windows: ' + $_.Exception.Message }

$tags = New-Object 'System.Collections.Generic.List[string]'
$aggregate = (($logErrors | ForEach-Object { $_.Match }) -join "`n")
if ($aggregate -match '(?i)\b(5\.7\.|535\b|530\b|relay denied|authentication failed|logon failed|unauthorized)') { $tags.Add('Mozliwy problem AUTH / relay / Send As') }
if ($aggregate -match '(?i)TLS|SSL|certificate|handshake|secure channel') { $tags.Add('Mozliwy problem TLS / certyfikatu') }
if ($aggregate -match '(?i)timeout|connection refused|socketexception|no such host|unreachable') { $tags.Add('Mozliwy problem sieci / SMTP') }
if ($aggregate -match '(?i)Failure sending mail|Mail will not be resent') { $tags.Add('Znaleziono blad wysylki w logach') }
if ($tags.Count -eq 0) { $tags.Add('Brak rozstrzygajacego wzorca - wymagany przeglad fragmentow logu') }

$settingsRows = foreach ($key in $settings.Keys) {
    "<tr><th>$(Html $key)</th><td>$(Html $settings[$key])</td></tr>"
}
$logCards = foreach ($x in $logErrors) {
    $headline = ([string]$x.Match).Trim()
    if ($headline.Length -gt 260) { $headline = $headline.Substring(0,260) + '…' }
    @"
    <details class="hit"><summary><span class="file">$(Html $x.File):$(Html $x.Line)</span> $(Html $headline)</summary>
    <pre>$(Html $x.Fragment)</pre></details>
"@
}
$eventCards = foreach ($ev in $events) {
    $msg = [string]$ev.Message
    if ($msg.Length -gt 2600) { $msg = $msg.Substring(0,2600) + '…' }
    @"
    <details class="hit"><summary>$(Html ($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))) — $(Html $ev.ProviderName) / ID $(Html $ev.Id) / $(Html $ev.LevelDisplayName)</summary><pre>$(Html $msg)</pre></details>
"@
}
$tagsHtml = ($tags | ForEach-Object { "<span class='tag'>$(Html $_)</span>" }) -join ' '
$fileRows = ($matchingFiles | ForEach-Object { "<tr><td>$(Html $_.Name)</td><td>$(Html $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))</td><td>$([math]::Round($_.Length / 1KB, 0)) KB</td></tr>" }) -join "`n"
if (-not $fileRows) { $fileRows = '<tr><td colspan="3">Brak plikow wedlug ustawionego okresu.</td></tr>' }
if (-not $logCards) { $logCards = '<p>Brak dopasowan. Mozesz podac szerszy przedzial, np. -DaysBack 5.</p>' }
if (-not $eventCards) { $eventCards = '<p>Brak pasujacych zdarzen.</p>' }
$style = @'
<style>
:root {color-scheme:light;--navy:#172b4d;--blue:#3458a4;--line:#e2e8f0;--bg:#f5f7fb;--gray:#64748b}
* {box-sizing:border-box} body{margin:0;background:var(--bg);font:15px/1.5 'Segoe UI',Arial,sans-serif;color:#1f2937}
header{background:#172b4d;color:white;padding:28px max(24px,calc((100vw - 1120px)/2)) 24px}
header h1{margin:0;font-size:27px}header p{margin:9px 0 0;color:#d5e2ff}
main{max-width:1120px;margin:24px auto;padding:0 18px 48px} .grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}
.card,section{background:white;border:1px solid var(--line);border-radius:12px;padding:20px;box-shadow:0 2px 7px #182c4911}
.metric{font-size:26px;font-weight:700;color:#172b4d}.muted{color:var(--gray);font-size:13px}.card strong{display:block;line-height:1.3;overflow-wrap:anywhere}
section{margin-top:16px}h2{margin:0 0 12px;font-size:20px;color:#172b4d}p{margin:6px 0 12px}
table{width:100%;border-collapse:collapse}th,td{padding:9px 10px;text-align:left;border-bottom:1px solid var(--line);vertical-align:top;overflow-wrap:anywhere}th{color:#334155;width:31%;font-weight:600}
.tag{display:inline-block;padding:7px 11px;border-radius:20px;margin:3px;background:#eef3ff;color:#27437e;font-size:13px}
.hit{border:1px solid var(--line);border-radius:8px;margin:8px 0;overflow:hidden}.hit summary{cursor:pointer;padding:12px 14px;font-weight:500;overflow-wrap:anywhere}.hit[open] summary{background:#f6f9ff}.file{display:block;color:var(--blue);font-size:12px;font-weight:700}
pre{white-space:pre-wrap;overflow-wrap:anywhere;margin:0;padding:14px;background:#0e182a;color:#e4eeff;font:12px/1.5 Consolas,monospace;max-height:420px;overflow:auto}
input{width:100%;border:1px solid #cbd5e1;border-radius:8px;padding:12px;margin:4px 0 12px;font:inherit} .warning{background:#fff5df;padding:12px 14px;border-radius:9px;border-left:4px solid #d38c17}
code{font-family:Consolas,monospace} .good{color:#146c43}.bad{color:#b42318} @media(max-width:800px){.grid{grid-template-columns:1fr}header{padding:25px}main{margin:14px auto}}
</style>
'@

$html = @"
<!doctype html><html lang="pl"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/><title>PBIRS - Diagnostyka poczty</title>
$style
</head><body>
<header><h1>Power BI Report Server — diagnostyka poczty</h1><p>Tylko odczyt • $(Html $started.ToString('yyyy-MM-dd HH:mm:ss')) • Serwer: $(Html $env:COMPUTERNAME)</p></header>
<main>
<div class="grid">
<div class="card"><div class="muted">Konfiguracja</div><strong>$(Html $configState)</strong><div class="muted">$(Html $configPath)</div></div>
<div class="card"><div class="muted">Połączenie z SMTP</div><strong>$(Html $tcpState)</strong><div class="muted">$(Html $server):$port</div></div>
<div class="card"><div class="muted">Fragmenty logów</div><div class="metric">$($logErrors.Count)</div><div class="muted">Zakres od $(Html $since.ToString('yyyy-MM-dd HH:mm'))</div></div>
</div>
<section><h2>1. Wstępne tropy</h2><div>$tagsHtml</div><p class="muted">Wskazówki rozpoznane po słowach kluczowych, nie diagnoza. TCP OK nie oznacza, ze poczta dziala.</p></section>
<section><h2>2. Konfiguracja SMTP (bez hasła i loginu)</h2><table>$($settingsRows -join "`n")</table><p class="muted">W raporcie nie sa wypisywane SendUserName ani SendPassword.</p></section>
<section><h2>3. Błędy i wyjątki z logów</h2><p>$(Html $logState) Rozwiń wybrany fragment.</p>
<input id="search" placeholder="Filtruj wpisy: SMTP, 535, TLS, certificate, exception..." oninput="filterHits(this.value)" />
<div id="hits">$($logCards -join "`n")</div></section>
<section><h2>4. Dziennik zdarzeń Windows</h2><p>$(Html $eventStatus)</p>$($eventCards -join "`n")</section>
<section><h2>5. Sprawdzone pliki</h2><table><tr><th>Plik</th><th>Ostatnia modyfikacja</th><th>Rozmiar</th></tr>$fileRows</table></section>
<section><h2>Przekazanie wyniku</h2><p class="warning"><b>Uwaga:</b> Fragmenty logów moga zawierac adresy e-mail, sciezki i nazwy serwerow. Przejrzyj dokument przed udostepnieniem. Skrypt nie modyfikowal konfiguracji ani nie wysylal maili.</p></section>
</main>
<script>
function filterHits(q){q=q.toLowerCase();document.querySelectorAll('#hits .hit').forEach(e=>{e.style.display=e.innerText.toLowerCase().includes(q)?'':'none';});}
</script></body></html>
"@
Set-Content -LiteralPath $output -Value $html -Encoding UTF8
Write-Host "Raport: $output" -ForegroundColor Green
Write-Host "Skonczono. Skrypt niczego nie zmienial i nie wysylal maili." -ForegroundColor Cyan
Start-Process -FilePath $output