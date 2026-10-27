#requires -Version 5.1
# Read-only inventory of lists in one SharePoint SPWeb.
# Run on SharePoint 2019 and SharePoint SE with the relevant URLs.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if (-not (Get-PSSnapin -Name 'Microsoft.SharePoint.PowerShell' -ErrorAction SilentlyContinue)) {
    Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction Stop
}

$web = Get-SPWeb -Identity $SiteUrl -ErrorAction Stop

try {
    $lists = @(
        foreach ($list in $web.Lists) {
            [PSCustomObject]@{
                ID       = $list.ID.ToString()
                Title    = $list.Title
                Hidden   = $list.Hidden
                BaseType = $list.BaseType.ToString()
            }
        }
    )

    $lists |
        Sort-Object ID |
        Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

    Write-Host "Site: $($web.Url)"
    Write-Host "List count: $($lists.Count)"
    Write-Host "Saved: $OutputPath"
}
finally {
    $web.Dispose()
}
