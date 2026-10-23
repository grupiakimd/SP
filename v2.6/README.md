# SharePoint SE — pilotaż migracji jednej kolekcji (v2.6)

Repo zawiera **kod i procedurę**, a nie produkcyjne dane ani kopie baz. Wykorzystujemy przygotowaną farmę SE (może być `SingleServerFarm`) do testu jednej Site Collection wyodrębnionej w osobnej Content DB.

## Co jest w folderze

- `Get-SPSEPilotReadiness.ps1` — wyłącznie odczytowa inwentaryzacja farmy SE, aplikacji WWW, ścieżek, baz, kolekcji i aplikacji usługowych. Tworzy lokalny dashboard HTML oraz poufny JSON.

## Uruchomienie bez dostępu serwera do internetu

1. Na komputerze z przeglądarką otwórz `https://github.com/grupiakimd/SP`, wybierz **Code → Download ZIP**.
2. Po rozpakowaniu skopiuj katalog `v2.6` na serwer SharePoint SE, np. `C:\temp\sprawdzenie\v26`.
3. W 64-bit Windows PowerShell 5.1 / SharePoint Management Shell jako administrator uruchom:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& 'C:\temp\sprawdzenie\v26\Get-SPSEPilotReadiness.ps1' -OutputRoot 'C:\SPSE_Pilot'
```

W nowym lokalnym katalogu `SE_Pilot_yyyyMMdd_HHmmss` powstaną:

- `SPSE_Pilot_Dashboard.html` — poufna, czytelna inwentaryzacja do obejrzenia w Edge/Chrome;
- `SPSE_Pilot_PRIVATE.json` — poufne dane techniczne do dalszej weryfikacji.

**Nie wysyłaj tych wyników do publicznego repo.** Skrypt nie pobiera instalatorów i nie wykonuje poleceń zmieniających SharePoint.

## Kolejność testowej migracji 2019 → SE

1. **Zidentyfikuj źródło**: upewnij się, że testowana witryna jest korzeniem osobnej Site Collection oraz że źródłowa Content DB zawiera tylko tę kolekcję. Sprawdź wersję źródłowej farmy i brak oczekujących aktualizacji.
2. **Zweryfikuj cel**: wersję/aktualizacje SE, role, Web Application, managed path, uwierzytelnianie, Service Applications, SQL i wolne miejsce. Zachowaj istniejące kolekcje i bazy.
3. **Ustal docelowy URL**: testowe DNS/IIS/Host Header i zgodną ścieżkę zarządzaną (np. `/sites`). Nie przekierowuj produkcyjnego adresu do testu.
4. **Odtwórz zależności**: wymagane Features, WSP, typy zawartości, konta, profile usług, Managed Metadata, Secure Store, Search i inne elementy wykryte przez audyt. Osobne bazy usług mogą wymagać osobnych procedur.
5. **BACKUP/RESTORE — wyłącznie kopia**: utwórz kopię produkcyjnej Content DB (np. backup SQL `COPY_ONLY`) i przywróć **pod inną nazwą** na testowym SQL. Nie podłączaj produkcyjnej bazy ani nie wykonuj operacji aktualizujących na źródle.
6. **Wykonaj Test-SPContentDatabase** na odtworzonej, jeszcze niepodłączonej kopii. Usuń lub udokumentuj blokujące zależności przed aktualizacją.
7. **Wykonaj Mount-SPContentDatabase** tylko dla zatwierdzonej **testowej kopii** w odpowiedniej Web Application. Mount uruchamia aktualizację schematu do SE; nie jest krokiem tylko do odczytu.
8. **Porównaj** dane, liczbę list i elementów, załączniki, wersje, uprawnienia, funkcje i historie procesów. Sprawdź Health Analyzer oraz logi Upgrade.
9. **Test workflow w izolacji**: początkowo zablokuj wysyłkę maili do prawdziwych użytkowników, Timer Jobs i integracje mogące zmieniać produkcję. Historyczne workflow 2010 nie są już wspierane w SE; sama obecność powiązań po migracji nie gwarantuje działania. Workflow 2013 wymagają kompatybilnego Workflow Manager.
10. **Odbiór pilota**: wykonaj scenariusze akceptacyjne w bezpiecznym środowisku, oceń procesy do zastąpienia lokalną automatyzacją i dopiero wtedy ustal plan produkcyjnego przełączenia.

## Czego NIE robi ten pakiet

- Nie tworzy Web Application, nie przywraca i nie montuje baz.
- Nie aktualizuje SharePoint SE ani SQL Server.
- Nie wykonuje prób workflow, nie wysyła poczty ani nie łączy z GitHubem z serwera.
- Nie przesądza jeszcze architektury docelowej, dopóki nie potwierdzimy stanu testowej farmy, SQL i zależności.

**Uwaga:** w publicznym repo trzymamy wyłącznie skrypty i sanitizowane instrukcje, bez wewnętrznych URL-i, nazw serwerów i baz, danych użytkowników, haseł, surowych JSON-ów i backupów. Nie umieszczaj instalatorów produktów Microsoft w repozytorium. Aktualizacje pobieraj z oficjalnych źródeł zgodnie z licencją i zaleceniami producenta.