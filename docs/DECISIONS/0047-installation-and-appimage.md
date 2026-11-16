# ADR-0047: Installation, desktop integration and the AppImage

- Status: accepted. 2026-11-15. Amended by ADR-0049: `make` also builds the AppImage, and
  `make install` installs it (the AppDir install below is now `make install-appdir`).
- AppImage (`make appimage`): the AppImage type 2 runtime (release `20251108`, SHA-256
  pinned) followed by a SquashFS of the AppDir (zstd, root-owned, fixed timestamps).
  - Built directly with Debian's `mksquashfs` (the AppImage file format), so appimagetool
    is not needed. The runtime is a tagged upstream release fetched once and hash-checked.
  - Nothing is uploaded or published.
  - No FUSE: `--appimage-extract-and-run`, `--appimage-extract`, or `make package`
    (`.tar.zst` of the same AppDir).
- One integration script, `usr/lib/mstsc-wine/integrate.sh`, used by `make install`
  (AppDir), `mstsc --integrate` (inside the AppImage: copies `$APPIMAGE`; from an
  extracted AppDir: copies the AppDir) and `make integrate-appimage`:
  - user install: `~/.local/opt/mstsc-wine`, `~/.local/bin/mstsc`,
    `~/.local/share/applications/org.mstscwine.RemoteDesktopConnection.desktop`, icons in
    `~/.local/share/icons/hicolor/<size>/apps/`;
  - `PREFIX=/opt/mstsc-wine` (+ `BINDIR`, `DATADIR`, `DESTDIR`) for system-style installs;
    the script never escalates privileges;
  - AppDir installs are versioned: `versions/<build-id>` and an atomically switched
    `current` symlink. The previous version is kept, so running sessions are not
    disturbed;
  - every created path is recorded in `install-manifest`. Install and uninstall touch only
    those paths. An existing file we do not own (another `mstsc`, desktop entry or icon) is
    reported and left alone unless `--force`. Install is idempotent;
  - uninstall keeps the prefix, settings, saved credentials and logs; `--purge` removes them;
  - the desktop entry is `Name=Remote Desktop Connection`,
    `GenericName=Remote Desktop Client`, `Categories=Network;RemoteAccess;`, `Terminal=false`,
    and `Exec="<installed launcher>" %f` quoted per the Desktop Entry spec. `.rdp`
    association only with `--mime`; the default handler is never changed;
  - `PATH`: if `~/.local/bin` is not on it, the installer prints how to add it. It does not
    edit shell start-up files.
- `StartupWMClass=mstsc.exe`: Wine sets `WM_CLASS` from the executable name. Verified on the
  real window in EXP-058.
- Icon: generated locally from the operator's files; a project-owned SVG fallback otherwise.
