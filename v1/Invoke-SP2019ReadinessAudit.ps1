#requires -Version 5.1
<#
.SYNOPSIS
  Audyt farmy SharePoint Server 2019 przed migracja do SharePoint Server Subscription Edition.
.DESCRIPTION
  ODCZYT SharePoint, SQL i (opcjonalnie) serwerow przez CIM/WMI i WinRM.
  Jedyny zapis: lokalne pliki raportu w OutputRoot. Niczego nie aktualizuje.
  Uruchom na serwerze SharePoint 2019 w Windows PowerShell 5.1 (64-bit),
  jako administrator farmy / SharePoint Shell Admin.
.PARAMETER OutputRoot
  Katalog wynikowy (tworzony automatycznie).
.PARAMETER DeepWebScan
  Opcjonalnie zbiera weby, listy, powiazania workflow i aktywne cechy site/web.
  Przy bardzo duzej farmie moze wykonac wiele zapytan do baz zawartosci.
.PARAMETER MaxWebs
  Limit liczby webow w trybie DeepWebScan (domyslnie 2000).
.PARAMETER SkipSQL
  Nie lacz sie z SQL w celu pobrania metadanych i historii backupow.
.PARAMETER SkipRemoteOS
  Nie odpytuj serwerow przez CIM/WMI.
.PARAMETER RemoteWinRM
  Dodatkowo odczytaj uslugi, certyfikaty i bindingi IIS przez WinRM.
  Wymaga dzialajacego WinRM oraz uprawnien na wezłach.
.PARAMETER SqlTrustServerCertificate
  Wylacz sprawdzanie lancucha certyfikatu serwera SQL (tylko przy wewnetrznym,
  w pelni zaufanym polaczeniu; preferowany certyfikat zaufanego CA).
.EXAMPLE
  .\Invoke-SP2019ReadinessAudit.ps1 -OutputRoot C:\SP_Audit
.EXAMPLE
  .\Invoke-SP2019ReadinessAudit.ps1 -OutputRoot D:\AudytSP -DeepWebScan -MaxWebs 5000 -RemoteWinRM
