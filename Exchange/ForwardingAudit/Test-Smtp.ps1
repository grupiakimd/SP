#requires -Version 5.1
# Diagnostyka SMTP, bez skanowania Exchange.
[CmdletBinding()]
param(
  [string]$ConfigPath=(Join-Path $PSScriptRoot 'config.json'),
  [switch]$PromptForCredential,
  [switch]$SaveCredential,
  [string]$SmtpServer,
  [string]$From,
  [string[]]$To,
  [ValidateSet('MailKit','SmtpClient','SendMailMessage')]
  [string]$Transport
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Smtp-Helpers.ps1')
try{
  if($SaveCredential -and -not $PromptForCredential){
    throw '-SaveCredential wymaga -PromptForCredential.'
  }
  $config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
  $email=$config.Email
  if(-not $email){throw 'Brak sekcji Email w config.json.'}
  # Copy current config so command-line overrides never persist in config.json.
  $testEmail=[pscustomobject]@{
    Host=if($PSBoundParameters.ContainsKey('SmtpServer')){$SmtpServer}else{$email.Host}
    Port=$email.Port
    UseStartTls=$email.UseStartTls
    From=if($PSBoundParameters.ContainsKey('From')){$From}else{$email.From}
    To=if($PSBoundParameters.ContainsKey('To')){$To}else{$email.To}
    CredentialFile=$email.CredentialFile
    Transport=if($PSBoundParameters.ContainsKey('Transport')){$Transport}elseif($email.PSObject.Properties['Transport']){$email.Transport}else{'SmtpClient'}
  }
  $promptCredential=$null
  if($PromptForCredential){
    $promptCredential=Get-Credential -Message 'Podaj konto i hasło SMTP, identyczne jak w działającym Send-MailMessage'
    if(-not $promptCredential){throw 'Anulowano wprowadzenie poświadczeń.'}
  }
  $smtp=Get-SmtpConfig -Email $testEmail -Root $PSScriptRoot -CredentialOverride $promptCredential
  Write-Host "SMTP: $($smtp.Host):$($smtp.Port), STARTTLS; transport: $($smtp.Transport)"
  Write-Host "Użytkownik SMTP: $($smtp.Credential.UserName)"
  Write-Host "Nadawca: $($smtp.From); odbiorcy: $($smtp.To -join ', ')"
  $ips=[Net.Dns]::GetHostAddresses([string]$smtp.Host)
  if(@($ips).Count -eq 0){throw 'DNS nie zwrócił adresu serwera SMTP.'}
  Write-Host "Adres SMTP: $($ips -join ', '). Próba wysyłki..."
  Send-AuditSmtpMessage -SmtpConfig $smtp -Subject ('Test SMTP Exchange Audit '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Body 'Wiadomość testowa SMTP AUTH + STARTTLS.'
  Write-Host 'SMTP: wysłano wiadomość testową.'
  if($SaveCredential){
    $name=([string]$email.CredentialFile).Trim()
    if(-not $name){throw 'Nie ustawiono Email.CredentialFile w config.json.'}
    $destination=if([IO.Path]::IsPathRooted($name)){$name}else{Join-Path $PSScriptRoot $name}
    $smtp.Credential | Export-Clixml -LiteralPath $destination -Force
    Write-Host "Zapisano poświadczenia DPAPI dla bieżącego konta Windows: $destination"
    Write-Host 'UWAGA: zadanie Harmonogramu musi używać tego samego konta Windows na tym samym komputerze.'
  }
  exit 0
}catch{
  Write-Error -ErrorAction Continue -Message ("SMTP: "+(Format-SmtpError -Exception $_.Exception))
  Write-Host 'Porównaj wartości Host/From/To z działającym poleceniem. Następnie sprawdź STARTTLS, SMTP AUTH i uprawnienia Send As.'
  exit 3
}
