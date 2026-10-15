# SharePoint Workflow — diagnostyka witryny (v2.4.1)

**Oddzielna wersja** — nie wymaga nazwy listy. Wersja v2.4 pozostaje bez zmian.

## Zakres

- Skrypt bada pojedynczy SPWeb wskazany przez -WebUrl, w tym workflow 2010 przypięte do witryny, typów zawartości i list/bibliotek.
- Odczytuje workflow 2013 przez CSOM EnumerateSubscriptions(), rozpoznaje scope po EventSourceId: SITE, LIST, OTHER_OR_UNKNOWN.
- Sprawdza lokalny SPTimerV4, Timer Jobs alert/workflow, Workflow Manager proxy oraz podstawowe ustawienia SMTP.
- Nie skanuje podwitryn. Jeśli workflow znajduje się w subsite, podaj jego własny adres.
- Domyślny limit: 500 list/bibliotek w bieżącej witrynie, również ukrytych.

## Uruchomienie offline

Pobierz repo przez GitHub → Code → Download ZIP, skopiuj folder v2.4.1 na serwer APP SharePoint 2019.
Windows PowerShell 5.1 x64, konto z uprawnieniami SharePoint Shell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
& 'C:\temp\SP-main\v2.4.1\Invoke-SPWorkflowSiteDiagnostic.ps1' -WebUrl 'https://ADRES_WITRYNY' -OutputRoot 'C:\SP_Workflow_Diagnostic'
```

**Nie podawaj -ListTitle**. Przy większej liczbie list świadomie dodaj -MaxLists 1500.

## Pliki wynikowe

- WorkflowSite_PRIVATE.json: dane poufne — rzeczywiste nazwy, adresy, GUID-y, błędy. Zachowaj lokalnie.
- WorkflowSite_SHAREABLE.md: pseudonimizowane liczby, statusy, aliasy LIST-001, dane potrzebne do analizy. Przejrzyj przed wysłaniem.

## Ograniczenia

Nie wykonuje workflow ani testowych maili. Nie diagnozuje ostatniej instancji procesu na elemencie; do tego użyj wersji v2.4 ze wskazaną listą i ItemId.
Jeśli odczyt subskrypcji 2013 się nie powiedzie, raport pokaże status NOT_RUN — nie oznacza to braku workflow 2013.
SMTP skonfigurowany nie znaczy SMTP sprawny. Testowanie dostarczania wymaga osobnej diagnostyki.
To raport pseudonimizowany, nie gwarantowana anonimowość.

Dokumentacja:
- https://learn.microsoft.com/en-us/previous-versions/office/sharepoint-csom/dn624342%28v%3Doffice.15%29
- https://learn.microsoft.com/en-us/sharepoint/dev/general-development/sharepoint-workflow-fundamentals