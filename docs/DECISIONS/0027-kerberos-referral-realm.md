# ADR-0027: Kerberos gives target names without a realm the referral realm (patch 0024)

- Status: accepted. 2026-11-15.
- Symptom (V): on a machine without `/etc/krb5.conf`, the usual case outside the domain,
  importing the target `TERMSRV/host` fails: "Configuration file does not specify default
  realm".
- Windows (I: documented referral behaviour): asks the user's own KDC for the service ticket
  and follows its referrals.
- Decision:
  - An ISC target name with a `/` and no `@` is imported as a Kerberos principal with an
    empty realm (`TERMSRV/host@`), the referral realm. MIT then asks the client's realm and
    follows referrals.
  - This skips MIT's DNS host-name canonicalization that a host-based service name would
    get. Windows does not canonicalize either.
  - Other names (with a realm, or no `/`) are imported as before.
- Tests:
  - `tests/security/kerberos/run.sh`: the realm config has no `default_realm`. Fails without
    the patch.
  - Live (EXP-041): no `krb5.conf` on the dev machine; the KDC was found through DNS SRV
    records, and the service ticket for `TERMSRV/<domain-rdp-host>` was issued.
