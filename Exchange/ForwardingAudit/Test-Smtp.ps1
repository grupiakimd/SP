#requires -Version 5.1
# SMTP test: uses Send-MailMessage only; DOES NOT scan Exchange mailboxes.
[CmdletBinding()]
param(
  [string]$ConfigPath=(Join-Path $PSScriptRoot 'config.json'),
  [switch]$PromptForCredential,
  [switch]$SaveCredential,
  [string]$SmtpServer,
  [string]$From,
  [string[]]$To
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Smtp-Helpers.ps1')
try{
  if($SaveCredential -and -not $PromptForCredential){
    throw '-SaveCredential wymaga -PromptForCredential.'
  }
  if($SaveCredential -and ($PSBoundParameters.ContainsKey('SmtpServer') -or
      $PSBoundParameters.ContainsKey('From') -or $PSBoundParameters.ContainsKey('To'))){
    throw 'Przed -SaveCredential ustaw dzialajace Host/From/To w config.json, a potem uruchom bez nadpisywania parametrow.'
  }
  $cfg=Get-Content -LiteralPath $ConfigPath -Encoding UTF8 -Raw | ConvertFrom-Json -ErrorAction Stop
  if(-not $cfg.Email){throw 'Brak Email w config.json.'}
  $email=[pscustomobject]@{
    Host=if($PSBoundParameters.ContainsKey('SmtpServer')){$SmtpServer}else{$cfg.Email.Host}
    Port=$cfg.Email.Port
    UseStartTls=$cfg.Email.UseStartTls
    From=if($PSBoundParameters.ContainsKey('From')){$From}else{$cfg.Email.From}
    To=if($PSBoundParameters.ContainsKey('To')){$To}else{$cfg.Email.To}
    CredentialFile=$cfg.Email.CredentialFile
  }
  $cred=$null
  if($PromptForCredential){
    $cred=Get-Credential -Message 'Podaj te same dane SMTP co w dzialajacym Send-MailMessage'
    if(-not $cred){throw 'Przerwano wprowadzanie danych.'}
  }
  $smtp=Get-SmtpConfig -Email $email -Root $PSScriptRoot -CredentialOverride $cred
  Write-Host "SMTP: $($smtp.Host):$($smtp.Port); polecenie: Send-MailMessage -UseSsl"
  Write-Host "Konto SMTP: $($smtp.Credential.UserName); From: $($smtp.From); To: $($smtp.To -join ', ')"
  $addresses=@([Net.Dns]::GetHostAddresses([string]$smtp.Host))
  if(-not $addresses.Count){throw 'Nie mozna rozwiazac serwera SMTP na adres IP.'}
  Send-AuditSmtpMessage -SmtpConfig $smtp -Subject ('Test Exchange Forwarding SMTP - '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Body 'Test wysylki SMTP przez Send-MailMessage. Nie wykonano audytu skrzynek.'
  Write-Host 'OK: wiadomosc testowa zostala przekazana do SMTP.'
  if($SaveCredential){
    $path=([string]$cfg.Email.CredentialFile).Trim()
    if(-not $path){throw 'Nie ustawiono Email.CredentialFile w config.json.'}
    if(-not [IO.Path]::IsPathRooted($path)){$path=Join-Path $PSScriptRoot $path}
    $smtp.Credential | Export-Clixml -LiteralPath $path -Force
    Write-Host "Po udanym tescie zapisano poswiadczenia DPAPI: $path"
    Write-Warning 'Harmonogram zadan musi wykonywac audyt jako to samo konto Windows na tym samym komputerze.'
  }
  exit 0
}catch{
  Write-Error -ErrorAction Continue -Message ('Test SMTP: '+(Format-SmtpError -Exception $_.Exception))
  Write-Host 'Sprawdz parametry Email.Host / Port / From / To i uzyte konto. Hasla nie wysylaj do repozytorium.'
  exit 3
}
