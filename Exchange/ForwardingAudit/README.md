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
- Bez niego: 10 kolumn — Skrzynka, Adres, Typ, Źródło przekierowania, Przekierowanie do, Kierunek, Status, Nazwa reguły, Warunki i wyjątki, Kopia w skrzynce.
- Z nim: 15 kolumn — dodatkowo Baza danych, Gdzie sprawdzić, Parametr techniczny, Identyfikator reguły, Oryginalny odbiorca (surowy).

**`-Full` nie zmienia zakresu skanowania.** Można przygotować szczegółowy raport dla czterech skrzynek testowych.

## Konfiguracja i uruchomienie

Wymagania: Windows PowerShell 5.1, komputer dołączony do domeny AD, konto z Exchange RBAC uprawnionym do odczytu skrzynek i reguł oraz dostęp do Exchange Remote PowerShell. Nie trzeba instalować Exchange Management Tools. Skrypt używa Kerberos i endpointu `http://<ExchangeServer>/PowerShell/` (zwykle TCP 80). Port SMTP 587 jest osobny.

1. Pobierz folder do `C:\Skrypty\exchange_forward`.
2. Skopiuj `config.example.json` do **lokalnego** `config.json`.
3. Ustaw `ExchangeServer` (np. `EXCHANGE-SERVER`), rzeczywiste bazy w `Databases` i cztery adresy w `TestMailboxes`; pozostaw `Mode=Test`. Koniecznie uzupełnij też `InternalDomains` rzeczywistymi domenami SMTP Twojej organizacji.
4. Uruchom w Windows PowerShell 5.1:

       cd C:\Skrypty\exchange_forward
       .\Audit-ExchangeForwarding.ps1 -ExchangeServer EXCHANGE-SERVER -NoEmail -OpenReport

5. Administracyjny raport z **tych samych** skrzynek:

       .\Audit-ExchangeForwarding.ps1 -ExchangeServer EXCHANGE-SERVER -Full -NoEmail -OpenReport

6. Bez zmiany pliku testowego możesz ręcznie podać adresy:

       .\Audit-ExchangeForwarding.ps1 -ExchangeServer EXCHANGE-SERVER -Mailboxes 'test1@firma.pl','test2@firma.pl','test3@firma.pl','test4@firma.pl' -NoEmail -OpenReport

`-NoEmail` wyłącza wysyłkę wyłącznie w bieżącym uruchomieniu. `-OpenReport` otwiera HTML w przeglądarce — używaj tylko interaktywnie, nie w Harmonogramie zadań.

## Interpretacja raportu

- **Aktywne**: skonfigurowane przekierowanie skrzynki lub aktywna reguła.
- **Wyłączone**: skonfigurowana, ale wyłączona reguła.
- **Kopia w skrzynce — Tak / Nie**: ustawienie `DeliverToMailboxAndForward` przekierowania skonfigurowanego na skrzynce Exchange.
- **Kopia w skrzynce — Zależnie od działań reguły**: nie zakładamy, że wiadomość zostaje, bo reguła może mieć dodatkowe akcje.
- **Outlook / OWA** oznacza typ reguły; nie jest dowodem, czy utworzył ją Outlook, OWA czy administrator przez PowerShell.
- **Wykryte przekierowania**: liczba pozycji/odbiorców, może być większa od liczby skrzynek.
- **Przekierowania na zewnątrz**: liczba pozycji z celem SMTP spoza listy `InternalDomains` (wliczane są również reguły wyłączone).
- **Kierunek**: `Wewnętrzne`, `Zewnętrzne` lub `Nieustalone`. Nieznany adres nigdy nie zostaje automatycznie uznany za wewnętrzny lub zewnętrzny.
- **Błędy odczytu**: np. brak uprawnień, nieistniejąca skrzynka lub niewłaściwa baza. Przy błędach raport ma status **Niepełny**.

Ukryte reguły ujawniane przez `Get-InboxRule -IncludeHidden` są automatycznie sprawdzane. To jednak nie gwarantuje wykrycia nietypowych manipulacji MAPI, reguł działających wyłącznie po stronie klienta ani faktycznego dostarczenia przekierowanej wiadomości. Skrypt pokazuje warunki i wyjątki, ale nie wykonuje ich logicznej symulacji.

## Domeny wewnętrzne i filtr zewnętrznych przekierowań

W lokalnym `config.json` dodaj:

~~~json
"InternalDomains": ["firma.pl", "firma.local", "druga-domena.pl"]
~~~

