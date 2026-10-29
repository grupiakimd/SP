#requires -Version 5.1
<#
 SPSE unattended binaries-only installer v1.1 (2026-10-29).
 ONLY SPSEAPP2 / SPSEWFE1 / SPSEWFE2, local execution, manual restarts.
 Does NOT create/join/configure a farm. No remoting, no SQL writes.
#>
[CmdletBinding(DefaultParameterSetName='Install')]
param(
  [Parameter(ParameterSetName='Install')][switch]$Resume,
  [Parameter(ParameterSetName='Install')][switch]$AcceptLicenseTerms,
  [Parameter(ParameterSetName='Audit')][switch]$Audit
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Allowed = @('SPSEAPP2','SPSEWFE1','SPSEWFE2')
$HostName = [string]$env:COMPUTERNAME
if ($HostName -notin $Allowed -or ((Get-CimInstance Win32_ComputerSystem).Name -ine $HostName)) {
  throw "BLOKADA: dozwolone wylacznie SPSEAPP2, SPSEWFE1, SPSEWFE2. Wykryto $HostName."
}
if (-not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) {
  throw 'Uruchom 64-bitowy Windows PowerShell 5.1.'
}
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Uruchom jako administrator lokalny.'
}
$os = Get-CimInstance Win32_OperatingSystem
if ($os.Caption -notmatch 'Windows Server 2025') { throw 'Wymagany Windows Server 2025.' }
$Root = Join-Path $env:ProgramData ("SPSE-Unattended\{0}" -f $HostName)
$ConfigFile = Join-Path $Root 'media.json'
$StateFile = Join-Path $Root 'progress.json'
$ReportFile = Join-Path $Root 'Raport.html'
$LogFile = Join-Path $Root 'Install.log'
$KeyFile = Join-Path $Root 'private\license.dpapi'
$IsApp = ($HostName -eq 'SPSEAPP2')
$PatchHash = '74860C53DAD8D985DC52844344CC5A82CFD04437A3B30C9C45CC6974222073C6'
$Required = @(
  'NET-WCF-Pipe-Activation45','NET-WCF-HTTP-Activation45','NET-WCF-TCP-Activation45',
  'Web-Server','Web-WebServer','Web-Common-Http','Web-Static-Content','Web-Default-Doc',
  'Web-Dir-Browsing','Web-Http-Errors','Web-App-Dev','Web-Asp-Net45','Web-Net-Ext45',
  'Web-ISAPI-Ext','Web-ISAPI-Filter','Web-Health','Web-Http-Logging','Web-Log-Libraries',
  'Web-Request-Monitor','Web-Http-Tracing','Web-Security','Web-Basic-Auth','Web-Windows-Auth',
  'Web-Filtering','Web-Performance','Web-Stat-Compression','Web-Dyn-Compression',
  'WAS','WAS-Process-Model','WAS-Config-APIs'
)
$Phases = @('WindowsFeatures','VCRedist','SqlAlias','Prerequisites','InstallCore','InstallPolishLP','InstallCU')

