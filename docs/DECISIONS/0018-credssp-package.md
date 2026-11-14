# ADR-0018: CredSSP client package in Wine secur32 (patches 0012, 0015)

- Status: accepted. 2026-11-14.
- Defect (V): Wine has no `CREDSSP` security package. mstsc therefore:
  - cannot use NLA, and fails against servers that require it;
  - defaults to "Connect and don't warn me" (ADR-0015).
- Decision: implement the client side of [MS-CSSP] v2–6 as a built-in secur32 provider
  (`dlls/secur32/credssp.c`), layered on the existing packages:
  1. TLS through Schannel. Manual credential validation is always set, because the
     caller decides trust.
  2. SPNEGO through Negotiate (NTLM via `ntlm_auth` today; Kerberos when available),
     carried in `TSRequest.negoTokens`.
  3. `pubKeyAuth` over the server's SubjectPublicKey: SHA-256 with a 32-byte client nonce
     from v5 on (CVE-2018-0886), the raw key for v2–4. The server's reply is verified.
  4. `authInfo`: `TSPasswordCreds` (domain, user, password), sealed with the Negotiate
     context.
  5. Afterwards, `EncryptMessage`/`DecryptMessage` and most attributes go to the TLS
     context.
- How mstsc calls it (V, EXP-028):
  - `AcquireCredentialsHandleW(NULL, "CREDSSP", OUTBOUND, CREDSSP_CRED{Type=50
    (SubmitBufferBoth), SCHANNEL_CRED v4, packed KERB_INTERACTIVE_UNLOCK_LOGON})`.
  - `InitializeSecurityContextW("TERMSRV/<host>", 0xc11f)`.
  - Also accepted: `SEC_WINNT_AUTH_IDENTITY_W`/`_EX` and `CREDSSP_CRED_EX`. Protected
    passwords are unprotected (ADR-0017).
- **Server authentication (V, EXP-029/031):** over NLA, mstsc does **not** check the
  certificate itself. It queries `SECPKG_ATTR_SERVER_AUTH_FLAGS` (0x80000083) on the
  CredSSP context.
  - The package verifies the chain (`CERT_CHAIN_POLICY_SSL`, host name from the SPN).
    Only a trusted, name-matching certificate sets `CREDSSP_SERVER_AUTH_CERTIFICATE`.
  - `SECPKG_ATTR_CERT_TRUST_STATUS` (0x80000084) returns the chain status.
  - Before this was implemented, the query fell through to Schannel, failed, and mstsc
    connected **without warning**. With it, mstsc shows the genuine certificate warning
    against a real Windows server (operator-confirmed).
- Order of delegation: like Windows' default policy (fresh credentials to `TERMSRV/*`
  after NTLM-only mutual authentication), credentials are delegated once the
  `pubKeyAuth` binding verifies. mstsc then warns about the certificate before the
  session.
- Rejected: native `credssp.dll` + `TSpkg.dll` (operator-supplied, not committed).
  - `TSpkg.dll` is an LSA package for lsass. It imports 10 undocumented `LSASRV.dll`
    internals (including Remote Credential Guard), plus `MSASN1` (Wine: 7 of 266 exports),
    `NTASN1` and `dsreg` (absent in Wine).
  - `credssp.dll` only forwards to it.
- Not yet: Kerberos-specific mutual-authentication flags (`CREDSSP_SERVER_AUTH_NEGOTIATE`),
  smart-card/certificate credentials, server side (`AcceptSecurityContext`),
  Remote Credential Guard / Restricted Admin, `CredWriteDomainCredentialsW`
  ("Remember my password").
- Tests:
  - `tests/static/credssp-client` (in `run-regression.sh`): both credential forms,
    server-auth flags for an untrusted cert, a wrong password rejected. Baseline fails,
    patched passes.
  - `tests/security/credssp/run.sh`: genuine mstsc, credential prompt, delegation,
    MCS over the channel.
  - Fixture: `fake-rdp-credssp.py` (pyspnego; verifies NTLMv2 over the raw blob as
    Windows does, R-019).
