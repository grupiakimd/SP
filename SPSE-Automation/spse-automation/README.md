# SharePoint Server SE — automatyzacja lokalna v0.3.3 (SAFE LOCAL)

**Model bezpieczeństwa:** Zrezygnowano CAŁKOWICIE z zarządzania zdalnego. ZIP nie zawiera skryptów Remote*, Distribute*, `Invoke-Command` ani transferu plików do innych maszyn. Każdą czynność operator uruchamia osobno na konsoli danej VM. Nie uruchamiaj skryptów v0.2 na środowisku produkcyjnym.

## Stała konfiguracja

| Host | Rola |
|---|---|
| SPSEAPP1 | ApplicationWithSearch — utworzenie farmy |
| SPSEAPP2 | ApplicationWithSearch |
| SPSEWFE1 | WebFrontEndWithDistributedCache |
| SPSEWFE2 | WebFrontEndWithDistributedCache |
| SPSEDB | istniejący SQL 2025, instancja domyślna TCP 1433; skrypt NIE jest uruchamiany na SQL |

Alias `SQL-SPSE` zapisujemy wyłącznie lokalnie na 4 hostach, docelowo wskazuje na SPSEDB:1433. Wyjątek od zasady „tylko lokalnie”: etap **CreateFarm/JoinFarm** z konieczności tworzy/modyfikuje bazę i konfigurację farmy na **SPSEDB**, ale tylko na świadome polecenie. Potencjalne działania usług SharePoint na AD/SQL wynikają z oprogramowania Microsoft, nie z logiki zdalnego sterowania skryptu.

## Przygotowanie fizyczne na każdym serwerze

1. Ręcznie kopiujesz skrypty na dysk lokalny docelowego serwera, np. `C:\temp\spse-automation`, a osobno obrazy ISO i CU **w dowolne lokalne lokalizacje** (np. `D:\ISO` lub `E:\instalki`).
2. **Nie edytujesz ścieżek ani nazw plików w `config.json`.** Instalator pyta o pełne ścieżki do właściwego ISO / LP / CU dopiero przy etapie, który tego potrzebuje. `Audit`, `SqlAlias`, `CreateFarm` i `JoinFarm` nie pytają o nośniki. Aktualizacja CU musi nadal pasować do wymaganego SHA256 z konfiguracji.
3. Uruchom **Windows PowerShell 5.1 x64** jako administrator na docelowym hostcie. Zalecane jest konto **dedykowane do instalacji**, będące lokalnym administratorem na tych czterech maszynach; konto Domain Admin nie jest domyślnie wymagane. Przy tworzeniu farmy niezbędne są oddzielnie właściwe uprawnienia do SQL i kont farmowych.
4. Wykonaj ręcznie backup / snapshot VM oraz ustal okno serwisowe. Nie uruchamiaj jednocześnie instalacji na kilku hostach.
5. Skrypt wymaga potwierdzenia tekstowego dla każdego kroku modyfikującego. Nie wywołuje `Restart-Computer`, `Invoke-Command`, `New-PSSession`, `Copy-Item` na inne VM ani nie używa `-ComputerName`.

## Przykład na SPSEAPP1

```powershell
cd C:\temp\spse-automation
.\SPSEAPP1.ps1 -Step Audit                 # tylko lokalny odczyt + zapis HTML/JSON
.\SPSEAPP1.ps1 -Step WindowsFeatures       # instaluje tylko lokalne funkcje po potwierdzeniu
# gdy jest wymagany restart, uruchamiasz ponownie serwer SAMODZIELNIE
.\SPSEAPP1.ps1 -Step SqlAlias              # lokalny kreator cliconfg.exe (64-bit), reczna konfiguracja aliasu
.\SPSEAPP1.ps1 -Step Prerequisites         # interaktywny installer Microsoft
# ręczny restart + Audit
.\SPSEAPP1.ps1 -Step InstallCore -AcceptLicenseTerms
# interaktywna instalacja binariów EN i ręczny restart
.\SPSEAPP1.ps1 -Step InstallPolishLP -AcceptLicenseTerms
# ręczny restart
.\SPSEAPP1.ps1 -Step InstallCU -AcceptLicenseTerms
# ręczny restart
.\SPSEAPP1.ps1 -Step Audit
```

