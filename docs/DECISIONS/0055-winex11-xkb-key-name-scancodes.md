# ADR-0055: Use XKB key names for keys without a scancode, including AltGr (patch 0045)

- Status: accepted
- Date: 2026-11-25
- Symptom (V): same report as ADR-0054. AltGr+Q (standard German) or AltGr+L (German
  Macintosh) types @ locally but not in the session. On unmodified Wine 11.0 the AltGr
  key reaches Windows applications as a spare virtual key (0xE4) with scancode 0x68 and
  no extended flag, and genuine mstsc sends scancode 0x68 to the server, which ignores
  it: the server sees a plain Q or L (EXP-074). The dead acute key of the German layouts
  (AE12) likewise gets an arbitrary scancode, because Wine's German table has no entry for
  it.
- Cause (V): with most European XKB layouts the right Alt key produces
  `ISO_Level3_Shift` (0xFE03). That keysym is outside the 0xFFxx range of winex11's
  non-character tables and produces no character, so `X11DRV_InitKeyboard()` finds no
  scancode for it and assigns one from 0x60 on. The same happens to any character key
  the layout table does not list.
- Decision: for keys that are still without a scancode at the end of
  `X11DRV_InitKeyboard()`, look up the XKB key name (`XkbGetNames`) and use the Windows
  scancode of that physical position (TLDE, AE01–AE13, AD01–AD12, AC01–AC12, AB01–AB11,
  BKSL, LSGT, modifiers, RALT = 0xE038, …). Only unknown names keep arbitrary scancodes.
  Windows scancodes name key positions, as xkeyboard-config key names do; FreeRDP/Remmina
  and Wine's own Wayland driver also derive scancodes from the physical key.
  Keys that already had a scancode (from the non-character or layout tables) are not
  touched, so user remaps (e.g. `caps:escape`, Alt/Win swaps) and Wine's table choices
  stay as they were.
- Not chosen: mapping AltGr to `VK_RMENU` and synthesizing the fake left Control that
  Windows adds for `KLLF_ALTGR` layouts. That is the full Windows model, but winex11's
  `ToUnicodeEx` returns no character for Ctrl+Alt and VK_MENU turns keys into
  `WM_SYSKEYDOWN`, so local AltGr typing (the part that works today) would break. The
  virtual key is left as it was; only the scancode (0x38 + extended flag) changes. A
  Windows server with an AltGr layout treats the right Alt key as AltGr, so the remote
  side types @ (verified at the protocol level; the server interpretation is documented
  Windows behavior).
- Limitations (H/I): layouts absent from Wine's tables whose characters match other
  table entries (e.g. German Neo 2) still get table-guessed scancodes for some keys; an
  `ISO_Level3_Shift` bound to another key sends that key's physical scancode, as
  FreeRDP does. The keyboard layout mstsc advertises comes from Wine's locale, not from
  XKB (R-032); that is unchanged. Confirmed live on a Windows session (EXP-074).
- Risk/rollback: affects only keys that previously had meaningless scancodes ≥ 0x60.
  Roll back patch 0045 if a keymap with nonstandard key names is found to misbehave.
- Tests: `tests/static/keyboard-layout` and `tests/launch/test-keyboard.sh`.
