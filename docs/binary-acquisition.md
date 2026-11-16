# Microsoft component acquisition

The operator supplies Microsoft files from a licensed Windows installation they control.
The project never downloads them and never commits them (`.gitignore` blocks `*.exe`,
`*.dll`, `*.mui`, `*.zip`, `private-input/`, …). Copy all files from **one** machine/build. Do not mix builds.

## Recommended: the exporter (packaging)

Run `windows/Export-MstscComponents.ps1` on the Windows machine (64-bit PowerShell, no
admin rights), e.g. `irm https://raw.githubusercontent.com/bobapplemac/mstsc-wine/main/windows/Export-MstscComponents.ps1 | iex`
(other ways: [PACKAGING.md](PACKAGING.md)). It writes `mstsc-components-<build>-amd64.zip` with exactly the files below
plus a `manifest.json` (file versions, SHA-256). Put the ZIP in `private-input/` (or pass
`MICROSOFT_COMPONENTS=/path/to/zip`) and run `make`. `make verify-components` checks it:
one Windows build, allowed files only (`packaging/components-policy.json`), hashes and
versions matching. Details: [PACKAGING.md](PACKAGING.md), ADR-0046.

The ZIP and every artifact built from it are private: they contain Microsoft's files.
Whether your licence allows copying them, running them on Linux and including them in your
local package is for you to check. The project grants no rights to them.

The manual folder layout below still works for development (`launcher/mstsc-wine import`),
and `tools/mscomponents.py from-dir FOLDER OUT.zip` turns such a folder into the ZIP.

## Current set: Windows Server 2022, build 10.0.20348.5866

Copy from `C:\Windows\System32\`, keeping the `en-US` sub-folder:

| File | Status | Why |
|---|---|---|
| `mstsc.exe` | supplied | the client |
| `mstscax.dll` | supplied | the RDP ActiveX control / protocol stack |
| `en-US\mstsc.exe.mui` | supplied | all mstsc dialogs/strings/menus (RESEARCH R-002) |
| `en-US\mstscax.dll.mui` | supplied | mstscax strings/dialogs and its COM registration scripts |
| `dui70.dll` (+ `en-US\dui70.dll.mui` if it exists) | recommended | 133 DirectUI functions delay-loaded by mstscax; no Wine equivalent |
| `duser.dll` (+ `en-US\duser.dll.mui` if it exists) | supplied (2026-11-15; no `.mui`) | DirectUI dependency, delay-loaded by mstscax |
| `devobj.dll` | **do not copy** | not needed: the runtime ships its own builtin (ADR-0004). `import` and the exporter skip it, like `credssp.dll` and `tspkg.dll` |

### Also needed (2026-11-14)

| Path under `Windows\` | Copy from | Why |
|---|---|---|
| `SystemResources\mstsc.exe.mun` | `C:\Windows\SystemResources\` | mstsc banner/chevron images (R-010) |
| `SystemResources\mstscax.dll.mun` (if present) | same | control images |
| `Fonts\segoeui.ttf`, `segoeuib.ttf`, `segoeuii.ttf`, `segoeuiz.ttf`, `seguisb.ttf`, `segoeuil.ttf` | `C:\Windows\Fonts\` | Segoe UI family used by dialogs |
| `Fonts\seguisym.ttf`, `segmdl2.ttf` | same | symbol/icon glyphs |
| `Fonts\tahoma.ttf`, `tahomabd.ttf`, `micross.ttf` | same | MS Shell Dlg (2) targets |

Fonts are Microsoft-licensed too: never commit or package them (`.gitignore` covers `*.ttf`, `*.ttc`, `*.mun`).

If the Windows display language is not English, also copy the matching
`<lang>\*.mui` folders.

## Folder layout

Mirror `C:\Windows`. The repo-root `Windows/` folder is gitignored for this purpose:

```
Windows/
  system32/            mstsc.exe, mstscax.dll, dui70.dll, duser.dll, en-US/*.mui
  Fonts/               *.ttf
  SystemResources/     *.mun
```

The component store keeps paths relative to `C:\windows`, and `init` installs them there.
A flat folder of system32 files (the older layout) is still accepted and stored under `system32/`.

## Import

```bash
launcher/mstsc-wine import Windows           # or /path/to/folder   # copies + hashes into $XDG_DATA_HOME/mstsc-wine/components/<version>
launcher/mstsc-wine init                     # verifies hashes (fail closed), installs into the prefix
launcher/mstsc-wine doctor
```
