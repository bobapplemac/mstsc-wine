# ADR-0039: CF_HDROP for virtual files on the OLE clipboard (patch 0036)

- Status: accepted. 2026-11-15.
- Requirement: spec F-007, T-012. Files copied in the remote session must paste in a Linux file manager.
- Situation (V, EXP-052):
  - mstsc puts remote files on the clipboard with `OleSetClipboard`, as `FileGroupDescriptorW` +
    `FileContents` (`TYMED_ISTREAM`) + `Preferred DropEffect`.
  - On Windows, Explorer pastes these by reading the streams and writing the files.
  - Linux file managers only accept file names (`text/uri-list`, `x-special/gnome-copied-files`). winex11 exports
    those only from CF_HDROP, so nothing could be pasted.
- Options considered:
  1. Materialise the files in winex11. Rejected: winex11's clipboard code runs on the Unix side of explorer.exe and
     cannot call COM. `FileContents` with `lindex` is only reachable through the source's IDataObject.
  2. A helper in explorer.exe. Rejected: it would need a marshalled IDataObject across processes, and FileContents
     calls through rpcss for every 64 KiB chunk.
  3. **ole32, in the owner process.** The OLE clipboard window already renders delayed formats from the original
     data object on the owner's thread. That is the same thread on which Explorer's marshalled calls arrive on
     Windows, so mstsc is built to answer `FileContents` there.
- Decision (3):
  - `set_clipboard_formats`: if the source has FileGroupDescriptorW and FileContents but no CF_HDROP, also announce
    a delayed CF_HDROP on the Win32 clipboard only. OLE consumers still enumerate the source's own list.
  - On `WM_RENDERFORMAT(CF_HDROP)`: create directories and write the files below
    `%TEMP%\Clipboard\<pid>-<tick>\`, set the write time if given, and return the top-level names
    (wide DROPFILES).
  - Names that are absolute or contain `..` or `:` are skipped, so the paste cannot escape that directory.
  - Not rendered on `WM_RENDERALLFORMATS` (would download everything at exit).
  - The previous directory is deleted on the next rendering.
- Consequences and limits (I):
  - Rendering is synchronous. A large file blocks the pasting X11 client until it has been transferred, as it
    blocks Explorer's paste dialog on Windows.
  - A Linux "move" is still a copy (the source is remote).
  - Up to one paste's files stay in the prefix's temp directory.
  - Other programs with virtual files (mail attachments, archives) benefit the same way.
- Tests: `tests/launch/test-clipboard.sh`: remote → local file (200,000 bytes, read via FileContents ranges of
  64 KiB), with name and content checked.
