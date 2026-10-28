# SPSE Automation v0.3.1 LOCAL-ONLY. Brak PowerShell Remoting i operacji na innych VM.
param(
    [Parameter(Mandatory)][ValidateSet('SPSEAPP1','SPSEAPP2','SPSEWFE1','SPSEWFE2')][string]$ExpectedHost,
    [ValidateSet('Audit','WindowsFeatures','SqlAlias','Prerequisites','InstallCore','InstallPolishLP','InstallCU','CreateFarm','JoinFarm','AuditFarm')]
    [string]$Step='Audit',
    [switch]$AcceptLicenseTerms,
    [string]$WindowsSource=''
)
. "$PSScriptRoot\Common.ps1"
# WAZNE: pierwsze sa blokady; przed nimi nie ma zmian ani polaczen zdalnych.
Assert-Elevated
$c=Read-SPSEConfig
Assert-StrictLocalHost -ExpectedHost $ExpectedHost -Config $c
$role=Get-LocalRole -Config $c
$reports=Join-Path $PSScriptRoot 'reports'
# Folder raportu tworzymy dopiero po walidacji hosta.
New-Item -ItemType Directory -Path $reports -Force | Out-Null
$server=$env:COMPUTERNAME
Write-Host "SPSE v0.3.1 / LOCAL ONLY | $server | $Step | $role" -ForegroundColor Cyan

