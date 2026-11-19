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
| advapi32 `CredWriteDomainCredentialsW` | mstsc.exe (delay) | missing export; not used by "Remember my password" (R-021) |
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
Update 2026-11-15: the operator supplied duser.dll (10.0.20348.1, x86-64, same build; carries
a MUI resource, but no en-US\duser.dll.mui was supplied). It is part of the component bundle
(20 files). mstsc's connection dialog still loads neither dui70 nor duser (V, +loaddll): they
are delay-loaded by specific UI only. The Microsoft devobj.dll was deleted the same day (not
needed; ADR-0004 update).

## R-009 mstscax self-registration (V/I)
No file contains a `REGISTRY` resource (V). On Windows, servicing manifests register
system COM classes, so `DllRegisterServer` probably fails there too (I). mstsc.exe got to
its connection dialog without any COM registration (V). If ActiveX hosting needs it later,
write the CLSID/TypeLib keys from the TYPELIB resource rather than patch around this.
**Resolved (V, 2026-11-14):** REGISTRY #101–103 are in `SystemResources\mstscax.dll.mun`.
With patch 0005, `regsvr32 /s mstscax.dll` exits 0 and registers the MsTscAx ProgIDs.
`new ActiveXObject("MsTscAx.MsTscAx.2").Version` returns `10.0.20348`. Other ProgIDs fail
from script with 0x800a01ad; that's probably not-safe-for-scripting classes (H).

## R-010 Images live outside the PE+MUI pair (V, 2026-11-14)
mstsc calls `SHCreateStreamOnModuleResourceW(mstsc.exe, #690/#675/#676, L"Image")`, and
neither mstsc.exe nor mstsc.exe.mui has an `IMAGE` type. Windows 10 1903+ loads such
resources from `%windir%\SystemResources\<name>.mun`. Wine has no `.mun` redirection, so
a loader change like ADR-0005 will be needed once the file is available to test.
**Confirmed:** `mstsc.exe.mun` holds 60 IMAGE resources (including #675/#676/#690), icons,
REGISTRY and UIFILE resources. Its MUI configuration is a byte copy of the LN module's (same
checksum, `file_type` 0x11). Patch 0005 loads it (ADR-0008), and the banner and chevron now render.

## R-011 Fonts (V)
The dialog templates in mstsc.exe.mui use `MS Shell Dlg` 8pt (25 dialogs) and
`Segoe UI` 9/10pt (6). Neither font is in the prefix or on the host (`fc-match` → Cantarell).

## R-012 Wine Mono / Gecko (V/H)
On 2026-11-14 a "Wine Mono Installer" prompt appeared during development. The operator
accepted it: `wine-mono-10.4.1-x86.msi` (WineHQ, open source, not Microsoft) went into
`~/.cache/wine/`, and Mono went into the regression prefix
`artifacts/prefixes/regress-install-wine-patched` only (V, by timestamp 08:13). The
launcher's mstsc prefixes have no Mono (V), because the launcher always sets
`mscoree=d;mshtml=d`. mstsc.exe and mstscax.dll are native C++ and import no .NET (V,
import tables), so **Mono is not a runtime dependency**. Packaging decision: keep
suppressing it and don't bundle it.
Gecko (`mshtml`) may be needed later if the Help button or another HTML surface
(`hh.exe`) is in scope (H). If so, bundle the matching `wine-gecko` MSI with the runtime
and install it offline at `init`. Never prompt the user and never download at runtime.

## R-013 Genuine fonts (V)
Win32u loads every font in `C:\windows\Fonts`, and the trace shows `segoeui.ttf`, `micross.ttf` and
`tahoma.ttf` loaded from there. The genuine Tahoma takes precedence over Wine's bundled Tahoma.
The launcher sets `MS Shell Dlg`→`Microsoft Sans Serif` and `MS Shell Dlg 2`→`Tahoma` as
Windows does; Wine's default maps both to Tahoma. Open issue: the "Show Options" label is
truncated to "Show Optio...", probably a text-metrics or DPI difference (H).

## R-014 Saved credentials (V/I)
Wine's advapi32 implements the Credential Manager (`CredReadW`/`CredWriteW`/`CredEnumerateW`).
Entries go in the prefix registry (`HKCU\Software\Wine\Credential Manager`) with the password
encrypted by a key that is also stored in the prefix. That is obfuscation, not real
protection (I). mstsc's "Remember me" should therefore work without a custom store.
Verify it once an endpoint exists. Don't add a plaintext JSON store; credentials must
not live in plain files. If stronger protection is needed, back the advapi32 credential
functions with libsecret (GNOME Keyring/KWallet) as a later, separately ADR'd change.

