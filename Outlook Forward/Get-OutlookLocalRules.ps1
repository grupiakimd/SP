#requires -Version 5.1
<#
.SYNOPSIS
    Wykrywa reguly "tylko na tym komputerze" w klasycznym Outlooku.
.DESCRIPTION
    Tylko odczyt: nie tworzy, nie modyfikuje ani nie usuwa regul.
    Przeglada wszystkie magazyny w aktualnie otwartym profilu Outlooka
    i wyswietla reguly, dla ktorych Outlook Rule.IsLocalRule = True.

    IsLocalRule oznacza REGULE WYKONYWANA LOKALNIE. Nie oznacza
    koniecznie, ze jej definicja jest przechowywana w pliku na dysku.

    Wymaga klasycznego Outlooka otwartego w tej samej sesji uzytkownika.
    Uruchamiac w Windows PowerShell 5.1 (STA), nie jako SYSTEM ani
    w sesji nieinteraktywnej GPO Startup.
.EXAMPLE
    powershell.exe -NoProfile -STA -File ".\Get-OutlookLocalRules.ps1"
.NOTES
    Exit code:
      0 - odczyt wszystkich magazynow powiodl sie (takze gdy brak regul)
      1 - Outlook niedostepny / niewlasciwe srodowisko
      2 - odczyt niepelny; nie traktuj wyniku jako kompletnego audytu

    Dokumentacja:
    https://learn.microsoft.com/en-us/office/vba/api/outlook.rule.islocalrule
    https://learn.microsoft.com/en-us/office/vba/api/outlook.store.getrules
#>

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Error 'Uzyj Windows PowerShell 5.1 (powershell.exe), nie PowerShell 7 (pwsh.exe).'
    exit 1
}

if ([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -ne 'STA') {
    Write-Error 'Uruchom skrypt z parametrem -STA.'
    exit 1
}

try {
    # Polacz z juz uruchomionym Outlookiem; NIE uruchamiaj nowej instancji.
    $outlook = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $stores = $outlook.Session.Stores
}
catch {
    Write-Error ('Nie mozna polaczyc z otwartym klasycznym Outlookiem w sesji tego uzytkownika: {0}' -f $_.Exception.Message)
    exit 1
}

$results = [System.Collections.Generic.List[object]]::new()
$checkedStores = 0
$errors = 0

for ($s = 1; $s -le $stores.Count; $s++) {
    $storeName = ('Magazyn #{0}' -f $s)

    try {
        $store = $stores.Item($s)
        $storeName = [string]$store.DisplayName
        $rules = $store.GetRules()
        $checkedStores++

        for ($i = 1; $i -le $rules.Count; $i++) {
            try {
                $rule = $rules.Item($i)

                if ([bool]$rule.IsLocalRule) {
                    $results.Add([pscustomobject]@{
                        Skrzynka = $storeName
                        Regula   = [string]$rule.Name
                        Aktywna  = [bool]$rule.Enabled
                        Lokalna  = $true
                    })
                }
            }
            catch {
                $errors++
                Write-Warning ('Nie odczytano reguly #{0} w "{1}": {2}' -f $i, $storeName, $_.Exception.Message)
            }
        }
    }
    catch {
        $errors++
        Write-Warning ('Nie odczytano regul magazynu "{0}": {1}' -f $storeName, $_.Exception.Message)
    }
}

Write-Host ''
Write-Host ('Komputer: {0} | Uzytkownik: {1}\{2}' -f $env:COMPUTERNAME, $env:USERDOMAIN, $env:USERNAME)
Write-Host ('Sprawdzone magazyny: {0}/{1}' -f $checkedStores, $stores.Count)
Write-Host ('Wykryte reguly lokalne: {0}' -f $results.Count)
Write-Host ''

if ($results.Count -gt 0) {
    $results.ToArray() | Format-Table -Property Skrzynka, Regula, Aktywna, Lokalna -AutoSize -Wrap
}
elseif ($errors -eq 0) {
    Write-Host 'Nie znaleziono regul dzialajacych tylko w kliencie Outlook.'
}

if ($errors -gt 0 -or $checkedStores -eq 0) {
    Write-Warning ('Audyt NIEPELNY: bledy odczytu = {0}. Brak wyniku nie dowodzi braku regul.' -f $errors)
    exit 2
}

# Nigdy nie wywoluj Rules.Save(), Rules.Remove() ani Outlook /cleanrules.
exit 0
