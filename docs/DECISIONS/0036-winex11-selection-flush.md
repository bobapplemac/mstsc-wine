# ADR-0036: Flush after acquiring the X11 selection (patch 0033)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-049): after a Windows program copies, X11 clients see no clipboard owner
  (`xclip -o` fails). Worse, a later copy in a Linux program is overridden by Wine.
- Cause (V):
  - winex11's `acquire_selection()` runs when explorer's clipboard thread handles `WM_CLIPBOARDUPDATE`.
  - In Wine 11.0, `ProcessEvents` (and its trailing `XFlush`) only runs when the X connection has input
    (QS_DRIVER), so `XCreateWindow` + `XSetSelectionOwner` stay in Xlib's buffer.
  - `xwininfo` confirmed it: the selection window never existed on the server.
  - The requests went out with the next X event on that connection, usually the XFixes notification for another
    client's copy. Wine then took the selection back from that client.
  - Also present in unmodified Wine 11.0 (reproduced on `build/install-wine-11.0`).
- Decision: `XFlush(display)` at the end of `acquire_selection()`. Other requests on that path are synchronous
  (they wait for replies) or run inside the event loop.
- Tests: `tests/static/ole-clipboard` covers both directions: `OleSetClipboard` delayed rendering pasted with
  `xclip`, and `xclip` text read by `OleGetClipboard`. Fails on baseline, passes on patched. Also covered by
  `tests/launch/test-clipboard.sh`.
