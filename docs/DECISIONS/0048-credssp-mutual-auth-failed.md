# ADR-0048: CredSSP fails with SEC_E_MUTUAL_AUTH_FAILED for an unauthenticated server (patch 0040)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-065):
  - Over NLA, the genuine mstsc connected to servers with self-signed certificates
    **without** the certificate warning. Seen on Windows Server 2025 by IP (operator, KDE
    machine), the domain RDP host by IP, and the EXP-031 test VM.
  - Genuine Windows mstsc warns for the same server (operator-checked from a fresh Windows PC).
  - The plain-TLS path warned correctly all along (`tests/security/cert-prompt`).
- Not a regression (V): a runtime with patches 0001–0015 (the EXP-031 state) behaves the
  same. EXP-031's "warning shown" was therefore not the NLA path, so that record was wrong.
  The NLA path had never warned.
- Cause (V):
  - Our CredSSP package (patch 0015) answered the server-authentication query
    correctly (`SECPKG_ATTR_SERVER_AUTH_FLAGS` = 0, chain `0x20`, `CERT_E_UNTRUSTEDROOT`).
    But `InitializeSecurityContextW` returned `SEC_E_OK` and claimed `ISC_RET_MUTUAL_AUTH`.
  - mstscax (disassembly, `artifacts/mstscax.dis`): the error classifier for a failed
    CredSSP handshake has a case for `SEC_E_MUTUAL_AUTH_FAILED` (0x80090363). Only there
    does it query `SECPKG_ATTR_CERT_TRUST_STATUS` (0x80000084) and compute the certificate
    errors that drive the warning dialog.
  - Neighbouring cases handle `SEC_E_CERT_UNKNOWN`, `SEC_E_CERT_EXPIRED`,
    `SEC_E_CERT_WRONG_USAGE` and `CRYPT_E_REVOKED` the same way.
  - So Windows' CredSSP signals an unauthenticated server by **failing** the handshake call.
    mstsc never looks at the flags alone.
- Decision (patch 0040):
  - In the step after the server's `pubKeyAuth` verifies, and **before** the TSCredentials
    are built: if the caller requested `ISC_REQ_MUTUAL_AUTH` and `server_auth` is 0,
    return `SEC_E_MUTUAL_AUTH_FAILED`. The password is never sent to a server the user has
    not accepted.
  - When the inner Negotiate step completes with `ISC_RET_MUTUAL_AUTH` and the negotiated
    package is Kerberos, set `CREDSSP_SERVER_AUTH_NEGOTIATE`. Kerberos authenticates the
    server; NTLM does not. Kerberos logons stay warning-free, as on Windows (ADR-0025).
  - Answer `SECPKG_ATTR_SERVER_AUTH_FLAGS` and `SECPKG_ATTR_CERT_TRUST_STATUS` once the
    certificate was checked, also after the failure (previously only in `STATE_DONE`).
  - Return `ISC_RET_MUTUAL_AUTH` only when the server was authenticated.
- Observed flow with the fix (V, offline and live):
  - First attempt with `0xc11f` → `SEC_E_MUTUAL_AUTH_FAILED`. mstsc queries the trust status,
    and the genuine warning appears ("not from a trusted certifying authority").
  - "Yes" → mstsc connects again requesting `0xc11d` (no `ISC_REQ_MUTUAL_AUTH`). CredSSP
    completes and delegates; the session starts.
  - "No" → no connection, nothing delegated.
  - Wrong password: the server rejects the NTLM logon before this point, so the re-prompt
    behaviour (ADR-0022) is unchanged.
- Difference from the TLS-path dialog: the NLA dialog lists only the trust error, not a
  host-name mismatch, because mstsc fills it from `CERT_TRUST_STATUS`, which has no
  name-mismatch bit. Compare with Windows if it matters (open).
- Tests:
  - `tests/static/credssp-client` (regression suite) does what mstsc does: refused before
    delegation, flags 0, untrusted root, then a second attempt without mutual
    authentication succeeds.
  - `tests/security/kerberos/run.sh`: Kerberos sets flags `0x1` on the first attempt.
  - `tests/security/credssp/run.sh` (genuine mstsc): the warning is shown before any
    delegation, also with saved credentials; "Yes" delegates the right password.