#>
[CmdletBinding()]
param(
    [string]$OutputRoot = 'C:\SP_Audit',
    [switch]$DeepWebScan,
    [ValidateRange(1,1000000)][int]$MaxWebs = 2000,
    [switch]$SkipSQL,
    [switch]$SkipRemoteOS,
    [switch]$RemoteWinRM,
    [switch]$SqlTrustServerCertificate
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Started = Get-Date
$stamp = $script:Started.ToString('yyyyMMdd_HHmmss')
$base = Join-Path $OutputRoot ("SP2019_Audit_{0}_{1}" -f $env:COMPUTERNAME,$stamp)
New-Item -ItemType Directory -Path $base -Force | Out-Null
$script:Base = $base
$script:Data = @{}
$script:Issues = New-Object System.Collections.ArrayList
$script:Errors = New-Object System.Collections.ArrayList
$script:Meta = [ordered]@{
    AuditVersion = '1.0.0'; Started = $script:Started.ToString('s'); Collector = $env:COMPUTERNAME
    Account = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    ReadOnly = $true; DeepWebScan = [bool]$DeepWebScan; MaxWebs = $MaxWebs
    SQLRequested = (-not $SkipSQL); RemoteOSRequested = (-not $SkipRemoteOS)
    SQLInstancesDiscovered = 0; DeepWebLimitReached = $false; DeepScannedWebs = 0
    RemoteWinRMRequested = [bool]$RemoteWinRM
    Sources = 'SharePoint PowerShell, WMI/CIM, SQL sys catalog, msdb backupset'
}

function Scalar($Object, [string]$Property) {
    if ($null -eq $Object) { return $null }
    try {
        $p = $Object.PSObject.Properties[$Property]
        if ($null -eq $p) { return $null }
        $v = $p.Value
        if ($null -eq $v) { return $null }
        if ($v -is [datetime]) { return $v.ToString('s') }
        if ($v -is [System.Guid]) { return $v.ToString() }
        if ($v -is [System.Enum]) { return $v.ToString() }
        if ($v -is [string] -or $v -is [ValueType]) { return $v }
        return [string]$v
    } catch { return $null }
}
function Note([string]$Section, [string]$Message) {
    [void]$script:Errors.Add([pscustomobject]@{ Section=$Section; Time=(Get-Date).ToString('s'); Message=$Message })
    Write-Warning ("{0}: {1}" -f $Section,$Message)
}
function Flag([string]$Level, [string]$Code, [string]$Object, [string]$Message, [string]$Action) {
    [void]$script:Issues.Add([pscustomobject]@{
        Priority=$Level; Code=$Code; Object=$Object; Observation=$Message; Recommendation=$Action
    })
}
function AddRow([string]$Section, $Row) {
    if (-not $script:Data.ContainsKey($Section)) { $script:Data[$Section] = New-Object System.Collections.ArrayList }
    [void]$script:Data[$Section].Add($Row)
}
function TrySection([string]$Name, [scriptblock]$Action) {
    Write-Host ("[AUDYT] {0}" -f $Name) -ForegroundColor Cyan
    try { & $Action } catch { Note $Name $_.Exception.Message }
}
function JoinNames($Items) {
    if ($null -eq $Items) { return '' }
    $v = @($Items | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
    return ($v -join '; ')
}
function HealthField($Item, [string]$FieldName) {
    try { return [string]$Item[$FieldName] } catch { return '' }
}
function Html([object]$Value) {
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

Write-Host ("\nSharePoint 2019 -> SE / AUDYT TYLKO DO ODCZYTU\nWyniki: {0}\n" -f $base) -ForegroundColor Green

# KRYTYCZNE: uruchom tylko w lokalnej powloce SharePoint 2019, NIE na SQL.
if (-not [Environment]::Is64BitProcess) { throw 'Uruchom Windows PowerShell 5.1 w wersji 64-bit.' }
try {
    if (-not (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)) {
        Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction Stop
    }
    $farm = Get-SPFarm -ErrorAction Stop
} catch {
    throw ("Brak dostepu do farmy SharePoint. Uruchom skrypt na WFE/APP jako SP Shell Admin. {0}" -f $_.Exception.Message)
}

# Metadane farmy (bez hasel, kluczy i connection strings).
TrySection 'Farm' {
    $build = Scalar $farm 'BuildVersion'
    $script:Meta.FarmBuild = [string]$build
    $script:Meta.FarmId = [string](Scalar $farm 'Id')
    AddRow 'Farm' ([pscustomobject]@{
        FarmId=(Scalar $farm 'Id'); BuildVersion=$build
        ConfigDB=(Scalar $farm 'Name'); Status=(Scalar $farm 'Status')
        CurrentServer=$env:COMPUTERNAME
    })
}

TrySection 'FarmServers' {
    foreach ($s in @(Get-SPServer)) {
        AddRow 'FarmServers' ([pscustomobject]@{
            Name=(Scalar $s 'Name'); Role=(Scalar $s 'Role'); Status=(Scalar $s 'Status')
            BuildVersion=(Scalar $s 'BuildVersion'); Id=(Scalar $s 'Id')
        })
    }
}

TrySection 'WebApplications_Auth' {
    foreach ($wa in @(Get-SPWebApplication -IncludeCentralAdministration)) {
        $waUrl = [string](Scalar $wa 'Url')
        AddRow 'WebApplications' ([pscustomobject]@{
            Name=(Scalar $wa 'Name'); Url=$waUrl; Id=(Scalar $wa 'Id')
            IsAdministrationWebApplication=(Scalar $wa 'IsAdministrationWebApplication')
            ApplicationPool=$(try { Scalar $wa.ApplicationPool 'Name' } catch { $null })
            UseClaimsAuthentication=(Scalar $wa 'UseClaimsAuthentication')
            AllowAnonymous=(Scalar $wa 'AllowAnonymous')
            ContentDatabaseCount=@($wa.ContentDatabases).Count
            MaxFileSizeMB=(Scalar $wa 'MaximumFileSize')
        })
        try {
            foreach ($entry in $wa.IisSettings.GetEnumerator()) {
                $zone = [string]$entry.Key
                $iis = $entry.Value
                $auth = @()
                foreach ($p in @($iis.AuthenticationProviders)) {
                    if ($null -ne $p) {
                        $auth += ('{0}:{1}' -f $p.GetType().Name,(Scalar $p 'DisplayName'))
                    }
                }
                AddRow 'WebAppZones' ([pscustomobject]@{
                    WebApplication=$waUrl; Zone=$zone; Authentication=(JoinNames $auth)
                    UseSSL=(Scalar $iis 'SecureSocketsLayer'); Anonymous=(Scalar $iis 'AllowAnonymous')
                    DisableKerberos=(Scalar $iis 'DisableKerberos')
                    IisPath=(Scalar $iis 'Path')
                })
            }
        } catch { Note 'WebAppZones' ("{0}: {1}" -f $waUrl,$_.Exception.Message) }
        try {
            foreach ($mp in @(Get-SPManagedPath -WebApplication $wa -ErrorAction Stop)) {
                AddRow 'ManagedPaths' ([pscustomobject]@{
                    WebApplication=$waUrl; Path=(Scalar $mp 'Name'); Type=(Scalar $mp 'Type')
                })
            }
        } catch { Note 'ManagedPaths' ("{0}: {1}" -f $waUrl,$_.Exception.Message) }
    }
    foreach ($a in @(Get-SPAlternateURL)) {
        AddRow 'AlternateAccessMappings' ([pscustomobject]@{
            IncomingUrl=(Scalar $a 'IncomingUrl'); PublicUrl=(Scalar $a 'PublicUrl')
            Zone=(Scalar $a 'Zone'); WebApplication=$(try { Scalar $a.WebApplication 'Url' } catch { $null })
        })
    }
}

TrySection 'ContentDatabases' {
    foreach ($db in @(Get-SPContentDatabase)) {
        $rbs = $null
        try { $rbs = Scalar $db.RemoteBlobStorageSettings 'Enabled' } catch {}
        $d = [pscustomobject]@{
            Name=(Scalar $db 'Name'); Id=(Scalar $db 'Id'); SqlServer=(Scalar $db.Server 'Name')
            WebApplication=(Scalar $db.WebApplication 'Url')
            SiteCollections=(Scalar $db 'CurrentSiteCount')
            WarningSiteCount=(Scalar $db 'WarningSiteCount')
            MaximumSiteCount=(Scalar $db 'MaximumSiteCount')
            NeedsUpgrade=(Scalar $db 'NeedsUpgrade')
            NeedsUpgradeIncludeChildren=(Scalar $db 'NeedsUpgradeIncludeChildren')
            BuildVersion=(Scalar $db 'BuildVersion'); Status=(Scalar $db 'Status')
            RBS_Enabled=$rbs
        }
        AddRow 'ContentDatabases' $d
        if ($d.NeedsUpgradeIncludeChildren -eq $true -or $d.NeedsUpgrade -eq $true) {
            Flag 'HIGH' 'CONTENT_DB_UPGRADE' $d.Name 'Baza raportuje koniecznosc aktualizacji w obecnej farmie.' 'Zbadac stan patchowania/upgrade przed migracja.'
        }
        if ($d.RBS_Enabled -eq $true) {
            Flag 'HIGH' 'RBS' $d.Name 'Wykryto Remote BLOB Storage.' 'Sprawdzic provider RBS, magazyn plikow i procedure migracji BLOB.'
        }
        if ($null -ne $d.MaximumSiteCount -and $null -ne $d.SiteCollections -and
            [double]$d.MaximumSiteCount -gt 0 -and [double]$d.SiteCollections -ge [double]$d.MaximumSiteCount) {
            Flag 'MEDIUM' 'SITE_LIMIT' $d.Name 'Osiagnieto limit site collections dla bazy.' 'Sprawdzic podzial baz i limity nowej farmy.'
        }
    }
}

TrySection 'AllSPDatabases' {
    foreach ($db in @(Get-SPDatabase)) {
        $dbName = [string](Scalar $db 'Name')
        $dbVersion = [string](Scalar $db 'BuildVersion')
        $dbNeedsUpgrade = Scalar $db 'NeedsUpgrade'
        AddRow 'SPDatabases' ([pscustomobject]@{
            Name=$dbName; SqlServer=(Scalar $db.Server 'Name'); Type=(Scalar $db 'TypeName')
            Id=(Scalar $db 'Id'); BuildVersion=$dbVersion
            NeedsUpgrade=$dbNeedsUpgrade; Status=(Scalar $db 'Status')
        })
        if ($dbNeedsUpgrade -eq $true) {
            Flag 'HIGH' 'SP_DATABASE_UPGRADE_PENDING' $dbName 'Baza SharePoint sygnalizuje koniecznosc aktualizacji.' 'Sprawdzic patchowanie i PSConfig na starej farmie przed migracja.'
        }
        try {
            if ($dbVersion -and ([version]$dbVersion -lt [version]'16.0.4351.1000')) {
                Flag 'HIGH' 'SP_DATABASE_BUILD_TOO_OLD' $dbName ('Wersja bazy '+$dbVersion+' jest ponizej minimum dla SE (16.0.4351.1000).') 'Najpierw przeprowadzic wlasciwe aktualizacje farmy zrodlowej.'
            }
        } catch { Note 'SPDatabaseVersion' ($dbName+': nie mozna porownac BuildVersion='+$dbVersion) }
    }
}

TrySection 'ServiceApplications' {
    foreach ($sa in @(Get-SPServiceApplication)) {
        $pool = ''
        try { $pool = Scalar $sa.ApplicationPool 'Name' } catch {}
        AddRow 'ServiceApplications' ([pscustomobject]@{
            Name=(Scalar $sa 'Name'); Type=(Scalar $sa 'TypeName'); DotNetType=$sa.GetType().FullName
            Id=(Scalar $sa 'Id'); Status=(Scalar $sa 'Status'); ApplicationPool=$pool
        })
        $type = [string](Scalar $sa 'TypeName')
        if ($type -match 'Access Services|PerformancePoint') {
            Flag 'HIGH' 'REMOVED_SERVICE' $type 'Usluga usunieta/nieobslugiwana w SE.' 'Zaplanowac zamiennik i migracje funkcji, nie tylko bazy.'
        }
        if ($type -match 'InfoPath') {
            Flag 'HIGH' 'INFOPATH' $type 'InfoPath Forms Services: wsparcie wygaslo 14.07.2026.' 'Zidentyfikowac formularze i przebudowac integracje.'
        }
    }
    foreach ($p in @(Get-SPServiceApplicationProxy)) {
        AddRow 'ServiceAppProxies' ([pscustomobject]@{
            Name=(Scalar $p 'Name'); Type=(Scalar $p 'TypeName'); Id=(Scalar $p 'Id')
            Status=(Scalar $p 'Status')
        })
    }
    try {
        foreach ($g in @(Get-SPServiceApplicationProxyGroup)) {
            AddRow 'ServiceAppProxyGroups' ([pscustomobject]@{
                Name=(Scalar $g 'Name'); Id=(Scalar $g 'Id')
                Proxies=(JoinNames @($g.Proxies | ForEach-Object { $_.Name }))
            })
        }
    } catch { Note 'ServiceAppProxyGroups' $_.Exception.Message }
}

TrySection 'ServiceInstances' {
    foreach ($si in @(Get-SPServiceInstance)) {
        AddRow 'ServiceInstances' ([pscustomobject]@{
            Type=(Scalar $si 'TypeName'); Id=(Scalar $si 'Id')
            Server=(Scalar $si.Server 'Name'); Status=(Scalar $si 'Status')
        })
    }
}

TrySection 'ManagedAccounts' {
    foreach ($a in @(Get-SPManagedAccount)) {
        AddRow 'ManagedAccounts' ([pscustomobject]@{
            UserName=(Scalar $a 'UserName'); AutomaticChange=(Scalar $a 'AutomaticChange')
            Id=(Scalar $a 'Id')
        })
    }
    foreach ($p in @(Get-SPServiceApplicationPool)) {
        AddRow 'ServiceAppPools' ([pscustomobject]@{
            Name=(Scalar $p 'Name'); UserName=(Scalar $p.ProcessAccount 'UserName'); Id=(Scalar $p 'Id')
        })
    }
}

TrySection 'FarmSolutions' {
    foreach ($sol in @(Get-SPSolution)) {
        $deployed = @()
        try { $deployed = @($sol.DeployedWebApplications | ForEach-Object { $_.Url }) } catch {}
        $x = [pscustomobject]@{
            Name=(Scalar $sol 'Name'); Id=(Scalar $sol 'Id')
            Deployed=(Scalar $sol 'Deployed'); ContainsGlobalAssembly=(Scalar $sol 'ContainsGlobalAssembly')
            DeploymentState=(Scalar $sol 'DeploymentState'); DeployedWebApplications=(JoinNames $deployed)
        }
        AddRow 'SolutionsWSP' $x
        if ($x.Deployed -eq $true) {
            Flag 'MEDIUM' 'CUSTOM_WSP' $x.Name 'Zainstalowany pakiet WSP wymaga zgodnosci z SE.' 'Pozyskac pliki zrodlowe i potwierdzic zgodnosc z SE na farmie testowej.'
        }
    }
}

TrySection 'FarmFeatures' {
    foreach ($f in @(Get-SPFeature -Farm -ErrorAction Stop)) {
        AddRow 'FarmFeatures' ([pscustomobject]@{
            DisplayName=(Scalar $f 'DisplayName'); Id=(Scalar $f 'Id')
            Scope=(Scalar $f 'Scope'); RootDirectory=(Scalar $f 'RootDirectory')
        })
    }
}

TrySection 'TimerJobs' {
    foreach ($job in @(Get-SPTimerJob)) {
        $r = [pscustomobject]@{
            Title=(Scalar $job 'Title'); Name=(Scalar $job 'Name')
            Type=$job.GetType().FullName; Id=(Scalar $job 'Id')
            IsDisabled=(Scalar $job 'IsDisabled'); Schedule=(Scalar $job 'Schedule')
            LastRunTime=(Scalar $job 'LastRunTime'); LastRunStatus=(Scalar $job 'LastRunStatus')
            WebApplication=(Scalar $job.WebApplication 'Url')
        }
        AddRow 'TimerJobs' $r
        if ($r.IsDisabled -eq $true) {
            AddRow 'DisabledTimerJobs' $r
        }
        if ($r.LastRunStatus -match 'Failed|Error') {
            Flag 'MEDIUM' 'TIMER_FAILURE' $r.Name ('Timer job: ' + $r.LastRunStatus) 'Sprawdzic logi ULS, zdarzenia i historie zadania.'
        }
    }
}

TrySection 'HealthRules' {
    if (Get-Command Get-SPHealthAnalysisRule -ErrorAction SilentlyContinue) {
        foreach ($rule in @(Get-SPHealthAnalysisRule)) {
            AddRow 'HealthRules' ([pscustomobject]@{
                Name=(Scalar $rule 'Name'); Title=(Scalar $rule 'Title')
                Enabled=(Scalar $rule 'Enabled'); Category=(Scalar $rule 'Category')
                Id=(Scalar $rule 'Id')
            })
        }
    } else { Note 'HealthRules' 'Brak cmdlet Get-SPHealthAnalysisRule; rzeczywiste alerty wymagaja osobnej weryfikacji w Central Administration.' }
}

TrySection 'HealthReports' {
    $reports = $null
    try {
        # Microsoft.SharePoint.Administration.Health.SPHealthReportsList.Local:
        # rzeczywiste raporty Health Analyzer z Central Administration (odczyt).
        $reports = [Microsoft.SharePoint.Administration.Health.SPHealthReportsList]::Local
        if ($null -eq $reports) { throw 'Brak lokalnej listy raportow Health Analyzer.' }
        $q = New-Object Microsoft.SharePoint.SPQuery
        $q.RowLimit = 500
        $q.Query = '<OrderBy><FieldRef Name="Modified" Ascending="FALSE" /></OrderBy>'
        foreach ($item in $reports.GetItems($q)) {
            try {
                AddRow 'HealthReports' ([pscustomobject]@{
                    Title=(HealthField $item 'Title'); Severity=(HealthField $item 'Severity')
                    Category=(HealthField $item 'Category'); FailingServers=(HealthField $item 'FailingServers')
                    FailingServices=(HealthField $item 'FailingServices')
                    Modified=(HealthField $item 'Modified'); Explanation=(HealthField $item 'Explanation')
                    Remedy=(HealthField $item 'Remedy')
                })
            } catch { Note 'HealthReports_Item' $_.Exception.Message }
        }
    } catch { Note 'HealthReports' $_.Exception.Message }
    finally { if ($null -ne $reports) { $reports.Dispose() } }
}

TrySection 'Search' {
    if (-not (Get-Command Get-SPEnterpriseSearchServiceApplication -ErrorAction SilentlyContinue)) {
        Note 'Search' 'Cmdlety Enterprise Search sa niedostepne.'
    } else {
        foreach ($sa in @(Get-SPEnterpriseSearchServiceApplication)) {
            AddRow 'SearchApplications' ([pscustomobject]@{
                Name=(Scalar $sa 'Name'); Id=(Scalar $sa 'Id'); Status=(Scalar $sa 'Status')
            })
            try {
                foreach ($top in @(Get-SPEnterpriseSearchTopology -SearchApplication $sa -ErrorAction Stop)) {
                    AddRow 'SearchTopologies' ([pscustomobject]@{
                        SearchApplication=(Scalar $sa 'Name'); TopologyId=(Scalar $top 'TopologyId')
                        State=(Scalar $top 'State')
                    })
                    try {
                        foreach ($comp in @(Get-SPEnterpriseSearchComponent -SearchTopology $top -ErrorAction Stop)) {
                            AddRow 'SearchComponents' ([pscustomobject]@{
                                SearchApplication=(Scalar $sa 'Name'); TopologyId=(Scalar $top 'TopologyId')
                                Component=(Scalar $comp 'Name'); Type=$comp.GetType().Name
                                Server=(Scalar $comp 'ServerName')
                            })
                        }
                    } catch { Note 'SearchComponents' $_.Exception.Message }
                }
            } catch { Note 'SearchTopologies' $_.Exception.Message }
            try {
                foreach ($cs in @(Get-SPEnterpriseSearchCrawlContentSource -SearchApplication $sa -ErrorAction Stop)) {
                    AddRow 'CrawlSources' ([pscustomobject]@{
                        SearchApplication=(Scalar $sa 'Name'); Name=(Scalar $cs 'Name')
                        Type=(Scalar $cs 'Type'); StartAddresses=(JoinNames $cs.StartAddresses)
                        CrawlState=(Scalar $cs 'CrawlState'); LastCrawlTime=(Scalar $cs 'LastCrawlTime')
                        LastCrawlStatus=(Scalar $cs 'LastCrawlStatus')
                    })
                }
            } catch { Note 'CrawlSources' $_.Exception.Message }
        }
    }
}

TrySection 'SiteCollections' {
    $n = 0
    foreach ($site in @(Get-SPSite -Limit All)) {
        $rootWeb = $null
        try {
            $n++
            $rootWeb = $site.RootWeb
            $sizeMB = $null
            try { $sizeMB = [math]::Round(($site.Usage.Storage / 1MB),2) } catch {}
            AddRow 'SiteCollections' ([pscustomobject]@{
                Url=(Scalar $site 'Url'); Id=(Scalar $site 'Id')
                ContentDB=(Scalar $site.ContentDatabase 'Name'); Template=(Scalar $rootWeb 'WebTemplate')
                Owner=(Scalar $site.Owner 'LoginName'); SecondaryOwner=(Scalar $site.SecondaryContact 'LoginName')
                StorageMB=$sizeMB; LastContentModified=(Scalar $site 'LastContentModifiedDate')
                LockState=(Scalar $site 'LockState'); CompatibilityLevel=(Scalar $site 'CompatibilityLevel')
                QuotaMaxBytes=(Scalar $site.Quota 'StorageMaximumLevel'); QuotaWarningBytes=(Scalar $site.Quota 'StorageWarningLevel')
            })
        } catch { Note 'SiteCollections' $_.Exception.Message }
        finally { if ($null -ne $rootWeb) { $rootWeb.Dispose() }; if ($null -ne $site) { $site.Dispose() } }
    }
    $script:Meta.SiteCollectionInventoryCount = $n
    foreach ($sc in @($script:Data['SiteCollections'] | Where-Object { $_.Template -match 'SPSPERS|SPSMSITEHOST' })) {
        AddRow 'MySites' $sc
    }
}


if ($DeepWebScan) {
    TrySection 'DeepWebScan' {
        $count = 0; $limited = $false
        foreach ($site in @(Get-SPSite -Limit All)) {
            try {
                foreach ($feat in @($site.Features)) {
                    AddRow 'SiteFeatures' ([pscustomobject]@{ SiteCollection=$site.Url; FeatureId=(Scalar $feat 'DefinitionId') })
                }
                if ($count -ge $MaxWebs) { $limited = $true; break }
                foreach ($web in $site.AllWebs) {
                    try {
                        if ($count -ge $MaxWebs) { $limited = $true; break }
                        $count++
                        AddRow 'Webs' ([pscustomobject]@{
                            Url=(Scalar $web 'Url'); Title=(Scalar $web 'Title'); SiteCollection=(Scalar $site 'Url')
                            Template=(Scalar $web 'WebTemplate'); Language=(Scalar $web 'Language')
                            LastItemModifiedDate=(Scalar $web 'LastItemModifiedDate')
                            ListCount=$web.Lists.Count
                        })
                        foreach ($as in @($web.WorkflowAssociations)) {
                            AddRow 'WorkflowAssociations' ([pscustomobject]@{
                                Web=$web.Url; List='(Web)'; Name=(Scalar $as 'Name')
                                Enabled=(Scalar $as 'Enabled'); BaseId=(Scalar $as 'BaseId')
                                Type=(Scalar $as 'BaseTemplate')
                            })
                        }
                        foreach ($list in $web.Lists) {
                            AddRow 'Lists' ([pscustomobject]@{
                                Web=$web.Url; Title=(Scalar $list 'Title'); Id=(Scalar $list 'Id')
                                Template=(Scalar $list 'BaseTemplate'); Hidden=(Scalar $list 'Hidden')
                                ItemCount=(Scalar $list 'ItemCount'); EnableVersioning=(Scalar $list 'EnableVersioning')
                                LastItemModifiedDate=(Scalar $list 'LastItemModifiedDate')
                                ContentTypesEnabled=(Scalar $list 'ContentTypesEnabled')
                            })
                            foreach ($as in @($list.WorkflowAssociations)) {
                                AddRow 'WorkflowAssociations' ([pscustomobject]@{
                                    Web=$web.Url; List=$list.Title; Name=(Scalar $as 'Name')
                                    Enabled=(Scalar $as 'Enabled'); BaseId=(Scalar $as 'BaseId')
                                    Type=(Scalar $as 'BaseTemplate')
                                })
                            }
                        }
                        foreach ($feat in @($web.Features)) {
                            AddRow 'WebFeatures' ([pscustomobject]@{
                                Web=$web.Url; FeatureId=(Scalar $feat 'DefinitionId')
                            })
                        }
                        if ($count % 100 -eq 0) { Write-Host ("  Przeskanowane weby: {0}/{1}" -f $count,$MaxWebs) }
                    } catch { Note 'DeepWebScan_Web' ("{0}: {1}" -f $web.Url,$_.Exception.Message) }
                    finally { if ($null -ne $web) { $web.Dispose() } }
                }
            } catch { Note 'DeepWebScan_Site' $_.Exception.Message }
            finally { if ($null -ne $site) { $site.Dispose() } }
        }
        $script:Meta.DeepScannedWebs = $count
        $script:Meta.DeepWebLimitReached = $limited
        if ($limited) {
            Flag 'UNKNOWN' 'DEEP_SCAN_TRUNCATED' 'Farma' "Osiagnieto limit $MaxWebs webow; skan niekompletny." 'Zweryfikowac liczbe webow i ponowic skan z wiekszym limitem poza godzinami pracy.'
        }
        if (@($script:Data['WorkflowAssociations']).Count -gt 0) {
            Flag 'HIGH' 'LEGACY_WORKFLOWS' 'Farma' 'Wykryto powiazania klasycznych workflow (brak pelnej klasyfikacji silnika).' 'Odrębnie zinwentaryzowac przeplywy 2010/2013 i sprawdzic silnik Workflow Manager.'
        }
    }
} else {
    Flag 'UNKNOWN' 'WORKFLOW_NOT_SCANNED' 'Farma' 'Nie uruchomiono DeepWebScan; listy, workflow i cechy witryn nie zostaly szczegolowo zbadane.' 'Po pierwszym audycie wykonac -DeepWebScan poza godzinami szczytu.'
}

# Zdalne OS po nazwach z SharePoint; SQL moze miec alias/instance, wiec wymaga normalizacji.
$hostsToQuery = @()
foreach ($sr in @($script:Data['FarmServers'])) {
    if ($null -ne $sr -and $sr.Name -and $sr.Name -notmatch '^(?i:Invalid|Unknown)$') {
        $hostsToQuery += ($sr.Name -split '[\\,]')[0]
    }
}
foreach ($db in @($script:Data['SPDatabases'])) {
    if ($null -ne $db -and $db.SqlServer) {
        $hostName = ($db.SqlServer -split '[\\,]')[0]
        if ($hostName -and $hostName -notmatch '^\(') { $hostsToQuery += $hostName }
    }
}
$hostsToQuery = @($hostsToQuery | Where-Object { $_ -ne '' } | Sort-Object -Unique)

if (-not $SkipRemoteOS) {
    TrySection 'OS_Hardware_Disks' {
        foreach ($h in $hostsToQuery) {
            try {
                $os = $null; $cs = $null; $cpu = @(); $disks = @()
                try {
                    $os = Get-CimInstance Win32_OperatingSystem -ComputerName $h -ErrorAction Stop
                    $cs = Get-CimInstance Win32_ComputerSystem -ComputerName $h -ErrorAction Stop
                    $cpu = @(Get-CimInstance Win32_Processor -ComputerName $h -ErrorAction Stop)
                    $disks = @(Get-CimInstance Win32_LogicalDisk -ComputerName $h -Filter 'DriveType=3' -ErrorAction Stop)
                } catch {
                    $os = Get-WmiObject Win32_OperatingSystem -ComputerName $h -ErrorAction Stop
                    $cs = Get-WmiObject Win32_ComputerSystem -ComputerName $h -ErrorAction Stop
                    $cpu = @(Get-WmiObject Win32_Processor -ComputerName $h -ErrorAction Stop)
                    $disks = @(Get-WmiObject Win32_LogicalDisk -ComputerName $h -Filter 'DriveType=3' -ErrorAction Stop)
                }
                AddRow 'OSInventory' ([pscustomobject]@{
                    Computer=$h; OS=$os.Caption; OSVersion=$os.Version; Build=$os.BuildNumber
                    LastBoot=$os.LastBootUpTime; Domain=$cs.Domain; Model=$cs.Model
                    PhysicalRAM_GB=[math]::Round($cs.TotalPhysicalMemory/1GB,2)
                    LogicalCPU=(($cpu | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
                    CPU=(JoinNames @($cpu | Select-Object -ExpandProperty Name))
                })
                foreach ($disk in $disks) {
                    AddRow 'ServerDisks' ([pscustomobject]@{
                        Computer=$h; Drive=$disk.DeviceID
                        CapacityGB=[math]::Round($disk.Size/1GB,2)
                        FreeGB=[math]::Round($disk.FreeSpace/1GB,2)
                        FreePct= $(if ($disk.Size -gt 0) { [math]::Round(100*$disk.FreeSpace/$disk.Size,1) } else { $null })
                    })
                }
            } catch {
                Note 'OSInventory' ("{0}: {1}" -f $h,$_.Exception.Message)
                Flag 'UNKNOWN' 'OS_NOT_REACHABLE' $h 'Nie mozna zdalnie odczytac systemu/dyskow przez CIM/WMI.' 'Sprawdzic DNS, WinRM/WMI, firewall i uprawnienia. W razie potrzeby lokalny raport.'
            }
        }
    }
}

if ($RemoteWinRM) {
    TrySection 'Remote_WinRM_IIS_Certificates' {
        foreach ($h in $hostsToQuery) {
            try {
                $remote = Invoke-Command -ComputerName $h -ErrorAction Stop -ScriptBlock {
                    $svc = @(Get-Service | Where-Object { $_.Name -match '^(SPTimerV4|SPAdminV4|W3SVC|OSearch16|SPSearchHostController|MSSQL|SQLAgent|SQLSERVERAGENT)' } |
                        Select-Object Name,Status,StartType)
                    $certs = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
                        Select-Object Subject,Issuer,Thumbprint,NotBefore,NotAfter,HasPrivateKey)
                    $bind = @()
                    if (Get-Module -ListAvailable -Name WebAdministration) {
                        try {
                            Import-Module WebAdministration -ErrorAction Stop
                            $bind = @(Get-WebBinding | Select-Object protocol,bindingInformation,sslFlags)
                        } catch {}
                    }
                    $dllVersion = $null
                    $dll = Join-Path $env:CommonProgramFiles 'microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.dll'
                    if (Test-Path $dll) { $dllVersion = (Get-Item $dll).VersionInfo.FileVersion }
                    [pscustomobject]@{ Services=$svc; Certificates=$certs; Bindings=$bind; SharePointDllVersion=$dllVersion }
                }
                AddRow 'SPBinaryVersions' ([pscustomobject]@{ Computer=$h; FileVersion=$remote.SharePointDllVersion })
                foreach ($s in @($remote.Services)) {
                    AddRow 'WindowsServices' ([pscustomobject]@{
                        Computer=$h; Name=$s.Name; Status=[string]$s.Status; StartType=[string]$s.StartType
                    })
                }
                foreach ($c in @($remote.Certificates)) {
                    AddRow 'Certificates' ([pscustomobject]@{
                        Computer=$h; Subject=$c.Subject; Issuer=$c.Issuer; Thumbprint=$c.Thumbprint
                        NotBefore=$c.NotBefore; NotAfter=$c.NotAfter; HasPrivateKey=$c.HasPrivateKey
                    })
                    if ($c.NotAfter -and $c.NotAfter -lt (Get-Date).AddDays(90)) {
                        Flag 'MEDIUM' 'CERT_EXPIRY' ("{0}: {1}" -f $h,$c.Subject) 'Certyfikat wygasly lub wygasa w ciagu 90 dni.' 'Zweryfikowac aktywne powiazania IIS oraz odnowienie certyfikatu.'
                    }
                }
                foreach ($b in @($remote.Bindings)) {
                    AddRow 'IISBindings' ([pscustomobject]@{
                        Computer=$h; Protocol=$b.protocol; BindingInformation=$b.bindingInformation; SSLFlags=$b.sslFlags
                    })
                }
            } catch { Note 'RemoteWinRM' ("{0}: {1}" -f $h,$_.Exception.Message) }
        }
    }
}

# Metadane SQL: wylacznie SELECT z widokow sys.* i msdb.dbo.backupset.
function Select-SqlRows([string]$Instance,[string]$Database,[string]$Query) {
    $conn = New-Object System.Data.SqlClient.SqlConnection
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b['Data Source'] = $Instance
    $b['Initial Catalog'] = $Database
    $b['Integrated Security'] = $true
    $b['Connect Timeout'] = 8
    $b['Application Name'] = 'SPSE-Readiness-ReadOnly-Audit'
    $b['Encrypt'] = $true
    $b['TrustServerCertificate'] = [bool]$SqlTrustServerCertificate
    $conn.ConnectionString = $b.ConnectionString
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = 45
        $table = New-Object System.Data.DataTable
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
        [void]$adapter.Fill($table)
        foreach ($dr in $table.Rows) {
            $o = [ordered]@{}
            foreach ($col in $table.Columns) {
                $v = $dr[$col.ColumnName]
                if ($v -is [System.DBNull]) { $v = $null }
                $o[[string]$col.ColumnName] = $v
            }
            [pscustomobject]$o
        }
    } finally { $conn.Dispose() }
}

if (-not $SkipSQL) {
    TrySection 'SQL_Inventory' {
        $instances = @($script:Data['SPDatabases'] | Where-Object { $_.SqlServer } | ForEach-Object { $_.SqlServer } | Sort-Object -Unique)
        $script:Meta.SQLInstancesDiscovered = @($instances).Count
        foreach ($instance in $instances) {
            try {
                $qServer = @'
SELECT @@SERVERNAME AS ServerName,
 CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(100)) AS ProductVersion,
 CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(100)) AS ProductLevel,
 CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(100)) AS ProductUpdateLevel,
 CAST(SERVERPROPERTY('Edition') AS nvarchar(200)) AS Edition,
 CAST(SERVERPROPERTY('Collation') AS nvarchar(200)) AS Collation,
 CAST(SERVERPROPERTY('IsHadrEnabled') AS int) AS IsHadrEnabled,
 CAST(SERVERPROPERTY('IsClustered') AS int) AS IsClustered
'@
                foreach ($r in @(Select-SqlRows $instance 'master' $qServer)) {
                    AddRow 'SQLInstances' ([pscustomobject]@{
                        ConnectionName=$instance; ServerName=$r.ServerName
                        ProductVersion=$r.ProductVersion; ProductLevel=$r.ProductLevel
                        ProductUpdateLevel=$r.ProductUpdateLevel; Edition=$r.Edition
                        Collation=$r.Collation; HADR=$r.IsHadrEnabled; Clustered=$r.IsClustered
                    })
                }
                $qDB = @'
SELECT d.name AS DatabaseName, d.database_id AS DatabaseId,
 d.state_desc AS State, d.recovery_model_desc AS RecoveryModel,
 d.compatibility_level AS CompatibilityLevel, d.page_verify_option_desc AS PageVerify,
 d.is_read_only AS IsReadOnly, d.is_auto_close_on AS AutoClose,
 d.is_auto_shrink_on AS AutoShrink,
 CAST(SUM(CASE WHEN f.type = 0 THEN f.size ELSE 0 END)*8.0/1024 AS decimal(18,2)) AS DataAllocatedMB,
 CAST(SUM(CASE WHEN f.type = 1 THEN f.size ELSE 0 END)*8.0/1024 AS decimal(18,2)) AS LogAllocatedMB,
 CAST(SUM(f.size)*8.0/1024 AS decimal(18,2)) AS TotalAllocatedMB,
 SUM(CASE WHEN f.type = 2 THEN 1 ELSE 0 END) AS FileStreamFiles
FROM sys.databases d LEFT JOIN sys.master_files f ON d.database_id=f.database_id
GROUP BY d.name,d.database_id,d.state_desc,d.recovery_model_desc,d.compatibility_level,
 d.page_verify_option_desc,d.is_read_only,d.is_auto_close_on,d.is_auto_shrink_on
ORDER BY d.name
'@
                foreach ($r in @(Select-SqlRows $instance 'master' $qDB)) {
                    $spName = @($script:Data['SPDatabases'] | Where-Object { $_.SqlServer -eq $instance -and $_.Name -eq $r.DatabaseName }).Count -gt 0
                    $x = [pscustomobject]@{
                        SQLInstance=$instance; Name=$r.DatabaseName; IsSharePointDB=$spName
                        State=$r.State; RecoveryModel=$r.RecoveryModel
                        CompatibilityLevel=$r.CompatibilityLevel; PageVerify=$r.PageVerify
                        IsReadOnly=$r.IsReadOnly; AutoClose=$r.AutoClose; AutoShrink=$r.AutoShrink
                        DataAllocatedMB=$r.DataAllocatedMB; LogAllocatedMB=$r.LogAllocatedMB
                        TotalAllocatedMB=$r.TotalAllocatedMB; FileStreamFiles=$r.FileStreamFiles
                    }
                    AddRow 'SQLDatabases' $x
                    if ($spName -and $r.TotalAllocatedMB -gt 307200) {
                        Flag 'MEDIUM' 'LARGE_DATABASE_300GB' $r.DatabaseName 'Rozmiar zaalokowany przekracza 300 GB (prog planistyczny, nie automatyczna blokada).' 'Oszacowac czas backup/restore, throughput, okno migracji i wzrost danych.'
                    }
                    if ($spName -and $r.State -ne 'ONLINE') {
                        Flag 'HIGH' 'SQL_DB_NOT_ONLINE' $r.DatabaseName ('SQL state: ' + $r.State) 'Usunac problem stanu bazy przed backupem i migracja.'
                    }
                    if ($spName -and $r.FileStreamFiles -gt 0) {
                        Flag 'HIGH' 'FILESTREAM' $r.DatabaseName 'SQL FILESTREAM wykryty - potencjalna zaleznosc RBS.' 'Sprawdzic providera i spojnosc BLOB oraz proces ich przeniesienia.'
                    }
                }
                try {
                    $qBackup = @'
WITH b AS (
 SELECT database_name, type, backup_finish_date, is_copy_only,
        backup_size/1048576.0 AS BackupSizeMB,
        ROW_NUMBER() OVER (PARTITION BY database_name,type ORDER BY backup_finish_date DESC,backup_set_id DESC) AS rn
 FROM msdb.dbo.backupset
 WHERE type IN ('D','I','L')
)
SELECT database_name AS DatabaseName, type AS BackupType,
       backup_finish_date AS LastBackupTime, is_copy_only AS IsCopyOnly,
       CAST(BackupSizeMB AS decimal(18,2)) AS BackupSizeMB
FROM b WHERE rn=1
'@
                    $backupRows = @(Select-SqlRows $instance 'msdb' $qBackup)
                    AddRow 'SQLBackupAuditStatus' ([pscustomobject]@{ SQLInstance=$instance; Access='OK'; Rows=$backupRows.Count })
                    foreach ($b in $backupRows) {
                        AddRow 'SQLBackupHistory' ([pscustomobject]@{
                            SQLInstance=$instance; Name=$b.DatabaseName; Type=$b.BackupType
                            LastBackupTime=$b.LastBackupTime; CopyOnly=$b.IsCopyOnly
                            BackupSizeMB=$b.BackupSizeMB
                        })
                    }
                    foreach ($sdb in @($script:Data['SPDatabases'] | Where-Object { $_.SqlServer -eq $instance })) {
                        $full = @($backupRows | Where-Object { $_.DatabaseName -eq $sdb.Name -and $_.BackupType -eq 'D' } | Sort-Object LastBackupTime -Descending | Select-Object -First 1)
                        if ($full.Count -eq 0) {
                            Flag 'UNKNOWN' 'FULL_BACKUP_NOT_IN_MSDB' $sdb.Name 'Brak historii backupu FULL w msdb (mozliwy backup zewnetrzny).' 'Potwierdzic w narzedziu backupu istnienie SPRAWNEJ kopii i test odtworzenia.'
                        } elseif ([datetime]$full[0].LastBackupTime -lt (Get-Date).AddDays(-7)) {
                            Flag 'MEDIUM' 'FULL_BACKUP_OLD' $sdb.Name 'Ostatni backup FULL z msdb jest starszy niz 7 dni.' 'Zweryfikowac polityke backupow oraz probe odtworzenia.'
                        }
                    }
                } catch {
                    Note 'SQLBackupHistory' ("{0}: {1}" -f $instance,$_.Exception.Message)
                    AddRow 'SQLBackupAuditStatus' ([pscustomobject]@{ SQLInstance=$instance; Access='FAILED'; Rows=$null })
                }
            } catch {
                Note 'SQLInventory' ("{0}: {1}" -f $instance,$_.Exception.Message)
                Flag 'UNKNOWN' 'SQL_NOT_AUDITED' $instance 'Nie udalo sie polaczyc z instancja SQL i odczytac metadanych.' 'Sprawdzic uprawnienia, SQL TLS/certyfikat, port, alias, firewall i DNS.'
            }
        }
    }
}

