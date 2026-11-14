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
| `en-US\mstsc.exe.mui` | **required, missing** | all mstsc dialogs/strings/menus (RESEARCH R-002) |
| `en-US\mstscax.dll.mui` | **required, missing** | mstscax strings/dialogs and its COM registration scripts |
| `dui70.dll` (+ `en-US\dui70.dll.mui` if it exists) | recommended | 133 DirectUI functions delay-loaded by mstscax; no Wine equivalent |
| `duser.dll` (+ `en-US\duser.dll.mui` if it exists) | recommended | DirectUI dependency, delay-loaded by mstscax |
| `devobj.dll` | optional | A/B diagnostics only; the runtime ships its own (ADR-0004) |

If the Windows display language is not English, also copy the matching
`<lang>\*.mui` folders.

## Import

```bash
launcher/mstsc-wine import /path/to/folder   # copies + hashes into $XDG_DATA_HOME/mstsc-wine/components/<version>
launcher/mstsc-wine init                     # verifies hashes (fail closed), installs into the prefix
launcher/mstsc-wine doctor
```
