#requires -Version 5.1
<#
Installs pinned, .NET Framework assemblies for MailKit once, on the execution host.
The audit NEVER downloads dependencies at runtime. Uses official nuget.org TLS endpoint
and verifies each package against its SHA512 from the NuGet flat-container feed.
#>
[CmdletBinding()]
param([string]$Destination=(Join-Path $PSScriptRoot 'Dependencies\MailKit\lib'))
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
# Windows PowerShell 5.1 + .NET Framework 4.8 (needed for this supported deployment).
$releaseKey=Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop
if([int]$releaseKey -lt 528040){throw 'MailKit: zainstaluj .NET Framework 4.8 lub nowszy na komputerze uruchamiającym audyt.'}
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
$packages=@(
  @{Id='System.Runtime.CompilerServices.Unsafe';Version='6.1.2';Assembly='System.Runtime.CompilerServices.Unsafe'}
  @{Id='System.Numerics.Vectors';Version='4.6.1';Assembly='System.Numerics.Vectors'}
  @{Id='System.Buffers';Version='4.6.1';Assembly='System.Buffers'}
  @{Id='System.Memory';Version='4.6.3';Assembly='System.Memory'}
  @{Id='System.Threading.Tasks.Extensions';Version='4.6.3';Assembly='System.Threading.Tasks.Extensions'}
  @{Id='System.Formats.Asn1';Version='8.0.1';Assembly='System.Formats.Asn1'}
  @{Id='BouncyCastle.Cryptography';Version='2.6.2';Assembly='BouncyCastle.Cryptography'}
  @{Id='MimeKit';Version='4.17.0';Assembly='MimeKit'}
  @{Id='MailKit';Version='4.17.0';Assembly='MailKit'}
)
[void][IO.Directory]::CreateDirectory($Destination)
$destinationAbsolute=[IO.Path]::GetFullPath($Destination)
$frameworks=@('net48','net47','net462','net461','net46','net45','netstandard2.0')
$tempDir=Join-Path ([IO.Path]::GetTempPath()) ('mailkit-install-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tempDir)
$manifest=New-Object 'System.Collections.Generic.List[object]'
try {
  foreach($p in $packages){
    $id=([string]$p.Id).ToLowerInvariant()
    $version=[string]$p.Version
    $baseUrl="https://api.nuget.org/v3-flatcontainer/$id/$version/$id.$version.nupkg"
    $pkg=Join-Path $tempDir "$id.$version.nupkg"
    Write-Host "NuGet: $($p.Id) $version"
    Invoke-WebRequest -Uri $baseUrl -OutFile $pkg -UseBasicParsing -ErrorAction Stop
    $expected=(Invoke-WebRequest -Uri ($baseUrl+'.sha512') -UseBasicParsing -ErrorAction Stop).Content.Trim()
    $stream=[IO.File]::OpenRead($pkg)
    try {
      $sha=[Security.Cryptography.SHA512]::Create()
      try { $actual=[Convert]::ToBase64String($sha.ComputeHash($stream)) }
      finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
    if($expected -ne $actual){throw "NuGet SHA512 mismatch: $($p.Id) $version"}
    $zip=[IO.Compression.ZipFile]::OpenRead($pkg)
    try {
      $entry=$null
      foreach($tfm in $frameworks){
        $wanted="lib/$tfm/$($p.Assembly).dll"
        $entry=@($zip.Entries | Where-Object { $_.FullName -ieq $wanted } | Select-Object -First 1)
        if($entry.Count){$entry=$entry[0];break}
        $entry=$null
      }
      if(-not $entry){throw "NuGet: brak biblioteki .NET Framework $($p.Assembly).dll w $($p.Id) $version"}
      $destinationFile=Join-Path $destinationAbsolute ($p.Assembly+'.dll')
      $entryStream=$entry.Open()
      $out=[IO.File]::Open($destinationFile,[IO.FileMode]::Create,[IO.FileAccess]::Write)
      try{$entryStream.CopyTo($out)}finally{$entryStream.Dispose();$out.Dispose()}
      if((Get-Item -LiteralPath $destinationFile).Length -lt 1000){throw "Pusty DLL: $destinationFile"}
      $manifest.Add([pscustomobject]@{Package=$p.Id;Version=$version;Target=$entry.FullName;NuGetSha512=$actual})
    }finally{$zip.Dispose()}
  }
  $manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $destinationAbsolute 'manifest.json') -Encoding UTF8
  Write-Host "Zainstalowano $($packages.Count) zależności w: $destinationAbsolute"
  Write-Host 'Audyt SMTP MailKit może teraz działać offline; nie pobiera bibliotek podczas skanowania.'
}finally{
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