# Ocena ryzyk nigdy nie stanowi certyfikacji gotowosci do migracji.
TrySection 'MigrationFlags' {
    foreach ($s in @($script:Data['ServiceInstances'])) {
        if ($null -ne $s -and $s.Type -match 'Claims to Windows Token') {
            Flag 'MEDIUM' 'C2WTS' $s.Server 'C2WTS nie wystepuje w SE.' 'Sprawdzic rozwiazania wymagajace delegacji Windows/Kerberos.'
        }
    }
    foreach ($a in @($script:Data['WebApplications'])) {
        if ($null -ne $a -and $a.UseClaimsAuthentication -eq $false) {
            Flag 'HIGH' 'CLASSIC_AUTH' $a.Url 'Klasyczny tryb uwierzytelniania nie jest wspierany w web app SE.' 'Zaplanowac claims auth przed odtworzeniem web application.'
        }
    }
    foreach ($z in @($script:Data['WebAppZones'])) {
        if ($null -ne $z -and $z.Authentication -match 'Basic') {
            Flag 'HIGH' 'BASIC_AUTH' $z.WebApplication 'Wykryto mozliwe Basic Auth; wsparcie wygaslo 14.07.2026.' 'Zweryfikowac providers i zaplanowac inne uwierzytelnianie.'
        }
    }
    Flag 'HIGH' 'SP2019_SUPPORT_ENDED' 'Farma zrodlowa' 'SharePoint Server 2019 osiagnal koniec wsparcia 14.07.2026.' 'Minimalizowac ekspozycje obecnej farmy i priorytetowo zaplanowac migracje SE.'
    $versions = @($script:Data['SPBinaryVersions'] | Where-Object { $_.FileVersion } | ForEach-Object { $_.FileVersion } | Sort-Object -Unique)
    if ($versions.Count -gt 1) {
        Flag 'HIGH' 'SP_PATCH_MISMATCH' 'Farma' 'Rozne wersje Microsoft.SharePoint.dll na wezlach farmy.' 'Zweryfikowac rownomierne patchowanie i stan PSConfig wszystkich serwerow.'
    }
    Flag 'UNKNOWN' 'MANUAL_DEPENDENCIES' 'Farma' 'Audyt API nie potwierdza: zewnetrznych integracji, przeplywow Workflow Manager 2013, niestandardowych web.config, InfoPath, SQL aliasow, load balancer, SMTP, DNS/SPN.' 'Wykonac przeglad manualny i testy funkcjonalne na farmie SE.'
    Flag 'UNKNOWN' 'SE_TEST_REQUIRED' 'Nowa farma SE' 'Test-SPContentDatabase na nowej farmie SE i testy aplikacji nie sa wykonywane na farmie 2019.' 'Po przygotowaniu farmy SE uruchomic Test-SPContentDatabase -Name ... -WebApplication ... bez montowania produkcyjnych baz.'
}

