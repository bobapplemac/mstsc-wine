# ADR-0002: Wine baseline pin

- Status: accepted (2026-11-13)
- Decision: Baseline is upstream **Wine 11.0** stable, tag `wine-11.0`, commit
  `db11d0fe6a169c457e23d007e20404643d067aa8` from
  https://gitlab.winehq.org/wine/wine (shallow clone in `wine-src/`, untracked).
- Built out-of-tree in `build/wine-11.0` with `--enable-archs=x86_64`
  (64-bit only: both supplied binaries are x86-64; no i386 PE is required yet).
- For the very first observations the official WineHQ binary packages
  `wine-stable{,-amd64}_11.0.0.0~trixie-1` were also used (SHA-256 verified
  against the WineHQ `Packages` index: b44710c2…9898, 5e12c8ed…b589). Both are
  unmodified upstream 11.0.
- Patches live on branch `mstsc-wine` in the `wine-patched/` worktree and are
  exported to `patches/` as an ordered series with `patches/series`.
- Alternatives: Wine development series (11.21 latest at time of writing) may
  contain relevant fixes; use for differential testing only, not as baseline.
