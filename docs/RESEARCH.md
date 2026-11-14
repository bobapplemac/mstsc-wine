# Research findings

Confidence: **V** = verified on this host with reproducible evidence; **I** = inference
from static analysis or documentation; **H** = untested hypothesis.

## R-001 Supplied binaries (V)

| File | SHA-256 | Version | Arch |
|---|---|---|---|
| mstsc.exe | d072dd1d8f82e6af8e52a0e1a579db691a6b76f0ce74d29df77cad42f1d0a7a2 | 10.0.20348.5866 (Server 2022) | x86-64 GUI |
| mstscax.dll | d0c9a8e14393e9217777d647e02d572b871b14d235bbe006db49b52b6d153b5d | 10.0.20348.5866 | x86-64 DLL |

- Neither file has an embedded Authenticode signature (`IMAGE_DIRECTORY_ENTRY_SECURITY` empty).
  System files on Windows are normally **catalog-signed**, so this is expected and is
  not evidence of tampering (I). Provenance relies on the operator. A future
  check could verify them against the `.cat` catalogs from the same machine (H).
- mstsc.exe manifest: `Microsoft.Windows.RemoteDesktopConnection`, depends on
  Common-Controls v6, `asInvoker`. mstscax.dll manifest: GdiPlus 1.1 and
  Common-Controls v6 (both optional dependencies).
- mstscax.dll exports only the COM entry points plus `DllGetTscCtlVer`.
- Full report: `tools/inspect-pe.py mstsc.exe mstscax.dll`.

## R-002 MUI split: UI resources live in satellite files (V)

Both binaries are **language-neutral (LN) main modules** (`MUI` config `file_type`
0x11, fallback language `en-US`). The `.mui` holds RT_ICON(3), MENU(4), DIALOG(5),
STRING(6), ACCELERATOR(9), GROUP_ICON(14) and VERSION(16). mstscax adds BITMAP(2)
and MESSAGETABLE(11). The main files contain **no dialogs or strings**.
Evidence: `tools/mui-config.py`.

Required satellites: `system32\en-US\mstsc.exe.mui` and `system32\en-US\mstscax.dll.mui`
from the same build. **Not supplied yet.**

## R-003 Wine 11.0 has no MUI satellite resource loading (V)

- No code in `dlls/ntdll`, `dlls/kernelbase` or `dlls/user32` opens `*.mui` files;
  `GetFileMUIPath` is a stub (`kernelbase/locale.c`).
- Reproduction `tests/static/mui-fixture`: an LN exe whose string exists only in
  `en-US\muitest.exe.mui`. Wine 11.0 gives `LoadStringW` = 0, `FindResourceW` = NULL.
- WineHQ bug 52215 (Win7 mstsc cannot find its MUI, NEW) depends on bug 43670
  ("missing MUI support", NEW since 2017). An out-of-tree patch,
  github.com/cschuls/WineMUI, was not accepted. It handles EXEs only, uses a single
  global and a single registry locale, and does no checksum check.
