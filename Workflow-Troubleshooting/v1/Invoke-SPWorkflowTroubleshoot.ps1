#requires -Version 5.1
<#
.SYNOPSIS
  Read-only SharePoint 2019 workflow incident diagnosis for one list.
.EXAMPLE
  .\Invoke-SPWorkflowTroubleshoot.ps1 -WebUrl 'https://sp/sites/x' -ListUrl 'https://sp/sites/x/Lists/Cases/AllItems.aspx'
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$WebUrl,
  [Parameter(Mandatory=$true)][string]$ListUrl,
  [ValidateRange(0,2147483647)][int]$ItemId=0,
  [ValidateRange(0,10)][int]$RecentItems=3,
  [ValidateRange(1,24)][int]$LogHours=3,
  [string]$OutputRoot='C:\SP_Workflow_Troubleshooting'
)
Set-StrictMode -Version 2
$ErrorActionPreference='Stop'
if(-not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) {
  throw 'Run Windows PowerShell 5.1 x64 on a SharePoint server.'
}
if(-not (Get-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)) {
  Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction Stop
}
$now=Get-Date
$dir=Join-Path $OutputRoot ('Run_'+$now.ToString('yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$errors=New-Object 'System.Collections.Generic.List[object]'
$r=[ordered]@{
  Version='1.0';Collected=$now.ToString('o');Server=$env:COMPUTERNAME
  Web=$WebUrl;ListUrl=$ListUrl;ListName=$null;ListId=$null
  Build=$null;EnablePreParseSecurityCheckForWorkflow=$null;ClassicWfmFlag53601=$null
  ProxyPresent=$null;ProxyStatus=$null;ProxyEndpoint=$null;TimerService=$null
  LegacyAssociations=@();WfmSubscriptions=@();Items=@();Uls=@()
  Status=[ordered]@{Legacy='NOT_RUN';Wfm2013='NOT_RUN';Uls='NOT_RUN'}
  Errors=@()
}
function Capture([string]$Area,[scriptblock]$Code) {
  try { & $Code } catch {
    $script:errors.Add([pscustomobject]@{Area=$Area;Type=$_.Exception.GetType().Name;Message=$_.Exception.Message})
    Write-Warning ($Area+' failed - details in private JSON')
  }
}
$web=$null;$site=$null;$ctx=$null
try {
  $web=Get-SPWeb -Identity $WebUrl -ErrorAction Stop
  $site=$web.Site
  $u=New-Object Uri($ListUrl,[UriKind]::Absolute)
  $rootUri=New-Object Uri($web.Url,[UriKind]::Absolute)
  if($u.Host -ne $rootUri.Host) { throw 'List and web hostnames differ.' }
  $path=[Uri]::UnescapeDataString($u.AbsolutePath).TrimEnd('/')
  $list=$null;$len=-1
  foreach($candidate in $web.Lists) {
    $folder=[Uri]::UnescapeDataString([string]$candidate.RootFolder.ServerRelativeUrl).TrimEnd('/')
    if($path.Equals($folder,[StringComparison]::OrdinalIgnoreCase) -or
      $path.StartsWith(($folder+'/'),[StringComparison]::OrdinalIgnoreCase)) {
      if($folder.Length -gt $len) {$len=$folder.Length;$list=$candidate}
    }
  }
  if($null -eq $list) { throw 'List not found. Use the exact SPWeb and normal list view URL.' }
  $r.ListName=[string]$list.Title;$r.ListId=[string]$list.ID

  Capture 'Farm' {
    $farm=Get-SPFarm -ErrorAction Stop
    $r.Build=[string]$farm.BuildVersion
    $prop=$farm.PSObject.Properties['EnablePreParseSecurityCheckForWorkflow']
    if($null -ne $prop){$r.EnablePreParseSecurityCheckForWorkflow=[bool]$prop.Value}
    $r.ClassicWfmFlag53601=[bool](@($farm.ServerDebugFlags) -contains 53601)
  }
  Capture 'Proxy' {
    $p=Get-SPWorkflowServiceApplicationProxy -ErrorAction Stop
    $r.ProxyPresent=($null -ne $p)
    if($null -ne $p) {
      $r.ProxyStatus=[string]$p.Status
      try{$r.ProxyEndpoint=[string]$p.GetWorkflowServiceAddress($site)}
      catch{$script:errors.Add([pscustomobject]@{Area='Endpoint';Type=$_.Exception.GetType().Name;Message=$_.Exception.Message})}
    }
  }
  Capture 'Timer' {$r.TimerService=[string](Get-Service SPTimerV4 -ErrorAction Stop).Status}
  Capture 'SP2010' {
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach($a in $list.WorkflowAssociations) {
      $rows.Add([pscustomobject]@{Scope='LIST';Name=[string]$a.Name;Id=[string]$a.Id
        Enabled=[bool]$a.Enabled;Create=[bool]$a.AutoStartCreate
        Change=[bool]$a.AutoStartChange;Manual=[bool]$a.AllowManual})
    }
    foreach($ct in $list.ContentTypes) {
      foreach($a in $ct.WorkflowAssociations) {
        $rows.Add([pscustomobject]@{Scope='CONTENT_TYPE';Name=[string]$a.Name;Id=[string]$a.Id
          Enabled=[bool]$a.Enabled;Create=[bool]$a.AutoStartCreate
          Change=[bool]$a.AutoStartChange;Manual=[bool]$a.AllowManual})
      }
    }
    $r.LegacyAssociations=@($rows.ToArray());$r.Status.Legacy='OK'
  }
  $checked=New-Object 'System.Collections.Generic.List[object]'
  if($ItemId -gt 0) {
    $checked.Add($list.GetItemById($ItemId))
  } elseif($RecentItems -gt 0) {
    $q=New-Object Microsoft.SharePoint.SPQuery
    $q.Query='<OrderBy><FieldRef Name="ID" Ascending="FALSE" /></OrderBy>'
    $q.RowLimit=[uint32]$RecentItems
    $q.ViewFields='<FieldRef Name="ID" />'
    foreach($x in $list.GetItems($q)){$checked.Add($x)}
  }
  $items=New-Object 'System.Collections.Generic.List[object]'
  foreach($item in $checked) {
    $row=[pscustomobject]@{ItemId=[int]$item.ID;SP2010=@();SP2013=@()}
    Capture 'SP2010Instances' {
      $instances=@($site.WorkflowManager.GetItemWorkflows($item))
      $row.SP2010=@(foreach($i in $instances) {
        [pscustomobject]@{AssociationId=[string]$i.AssociationId
          InstanceId=[string]$i.InstanceId;State=[string]$i.InternalState
          Completed=[bool]$i.IsCompleted;Created=[string]$i.Created}
      })
    }
    $items.Add($row)
  }
  $r.Items=@($items.ToArray())
  Capture 'SP2013CSOM' {
    $base=Join-Path $env:CommonProgramFiles 'Microsoft Shared\Web Server Extensions\16\ISAPI'
    foreach($dll in @('Microsoft.SharePoint.Client.Runtime.dll','Microsoft.SharePoint.Client.dll',
                      'Microsoft.SharePoint.Client.WorkflowServices.dll')) {
      $asm=[IO.Path]::GetFileNameWithoutExtension($dll)
      if(@([AppDomain]::CurrentDomain.GetAssemblies() |
          Where-Object{$_.GetName().Name -eq $asm}).Count -eq 0) {
        Add-Type -Path (Join-Path $base $dll) -ErrorAction Stop
      }
    }
    $ctx=New-Object Microsoft.SharePoint.Client.ClientContext($web.Url)
    $ctx.Credentials=[Net.CredentialCache]::DefaultNetworkCredentials
    $mgr=New-Object Microsoft.SharePoint.Client.WorkflowServices.WorkflowServicesManager($ctx,$ctx.Web)
    $subs=$mgr.GetWorkflowSubscriptionService().EnumerateSubscriptionsByList($list.ID)
    $ctx.Load($subs);$ctx.ExecuteQuery()
    $r.WfmSubscriptions=@(foreach($s in $subs){
      [pscustomobject]@{Name=[string]$s.Name;Id=[string]$s.Id;Enabled=[bool]$s.Enabled
        EventTypes=@($s.EventTypes | ForEach-Object{[string]$_})}
    })
    $r.Status.Wfm2013='OK'
    for($n=0;$n -lt $checked.Count;$n++) {
      try {
        $instances=$mgr.GetWorkflowInstanceService().EnumerateInstancesForListItem($list.ID,[int]$checked[$n].ID)
        $ctx.Load($instances);$ctx.ExecuteQuery()
        $items[$n].SP2013=@(foreach($i in $instances){
          [pscustomobject]@{Id=[string]$i.Id;Status=[string]$i.Status
            SubscriptionId=[string]$i.WorkflowSubscriptionId}
        })
      } catch {
        $script:errors.Add([pscustomobject]@{Area='SP2013Instances';Type=$_.Exception.GetType().Name;Message=$_.Exception.Message})
      }
    }
  }
  Capture 'ULS' {
    $pattern='workflow|xoml|CodeDom|PreParse|authorizedType|ServiceBus|SPWFM'
    $r.Uls=@(Get-SPLogEvent -StartTime $now.AddHours(-$LogHours) -EndTime $now -MinimumLevel Warning |
      Where-Object { ($_.Area+' '+$_.Category+' '+$_.Message) -match $pattern } |
      Select-Object -First 100 |
      ForEach-Object {[pscustomobject]@{Time=[string]$_.Timestamp
        Area=[string]$_.Area;Category=[string]$_.Category
        Message=[string]$_.Message;Correlation=[string]$_.Correlation}})
    $r.Status.Uls='OK_LOCAL_ONLY'
  }
} finally {
  if($null -ne $ctx){$ctx.Dispose()}
  if($null -ne $web){$web.Dispose()}
  if($null -ne $site){$site.Dispose()}
}
$r.Errors=@($errors.ToArray())
$private=Join-Path $dir 'WorkflowTroubleshoot_PRIVATE.json'
$r | ConvertTo-Json -Depth 15 | Out-File -LiteralPath $private -Encoding UTF8
$legacy=@($r.LegacyAssociations);$wfm=@($r.WfmSubscriptions)
$legacyEnabled=@($legacy|Where-Object{$_.Enabled})
$wfmEnabled=@($wfm|Where-Object{$_.Enabled})
$lines=New-Object 'System.Collections.Generic.List[string]'
foreach($t in @(
  '# SharePoint workflow troubleshooting - safe summary'
  ''
  ('Build: {0}' -f $r.Build)
  ('SP2010 preparse security: {0}' -f $r.EnablePreParseSecurityCheckForWorkflow)
  ('Classic Workflow Manager compatibility flag 53601: {0}' -f $r.ClassicWfmFlag53601)
  ('Workflow Manager proxy present: {0}; status: {1}' -f $r.ProxyPresent,$r.ProxyStatus)
  ('Local SPTimerV4: {0}' -f $r.TimerService)
  ('SP2010 workflow associations: {0}; enabled: {1}; autostart create: {2}' -f
    $legacy.Count,$legacyEnabled.Count,@($legacyEnabled|Where-Object{$_.Create}).Count)
  ('SP2013 subscriptions: {0}; enabled: {1}; ItemAdded: {2}' -f
    $wfm.Count,$wfmEnabled.Count,@($wfmEnabled|Where-Object{$_.EventTypes -contains 'ItemAdded'}).Count)
  ('Checked items: {0}' -f $r.Items.Count)
  ('ULS local workflow warnings/errors (max 100): {0}' -f @($r.Uls).Count)
  ('Collector errors: {0}' -f $errors.Count)
  ('Collection status: 2010={0}; 2013={1}; ULS={2}' -f
    $r.Status.Legacy,$r.Status.Wfm2013,$r.Status.Uls)
  ''
  '## Instance states by anonymized item'
)){$lines.Add([string]$t)}
$n=0
foreach($x in $r.Items) {
  $n++
  $a=@($x.SP2010 | ForEach-Object{$_.State}) -join ','
  $b=@($x.SP2013 | ForEach-Object{$_.Status}) -join ','
  if(-not $a){$a='none returned'};if(-not $b){$b='none returned'}
  $lines.Add(('ITEM-{0}: 2010=[{1}], 2013=[{2}]' -f $n,$a,$b))
}
$lines.Add('')
$lines.Add('## Collection failures (without sensitive exception text)')
foreach($e in $errors) {
  $name=if($e.Area -in @('Farm','Proxy','Endpoint','Timer','SP2010','SP2010Instances',
      'SP2013CSOM','SP2013Instances','ULS')) {$e.Area} else {'OTHER'}
  $lines.Add(('- {0}: FAILED' -f $name))
}
$lines.Add('')
$lines.Add('Read-only. Empty/failed 2013 result is not proof of no workflows.')
$lines.Add('ULS is LOCAL ONLY on collecting server, not all farm servers.')
$lines.Add('PRIVATE JSON contains internal URLs and ULS messages. Never commit reports to GitHub.')
$lines.Add('Review this summary before sharing.')
$summary=Join-Path $dir 'WorkflowTroubleshoot_SHAREABLE.md'
[IO.File]::WriteAllText($summary,($lines -join [Environment]::NewLine),(New-Object System.Text.UTF8Encoding($true)))
Write-Host ('PRIVATE: '+$private) -ForegroundColor Yellow
Write-Host ('SHAREABLE: '+$summary) -ForegroundColor Green
Write-Host ('2010: {0}; 2013: {1}; errors: {2}' -f $legacy.Count,$wfm.Count,$errors.Count)
