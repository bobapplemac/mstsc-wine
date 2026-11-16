# ADR-0044: Native dependency policy (bundled vs host)

- Status: accepted. 2026-11-15.
- Rule: a library is **bundled** when it is application-specific or its behaviour is part of
  what was verified (TLS, Kerberos, NTLM). It is **host-provided** when it must match the
  host's display, audio, graphics drivers or fonts, or is part of the platform ABI.
- Bundled (copied by `tools/collect-libs.py`, which reads `DT_NEEDED` with readelf and fails
  on anything unresolved that is not on the host list):
  - `gnutls/`: the patched `libgnutls.so.30` and nettle, hogweed, gmp, libtasn1, libidn2,
    libunistring, p11-kit, libffi.
  - `deps/`: MIT Kerberos (`libgssapi_krb5`, `libkrb5`, `libk5crypto`, `libkrb5support`,
    `libcom_err`, `libkeyutils`), dlopened by Wine's `kerberos.so`, and `libunwind`
    (`DT_NEEDED` of `ntdll.so`, so Wine can't start without it).
  - `samba/lib/`: everything the Debian `ntlm_auth` needs that is not above (ADR-0042),
    including OpenSSL, OpenLDAP, Cyrus SASL and ICU, which Samba's libraries link.
  - Sources: Debian 13 binary packages pinned in `packaging/debian-binaries.lock` (ADR-0045),
    except GnuTLS, which is built from Debian's source plus the project patch.
- Host (`packaging/host-libs.txt`, plus Wine's dlopen list in `tools/dependency-manifest.py`):
  - glibc; libgcc_s, libstdc++, zlib, liblzma, libzstd, libsystemd, libcap
    (required/important on every Debian 13 system).
  - X11/XWayland client libraries, FreeType, Fontconfig, PulseAudio/PipeWire and ALSA
    clients, udev, OpenGL/EGL/Vulkan loaders.
  - Optional: libusb, pcsclite, cups, SDL2, v4l2.
  - Facilities: the CA trust store, the optional `/etc/krb5.conf` and `/etc/gnutls/config`, DNS.
- Isolation: the launcher puts `gnutls/` and `deps/` first on `LD_LIBRARY_PATH` for the Wine
  child only. The NTLM helper's wrapper adds `samba/lib/`. `doctor` checks with
  `ld.so --list` that every bundled library resolves inside the package. A copy found on
  the host is reported as `SYSTEM-RESOLVED`.
- Consequences:
  - Bundled Debian libraries get no host security updates: refresh the lock file and rebuild
    (`dependency-manifest.json` → `security_update_guidance`).
  - Size: about 350 MB unpacked.
  - Host processes started by Wine (e.g. `xdg-open`) inherit the private library path. They
    find ABI-compatible Debian 13 copies; documented, not changed.
- Wine's optional features are fixed at configure time (`--without-wayland,dbus,gstreamer,
  ffmpeg,netapi,…`) so every build engine produces the same set of `DT_NEEDED` entries,
  matching the verified development runtime.
