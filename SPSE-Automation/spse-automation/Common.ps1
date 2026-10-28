Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-SPSEConfig {
    param([string]$ConfigJson)
    if (-not $ConfigJson) {
        $p = Join-Path $PSScriptRoot 'config.json'
        if (-not (Test-Path -LiteralPath $p)) { throw "Brak config.json. Skopiuj i uzupelnij config.example.json." }
        $ConfigJson = Get-Content -LiteralPath $p -Raw
    }
    $c = $ConfigJson | ConvertFrom-Json
    # Paths to installation files are NEVER stored in config.json. Prompt per step.
    $expected = @('PatchSha256','SqlAlias','SqlTarget','SqlPort','FarmConfigDb','FarmAdminContentDb',
                  'CentralAdminPort','CentralAdminAuth','PrimaryServer','Servers')
    foreach ($key in $expected) {
        if (-not $c.PSObject.Properties[$key] -or [string]::IsNullOrWhiteSpace([string]$c.$key)) {
            throw "Brak pola: $key"
        }
    }
    if ($c.SqlTarget -like '*.example.local') {
        throw 'Konfiguracja zawiera przykladowe nazwy. Uzupelnij config.json przed uruchomieniem.'
    }
    if ($c.SqlAlias -match '[\\,;:]' -or $c.SqlTarget -match '[,;:]') { throw 'Alias i SQL target bez separatorow portu.' }
    if ([int]$c.SqlPort -lt 1 -or [int]$c.SqlPort -gt 65535) { throw 'Nieprawidlowy port SQL.' }
    if ([int]$c.CentralAdminPort -lt 1 -or [int]$c.CentralAdminPort -gt 65535) { throw 'Nieprawidlowy port CA.' }
    if ($c.CentralAdminAuth -notin @('NTLM','Kerberos')) { throw 'CentralAdminAuth: NTLM lub Kerberos.' }
    $serverNames = @($c.Servers.PSObject.Properties | ForEach-Object { $_.Name })
    if ($serverNames.Length -ne 4) { throw 'Wymagane sa dokladnie 4 serwery SPSE.' }
    $allowed = @('ApplicationWithSearch','WebFrontEndWithDistributedCache')
    foreach ($s in $c.Servers.PSObject.Properties) {
        if ($s.Value -notin $allowed) { throw "Niepoprawna MinRole dla $($s.Name): $($s.Value)" }
    }
    if (-not $c.Servers.PSObject.Properties[$c.PrimaryServer]) { throw 'PrimaryServer musi wystepowac w Servers.' }
    return $c
}

# Only explicitly selected fixed local disks are accepted as installation sources.
# No UNC, no mapped network drives, no relative paths and no remote management.
function Assert-SPSELocalPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('Leaf','Container')][string]$PathType,
        [Parameter(Mandatory)][string]$Label,
        [string]$Extension = ''
    )
    $p = $Path.Trim().Trim('"').Trim("'")
    if ($p -notmatch '^[A-Za-z]:\\' -or $p -match '^[A-Za-z]:\\\\') {
        throw "Wymagana pelna sciezka na lokalnym dysku, bez UNC: $Label"
    }
    $drive = $p.Substring(0,1).ToUpperInvariant()
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($drive):'" -ErrorAction Stop
    if ($null -eq $disk -or [int]$disk.DriveType -ne 3) {
        throw "Sciezka $Label musi lezec na lokalnym dysku stalym (nie SMB/mapped/removable)."
    }
    $item = Get-Item -LiteralPath $p -ErrorAction Stop
    if ($PathType -eq 'Leaf' -and $item.PSIsContainer) { throw "$Label musi wskazywac plik: $p" }
    if ($PathType -eq 'Container' -and -not $item.PSIsContainer) { throw "$Label musi wskazywac katalog: $p" }
    # Reject symlinks/junctions anywhere along the path, including a local junction to a share.
    $part = $item
    while ($null -ne $part) {
        if ($part.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Link/reparse point jest niedozwolony w sciezce: $($part.FullName)"
        }
        $part = $part.Parent
    }
    if ($Extension -and [IO.Path]::GetExtension($item.FullName) -ine $Extension) {
        throw "Oczekiwany plik $Extension dla: $Label"
    }
    return $item.FullName
}

