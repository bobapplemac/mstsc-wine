# ADR-0007: SHCreateStreamOnModuleResourceW (patch 0004)

- Status: accepted (upstream candidate)
- Defect (V): mstsc.exe imports `SHLWAPI.dll` ordinal 628 to get an IStream for its
  `IMAGE` resources, then passes the stream to `IWICImagingFactory::CreateDecoderFromStream`.
  Wine 11.0 has no shlwapi 628, and shcore 109 is a stub. The import stayed unresolved,
  the call returned success with a NULL stream, and windowscodecs then crashed in
  `BitmapDecoderInfo_MatchesPattern`. The backtrace runs from mstsc's connection dialog
  `WM_INITDIALOG`.
- Fix: implement shcore 109 (Find/Load/Lock resource, then `SHCreateMemStream`, returning
  the HRESULT from the last error on failure). Export shlwapi 628 as a forward by
  **ordinal** (`shcore.#109`), because shcore exports it `-noname`.
- Signature `(HMODULE, LPCWSTR name, LPCWSTR type, IStream **)`: (V) from the call site;
  the name is (I) from Wine's existing shcore.spec annotation.
- Test: `dlls/shcore/tests/shcore.c` `test_SHCreateStreamOnModuleResourceW` uses an
  embedded RCDATA resource and passes on Wine. It has not been run on Windows.
- Not covered: WIC should return E_INVALIDARG for a NULL stream instead of crashing.
  That is a separate robustness bug, now hidden because callers no longer get NULL.
