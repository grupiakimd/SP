#requires -Version 5.1
# Shared SMTP helper; secrets remain in DPAPI-encrypted file.
function Get-SmtpConfig {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Email,[Parameter(Mandatory)][string]$Root,[pscredential]$CredentialOverride)
  if(-not $Email){throw 'Brak sekcji Email w config.json'}
  $hostName=([string]$Email.Host).Trim()
  if(-not $hostName -or $hostName -match '(^|\.)example\.(local|com|net|org)$'){
    throw 'Email.Host zawiera nazwę przykładową. Wpisz rzeczywisty FQDN Exchange/serwera SMTP (nie ExchangeServer).'
  }
  $port=0
  if(-not [int]::TryParse([string]$Email.Port,[ref]$port) -or $port -lt 1 -or $port -gt 65535){
    throw 'Email.Port musi mieć wartość od 1 do 65535; dla SMTP Submission zwykle 587.'
  }
  if($Email.UseStartTls -ne $true){throw 'Email.UseStartTls musi być true (SMTP STARTTLS, zwykle port 587).'}
  $from=([string]$Email.From).Trim()
  $to=@($Email.To | Where-Object { $_ -and ([string]$_).Trim() })
  if(-not $from -or $to.Count -eq 0){throw 'Email.From i Email.To muszą zawierać rzeczywiste adresy.'}
  $transport='SmtpClient'
  if($Email.PSObject.Properties['Transport'] -and $Email.Transport){
    $transport=[string]$Email.Transport
  }
  if($transport -notin @('SmtpClient','SendMailMessage')){
    throw "Email.Transport musi mieć wartość SmtpClient lub SendMailMessage, otrzymano: $transport."
  }
  if($CredentialOverride){
    $credential=$CredentialOverride
  }else{
    $file=([string]$Email.CredentialFile).Trim()
    if(-not $file){throw 'Email.CredentialFile jest puste.'}
    if(-not [IO.Path]::IsPathRooted($file)){$file=Join-Path $Root $file}
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){
      throw "Brak pliku poświadczeń SMTP: $file. Uruchom Set-SmtpCredential.ps1 jako konto wykonujące audyt."
    }
    try{
      $credential=Import-Clixml -LiteralPath $file -ErrorAction Stop
      if($credential -isnot [pscredential]){throw 'Nieprawidłowy format poświadczeń.'}
      $null=$credential.GetNetworkCredential().Password
    }catch{
      throw "Nie można odczytać poświadczeń SMTP pod bieżącym kontem Windows: $($_.Exception.Message)"
    }
  }
  [pscustomobject]@{Host=$hostName;Port=$port;From=$from;To=$to;Credential=$credential;Transport=$transport}

}
function Format-SmtpError {
  [CmdletBinding()]
  param([Parameter(Mandatory)][System.Exception]$Exception)
  $parts=New-Object 'System.Collections.Generic.List[string]'
  $item=$Exception
  $level=0
  while($item -and $level -lt 8){
    $detail="[$($item.GetType().Name)] $($item.Message)"
    if($item -is [System.Net.Mail.SmtpException]){$detail+="; SMTP status: $($item.StatusCode)"}
    if($item -is [System.Net.Sockets.SocketException]){$detail+="; socket: $($item.SocketErrorCode)"}
    $parts.Add($detail)
    $item=$item.InnerException
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
  # Legacy parity with the proven Windows PowerShell Send-MailMessage command.
  # It uses the same .NET SMTP implementation; no TLS/certificate checks are disabled.
  if($SmtpConfig.Transport -eq 'SendMailMessage'){
    $args=@{
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
    if($Attachments.Count){$args.Attachments=[string[]]$Attachments}
    Send-MailMessage @args
    return
  }
  if($SmtpConfig.Transport -ne 'SmtpClient'){
    throw "Nieobsługiwany transport SMTP: $($SmtpConfig.Transport)"
  }
  $message=$null
  $client=$null
  try{
    $message=New-Object System.Net.Mail.MailMessage
    $message.From=[string]$SmtpConfig.From
    foreach($recipient in $SmtpConfig.To){[void]$message.To.Add([string]$recipient)}
    $message.Subject=$Subject
    $message.Body=$Body
    $message.SubjectEncoding=[Text.Encoding]::UTF8
    $message.BodyEncoding=[Text.Encoding]::UTF8
    foreach($path in @($Attachments)){
      if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Nie istnieje załącznik: $path"}
      [void]$message.Attachments.Add([System.Net.Mail.Attachment]::new($path))
    }
    $client=[System.Net.Mail.SmtpClient]::new([string]$SmtpConfig.Host,[int]$SmtpConfig.Port)
    $client.EnableSsl=$true
    $client.UseDefaultCredentials=$false
    $client.Credentials=$SmtpConfig.Credential.GetNetworkCredential()
    $client.Timeout=30000
    $client.Send($message)
  }finally{
    if($message){$message.Dispose()}
    if($client){$client.Dispose()}
  }
}
