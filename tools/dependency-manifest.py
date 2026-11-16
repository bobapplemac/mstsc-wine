#!/usr/bin/env python3
"""Write metadata/dependency-manifest.json and license notices for an AppDir (spec §5.2, PKG-018).

    dependency-manifest.py --build BUILD --libs LIBS.json --appdir APPDIR --out FILE --notices DIR

Every native component is classified as "bundled" (private copy in the AppDir) or "host"
(provided by the target system), with origin, version, license, SHA-256 and the reason.
"""
import argparse, datetime, glob, hashlib, json, os, re, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HOST_DLOPEN = {
    # soname: reason (dlopened by Wine; optional unless noted)
    "libX11.so.6": "X11/XWayland display (required)",
    "libXext.so.6": "X11 extensions", "libXrender.so.1": "X11 rendering", "libXrandr.so.2": "display modes",
    "libXi.so.6": "input devices", "libXcursor.so.1": "cursors", "libXfixes.so.3": "clipboard/selection events",
    "libXcomposite.so.1": "compositing", "libXinerama.so.1": "multi-monitor", "libXxf86vm.so.1": "gamma/modes",
    "libfreetype.so.6": "font rendering (required); must match the host's font stack",
    "libfontconfig.so.1": "host font discovery; reads the host's fontconfig configuration",
    "libpulse.so.0": "audio (PulseAudio or PipeWire-pulse)", "libasound.so.2": "audio (ALSA fallback)",
    "libudev.so.1": "device enumeration", "libGL.so.1": "OpenGL (host driver stack)",
    "libEGL.so.1": "EGL (host driver stack)", "libvulkan.so.1": "Vulkan (host driver stack)",
    "libcups.so.2": "printing (not used by mstsc)", "libSDL2-2.0.so.0": "game controllers (not used)",
    "libv4l2.so.0": "video capture (not used)", "libodbc.so": "ODBC (not used)",
    "libusb-1.0.so.0": "USB (not used by mstsc)", "libpcsclite.so.1": "smart cards (optional)",
}
FOUNDATIONAL = [
    {"name": "glibc (libc, libm, ld-linux)", "reason": "platform ABI; baseline Debian 13 glibc 2.41"},
    {"name": "Linux kernel, X11 server or XWayland", "reason": "display; Wine uses winex11 on X11/XWayland"},
    {"name": "/etc/ssl/certs/ca-certificates.crt", "reason": "system CA trust store used by the patched GnuTLS (ca-certificates)"},
    {"name": "/etc/krb5.conf (optional)", "reason": "Kerberos works without it (DNS SRV lookup, ADR-0027); honoured if present"},
    {"name": "/etc/gnutls/config (optional)", "reason": "system crypto policy, as for Debian's own GnuTLS"},
    {"name": "DNS resolver, NSS", "reason": "name resolution through glibc"},
    {"name": "fontconfig configuration and fonts", "reason": "host fonts as fallbacks; Microsoft fonts come from the component bundle"},
]


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def licenses_of(copyright_file):
    try:
        text = open(copyright_file, errors="replace").read()
    except OSError:
        return []
    found = []
    for m in re.finditer(r"^License:\s*(\S[^\n]*)", text, re.M):
        lic = m.group(1).strip()
        if lic not in found:
            found.append(lic)
    return found[:8]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", required=True)
    ap.add_argument("--libs", required=True)
    ap.add_argument("--appdir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--notices", required=True)
    a = ap.parse_args()
    os.makedirs(a.notices, exist_ok=True)
    deb = os.path.join(a.build, "debroot")
    pkgs = {}
    for line in open(os.path.join(deb, ".packages")):
        p = line.split()
        if len(p) == 4:
            pkgs[p[0]] = {"package": p[0], "version": p[1], "deb_sha256": p[2], "pool_path": p[3]}
    info = dict(l.strip().split("=", 1) for l in open(os.path.join(a.build, "stage", "wine-build-info.txt")) if "=" in l)
    gn = dict(l.strip().split("=", 1) for l in open(os.path.join(a.build, "install-gnutls", "gnutls-build-info.txt")) if "=" in l)
    lib_root = os.path.join(a.appdir, "usr", "lib", "mstsc-wine")

    used_pkgs = set()
    libs = []
    for r in json.load(open(a.libs)):
        loc = None
        for sub in ("gnutls", "deps", "samba/lib"):
            if os.path.exists(os.path.join(lib_root, sub, r["soname"])):
                loc = "usr/lib/mstsc-wine/%s/%s" % (sub, r["soname"])
                break
        pkg = r.get("package", "unknown").split()[0]
        if pkg in pkgs:
            used_pkgs.add(pkg)
        libs.append({
            "soname": r["soname"], "location": loc, "sha256": sha(os.path.join(a.appdir, loc)) if loc else r["sha256"],
            "classification": "bundled", "debian_package": r.get("package", "unknown"),
            "license": licenses_of(os.path.join(deb, "usr/share/doc", pkg, "copyright")),
            "reason": "needed by %s" % r.get("needed_by", "?"),
        })
    used_pkgs.add("winbind")
    for p in sorted(used_pkgs):
        src = os.path.join(deb, "usr/share/doc", p, "copyright")
        if os.path.exists(src):
            shutil.copy(src, os.path.join(a.notices, p + ".copyright"))
    # Wine and GnuTLS notices
    wsrc = os.path.join(a.build, "wine-dist-src")
    for f in ("COPYING.LIB", "LICENSE", "AUTHORS"):
        if os.path.exists(os.path.join(wsrc, f)):
            shutil.copy(os.path.join(wsrc, f), os.path.join(a.notices, "wine-" + f))
    gc = os.path.join(a.build, "install-gnutls", "gnutls.copyright")
    if os.path.exists(gc):
        shutil.copy(gc, os.path.join(a.notices, "gnutls28.copyright"))

    winbind = pkgs.get("winbind", {})
    components = [
        {"name": "Wine (patched)", "classification": "bundled", "location": "usr/lib/mstsc-wine/wine",
         "version": info.get("wine_version"), "license": "LGPL-2.1-or-later",
         "origin": {"url": "https://gitlab.winehq.org/wine/wine.git", "tag": info.get("wine_tag"),
                    "commit": info.get("wine_commit")},
         "patches": {"count": info.get("patch_count"), "series_sha256": info.get("patch_series_sha256"),
                     "content_sha256": info.get("patches_sha256"), "source_tree": info.get("source_tree"),
                     "copy": "usr/share/mstsc-wine/metadata/source/patches"},
         "reason": "runs the Microsoft client; patches 0001-%s (docs/DECISIONS)" % info.get("patch_count"),
         "security_updates": "rebuild from source after updating the pinned tag or patches/series"},
        {"name": "GnuTLS (patched)", "classification": "bundled",
         "location": "usr/lib/mstsc-wine/gnutls/libgnutls.so.30",
         "sha256": sha(os.path.join(lib_root, "gnutls", "libgnutls.so.30")),
         "version": gn.get("gnutls_version"), "license": "LGPL-2.1-or-later",
         "origin": {"debian_source": "gnutls28 %s" % gn.get("gnutls_version", "").replace("+mstsc1", ""),
                    "url": "https://deb.debian.org/debian/pool/main/g/gnutls28/",
                    "project_patches": gn.get("gnutls_patches", "").split()},
         "reason": "accepts RDP self-signed server certificates without digitalSignature key usage "
                   "(ADR-0013); all other verification unchanged. Security-relevant deviation: it "
                   "broadens acceptance of one invalid key-usage case.",
         "security_updates": "update VER/DEB/DSC_SHA256 in tools/build-gnutls.sh to the current Debian 13 "
                             "gnutls28 and rebuild"},
        {"name": "Samba ntlm_auth (client helper)", "classification": "bundled",
         "location": "usr/lib/mstsc-wine/samba/bin/ntlm_auth.bin",
         "sha256": sha(os.path.join(lib_root, "samba", "bin", "ntlm_auth.bin")),
         "version": winbind.get("version"), "license": "GPL-3.0-or-later",
         "origin": {"debian_package": "winbind", "deb_sha256": winbind.get("deb_sha256"),
                    "pool_path": winbind.get("pool_path")},
         "reason": "NTLM for CredSSP/NLA; run by Wine through WINENTLMAUTH (patch 0039, ADR-0042); "
                   "client mode needs no winbindd",
         "security_updates": "tools/update-debian-lock.sh, then rebuild"},
        {"name": "mstsc-samba-paths shim", "classification": "bundled",
         "location": "usr/lib/mstsc-wine/samba/lib/libmstsc-samba-paths.so", "license": "MIT",
         "origin": {"source": "packaging/samba/mstsc-samba-paths.c"},
         "reason": "keeps the bundled ntlm_auth from loading host Samba modules (ADR-0042)"},
    ]
    host = []
    for line in open(os.path.join(ROOT, "packaging", "host-libs.txt")):
        s = line.split("#", 1)
        if s[0].strip():
            host.append({"soname": s[0].strip(), "classification": "host", "linked": True,
                         "reason": s[1].strip() if len(s) > 1 else ""})
    for so, why in HOST_DLOPEN.items():
        if not any(h["soname"] == so for h in host):
            host.append({"soname": so, "classification": "host", "linked": False, "reason": why})
    out = {
        "schema": "mstsc-wine-dependencies/1",
        "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "components": components,
        "bundled_libraries": sorted(libs, key=lambda x: x["location"] or ""),
        "debian_packages": [dict(pkgs[p], license=licenses_of(os.path.join(deb, "usr/share/doc", p, "copyright")))
                            for p in sorted(used_pkgs) if p in pkgs],
        "host_libraries": host,
        "host_facilities": FOUNDATIONAL,
        "microsoft_components": "see component-manifest.json (operator-supplied; never redistributed)",
        "security_update_guidance": [
            "Bundled Debian libraries do not receive host security updates. Refresh "
            "packaging/debian-binaries.lock with tools/update-debian-lock.sh and rebuild (make) after "
            "Debian security advisories for samba, krb5, openssl, gnutls28, nettle, libtasn1-6, "
            "p11-kit, icu or openldap.",
            "Host libraries are updated by the host's package manager as usual.",
        ],
    }
    json.dump(out, open(a.out, "w"), indent=1)
    print("dependency-manifest: %d bundled libraries, %d Debian packages, %d host libraries"
          % (len(libs), len(out["debian_packages"]), len(host)))


if __name__ == "__main__":
    main()
