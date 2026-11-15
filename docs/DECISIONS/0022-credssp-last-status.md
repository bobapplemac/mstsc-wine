# ADR-0022: CredSSP leaves the server's NTSTATUS as the last status on failure (patch 0019)

- Status: accepted. 2026-11-14.
- Symptom (V, operator on `<test-host>`; EXP-038 offline): a wrong password still
  connects, and the server then shows its own Windows logon screen. On Windows, mstsc
  says the credentials did not work and asks again.
- How mstsc decides (V: static analysis of `mstscax.dll` plus a winedbg breakpoint):
  - After the NLA handshake fails, mstscax's security filter reads
    `ntdll!RtlGetLastNtStatus()` and keeps it as `lastStatusError`.
  - `SslFilter::MapErrorCode(hr, lastStatusError)` maps `SEC_E_LOGON_DENIED` together
    with `STATUS_LOGON_FAILURE` (or `SEC_E_LOGON_DENIED` itself) to "logon failed":
    "Your credentials did not work" and a new prompt.
  - It maps other statuses to more specific reasons (no such user, disabled, expired,
    locked out, must change password, and so on).
  - Anything unrecognised counts as a generic failure. mstsc then retries the connection
    without NLA (`requestedProtocols=1`). A server that does not require NLA accepts that
    retry and shows its own logon screen.
- Cause (V): our CredSSP returned `SEC_E_LOGON_DENIED` but never set the thread's last
  status. mstsc read whatever an earlier call had left there (`0xC0000034` in the
  fixture).
- Decision:
  - Keep the server's `TSRequest.errorCode`, when it is an NTSTATUS, in the context.
  - When `InitializeSecurityContextW` fails, call `RtlNtStatusToDosError` on it as the
    last step. That sets `TEB->LastStatusValue`, as Windows' SSPI does.
  - The returned `SECURITY_STATUS` mapping is unchanged.
- What the server sends (V/I):
  - A Windows server sends `STATUS_LOGON_FAILURE` (V, EXP-030).
  - pyspnego sends the HRESULT `0x8009030C` instead, so the test server now converts it
    to the Windows value.
  - Failures detected on the client side, and HRESULT error codes, leave the last status
    untouched (I: Windows' behaviour there is unverified).
- Tests:
  - `tests/static/credssp-client`: a wrong password must leave the last status at
    `0xC000006D`. It fails without the patch.
  - `tests/security/credssp/run.sh` phase 3, with the genuine mstsc: "Your credentials
    did not work" is shown and there is no retry without NLA. Without the patch mstsc
    retries with `requestedProtocols=1`.
  - Wine `secur32_test`: same results as before.
- Known cosmetic differences from Windows (I): the re-prompt's message is cut off after
  one line ("…to connect to localhost did"), and the old password is pre-filled. Both
  are in Wine's classic credential dialog, not in CredSSP.
- Operator confirmation (V): against `<test-host>` a wrong password now gives mstsc's re-prompt instead of the server's logon screen.
