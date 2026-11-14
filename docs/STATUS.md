# Project status

_Last updated: 2026-11-14_

## Current milestone: M3 (first connection): **first interactive session achieved** (2026-11-14)

| Milestone | State |
|---|---|
| M0 research inventory | **done**: binaries inspected and hashed, dependency closure analysed, required satellites identified |
| M1 build foundation | **done**: pinned Wine 11.0 builds from source, both unmodified and patched; launcher; isolated prefix; benign PE runs |
| M2 genuine MSTSC launch | **done**: genuine dialog renders with images and fonts (patches 0001–0009); mstscax registers and instantiates; Connect resolves the target and reports unreachable hosts the way Windows does |
| M3 connection | **in progress**: TLS session to a Windows host works (EXP-023); certificate warning verified (EXP-026); **NLA/CredSSP with NTLM works against a real Windows host** (EXP-030/031, ADR-0016–0018) |
| M4–M8 | not started |

## Completed
- Environment inventory: LMDE 7 / Debian 13 base, Cinnamon **X11** (not the KDE/Wayland
  primary target), 8 CPUs, 11 GiB RAM, passwordless sudo since 2026-11-14 (builds stay rootless). Rootless build sysroot (ADR-0001).
- Wine 11.0 (`db11d0fe`) built out-of-tree with no modifications in about 6 min (`tools/build-wine.sh baseline`).
- Patch series (`patches/series`) built and tested (`tools/build-wine.sh patched`):
  - 0001 `devobj`: new builtin; unblocks loading `mstscax.dll` (verified).
  - 0002 `ntdll` MUI satellite loading: fixture passes; engages for mstsc.exe and
    mstscax.dll (verified by trace). Real satellites not yet available to test.
- Tools: `inspect-pe.py` (manifest inspector), `check-imports.py` (imports vs Wine
  exports), `mui-config.py`, `xshot.py`, `build-wine.sh`.
- Launcher `launcher/mstsc-wine`: init/import/run/exec/doctor/--version, hash-verified
  component store, private prefix, redacted deterministic logs.
- Tests: regression A/B suite (incl. CredSSP client), launcher isolation test, server-certificate warning test (`tests/security/cert-prompt/run.sh`), NLA end-to-end (`tests/security/credssp/run.sh`; needs `python3-pyspnego`), fullscreen Restore/Maximize end-to-end (`tests/launch/test-fullscreen-restore.sh`, local RDP server endpoint).
- Fullscreen → windowed: Restore then Maximize works under muffin and metacity (patch 0016, ADR-0019). KDE/XWayland still to test.

## Blockers (need human input)
1. A domain-joined test host (Kerberos) when available. The current host covers NLA with NTLM.
2. The primary target environment (KDE Plasma Wayland, 125%) is not this machine.

## Next actions
1. NLA follow-ups: "Remember my password" (`CredWriteDomainCredentialsW`), Kerberos/domain host, wrong-password re-prompt UX, server with NLA *required*.
2. Certificate prompt with a CA-trusted certificate (expect no prompt, flags `CREDSSP_SERVER_AUTH_CERTIFICATE`).
3. Phase 1 features on the live session: clipboard (text and files), keyboard, audio, fullscreen and windowed, DPI.
4. Packaging: bundle the patched GnuTLS (`tools/build-gnutls.sh`) and `ntlm_auth` dependency; Wine Mono not needed.