function Get-AuditInfo {
    $os=Get-CimInstance Win32_OperatingSystem
    $computer=Get-CimInstance Win32_ComputerSystem
    $features=@(Get-SPSEFeatureStatus)
    $missing=@($features | Where-Object InstallState -ne 'Installed' | ForEach-Object Name)
    $disk=Get-PSDrive -Name E -ErrorAction SilentlyContinue
    $media=@(@($c.SharePointIso,$c.LanguagePackIso,$c.PatchExe) | ForEach-Object {
        $p=Join-Path $c.InstallRoot $_
        [pscustomobject]@{Name=$_;Present=(Test-Path -LiteralPath $p -PathType Leaf)}
    })
    $vc=$null
    try { $vc=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction Stop } catch {}
    $vcInstalled=$false
    if ($vc) {
        $vcInstalledProperty=$vc.PSObject.Properties['Installed']
        if ($null -ne $vcInstalledProperty) { $vcInstalled=([int]$vcInstalledProperty.Value -eq 1) }
    }
    $release=0
    try { $release=[int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop).Release } catch {}
    $aliasKey='HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo'
    $aliasValue=''
    try { $aliasValue=[string](Get-ItemProperty -Path $aliasKey -Name $c.SqlAlias -ErrorAction Stop).($c.SqlAlias) } catch {}
    $build=''
    if (Get-SharePointPresent) {
        $path=Join-Path ${env:CommonProgramFiles} 'microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.dll'
        $build=(Get-Item -LiteralPath $path).VersionInfo.FileVersion
    }
    [pscustomobject]@{
        Server=$server; Step='Audit'; Time=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Role=$role; OS=$os.Caption; Domain=$computer.Domain; DomainJoined=$computer.PartOfDomain
        InstalledWindowsFeatures=$features.Count-$missing.Count; RequiredWindowsFeatures=$features.Count
        MissingFeatures=($missing -join ', '); DotNetRelease=$release; VCRedist=$vcInstalled
        SharePointPresent=(Get-SharePointPresent); SharePointFileVersion=$build
        PendingReboot=(Test-RebootPending); LocalDiskE=([bool]$disk)
        SqlTarget=$c.SqlTarget; SqlPort=$c.SqlPort; SqlAlias=$c.SqlAlias; SqlAliasRegistry=$aliasValue
        Media=($media | ForEach-Object { "$($_.Name):$($_.Present)" }) -join '; '
        State=((Get-State) | ConvertTo-Json -Compress)
    }
}
function Publish-LocalAudit {
    $info=Get-AuditInfo
    $json=Join-Path $reports 'LocalAudit.json'
    $html=Join-Path $reports 'LocalAudit.html'
    $info | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $json -Encoding UTF8
    $rows=@($info.PSObject.Properties | ForEach-Object {
        [pscustomobject]@{Pozycja=$_.Name;Wynik=[string]$_.Value}
    })
    $frag=$rows | ConvertTo-Html -Fragment
    $body=@"
<html><head><meta charset="utf-8"><style>body{font:14px Segoe UI,Arial,sans-serif;margin:32px auto;max-width:1100px;color:#213043;background:#f5f8fb}main{background:white;padding:26px;border-radius:10px;border:1px solid #d5dfe9}table{border-collapse:collapse;width:100%}td,th{border:1px solid #dee5eb;padding:10px;word-break:break-word}th{background:#e8eff9;text-align:left}</style></head><body><main><h1>SPSE / audyt lokalny / $server</h1><p>Raport tylko z tego serwera. Nie wykonano zdalnego audytu innych komputerow.</p>$frag</main></body></html>
"@
    [IO.File]::WriteAllText($html,$body,[Text.UTF8Encoding]::new($false))
    $info | Format-List
    Write-Host "Raport HTML: $html" -ForegroundColor Green
}
function Require-InstalledFeatures {
    $missing=@(Get-SPSEFeatureStatus | Where-Object InstallState -ne 'Installed' | ForEach-Object Name)
    if ($missing.Count) { throw "Brakuje funkcji Windows: $($missing -join ', '); wykonaj WindowsFeatures." }
}
function Run-IsoCommand {
    param([string]$IsoName,[string]$ExeRelative,[string]$Arguments='')
    $iso=Join-Path $c.InstallRoot $IsoName
    Test-FilePresent -Path $iso -Label 'ISO'
    $disk=Get-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue
    $ownedMount=(-not ($disk -and $disk.Attached))
    try {
        if ($ownedMount) { Mount-DiskImage -ImagePath $iso -ErrorAction Stop | Out-Null }
        $drive=(Get-DiskImage -ImagePath $iso -ErrorAction Stop | Get-Volume -ErrorAction Stop | Where-Object DriveLetter | Select-Object -First 1).DriveLetter
        if (-not $drive) { throw "Brak litery dysku dla $iso" }
        $exe=Join-Path ("{0}:\" -f $drive) $ExeRelative
        Test-FilePresent -Path $exe -Label 'Plik programu na ISO'
        if ([string]::IsNullOrWhiteSpace($Arguments)) {
            $proc=Start-Process -FilePath $exe -Wait -PassThru
        } else {
            $proc=Start-Process -FilePath $exe -ArgumentList $Arguments -Wait -PassThru
        }
        if ($proc.ExitCode -notin @(0,3010,1641)) { throw "Instalator: exitcode $($proc.ExitCode)" }
        Write-Host "Zakonczono (ExitCode=$($proc.ExitCode)). Restart sprawdz recznie." -ForegroundColor Yellow
        return $proc.ExitCode
    }
    finally {
        if ($ownedMount) { Dismount-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue | Out-Null }
    }
}
function Assert-InstalledStage {
    param([string]$StageName)
    $state=Get-State
    if (-not $state.PSObject.Properties[$StageName] -or -not $state.$StageName) {
        throw "Nie zakonczono etapu $StageName w lokalnym state.json. Zweryfikuj i uruchom odpowiedni etap."
    }
}
function Check-PatchSignature {
    $path=Join-Path $c.InstallRoot $c.PatchExe
    Test-FilePresent -Path $path -Label 'CU'
    $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hash -ne $c.PatchSha256.ToUpperInvariant()) { throw "NIEPRAWIDLOWY SHA256 dla CU: $hash" }
    if ($c.PatchExe -notmatch '(?i)kb5002927') { throw 'Oczekiwany KB5002927. Wymagana rewizja wersji i SHA.' }
    $sig=Get-AuthenticodeSignature -FilePath $path
    if ($sig.Status -ne 'Valid') { throw "Podpis CU nieprawidlowy: $($sig.Status)" }
    return $path
}

switch ($Step) {
 'Audit' { Publish-LocalAudit; break }
 'WindowsFeatures' {
    $os=(Get-CimInstance Win32_OperatingSystem).Caption
    if ($os -notmatch 'Windows Server 2025') { throw "Nie jest Windows Server 2025: $os" }
    Assert-LocalReady
    $missing=@(Get-SPSEFeatureStatus | Where-Object InstallState -ne 'Installed' | ForEach-Object Name)
    if (-not $missing.Count) { Write-Host 'Funkcje Windows juz zainstalowane.' -ForegroundColor Green; break }
    Write-Host "Brakujace funkcje: $($missing -join ', ')"
    Confirm-LocalAction -Phrase "INSTALUJ $server" -Description 'Doinstaluje brakujace lokalne funkcje Windows, bez automatycznego restartu.'
    $args=@{Name=$missing;ErrorAction='Stop'}
    if ($WindowsSource) {
        if (-not (Test-Path -LiteralPath $WindowsSource)) { throw "Brak lokalnego WindowsSource: $WindowsSource" }
        $args['Source']=$WindowsSource
    }
    $r=Install-WindowsFeature @args  # BRAK -ComputerName, BRAK -Restart
    if (-not $r.Success) { throw 'Instalacja funkcji Windows: Success=False.' }
    Write-Host "Funkcje Windows: Success=$($r.Success), RestartNeeded=$($r.RestartNeeded)" -ForegroundColor Yellow
    Publish-LocalAudit; break
 }
 'SqlAlias' {
    Assert-LocalReady
    Confirm-LocalAction -Phrase "ALIAS $server" -Description "Doda lokalny alias $($c.SqlAlias) -> $($c.SqlTarget):$($c.SqlPort)."
    Set-SPSESqlAlias -Config $c | Out-Host
    break
 }
 'Prerequisites' {
    Assert-LocalReady; Require-InstalledFeatures
    Confirm-LocalAction -Phrase "PREREQ $server" -Description 'Uruchomi lokalny, INTERAKTYWNY prerequisiteinstaller.exe firmy Microsoft. Moze wymagac restartu i pobran z Microsoft.'
    # GUI/interactive instead of /unattended; operator controls Microsoft installer and restarts.
    $code=Run-IsoCommand -IsoName $c.SharePointIso -ExeRelative 'prerequisiteinstaller.exe'
    if ($code -ne 0) { throw 'Microsoft Prerequisite Installer zglosil restart. Wykonaj recznie restart i wznow etap.' }
    if (Test-RebootPending) { throw 'Restart wymagany po prerequisiteinstaller.exe; wykonaj go recznie i powtorz AUDIT.' }
    Save-LocalStep -Name 'Prerequisites'
    break
 }
 'InstallCore' {
    Assert-LocalReady; Require-InstalledFeatures; Assert-InstalledStage -StageName 'Prerequisites'
    if (Get-SharePointPresent) { throw 'SharePoint juz jest na dysku; nie wykonuje ponownej instalacji. Zweryfikuj recznie.' }
    if (-not $AcceptLicenseTerms) { throw 'Po zapoznaniu sie z licencja uruchom z -AcceptLicenseTerms.' }
    Confirm-LocalAction -Phrase "SHAREPOINT $server" -Description 'Uruchomi LOKALNY setup.exe SharePoint SE. Klucz licencji podajesz w oknie Microsoft Setup.'
    # Interaktywne Setup: nie zapisujemy klucza produktu do plikow tymczasowych.
    Run-IsoCommand -IsoName $c.SharePointIso -ExeRelative 'setup.exe'
    if (-not (Get-SharePointPresent)) { throw 'Nie wykryto binariow po instalacji. Zweryfikuj komunikaty Setup.' }
    Save-LocalStep -Name 'Core'
    Write-Warning 'Przed PL wykonaj reczny restart systemu nawet jesli Windows go nie wymaga.'
    break
 }
 'InstallPolishLP' {
    Assert-LocalReady; Assert-CoreInstalled; Assert-InstalledStage -StageName 'Core'
    if (-not $AcceptLicenseTerms) { throw 'Po zapoznaniu sie z licencja uzyj -AcceptLicenseTerms.' }
    Confirm-LocalAction -Phrase "POLSKI $server" -Description 'Uruchomi interaktywnie instalator polskiego Language Pack z lokalnego ISO.'
    Run-IsoCommand -IsoName $c.LanguagePackIso -ExeRelative 'setup.exe'
    Save-LocalStep -Name 'LanguagePack'
    Write-Warning 'Wykonaj reczny restart przed CU.'
    break
 }
 'InstallCU' {
    Assert-LocalReady; Assert-CoreInstalled; Assert-InstalledStage -StageName 'Core'; Assert-InstalledStage -StageName 'LanguagePack'
    if (-not $AcceptLicenseTerms) { throw 'Po zapoznaniu sie z warunkami uzyj -AcceptLicenseTerms.' }
    $patchPath=Check-PatchSignature
    Confirm-LocalAction -Phrase "CU $server" -Description 'Zainstaluje zweryfikowana CU lokalnie przez /quiet /norestart. Nie uruchamia PSConfig.'
    $restartCU=Invoke-SPSEInstaller -File $patchPath -Arguments '/quiet /norestart'
    Save-LocalStep -Name 'Patch'
    Write-Warning 'Wykonaj reczny restart. Przed tworzeniem farmy wykonaj audyt instalacji na WSZYSTKICH 4 serwerach.'
    break
 }
 'CreateFarm' {
    if ($server -ine 'SPSEAPP1') { throw 'Tworzenie farmy tylko na SPSEAPP1.' }
    Assert-LocalReady; Assert-CoreInstalled
    Assert-InstalledStage -StageName 'Core'; Assert-InstalledStage -StageName 'LanguagePack'; Assert-InstalledStage -StageName 'Patch'
    Assert-LocalSqlAlias -Config $c
    Write-Host "UWAGA: ten etap zmieni SQL na $($c.SqlTarget):$($c.SqlPort) poprzez $($c.SqlAlias)." -ForegroundColor Yellow
    Confirm-LocalAction -Phrase 'UTWORZ FARME SPSEAPP1' -Description 'Tworzenie baz konfiguracyjnych na SPSEDB i nowej farmy SharePoint.'
    & "$PSScriptRoot\LocalFarm.ps1" -Action Create -ExpectedHost $ExpectedHost
    break
 }
 'JoinFarm' {
    if ($server -ieq 'SPSEAPP1') { throw 'SPSEAPP1 jest hostem inicjujacym farme (CreateFarm).' }
    Assert-LocalReady; Assert-CoreInstalled
    Assert-InstalledStage -StageName 'Core'; Assert-InstalledStage -StageName 'LanguagePack'; Assert-InstalledStage -StageName 'Patch'
    Assert-LocalSqlAlias -Config $c
    Confirm-LocalAction -Phrase "DOLACZ $server" -Description 'Dolaczenie TYLKO tego hosta do nowej farmy na SPSEDB. Modyfikuje SQL/farme.'
    & "$PSScriptRoot\LocalFarm.ps1" -Action Join -ExpectedHost $ExpectedHost
    break
 }
 'AuditFarm' {
    Assert-CoreInstalled
    Import-SPSEPowerShell
    $farm=Get-SPFarm -ErrorAction Stop
    $sp=Get-SPServer | Where-Object { $_.Address.Split('.')[0] -ieq $server } | Select-Object -First 1
    [pscustomobject]@{Server=$server;Farm=$farm.Name;LocalRole=$(if ($sp){$sp.Role}else{'BRAK'});Timestamp=(Get-Date)} | Format-List
    break
 }
}
