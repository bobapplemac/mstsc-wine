# ADR-0037: GetClipboardFormatNameW fails for predefined formats (patch 0034)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-050): mstsc's cliprdr Format List names predefined formats `#13`, `#16`, `#1`, `#7`.
  MS-RDPECLIP and the native client send empty names for them.
- Cause (V): user32 exported `GetClipboardFormatNameW` as a direct forward to `NtUserGetClipboardFormatName`,
  which returns integer-atom names. `GetClipboardFormatNameA` already returned 0 below 0xc000, as on Windows
  (Wine's own test checks the A version).
- Decision: a user32 wrapper with the same range check. win32u is unchanged, because its debug helpers rely on
  the atom names.
- Risk: a real rdpclip may register `#13` as a name and offer a bogus format to remote applications. No longer
  possible.
- Tests: user32 `clipboard` conformance test extended to the W version (54,976 tests, 0 failures);
  `tests/static/ole-clipboard` probe; launch test format lists show empty names.
