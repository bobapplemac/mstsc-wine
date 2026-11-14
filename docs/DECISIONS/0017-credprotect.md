# ADR-0017: CredProtectW / CredUnprotectW / CredIsProtectedW (patch 0013)

- Status: accepted. 2026-11-14.
- Defect (V): mstscax imports `CredProtectW` and `CredUnprotectW`, and native tspkg uses
  them too. In Wine's sechost they were unimplemented stubs, so calling them would abort
  the process. Unpacking credentials with `CRED_PACK_PROTECTED_CREDENTIALS` needs them.
- Decision:
  - Implemented in advapi32, with sechost forwarding to it.
  - Protected strings use Windows' `@@D` prefix, followed by the UTF-16 code units in hex.
  - `CredIsProtectedW` recognises that form. Protecting an already-protected string
    fails, and unprotecting an unprotected one fails with `ERROR_NOT_CAPABLE`.
- Security limitation (V):
  - Windows encrypts with a logon-session key. Wine has no such key yet
    (`RtlEncryptMemory` is a no-op stub), so this is **encoding, not encryption**.
  - The secret only ever lives in the mstsc process, which already holds the clear text,
    so in-process exposure is unchanged.
  - Never write a protected string to disk on the assumption that it is encrypted.
    Persisting credentials ("Remember my password", `CredWriteDomainCredentialsW`) is a
    separate, not-yet-implemented item.
- Tests: advapi32 conformance `test_CredProtect`: round trip, `CredIsProtectedW`, sizes.
  Assertions are format-independent, so they hold on Windows too.
