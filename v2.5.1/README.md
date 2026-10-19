# SharePoint Workflow Migration Analyzer — v2.5.1

**Osobny hotfix dla Windows PowerShell 5.1.** `v2.5/` zostaje bez zmian jako historia. Folder `v2.5.1/` ma trzy kompletne pliki `.ps1` — kolektor, generator raportu i uruchamiacz.

## Co się zepsuło?

W wersji 2.5 kolektor prawidłowo zapisywał `WorkflowDefinitions_PRIVATE.json`, ale raportowanie HTML/MD zatrzymywało się z błędami `Expressions are only allowed as the first element of a pipeline` oraz `Missing expression after unary operator '-'`, m.in. na wierszach tabel Markdown.

Przyczyną jest ryzyko błędnego odczytu plików UTF-8 bez BOM przez Windows PowerShell 5.1 (lokalne kodowanie ANSI, znaki Unicode typu `→`, które po błędnym dekodowaniu mogą zmienić interpretację znaków cudzysłowu). W poprawce WSZYSTKIE trzy skrypty `v2.5.1` zapisano z **UTF-8 BOM**, a argumenty z tabelami Markdown dodatkowo jawnie ujęto w nawiasy.

## Szybka naprawa BEZ nowego audytu

1. Pobierz aktualne repo przez GitHub → **Code → Download ZIP** (bez pobierania przez PowerShell).
2. Rozpakuj, skopiuj cały katalog `v2.5.1` na serwer, np. do `C:\temp\sprawdzenie\v251`.
3. Uruchom **tylko generator**, podając folder ze STARYM wynikiem:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force

& 'C:\temp\sprawdzenie\v251\New-SPWorkflowMigrationReport.ps1' `
    -InputPath 'C:\temp\sprawdzenie\v25\SP_Workflow_Migration'
```

Generator sam odszuka najnowszy `WorkflowDefinitions_PRIVATE.json` w podfolderze `WorkflowDefinitions_YYYYMMDD_HHMMSS` i utworzy obok:

- `WorkflowMigration_Dashboard.html` — lokalny, graficzny panel ze szczegółami dla administratora;
- `WorkflowMigration_SHAREABLE.md` — pseudonimizowany plik do analizy po ręcznym przejrzeniu;
- `WorkflowDefinitions_PRIVATE.json` — pozostaje bez zmian i jest poufny.

### Jeśli potrzeba później nowego zbierania danych

```powershell
& 'C:\temp\sprawdzenie\v251\Invoke-SPWorkflowMigrationAudit.ps1' `
    -WebUrl 'https://ADRES_WITRYNY' `
    -OutputRoot 'C:\SP_Workflow_Migration' `
    -MaxLists 1500
```

Uruchomi kolektor i raportowanie w jednym poleceniu. Wcześniejszych źródeł nie nadpisuje.

## Aktualny stan środowiska (z przebiegu 19.10.2026)

- Wykryto `761` powiązań workflow 2010. To powiązania, nie potwierdzona liczba różnych definicji.
- Znaleziono `198` plików/artefaktów z biblioteki Workflows; nie oznacza to 198 różnych, aktywnych procesów.
- Dostęp do workflow 2013 w tym przebiegu zakończył się jednym błędem odczytu. `0 definitions` w raporcie nie oznacza braku workflow 2013.

## Test

W pobranym repo, z jego katalogu głównego:

```powershell
& '.\tests\Test-SPWorkflowMigrationV251.ps1'
```

Test sprawdza bajty BOM, składnię przez `[System.Management.Automation.Language.Parser]` i generowanie HTML/MD z fikcyjnego JSON. Nie wymaga SharePoint.

Status: poprawkę zapisano na GitHubie; przed uznaniem wydania za potwierdzone wymagane jest przejście testu w Windows PowerShell 5.1 oraz próba raportowania istniejącego JSON.

**Bezpieczeństwo:** dane w `PRIVATE.json` i HTML zawierają oryginalne nazwy/ścieżki i pozostają lokalnie. Nie publikuj ich; MD też zweryfikuj przed wysłaniem.