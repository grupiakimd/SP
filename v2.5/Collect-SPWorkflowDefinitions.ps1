#requires -Version 5.1
<#
.SYNOPSIS
  v2.5 Read-only SharePoint 2019 workflow definition inventory, one SPWeb.
.DESCRIPTION
  Inventories 2010 site/list/content-type associations, separate 2010 XOML artifacts
  in the hidden Workflows library, and 2013 subscriptions/definitions via CSOM.
  Never starts/stops workflow, changes list, deploys WSP, or accesses SQL directly.
  Source markup is parsed in memory only; no raw XOML/XAML is exported.
  Outputs LOCAL CONFIDENTIAL WorkflowDefinitions_PRIVATE.json.
.EXAMPLE
  .\Collect-SPWorkflowDefinitions.ps1 -WebUrl 'https://portal/sites/workflow'
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$WebUrl,
  [string]$OutputRoot='C:\SP_Workflow_Migration',
  [ValidateRange(1,10000)][int]$MaxLists=1500,
  [ValidateRange(1,10000)][int]$MaxMarkupFiles=1500,
  [ValidateRange(16384,8388608)][int]$MaxMarkupBytes=1048576,
  [ValidateRange(1,2000)][int]$Max2013Definitions=500
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if(-not [Environment]::Is64BitProcess){throw 'Windows PowerShell 5.1 x64 jest wymagany.'}
if(-not (Get-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue)){
  Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction Stop
}
$started=Get-Date
$folder=Join-Path $OutputRoot ('WorkflowDefinitions_'+$started.ToString('yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$r=[ordered]@{
  Schema='SP-WF-DEFINITIONS-v2.5'
  Scope='ONE_SPWEB'
  WebUrl=$WebUrl
  Started=$started.ToString('s')
  Finished=$null
  Coverage=[ordered]@{
    MaxLists=$MaxLists;ListsTotal=0;ListsScanned=0;ListsTruncated=$false
    MaxMarkupFiles=$MaxMarkupFiles;MarkupFilesExamined=0;MarkupFilesTruncated=$false
    Max2013Definitions=$Max2013Definitions;Definitions2013Examined=0;Definitions2013Truncated=$false
    Workflow2010='NOT_RUN';Workflow2010Markup='NOT_RUN';Workflow2013='NOT_RUN'
  }
  Associations2010=@()
  MarkupArtifacts2010=@()
  Subscriptions2013=@()
  Definitions2013=@()
  Errors=@()
}
$errors=New-Object 'System.Collections.Generic.List[object]'
function Record-Failure([string]$section,[System.Exception]$exception){
  $script:errors.Add([pscustomobject]@{Section=$section;Type=$exception.GetType().Name;Message=$exception.Message})
  Write-Warning ("{0}: brak pelnego odczytu; szczegoly tylko w lokalnym JSON." -f $section)
}
function Read-Property($obj,[string]$name){
  if($null -eq $obj){return $null}
  try {
    $prop=$obj.PSObject.Properties[$name]
    if($null -ne $prop){return $prop.Value}
  } catch {}
  return $null
}
function Hash-String([string]$value){
  $sha=[Security.Cryptography.SHA256]::Create()
  try {
    $bytes=[Text.Encoding]::UTF8.GetBytes($value)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
  } finally {$sha.Dispose()}
}
function Inspect-Markup([string]$text,[string]$kind){
  # XML parser runs with DTD and external entities disabled.
  if([string]::IsNullOrWhiteSpace($text)){throw 'Pusty markup.'}
  $settings=New-Object System.Xml.XmlReaderSettings
  $settings.DtdProcessing=[System.Xml.DtdProcessing]::Prohibit
  $settings.XmlResolver=$null
  $settings.MaxCharactersInDocument=8388608
  $settings.MaxCharactersFromEntities=0
  $counts=@{}
  $types=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $reader=[Xml.XmlReader]::Create(([IO.StringReader]::new($text)),$settings)
  $elements=0
  try {
    while($reader.Read()){
      if($reader.NodeType -ne [Xml.XmlNodeType]::Element){continue}
      $elements++
      $local=[string]$reader.LocalName
      if(-not $counts.ContainsKey($local)){$counts[$local]=0}
      $counts[$local]++
      # Attribute keys/names classify behavior; attribute values can contain secrets,
      # URLs and email addresses and MUST NOT leave this function.
      $probe=$local
      if($reader.HasAttributes){
        while($reader.MoveToNextAttribute()){
          if($reader.LocalName -in @('Type','ActivityType','Class','Method','Name')){
            $v=[string]$reader.Value
            # Only include the terminal *identifier* when there are no unsafe chars.
            # Never record arbitrary attribute content.
            if($v.Length -le 100 -and $v -match '^[A-Za-z][A-Za-z0-9_.+]*$'){
              $probe+=' '+$v
            }
          }
        }
        [void]$reader.MoveToElement()
      }
      switch -regex ($probe){
        '(?i)send.?mail|send.?email|email|smtp' {[void]$types.Add('EMAIL');break}
        '(?i)create.?task|assign.?task|taskprocess|approval|approve' {[void]$types.Add('TASK_APPROVAL');break}
        '(?i)condition|ifelse|switch|compare' {[void]$types.Add('CONDITION');break}
        '(?i)while|foreach|loop|repeat' {[void]$types.Add('LOOP');break}
        '(?i)delay|wait|pause|timer' {[void]$types.Add('WAIT');break}
        '(?i)http|webservice|rest|soap|invoke.?method' {[void]$types.Add('EXTERNAL_CALL');break}
        '(?i)update.?list|update.?item|create.?list|create.?item|delete.?item' {[void]$types.Add('LIST_MUTATION');break}
      }
    }
  } finally {$reader.Dispose()}
  $signature=@($counts.Keys | Sort-Object | ForEach-Object {($_+':'+$counts[$_])}) -join ';'
  # A signature collision means only identical tag counts, NOT equivalent behavior.
  return [pscustomobject]@{
    Parse='OK';Kind=$kind;Elements=$elements
    Categories=@($types | Sort-Object)
    SignatureHash=Hash-String ($kind+'|'+$signature)
    ActionHints=@($counts.Keys | Where-Object {
      $_ -match '(?i)mail|task|condition|ifelse|wait|delay|loop|update|create|http|approval'
    } | Sort-Object | Select-Object -First 25)
    Unclassified=($types.Count -eq 0)
  }
}
function Association-Row($a,[string]$scope,[string]$owner){
  $t=Read-Property $a 'BaseTemplate'
  $base=Read-Property $a 'BaseId'
  $templateId=if($null -ne $base){[string]$base}else{''}
  $isDeclarative=Read-Property $a 'IsDeclarative'
  if($null -eq $isDeclarative -and $null -ne $t){$isDeclarative=Read-Property $t 'IsDeclarative'}
  [pscustomobject]@{
    Scope=$scope;Owner=$owner;Id=[string](Read-Property $a 'Id')
    Name=[string](Read-Property $a 'Name')
    BaseTemplateId=$templateId
    TemplateName=[string](Read-Property $t 'Name')
    IsDeclarative=$isDeclarative
    Enabled=[bool](Read-Property $a 'Enabled')
    AutoStartCreate=[bool](Read-Property $a 'AutoStartCreate')
    AutoStartChange=[bool](Read-Property $a 'AutoStartChange')
    AllowManual=[bool](Read-Property $a 'AllowManual')
    DefinitionLinked=$false
    LinkEvidence='NOT_RESOLVED'
  }
}
$web=$null;$ctx=$null
try{
  $web=Get-SPWeb -Identity $WebUrl -ErrorAction Stop
  $assoc=New-Object 'System.Collections.Generic.List[object]'
  try{
    foreach($a in $web.WorkflowAssociations){$assoc.Add((Association-Row $a 'SITE' ([string]$web.ID)))}
    foreach($ct in $web.ContentTypes){
      foreach($a in $ct.WorkflowAssociations){
        $assoc.Add((Association-Row $a 'CONTENT_TYPE' ([string]$ct.Id)))
      }
    }
    $lists=@($web.Lists)
    $r.Coverage.ListsTotal=$lists.Count
    foreach($list in @($lists | Select-Object -First $MaxLists)){
      try {
        $owner=''+$list.ID
        foreach($a in $list.WorkflowAssociations){
          $assoc.Add((Association-Row $a 'LIST' $owner))
        }
        $r.Coverage.ListsScanned++
      }catch {Record-Failure 'AssociationList' $_.Exception}
    }
    $r.Coverage.ListsTruncated=($lists.Count -gt $MaxLists)
    $r.Coverage.Workflow2010=$(if($r.Coverage.ListsTruncated){'PARTIAL_LIMIT'}elseif(@($errors|Where-Object {$_.Section -eq 'AssociationList'}).Count -gt 0){'PARTIAL_ERRORS'}else{'OK'})
  }catch{Record-Failure 'Associations2010' $_.Exception;$r.Coverage.Workflow2010='FAILED'}
  $r.Associations2010=@($assoc.ToArray())

  # Declarative SPD 2010 workflows usually live in the hidden site-level 'Workflows'
  # library. These artifacts are inventoried INDEPENDENTLY. Name matching is not
  # a safe binding to SPWorkflowAssociation — this collector never guesses one.
  try{
    $wfFolder=$web.GetFolder('Workflows')
    if($null -eq $wfFolder -or -not $wfFolder.Exists){
      $r.Coverage.Workflow2010Markup='NOT_FOUND'
    }else{
      $stack=New-Object 'System.Collections.Generic.Stack[object]'
      $stack.Push($wfFolder)
      $items=New-Object 'System.Collections.Generic.List[object]'
      $seen=0
      while($stack.Count -gt 0){
        $f=$stack.Pop()
        foreach($sub in $f.SubFolders){
          if($sub.Name -ne 'Forms'){$stack.Push($sub)}
        }
        foreach($file in $f.Files){
          $ext=[IO.Path]::GetExtension([string]$file.Name).ToLowerInvariant()
          if($ext -notin @('.xoml','.xaml','.rules','.xml','.wfconfig')){continue}
          if($seen -ge $MaxMarkupFiles){$r.Coverage.MarkupFilesTruncated=$true;break}
          $seen++
          $row=[ordered]@{
            Path=[string]$file.ServerRelativeUrl
            Length=[int64]$file.Length
            Extension=$ext
            Parse='NOT_READ';Elements=0;Categories=@();ActionHints=@()
            SignatureHash=$null;Unclassified=$true
          }
          if([int64]$file.Length -gt $MaxMarkupBytes){$row.Parse='OVERSIZE'}
          else{
            try{
              $bytes=$file.OpenBinary()
              $raw=[Text.Encoding]::UTF8.GetString($bytes)
              $detail=Inspect-Markup $raw $ext
              $row.Parse=$detail.Parse;$row.Elements=$detail.Elements
              $row.Categories=$detail.Categories;$row.ActionHints=$detail.ActionHints
              $row.SignatureHash=$detail.SignatureHash;$row.Unclassified=$detail.Unclassified
            }catch{ $row.Parse='FAILED';Record-Failure 'MarkupParse' $_.Exception}
          }
          $items.Add([pscustomobject]$row)
        }
        if($seen -ge $MaxMarkupFiles){break}
      }
      $r.MarkupArtifacts2010=@($items.ToArray())
      $r.Coverage.MarkupFilesExamined=$seen
      $r.Coverage.Workflow2010Markup=$(if($r.Coverage.MarkupFilesTruncated){'PARTIAL_LIMIT'}else{'OK'})
    }
  }catch{Record-Failure 'WorkflowLibrary' $_.Exception;$r.Coverage.Workflow2010Markup='FAILED'}

  # 2013 workflow is a distinct engine. Failures are UNKNOWN, not 0 workflows.
  try{
    $isapi=Join-Path $env:CommonProgramFiles 'Microsoft Shared\Web Server Extensions\16\ISAPI'
    foreach($dll in @('Microsoft.SharePoint.Client.Runtime.dll','Microsoft.SharePoint.Client.dll',
                      'Microsoft.SharePoint.Client.WorkflowServices.dll')){
      $name=[IO.Path]::GetFileNameWithoutExtension($dll)
      if(@([AppDomain]::CurrentDomain.GetAssemblies() |
          Where-Object {$_.GetName().Name -eq $name}).Count -eq 0){
        Add-Type -Path (Join-Path $isapi $dll) -ErrorAction Stop
      }
    }
    $ctx=New-Object Microsoft.SharePoint.Client.ClientContext($web.Url)
    $ctx.Credentials=[Net.CredentialCache]::DefaultNetworkCredentials
    $mgr=New-Object Microsoft.SharePoint.Client.WorkflowServices.WorkflowServicesManager($ctx,$ctx.Web)
    $ss=$mgr.GetWorkflowSubscriptionService()
    $subs=$ss.EnumerateSubscriptions()
    $ctx.Load($subs);$ctx.ExecuteQuery()
    $subscriptions=New-Object 'System.Collections.Generic.List[object]'
    $defs=New-Object 'System.Collections.Generic.List[object]'
    $definitionIds=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($sub in $subs){
      $id=[string]$sub.DefinitionId
      $subscriptions.Add([pscustomobject]@{
        Id=[string]$sub.Id;Name=[string]$sub.Name
        DefinitionId=$id;EventSourceId=[string]$sub.EventSourceId
        Enabled=[bool]$sub.Enabled
        EventTypes=@($sub.EventTypes | ForEach-Object {[string]$_})
      })
      if($id -and $id -ne [guid]::Empty.ToString()){[void]$definitionIds.Add($id)}
    }
    $r.Subscriptions2013=@($subscriptions.ToArray())
    $deploy=$mgr.GetWorkflowDeploymentService()
    foreach($id in $definitionIds){
      if($r.Coverage.Definitions2013Examined -ge $Max2013Definitions){
        $r.Coverage.Definitions2013Truncated=$true;break
      }
      $r.Coverage.Definitions2013Examined++
      try{
        $def=$deploy.GetDefinition([guid]$id)
        $ctx.Load($def)
        $ctx.ExecuteQuery()
        $xaml=[string]$def.Xaml
        $row=[ordered]@{
          Id=$id;DisplayName=[string]$def.DisplayName;Published=[bool]$def.Published
          Parse='MISSING';Elements=0;Categories=@();ActionHints=@()
          SignatureHash=$null;Unclassified=$true
        }
        if($xaml.Length -gt $MaxMarkupBytes){$row.Parse='OVERSIZE'}
        elseif($xaml){
          $profile=Inspect-Markup $xaml '.xaml'
          $row.Parse=$profile.Parse;$row.Elements=$profile.Elements
          $row.Categories=$profile.Categories;$row.ActionHints=$profile.ActionHints
          $row.SignatureHash=$profile.SignatureHash;$row.Unclassified=$profile.Unclassified
        }
        $defs.Add([pscustomobject]$row)
      }catch{Record-Failure 'Definition2013' $_.Exception}
    }
    $r.Definitions2013=@($defs.ToArray())
    $r.Coverage.Workflow2013=$(if($r.Coverage.Definitions2013Truncated){'PARTIAL_LIMIT'}elseif(@($errors|Where-Object {$_.Section -eq 'Definition2013'}).Count -gt 0){'PARTIAL_ERRORS'}else{'OK'})
  }catch{
    Record-Failure 'Workflow2013' $_.Exception
    $r.Coverage.Workflow2013='FAILED'
  }
}finally{
  if($null -ne $ctx){$ctx.Dispose()}
  if($null -ne $web){$web.Dispose()}
}
$r.Errors=@($errors.ToArray())
$r.Finished=(Get-Date).ToString('s')
$target=Join-Path $folder 'WorkflowDefinitions_PRIVATE.json'
$r|ConvertTo-Json -Depth 20|Out-File -LiteralPath $target -Encoding UTF8 -ErrorAction Stop
Write-Host ('PRIVATE INVENTORY: '+$target) -ForegroundColor Green
Write-Host ('2010 associations: '+@($r.Associations2010).Count+'; XOML files: '+@($r.MarkupArtifacts2010).Count+
            '; 2013 definitions: '+@($r.Definitions2013).Count+'; errors: '+$errors.Count)
Write-Warning 'CONFIDENTIAL: names, paths and server errors stay local. Run New-SPWorkflowMigrationReport.ps1 to build HTML and shareable MD.'
