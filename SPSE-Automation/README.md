# SharePoint SE — instalacja lokalna (v0.3)

Pakiet instalacyjny dla farmy SharePoint Server Subscription Edition: SPSEAPP1, SPSEAPP2, SPSEWFE1, SPSEWFE2, z istniejącym serwerem SQL SPSEDB (TCP 1433).

**[Pobierz pakiet ZIP](SPSE_Automation_v03_Local.zip)** — zawiera dziewięć plików: cztery skrypty startowe, moduły Common.ps1, Invoke-SPSELocal.ps1, LocalFarm.ps1, config.json i szczegółową instrukcję README.md.

## Zasady bezpieczeństwa

- Uruchamianie osobno **lokalnie** na każdej maszynie, z blokadą nazwy hosta.
- Bez WinRM, Invoke-Command, zdalnej dystrybucji i automatycznego kopiowania nośników.
- Domyślna czynność: **Audit** (odczyt systemu i lokalny raport).
- Instalacja funkcji systemowych i SharePoint wymaga osobnego kroku i potwierdzenia.
- Tworzenie farmy i dołączanie serwerów zmienia konfigurację na **SPSEDB** — wykonuj wyłącznie po analizie i autoryzacji.
- Obrazy ISO, CU, hasła i klucze produktu nie są publikowane w repozytorium.
- Repozytorium jest publiczne: nie commituj raportów ani plików zawierających dane firmowe.

## Pierwszy krok

Skopiuj archiwum i instalatory ręcznie na wybrany serwer, rozpakuj skrypty do `E:\install\spse-automation`, a następnie na **SPSEAPP1** uruchom w Windows PowerShell 5.1 x64 jako administrator:

```powershell
cd E:\install\spse-automation
.\SPSEAPP1.ps1 -Step Audit
```

Raport: `E:\install\spse-automation\reports\LocalAudit.html`.

Na pozostałych serwerach użyj odpowiednio `SPSEAPP2.ps1`, `SPSEWFE1.ps1` i `SPSEWFE2.ps1`.

**Uwaga:** pakiet przeszedł kontrolę statyczną, lecz nie został przetestowany na Windows Server 2025. Przed wykonaniem kroków modyfikujących przeanalizuj raport Audit i instrukcję dołączoną do ZIP.

SHA256 archiwum: `071d6670436e3588588e4561a338c667e66d510e13da03157bcc9c553bf5c62d`.

Bez CI / GitHub Actions. Instalacja i testy odbywają się lokalnie, a GitHub służy tylko do przechowywania wersji.
