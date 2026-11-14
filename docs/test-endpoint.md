# RDP test endpoint (M3+)

A disposable Windows machine you control. Never use a production or shared server.

## Machine
- Windows Server 2022 (best match for the client build), Windows 10/11 Pro, or Enterprise. A local VM is fine.
- Remote Desktop enabled (Settings → System → Remote Desktop). Leave **Network Level
  Authentication on**: CredSSP is part of what we must test.
- Reachable from this Linux host on TCP 3389. Firewall rule "Remote Desktop – User Mode (TCP-In)" enabled.
- Audio: enable "Windows Audio" service (default on client SKUs; on Server enable it).
- Optional later: a shared folder / printer are *not* needed for Phase 1.

## Account
- A local, non-admin test user in the "Remote Desktop Users" group, with a throwaway password.
- Type the credentials yourself in the credential prompt (Wine's dialog, ADR-0016). Never put them in
  files, environment variables, commands, chat or logs.

## Certificate
- The default self-signed RDP certificate is fine. mstsc will show its genuine
  certificate warning. Inspect the thumbprint against the server (`certlm.msc` → Remote
  Desktop) and accept it interactively. That is normal certificate verification, not
  disabling it. Never set `authentication level:i:0` or similar shortcuts.

## Telling the project about it
- Host name or IP: type it into the mstsc dialog. If a script needs it, export it at run
  time only, e.g. `MSTSC_WINE_TEST_HOST`. Never commit it; docs and logs use `<test-host>`.
