# ADR-0010: NS_NLA network enumeration in `WSALookupService*W` (patch 0007)

- Status: accepted (upstream candidate)
- Defect (V): mstscax calls `WSALookupServiceBeginW` with `dwNameSpace = NS_NLA (15)`,
  class `{0037e515-…}` (NLA_SERVICE_CLASS_GUID), provider `{6642243a-…}`, and
  `LUP_RETURN_ALL`. That's a network-availability check, not host-name resolution.
  Wine 11.0 stubs it (`WSA_NOT_ENOUGH_MEMORY`) and returns a NULL handle to `NextW`.
- Fix: one result per operational, non-loopback adapter (`GetAdaptersAddresses`):
  - Name: the DNS suffix, or else the friendly name.
  - Blob: `NLA_INTERFACE`, then `NLA_CONNECTIVITY`. Internet is YES when a gateway exists,
    otherwise UNKNOWN (I).
  - Handles are validated; parameter errors follow the existing Windows-derived tests,
    whose `todo_wine` markers are removed.
  - The A variants and other namespaces remain stubs (FIXME + `WSASERVICE_NOT_FOUND`).
- On Windows the network name is the network profile name (for example the SSID). Ours is
  an approximation (H).
- Effect: this was **not** the cause of mstsc's 0xa08 (that was patch 0009), but mstscax
  consumes the result. Confidence that it matters for network-change handling: H.
- Test: `ws2_32_test.exe protocol`, `test_WSALookupService` and the new `test_WSALookupService_NLA`.
