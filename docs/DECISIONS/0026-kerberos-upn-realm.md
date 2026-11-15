# ADR-0026: Kerberos builds the realm from a user principal name, upper-cased (patch 0023)

- Status: accepted. 2026-11-15.
- Symptom (V, code reading and EXP-040):
  - A user name like `user@dns.domain` with no separate domain became the principal
    `user@dns.domain@`, which MIT cannot parse. Kerberos was skipped and NTLM used.
  - A lower-case domain (`dns.domain\user`) became the realm `dns.domain`. AD realms, and
    the test realm, are upper-case.
- Decision:
  - With no domain, split the user name at its last `@`.
  - Upper-case the realm (ASCII), as Windows does with AD realms.
  - `DOMAIN\user` with a NetBIOS domain still gives the realm `DOMAIN`, which normally
    does not exist. Kerberos then fails and Negotiate falls back to NTLM.
    Mapping NetBIOS names to DNS domains (DsGetDcName) is not implemented (I).
- Tests:
  - `tests/security/kerberos/run.sh`: `nla-test@mstsc.test` and `mstsc.test\nla-test` use
    Kerberos. Both fail without the patch.
