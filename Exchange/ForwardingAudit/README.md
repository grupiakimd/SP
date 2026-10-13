# Exchange Server SE: forwarding audit

Independent tool, unrelated to the SharePoint versions in this repository.

## Scope

Scans only UserMailbox and SharedMailbox in exactly five allowlisted mailbox databases. Audits administrative mailbox forwarding (ForwardingAddress and ForwardingSmtpAddress, plus DeliverToMailboxAndForward) and Outlook/OWA Inbox Rules (ForwardTo, RedirectTo, ForwardAsAttachmentTo), including hidden and disabled rules. No Transport Rules. No message content. Output tables show **only detected forwarding**.

## Installation

1. Copy this folder onto a secured Exchange SE server (Windows PowerShell 5.1 and Exchange Management Tools).
2. Copy config.example.json to config.json locally and replace ALL FIVE database placeholders with actual mailbox database names. The script deliberately fails when placeholders remain.
3. Run as an Exchange RBAC account authorized to read mailboxes and Inbox Rules. Test from Exchange Management Shell first.
4. Example: powershell.exe -NoProfile -File "C:\ExchangeAudit\Audit-ExchangeForwarding.ps1"
5. To register a daily task at 06:00, run elevated Windows PowerShell: .\Register-ScheduledTask.ps1 -ScriptDirectory C:\ExchangeAudit -At 06:00 -User 'DOMAIN\svc-exchange-audit'

Scheduled execution bootstraps RemoteExchange.ps1 / Connect-ExchangeServer -Auto if Exchange cmdlets are unavailable. It prompts for task-account credentials at registration; credentials are not kept in code or config. The service account still needs appropriate Exchange rights and network/authentication access.

## Reports

Saved locally under Reports (or configured OutputDirectory):
- Forwarding_timestamp.html: browser-filterable table, only positive findings
- Forwarding_timestamp.csv: matching table, UTF-8, semicolon separator
- Summary_timestamp.json: scanned/forwarding/error counts and COMPLETE vs PARTIAL
- Errors_timestamp.csv: only on read failures, outside the main report

Exit code 0 means scan completed, 2 means incomplete (check diagnostics), nonzero exceptions indicate startup failure. Do not treat a partial or failed audit as showing no forwarding.

## Limits and safety

Get-InboxRule covers Exchange-visible Inbox Rules; client-only Outlook behavior or nonstandard MAPI changes may not be fully represented. Descriptions show conditions/exceptions, but script does not evaluate them or confirm message delivery. Targets are resolved to primary SMTP when feasible; otherwise the raw Exchange identifier remains. Keep output restricted to administrators: email addresses, redirect targets and rule descriptions are sensitive. **Never commit reports or real config.json to this public repository.** No Exchange modifications are performed.


## Test mode: four specific mailboxes

The updated config.example.json defaults to Mode=Test and contains four TestMailboxes placeholders. Create your **local** config.json and replace the placeholder mailbox addresses with actual identities, and list their allowed Exchange databases in Databases. Unlike Full, Test does not require five configured databases; the specified mailboxes must belong to one of those allowed databases. A mailbox outside the allowlist or a missing mailbox is recorded as a **PARTIAL** audit error, never silently included.

Run the configured test set:

    powershell.exe -NoProfile -File C:\ExchangeAudit\Audit-ExchangeForwarding.ps1

Override test selection directly from PowerShell (while Mode=Test):

    .\Audit-ExchangeForwarding.ps1 -Mailboxes 'user1@company.pl','shared1@company.pl','user2@company.pl','shared2@company.pl'

For a full scan, change Mode to Full and provide exactly five valid databases. Full ignores TestMailboxes in config. Do not switch to Full until test findings are reviewed.

## SMTP report delivery

Set Email.Enabled=true and configure Host, Port, From, To, CredentialFile, UseStartTls=true in your local config.json. This implementation uses Windows PowerShell 5.1 System.Net.Mail.SmtpClient with authenticated **STARTTLS**, conventionally TCP 587; it does **not** support implicit TLS on port 465. Verify that your SMTP server accepts AUTH LOGIN/PLAIN (or another supported authentication method) and allows sending as configured From. Certificates must validate; this tool does not disable verification. Some servers that only accept OAuth cannot use this method.

Under the **same Windows identity on the same machine** that will run the Task Scheduler job, run:

    .\Set-SmtpCredential.ps1

This prompts for SMTP login/password and writes a Windows DPAPI-protected smtp-credential.xml. Protect that file with NTFS ACLs. It is not portable to another Windows account or computer. If using a service account for the task, provision the credential while logged in as that account. Do not publish real addresses, credentials, config or reports.

The email contains the HTML report, CSV findings, JSON summary and (on a partial audit) CSV error diagnostics. SMTP send failure returns exit code 3. Reports remain saved locally even if sending fails. SMTP is optional; disabled by default. Review the SMTP server logs and actual receipt during initial verification.

### Important operational note

A test is still a live read-only interrogation of real Exchange configuration, but it does not modify mailboxes. Neither this version nor scheduled email have been validated against your Exchange SE deployment.