## R-015 Connect fails with 0xa08 (superseded, see below)
`mstsc /v:rdp-test.invalid` gets as far as a connection attempt. It then shows "An internal
error has occurred" (0xa08 / ext 0x0). Just before that, the trace shows
`WSALookupServiceBeginW(…, 0xff0, …)` and `WSALookupServiceNextW`, which are stubs in Wine
11.0 ("Stub!"). The RDP client resolves the host through the NS_* name-service API. With
the stub, it gets an unexpected failure instead of "host not found" (I). Next step:
implement `WSALookupServiceBegin/Next/End` for host-name queries (SVCID_INET_HOSTADDRBYNAME
and similar) on top of getaddrinfo, with a ws2_32 conformance test. Confirm first with a
call-site trace that the class GUID is the host-address one.

**Resolution (V, 2026-11-14):** the R-015 hypothesis was wrong. The `WSALookupService` query
is an NS_NLA network-availability check, not name resolution (patch 0007, ADR-0010). The
real cause was `IXMLDOMAttribute::put_nodeTypedValue` returning E_NOTIMPL, found with
breakpoints on mstscax's 0xa08 sites (ADR-0012). With patches 0007–0009, Connect resolves
the target and shows the genuine "can't find the computer" error for `.invalid` hosts.
mstscax's WPP tracing (the `testb $0x1,0x1c(%rax)` checks) is inert because Wine's ETW is
stubbed. Enabling it would make future diagnosis much easier (idea, not planned).

## R-016 TLS to servers with default RDP certificates (V/I)
Default self-signed RDP certificates have keyUsage keyEncipherment + dataEncipherment only.
Servers still pick ECDHE_RSA, which signs the key exchange with that key. GnuTLS rejects
this (`GNUTLS_E_KEY_USAGE_VIOLATION`); Windows Schannel accepts it (I: mstsc works against
such servers on Windows). Certificate *trust* is a separate check, done by mstsc (its
certificate prompt). In GnuTLS 3.8.9 (`lib/tls-sig.c`), the peer-certificate exemption reads
`session->internals.allow_key_usage_violation`. Only `%COMPAT` or
`gnutls_session_enable_compatibility_mode()` set it, and both also disable Extended Master
Secret and Encrypt-then-MAC (V, EXP-022). Decision (operator-approved, 2026-11-14): don't
accept that downgrade. Instead, ship a patched GnuTLS whose only change exposes the
peer-key-usage exemption on its own, enabled by Wine's Schannel for client sessions only.
Built from Debian's `gnutls28 3.8.9-3+deb13u4` source so it matches the system library's
security patches.

## R-017 First session; remaining security gaps (V/H)
With patches 0010–0011 and the bundled GnuTLS, mstsc completes TLS and runs a full session
(EXP-023). The logon happened inside the session (server NLA not enforced). Still missing for
Phase 1:
- **CredSSP/NLA:** Wine has no `CREDSSP` package. mstsc probes it with
  `QuerySecurityPackageInfoW(L"CREDSSP")`. Plan: implement [MS-CSSP] in Wine over Schannel
  plus Negotiate/NTLM (`ntlm_auth` is now installed). Operator preference: either Wine or
  native is fine; Wine is recommended (H: native tspkg/credssp need LSA infrastructure).
- **Certificate prompt:** not observed yet. Check whether mstsc's own trust check ran and
  passed silently, or wasn't reached (I). Test with an untrusted certificate (expect the
  genuine prompt) and with a valid one (expect no prompt).

## R-018 Default server-authentication level depends on CredSSP (V)
mstsc probes `QuerySecurityPackageInfoW(L"CREDSSP")` at startup. Without the package it
defaults to "Connect and don't warn me" and labels the option "If the actual verification
does not meet minimum policy requirements". With the package, it defaults to "Warn me"
(EXP-025, EXP-027). Wine's crypt32 verdicts are correct. The launcher seeds level 2 until
CredSSP exists (ADR-0015). The certificate prompt itself works (EXP-026), including
"Don't ask me again" pinning (`CertHash`).

