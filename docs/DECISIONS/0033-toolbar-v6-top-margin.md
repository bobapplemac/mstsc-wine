# ADR-0033: No top margin for non-flat toolbars in comctl32 v6 (patch 0030)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-046, operator): hovering over **Show Options** / **Hide Options** draws a
  hot-tracking frame whose bottom edge is cut off. The label also sits about 2 pixels lower
  than the Connect button's; on Windows Server 2022 they share a baseline (operator's screenshots).
- Cause (V):
  - The expander is a `TBSTYLE_LIST | TBSTYLE_TRANSPARENT` toolbar without `TBSTYLE_FLAT`
    (style 0x5603904c). It is 23 pixels tall, as is its button.
  - Wine gives toolbars without `TBSTYLE_FLAT` a 2-pixel top margin (`TOP_BORDER`), so the
    button spanned y 2–25. Its frame's bottom edge fell outside the window.
  - Wine's toolbar tests state that the top margin is recomputed from the style only in
    comctl32 below v6. The size tests that check the margin run against v5 only.
  - On Windows (v6) the content is 2 pixels higher than in Wine, so the button starts at the top.
- Decision: in the comctl32 v6 build (`__WINE_COMCTL32_VERSION == 6`), the default top
  margin is 0 for every style. v5 keeps `TOP_BORDER` for non-flat toolbars.
- Confidence: the v6 layout is inferred from the screenshots and the test comment (I). It
  matches Windows for mstsc's toolbar.
- Tests:
  - `tests/static/dialog-layout` (tbmargin.exe, v6 manifest): the button must lie inside a
    toolbar as tall as itself. Fails on baseline ((0,2)-(101,25) in 23 pixels), passes on
    patched ((0,0)-(101,23)).
  - comctl32 `toolbar` conformance: 2195 tests, 0 failures on both runtimes.
  - Genuine mstsc: the hover frame is complete.
