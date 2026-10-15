#requires -Version 5.1
<#
.SYNOPSIS
  Test read-only local connection to a SQL Server default or named instance.
.DESCRIPTION
  Uses shared memory lpc: and Windows Integrated Authentication on the SQL host.
  Does not modify or back up databases. No secrets are recorded.
.EXAMPLE
  .\Test-SPSESqlLocal.ps1
.EXAMPLE
  .\Test-SPSESqlLocal.ps1 -InstanceName SPDATA
#>
[CmdletBinding()]
param(
    [string]$InstanceName='MSSQLSERVER',
    [ValidateRange(5,180)][int]$ConnectTimeout=20
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($InstanceName -notmatch '^[A-Za-z0-9_-]+$'){throw 'Wpisz MSSQLSERVER dla domyslnej lub sama nazwe instancji nazwanej.'}
$target=if($InstanceName -ieq 'MSSQLSERVER'){'lpc:.'}else{'lpc:.\'+$InstanceName}
$builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source']=$target
$builder['Initial Catalog']='master'
$builder['Integrated Security']=$true
$builder['Connect Timeout']=$ConnectTimeout
$builder['Encrypt']=$false
$builder['Application Name']='SPSE Local SQL preflight'
$connection=[System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
Write-Host ("Probe: {0} (Shared Memory), Windows Integrated Authentication" -f $target)
try {
    $connection.Open()
    $cmd=$connection.CreateCommand()
    try {
        $cmd.CommandTimeout=30
        $cmd.CommandText="SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(80))"
        $version=$cmd.ExecuteScalar()
        if(-not $version){throw 'SQL zwrocil pusty ProductVersion.'}
        Write-Host ('SQL CONNECTED: '+$version) -ForegroundColor Green
        Write-Host 'Mozesz uruchomic Collect-SPSESqlLocal.ps1 bez -InstanceName (domyslna MSSQLSERVER).' -ForegroundColor Green
    } finally { $cmd.Dispose() }
} catch {
    Write-Warning ('SQL preflight FAILED: '+$_.Exception.Message)
    try{
        $svc=Get-Service -Name $(if($InstanceName -ieq 'MSSQLSERVER'){'MSSQLSERVER'}else{'MSSQL$'+$InstanceName}) -ErrorAction Stop
        Write-Host ('SQL Windows Service: '+$svc.Name+' / '+$svc.Status)
    }catch{Write-Warning 'Nie odnaleziono oczekiwanej uslugi SQL. Sprawdz zainstalowane instancje: Get-Service *MSSQL*'}
    throw
} finally { $connection.Dispose() }
