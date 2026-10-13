# Historia wersji

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