function Read-SPSELocalFilePath {
    param([Parameter(Mandatory)][string]$Label,[Parameter(Mandatory)][string]$Extension)
    for ($attempt=1; $attempt -le 3; $attempt++) {
        $answer=Read-Host "Podaj pelna lokalna sciezke do $Label ($Extension; ENTER = anuluj)"
        if ([string]::IsNullOrWhiteSpace($answer)) { throw 'Anulowano wybor pliku. Nie dokonano instalacji.' }
        try { return Assert-SPSELocalPath -Path $answer -PathType Leaf -Label $Label -Extension $Extension }
        catch { Write-Warning $_.Exception.Message }
    }
    throw "Niepoprawna sciezka $Label po trzech probach. Przerwano."
}

function Get-LocalRole {
    param($Config)
    $localShort = $env:COMPUTERNAME.ToLowerInvariant()
    $fqdn = try { [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName.ToLowerInvariant() } catch { $localShort }
    foreach ($p in $Config.Servers.PSObject.Properties) {
        $candidate = $p.Name.ToLowerInvariant()
        if ($candidate -eq $localShort -or $candidate -eq $fqdn -or $candidate.Split('.')[0] -eq $localShort) {
            return [string]$p.Value
        }
    }
    throw "Serwer $env:COMPUTERNAME nie wystepuje w config.json."
}

function Assert-Elevated {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Uruchom Windows PowerShell 5.1 jako administrator.'
    }
    if (-not [Environment]::Is64BitProcess) { throw 'Wymagany 64-bit Windows PowerShell.' }
    if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Uruchom Windows PowerShell 5.1 (nie PowerShell 7).'}
}

