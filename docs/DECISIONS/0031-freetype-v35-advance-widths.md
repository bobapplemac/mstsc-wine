# ADR-0031: Use the v35 TrueType interpreter for Windows advance widths (patch 0028)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-044): mstsc's message "The computer name field is blank. Enter a full
  remote computer name." wraps before "computer" in Wine and after it on Windows Server 2022.
- Cause (V):
  - The dialog text is `MS Shell Dlg` 8pt. Both Windows and Wine map that to Microsoft Sans
    Serif (genuine `micross.ttf`, -11 px). The face is right.
  - Wine measures the line 309 pixels wide; Windows draws it 294 pixels wide (reference
    screenshot). "computer" alone is 46 vs 44 pixels.
  - Windows GDI uses the advance widths of the hinted glyphs (the font's bytecode, applied
    horizontally too). FreeType's default v40 interpreter ignores horizontal hinting.
  - Wine selected v35 only for FreeType older than 2.8.1.
- Decision:
  - Select the v35 interpreter in `init_freetype()` unless `FREETYPE_PROPERTIES` already
    sets an interpreter version.
  - Users can still choose v40 (`FREETYPE_PROPERTIES=truetype:interpreter-version=40`).
- Result (V): the line measures 294 pixels, as on Windows, and the message wraps after
  "computer". Text positions in the collapsed dialog match the reference to within a pixel.
- Effect: TrueType fonts with bytecode hints (the genuine Microsoft fonts) are now fully
  hinted in both directions in all Wine text, as in Windows GDI. Fonts without hints (Wine's
  own) are unchanged.
- Alternative rejected: `FREETYPE_PROPERTIES` in the launcher. It would miss `launcher exec`
  and any other way the runtime is started, and it is a Wine behaviour, not a launcher one.
- Tests:
  - `tests/static/dialog-layout` (textwidth.exe) measures mstsc's line in Microsoft Sans
    Serif -11 px: at most 294 pixels.
  - The test needs the genuine `micross.ttf` in `Windows/Fonts` (not committed) and is
    skipped without it. Fails on baseline (309), passes on patched (294).
