# ADR-0035: ntdll feature configuration exports (patch 0032)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-048): with clipboard redirection on, text copied on the remote side can never be
  pasted locally. mstsc answers every server Format List with `CB_RESPONSE_FAIL`.
- Cause (V):
  - mstscax's WIL feature checks call `GetProcAddress(ntdll, "RtlQueryFeatureConfiguration")` and
    `"RtlRegisterFeatureConfigurationChangeNotification"`. A relay trace counted about 22,000 of each per session.
    Wine 11.0 has neither export, so each call leaves `ERROR_PROC_NOT_FOUND` (127) as the last error.
  - mstscax's clipboard code calls `GlobalAlloc(GMEM_ZEROINIT, 4)` and then treats any non-zero
    `GetLastError()` as failure. The allocation succeeds, but the stale 127 fails the Format List.
  - Found with mstscax's own WPP trace calls (`hr 0x8007007f`), using a temporary local ntdll hook that enables
    WPP providers. That hook is not part of the series.
- Decision:
  - Add `RtlQueryFeatureConfiguration` (returns `STATUS_NOT_FOUND`: no override, so the caller uses its
    built-in default, as on a Windows installation without feature overrides),
    `RtlQueryFeatureConfigurationChangeStamp` (KUSER_SHARED_DATA stamp, 0), and
    `Rtl(Un)RegisterFeatureConfigurationChangeNotification`. The configuration never changes, so callbacks never fire.
  - Rejected: clearing the last error in `GlobalAlloc` (Windows does not document it, and it would hide the real gap),
    or patching mstscax (never modify Microsoft binaries).
- Effect: feature defaults are unchanged (WIL already fell back to them); the stale error and ~44k failing lookups
  per session are gone.
- Tests:
  - ntdll `rtl` conformance (`test_RtlQueryFeatureConfiguration`): 0 failures.
  - `tests/static/ole-clipboard` probe: GetProcAddress leaves no error, and `GlobalAlloc` is followed by a last
    error of 0. Fails on baseline, passes on patched.
  - `tests/launch/test-clipboard.sh`: remote → local text.
