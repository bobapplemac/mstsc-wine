# ADR-0009: Implement `SspiPrepareForCredRead` (patch 0006)

- Status: accepted (upstream candidate)
- Defect (V): `mstsc /v:rdp-test.invalid` aborts with "unimplemented function
  sspicli.dll.SspiPrepareForCredRead". Wine 11.0 exports it as `@ stub`.
- Documented signature: `SECURITY_STATUS SspiPrepareForCredRead(PSEC_WINNT_AUTH_IDENTITY_OPAQUE,
  PCWSTR pszTargetName, PULONG pCredmanCredentialType, PCWSTR *ppszCredmanTargetName)`.
  It produces the Credential Manager type and target name used for `CredRead`.
- Fix: copy `pszTargetName`, or build `domain\user` from the identity when no target is
  given, and return `CRED_TYPE_DOMAIN_PASSWORD`. The string is freed with `SspiLocalFree`.
  This mirrors Wine's existing `SspiPrepareForCredWrite`. Also exported from secur32.
- Exact Windows output for every input is not verified (H). The conformance test only
  checks the documented contract: success, type `CRED_TYPE_DOMAIN_PASSWORD`, and a copied target.
- Test: `secur32_test.exe secur32`, `test_SspiPrepareForCredRead`.
- Credentials: Wine's advapi32 Credential Manager (`CredReadW`/`CredWriteW`) already
  stores saved credentials in the private prefix's registry, so no custom store is needed
  (R-014).