function Get-SPSEStateDirectory {
    $path = Join-Path $env:ProgramData 'SPSE-Automation'
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}
function Get-State {
    $p = Join-Path (Get-SPSEStateDirectory) 'state.json'
    if (Test-Path $p) { return (Get-Content $p -Raw | ConvertFrom-Json) }
    return [pscustomobject]@{ Prerequisites=$false; PrereqStarted=$false; PrereqRestartBoot=''; Core=$false; LanguagePack=$false; Patch=$false }
}
function Save-State {
    param($State)
    $p = Join-Path (Get-SPSEStateDirectory) 'state.json'
    ($State | ConvertTo-Json -Depth 5) | Set-Content -Encoding UTF8 -Path $p
}
function Test-RebootPending {
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
                         'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-Path $key) { return $true }
    }
    $sessionMgr = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    # PendingFileRenameOperations is an OPTIONAL registry value. StrictMode forbids direct access when absent.
    if ($sessionMgr) {
        $pendingProp = $sessionMgr.PSObject.Properties['PendingFileRenameOperations']
        if ($null -ne $pendingProp -and $null -ne $pendingProp.Value -and @($pendingProp.Value).Length -gt 0) {
            return $true
        }
    }
    return $false
}
function Get-SharePointPresent {
    return (Test-Path (Join-Path ${env:CommonProgramFiles} 'microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.dll'))
}
function Import-SPSEPowerShell {
    if (-not (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)) {
        Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction Stop
    }
}
function Invoke-SPSEInstaller {
    param([string]$File, [string]$Arguments)
    Write-Host "Instalator: $File" -ForegroundColor Cyan
    $process = Start-Process -FilePath $File -ArgumentList $Arguments -PassThru -Wait
    if ($process.ExitCode -notin @(0,3010,1641)) {
        throw "Instalator przerwany: exitcode $($process.ExitCode). Plik: $File"
    }
    if ($process.ExitCode -in @(3010,1641)) {
        Write-Warning "Instalator wymaga restartu (exitcode $($process.ExitCode))."
        return $true
    }
    return $false
}
function Invoke-FromIso {
    param([string]$IsoPath, [scriptblock]$Action)
    if (-not (Test-Path -LiteralPath $IsoPath)) { throw "Brak ISO: $IsoPath" }
    $image = Get-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
    $ownedMount = -not ($image -and $image.Attached)
    try {
        if ($ownedMount) { Mount-DiskImage -ImagePath $IsoPath -ErrorAction Stop | Out-Null }
        $drive = (Get-DiskImage -ImagePath $IsoPath | Get-Volume | Where-Object DriveLetter | Select-Object -First 1).DriveLetter
        if (-not $drive) { throw "Brak litery dla ISO: $IsoPath" }
        & $Action ("{0}:\" -f $drive)
    }
    finally {
        if ($ownedMount) { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null }
    }
}
function Set-SPSESqlAlias {
    param($Config)
    # Windows x64 alias. Ustawianie 32-bit aliasu nie jest potrzebne dla SPSE.
    $key = 'HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo'
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    $value = "DBMSSOCN,$($Config.SqlTarget),$([int]$Config.SqlPort)"
    $current = (Get-ItemProperty -Path $key -Name $Config.SqlAlias -ErrorAction SilentlyContinue).($Config.SqlAlias)
    if ($current -and $current -ne $value) {
        throw "Alias $($Config.SqlAlias) juz istnieje z innym celem ($current). Nie nadpisuje bez analizy."
    }
    if (-not $current) { New-ItemProperty -Path $key -Name $Config.SqlAlias -Value $value -PropertyType String -Force | Out-Null }
    return $value
}

# Dokladna lista z Microsoft Learn: wymagane Windows Server roles/features dla SPSE.
function Get-SPSERequiredWindowsFeatures {
    @(
        'NET-WCF-Pipe-Activation45','NET-WCF-HTTP-Activation45','NET-WCF-TCP-Activation45',
        'Web-Server','Web-WebServer','Web-Common-Http','Web-Static-Content',
        'Web-Default-Doc','Web-Dir-Browsing','Web-Http-Errors','Web-App-Dev',
        'Web-Asp-Net45','Web-Net-Ext45','Web-ISAPI-Ext','Web-ISAPI-Filter',
        'Web-Health','Web-Http-Logging','Web-Log-Libraries','Web-Request-Monitor',
        'Web-Http-Tracing','Web-Security','Web-Basic-Auth','Web-Windows-Auth',
        'Web-Filtering','Web-Performance','Web-Stat-Compression','Web-Dyn-Compression',
        'WAS','WAS-Process-Model','WAS-Config-APIs'
    )
}
function Get-SPSEFeatureStatus {
    Import-Module ServerManager -ErrorAction Stop
    $required = @(Get-SPSERequiredWindowsFeatures)
    $features = @(Get-WindowsFeature -Name $required -ErrorAction Stop)
    $foundNames = @($features | ForEach-Object Name)
    $invalid = @($required | Where-Object { $_ -notin $foundNames })
    if ($invalid.Count -gt 0) { throw "Nie znaleziono Windows Features: $($invalid -join ', ')" }
    return @($features | Sort-Object Name | Select-Object Name,DisplayName,InstallState)
}

function Assert-StrictLocalHost {
    param([Parameter(Mandatory)][string]$ExpectedHost, $Config)
    if ($ExpectedHost -cnotmatch '^SPSE(APP[12]|WFE[12])$') { throw 'Niedozwolony oczekiwany hostname.' }
    $detected = [string]$env:COMPUTERNAME
    $cimName = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Name
    if ($detected -ine $ExpectedHost -or $cimName -ine $ExpectedHost) {
        throw "BLOKADA: uruchomiono na $detected / $cimName, skrypt jest tylko dla $ExpectedHost. Nic nie wykonano."
    }
    if (-not $Config.Servers.PSObject.Properties[$ExpectedHost]) {
        throw "Host $ExpectedHost nie jest wpisany do config.json."
    }
    if ($Config.SqlTarget -ine 'SPSEDB' -or [int]$Config.SqlPort -ne 1433) {
        throw 'Nieoczekiwany SQL target. Zmiana SPSEDB:1433 wymaga przegladu konfiguracji.'
    }
}
function Confirm-LocalAction {
    param([string]$Phrase, [string]$Description)
    Write-Host "ZMIANA LOKALNA / $($env:COMPUTERNAME): $Description" -ForegroundColor Yellow
    $entered = Read-Host "Aby wykonac, wpisz dokladnie: $Phrase"
    if ($entered -cne $Phrase) { throw 'Przerwano: brak prawidlowego potwierdzenia.' }
}
function Assert-LocalReady {
    if (Test-RebootPending) { throw 'System wymaga restartu; dokonaj go recznie i powtorz etap.' }
}
function Test-FilePresent {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Brakuje $Label : $Path" }
}
function Save-LocalStep {
    param([string]$Name)
    $state = Get-State
    if (-not $state.PSObject.Properties[$Name]) {
        $state | Add-Member -MemberType NoteProperty -Name $Name -Value $true
    } else { $state.$Name=$true }
    Save-State $state
}
function Assert-CoreInstalled {
    if (-not (Get-SharePointPresent)) { throw 'Nie stwierdzono zainstalowanych binariow SharePoint SE; wykonaj InstallCore.' }
}

function Assert-LocalSqlAlias {
    param($Config)
    $key='HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo'
    $expected="DBMSSOCN,$($Config.SqlTarget),$([int]$Config.SqlPort)"
    $current=$null
    try { $current=(Get-ItemProperty -Path $key -Name $Config.SqlAlias -ErrorAction Stop).($Config.SqlAlias) } catch {}
    if ($current -ne $expected) { throw "Lokalny alias $($Config.SqlAlias) powinien miec $expected, ma: $current. Uruchom osobny etap SqlAlias." }
}
