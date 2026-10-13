# SP — SharePoint 2019 → SE / v2.2

Wersja **v2.2** rozwija v2.1 o **oddzielny, pseudonimizowany raport Markdown**, nadający się do kontrolowanego przekazania innej osobie w celu analizy migracyjnej.

## Tryb prywatny i udostępniany

- `FullInventory.json`, CSV i `SPSE_Readiness_Report.html` są **poufne**: zawierają rzeczywiste dane farmy i zostają lokalnie.
- `SP_Audit_SHAREABLE_YYYYMMDD_HHMMSS.md` jest generowany **osobno** i zawiera tylko jawnie dozwolone pola, dane liczbowe oraz aliasy.
- Aliasowanie działa w ramach jednego raportu, np. `SERVER-001`, `DB-001`, `WEBAPP-001`. Nie powstaje mapa aliasów do nazw oryginalnych.
- Dane nie są wysyłane do internetu. To **pseudonimizacja, nie pełna anonimowość**: rozmiary, wersje, liczby i charakter problemów również mogą być poufne.

## 1. Wygeneruj MD z istniejącego audytu — bez ponownego skanowania

W Windows PowerShell 5.1:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
& "C:\Scripts\SP\v2.2\New-SPSEShareableAudit.ps1" -InputPath "C:\SP_Audit"
```

`InputPath` może wskazywać konkretny folder przebiegu, katalog nadrzędny albo istniejący JSON/CSV.
Domyślny wynik trafia **obok** katalogu wybranego przebiegu audytu.

Możesz wskazać własny plik wyjściowy:

```powershell
& "C:\Scripts\SP\v2.2\New-SPSEShareableAudit.ps1" `
  -InputPath "C:\SP_Audit" `
  -OutputPath "C:\SP_Share\Audit_for_review.md"
```

Jeśli brakuje `FullInventory.json`, generator próbuje odzyskać dane z CSV i wyraźnie oznacza niekompletność.

## 2. Przy nowym audycie

Przenieś razem do jednego katalogu cztery pliki z `v2.2/`:
`Invoke-SP2019ReadinessAudit.ps1`, `New-SPSEDashboard.ps1`,
`New-SPSEShareableAudit.ps1`, `dashboard_template.html`.

```powershell
& "C:\Scripts\SP\v2.2\Invoke-SP2019ReadinessAudit.ps1" `
  -OutputRoot "C:\SP_Audit" -ShareableReport
```

`-ShareableReport` jest **opcjonalny**. Zapisuje plik MD osobno od archiwum z surowymi wynikami.

## Co jest w raporcie?

- Wersje SharePoint i SQL; role serwerów, RAM, vCPU, dyski.
- Web Applications, bazy SharePoint i SQL, relacje między nimi.
- Site Collections, szablony i rozmiary, bez URL i danych właścicieli.
- Backupy SQL, stan baz, WSP, Search, Workflow i kody ryzyk migracji.
- Liczniki pozostałych sekcji oraz oznaczenia braków audytu.

**Celowo pomijane:** dane kont, domeny, FQDN/IP, URL, teksty Health Analyzer, tytuły witryn, nazwy WSP i baz, identyfikatory GUID, certyfikaty, ścieżki i surowe komunikaty błędów. Każde nowo dodane pole kolektora jest domyślnie blokowane, dopóki ktoś świadomie nie rozszerzy listy dozwolonych pól.

## Test

Na środowisku testowym bez SharePoint można wykonać:

```powershell
& ".\tests\Test-ShareableAudit.ps1"
```

Test korzysta z **fikcyjnego** inwentarza i szuka charakterystycznych sekretów, nazw, adresów i loginów w wyniku. Test nie jest formalnym potwierdzeniem pełnej anonimowości.

**Przed udostępnieniem przeczytaj cały plik MD**, a jeśli zawiera informacje dotyczące organizacji, zastosuj jej zasady klasyfikacji i akceptacji udostępniania. Nie umieszczaj produkcyjnych audytów ani nawet pseudonimizowanych raportów w repozytorium publicznym.
