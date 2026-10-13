SHAREPOINT 2019 -> SHAREPOINT SUBSCRIPTION EDITION
AUDYT MIGRACYJNY — INSTRUKCJA v1.0
==========================================

1. GDZIE URUCHOMIC
-----------------
Na jednym z 4 aktualnych serwerow SharePoint 2019 (preferowany APP),
NIE na serwerze SQL. Windows PowerShell 5.1 x64 jako administrator.
Konto musi miec SharePoint Shell Admin / uprawnienia admina farmy.
Na serwerach zdalnych WMI/CIM i WinRM moze wymagac dodatkowych uprawnien.
SQL: Windows Integrated Security, odczyt katalogow sys.* i msdb.dbo.backupset.

2. PIERWSZY AUDYT — W CIAGU GODZIN PRACY
---------------------------------------
Zapisz Invoke-SP2019ReadinessAudit.ps1 np. w C:\Scripts.
Otworz Windows PowerShell (64-bit) jako administrator i wykonaj:

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "C:\Scripts\Invoke-SP2019ReadinessAudit.ps1" -OutputRoot "C:\SP_Audit"

Skrypt NIE modyfikuje farmy, baz SQL, uslug, konfiguracji ani zawartosci.
Wykonuje odczyt i tworzy raporty w podanym katalogu.

3. DRUGI AUDYT — POZA GODZINAMI PRACY
------------------------------------
& "C:\Scripts\Invoke-SP2019ReadinessAudit.ps1" -OutputRoot "C:\SP_Audit" -DeepWebScan -MaxWebs 5000 -RemoteWinRM

-DeepWebScan: przeglada kolekcje witryn, weby, listy, powiazania workflow,
  aktywne cechy; bardzo duze farmy wymagaja zwiekszenia MaxWebs,
  a samo skanowanie moze czasowo obciazyc bazy i serwery.
-RemoteWinRM: czyta certyfikaty (bez kluczy!), uslugi Windows,
  IIS bindings oraz Microsoft.SharePoint.dll z pozostalych wezlow.
Bez RemoteWinRM skrypt nadal czyta konfiguracje farmy, SQL i OS przez CIM/WMI.

4. JESLI SQL NIE ODPOWIADA
--------------------------
Domyslnie SQL wymaga poprawnego, zaufanego certyfikatu TLS.
Przy wewnetrznym SQL uzywajacym self-signed (jesli akceptujesz ryzyko):

& "C:\Scripts\Invoke-SP2019ReadinessAudit.ps1" -OutputRoot "C:\SP_Audit" -SqlTrustServerCertificate

Preferowanym rozwiazaniem jest certyfikat SQL zaufanego CA.
Przelacznik nie wylacza szyfrowania polaczenia, tylko weryfikacje certyfikatu.
Jesli nie ma uprawnien do SQL, uzyj -SkipSQL i dostarcz raport SQL osobno.

5. WYNIKI
---------
W C:\SP_Audit\SP2019_Audit_KOMPUTER_DATA\ znajduja sie:
- SPSE_Readiness_Report.html : raport do przegladarki;
- MigrationRisks.csv      : wykryte ryzyka i kolejne dzialania;
- CollectionErrors.csv    : pola nieodczytane, bledy uprawnien/sieci;
- ContentDatabases.csv   : bazy zawartosci, liczba kolekcji i limity;
- SPDatabases.csv        : wszystkie bazy zarejestrowane w farmie;
- SQLDatabases.csv       : rozmiary baz, tryby recovery, poziomy zgodnosci;
- SQLBackupHistory.csv   : ostatnie rekordy FULL/DIFF/LOG w msdb;
- Search*.csv            : SSA, topologia, komponenty, crawl sources;
- SolutionsWSP.csv       : deployed WSP;
- ServiceApplications.csv, ManagedAccounts.csv, TimerJobs.csv;
- WebApplications.csv, WebAppZones.csv, ManagedPaths.csv, AlternateAccessMappings.csv;
- SiteCollections.csv, MySites.csv, a po DeepWebScan: Webs, Lists, WorkflowAssociations;
- FullInventory.json     : zbior danych do automatycznej analizy;
- archiwum .zip obok folderu.

Uwagi o wiarygodnosci:
* Brak danych != brak problemu. Sprawdz CollectionErrors.csv.
* ReadinessScore jesli zostanie policzony, jest pomocnicza heurystyka,
  a NIE potwierdzeniem gotowosci migracyjnej.
* Raport list jest punktowy; Workflow 2013 (Workflow Manager), formularze
  InfoPath, niestandardowe web.config i zewnetrzne integracje wymagaja
  recznej inwentaryzacji. Brak wpisow WorkflowAssociations nie wyklucza workflow.
* HealthRules.csv zawiera reguly, a HealthReports.csv do 500 najnowszych
  raportow Health Analyzer (moga zawierac zdarzenia historyczne).
* Backup w msdb NIE potwierdza poprawnego odtwarzania kopii.
* Skrypt NIE wywoluje Test-SPContentDatabase na farmie 2019.
  Test wykonuje sie na docelowej farmie SE na odtworzonych bazach testowych.
* Rozmiar SQLDatabases.csv to zaalokowane strony/plik, nie pelna ilosc
  danych uzytkownika ani faktyczny czas transferu.

6. PO PIERWSZYM URUCHOMIENIU
---------------------------
Przeslij do analizy archiwum ZIP. Sprawdz je wczesniej pod katem danych
poufnych (URL, nazwy serwerow, konta uslugowe, wlasciciele witryn).
Nie zawiera hasel, kluczy prywatnych ani zawartosci dokumentow.

7. PODSTAWY PROCESU MIGRACJI
----------------------------
- Migracja 2019 -> SE: nowa farma + database attach (nie in-place).
- Konfiguracja farmy, czesc aplikacji i integracji nie sa przenoszone
  przez samo odtworzenie bazy konfiguracyjnej z 2019.
- Nie wykonuj detach/attach, upgrade, PSConfig ani zmian compatibility
  na produkcyjnych bazach bez zatwierdzonego planu i testu.
- SQL Server 2025 obsługuje compat level 150, wymagany przez SE;
  nie wymuszaj compatibility level 170 w bazach SharePoint.
- SP2019 wyszedl ze wsparcia 14 lipca 2026.

Zrodla (Microsoft Learn):
https://learn.microsoft.com/en-us/sharepoint/upgrade-and-update/overview-of-the-upgrade-process-subscription-edition
https://learn.microsoft.com/en-us/sharepoint/upgrade-and-update/create-the-sharepoint-server-subscription-edition-farm-for-a-database-attach-upgrade
https://learn.microsoft.com/en-us/sharepoint/install/software-requirements-for-sharepoint-servers-for-sharepoint-server-subscription-edition
https://learn.microsoft.com/en-us/sharepoint/install/software-requirements-for-database-servers-for-sharepoint-server-subscription-edition
https://learn.microsoft.com/en-us/sharepoint/what-s-new/what-s-deprecated-or-removed-from-sharepoint-server-subscription-edition
