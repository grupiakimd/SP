#requires -Version 5.1
[CmdletBinding()]
param(
 [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
 [string[]]$Mailboxes,
 [switch]$NoEmail,
 [switch]$OpenReport
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
function Encode($s) { [Net.WebUtility]::HtmlEncode([string]$s) }
function Resolve-Target($item) {
  if ($null -eq $item) { return '' }
  $s=[string]$item
  if ($s -match '(?i)^smtp:') { return ($s -replace '(?i)^smtp:','') }
  if ($s -match '^[^@\s]+@[^@\s]+$') { return $s }
  try { $r=Get-Recipient -Identity $s -ErrorAction Stop; if($r.PrimarySmtpAddress){return [string]$r.PrimarySmtpAddress} } catch {}
  return $s
}
function Finding($mb,$mechanism,$destination,$status,$rule='',$details='',$keep='') {
  $script:records.Add([pscustomobject][ordered]@{
    Database=[string]$mb.Database; Mailbox=[string]$mb.DisplayName
    Address=[string]$mb.PrimarySmtpAddress; Type=[string]$mb.RecipientTypeDetails
    Mechanism=$mechanism; Destination=(Resolve-Target $destination)
    Status=$status; Rule=$rule; Details=$details; KeepOriginal=$keep
  })
}
function ErrorRecord($scope,$identity,$reason) {
  $script:problems.Add([pscustomobject]@{Time=(Get-Date).ToString('s');Scope=$scope;Identity=$identity;Error=$reason})
}
if(!(Test-Path -LiteralPath $ConfigPath -PathType Leaf)){throw "Missing config.json: $ConfigPath"}
$cfg=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
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
  $hostName=[string]$cfg.ExchangeServer
  if([string]::IsNullOrWhiteSpace($hostName)){throw 'Set ExchangeServer to the Exchange FQDN in config.json.'}
  if($hostName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]*$'){throw 'ExchangeServer must be a server DNS name, not a URL.'}
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
    if($mb.ForwardingAddress){Finding $mb 'Mailbox.ForwardingAddress' ([string]$mb.ForwardingAddress) 'Enabled' '' '' $keep}
    if($mb.ForwardingSmtpAddress){Finding $mb 'Mailbox.ForwardingSmtpAddress' ([string]$mb.ForwardingSmtpAddress) 'Enabled' '' '' $keep}
    try{
      $rules=@(Get-InboxRule -Mailbox ([string]$mb.Identity) -IncludeHidden -ResultSize Unlimited -ErrorAction Stop)
      foreach($rule in $rules){
        $status=if($rule.Enabled){'Enabled'}else{'Disabled'}
        foreach($action in @('ForwardTo','RedirectTo','ForwardAsAttachmentTo')){
          $targets=@($rule.$action)
          foreach($target in $targets){
            if($null -eq $target -or [string]::IsNullOrWhiteSpace([string]$target)){continue}
            Finding $mb "InboxRule.$action" ([string]$target) $status ([string]$rule.Name) ([string]$rule.Description) 'Depends on rule'
          }
        }
      }
    }catch{ErrorRecord 'InboxRule' ([string]$mb.PrimarySmtpAddress) $_.Exception.Message}
}
$rows=@($records.ToArray() | Sort-Object Address,Mechanism,Destination)
$columns=@('Database','Mailbox','Address','Type','Mechanism','Destination','Status','Rule','Details','KeepOriginal')
$csv=Join-Path $folder "Forwarding_$stamp.csv"
if($rows.Count){$rows | Export-Csv -Path $csv -Delimiter ';' -Encoding UTF8 -NoTypeInformation}
else{('"' + ($columns -join '";"') + '"') | Set-Content $csv -Encoding UTF8}
if($problems.Count){$problems.ToArray() | Export-Csv (Join-Path $folder "Errors_$stamp.csv") -Encoding UTF8 -Delimiter ';' -NoTypeInformation}
$unique=@($rows | Select-Object -ExpandProperty Address -Unique).Count
$state=if($problems.Count){'PARTIAL'}else{'COMPLETE'}
[pscustomobject]@{Date=(Get-Date).ToString('o');Status=$state;Mode=$mode;Databases=$dbs;Scanned=$scanned;WithForwarding=$unique;ForwardingEntries=$rows.Count;Errors=$problems.Count} |
  ConvertTo-Json -Depth 4 | Set-Content (Join-Path $folder "Summary_$stamp.json") -Encoding UTF8
$thead=($columns|ForEach-Object{"<th>$(Encode $_)</th>"}) -join ''
$body=($rows|ForEach-Object{$r=$_;'<tr>'+(($columns|ForEach-Object{"<td>$(Encode $r.$_)</td>"})-join '')+'</tr>'}) -join [Environment]::NewLine
$page=@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Exchange Forwarding Audit</title>
<style>body{font:14px Segoe UI,Arial;margin:25px;background:#f5f7fa;color:#1b2b44}
main{max-width:100%;}section{display:flex;gap:12px;flex-wrap:wrap;margin:20px 0}
section span{background:white;border:1px solid #dbe3ec;padding:14px;border-radius:8px}
input{padding:10px;width:350px;max-width:95%;margin-bottom:12px}
div.scroll{overflow:auto;background:white}table{border-collapse:collapse;width:100%;white-space:nowrap}
th,td{padding:9px 12px;border-bottom:1px solid #dbe3ec;text-align:left}
th{background:#eaf0f7}tr:hover{background:#eef5ff}</style></head><body><main>
<h1>Exchange forwarding audit</h1><p>$(Encode $stamp) | Status: $(Encode $state) | Mode: $(Encode $mode) | selected databases only</p>
<section><span>Scanned: $scanned</span><span>Mailboxes with forwarding: $unique</span><span>Forwarding entries: $($rows.Count)</span><span>Errors: $($problems.Count)</span></section>
<p>Only mailboxes with configured forwarding appear below. Disabled rules are marked. Details may include rule conditions and exceptions.</p>
<input id="q" type="search" placeholder="Filter results"><div class="scroll"><table><thead><tr>$thead</tr></thead><tbody>$body</tbody></table></div>
<script>document.getElementById('q').addEventListener('input',function(){let q=this.value.toLowerCase();document.querySelectorAll('tbody tr').forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(q))})</script>
</main></body></html>
"@
$page | Set-Content (Join-Path $folder "Forwarding_$stamp.html") -Encoding UTF8
Write-Host "Audit $state; scanned=$scanned; entries=$($rows.Count); errors=$($problems.Count); output=$folder"
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
    $mail.Body="Scanned: $scanned; mailboxes with forwarding: $unique; entries: $($rows.Count); errors: $($problems.Count). See attached reports."
    $mail.Attachments.Add((New-Object Net.Mail.Attachment (Join-Path $folder "Forwarding_$stamp.html")))
    $mail.Attachments.Add((New-Object Net.Mail.Attachment $csv))
    $mail.Attachments.Add((New-Object Net.Mail.Attachment (Join-Path $folder "Summary_$stamp.json")))
    if($problems.Count){$mail.Attachments.Add((New-Object Net.Mail.Attachment (Join-Path $folder "Errors_$stamp.csv")))}
    $smtp=New-Object Net.Mail.SmtpClient([string]$ec.Host,[int]$ec.Port)
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