**UWAGA:** instalatory Microsoft w trybie interaktywnym mogą żądać restartów. Nie uruchamiamy ich z flagą `/unattended`; skrypt nie zawiera automatycznego restartowania. Po zakończeniu każdego etapu sprawdź wymagane restarty. Instalacja CU jest jedynym krokiem `/quiet /norestart`; skrót pliku oraz podpis Authenticode sprawdzane są przed uruchomieniem.

Na pozostałych serwerach **powtarzasz TYLKO na ich własnych konsolach**, zastępując `SPSEAPP1.ps1` odpowiednim `SPSEAPP2.ps1`, `SPSEWFE1.ps1` lub `SPSEWFE2.ps1`. Skrypt przeznaczony dla innej nazwy serwera natychmiast zakończy działanie bez zmian.

## Tworzenie nowej farmy — oddzielna zgoda

Dopiero **gdy na wszystkich czterech VM** potwierdzono instalację EN + PL + CU i restarty (lokalny raport z każdej):

```powershell
# Na SPSEAPP1, tylko raz:
.\SPSEAPP1.ps1 -Step CreateFarm

# Na SPSEAPP2, lokalnie:
.\SPSEAPP2.ps1 -Step JoinFarm
# Na SPSEWFE1, lokalnie:
.\SPSEWFE1.ps1 -Step JoinFarm
# Na SPSEWFE2, lokalnie:
.\SPSEWFE2.ps1 -Step JoinFarm
```

Tworzenie farmy zakłada nowe DB `SPSE_Config` i `SPSE_AdminContent` na `SPSEDB` (przez alias SQL-SPSE) i wymaga konta FARM oraz passphrase. **Nie przywracaj SharePoint 2019 Config DB.** Etapy te modyfikują istniejący serwer SQL — przed nimi osobno weryfikujemy nazwy baz, uprawnienia i źródło backupów. NIE MA tu migracji baz 2019, ustawień LB, SPN ani Workflow Managera.

## Raport lokalny

`<folder_skryptów>\reports\LocalAudit.html` to zbiorczy wynik tylko z bieżącego hosta: role/funkcje, OS, domena, nośniki, SharePoint, alias, lokalny stan instalacji. Nie agreguje danych z innych serwerów. Część `state.json` w `%ProgramData%\SPSE-Automation` to znaczniki procesu (nie gwarancja pomyślnego stanu binariów). Kontrolę rzeczywistej wersji / poprawności LP trzeba wykonać przed `CreateFarm`.

## Ograniczenia i ryzyka

- Nie przetestowano wykonania skryptów w środowisku Windows Server 2025; przeprowadzono audyt statyczny kodu i kompletności archiwum. Zacznij od `-Step Audit` na jednej VM i prześlij raport.
- Etapy `Prerequisites`, `InstallCore` i `InstallPolishLP` uruchamiają **oryginalne GUI Microsoft**. Dzięki temu nie ma pliku z kluczem licencji i nie ma „ukrytej” automatycznej instalacji; wymagają ręcznej obsługi w GUI.
- `prerequisiteinstaller.exe` może wymagać dostępu do Internetu lub mediów offline. Nie wymuszamy pobierania komponentów spoza domeny Microsoft.
- `WindowsFeatures` instaluje jedynie zdefiniowane brakujące lokalne role/funkcje, a nie zmienia ustawień GPO i IIS na innych maszynach.
- **Nie używamy konta Domain Admin, jeśli da się nadać tylko wymagane uprawnienia lokalne i SQL.** Uprawnienia kont domenowych w SharePoint/SQL wymagają planu, nie automatycznego podwyższania.
- `CreateFarm`/`JoinFarm`: konfiguracja farmy jest działaniem z efektami na SQL i wewnętrzne usługi SharePoint; nie jest „wyłącznie lokalna”.
- Przed wdrożeniem na produkcji zweryfikuj działanie na środowisku testowym lub odizolowanej nowej VM.

