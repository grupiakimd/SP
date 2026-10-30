# SPSEAPP2 — uzgodnienie statusu KB5002927 (30.10.2026)

Tylko na SPSEAPP2, tylko Windows PowerShell 5.1 x64 i lokalny administrator.

`Confirm-SPSE-CU.ps1` to bezpieczna poprawka po sytuacji, kiedy instalator KB5002927 zwrócił kod -1, ale Windows Installer zarejestrował poprawne instalacje aktualizacji w SharePoint Core i Language Pack EN/PL, a po restarcie plik Microsoft.SharePoint.dll ma poprawny build.

Najpierw wykonaj WYŁĄCZNIE audyt:

```powershell
cd C:\temp\SPSE_Unattended_v1
Unblock-File .\Confirm-SPSE-CU.ps1
.\Confirm-SPSE-CU.ps1
```

Raport powstanie lokalnie w `C:\ProgramData\SPSE-Unattended\SPSEAPP2\CU-Weryfikacja.html`.

Weryfikacja wymaga: dokładnego build `16.0.20326.20190`, braku zalegającego restartu, prawidłowego lokalnego stanu wcześniejszych etapów, wcześniejszego błędu `-1` i zdarzeń Microsoft Windows Installer **ID 1022** dotyczących KB5002927 dla SharePoint Core, English Language Pack 1033 i Polish Language Pack 1045. **Nie zmienia** SQL, farmy, instalacji ani usług.

Gdy wszystkie warunki spełnione, uruchom świadomie:

```powershell
.\Confirm-SPSE-CU.ps1 -Apply
```

Po potwierdzeniu `POTWIERDZ CU SPSEAPP2` skrypt utworzy kopię `progress.json` i poprawi wyłącznie lokalny znacznik zakończenia `InstallCU` (dodając ślad audytowy), bez ponownej instalacji. Jeżeli warunek nie jest spełniony, nie zmieni stanu.

Na koniec użyj obecnego instalatora v1.1:

```powershell
.\Install-SPSE-Unattended.ps1 -Resume -AcceptLicenseTerms
```

Nie modyfikuj `progress.json` samodzielnie i nie uruchamiaj CU ponownie w ciemno. Końcowe przyłączenie farmy i PSConfig są oddzielnymi etapami, nie wykonywanymi przez ten pakiet.

Bezpieczeństwo: nic nie jest przesyłane do GitHuba z serwera; nie publikuj logów firmowego środowiska w publicznym repozytorium. Skrypt testowany statycznie, bez wykonania na Windows Server 2025.
