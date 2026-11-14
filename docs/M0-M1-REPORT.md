# M0–M1 report

## Verified
- **Host:** LMDE 7 (Debian 13 "trixie" base), x86-64, kernel 6.12.116, Cinnamon on X11,
  8 CPUs / 11 GiB. No Wine was installed and no build dependencies were present; there
  is no password-less sudo. This is a *secondary* environment per spec §3.2.
- **Client binaries:** mstsc.exe / mstscax.dll 10.0.20348.5866, x86-64, hashes in
  RESEARCH R-001. Neither has an embedded signature (catalog-signed system files).
- **Required extra inputs identified:** `en-US\mstsc.exe.mui`, `en-US\mstscax.dll.mui`
  (R-002); recommended: `dui70.dll`, `duser.dll`.
- **Upstream baseline:** Wine 11.0 tag `wine-11.0` = `db11d0fe6a16…`; builds
  out-of-tree in ≈6 min; runs a benign MinGW-built PE (`hello.exe`) and `cmd`
  in a fresh isolated prefix.
- **Unmodified-Wine behaviour of the supplied client:** mstsc.exe starts and shows
  only its "MUI not found" error (EXP-001). mstscax.dll fails to load: no DEVOBJ.dll (EXP-003).
- **With patches 0001–0002:** mstscax.dll loads and begins self-registration. Both binaries
  search for their satellites through the new loader path (EXP-004/005).
- **Regression suite:** green on both baseline (expected failures) and patched.

## Inference / hypotheses
- The real satellites' `checksum` field matches the LN file's (ADR-0005). If it doesn't,
  patch 0002 will reject them; the WARN message says so and is visible with `WINEDEBUG=warn+resource`.
- `DevObjGetClassDevs` semantics (ADR-0004) come from call-site analysis, not Windows tests.

## Remaining inputs needed
1. The satellite and DirectUI files listed in `docs/binary-acquisition.md`.
2. A disposable Windows RDP endpoint and test credentials (for M3). Enter credentials
   interactively, never in files.

## Next M2 command
```bash
launcher/mstsc-wine import /path/to/server2022-files
launcher/mstsc-wine init
launcher/mstsc-wine exec regsvr32 /s mstscax.dll
MSTSC_WINE_TRACE=+loaddll,+seh,warn+resource launcher/mstsc-wine
```
