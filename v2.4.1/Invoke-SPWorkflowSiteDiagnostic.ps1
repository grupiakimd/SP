#requires -Version 5.1
<#
.SYNOPSIS
  Read-only workflow diagnosis for ONE SharePoint 2019 SPWeb (site), no ListTitle needed.
.DESCRIPTION
  Audits 2010 site/list/content type associations and 2013 workflow subscriptions
  via CSOM, plus SMTP configuration, WFM proxy and alert/workflow Timer Jobs.
  DOES NOT recursively scan subwebs or execute any workflows or create test items.
  Writes PRIVATE.json and pseudonymized SHAREABLE.md locally.
.EXAMPLE
  .\Invoke-SPWorkflowSiteDiagnostic.ps1 -WebUrl 'https://intranet/sites/workflows'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$WebUrl,
    [string]$OutputRoot='C:\SP_Workflow_Diagnostic',
    [ValidateRange(1,10000)][int]$MaxLists=500
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if(-not [Environment]::Is64BitProcess){throw 'Uruchom Windows PowerShell 5.1 x64 na serwerze SharePoint.'}
if(-not (Get-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)){
    Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction Stop
}
$start=Get-Date
$dir=Join-Path $OutputRoot ('SiteWorkflow_'+$start.ToString('yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $dir -Force|Out-Null
$errors=New-Object 'System.Collections.Generic.List[object]'
$report=[ordered]@{
    Version='2.4.1'
    Date=$start.ToString('s')
    WebUrl=$WebUrl
    WebId=$null
    ListTotal=0
    ListScanned=0
    ListTruncated=$false
    SiteLegacy=@()
    ContentTypeLegacy=@()
    Lists=@()
    Workflow2013=@()
    Unmatched2013Count=0
    Workflow2013Status='NOT_RUN'
    LegacyStatus='NOT_RUN'
    SMTP=[ordered]@{ServerConfigured=$null;FromConfigured=$null;Server=$null}
    WorkflowManager=[ordered]@{ProxyKnown=$false;Available=$null;Status='UNKNOWN';Endpoint=$null}
    TimerService='UNKNOWN'
    TimerJobs=@()
    Errors=@()
}
function Record-Error([string]$section,[System.Exception]$exception){
    $script:errors.Add([pscustomobject]@{
        Section=$section
        Type=$exception.GetType().Name
        Message=$exception.Message
    })
    Write-Warning ("{0}: odczyt sie nie udal; szczegoly zapisano w prywatnym JSON." -f $section)
}
function Attempt([string]$section,[scriptblock]$run){
    try{& $run}catch{Record-Error $section $_.Exception}
}
function LegacyRow($a,[string]$scope,[string]$owner){
    [pscustomobject]@{
        Scope=$scope;Owner=$owner
        Name=[string]$a.Name
        Id=[string]$a.Id
        Enabled=[bool]$a.Enabled
        AutoStartCreate=[bool]$a.AutoStartCreate
        AutoStartChange=[bool]$a.AutoStartChange
        AllowManual=[bool]$a.AllowManual
    }
}
$web=$null
$ctx=$null
try{
    $web=Get-SPWeb -Identity $WebUrl -ErrorAction Stop
    $report.WebId=[string]$web.ID
    Attempt 'MailConfiguration' {
        $wa=$web.Site.WebApplication
        $smtp=[string]$wa.OutboundMailServer
        $from=[string]$wa.OutboundMailSenderAddress
        $report.SMTP.Server=$smtp
        $report.SMTP.ServerConfigured=(-not [string]::IsNullOrWhiteSpace($smtp))
        $report.SMTP.FromConfigured=(-not [string]::IsNullOrWhiteSpace($from))
    }
    Attempt 'WorkflowManagerProxy' {
        $p=Get-SPWorkflowServiceApplicationProxy -ErrorAction Stop
        $report.WorkflowManager.ProxyKnown=$true
        $report.WorkflowManager.Available=($null -ne $p)
        if($null -ne $p){
            $report.WorkflowManager.Status=[string]$p.Status
            try {$report.WorkflowManager.Endpoint=[string]$p.GetWorkflowServiceAddress($web.Site)}
            catch{ Record-Error 'WorkflowManagerEndpoint' $_.Exception }
        }
    }
    Attempt 'TimerService' {
        $report.TimerService=[string](Get-Service -Name SPTimerV4 -ErrorAction Stop).Status
    }
    Attempt 'TimerJobs' {
        $report.TimerJobs=@(Get-SPTimerJob -ErrorAction Stop |
            Where-Object { $_.Name -match 'alert|workflow' -or $_.DisplayName -match 'alert|workflow' } |
            ForEach-Object {
                [pscustomobject]@{
                    Name=[string]$_.Name
                    DisplayName=[string]$_.DisplayName
                    Disabled=[bool]$_.IsDisabled
                    Schedule=[string]$_.Schedule
                }
            })
    }

    # Inventory only this SPWeb (site) and its lists; never recurse into AllWebs.
    Attempt 'SP2010SiteAndList' {
        $report.SiteLegacy=@(foreach($a in $web.WorkflowAssociations){
            LegacyRow $a 'SITE' ([string]$web.ID)
        })
        $report.ContentTypeLegacy=@(foreach($ct in $web.ContentTypes){
            foreach($a in $ct.WorkflowAssociations){
                LegacyRow $a 'CONTENT_TYPE' ([string]$ct.Id)
            }
        })
        $all=@($web.Lists)
        $report.ListTotal=$all.Count
        $selected=@($all | Select-Object -First $MaxLists)
        $report.ListTruncated=($all.Count -gt $selected.Count)
        $listRows=New-Object 'System.Collections.Generic.List[object]'
        foreach($l in $selected){
            try {
                $associations=@(foreach($a in $l.WorkflowAssociations){
                    LegacyRow $a 'LIST' ([string]$l.ID)
                })
                $listRows.Add([pscustomobject]@{
                    Id=[string]$l.ID
                    Title=[string]$l.Title
                    Url=[string]$l.RootFolder.ServerRelativeUrl
                    Hidden=[bool]$l.Hidden
                    Legacy=@($associations)
                    Workflow2013=@()
                })
                $report.ListScanned++
            }catch{
                Record-Error 'ListLegacy' $_.Exception
            }
        }
        $report.Lists=@($listRows.ToArray())
        $report.LegacyStatus=$(if($report.ListTruncated -or @($errors|Where-Object {$_.Section -eq 'ListLegacy'}).Count -gt 0){'PARTIAL'}else{'OK'})
    }

    # 2013 WFM subscriptions are NOT stored in SPWorkflowAssociation.
    # Enumerate web-wide once and classify by EventSourceId (site/list/unknown).
    Attempt 'SP2013Subscriptions' {
        $isapi=Join-Path $env:CommonProgramFiles 'Microsoft Shared\Web Server Extensions\16\ISAPI'
        foreach($file in @('Microsoft.SharePoint.Client.Runtime.dll',
                           'Microsoft.SharePoint.Client.dll',
                           'Microsoft.SharePoint.Client.WorkflowServices.dll')){
            $name=[IO.Path]::GetFileNameWithoutExtension($file)
            if(-not @([AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object {$_.GetName().Name -eq $name}).Count){
                $path=Join-Path $isapi $file
                if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
                    throw ("Brak biblioteki CSOM: "+$file)
                }
                Add-Type -Path $path -ErrorAction Stop
            }
        }
        $ctx=New-Object Microsoft.SharePoint.Client.ClientContext($web.Url)
        $ctx.Credentials=[Net.CredentialCache]::DefaultNetworkCredentials
        $mgr=New-Object Microsoft.SharePoint.Client.WorkflowServices.WorkflowServicesManager($ctx,$ctx.Web)
        $subs=$mgr.GetWorkflowSubscriptionService().EnumerateSubscriptions()
        $ctx.Load($subs)
        $ctx.ExecuteQuery()
        $known=@{}
        foreach($row in $report.Lists){
            $known[$row.Id.ToLowerInvariant()]=$row
        }
        $siteId=([string]$web.ID).ToLowerInvariant()
        $found=New-Object 'System.Collections.Generic.List[object]'
        foreach($sub in $subs){
            $eventSource=([string]$sub.EventSourceId).ToLowerInvariant()
            $scope='OTHER_OR_UNKNOWN'
            if($eventSource -eq $siteId){$scope='SITE'}
            elseif($known.ContainsKey($eventSource)){$scope='LIST'}
            $row=[pscustomobject]@{
                Name=[string]$sub.Name
                Id=[string]$sub.Id
                DefinitionId=[string]$sub.DefinitionId
                EventSourceId=$eventSource
                Scope=$scope
                Enabled=[bool]$sub.Enabled
                EventTypes=@($sub.EventTypes | ForEach-Object {[string]$_})
            }
            $found.Add($row)
            if($scope -eq 'LIST'){
                $list=$known[$eventSource]
                $list.Workflow2013=@($list.Workflow2013)+@($row)
            }elseif($scope -eq 'OTHER_OR_UNKNOWN'){$report.Unmatched2013Count++}
        }
        $report.Workflow2013=@($found.ToArray())
        $report.Workflow2013Status=$(if($report.ListTruncated){'PARTIAL_SCOPE'}else{'OK'})
    }
}finally{
    if($null -ne $ctx){$ctx.Dispose()}
    if($null -ne $web){$web.Dispose()}
}

$report.Errors=@($errors.ToArray())
$json=Join-Path $dir 'WorkflowSite_PRIVATE.json'
$report | ConvertTo-Json -Depth 15 | Out-File -LiteralPath $json -Encoding UTF8
$siteLegacy=@($report.SiteLegacy)
$typeLegacy=@($report.ContentTypeLegacy)
$allListLegacy=@(foreach($r in $report.Lists){foreach($a in $r.Legacy){$a}})
$allLegacy=@($siteLegacy)+@($typeLegacy)+@($allListLegacy)
$wf13=@($report.Workflow2013)
$enabledLegacy=@($allLegacy|Where-Object {$_.Enabled})
$enabled13=@($wf13|Where-Object {$_.Enabled})
$timer=@($report.TimerJobs)
$disabledTimer=@($timer|Where-Object {$_.Disabled})
$site13=@($wf13|Where-Object {$_.Scope -eq 'SITE'})
$list13=@($wf13|Where-Object {$_.Scope -eq 'LIST'})
$unknown13=@($wf13|Where-Object {$_.Scope -eq 'OTHER_OR_UNKNOWN'})
$md=New-Object 'System.Collections.Generic.List[string]'
[void]$md.Add('# SharePoint Workflow — raport dla jednej witryny')
[void]$md.Add('')
[void]$md.Add('Tryb tylko do odczytu. Nie skanowano podwitryn ani instancji elementow.')
[void]$md.Add('')
foreach($line in @(
    ('- Workflow 2010 status: **{0}**' -f $report.LegacyStatus),
    ('- Workflow 2013 status: **{0}**' -f $report.Workflow2013Status),
    ('- Lists scanned / total: **{0}/{1}**' -f $report.ListScanned,$report.ListTotal),
    ('- List scan truncated: **{0}**' -f $report.ListTruncated),
    ('- Site-level 2010 associations: **{0}**' -f $siteLegacy.Count),
    ('- Content-type 2010 associations: **{0}**' -f $typeLegacy.Count),
    ('- List-level 2010 associations: **{0}**' -f $allListLegacy.Count),
    ('- Enabled 2010 associations: **{0}**' -f $enabledLegacy.Count),
    ('- Enabled 2010 AutoStartCreate: **{0}**' -f @($enabledLegacy|Where-Object {$_.AutoStartCreate}).Count),
    ('- Enabled 2010 AutoStartChange: **{0}**' -f @($enabledLegacy|Where-Object {$_.AutoStartChange}).Count),
    ('- 2013 subscriptions (all returned): **{0}**' -f $wf13.Count),
    ('- 2013 site scope: **{0}**, list scope: **{1}**, other/unknown: **{2}**' -f $site13.Count,$list13.Count,$unknown13.Count),
    ('- Enabled 2013 subscriptions: **{0}**' -f $enabled13.Count),
    ('- Enabled 2013 ItemAdded: **{0}**' -f @($enabled13|Where-Object {$_.EventTypes -contains 'ItemAdded'}).Count),
    ('- Enabled 2013 ItemUpdated: **{0}**' -f @($enabled13|Where-Object {$_.EventTypes -contains 'ItemUpdated'}).Count),
    ('- WFM proxy available: **{0}**' -f $report.WorkflowManager.Available),
    ('- Local SPTimerV4: **{0}**' -f $(if($report.TimerService -in @('Running','Stopped','Paused')){$report.TimerService}else{'UNKNOWN'})),
    ('- Alert/workflow Timer Jobs: **{0}**, disabled: **{1}**' -f $timer.Count,$disabledTimer.Count),
    ('- SMTP configured: **{0}**' -f $report.SMTP.ServerConfigured),
    ('- Outbound sender configured: **{0}**' -f $report.SMTP.FromConfigured),
    ('- Read errors: **{0}** (raw messages LOCAL ONLY)' -f $errors.Count)
)){
    [void]$md.Add($line)
}
[void]$md.Add('')
[void]$md.Add('## Listy z workflow (aliasy tylko w tym raporcie)')
[void]$md.Add('')
[void]$md.Add('| Lista | 2010 | 2010 enabled | 2010 auto-create | 2013 | 2013 enabled |')
[void]$md.Add('| --- | ---: | ---: | ---: | ---: | ---: |')
$n=0
foreach($l in $report.Lists){
    $legacy=@($l.Legacy);$current=@($l.Workflow2013)
    if(($legacy.Count+$current.Count) -eq 0){continue}
    $n++
    [void]$md.Add(('| LIST-{0:D3} | {1} | {2} | {3} | {4} | {5} |' -f
        $n,$legacy.Count,@($legacy|Where-Object {$_.Enabled}).Count,
        @($legacy|Where-Object {$_.Enabled -and $_.AutoStartCreate}).Count,
        $current.Count,@($current|Where-Object {$_.Enabled}).Count))
}
if($n -eq 0){[void]$md.Add('| — | 0 | 0 | 0 | 0 | 0 |')}
[void]$md.Add('')
[void]$md.Add('## Niezebrane dane')
[void]$md.Add('Nie stwierdza ostatnich uruchomien workflow, bledow akcji Send Email ani dostarczenia SMTP. UNKNOWN i FAILED nie oznaczaja zera workflow.')
[void]$md.Add('Przyklady brakow: stare Workflow 2010 w innych podwitrynach; subskrypcje 2013 poza biezacym SPWeb; listy poza MaxLists.')
[void]$md.Add('Raport to pseudonimizacja, nie pelna anonimowosc. Sprawdz zawartosc przed udostepnieniem.')
[void]$md.Add('')
[void]$md.Add('## Kategorie problemow kolektora')
$allowedSections=@('MailConfiguration','WorkflowManagerProxy','WorkflowManagerEndpoint',
    'TimerService','TimerJobs','SP2010SiteAndList','ListLegacy','SP2013Subscriptions')
foreach($e in $errors){
    $label=if($e.Section -in $allowedSections){[string]$e.Section}else{'OTHER'}
    [void]$md.Add(('- {0}: FAILED' -f $label))
}
$target=Join-Path $dir 'WorkflowSite_SHAREABLE.md'
[IO.File]::WriteAllText($target,($md -join [Environment]::NewLine),(New-Object System.Text.UTF8Encoding($true)))
Write-Host ('PRIVATE: '+$json) -ForegroundColor Yellow
Write-Host ('SHAREABLE (przejrzyj przed wyslaniem): '+$target) -ForegroundColor Green
Write-Host ("Witryna: {0} list, 2010: {1}, 2013: {2}, errors: {3}" -f
    $report.ListScanned,$allLegacy.Count,$wf13.Count,$errors.Count)
