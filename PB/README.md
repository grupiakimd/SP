# PB — Power BI Report Server

Diagnostyka problemów z subskrypcjami i powiadomieniami e-mail w **Power BI Report Server (On-Premises)**.

## Zgłoszenie: 16.10.2026

- Środowisko: Power BI Report Server, wydanie September 2026 (zaktualizowane 15.10.2026).
- Serwer pocztowy: **Exchange On-Premises**.
- Objawy: **wszystkie** subskrypcje e-mail przestały wysyłać wiadomości po aktualizacji PBIRS.
- Przykładowy błąd w interfejsie subskrypcji, 16.10.2026 ok. 11:03:

  `Failure sending mail: One or more errors occurred. Mail will not be resent.`

- **Stan:** przyczyna nieustalona — oczekiwanie na szczegółowy raport diagnostyczny HTML.

Komunikat interfejsu nie rozstrzyga, czy problem dotyczy konfiguracji PBIRS, połączenia SMTP, TLS, uwierzytelnienia, uprawnień relay/Send As czy wyjątku w mechanizmie subskrypcji. Związek czasowy z aktualizacją nie jest samodzielnym dowodem regresji.

## Skrypt

[`PBIRS_Diagnostyka_Mail.ps1`](./PBIRS_Diagnostyka_Mail.ps1)

Skrypt **tylko odczytu** dla Windows PowerShell 5.1+:

1. Odczytuje wybrane ustawienia SMTP z `RSReportServer.config` (bez haseł i loginów).
2. Testuje dostępność hosta SMTP na skonfigurowanym porcie przez TCP.
3. Wyszukuje błędy i wyjątki w logach usługi PBIRS.
4. Zbiera powiązane zdarzenia z dziennika Windows Application.
5. Tworzy czytelny **raport HTML** na pulpicie lub w katalogu tymczasowym i otwiera go w przeglądarce.

Test TCP **nie potwierdza** poprawnego uzgadniania TLS, uwierzytelnienia ani faktycznej dostawy wiadomości. Wskazówki z analizy słów kluczowych nie są jeszcze rozpoznaniem przyczyny.

### Uruchomienie

Na serwerze PBIRS, w PowerShell uruchomionym jako administrator:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\PBIRS_Diagnostyka_Mail.ps1"
```

Opcjonalne rozszerzenie okresu analizy:

```powershell
.\PBIRS_Diagnostyka_Mail.ps1 -DaysBack 5
```

W razie niestandardowej instalacji użyj parametru `-PBIRSRoot`.

## Co dalej

1. Zebrać raport HTML i znaleźć **pełny wyjątek / InnerException** z momentu nieudanej wysyłki.
2. Sprawdzić ustawienia SMTP w PBIRS oraz, zależnie od logów, odpowiedni Receive Connector i logi protokołu SMTP na Exchange.
3. Ustalić, czy wysyłka działa przez anonimowy relay (zaufany IP), czy z użyciem konta.
4. Dopiero po identyfikacji przyczyny zmieniać konfigurację lub rozważać rollback.

**Bezpieczeństwo:** Nie commitować raportów HTML z rzeczywistego środowiska, zrzutów logów, danych użytkowników, adresów wewnętrznych, poświadczeń ani plików `RSReportServer.config`. Raport może ujawniać nazwy serwerów, ścieżki i adresy e-mail. Sprawdzić i zanonimizować go przed przekazaniem poza organizację. Skrypt nie wysyła maili ani nie restartuje usług.
