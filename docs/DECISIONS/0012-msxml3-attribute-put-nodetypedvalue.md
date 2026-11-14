# ADR-0012: `IXMLDOMAttribute::put_nodeTypedValue` (patch 0009)

- Status: accepted (upstream candidate)
- Defect (V): Connect failed with "An internal error has occurred" (0xa08 / ext 0x0).
  - Breakpoints on all 7 sites in mstscax.dll that store 0xa08 showed the failing path:
    mstscax+0x102e43, after the state-machine call at mstscax+0x996a0 returned
    0x80004001 (E_NOTIMPL).
  - Relay tracing showed that no exported API returned E_NOTIMPL. The only E_NOTIMPL COM
    stub hit on that path was msxml3 `domattr_put_nodeTypedValue` (VT_UINT 1).
- Fix: convert the value to a string and store it, as `put_value` and the element version
  do for untyped nodes. Attributes typed through the `dt:` namespace are not encoded (FIXME).
- Result (V): `mstsc /v:rdp-test.invalid` now resolves the host (`GetAddrInfoW …:3389`) and
  shows the genuine "Remote Desktop can't find the computer" dialog.
- Tests: `msxml3_test.exe domdoc`, `test_attribute_put_nodeTypedValue`;
  GUI: `tests/launch/test-connect-invalid.sh`.
