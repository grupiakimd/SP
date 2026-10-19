#requires -Version 5.1
<#
.SYNOPSIS
  v2.5 Offline HTML + pseudonymized Markdown from EXISTING definition inventory.
.DESCRIPTION
  Does not connect to SharePoint, SQL or Internet. Private HTML contains actual
  workflow names and paths. Shareable MD is strict allowlist (numbers/statuses/
  technical category names only), NEVER raw names, markup, error messages, URLs.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$InputPath,
  [string]$OutputDirectory
)
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
$item=Get-Item -LiteralPath $InputPath -ErrorAction Stop
if($item.PSIsContainer){
  $found=@(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Filter 'WorkflowDefinitions_PRIVATE.json' |
      Sort-Object LastWriteTime -Descending)
  if($found.Count -eq 0){throw 'Nie znaleziono WorkflowDefinitions_PRIVATE.json.'}
  $source=$found[0].FullName
}else{
  if($item.Name -ne 'WorkflowDefinitions_PRIVATE.json'){throw 'Wskaz WorkflowDefinitions_PRIVATE.json.'}
  $source=$item.FullName
}
$d=Get-Content -LiteralPath $source -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
if([string]$d.Schema -ne 'SP-WF-DEFINITIONS-v2.5'){throw 'Nieobslugiwany format danych.'}
if(-not $OutputDirectory){$OutputDirectory=Split-Path -Parent $source}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$assoc=@($d.Associations2010 | Where-Object {$null -ne $_})
$files=@($d.MarkupArtifacts2010 | Where-Object {$null -ne $_})
$subs=@($d.Subscriptions2013 | Where-Object {$null -ne $_})
$defs=@($d.Definitions2013 | Where-Object {$null -ne $_})
$errs=@($d.Errors | Where-Object {$null -ne $_})
$active2010=@($assoc|Where-Object {$_.Enabled -eq $true})
$active13=@($subs|Where-Object {$_.Enabled -eq $true})
$parsable2010=@($files|Where-Object {$_.Parse -eq 'OK' -and $_.Extension -in @('.xoml','.xaml')})
$parsable13=@($defs|Where-Object {$_.Parse -eq 'OK'})
$allProfiles=@($parsable2010)+@($parsable13)

$groups=@($allProfiles | Where-Object {$_.SignatureHash} |
  Group-Object SignatureHash | Sort-Object Count -Descending)
$batchGroups=@($groups | Where-Object {$_.Count -gt 1})
$categoryCounts=[ordered]@{EMAIL=0;TASK_APPROVAL=0;CONDITION=0;LOOP=0;WAIT=0;EXTERNAL_CALL=0;LIST_MUTATION=0}
foreach($itemp in $allProfiles){
  foreach($cat in $itemp.Categories){
    if($categoryCounts.Contains([string]$cat)){$categoryCounts[[string]$cat]++}
  }
}
$alert=@($assoc|Where-Object {$_.Enabled -and $_.AutoStartCreate})
$activeUnknown=@($active2010|Where-Object {$_.DefinitionLinked -ne $true})
$blocked=$false
$cv=$d.Coverage
if([string]$cv.Workflow2010 -ne 'OK' -or
   [string]$cv.Workflow2010Markup -ne 'OK' -or
   [string]$cv.Workflow2013 -ne 'OK' -or
   $errs.Count -gt 0 -or [bool]$cv.ListsTruncated -or
   [bool]$cv.MarkupFilesTruncated -or [bool]$cv.Definitions2013Truncated){
    $blocked=$true
}

function Escape-Html($v){
  if($null -eq $v){return '—'}
  return [Net.WebUtility]::HtmlEncode([string]$v)
}
function Checked-Status($v){
  if($v -eq $true){return '<span class="yes">TAK</span>'}
  if($v -eq $false){return '<span class="no">NIE</span>'}
  return '<span class="muted">NIEZNANE</span>'
}
function AddHtml([string]$line){[void]$script:html.Add($line)}
$md=New-Object 'System.Collections.Generic.List[string]'
function AddMd([string]$line){[void]$script:md.Add($line)}
AddMd '# SharePoint 2019 → SE: analiza definicji workflow (pseudonimizowana)'
AddMd ''
AddMd '**Zakres:** jedna witryna SPWeb, bez podwitryn; pliki XOML i definicje XAML sa artefaktami technicznymi.'
AddMd ''
AddMd ('- Workflow 2010 — powiazania: **{0}**, wlaczone: **{1}**.' -f $assoc.Count,$active2010.Count)
AddMd ('- Autostart 2010 po utworzeniu: **{0}**.' -f $alert.Count)
AddMd ('- Workflow 2013 — subskrypcje: **{0}**, wlaczone: **{1}**.' -f $subs.Count,$active13.Count)
AddMd ('- Artefakty XOML/XAML (2010) odczytane: **{0}**, przetworzone strukturalnie: **{1}**.' -f $files.Count,$parsable2010.Count)
AddMd ('- Definicje XAML (2013) odczytane: **{0}**, przetworzone strukturalnie: **{1}**.' -f $defs.Count,$parsable13.Count)
AddMd ('- Grup o jednakowej sygnaturze strukturalnej: **{0}**, w tym wieloelementowych: **{1}**.' -f $groups.Count,$batchGroups.Count)
AddMd ('- Bledy zbierania: **{0}** (bez nazw i komunikatow).' -f $errs.Count)
AddMd ('- Pokrycie: 2010 associations **{0}**, XOML library **{1}**, 2013 **{2}**.' -f
  ([string]$cv.Workflow2010),([string]$cv.Workflow2010Markup),([string]$cv.Workflow2013))
