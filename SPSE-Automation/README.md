# SPSE Automation v0.3.3 — LOCAL ONLY

Instalator SharePoint Server Subscription Edition dla 4 serwerów Windows Server 2025:
`SPSEAPP1`, `SPSEAPP2`, `SPSEWFE1`, `SPSEWFE2`. SQL: `SPSEDB` (TCP 1433).

**[Pobierz najnowszy ZIP v0.3.3](SPSE_Automation_v03_3_Local.zip)** · **[Kod źródłowy](spse-automation/)** · **[Pełna instrukcja](spse-automation/README.md)**

## Co zmieniło się w v0.3.3?

Audyt SPSEAPP1 potwierdził zainstalowanie wszystkich 30 wymaganych funkcji Windows i brak oczekującego restartu.

Poprawiono krok `SqlAlias`: wcześniej próbował bezpośrednio tworzyć wpis w rejestrze i mógł wywołać błąd `PropertyNotFoundStrict`, gdy alias nie istniał. Teraz uruchamia **lokalnie 64-bitowy SQL Server Client Network Utility (`cliconfg.exe`)**. Operator sam tworzy alias przez GUI, a skrypt sprawdza wynik bez modyfikacji rejestru. W przypadku konfliktu z już istniejącym aliasem skrypt odmawia nadpisania.

Instrukcja w narzędziu: **Alias > Add > TCP/IP**, alias `SQL-SPSE`, serwer `SPSEDB`, port `1433`.

### Kolejny krok tylko na SPSEAPP1

```powershell
# 1. Potwierdzenie 30/30 funkcji Windows:
.\SPSEAPP1.ps1 -Step Audit
# 2. Konfiguracja klienta SQL:
.\SPSEAPP1.ps1 -Step SqlAlias
# 3. Ponowny audyt lokalny:
.\SPSEAPP1.ps1 -Step Audit
```

Nie uruchamiaj jeszcze `CreateFarm`, `JoinFarm` ani pozostałych instalacji bez weryfikacji.

## Bezpieczeństwo

- Tylko wykonanie lokalne, jeden serwer naraz, sprawdzenie nazwy hosta.
- Brak PowerShell Remoting, zdalnej dystrybucji instalatorów, automatycznych restartów i CI.
- Nie przechowuj w publicznym repozytorium kluczy licencyjnych, haseł ani wyników audytów infrastruktury.
- Wersja nie jest przetestowana na docelowym Windows Server 2025 poza zgłoszonym działającym etapem `Audit` v0.3.2; nowe `SqlAlias` wymaga lokalnej weryfikacji.

SHA256 ZIP: `7f4db99f78c0aceffea2d202ee85b26e498a82770cd08cc58e18d903792f3ff6`.
