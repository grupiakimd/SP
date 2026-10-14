#requires -Version 5.1
# Optional PDF export using Microsoft Edge installed on the execution host.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$InputHtml,
  [Parameter(Mandatory)][string]$OutputPdf,
  [string]$EdgePath
)
$ErrorActionPreference='Stop'
if(-not (Test-Path -LiteralPath $InputHtml -PathType Leaf)){throw "HTML report not found: $InputHtml"}
$inputAbsolute=[IO.Path]::GetFullPath($InputHtml)
$outputAbsolute=[IO.Path]::GetFullPath($OutputPdf)
[void][IO.Directory]::CreateDirectory((Split-Path -Path $outputAbsolute -Parent))
$candidates=New-Object 'System.Collections.Generic.List[string]'
if($EdgePath){$candidates.Add($EdgePath)}
$programFilesX86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
if($programFilesX86){$candidates.Add((Join-Path $programFilesX86 'Microsoft\Edge\Application\msedge.exe'))}
if($env:ProgramFiles){$candidates.Add((Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'))}
$edge=$null
foreach($candidate in $candidates){if(Test-Path -LiteralPath $candidate -PathType Leaf){$edge=$candidate;break}}
if(-not $edge){throw 'Brak Microsoft Edge na komputerze audytowym. Raport HTML nadal można wydrukować do PDF w przeglądarce.'}
$profile=Join-Path $env:TEMP ('exchange-audit-pdf-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($profile)
$process=$null
try{
  if(Test-Path -LiteralPath $outputAbsolute){Remove-Item -LiteralPath $outputAbsolute -Force}
  $uri=([uri]$inputAbsolute).AbsoluteUri
  $arguments=@(
    '--headless','--disable-gpu','--disable-extensions','--no-first-run','--no-default-browser-check',
    '--disable-background-networking','--no-pdf-header-footer',
    ('--user-data-dir="{0}"' -f $profile),
    ('--print-to-pdf="{0}"' -f $outputAbsolute),
    ('"{0}"' -f $uri)
  )
  $process=Start-Process -FilePath $edge -ArgumentList $arguments -PassThru -WindowStyle Hidden -ErrorAction Stop
  if(-not $process.WaitForExit(60000)){
    try{$process.Kill()}catch{}
    throw 'Timeout generowania PDF przez Microsoft Edge (60 sekund).'
  }
  if(-not (Test-Path -LiteralPath $outputAbsolute -PathType Leaf)){
    throw "Microsoft Edge nie wygenerował PDF (ExitCode: $($process.ExitCode))."
  }
  $file=Get-Item -LiteralPath $outputAbsolute
  if($file.Length -lt 150){throw 'PDF jest pusty lub niepoprawny.'}
  Write-Host "PDF: $outputAbsolute"
}finally{
  if($process){$process.Dispose()}
  Remove-Item -LiteralPath $profile -Force -Recurse -ErrorAction SilentlyContinue
}
