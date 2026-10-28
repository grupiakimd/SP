# TYLKO SPSEWFE2. Nie wykonuje operacji administracyjnych na innych hostach.
param(
    [ValidateSet('Audit','WindowsFeatures','SqlAlias','Prerequisites','InstallCore','InstallPolishLP','InstallCU','CreateFarm','JoinFarm','AuditFarm')]
    [string]$Step='Audit',
    [switch]$AcceptLicenseTerms,
    [string]$WindowsSource=''
)
& "$PSScriptRoot\Invoke-SPSELocal.ps1" -ExpectedHost 'SPSEWFE2' -Step $Step -AcceptLicenseTerms:$AcceptLicenseTerms -WindowsSource $WindowsSource
