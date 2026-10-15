# SP v2.4 — Workflow Diagnostics

**Oddzielny zestaw diagnostyczny**, bez zmian w v2.3.1. Służy do ustalenia, dlaczego w SharePoint 2019 nie uruchamiają się workflow albo nie dochodzą powiadomienia po dodaniu elementu listy.

## Co bada

- Mechanizm SharePoint 2010: powiązania SPWorkflowAssociation, Enabled, AutoStartCreate, AutoStartChange, AllowManual i instancje wskazanego elementu.
- Mechanizm 2013: osobny Workflow Subscription Service przez CSOM, Enabled i EventTypes oraz opcjonalnie instancje elementu. **Nie należy utożsamiać ich z 2010**.
- Proxy i adres Workflow Manager, działanie SPTimerV4, zadania Timer Job zawierające słowa workflow lub alert.
- Ustawienia SMTP aplikacji WWW (czy są skonfigurowane — bez udostępniania hosta w MD).
- Raport lokalny JSON z pełnymi danymi i osobny, pseudonimizowany Markdown.

## Uruchomienie offline

Pobierz repo przez GitHub → Code → Download ZIP. Na serwerze APP SharePoint 2019 w Windows PowerShell 5.1 (x64), jako administrator z uprawnieniami SharePoint Shell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force

& "C:\temp\SP-main\v2.4\Invoke-SPWorkflowDiagnostic.ps1" `
  -WebUrl "https://ADRES_WITRYNY" `
  -ListTitle "NAZWA_LISTY" `
  -OutputRoot "C:\SP_Workflow_Diagnostic"
```

Wskazując **konkretny ID elementu**, na którym proces/notification nie zadziałał, otrzymasz dodatkowo odczyt instancji:

```powershell
& "C:\temp\SP-main\v2.4\Invoke-SPWorkflowDiagnostic.ps1" `
  -WebUrl "https://ADRES_WITRYNY" `
  -ListTitle "NAZWA_LISTY" `
  -ItemId 123 `
  -OutputRoot "C:\SP_Workflow_Diagnostic"
```

**Żadne elementy ani workflow nie są tworzone, uruchamiane, wznawiane, wyłączane czy zmieniane.** Skrypt nie wysyła testowego e-maila.

Wyniki w katalogu `Workflow_YYYYMMDD_HHMMSS`:
- `WorkflowDiagnostic_PRIVATE.json` — poufny, zawiera adresy, nazwy procesów, identyfikatory i lokalne komunikaty błędów.
- `WorkflowDiagnostic_SHAREABLE.md` — tylko liczby, flagi i dozwolone kategorie błędów. **Przejrzyj przed udostępnieniem.**

## Jak interpretować

| Wynik | Znaczenie |
|---|---|
| Legacy Enabled=YES + AutoStartCreate=NO | Proces nie został skonfigurowany do startu po dodaniu elementu. |
| Legacy Enabled=YES + AutoStartCreate=YES | Powinien startować; sprawdź konkretne instancje i ULS. |
| Workflow2013=FAILED | **Nie oznacza braku procesów 2013**; sprawdź workflow proxy, endpoint, certyfikaty, OAuth i dostęp do CSOM. |
| Workflow2013=OK, Subscriptions=0 | W tej konkretnej liście nie znaleziono subskrypcji 2013; nie oznacza to ich braku w całej farmie. |
| Legacy associations > 0 | Kandydaci do migracji/wycofania, NIE dowód używania procesu ani jego wersji 2013. |
| Alert timer disabled | Możliwe problemy z klasycznymi alertami SharePoint, niezależnie od Workflow Manager. |
| SMTP not configured | Sprawdź konfigurację wysyłki na farmie i overrides dla Web Application. |

## Pozostałe kontrole ręczne

- Czy powiadomienie pochodzi z klasycznego **Alert Me**, czy z akcji **Send Email** wewnątrz workflow? To różne mechanizmy.
- W przypadku procesów 2013 sprawdź wersję i stan osobnej farmy Workflow Manager; proxy w SharePoint nie dowodzi działania całego silnika.
- W Central Administration → Monitoring sprawdź historię i status zadań **Immediate Alerts** oraz SharePoint Timer Service.
- Zapisz godzinę utworzenia testowego elementu, ID i identyfikator korelacji, następnie zbadaj ULS na konkretnym serwerze i SMTP relay po tej godzinie.
- Nie wykonuj teraz `Register-SPWorkflowService -Force`, zmian certyfikatów/OAuth, restartów czy ręcznego uruchamiania wszystkich workflow bez diagnozy.

## Konsekwencje dla nowej farmy SE

SharePoint 2010 workflows są bez wsparcia od 14.07.2026. Workflows 2013 on-prem mogą działać z **SharePoint Workflow Manager**, który Microsoft zaleca uruchamiać na osobnych hostach. Wspierana topologia SPWFM ma 1/3/5 hostów (nie 2/4). Dlatego dopiero po identyfikacji użytkowanych workflow wybierzemy strategię: odtworzenie 2013 na SPWFM lub przebudowa na utrzymywane automatyzacje.

## Ograniczenia

Skrypt działa na jednej liście, nie przegląda całych 31 tys. list. Nie wykonuje testu SMTP ani nie potwierdza dostarczenia e-maila. Zdarzenia 2013 via CSOM zależą od uprawnień, bibliotek klienta i stanu Workflow Manager; niepowodzenie odczytu jest raportowane jako błąd, nie jako zero workflow. Skrypt nie był testowany na rzeczywistej farmie — pierwszy przebieg traktuj jako weryfikacyjny.

Dokumentacja:
- [Microsoft: features deprecated in SE](https://learn.microsoft.com/en-us/sharepoint/what-s-new/what-s-deprecated-or-removed-from-sharepoint-server-subscription-edition)
- [Microsoft: configure SP Workflow Manager](https://learn.microsoft.com/en-us/sharepoint/governance/install-and-configure-workflow-for-sharepoint-server)
- [Microsoft: SharePoint workflow associations](https://learn.microsoft.com/en-us/previous-versions/office/developer/sharepoint-2010/ms442481%28v%3Doffice.14%29)
