#requires -Version 5.1
<#
.SYNOPSIS
  Generates a graphical, fully offline SharePoint workflow incident dashboard.
.DESCRIPTION
  Uses an EXISTING WorkflowTroubleshoot_PRIVATE.json. No SharePoint connection.
  All CSS and JavaScript are embedded. Private infrastructure and ULS messages
  remain inside the resulting local HTML. Do NOT publish it.
.EXAMPLE
  .\New-SPWorkflowTroubleshootDashboard.ps1 -InputPath 'C:\SP_Workflow_Troubleshooting'
.EXAMPLE
  .\New-SPWorkflowTroubleshootDashboard.ps1 -InputPath 'C:\SP_Workflow_Troubleshooting\Run_20261016_090000\WorkflowTroubleshoot_PRIVATE.json'
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$InputPath,
  [string]$OutputPath
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$sourceItem = Get-Item -LiteralPath $InputPath -ErrorAction Stop
if($sourceItem.PSIsContainer) {
  $candidates = @(Get-ChildItem -LiteralPath $sourceItem.FullName -Filter 'WorkflowTroubleshoot_PRIVATE.json' -File -Recurse |
    Sort-Object LastWriteTime -Descending)
  if($candidates.Count -lt 1) { throw 'Nie znaleziono WorkflowTroubleshoot_PRIVATE.json w podanym katalogu.' }
  $source = $candidates[0].FullName
} else {
  if($sourceItem.Name -ine 'WorkflowTroubleshoot_PRIVATE.json') {
    throw 'Podaj katalog raportow lub plik WorkflowTroubleshoot_PRIVATE.json.'
  }
  $source = $sourceItem.FullName
}
$data = Get-Content -LiteralPath $source -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
if(-not $data.PSObject.Properties['LegacyAssociations'] -or
   -not $data.PSObject.Properties['WfmSubscriptions'] -or
   -not $data.PSObject.Properties['Items']) {
  throw 'Nieobslugiwany format raportu. Wymagany JSON z Workflow-Troubleshooting/v1.'
}
if([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path (Split-Path -Parent $source) 'WorkflowTroubleshoot_Dashboard.html'
}
if([IO.Path]::GetExtension($OutputPath) -ine '.html') { throw 'OutputPath musi konczyc sie na .html.' }
$fullPath = [IO.Path]::GetFullPath($OutputPath)
$folder = Split-Path -Parent $fullPath
if(-not(Test-Path -LiteralPath $folder -PathType Container)) {
  New-Item -Path $folder -ItemType Directory -Force | Out-Null
}

# Store data in a non-executable JSON script tag, preventing HTML/script injection.
$json = $data | ConvertTo-Json -Depth 25 -Compress
$json = $json.Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e')
$json = $json.Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
$template = @'
<!doctype html>
<html lang="pl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'">
<title>Diagnostyka Workflow | SharePoint 2019</title>
<style>
:root{--nav:#10263b;--ink:#192e43;--muted:#64778c;--line:#dfe7f0;--paper:#fff;--bg:#f3f6fa;--blue:#176dba;--bluebg:#ebf4fe;--green:#0a7962;--greenbg:#e6f6f0;--amber:#9a631a;--amberbg:#fff5e6;--red:#b34240;--redbg:#fff0ef}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);font-family:system-ui,-apple-system,"Segoe UI",Arial,sans-serif;font-size:14px;line-height:1.48;color:var(--ink)}
header{background:linear-gradient(110deg,#10263b,#17486a);color:#fff}
.hero{max-width:1250px;margin:auto;padding:35px 22px 30px}
.eyebrow{color:#b6d6ef;font-size:11px;letter-spacing:.13em;text-transform:uppercase;font-weight:800}
h1{font-size:27px;letter-spacing:-.035em;margin:7px 0 8px}
.hero p{color:#d0e0ed;margin:0}
.hero .meta{margin-top:17px;font-size:12px;color:#b9d3e4;overflow-wrap:anywhere}
main{max-width:1250px;margin:auto;padding:24px 20px 38px}
.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:13px;margin:0 0 18px}
.metric,.panel{background:var(--paper);border:1px solid var(--line);border-radius:13px}
.metric{padding:18px 18px 16px;min-height:132px}
.metric .label{font-size:12px;color:var(--muted);font-weight:700}
.metric .number{font-size:32px;font-weight:750;line-height:1.3;letter-spacing:-.04em;margin:5px 0 2px}
.metric .small{font-size:12px;color:var(--muted)}
.metric.danger{border-top:3px solid var(--red)}
.metric.alert{border-top:3px solid #d99b35}
.metric.info{border-top:3px solid var(--blue)}
.metric.good{border-top:3px solid var(--green)}
.panel{padding:22px;margin:0 0 18px}
.panel-head{display:flex;justify-content:space-between;gap:18px;align-items:center;margin-bottom:15px;flex-wrap:wrap}
h2{margin:0;font-size:18px;letter-spacing:-.018em}
.sub{font-size:12px;color:var(--muted)}
.pill{display:inline-flex;align-items:center;gap:6px;padding:3px 9px;border-radius:30px;font-size:11px;font-weight:700;background:#e9f0f7;color:#49627a}
.pill.green{background:var(--greenbg);color:var(--green)}.pill.red{background:var(--redbg);color:var(--red)}.pill.amber{background:var(--amberbg);color:var(--amber)}
.notice{border:1px solid #d0e4f5;background:var(--bluebg);padding:13px 16px;border-radius:10px;margin:10px 0}
.notice.red{border-color:#f0c4c1;background:var(--redbg)}.notice.amber{border-color:#f0d6ad;background:var(--amberbg)}
.notice b{display:block;margin-bottom:3px}.notice p{margin:0;color:#475f73}
.pipeline{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin:13px 0 10px}
.stage{border:1px solid var(--line);border-radius:10px;padding:15px;background:#fcfdff;min-width:0}
.stage b{display:block;font-size:13px}.stage small{font-size:12px;color:var(--muted);display:block;margin-top:4px}
.stage .index{display:inline-block;background:#e7f0f8;color:#296d9e;width:23px;height:23px;text-align:center;line-height:23px;border-radius:50%;font-weight:800;margin-bottom:8px}
.stage.dim{background:#f7f9fc}
table{border-collapse:collapse;width:100%;font-size:12.5px}
th,td{padding:11px 10px;text-align:left;border-bottom:1px solid #e7edf3;vertical-align:top;overflow-wrap:anywhere}
th{position:sticky;top:0;background:#f0f5fa;color:#4b6279;font-weight:750;z-index:1}
tr:hover td{background:#f8fbff}
.scroller{max-height:470px;overflow:auto;border:1px solid var(--line);border-radius:9px}
input[type=search]{border-radius:8px;border:1px solid #cbd7e3;padding:10px 12px;min-width:250px;max-width:100%;font:inherit}
.searchrow{display:flex;gap:12px;align-items:center;margin-bottom:13px;flex-wrap:wrap}
.muted{color:var(--muted)}
pre{margin:0;white-space:pre-wrap;word-break:break-word;font:12px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace;color:#334d66;max-width:690px}
.probe{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}
.probe>div{background:#f7faff;border:1px solid var(--line);padding:12px;border-radius:9px}
.probe .k{font-size:12px;color:var(--muted)}.probe .v{font-weight:750;margin-top:4px;overflow-wrap:anywhere}
.bars{display:grid;gap:10px}
.barline{display:grid;grid-template-columns:135px 1fr 30px;gap:9px;align-items:center;font-size:12px;color:var(--muted)}
.track{height:10px;border-radius:9px;background:#ebf0f6;overflow:hidden}
.fill{height:100%;background:#327eba;border-radius:9px}
.controls{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
select{border:1px solid #cbd7e3;border-radius:7px;padding:9px;color:var(--ink);background:#fff}
footer{color:var(--muted);font-size:12px;line-height:1.5;padding:5px 0 30px}
.empty{padding:20px;color:var(--muted)}
details summary{cursor:pointer;color:#225a8c;font-weight:700}
@media(max-width:960px){.grid{grid-template-columns:repeat(2,1fr)}.pipeline{grid-template-columns:repeat(2,1fr)}.probe{grid-template-columns:repeat(2,1fr)}}
@media(max-width:580px){.grid{grid-template-columns:1fr}.pipeline,.probe{grid-template-columns:1fr}.barline{grid-template-columns:110px 1fr 28px}h1{font-size:24px}}
@media print{body{background:#fff}header{background:#fff;color:#000}.hero p,.hero .meta,.eyebrow{color:#444}.scroller{max-height:none;overflow:visible}.panel{break-inside:avoid}}
</style>
</head>
<body>
<header><div class="hero">
<div class="eyebrow">SharePoint On-Prem / analiza incydentu</div>
<h1>Diagnostyka Workflow</h1>
<p>Przejrzysty podgląd problemów z procesami uruchamianymi z listy</p>
<div class="meta" id="subtitle"></div>
</div></header>
<main>
<div class="grid" id="metrics"></div>
<section class="panel">
  <div class="panel-head"><h2>Przebieg procesu i punkt awarii</h2><span class="pill" id="coverage"></span></div>
  <div class="pipeline" id="pipeline"></div>
  <p class="sub">Etapy są modelem diagnostycznym, a nie potwierdzeniem wykonania każdego kroku. Wysyłka e-mail z SharePoint nie jest równoznaczna z udaną akcją Send Email w workflow.</p>
  <div id="findings"></div>
</section>
<section class="panel">
 <div class="panel-head"><h2>Workflow przypisane do listy</h2><span class="sub" id="workflowCount"></span></div>
 <div class="searchrow"><input type="search" id="wfSearch" placeholder="Szukaj workflow / wyzwalacza..."></div>
 <div class="scroller"><table><thead><tr><th>Silnik</th><th>Nazwa</th><th>Aktywne</th><th>Wyzwalacze</th><th>Zakres</th></tr></thead><tbody id="workflows"></tbody></table></div>
 <p class="sub">Gdy odczyt silnika jest nieudany, brak wierszy nie oznacza braku workflow.</p>
</section>
<section class="panel">
 <div class="panel-head"><h2>Uruchomienia na sprawdzonych elementach</h2><span class="sub" id="itemsCount"></span></div>
 <div class="scroller"><table><thead><tr><th>Element</th><th>Silnik</th><th>Identyfikator procesu</th><th>Stan instancji</th><th>Utworzono</th></tr></thead><tbody id="instances"></tbody></table></div>
 <p class="sub">Odczyty nie obejmują gwarantowanej pełnej historii instancji; brak instancji nie dowodzi, że nigdy nie została uruchomiona.</p>
</section>
<section class="panel">
 <div class="panel-head"><h2>Diagnostyka farmy</h2><span class="sub">Konfiguracja odczytana bez zmian</span></div>
 <div class="probe" id="probes"></div>
</section>
<section class="panel">
 <div class="panel-head"><h2>Lokalne ostrzeżenia i błędy ULS</h2><span class="pill" id="ulsStatus"></span></div>
 <div class="searchrow"><input type="search" id="logSearch" placeholder="Filtruj błędy, komunikaty, Correlation ID..."><span class="sub" id="logCount"></span></div>
 <div class="scroller"><table><thead><tr><th>Czas</th><th>Obszar / kategoria</th><th>Komunikat</th><th>Correlation ID</th></tr></thead><tbody id="uls"></tbody></table></div>
 <p class="sub">ULS z serwera, na którym uruchomiono skrypt. Wpisy z innych WFE/APP mogą nie być widoczne. Do raportu trafia maksymalnie 100 dopasowanych wpisów.</p>
</section>
<section class="panel">
 <div class="panel-head"><h2>Błędy samego audytu</h2><span class="sub" id="errorCount"></span></div>
 <div id="collectorErrors"></div>
</section>
<footer>Raport lokalny i poufny · dane pochodzą z WorkflowTroubleshoot_PRIVATE.json · bez Internetu i zewnętrznych bibliotek · nie publikuj HTML ani źródłowego JSON w repozytorium publicznym.</footer>
</main>
<script id="sp-data" type="application/json">__SAFE_JSON__</script>
<script>
(function(){
'use strict';
var d=JSON.parse(document.getElementById('sp-data').textContent);
var list2010=Array.isArray(d.LegacyAssociations)?d.LegacyAssociations:[];
var list2013=Array.isArray(d.WfmSubscriptions)?d.WfmSubscriptions:[];
var items=Array.isArray(d.Items)?d.Items:[];
var logs=Array.isArray(d.Uls)?d.Uls:[];
var errors=Array.isArray(d.Errors)?d.Errors:[];
var statuses=d.Status||{};
var known10=String(statuses.Legacy||'')==='OK';
var known13=String(statuses.Wfm2013||'')==='OK';
function txt(x){return (x===null||x===undefined||x==='')?'—':String(x);}
function element(tag,cls,textValue){var x=document.createElement(tag);if(cls)x.className=cls;if(textValue!==undefined)x.textContent=txt(textValue);return x;}
function append(parent,child){parent.appendChild(child);return child;}
function metric(label,value,foot,type){var c=append(document.getElementById('metrics'),element('div','metric '+type));append(c,element('div','label',label));append(c,element('div','number',value));append(c,element('div','small',foot));}
function pill(status){var t=txt(status),c='pill';if(/(fail|error|suspend|terminat|stop|disable)/i.test(t))c+=' red';else if(/(run|active|start|complet|finish|ok|enabled|ready)/i.test(t))c+=' green';else c+=' amber';return element('span',c,t);}
function cell(row,text){return append(row,element('td','',text));}
function cellBadge(row,value){var td=append(row,element('td'));append(td,pill(value));return td;}
function rowMessage(parent,columns,message){var row=append(parent,element('tr')),col=append(row,element('td','empty',message));col.colSpan=columns;}
function makeRows(target,data,columns,predicate,render,empty){
 var box=document.getElementById(target);box.replaceChildren();var found=0;
 data.forEach(function(x){if(!predicate||predicate(x)){var tr=append(box,element('tr'));render(tr,x);found++;}});
 if(!found)rowMessage(box,columns,empty);
 return found;
}
document.getElementById('subtitle').textContent=txt(d.ListName)+' · build '+txt(d.Build)+' · '+txt(d.Collected)+' · '+txt(d.Server);
var active10=list2010.filter(function(x){return x.Enabled===true;});
var active13=list2013.filter(function(x){return x.Enabled===true;});
var create10=active10.filter(function(x){return x.Create===true;}).length;
var create13=active13.filter(function(x){return (x.EventTypes||[]).indexOf('ItemAdded')>=0;}).length;
var allInstances=[];
items.forEach(function(x){(x.SP2010||[]).forEach(function(v){allInstances.push({item:x.ItemId,engine:'2010',id:v.InstanceId,state:v.State,date:v.Created});});
 (x.SP2013||[]).forEach(function(v){allInstances.push({item:x.ItemId,engine:'2013',id:v.Id,state:v.Status,date:null});});});
var suspect=allInstances.filter(function(x){return /error|fail|fault|cancel|suspend|terminat/i.test(String(x.state||''));}).length;
metric('Workflow 2010',known10?list2010.length:'?',known10?active10.length+' aktywnych':'Brak wiarygodnego odczytu','info');
metric('Workflow 2013',known13?list2013.length:'?',known13?active13.length+' aktywnych':'Brak wiarygodnego odczytu','info');
metric('Próbka instancji',allInstances.length,suspect+' w stanie potencjalnego błędu','alert');
metric('ULS / ostrzeżenia',statuses.Uls==='OK_LOCAL_ONLY'?logs.length:'?',errors.length+' błędów zbierania','danger');
document.getElementById('coverage').textContent=(known10&&known13?'Odczyt definicji OK':'Niepełny odczyt definicji');
var stages=[
 ['Zapis do listy','Dane formularza / elementu — według zgłoszenia użytkownika'],
 ['Wyzwalacz','Start po utworzeniu: 2010 = '+(known10?create10:'?')+', 2013 = '+(known13?create13:'?')],
 ['Silnik Workflow','Workflow 2010 lub Workflow Manager 2013; status z raportu'],
 ['Akcja e-mail','Sprawność wysyłki samego workflow niepotwierdzona']];
stages.forEach(function(s,i){var e=append(document.getElementById('pipeline'),element('div','stage'+(i===3?' dim':'')));append(e,element('span','index',i+1));append(e,element('b','',s[0]));append(e,element('small','',s[1]));});
function finding(title,description,tone){var box=append(document.getElementById('findings'),element('div','notice '+tone));append(box,element('b','',title));append(box,element('p','',description));}
if(errors.length)finding('Część kontroli nie powiodła się','Sprawdź błędy samego kolektora poniżej. Nie interpretuj zer z nieudanych odczytów jako braku workflow.','amber');
if(list2010.length>0 && known10)finding('Wykryto powiązania Workflow 2010','Po aktualizacji SharePoint sprawdź wpisy ULS i mechanizm weryfikacji starszych workflow. Nie wyłączaj zabezpieczeń automatycznie.','amber');
if(list2013.length>0 && d.ProxyPresent===false)finding('Brak proxy Workflow Manager','Wykryto definicje 2013, ale proxy nie jest dostępne. Należy zweryfikować połączenie z Workflow Managerem.','red');
if(list2013.length>0 && d.ClassicWfmFlag53601===false)finding('Flaga 53601 nie jest włączona','Ma znaczenie tylko, jeżeli używany jest Classic Workflow Manager. Sama nieobecność flagi nie dowodzi awarii.','amber');
if(suspect>0)finding('Nieprawidłowe stany istniejących instancji','Zidentyfikowano '+suspect+' instancji o stanie sugerującym przerwanie lub błąd. Zobacz tabelę uruchomień i powiązane wpisy ULS.','red');
if(!known13)finding('Nie udało się potwierdzić workflow 2013','Odczyt subskrypcji Workflow Manager nie zakończył się poprawnie. Liczba zero nie jest potwierdzona.','amber');
if(!errors.length && !suspect && known10 && known13)finding('Brak jednoznacznej przyczyny w próbce','Stan definicji i brak błędnych instancji nie potwierdzają poprawności działania. Następny krok: element z nieudanego zgłoszenia i ULS z czasu próby.','');
var wfRows=[];
list2010.forEach(function(w){wfRows.push({engine:'2010',name:w.Name,enabled:w.Enabled,triggers:[w.Create?'Utworzenie':null,w.Change?'Modyfikacja':null,w.Manual?'Ręcznie':null].filter(Boolean).join(', ')||'Brak',scope:w.Scope});});
list2013.forEach(function(w){wfRows.push({engine:'2013',name:w.Name,enabled:w.Enabled,triggers:(w.EventTypes||[]).join(', ')||'Nieznane',scope:'Lista'});});
function renderWorkflows(){var q=document.getElementById('wfSearch').value.toLocaleLowerCase('pl');
 var count=makeRows('workflows',wfRows,5,function(w){return (w.name+' '+w.engine+' '+w.triggers+' '+w.scope).toLocaleLowerCase('pl').indexOf(q)>=0;},
 function(row,w){cell(row,w.engine);cell(row,w.name);cellBadge(row,w.enabled?'Tak':'Nie');cell(row,w.triggers);cell(row,w.scope);},
 'Brak widocznych definicji. Sprawdź status odczytu i filtr.');
 document.getElementById('workflowCount').textContent=count+' z '+wfRows.length+' widocznych';}
document.getElementById('wfSearch').addEventListener('input',renderWorkflows);renderWorkflows();
document.getElementById('itemsCount').textContent='Sprawdzone elementy: '+items.length+' · znalezione instancje: '+allInstances.length;
makeRows('instances',allInstances,5,null,function(row,w){cell(row,w.item);cell(row,w.engine);cell(row,w.id);cellBadge(row,w.state);cell(row,w.date);},
 'Nie zwrócono instancji dla sprawdzonych elementów — to nie dowód braku wcześniejszych uruchomień.');
var probes=[
 ['Build farmy',d.Build],
 ['Kontrola wstępna starszych workflow',d.EnablePreParseSecurityCheckForWorkflow===null?'Brak odczytu':d.EnablePreParseSecurityCheckForWorkflow?'Włączona':'Wyłączona'],
 ['Classic WFM: flaga 53601',d.ClassicWfmFlag53601===null?'Brak odczytu':d.ClassicWfmFlag53601?'Obecna':'Nieobecna'],
 ['Workflow Manager proxy',d.ProxyPresent===null?'Brak odczytu':d.ProxyPresent?'Obecne':'Nieobecne'],
 ['Status proxy',d.ProxyStatus],
 ['Timer lokalny SPTimerV4',d.TimerService],
 ['Odczyt workflow 2010',statuses.Legacy],
 ['Odczyt workflow 2013',statuses.Wfm2013],
 ['Odczyt lokalnych ULS',statuses.Uls]
];
probes.forEach(function(p){var box=append(document.getElementById('probes'),element('div'));append(box,element('div','k',p[0]));append(box,element('div','v',p[1]));});
document.getElementById('ulsStatus').textContent=statuses.Uls==='OK_LOCAL_ONLY'?'Odczyt lokalny':'Niepełny odczyt';
function renderLogs(){var q=document.getElementById('logSearch').value.toLocaleLowerCase('pl');
 var count=makeRows('uls',logs,4,function(l){return (l.Area+' '+l.Category+' '+l.Message+' '+l.Correlation+' '+l.Time).toLocaleLowerCase('pl').indexOf(q)>=0;},
 function(row,l){cell(row,l.Time);cell(row,txt(l.Area)+' / '+txt(l.Category));var td=append(row,element('td')),pre=append(td,element('pre'));pre.textContent=txt(l.Message);cell(row,l.Correlation);},
 'Brak dopasowanych wpisów lokalnego ULS; nie jest to potwierdzenie braku błędów na innych serwerach.');
 document.getElementById('logCount').textContent='Widoczne: '+count+' / '+logs.length;}
document.getElementById('logSearch').addEventListener('input',renderLogs);renderLogs();
document.getElementById('errorCount').textContent=errors.length+' błędów kolektora';
if(!errors.length)append(document.getElementById('collectorErrors'),element('p','muted','Brak zgłoszonych błędów odczytu kolektora.'));
errors.forEach(function(e){var box=append(document.getElementById('collectorErrors'),element('div','notice amber'));append(box,element('b','',txt(e.Area)+' · '+txt(e.Type)));append(box,element('p','',e.Message));});
})();
</script>
</body>
</html>
'@
$html = $template.Replace('__SAFE_JSON__',$json)
$tmp = Join-Path $folder ('SPworkflow_'+[guid]::NewGuid().ToString('N')+'.tmp')
try {
  [IO.File]::WriteAllText($tmp,$html,(New-Object System.Text.UTF8Encoding($true)))
  Move-Item -LiteralPath $tmp -Destination $fullPath -Force -ErrorAction Stop
} finally {
  if(Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}
Write-Host ('DASHBOARD HTML: '+$fullPath) -ForegroundColor Green
Write-Warning 'Raport HTML jest POUFNY: zawiera nazwy workflow, URL witryny i komunikaty ULS. Pozostaw lokalnie.'
