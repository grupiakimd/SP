#requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'))
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
if($dbs.Count -ne 5){throw 'Exactly five real database names required in config.json; placeholders not accepted.'}
if(!(Get-Command Get-Mailbox -ErrorAction SilentlyContinue)){
  $install=[Environment]::GetEnvironmentVariable('ExchangeInstallPath')
  if(!$install){throw 'Run on an Exchange server with Exchange Management Tools (ExchangeInstallPath missing).'}
  $bootstrap=Join-Path $install 'bin\RemoteExchange.ps1'
  if(!(Test-Path $bootstrap)){throw "Exchange bootstrap missing: $bootstrap"}
  . $bootstrap
  Connect-ExchangeServer -Auto -ErrorAction Stop | Out-Null
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
foreach($db in $dbs){
  try {
    $null=Get-MailboxDatabase -Identity $db -ErrorAction Stop
    $mailboxes=@(Get-Mailbox -Database $db -RecipientTypeDetails UserMailbox,SharedMailbox -ResultSize Unlimited -ErrorAction Stop)
  } catch { ErrorRecord 'Database' $db $_.Exception.Message; continue }
  foreach($mb in $mailboxes){
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
}
$rows=@($records.ToArray() | Sort-Object Address,Mechanism,Destination)
$columns=@('Database','Mailbox','Address','Type','Mechanism','Destination','Status','Rule','Details','KeepOriginal')
$csv=Join-Path $folder "Forwarding_$stamp.csv"
if($rows.Count){$rows | Export-Csv -Path $csv -Delimiter ';' -Encoding UTF8 -NoTypeInformation}
else{('"' + ($columns -join '";"') + '"') | Set-Content $csv -Encoding UTF8}
if($problems.Count){$problems.ToArray() | Export-Csv (Join-Path $folder "Errors_$stamp.csv") -Encoding UTF8 -Delimiter ';' -NoTypeInformation}
$unique=@($rows | Select-Object -ExpandProperty Address -Unique).Count
$state=if($problems.Count){'PARTIAL'}else{'COMPLETE'}
[pscustomobject]@{Date=(Get-Date).ToString('o');Status=$state;Databases=$dbs;Scanned=$scanned;WithForwarding=$unique;ForwardingEntries=$rows.Count;Errors=$problems.Count} |
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
<h1>Exchange forwarding audit</h1><p>$(Encode $stamp) | Status: $(Encode $state) | selected databases only</p>
<section><span>Scanned: $scanned</span><span>Mailboxes with forwarding: $unique</span><span>Forwarding entries: $($rows.Count)</span><span>Errors: $($problems.Count)</span></section>
<p>Only mailboxes with configured forwarding appear below. Disabled rules are marked. Details may include rule conditions and exceptions.</p>
<input id="q" type="search" placeholder="Filter results"><div class="scroll"><table><thead><tr>$thead</tr></thead><tbody>$body</tbody></table></div>
<script>document.getElementById('q').addEventListener('input',function(){let q=this.value.toLowerCase();document.querySelectorAll('tbody tr').forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(q))})</script>
</main></body></html>
"@
$page | Set-Content (Join-Path $folder "Forwarding_$stamp.html") -Encoding UTF8
Write-Host "Audit $state; scanned=$scanned; entries=$($rows.Count); errors=$($problems.Count); output=$folder"
if($problems.Count){exit 2}
exit 0
