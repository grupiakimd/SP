#requires -Version 5.1
<#
.SYNOPSIS
  Tworzy publiczne repozytorium grupiakimd/SP i publikuje ten pakiet.
.REQUIREMENTS
  Zainstalowane git i GitHub CLI (gh). Logowanie do gh jest interaktywne.
.DESCRIPTION
  Uruchom z rozpakowanego katalogu projektu, nie na serwerze SharePoint.
  Nie publikuje wynikow produkcyjnego audytu.
#>
[CmdletBinding()]
param(
    [string]$Owner = 'grupiakimd',
    [string]$Repo = 'SP'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Brak programu '$Name'. Zainstaluj go przed publikacja."
    }
}
function Invoke-Checked([string]$Exe, [string[]]$ArgsToRun) {
    & $Exe @ArgsToRun
    if ($LASTEXITCODE -ne 0) { throw "$Exe zwrocil kod bledu $LASTEXITCODE." }
}
Require-Command 'git'
Require-Command 'gh'

$required = @('README.md', '.gitignore', 'CHANGELOG.md', 'v1\Invoke-SP2019ReadinessAudit.ps1', 'v2\Invoke-SP2019ReadinessAudit.ps1', 'v2\New-SPSEDashboard.ps1', 'v2\dashboard_template.html')
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $relative) -PathType Leaf)) {
        throw "Brak wymaganego pliku: $relative. Rozpakuj cale archiwum."
    }
}

Push-Location -LiteralPath $PSScriptRoot
try {
    Write-Host 'Sprawdzanie logowania GitHub...' -ForegroundColor Cyan
    $ErrorActionPreference = 'Continue'
    & gh auth status --hostname github.com *> $null
    $authStatus = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($authStatus -ne 0) {
        Write-Host 'Zaloguj sie do GitHub w oknie przegladarki...' -ForegroundColor Yellow
        Invoke-Checked 'gh' @('auth','login','--hostname','github.com','--web')
    }

    $target = "$Owner/$Repo"
    if (Test-Path -LiteralPath '.git') { throw 'W tym katalogu istnieje .git. Przerwano dla bezpieczenstwa.' }
    Invoke-Checked 'git' @('init','-b','main')
    Invoke-Checked 'git' @('add','--','README.md','CHANGELOG.md','.gitignore','Publish-SP.ps1','v1','v2')

    $staged = & git diff --cached --name-only
    if ($LASTEXITCODE -ne 0 -or -not $staged) { throw 'Brak plikow do commita.' }
    if (@($staged | Where-Object { $_ -notmatch '^(README\.md|CHANGELOG\.md|\.gitignore|Publish-SP\.ps1|v1/|v2/)' }).Count -gt 0) {
        throw 'Wykryto nieoczekiwane pliki do publikacji. Przerwano.'
    }
    Write-Host 'Pliki do publikacji:' -ForegroundColor Cyan
    $staged | ForEach-Object { Write-Host "  $_" }

    Invoke-Checked 'git' @('commit','-m','Initial release: SharePoint 2019 to SE audit v1 and v2')
    Write-Host "Tworzenie PUBLICZNEGO repozytorium $target i publikacja..." -ForegroundColor Cyan
    Invoke-Checked 'gh' @('repo','create',$target,'--public','--source','.','--remote','origin','--push','--description','SharePoint 2019 to Subscription Edition migration readiness audit (PowerShell, HTML)')
    Invoke-Checked 'gh' @('repo','view',$target,'--json','nameWithOwner,visibility,url')
    Write-Host "Gotowe: https://github.com/$target" -ForegroundColor Green
}
finally { Pop-Location }
