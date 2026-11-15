# ADR-0028: Kerberos keeps tickets for explicit credentials in a memory cache (patch 0025)

- Status: accepted. 2026-11-15.
- Symptom (V): `AcquireCredentialsHandle` with a user name and password stored the new
  ticket-granting ticket in the default credential cache, usually `/tmp/krb5cc_<uid>`.
  - It replaced any tickets the Linux user had there.
  - It left the domain TGT on disk after mstsc exited.
- Windows: such tickets live in the logon session in LSA memory (I).
- Decision:
  - Create a new `MEMORY` cache per credential handle (`krb5_cc_new_unique`).
  - Store the TGT there, and acquire the GSS credential from it (`gss_acquire_cred_from`
    with a `ccache` store).
  - The functions are optional. Without them (older or Heimdal libraries), the default cache
    is used as before.
  - The cache lives as long as the process (H: freeing it with the credential handle needs
    a handle structure change; not needed for mstsc).
  - Without explicit credentials, the default cache (`kinit` tickets) is still used.
- Tests:
  - `tests/security/kerberos/run.sh`: `KRB5CCNAME` points to a file that must not appear.
    It is created without the patch.