# Eksport: wszystkie sekcje, nawet puste, do CSV UTF8 z BOM (Excel PL).
TrySection 'Export_CSV_JSON_HTML' {
    $sections = @(
        'Farm','FarmServers','OSInventory','ServerDisks','WindowsServices','Certificates','IISBindings','SPBinaryVersions',
        'WebApplications','WebAppZones','AlternateAccessMappings','ManagedPaths',
        'ContentDatabases','SPDatabases','SQLInstances','SQLDatabases','SQLBackupHistory','SQLBackupAuditStatus',
        'ServiceApplications','ServiceAppProxies','ServiceAppProxyGroups','ServiceInstances',
        'ManagedAccounts','ServiceAppPools','SolutionsWSP','FarmFeatures',
        'TimerJobs','DisabledTimerJobs','HealthRules','HealthReports','SearchApplications','SearchTopologies',
        'SearchComponents','CrawlSources','SiteCollections','MySites','Webs','Lists',
        'WebFeatures','SiteFeatures','WorkflowAssociations'
    )
    foreach ($s in $sections) {
        $rows = @($script:Data[$s] | Where-Object { $null -ne $_ })
        $file = Join-Path $base ("{0}.csv" -f $s)
        if ($rows.Count -gt 0) {
            $rows | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8 -Delimiter ';'
        } else {
            ('"BRAK_DANYCH";"Nie znaleziono elementow lub sekcja nie zostala wykonana"') | Set-Content -Path $file -Encoding UTF8
        }
    }
    $script:Issues | Export-Csv (Join-Path $base 'MigrationRisks.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    $script:Errors | Export-Csv (Join-Path $base 'CollectionErrors.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    $script:Meta.Finished = (Get-Date).ToString('s')
    $script:Meta.CollectionErrors = $script:Errors.Count
    $script:Meta.RisksHigh = @($script:Issues | Where-Object { $_.Priority -eq 'HIGH' }).Count
    $script:Meta.RisksMedium = @($script:Issues | Where-Object { $_.Priority -eq 'MEDIUM' }).Count
    $script:Meta.Unknowns = @($script:Issues | Where-Object { $_.Priority -eq 'UNKNOWN' }).Count
    # Punktacja pomocnicza tylko przy kompletnych danych. W innym wypadku BRAK.
    $hasSQL = (-not $SkipSQL) -and (@($script:Data['SQLInstances']).Count -gt 0) -and (@($script:Data['SQLInstances']).Count -ge [int]$script:Meta.SQLInstancesDiscovered)
    $backupOK = (@($script:Data['SQLBackupAuditStatus'] | Where-Object { $_.Access -eq 'OK' }).Count -ge [int]$script:Meta.SQLInstancesDiscovered)
    $complete = ($script:Errors.Count -eq 0 -and $hasSQL -and $backupOK -and $DeepWebScan -and -not $script:Meta.DeepWebLimitReached)
    $script:Meta.ReadinessScore = $(if ($complete) {
        [math]::Max(0,100-20*$script:Meta.RisksHigh-8*$script:Meta.RisksMedium)
    } else { 'NOT_SCORED_INCOMPLETE_EVIDENCE' })

    $dataset = [ordered]@{ Metadata=$script:Meta; Risks=@($script:Issues.ToArray()); Errors=@($script:Errors.ToArray()) }
    foreach ($s in $sections) { $dataset[$s] = @($script:Data[$s] | Where-Object { $null -ne $_ }) }
    $dataset | ConvertTo-Json -Depth 9 | Out-File -FilePath (Join-Path $base 'FullInventory.json') -Encoding utf8

    $css = @'
body{font:14px/1.5 Segoe UI,Arial,sans-serif;background:#f4f6fa;color:#13233b;margin:32px auto;max-width:1200px;padding:0 20px}
h1{font-size:26px}h2{margin-top:34px;border-bottom:2px solid #dde5ee;padding-bottom:7px}
p{color:#38475d}.card{background:#fff;border:1px solid #dde5ee;border-radius:12px;padding:20px;margin:12px 0}
.row{display:flex;gap:14px;flex-wrap:wrap}.metric{background:#edf2f8;padding:12px 18px;border-radius:8px}
.metric strong{display:block;font-size:23px}.scroll{overflow:auto;max-height:540px}table{border-collapse:collapse;width:100%;font-size:12px}
th,td{border-bottom:1px solid #dfe5ef;padding:7px 10px;text-align:left;vertical-align:top;white-space:nowrap}
th{background:#e8eef7;position:sticky;top:0}tr:hover{background:#f1f5fb}
.HIGH{color:#ae1e25;font-weight:700}.MEDIUM{color:#8d5900;font-weight:700}.UNKNOWN{color:#5c6470;font-weight:700}
small{color:#66758b}
'@
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine('<!doctype html><html lang="pl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>SharePoint Readiness Audit</title><style>'+$css+'</style></head><body>')
    [void]$builder.AppendLine('<h1>SharePoint Server 2019 → Subscription Edition</h1>')
    [void]$builder.AppendLine('<p>Raport z odczytu konfiguracji. Brak gwarancji zgodnosci WSP, workflow, InfoPath ani gotowosci migracyjnej.</p>')
    [void]$builder.AppendLine('<div class="card row">')
    foreach ($m in @('Started','Collector','FarmBuild','CollectionErrors','RisksHigh','RisksMedium','Unknowns','ReadinessScore')) {
        [void]$builder.AppendLine(('<div class="metric">{0}<strong>{1}</strong></div>' -f (Html $m),(Html $script:Meta[$m])))
    }
    [void]$builder.AppendLine('</div>')
    [void]$builder.AppendLine('<div class="card"><h2>Ograniczenia</h2><p>Wymagane testy na nowej farmie SE, przeglad customizacji, rozpoznanie Workflow 2013 / InfoPath, walidacja kopii i test odtworzenia. Brak danych NIE oznacza braku problemu.</p></div>')
    $render = @(@{Name='Ryzyka'; Rows=@($script:Issues.ToArray())},@{Name='BledyZbierania'; Rows=@($script:Errors.ToArray())})
    foreach ($s in $sections) { $render += @{Name=$s; Rows=@($script:Data[$s] | Where-Object { $null -ne $_ })} }
    foreach ($group in $render) {
        $rows = @($group.Rows)
        [void]$builder.AppendLine(('<section class="card"><h2>{0} ({1})</h2>' -f (Html $group.Name),$rows.Count))
        if ($rows.Count -eq 0) { [void]$builder.AppendLine('<p>Brak danych / nie dotyczy / brak uprawnien / opcja niewykonana - patrz CollectionErrors.csv.</p>') }
        else {
            [void]$builder.AppendLine('<div class="scroll"><table><thead><tr>')
            $props = @($rows[0].PSObject.Properties | ForEach-Object { $_.Name })
            foreach ($prop in $props) { [void]$builder.AppendLine(('<th>{0}</th>' -f (Html $prop))) }
            [void]$builder.AppendLine('</tr></thead><tbody>')
            $shown = 0
            foreach ($r in $rows) {
                if ($shown -ge 600) { break }
                $shown++
                [void]$builder.AppendLine('<tr>')
                foreach ($prop in $props) {
                    $v = [string]$r.$prop
                    $cls = $(if ($v -in @('HIGH','MEDIUM','UNKNOWN')) { ' class="'+$v+'"' } else { '' })
                    [void]$builder.AppendLine(('<td{0}>{1}</td>' -f $cls,(Html $v)))
                }
                [void]$builder.AppendLine('</tr>')
            }
            [void]$builder.AppendLine('</tbody></table></div>')
            if ($rows.Count -gt 600) { [void]$builder.AppendLine('<p>HTML pokazuje pierwsze 600 rekordow. Pelny wynik w CSV/JSON.</p>') }
        }
        [void]$builder.AppendLine('</section>')
    }
    [void]$builder.AppendLine('<p><small>Zrodla: Microsoft Learn / SharePoint Server Subscription Edition. Raport wykonany bez jakichkolwiek polecen zmieniajacych farme lub bazy danych.</small></p></body></html>')
    [IO.File]::WriteAllText((Join-Path $base 'SPSE_Readiness_Report.html'),$builder.ToString(),(New-Object System.Text.UTF8Encoding($true)))
    $script:Meta | ConvertTo-Json -Depth 6 | Out-File (Join-Path $base 'AuditMetadata.json') -Encoding UTF8
}

try {
    $zip = $base + '.zip'
    Compress-Archive -Path (Join-Path $base '*') -DestinationPath $zip -Force -ErrorAction Stop
    Write-Host ("\nZAKONCZONO: {0}\nArchiwum: {1}" -f $base,$zip) -ForegroundColor Green
} catch { Note 'ZIP' $_.Exception.Message }
Write-Host ("Ryzyka HIGH: {0} | MEDIUM: {1} | UNKNOWN: {2} | Bledy zbierania: {3}" -f $script:Meta.RisksHigh,$script:Meta.RisksMedium,$script:Meta.Unknowns,$script:Errors.Count)
Write-Host 'Raport z audytu zawiera nazwy serwerow, kont, witryn i baz - przechowuj go bezpiecznie.' -ForegroundColor Yellow
