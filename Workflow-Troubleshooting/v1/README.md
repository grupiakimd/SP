# Diagnostyka workflow SharePoint 2019 - v1 z panelem graficznym

Zestaw narzedzi tylko do odczytu. Dotyczy jednej witryny i jednej listy: workflow 2010/2013, instancje na wybranych elementach, konfiguracja i lokalne logi ULS. Bez zmian w farmie, bez uruchamiania workflow, bez wysylania maili.

## A. Masz juz pliki JSON i .md? Wykonaj tylko to

Nie powtarzaj audytu. Pobierz aktualny folder Workflow-Troubleshooting/v1 z repo (GitHub -> Code -> Download ZIP). Skopiuj plik New-SPWorkflowTroubleshootDashboard.ps1 na komputer z PowerShell 5.1, np. do C:\Temp\SP-main\Workflow-Troubleshooting\v1\.

Uruchom:

~~~powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
& 'C:\Temp\SP-main\Workflow-Troubleshooting\v1\New-SPWorkflowTroubleshootDashboard.ps1' -InputPath 'C:\SP_Workflow_Troubleshooting'
~~~

Generator automatycznie wybierze najnowszy WorkflowTroubleshoot_PRIVATE.json w podkatalogach Run_* i stworzy **WorkflowTroubleshoot_Dashboard.html** w tym samym katalogu. Otworz HTML dwuklikiem w Edge lub Chrome.

Mozna wskazac konkretny JSON:

~~~powershell
& 'C:\Temp\SP-main\Workflow-Troubleshooting\v1\New-SPWorkflowTroubleshootDashboard.ps1' -InputPath 'C:\SP_Workflow_Troubleshooting\Run_YYYYMMDD_HHMMSS\WorkflowTroubleshoot_PRIVATE.json'
~~~

Generator nie wymaga serwera SharePoint, polaczenia z farma ani dostepu do Internetu. Tylko odczytuje JSON i zapisuje HTML lokalnie.

## B. Kolejne uruchomienia audytu

Nowa wersja Invoke-SPWorkflowTroubleshoot.ps1 automatycznie generuje dashboard HTML po zapisaniu raportu, jesli oba skrypty znajduja sie w tym samym folderze:

~~~powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
& 'C:\Temp\SP-main\Workflow-Troubleshooting\v1\Invoke-SPWorkflowTroubleshoot.ps1' -WebUrl 'https://sharepoint/sites/example' -ListUrl 'https://sharepoint/sites/example/Lists/Requests/AllItems.aspx' -LogHours 6
~~~

Dla znanego nieudanego elementu uzyj dodatkowo -ItemId 123.

Skrypt audytowy wymaga Windows PowerShell 5.1 x64, SharePoint Management Shell oraz uprawnien do odczytu listy i farmy.

## C. Co pokazuje dashboard

- Liczniki workflow 2010 i 2013, aktywnych definicji, instancji i bledow ULS.
- Graficzny przebieg: zapis listy -> wyzwalacz -> silnik -> e-mail.
- Tabela workflow z wyszukiwaniem i sposobem wyzwalania.
- Istniejace instancje i ich stany na sprawdzonych elementach.
- Przeglad ustawien bezpieczenstwa i zgodnosci (w tym 53601).
- Lokalny ULS, filtrowanie komunikatow i identyfikatory Correlation ID.
- Wskazowki diagnostyczne zalezne od zebranych danych (nie automatyczna diagnoza przyczyny).

## D. Ochrona danych

- **WorkflowTroubleshoot_Dashboard.html** — POUFNY, zawiera wewnetrzne nazwy, URL oraz komunikaty ULS. Tylko lokalnie; nie publikuj go w GitHub.
- **WorkflowTroubleshoot_PRIVATE.json** — POUFNY, zachowaj lokalnie.
- **WorkflowTroubleshoot_SHAREABLE.md** — skrocony, pseudonimizowany; sprawdz recznie przed przeslaniem.

Dashboard jest w jednym HTML: dziala offline, bez CDN i bibliotek zewnetrznych. Sekcje workflow 2013, ktorych nie udalo sie odczytac, nie sa falszywie oznaczane jako pewne zero. ULS obejmuje wylacznie serwer zbierajacy dane oraz zadany okres czasu. Brak instancji w probce nie oznacza braku uruchomien.

## E. Nawiązanie do aktualizacji

Build 16.0.10417.20198 (KB5002894) uzasadnia analize zachowania starszych workflow. Potencjalna zgodnosc z Classic Workflow Manager wymaga potwierdzenia faktycznej wersji WFM; nie ustawiaj automatycznie flagi 53601 i nie wylaczaj mechanizmu zabezpieczen.

Dokumentacja Microsoft: https://support.microsoft.com/en-us/servicing/office/hotfix/sharepoint/5002894
