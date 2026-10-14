#requires -Version 5.1
# Tests authenticated SMTP without querying Exchange mailboxes.
[CmdletBinding()]
param([string]$ConfigPath=(Join-Path $PSScriptRoot 'config.json'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Smtp-Helpers.ps1')
try{
  $config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
  $smtp=Get-SmtpConfig -Email $config.Email -Root $PSScriptRoot
  Write-Host "SMTP: $($smtp.Host):$($smtp.Port), STARTTLS, użytkownik: $($smtp.Credential.UserName)"
  Write-Host "Nadawca: $($smtp.From); odbiorcy: $($smtp.To -join ', ')"
  $tcp=New-Object System.Net.Sockets.TcpClient
  try{
    $async=$tcp.BeginConnect([string]$smtp.Host,[int]$smtp.Port,$null,$null)
    try{
      if(-not $async.AsyncWaitHandle.WaitOne(10000,$false)){throw 'Timeout TCP (10 s). Sprawdź DNS, firewall i port SMTP.'}
      $tcp.EndConnect($async)
      Write-Host 'TCP: połączenie ustanowione.'
    }finally{$async.AsyncWaitHandle.Close()}
  }finally{$tcp.Close()}
  Send-AuditSmtpMessage -SmtpConfig $smtp -Subject ('Test SMTP Exchange Audit '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Body 'Wiadomość testowa: logowanie SMTP AUTH i wysyłka STARTTLS działają.'
  Write-Host 'SMTP AUTH/STARTTLS: wiadomość testowa wysłana poprawnie.'
  exit 0
}catch{
  Write-Error -ErrorAction Continue -Message ("SMTP: "+(Format-SmtpError -Exception $_.Exception))
  Write-Host 'Typowe przyczyny: błędny Email.Host, port/firewall, brak STARTTLS, certyfikat, SMTP AUTH wyłączony, złe hasło, brak Send As.'
  exit 3
}
