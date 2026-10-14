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
# Package SHA512 values pinned from official NuGet nupkg content.
$expectedHashes=@{
  'system.runtime.compilerservices.unsafe'='t2aXWJZBkAkRrTOnw31OBELKEVSDD5YvC3O5dXaHFsR66/nRTKm1y3Iq6NwFI5u5IlKrWYfdan66V+GKKkY8hQ=='
  'system.numerics.vectors'='/rkvpUeUPlCY/2qYVQKiUsj5IKaXZcy2+SQAGAfemAdyEF5AgIgYOFNSTMWDXo09JWFX9HB+wV1yCyi2Mwi3TA=='
  'system.buffers'='qve/dFwECwehSWlZmpkrrlIeATCvo/Hw2koyMrUVcDBy5gXAQrnwX8pHEoqgj8DgkrWuWW1DrQbFqoMbo+Fvrg=='
  'system.memory'='NXcNYlWoXe5cz9sb8Huo6x2dCZVYkhwKtgE00n/MoI8V4ZI/7/t+EI5bOhQFlZfFjjqM8+U6prjU/aARt7H/tA=='
  'system.threading.tasks.extensions'='zWRHXIBnbfzQE1SamNoW9X5NjEcW/JNAtvVxGKd3bcg71wQVmoI3pDq+WUa2A+temXSNCm7707hmAFwwcYlK0A=='
  'system.formats.asn1'='BmMIpT6SEmFhYntSyWjEV14uTdPj11cyPzaqn3nr+v4mcRStpRQ5g3siendvADafgOGevAdIKCDmwoqJ6zkQ7g=='
  'bouncycastle.cryptography'='Thoy+Tfuu6E08cZkbAtVTtqhvEGWnexYFtEcPChZBuEGN3ET6mwcsLFhdJ/wiuitOd8FlWtiq+InTUswYPDa7w=='
  'mimekit'='uH/TEqa5XnbxCid4CXk12IhCwUvbg11erqOBLEmQ2fC6Nn/ksY6mYevbPB+GiC+FE7v8d5lfdBmil+UF7mxJ5g=='
  'mailkit'='eOy/ZDcmdeD76anXpviyZYynl7k45FhwWIQAHU8W0/uyeKbsKo2MEtQUmD5n2wHeQAGzKCcIRt2LjZJXLC6kPw=='
}
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
    $stream=[IO.File]::OpenRead($pkg)
    try {
      $sha=[Security.Cryptography.SHA512]::Create()
      try { $actual=[Convert]::ToBase64String($sha.ComputeHash($stream)) }
      finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
    if(-not $expectedHashes.ContainsKey($id) -or $actual -cne $expectedHashes[$id]){
      throw "NuGet SHA512 niezgodne z przypiętą wersją: $($p.Id) $version"
    }
    Write-Host "PASS SHA512: $($p.Id) $version"
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
