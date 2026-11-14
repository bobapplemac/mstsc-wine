# ADR-0001: Rootless build toolchain and sysroot

- Status: accepted (2026-11-13)
- Context: The development host (LMDE 7 / Debian 13 base, Cinnamon X11) has no
  Wine build dependencies installed, and `sudo` requires a password that the
  agent does not have. The spec (§8) allows administrator-installed packages but
  forbids requiring root at runtime.

## Decision
Download the official Debian 13 build-dependency packages with
`apt-get download` (no root, signature-verified apt metadata), extract them with
`dpkg -x` into `.deps/sysroot/` (git-ignored), repoint `-dev` `.so` symlinks at
the already-installed system runtime libraries, and build Wine against it via
`tools/build-env.sh` (pkg-config sysroot, CPPFLAGS/LDFLAGS, bison/autoconf
relocation).

## Alternatives
1. Ask the operator to `apt install` build-deps: cleanest; still recommended for
   CI and release builds (`packaging/build-deps.txt` lists them). Not chosen now
   only because it would block autonomous progress.
2. Container (podman/docker): not installed, needs root to install.
3. llvm-mingw tarball: viable for PE side but does not solve Unix headers.

## Consequences
- Builds are reproducible from pinned Debian package versions recorded in
  `artifacts/` (not tracked); release builds must use a normal build-deps install.
- Missing optional dev packages (Wayland, D-Bus, GStreamer base plugins) mean the
  dev build lacks those features. These are not needed for M1–M3; revisit for
  F-020 (Wayland) and device hotplug.
- Rollback: delete `.deps/`.
