# SharePoint SE — instalacja lokalna

Środowisko: `SPSEAPP1`, `SPSEAPP2`, `SPSEWFE1`, `SPSEWFE2`; SQL `SPSEDB:1433`.

## Ważna poprawka 28.10.2026

**Archiwum `SPSE_Automation_v03_Local.zip` zawiera błąd audytu!** W Windows PowerShell 5.1 przy `Set-StrictMode -Version Latest` może pojawić się komunikat `The property 'Count' cannot be found on this object`. Nie używaj tego archiwum bez poprawki.

- [Poprawka kodu do wersji v0.3.1](FIX-v0.3.1.patch) — usuwa błąd `.PSObject.Properties.Count` i zabezpiecza dwa opcjonalne odczyty rejestru.
- Pełne poprawione archiwum **SPSE_Automation_v03_1_Local.zip** zostało przekazane w rozmowie ChatGPT 28.10.2026. W repozytorium na razie przechowywana jest oryginalna wersja v0.3 i poprawka w pliku `.patch`.

## Zasady bezpieczeństwa

- Skrypty działają tylko **lokalnie**, na serwerze o nazwie przypisanej do pliku uruchomieniowego.
- Bez PowerShell Remoting, kopiowania plików przez sieć i centralnego wykonania.
- Domyślna czynność `Audit` nie instaluje funkcji Windows ani SharePoint.
- Nośniki ISO, klucz licencyjny, hasła i raporty infrastruktury nie trafiają do publicznego repozytorium.
- Instalację i testy wykonuje operator na jednej VM naraz; bez CI na GitHubie.

## Uruchomienie audytu

Po pobraniu **poprawionej wersji v0.3.1** i rozpakowaniu jej na `SPSEAPP1`:

```powershell
cd C:\temp\SPSE_Automation_v03_1_Local\spse-automation
.\SPSEAPP1.ps1 -Step Audit
```

Jeżeli system blokuje niepodpisane skrypty pobrane z Internetu, po zweryfikowaniu źródła można usunąć znacznik pobrania z konkretnych plików przez `Get-ChildItem -Filter *.ps1 | Unblock-File`. Nie zmieniaj systemowo Execution Policy.

Raport: lokalny `reports\LocalAudit.html`. Nie uruchamiaj kolejnych etapów bez jego oceny.

Więcej informacji: pełne `README.md` znajduje się w archiwum ZIP.
