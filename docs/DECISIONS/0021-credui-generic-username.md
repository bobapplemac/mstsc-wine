# ADR-0021: The credential dialog keeps generic user names as typed (patch 0017)

- Status: accepted. 2026-11-14.
- Symptom (V, EXP-035): a user name typed without a domain ("Administrator") came back
  as "Enter your credentials\Administrator". mstsc saved that name and offered it
  next time. After editing the saved credentials it came back as
  "Update your credentials\Administrator". On Windows the name stays as typed.
- Cause (V):
  - `CredUIPromptForWindowsCredentialsW` (patch 0014) shows Wine's classic dialog and
    passes the caption as its target name.
  - On OK, the classic dialog completes any user name without `\` or `@` with
    `target\`, even for `CREDUI_FLAGS_GENERIC_CREDENTIALS`.
- Decision: complete user names only for domain credentials, that is when
  `CREDUI_FLAGS_GENERIC_CREDENTIALS` is not set.
  - Generic credentials are free-form, so they come back as typed.
  - `CredUIPromptForWindowsCredentialsW` always uses generic credentials, so its callers
    get the name as typed, as with Windows' prompt (V for mstsc).
  - `CredUIPromptForCredentialsW` callers that ask for domain credentials keep Wine's
    existing completion (I: matches Windows' documented behaviour for domain
    credentials).
- Tests:
  - `tests/static/credui-prompt`, in the regression suite (own Xephyr `:9`): types
    "Administrator", and the caller unpacks the buffer without a domain buffer, as mstsc
    does. Without the patch it gets "Enter your credentials\Administrator".
  - Wine `credui_test`: no failures on either runtime.
- Note: names saved before this fix keep the wrong domain. The user must edit them once
  (Edit or Delete on mstsc's General tab).
- Alternative rejected: passing an empty target from `CredUIPromptForWindowsCredentialsW`.
  The classic dialog uses the target for its message and title, and would still complete
  names with a bare `\`.
