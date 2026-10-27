#requires -Version 5.1
# Read-only SharePoint SE site collection and upgrade status diagnostics.
# Run in SharePoint Management Shell on the target farm.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl
)

$ErrorActionPreference = 'Stop'
Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue

$site = Get-SPSite -Identity $SiteUrl -ErrorAction Stop

try {
    Write-Host "`n=== STAN KOLEKCJI ===" -ForegroundColor Cyan

    $site |
        Select-Object Url, NeedsUpgrade, NeedsUpgradeIncludeChildren |
        Format-List

    Write-Host "`n=== OSTATNIA SESJA KOLEKCJI ===" -ForegroundColor Cyan

    Get-SPSiteUpgradeSessionInfo -Site $site |
        Select-Object Status, UpgradeType, Errors, Warnings,
            RequestDate, StartTime, LastUpdated |
        Format-List
}
finally {
    $site.Dispose()
}

Write-Host "`n=== LOGI AKTUALIZACJI ===" -ForegroundColor Cyan

$logDir = Join-Path ${env:CommonProgramFiles} `
    "Microsoft Shared\Web Server Extensions\16\LOGS"

Get-ChildItem -Path $logDir -File |
    Where-Object {
        $_.Name -match '^(Upgrade|SiteUpgrade).*\.log$'
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10 Name, LastWriteTime |
    Format-Table -AutoSize
