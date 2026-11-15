# ADR-0025: Kerberos EncryptMessage/DecryptMessage use Windows' token layout (patch 0022)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-040): CredSSP with Kerberos. The server accepts the Kerberos
  authentication, then rejects the client's `pubKeyAuth`: "Token header is malformed or
  corrupt" (MIT acceptor).
- Cause (V, code reading):
  - For a context without DCE style, Wine's Kerberos `SpSealMessage` called `gss_wrap` and
    split the output: the first *n* bytes, which start with the token header, went into the
    data buffer, and the rest into the token buffer. `SpUnsealMessage` joined them back in
    that order.
  - So only Wine could read what Wine sealed. Windows, and CredSSP, send token + data.
- Windows' layout (V for interop; spec MS-KILE 3.4.5.4, RFC 4121 RRC):
  - The token buffer holds the wrap token header, with the trailer rotated into it (RRC).
  - The data is encrypted in place.
  - Token + data is then an ordinary wrap token for the peer.
- Decision:
  - Seal with `gss_wrap_iov`, using a HEADER buffer and a DATA buffer but no TRAILER buffer.
    MIT then puts the trailer into the header (RRC), as Windows does.
  - This applies to enctypes without padding (AES). Others (RC4) keep the old path (H: they
    need Windows' padding buffer, which is not implemented).
  - Unseal joins token + data, in that order. The result is the same whatever the split
    point, so a peer whose `EC` differs still works. A plaintext longer than the data
    buffer is rejected.
  - `SECPKG_ATTR_SIZES` reports the real header length as `cbSecurityTrailer` (60 for AES)
    instead of a fixed 64, so the data CredSSP splits off is never shorter than the
    plaintext.
  - DCE-style contexts are unchanged.
- Tests:
  - `tests/security/kerberos/run.sh` (regression suite): CredSSP with Kerberos against a
    throwaway MIT realm. Fails without the patch.
  - Live (EXP-041): a domain RDP host accepted the Kerberos `pubKeyAuth`, and the client
    decrypted the server's reply.
