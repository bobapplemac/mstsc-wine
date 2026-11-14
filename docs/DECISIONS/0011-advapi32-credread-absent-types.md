# ADR-0011: `CredReadW` returns ERROR_NOT_FOUND for absent credential types (patch 0008)

- Status: accepted (upstream candidate)
- Defect (V): before connecting, mstscax calls `CredReadW(<host>, 6 /* CRED_TYPE_DOMAIN_EXTENDED */)`.
  Wine rejects every type except GENERIC and DOMAIN_PASSWORD with ERROR_INVALID_PARAMETER.
  On Windows, a missing credential gives ERROR_NOT_FOUND (I, from documented CredRead behaviour).
- Fix: accept types 1–6. Types other than 1 and 2 can never have been stored, because
  `CredWriteW` only accepts 1 and 2, so the call returns ERROR_NOT_FOUND. Wine has no
  `CRED_TYPE_DOMAIN_EXTENDED` define, so one was added; `CRED_TYPE_MAXIMUM` is unchanged
  to keep `CredGetSessionTypes` behaviour.
- The credential store itself is unchanged: entries sit in the prefix registry (R-014).
  Extending storage to more types or a host keyring is a separate decision.
- Test: `advapi32_test.exe cred`, `test_CredReadA` additions.
- Effect on 0xa08: not causal (the error persisted until patch 0009), but it removes a wrong error code.
