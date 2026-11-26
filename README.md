# mstsc-wine

Run Microsoft's genuine Remote Desktop Connection client (`mstsc.exe` + `mstscax.dll`)
on Linux through a purpose-built, isolated Wine runtime. The RDP protocol is
Microsoft's. There is no FreeRDP, no VM and no remote Windows.

**Status: alpha.** It connects to real Windows hosts and runs full sessions, but it's
tested on only one Linux desktop so far. Details: [docs/STATUS.md](docs/STATUS.md).

What works with the genuine client:
- The connection dialog, rendered close to Windows Server 2022.
- TLS connections, with Windows' certificate warning.
- Network Level Authentication (CredSSP) with NTLM, and with Kerberos without joining the
  Linux machine to the domain (sign in as `user@dns.domain`).
- "Remember my password", and the "Your credentials did not work" re-prompt.
- Fullscreen, Restore and Maximize.
- Clipboard redirection: text, files and pictures, in both directions.
- International keyboards: keys reach the remote session as Windows sends them, so the
  remote keyboard layout applies (tested: German, including Apple/Macintosh layouts, with
  umlauts, AltGr and dead keys such as ´ and ^; US).

- A self-contained, relocatable package built locally from source and your own Microsoft
  files: AppDir, single-file AppImage and `.tar.zst`. It brings its own Wine, patched
  GnuTLS, Kerberos and NTLM helper, and needs no Wine, Samba or Winbind on the machine.
  `make install` installs the AppImage with a "Remote Desktop Connection" menu entry and the
  `mstsc` command
  ([docs/PACKAGING.md](docs/PACKAGING.md)).

