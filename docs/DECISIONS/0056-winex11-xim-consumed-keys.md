# ADR-0056: Report keys consumed by Xlib's input method as processed keys (patch 0046)

- Status: accepted
- Date: 2026-11-26
- Symptom (V): after patches 0044/0045 the reporter of issue #1 (`setxkbmap -query`:
  rules evdev, model apple, layout de, option terminate:ctrl_alt_bksp, i.e. German with
  dead keys) can type everything except the dead ´/` key left of Backspace: in the RDP
  session it "does nothing", so é, ò … cannot be composed. Remmina composes them.
- Not the scancode (V): with no X input method, AE12 already reaches Windows applications
  as scancode 0x0D down and up (patch 0045), and genuine mstsc sends the dead-key
  sequences in full to a local RDP server. Earlier test runs had no input method only
  because the inherited `XMODIFIERS=@im=ibus` names a server that does not exist on the
  nested display.
- Cause (V): a desktop session always has an X input method: Xlib's own compose-based
  one when `XMODIFIERS` is unset or `@im=none` (MATE without ibus), or a server such as
  ibus. winex11 passes every event to `XFilterEvent()` and drops it when that returns
  TRUE. Xlib's input method consumes the dead key press and the press of the key composed
  with it, then hands back the result as an event with keycode 0 (no scancode). Windows
  applications therefore got only the two key releases and a VK_NONAME key with
  scancode 0 carrying é. mstsc forwards only real keys: the server received two releases
  and nothing to compose (V, `tests/launch/test-keyboard.sh` with `MSTSC_KBD_CLIENT_XIM`).
  The local dialog was fine, because WM_CHAR é still arrives.
- Decision: follow what Windows does with keys an IME processes. They still reach
  low-level hooks and raw input with their virtual key and scancode, and the window gets
  them as `VK_PROCESSKEY`, so they produce no characters themselves; the IME supplies the
  text. winex11 now sends a key event that Xlib's input method consumed as hardware input
  (`X11DRV_FilteredKeyEvent`), remembers the key press per thread, and claims it in a new
  `ImeProcessKey` driver entry point, so that win32u's existing `ImmProcessKey` path turns
  its message into `VK_PROCESSKEY`. Unclaimed entries expire after 2 s; earlier entries
  are dropped when a later one is claimed (messages are processed in order). The event is
  copied before filtering, because Xlib's input method clears the keycode of the event it
  consumes. The composed text keeps its existing path.
- Scope: only Xlib's in-process input method (`@im=none`, `@im=local`, or no `@im` name,
  mirroring Xlib's `_XimCheckIfLocalProcessing`). Input method servers (ibus, fcitx, …)
  consume every key and forward back, asynchronously, an identical copy of those they do
  not use; reporting the consumed events too doubled every key (V, ibus on a nested
  display). Their events keep the existing handling.
- Not chosen: disabling XIM for mstsc (breaks local dead keys in the dialog: Wine's own
  `ToUnicodeEx` has no dead-key state); synthesizing characters or Unicode events (the
  remote layout must compose, as from a Windows client); an mstsc-specific workaround.
- Limitations (V/I): with an input method server that composes (e.g. an ibus engine with
  dead keys), consumed keys still do not reach Windows applications (I; upstream Wine has
  the same `XFilterEvent` handling). An ibus that does not compose forwards every key
  back, and those keys reach mstsc and the server as before (V). Workaround for users of a
  composing server: run mstsc with `XMODIFIERS=@im=none` (Xlib's input method, the
  configuration patch 0046 was tested and confirmed live with); the server's own input
  (e.g. CJK) is then unavailable in mstsc's local dialogs. Documented in README.md. Locally, acute + space gives `'` (X's Compose table)
  where Windows gives ´; unchanged and irrelevant remotely, where the server composes.
- Risk/rollback: affects only key presses that Xlib's input method consumes, i.e. dead
  keys and compose sequences; other keys are untouched (all keyboard tests unchanged).
  Roll back patch 0046 if an application mishandles VK_PROCESSKEY for dead keys.
- Tests: `tests/static/keyboard-layout` (de-apple-im: six dead-key sequences, every key
  down and up at the hook, 12 VK_PROCESSKEY, composed text once; de-mac-im: no change for
  ordinary keys; fails on 11.0), `tests/launch/test-keyboard.sh` layout `de-apple-im`
  (server receives all key-downs and key-ups). Live: a real Windows session with German
  active types `éáò´`âä` (EXP-075).
