# SharePoint SE - nocny audyt (v2.2.1)

Pliki:
- **Run-SPAudit-Night.ps1** - uruchamia pelny audyt, zapisuje lokalny log, kontroluje wyniki.
- **Register-SPAuditTask.ps1** - rejestruje jednorazowe zadanie Windows Task Scheduler.

## Instalacja offline

GitHub: Code -> Download ZIP. Przenies **caly** katalog v2.2 do:

    C:\temp\sprawdzenie\v22

Oczekiwany uklad:

    C:\temp\sprawdzenie\v22\
      Invoke-SP2019ReadinessAudit.ps1
      New-SPSEDashboard.ps1
      New-SPSEShareableAudit.ps1
      dashboard_template.html
      scheduler\
        Register-SPAuditTask.ps1
        Run-SPAudit-Night.ps1

Na APP (ewentualnie WFE) SharePoint 2019 uruchom Windows PowerShell 5.1 64-bit jako administrator:

    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    & "C:\temp\sprawdzenie\v22\scheduler\Register-SPAuditTask.ps1"

Instalator zapyta lokalnie o konto i haslo przez Get-Credential; **zadnych hasel w GitHub ani skryptach**. Windows przechowuje sekret zadania przez Task Scheduler. Wybierz konto z uprawnieniami SharePoint Shell Admin, odczytem SQL, dostepem do WMI/WinRM i folderu wynikowego, z prawem "Log on as batch job". **Nie wybieraj SYSTEM**.

## Konfiguracja

- Uruchomienie: **JEDNORAZOWE**, najblizsza 22:00 wedlug **czasu serwera**.
- Limit trwania: domyslnie 8 godzin.
- Maksymalnie 5000 webow, DeepWebScan, RemoteWinRM oraz odczyt SQL.
- Wyniki HTML/CSV/JSON w katalogu przebiegu, osobny pseudonimizowany MD w OutputRoot i log pod _logs.
- Brak automatycznego odpalania zadania w dzien po przegapieniu terminu.
- Brak rownoleglych instancji; zadanie nie wykonuje backupu i nie wysyla danych do internetu.

Inny termin:

    & "C:\temp\sprawdzenie\v22\scheduler\Register-SPAuditTask.ps1" -At "2026-10-14 22:00"

Podglad bez rejestracji:

    & "C:\temp\sprawdzenie\v22\scheduler\Register-SPAuditTask.ps1" -WhatIf

Swadoma zmiana juz istniejacego zadania:

    & "C:\temp\sprawdzenie\v22\scheduler\Register-SPAuditTask.ps1" -ReplaceExisting

Bez zdalnego WinRM:

    & "C:\temp\sprawdzenie\v22\scheduler\Register-SPAuditTask.ps1" -SkipRemoteWinRM

Reczne wykonanie launchera:

    & "C:\temp\sprawdzenie\v22\scheduler\Run-SPAudit-Night.ps1" -OutputRoot "C:\temp\sprawdzenie\SP_Audit"

## Kontrola rano

    Get-ScheduledTaskInfo -TaskName "SharePoint SE Full Audit" |
      Select-Object LastRunTime, LastTaskResult, NextRunTime

    Get-ChildItem "C:\temp\sprawdzenie\SP_Audit\_logs" -Filter "NightAudit_*.log" |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1

    Get-ChildItem "C:\temp\sprawdzenie\SP_Audit" -Filter "SP_Audit_SHAREABLE_*.md" |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1

Kod 0: HTML, JSON i MD sa utworzone, zero zgloszonych bledow zbierania.
Kod 2: raporty sa, ale zgloszono braki / bledy poszczegolnych sekcji.
Kod 1: blad krytyczny, brak danych lub konflikt blokady.

Dokladny wynik sprawdz w AuditStatus.txt i CollectionErrors.csv. Brak bledow nie dowodzi kompletnej gotowosci do migracji.

**OSTRZEZENIA:** Pelne wyniki, logi i HTML sa poufne. Markdown nadal wymaga recznego przegladu przed udostepnieniem. Limit 5000 webow nie gwarantuje zbadania calej farmy. Audyt moze obciazyc SQL - dopasuj termin do backupow. Zadanie przerwane po 8 godzinach moze nie wygenerowac raportow koncowych.