## R-019 NLA in Wine: CredSSP client, server authentication, NTLM interop (V)
- mstsc over NLA delegates trust decisions to the CredSSP package via
  `SECPKG_ATTR_SERVER_AUTH_FLAGS`. It does not run its own chain check, as it does for
  TLS-only. Any CredSSP implementation must verify the certificate and report it, or
  mstsc connects silently (EXP-029).
- Samba's `ntlm_auth` (used by Wine's msv1_0) sends the NTLMv2 client blob without the
  4 trailing zero bytes from the MS-NLMP pseudocode. Windows hashes the blob as
  received and accepts it (EXP-030). pyspnego re-serializes it and rejects it; the test
  fixture verifies the raw blob instead.
- Native credssp/tspkg are not viable under Wine (ADR-0018).
- CredProtect in Wine is encoding only (ADR-0017).

## R-020 Fullscreen pointer grab and window managers (V/I)
- Wine clips the cursor to the monitor for a foreground fullscreen window. On X11 this is
  a pointer grab on an InputOnly clip window (V). Before patch 0016 it outlived the
  fullscreen state while the window stayed visible (V, EXP-033).
- Wine only grabs while X focus is on one of its windows. In a nested Xephyr without a
  window manager the focus check fails for a fresh process, so fixtures need a WM (V).
- Whether a stale grab is visible depends on the WM. Muffin kept the grab and ignored frame
  clicks; metacity runs recovered (I: focus change resets the clip).
- A local RDP *server* (FreeRDP shadow server sharing a private Xvfb, with a SAM-file NLA
  account) is a usable offline endpoint for client-side GUI behaviour. It does not replace
  a Windows host for protocol or feature fidelity (V for window behaviour, H otherwise).

## R-021 "Remember my password" (V/I)
- mstscax saves credentials only after the server reports a completed logon
  (`OnLoginComplete` → `PersistTsCredentialsAndUsernameHint` → `SaveCreds`), with
  `CredGetSessionTypes` and `CredWriteW`: `CRED_TYPE_DOMAIN_PASSWORD`, target
  `TERMSRV/<host>`, `CRED_PERSIST_LOCAL_MACHINE` (V: static analysis plus EXP-034 trace).
  The prompt-time path with `CredWriteDomainCredentialsW` was skipped in every run (I).
- The prompt is shown by mstscax (`CTscCredentialsQueryUi`), not mstsc.exe (V: relay
  return addresses).
- On reconnect mstsc only checks that a saved credential exists, then passes CredSSP no
  credentials (submit type 51, `pSpnegoCred` NULL). CredSSP must find the saved password
  itself, as Windows LSA does for `TERMSRV/*` under the default delegation policy (V for
  mstsc's side; H that Windows' lookup is by exact SPN).
- A FreeRDP shadow server never sends the logon-complete notification, so the save can
  only be observed against Windows. Tests seed the saved credential directly (V).
- Saved settings in a prefix (`Default.rdp`, `LastBBarXPos`/`LastBBarWidth`) move the
  connection bar; GUI tests that click it must reset them (V).

## R-022 How mstsc tells a wrong password from a server without NLA (V)
- After a failed NLA handshake, mstscax reads `ntdll!RtlGetLastNtStatus()` (security
  filter helper, stored at object offset `0x164`). `SslFilter::MapErrorCode(hr,
  lastStatusError)` turns `SEC_E_LOGON_DENIED` + `STATUS_LOGON_FAILURE` into "logon
  failed" (re-prompt). It has specific reasons for `0xC0000064`, `0xC000006E`–`0xC0000072`,
  `0xC000015B`, `0xC0000193`, `0xC0000224`, `0xC0000234`, `0xC0000380/381`, `0xC0000408`.
  Anything else means a generic failure, then a retry without NLA.
- Windows servers put the NTSTATUS in `TSRequest.errorCode` (EXP-030). pyspnego sends an
  HRESULT there.
- winedbg breakpoints work when attached (`--file` script, `attach 0x<pid>`). Earlier
  "breakpoints never hit" (R-021 work) were breakpoints on unused code paths. mstscax
  loads at `0x6ffffa6d0000` (relocated from `0x16a600000`).

## R-023 mstsc's re-prompt dialog (V/I)
- mstsc's re-prompt calls `CredUIPromptForWindowsCredentialsW` with the caption "Your
  credentials did not work", the error `SEC_E_LOGON_DENIED`, and the buffer it got back
  from the first prompt, which holds the old user name and password (V, `+credui`).
- Message text (V, `mstscax.dll.mui`): "The credentials that were used to connect to %s did
  not work. Please enter new credentials." It needs two lines or more in the classic
  dialog, more with a long host name.
