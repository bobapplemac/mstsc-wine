# ADR-0004: Implement devobj.dll as a Wine builtin (patch 0001)

- Status: accepted (2026-11-13)
- Evidence: R-005. `mstscax.dll` statically imports 13 `DevObj*` functions;
  without `DEVOBJ.dll` it cannot load (regsvr32: "Library DEVOBJ.dll ... not found").
- Decision: Add `dlls/devobj` to Wine. Exports whose x86 stdcall argument size
  matches the public `SetupDi*W` function are spec-forwarded; the two that differ
  (`DevObjCreateDeviceInfoList`, `DevObjGetClassDevs`) get small wrappers whose
  semantics come from mstscax call sites. Unknown parameters emit FIXMEs.
  All other exports are stubs. Conformance test: `dlls/devobj/tests`.
- Alternatives:
  1. Native Microsoft `devobj.dll` override: it depends on Windows cfgmgr32/PnP
     internals and would widen the proprietary surface (spec §4.3). Kept only as an
     optional A/B diagnostic if the operator supplies it.
  2. Patch mstscax imports: modifying Microsoft binaries is not acceptable.
- Upstreamability: plausible. The conformance test should first be run on real
  Windows to confirm the inferred `DevObjGetClassDevs` semantics. Until then the
  test documents an inference.
- Risk: device-enumeration paths in mstscax (camera/USB/PnP redirection, P2) may hit
  stubs; acceptable for Phase 1.
- Update 2026-11-15: the Microsoft `devobj.dll` is no longer kept at all. It was only held for
  A/B comparisons, which are no longer needed. The component exporter and policy exclude it,
  `mstsc-wine import` skips it, the `MSTSC_WINE_INSTALL_ALL` override is gone, and the copies
  in `Windows/` and the development store were deleted. A store that still contains it never
  installs it.
