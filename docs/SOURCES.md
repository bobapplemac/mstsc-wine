# Sources of this MSTSC-Wine build

This file is shipped inside every locally generated MSTSC-Wine AppDir, AppImage and tarball
(`usr/share/mstsc-wine/metadata/SOURCES.md`). It says where the source of each open-source
component is and how to rebuild it. The exact versions, hashes and licences of this
particular build are in `build-info.json` and `dependency-manifest.json` next to this file.

The artifact was built on the operator's machine from source. The mstsc-wine project does
not publish binaries. An artifact also contains the operator's own Microsoft files, so it
is a private build: don't share it (see "Microsoft components" below).

## Open-source components and their licences

| Component | Licence | Source |
|---|---|---|
| mstsc-wine launcher and build tools | MIT (`license-notices/mstsc-wine-LICENSE`) | the mstsc-wine repository, revision in `build-info.json` |
| Wine 11.0 + mstsc-wine patches | LGPL-2.1-or-later (`license-notices/wine-COPYING.LIB`) | https://gitlab.winehq.org/wine/wine.git tag `wine-11.0` (commit in `build-info.json`) plus `source/patches/` in the order of `source/patches/series` |
| GnuTLS 3.8.9 (patched) | LGPL-2.1-or-later (`license-notices/gnutls28.copyright`) | Debian source package `gnutls28` (version in `build-info.json`) from https://deb.debian.org/debian/pool/main/g/gnutls28/ plus `source/patches/gnutls/` |
| Samba `ntlm_auth` and its libraries | GPL-3.0-or-later / LGPL-3.0-or-later (`license-notices/*.copyright`) | Debian 13 binary packages listed in `source/debian-binaries.lock`; their source packages are on https://deb.debian.org/debian/ and https://snapshot.debian.org/ |
| MIT Kerberos, Nettle, GMP, libtasn1, libidn2, libunistring, p11-kit, libffi, libunwind, OpenLDAP, Cyrus SASL, OpenSSL, ICU, popt, libbsd, libmd, jansson | see `license-notices/<package>.copyright` | Debian 13 binary packages, same lock file |

## Rebuilding

From a checkout of the mstsc-wine repository at the revision in `build-info.json`:

```bash
make                      # Docker (or BUILD_ENGINE=native) build of Wine, GnuTLS and the NTLM helper,
                          # then assembly with your Microsoft component ZIP
make appimage             # optional: single-file AppImage
```

The Debian binary packages are fetched by `tools/fetch-debs.sh` and checked against the
SHA-256 values in `packaging/debian-binaries.lock`. To get the corresponding source of a
Debian package, run `apt-get source <source-package>=<version>` on Debian 13 or download it
from snapshot.debian.org.

## Microsoft components

`usr/share/mstsc-wine/Windows/` holds Microsoft files that the operator exported from
their own Windows installation (`component-manifest.json` lists them with SHA-256). They are
not open source and are not covered by any licence above. The mstsc-wine project does not
distribute them and grants no rights to them. Whether your Microsoft licence allows
copying them, running them on Linux and including them in this private artifact is for you
to determine. Not redistributing them does not, by itself, make that use compliant. Do not
publish or share an artifact that contains them.
