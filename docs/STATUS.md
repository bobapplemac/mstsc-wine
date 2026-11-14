# Project status

_Last updated: 2026-11-14_

## Current milestone: M2 (genuine MSTSC launch): dialog renders with images and genuine fonts

| Milestone | State |
|---|---|
| M0 research inventory | **done**: binaries inspected and hashed, dependency closure analysed, required satellites identified |
| M1 build foundation | **done**: pinned Wine 11.0 builds from source, both unmodified and patched; launcher; isolated prefix; benign PE runs |
| M2 genuine MSTSC launch | **in progress**: genuine dialog renders with images and fonts (patches 0001–0009); mstscax registers and instantiates; Connect resolves the target and reports unreachable hosts the way Windows does |
| M3–M8 | not started; M3 also needs a Windows RDP test endpoint |

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
1. M3: the operator is setting up the endpoint (checklist: `docs/test-endpoint.md`). Next is TLS/CredSSP,
   logon and graphics. The local error paths (refused, hang-up after X.224) already match Windows (EXP-019/020).
2. (done) local error-path checks.
3. Investigate the truncated "Show Options" label (text metrics or DPI).
4. Packaging: Wine Mono is not needed (R-012); keep `mscoree=d`. Decide on bundling wine-gecko offline only if Help/HTML is in scope.
5. Import-gap backlog (R-006).
