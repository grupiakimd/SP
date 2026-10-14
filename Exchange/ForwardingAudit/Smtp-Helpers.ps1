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
  $transport='MailKit'
  if($Email.PSObject.Properties['Transport'] -and $Email.Transport){
    $transport=[string]$Email.Transport
  }
  if($transport -notin @('MailKit','SmtpClient','SendMailMessage')){
    throw "Email.Transport musi mieć wartość MailKit, SmtpClient lub SendMailMessage, otrzymano: $transport."
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
  [pscustomobject]@{Host=$hostName;Port=$port;From=$from;To=$to;Credential=$credential;Transport=$transport;LibraryRoot=(Join-Path $Root 'Dependencies\MailKit\lib')}

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
function Import-AuditMailKit {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$LibraryRoot)
  $assemblies=@(
    'System.Runtime.CompilerServices.Unsafe',
    'System.Numerics.Vectors',
    'System.Buffers',
    'System.Memory',
    'System.Threading.Tasks.Extensions',
    'System.Formats.Asn1',
    'BouncyCastle.Cryptography',
    'MimeKit',
    'MailKit'
  )
  if(-not (Test-Path -LiteralPath (Join-Path $LibraryRoot 'manifest.json') -PathType Leaf)){
    throw "MailKit nie jest zainstalowany w $LibraryRoot. Najpierw uruchom .\Install-MailKit.ps1 na komputerze wykonującym audyt."
  }
  foreach($name in $assemblies){
    $file=Join-Path $LibraryRoot ($name+'.dll')
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "Brak zależności MailKit: $file. Ponów .\Install-MailKit.ps1"}
    # Prevent inadvertently binding an incompatible preloaded assembly from a different version.
    $loaded=@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq $name })
    if($loaded.Count){
      $loadedPath=([string]$loaded[0].Location)
      if($loadedPath -and (-not [string]::Equals([IO.Path]::GetFullPath($loadedPath),[IO.Path]::GetFullPath($file),[StringComparison]::OrdinalIgnoreCase))){
        throw "Konflikt bibliotek: $name został załadowany z $loadedPath. Uruchom audyt w nowej sesji Windows PowerShell 5.1."
      }
      continue
    }
    try{
      # Loading assemblies is sufficient; Add-Type forces eager enumeration of all exported
      # types and fails unnecessarily on optional reflection dependencies in .NET Framework.
      $null=[Reflection.Assembly]::LoadFrom($file)
    }catch{
      $reason=$_.Exception.Message
      $reflectionException=$_.Exception
      while($reflectionException -and $reflectionException -isnot [Reflection.ReflectionTypeLoadException]){
        $reflectionException=$reflectionException.InnerException
      }
      if($reflectionException){
        $detail=@($reflectionException.LoaderExceptions | Where-Object { $_ } | ForEach-Object { $_.Message }) -join ' | '
        $reason+=" $detail"
      }
      throw "MailKit DLL: $name; $reason"
    }
  }
  $null=[MailKit.Net.Smtp.SmtpClient]
  $null=[MimeKit.MimeMessage]
}
function New-AuditMimeMessage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$SmtpConfig,
    [Parameter(Mandatory)][string]$Subject,
    [Parameter(Mandatory)][string]$Body,
    [string[]]$Attachments=@()
  )
  $message=[MimeKit.MimeMessage]::new()
  $message.From.Add([MimeKit.MailboxAddress]::Parse([string]$SmtpConfig.From))
  foreach($recipient in @($SmtpConfig.To)){
    $message.To.Add([MimeKit.MailboxAddress]::Parse([string]$recipient))
  }
  $message.Subject=$Subject
  $builder=[MimeKit.BodyBuilder]::new()
  $builder.TextBody=$Body
  foreach($attachment in @($Attachments)){
    if(-not (Test-Path -LiteralPath $attachment -PathType Leaf)){
      throw "Nie istnieje załącznik: $attachment"
    }
    [void]$builder.Attachments.Add([IO.Path]::GetFullPath($attachment))
  }
  $message.Body=$builder.ToMessageBody()
  return $message
}
function Send-AuditSmtpMessage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$SmtpConfig,
    [Parameter(Mandatory)][string]$Subject,
    [Parameter(Mandatory)][string]$Body,
    [string[]]$Attachments=@()
  )
  if($SmtpConfig.Transport -eq 'MailKit'){
    Import-AuditMailKit -LibraryRoot $SmtpConfig.LibraryRoot
    $mime=New-AuditMimeMessage -SmtpConfig $SmtpConfig -Subject $Subject -Body $Body -Attachments $Attachments
    $client=$null
    try {
      $client=[MailKit.Net.Smtp.SmtpClient]::new()
      $client.Timeout=30000
      # StartTls fails closed if STARTTLS is not offered; default certificate validation remains enabled.
      $client.Connect([string]$SmtpConfig.Host,[int]$SmtpConfig.Port,[MailKit.Security.SecureSocketOptions]::StartTls)
      if(-not $client.IsSecure){throw 'MailKit: brak zabezpieczonego połączenia STARTTLS.'}
      if(-not $client.IsAuthenticated){
        $network=$SmtpConfig.Credential.GetNetworkCredential()
        $client.Authenticate([string]$network.UserName,[string]$network.Password)
      }
      $null=$client.Send($mime)
      $client.Disconnect($true)
    }finally{
      if($client){$client.Dispose()}
    }
    return
  }
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
