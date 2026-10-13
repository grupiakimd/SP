# Exchange Server SE: forwarding audit

Independent tool, unrelated to the SharePoint versions in this repository.

## Scope

Scans only UserMailbox and SharedMailbox in exactly five allowlisted mailbox databases. Audits administrative mailbox forwarding (ForwardingAddress and ForwardingSmtpAddress, plus DeliverToMailboxAndForward) and Outlook/OWA Inbox Rules (ForwardTo, RedirectTo, ForwardAsAttachmentTo), including hidden and disabled rules. No Transport Rules. No message content. Output tables show **only detected forwarding**.

## Installation

1. Copy this folder to a secured **domain-joined Windows server** with Windows PowerShell 5.1. Exchange management tools are **not required**; the script imports a Kerberos-authenticated remote Exchange PowerShell session.
2. Copy config.example.json to config.json locally and replace ALL FIVE database placeholders with actual mailbox database names. The script deliberately fails when placeholders remain.
3. Run as an Exchange RBAC account authorized to read mailboxes and Inbox Rules. Test from Exchange Management Shell first.
4. Example: powershell.exe -NoProfile -File "C:\ExchangeAudit\Audit-ExchangeForwarding.ps1"
5. To register a daily task at 06:00, run elevated Windows PowerShell: .\Register-ScheduledTask.ps1 -ScriptDirectory C:\ExchangeAudit -At 06:00 -User 'DOMAIN\svc-exchange-audit'

Scheduled execution connects to `http://<ExchangeServer>/PowerShell/` using `New-PSSession -ConfigurationName Microsoft.Exchange -Authentication Kerberos` and imports cmdlets. Set `ExchangeServer` to the Exchange server FQDN in config.json. This is a separate connection from SMTP TCP/587. The Microsoft-supported Kerberos endpoint uses HTTP with Kerberos payload encryption; do not enable Basic or TrustedHosts to make it work. It prompts for task-account credentials at registration; credentials are not kept in code or config. The scheduled-task domain account needs Exchange RBAC permissions, WinRM client/remote PowerShell prerequisites, Kerberos and DNS connectivity, and access to the Exchange PowerShell virtual directory (typically TCP/80). Do not confuse this port with SMTP submission on TCP/587.

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

## Running from a separate Windows server

- Set `ExchangeServer` in config.json to the Exchange FQDN (not an HTTP URL), and run under a domain account authorized for Exchange remote PowerShell and mailbox rules.
- Keep Mode=Test until the four selected mailboxes are checked. Test and Full both require their targets to belong to the allowed Databases.
- For scheduled execution the same Windows identity must have previously created `smtp-credential.xml` on this *execution host* using `Set-SmtpCredential.ps1`. That credential is for SMTP only, not the Exchange Kerberos session.
- The host must reach Exchange Remote PowerShell (commonly TCP 80 to /PowerShell/) and SMTP submission TCP 587. Confirm SMTP STARTTLS + SMTP AUTH actually work for the account; port accessibility alone is not proof.
- A remote Exchange session is removed after successful normal execution. On fatal termination, PowerShell cleans up at process end.

## Manual audit without email

Even if Email.Enabled=true in config.json, override delivery for one run:

    .\Audit-ExchangeForwarding.ps1 -NoEmail -OpenReport

`-NoEmail` skips SMTP; `-OpenReport` opens the locally generated HTML in the default browser (use interactively, not in unattended Scheduled Tasks). Without `-OpenReport`, files are still saved locally. Scheduled Tasks use the config default unless explicitly supplied `-NoEmail`.
