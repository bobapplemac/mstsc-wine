# ADR-0005: MUI satellite resource loading in ntdll (patch 0002)

- Status: accepted, pending validation with the real satellites (2026-11-13)
- Evidence: R-002, R-003, R-004. mstsc.exe and mstscax.dll keep all dialogs,
  strings, menus and even their ATL `REGISTRY` scripts in `en-US\*.mui`. Wine
  has no loader support, so both the UI and `DllRegisterServer` fail.
- Decision: In `LdrFindResource_U`, when a lookup in a normally loaded module fails
  and the module has a `MUI` config marking it as a language-neutral main file,
  map `<dir>\<lang>\<file>.mui` as an image resource. Languages are tried in this
  order: user UI language, system UI language, then the config's fallback, each
  followed by its neutral parent. The satellite's `MUI` config must mark it as a
  satellite and carry the same `checksum`. `LdrAccessResource` maps entries inside
  a satellite to that mapping. Mappings are cached per module, and stale entries
  are dropped if a different module reuses the address.
- Why LN-first, satellite-on-miss: identical results for every resource that
  exists today, so it cannot regress applications that currently work.
  Windows' exact order is undocumented (H).
- Alternatives:
  1. `AppDefaults\mstsc.exe\Version=winxp64`: mstsc then loads its own satellite
     (verified). Rejected as the primary path: it lies about the OS version to
     the RDP stack (CredSSP/NLA, DPI, feature gates) and does not help
     mstscax's `DllRegisterServer`. Retained as a documented fallback experiment.
  2. Merge satellite resources into copies of the Microsoft binaries: modifies
     Microsoft files and needs re-signing. Rejected.
  3. cschuls/WineMUI (out of tree, rejected upstream): EXE-only, global state,
     no checksum. Not adopted.
- Open questions to verify with real files: (a) does the real `.mui` checksum
  equal the LN file's `checksum` field? (b) `EnumResource*` on satellite-only types
  is not redirected yet. (c) Thread/process preferred UI languages are not
  consulted (Wine stubs them).
- Upstreamability: good candidate for WineHQ bug 43670 once (a) is verified and
  a conformance test that builds its own satellite is added to `dlls/kernel32/tests`.

## Update 2026-11-14
- Open question (a) is **answered (V)**: for mstsc.exe, mstscax.dll and dui70.dll the
  satellite `checksum` equals the main file's.
- The real satellites are **i386 resource-only images** even for x64 modules. Mapping one
  with `SEC_IMAGE` in a 64-bit process returns the informational
  `STATUS_IMAGE_MACHINE_TYPE_MISMATCH`, which the first version wrongly treated as
  failure. The patch now accepts every non-negative status, as kernelbase's
  `MapViewOfFile` does. The fixture gained an i386 satellite (`i386/`), built with
  windres plus `ld -m i386pe` and a minimal linker script.
