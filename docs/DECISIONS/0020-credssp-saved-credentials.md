# ADR-0020: CredSSP delegates saved credentials when the caller supplies none (patch 0018)

- Status: accepted. 2026-11-14.
- Symptom (V, EXP-034): with "Remember my password", the next connection skips mstsc's
  prompt, but the server shows its own Windows logon screen.
- How mstsc saves and reuses a password (V, EXP-034/036, static analysis of `mstscax.dll`):
  - It saves only after the server reports a completed logon (`OnLoginComplete`, then
    `PersistTsCredentialsAndUsernameHint` / `SaveCreds`).
  - It saves with `CredGetSessionTypes` and `CredWriteW`: `CRED_TYPE_DOMAIN_PASSWORD`,
    target `TERMSRV/<host>`, `CRED_PERSIST_LOCAL_MACHINE`. Wine already implements both.
    `CredWriteDomainCredentialsW` (listed as the gap in R-006) is not on this path.
  - On the next connection, `CredReadW(TERMSRV/<host>, DOMAIN_PASSWORD)` only tells
    mstsc that a saved credential exists. It then calls
    `AcquireCredentialsHandle("CREDSSP")` with submit type 51 and **no** SPNEGO
    credentials.
  - It relies on CredSSP to find the saved password. Windows does this in LSA, under the
    default policy (AllowSavedCredentials and AllowSavedCredentialsWhenNTLMOnly, not
    configured = allowed for `TERMSRV/*`).
- Cause (V, EXP-036): our CredSSP (patch 0015) acquired Negotiate with no identity in that
  case. NTLM then ran as the current Linux user, and the server rejected it or fell back
  to its own logon screen.
- Decision:
  - When the credential handle has no user name and the target SPN starts with
    `TERMSRV/`, the new context reads the saved `CRED_TYPE_DOMAIN_PASSWORD` credential
    named after the SPN.
  - It splits `DOMAIN\user`, acquires its own Negotiate handle, authenticates with it,
    and delegates it in `TSPasswordCreds`.
  - The saved credential belongs to the context, so one credential handle can serve
    different targets.
- Scope and limits:
  - Only `TERMSRV/` targets, matching Windows' default policy. Group-policy lists of
    other SPNs and wildcards are not read (I: not needed for mstsc).
  - Exact SPN match only. Windows also matches `TERMSRV/*` wildcard entries (H), which
    mstsc does not create.
  - Wine has no LSA boundary: the password is read in the client process. That is
    already how Wine stores and returns `CRED_TYPE_DOMAIN_PASSWORD` blobs (`CredReadW`).
- Tests:
  - `tests/static/credssp-client` "saved" mode, in the regression suite: stores the
    credential like mstsc, passes no credentials, and the server verifies the delegated
    password. Fails without the patch (`SEC_E_INVALID_TOKEN` 0x80090308).
  - `tests/security/credssp/run.sh` phase 2: the genuine mstsc reconnects without a
    prompt, and the server confirms the saved password was delegated.
  - Wine `secur32_test`: same results on both runtimes (one pre-existing schannel
    failure).
- Alternatives rejected:
  - Making mstsc pass explicit credentials is impossible: the binary is genuine and
    unmodified.
  - Implementing `CredWriteDomainCredentialsW`/`CredReadDomainCredentialsW` does not help:
    mstsc does not call them on this path (no stub exception in `+seh` traces).