## Oficjalna dokumentacja

- https://learn.microsoft.com/en-us/sharepoint/install/software-requirements-for-sharepoint-servers-for-sharepoint-server-subscription-edition
- https://learn.microsoft.com/en-us/sharepoint/install/installing-sharepoint-server-subscription-edition-on-windows-server-core
- https://support.microsoft.com/en-us/servicing/office/hotfix/sharepoint/5002927

## Poprawka v0.3.1 (28.10.2026)

- Poprawiono sprawdzanie liczby zdefiniowanych serwerów w trybie `Set-StrictMode -Version Latest`: `.PSObject.Properties.Count` zastąpiono przez jawną tablicę nazw i `.Length`.
- Dodano bezpieczny odczyt opcjonalnej wartości rejestru `PendingFileRenameOperations`.
- Poprawiono wykrywanie opcjonalnej wartości `Installed` w rejestrze Visual C++ Redistributable.
- Nie zmieniono zakresu uprawnień ani kroków modyfikujących; nadal wymagane jest oddzielne potwierdzenie każdej instalacji.

Po rozpakowaniu archiwum pobranego z GitHub (po weryfikacji źródła) można wykonać `Get-ChildItem .\*.ps1 | Unblock-File`, jeśli system blokuje niepodpisane skrypty po pobraniu. Nie wyłączaj polityki skryptów systemowo.

## Aktualizacja v0.3.2 — ścieżki wybierane podczas wykonania

- **Prerequisites** i **InstallCore**: podaj pełną lokalną ścieżkę do obrazu angielskiego SharePoint SE ISO, np. `E:\install\SW_DVD5_...iso`.
- **InstallPolishLP**: podaj pełną lokalną ścieżkę do polskiego ISO (np. `D:\Media\ServerLanguagePack.iso`).
- **InstallCU**: podaj pełną lokalną ścieżkę do pliku `.exe` aktualizacji. Weryfikacja SHA256 i podpisu pozostaje obowiązkowa.
- **WindowsFeatures**: gdy brakuje funkcji, skrypt pyta opcjonalnie o lokalny folder źródła Windows, np. `D:\sources\sxs` (Enter = bez podanego źródła).
- **Audit** nie zadaje pytań o nośniki; raport zapisuje w podfolderze `reports` katalogu skryptu.
- Nie zapisujemy wybranych ścieżek w `config.json`, `state.json` ani repozytorium. Za każdym razem wskazujesz je ręcznie. Akceptowane są tylko istniejące pliki/katalogi na lokalnych dyskach stałych. Ścieżki UNC i mapowane dyski sieciowe są zabronione.
- Wciśnięcie Enter przy wymaganym pliku anuluje etap **bez uruchomienia instalatora**.

Przykład uruchomienia `Prerequisites`:

```powershell
.\SPSEAPP1.ps1 -Step Prerequisites
# W odpowiedzi na pytanie wpisz: E:\install\obraz_sharepoint.iso
# Potwierdzenie instalacji jest nadal oddzielnym krokiem.
```

## Aktualizacja v0.3.3 — lokalna konfiguracja aliasu SQL

Etap `SqlAlias` otwiera **64-bitowe `cliconfg.exe`** po oddzielnym potwierdzeniu; nie zmienia bezposrednio rejestru. W oknie narzedzia wybierz zakladke **Alias > Add**, protokol **TCP/IP**, alias `SQL-SPSE`, serwer `SPSEDB`, port `1433`. Zatwierdz i zamknij okno. Skrypt sprawdzi wynik w lokalnym rejestrze, nie laczy sie z SQL i nie zapisuje danych na serwerze bazy. W razie istniejacego aliasu wskazujacego gdzie indziej skrypt bezpiecznie przerwie. Przed utworzeniem farmy wykonaj oddzielny test polaczenia z SQL.