Wpisz **wszystkie domeny SMTP obsługiwane wewnętrznie**, także domeny alternatywne. Skrypt wymaga tej listy i nie rozpocznie skanowania, jeżeli jej brakuje. Porównuje domeny w sposób nieczuły na wielkość liter, **po pełnej nazwie**, a nie przez fragment tekstu. Poddomeny trzeba dopisać osobno.

Skrzynki i reguły nadal są zbierane w pełnym zakresie. W HTML obok pola wyszukiwania jest filtr **Tylko przekierowania zewnętrzne**. Filtr nie zmienia CSV ani danych audytu. Licznik przekierowań zewnętrznych zastępuje licznik błędów w widocznym nagłówku.

Skrypt rozwiązuje obiekty MailContact/MailUser na ich `ExternalEmailAddress`, jeśli Exchange zwróci taki adres; dzięki temu kontakt o wewnętrznym aliasie prowadzący na zewnątrz zostanie wykryty. Gdy nie można ustalić adresu SMTP celu, wynik ma kierunek `Nieustalone` — nie jest ukrywany przez główny raport. Skrypt nie analizuje docelowych członków grup dystrybucyjnych ani dalszych przekierowań kaskadowych. Pełną listę zaakceptowanych domen możesz zweryfikować na serwerze Exchange poleceniem `Get-AcceptedDomain`, ale nie każda domena zaakceptowana musi oznaczać lokalne miejsce ostatecznego dostarczenia.

Błędy odczytu **nadal są zapisywane** w `Errors_*.csv`, a status `Niepełny` pozostaje widoczny — usunięcie kafelka z liczbą błędów nie oznacza ignorowania problemów audytu.

## Raporty

`Reports` (lub folder ustawiony w `OutputDirectory`):
- `Forwarding_YYYYMMDD_HHMMSS.html` — interaktywny HTML z filtrem, po polsku.
- `Forwarding_YYYYMMDD_HHMMSS.csv` — te same kolumny, UTF-8 i separator średnik.
- `Summary_YYYYMMDD_HHMMSS.json` — statystyki oraz techniczny stan COMPLETE/PARTIAL.
- `Errors_YYYYMMDD_HHMMSS.csv` — tworzony tylko gdy wystąpi błąd odczytu.

Kod wyjścia: 0 = kompletny audyt; 2 = niepełny audyt; 3 = błąd wysyłki SMTP; 4 = PDF nie powstał mimo włączenia. Awaria uruchomienia/połączenia również uniemożliwia uznanie audytu za kompletny.

## SMTP AUTH i Harmonogram zadań

W lokalnym `config.json` uzupełnij `Email.Enabled=true`, `Host`, `Port=587`, `UseStartTls=true`, `From`, `To`, `CredentialFile`. Exchange musi udostępniać rzeczywiste uwierzytelnienie SMTP AUTH/STARTTLS i certyfikat zaufany dla Windows. Sam otwarty port 587 nie wystarczy; implicit TLS 465 i OAuth nie są obsługiwane w tym skrypcie.

**Pod tym samym kontem Windows, które uruchomi zadanie, na tym samym komputerze** wykonaj:

    .\Set-SmtpCredential.ps1

Plik `smtp-credential.xml` jest szyfrowany Windows DPAPI dla tożsamości, która go utworzyła. Zabezpiecz ACL folderu. Następnie zarejestruj zadanie (przykład na 06:00):

    .\Register-ScheduledTask.ps1 -ScriptDirectory C:\Skrypty\exchange_forward -At 06:00 -User 'DOMENA\svc-exchange-audit'

Harmonogram uruchamia skrypt według lokalnego `config.json`, bez `-OpenReport`; przy włączonym SMTP wysyła HTML, CSV, JSON i ewentualnie diagnostykę.

## Bezpieczeństwo i weryfikacja

Repozytorium jest obecnie prywatne, ale nadal trzeba chronić pliki lokalne. **Nie publikuj** rzeczywistego `config.json`, plików DPAPI i raportów zawierających nazwy skrzynek, adresy przekierowań lub treści reguł. Ogranicz dostęp NTFS do katalogu wynikowego.

GitHub Actions uruchamia parser Windows PowerShell 5.1 oraz testy offline standardowego i administracyjnego raportu na czterech sztucznych skrzynkach, w tym ukrytej/wyłączonej regule przekierowania. Testy **nie zastępują** sprawdzenia działania na rzeczywistym Exchange SE.

## Filtrowanie kolumn i PDF

W HTML można używać jednocześnie wyszukiwania globalnego, filtra zewnętrznych przekierowań oraz **filtrów dla poszczególnych kolumn** (lista wyboru lub wpisanie tekstu). Przycisk `Wyczyść filtry` przywraca wszystkie wiersze. Filtrowanie nie zmienia CSV ani zebranych danych.

