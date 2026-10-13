# Exchange Server SE — audyt przekierowań poczty

Niezależny moduł repozytorium `SP`. Działa **tylko do odczytu** na stacji/serwerze Windows w domenie AD, poza serwerem Exchange. Raporty HTML i CSV zawierają **wyłącznie skrzynki z wykrytym przekierowaniem**.

## Zakres

- UserMailbox i SharedMailbox tylko w bazach wskazanych w `config.json`.
- Ustawienia skrzynek: `ForwardingAddress`, `ForwardingSmtpAddress` oraz `DeliverToMailboxAndForward`.
- Reguły: `Get-InboxRule -IncludeHidden`, akcje `ForwardTo`, `RedirectTo`, `ForwardAsAttachmentTo`, także reguły wyłączone i ukryte widoczne dla Exchange PowerShell.
- **Nie** skanuje Transport Rules ani treści wiadomości i nie zmienia ustawień.

## Dwa niezależne znaczenia „Full”

**Zakres skrzynek** określa `Mode` w lokalnym `config.json`:
- `"Mode": "Test"`: tylko skrzynki z `TestMailboxes` (albo z `-Mailboxes`), i tylko jeśli należą do baz z `Databases`. Do testu wystarczy wskazać jedną lub więcej właściwych baz.
- `"Mode": "Full"`: UserMailbox i SharedMailbox w **pięciu** bazach z `Databases`. Lista testowa nie jest wtedy używana.

**Szczegółowość raportu** określa przełącznik **`-Full`**:
- Bez niego: 9 kolumn — Skrzynka, Adres, Typ, Źródło przekierowania, Przekierowanie do, Status, Nazwa reguły, Warunki i wyjątki, Kopia w skrzynce.
- Z nim: 14 kolumn — dodatkowo Baza danych, Gdzie sprawdzić, Parametr techniczny, Identyfikator reguły, Oryginalny odbiorca (surowy).

**`-Full` nie zmienia zakresu skanowania.** Można przygotować szczegółowy raport dla czterech skrzynek testowych.

## Konfiguracja i uruchomienie

Wymagania: Windows PowerShell 5.1, komputer dołączony do domeny AD, konto z Exchange RBAC uprawnionym do odczytu skrzynek i reguł oraz dostęp do Exchange Remote PowerShell. Nie trzeba instalować Exchange Management Tools. Skrypt używa Kerberos i endpointu `http://<ExchangeServer>/PowerShell/` (zwykle TCP 80). Port SMTP 587 jest osobny.

1. Pobierz folder do `C:\Skrypty\exchange_forward`.
2. Skopiuj `config.example.json` do **lokalnego** `config.json`.
3. Ustaw `ExchangeServer` (np. `exmb1`), rzeczywiste bazy w `Databases` i cztery adresy w `TestMailboxes`; pozostaw `Mode=Test`.
4. Uruchom w Windows PowerShell 5.1:

       cd C:\Skrypty\exchange_forward
       .\Audit-ExchangeForwarding.ps1 -ExchangeServer exmb1 -NoEmail -OpenReport

5. Administracyjny raport z **tych samych** skrzynek:

       .\Audit-ExchangeForwarding.ps1 -ExchangeServer exmb1 -Full -NoEmail -OpenReport

6. Bez zmiany pliku testowego możesz ręcznie podać adresy:

       .\Audit-ExchangeForwarding.ps1 -ExchangeServer exmb1 -Mailboxes 'test1@firma.pl','test2@firma.pl','test3@firma.pl','test4@firma.pl' -NoEmail -OpenReport

`-NoEmail` wyłącza wysyłkę wyłącznie w bieżącym uruchomieniu. `-OpenReport` otwiera HTML w przeglądarce — używaj tylko interaktywnie, nie w Harmonogramie zadań.

## Interpretacja raportu

