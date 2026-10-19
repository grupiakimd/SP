# SharePoint Workflow Migration Analyzer v2.5.2

Oddzielna poprawka do generowania raportu z audytu v2.5/v2.5.1. Nie modyfikuje starszych wersji.

## Przyczyna problemu

Poprzedni `New-SPWorkflowMigrationReport.ps1` próbował wyświetlić `$items[0].Kind`.
Kolektor definicji w `WorkflowDefinitions_PRIVATE.json` **nie zapisuje pola Kind**.
Dla artefaktów workflow 2010 zapisuje `Extension` (np. `.xoml`), a dla definicji 2013 m.in. `DisplayName` i `Id`.
W trybie `Set-StrictMode` odwołanie do nieistniejącej właściwości przerywa generowanie HTML.

Poprawka v2.5.2:
- nazywa typ profilu na podstawie faktycznie istniejących właściwości (`Kind`, `Extension`, `DisplayName`) bez zgadywania pól,
- pokazuje Workflow 2013 jako `NIEUSTALONE`, jeśli odczyt zakończył się błędem,
- zachowuje UTF-8 BOM w wszystkich plikach PowerShell dla Windows PowerShell 5.1,
- obejmuje test syntetyczny dla **obydwu typów obiektów bez Kind**,
- zachowuje komplet trzech skryptów w osobnym folderze `v2.5.2`.

## Najprostsza naprawa — bez kolejnego audytu

Pobierz GitHub **Code → Download ZIP**, skopiuj **cały** folder `v2.5.2` na serwer APP np. do:

`C:\temp\sprawdzenie\v252`

W Windows PowerShell 5.1 wykonaj tylko:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force

& "C:\temp\sprawdzenie\v252\New-SPWorkflowMigrationReport.ps1" `
    -InputPath "C:\temp\sprawdzenie\v25\SP_Workflow_Migration"
```

Jeżeli wcześniej zbierałeś dane do innego katalogu, podaj faktyczny katalog zawierający `WorkflowDefinitions_PRIVATE.json` albo pełną ścieżkę do tego pliku. Możesz też użyć `-OutputDirectory`.

Generator znajdzie najnowszy przebieg i utworzy obok:
- `WorkflowMigration_Dashboard.html` — poufny dashboard administratora;
- `WorkflowMigration_SHAREABLE.md` — pseudonimizowany raport do ręcznej kontroli.

Już zapisany `WorkflowDefinitions_PRIVATE.json` pozostanie nietknięty. Ponowny skan farmy nie jest potrzebny.

**Uwaga:** Na poprzednim zrzucie uruchomiono skrypt z `C:\temp\sprawdzenie\v25`, nie z nowego katalogu. Aby skorzystać z poprawki, wywołaj konkretnie skrypt `v252`.

## Pełny audyt w przyszłości

W razie potrzeby kolejne skanowanie można uruchomić:

```powershell
& "C:\temp\sprawdzenie\v252\Invoke-SPWorkflowMigrationAudit.ps1" `
    -WebUrl "https://ADRES_WITRYNY" `
    -OutputRoot "C:\SP_Workflow_Migration" -MaxLists 1500
```

## Kontrola jakości

Test (Windows PowerShell 5.1, bez SharePoint):

```powershell
& ".\tests\Test-SPWorkflowMigrationV252.ps1"
```

Test sprawdza składnię, BOM, generowanie HTML i MD z obiektów XOML i XAML bez pola `Kind`, oznaczanie nieudanych odczytów i brak ujawniania nazw w pseudonimizowanym MD.

**Stan:** pliki w repozytorium; nie zakładaj pomyślnego wykonania na Twoim serwerze przed próbą raportowania. W razie błędu zachowaj prywatny JSON i prześlij tylko tekst błędu.

## Bezpieczeństwo

HTML i JSON zawierają rzeczywiste nazwy procesów, adresy i ścieżki — trzymaj je wyłącznie lokalnie. MD nie zawiera znanych pól identyfikujących, ale nadal wymaga przeglądu przed udostępnieniem.

Workflow 2013 nadal nie ma potwierdzonego odczytu w Twojej farmie; ten hotfix naprawia **prezentację**, a nie inwentaryzację silnika 2013.