Przycisk `Drukuj / zapisz do PDF` wywołuje okno wydruku dla aktualnie widocznych wierszy. Wybierz systemową drukarkę `Microsoft Print to PDF` albo `Zapisz jako PDF` w przeglądarce. To nie jest samodzielny generator PDF.

Możesz włączyć **automatyczne zapisywanie pliku PDF** do Reports również z Harmonogramu. Wymagany jest **Microsoft Edge zainstalowany na komputerze wykonującym audyt**, nie na Exchange. Opcjonalna sekcja lokalnego `config.json`:

~~~json
"Pdf": {
  "Enabled": true,
  "EdgePath": ""
}
~~~

Pusty `EdgePath` oznacza standardową ścieżkę instalacji Edge. Możesz też wymusić PDF dla jednego uruchomienia przełącznikiem `-Pdf`. Wynik: `Forwarding_YYYYMMDD_HHMMSS.pdf`, a przy włączonym SMTP także załącznik do e-maila. Ten PDF obejmuje cały raport; przefiltrowany wydruk uzyskasz przez przycisk w przeglądarce. Jeśli eksport automatyczny się nie uda, HTML/CSV pozostaną, a skrypt zwróci kod 4 (o ile nie było wcześniejszego błędu SMTP).

Test eksportu PDF bez wysyłki e-maila:

    .\Audit-ExchangeForwarding.ps1 -NoEmail -Pdf -OpenReport

## Testowanie SMTP bez ponownego skanowania Exchange

`ExchangeServer` służy do odczytu skrzynek, a **`Email.Host` służy do połączenia SMTP**. W `config.json` trzeba wpisać rzeczywisty FQDN serwera poczty obsługującego SMTP AUTH / STARTTLS, `Port=587`, `UseStartTls=true`, prawidłowego nadawcę i odbiorców. Konto SMTP musi mieć zgodę na wysyłkę z wybranego adresu.

Po pobraniu nowych plików wykonaj:

    .\Test-Smtp.ps1

Skrypt nie łączy się z Exchange PowerShell i nie odczytuje żadnych skrzynek. Sprawdza DNS i wysyła krótką wiadomość testową przez uwierzytelnione SMTP. Pokazuje pełniejszy łańcuch przyczyn błędów, w tym `InnerException` i status SMTP; **nie wypisuje hasła**. Właściwy audyt również używa tego modułu.

Typowe przyczyny to błędny `Email.Host`, brak komunikacji na TCP 587, certyfikat niezaufany, brak obsługi STARTTLS, zablokowany SMTP AUTH, niepoprawne hasło albo brak `Send As`. Nie wyłączaj weryfikacji certyfikatu TLS.

## Gdy Send-MailMessage działa, a wysyłka audytu nie

Jeżeli ręczne `Send-MailMessage -SmtpServer <serwer> -UseSsl -Port 587 -Credential (Get-Credential)` działa, użyj dokładnie **tych samych** parametrów w `config.json`:

~~~json
"Email": {
  "Enabled": true,
  "Host": "10.0.0.10",
  "Port": 587,
  "UseStartTls": true,
  "Transport": "SendMailMessage",
  "From": "audit@example.local",
  "To": ["odbiorca@example.local"],
  "CredentialFile": "smtp-credential.xml"
}
~~~

Powyższe wartości to przykłady — wstaw **swój działający adres IP SMTP, From i To**. Połączenie Exchange Remote PowerShell (`ExchangeServer`) jest niezależne od serwera pocztowego `Email.Host`. `Transport=SendMailMessage` uruchamia znane polecenie Windows PowerShell 5.1 (`Send-MailMessage`) z hasłem z bezpiecznego pliku DPAPI. Mechanizmy `Transport=SmtpClient` i `Transport=SendMailMessage` pozostają obsługiwane wyłącznie jako opcje awaryjne; domyślnym transportem jest `MailKit`.

**Sprawdź pocztę bez skanowania skrzynek i z interaktywnym logowaniem:**

    .\Test-Smtp.ps1 -PromptForCredential -Transport SendMailMessage

Jeżeli `config.json` ma inny serwer/nadawcę/odbiorców niż działające polecenie, można tymczasowo podać parametry bez zapisywania ich do konfiguracji:

    .\Test-Smtp.ps1 -PromptForCredential -Transport SendMailMessage -SmtpServer "10.0.0.10" -From "audit@example.local" -To "odbiorca@example.local"

**Jeśli test się uda**, powtórz go z `-SaveCredential`, aby zapisać poświadczenia **tego samego konta SMTP** dla audytu:

    .\Test-Smtp.ps1 -PromptForCredential -Transport SendMailMessage -SaveCredential