- On Windows the password field is empty after a failed logon (V, operator). Windows'
  behaviour for an input buffer without an error is not checked (H: it fills the fields);
  Wine keeps filling both there.

## R-024 Kerberos for NLA without joining the domain (V/I)
- What it needs (V, EXP-041):
  - A KDC the client can reach. MIT finds it through DNS SRV records
    (`_kerberos._tcp.<dns.domain>`), so no `krb5.conf` is required.
  - The realm in the user name: a user principal name (`user@dns.domain`) or
    `dns.domain\user`.
  - The server addressed by its DNS name; an IP gives an SPN no KDC knows, so it falls
    back to NTLM.
  - Clocks within 5 minutes of the KDC.
- `DOMAIN\user` with the NetBIOS name gives the realm `DOMAIN` and falls back to NTLM (I).
  Windows maps NetBIOS names with DsGetDcName.
- A wrong password: the TGT request fails, Negotiate falls back to NTLM, and the server
  rejects that with `STATUS_LOGON_FAILURE`, so mstsc re-prompts (V, offline). That is two
  failed logons per attempt toward lockout (H: Windows may not fall back here).
- With Kerberos, mstsc shows no certificate warning (V, operator). Mutual Kerberos
  authentication proves the server's identity, so mstsc does not need to trust its TLS
  certificate. Windows clients behave the same way.
- pyspnego accepts Kerberos with `python3-gssapi` alone. It refuses to load GSSAPI without
  the `krb5` module, which it needs only for client passwords and which Debian does not
  package. The test server installs a stand-in module.
- The KDC for tests is Debian's MIT krb5-kdc unpacked under `.deps` (`tools/fetch-krb5kdc.sh`).
  It runs as the user on a high port, with no system configuration.

## R-025 How the genuine mstsc dialog gets its look (V/I)
- Fonts (V, EXP-044):
  - The connection dialog's templates in `mstsc.exe.mui` use `MS Shell Dlg` 8pt. Only the
    RemoteApp and Desktop Connections pages (417–419, Segoe UI 9pt) and three untitled
    templates (20019, 20050, 20090; Segoe UI 10pt) differ.
  - `MS Shell Dlg` maps to Microsoft Sans Serif on Windows and in the prefix; the genuine
    `micross.ttf` is installed. The Windows Server 2022 screenshots show Microsoft Sans
    Serif, not Segoe UI.
  - The banner fonts are created by mstsc itself with the face name "Tahoma" hard-coded
    (-20 px regular, -24 px bold), on Windows too.
  - mstsc does not use the system message font (`SPI_GETNONCLIENTMETRICS`) for its
    dialog text.
- Sizes (V): the collapsed client area is 405x221 on both systems. The dialog units match
  because the base units come from the same font.
- Text widths (V): Windows GDI advances hinted glyphs; FreeType v40 ignores horizontal
  hinting. The difference (about 5%) is enough to change where lines wrap (ADR-0031).
- Animation (V, EXP-043): **Show Options** grows the window from a worker thread in about
  six steps and moves the bottom row in `WM_WINDOWPOSCHANGED` after each step.
- Theme (V/I, EXP-045):
  - mstsc loads `uxtheme.dll` at run time and calls `EnableThemeDialogTexture(page,
    ETDT_ENABLETAB)` on the General page only (V, relay trace).
  - comctl32 calls `EnableThemeDialogTexture(parent, ETDT_ENABLE)` for every themed button
    and static, so every dialog holding controls gets `ETDT_ENABLE`. That includes the
    "Credentials" panel nested in the General page (V).
  - Windows draws that panel with the page's white tab texture. So native uxtheme gives an
    `ETDT_ENABLE` child dialog the texture of its textured parent (I, inferred from mstsc
    behaving the same on both systems). Implemented in patch 0029 (ADR-0032).
    `tests/static/dialog-layout/nested.exe` can confirm the rule on Windows.
- Toolbar and group box (V/I, EXP-046/047):
  - In comctl32 v6 the expander button starts at the top of its non-flat toolbar. Wine
    used the v5 2-pixel margin (patch 0030).
  - Windows leaves 2–3 pixels between a themed group box frame and its caption (patch 0031).
- Other small differences (I): Windows 10 button faces are drawn 1 px inside the button
  rectangle on each side; the tab row is a few pixels taller. These are theme drawing, not
  layout.

