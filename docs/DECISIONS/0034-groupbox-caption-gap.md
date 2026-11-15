# ADR-0034: Space between a themed group box frame and its caption (patch 0031)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-047, operator): the top line of the "Logon settings" and "Connection
  settings" frames runs into the caption.
- Measured on the operator's screenshots (V):
  - Windows Server 2022: the line stops 2 pixels before the first glyph and resumes 3 pixels
    after the last.
  - Wine: 1 pixel and 0 pixels.
- Cause (V): `GB_ThemedPaint` excludes and refills exactly the caption's
  `DrawText(DT_CALCRECT)` rectangle, so the frame line reaches the glyphs.
- Decision:
  - Exclude and fill the text rectangle widened by 2 pixels on each side.
  - The caption itself stays where it was; its position already matches Windows.
  - Result with Microsoft Sans Serif 8pt: gaps of 3 and 2 pixels, within one pixel of
    Windows on each side (I: the exact native rule is unknown).
- Tests:
  - `tests/static/dialog-layout` (groupbox.exe, v6 manifest) measures both gaps on the
    frame line: at least 2 pixels each.
  - The test needs the genuine `micross.ttf`, else it is skipped. With Tahoma the measured
    text rectangle extends past the glyphs and hides the problem.
  - Fails on baseline, passes on patched.
  - comctl32 `button` conformance: 11998 tests, 0 failures on both runtimes.
  - Genuine mstsc: both frames leave space around their captions.
