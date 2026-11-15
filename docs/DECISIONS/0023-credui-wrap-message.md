# ADR-0023: The credential dialog wraps long messages (patch 0020)

- Status: accepted. 2026-11-14.
- Symptom (V, EXP-039): mstsc's re-prompt message is cut off after one line ("The
  credentials that were used to connect to localhost did").
- Cause (V): Wine's classic credential dialog has a message control one line high
  (8 dialog units). Longer text wraps inside it and the lines after the first are hidden.
- Decision:
  - When the dialog opens, measure the message with `DrawTextW(DT_CALCRECT | DT_WORDBREAK)`
    in the control's font.
  - If it needs more room, make the control taller, move every control below it down by the
    same amount, and grow the dialog by that amount. Short messages keep today's layout.
  - credui now imports gdi32 (`SelectObject`).
- Tests:
  - `tests/static/credui-prompt` passes mstsc's message for a long host name and checks,
    in the dialog, that the text fits, does not cover the user name field, and the OK button
    stays inside the dialog. Fails without the patch (needs 39 pixels, has 13).
  - `tests/lib/enter-credentials.sh` now clicks relative to the dialog's bottom edge, so it
    still finds the fields when the dialog grows.
  - Genuine mstsc, wrong password (offline): the message shows in full on two lines.
- Alternative rejected: a taller fixed message control. It would leave a gap for short
  messages and still cut off long host names.
