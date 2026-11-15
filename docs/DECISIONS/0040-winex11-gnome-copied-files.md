# ADR-0040: Export CF_HDROP as x-special/gnome-copied-files (patch 0037)

- Status: accepted. 2026-11-15.
- Requirement: spec F-019 (GTK and Qt file managers), T-011/T-012.
- Situation (V): Nautilus, Nemo and Caja paste files only from `x-special/gnome-copied-files`
  (`copy\n<uri>\n<uri>`). Dolphin uses `text/uri-list`, which winex11 already exported.
- Decision:
  - Add the target to winex11's builtin table, exported from CF_HDROP: "copy", then the same URIs, one per line,
    with no trailing newline.
  - No import function. GTK file managers also offer `text/uri-list`, which winex11 already imports
    (local → remote files work through it).
- Tests: launch test, "GTK file managers get x-special/gnome-copied-files": the URI resolves with GLib and the
  file content matches. Confirmation in a real Nemo/Dolphin session is still pending.