AddMd ('- Listy: **{0}/{1}**; limit list: **{2}**.' -f
  [int]$cv.ListsScanned,[int]$cv.ListsTotal,[bool]$cv.ListsTruncated)
AddMd ('- Gotowosc klasyfikacji: **{0}**.' -f $(if($blocked){'CZESCIOWA'}else{'PELNE ZEBRANIE DOSTEPNYCH SEKCJI'}))
AddMd ''
AddMd '## Sygnaly zdefiniowanych operacji'
AddMd '| Klasa operacji | Liczba profili zawierajacych klase |'
AddMd '| --- | ---: |'
foreach($key in $categoryCounts.Keys){AddMd ('| '+$key+' | '+$categoryCounts[$key]+' |')}
AddMd ''
AddMd '## Potencjal zbiorczej przebudowy — hipotezy'
AddMd ('- Wylaczone powiazania 2010: **{0}**. Wymagaja uzgodnienia z wlascicielami procesow.' -f ($assoc.Count-$active2010.Count))
AddMd ('- Aktywne powiazania 2010 bez pewnego mapowania na definicje: **{0}**.' -f $activeUnknown.Count)
AddMd ('- Sygnatury z minimum 2 artefaktami: **{0}**. Tylko podobienstwo tagow XML, NIE dowod rownowaznosci.' -f $batchGroups.Count)
AddMd ''
AddMd '| Rodzina | Liczba artefaktow | Wskazowki klas operacji |'
AddMd '| --- | ---: | --- |'
$gi=0
foreach($g in ($batchGroups | Select-Object -First 30)){
  $gi++
  $cats=@($g.Group|ForEach-Object {$_.Categories}|ForEach-Object {$_}|Sort-Object -Unique)
  $approved=@($cats | Where-Object {$_ -in @('EMAIL','TASK_APPROVAL','CONDITION','LOOP','WAIT','EXTERNAL_CALL','LIST_MUTATION')})
  AddMd ('| FAMILY-{0:D3} | {1} | {2} |' -f $gi,$g.Count,($approved -join ', '))
}
if($gi -eq 0){AddMd '| Brak potwierdzonych wieloelementowych rodzin | 0 | — |'}
AddMd ''
AddMd '## Obowiazkowa walidacja przed wdrozeniem'
AddMd '1. Ustal powiazanie konkretnych wlaczonych workflow 2010 z ich definicjami; sam podobny tytul pliku nie jest dowodem.'
AddMd '2. Przejrzyj logike warunkow, odbiorcow, parametrow i lookupow lokalnie. Analiza struktury XML nie odczytuje semantyki.'
AddMd '3. Zbierz brakujace procesy 2013 (FAILED/NOT_RUN nie oznacza zera).'
AddMd '4. Przygotuj proby uruchomienia na odizolowanej farmie SE z blokada rzeczywistych powiadomien.'
AddMd '5. Nie zakladaj, ze identyczny hash zliczen tagow XML oznacza identyczne workflow.'
AddMd ''
AddMd 'Plik MD nie zawiera nazw kont, serwerow, witryn, plikow, adresow ani surowych bledow. Nadal wymaga przegladu przed udostepnieniem.'
$mdFile=Join-Path $OutputDirectory 'WorkflowMigration_SHAREABLE.md'
[IO.File]::WriteAllText($mdFile,($md -join [Environment]::NewLine),([Text.UTF8Encoding]::new($true)))