- **Aktywne**: skonfigurowane przekierowanie skrzynki lub aktywna reguła.
- **Wyłączone**: skonfigurowana, ale wyłączona reguła.
- **Kopia w skrzynce — Tak / Nie**: ustawienie `DeliverToMailboxAndForward` przekierowania skonfigurowanego na skrzynce Exchange.
- **Kopia w skrzynce — Zależnie od działań reguły**: nie zakładamy, że wiadomość zostaje, bo reguła może mieć dodatkowe akcje.
- **Outlook / OWA** oznacza typ reguły; nie jest dowodem, czy utworzył ją Outlook, OWA czy administrator przez PowerShell.
- **Wykryte przekierowania**: liczba pozycji/odbiorców, może być większa od liczby skrzynek.
- **Błędy odczytu**: np. brak uprawnień, nieistniejąca skrzynka lub niewłaściwa baza. Przy błędach raport ma status **Niepełny**.

Ukryte reguły ujawniane przez `Get-InboxRule -IncludeHidden` są automatycznie sprawdzane. To jednak nie gwarantuje wykrycia nietypowych manipulacji MAPI, reguł działających wyłącznie po stronie klienta ani faktycznego dostarczenia przekierowanej wiadomości. Skrypt pokazuje warunki i wyjątki, ale nie wykonuje ich logicznej symulacji.

## Raporty

`Reports` (lub folder ustawiony w `OutputDirectory`):
- `Forwarding_YYYYMMDD_HHMMSS.html` — interaktywny HTML z filtrem, po polsku.
- `Forwarding_YYYYMMDD_HHMMSS.csv` — te same kolumny, UTF-8 i separator średnik.
- `Summary_YYYYMMDD_HHMMSS.json` — statystyki oraz techniczny stan COMPLETE/PARTIAL.
- `Errors_YYYYMMDD_HHMMSS.csv` — tworzony tylko gdy wystąpi błąd odczytu.

Kod wyjścia: 0 = kompletny audyt; 2 = niepełny audyt; 3 = błąd wysyłki SMTP. Awaria uruchomienia/połączenia również uniemożliwia uznanie audytu za kompletny.

## SMTP AUTH i Harmonogram zadań

W lokalnym `config.json` uzupełnij `Email.Enabled=true`, `Host`, `Port=587`, `UseStartTls=true`, `From`, `To`, `CredentialFile`. Exchange musi udostępniać rzeczywiste uwierzytelnienie SMTP AUTH/STARTTLS i certyfikat zaufany dla Windows. Sam otwarty port 587 nie wystarczy; implicit TLS 465 i OAuth nie są obsługiwane w tym skrypcie.

**Pod tym samym kontem Windows, które uruchomi zadanie, na tym samym komputerze** wykonaj:

    .\Set-SmtpCredential.ps1

Plik `smtp-credential.xml` jest szyfrowany Windows DPAPI dla tożsamości, która go utworzyła. Zabezpiecz ACL folderu. Następnie zarejestruj zadanie (przykład na 06:00):

    .\Register-ScheduledTask.ps1 -ScriptDirectory C:\Skrypty\exchange_forward -At 06:00 -User 'DOMENA\svc-exchange-audit'

Harmonogram uruchamia skrypt według lokalnego `config.json`, bez `-OpenReport`; przy włączonym SMTP wysyła HTML, CSV, JSON i ewentualnie diagnostykę.

## Bezpieczeństwo i weryfikacja

Repozytorium jest publiczne. **Nie publikuj** rzeczywistego `config.json`, plików DPAPI i raportów zawierających nazwy skrzynek, adresy przekierowań lub treści reguł. Ogranicz dostęp NTFS do katalogu wynikowego.

GitHub Actions uruchamia parser Windows PowerShell 5.1 oraz testy offline standardowego i administracyjnego raportu na czterech sztucznych skrzynkach, w tym ukrytej/wyłączonej regule przekierowania. Testy **nie zastępują** sprawdzenia działania na rzeczywistym Exchange SE.
