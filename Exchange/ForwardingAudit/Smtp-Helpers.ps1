#requires -Version 5.1
# SMTP transport: Send-MailMessage only (the proven method on this Exchange).
# This file does not load or require MailKit, NuGet or any external modules.
function Get-SmtpConfig {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Email,
    [Parameter(Mandatory)][string]$Root,
    [pscredential]$CredentialOverride
  )
  if(-not $Email){throw 'Brak sekcji Email w config.json.'}
  $hostName=([string]$Email.Host).Trim()
  if(-not $hostName -or $hostName -match '(^|\.)example\.(local|com|net|org)$'){
    throw 'Email.Host jest pusty lub przykladowy. Wpisz serwer SMTP z dzialajacego polecenia Send-MailMessage.'
  }
  $port=0
  if(-not [int]::TryParse([string]$Email.Port,[ref]$port) -or $port -lt 1 -or $port -gt 65535){
    throw 'Email.Port musi byc liczba od 1 do 65535 (najczesciej 587).'
  }
  if($Email.UseStartTls -ne $true){
    throw 'Email.UseStartTls musi byc true: wysylka korzysta z -UseSsl (STARTTLS).'
  }
  $from=([string]$Email.From).Trim()
  $to=@($Email.To | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ([string]$_).Trim() })
  if(-not $from -or $to.Count -eq 0){
    throw 'Ustaw Email.From i przynajmniej jeden odbiorca Email.To.'
  }
  if($Email.PSObject.Properties['Transport'] -and $Email.Transport -and [string]$Email.Transport -ne 'SendMailMessage'){
    Write-Warning "Ignoruje dawne Email.Transport='$($Email.Transport)'. Wysylka zawsze uzywa Send-MailMessage."
  }
  $credential=$CredentialOverride
  if(-not $credential){
    $file=([string]$Email.CredentialFile).Trim()
    if(-not $file){throw 'Brak Email.CredentialFile w config.json.'}
    if(-not [IO.Path]::IsPathRooted($file)){$file=Join-Path $Root $file}
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){
      throw "Nie znaleziono poswiadczen SMTP: $file. Uruchom Set-SmtpCredential.ps1 jako wlasciwe konto Windows."
    }
    try{
      $credential=Import-Clixml -LiteralPath $file -ErrorAction Stop
      if($credential -isnot [pscredential]){throw 'Nieprawidlowy format pliku PSCredential.'}
      $null=$credential.GetNetworkCredential().Password
    }catch{
      throw "Nie mozna odczytac pliku DPAPI SMTP w biezacym kontekscie Windows: $($_.Exception.Message)"
    }
  }
  return [pscustomobject]@{
    Host=$hostName;Port=$port;From=$from;To=$to
    Credential=$credential;Transport='SendMailMessage'
  }
}

function Format-SmtpError {
  [CmdletBinding()]
  param([Parameter(Mandatory)][System.Exception]$Exception)
  $parts=New-Object 'System.Collections.Generic.List[string]'
  $current=$Exception
  $level=0
  while($current -and $level -lt 8){
    $info="[$($current.GetType().Name)] $($current.Message)"
    if($current -is [System.Net.Mail.SmtpException]){
      $info+="; SMTP StatusCode: $($current.StatusCode)"
    }
    if($current -is [System.Net.Sockets.SocketException]){
      $info+="; SocketErrorCode: $($current.SocketErrorCode)"
    }
    $parts.Add($info)
    $current=$current.InnerException
    $level++
  }
  return ($parts -join ' -> ')
}

function Send-AuditSmtpMessage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$SmtpConfig,
    [Parameter(Mandatory)][string]$Subject,
    [Parameter(Mandatory)][string]$Body,
    [string[]]$Attachments=@()
  )
  $attachmentPaths=@($Attachments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  foreach($file in $attachmentPaths){
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){
      throw "Brak zalacznika raportu: $file"
    }
  }
  $mailArgs=@{
    SmtpServer=[string]$SmtpConfig.Host
    Port=[int]$SmtpConfig.Port
    UseSsl=$true
    Credential=$SmtpConfig.Credential
    From=[string]$SmtpConfig.From
    To=[string[]]@($SmtpConfig.To)
    Subject=$Subject
    Body=$Body
    Encoding='UTF8'
    ErrorAction='Stop'
  }
  if($attachmentPaths.Count){
    $mailArgs.Attachments=[string[]]$attachmentPaths
  }
  Send-MailMessage @mailArgs
}
