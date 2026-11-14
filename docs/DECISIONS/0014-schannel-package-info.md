# ADR-0014: Schannel `SECPKG_ATTR_PACKAGE_INFO` (patch 0011)

- Status: accepted (upstream candidate)
- Defect (V): after the TLS handshake, mstscax queries `SECPKG_ATTR_PACKAGE_INFO` (10)
  on the Schannel context. Wine returns SEC_E_UNSUPPORTED_FUNCTION, and mstsc shows
  "An authentication error has occurred (Code: 0x80090302)".
- Fix: return `QuerySecurityPackageInfo(UNISP_NAME)`, freed with `FreeContextBuffer`, for
  both the W and A variants. This is documented SSPI behaviour.
- Not done: attribute `0x80000081` is also queried. It's undocumented, Wine has no name for
  it, and it still returns unsupported. mstsc tolerates that (V: the session connects).
- Tests: `secur32_test.exe schannel` (`test_communication`, needs test.winehq.org) and the
  offline fixture `tests/static/schannel-keyusage/tlsclient.c`.
