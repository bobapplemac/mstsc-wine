# ADR-0045: Build inputs and build engines (Docker and native)

- Status: accepted. 2026-11-15.
- Inputs, all pinned and integrity-checked:
  - Wine: tag `wine-11.0` = commit `db11d0fe…` (`tools/build-wine.sh` refuses any other).
    `dist` builds use a fresh worktree with exactly `patches/series` applied; the series
    and patch-content hashes and the resulting tree hash go into `build-info.json` (PKG-003).
  - GnuTLS: Debian `gnutls28` 3.8.9-3+deb13u4. The `.dsc` SHA-256 is pinned in the script,
    the `.dsc` pins the tarballs, and its signature is checked as well when `debian-keyring`
    is installed. Debian's patch series is applied, then `patches/gnutls/`.
  - Debian binary packages: `packaging/debian-binaries.lock` (package, version, SHA-256,
    pool path), generated from APT's signature-verified indices by
    `tools/update-debian-lock.sh`. `tools/fetch-debs.sh` tries deb.debian.org,
    security.debian.org, then snapshot.debian.org at the lock's date; a hash mismatch fails.
  - AppImage runtime: AppImage type2-runtime release `20251108`, SHA-256 pinned (ADR-0047).
- Engines:
  - `docker` (default when usable): `docker/Dockerfile`, Debian 13 by image digest, APT
    sources pinned to snapshot.debian.org `20261115T000000Z` (override `DOCKER_SNAPSHOT`;
    empty = live mirrors). The build context is `docker/` alone (`.dockerignore` excludes
    everything but the Dockerfile).
    - At run time only `tools/`, `patches/` and `packaging/` are mounted, read-only.
    - Outputs go to `build/docker`, the download cache to `build/docker-cache`. The
      container runs as the invoking user with `no-new-privileges`: no root-owned files, no
      devices, no X11.
    - Microsoft files and `private-input/` are never mounted and never in an image layer.
  - `native`: the same scripts on a Debian 13 host (`packaging/build-deps.txt`, or the
    rootless sysroot of ADR-0001), outputs in `build/native`. Must be chosen explicitly
    (`BUILD_ENGINE=native`): there is no silent fallback to an unpinned host toolchain.
  - When Docker is installed but unusable (as on the development host: not in the `docker`
    group), `make` stops with the choices: `DOCKER='sudo docker'`, `DOCKER=podman`, or
    `BUILD_ENGINE=native`.
- Assembly (`tools/assemble-appdir.sh`) always runs on the host and is where the Microsoft
  ZIP is read (spec §6 preferred approach).
- Incremental: make targets depend on the scripts, the patch series and the lock file.
  Wine's own make is incremental. Download caches survive `make clean` (`make distclean`
  removes them).
