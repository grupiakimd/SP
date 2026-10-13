# SP — SharePoint 2019 → SharePoint Subscription Edition

Zestaw narzędzi **PowerShell 5.1** do inwentaryzacji istniejącej farmy SharePoint Server 2019 przed migracją typu *database attach* do SharePoint Server Subscription Edition (SE).

> **Uwaga:** narzędzie ma charakter diagnostyczny. Wynik audytu ani wskaźnik *readiness* nie stanowią potwierdzenia gotowości do migracji. Skrypty nie były przetestowane na rzeczywistej farmie produkcyjnej. Uruchom najpierw w ograniczonym zakresie i oceń `CollectionErrors.csv`.

## Wersje

| Wersja | Katalog | Zawartość |
|---|---|---|
| **v1.0** | [`v1/`](v1/) | Pierwotny kolektor PowerShell, raporty CSV/JSON, podstawowy HTML. |
| **v2.0** | [`v2/`](v2/) | Pierwszy interaktywny dashboard HTML offline; wersja archiwalna. |
| **v2.1** | [`v2.1/`](v2.1/) | **Zalecana.** Naprawiony eksport HTML, automatyczne wykrywanie przebiegu, odzyskiwanie z CSV, testy offline. |

![Podgląd dashboardu v2](v2/docs/dashboard_preview.png)

Wersje pozostają **oddzielne i nie są nadpisywane**. **Używaj `v2.1`** — `v2` jest pozostawiona jako historia zmian.

## Szybki start — v2.1

Skopiuj trzy pliki z [`v2.1/`](v2.1/) do jednego katalogu na serwerze APP/WFE SharePoint 2019:

- `Invoke-SP2019ReadinessAudit.ps1`
- `New-SPSEDashboard.ps1`
- `dashboard_template.html`

Uruchom **Windows PowerShell 5.1 (x64)** z uprawnieniami do farmy SharePoint (i odpowiednimi prawami odczytu SQL):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "C:\Scripts\SPSEAudit\v2.1\Invoke-SP2019ReadinessAudit.ps1" -OutputRoot "C:\SP_Audit"
```

Następnie otwórz `SPSE_Readiness_Report.html` z katalogu przebiegu. Więcej szczegółów: [`v2.1/README.md`](v2.1/README.md).

**Odtworzenie dashboardu z istniejącego audytu**, bez ponownego skanowania farmy:

```powershell
& "C:\Scripts\SPSEAudit\v2.1\New-SPSEDashboard.ps1" -InputPath "C:\SP_Audit"
```

## Bezpieczeństwo i ograniczenia

- **Nie publikuj wyników audytu** (`FullInventory.json`, CSV, raportów HTML z produkcji, ZIP-ów wynikowych). Mogą zawierać nazwy serwerów, kont, adresy wewnętrzne, ścieżki oraz wpisy diagnostyczne.
- W repozytorium jest tylko **przykładowy, fikcyjny** raport HTML (`v2/PRZYKLAD_DASHBOARD_DEMO.html`).
- Skrypty wykonują odczyt danych farmy i zapisują raporty lokalnie; opcjonalne głębokie skanowanie witryn może obciążyć produkcję.
- SQL, WinRM, WMI/CIM oraz poszczególne komponenty SharePoint wymagają stosownych uprawnień. Brak wyniku nie jest potwierdzeniem braku problemu.
- Przed migracją niezależnie zweryfikuj wspieraną ścieżkę upgrade'u, aktualne wymagania środowiska docelowego, test odtworzenia backupów, niestandardowe rozwiązania oraz procedurę rollback.

## Struktura projektu

```text
SP/
├── README.md
├── CHANGELOG.md
├── .gitignore
├── v1/
│   ├── Invoke-SP2019ReadinessAudit.ps1
│   └── README_START_HERE.txt
└── v2/
    ├── Invoke-SP2019ReadinessAudit.ps1
    ├── New-SPSEDashboard.ps1
    ├── dashboard_template.html
    ├── PRZYKLAD_DASHBOARD_DEMO.html
    ├── README_START_HERE.txt
    └── docs/dashboard_preview.png
└── v2.1/
    ├── Invoke-SP2019ReadinessAudit.ps1
    ├── New-SPSEDashboard.ps1
    ├── dashboard_template.html
    ├── README.md
    └── tests/Test-Dashboard.ps1
```

Repozytorium publiczne nie oznacza automatycznie udzielenia licencji open-source. Licencję można dobrać później, jeśli projekt ma umożliwiać dalsze wykorzystanie przez innych.
