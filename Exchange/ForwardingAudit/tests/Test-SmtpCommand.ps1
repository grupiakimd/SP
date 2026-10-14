#requires -Version 5.1
# Offline integration test of the exact, confirmed Send-MailMessage invocation.
# Replaces the cmdlet with a mock so nothing is sent over the network.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\Smtp-Helpers.ps1')
$script:mailCalls=0
$script:expectedAttachment=$null
function Send-MailMessage {
  param(
    [string]$SmtpServer,[int]$Port,[string]$From,[string[]]$To,
    [string]$Subject,[string]$Body,[switch]$BodyAsHtml,
    [pscredential]$Credential,[string[]]$Attachments,
    [string]$ErrorAction,[switch]$UseSsl
  )
  if($SmtpServer -ne '192.0.2.10' -or $Port -ne 587){throw 'Host/port mismatch'}
  if($From -ne 'audit@example.local' -or @($To).Count -ne 1 -or $To[0] -ne 'admin@example.local'){
    throw 'From/To mismatch'
  }
  if($Subject -ne 'Test' -or $Body -ne 'testpoczty' -or -not $BodyAsHtml){
    throw 'BodyAsHtml/Subject/Body mismatch'
  }
  if($Credential.UserName -ne 'fixture-user'){throw 'Credential mismatch'}
  if($UseSsl){throw 'UseSsl was unexpectedly enabled'}
  if($script:expectedAttachment){
    if(@($Attachments).Count -ne 1 -or $Attachments[0] -ne $script:expectedAttachment){
      throw 'Missing report attachment'
    }
  }else{
    if(@($Attachments).Count -ne 0){throw 'Unexpected report attachment'}
  }
  $script:mailCalls++
}
$secret=ConvertTo-SecureString 'test-value-only' -AsPlainText -Force
$credential=New-Object System.Management.Automation.PSCredential('fixture-user',$secret)
$config=[pscustomobject]@{
  Host='192.0.2.10';Port=587;From='audit@example.local'
  To=@('admin@example.local');Credential=$credential
}
Send-AuditSmtpMessage -SmtpConfig $config -Subject 'Test' -Body 'testpoczty'
$attachment=Join-Path $env:TEMP ('smtp-test-'+[guid]::NewGuid().ToString('N')+'.txt')
try{
  'file' | Set-Content -LiteralPath $attachment -Encoding UTF8
  $script:expectedAttachment=$attachment
  Send-AuditSmtpMessage -SmtpConfig $config -Subject 'Test' -Body 'testpoczty' -Attachments @($attachment)
}finally{
  Remove-Item -LiteralPath $attachment -Force -ErrorAction SilentlyContinue
}
if($script:mailCalls -ne 2){throw "Expected two SMTP invocations: $($script:mailCalls)"}
Write-Host 'PASS: Send-MailMessage exactly matches screenshot (no UseSsl), including HTML and attachments.'
