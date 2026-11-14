# mstsc-wine

Run Microsoft's genuine Remote Desktop Connection client (`mstsc.exe` + `mstscax.dll`)
on Linux through a purpose-built, isolated Wine runtime. The RDP protocol is
Microsoft's. There is no FreeRDP, no VM and no remote Windows.

**Status: pre-alpha.** The runtime builds and loads the client; the client UI is blocked
on operator-supplied MUI files. See [docs/STATUS.md](docs/STATUS.md).

- Authoritative spec: [MSTSC-Wine-Master-Specification.md](MSTSC-Wine-Master-Specification.md)
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
