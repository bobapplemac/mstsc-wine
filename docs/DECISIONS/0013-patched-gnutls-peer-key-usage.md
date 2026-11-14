# ADR-0013: Private patched GnuTLS + Schannel client key-usage tolerance (patch 0010)

- Status: accepted. Operator-approved 2026-11-14 ("approve the relaxation"; "ok shipping our own patched GnuTLS").
- Defect (V):
  - Default self-signed RDP server certificates have keyUsage keyEncipherment +
    dataEncipherment, with no digitalSignature. Servers still pick ECDHE_RSA, which signs
    the key exchange with that key.
  - GnuTLS aborts with `GNUTLS_E_KEY_USAGE_VIOLATION`, and mstsc reports "An
    authentication error has occurred". Windows Schannel accepts these certificates (I:
    mstsc connects to such servers on Windows).
- Why not stock GnuTLS (V, EXP-022, GnuTLS 3.8.9 source):
  - The peer-certificate exemption (`session->internals.allow_key_usage_violation`) is
    only reachable through `%COMPAT` or `gnutls_session_enable_compatibility_mode()`.
  - Both also disable Extended Master Secret and Encrypt-then-MAC; measured EMS=0.
  - `%FORCE_SESSION_HASH` cannot restore EMS: the handshake fails.
  - `%DEBUG_ALLOW_KEY_USAGE_VIOLATIONS` only covers the *local* certificate.
- Decision:
  - **GnuTLS** (`patches/gnutls/0001-…`): `%DEBUG_ALLOW_KEY_USAGE_VIOLATIONS` also sets
    `_allow_key_usage_violation`, which `gnutls_priority_set()` copies to the session.
    Nothing else changes, and sessions that don't request the keyword are unaffected.
  - **Build** (`tools/build-gnutls.sh`): from Debian `gnutls28 3.8.9-3+deb13u4`. The
    signed `.dsc` is checked against the Debian keyring and the hashes are verified. All 50
    Debian patches, including the CVE fixes, plus ours. The library alone; no tools.
  - **Install**: into `RUNTIME/lib/mstsc-wine/`. The launcher prepends it to
    `LD_LIBRARY_PATH`, so only the mstsc-wine runtime uses it; host applications don't.
  - **Wine** (patch 0010): Schannel adds the keyword to *client* sessions only. If a GnuTLS
    rejects the keyword, it falls back to the previous priority string. With stock GnuTLS
    the keyword is accepted but has no peer effect, so behaviour is unchanged.
- Security notes:
  - Certificate trust (chain, name, expiry) is unaffected. mstsc validates it itself and
    shows its certificate prompt.
  - EMS stays negotiated: measured EMS=1 with the patched library.
  - Encrypt-then-MAC is untouched; verified by code reading only. A CBC test against
    `openssl s_server` failed for unrelated reasons.
- Maintenance: rebuild whenever Debian publishes a gnutls28 security update; bump `DEB`
  in the script. `mstsc-wine doctor` reports whether the bundled library is present.
- Tests: `tests/static/schannel-keyusage` (in `run-regression.sh`) fails on baseline and
  passes on patched with the bundled GnuTLS. End to end: the first interactive session to
  a Windows host (EXP-023).
