# Project status

_Last updated: 2026-11-14_

## Current milestone: M3 (first connection): **first interactive session achieved** (2026-11-14)

| Milestone | State |
|---|---|
| M0 research inventory | **done**: binaries inspected and hashed, dependency closure analysed, required satellites identified |
| M1 build foundation | **done**: pinned Wine 11.0 builds from source, both unmodified and patched; launcher; isolated prefix; benign PE runs |
| M2 genuine MSTSC launch | **done**: genuine dialog renders with images and fonts (patches 0001–0009); mstscax registers and instantiates; Connect resolves the target and reports unreachable hosts the way Windows does |
| M3 connection | **in progress**: TLS session to a Windows host works (EXP-023); NLA/CredSSP, certificate prompt, NTLM pending |
| M4–M8 | not started |

## Completed
- Environment inventory: LMDE 7 / Debian 13 base, Cinnamon **X11** (not the KDE/Wayland
  primary target), 8 CPUs, 11 GiB RAM, no sudo. Rootless build sysroot (ADR-0001).
- Wine 11.0 (`db11d0fe`) built out-of-tree with no modifications in about 6 min (`tools/build-wine.sh baseline`).
- Patch series (`patches/series`) built and tested (`tools/build-wine.sh patched`):
  - 0001 `devobj`: new builtin; unblocks loading `mstscax.dll` (verified).
  - 0002 `ntdll` MUI satellite loading: fixture passes; engages for mstsc.exe and
    mstscax.dll (verified by trace). Real satellites not yet available to test.
- Tools: `inspect-pe.py` (manifest inspector), `check-imports.py` (imports vs Wine
  exports), `mui-config.py`, `xshot.py`, `build-wine.sh`.
- Launcher `launcher/mstsc-wine`: init/import/run/exec/doctor/--version, hash-verified
  component store, private prefix, redacted deterministic logs.
- Tests: regression A/B suite, launcher isolation test (all green).

## Blockers (need human input)
1. **RDP test endpoint** for M3+: a disposable Windows host and a test account. Never production.
2. The primary target environment (KDE Plasma Wayland, 125%) is not this machine.

## Next actions
1. CredSSP/NLA in Wine ([MS-CSSP] over Schannel + NTLM via `ntlm_auth`); test with NLA enforced on the server.
2. Certificate prompt: untrusted certificate (expect genuine prompt, accept or reject), valid certificate (no prompt).
3. Connection-bar restore/maximize leaves the window unusable (EXP-024): reproduce under a real WM.
4. Phase 1 features on the live session: clipboard (text and files), keyboard, audio, fullscreen and windowed, DPI.
5. Packaging: bundle the patched GnuTLS (`tools/build-gnutls.sh`) and `ntlm_auth` dependency; Wine Mono not needed.
6. Disk: the build host is near full (about 2.5 GB free); prune `build/wine-11.0` objects if space is needed.
