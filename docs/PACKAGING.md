# Building and installing MSTSC-Wine

This builds a private, self-contained Linux package of Microsoft's Remote Desktop Connection
client: the genuine `mstsc.exe` and `mstscax.dll` you supply, running on a patched Wine
built from source with its own GnuTLS, Kerberos and NTLM helper. The package needs no Wine,
Samba, Winbind or `ntlm_auth` on the machine that runs it, and it doesn't touch any other
Wine installation.

Target: Debian 13 (trixie), x86-64. Tested on Cinnamon (X11); KDE Plasma (Wayland, through
XWayland) is not tested yet. Other distributions are not claimed.

## 1. Export your Microsoft files (on Windows)

On a Windows machine you are licensed to use (Windows Server 2022 is the verified source),
open 64-bit PowerShell (5.1 or 7). No administrator rights are needed.

**Quick:** download and run the current version in one step:

```powershell
irm https://raw.githubusercontent.com/bobapplemac/mstsc-wine/main/windows/Export-MstscComponents.ps1 | iex
```

- **Options.** `iex` can't pass parameters, so set environment variables first, e.g.
  `$env:MSTSC_EXPORT_OUTDIR = 'D:\out'`, `$env:MSTSC_EXPORT_LANGUAGE = 'de-DE'`, or
  `$env:MSTSC_EXPORT_EXPERIMENTAL = '1'`.
- **Parameters.** Alternatively:
  `& ([scriptblock]::Create((irm https://raw.githubusercontent.com/bobapplemac/mstsc-wine/main/windows/Export-MstscComponents.ps1))) -Experimental`.
- **Errors.** An error is reported without closing your PowerShell window.

**Reviewed:** read the script before running it, and pin a version:

```powershell
irm https://raw.githubusercontent.com/bobapplemac/mstsc-wine/main/windows/Export-MstscComponents.ps1 -OutFile Export-MstscComponents.ps1
notepad .\Export-MstscComponents.ps1
powershell -ExecutionPolicy Bypass -File .\Export-MstscComponents.ps1
```

The quick variant runs whatever is on `main` at that moment. For a fixed version, replace
`main` in the URL with a release tag or commit. You can also copy the script from your
checkout (`windows/Export-MstscComponents.ps1`). Older Windows PowerShell may need TLS 1.2
enabled first: `[Net.ServicePointManager]::SecurityProtocol = 'Tls12'`. The script:
- writes `mstsc-components-<build>-amd64.zip` with only the files listed in
  `packaging/components-policy.json` and a `manifest.json` (versions, SHA-256);
- copies nothing else (no registry, credentials, user or machine names) and uploads nothing;
- refuses mixed builds, 32-bit PowerShell and Windows builds that have not been verified
  (`-Experimental` exports one anyway, marked as such).