## R-026 How mstsc's clipboard redirection uses Wine (V/I)
- Channel (V, EXP-048): static virtual channel `cliprdr`. The general capability flags sent by mstsc are 0x1e:
  long format names, stream file clip, no file paths, can lock clip data.
- Local side (V, relay):
  - A thread with the `RdpClipRdrWindowClass` window and `OleInitialize`.
  - `AddClipboardFormatListener` and `GetUpdatedClipboardFormats` are resolved with `GetProcAddress`.
  - Reading the local clipboard: `OleGetClipboard` + `GetData`.
  - Remote data: `OleSetClipboard` with mstsc's own delayed-render data object.
  - Remote files: FileGroupDescriptorW + FileContents (`TYMED_ISTREAM`, `lindex` = item) +
    Preferred DropEffect.
  - Local files: built by mstsc itself from CF_HDROP. It reads the files and serves FileContents
    SIZE/RANGE requests, after the server has locked the data (Lock Clipboard Data PDU).
- Diagnostics (V):
  - mstscax logs errors with `OutputDebugStringW` (`+seh` shows them).
  - Everything else goes to WPP (`TraceMessage`): message number and arguments only, no format strings.
  - A temporary ntdll hook that calls the WPP control callback with all flags enabled, and prints each message
    with its return addresses, located both failures (`hr` arguments 0x8007007f and 0x80040069).
    Not in the patch series; recreate it locally when needed.
- Enterprise data protection (V/I): `RdpEdpPolicyManager::CreateInstance` fails, because
  `ole32!OleGetClipboardWithEnterpriseInfo`, `srpapi!SrpGetEnterpriseIds` and the WinRT
  `ProtectionPolicyManager` are absent. The failure is logged and non-fatal: clipboard copy works without the
  policy manager. Not implemented.
- WIL feature probes (V): ~22,000 `GetProcAddress(ntdll, "RtlQueryFeatureConfiguration")` per session before
  patch 0032. Any Windows 10 2004+ binary built with WIL does this.
- X11 side (V):
  - winex11's clipboard thread lives in explorer.exe.
  - In Wine 11.0 its requests are flushed only after X input (ADR-0036).
  - One X11 copy is imported twice (on SelectionClear and on the XFixes notification), which produces two
    Windows clipboard updates (open).


## R-027 Packaging: relocation, private helpers and dependency closure (V/I)

- Wine 11.0 is relocatable as built (V): `ntdll.so` derives `bin_dir`/`data_dir` from its own
  location and the compiled-in relation between `LIBDIR`, `BINDIR` and `DATADIR`
  (`init_paths()`, `build_relative_path()`); `wineserver` is started from `bin_dir` first
  (`exec_wineserver()`), with `WINESERVER`, `PATH` and the compiled `BINDIR` only as
  fallbacks. A `DESTDIR` install runs from any directory, including paths with spaces and
  non-ASCII characters (EXP-057). The configure prefix still appears in `ntdll.so` as a string
  (fallback), so packaging builds use the neutral `/usr/lib/mstsc-wine/wine` (ADR-0043).
- `msv1_0` runs `ntlm_auth` through `posix_spawnp` (V); patch 0039 adds `WINENTLMAUTH`.
  Client mode (`ntlmssp-client-1` with explicit user and domain) works without winbindd: no
  socket is opened, no Samba state is read; with `--configfile` the host `smb.conf` is not
  read (strace, V).
- Debian's `ntlm_auth` scans the compiled-in Samba module directory (`…/samba/gensec`, V) and
  would `dlopen` host modules. `set_dyn_MODULESDIR()` is exported by `libsamba-util`; a
  preloaded constructor redirects it into the bundle (V, strace shows only the private path).
  `LD_PRELOAD` entries cannot contain spaces, so the shim is preloaded by soname and found
  through `LD_LIBRARY_PATH` (V).
- Closure sizes (V): GnuTLS + 8 libraries (14 MB), Kerberos + libunwind 6 libraries (1.2 MB),
  Samba helper 86 libraries (61 MB, ICU is half). AppDir 351 MB, AppImage (zstd) 100 MB,
  tarball (zstd -19) 65 MB.
- Wine's only hard non-glibc `DT_NEEDED` outside winex11/audio drivers is `libunwind.so.8`
  (`ntdll.so`, V): without it Wine does not start. `libunwind8` is not present on every
  Debian 13 system, so it is bundled.
- First prefix boot prints `err:ole` marshalling and `start_rpcss` messages with both the
  development and the packaged runtime (V): normal, not a packaging defect.
