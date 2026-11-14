# ADR-0015: Seed the Windows default server-authentication level (launcher, interim)

- Status: accepted (interim, until CredSSP exists in Wine). 2026-11-14.
- Defect (V):
  - With default settings (empty `Default.rdp`), the genuine mstsc connected to a
    server with an untrusted self-signed certificate **without warning** (EXP-025).
  - The Advanced tab showed "If the actual verification does not meet minimum policy
    requirements: Connect and don't warn me".
- Cause (V, EXP-027):
  - At startup mstsc calls `QuerySecurityPackageInfoW(L"CREDSSP")`. Wine has no CredSSP
    package, so mstsc chooses its legacy, pre-CredSSP default: connect, don't warn.
  - With a test-only provider advertising `CREDSSP`, the same mstsc shows "If server
    authentication fails: Warn me". That matches Windows: operator-confirmed default,
    and public reports (I).
  - Wine's certificate checks are correct: chain error `CERT_TRUST_IS_UNTRUSTED_ROOT`,
    SSL policy `CERT_E_UNTRUSTEDROOT`. With `authentication level:i:2` the genuine
    warning appears (EXP-026).
- Decision:
  - `mstsc-wine run` writes `authentication level:i:2` (UTF-16, as mstsc writes it) to
    `Documents\Default.rdp` **only if that file is missing or empty**.
  - A level the user saves later (mstsc rewrites `Default.rdp`) is never overridden.
    `.rdp` files and policy still take precedence, as on Windows.
- Rejected:
  - A stub CredSSP package: mstsc would then request NLA (PROTOCOL_HYBRID). That breaks
    servers that pick it, and they would fail without a real implementation.
  - Enforcing via policy (`AuthenticationLevel` under Policies): stronger than Windows'
    default and not user-changeable.
- Removal: when CredSSP lands, mstsc picks "Warn me" itself; drop `seed_default_rdp`.
- Test: `tests/security/cert-prompt/run.sh`. It needs Xephyr and a prefix with mstsc, and
  uses a local fake endpoint (`fake-rdp-tls.py`: X.224 + TLS only, no RDP session).
  - Fails without the seeding, passes with it.
  - Also checks that a user-saved level 0 is respected.
