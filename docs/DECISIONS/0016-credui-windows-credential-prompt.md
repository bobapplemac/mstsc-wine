# ADR-0016: credui Windows credential prompt and packed credentials (patch 0014)

- Status: accepted. 2026-11-14.
- Defect (V): with NLA, mstsc calls `CredPackAuthenticationBufferW` (to prefill),
  `CredUIPromptForWindowsCredentialsW` and `CredUnPackAuthenticationBufferW`. All three
  were Wine stubs. The prompt returned `ERROR_CALL_NOT_IMPLEMENTED`, and mstsc showed
  "An authentication error has occurred (Code: 0x80070078)".
- Decision:
  - **Packing:** packed credentials use `KERB_INTERACTIVE_UNLOCK_LOGON` with
    offset-based strings (`MessageType` `KerbInteractiveLogon`). A `DOMAIN\user` name is
    split into domain and user. Unpacking without a domain buffer returns `DOMAIN\user`.
    With `CRED_PACK_PROTECTED_CREDENTIALS` it returns a `CredProtect`ed password
    (ADR-0017). mstsc passes the packed buffer straight to the CredSSP package (ADR-0018).
  - **Prompt:** reuses Wine's existing `CredUIPromptForCredentialsW` dialog: user name,
    password and the "Remember my password" box for `CREDUIWIN_CHECKBOX`. It never stores
    credentials itself; storing is the caller's choice. The output buffer comes from
    `CoTaskMemAlloc`, as documented.
- Not native: Windows' prompt is the credential-provider UI (credui + LogonUI
  framework). That is far heavier than this dialog, so the prompt looks like Wine's rather
  than Windows'. mstsc's own text appears in it ("These credentials will be used to
  connect to …").
- Tests: credui conformance `test_CredPackAuthenticationBuffer` (round trip, sizes). End to
  end: `tests/security/credssp/run.sh`, EXP-028/030.
