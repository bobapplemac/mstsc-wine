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
| EXP-007 | 2026-11-14 | source 11.0 + patches 0001-0002 | Real satellites imported; `regsvr32 mstscax.dll` | Satellite not mapped: i386 image gives informational status → rejected. **Fixed in 0002** (fixture `i386/`). After the fix the satellite loads, but `REGISTRY` #101 is in neither mstscax.dll nor the satellite, so DllRegisterServer still fails (exit 5). See R-009 |
| EXP-008 | 2026-11-14 | + 0002 fix | `mstsc-wine run` | Aborts: unimplemented `user32.dll.2598` (DPI helper). **Patch 0003** |
| EXP-009 | 2026-11-14 | + 0003 | `mstsc-wine run` | Page fault in windowscodecs: NULL stream from unresolved `SHLWAPI.628`. **Patch 0004** |
| EXP-010 | 2026-11-14 | + 0004 | `mstsc-wine run` (Xephyr :5) | **Genuine connection dialog renders**: Computer combo with placeholder text, User, Connect/Help, en-US strings from satellite. Missing banner and "Show Options" chevron (`IMAGE` #690/#675/#676 not found: likely `SystemResources\mstsc.exe.mun`, H). Wrong fonts (Segoe UI, MS Shell Dlg absent) |
| EXP-011 | 2026-11-14 | + 0005, genuine fonts | `mstsc-wine run` (Xephyr :5) | `.mun` loaded (trace). **Banner image, Segoe UI title, monitor icon and Show Options chevron render**. Genuine fonts are used. "Show Options" label is truncated |
| EXP-012 | 2026-11-14 | + 0005 | `regsvr32 /s mstscax.dll` | **exit 0**; MsTscAx CLSIDs/ProgIDs registered (REGISTRY from `.mun`) |
| EXP-013 | 2026-11-14 | + 0005 | `cscript probe-mstscax.js` | `MsTscAx.MsTscAx.2` created, `Version=10.0.20348`. MsTscAx.MsTscAx, .11 and MsRdpClient fail 0x800a01ad |
| EXP-014 | 2026-11-14 | + 0005 | `mstsc-wine run /v:rdp-test.invalid` | Aborts: unimplemented `sspicli.SspiPrepareForCredRead`. **Patch 0006** |
| EXP-015 | 2026-11-14 | + 0006 | same | Connection attempt runs; mstscax loads d2d1/wined3d/audio/crypt32. Ends in **"An internal error has occurred", error code 0xa08**. Windows would report a name-lookup failure. Trace shows name resolution through `WSALookupServiceBeginW`/`NextW`, which are stubs in Wine (R-015). Expanded "See details" area repaints badly in Xephyr without a WM |
| EXP-016 | 2026-11-14 | + 0007 (NLA) | `/v:rdp-test.invalid` | NLA enumeration succeeds; still 0xa08. Also observed: `CredReadW` type 6 rejected → **patch 0008**; still 0xa08 |
| EXP-017 | 2026-11-14 | + 0008 | winedbg breakpoints on the 7 `0xa08` sites; relay trace | Hit mstscax+0x102e43 after an internal call returned E_NOTIMPL. Source: msxml3 attribute `put_nodeTypedValue` stub → **patch 0009** |
| EXP-018 | 2026-11-14 | + 0009 | `/v:rdp-test.invalid` | `GetAddrInfoW("rdp-test.invalid","3389")`. **Genuine "Remote Desktop can't find the computer" dialog** (expected Windows behaviour) |
| EXP-019 | 2026-11-14 | 0001–0009 | `/v:127.0.0.1:3390` (nothing listening) | `connect` refused. Genuine "Remote Desktop can't connect to the remote computer for one of these reasons…" dialog |
| EXP-020 | 2026-11-14 | 0001–0009 | `/v:127.0.0.1:3391`, local listener that reads then closes | Client sent a 19-byte TPKT/X.224 Connection Request (`03 00 00 13`…), the first RDP PDU from the genuine stack. Genuine "This computer can't connect to the remote computer" dialog. No unimplemented functions |
| EXP-021 | 2026-11-14 | 0001–0009 | `/v:<test-host>` (Windows, not domain-joined) | mstsc probes the `CREDSSP` package (absent in Wine) and falls back to Schannel TLS. The handshake fails: GnuTLS "Key usage violation". The server's default self-signed RDP certificate lacks digitalSignature, and the server picks ECDHE_RSA. mstsc shows "An authentication error has occurred. File not found." Reproduced locally with `tests/static/schannel-keyusage` (fails on baseline and patched) |
| EXP-022 | 2026-11-14 | host GnuTLS 3.8.9 | Native probe of GnuTLS priority strings against the fixture server | `%DEBUG_ALLOW_KEY_USAGE_VIOLATIONS` covers only the local certificate (no effect for clients). `%COMPAT` passes but drops Extended Master Secret (EMS=0). Adding `%FORCE_SESSION_HASH` makes the handshake fail. **No priority string gives "accept peer key-usage violation" while keeping EMS** → patched GnuTLS needed (R-016) |
| EXP-023 | 2026-11-14 | 0001–0011 + bundled GnuTLS (ADR-0013) | `/v:<test-host>` (Windows Server, not domain-joined, NLA not enforced) | TLS completes (ECDHE_RSA, RDP default cert). `SECPKG_ATTR_PACKAGE_INFO` → **patch 0011**. Then: **first Remote Desktop session.** Operator signed in interactively at the Windows logon screen; full desktop, connection bar, taskbar rendered (d3d/llvmpipe). No CredSSP (Wine has no package), so this was TLS-only security |
| EXP-024 | 2026-11-14 | same | Operator clicked restore/maximize on the fullscreen connection bar | Window became unusable (in Xephyr without a window manager). **Open issue**, to be reproduced under a real WM (Cinnamon) and KDE/XWayland |
| EXP-025 | 2026-11-14 | 0001–0011 + bundled GnuTLS | `/v:localhost:<port>` → `fake-rdp-tls.py` (X.224 + TLS, untrusted self-signed cert, CN matches), empty `Default.rdp` | **No certificate warning**: MCS Connect Initial sent 0.07 s after TLS. Chain `0x20` (untrusted root) and `CERT_E_UNTRUSTEDROOT` computed correctly; mstsc policy flags `0x12380`. Advanced tab default: "Connect and don't warn me" |
| EXP-026 | 2026-11-14 | same | Same endpoint with `authentication level:i:2` (`.rdp` file) | Genuine "Unknown remote connection" (unsigned .rdp) dialog, then the genuine **certificate warning** ("not from a trusted certifying authority"). "Don't ask me again" stores `Servers\<host>\CertHash`, after which it reconnects without prompting |
| EXP-027 | 2026-11-14 | same + test-only provider advertising `CREDSSP` | Advanced tab with empty `Default.rdp` | Default becomes **"If server authentication fails: Warn me"** (Windows behaviour). Cause of EXP-025 is the missing CredSSP package. Interim fix: ADR-0015 |

## Reproducible tests

| Test | Command | Covers |
|---|---|---|
| Patch regression A/B | `tests/run-regression.sh build/install-wine-11.0 baseline` / `... build/install-wine-patched patched` | patches 0001, 0002 |
| MUI fixture | `tests/static/mui-fixture/build.sh OUT` then `wine OUT/muitest.exe` | LN exe + satellite, Unicode string, checksum rejection |
| devobj conformance | `wine build/wine-patched/dlls/devobj/tests/x86_64-windows/devobj_test.exe devobj` | DevObj create/GetClassDevs/enum/destroy |
| `.mun` fixture | `wine OUT/mun/muntest.exe` (after copying `OUT/mun/SystemResources/*` to `C:\windows\SystemResources`) | patch 0005 |
| secur32 conformance | `wine build/wine-patched/dlls/secur32/tests/x86_64-windows/secur32_test.exe secur32` | patch 0006 |
| GUI driving | `tools/xclick.py :5 click X Y` / `type TEXT` / `key Return` (XTEST) | manual GUI steps in Xephyr |
| Connect smoke (GUI) | `DISPLAY=:5 tests/launch/test-connect-invalid.sh` | patches 0006–0009 end to end |
| ws2_32 / advapi32 / msxml3 conformance | `ws2_32_test.exe protocol`, `advapi32_test.exe cred`, `msxml3_test.exe domdoc` | patches 0007–0009 |
| Schannel vs RDP-style certificate | `tests/static/schannel-keyusage/build.sh OUT && run.sh WINE OUT` | R-016 (currently fails on both runtimes) |
| user32 #2598 | `wine artifacts/user32-ordinals/ord2598.exe` | patch 0003 |
| shcore conformance | `wine build/wine-patched/dlls/shcore/tests/x86_64-windows/shcore_test.exe shcore` | patch 0004 |
| Launcher isolation | `tests/launch/test-launcher-isolation.sh` | F-013, N-003 |
| mstscax probe (needs registration) | `wine cscript //nologo tests/launch/probe-mstscax.js` | ProgID activation, `Version` |

## Phase 1 acceptance status (T-001…T-021)

T-001 (launch) is **largely met**: the genuine dialog renders with its images and genuine fonts. One label is truncated.
T-002 onward also need a Windows RDP test endpoint, which hasn't been provided.
