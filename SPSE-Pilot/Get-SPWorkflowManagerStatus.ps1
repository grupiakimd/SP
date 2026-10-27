# Read-only check of the SharePoint Workflow Manager connection on SPSETEST.
# Run from SharePoint Management Shell.

$site = Get-SPSite "http://spsetest/sites/kampaniedsd" -ErrorAction Stop

try {
    $proxy = Get-SPWorkflowServiceApplicationProxy

    if ($null -eq $proxy) {
        Write-Host "BRAK Workflow Manager w farmie SE" -ForegroundColor Red
    }
    else {
        Write-Host "Workflow Proxy: $($proxy.Name)" -ForegroundColor Green

        try {
            $adres = $proxy.GetWorkflowServiceAddress($site)
            Write-Host "Adres Workflow Manager: $adres" -ForegroundColor Cyan
        }
        catch {
            Write-Host "BLAD polaczenia: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
finally {
    $site.Dispose()
}
