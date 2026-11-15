# ADR-0030: Invalidate a child moved into an invalid part of its parent (patch 0027)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-043): after **Show Options**, the Connect and Help buttons are missing.
  The buttons exist and are visible (`IsWindowVisible`), are at the right place, and have
  no pending update region. Hovering repaints them.
- Cause (V, reproduced on the unmodified Wine 11.0 with `tests/static/dialog-layout/expand.c`):
  - mstsc animates the expansion. A worker thread grows the dialog in about six steps
    (`SetWindowPos` with `SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_NOSENDCHANGING`).
  - After each step, the dialog's `WM_WINDOWPOSCHANGED` handler moves the toolbar and the
    two buttons to the new bottom edge (`SWP_NOSIZE|SWP_NOZORDER`).
  - Each step exposes a strip at the bottom of the dialog. The strip is invalid in the dialog.
  - The buttons move into that strip with their bits copied, so the server considers them
    valid there.
  - The dialog has no `WS_CLIPCHILDREN`. When it then paints its invalid strip, it paints
    over the buttons, and nothing invalidates them.
  - Wine already invalidates children under a non-`WS_CLIPCHILDREN` parent when the parent
    is invalidated while they are in place (`redraw_window`). It did not when a child moves
    into a part of the parent that is already invalid.
  - Without message processing between steps there is no paint in between and the bug does
    not show. That is why only the animated mstsc dialog showed it.
- Decision:
  - In the server's `set_window_pos`, after a visible child's window rectangle changes
    (unless `SWP_NOREDRAW`), intersect its new rectangle with the parent's update region,
    if the parent has no `WS_CLIPCHILDREN`.
  - Invalidate the child there (`RDW_INVALIDATE|RDW_ERASE|RDW_FRAME|RDW_ALLCHILDREN`), the
    same way `redraw_window()` treats such children.
- Confidence: the rule matches Wine's own invalidation semantics (V). That Windows does
  exactly this is inferred (I): on Windows the buttons are visible after expanding (reference
  screenshot).
- Cost: an extra repaint of a moved child only when its parent has a pending invalid area
  under it.
- Tests:
  - `tests/static/dialog-layout` (expand.exe) grows a dialog from a second thread and moves
    a button the same way. Fails on baseline (button blank), passes on patched. The variants
    `SAME_THREAD=1 PUMP=1` and `NO_HIDE=1` give the same result.
  - Genuine mstsc shows Connect and Help after **Show Options**, with and without a window
    manager.
