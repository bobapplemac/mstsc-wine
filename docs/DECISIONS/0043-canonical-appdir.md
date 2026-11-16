# ADR-0043: One canonical, relocatable AppDir

- Status: accepted. 2026-11-15.
- Context: the packaging spec (§1.8, §4) needs an AppImage, a tarball and an installation.
  Before this, the launcher found its runtime by an override, a user data directory or the
  source tree's `build/install-wine-patched`.
- Findings (V):
  - Wine 11.0 finds its own files relative to `ntdll.so` (`init_paths()` in
    `dlls/ntdll/unix/loader.c` computes `bin_dir`/`data_dir` from the compiled-in relation
    between `LIBDIR`, `BINDIR` and `DATADIR`, not their absolute values). `wineserver` is
    started from that `bin_dir` first; `WINESERVER` and `PATH` are only fallbacks.
  - A Wine tree installed with `DESTDIR` therefore runs from any directory. Checked from a
    copy at a path with a space and `Ä`, with every inherited `WINE*` variable pointing
    elsewhere (EXP-057).
  - The configure prefix still appears as a string in `ntdll.so` (the fallback above) and
    debug info contained build paths. The packaging build therefore uses the neutral prefix
    `/usr/lib/mstsc-wine/wine`, `-ffile-prefix-map` and `strip --strip-debug`. The
    assembler fails if any build path remains in the AppDir.
- Decision: one tree, `MSTSC-Wine.AppDir/`, built by `tools/assemble-appdir.sh` and used
  unchanged by the AppImage (`make appimage`), the tarball (`make package`) and
  `make install` (copied as a whole):

  ```
  AppRun                                  -> usr/bin/mstsc
  org.mstscwine.RemoteDesktopConnection.{desktop,png|svg}, .DirIcon
  usr/bin/mstsc                           launcher (the same file as launcher/mstsc-wine)
  usr/lib/mstsc-wine/wine/                patched Wine (bin/, lib/wine/, share/wine/)
  usr/lib/mstsc-wine/gnutls/              patched GnuTLS + its libraries
  usr/lib/mstsc-wine/deps/                MIT Kerberos, libunwind
  usr/lib/mstsc-wine/samba/{bin,lib,smb.conf}   private ntlm_auth (ADR-0042)
  usr/lib/mstsc-wine/integrate.sh         install/desktop integration (ADR-0047)
  usr/share/mstsc-wine/Windows/           operator's Microsoft files + manifest.sha256
  usr/share/mstsc-wine/metadata/          build-info, component and dependency manifests,
                                          licence notices, SOURCES.md, patches
  usr/share/applications/, usr/share/icons/hicolor/
  ```
  The spec's example layout is kept, with `deps/` for Kerberos and libunwind (shared by
  Wine and the helper) and the desktop ID `org.mstscwine.RemoteDesktopConnection`.
- The launcher detects the packaged layout from its own location
  (`<AppDir>/usr/bin/mstsc` → `../lib/mstsc-wine/wine/bin/wine`). It resolves symlinks
  (`~/.local/bin/mstsc`) and does not depend on `$APPDIR`, the current directory or the
  repository. Development mode (source tree) is unchanged.
- Mutable state stays outside: `XDG_DATA_HOME/mstsc-wine/prefix`, `XDG_STATE_HOME/mstsc-wine/logs`,
  `XDG_CONFIG_HOME/mstsc-wine/mstsc-wine.conf`, `XDG_CACHE_HOME/mstsc-wine`. The AppDir can be read-only.
- Not done: a generic `wine` command, global symlinks, file associations, services.
  `mstsc --wine-tool` exists for developers and tests only.
- Limitation: the AppDir path must not contain `:` (library search paths).
