# SPSE — automatyczna instalacja lokalna EN + PL + KB5002927 (v1.0)

**Cel:** instalacja *samych binariów* SharePoint Server Subscription Edition na **SPSEAPP2, SPSEWFE1, SPSEWFE2** na Windows Server 2025. Skrypt celowo **odmawia działania na SPSEAPP1 i SPSEDB**.

## Przygotowanie każdego serwera (ręcznie, bez działania zdalnego)

1. Utwórz snapshot/backup VM przed zmianami. Zaloguj się kontem uprawnionym do lokalnej instalacji (np. `WINAD\SPSE_SETUP`, o ile nadano mu lokalne uprawnienia). Nie uruchamiaj na koncie SharePoint Farm Service.
2. Skopiuj **osobno na każdy serwer**, na lokalny dysk, cztery pliki: `OfficeServer.iso` (EN), `ServerLanguagePack.iso` (PL), `uber-subscription-kb5002927-fullfile-x64-glb.exe` i `vc_redist.x64.exe`. Domyślna lokalizacja: `E:\install`. Internet/Windows Update może być wymagany przez Microsoft Prerequisite Installer; obecność tych czterech plików nie gwarantuje pełnego trybu offline. Pliki ISO mają zostać na stałych dyskach lokalnych, nie na SMB.
3. Na **SPSEAPP2** wcześniej dodaj dysk **S: 200 GB, NTFS** z wystarczającą ilością wolnej przestrzeni. Skrypt ustawi `DATADIR=S:\SearchIndex` przy instalacji. Na `SPSEWFE1/WFE2` oddzielny Search dysk nie jest wymagany.
4. Uruchom **Windows PowerShell 5.1 x64 jako administrator** w katalogu skryptu.

## Start — tylko jeden serwer na raz

```powershell
cd C:\install\SPSE-Unattended
Get-ChildItem .\*.ps1 | Unblock-File
.\Install-SPSE-Unattended.ps1 -AcceptLicenseTerms
```

Skrypt od razu pyta o katalog nośników, ścieżki do 2 ISO, CU, ewentualnie VC++ i źródło funkcji Windows. Przed jakąkolwiek właściwą instalacją pokazuje plan i wymaga wpisania **`INSTALUJ SPSEAPP2`**, **`INSTALUJ SPSEWFE1`** albo **`INSTALUJ SPSEWFE2`** (zależnie od lokalnego hosta).

Po potwierdzeniu kolejno:

1. Instaluje brakujące 30 funkcji Windows (`Install-WindowsFeature`) tylko na bieżącym serwerze.
2. Instaluje lokalnie VC++ x64 (jeżeli brak), bez kreatora.
3. Tworzy **tylko lokalny** alias SQL `SQL-SPSE -> SPSEDB,1433`, jeśli nie istnieje; nie nadpisuje konfliktu. Nie łączy się z serwerem SQL.
4. Uruchamia `prerequisiteinstaller.exe /unattended` (lub `/continue /unattended` po restarcie).
5. Instaluje SharePoint SE EN przez `setup.exe /config ... /IAcceptTheLicenseTerms`, wyłączając kreator i automatyczny restart w XML. **Klucz podajesz tylko raz podczas pierwszego uruchomienia skryptu**. Jest zapisany do czasu etapu Setup jedynie w formie zaszyfrowanej Windows DPAPI (związanej z tym samym kontem Windows), nie w media.json, progress.json ani raportach. Tymczasowy XML z kluczem jest chroniony ACL i usuwany po uruchomieniu instalatora.
6. Instaluje polski LP przez `setup.exe /config ... /IAcceptTheLicenseTerms`, bez GUI.
7. Weryfikuje SHA256 `74860C53DAD8D985DC52844344CC5A82CFD04437A3B30C9C45CC6974222073C6` i podpis cyfrowy KB5002927; uruchamia CU z `/quiet /norestart`.
8. Tworzy **lokalny raport HTML** w `C:\ProgramData\SPSE-Unattended\<NAZWA_SERWERA>\Raport.html` i log przebiegu bez kluczy.

## Restarty i wznawianie — bez klikania w kreatorach