`-SaveCredential` zapisuje plik `smtp-credential.xml` *dopiero po udanej wysyłce*, pod tożsamością Windows bieżącej sesji. Harmonogram musi działać na tym samym komputerze i koncie Windows. W razie uruchamiania Harmonogramu jako inne konto, zapisane poświadczenia należy przygotować pod to konto. Nie zapisuj hasła w JSON ani repozytorium.

Uwaga: `Send-MailMessage` jest wycofanym poleceniem, ale w tym środowisku Windows PowerShell 5.1 służy jako świadomie wybrany tryb zgodności z już działającym procesem. `-UseSsl` wymaga STARTTLS, nie wyłącza weryfikacji certyfikatu. Po teście warto przejść docelowo na utrzymywany klient SMTP z TLS i uwierzytelnianiem zgodnym z polityką organizacji.


## MailKit — aktualnie zalecany mechanizm SMTP (Windows PowerShell 5.1)

Domyślny transport to **MailKit** z obowiązkowym STARTTLS na TCP 587 i weryfikacją certyfikatu TLS. Poświadczenia nadal pochodzą z lokalnego pliku DPAPI `smtp-credential.xml` i nie są kopiowane do repozytorium.

**Jednorazowo na komputerze wykonującym audyt** (wymagany Windows PowerShell 5.1, .NET Framework 4.8+ oraz chwilowy dostęp HTTPS do `api.nuget.org`):

    cd C:\Skrypty\exchange_forward
    .\Install-MailKit.ps1

Instalator pobiera **przypięte wersje** MailKit 4.17.0 / MimeKit 4.17.0 i ich zależności z oficjalnego NuGet; sprawdza SHA512 paczek i zapisuje biblioteki do `Dependencies\MailKit\lib`. Folder `Dependencies/` jest ignorowany przez Git. **W codziennym audycie i Harmonogramie nie następuje żadne pobieranie zależności.** Jeśli serwer nie ma dostępu do NuGet, możesz zainstalować biblioteki na komputerze administracyjnym o takim samym .NET Framework i skopiować cały folder `Dependencies\MailKit\lib` na maszynę docelową, pamiętając o zasadach bezpieczeństwa organizacji.

W `config.json` ustaw w istniejącej sekcji `Email`:

~~~json
"Transport": "MailKit",
"Port": 587,
"UseStartTls": true
~~~

Pozostaw istniejące `Email.Host`, `From`, `To` i `CredentialFile`. Wpisz rzeczywistą nazwę serwera SMTP — dla certyfikatu TLS warto użyć FQDN zgodnego z nazwą na certyfikacie; IP z wcześniejszego testu może się nie zgadzać z SAN certyfikatu. **Nie wyłączaj kontroli certyfikatu**, nie używaj obejścia `ServicePointManager.ServerCertificateValidationCallback`.

Sprawdzenie samej wysyłki, bez powtarzania audytu Exchange:

    .\Test-Smtp.ps1 -Transport MailKit

Lub do jednorazowego testu z ponownym wpisaniem poświadczeń:

    .\Test-Smtp.ps1 -Transport MailKit -PromptForCredential

Aby dopiero po udanym teście zapisać sprawdzone poświadczenia SMTP pod kontem bieżącego użytkownika:

    .\Test-Smtp.ps1 -Transport MailKit -PromptForCredential -SaveCredential

Następnie zwykłe uruchomienie audytu:

    .\Audit-ExchangeForwarding.ps1 -Pdf -OpenReport

`-NoEmail` nadal wyłącza wysyłkę dla jednego uruchomienia. Automatyczne zadanie Windows korzysta z `Email.Transport` i nie wymaga ponownej rejestracji po aktualizacji skryptu, o ile ścieżki nie zmieniono.

**Wycofane mechanizmy** `SendMailMessage` i `SmtpClient` pozostają obsługiwane **wyłącznie jako jawnie wybrane rozwiązanie awaryjne**. MailKit nie przełącza się automatycznie na nieszyfrowaną komunikację ani na inny transport. Uwaga: MailKit wymaga weryfikacji na właściwym serwerze SMTP; testy CI weryfikują ładowanie zależności i budowę wiadomości, nie uwierzytelnienie w firmowej sieci.

Źródła bibliotek: https://www.nuget.org/packages/MailKit/4.17.0 oraz https://www.nuget.org/packages/MimeKit/4.17.0. Biblioteki nie są dodawane do repozytorium. Lista dokładnych wersji i użytych docelowych DLL jest zapisana lokalnie w `manifest.json`.
