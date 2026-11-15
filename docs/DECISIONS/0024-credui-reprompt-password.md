# ADR-0024: No pre-filled password when asking again after a failed logon (patch 0021)

- Status: accepted. 2026-11-14.
- Symptom (V, EXP-039): after a wrong password, mstsc's re-prompt shows the old password
  as dots. On Windows the password field is empty (V, operator).
- Cause (V, `+credui`): mstsc calls `CredUIPromptForWindowsCredentialsW` with
  `SEC_E_LOGON_DENIED` and the buffer from the first prompt, which holds the old user name
  and password. Our implementation (patch 0014) filled both fields from it.
- Decision: when the caller passes an error, fill in the user name only, and clear the
  unpacked password. Without an error both fields are still filled from the input buffer
  (H: Windows does the same; unverified, R-023).
- Tests:
  - `tests/static/credui-prompt` "reprompt" mode passes a packed user name and password
    with `SEC_E_LOGON_DENIED`, checks that the password field is empty, then cancels.
    Fails without the patch (`PASSWORD FILLED`).
  - Genuine mstsc, wrong password (offline): user name kept, password empty, focus in the
    password field.
