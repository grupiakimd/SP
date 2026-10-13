# Historia wersji

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
