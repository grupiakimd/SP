SharePoint 2019 -> SharePoint Subscription Edition
AUDYT v2.0 + INTERAKTYWNY DASHBOARD HTML (OFFLINE)
===================================================

NOWOSC W V2
- Jeden czytelny SPSE_Readiness_Report.html z bocznym menu i KPI.
- Ryzyka HIGH / MEDIUM / UNKNOWN oraz dzialania do wykonania.
- Osobne zakladki: infrastruktura, SharePoint, SQL, uslugi, diagnostyka.
- Wyszukiwanie, sortowanie, filtrowanie ryzyk, strony tabel, CSV.
- Widoczny status, czy kolektor zdobyl komplet wymaganych danych.
- Wszystkie rekordy z FullInventory.json (bez limitu 600 z v1).
- HTML nie wymaga internetu, CDN, serwera WWW ani dostepu do SharePoint.
- Mozna wygenerowac dashboard z juz istniejacego audytu v1, bez ponownego skanu.

PLIKI W PAKIECIE
- Invoke-SP2019ReadinessAudit.ps1 : kolektor danych (audyt calej farmy).
- New-SPSEDashboard.ps1          : generator HTML z istniejacego audytu.
- dashboard_template.html       : szablon wymagany przez generator.
- PRZYKLAD_DASHBOARD_DEMO.html  : przyklad z DANYMI FIKCYJNYMI.

1. NOWY AUDYT FARMY
-------------------
Wszystkie trzy pliki (oba PS1 + dashboard_template.html) rozpakuj
DO JEDNEGO katalogu, np. C:\Scripts\SPSEAudit.
Na obecnym APP/WFE SharePoint 2019 uruchom Windows PowerShell 5.1 x64,
z uprawnieniami SharePoint Shell Admin i odczytu konfiguracji farmy:

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "C:\Scripts\SPSEAudit\Invoke-SP2019ReadinessAudit.ps1" -OutputRoot "C:\SP_Audit"

Wyniki trafiaja do osobnego katalogu:
  C:\SP_Audit\SP2019_Audit_<SERWER>_<DATA>\

Otworz DWUKLIKIEM:
  SPSE_Readiness_Report.html

Powstana tez CSV, FullInventory.json, AuditMetadata.json i ZIP calosci.
Audyt farmy tylko odczytuje; zapisuje wylacznie lokalne pliki wynikow.
Nie modyfikuje SharePoint, baz SQL, IIS ani uslug Windows.

Opcjonalny glebszy audyt (poza godzinami pracy):
& "C:\Scripts\SPSEAudit\Invoke-SP2019ReadinessAudit.ps1" `
  -OutputRoot "C:\SP_Audit" -DeepWebScan -MaxWebs 5000 -RemoteWinRM

RemoteWinRM i SQL wymagaja odpowiednich uprawnien. Skan witryn i list
moze obciazyc baze zawartosci; nie uruchamiaj glebi w godzinach szczytu.

2. ULEPSZENIE STAREGO AUDYTU v1 — BEZ PONOWNEGO SKANOWANIA
---------------------------------------------------------
Wystarczy stary katalog audytu z FullInventory.json lub ZIP z wynikami.
Nie trzeba byc na serwerze SharePoint; wystarczy PowerShell 5.1 i
obecnosc obu plikow generatora w tym samym katalogu.

Przyklad dla istniejacego folderu:
& "C:\Scripts\SPSEAudit\New-SPSEDashboard.ps1" `
  -InputPath "C:\SP_Audit\SP2019_Audit_APP01_20261013_092500"

Przyklad dla starego ZIP (rozpakowany tymczasowo przez generator):
& "C:\Scripts\SPSEAudit\New-SPSEDashboard.ps1" `
  -InputPath "C:\SP_Audit\SP2019_Audit_APP01_20261013_092500.zip"

Dla ZIP powstaje HTML obok ZIP. Mozna jawnie wskazac lokalizacje:
& "C:\Scripts\SPSEAudit\New-SPSEDashboard.ps1" `
  -InputPath "D:\Audyt\FullInventory.json" `
  -OutputPath "D:\Audyt\Raport_SPSE.html"

3. OGRANICZENIA I WAZNE WSKAZOWKI
--------------------------------
- Raport pokazuje stan z CHWILI audytu. Nie odpytuje farmy z przegladarki.
- 0 wynikow nie musi oznaczac, ze elementu nie ma: diagnostyka rozroznia
  skan pominiety, blad i pusty wynik, o ile takie dane sa dostepne.
- Wynik nie jest automatycznym GO do migracji ani certyfikatem zgodnosci.
- WSP, InfoPath, Workflow Manager/2013, auth, integracje i web.config
  wymagaja recznej walidacji i testow na nowej farmie SE.
- Historia backupow z msdb nie jest testem odtworzenia kopii.
- Wielkosci baz SQL oznaczaja miejsce zaalokowane, nie realny rozmiar danych.
- W duzych farmach FullInventory.json/HTML moga byc znacznej wielkosci.
  HTML wyswietla tabele porcjami, aby ograniczyc ilosc elementow ekranu.
- Plik HTML i ZIP zawieraja nazwy serwerow, konta, adresy wewnetrzne,
  wpisy bledow i nazwy witryn: udostepniaj je tylko uprawnionym osobom.
- Eksport filtrowanych CSV dziala po stronie przegladarki (nie w chmurze).
- PowerShell 5.1 na rzeczywistej farmie NIE zostal w tym srodowisku
  wykonany; generator i raport testowane sa na danych demonstracyjnych.

4. KOLEJNY KROK
--------------
Przejrzyj Dashboard -> Diagnostyka -> Ryzyka, a potem przekaz ZIP z
wynikami do analizy migracji. Ostateczna sciezka migracji zalezy od
stanu faktycznego farmy i testow odtwarzania baz na SharePoint SE.
