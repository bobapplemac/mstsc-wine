# Compatibility log

Host for all entries unless noted: LMDE 7 (Debian 13 base), kernel 6.12.116, Cinnamon
on **X11** (spec secondary environment); GUI tests in nested `Xephyr :5` 1280x800.
Client: mstsc.exe / mstscax.dll **10.0.20348.5866** (Server 2022), SHA-256 in RESEARCH R-001.

| ID | Date | Runtime | Experiment | Result |
|---|---|---|---|---|
| EXP-001 | 2026-11-13 | WineHQ 11.0 binaries | `mstsc-wine run` (no args), fresh prefix, Windows version default (win10) | mstsc.exe loads (native) and shows only *"File not found. C:\windows\system32\<LANG_NAME>\mstsc.exe.MUI"*. No `.mui` file is opened. **Blocked: missing MUI satellite + no Wine MUI loader** |
| EXP-002 | 2026-11-13 | WineHQ 11.0 | Same with `AppDefaults\mstsc.exe\Version=winxp64` + `+file` | mstsc probes `system32\en-US\`, `system32\en\`, `system32\mstsc.exe.mui` itself. Same error (file absent) |
| EXP-003 | 2026-11-13 | WineHQ 11.0 | `regsvr32 mstscax.dll` | Load fails: `Library DEVOBJ.dll ... not found` |
| EXP-004 | 2026-11-13 | source 11.0 + patches 0001-0002 | `regsvr32 mstscax.dll` | mstscax **loads**. DllRegisterServer registers the WTS proxy/stubs (`NdrDllRegisterProxy` ok), then needs `REGISTRY` #101, which lives in the satellite. The loader tries `en-US\mstscax.dll.mui` and `en\mstscax.dll.mui` (absent) and "Failed to register DLL". **Blocked on mstscax.dll.mui** |
| EXP-005 | 2026-11-13 | source 11.0 + patches | `mstsc-wine run` | Loader now searches `en-US\mstsc.exe.mui`. Same error until the satellite is supplied |
| EXP-006 | 2026-11-13 | source 11.0 (unmodified) and patched | `tests/run-regression.sh` | Baseline: MUI fixture FAIL, devobj absent (both expected). Patched: all pass |

## Reproducible tests

| Test | Command | Covers |
|---|---|---|
| Patch regression A/B | `tests/run-regression.sh build/install-wine-11.0 baseline` / `... build/install-wine-patched patched` | patches 0001, 0002 |
| MUI fixture | `tests/static/mui-fixture/build.sh OUT` then `wine OUT/muitest.exe` | LN exe + satellite, Unicode string, checksum rejection |
| devobj conformance | `wine build/wine-patched/dlls/devobj/tests/x86_64-windows/devobj_test.exe devobj` | DevObj create/GetClassDevs/enum/destroy |
| Launcher isolation | `tests/launch/test-launcher-isolation.sh` | F-013, N-003 |
| mstscax probe (needs registration) | `wine cscript //nologo tests/launch/probe-mstscax.js` | ProgID activation, `Version` |

## Phase 1 acceptance status (T-001…T-021)

None pass yet. T-001 is blocked by the missing MUI satellites (operator input).
T-002 onward also need a Windows RDP test endpoint, which hasn't been provided.
