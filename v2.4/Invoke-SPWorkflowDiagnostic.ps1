#requires -Version 5.1
<#
.SYNOPSIS
  Read-only, TARGETED SharePoint 2019 Workflow & alert diagnostic (SP 2010/2013).
.DESCRIPTION
  Run on SP2019 APP/WFE in 64-bit Windows PowerShell 5.1 as farm/shell admin.
  Only reads one existing SharePoint Web and one list (never creates an item or sends mail).
  Local JSON is confidential; separate Markdown contains only counts/statuses, no paths/URLs.
.EXAMPLE
  .\Invoke-SPWorkflowDiagnostic.ps1 -WebUrl "https://intranet/sites/a" -ListTitle "Zgloszenia"
.EXAMPLE
  .\Invoke-SPWorkflowDiagnostic.ps1 -WebUrl "https://intranet/sites/a" -ListTitle "Zgloszenia" -ItemId 123
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$WebUrl,
  [Parameter(Mandatory=$true)][string]$ListTitle,
  [ValidateRange(0,2147483647)][int]$ItemId = 0,
  [string]$OutputRoot = 'C:\SP_Workflow_Diagnostic'
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
if(-not [Environment]::Is64BitProcess){throw 'Wymagany Windows PowerShell 5.1 64-bit.'}
if(-not (Get-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)){
  Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction Stop
}
$started=Get-Date
$dir=Join-Path $OutputRoot ('Workflow_'+$started.ToString('yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$diag=[ordered]@{
  Version='2.4.0'
  Started=$started.ToString('s')
  Target=[ordered]@{WebUrl=$WebUrl;ListTitle=$ListTitle;ItemId=$ItemId;ListId=$null}
  Mail=[ordered]@{FarmMailKnown=$false;WebAppMailConfigured=$null;WebAppSmtpServer=$null;WebAppFromConfigured=$null}
  WorkflowProxy=[ordered]@{Available=$null;Status=$null;Endpoint=$null}
  TimerService=$null
  TimerJobs=@()
  LegacyAssociations=@()
  Workflow2013Subscriptions=@()
  LegacyInstances=@()
  Workflow2013Instances=@()
  Errors=@()
  Checks=[ordered]@{Legacy='NOT_RUN';Workflow2013='NOT_RUN';ItemInstances='NOT_REQUESTED'}
}
$errs=New-Object 'System.Collections.Generic.List[object]'
function SafeValue($obj,[string]$prop) {
  if($null -eq $obj){return $null}
  try{$p=$obj.PSObject.Properties[$prop];if($null -eq $p){return $null};return $p.Value}catch{return $null}
}
function Check([string]$Section,[scriptblock]$Script){
  try{& $Script}
  catch{
    $script:errs.Add([pscustomobject]@{Section=$Section;Type=$_.Exception.GetType().Name;Message=$_.Exception.Message})
    Write-Warning ("{0} nieudane; zapisano blad lokalnie." -f $Section)
  }
}
$web=$null;$site=$null;$ctx=$null;$list=$null
try {
  $web=Get-SPWeb -Identity $WebUrl -ErrorAction Stop
  $site=$web.Site
  try{$list=$web.Lists[$ListTitle]}catch{throw 'Nie znaleziono wskazanej listy w tej witrynie.'}
  if($null -eq $list){throw 'Nie znaleziono wskazanej listy.'}
  $diag.Target.ListId=[string]$list.ID
  Check 'EmailConfiguration' {
    $wa=$site.WebApplication
    $smtp=SafeValue $wa 'OutboundMailServer'
    $from=SafeValue $wa 'OutboundMailSenderAddress'
    $diag.Mail.WebAppSmtpServer=[string]$smtp
    $diag.Mail.WebAppMailConfigured=(-not [string]::IsNullOrWhiteSpace([string]$smtp))
    $diag.Mail.WebAppFromConfigured=(-not [string]::IsNullOrWhiteSpace([string]$from))
    $diag.Mail.FarmMailKnown=$true
  }
  Check 'TimerJobs' {
    $diag.TimerJobs=@(Get-SPTimerJob | Where-Object {
      $_.Name -match 'alert|workflow' -or $_.DisplayName -match 'alert|workflow'
    } | ForEach-Object {
      [pscustomobject]@{
        Name=[string]$_.Name
        DisplayName=[string]$_.DisplayName
        Disabled=[bool]$_.IsDisabled
        Schedule=[string]$_.Schedule
      }
    })
  }
  Check 'SPTimerService' {
    $diag.TimerService=[string](Get-Service SPTimerV4 -ErrorAction Stop).Status
  }
  Check 'WorkflowProxy' {
    $proxy=Get-SPWorkflowServiceApplicationProxy -ErrorAction Stop
    $diag.WorkflowProxy.Available=($null -ne $proxy)
    if($null -ne $proxy){
      $diag.WorkflowProxy.Status=[string](SafeValue $proxy 'Status')
      try{$diag.WorkflowProxy.Endpoint=[string]$proxy.GetWorkflowServiceAddress($site)}
      catch{$script:errs.Add([pscustomobject]@{Section='WorkflowEndpoint';Type=$_.Exception.GetType().Name;Message=$_.Exception.Message})}
    }
  }
  Check 'LegacyAssociations' {
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach($pair in @(@{Scope='Web';Associations=$web.WorkflowAssociations},@{Scope='List';Associations=$list.WorkflowAssociations})){
      foreach($a in $pair.Associations){
        $rows.Add([pscustomobject]@{
          Scope=$pair.Scope;Name=[string]$a.Name;Id=[string]$a.Id
          Enabled=[bool]$a.Enabled
          AutoStartCreate=[bool]$a.AutoStartCreate
          AutoStartChange=[bool]$a.AutoStartChange
          AllowManual=[bool]$a.AllowManual
          TemplateId=[string]$a.BaseId
          HistoryListId=[string]$a.HistoryListId
          TaskListId=[string]$a.TaskListId
        })
      }
    }
    $diag.LegacyAssociations=@($rows.ToArray())
    $diag.Checks.Legacy='OK'
  }
  if($ItemId -gt 0){
    $diag.Checks.ItemInstances='PARTIAL'
    Check 'LegacyItemInstances' {
      $item=$list.GetItemById($ItemId)
      $instances=@($site.WorkflowManager.GetItemWorkflows($item))
      $diag.LegacyInstances=@(foreach($w in $instances){
        [pscustomobject]@{
          AssociationId=[string]$w.AssociationId
          InternalState=[string]$w.InternalState
          IsCompleted=[bool]$w.IsCompleted
          Created=[string]$w.Created
          Modified=[string]$w.Modified
        }
      })
    }
  }
  # 2013 engine is independent of the SPWorkflowAssociation object model above.
  Check 'Workflow2013Subscriptions' {
    $isapi=Join-Path $env:CommonProgramFiles 'Microsoft Shared\Web Server Extensions\16\ISAPI'
    foreach($asm in @('Microsoft.SharePoint.Client.Runtime.dll','Microsoft.SharePoint.Client.dll','Microsoft.SharePoint.Client.WorkflowServices.dll')){
      $full=Join-Path $isapi $asm
      if(-not (Test-Path -LiteralPath $full)){throw ('Brak wymaganej biblioteki CSOM: '+$asm)}
      Add-Type -Path $full -ErrorAction Stop
    }
    $ctx=New-Object Microsoft.SharePoint.Client.ClientContext($web.Url)
    $ctx.Credentials=[Net.CredentialCache]::DefaultNetworkCredentials
    $wsm=New-Object Microsoft.SharePoint.Client.WorkflowServices.WorkflowServicesManager($ctx,$ctx.Web)
    $svc=$wsm.GetWorkflowSubscriptionService()
    $subs=$svc.EnumerateSubscriptionsByList($list.ID)
    $ctx.Load($subs)
    $ctx.ExecuteQuery()
    $diag.Workflow2013Subscriptions=@(foreach($w in $subs){
      [pscustomobject]@{
        Name=[string]$w.Name
        Id=[string]$w.Id
        DefinitionId=[string]$w.DefinitionId
        Enabled=[bool]$w.Enabled
        EventTypes=@($w.EventTypes | ForEach-Object {[string]$_})
      }
    })
    $diag.Checks.Workflow2013='OK'
    if($ItemId -gt 0){
      $inst=$wsm.GetWorkflowInstanceService().EnumerateInstancesForListItem($list.ID,$ItemId)
      $ctx.Load($inst)
      $ctx.ExecuteQuery()
      $diag.Workflow2013Instances=@(foreach($w in $inst){
        [pscustomobject]@{
          Id=[string]$w.Id
          Status=[string]$w.Status
          WorkflowSubscriptionId=[string]$w.WorkflowSubscriptionId
        }
      })
    }
  }
  if($ItemId -gt 0 -and $errs.Count -eq 0){$diag.Checks.ItemInstances='OK'}
}finally{
  if($null -ne $ctx){$ctx.Dispose()}
  if($null -ne $web){$web.Dispose()}
  if($null -ne $site){$site.Dispose()}
}
$diag.Errors=@($errs.ToArray())
$full=Join-Path $dir 'WorkflowDiagnostic_PRIVATE.json'
$diag | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $full -Encoding UTF8
$legacy=@($diag.LegacyAssociations)
$wf13=@($diag.Workflow2013Subscriptions)
$timer=@($diag.TimerJobs)
$activeLegacy=@($legacy | Where-Object { $_.Enabled })
$active2013=@($wf13 | Where-Object { $_.Enabled })
$immediate=@($timer | Where-Object { $_.Name -match 'alert' -or $_.DisplayName -match 'alert' })
$md=@(
  '# SharePoint Workflow — diagnostyka pseudonimizowana'
  ''
  'Tryb: odczyt tylko jednej listy, bez uruchamiania procesow i bez wysylki maili.'
  ''
  ('- Workflow 2010 object model check: **{0}**' -f $diag.Checks.Legacy)
  ('- Workflow 2013 subscription check: **{0}**' -f $diag.Checks.Workflow2013)
  ('- Powiazania legacy: **{0}**, enabled: **{1}**' -f $legacy.Count,$activeLegacy.Count)
  ('- Legacy autostart create: **{0}**' -f @($activeLegacy | Where-Object {$_.AutoStartCreate}).Count)
  ('- Legacy autostart change: **{0}**' -f @($activeLegacy | Where-Object {$_.AutoStartChange}).Count)
  ('- Subskrypcje 2013: **{0}**, enabled: **{1}**' -f $wf13.Count,$active2013.Count)
  ('- Subskrypcje 2013 Enabled + ItemAdded: **{0}**' -f @($active2013 | Where-Object {$_.EventTypes -contains 'ItemAdded'}).Count)
  ('- Subskrypcje 2013 Enabled + ItemUpdated: **{0}**' -f @($active2013 | Where-Object {$_.EventTypes -contains 'ItemUpdated'}).Count)
  ('- Proxy WFM present: **{0}**' -f $diag.WorkflowProxy.Available)
  ('- Proxy WFM status: **{0}**' -f $diag.WorkflowProxy.Status)
  ('- SMTP skonfigurowany: **{0}**' -f $diag.Mail.WebAppMailConfigured)
  ('- From address skonfigurowany: **{0}**' -f $diag.Mail.WebAppFromConfigured)
  ('- Timer service: **{0}**' -f $diag.TimerService)
  ('- Timer jobs z alertami: **{0}**, disabled: **{1}**' -f $immediate.Count,@($immediate|Where-Object {$_.Disabled}).Count)
  ('- Workflow legacy instances for item (if requested): **{0}**' -f @($diag.LegacyInstances).Count)
  ('- Workflow 2013 instances for item (if requested): **{0}**' -f @($diag.Workflow2013Instances).Count)
  ('- Legacy instances with Failure/Error/Fault: **{0}**' -f @($diag.LegacyInstances | Where-Object {$_.InternalState -match '(?i)fail|fault|error'}).Count)
  ('- 2013 instances Suspended/Terminated: **{0}**' -f @($diag.Workflow2013Instances | Where-Object {$_.Status -match '(?i)suspend|terminat'}).Count)
  ('- Errors: **{0}** (tylko liczba, bez tresci)' -f $errs.Count)
  ''
  '## Coverage'
  '2010 object-model associations and 2013 subscriptions are separate. UNKNOWN/FAILED != zero workflows.'
  'No SMTP test email, alert delivery trace or full farm inventory was performed.'
  'Raw JSON contains server names, workflow names and URL; do not publish it.'
  'Markdown contains technical metadata and still requires review before sharing.'
)
# Whitelisted diagnostics, never raw error messages or exception values from the environment.
$allowedSections=@('EmailConfiguration','TimerJobs','SPTimerService','WorkflowProxy','WorkflowEndpoint',
                   'LegacyAssociations','LegacyItemInstances','Workflow2013Subscriptions')
$allowedErrors=@('COMException','SqlException','WebException','UnauthorizedAccessException',
                 'InvalidOperationException','FileNotFoundException','TypeLoadException','RuntimeException',
                 'ArgumentException','Exception')
$md+= ''
$md+= '## Failure categories'
foreach($e in $errs){
  $sect=if([string]$e.Section -in $allowedSections){[string]$e.Section}else{'Other'}
  $typ=if([string]$e.Type -in $allowedErrors){[string]$e.Type}else{'Other'}
  $md+= ('- {0}: {1}' -f $sect,$typ)
}
$mdPath=Join-Path $dir 'WorkflowDiagnostic_SHAREABLE.md'
[IO.File]::WriteAllText($mdPath,($md -join [Environment]::NewLine),(New-Object System.Text.UTF8Encoding($true)))
Write-Host ('PRIVATE: '+$full) -ForegroundColor Yellow
Write-Host ('SHAREABLE (REVIEW FIRST): '+$mdPath) -ForegroundColor Green
Write-Host ('Legacy associations: '+$legacy.Count+'; SP2013 subscriptions: '+$wf13.Count+'; errors: '+$errs.Count)
