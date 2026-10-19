# SharePoint Workflow Migration Analyzer — v2.5

**Etap projektowania migracji 2019 → SE, tylko on-premises.** Nowy, odrębny katalog. Nie zmienia kodu v2.4.x ani istniejących baz i workflow.

## Po co

Dotychczasowy audyt ustalił dla jednej witryny 754 powiązania workflow 2010, 76 włączonych, ale brakowało definicji procesów. Wersja v2.5 analizuje odczytywalne artefakty XML i przygotowuje **hipotezy powtarzalnych rodzin workflow**, aby ustalić rzeczywisty nakład przebudowy.

## Zakres zbierania

- Powiązania legacy/SP2010: site, content types, listy/biblioteki; Enabled, AutoStartCreate, AutoStartChange, AllowManual, BaseTemplateId, deklaratywność.
- Przegląd biblioteki `Workflows` w jednym SPWeb: dostępne XOML/XAML, XML/rules/config jako oddzielne artefakty. Pliki >1 MB domyślnie są pomijane, nie kopiowane.
- Workflow 2013: CSOM subscriptions + `WorkflowDeploymentService.GetDefinition` i `WorkflowDefinition.Xaml`, o ile silnik i proxy pozwalają na odczyt.
- Bezpieczne parsowanie XML: DTD i external entities wyłączone; analizowane są tylko nazwy elementów i **wąska lista** identyfikatorów typów. Treść zmiennych, adresów, warunków i odbiorców nie jest kopiowana do raportów.
- Detekcja obecności ogólnych klas kroków: EMAIL, TASK_APPROVAL, CONDITION, LOOP, WAIT, EXTERNAL_CALL, LIST_MUTATION.
- SHA256 od policzonych tagów XML to **grupowanie heurystyczne**. Ten sam hash sygnatury nie oznacza identycznych warunków, akcji ani odbiorców.
- Powiązania z konkretnymi plikami definicji są oznaczone jako NOT_RESOLVED, dopóki nie da się ich jednoznacznie potwierdzić. Nie przypisujemy według zbieżności nazw.

## Uruchomienie na obecnej farmie SharePoint 2019

Na jednym serwerze APP, w Windows PowerShell 5.1 x64, z uprawnieniami SharePoint Shell Admin:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force

& 'C:\temp\SP-main\v2.5\Collect-SPWorkflowDefinitions.ps1' `
  -WebUrl 'https://ADRES_WITRYNY' `
  -OutputRoot 'C:\SP_Workflow_Migration' `
  -MaxLists 1500 `
  -MaxMarkupFiles 1500
```

Nie trzeba podawać ListTitle; audytuje **jedną witrynę SPWeb** i wszystkie listy bezpośrednio w niej, do limitu. Nie skanuje automatycznie podwitryn. Zacznij od wcześniej analizowanej witryny z 519 listami.

Na podstawie wygenerowanego JSON utwórz raporty (bez ponownego obciążania SharePoint):

```powershell
& 'C:\temp\SP-main\v2.5\New-SPWorkflowMigrationReport.ps1' `
  -InputPath 'C:\SP_Workflow_Migration'
```

Generator automatycznie wybierze najnowszy przebieg `WorkflowDefinitions_...`. Otwórz `WorkflowMigration_Dashboard.html` w Edge/Chrome bez IIS i internetu.

## Pliki wynikowe

| Plik | Status | Zawartość |
| --- | --- | --- |
| `WorkflowDefinitions_PRIVATE.json` | POUFNY | Listy, workflow, ścieżki plików, ID, statusy, surowe błędy |
| `WorkflowMigration_Dashboard.html` | POUFNY | Graficzny podgląd nazw, konfiguracji, rodzin, klasyfikacji, wyszukiwarka |
| `WorkflowMigration_SHAREABLE.md` | DO KONTROLI | Tylko liczniki, znane kody kategorii, hipotetyczne rodziny; bez nazw i adresów |

**Nigdy nie publikuj prywatnego JSON/HTML w publicznym repozytorium.** MD wymaga ręcznego przeglądu przed wysłaniem.

## Na co uważać

- `Workflow2013=FAILED` nie oznacza `0` procesów 2013. Skrypt nie instaluje ani nie naprawia WFM.
- Workflow skompilowane w WSP/GAC mogą nie mieć XOML w bibliotece. Potrzebny kod źródłowy rozwiązania i osobny audyt WSP.
- Sam XML ma ograniczoną wartość bez interpretacji parametrów, pól list, lookupów, tożsamości i warunków. Skrypt **nie konwertuje** workflow.
- Brak mapowania association↔XOML oznacza, że wyniki nie uprawniają do policzenia „ile z 76 aktywnych można automatycznie zastąpić”. To następny etap.
- Nie zbiera ostatnich wykonań ani prób wysyłki — diagnostyka uszkodzonych procesów pozostaje w osobnym zadaniu.
- Limity rozmiaru i liczby artefaktów chronią produkcję; limit oraz błędy są oznaczane w raporcie.

## Jak będziemy podejmować decyzje

1. Potwierdzamy zakres i brakujące definicje, w tym silnik 2013.
2. Na podstawie lokalnej analizy grupujemy konkretne aktywne definicje w rodziny (powiadomienia, akceptacje, operacje na listach, integracje).
3. Wybieramy docelowy **w pełni lokalny** mechanizm: SharePoint Workflow Manager dla wspieranych procesów 2013, albo centralna usługa automatyzacji z bezpieczną integracją SharePoint on-prem (API/zdarzenia, trwała kolejka, retry, idempotencja, monitoring).
4. Tworzymy pilota 2–3 typowych procesów na odizolowanej farmie SE i sprawdzamy zgodność biznesową.
5. Dopiero po zatwierdzeniu działania automatyzujemy wdrożenie na kolejne listy.

**Dlaczego nie samo database attach?** SharePoint SE zakończył wsparcie workflow 2010 14.07.2026, natomiast workflow 2013 on-prem działają z SharePoint Workflow Manager. Nie ma wspieranego konwertera starych workflow 2010 na nowy mechanizm on-prem.

## Weryfikacja

Test syntetyczny na Windows PowerShell 5.1 (bez kontaktu z farmą):

```powershell
& '.\tests\Test-SPWorkflowMigrationV25.ps1'
```

Pierwszy przebieg na Twojej farmie jest testem pilotażowym — nie jest to jeszcze produkcyjnie sprawdzony kolektor.

Dokumentacja:
- https://learn.microsoft.com/en-us/sharepoint/what-s-new/what-s-deprecated-or-removed-from-sharepoint-server-subscription-edition
- https://learn.microsoft.com/en-us/previous-versions/office/developer/sharepoint-2010/bb417436%28v%3Doffice.14%29
- https://learn.microsoft.com/en-us/previous-versions/office/sharepoint-csom/dn624249%28v%3Doffice.15%29
- https://learn.microsoft.com/en-us/previous-versions/office/sharepoint-csom/dn624230%28v%3Doffice.15%29