Not done or not yet tested:
- KDE Plasma on Wayland (the spec's primary target): tested so far on Cinnamon (X11) and
  KDE Plasma (X11).
- Servers that *require* NLA.
- Kerberos with a NetBIOS domain name (`DOMAIN\user` falls back to NTLM).
- Copying folder trees through the clipboard, and two sessions at once.
- Dead keys (´ ` ^ …) when IBus or Fcitx is your input method (`XMODIFIERS=@im=ibus` or
  `@im=fcitx`) *and composes accents itself*: the dead key may then do nothing in the
  session. Without IBus/Fcitx (X's own input method, the tested case) accents work, and an
  IBus that does not compose hands the keys through unchanged. The fix for X's own input
  method is deliberately not applied with IBus/Fcitx: they take every key and hand the
  unused ones back a moment later, so applying it doubled every key (tested with IBus;
  Fcitx works the same way over XIM)
  ([ADR-0056](docs/DECISIONS/0056-winex11-xim-consumed-keys.md)). Workaround: start mstsc
  with X's own input method, `XMODIFIERS=@im=none mstsc` (IBus/Fcitx input, e.g. for
  Chinese or Japanese, is then unavailable in mstsc's local dialogs).

- Authoritative spec: [docs/MSTSC-Wine-Master-Specification.md](docs/MSTSC-Wine-Master-Specification.md)
- Microsoft files you must supply: [docs/binary-acquisition.md](docs/binary-acquisition.md)
- Findings / experiments / decisions: [docs/RESEARCH.md](docs/RESEARCH.md),
  [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md), [docs/DECISIONS/](docs/DECISIONS/)

## Quick start (package)

On the Windows machine you take the client from, in PowerShell (no admin rights needed):

```powershell
irm https://raw.githubusercontent.com/bobapplemac/mstsc-wine/main/windows/Export-MstscComponents.ps1 | iex
```

This writes `mstsc-components-<build>-amd64.zip` into the current folder. The script copies
only the files mstsc-wine needs and uploads nothing. It runs the current `main` version: to
read it first, or to use a tagged version, see
[docs/PACKAGING.md](docs/PACKAGING.md#1-export-your-microsoft-files-on-windows).

Then on Debian 13, install the build prerequisites once:

```bash
sudo apt install git make python3 curl ca-certificates squashfs-tools zstd fuse3 desktop-file-utils docker.io
```

The build runs in Docker. Either add yourself to the `docker` group (`sudo usermod -aG docker $USER`,
then log out and in; the group is equivalent to root access), or add `DOCKER='sudo docker'` to
each `make` command below. Without Docker, `make BUILD_ENGINE=native` builds directly on the
host; it needs the packages in [packaging/build-deps.txt](packaging/build-deps.txt)
(`sudo apt install $(grep -v '^#' packaging/build-deps.txt)`).

Then build and run:

```bash
git clone https://github.com/bobapplemac/mstsc-wine.git && cd mstsc-wine
cp /path/to/mstsc-components-*.zip private-input/
make                      # Docker build of the runtime → artifacts/mstsc-wine-x86_64.AppImage
./artifacts/mstsc-wine-x86_64.AppImage /v:server01
make install              # installs the AppImage: menu entry "Remote Desktop Connection"
                          # and ~/.local/bin/mstsc
```

To update later: `git pull`, then `make install` (it rebuilds first).

The first build takes 20–40 minutes; later builds are incremental. Details, options, the extra
packages for `make test`, install and uninstall, and diagnostics:
[docs/PACKAGING.md](docs/PACKAGING.md).

## Quick start (development)

```bash
tools/build-wine.sh patched                # pinned Wine 11.0 + patches/ → build/install-wine-patched
launcher/mstsc-wine import /path/to/ms-files
launcher/mstsc-wine init
launcher/mstsc-wine doctor
launcher/mstsc-wine                        # runs mstsc.exe
tests/run-regression.sh build/install-wine-patched patched
```

## Assumptions (explicit)
- x86-64 only; both supplied binaries are x86-64, so the build uses `--enable-archs=x86_64`.
- XWayland/X11 (winex11) first; native Wayland is a later experiment.
- Microsoft binaries are never committed, published or downloaded by this project. They go
  only into the private artifacts *you* build from your own files (see below).
- The Wine prefix is an isolation boundary for *configuration*, not a security sandbox.

## License

- **This project's own code and docs** (launcher, tools, tests, docs, specification) are
  under the [MIT License](LICENSE).
- **The Wine patches in [`patches/`](patches/)** change Wine's own source files. They are
  derivative works of Wine and are distributed under Wine's license, the
  [GNU LGPL 2.1 or later](https://gitlab.winehq.org/wine/wine/-/blob/master/COPYING.LIB),
  not under MIT.
- **Wine and the libraries it uses** keep their own licenses: Wine is LGPL 2.1 or later,
  and libraries such as GnuTLS, FreeType and MIT Kerberos each have their own.
  A runtime built with `tools/build-wine.sh` is a build of Wine, so redistributing it
  means following Wine's LGPL and the licenses of the libraries it bundles.
- **Test-only tools** (the FreeRDP shadow server used as a local RDP *server*, pyspnego,
  python-gssapi, python-xlib, Debian's MIT KDC) are fetched or installed separately, keep
  their own licenses, and are not distributed by this project.

### Microsoft files

- **The public repository and anything the project publishes** (source, releases, CI
  results, container images) contain no Microsoft software. The project never downloads or
  redistributes any.
- **What you build yourself** (AppDir, AppImage, tarball, installation) *does* contain the
  Microsoft files you supplied. You export `mstsc.exe`, `mstscax.dll`, their MUI files,
  `.mun` resources and fonts from a Windows installation you are licensed to use
  (`windows/Export-MstscComponents.ps1`, [docs/binary-acquisition.md](docs/binary-acquisition.md)),
  and `make` copies them into your local artifact. That artifact is private: do not
  publish or share it.
- **Your licence is your responsibility.** Check that your Microsoft licence allows
  extracting these files, running them on Linux and including them in your locally built
  package. Not redistributing them does not, by itself, make that use compliant. Windows
  Server terms in particular may restrict running its components on another operating
  system. Nothing in this repository grants any rights to Microsoft software or bypasses
  its licensing, activation or security controls.

Microsoft, Windows and Remote Desktop are trademarks of Microsoft Corporation. This
project is not affiliated with or endorsed by Microsoft.
