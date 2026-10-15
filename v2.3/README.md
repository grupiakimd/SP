# SharePoint 2019 → SE — audyt SQL lokalnie + scalanie (v2.3)

**Cel:** usunąć zależność od niedziałających połączeń APP → SQL (WMI/RPC, WinRM/Kerberos, SQL/TLS pre-login). Zbieramy SQL **na serwerze SQL**, następnie bez sieci (np. zatwierdzonym nośnikiem lub bezpiecznym udziałem) przenosimy pojedynczy JSON do serwera APP i budujemy jeden raport HTML oraz MD.

Ten mechanizm NIE zastępuje weryfikacji technicznej połączenia aplikacji SharePoint z SQL — naprawa błędów komunikacji pozostaje osobnym zadaniem.

## Co uruchomić na którym serwerze

## Poprawka v2.3.1 — błąd DataSource

W pierwotnym `Collect-SPSESqlLocal.ps1` PowerShell 5.1 zwracał `Keyword not supported: 'DataSource'`. To błąd zapisu klucza ConnectionStringBuilder w skrypcie, a nie dowód niedostępności SQL ani problem uprawnień. Poprawiono użycie kanonicznego klucza `Data Source`.

Najpierw skopiuj **nowe pliki** z GitHub (zwykłe Code → Download ZIP, nie Invoke-WebRequest) na serwer SQL. Możesz uruchomić szybki test domyślnej instancji bez podawania nazwy:

```powershell
& "C:\temp\SP-main\v2.3\Test-SPSESqlLocal.ps1"
```

Oczekiwany komunikat: `SQL CONNECTED: <wersja>`. Następnie pełny lokalny audyt:

```powershell
& "C:\temp\SP-main\v2.3\Collect-SPSESqlLocal.ps1" -OutputRoot "C:\temp\SPSE_SQL_Audit"
```

Parametr `-InstanceName` jest opcjonalny i domyślnie przyjmuje `MSSQLSERVER`. Jeśli test się nie powiedzie, sprawdź `Get-Service MSSQLSERVER` (na rzeczywistym serwerze SQL). Test i audyt nie restartują usług i nie zmieniają baz.

### A. SQL Server 2019 (bezpośrednio na maszynie SQL)

Skopiuj tylko plik `Collect-SPSESqlLocal.ps1` na serwer baz. W **Windows PowerShell 5.1 x64**, na koncie z uprawnieniami `sysadmin`:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
& "C:\SPSE\Collect-SPSESqlLocal.ps1" -InstanceName "MSSQLSERVER" -OutputRoot "C:\SPSE_SQL_Audit"
```

Dla instancji nazwanej zamiast `MSSQLSERVER` podaj samą nazwę instancji, np. `SPDATA`. Skrypt łączy się **lokalnie** z `lpc:.` (Shared Memory), a dla instancji nazwanej `lpc:.\SPDATA`, z Windows Integrated Authentication. Nie potrzebuje WinRM, WMI do innych hostów ani zdalnego TCP do SQL. Lokalny odczyt parametrów Windows odbywa się osobno przez CIM.

Powstanie:

```powershell
C:\SPSE_SQL_Audit\SQL_Local_YYYYMMDD_HHMMSS\SQLInventory.json
```

Plik zawiera **prawdziwe nazwy baz, instancji i serwera**. Nie przesyłaj go do ChatGPT ani publicznego repozytorium. Skopiuj go bezpiecznie na APP, np. pod:

`C:\temp\sprawdzenie\SQL_Import\SQLInventory.json`

### B. SharePoint APP

Zachowaj dotychczasowy katalog audytu SharePoint (z `FullInventory.json`), np.:

`C:\temp\sprawdzenie\v2\SP_Audit`

Skopiuj z GitHub **cały katalog v2.3** (cztery pliki obok siebie: `Merge-SPSEAudit.ps1`, `New-SPSEDashboard.ps1`, `New-SPSEShareableAudit.ps1`, `dashboard_template.html`) na APP do `C:\temp\sprawdzenie\v23`.

Następnie:

```powershell
& "C:\temp\sprawdzenie\v23\Merge-SPSEAudit.ps1" `
   -SharePointAuditPath "C:\temp\sprawdzenie\v2\SP_Audit" `
   -SqlAuditPath "C:\temp\sprawdzenie\SQL_Import" `
   -OutputRoot "C:\temp\sprawdzenie\Merged"
```

Jeśli w SharePoint instancja ma inną nazwę logiczną (alias/FQDN), można podać:

```powershell
-SqlInstanceAlias "SQL-NAME-USED-BY-SHAREPOINT"
```

Nie podawaj przykładowej nazwy bez sprawdzenia. Skrypt nie dopasowuje na siłę: gdy brak wspólnych baz SharePoint/SQL **odmawia scalenia**, a niezgodność identyfikatorów SQL zostaje oznaczona jako ryzyko.

### C. Wyniki

W nowym folderze `Merged_...`:

- `SPSE_Readiness_Report_MERGED.html` — **jeden lokalny dashboard**, dodatkowo widoki konfiguracji i plików SQL.
- `SP_Audit_SHAREABLE_MERGED.md` — **jeden pseudonimizowany raport** do ręcznej kontroli przed udostępnieniem.
- `FullInventory.json` — **poufna** techniczna kopia po scaleniu.
- `MergeStatus.txt` — status i informacja o pochodzeniu danych.

**Źródłowy audyt SharePoint i źródłowy audyt SQL nie są modyfikowane.** W HTML pozostawione zostają oryginalne błędy zdalnego SQL APP → SQL, ale na panelu jest pokazane, że wartości SQL zostały zastąpione wynikiem lokalnym. Błędy WMI/WinRM nie znikają — to prawdziwe problemy infrastrukturalne, których lokalny odczyt baz nie naprawia.

## Zakres lokalnego SQL

Wersja/edycja/aktualizacje SQL, HADR/klaster, recovery model, compatibility level, rozmiary danych i logów, autogrowth, stan baz, historia FULL/DIFF/LOG z `msdb`, podstawowe ustawienia silnika, RAM/CPU, dyski. Nie wykonuje backupu, testowego odtworzenia, DBCC ani restartów.

Brak wpisów `msdb` **nie dowodzi**, że backup nie istnieje (zewnętrzne narzędzia mogą nie zapisywać historii). Potwierdzenie odtwarzalności wymaga osobnego testu restore.

## Kontrola / test bez produkcyjnej farmy

Test z fikcyjnymi danymi uruchamiany w Windows PowerShell 5.1:

```powershell
& ".\tests\Test-SPSESqlMerge.ps1"
```

Test wymaga pobranego całego repozytorium (nie samego katalogu v2.3) i nie łączy się z SQL/SharePoint.

**Bezpieczeństwo:** Pliki JSON i HTML są poufne. Raport MD nadal może zdradzać wersje, liczbę baz i skalę środowiska. Nie publikuj go na GitHubie i przejrzyj go przed udostępnieniem.
