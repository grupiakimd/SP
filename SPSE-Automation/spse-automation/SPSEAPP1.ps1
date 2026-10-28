# TYLKO SPSEAPP1. Nie wykonuje operacji administracyjnych na innych hostach.
param(
    [ValidateSet('Audit','WindowsFeatures','SqlAlias','Prerequisites','InstallCore','InstallPolishLP','InstallCU','CreateFarm','JoinFarm','AuditFarm')]
    [string]$Step='Audit',
    [switch]$AcceptLicenseTerms,
    [string]$WindowsSource=''
)
& "$PSScriptRoot\Invoke-SPSELocal.ps1" -ExpectedHost 'SPSEAPP1' -Step $Step -AcceptLicenseTerms:$AcceptLicenseTerms -WindowsSource $WindowsSource
