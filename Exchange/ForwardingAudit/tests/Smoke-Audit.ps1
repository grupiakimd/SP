#requires -Version 5.1
# Offline integration fixture: fake Exchange cmdlets, real report code, no production access.
[CmdletBinding()]
param(
  [ValidateSet('Standard','Full')][string]$ReportFormat = 'Standard',
  [Parameter(Mandatory)][string]$OutputRoot
)
$ErrorActionPreference='Stop'
$folder=Join-Path $OutputRoot $ReportFormat
[void][IO.Directory]::CreateDirectory($folder)
$cfgFile=Join-Path $folder 'config.json'
$fixture=@{
  ExchangeServer='fixture.exchange.local'; Mode='Test'
  Databases=@('TEST-DB')
  TestMailboxes=@('one@example.local','two@example.local','three@example.local','four@example.local')
  OutputDirectory=$folder
  Email=@{Enabled=$false}
}
$fixture | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $cfgFile -Encoding UTF8

function Get-Mailbox {
  [CmdletBinding()]
  param([string]$Identity,[string]$Database,[string[]]$RecipientTypeDetails,[string]$ResultSize)
  if(!$Identity){throw 'Fixture only supports test mailbox lookup'}
  if($Identity -notin $fixture.TestMailboxes){throw "Unknown fixture mailbox $Identity"}
  [pscustomobject]@{
    Database='TEST-DB'; Identity=$Identity; DisplayName=$Identity
    PrimarySmtpAddress=$Identity; RecipientTypeDetails=if($Identity -eq 'four@example.local'){'SharedMailbox'}else{'UserMailbox'}
    ForwardingAddress=$null
    ForwardingSmtpAddress=if($Identity -eq 'one@example.local'){'smtp:forward@example.net'}else{$null}
    DeliverToMailboxAndForward=$false
  }
}
function Get-MailboxDatabase {
  param([string]$Identity)
  if($Identity -ne 'TEST-DB'){throw "Invalid fixture database $Identity"}
  [pscustomobject]@{Name='TEST-DB'}
}
function Get-InboxRule {
  [CmdletBinding()]
  param([string]$Mailbox,[switch]$IncludeHidden)
  if(!$IncludeHidden){throw 'Hidden Inbox Rules were not requested'}
  if($Mailbox -eq 'two@example.local'){
    [pscustomobject]@{
      Name='Forward from user'; Identity='two@example.local\Forward from user'
      Enabled=$true; Description='Forward matching messages'
      ForwardTo=@('copy@example.net'); RedirectTo=@(); ForwardAsAttachmentTo=@()
    }
  }
  if($Mailbox -eq 'three@example.local'){
    [pscustomobject]@{
      Name='Hidden forwarding rule'; Identity='three@example.local\Hidden forwarding rule'
      Enabled=$false; Description='Hidden forwarding test'
      ForwardTo=@(); RedirectTo=@('hidden@example.net'); ForwardAsAttachmentTo=@()
    }
  }
}
function Get-Recipient {
  param([string]$Identity)
  throw 'Unexpected recipient resolution in the fixture'
}
$source=Join-Path (Split-Path $PSScriptRoot -Parent) 'Audit-ExchangeForwarding.ps1'
if($ReportFormat -eq 'Full'){
  & $source -ConfigPath $cfgFile -NoEmail -Full
}else{
  & $source -ConfigPath $cfgFile -NoEmail
}
