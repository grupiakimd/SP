#requires -Version 5.1
<#
.SYNOPSIS
  LOCAL SQL Server migration inventory, read-only. Run on SQL Server itself.
.DESCRIPTION
  Windows Integrated Authentication via SQL Shared Memory (lpc:), no remote WMI/WinRM.
  Writes one confidential SQLInventory.json to OutputRoot. It never alters SQL data.
  For a named SQL instance use -InstanceName INSTANCE (not server\INSTANCE).
#>
[CmdletBinding()]
param(
    [string]$InstanceName = 'MSSQLSERVER',
    [string]$OutputRoot = 'C:\SPSE_SQL_Audit',
    [ValidateRange(10,180)][int]$ConnectTimeout = 45,
    [ValidateRange(30,600)][int]$CommandTimeout = 120
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if(-not [Environment]::Is64BitProcess){throw 'Uruchom Windows PowerShell 5.1 64-bit.'}
if($InstanceName -notmatch '^[A-Za-z0-9_-]+$'){throw 'InstanceName: podaj tylko nazwe instancji bez nazwy serwera.'}
$server = if ($InstanceName -ieq 'MSSQLSERVER') {'lpc:.'} else {'lpc:.\'+$InstanceName}
$started=Get-Date
$root=Join-Path $OutputRoot ('SQL_Local_'+$started.ToString('yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $root -Force|Out-Null
$issues=New-Object 'System.Collections.Generic.List[object]'
$sections=[ordered]@{
    SQLInstances=@();SQLDatabases=@();SQLBackupHistory=@();SQLBackupAuditStatus=@()
    SQLSettings=@();SQLStorage=@();OSInventory=@();ServerDisks=@()
}
$connection=$null
function Capture-Section([string]$Name,[scriptblock]$Action){
    try {& $Action} catch {
        $script:issues.Add([pscustomobject]@{Section=$Name;Message=$_.Exception.Message})
        Write-Warning ("{0}: {1}" -f $Name,$_.Exception.Message)
    }
}
function Query([string]$Sql,[string]$Database='master'){
    $b=New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b.DataSource=$server
    $b.InitialCatalog=$Database
    $b.IntegratedSecurity=$true
    $b.ConnectTimeout=$ConnectTimeout
    $b.Encrypt=$false   # Shared Memory; SQL may still enforce encryption per server policy.
    $b.ApplicationName='SPSE ReadOnly Local SQL Audit v2.3'
    $cn=New-Object System.Data.SqlClient.SqlConnection($b.ConnectionString)
    $cmd=$null
    try{
        $cn.Open()
        $cmd=$cn.CreateCommand()
        $cmd.CommandText=$Sql
        $cmd.CommandTimeout=$CommandTimeout
        $reader=$cmd.ExecuteReader()
        try{
            while($reader.Read()){
                $row=[ordered]@{}
                for($ix=0;$ix -lt $reader.FieldCount;$ix++){
                    $field=$reader.GetName($ix)
                    $row[$field]=if($reader.IsDBNull($ix)){$null}else{
                        $value=$reader.GetValue($ix)
                        if($value -is [datetime]){$value.ToString('s')}else{$value}
                    }
                }
                [pscustomobject]$row
            }
        }finally{$reader.Close()}
    }finally{
        if($null -ne $cmd){$cmd.Dispose()}
        $cn.Dispose()
    }
}
Capture-Section 'SQLInstances' {
    $q=@'
SELECT CAST(SERVERPROPERTY('ServerName') AS nvarchar(256)) AS ServerName,
 CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(80)) AS ProductVersion,
 CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(80)) AS ProductLevel,
 CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(80)) AS ProductUpdateLevel,
 CAST(SERVERPROPERTY('Edition') AS nvarchar(256)) AS Edition,
 CAST(SERVERPROPERTY('Collation') AS nvarchar(256)) AS Collation,
 CAST(SERVERPROPERTY('IsHadrEnabled') AS int) AS HADR,
 CAST(SERVERPROPERTY('IsClustered') AS int) AS Clustered,
 CAST(SERVERPROPERTY('EngineEdition') AS int) AS EngineEdition;
'@
    $rows=@(Query $q)
    if($rows.Count -eq 0){throw 'Brak odpowiedzi od instancji SQL.'}
    foreach($row in $rows){
        $sections.SQLInstances+= [pscustomobject]@{
            ConnectionName=[string]$row.ServerName;ServerName=[string]$row.ServerName
            ProductVersion=$row.ProductVersion;ProductLevel=$row.ProductLevel
            ProductUpdateLevel=$row.ProductUpdateLevel;Edition=$row.Edition
            Collation=$row.Collation;HADR=$row.HADR;Clustered=$row.Clustered
            EngineEdition=$row.EngineEdition
        }
    }
}
Capture-Section 'SQLDatabases' {
    $q=@'
SELECT d.name AS Name, d.state_desc AS State, d.recovery_model_desc AS RecoveryModel,
 d.compatibility_level AS CompatibilityLevel, d.page_verify_option_desc AS PageVerify,
 d.is_read_only AS IsReadOnly,d.is_auto_close_on AS AutoClose,
 d.is_auto_shrink_on AS AutoShrink,
 CAST(COALESCE(SUM(CASE WHEN f.type=0 THEN CAST(f.size AS bigint) ELSE 0 END),0)*8.0/1024 AS decimal(19,2)) AS DataAllocatedMB,
 CAST(COALESCE(SUM(CASE WHEN f.type=1 THEN CAST(f.size AS bigint) ELSE 0 END),0)*8.0/1024 AS decimal(19,2)) AS LogAllocatedMB,
 CAST(COALESCE(SUM(CAST(f.size AS bigint)),0)*8.0/1024 AS decimal(19,2)) AS TotalAllocatedMB,
 SUM(CASE WHEN f.type=2 THEN 1 ELSE 0 END) AS FileStreamFiles
FROM sys.databases d LEFT JOIN sys.master_files f ON f.database_id=d.database_id
GROUP BY d.name,d.state_desc,d.recovery_model_desc,d.compatibility_level,
 d.page_verify_option_desc,d.is_read_only,d.is_auto_close_on,d.is_auto_shrink_on
ORDER BY d.name;
'@
    $sections.SQLDatabases=@(Query $q)
}
Capture-Section 'SQLBackupHistory' {
    $q=@'
;WITH b AS(
 SELECT database_name AS Name, type AS Type, backup_finish_date AS LastBackupTime,
 is_copy_only AS CopyOnly, CAST(backup_size/1048576.0 AS decimal(19,2)) AS BackupSizeMB,
 ROW_NUMBER() OVER(PARTITION BY database_name,type ORDER BY backup_finish_date DESC,backup_set_id DESC) AS rn
 FROM msdb.dbo.backupset
 WHERE backup_finish_date IS NOT NULL
)
SELECT Name,Type,LastBackupTime,CopyOnly,BackupSizeMB FROM b WHERE rn=1 ORDER BY Name,Type;
'@
    $sections.SQLBackupHistory=@(Query $q 'msdb')
    $sections.SQLBackupAuditStatus=@([pscustomobject]@{
        Access='OK';Rows=$sections.SQLBackupHistory.Count
    })
}
Capture-Section 'SQLSettings' {
    $q=@'
SELECT name AS SettingName, CAST(value_in_use AS bigint) AS ValueInUse
FROM sys.configurations
WHERE name IN ('max server memory (MB)','min server memory (MB)','max degree of parallelism',
 'cost threshold for parallelism','backup compression default','remote admin connections',
 'optimize for ad hoc workloads')
ORDER BY name;
'@
    $sections.SQLSettings=@(Query $q)
}
Capture-Section 'SQLStorage' {
    $q=@'
SELECT DB_NAME(mf.database_id) AS DatabaseName, mf.type_desc AS FileType,
 CAST(mf.size*8.0/1024 AS decimal(19,2)) AS AllocatedMB,
 mf.growth AS GrowthValue, mf.is_percent_growth AS GrowthIsPercent,
 CASE WHEN mf.is_percent_growth=0 THEN CAST(mf.growth*8.0/1024 AS decimal(19,2)) ELSE NULL END AS GrowthMB,
 mf.max_size AS MaxSizePages, mf.state_desc AS State
FROM sys.master_files mf
ORDER BY mf.database_id,mf.file_id;
'@
    # Deliberately omit physical file paths for this inventory.
    $sections.SQLStorage=@(Query $q)
}
Capture-Section 'OSInventory' {
    $os=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $cs=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $sections.OSInventory=@([pscustomobject]@{
        Computer=$env:COMPUTERNAME;OS=$os.Caption
        OSVersion=$os.Version;PhysicalRAM_GB=[math]::Round(($cs.TotalPhysicalMemory/1GB),2)
        LogicalCPU=$cs.NumberOfLogicalProcessors
    })
}
Capture-Section 'ServerDisks' {
    $disks=@(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)
    $sections.ServerDisks=@(foreach($d in $disks){
        [pscustomobject]@{
            Computer=$env:COMPUTERNAME;Drive=$d.DeviceID
            CapacityGB=[math]::Round($d.Size/1GB,2)
            FreeGB=[math]::Round($d.FreeSpace/1GB,2)
            FreePct=$(if($d.Size -gt 0){[math]::Round(100*$d.FreeSpace/$d.Size,1)}else{$null})
        }
    })
}
if($sections.SQLInstances.Count -eq 0){throw 'Nie udalo sie odczytac lokalnej instancji SQL. Sprawdz nazwe instancji i lokalne polaczenie lpc:.'}
$raw=[ordered]@{
    Schema='SPSE-SQL-LOCAL-v1'
    Metadata=[ordered]@{
        Source='LOCAL_SQL_SHARED_MEMORY'
        ExecutedAt=$started.ToString('s')
        FinishedAt=(Get-Date).ToString('s')
        Host=$env:COMPUTERNAME
        InstanceName=$InstanceName
        ConnectionMethod=$server
        SQLStatus= $(if($issues.Count -eq 0){'OK'}else{'PARTIAL'})
        Errors=$issues.Count
    }
    SQLInstances=@($sections.SQLInstances)
    SQLDatabases=@($sections.SQLDatabases)
    SQLBackupHistory=@($sections.SQLBackupHistory)
    SQLBackupAuditStatus=@($sections.SQLBackupAuditStatus)
    SQLSettings=@($sections.SQLSettings)
    SQLStorage=@($sections.SQLStorage)
    OSInventory=@($sections.OSInventory)
    ServerDisks=@($sections.ServerDisks)
    Errors=@($issues.ToArray())
}
$target=Join-Path $root 'SQLInventory.json'
$raw|ConvertTo-Json -Depth 8|Out-File -LiteralPath $target -Encoding UTF8 -ErrorAction Stop
Write-Host ('LOCAL SQL AUDIT: '+$target) -ForegroundColor Green
Write-Host ('State: '+$raw.Metadata.SQLStatus+'; errors: '+$raw.Metadata.Errors)
Write-Warning 'SQLInventory.json contains real database names and local infrastructure information. Transfer securely. Do NOT publish.'