Instalacja jest cicha **pomiędzy** restartami. Microsoft nie gwarantuje, że `prerequisiteinstaller.exe /unattended` sam nie zainicjuje restartu lub nie utworzy autostartu. Dlatego obserwuj konsolę i nie traktuj jej jako absolutnej blokady rebootu. Nasz skrypt nie wywołuje `Restart-Computer`, natomiast Microsoft Prerequisite Installer może sam zarządzać restartami. Skrypt zatrzymuje się na wymaganych restartach po funkcjach systemowych, komponentach wstępnych, bazowym SharePoint, polskim LP i CU (zależnie od etapu).

**Po każdym restarcie uruchom na tym samym serwerze:**

```powershell
.\Install-SPSE-Unattended.ps1 -Resume -AcceptLicenseTerms
```

Stan jest przechowywany lokalnie w `%ProgramData%\SPSE-Unattended\<serwer>\progress.json`. Nie wpisujesz ponownie klucza przy `-Resume`, o ile logujesz się **tym samym kontem Windows na tym samym serwerze**. Zaszyfrowany klucz DPAPI w katalogu `private` jest usuwany po etapie `InstallCore` (nie pozostaje w repozytorium ani raporcie).

Nie uruchamiaj ponownie zwykłego trybu po rozpoczęciu instalacji — używaj `-Resume`. Jeśli instalator częściowo się wykonał i stan nie odpowiada plikom, skrypt zatrzyma się zamiast wymuszać reinstalację. Nie kasuj `progress.json` w celu wymuszenia powtórki.

## Audyt bez zmian w instalacji

```powershell
.\Install-SPSE-Unattended.ps1 -Audit
```

Raport po instalacji **nie dowodzi jeszcze poprawnego działania farmy**. Osobno sprawdzimy rzeczywistą wersję CU, polskie szablony, MinRole i dołączanie do farmy. Program NIE tworzy bazy farmy, NIE uruchamia PSConfig, NIE dołącza do farmy, NIE modyfikuje SQL/AD i NIE wykonuje zdalnych komend. Rolę `ApplicationWithSearch` lub `WebFrontEndWithDistributedCache` ustawimy dopiero podczas kontrolowanego `JoinFarm`.

## Ograniczenia i bezpieczeństwo

- Skrypt **nie był wykonywany na Windows Server 2025**; przeprowadzono wyłącznie kontrolę statyczną. Rozpocznij od `SPSEAPP2` i raportu po pierwszych etapach, nie uruchamiaj równolegle na trzech hostach.
- Przed instalacją obowiązkowo sprawdź licencję Microsoft; `-AcceptLicenseTerms` jest deklaracją jej akceptacji.
- Klucz licencji podczas działania Setup pojawia się na krótko w chronionym lokalnie XML, nie w argumentach uruchomienia ani zapisanym dzienniku. Plik tymczasowy XML zawiera klucz w postaci jawnej tylko w trakcie pracy Setup; przy awarii zasilania może pozostać na dysku i wymagać kontroli. Skrypt usuwa znane pliki tymczasowe przy kolejnym starcie. Do instalacji klucza między restartami używa lokalnego, zaszyfrowanego pliku DPAPI dostępnego pod tym samym kontem Windows.
- Odczyt i zapis stanu tylko lokalnie, brak WinRM, SMB, orkiestracji między VM, automatycznego tworzenia/dołączania farmy, zmian w SQL/AD i automatycznych testów GitHub. Raporty firmowe **nie mogą być wrzucane do publicznego GitHub**.
- `SPSEAPP1` pozostaje przy instalacji już wykonanej innym skryptem. Tego narzędzia nie stosuj do jego ponownej instalacji.

## Źródła Microsoft

- https://learn.microsoft.com/en-us/sharepoint/install/installing-sharepoint-server-subscription-edition-on-windows-server-core
- https://learn.microsoft.com/en-us/sharepoint/install/install-or-uninstall-language-packs-subscription
- https://learn.microsoft.com/en-us/sharepoint/install/software-requirements-for-sharepoint-servers-for-sharepoint-server-subscription-edition
- https://support.microsoft.com/en-us/servicing/office/hotfix/sharepoint/5002927
