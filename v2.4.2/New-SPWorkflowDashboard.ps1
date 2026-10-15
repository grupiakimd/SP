#requires -Version 5.1
<#
.SYNOPSIS
  Creates a fully offline HTML dashboard from an EXISTING v2.4.1 site workflow audit.
.DESCRIPTION
  READ-ONLY. Does not connect to SharePoint, SQL or the Internet.
  The HTML includes real workflow/list names; keep it PRIVATE on the admin machine.
.EXAMPLE
  .\New-SPWorkflowDashboard.ps1 -InputPath 'C:\SP_Workflow_Diagnostic'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [string]$OutputPath
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$item=Get-Item -LiteralPath $InputPath -ErrorAction Stop
if($item.PSIsContainer){
    $files=@(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Filter 'WorkflowSite_PRIVATE.json' |
        Sort-Object LastWriteTime -Descending)
    if($files.Count -eq 0){throw 'Brak WorkflowSite_PRIVATE.json. Wskaz folder z audytem v2.4.1.'}
    $source=$files[0].FullName
}else{
    if($item.Name -ne 'WorkflowSite_PRIVATE.json'){throw 'Wskaz WorkflowSite_PRIVATE.json lub katalog zawierajacy ten plik.'}
    $source=$item.FullName
}
$d=Get-Content -LiteralPath $source -Encoding UTF8 -Raw | ConvertFrom-Json -ErrorAction Stop
if(-not $d.PSObject.Properties['Workflow2013'] -or -not $d.PSObject.Properties['Lists']){
    throw 'Nieobslugiwany format JSON (wymagany raport site v2.4.1).'
}
if(-not $OutputPath){$OutputPath=Join-Path (Split-Path -Parent $source) 'WorkflowSite_Dashboard.html'}
if([IO.Path]::GetExtension($OutputPath) -ine '.html'){throw 'OutputPath musi byc plikiem .html.'}
$destDir=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
if(-not(Test-Path -LiteralPath $destDir -PathType Container)){
    New-Item -ItemType Directory -Path $destDir -Force|Out-Null
}
function E($value){
    if($null -eq $value){return '—'}
    return [System.Net.WebUtility]::HtmlEncode([string]$value)
}
function A($value){return @($value|Where-Object {$null -ne $_})}
function N($value){return @($value|Where-Object {$null -ne $_}).Count}
function Flag($value){
    if($null -eq $value){return '<span class="muted">Brak danych</span>'}
    if($value -eq $true){return '<span class="yes">Tak</span>'}
    return '<span class="muted">Nie</span>'
}
$lists=@($d.Lists|Where-Object {$null -ne $_})
$site=@($d.SiteLegacy|Where-Object {$null -ne $_})
$types=@($d.ContentTypeLegacy|Where-Object {$null -ne $_})
$wf13=@($d.Workflow2013|Where-Object {$null -ne $_})
$all2010=@($site)+@($types)+@(foreach($l in $lists){foreach($a in @($l.Legacy|Where-Object {$null -ne $_})){$a}})
$enabled2010=@($all2010|Where-Object {$_.Enabled -eq $true})
$enabled13=@($wf13|Where-Object {$_.Enabled -eq $true})
$autoCreate=@($enabled2010|Where-Object {$_.AutoStartCreate -eq $true})
$autoChange=@($enabled2010|Where-Object {$_.AutoStartChange -eq $true})
$errors=@($d.Errors|Where-Object {$null -ne $_})
$known2013=([string]$d.Workflow2013Status -eq 'OK')
$legacyOK=([string]$d.LegacyStatus -eq 'OK')
$complete=($known2013 -and $legacyOK -and $errors.Count -eq 0 -and -not [bool]$d.ListTruncated)

