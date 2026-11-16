# ADR-0046: Microsoft component bundle and import pipeline

- Status: accepted. 2026-11-15.
- Bundle: `mstsc-components-<OS build>-amd64.zip` holds `manifest.json` (schema
  `mstsc-wine-components/1`: OS build, product/edition, architecture, language, support
  level, and per file its path, role, size, SHA-256 and file version) and the files under
  `Windows/{System32,SystemResources,Fonts}`. No user, machine or source-path fields.
- Producers:
  - `windows/Export-MstscComponents.ps1`: on Windows, no admin rights, never uploads.
    Rejects non-x64 Windows, 32-bit PowerShell, missing required files and mixed builds.
    Rejects unverified OS builds unless `-Experimental`.
  - `tools/mscomponents.py from-dir`: the same bundle from a folder that mirrors
    `C:\Windows` (operators who already copied files).
- Policy (`packaging/components-policy.json`, mirrored in the exporter):
  - Required: `mstsc.exe`, `mstscax.dll`, their `<lang>` MUI files, `mstsc.exe.mun`.
  - Recommended: `mstscax.dll.mun`, `dui70`/`duser` (+MUI), and the Segoe UI, Tahoma and
    Microsoft Sans Serif fonts.
  - Excluded: `devobj.dll` (builtin, ADR-0004), `credssp.dll`/`tspkg.dll` (Wine's
    builtins are used, ADR-0018). Anything not listed is rejected.
  - Verified builds: 20348 (Server 2022). Others need `MSTSC_COMPONENTS_EXPERIMENTAL=1`.
- Verification (`tools/mscomponents.py verify`, `make verify-components`), fails closed on:
  - an unsafe path or size, a schema or architecture mismatch;
  - a file that is missing, extra or not allowed, or whose hash or file version does not match;
  - non-x64 binaries;
  - mstsc.exe ≠ mstscax.dll version, a binary from another build, OS build ≠ client build.
- Assembly: verified files are unpacked into `usr/share/mstsc-wine/Windows/` (read-only in
  the AppDir) with `manifest.sha256`. The icon is extracted locally from `mstsc.exe` or
  `mstsc.exe.mun`, pure Python, PNG with alpha, 16–256 px. It stays in the private artifact.
- Prefix staging: copy, not symlink (an AppImage mount point changes on every start). The
  launcher copies the components into the prefix once, under a per-application lock
  (`flock` on `XDG_DATA_HOME/mstsc-wine/.lock`), and records
  `format=1 runtime=<id> components=<id>` in `<prefix>/.mstsc-wine-state` (atomic rename).
  - A later start compares that line and does nothing when it matches (PKG-014).
  - A new runtime or component set triggers `wineboot -u` and a re-copy. The registry hives
    are saved first to `XDG_DATA_HOME/mstsc-wine/backups/<time>/`; the last five are kept.
    Saved credentials and `Default.rdp` survive: they live in the prefix and are not touched.
- Git hygiene: `.gitignore` excludes `private-input/`, `*.zip`, `*.mun`, `*.ico`,
  `*.AppImage`, `*.tar.zst`, AppDirs and `mstsc-components-*`. `tests/portability/test-repo-hygiene.sh`
  checks tracked files and the Docker context (PKG-002).