function Write-Info([string]$Message) {
  $line = ('{0} | {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message)
  Write-Host $line -ForegroundColor Cyan
  if (Test-Path -LiteralPath $Root) { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 }
}
function Get-BootStamp { return (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o') }
function Get-PendingReboot {
  foreach($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
                 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
    if (Test-Path -LiteralPath $k) { return $true }
  }
  $m=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
  if ($null -ne $m) {
    $p=$m.PSObject.Properties['PendingFileRenameOperations']
    if ($null -ne $p -and $null -ne $p.Value -and @($p.Value).Length -gt 0) { return $true }
  }
  return $false
}
function Assert-LocalPath([string]$Path,[string]$Type,[string]$Ext='') {
  $p=$Path.Trim().Trim('"').Trim("'")
  if ($p -notmatch '^[a-zA-Z]:\\[^\\]' -or $p -match '^[a-zA-Z]:\\\\') { throw "Niedozwolona sciezka (tylko dysk lokalny): $p" }
  $drive = $p.Substring(0,1).ToUpperInvariant()
  $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($drive):'"
  if ($null -eq $disk -or [int]$disk.DriveType -ne 3) { throw "Niedozwolony dysk sieciowy/wymienny: $p" }
  $item = Get-Item -LiteralPath $p -ErrorAction Stop
  if ($Type -eq 'File' -and $item.PSIsContainer) { throw "Wymagany plik: $p" }
  if ($Type -eq 'Directory' -and -not $item.PSIsContainer) { throw "Wymagany katalog: $p" }
  if ($Ext -and [IO.Path]::GetExtension($item.FullName) -ine $Ext) { throw "Oczekiwano $Ext : $p" }
  $node = $item
  while ($null -ne $node) {
    if (([int]$node.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Zabroniony link/junction: $($node.FullName)"
    }
    if ($node -is [IO.FileInfo]) { $node=$node.Directory } else { $node=$node.Parent }
  }
  return [string]$item.FullName
}
function Read-Path([string]$Label,[string]$Default,[string]$Type,[string]$Ext='') {
  while ($true) {
    $s=Read-Host "$Label [$Default]"
    if ([string]::IsNullOrWhiteSpace($s)) { $s=$Default }
    try { return (Assert-LocalPath -Path $s -Type $Type -Ext $Ext) }
    catch { Write-Warning $_.Exception.Message }
  }
}
function Save-Json([string]$Path,$Object) {
  $tmp="$Path.tmp"
  $Object | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function New-State {
  return [pscustomobject]@{Server=$HostName; Completed=@(); PauseBoot=''; PauseReason=''; PrereqStarted=$false; Started=(Get-Date -Format 's'); LastError=''}
}
function Read-State {
  if (-not (Test-Path -LiteralPath $StateFile)) { throw 'Brak progress.json. Najpierw wykonaj normalny start.' }
  $s=Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
  if ($s.Server -cne $HostName) { throw 'Plik stanu jest z innego serwera.' }
  foreach($key in @('Completed','PauseBoot','PauseReason','PrereqStarted','LastError')) {
    if (-not $s.PSObject.Properties[$key]) { throw "Niepoprawny plik stanu: $key" }
  }
  return $s
}
function Save-State($s) { Save-Json -Path $StateFile -Object $s }
function Is-Complete($s,[string]$step) { return (@($s.Completed) -contains $step) }
function Mark-Complete($s,[string]$step) {
  if (-not (Is-Complete $s $step)) { $s.Completed=@($s.Completed)+@($step) }
  $s.LastError=''
  Save-State $s
}
function Stop-ForReboot($s,[string]$reason) {
  $s.PauseBoot=Get-BootStamp
  $s.PauseReason=$reason
  Save-State $s
  Write-Warning "STOP: $reason. Uruchom ponownie TYLKO TEN serwer, a nastepnie: .\Install-SPSE-Unattended.ps1 -Resume -AcceptLicenseTerms"
  Write-Report $s
  throw [System.OperationCanceledException]::new('SPSE_REBOOT_REQUIRED')
}
function Assert-NoPendingRestart {
  if (Get-PendingReboot) { throw 'Zalegly restart Windows. Wykonaj reczny restart przed instalacja.' }
}
function Get-Features {
  Import-Module ServerManager -ErrorAction Stop
  $fs=@(Get-WindowsFeature -Name $Required -ErrorAction Stop)
  $names=@($fs | ForEach-Object Name)
  if (@($Required | Where-Object { $_ -notin $names }).Length -gt 0) { throw 'Brak czesci nazw funkcji Windows na tej wersji OS.' }
  return $fs
}
function Get-CorePresent { return (Test-Path -LiteralPath (Join-Path $env:CommonProgramFiles 'microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.dll') -PathType Leaf) }
function Get-LanguagePresent { return (Test-Path -LiteralPath (Join-Path $env:CommonProgramFiles 'microsoft shared\Web Server Extensions\16\TEMPLATE\1045') -PathType Container) }
function Get-VCInstalled {
  $p=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
  if ($null -eq $p) { return $false }
  $value=$p.PSObject.Properties['Installed']
  return ($null -ne $value -and [int]$value.Value -eq 1)
}
function Check-Signature([string]$File) {
  $sig=Get-AuthenticodeSignature -LiteralPath $File
  if ($sig.Status -ne 'Valid') { throw "Brak waznego podpisu cyfrowego ($($sig.Status)): $File" }
}
function Check-Patch([string]$File) {
  $h=(Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
  if ($h -ne $PatchHash) { throw "BLEDNY SHA256 KB5002927! Otrzymany $h, wymagany $PatchHash" }
  Check-Signature $File
}
function With-Iso([string]$File,[scriptblock]$Action) {
  $image=Get-DiskImage -ImagePath $File -ErrorAction SilentlyContinue
  $owned=(-not ($image -and $image.Attached))
  try {
    if ($owned) { Mount-DiskImage -ImagePath $File -ErrorAction Stop | Out-Null }
    $v=Get-DiskImage -ImagePath $File -ErrorAction Stop | Get-Volume -ErrorAction Stop | Where-Object DriveLetter | Select-Object -First 1
    if ($null -eq $v) { throw "Brak litery ISO: $File" }
    $drive=('{0}:\' -f $v.DriveLetter)
    return (& $Action $drive)
  }
  finally {
    if ($owned) { Dismount-DiskImage -ImagePath $File -ErrorAction SilentlyContinue | Out-Null }
  }
}
function Invoke-Exe {
  param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Exe,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ArgumentLine
  )
  # Nie stosuj nazwy $Args: $args jest automatyczna zmienna PowerShell,
  # przez ktora v1.0 wywolywal Start-Process z pustym -ArgumentList.
  if ([string]::IsNullOrWhiteSpace($ArgumentLine)) { throw 'Puste parametry instalatora; przerwano bez uruchomienia EXE.' }
  if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "Brak pliku instalatora: $Exe" }
  Write-Info "Instalator: $([IO.Path]::GetFileName($Exe)); parametry trybu cichego, bez kluczy i hasel."
  $p=Start-Process -FilePath $Exe -ArgumentList $ArgumentLine -PassThru -Wait -ErrorAction Stop
  Write-Info "Kod zakonczenia: $($p.ExitCode)"
  if ([int]$p.ExitCode -notin @(0,3010,1641)) { throw "Instalator zakonczyl sie kodem $($p.ExitCode). Nie kontynuowano." }
  return [int]$p.ExitCode
}
function Set-XmlAttribute([xml]$Document,[string]$Element,[string]$Attr,[string]$Value) {
  $root=$Document.DocumentElement
  $node=$root.SelectSingleNode($Element)
  if ($null -eq $node) { $node=$Document.CreateElement($Element); [void]$root.AppendChild($node) }
  $node.SetAttribute($Attr,$Value)
}
function Set-XmlSetting([xml]$Document,[string]$Id,[string]$Value) {
  $root=$Document.DocumentElement
  $node=$root.SelectSingleNode("Setting[@Id='$Id']")
  if ($null -eq $node) { $node=$Document.CreateElement('Setting'); $node.SetAttribute('Id',$Id); [void]$root.AppendChild($node) }
  $node.SetAttribute('Value',$Value)
}
function Protect-SecretFolder([string]$Dir) {
  New-Item -ItemType Directory -Path $Dir -Force | Out-Null
  $acl=Get-Acl -LiteralPath $Dir
  $acl.SetAccessRuleProtection($true,$false)
  foreach($r in @($acl.Access)) { [void]$acl.RemoveAccessRuleAll($r) }
  $rights=[Security.AccessControl.FileSystemRights]::FullControl
  $inherit=[Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
  $prop=[Security.AccessControl.PropagationFlags]::None
  $type=[Security.AccessControl.AccessControlType]::Allow
  foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')) {
    $id=[Security.Principal.SecurityIdentifier]::new($sid)
    $rule=[Security.AccessControl.FileSystemAccessRule]::new($id,$rights,$inherit,$prop,$type)
    $acl.AddAccessRule($rule)
  }
  Set-Acl -LiteralPath $Dir -AclObject $acl
}
function Write-Report($s) {
  if (-not (Test-Path -LiteralPath $Root)) { return }
  $core=Get-CorePresent
  $lp=Get-LanguagePresent
  $f=@(Get-Features)
  $featureCount=@($f | Where-Object InstallState -eq 'Installed').Length
  $dll=Join-Path $env:CommonProgramFiles 'microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.dll'
  $ver='-'
  if ($core) { $ver=(Get-Item -LiteralPath $dll).VersionInfo.FileVersion }
  $rows=@(
    [pscustomobject]@{Etap='Server';Wynik=$HostName},
    [pscustomobject]@{Etap='Windows';Wynik=$os.Caption},
    [pscustomobject]@{Etap='Role plan';Wynik=$(if ($IsApp) {'ApplicationWithSearch'} else {'WebFrontEndWithDistributedCache'})},
    [pscustomobject]@{Etap='Windows features';Wynik="$featureCount/$($Required.Length)"},
    [pscustomobject]@{Etap='VC++ x64';Wynik=(Get-VCInstalled)},
    [pscustomobject]@{Etap='SharePoint installed';Wynik=$core},
    [pscustomobject]@{Etap='SharePoint DLL version';Wynik=$ver},
    [pscustomobject]@{Etap='Polish templates 1045';Wynik=$lp},
    [pscustomobject]@{Etap='Pending reboot';Wynik=(Get-PendingReboot)},
    [pscustomobject]@{Etap='Completed steps';Wynik=(@($s.Completed) -join ', ')},
    [pscustomobject]@{Etap='Paused';Wynik=$s.PauseReason},
    [pscustomobject]@{Etap='Error';Wynik=$s.LastError},
    [pscustomobject]@{Etap='Farm joined';Wynik='NIE: skrypt NIE wykonuje operacji farmy'}
  )
  $fragment=$rows | ConvertTo-Html -Fragment
  $html=@"
<!doctype html><html lang="pl"><head><meta charset="utf-8"><title>SPSE $HostName</title><style>body{font:15px Segoe UI,Arial;background:#eef2f7;color:#182b41;padding:35px}main{max-width:1100px;margin:auto;background:white;border:1px solid #d6e0eb;border-radius:14px;padding:30px}h1{color:#15517b}table{border-collapse:collapse;width:100%}td,th{padding:12px;text-align:left;border-bottom:1px solid #e4e8ed}th{background:#ecf3f9}</style></head><body><main><h1>SharePoint SE: $HostName</h1><p>Raport LOKALNY • $(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>$fragment<p>Brak klucza licencji, hasel i danych dostepowych.</p></main></body></html>
"@
  [IO.File]::WriteAllText($ReportFile,$html,[Text.UTF8Encoding]::new($false))
  Write-Host "Raport HTML: $ReportFile" -ForegroundColor Green
}
function Check-Media($cfg) {
  $cfg.CoreIso=Assert-LocalPath -Path $cfg.CoreIso -Type File -Ext '.iso'
  $cfg.PlIso=Assert-LocalPath -Path $cfg.PlIso -Type File -Ext '.iso'
  $cfg.Patch=Assert-LocalPath -Path $cfg.Patch -Type File -Ext '.exe'
  if ($cfg.VC) { $cfg.VC=Assert-LocalPath -Path $cfg.VC -Type File -Ext '.exe' }
  if ($cfg.WindowsSource) { $cfg.WindowsSource=Assert-LocalPath -Path $cfg.WindowsSource -Type Directory }
  if ($cfg.CoreIso -ieq $cfg.PlIso) { throw 'ISO SharePoint EN oraz Polish LP musza byc rozne.' }
  Write-Info 'Kontrola SHA256 i podpisu KB5002927 ...'
  Check-Patch $cfg.Patch
  With-Iso $cfg.CoreIso {
    param($drive)
    foreach($file in @('setup.exe','prerequisiteinstaller.exe','Files\SetupSilent\config.xml')) {
      if (-not (Test-Path -LiteralPath (Join-Path $drive $file) -PathType Leaf)) { throw "Brak $file na SharePoint ISO" }
    }
  } | Out-Null
  With-Iso $cfg.PlIso {
    param($drive)
    foreach($file in @('setup.exe','Files\SetupSilent\config.xml')) {
      if (-not (Test-Path -LiteralPath (Join-Path $drive $file) -PathType Leaf)) { throw "Brak $file na Language Pack ISO" }
    }
  } | Out-Null
  if ($IsApp) {
    $volume=Get-Volume -DriveLetter S -ErrorAction Stop
    if ($volume.FileSystem -ne 'NTFS' -or $volume.Size -lt 170GB) { throw 'Na SPSEAPP2 wymagany lokalny dysk S: NTFS >= 170 GiB (plan 200 GB).' }
    if ($volume.SizeRemaining -lt 100GB) { throw 'Za malo wolnego miejsca na S: (minimum 100 GB).' }
    $sdrive=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='S:'"
    if ($null -eq $sdrive -or [int]$sdrive.DriveType -ne 3) { throw 'S: musi byc lokalnym dyskiem stalym.' }
  }
}
function Configure-SqlAlias {
  $path='HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo'
  $want='DBMSSOCN,SPSEDB,1433'
  $found=$null
  if (Test-Path -LiteralPath $path) {
    $prop=Get-ItemProperty -LiteralPath $path -ErrorAction Stop
    $field=$prop.PSObject.Properties['SQL-SPSE']
    if ($null -ne $field) { $found=[string]$field.Value }
  }
  if ($found -and $found -ne $want) { throw "Konflikt aliasu SQL-SPSE: $found, wymagane $want. Nie nadpisano." }
  if (-not $found) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -LiteralPath $path -Name 'SQL-SPSE' -Value $want -PropertyType String -Force | Out-Null
  }
  Write-Info "Lokalny alias SQL-SPSE = $want"
}
function Do-Prerequisites($cfg,$s) {
  With-Iso $cfg.CoreIso {
    param($drive)
    $pr=Join-Path $drive 'prerequisiteinstaller.exe'
    $commandLine=if ($s.PrereqStarted) {'/continue /unattended'} else {'/unattended'}
    $s.PrereqStarted=$true
    Save-State $s
    $code=Invoke-Exe $pr $commandLine
    if ($code -eq 0 -and -not (Get-PendingReboot)) {
      $s.PrereqStarted=$false
      Mark-Complete $s 'Prerequisites'
    } else {
      Stop-ForReboot $s 'Wymagany restart po Microsoft Prerequisite Installer; po restarcie zostanie uzyte /continue.'
    }
  } | Out-Null
}
function Do-Core($cfg,$s) {
  if (Get-CorePresent) { throw 'SharePoint juz obecny przed etapem InstallCore. Zatrzymano bez ponownego instalowania.' }
  if (-not $AcceptLicenseTerms) { throw 'Do instalacji wymagany parametr -AcceptLicenseTerms.' }
  if (-not (Test-Path -LiteralPath $KeyFile -PathType Leaf)) {
    throw 'Brak zaszyfrowanego klucza licencyjnego. Sprawdz, czy uruchamiasz ten sam profil Windows.'
  }
  $secure=(Get-Content -LiteralPath $KeyFile -Raw).Trim() | ConvertTo-SecureString
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  $key=''
  try { $key=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim().ToUpperInvariant() }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
  if ($key -notmatch '^([A-Z0-9]{5}-){4}[A-Z0-9]{5}$') { throw 'Blad odczytu klucza produktu z DPAPI.' }
  $secretDir=Join-Path $Root 'private'
  Protect-SecretFolder $secretDir
  $tempConfig=Join-Path $secretDir 'setup-core.xml'
  try {
    With-Iso $cfg.CoreIso {
      param($drive)
      $template=Join-Path $drive 'Files\SetupSilent\config.xml'
      [xml]$doc=Get-Content -LiteralPath $template -Raw
      Set-XmlAttribute -Document $doc -Element 'PIDKEY' -Attr 'Value' -Value $key
      Set-XmlAttribute -Document $doc -Element 'Display' -Attr 'Level' -Value 'none'
      Set-XmlAttribute -Document $doc -Element 'Display' -Attr 'CompletionNotice' -Value 'no'
      Set-XmlSetting -Document $doc -Id 'SETUP_REBOOT' -Value 'Never'
      Set-XmlSetting -Document $doc -Id 'USINGUIINSTALLMODE' -Value '0'
      Set-XmlSetting -Document $doc -Id 'SETUPTYPE' -Value 'CLEAN_INSTALL'
      if ($IsApp) { Set-XmlAttribute -Document $doc -Element 'DATADIR' -Attr 'Value' -Value 'S:\SearchIndex' }
      $doc.Save($tempConfig)
      $key=$null
      $c=Invoke-Exe (Join-Path $drive 'setup.exe') ('/config "{0}" /IAcceptTheLicenseTerms' -f $tempConfig)
      if (-not (Get-CorePresent)) { throw 'Setup zakonczony, ale nie wykryto Microsoft.SharePoint.dll. Analizuj logi Setup.' }
      Mark-Complete $s 'InstallCore'
      Stop-ForReboot $s 'Po instalacji SharePoint EN wymagany reczny restart.'
    } | Out-Null
  }
  finally {
    $key=$null
    Remove-Item -LiteralPath $tempConfig -Force -ErrorAction SilentlyContinue
    # v1.0 usuwala klucz po dowolnym bledzie Setup. Zachowaj DPAPI na retry.
    if (Is-Complete $s 'InstallCore') {
      Remove-Item -LiteralPath $KeyFile -Force -ErrorAction SilentlyContinue
    }
  }
}
function Do-Language($cfg,$s) {
  if (-not (Get-CorePresent)) { throw 'Brak SharePoint EN; nie instalowano LP.' }
  if (-not $AcceptLicenseTerms) { throw 'Wymagany -AcceptLicenseTerms.' }
  $private=Join-Path $Root 'private'
  Protect-SecretFolder $private
  $tempConfig=Join-Path $private 'setup-language.xml'
  try {
    With-Iso $cfg.PlIso {
      param($drive)
      [xml]$doc=Get-Content -LiteralPath (Join-Path $drive 'Files\SetupSilent\config.xml') -Raw
      Set-XmlAttribute -Document $doc -Element 'Display' -Attr 'Level' -Value 'none'
      Set-XmlAttribute -Document $doc -Element 'Display' -Attr 'CompletionNotice' -Value 'no'
      Set-XmlSetting -Document $doc -Id 'SETUP_REBOOT' -Value 'Never'
      $doc.Save($tempConfig)
      $c=Invoke-Exe (Join-Path $drive 'setup.exe') ('/config "{0}" /IAcceptTheLicenseTerms' -f $tempConfig)
      Mark-Complete $s 'InstallPolishLP'
      Stop-ForReboot $s 'Po instalacji Polish Language Pack wymagany reczny restart.'
    } | Out-Null
  }
  finally { Remove-Item -LiteralPath $tempConfig -Force -ErrorAction SilentlyContinue }
}
function Do-CU($cfg,$s) {
  if (-not (Get-CorePresent)) { throw 'Brak SharePoint SE; nie instalowano CU.' }
  if (-not (Get-LanguagePresent)) { throw 'Nie wykryto polskich szablonow 1045 po restarcie; przerwano CU.' }
  if (-not $AcceptLicenseTerms) { throw 'Wymagany -AcceptLicenseTerms.' }
  Check-Patch $cfg.Patch
  $code=Invoke-Exe $cfg.Patch '/quiet /norestart'
  Mark-Complete $s 'InstallCU'
  Stop-ForReboot $s 'Po KB5002927 wymagany reczny restart. Instalator nie uruchamia PSConfig.'
}

try {
  if ($Audit) {
    if (-not (Test-Path -LiteralPath $StateFile)) { throw 'Brak dotychczasowego stanu instalacji do audytu.' }
    $state=Read-State
    Write-Report $state
    exit 0
  }
  if (-not $Resume) {
    if (Test-Path -LiteralPath $StateFile) { throw 'Istnieje stan poprzedniej proby. Uzyj -Resume; nie wykonuj swiezej instalacji.' }
    Write-Host "=== SPSE UNATTENDED v1.1 | $HostName | BEZ tworzenia farmy ===" -ForegroundColor Green
    Write-Host 'Przed uruchomieniem sprawdz snapshot VM, uprawnienia i dostep do Microsoft Update.'
    $media=Read-Host 'Lokalny katalog nośników [E:\install]'
    if ([string]::IsNullOrWhiteSpace($media)) { $media='E:\install' }
    $media=Assert-LocalPath $media 'Directory'
    $cfg=[pscustomobject]@{
      CoreIso=Read-Path 'SharePoint SE EN ISO' (Join-Path $media 'OfficeServer.iso') 'File' '.iso'
      PlIso=Read-Path 'Polski Language Pack ISO' (Join-Path $media 'ServerLanguagePack.iso') 'File' '.iso'
      Patch=Read-Path 'KB5002927 EXE' (Join-Path $media 'uber-subscription-kb5002927-fullfile-x64-glb.exe') 'File' '.exe'
      VC='';WindowsSource=''
    }
    $vcDefault=Join-Path $media 'vc_redist.x64.exe'
    if (-not (Get-VCInstalled)) { $cfg.VC=Read-Path 'VC++ x64 (brak w rejestrze)' $vcDefault 'File' '.exe' }
    $source=Read-Host 'Opcjonalne lokalne zrodlo Windows Features (folder); ENTER = Windows Update'
    if (-not [string]::IsNullOrWhiteSpace($source)) { $cfg.WindowsSource=Assert-LocalPath $source 'Directory' }
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    Check-Media $cfg
    Write-Host "`nHOST: $HostName | ROLA DOCELOWA: $(if ($IsApp) {'ApplicationWithSearch'} else {'WebFrontEndWithDistributedCache'})"
    Write-Host "ISO EN: $($cfg.CoreIso)`nISO PL: $($cfg.PlIso)`nCU: $($cfg.Patch)`nSQL alias: SQL-SPSE -> SPSEDB:1433"
    if ($IsApp) { Write-Host 'SEARCH: S:\SearchIndex' }
    Write-Host 'Skrypt instaluje lokalne funkcje/komponenty i nie tworzy farmy. Nie uruchamia Restart-Computer.'
    Write-Warning 'Microsoft prerequisiteinstaller.exe /unattended moze sam inicjowac restart; nie da sie tego w pelni zagwarantowac z poziomu skryptu.'
    Write-Host "UWAGA: potwierdzenie jest zgodą na uruchomienie instalatorów i modyfikacje tej VM."
    $confirm=Read-Host ("Wpisz dokladnie INSTALUJ {0}" -f $HostName)
    if ($confirm -cne "INSTALUJ $HostName") { throw 'Brak potwierdzenia. Nie rozpoczeto instalacji.' }
    if (-not $AcceptLicenseTerms) { throw 'Wymagane -AcceptLicenseTerms (po zapoznaniu sie z licencjami Microsoft).' }
    $private=Join-Path $Root 'private'
    Protect-SecretFolder $private
    Write-Host 'Wprowadz klucz produktu SharePoint SE (zostanie zaszyfrowany lokalnie przez DPAPI do czasu etapu Setup):' -ForegroundColor Yellow
    $secureKey=Read-Host 'Product Key' -AsSecureString
    $pKey=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try {
      $keyText=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pKey).Trim().ToUpperInvariant()
      if ($keyText -notmatch '^([A-Z0-9]{5}-){4}[A-Z0-9]{5}$') { throw 'Klucz produktu ma nieprawidlowy format.' }
    } finally {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pKey)
      $keyText=$null
    }
    ConvertFrom-SecureString -SecureString $secureKey | Set-Content -LiteralPath $KeyFile -Encoding ASCII -NoNewline
    Save-Json -Path $ConfigFile -Object $cfg
    $state=New-State
    Save-State $state
  } else {
    $state=Read-State
    $cfg=Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
    if (-not $AcceptLicenseTerms) { throw 'Przy wznowieniu wymagane -AcceptLicenseTerms.' }
    # Migracja blednego znacznika z v1.0: Start-Process nie uruchomil niczego.
    # Nie kasuj stanu, nie powtarzaj WindowsFeatures / SqlAlias, nie uzywaj /continue.
    if ($state.PrereqStarted -and -not (Is-Complete $state 'Prerequisites') -and
        $state.LastError -match '(?i)ArgumentList') {
      Write-Warning 'Odzysk v1.0: wyzerowano PrereqStarted po pustym ArgumentList (instalator Microsoft NIE wystartowal).'
      $state.PrereqStarted=$false
      $state.LastError=''
      Save-State $state
    }
    if ($state.PauseBoot) {
      if ($state.PauseBoot -eq (Get-BootStamp)) { throw "Najpierw uruchom ponownie serwer: $($state.PauseReason)" }
      $state.PauseBoot='';$state.PauseReason=''
      Save-State $state
    }
    Check-Media $cfg
  }
  # Usun pozostalosci tymczasowych konfiguracji po przerwanych proba instalacji.
  # setup-core.xml zawiera jednorazowo klucz produktu; nie jest zapisywany w state.json.
  $private=Join-Path $Root 'private'
  if (Test-Path -LiteralPath $private) {
    foreach($f in @('setup-core.xml','setup-language.xml')) {
      Remove-Item -LiteralPath (Join-Path $private $f) -Force -ErrorAction SilentlyContinue
    }
  }
  if (-not $state.PauseBoot) { Assert-NoPendingRestart }
  Write-Info "Start/wznowienie na $HostName"
  foreach($phase in $Phases) {
    if (Is-Complete $state $phase) {
      if ($phase -eq 'InstallCore' -and -not (Get-CorePresent)) { throw 'Oznaczono InstallCore, ale SharePoint DLL jest nieobecny.' }
      if ($phase -eq 'InstallPolishLP' -and -not (Get-LanguagePresent)) { throw 'Oznaczono InstallPolishLP, ale brakuje szablonow 1045.' }
      continue
    }
    Write-Info "ETAP $phase"
    switch($phase) {
      'WindowsFeatures' {
        $missing=@(Get-Features | Where-Object InstallState -ne 'Installed' | ForEach-Object Name)
        if ($missing.Length -gt 0) {
          $arg=@{Name=$missing;ErrorAction='Stop'}
          if ($cfg.WindowsSource) { $arg['Source']=$cfg.WindowsSource }
          $r=Install-WindowsFeature @arg
          if (-not $r.Success) { throw 'Install-WindowsFeature: Success=False' }
          if (@(Get-Features | Where-Object InstallState -ne 'Installed').Length -gt 0) { throw 'Po instalacji nadal brakuje Windows Features.' }
          Mark-Complete $state $phase
          if ($r.RestartNeeded -ne 'No' -or (Get-PendingReboot)) { Stop-ForReboot $state 'Windows Features wymagaja restartu.' }
        } else { Mark-Complete $state $phase }
      }
      'VCRedist' {
        if (-not (Get-VCInstalled)) {
          if (-not $cfg.VC) { throw 'Brak pakietu VC++ x64.' }
          Check-Signature $cfg.VC
          $exit=Invoke-Exe $cfg.VC '/install /quiet /norestart'
          if (-not (Get-VCInstalled)) { throw 'VC++ nie jest zarejestrowany po instalacji.' }
          Mark-Complete $state $phase
          if ($exit -ne 0 -or (Get-PendingReboot)) { Stop-ForReboot $state 'VC++ wymaga restartu.' }
        } else { Mark-Complete $state $phase }
      }
      'SqlAlias' { Configure-SqlAlias;Mark-Complete $state $phase }
      'Prerequisites' { Do-Prerequisites $cfg $state }
      'InstallCore' { Do-Core $cfg $state }
      'InstallPolishLP' { Do-Language $cfg $state }
      'InstallCU' { Do-CU $cfg $state }
    }
  }
  if (-not (Get-CorePresent) -or -not (Get-LanguagePresent)) { throw 'Koncowa kontrola EN/PL niepowodzenie.' }
  Write-Info 'ZAKONCZONO instalacje binariow EN + PL + KB5002927. Nie polaczono z farma.'
  Write-Report $state
} catch {
  if ($_.Exception -is [System.OperationCanceledException] -and $_.Exception.Message -eq 'SPSE_REBOOT_REQUIRED') {
    Write-Host 'Etap zakonczony. Po recznym restarcie uruchom -Resume -AcceptLicenseTerms.' -ForegroundColor Yellow
    return
  }
  $err=$_.Exception.Message
  Write-Host "BLAD: $err" -ForegroundColor Red
  if (Test-Path -LiteralPath $StateFile) {
    $s=Read-State;$s.LastError=$err;Save-State $s
    try { Write-Report $s } catch { Write-Warning "Raport: $($_.Exception.Message)" }
  }
  throw
}