Already have the files in a folder that mirrors `C:\Windows` (`System32\`, `Fonts\`,
`SystemResources\`)? On Linux, `python3 tools/mscomponents.py from-dir Windows private-input/mstsc-components-<build>-amd64.zip`
makes the same ZIP.

**Licence.** These are Microsoft's proprietary files. The project does not give you any right
to copy them, run them on Linux or include them in a package. You must check that your
Microsoft licence allows it; not redistributing them does not, by itself, make it
compliant. Windows Server licence terms in particular may restrict running its components
elsewhere. Never publish or share the ZIP or anything built from it.

## 2. Build (on Debian 13)

On a fresh Debian 13, install the build prerequisites once:

```bash
sudo apt install git make python3 curl ca-certificates squashfs-tools zstd fuse3 desktop-file-utils docker.io
```

Then either let your user run Docker (`sudo usermod -aG docker $USER`, then log out and in
again: membership of the `docker` group is equivalent to root access) or build with
`make DOCKER='sudo docker'`. Podman works too (`sudo apt install podman`, `make DOCKER=podman`).

Only for `make test` (each missing tool makes its checks SKIP; none is needed to build or run):

```bash
sudo apt install gcc-mingw-w64-x86-64 xserver-xephyr xvfb x11-utils xclip bubblewrap metacity \
    python3-pil python3-xlib python3-gi python3-pyspnego python3-gssapi openssl \
    freerdp3-shadow-x11 freerdp3-dev
tools/fetch-krb5kdc.sh      # optional: offline Kerberos realm for the Kerberos test
```

Then:

```bash
git clone <repository-url> mstsc-wine
cd mstsc-wine
cp /path/to/mstsc-components-*.zip private-input/     # or: make MICROSOFT_COMPONENTS=/path/to/zip
make                                                  # → artifacts/MSTSC-Wine.AppDir and
                                                      #   artifacts/mstsc-wine-x86_64.AppImage
```

- **Build engine.** `make` compiles Wine, GnuTLS and the NTLM helper in a pinned Debian 13
  Docker image (`docker/Dockerfile`).
  - If you may not use Docker directly: `make DOCKER='sudo docker'`, or `DOCKER=podman`.
  - Without Docker: `make BUILD_ENGINE=native` on Debian 13, with the packages from
    `packaging/build-deps.txt` installed.
  - The first build downloads sources and takes 15–30 minutes. Later builds are incremental.
- **What stays local.** Your ZIP is read only on the host, in the assembly step. It never
  enters a container, an image or a cache that could be published.
- **Host tools.** `make` needs `squashfs-tools` for the AppImage, and `make package` needs `zstd`.
- **Other targets.** `make verify-components`, `make package` (`.tar.zst` of the AppDir),
  `make test`, `make doctor`, `make help`.

## 3. Run without installing

```bash
./artifacts/mstsc-wine-x86_64.AppImage /v:server01
./artifacts/MSTSC-Wine.AppDir/AppRun /v:server01        # same thing, unpacked
```

Arguments go to mstsc as on Windows (`/v:host`, `/f`, `/w:… /h:…`, `file.rdp`; Linux paths
to `.rdp` files are converted). `mstsc /?` shows mstsc's own help, and `mstsc --help` shows
the launcher's.

- **No FUSE?** Use `./mstsc-wine-x86_64.AppImage --appimage-extract-and-run /v:server01`, or
  unpack the tarball (`tar -I zstd -xf mstsc-wine-*-x86_64.tar.zst`) and run
  `MSTSC-Wine.AppDir/AppRun`.
- **Moving it.** The AppDir and the AppImage work from any directory, and may be read-only.
  The path must not contain `:`.

## 4. Install (menu entry and `mstsc` command)

```bash
make install            # rebuilds, then installs the AppImage: ~/.local/opt/mstsc-wine,
                        # ~/.local/bin/mstsc, menu entry "Remote Desktop Connection"
./artifacts/mstsc-wine-x86_64.AppImage --integrate      # the same, from a copied AppImage
make install-appdir     # development, or no FUSE: install the unpacked AppDir instead
```

- **Updating.** `git pull`, then `make install`. It always rebuilds first, so it never
  installs a stale build. The installed AppImage is replaced atomically. Switching between
  `make install` and `make install-appdir` replaces the other kind of installation
  (ADR-0049).
- **No FUSE.** `make install` checks that the AppImage starts and, if not, says to install
  `fuse3` or use `make install-appdir`.
- **Uninstall.** `make uninstall` (or `mstsc --unintegrate`) removes exactly what was
  installed. Your settings, saved credentials and logs stay; `make uninstall PURGE=1` (or
  `mstsc --unintegrate --purge`) removes them too, also after the application was already
  uninstalled. (`make uninstall --purge` doesn't work: make reads `--purge` as its own option.)
- **What is never replaced.** An existing `mstsc` command, menu entry or icon that
  mstsc-wine did not install is left alone (`--force` replaces it).
- **`.rdp` files.** Not associated unless you ask: `make install MIME=1`.
- **System-style install.** `make install PREFIX=/opt/mstsc-wine` (plus `BINDIR=`,
  `DATADIR=`, `DESTDIR=`). The installer never asks for root; run it with the privileges
  you intend.
- **`PATH`.** If `~/.local/bin` is not on your `PATH` yet, log out and in again (Debian's
  `~/.profile` adds it when the directory exists).
- **Upgrades.** Installing a new build switches atomically. The previous version stays until
  the next upgrade, so running sessions are not disturbed.

## 5. Where things are

| What | Where |
|---|---|
| Wine prefix (registry, saved credentials, `Default.rdp`) | `${XDG_DATA_HOME:-~/.local/share}/mstsc-wine/prefix` |
| Registry backups made before a runtime upgrade | `${XDG_DATA_HOME:-~/.local/share}/mstsc-wine/backups/` |
| Settings (`MSTSC_WINE_BACKEND=`, `MSTSC_WINE_DPI=`, `MSTSC_WINE_DLLOVERRIDES=`, `MSTSC_WINE_TRACE=`) | `${XDG_CONFIG_HOME:-~/.config}/mstsc-wine/mstsc-wine.conf` |
| Logs (no host names, user names or passwords) | `${XDG_STATE_HOME:-~/.local/state}/mstsc-wine/logs/` |
| Build provenance, licences, sources | `<AppDir>/usr/share/mstsc-wine/metadata/` |

- **Prefix updates.** The prefix is set up on the first start, under a lock, so starting
  several windows at once is safe. It is updated again only when the runtime or the
  Microsoft components change; the registry hives are saved first.
- **Restoring a backup.** To go back after an upgrade, copy the `*.reg` files from a
  `backups/<time>/` folder into the prefix while mstsc is not running.
- **Isolation.** `~/.wine`, other Wine installations, Bottles, Lutris, `/etc/samba` and the
  system Wine are never used or changed. `WINEPREFIX`, `WINELOADER`, `WINESERVER`,
  `WINEDLLPATH`, `WINEDLLOVERRIDES` and every other inherited `WINE*` variable are ignored.
  The prefix is a configuration boundary, not a security sandbox.
- **Display scaling.** On X11 and XWayland, the launcher copies the desktop's published
  `Xft.dpi` into Wine's private `LogPixels` setting. A changed DPI updates the prefix on
  the next launch. `mstsc doctor` reports both the value and its source. If a Wayland
  compositor does not publish DPI for XWayland clients, set an explicit integer, for
  example `MSTSC_WINE_DPI=144` for 150%, in `mstsc-wine.conf`. Use the compositor's
  default XWayland scaling policy first; an override can double-scale applications when
  the compositor already scales them.

## 6. Diagnostics

```bash
mstsc --version        # app, Wine revision and patch set, GnuTLS, NTLM helper, Microsoft client build
mstsc doctor           # bundled vs host libraries, NTLM helper self-test, components, display
mstsc doctor --paths   # same with full paths (home directory is shown as ~ otherwise)
```

- **Wine traces.** `MSTSC_WINE_TRACE=+channel` adds Wine trace channels. Traces can contain
  host names and protocol data: do not publish them unredacted.
- **Developers.** `mstsc --wine-tool wine|wineserver|… ARGS` runs a runtime tool with
  exactly mstsc's environment.

## 7. Host requirements (not bundled)

- **Display and platform.** glibc (Debian 13), X11 or XWayland and the X client libraries,
  FreeType and Fontconfig.
- **Audio.** PulseAudio or PipeWire-pulse (`libpulse`), or ALSA.
- **System facilities.** The CA trust store (`/etc/ssl/certs/ca-certificates.crt`) and DNS.
  `/etc/krb5.conf` is optional.
- **Full list.** `metadata/dependency-manifest.json` → `host_libraries`, `host_facilities`.
  `mstsc doctor` checks it.

**Security updates.** The bundled Samba, Kerberos, OpenSSL, GnuTLS and their libraries don't
get Debian's security updates automatically. After an advisory, run
`tools/update-debian-lock.sh` (Debian 13, after `apt update`) and rebuild with `make`.

## 8. Clean-host test checklist (release gates needing people or machines)

Automated gates: `make test` (`tests/portability/run.sh`; it prints PASS/FAIL/SKIP per
PKG-ID). By hand, on a disposable Debian 13 VM **without** wine, samba, winbind:

1. Copy only the AppImage. `./mstsc-wine-x86_64.AppImage doctor` → `doctor: OK`,
   `ntlm_auth: bundled`, `host wine: none`.
2. Connect to a disposable Windows RDP host with NTLM (`user` / `DOMAIN\user`) and Kerberos
   (`user@dns.domain`). Check the certificate warning, fullscreen and back, keyboard, audio,
   and clipboard (text, picture, files) in both directions.
3. `--integrate`. Start "Remote Desktop Connection" from the menu (Cinnamon and KDE Plasma).
   Check the icon and that the taskbar shows a single entry. Open a new terminal and run
   `command -v mstsc`.
4. Install `wine` and `winbind` from apt, start `winecfg`, and repeat steps 1–2: nothing
   changes.
5. Record the redacted results with `mstsc --version` in `docs/COMPATIBILITY.md`.
