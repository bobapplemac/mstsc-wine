# ADR-0003: Launcher and prefix isolation

- Status: accepted (2026-11-13)
- Decision: A Bash launcher `launcher/mstsc-wine` owns all Wine invocation.
  - Prefix: `$XDG_DATA_HOME/mstsc-wine/prefix` (never `~/.wine`), `WINEARCH=win64`.
  - `winemenubuilder.exe` disabled (no host menu entries / MIME pollution, F-013);
    `mscoree`/`mshtml` disabled (no Mono/Gecko prompts, T-001).
  - The prefix's user shell folders are real directories, not symlinks to `$HOME`.
  - Microsoft components are imported once with `mstsc-wine import DIR` into
    `$XDG_DATA_HOME/mstsc-wine/components/<FileVersion>/` with a `manifest.sha256`;
    `init` verifies hashes (fail closed) and copies them into `system32`.
  - Logs: `$XDG_STATE_HOME/mstsc-wine/logs/<timestamp>-<kind>.log` with a header
    of runtime/prefix/session metadata. Argument *values* are never logged (they
    may contain hostnames); Wine traces are opt-in via `MSTSC_WINE_TRACE`.
- Alternatives: Python launcher (more structure, extra dependency); deferred until
  the launcher grows beyond process management.
- Rollback: remove `$XDG_DATA_HOME/mstsc-wine` and `$XDG_STATE_HOME/mstsc-wine`.
