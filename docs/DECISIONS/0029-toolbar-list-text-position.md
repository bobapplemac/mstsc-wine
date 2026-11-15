# ADR-0029: List-style toolbar text starts right after the bitmap (patch 0026)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-042): mstsc's expander reads "Show Optio..." and "Hide Optio..." instead of
  "Show Options" and "Hide Options".
- Cause (V):
  - The expander is a `TBSTYLE_LIST` toolbar. Its one `BTNS_AUTOSIZE` button has a 21x17
    bitmap and the text "Show &Options ". mstsc sets `TB_SETPADDING` cx = 0.
  - `TOOLBAR_MeasureButton()` sizes the button as `2*cxedge + bitmap + iListGap + text + padding.cx`.
  - `TOOLBAR_DrawButton()` started the text at `cxedge + bitmap + iListGap + 2`.
  - With no horizontal padding, the text rectangle was 2 pixels narrower than the text (70
    vs 72), so `DT_END_ELLIPSIS` cut it.
- Evidence for the Windows position (V, reference screenshot from Windows Server 2022):
  - On Windows the label starts 23 pixels after the left edge of the arrow glyph.
  - In Wine it started 25 pixels after.
  - So Windows starts the text at bitmap + list gap, without the extra 2 pixels.
- Decision:
  - Drop the `+ 2`, so the text rectangle is exactly what the measurement reserved.
  - Keep the bitmap where it is. On Windows the whole button content sits 2 pixels further
    left (cxedge), but one screenshot with padding 0 is not enough to change the bitmap
    position for every padding (I).
- Effect on other applications: in every list-style toolbar, text moves 2 pixels left and
  gains 2 pixels of room.
- Tests:
  - `tests/static/dialog-layout` (toolbar.exe) draws the expander button at its own size and
    200 pixels wide, without antialiasing, and compares the label. Fails on baseline (label
    cut), passes on patched.
  - Genuine mstsc shows "Show Options" and "Hide Options" in full.
