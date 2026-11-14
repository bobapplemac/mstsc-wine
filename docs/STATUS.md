# Project status

_Last updated: 2026-11-13_

## Current milestone: M1 complete → M2 (genuine MSTSC launch) blocked on operator input

| Milestone | State |
|---|---|
| M0 research inventory | **done**: binaries inspected and hashed, dependency closure analysed, required satellites identified |
| M1 build foundation | **done**: pinned Wine 11.0 builds from source, both unmodified and patched; launcher; isolated prefix; benign PE runs |
| M2 genuine MSTSC launch | **blocked**: needs `en-US\mstsc.exe.mui`, `en-US\mstscax.dll.mui` (operator) |
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
1. **MUI satellites** from the same Server 2022 build: `C:\Windows\System32\en-US\mstsc.exe.mui`
   and `en-US\mstscax.dll.mui` (required). Also `dui70.dll` and `duser.dll`, plus their
   `en-US` `.mui` files if present (recommended). See `docs/binary-acquisition.md`.
2. **RDP test endpoint** for M3+: a disposable Windows 10/11 or Server host and a test
   account, supplied by the operator. Never production.
3. Primary target environment (KDE Plasma Wayland, 125%) is not this machine. Acceptance on
   it must happen on that machine later.

## Next actions (once satellites arrive)
1. `mstsc-wine import <folder> && mstsc-wine init`, then check that patch 0002 accepts the real
   satellites (checksum assumption, ADR-0005 open question a).
2. `regsvr32 mstscax.dll`, then `cscript tests/launch/probe-mstscax.js`.
3. Launch mstsc and record the first failure. Then work through the import-gap backlog
   (RESEARCH R-006) in the order it is actually hit: `__C_specific_handler_noexcept`,
   shlwapi #628, Cred* stubs, DirectUI.
4. Install the optional build deps (Wayland, D-Bus, GStreamer) for later milestones.
