#requires -Version 5.1
<#
.SYNOPSIS
  Read-only inventory of an existing SharePoint SE pilot farm.
.DESCRIPTION
  Designed for an already configured SingleServerFarm or multi-server SE farm.
  Produces a PRIVATE local HTML dashboard and JSON. No upload, no backup,
  no migration and no SharePoint configuration changes.
.EXAMPLE
  .\Get-SPSEPilotReadiness.ps1 -OutputRoot "C:\SPSE_Pilot"
#>
[CmdletBinding()]
param([string]$OutputRoot='C:\SPSE_Pilot')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if(-not [Environment]::Is64BitProcess){throw 'Run 64-bit Windows PowerShell 5.1 on a SharePoint SE server.'}
if(-not (Get-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)){
    Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction Stop
}
function Get-Value($item,[string]$property){
    if($null -eq $item){return $null}
    try{
        $p=$item.PSObject.Properties[$property]
        if($null -ne $p){return $p.Value}
    }catch{}
    return $null
}
function Html($value){return [Net.WebUtility]::HtmlEncode([string]$value)}
function Html-Table([string]$name,$items,[string[]]$fields){
    $rows=@($items|Where-Object {$null -ne $_})
    $buffer=New-Object 'System.Collections.Generic.List[string]'
    [void]$buffer.Add(('<section><h2>'+(Html $name)+' <small>('+ $rows.Count +')</small></h2>'))
    if($rows.Count -eq 0){
        [void]$buffer.Add('<p>Brak wynikow (albo odczyt sekcji nie powiodl sie).</p>')
    }else{
        [void]$buffer.Add('<div class="scroll"><table><thead><tr>')
        foreach($f in $fields){[void]$buffer.Add('<th>'+(Html $f)+'</th>')}
        [void]$buffer.Add('</tr></thead><tbody>')
        foreach($item in $rows){
            [void]$buffer.Add('<tr>')
            foreach($f in $fields){[void]$buffer.Add('<td>'+(Html (Get-Value $item $f))+'</td>')}
            [void]$buffer.Add('</tr>')
        }
        [void]$buffer.Add('</tbody></table></div>')
    }
    [void]$buffer.Add('</section>')
    return ($buffer -join [Environment]::NewLine)
}
$issues=New-Object 'System.Collections.Generic.List[object]'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$outDir=Join-Path $OutputRoot ('SE_Pilot_'+$stamp)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$inventory=[ordered]@{
    Schema='SPSE-PILOT-READINESS-v1'
    CollectedAt=(Get-Date).ToString('s')
    Farm=@()
    Servers=@()
    WebApplications=@()
    ContentDatabases=@()
    ManagedPaths=@()
    SiteCollections=@()
    ServiceApplications=@()
    Errors=@()
}
function Capture([string]$section,[scriptblock]$block){
    try{& $block}catch{
        $script:issues.Add([pscustomobject]@{
            Section=$section
            Message=$_.Exception.Message
        })
        Write-Warning ('Nie udalo sie odczytac sekcji '+$section+'. Szczegoly tylko lokalnie.')
    }
}
Capture 'Farm' {
    $farm=Get-SPFarm -ErrorAction Stop
    $inventory.Farm=@([pscustomobject]@{
        BuildVersion=[string]$farm.BuildVersion
        FarmId=[string]$farm.Id
    })
}
Capture 'Servers' {
    $inventory.Servers=@(Get-SPServer -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Address=[string]$_.Address
            Role=[string]$_.Role
            Status=[string]$_.Status
        }
    })
}
Capture 'WebApplicationsAndDatabases' {
    $webApps=@(Get-SPWebApplication -ErrorAction Stop)
    $inventory.WebApplications=@(foreach($wa in $webApps){
        [pscustomobject]@{
            Url=[string]$wa.Url
            Claims=[bool](Get-Value $wa 'UseClaimsAuthentication')
            Name=[string]$wa.Name
        }
    })
    foreach($wa in $webApps){
        try{
            $inventory.ContentDatabases+=@(Get-SPContentDatabase -WebApplication $wa -ErrorAction Stop |
                ForEach-Object {
                    [pscustomobject]@{
                        Name=[string]$_.Name
                        SqlServer=[string]$_.Server
                        WebApplication=[string]$wa.Url
                        CurrentSiteCount=[int]$_.CurrentSiteCount
                        Status=[string]$_.Status
                    }
                })
        }catch{
            $issues.Add([pscustomobject]@{Section='ContentDatabases';Message=$_.Exception.Message})
        }
        try {
            $inventory.ManagedPaths+=@(Get-SPManagedPath -WebApplication $wa -ErrorAction Stop |
                ForEach-Object {
                    [pscustomobject]@{
                        WebApplication=[string]$wa.Url
                        Name=[string]$_.Name
                        Type=[string]$_.Type
                    }
                })
        }catch{
            $issues.Add([pscustomobject]@{Section='ManagedPaths';Message=$_.Exception.Message})
        }
        try{
            $inventory.SiteCollections+=@(Get-SPSite -WebApplication $wa -Limit All -ErrorAction Stop |
                ForEach-Object {
                    try{
                        [pscustomobject]@{
                            Url=[string]$_.Url
                            SiteId=[string]$_.Id
                            Database=[string]$_.ContentDatabase.Name
                        }
                    }finally{$_.Dispose()}
                })
        }catch{
            $issues.Add([pscustomobject]@{Section='SiteCollections';Message=$_.Exception.Message})
        }
    }
}
Capture 'ServiceApplications' {
    $inventory.ServiceApplications=@(Get-SPServiceApplication -ErrorAction Stop |
        ForEach-Object {
            [pscustomobject]@{
                DisplayName=[string]$_.DisplayName
                TypeName=[string]$_.TypeName
                Status=[string]$_.Status
            }
        })
}
$inventory.Errors=@($issues.ToArray())
$json=Join-Path $outDir 'SPSE_Pilot_PRIVATE.json'
$inventory | ConvertTo-Json -Depth 9 | Out-File -LiteralPath $json -Encoding UTF8 -ErrorAction Stop
$blocks=New-Object 'System.Collections.Generic.List[string]'
[void]$blocks.Add(Html-Table 'Farma' $inventory.Farm @('BuildVersion','FarmId'))
[void]$blocks.Add(Html-Table 'Serwery' $inventory.Servers @('Address','Role','Status'))
[void]$blocks.Add(Html-Table 'Web Applications' $inventory.WebApplications @('Url','Name','Claims'))
[void]$blocks.Add(Html-Table 'Content Databases' $inventory.ContentDatabases @('Name','SqlServer','WebApplication','CurrentSiteCount','Status'))
[void]$blocks.Add(Html-Table 'Managed Paths' $inventory.ManagedPaths @('WebApplication','Name','Type'))
[void]$blocks.Add(Html-Table 'Site Collections' $inventory.SiteCollections @('Url','Database','SiteId'))
[void]$blocks.Add(Html-Table 'Service Applications' $inventory.ServiceApplications @('DisplayName','TypeName','Status'))
[void]$blocks.Add(Html-Table 'Bledy kolektora' $inventory.Errors @('Section','Message'))
$head=@'
<!doctype html><html lang="pl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>SharePoint SE - pilot</title><style>
*{box-sizing:border-box}body{margin:0;background:#f4f7fb;color:#1a3048;font:14px/1.5 system-ui,Segoe UI,Arial}
header{background:#142a42;color:white;padding:26px max(calc((100vw - 1100px)/2),20px)}
main{max-width:1100px;margin:auto;padding:18px}section{background:#fff;border:1px solid #dce4ed;
border-radius:12px;padding:20px;margin:0 0 16px}h1{margin:0}h2{font-size:19px;margin:0 0 12px}
small{color:#6b7e92}header p{color:#c0d2e5}
.scroll{overflow:auto;max-height:440px}table{border-collapse:collapse;width:100%;font-size:12px}
th,td{text-align:left;border-bottom:1px solid #e8eef5;padding:9px;vertical-align:top;overflow-wrap:anywhere}
th{background:#eaf1f8}p.warn{background:#fff2d8;border-left:4px solid #c9882c;padding:12px}
</style></head><body><header><h1>SharePoint SE | Pilot Migration</h1>
<p>Inwentaryzacja lokalna, tylko do odczytu</p></header><main>
<p class="warn">POUFNE: wynik zawiera adresy, serwery, nazwy baz i konfiguracje.
Nie publikuj tego pliku ani JSON w publicznym GitHubie.</p>
'@
$tail='</main></body></html>'
$htmlFile=Join-Path $outDir 'SPSE_Pilot_Dashboard.html'
[IO.File]::WriteAllText($htmlFile,($head+[Environment]::NewLine+($blocks -join [Environment]::NewLine)+$tail),
    [Text.UTF8Encoding]::new($true))
Write-Host ('PRIVATE HTML: '+$htmlFile) -ForegroundColor Green
Write-Host ('PRIVATE JSON: '+$json) -ForegroundColor Yellow
Write-Host ('COLLECTOR ERRORS: '+$issues.Count)
Write-Warning 'Wyniki przechowuj lokalnie. Skrypt niczego nie montuje, kopiuje ani nie zmienia w SharePoint.'
