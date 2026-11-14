# Microsoft component acquisition

The operator supplies Microsoft files from a licensed Windows installation they control.
The project never downloads them and never commits them (`.gitignore` blocks `*.exe`,
`*.dll`, `*.mui`, …). Copy all files from **one** machine/build. Do not mix builds.

## Current set: Windows Server 2022, build 10.0.20348.5866

Copy from `C:\Windows\System32\`, keeping the `en-US` sub-folder:

| File | Status | Why |
|---|---|---|
| `mstsc.exe` | supplied | the client |
| `mstscax.dll` | supplied | the RDP ActiveX control / protocol stack |
| `en-US\mstsc.exe.mui` | supplied | all mstsc dialogs/strings/menus (RESEARCH R-002) |
| `en-US\mstscax.dll.mui` | supplied | mstscax strings/dialogs and its COM registration scripts |
| `dui70.dll` (+ `en-US\dui70.dll.mui` if it exists) | recommended | 133 DirectUI functions delay-loaded by mstscax; no Wine equivalent |
| `duser.dll` (+ `en-US\duser.dll.mui` if it exists) | recommended | DirectUI dependency, delay-loaded by mstscax |
| `devobj.dll` | optional | A/B diagnostics only; the runtime ships its own (ADR-0004) |

### Also needed (2026-11-14)

Put these in sub-folders of the same import folder; the launcher maps them into `C:\windows`:

| Path in import folder | Copy from | Why |
|---|---|---|
| `SystemResources\mstsc.exe.mun` | `C:\Windows\SystemResources\` | mstsc banner/chevron images (R-010) |
| `SystemResources\mstscax.dll.mun` (if present) | same | control images |
| `Fonts\segoeui.ttf`, `segoeuib.ttf`, `segoeuii.ttf`, `segoeuiz.ttf`, `seguisb.ttf`, `segoeuil.ttf` | `C:\Windows\Fonts\` | Segoe UI family used by dialogs |
| `Fonts\seguisym.ttf`, `segmdl2.ttf` | same | symbol/icon glyphs |
| `Fonts\tahoma.ttf`, `tahomabd.ttf`, `micross.ttf` | same | MS Shell Dlg (2) targets |

Fonts are Microsoft-licensed too: never commit or package them (`.gitignore` covers `*.ttf`, `*.ttc`, `*.mun`).

If the Windows display language is not English, also copy the matching
`<lang>\*.mui` folders.

## Import

```bash
launcher/mstsc-wine import /path/to/folder   # copies + hashes into $XDG_DATA_HOME/mstsc-wine/components/<version>
launcher/mstsc-wine init                     # verifies hashes (fail closed), installs into the prefix
launcher/mstsc-wine doctor
```
