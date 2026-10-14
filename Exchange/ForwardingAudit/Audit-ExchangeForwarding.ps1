#requires -Version 5.1
[CmdletBinding()]
param(
 [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
 [string[]]$Mailboxes,
 [string]$ExchangeServer,
 [switch]$Full,
 [switch]$Pdf,
 [switch]$NoEmail,
 [switch]$OpenReport
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
function Encode($s) { [Net.WebUtility]::HtmlEncode([string]$s) }
function Resolve-Target($item) {
  if ($null -eq $item) { return '' }
  $s=([string]$item).Trim()
  if($s -match '(?i)^smtp:(.+)$'){$s=$Matches[1].Trim()}
  if($s -match '<([^\s@<>]+@[^\s@<>]+)>'){$s=$Matches[1]}
  # Resolve also SMTP-looking recipients: an internal-looking MailContact can deliver externally.
  # For MailContact and MailUser use the external delivery target if available.
  try{
    $r=Get-Recipient -Identity $s -ErrorAction Stop
    if(([string]$r.RecipientTypeDetails) -in @('MailContact','MailUser') -and $r.ExternalEmailAddress){
      return (([string]$r.ExternalEmailAddress) -replace '(?i)^smtp:', '')
    }
    if($r.PrimarySmtpAddress){return [string]$r.PrimarySmtpAddress}
  }catch{}
  return $s
}
function Get-ForwardingDirection([string]$Destination,[string[]]$InternalDomains){
  $address=$Destination.Trim()
  if($address -match '(?i)^smtp:(.+)$'){$address=$Matches[1].Trim()}
  if($address -notmatch '^[^@\s<>]+@([a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9])$'){return 'Nieustalone'}
  $domain=$Matches[1].ToLowerInvariant()
  if($InternalDomains -contains $domain){return 'Wewnętrzne'}
  return 'Zewnętrzne'
}
function Get-MechanismDetails([string]$Mechanism) {
  # Do not claim a rule was created in Outlook: it may also be created via OWA or Exchange PowerShell.
  switch ($Mechanism) {
    'InboxRule.ForwardTo' {
      return @{ Friendly='Outlook / OWA - reguła: Prześlij dalej'; Location='Outlook/OWA: Reguły skrzynki; PowerShell: Get-InboxRule -Mailbox <adres> -IncludeHidden' }
    }
    'InboxRule.RedirectTo' {
      return @{ Friendly='Outlook / OWA - reguła: Przekieruj'; Location='Outlook/OWA: Reguły skrzynki; PowerShell: Get-InboxRule -Mailbox <adres> -IncludeHidden' }
    }
    'InboxRule.ForwardAsAttachmentTo' {
      return @{ Friendly='Outlook / OWA - reguła: Jako załącznik'; Location='Outlook/OWA: Reguły skrzynki; PowerShell: Get-InboxRule -Mailbox <adres> -IncludeHidden' }
    }
    'Mailbox.ForwardingAddress' {
      return @{ Friendly='Exchange (serwer) - ForwardingAddress'; Location='EAC: Odbiorcy > Skrzynki > Funkcje skrzynki > Przepływ poczty > Szczegóły; PowerShell: Get-Mailbox' }
    }
    'Mailbox.ForwardingSmtpAddress' {
      return @{ Friendly='Exchange (serwer) - ForwardingSmtpAddress'; Location='EAC: Odbiorcy > Skrzynki > Funkcje skrzynki > Przepływ poczty > Szczegóły; PowerShell: Get-Mailbox' }
    }
    default { return @{ Friendly=$Mechanism; Location='Sprawdź konfigurację Exchange PowerShell' } }
  }
}
function Get-ReportColumns {
  [CmdletBinding()]
  param([switch]$Detailed)
  if($Detailed) {
    return @('Database','Mailbox','Address','Type','Mechanism','Destination','Direction',
      'Status','WhereToCheck','TechnicalMechanism','Rule','RuleIdentity',
      'Details','KeepOriginal','OriginalTarget')
  }
  return @('Mailbox','Address','Type','Mechanism','Destination','Direction','Status',
    'Rule','Details','KeepOriginal')
}
function Get-ColumnLabels {
  return @{
    Database='Baza danych'; Mailbox='Skrzynka'; Address='Adres skrzynki'
    Type='Typ skrzynki'; Mechanism='Źródło przekierowania'
    Destination='Przekierowanie do'; Direction='Kierunek'; Status='Status'
    WhereToCheck='Gdzie sprawdzić'; TechnicalMechanism='Parametr techniczny'
    Rule='Nazwa reguły'; RuleIdentity='Identyfikator reguły'
    Details='Warunki i wyjątki'; KeepOriginal='Kopia w skrzynce'
    OriginalTarget='Oryginalny odbiorca (surowy)'
  }
}
function Get-CopyDescription([string]$Mechanism, [string]$RawFlag) {
  # Inbox Rule forwarding does not tell us whether other actions delete/move the original.
  if($Mechanism -like 'InboxRule.*'){return 'Zależnie od działań reguły'}
  if($RawFlag -eq 'True'){return 'Tak'}
  if($RawFlag -eq 'False'){return 'Nie'}
  return 'Nie ustalono'
}
function Finding($mb,$mechanism,$destination,$status,$rule='',$details='',$keep='',$ruleIdentity='') {
  $info=Get-MechanismDetails $mechanism
  $resolved=Resolve-Target $destination
  $direction=Get-ForwardingDirection $resolved $script:internalDomains
  $script:records.Add([pscustomobject][ordered]@{
    Database=[string]$mb.Database; Mailbox=[string]$mb.DisplayName
    Address=[string]$mb.PrimarySmtpAddress; Type=[string]$mb.RecipientTypeDetails
    Mechanism=[string]$info.Friendly; Destination=$resolved; Direction=$direction
    Status=$status; WhereToCheck=[string]$info.Location; TechnicalMechanism=$mechanism
    Rule=$rule; RuleIdentity=$ruleIdentity; Details=$details
    KeepOriginal=(Get-CopyDescription $mechanism $keep); OriginalTarget=[string]$destination
  })
}
function ErrorRecord($scope,$identity,$reason) {
  $script:problems.Add([pscustomobject]@{Time=(Get-Date).ToString('s');Scope=$scope;Identity=$identity;Error=$reason})
}
if(!(Test-Path -LiteralPath $ConfigPath -PathType Leaf)){throw "Missing config.json: $ConfigPath"}
$cfg=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
# Exact SMTP-domain allowlist. All internal accepted SMTP domains must be listed.
$internalDomains=@($cfg.InternalDomains | ForEach-Object {
  $domain=([string]$_).Trim().ToLowerInvariant()
  if($domain -notmatch '^[a-z0-9](?:[a-z0-9-]*\.)+[a-z0-9-]+$'){
    throw "Niepoprawna domena InternalDomains: '$domain'."
  }
  $domain
} | Select-Object -Unique)
if($internalDomains.Count -eq 0){throw 'Brak InternalDomains w config.json. Wpisz wszystkie wewnętrzne domeny SMTP.'}
$dbs=@($cfg.Databases | Where-Object { $_ -and $_ -notmatch '^CHANGE_ME_' } | Select-Object -Unique)
$mode=[string]$cfg.Mode
if(!$mode){$mode='Test'}
if($mode -notin @('Test','Full')){throw 'Mode must be Test or Full.'}
if($mode -eq 'Full' -and $dbs.Count -ne 5){throw 'Full mode requires exactly five real databases.'}
$selected=@()
if($PSBoundParameters.ContainsKey('Mailboxes')){$selected=@($Mailboxes | Where-Object {$_ -and $_.Trim()} | Select-Object -Unique)}
elseif($mode -eq 'Test'){$selected=@($cfg.TestMailboxes | Where-Object {$_ -and $_.Trim()} | Select-Object -Unique)}
if($mode -eq 'Test' -and $selected.Count -eq 0){throw 'Test mode requires Mailboxes parameter or TestMailboxes in config.'}
if($mode -eq 'Test' -and $dbs.Count -eq 0){throw 'Test mode requires at least one allowed database.'}
# Remote Exchange PowerShell from any domain-joined Windows host (PowerShell 5.1).
# Current task identity is used with Kerberos; no Exchange installation is required.
$exchangeSession=$null
if(!(Get-Command Get-Mailbox -ErrorAction SilentlyContinue)){
  $hostName=if($PSBoundParameters.ContainsKey('ExchangeServer')) { $ExchangeServer } else { [string]$cfg.ExchangeServer }
  if([string]::IsNullOrWhiteSpace($hostName)){throw 'Set ExchangeServer to the real Exchange FQDN in config.json or specify -ExchangeServer.'}
  if($hostName -match '(?i)(^|\.)example\.(local|com|net|org)$'){throw "Placeholder ExchangeServer '$hostName' detected. Replace it with the actual Exchange hostname in config.json or use -ExchangeServer."}
  if($hostName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]*$'){throw 'ExchangeServer must be a plain server DNS name, not a URL.'}
  $uri="http://$hostName/PowerShell/"
  try {
    $exchangeSession=New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $uri -Authentication Kerberos -ErrorAction Stop
    $null=Import-PSSession $exchangeSession -DisableNameChecking -AllowClobber -ErrorAction Stop
  } catch {
    if($exchangeSession){Remove-PSSession $exchangeSession -ErrorAction SilentlyContinue}
    throw "Exchange remote PowerShell connection failed ($uri): $($_.Exception.Message)"
  }
}
foreach($command in 'Get-Mailbox','Get-InboxRule','Get-MailboxDatabase'){
  if(!(Get-Command $command -ErrorAction SilentlyContinue)){throw "Missing cmdlet: $command"}
}
$folder=[string]$cfg.OutputDirectory
if(!$folder){$folder='Reports'}
if(![IO.Path]::IsPathRooted($folder)){$folder=Join-Path $PSScriptRoot $folder}
[void][IO.Directory]::CreateDirectory($folder)
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$records=New-Object 'System.Collections.Generic.List[object]'
$problems=New-Object 'System.Collections.Generic.List[object]'
$scanned=0
$scanList=New-Object 'System.Collections.Generic.List[object]'
if($mode -eq 'Test'){
  foreach($identity in $selected){
    try{
      $mb=Get-Mailbox -Identity $identity -ErrorAction Stop
      if([string]$mb.RecipientTypeDetails -notin @('UserMailbox','SharedMailbox')){
        ErrorRecord 'Scope' $identity 'Mailbox type excluded';continue
      }
      if(([string]$mb.Database) -notin $dbs){
        ErrorRecord 'Scope' $identity 'Mailbox database not in allowlist';continue
      }
      $scanList.Add($mb)
    }catch{ErrorRecord 'Mailbox' $identity $_.Exception.Message}
  }
}else{
  foreach($db in $dbs){
    try{
      $null=Get-MailboxDatabase -Identity $db -ErrorAction Stop
      $found=@(Get-Mailbox -Database $db -RecipientTypeDetails UserMailbox,SharedMailbox -ResultSize Unlimited -ErrorAction Stop)
      foreach($mb in $found){$scanList.Add($mb)}
    }catch{ErrorRecord 'Database' $db $_.Exception.Message}
  }
}
foreach($mb in $scanList){
    $scanned++
    $keep=[string][bool]$mb.DeliverToMailboxAndForward
    if($mb.ForwardingAddress){Finding $mb 'Mailbox.ForwardingAddress' ([string]$mb.ForwardingAddress) 'Aktywne' '' '' $keep}
    if($mb.ForwardingSmtpAddress){Finding $mb 'Mailbox.ForwardingSmtpAddress' ([string]$mb.ForwardingSmtpAddress) 'Aktywne' '' '' $keep}
    try{
      $rules=@(Get-InboxRule -Mailbox ([string]$mb.Identity) -IncludeHidden -ErrorAction Stop)
      foreach($rule in $rules){
        $status=if($rule.Enabled){'Aktywne'}else{'Wyłączone'}
        foreach($action in @('ForwardTo','RedirectTo','ForwardAsAttachmentTo')){
          $targets=@($rule.$action)
          foreach($target in $targets){
            if($null -eq $target -or [string]::IsNullOrWhiteSpace([string]$target)){continue}
            Finding $mb "InboxRule.$action" ([string]$target) $status ([string]$rule.Name) ([string]$rule.Description) '' ([string]$rule.Identity)
          }
        }
      }
    }catch{ErrorRecord 'InboxRule' ([string]$mb.PrimarySmtpAddress) $_.Exception.Message}
}
$rows=@($records.ToArray() | Sort-Object Address,Mechanism,Destination)
$columns=@(Get-ReportColumns -Detailed:$Full)
$labels=Get-ColumnLabels
$csv=Join-Path $folder "Forwarding_$stamp.csv"
if($rows.Count){
  $exportRows=@(foreach($row in $rows){
    $values=[ordered]@{}
    foreach($column in $columns){$values[[string]$labels[$column]]=[string]$row.$column}
    [pscustomobject]$values
  })
  $exportRows | Export-Csv -Path $csv -Delimiter ';' -Encoding UTF8 -NoTypeInformation
}else{
  $csvHead=($columns | ForEach-Object { '"' + ([string]$labels[$_]).Replace('"','""') + '"' }) -join ';'
  $csvHead | Set-Content -LiteralPath $csv -Encoding UTF8
}
if($problems.Count){
  $problems.ToArray() | Export-Csv (Join-Path $folder "Errors_$stamp.csv") -Encoding UTF8 -Delimiter ';' -NoTypeInformation
}
$unique=@($rows | Select-Object -ExpandProperty Address -Unique).Count
$externalEntries=@($rows | Where-Object { $_.Direction -eq 'Zewnętrzne' }).Count
$activeExternalEntries=@($rows | Where-Object { $_.Direction -eq 'Zewnętrzne' -and $_.Status -eq 'Aktywne' }).Count
$unresolvedEntries=@($rows | Where-Object { $_.Direction -eq 'Nieustalone' }).Count
$state=if($problems.Count){'PARTIAL'}else{'COMPLETE'}
$stateLabel=if($problems.Count){'Niepełny - błędy odczytu'}else{'Zakończono pomyślnie'}
$completed=Get-Date
$completedText=$completed.ToString('dd.MM.yyyy HH:mm:ss')
[pscustomobject]@{
  Date=$completed.ToString('o'); Status=$state; Mode=$mode
  ReportFormat=$(if($Full){'Full'}else{'Standard'})
  Databases=$dbs; Scanned=$scanned; WithForwarding=$unique
  ForwardingEntries=$rows.Count; ExternalEntries=$externalEntries
  ActiveExternalEntries=$activeExternalEntries; UnresolvedEntries=$unresolvedEntries
  InternalDomains=$internalDomains; Errors=$problems.Count
} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $folder "Summary_$stamp.json") -Encoding UTF8

$thead=($columns | ForEach-Object {'<th>'+(Encode $labels[$_])+'</th>'}) -join ''
# Column filters are client-side only; never discard audit evidence or alter the CSV.
$filterCells=New-Object 'System.Collections.Generic.List[string]'
for($ci=0;$ci -lt $columns.Count;$ci++){
  $key=[string]$columns[$ci]
  $label=Encode $labels[$key]
  if($key -in @('Database','Type','Mechanism','Direction','Status','KeepOriginal')){
    $filterCells.Add('<th><select class="columnFilter" data-col="'+$ci+'" aria-label="Filtruj: '+$label+'"><option value="">Wszystkie</option></select></th>')
  }else{
    $filterCells.Add('<th><input type="text" class="columnFilter" data-col="'+$ci+'" aria-label="Filtruj: '+$label+'" placeholder="Filtruj..." autocomplete="off"></th>')
  }
}
$filterHead=$filterCells -join ''
$body=($rows | ForEach-Object {
  $row=$_
  '<tr data-direction="'+(Encode $row.Direction)+'">'+(($columns | ForEach-Object {'<td>'+(Encode $row.$_)+'</td>'}) -join '')+'</tr>'
}) -join [Environment]::NewLine
$noResults=if($rows.Count -eq 0){'<p>Nie wykryto przekierowań w zbadanych skrzynkach.</p>'}else{''}
$page=@"
<!doctype html>
<html lang="pl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Audyt przekierowań poczty Exchange</title>
<style>
body{font:14px/1.5 Segoe UI,Arial,sans-serif;margin:26px;background:#f5f7fa;color:#172338}
h1{margin:0 0 8px;font-size:25px}p{margin:11px 0}
.subtitle{color:#40536c;margin-bottom:16px}
.stats{display:flex;flex-wrap:wrap;gap:10px;margin:16px 0}
.stats span{display:inline-block;padding:12px 14px;background:#fff;border:1px solid #d5dfeb;border-radius:7px}
.note{color:#40536c;max-width:1150px}
input[type=search]{padding:10px;width:320px;max-width:95%;border:1px solid #aab8c9;border-radius:5px;margin:14px 0}
.filters{display:flex;gap:16px;align-items:center;flex-wrap:wrap;margin:10px 0}
.filters label{cursor:pointer}
.buttons{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin:10px 0}
button{cursor:pointer;border:1px solid #9bb0c7;border-radius:5px;padding:9px 13px;background:#fff;color:#172338}
button:hover{background:#eaf0f8}
.columnFilter{width:100%;min-width:95px;box-sizing:border-box;border:1px solid #bdccdc;border-radius:3px;padding:5px;font:12px Segoe UI,Arial,sans-serif}
.filtersRow th{background:#f7f9fc;padding:5px}
@page{size:A3 landscape;margin:10mm}
@media print{
  body{margin:0;background:white;color:black;font-size:10px}
  .filters,.buttons,.filtersRow{display:none!important}
  .scroll{overflow:visible;border:0}
  table{white-space:normal;table-layout:auto}
  th,td{padding:4px 5px;border:1px solid #c6c6c6;font-size:9px;word-wrap:break-word}
  thead{display:table-header-group}
  tr{page-break-inside:avoid}
}
.scroll{overflow-x:auto;background:white;border:1px solid #d5dfeb;border-radius:7px}
table{width:100%;border-collapse:collapse;white-space:nowrap}
th,td{padding:10px 12px;text-align:left;vertical-align:top;border-bottom:1px solid #e3e8f0}
th{background:#e9f0f8}
tbody tr:hover{background:#f0f6ff}
td{max-width:520px;white-space:normal;overflow-wrap:break-word;word-wrap:break-word}
</style></head><body>
<h1>Audyt przekierowań poczty Exchange</h1>
<p class="subtitle">Data wykonania skanu: $(Encode $completedText) | Status: $(Encode $stateLabel)</p>
<div class="stats"><span>Przeskanowano skrzynek: <strong>$scanned</strong></span>
<span>Skrzynki z przekierowaniami: <strong>$unique</strong></span>
<span>Wykryte przekierowania: <strong>$($rows.Count)</strong></span>
<span>Przekierowania na zewnątrz: <strong>$externalEntries</strong></span></div>
<p class="note">Wyświetlane są wyłącznie skrzynki z wykrytymi przekierowaniami (także wyłączonymi). Licznik zewnętrznych uwzględnia też wyłączone reguły. Domeny wewnętrzne definiuje konfiguracja; nierozpoznane cele oznaczane są jako „Nieustalone”. Audyt obejmuje również reguły ukryte dostępne przez Exchange PowerShell.</p>
<p class="note"><strong>Gdzie szukać?</strong> Exchange (serwer): EAC &gt; Odbiorcy &gt; Skrzynki &gt; Funkcje skrzynki &gt; Przepływ poczty &gt; Szczegóły. Outlook/OWA: Reguły skrzynki.</p>
<div class="filters"><label for="q">Filtruj wyniki:</label>
<input id="q" type="search" placeholder="Wpisz nazwę, adres lub źródło">
<label for="onlyExternal"><input id="onlyExternal" type="checkbox"> Tylko przekierowania zewnętrzne</label></div>
<div class="buttons"><button type="button" id="printPdf">Drukuj / zapisz do PDF</button><button type="button" id="clearFilters">Wyczyść filtry</button><span id="visibleCount"></span></div>
$noResults
<div class="scroll"><table id="results"><thead><tr>$thead</tr><tr class="filtersRow">$filterHead</tr></thead><tbody>$body</tbody></table></div>
<script>
(function() {
  var field=document.getElementById('q');
  var checkbox=document.getElementById('onlyExternal');
  var filters=document.querySelectorAll('.columnFilter');
  var rows=document.querySelectorAll('#results tbody tr');
  var count=document.getElementById('visibleCount');
  function content(el){return (el.textContent||el.innerText||'').replace(/^\s+|\s+$/g,'');}
  function getCell(row,index){return content(row.cells[index]);}
  // Build allowed select values from the actual table data, no network calls.
  for(var i=0;i<filters.length;i++){
    if(filters[i].tagName.toLowerCase()!=='select'){continue;}
    var index=parseInt(filters[i].getAttribute('data-col'),10);
    var values=[];
    var seen={};
    for(var j=0;j<rows.length;j++){
      var item=getCell(rows[j],index);
      if(!seen['v:'+item]){seen['v:'+item]=true;values.push(item);}
    }
    values.sort();
    for(var k=0;k<values.length;k++){
      var option=document.createElement('option');
      option.value=values[k];option.appendChild(document.createTextNode(values[k]));
      filters[i].appendChild(option);
    }
  }
  function updateRows(){
    var q=field.value.toLowerCase();
    var visible=0;
    for(var i=0;i<rows.length;i++){
      var row=rows[i];
      var external=row.getAttribute('data-direction')==='Zewnętrzne';
      var show=content(row).toLowerCase().indexOf(q)>=0 && (!checkbox.checked||external);
      if(show){
        for(var j=0;j<filters.length;j++){
          var filter=filters[j];
          var value=filter.value.toLowerCase();
          if(!value){continue;}
          var cell=getCell(row,parseInt(filter.getAttribute('data-col'),10)).toLowerCase();
          if(filter.tagName.toLowerCase()==='select' ? cell!==value : cell.indexOf(value)<0){
            show=false;break;
          }
        }
      }
      row.style.display=show?'':'none';
      if(show){visible++;}
    }
    count.innerHTML='Widoczne wiersze: '+visible+' / '+rows.length;
  }
  field.onkeyup=updateRows;field.oninput=updateRows;
  checkbox.onchange=updateRows;
  for(var j=0;j<filters.length;j++){filters[j].onkeyup=updateRows;filters[j].onchange=updateRows;filters[j].oninput=updateRows;}
  document.getElementById('clearFilters').onclick=function(){
    field.value='';checkbox.checked=false;
    for(var j=0;j<filters.length;j++){filters[j].value='';}
    updateRows();
  };
  document.getElementById('printPdf').onclick=function(){window.print();};
  updateRows();
})();
</script>
</body></html>
"@
$page | Set-Content (Join-Path $folder "Forwarding_$stamp.html") -Encoding UTF8
Write-Host "Audyt: $stateLabel; przeskanowano: $scanned; skrzynki z przekierowaniami: $unique; przekierowania: $($rows.Count); zewnętrzne: $externalEntries; błędy: $($problems.Count); raport: $folder"

# Open the HTML even if subsequent SMTP delivery fails during an interactive run.
$reportHtml=Join-Path $folder "Forwarding_$stamp.html"
if($OpenReport){Start-Process -FilePath $reportHtml}
$pdfFile=Join-Path $folder "Forwarding_$stamp.pdf"
$pdfCreated=$false
$pdfError=$null
# Backward compatible: existing config.json files need no Pdf section.
$pdfConfig=$null
$pdfProperty=$cfg.PSObject.Properties['Pdf']
if($pdfProperty){$pdfConfig=$pdfProperty.Value}
$pdfRequested=[bool]$Pdf -or [bool]($pdfConfig -and $pdfConfig.Enabled)
if($pdfRequested){
  try{
    $edgePath=if($pdfConfig -and $pdfConfig.PSObject.Properties['EdgePath']){[string]$pdfConfig.EdgePath}else{''}
    & (Join-Path $PSScriptRoot 'Export-ReportPdf.ps1') -InputHtml $reportHtml -OutputPdf $pdfFile -EdgePath $edgePath
    $pdfCreated=Test-Path -LiteralPath $pdfFile
  }catch{
    $pdfError=$_.Exception.Message
    Write-Warning "PDF nie został wygenerowany: $pdfError"
  }
}
if(-not $NoEmail -and $cfg.Email -and $cfg.Email.Enabled){
  . (Join-Path $PSScriptRoot 'Smtp-Helpers.ps1')
  try{
    $ec=Get-SmtpConfig -Email $cfg.Email -Root $PSScriptRoot
    Write-Host "Wysyłka SMTP: $($ec.Host):$($ec.Port), STARTTLS, konto: $($ec.Credential.UserName)"
    $attachments=@($reportHtml,$csv,(Join-Path $folder "Summary_$stamp.json"))
    if($problems.Count){$attachments+=Join-Path $folder "Errors_$stamp.csv"}
    if($pdfCreated){$attachments+=$pdfFile}
    $body="Przeskanowano: $scanned; skrzynki z przekierowaniem: $unique; wpisy: $($rows.Count); zewnętrzne: $externalEntries; nieustalone: $unresolvedEntries; błędy odczytu: $($problems.Count)."
    if($pdfError){$body+=" Uwaga: nie udało się wygenerować PDF: $pdfError"}
    Send-AuditSmtpMessage -SmtpConfig $ec -Subject "Audyt przekierowań Exchange - $state - $stamp" -Body $body -Attachments $attachments
    Write-Host 'Raport wysłany przez uwierzytelnione SMTP.'
  }catch{
    $details=Format-SmtpError -Exception $_.Exception
    Write-Error -Message ("Wysyłka SMTP nieudana: "+$details) -ErrorAction Continue
    Write-Warning 'Sprawdź Email.Host, port 587, TLS/certyfikat, SMTP AUTH, konto i uprawnienie Send As. Uruchom Test-Smtp.ps1.'
    if($exchangeSession){Remove-PSSession $exchangeSession -ErrorAction SilentlyContinue}
    exit 3
  }
}
if($exchangeSession){Remove-PSSession $exchangeSession -ErrorAction SilentlyContinue}
if($pdfError){exit 4}
if($problems.Count){exit 2}
exit 0
