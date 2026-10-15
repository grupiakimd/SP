# SharePoint 2019 → SE — wydanie v2.3.1

**Oddzielne wydanie.** Nie trzeba mieszać plików z v2.3. Poprawia dwa błędy kolektora SQL:
- `Keyword not supported: DataSource` — zastosowano poprawny klucz `Data Source` w ADO.NET.
- `Incorrect syntax near the keyword 'Clustered'` — ujęto aliasy T-SQL w nawiasy kwadratowe, np. `AS [Clustered]`. Dodatkowo ujęto aliasy `Type` i `State`.

## Zawartość folderu v2.3.1

| Plik | Funkcja |
|---|---|
| `Test-SPSESqlLocal.ps1` | Krótki test połączenia i **dokładnego zapytania SQLInstances** (z aliasem Clustered) |
| `Collect-SPSESqlLocal.ps1` | Pełny lokalny audyt SQL i zapis SQLInventory.json |
| `Merge-SPSEAudit.ps1` | Scalenie lokalnego SQL z istniejącym audytem SharePoint |
| `New-SPSEDashboard.ps1`, `dashboard_template.html` | Jeden HTML z danymi SharePoint i SQL |
| `New-SPSEShareableAudit.ps1` | Jeden pseudonimizowany raport Markdown |

## Instalacja offline

Pobierz [całe repozytorium SP](https://github.com/grupiakimd/SP) za pomocą **Code → Download ZIP**. Na serwer SQL skopiuj folder `v2.3.1` np. do `C:\temp\SP-main\v2.3.1`. Nie jest wymagany dostęp do Internetu z serwera.

## Serwer SQL — instancja domyślna MSSQLSERVER

W Windows PowerShell 5.1 (x64):

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force

& "C:\temp\SP-main\v2.3.1\Test-SPSESqlLocal.ps1"
```

Test powinien wyświetlić `SQL CONNECTED: 15.0.x` i `PASS: SQLInstances T-SQL query was accepted...`. Sprawdza zarówno połączenie przez Shared Memory, jak i zapytanie `SERVERPROPERTY`, które dotychczas się nie wykonywało.

Jeśli test przeszedł:

```powershell
& "C:\temp\SP-main\v2.3.1\Collect-SPSESqlLocal.ps1" `
    -OutputRoot "C:\temp\SPSE_SQL_Audit"
```

Dla instancji **domyślnej** nie podawaj `-InstanceName`. Oba skrypty mają ustawione `MSSQLSERVER`. Nie wpisuj nazw serwera ani FQDN — `lpc:.` łączy się lokalnie bez WinRM i zdalnego TCP.

Powstanie `C:\temp\SPSE_SQL_Audit\SQL_Local_YYYYMMDD_HHMMSS\SQLInventory.json`. Jest to **poufny** plik zawierający nazwy baz i konfigurację; nie przesyłaj go do ChatGPT ani nie publikuj na GitHubie.

## APP — scalanie z wcześniejszym audytem SharePoint

Bezpiecznie przenieś `SQLInventory.json` na APP (np. do `C:\temp\sprawdzenie\SQL_Import\SQLInventory.json`). Na APP umieść cały `v2.3.1` obok siebie i uruchom:

```powershell
& "C:\temp\SP-main\v2.3.1\Merge-SPSEAudit.ps1" `
    -SharePointAuditPath "C:\temp\sprawdzenie\v2\SP_Audit" `
    -SqlAuditPath "C:\temp\sprawdzenie\SQL_Import" `
    -OutputRoot "C:\temp\sprawdzenie\Merged"
```

Gdy SharePoint korzysta z aliasu SQL, do scalania można przekazać `-SqlInstanceAlias` z rzeczywistą nazwą pod którą SharePoint widzi serwer. Program wymaga zgodności przynajmniej jednej bazy SharePoint z lokalnym wykazem SQL; jeśli nie znajdzie, zatrzyma się.

W katalogu `Merged_...` powstaną:
- `SPSE_Readiness_Report_MERGED.html` — zbiorczy, poufny dashboard;
- `SP_Audit_SHAREABLE_MERGED.md` — pseudonimizowany raport do ręcznej kontroli;
- `FullInventory.json` — poufna wersja strukturalna;
- `MergeStatus.txt` — szczegóły pochodzenia danych.

Źródłowe raporty pozostają bez zmian. Błędy dawnego odczytu SQL z APP pozostają w historii diagnostyki.

## Granice diagnostyki

Lokalny skrypt nie naprawia błędów WinRM, RPC, Kerberos ani TLS APP→SQL. Audyt pozostaje tylko do odczytu. Nie wykonuje DBCC, backupu ani testu odtwarzania. Jeżeli sekcja zgłasza WARNING, sprawdź jej zakres — wygenerowanie pliku samo w sobie nie oznacza kompletnego audytu.

## Test bez środowiska produkcyjnego

W pobranym pełnym repozytorium z katalogu głównego:

```powershell
& ".\tests\Test-SPSESqlMerge_v2_3_1.ps1"
```

Test przygotowuje **fikcyjne** dane i sprawdza składnię, konstrukcję zapytań oraz generowanie scalonego HTML i pseudonimizowanego MD. Wynik testu w rzeczywistym SQL wymaga uruchomienia na serwerze.
