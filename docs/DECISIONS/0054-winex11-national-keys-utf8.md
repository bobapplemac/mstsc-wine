# ADR-0054: Match national characters to Wine's layout tables in UTF-8 locales (patch 0044)

- Status: accepted
- Date: 2026-11-25
- Symptom (V): first external report (Debian 13, MATE, X11, Apple MacBook Air, XKB
  "German (Macintosh, no dead keys)" with Right Alt as AltGr). ä, ö, ü, @ and | work in
  mstsc's local dialog but not in the RDP session; ASCII letters, Y and Z included, work.
  Reproduced without mstsc on unmodified Wine 11.0 (EXP-074): with that layout, or the
  standard German one, ü ö ä ß reach Windows applications with scancodes 0x62 0x63 0x64
  0x60 instead of 0x1A 0x27 0x28 0x0C. Genuine mstsc forwards exactly those values to the
  RDP server (`tests/launch/test-keyboard.sh`), where no key has them.
- Cause (V): winex11 builds its keycode → scancode/virtual-key tables by comparing each
  keycode's characters with the built-in layout tables, which are single-byte (Latin-1,
  KOI8, …) strings. `XkbTranslateKeySym()` cannot put a non-ASCII character in one byte in
  a UTF-8 locale. `X11DRV_KEYBOARD_DetectLayout()` then falls back to the low byte of the
  keysym (equal to the Latin-1/KOI8 code by design of the X keysym tables), but
  `X11DRV_InitKeyboard()` substituted 0. Detection picks the right table, but every key
  carrying a national character fails to match it, gets a spare virtual key, and is
  later given an arbitrary scancode from 0x60 on. Local typing is unaffected, because
  characters come from X (ToUnicodeEx/XIM), which is why the dialog works.
- Decision: use the same low-byte fallback in `X11DRV_InitKeyboard()`. General: it fixes
  every layout whose national characters are in Wine's tables (French, Swiss, Russian,
  Brazilian, … were measured, EXP-074), with no layout-specific code.
- Risk/rollback: the keys concerned now get their table's scancodes and virtual keys
  instead of spare ones, which is what the table always intended and what Windows sends.
  Keys that matched before are unchanged (measured for de, de Macintosh, us, us Dvorak,
  gb, fr, ch, ru, jp, br). Roll back patch 0044 if an application is found to depend on the
  spare virtual keys.
- Tests: `tests/static/keyboard-layout` (regression suite; fails on 11.0, passes patched)
  and `tests/launch/test-keyboard.sh` (genuine mstsc against a local RDP server).
