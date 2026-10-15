# SP v2.4.2 — graficzny raport Workflow, bez ponownego audytu

**Oddzielna wersja** w repozytorium. Wcześniejsze skrypty v2.4 i v2.4.1 pozostają nienaruszone.

## Po co

Dotychczas v2.4.1 generował tylko `WorkflowSite_PRIVATE.json` i `WorkflowSite_SHAREABLE.md`. Nowy generator odczytuje istniejący JSON i tworzy czytelny panel `WorkflowSite_Dashboard.html`, działający **offline w przeglądarce**.

Panel zawiera: podsumowanie 2010 i 2013, listy i biblioteki z workflow, flagi Enabled/AutoStartCreate, podział site/content type/list, subskrypcje 2013, informację o brakach audytu oraz wstępne konsekwencje migracyjne. Jest wyszukiwanie list i przełącznik ukrywania list bez workflow.

## Instrukcja

1. Na GitHub kliknij **Code → Download ZIP**. Z folderu `v2.4.2` skopiuj `New-SPWorkflowDashboard.ps1` na serwer APP (lub komputer Windows PowerShell 5.1 z dostępem do wcześniej wygenerowanego JSON).
2. Uruchom PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& 'C:\temp\SP-main\v2.4.2\New-SPWorkflowDashboard.ps1' `
  -InputPath 'C:\SP_Workflow_Diagnostic'
```

Generator automatycznie znajdzie najnowszy `WorkflowSite_PRIVATE.json` w katalogach `SiteWorkflow_YYYYMMDD_HHMMSS` i utworzy `WorkflowSite_Dashboard.html` w tym samym podfolderze.

Możesz też wybrać konkretny wynik i lokalizację HTML:

```powershell
& 'C:\temp\SP-main\v2.4.2\New-SPWorkflowDashboard.ps1' `
  -InputPath 'C:\SP_Workflow_Diagnostic\SiteWorkflow_YYYYMMDD_HHMMSS\WorkflowSite_PRIVATE.json' `
  -OutputPath 'C:\SP_Workflow_Diagnostic\Dashboard_Workflow.html'
```

3. Otwórz HTML dwuklikiem w Edge lub Chrome. **Nie trzeba IIS, serwera WWW ani dostępu do Internetu.**

## Który plik do czego?

| Plik | Dla kogo | Poufność |
|---|---|---|
| `WorkflowSite_PRIVATE.json` | Administracja / ponowne generowanie HTML | Poufny |
| `WorkflowSite_Dashboard.html` | Czytelny panel administratora | Poufny — rzeczywiste nazwy list i workflow |
| `WorkflowSite_SHAREABLE.md` | Analiza poza środowiskiem, po ręcznym przeglądzie | Pseudonimizowany, nadal może być poufny |

## Ograniczenia

- Panel nie uruchamia i nie naprawia workflow, nie wysyła testowych maili.
- Flaga Enabled/AutoStartCreate to stan konfiguracji, nie dowód ostatniego wykonania.
- Błąd zbierania Workflow 2013 powoduje wyświetlenie `?` zamiast nieprawdziwego `0`.
- Skrypt nie zawiera bibliotek zewnętrznych i nie wykonuje żądań sieciowych.
- Test na danych fikcyjnych znajduje się w `tests/Test-SPWorkflowDashboard.ps1`. Kod musi jeszcze przejść weryfikację w Twoim Windows PowerShell 5.1.

**Cel w tym projekcie:** inwentaryzacja i plan migracji SharePoint 2019 → SE. Diagnostykę problemu konkretnego niedziałającego workflow prowadzimy osobno.