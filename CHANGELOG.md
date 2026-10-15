# Historia wersji

## v2.4 — 2026-10-15

- Nowy **oddzielny** skrypt diagnostyki dla jednej witryny i listy: workflow object model 2010, subskrypcje 2013 (CSOM), konfiguracja autostartu.
- Odczyt WFM proxy, lokalnego SPTimerV4, Timer Jobs i SMTP, opcjonalnie instancji konkretnego elementu.
- Poufny JSON i pseudonimizowany Markdown bez adresów, nazw i surowych błędów.
- Test składni i statyczne kontrole braku operacji modyfikujących.



## v2.3.1 — 2026-10-15 (T-SQL aliases)

- **Osobny, kompletny katalog v2.3.1/** — nie nadpisuje historycznej wersji v2.3.
- Korekta `AS Clustered` → `AS [Clustered]`, dodatkowo zabezpieczenie aliasów `Type` i `State`.
- Rozszerzenie `Test-SPSESqlLocal.ps1`: sprawdza też zapytanie `SERVERPROPERTY` z aliasem `Clustered`, nie tylko połączenie.
- Test regresyjny i workflow PowerShell 5.1 dla izolowanej wersji.



## v2.3.1 — 2026-10-15 (SQL ConnectionStringBuilder)

- Naprawiono `Keyword not supported: 'DataSource'` w Windows PowerShell 5.1.
- Parametry lokalnego połączenia Shared Memory budowane z kanonicznych kluczy ADO.NET.
- Dodano `Test-SPSESqlLocal.ps1` do szybkiego sprawdzenia instancji domyślnej, bez pełnego audytu.
- Dodano test regresji ConnectionStringBuilder w Windows PowerShell 5.1.

## v2.3 — 2026-10-15

- Niezależny lokalny skan SQL przez Shared Memory z Windows Integrated Authentication, bez WMI/WinRM z APP.
- Weryfikacja bazy SharePoint przed scaleniem: blokada importu niewłaściwej instancji i ostrzeżenie o brakach baz.
- Jeden połączony HTML z dodatkowymi sekcjami SQLSettings/SQLStorage oraz pseudonimizowany MD.
- Oryginalne raporty pozostają nienaruszone; zachowana informacja o błędach i pochodzeniu danych.
- Test regresyjny syntetycznego scalenia w Windows PowerShell 5.1.



## v2.2.1 — nocny harmonogram (2026-10-13)

- Folder `v2.2/scheduler/` z gotowym skryptem nocnym i instalatorem Task Scheduler.
- Jednorazowe uruchomienie o najbliższej 22:00, limit pracy 8 godzin i ochrona przed równoległym skanem.
- Logi i walidacja wygenerowanych HTML, JSON, MD; exit code 2 dla audytu częściowego.
- Hasło konta zadania pobierane lokalnie, nieobecne w repozytorium.

## v2.2.1 — 2026-10-13 (poprawka)

- Naprawa konfliktu funkcji `R` z aliasem `Invoke-History` w Windows PowerShell 5.1.
- Jawny status `[MD: OK/FAILED]` oraz pełna ścieżka lokalnego raportu.
- Odtworzenie MD także z częściowych wyników CSV i obsługa `OutputPath` bez rozszerzenia.
- Poprawka tworzenia wierszy tabel Markdown i testy regresyjne.

## v2.2 — 2026-10-13

- Nowy lokalny `New-SPSEShareableAudit.ps1`, tworzący pojedynczy raport `.md` tylko z dozwolonych pól.
- Spójne aliasowanie hostów, baz, Web Applications, site collections, WSP i workflow.
- Celowe pomijanie kont, domen, URL, surowych komunikatów błędów, tekstów z Health Analyzer i ścieżek.
- Opcjonalny przełącznik `-ShareableReport` do głównego audytu; nie publikuje nic automatycznie.
- Fikcyjny test wycieku danych w Windows PowerShell 5.1 i workflow CI.



## v2.1 — 2026-10-13 (poprawka)

- Obsługa katalogu nadrzędnego z wieloma przebiegami audytu.
- Awaryjne generowanie HTML z zachowanych CSV, gdy brak JSON.
- Rozdzielenie eksportów CSV, JSON, HTML i diagnostyki; czytelny AuditStatus.txt.
- Testy generatora na syntetycznych danych JSON/CSV/ZIP (do uruchomienia w PowerShell 5.1).
- Niepełne wyniki są jednoznacznie oznaczone jako niezweryfikowane.

## v2.0 — 2026-10-13

- Interaktywny, lokalny dashboard HTML z nawigacją między obszarami farmy.
- Filtrowanie i wyszukiwanie danych oraz stronicowanie tabel.
- Widok ryzyk migracji oraz diagnostyki brakujących danych.
- Generator `New-SPSEDashboard.ps1` obsługujący wcześniejszy `FullInventory.json` / ZIP audytu.
- Zachowany kolektor i eksport danych strukturalnych CSV/JSON.

## v1.0 — 2026-10-12

- Pierwsza wersja kolektora SharePoint 2019 do audytu gotowości migracji do SE.
- Inwentaryzacja komponentów farmy, baz SQL, SharePoint i powiązanych elementów.
- Eksport CSV/JSON oraz podstawowy raport HTML.
