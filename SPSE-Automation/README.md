# SPSE Automation v0.3.4 — LOCAL ONLY

Automatyzacja instalacji SharePoint Server Subscription Edition na czterech serwerach Windows Server 2025:
- `SPSEAPP1`, `SPSEAPP2` — Application with Search
- `SPSEWFE1`, `SPSEWFE2` — Web Front End with Distributed Cache
- istniejący SQL Server `SPSEDB:1433`

**[Pobierz najnowszą paczkę v0.3.4 (ZIP)](SPSE_Automation_v03_4_Local.zip)** · **[Źródła PowerShell](spse-automation/)** · **[Pełna instrukcja](spse-automation/README.md)**

## Poprawka v0.3.4 (28 października 2026 r.)

Po podaniu lokalnego obrazu ISO etap `Prerequisites` w v0.3.3 zgłaszał błąd `The property 'Parent' cannot be found on this object`.

W `Common.ps1`, funkcja `Assert-SPSELocalPath`, poprawiono przechodzenie po ścieżce:
- dla `FileInfo` pobierany jest nadrzędny katalog przez `Directory`;
- dla `DirectoryInfo` pobierany jest `Parent`;
- plik i wszystkie katalogi nadrzędne nadal są sprawdzane pod kątem reparse points (linków/junction);
- pozostała walidacja tylko lokalnych dysków stałych oraz jawne potwierdzenie instalacji.

To **poprawka walidacji ścieżek**, bez zmian w konfiguracji SQL, farmy, SharePoint oraz funkcji Windows. Archiwum i zgodność plików sprawdzono statycznie; działania Windows PowerShell na Windows Server 2025 wymagają lokalnego sprawdzenia.

## Uruchomienie na SPSEAPP1

Pobierz i rozpakuj nowe ZIP na lokalny dysk, a następnie w Windows PowerShell 5.1 x64:

```powershell
cd C:\temp\spse-automation
.\SPSEAPP1.ps1 -Step Prerequisites
```

Wprowadź pełną ścieżkę do angielskiego ISO SharePoint SE (np. `C:\install\SE\OfficeServer.iso`). Poczekaj na wynik walidacji; instalator ruszy dopiero po ręcznym wpisaniu `PREREQ SPSEAPP1`. Po jego zakończeniu prześlij wynik przed przejściem dalej.

**Nie uruchamiaj `CreateFarm` ani `JoinFarm`.**

## Bezpieczeństwo

- Instalacja lokalna, jedna maszyna naraz; blokada nazwy docelowej VM.
- Bez PowerShell Remoting, centralnego kopiowania, automatycznych restartów i CI.
- Nie publikujemy kluczy produktów, haseł, obrazów ISO ani raportów z infrastruktury.
- Zdalne modyfikacje baz możliwe dopiero w ręcznie zatwierdzonych etapach tworzenia/dołączania farmy.

SHA256 archiwum: `11634cfdf8106a2839c4dc19332ccdfd050b4904fed2288235e32c65157069c6`
