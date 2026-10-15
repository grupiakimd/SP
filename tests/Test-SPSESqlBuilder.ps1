#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot
$paths=@(
    'v2.3\Collect-SPSESqlLocal.ps1',
    'v2.3\Test-SPSESqlLocal.ps1'
)
foreach($rel in $paths){
    $path=Join-Path $root $rel
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -gt 0){
        throw ("Parser errors in {0}: {1}" -f $rel,(@($parseErrors|ForEach-Object{$_.Message})-join '; '))
    }
    $script=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if($script -match '\$b\.DataSource\s*=' -or $script -match '\$builder\.DataSource\s*='){
        throw ('Regression: unsupported builder dynamic property key in '+$rel)
    }
    if($script -notmatch "\['Data Source'\]"){throw ('Missing canonical ADO.NET key in '+$rel)}
}
# Test runs without SQL Server; validates Windows PowerShell 5.1 builder adapter.
$b=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$b['Data Source']='lpc:.'
$b['Initial Catalog']='master'
$b['Integrated Security']=$true
$b['Connect Timeout']=20
$b['Encrypt']=$false
$b['Application Name']='test'
$cs=$b.ConnectionString
if($cs -notmatch 'Data Source=lpc:\.' -or $cs -notmatch 'Initial Catalog=master'){
    throw ('ConnectionStringBuilder emitted unexpected output: '+$cs)
}
$cn=[System.Data.SqlClient.SqlConnection]::new($cs)
try{
    if($cn.DataSource -ne 'lpc:.'){throw 'Incorrect DataSource after construction'}
}finally{$cn.Dispose()}
Write-Host 'PASS: PowerShell 5.1 builder, parser, connection object (without opening SQL)' -ForegroundColor Green
