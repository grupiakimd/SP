# SPSE Automation v0.3.2 — LOCAL ONLY

Kompletny pakiet instalacyjny SharePoint Server Subscription Edition dla czterech serwerów Windows Server 2025:

- `SPSEAPP1`, `SPSEAPP2` — Application with Search
- `SPSEWFE1`, `SPSEWFE2` — Web Front End with Distributed Cache
- SQL Server (istniejący): `SPSEDB`, domyślna instancja TCP 1433

**[Pobierz pełny ZIP v0.3.2](SPSE_Automation_v03_2_Local.zip)** · **[Instrukcja krok po kroku](spse-automation/README.md)** · **[Skrypty źródłowe](spse-automation/)**

## Co zmieniło się w v0.3.2

Ścieżki do mediów **nie są wpisane do `config.json`**. Program pyta o nie interaktywnie, tylko podczas kroku, który wymaga pliku:

| Etap | Pytanie o lokalizację |
|---|---|
| `Audit` | Nie, bez wskazywania ISO |
| `WindowsFeatures` | Opcjonalny lokalny katalog źródłowy komponentów Windows |
| `Prerequisites` / `InstallCore` | Pełna lokalna ścieżka do angielskiego ISO SharePoint SE |
| `InstallPolishLP` | Pełna lokalna ścieżka do polskiego ISO Language Pack |
| `InstallCU` | Pełna lokalna ścieżka do pakietu aktualizacji `.exe` |

Nazwy i katalogi mogą różnić się na każdym serwerze. Ścieżki UNC, mapowane dyski oraz linki/junctions są odrzucane; wymagany jest lokalny dysk stały. Dla CU pozostaje kontrola sumy SHA256 i podpisu.

## Pierwszy krok: tylko audyt

Skopiuj ZIP ręcznie na `SPSEAPP1`, rozpakuj w **dowolnym lokalnym katalogu**, np. `C:\temp`. W Windows PowerShell 5.1 x64 jako administrator:

```powershell
cd C:\temp\spse-automation
.\SPSEAPP1.ps1 -Step Audit
```

Raport HTML w `reports\LocalAudit.html`, pod katalogiem skryptów. Nie uruchamiaj jeszcze instalacji, dopóki nie przeanalizujemy raportu.

## Zasady bezpieczeństwa

- **Jeden serwer = jedno lokalne wykonanie**. Skrypt sprawdza rzeczywistą nazwę komputera.
- Brak zdalnych wywołań PowerShell, kopiowania instalatorów i restartów.
- Instalacyjne etapy wymagają oddzielnego wyraźnego potwierdzenia.
- Utworzenie lub dołączenie do farmy oddziałuje na SQL `SPSEDB` i wymaga osobnej autoryzacji.
- Nigdy nie publikuj w tym publicznym repozytorium haseł, kluczy licencyjnych, ISO ani raportów infrastruktury.
- Brak CI/GitHub Actions; testy i instalacje wyłącznie lokalnie.

Pakiet przeszedł kontrolę struktury, archiwum ZIP oraz statyczne sprawdzenie niedozwolonych poleceń zdalnych, ale **nie został jeszcze wykonany na Windows Server 2025**.

SHA256 ZIP: `3285ba26b741e28aad2bfd4993fc03b1c2c8f1f6750f8e917a077ecb133fdf19`.
