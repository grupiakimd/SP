#requires -Version 5.1
<#
.SYNOPSIS
    Wykrywa tylko lokalne reguly przekazywania/przekierowania poczty Outlook.
.DESCRIPTION
    Audyt TYLKO DO ODCZYTU. Wyswietla reguly, dla ktorych:
      Rule.IsLocalRule = True
      oraz co najmniej jedna z akcji Forward, ForwardAsAttachment,
      Redirect ma Enabled = True.

    Uwzglednia takze wylaczone reguly (kolumna Aktywna), jesli ich
    akcja przekazywania jest skonfigurowana i wlaczona.

    Wymaga otwartego klasycznego Outlooka w tej samej sesji uzytkownika
    oraz Windows PowerShell 5.1 w trybie STA. Nie uruchamiac jako SYSTEM.
    Magazyny nieobslugujace regul (np. Listy SharePoint) sa pomijane.
    Nie obejmuje przekazywania implementowanego przez VBA/makra/dodatki.

.EXAMPLE
    powershell.exe -NoProfile -STA -File ".\Get-OutlookLocalForwardRules.ps1"

.NOTES
    Kod wyjscia:
      0 = pelny audyt obslugiwanych magazynow
      1 = brak dostepu do dzialajacego Outlooka / zly PowerShell
      2 = audyt niepelny, wystapily nieoczekiwane bledy odczytu

    https://learn.microsoft.com/en-us/office/vba/api/outlook.rule.islocalrule
    https://learn.microsoft.com/en-us/office/vba/api/outlook.sendruleaction
#>

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -ne 'Desktop' -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -ne 'STA') {
    Write-Error 'Uruchom w Windows PowerShell 5.1: powershell.exe -NoProfile -STA -File ...'
    exit 1
}

function Get-OutlookRecipientAddress {
    param($Recipient)

    $fallback = ''
    try { $fallback = [string]$Recipient.Address } catch { }

    if ($fallback -match '@') { return $fallback }

    try {
        $entry = $Recipient.AddressEntry
        if ($null -ne $entry) {
            # PR_SMTP_ADDRESS - probujemy odczytac rzeczywisty adres SMTP.
            try {
                $smtp = [string]$entry.PropertyAccessor.GetProperty(
                    'http://schemas.microsoft.com/mapi/proptag/0x39FE001E'
                )
                if ($smtp -match '@') { return $smtp }
            }
            catch { }

            if ([string]$entry.Type -eq 'EX') {
                try {
                    $user = $entry.GetExchangeUser()
                    if ($null -ne $user -and $user.PrimarySmtpAddress) {
                        return [string]$user.PrimarySmtpAddress
                    }
                }
                catch { }

                try {
                    $group = $entry.GetExchangeDistributionList()
                    if ($null -ne $group -and $group.PrimarySmtpAddress) {
                        return [string]$group.PrimarySmtpAddress
                    }
                }
                catch { }
            }
        }
    }
    catch { }

    if (-not [string]::IsNullOrWhiteSpace($fallback)) { return $fallback }

    try {
        if ($Recipient.Name) { return ('[Nazwa: {0}]' -f $Recipient.Name) }
    }
    catch { }

    return '[nie ustalono adresu]'
}

try {
    # Podlacz do juz uruchomionego Outlooka; nie tworz nowego profilu.
    $outlook = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $stores = $outlook.Session.Stores
}
catch {
    Write-Error ('Nie mozna polaczyc z klasycznym Outlookiem: {0}' -f $_.Exception.Message)
    exit 1
}

$results = [Collections.Generic.List[object]]::new()
$ruleCount = 0
$checked = 0
$skipped = 0
$errors = 0

for ($s = 1; $s -le $stores.Count; $s++) {
    $storeName = 'Magazyn #{0}' -f $s

    try {
        $store = $stores.Item($s)
        $storeName = [string]$store.DisplayName
        $rules = $store.GetRules()
        $checked++
    }
    catch {
        $message = [string]$_.Exception.Message

        # Magazyn SharePoint i inne bez obslugi regul: oczekiwane.
        if ($message -match '(?i)(does not support rules|rules are not supported|nie obs[łl]uguje regu[łl])') {
            $skipped++
            Write-Host ('Pominieto magazyn bez obslugi regul: {0}' -f $storeName)
        }
        else {
            $errors++
            Write-Warning ('Nie odczytano magazynu "{0}": {1}' -f $storeName, $message)
        }
        continue
    }

    for ($i = 1; $i -le $rules.Count; $i++) {
        try {
            $rule = $rules.Item($i)
            if (-not [bool]$rule.IsLocalRule) { continue }

            $hasForward = $false
            foreach ($kind in @('Forward', 'ForwardAsAttachment', 'Redirect')) {
                switch ($kind) {
                    'Forward'             { $action = $rule.Actions.Forward }
                    'ForwardAsAttachment' { $action = $rule.Actions.ForwardAsAttachment }
                    'Redirect'            { $action = $rule.Actions.Redirect }
                }

                if (-not [bool]$action.Enabled) { continue }
                $hasForward = $true

                $addresses = [Collections.Generic.List[string]]::new()
                $recipients = $action.Recipients

                for ($r = 1; $r -le $recipients.Count; $r++) {
                    $addresses.Add([string](Get-OutlookRecipientAddress -Recipient $recipients.Item($r)))
                }

                $recipientsText = if ($addresses.Count -gt 0) {
                    [string]::Join('; ', [string[]]$addresses.ToArray())
                }
                else {
                    '[brak odbiorcow]'
                }

                $results.Add([pscustomobject]@{
                    Skrzynka   = $storeName
                    Regula     = [string]$rule.Name
                    Aktywna    = [bool]$rule.Enabled
                    Typ        = $kind
                    Odbiorcy   = $recipientsText
                })
            }

            if ($hasForward) { $ruleCount++ }
        }
        catch {
            $errors++
            Write-Warning ('Blad odczytu reguly #{0} w "{1}": {2}' -f $i, $storeName, $_.Exception.Message)
        }
    }
}

Write-Host ''
Write-Host ('Komputer: {0} | Uzytkownik: {1}\{2}' -f $env:COMPUTERNAME, $env:USERDOMAIN, $env:USERNAME)
Write-Host ('Magazyny: sprawdzone {0}, pominiete bez obslugi regul {1}, bledy {2}' -f $checked, $skipped, $errors)
Write-Host ('Lokalne reguly z akcja forward/redirect: {0}' -f $ruleCount)
Write-Host ''

if ($results.Count -gt 0) {
    $results.ToArray() | Format-Table -Property Skrzynka, Regula, Aktywna, Typ, Odbiorcy -AutoSize -Wrap
}
elseif ($errors -eq 0) {
    Write-Host 'Nie znaleziono lokalnych regul Forward, ForwardAsAttachment ani Redirect.'
}

if ($errors -gt 0 -or $checked -eq 0) {
    Write-Warning 'AUDYT NIEPELNY. Wynik nie potwierdza braku przekierowan.'
    exit 2
}

# Brak operacji Save/Remove/Resolve: skrypt nie modyfikuje profilu/regul.
exit 0
