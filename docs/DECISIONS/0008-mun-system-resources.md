# ADR-0008: Load main resources from `SystemResources\*.mun` (patch 0005)

- Status: accepted (upstream candidate)
- Defect (V): Windows 10 1903+ removes non-localizable resources (IMAGE, RT_ICON,
  RT_GROUP_ICON, REGISTRY, UIFILE, …) from system binaries and ships them in
  `%windir%\SystemResources\<file>.mun`. Wine 11.0 never looks there. For mstsc.exe
  10.0.20348, IMAGE #690/#675/#676 (banner, chevrons) are missing, so the dialog has no
  pictures. For mstscax.dll, REGISTRY #101 is missing, so `DllRegisterServer` fails (R-009).
- Evidence (V):
  - `mstsc.exe.mun` and `mstscax.dll.mun` are i386 resource-only images with the
    resources listed above.
  - Their `MUI` resource is byte-identical to the LN module's: `file_type` 0x11, with
    the same checksum and service checksum. The `.mui` satellite has `file_type` 0x12
    and the same checksum.
- Fix: patch 0005 extends ADR-0005's lookup to module → `.mui` satellite → `.mun`:
  - It runs only for LN main modules. The path is `NtSystemRoot\SystemResources\<basename>.mun`.
  - The `.mun` must be LN-main and have a matching checksum.
  - The mapping is cached per module, and `LdrAccessResource` resolves entries inside it.
- Exact Windows precedence is unknown (H). Satellite and `.mun` types don't overlap in the
  observed files, so the order doesn't change any result we have.
- Tests (fail on baseline, pass on patched): `tests/static/mui-fixture` `mun/muntest.exe`
  checks that IMAGE #200 is loaded from the `.mun`. `mun/muntestbad.exe` checks that a
  checksum mismatch is rejected.
- Not covered: resource enumeration (`LdrFindResourceDirectory_U`) doesn't merge the
  `.mui`/`.mun` directories. That matches ADR-0005.