$html=New-Object 'System.Collections.Generic.List[string]'
function Add([string]$line){[void]$script:html.Add($line)}
Add @'
<!doctype html>
<html lang="pl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'none'; connect-src 'none'">
<title>SharePoint Workflow — audyt witryny</title>
<style>
:root{--bg:#f4f7fb;--paper:#fff;--ink:#18293f;--muted:#64748b;--line:#dae4ee;--blue:#1769aa;--nav:#14283f;--amber:#9a5800}
*{box-sizing:border-box}body{margin:0;font:14px/1.55 system-ui,'Segoe UI',Arial,sans-serif;background:var(--bg);color:var(--ink)}
header{background:var(--nav);color:white;padding:30px max(calc((100vw - 1180px)/2),24px)}
header p{color:#d2e2ee;margin:7px 0 0}h1{font-size:27px;line-height:1.2;margin:0}h2{font-size:19px;margin:0 0 14px}
main{max-width:1180px;margin:auto;padding:22px 16px 50px}.sub{font-size:12px;color:var(--muted)}
.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin-bottom:19px}
.card,.panel{background:var(--paper);border:1px solid var(--line);border-radius:12px}
.card{padding:19px}.card strong{display:block;font-size:29px;line-height:1.15;margin:7px 0;color:var(--ink)}
.card .label{color:var(--muted);font-size:12px;font-weight:600}
.panel{margin:16px 0;padding:22px}.notice{padding:13px 16px;border-left:4px solid var(--blue);background:#edf5fc;border-radius:6px;margin:12px 0 18px}
.warn{border-color:#e4a236;background:#fff6e6}.meta{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
.meta div{padding:10px 0;border-bottom:1px solid var(--line)}
.meta b{display:block;color:var(--muted);font-size:12px;font-weight:500}
table{border-collapse:collapse;width:100%;font-size:12.5px}th,td{text-align:left;padding:10px;border-bottom:1px solid #e6edf4;vertical-align:top}
th{background:#eef3f9;color:#475569;position:sticky;top:0}
tr:hover td{background:#f7faff}.scroll{overflow:auto;max-height:580px}
.yes{color:#0a7251;font-weight:600}.muted{color:#8090a2}.tag{display:inline-block;background:#edf3fc;border-radius:5px;padding:2px 7px;font-size:11px}
.controls{display:flex;gap:12px;margin:0 0 14px;align-items:center;flex-wrap:wrap}
input[type=search]{border:1px solid #bdcad9;border-radius:7px;padding:10px 12px;min-width:270px;max-width:100%}
footer{color:var(--muted);font-size:12px;padding:16px 0}
@media(max-width:800px){.grid{grid-template-columns:repeat(2,1fr)}.meta{grid-template-columns:1fr}}
@media(max-width:480px){.grid{grid-template-columns:1fr}}
</style></head><body>
'@
Add ('<header><h1>SharePoint · audyt Workflow</h1><p>Inwentaryzacja jednej witryny przed migracją SharePoint 2019 → SE</p><p class="sub" style="color:#c4d8e8">Witryna: '+(E $d.WebUrl)+' &nbsp; · &nbsp; audyt: '+(E $d.Date)+'</p></header>')
Add '<main>'
Add '<div class="grid">'
Add ('<div class="card"><div class="label">Workflow 2010 · powiązania</div><strong>'+ $all2010.Count+'</strong><span class="sub">Włączone: '+$enabled2010.Count+'</span></div>')
Add ('<div class="card"><div class="label">Workflow 2013 · subskrypcje</div><strong>'+ $(if($known2013){$wf13.Count}else{'?'}) +'</strong><span class="sub">Status odczytu: '+(E $d.Workflow2013Status)+'</span></div>')
Add ('<div class="card"><div class="label">Automatyczny start 2010</div><strong>'+ $autoCreate.Count +'</strong><span class="sub">Po utworzeniu; po zmianie: '+$autoChange.Count+'</span></div>')
Add ('<div class="card"><div class="label">Listy · odczytane</div><strong>'+ $d.ListScanned +'</strong><span class="sub">Łącznie: '+$d.ListTotal+'</span></div>')
Add '</div>'
if($complete){
    Add '<div class="notice">Odczyt objętych sekcji zakończony bez zgłoszonych błędów. To nie potwierdza, że workflow są uruchamiane ani że działają poprawnie.</div>'
}else{
    Add ('<div class="notice warn"><b>Audyt częściowy / wymagający weryfikacji.</b> Workflow 2010: '+(E $d.LegacyStatus)+
         '; workflow 2013: '+(E $d.Workflow2013Status)+'; błędy kolektora: '+$errors.Count+
         '; limit list osiągnięty: '+(E $d.ListTruncated)+'. Brak odczytu nie oznacza braku workflow.</div>')
}
Add '<section class="panel"><h2>Konsekwencje migracji</h2>'
Add ('<div class="notice warn"><b>Workflow 2010: '+$all2010.Count+' wykrytych powiązań.</b> Potrzebny przegląd i plan zastąpienia procesów, które są nadal używane. Sama flaga Enabled nie potwierdza rzeczywistego działania.</div>')
Add ('<div class="notice"><b>Workflow 2013: '+$(if($known2013){[string]$wf13.Count}else{'liczba niepotwierdzona'})+'.</b> Ewentualna migracja wymaga przygotowania odpowiedniego Workflow Managera, zgodności procesów i testów funkcjonalnych.</div>')
Add '<p class="sub">To inwentaryzacja konfiguracji, a nie diagnostyka niedziałających maili ani raport o ostatnich wykonaniach.</p></section>'
Add '<section class="panel"><h2>Stan zbierania danych</h2><div class="meta">'
foreach($a in @(
    @('Workflow 2010', $d.LegacyStatus),
    @('Workflow 2013', $d.Workflow2013Status),
    @('Powiązania na poziomie witryny', $site.Count),
    @('Powiązania typów zawartości', $types.Count),
    @('Subskrypcje 2013 bez przypisania', $d.Unmatched2013Count),
    @('Wykryte błędy odczytu', $errors.Count),
    @('Timer Service na serwerze', $d.TimerService),
    @('WFM proxy', $d.WorkflowManager.Available),
    @('SMTP skonfigurowany', $d.SMTP.ServerConfigured)
)){
    Add ('<div><b>'+ (E $a[0])+'</b>'+ (E $a[1])+'</div>')
}
Add '</div></section>'

Add '<section class="panel"><h2>Listy i biblioteki z workflow</h2>'
Add '<div class="controls"><input id="filter" type="search" placeholder="Szukaj nazwy listy..."><label><input id="only" type="checkbox" checked> Tylko listy z workflow</label><span class="sub" id="count"></span></div>'
Add '<div class="scroll"><table><thead><tr><th>Lista / biblioteka</th><th>2010</th><th>Włączone 2010</th><th>Start: utworzenie</th><th>2013</th><th>Włączone 2013</th></tr></thead><tbody id="listrows">'
foreach($l in $lists){
    $legacy=@($l.Legacy|Where-Object {$null -ne $_})
    $current=@($l.Workflow2013|Where-Object {$null -ne $_})
    $active=@($legacy|Where-Object {$_.Enabled -eq $true})
    $lc=@($active|Where-Object {$_.AutoStartCreate -eq $true}).Count
    $c13=@($current|Where-Object {$_.Enabled -eq $true}).Count
    $has=if($legacy.Count+$current.Count -gt 0){'1'}else{'0'}
    Add ('<tr data-has="'+$has+'"><td><b>'+ (E $l.Title)+'</b>'+$(if($l.Hidden){' <span class="tag">Ukryta</span>'}else{''})+
      '</td><td>'+ $legacy.Count+'</td><td>'+ $active.Count+'</td><td>'+ $lc+'</td><td>'+ $current.Count+'</td><td>'+ $c13+'</td></tr>')
}
Add '</tbody></table></div><p class="sub">Lista może mieć więcej niż jedno powiązanie workflow. 2013 bez przypisania do listy nie jest sztucznie przypisywany do żadnej pozycji.</p></section>'

Add '<section class="panel"><h2>Workflow na poziomie witryny i typów zawartości (2010)</h2>'
Add '<div class="scroll"><table><thead><tr><th>Zakres</th><th>Nazwa</th><th>Włączony</th><th>Start przy utworzeniu</th><th>Start przy zmianie</th></tr></thead><tbody>'
foreach($w in $site){
    Add ('<tr><td>Witryna</td><td>'+ (E $w.Name)+'</td><td>'+ (Flag $w.Enabled)+'</td><td>'+ (Flag $w.AutoStartCreate)+'</td><td>'+ (Flag $w.AutoStartChange)+'</td></tr>')
}
foreach($w in $types){
    Add ('<tr><td>Typ zawartości</td><td>'+ (E $w.Name)+'</td><td>'+ (Flag $w.Enabled)+'</td><td>'+ (Flag $w.AutoStartCreate)+'</td><td>'+ (Flag $w.AutoStartChange)+'</td></tr>')
}
if($site.Count+$types.Count -eq 0){Add '<tr><td colspan="5">Brak wykrytych powiązań lub odczyt niekompletny — patrz status audytu.</td></tr>'}
Add '</tbody></table></div></section>'
Add '<section class="panel"><h2>Subskrypcje workflow 2013</h2>'
Add '<div class="scroll"><table><thead><tr><th>Nazwa</th><th>Zakres</th><th>Włączony</th><th>Zdarzenia</th></tr></thead><tbody>'
foreach($w in $wf13){
    Add ('<tr><td>'+ (E $w.Name)+'</td><td>'+ (E $w.Scope)+'</td><td>'+ (Flag $w.Enabled)+'</td><td>'+ (E (($w.EventTypes | Where-Object {$null -ne $_}) -join ', '))+'</td></tr>')
}
if($wf13.Count -eq 0){Add '<tr><td colspan="4">Brak wyników — sprawdź status odczytu Workflow 2013 powyżej.</td></tr>'}
Add '</tbody></table></div></section>'

Add '<section class="panel"><h2>Ograniczenia i bezpieczeństwo</h2><p>Raport zawiera rzeczywiste nazwy list i workflow. <b>Nie wysyłaj tego HTML do publicznych repozytoriów ani do zewnętrznych odbiorców.</b> Do analizy zdalnej służy osobny pseudonimizowany <code>WorkflowSite_SHAREABLE.md</code>.</p>'
Add '<p>Skrypt nie skanuje podwitryn, historii wszystkich instancji ani skuteczności powiadomień. Nie łączy się z internetem i nie modyfikuje SharePoint.</p></section>'
Add '<footer>Wygenerowano lokalnie z WorkflowSite_PRIVATE.json · dashboard offline · bez zewnętrznych bibliotek</footer></main>'
Add @'
<script>
(function(){
  var input=document.getElementById('filter');
  var only=document.getElementById('only');
  var rows=Array.prototype.slice.call(document.querySelectorAll('#listrows tr'));
  var counter=document.getElementById('count');
  function filterRows(){
    var q=input.value.toLocaleLowerCase('pl');
    var show=0;
    rows.forEach(function(r){
      var ok=(!only.checked||r.getAttribute('data-has')==='1')&&
          r.textContent.toLocaleLowerCase('pl').indexOf(q)>=0;
      r.style.display=ok?'':'none';
      if(ok)show++;
    });
    counter.textContent='Widoczne: '+show+' / '+rows.length;
  }
  input.addEventListener('input',filterRows);
  only.addEventListener('change',filterRows);
  filterRows();
})();
</script></body></html>
'@

$output=$html -join [Environment]::NewLine
$temp=Join-Path $destDir ('SPSE_workflow_'+[guid]::NewGuid().ToString('N')+'.tmp')
try{
    [IO.File]::WriteAllText($temp,$output,(New-Object System.Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $temp -Destination $OutputPath -Force -ErrorAction Stop
}finally{
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}
}
Write-Host ('DASHBOARD HTML: '+([IO.Path]::GetFullPath($OutputPath))) -ForegroundColor Green
Write-Warning 'PRIVATE REPORT: zawiera rzeczywiste nazwy workflow i list. Pozostaw lokalnie.'
