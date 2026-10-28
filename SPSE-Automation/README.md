# SPSE Automation v0.3.1 — LOCAL ONLY

Kompletny pakiet instalacyjny SharePoint Server Subscription Edition dla czterech serwerów Windows Server 2025:

- SPSEAPP1, SPSEAPP2 — Application with Search
- SPSEWFE1, SPSEWFE2 — Web Front End with Distributed Cache
- SQL Server (już zainstalowany): SPSEDB, instancja domyślna TCP 1433

**[Pobierz pełną wersję v0.3.1 (ZIP)](SPSE_Automation_v03_1_Local.zip)**  
**[Instrukcja wykonywania i opis kroków](spse-automation/README.md)**

W katalogu [spse-automation](spse-automation/) opublikowane są wszystkie 9 plików źródłowych z archiwum, z identyczną zawartością.

## Zasady bezpieczeństwa

Każdy skrypt działa wyłącznie lokalnie na serwerze o zgodnej nazwie. Nie ma zdalnego kopiowania ISO, wykonywania poleceń PowerShell Remoting ani automatycznej instalacji na innych VM. Pliki instalacyjne kopiujesz ręcznie.

Domyślnie uruchamiaj tylko `Audit`. Instalacja funkcji Windows, SQL Alias, SharePoint, aktualizacji i utworzenie/dołączenie do farmy są osobnymi etapami z jawnym potwierdzeniem. Etapy tworzenia/dołączania farmy oddziałują na serwer SQL SPSEDB, mimo że wykonywane są lokalnie.

Nie publikuj w tym publicznym repozytorium kluczy, haseł, plików ISO ani raportów z infrastruktury.

## Pierwsze uruchomienie

Na **SPSEAPP1** rozpakuj paczkę i otwórz Windows PowerShell 5.1 x64 jako administrator:

```powershell
cd C:\temp\SPSE_Automation_v03_1_Local\spse-automation
.\SPSEAPP1.ps1 -Step Audit
```

Raport HTML: `reports\LocalAudit.html` (lokalnie). Do momentu analizy wyniku nie uruchamiaj instalacji.

Pakiet v0.3.1 poprawia błąd `The property 'Count' cannot be found` oraz kontrolę brakujących wartości w rejestrze przy `StrictMode`. Nie był jeszcze uruchamiany na Windows Server 2025 — wymaga lokalnej weryfikacji przed wykonaniem zmian.

SHA256 archiwum: `8f7f0aa00f95bba7606313b35775e83b05a600480dd2bd3adf13647c4b6b609b`.

Bez CI i GitHub Actions; GitHub pełni jedynie rolę repozytorium kodu.
