param(
    [ValidateSet('Create','Join')][string]$Action,
    [Parameter(Mandatory)][string]$ExpectedHost
)
. "$PSScriptRoot\Common.ps1"
Assert-Elevated
$c = Read-SPSEConfig
Assert-StrictLocalHost -ExpectedHost $ExpectedHost -Config $c
$role = Get-LocalRole -Config $c
$s = Get-State
if (-not ($s.Prerequisites -and $s.Core -and $s.LanguagePack -and $s.Patch)) {
    throw 'Najpierw zakoncz 01-InstallSoftware.ps1 i wszystkie restarty.'
}
if (Test-RebootPending) { throw 'Przed konfiguracja farmy wymagany jest restart.' }
Import-SPSEPowerShell
$existingFarm = $null
try { $existingFarm = Get-SPFarm -ErrorAction Stop } catch { $existingFarm = $null }
if ($existingFarm) {
    throw "Serwer jest juz przylaczony do farmy: $($existingFarm.Name). Nie wykonuje zmian."
}
$localShort = $env:COMPUTERNAME
$primaryShort = $c.PrimaryServer.Split('.')[0]
if ($Action -eq 'Create' -and $localShort -ine $primaryShort) {
    throw "Farma moze byc utworzona tylko na PrimaryServer ($primaryShort)."
}
if ($Action -eq 'Join' -and $localShort -ieq $primaryShort) {
    throw 'Na serwerze PrimaryServer uzyj Create, nie Join.'
}
Write-Host "Dzialanie: $Action, serwer: $env:COMPUTERNAME, role: $role, SQL: $($c.SqlAlias)" -ForegroundColor Cyan
$passphrase = Read-Host 'Passphrase nowej farmy (taka sama dla dolaczanych serwerow)' -AsSecureString

if ($Action -eq 'Create') {
    Write-Host 'Uwaga: tworzona jest NOWA baza SPSE_Config, nie przywracamy starego SP2019 Config DB.' -ForegroundColor Yellow
    $confirmation = Read-Host "Wpisz UTWORZ, aby utworzyc nowa farme na SQL $($c.SqlAlias)"
    if ($confirmation -cne 'UTWORZ') { throw 'Anulowano tworzenie farmy.' }
    $farmCredential = Get-Credential -Message 'Istniejace konto FARM (DOMENA\konto + haslo)'
    New-SPConfigurationDatabase -DatabaseName $c.FarmConfigDb `
        -DatabaseServer $c.SqlAlias `
        -AdministrationContentDatabaseName $c.FarmAdminContentDb `
        -FarmCredentials $farmCredential -Passphrase $passphrase -LocalServerRole $role
} else {
    $confirmation = Read-Host "Wpisz DOLACZ, aby przylaczyc $env:COMPUTERNAME do farmy"
    if ($confirmation -cne 'DOLACZ') { throw 'Anulowano dolaczanie.' }
    Connect-SPConfigurationDatabase -DatabaseName $c.FarmConfigDb `
        -DatabaseServer $c.SqlAlias -Passphrase $passphrase -LocalServerRole $role
}

# Kroki lokalnego provisioningu wymagane po New/Connect-SPConfigurationDatabase.
$flight = Join-Path ${env:CommonProgramFiles} 'microsoft shared\Web Server Extensions\16\CONFIG\SPFlightRawConfig.json'
if ((Test-Path $flight) -and (Get-Command Update-SPFlightsConfigFile -ErrorAction SilentlyContinue)) {
    Update-SPFlightsConfigFile -FilePath $flight
}
Install-SPHelpCollection -All
Initialize-SPResourceSecurity
Install-SPService
Install-SPFeature -AllExistingFeatures
if ($Action -eq 'Create') {
    New-SPCentralAdministration -WindowsAuthProvider $c.CentralAdminAuth -Port ([int]$c.CentralAdminPort)
}
Install-SPApplicationContent
Start-Service -Name SPTimerV4 -ErrorAction Stop
$connected = Get-SPFarm -ErrorAction Stop
Write-Host "OK. Farma: $($connected.Name), serwer: $env:COMPUTERNAME, MinRole: $role" -ForegroundColor Green
Write-Warning 'Nie uruchomiono Farm Configuration Wizard ani nie utworzono nowych Service Applications. Najpierw plan migracji baz SP2019.'
