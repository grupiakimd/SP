#requires -Version 5.1
[CmdletBinding()]
param(
 [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
 [string[]]$Mailboxes,
 [string]$ExchangeServer,
 [switch]$Full,
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
  if($s -match '^[^@\s<>]+@[^@\s<>]+$'){return $s}
  if($s -match '<([^\s@<>]+@[^\s@<>]+)>'){return $Matches[1]}
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
  if($domain -notmatch '^[a-z0-9](?:[a-z0-9-]*\.)+[a-z0-9-]+$' -or $domain -match '^example\.'){
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
$noResults
<div class="scroll"><table id="results"><thead><tr>$thead</tr></thead><tbody>$body</tbody></table></div>
<script>
(function() {
  var field=document.getElementById('q');
  var checkbox=document.getElementById('onlyExternal');
  function updateRows(){
    var q=field.value.toLowerCase();
    var rows=document.querySelectorAll('#results tbody tr');
    for(var i=0;i<rows.length;i++){
      var content=(rows[i].textContent||rows[i].innerText||'').toLowerCase();
      var external=rows[i].getAttribute('data-direction')==='Zewnętrzne';
      rows[i].style.display=(content.indexOf(q)>=0 && (!checkbox.checked || external))?'':'none';
    }
  }
  field.onkeyup=updateRows;
  field.oninput=updateRows;
  checkbox.onchange=updateRows;
})();
</script>
</body></html>
"@
$page | Set-Content (Join-Path $folder "Forwarding_$stamp.html") -Encoding UTF8
Write-Host "Audyt: $stateLabel; przeskanowano: $scanned; skrzynki z przekierowaniami: $unique; przekierowania: $($rows.Count); zewnętrzne: $externalEntries; błędy: $($problems.Count); raport: $folder"

if(-not $NoEmail -and $cfg.Email -and $cfg.Email.Enabled){
  $mail=$null;$smtp=$null
  try{
    $ec=$cfg.Email
    if(!$ec.Host -or !$ec.From -or !$ec.To -or !$ec.CredentialFile){throw 'Email Host, From, To and CredentialFile are required.'}
    if($ec.Port -lt 1 -or $ec.Port -gt 65535){throw 'Invalid SMTP port.'}
    if($ec.UseStartTls -ne $true){throw 'SMTP email requires UseStartTls=true. This implementation supports STARTTLS (typically port 587), not implicit TLS port 465.'}
    $credentialFile=[string]$ec.CredentialFile
    if(![IO.Path]::IsPathRooted($credentialFile)){$credentialFile=Join-Path $PSScriptRoot $credentialFile}
    $credential=Import-Clixml -LiteralPath $credentialFile -ErrorAction Stop
    if($credential -isnot [pscredential]){throw 'Invalid credential file'}
    $mail=New-Object Net.Mail.MailMessage
    $mail.From=[string]$ec.From
    foreach($recipient in @($ec.To)){if($recipient){[void]$mail.To.Add([string]$recipient)}}
    if(!$mail.To.Count){throw 'No email recipients.'}
    $mail.Subject="Exchange forwarding audit ($mode): $state - $stamp"
    $mail.Body="Scanned: $scanned; mailboxes with forwarding: $unique; entries: $($rows.Count); external: $externalEntries; unresolved: $unresolvedEntries; errors: $($problems.Count). See attached reports."
    $mail.Attachments.Add(([System.Net.Mail.Attachment]::new((Join-Path $folder "Forwarding_$stamp.html"))))
    $mail.Attachments.Add(([System.Net.Mail.Attachment]::new($csv)))
    $mail.Attachments.Add(([System.Net.Mail.Attachment]::new((Join-Path $folder "Summary_$stamp.json"))))
    if($problems.Count){$mail.Attachments.Add(([System.Net.Mail.Attachment]::new((Join-Path $folder "Errors_$stamp.csv"))))}
    $smtp=[System.Net.Mail.SmtpClient]::new([string]$ec.Host,[int]$ec.Port)
    $smtp.EnableSsl=$true
    $smtp.UseDefaultCredentials=$false
    $smtp.Credentials=$credential.GetNetworkCredential()
    $smtp.Timeout=30000
    $smtp.Send($mail)
    Write-Host 'SMTP report sent.'
  }catch{
    Write-Error -Message ("SMTP delivery failed: "+$_.Exception.Message) -ErrorAction Continue
    exit 3
  }finally{
    if($mail){$mail.Dispose()}
    if($smtp){$smtp.Dispose()}
  }
}
if($OpenReport){ Start-Process -FilePath (Join-Path $folder "Forwarding_$stamp.html") }
if($exchangeSession){Remove-PSSession $exchangeSession -ErrorAction SilentlyContinue}
if($problems.Count){exit 2}
exit 0
