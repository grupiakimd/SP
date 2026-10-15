# SharePoint 2019 - targeted workflow troubleshooting (v1)

This is a separate read-only incident diagnostic, not the farm inventory or migration dashboard.

## Scope
One SPWeb and one list, selected by URL. Reads:
- SharePoint build and workflow security/compatibility settings (including 53601).
- 2010-style workflow associations on the list and its content types.
- 2013-style Workflow Manager subscriptions (CSOM).
- Existing instances on the newest three items, or on a selected item (-ItemId).
- Workflow Manager proxy, local timer service and recent local ULS workflow warnings/errors.

No changes to the farm, web.config, IIS, workflow definitions, item content, SMTP or services. No new list items or test email are sent. Output files are written only to a local folder.

## Run
1. GitHub: Code -> Download ZIP. Copy the Workflow-Troubleshooting/v1 folder onto an APP SharePoint server.
2. Open SharePoint Management Shell (Windows PowerShell 5.1 x64) as an authorized SharePoint administrator.
3. Change the two example URLs below to your real SPWeb URL and the usual list/view URL.

    Set-ExecutionPolicy -Scope Process Bypass -Force
    & 'C:\Temp\SP-main\Workflow-Troubleshooting\v1\Invoke-SPWorkflowTroubleshoot.ps1' -WebUrl 'https://sharepoint/sites/example' -ListUrl 'https://sharepoint/sites/example/Lists/Requests/AllItems.aspx'

If you know the ID of an item where the workflow should have run, add -ItemId 123 -LogHours 6. This is preferred for a focused failure investigation.

## Files
Output defaults to C:\SP_Workflow_Troubleshooting\Run_YYYYMMDD_HHMMSS:
- WorkflowTroubleshoot_PRIVATE.json: sensitive raw URLs, names, instance IDs, ULS details. Keep private.
- WorkflowTroubleshoot_SHAREABLE.md: pseudonymized counts and statuses. Review manually before sharing.

Never commit results to a public GitHub repository.

## Important limitations
- 2013 instances returned by CSOM are not a guaranteed complete history. Zero returned is not proof of zero executions.
- ULS is collected from only the server where the script is run, for the selected lookback period.
- Errors in any section are shown in PRIVATE.json; an unsuccessful check is not equivalent to a zero count.
- Flag 53601 is for Classic Workflow Manager only. Absence does not automatically require remediation.
- The pre-parse security check should not be disabled just to force legacy workflows to run.

Official reference for build 16.0.10417.20198 (KB5002894):
https://support.microsoft.com/en-us/servicing/office/hotfix/sharepoint/5002894

CSOM methods:
https://learn.microsoft.com/en-us/previous-versions/office/sharepoint-csom/dn624352(v=office.15)
https://learn.microsoft.com/en-us/previous-versions/office/sharepoint-csom/dn624289(v=office.15)
