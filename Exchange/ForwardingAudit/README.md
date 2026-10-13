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
