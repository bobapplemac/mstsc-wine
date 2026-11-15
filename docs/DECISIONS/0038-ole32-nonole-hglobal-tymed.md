# ADR-0038: HGLOBAL storage for handle-based predefined formats (patch 0035)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-051): a picture copied in a Linux program (`image/bmp`) reaches Wine's clipboard as CF_DIB.
  mstsc announces it, but answers the server's data request with FAIL.
- Cause (V): mstsc reads the local clipboard with `OleGetClipboard`. For a clipboard set without OLE, ole32's
  `get_tymed_from_nonole_cf()` returned `TYMED_NULL` for CF_DIB and CF_DIBV5, so `GetData` failed
  (`0x80040069`, seen in mstscax's WPP trace).
- Decision:
  - Report `TYMED_ISTREAM | TYMED_HGLOBAL` for the HGLOBAL predefined formats: CF_DIB, CF_DIBV5, CF_LOCALE,
    CF_SYLK, CF_DIF, CF_TIFF, CF_RIFF and CF_WAVE.
  - Windows does this for CF_LOCALE: the existing ole32 test was `todo_wine` and now passes.
  - CF_DIB is inferred from the same rule (I) and checked by the new `test_nonole_dib`.
- Tests: ole32 `clipboard` conformance (583 tests, 0 failures, one todo_wine removed); launch test: picture
  local → remote (pixels compared; mstsc sends 32 bpp).