- Microsoft's documented loader fallback list is thread preferred UI languages, then
  process, user UI language, system UI language, then the "guaranteed good" fallback
  from the resource configuration. Satellites are associated by a checksum
  (https://learn.microsoft.com/windows/win32/intl/user-interface-language-management,
  https://learn.microsoft.com/windows/win32/intl/mui-resource-management).
  Whether the LN module or the satellite is searched first is undocumented.

## R-004 mstsc behaviour depends on the reported Windows version (V)

- With Wine's default (Windows 10), mstsc.exe never opens any `.mui` file. It relies on
  the OS loader and shows `File not found. C:\windows\system32\<LANG_NAME>\mstsc.exe.MUI`
  (screenshot `artifacts/exp001-launch.png`).
- With `HKCU\Software\Wine\AppDefaults\mstsc.exe\Version=winxp64` it probes the
  satellite itself: `system32\en-US\`, `system32\en\`, then `system32\mstsc.exe.mui`
  (`+file` trace). So an interim no-patch path exists once the satellites are
  supplied. However, a pre-Vista version may disable or alter CredSSP/NLA, DPI and
  other paths (H), so it is not the chosen solution.

## R-005 DEVOBJ.dll is a hard load-time blocker for mstscax.dll (V)

- `regsvr32 mstscax.dll` fails: `Library DEVOBJ.dll ... not found`. Wine 11.0 has no devobj.
- mstscax imports 13 `DevObj*` functions. Argument counts come from mingw-w64
  `lib32/devobj.def` stdcall decorations (mingw-w64 git). 11 match their
  `SetupDi*W` equivalents exactly. Disassembly of the call sites (`objdump -d`,
  call sites at 0x16aaf7b58, 0x16aaf7c0a, 0x16ab8f895, 0x16aaf80a0, 0x16aaf89b4)
  confirms the argument order for OpenDeviceInterface, OpenDevRegKey and
  GetDeviceRegistryProperty (I, high confidence).
- `DevObjCreateDeviceInfoList` (5 args) is called with all NULL and checked
  against INVALID_HANDLE_VALUE. `DevObjGetClassDevs(set, guid, NULL, 0x12, NULL, NULL)`
  returns a **BOOL**, with the existing set as the first argument (I).
- Fix: new Wine builtin `devobj.dll` (patch 0001).

## R-006 Other import gaps (static analysis, I)

From `tools/check-imports.py wine-src mstsc.exe mstscax.dll`. These resolve to
"unimplemented function" thunks that crash only if called:

| Import | Used by | Notes |
|---|---|---|
| ucrtbase `__C_specific_handler_noexcept` | mstsc.exe (static) | SEH handler for noexcept frames; hit only while an exception unwinds |
| shlwapi ordinal 628 | both (static) | identity unknown; needs call-site analysis |
| sechost `CredWriteDomainCredentialsW`, `CredProtectW`, `CredUnprotectW` (stubs) | mstscax (static) | credential saving paths |
| advapi32 `CredWriteDomainCredentialsW` | mstsc.exe (delay) | missing export |
| oleaut32 `BSTR_User*64` | mstscax (delay) | Wine exports only the non-64 names |
| rpcrt4 `NdrMesType{Encode,Decode,Free}3` | mstscax (delay) | serialization |
| comctl32 ordinal 345, d2d1 ordinal 1 | delay | identity to confirm |
| `DUI70.dll` (133 functions), `DUser.dll` | mstscax (delay) | DirectUI; no Wine implementation |

API sets: all `api-ms-win-*` imports resolve through Wine's `apisetschema`
(the loader ignores the last version component).

## R-007 Prior Wine/mstsc history (I)

- Bug 25343 (RDP 7 client fails, CLOSED FIXED in 1.7.19, 2014). Historical crashes
  in secur32 `DecryptMessage` with TLS (2011) and a stack overflow on exit (2014).
  Suggests the old mstsc ran on Wine; the modern client is far larger.

## R-008 Supplied component set, 2026-11-14 (V)
Folder `system32/` (gitignored) holds mstsc.exe and mstscax.dll (20348.5866), dui70.dll
(20348.4893), devobj.dll (20348.2849), and en-US `.mui` for mstsc, mstscax and dui70
(i386 resource-only). duser.dll was not supplied; it is delay-loaded by dui70 and has
not been needed yet. Native devobj.dll is kept in the store but not installed (ADR-0004).

## R-009 mstscax self-registration (V/I)
No file contains a `REGISTRY` resource (V). On Windows, servicing manifests register
system COM classes, so `DllRegisterServer` probably fails there too (I). mstsc.exe got to
its connection dialog without any COM registration (V). If ActiveX hosting needs it later,
write the CLSID/TypeLib keys from the TYPELIB resource rather than patch around this.

## R-010 Images live outside the PE+MUI pair (H)
mstsc calls `SHCreateStreamOnModuleResourceW(mstsc.exe, #690/#675/#676, L"Image")`, and
neither mstsc.exe nor mstsc.exe.mui has an `IMAGE` type. Windows 10 1903+ loads such
resources from `%windir%\SystemResources\<name>.mun`. Wine has no `.mun` redirection, so
a loader change like ADR-0005 will be needed once the file is available to test.

## R-011 Fonts (V)
The dialog templates in mstsc.exe.mui use `MS Shell Dlg` 8pt (25 dialogs) and
`Segoe UI` 9/10pt (6). Neither font is in the prefix or on the host (`fc-match` → Cantarell).
