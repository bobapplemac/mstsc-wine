# ADR-0049: `make` builds the AppImage, `make install` installs it

- Status: accepted. 2026-11-16. Amends ADR-0047.
- Context:
  - `make` built only the AppDir, and `make install` copied that AppDir into
    `~/.local/opt/mstsc-wine/versions/<build>`.
  - `make install` did not rebuild. After `git pull`, running `make install` without `make`
    silently installed the previous build.
  - The operator prefers the unpacked AppDir to be a development artifact: what gets
    installed should be the same single file a user would run, and the one the release
    gates test (PKG-010/024).
- Decision:
  - `make` (`all`) = `verify-components` + `appdir` + `appimage`. `make appimage` stays as a
    target. Assembly and the AppImage take about 12 s together once the open-source parts are
    built.
  - `make install` depends on `all`, so it always installs the current source. It then runs
    `<AppImage> --integrate`: the AppImage's own `integrate.sh` copies it to
    `~/.local/opt/mstsc-wine/mstsc-wine-x86_64.AppImage`, and the menu entry and
    `~/.local/bin/mstsc` point at that file. `MIME=1`, `PREFIX`, `BINDIR`, `DATADIR` and
    `DESTDIR` work as before.
  - Before that, `make install` runs `<AppImage> --version`. If it does not start (no FUSE),
    it stops with a message naming `fuse3` and `make install-appdir`.
  - `make install-appdir` keeps the old behaviour (versioned AppDir copies, atomic `current`
    switch), for development and for machines without FUSE.
  - The removed `make integrate-appimage` target was the same thing as the new `make install`.
  - Switching modes leaves one installation: installing the AppImage removes `current`,
    `versions/` and their markers; installing an AppDir removes the installed AppImage.
    Sessions still running from removed AppDir files should be restarted. An upgraded
    AppImage replaces the file atomically, so a running session keeps its mounted image.
  - `make uninstall` is unchanged; it handles both modes from the manifest.
- Fixed on the way (V): `integrate.sh` could exit before renaming `install-manifest.tmp`
  when the last previously owned path no longer existed (`[[ -e ]] && printf` as the
  loop's last command, under `pipefail`/`set -e`). The loop order is that of a bash
  associative array, so it failed intermittently. A later uninstall then left the
  application behind. It was latent because no owned path disappeared between installs
  until mode switching. Rewritten without pipelines or a trailing `&&`; 8/8 repeated runs
  pass.
- Tests: `tests/portability/test-install.sh appimage` now covers the `make install` path,
  including AppImage → AppDir → AppImage switches (gate PKG-017). The `appdir` mode covers
  `make install-appdir`.
- Trade-offs: an AppImage needs FUSE (Debian 13 has `fuse3` on desktop installs) and mounts
  its SquashFS on each start (unmeasurable next to Wine's start-up).