- `WM_CLASS` of the genuine mstsc main window is `"mstsc.exe", "mstsc.exe"` (V, xprop),
  hence `StartupWMClass=mstsc.exe`.
- The AppImage type 2 runtime (release 20251108) mounts a zstd SquashFS produced by Debian's
  `mksquashfs` (V); appimagetool is not needed.

## R-028 Desktop scaling and Wine system DPI (V/I)

- Wine 11.0 initializes system DPI from `HKCU\Control Panel\Desktop\LogPixels`, then
  `HKCC\Software\Fonts\LogPixels`, and finally 96 (V, `dlls/win32u/font.c`). Its X11
  display enumeration uses that Wine system DPI; it does not import the X resource
  manager's `Xft.dpi` (V, source review).
- Genuine mstsc resolves the per-monitor-DPI APIs and opts into monitor awareness (V,
  R-006/ADR-0006). Therefore a 96-DPI Wine prefix can produce a physically tiny UI on a
  scaled desktop rather than receiving legacy bitmap scaling (I; matches the operator's
  LMDE/Cinnamon 150% report).
- Cinnamon publishes its effective X11-client DPI as `Xft.dpi`; with its X11 fractional
  framebuffer mode this can intentionally be an integer UI scale (for example 192) that
  the compositor later downsamples, rather than simply `96 * requested_fraction` (V/I,
  upstream Cinnamon/Muffin source and issue evidence). Copy the published value; do not
  recompute it from the nominal percentage or physical monitor dimensions.
- KDE and Cinnamon can both expose X resources to X11/XWayland clients. Whether the
  compositor also scales those clients is session policy, so the four-environment matrix
  (Cinnamon/KDE × X11/Wayland) still needs live checks (H). ADR-0050 provides an explicit
  DPI override and diagnostics without branching on desktop names.

## R-029 mstsc audio-format negotiation and Wine ACM handles (V)

- Wine's PulseAudio backend is functional on the reported LMDE machine: `winepulse.drv`
  is selected and the Wine control-panel test sound plays (operator, V). In a remote
  session mstsc opened and closed `WAVE_MAPPER`, but made no `waveOutWrite` call (trace, V).
- A local `rdpsnd` server fixture showed that mstsc received a PCM server format but
  replied with zero client formats (V). Its ACM enumeration calls
  `acmFormatTagDetailsW` with the `HACMDRIVERID` returned by `acmDriverEnum`, not with an
  opened `HACMDRIVER` (trace and disassembly, V).
- Wine 11.0 accepted only open driver handles on that path, so all of mstsc's format-tag
  queries returned `ACMERR_NOTPOSSIBLE` (V). Native Windows accepts the driver ID even
  though the public signature names an `HACMDRIVER` (conformance test, V).
- Patch 0041 temporarily opens an incoming driver ID. With the patch, mstsc advertises
  PCM stereo at 44.1 kHz and writes the fixture's tone through `waveOutWrite` (V). A
  GStreamer-enabled Wine build, callback-timing changes, and pitch-control changes did
  not alter the pre-fix failure (V); none is required for the fix.

## R-030 live audio stops before Wine playback (V/I)

- Patch 0041 is installed and active on the operator's LMDE laptop (V). In a real Windows
  session mstsc successfully probes PCM conversions for MS ADPCM (tag 2), IMA ADPCM
  (tag 17), A-law (tag 6), and GSM 6.10 (tag 49), but it never calls
  `acmStreamPrepareHeader`, `acmStreamConvert`, or `waveOutWrite` (V). The initial output
  device is opened successfully and then closed.
- The server session shows `Remote Audio`, and the same result occurs with
  `audioqualitymode` 0 and 2 and with `fClientDisableUDP=1` (V). The remaining failure is
  therefore before Wine's codec/output path and is not explained by UDP transport or the
  selected quality mode (I).
- `+seh` exposes no relevant `OutputDebugStringW` failure (V). MSTSC's detailed RDPSND and
  dynamic-channel diagnostics use classic WPP; Wine 11.0 registers those providers but
  never enables them, while `EtwTraceMessageVa` discards their events (V, source review).
- Patch 0042 adds an opt-in `+wpp` channel that enables classic providers and logs event
  IDs and bounded arguments (ADR-0052). A synthetic provider test fails on unmodified
  Wine and passes on patched Wine (V). Live WPP capture and call-site mapping are next.