$html=New-Object 'System.Collections.Generic.List[string]'
AddHtml @'
<!doctype html><html lang="pl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'none'; connect-src 'none'">
<title>SP Workflow Migration Analyzer v2.5</title>
<style>
:root{--bg:#f4f7fb;--panel:#fff;--dark:#16314c;--muted:#657587;--line:#e0e8f1;--accent:#176eb0}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--dark);font:14px/1.55 system-ui,'Segoe UI',Arial,sans-serif}
header{background:#142c45;color:#fff;padding:27px max(calc((100vw - 1180px)/2),22px)}header h1{font-size:24px;margin:0}
header p{color:#c4d8e8;margin:6px 0 0;overflow-wrap:anywhere}
main{max-width:1180px;margin:auto;padding:20px 16px 50px}.kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:11px}
.kpi,.box{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:20px}
.kpi b{font-size:28px;display:block;margin:5px 0}.muted{color:var(--muted)}
.box{margin-top:15px}.box h2{margin:0 0 13px;font-size:19px}.notice{padding:13px;border-left:4px solid var(--accent);background:#e8f2fa;border-radius:5px;margin-top:15px}
.warn{background:#fff4df;border-color:#b8791d}
table{width:100%;border-collapse:collapse;white-space:nowrap;font-size:12.5px}td,th{padding:9px 11px;text-align:left;border-bottom:1px solid #e5edf5}
th{background:#ecf3fa;position:sticky;top:0}.scroll{overflow:auto;max-height:560px}
input{font:inherit;padding:10px;border-radius:7px;border:1px solid #bdcad9;min-width:240px;max-width:100%}
.yes{color:#0b7a5b;font-weight:bold}.no{color:#728397}
h3{margin-top:22px;font-size:15px}.hint{font-size:12px;color:#718095}
@media(max-width:760px){.kpis{grid-template-columns:repeat(2,1fr)}}@media(max-width:480px){.kpis{grid-template-columns:1fr}}
</style></head><body>
'@
AddHtml ('<header><h1>SharePoint · Workflow Migration Analyzer v2.5</h1><p>Audyt definicji i powtarzalności procesu — '+(Escape-Html $d.WebUrl)+'</p></header><main>')
AddHtml '<div class="kpis">'
foreach($tuple in @(
  @('Powiązania 2010',$assoc.Count,('Włączone: '+$active2010.Count)),
  @('Subskrypcje 2013',$(if([string]$cv.Workflow2013 -eq 'OK'){$subs.Count}else{'?'}),('Pokrycie: '+[string]$cv.Workflow2013)),
  @('Profile XML',$allProfiles.Count,('XOML: '+$parsable2010.Count+' · XAML: '+$parsable13.Count)),
  @('Rodziny podobieństw',$batchGroups.Count,'Sygnatury tagów, nie równoważność')
)){
  AddHtml ('<div class="kpi"><span class="muted">'+(Escape-Html $tuple[0])+'</span><b>'+ (Escape-Html $tuple[1])+
           '</b><span class="hint">'+ (Escape-Html $tuple[2]) +'</span></div>')
}
AddHtml '</div>'
AddHtml ('<div class="notice'+$(if($blocked){' warn'}else{''})+'"><b>Stan audytu: '+$(if($blocked){'CZĘŚCIOWY'}else{'ODCZYT ZAKOŃCZONY'})+
  '</b> · 2010: '+(Escape-Html $cv.Workflow2010)+
  ' · XOML: '+(Escape-Html $cv.Workflow2010Markup)+
  ' · 2013: '+(Escape-Html $cv.Workflow2013)+
  ' · Listy: '+[int]$cv.ListsScanned+'/'+[int]$cv.ListsTotal+
  ' · Błędy: '+$errs.Count+'</div>')
AddHtml '<section class="box"><h2>Wnioski migracyjne — stan faktyczny i ograniczenia</h2>'
AddHtml '<p><b>Nie konwertuj automatycznie.</b> Zmiana silnika workflow 2010 na wspierany mechanizm wymaga zachowania skutku biznesowego, odbiorców, warunków, zadań i zachowania przy błędach. Powtarzające się sygnatury XML są kandydatami do ręcznego porównania.</p>'
AddHtml '<p>Silnik 2010 nie jest wspierany w SE po 14.07.2026. Procesy 2013 wymagają odpowiedniego Workflow Managera i testów. Status niepełnego odczytu 2013 nie oznacza braku takich workflow.</p>'
AddHtml ('<p><b>Włączone 2010 bez zweryfikowanego mapowania do źródeł:</b> '+$activeUnknown.Count+'. Nie opieraj decyzji o zbiorczej przebudowie wyłącznie na nazwach lub identycznych tagach.</p></section>')

AddHtml '<section class="box"><h2>Rodziny podobnych definicji</h2><p class="hint">SHA256 podpisu liczby tagów XML — tylko wstępna heurystyka. Rodzina nie oznacza identycznego działania.</p><div class="scroll"><table><thead><tr><th>Rodzina</th><th>Liczba</th><th>Silnik/typ</th><th>Klasy operacji</th><th>Przykładowe artefakty</th></tr></thead><tbody>'
$idx=0
foreach($g in $groups){
  $idx++;$items=@($g.Group)
  $cats=@($items|ForEach-Object {$_.Categories}|ForEach-Object {$_}|Sort-Object -Unique)
  $examples=@($items|Select-Object -First 4|ForEach-Object {
    if($_.PSObject.Properties['Path']){[string]$_.Path}else{[string]$_.DisplayName}
  })
  AddHtml ('<tr><td>FAMILY-'+('{0:D3}' -f $idx)+'</td><td>'+ $g.Count+
    '</td><td>'+(Escape-Html $items[0].Kind)+'</td><td>'+(Escape-Html ($cats -join ', '))+
    '</td><td>'+(Escape-Html ($examples -join '; '))+'</td></tr>')
}
if($groups.Count -eq 0){AddHtml '<tr><td colspan="5">Brak odczytanych XML — nie można ocenić rodzin procesów.</td></tr>'}
AddHtml '</tbody></table></div></section>'

AddHtml '<section class="box"><h2>Aktywne powiązania workflow 2010</h2>'
AddHtml '<p class="hint">To są przypisania do list i witryn. Nie utożsamiaj powiązania z samym plikiem XOML.</p>'
AddHtml '<input id="wfsearch" type="search" placeholder="Szukaj nazwy workflow, listy lub ID...">'
AddHtml '<div class="scroll"><table><thead><tr><th>Zakres</th><th>Nazwa</th><th>Włączone</th><th>Utworzenie</th><th>Zmiana</th><th>Typ</th><th>Źródło</th></tr></thead><tbody id="wfrows">'
foreach($a in $assoc){
  AddHtml ('<tr><td>'+(Escape-Html $a.Scope)+'</td><td>'+(Escape-Html $a.Name)+
    '</td><td>'+(Checked-Status $a.Enabled)+'</td><td>'+(Checked-Status $a.AutoStartCreate)+
    '</td><td>'+(Checked-Status $a.AutoStartChange)+
    '</td><td>'+(Escape-Html $a.IsDeclarative)+'</td><td>'+(Escape-Html $a.LinkEvidence)+'</td></tr>')
}
AddHtml '</tbody></table></div></section>'
AddHtml '<section class="box"><h2>Odczytane artefakty XOML / definicje XAML</h2><div class="scroll">'
AddHtml '<table><thead><tr><th>Typ</th><th>Definicja / plik</th><th>Status XML</th><th>Elementy</th><th>Klasy operacji</th></tr></thead><tbody>'
foreach($f in $files){
  AddHtml ('<tr><td>'+(Escape-Html $f.Extension)+'</td><td>'+(Escape-Html $f.Path)+
    '</td><td>'+(Escape-Html $f.Parse)+'</td><td>'+(Escape-Html $f.Elements)+
    '</td><td>'+(Escape-Html (($f.Categories) -join ', '))+'</td></tr>')
}
foreach($f in $defs){
  AddHtml ('<tr><td>2013 XAML</td><td>'+(Escape-Html $f.DisplayName)+
    '</td><td>'+(Escape-Html $f.Parse)+'</td><td>'+(Escape-Html $f.Elements)+
    '</td><td>'+(Escape-Html (($f.Categories) -join ', '))+'</td></tr>')
}
AddHtml '</tbody></table></div></section>'
AddHtml '<section class="box"><h2>Pokrycie i następne kroki</h2><p>Nieprzetworzone pliki XML, limit rozmiaru, brak WFM oraz biblioteka Workflows poza bieżącym Web wymagają osobnego sprawdzenia. Nie opieraj migracji na „0” z sekcji FAILED.</p>'
AddHtml '<p>Następny etap: potwierdzić mapowanie aktywnych 2010 do ich definicji, zebrać zależności oraz przetestować 2–3 reprezentatywne procesy na odizolowanej farmie SE.</p>'
AddHtml '<p class="hint">HTML zawiera nazwy list, procesów i ścieżki. Zachowaj go wyłącznie lokalnie. Do przekazania służy przejrzany WorkflowMigration_SHAREABLE.md.</p></section>'
AddHtml @'
<script>
(function(){
 const field=document.getElementById('wfsearch');
 field.addEventListener('input',function(){
   const q=field.value.toLowerCase();
   document.querySelectorAll('#wfrows tr').forEach(function(tr){
     tr.style.display=tr.textContent.toLowerCase().indexOf(q)>=0?'':'none';
   });
 });
})();
</script></main></body></html>
'@
$htmlFile=Join-Path $OutputDirectory 'WorkflowMigration_Dashboard.html'
[IO.File]::WriteAllText($htmlFile,($html -join [Environment]::NewLine),([Text.UTF8Encoding]::new($true)))
Write-Host ('ADMIN HTML (PRIVATE): '+$htmlFile) -ForegroundColor Green
Write-Host ('SHAREABLE MD (REVIEW): '+$mdFile) -ForegroundColor Green
Write-Warning 'Pseudonimizacja != pelna anonimowosc. Nigdy nie publikuj PRIVATE JSON/HTML.'
