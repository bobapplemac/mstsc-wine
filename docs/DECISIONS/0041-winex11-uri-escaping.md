# ADR-0041: Do not escape path separators in exported file URIs (patch 0038)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-053):
  - winex11's `export_hdrop` percent-encoded every byte, e.g. `file:///%68%6f%6d%65%2f...`.
  - GLib's `g_filename_from_uri` rejects it: "contains invalidly escaped characters".
  - `g_file_get_path` returns NULL, so GTK applications could not open any file copied in Wine below `/`.
  - Present in unmodified Wine 11.0.
- Cause (V): RFC 3986. An escaped `/` is data inside a segment, not a separator.
- Decision: leave `/` and unreserved characters (`A-Za-z0-9-._~`) as they are; escape everything else, including
  UTF-8 bytes. The buffer size calculation still assumes the worst case.
- Tests: launch test, "GLib accepts the text/uri-list URI" (GLib through python3-gi).
