# ADR-0019: Release Wine's fullscreen pointer grab when a window leaves fullscreen (patch 0016)

- Status: accepted. 2026-11-14.
- Symptom (V, EXP-024/032): in a fullscreen session, clicking **Restore** on the connection
  bar gives a normal window, as on Windows. After that the window manager's title-bar
  buttons no longer work, so **Maximize** cannot return to fullscreen. Without a window
  manager the window is unusable.
- Cause (V, EXP-033):
  - win32u clips the cursor to the monitor for the foreground fullscreen window
    (`clip_fullscreen_window`, Wine's own behaviour, not a Windows one).
  - winex11 implements that clip as an X pointer grab on its InputOnly clip window.
  - `X11DRV_WindowPosChanged` released the grab only when a fullscreen window was hidden.
    A window that stays visible but stops being fullscreen kept the grab.
  - With the grab held, every click goes to Wine, including clicks on the window
    manager's frame buttons.
  - Upstream master (checked 2026-11-14) has the same code.
- Decision: in `X11DRV_WindowPosChanged`, release the clip when a visible window goes
  from fullscreen to not fullscreen, but only if the current clip rectangle covers the
  whole virtual screen (`is_fullscreen_clipping()`).
  - A clip that covers the whole screen means "no clipping" to a Windows application, so
    releasing it changes nothing the application can observe.
  - A smaller rectangle the application set itself with `ClipCursor` is kept, as on
    Windows (fixture check 3).
- Known limit (I): with `GrabFullscreen=Y` on a multi-monitor desktop, the fullscreen clip
  is one monitor, smaller than the virtual screen. It is then treated like an application
  clip and kept. That is a non-default setting.
- Tests:
  - `tests/static/fullscreen-clip`, in the regression suite: fails on baseline, passes
    on patched.
  - `tests/launch/test-fullscreen-restore.sh`: genuine mstsc, Restore, then Maximize,
    under muffin (Cinnamon's WM) or metacity, against a local RDP server endpoint.
  - Wine `user32_test input` and `win` give identical results on both runtimes.
- Alternatives rejected:
  - Releasing unconditionally (`NtUserClipCursor(NULL)`) would drop an application's own
    clip rectangle.
  - Disabling fullscreen clipping in the prefix would change behaviour for every
    fullscreen window, including the session itself, to work around one transition.
