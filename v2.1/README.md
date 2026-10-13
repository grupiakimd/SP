# SharePoint 2019 -> Subscription Edition | Audyt v2.1

## Co poprawiono

- Generator HTML automatycznie wyszukuje **najnowszy przebieg** w katalogu nadrzednym (np. C:\SP_Audit).
- Gdy FullInventory.json nie istnieje lub jest uszkodzony, generator probuje odtworzyc dashboard z CSV.
- Raport odzyskany z CSV ma **oznaczenie danych niepelnych** i nie otrzymuje pozornej punktacji gotowosci.
- Eksport CSV, JSON i HTML odbywa sie w oddzielnych etapach; blad JSON nie blokuje automatycznie HTML.
- Kolektor zapisuje AuditStatus.txt i CollectionErrors.csv, aby od razu pokazac ewentualne bledy eksportu.
- v1 oraz v2 pozostaja bez zmian.

## Odzyskanie HTML BEZ powtarzania audytu

Pobierz komplet plikow z katalogu v2.1 do jednego katalogu na serwerze:
- New-SPSEDashboard.ps1
- dashboard_template.html

Uruchom **Windows PowerShell 5.1, 64-bit**, a nastepnie:

~~~powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
& "C:\Scripts\SP\v2.1\New-SPSEDashboard.ps1" -InputPath "C:\SP_Audit"
~~~

Mozesz wskazac rowniez katalog konkretnego przebiegu audytu,
bezposrednio FullInventory.json albo ZIP z wynikami.

HTML zostanie zapisany w katalogu wykrytego przebiegu jako
**SPSE_Readiness_Report.html**; dla ZIP — obok archiwum.

Jesli stare CSV sa poza C:\SP_Audit, podaj ich rzeczywisty katalog,
np. C:\temp\sprawdzenie\v2\SP_Audit.

## Nowy audyt v2.1

Skopiuj do jednego katalogu trzy pliki:
- Invoke-SP2019ReadinessAudit.ps1
- New-SPSEDashboard.ps1
- dashboard_template.html

Uruchom lokalnie na serwerze SharePoint 2019 z uprawnieniami SP Shell Admin:

~~~powershell
& "C:\Scripts\SP\v2.1\Invoke-SP2019ReadinessAudit.ps1" -OutputRoot "C:\SP_Audit"
~~~

Nastepnie sprawdz AuditStatus.txt oraz raport HTML w nowym podkatalogu.

## Test generatora bez SharePoint

~~~powershell
& "C:\Scripts\SP\v2.1\tests\Test-Dashboard.ps1"
~~~

Test tworzy tymczasowe syntetyczne dane, sprawdza odzyskiwanie z CSV
i sprzata katalog testowy. Nie laczy sie z farma.

## Ograniczenia i bezpieczenstwo

- **Nie publikuj na GitHubie wynikow audytu produkcyjnego**: zawieraja nazwy serwerow, kont, witryn, bazy danych, URL i certyfikaty.
- CSV-only nie gwarantuje kompletnego inwentarza; raport wyraznie pokazuje to ograniczenie.
- Po pierwszym uruchomieniu zweryfikuj logi PowerShell i CollectionErrors.csv.
- Nie przeprowadzono testu wykonania kolektora na realnej farmie SharePoint 2019.
- Narzedzia niczego nie zmieniaja w SharePoint ani SQL, ale DeepWebScan i zdalne sondowanie moga obciazyc srodowisko.
