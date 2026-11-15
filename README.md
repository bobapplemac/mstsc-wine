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

Not done or not yet tested:
- KDE Plasma on Wayland (the spec's primary target): tested so far only on Cinnamon (X11).
- Servers that *require* NLA.
- Kerberos with a NetBIOS domain name (`DOMAIN\user` falls back to NTLM).
- Copying folder trees through the clipboard, and two sessions at once.
- Packaging.

- Authoritative spec: [docs/MSTSC-Wine-Master-Specification.md](docs/MSTSC-Wine-Master-Specification.md)
- Microsoft files you must supply: [docs/binary-acquisition.md](docs/binary-acquisition.md)
- Findings / experiments / decisions: [docs/RESEARCH.md](docs/RESEARCH.md),
  [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md), [docs/DECISIONS/](docs/DECISIONS/)

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
- Microsoft binaries are never committed, packaged or downloaded by this project.
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

This project contains no Microsoft software and never downloads or redistributes any.
You must supply `mstsc.exe`, `mstscax.dll`, their MUI files, fonts and any other Microsoft
files yourself, from a Windows installation you are licensed to use. It is your
responsibility to make sure your license permits using those files this way (see
[docs/binary-acquisition.md](docs/binary-acquisition.md)). Nothing in this repository
grants any rights to Microsoft software.

Microsoft, Windows and Remote Desktop are trademarks of Microsoft Corporation. This
project is not affiliated with or endorsed by Microsoft.
