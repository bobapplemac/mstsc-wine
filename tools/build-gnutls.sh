#!/bin/bash
# Build the runtime's private GnuTLS: Debian's gnutls28 source (same version and security
# patches as Debian 13's libgnutls30t64) plus patches/gnutls/*.patch (ADR-0013).
# Installs into build/install-gnutls and copies libgnutls.so.30* into
# RUNTIME/lib/mstsc-wine/ (default build/install-wine-patched), where the launcher
# puts it on LD_LIBRARY_PATH.
#   tools/build-gnutls.sh [RUNTIME_DIR]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUNTIME=${1:-$ROOT/build/install-wine-patched}
VER=3.8.9 DEB=3.8.9-3+deb13u4
POOL=https://deb.debian.org/debian/pool/main/g/gnutls28
DL=$ROOT/.deps/dl/gnutls28 SRC=$ROOT/.deps/src/gnutls-$VER B=$ROOT/build/gnutls I=$ROOT/build/install-gnutls

mkdir -p "$DL"
for f in gnutls28_$DEB.dsc gnutls28_$VER.orig.tar.xz gnutls28_$DEB.debian.tar.xz; do
    [[ -f $DL/$f ]] || curl -sSfL --max-time 300 -o "$DL/$f" "$POOL/$f"
done
# Signature on the .dsc (Debian keyring, if present), then hashes from the .dsc.
if [[ -f /usr/share/keyrings/debian-keyring.gpg ]]; then
    gpgv --keyring /usr/share/keyrings/debian-keyring.gpg "$DL/gnutls28_$DEB.dsc" 2>&1 | grep -q 'Good signature' \
        || { echo "bad .dsc signature" >&2; exit 1; }
else echo "warning: debian-keyring not installed; .dsc signature not checked" >&2; fi
(cd "$DL" && awk '/^Checksums-Sha256:/{f=1;next} /^[A-Z]/{f=0} f&&NF==3&&$3!~/\.asc$/{print $1"  "$3}' gnutls28_$DEB.dsc | sha256sum -c --quiet) \
    || { echo "source hash mismatch" >&2; exit 1; }

if [[ ! -f $SRC/.mstsc-prepared ]]; then
    rm -rf "$SRC"; mkdir -p "$(dirname "$SRC")"
    tar -C "$(dirname "$SRC")" -xf "$DL/gnutls28_$VER.orig.tar.xz"
    tar -C "$SRC" -xf "$DL/gnutls28_$DEB.debian.tar.xz"
    (cd "$SRC"
     grep -v '^#' debian/patches/series | while read -r p; do [[ -n $p ]] && patch -p1 -s < "debian/patches/$p"; done
     for p in "$ROOT"/patches/gnutls/*.patch; do patch -p1 -s < "$p"; done
     grep -rl --null gettext-0.20 m4/ | xargs -0r rm
     env GTKDOCIZE="echo DISABLED gtkdocize" autoreconf -fi >/dev/null 2>&1)
    touch "$SRC/.mstsc-prepared"
fi

[[ -d $ROOT/.deps/sysroot ]] && . "$ROOT/tools/build-env.sh"
rm -rf "$B"; mkdir -p "$B"
(cd "$B" && "$SRC/configure" --prefix="$I" --libdir="$I/lib" \
    --enable-ld-version-script --disable-rpath --disable-doc --disable-manpages --disable-tools \
    --disable-tests --disable-cxx --disable-guile --disable-libdane --without-tpm --without-tpm2 \
    --without-zstd --disable-nls --with-default-trust-store-file=/etc/ssl/certs/ca-certificates.crt \
    --with-packager=mstsc-wine --with-packager-version="$DEB+mstsc1" >configure.out 2>&1)
make -C "$B" -j"$(nproc)" >"$B/make.out" 2>&1
make -C "$B" install >"$B/install.out" 2>&1
mkdir -p "$RUNTIME/lib/mstsc-wine"
cp -P "$I"/lib/libgnutls.so.30* "$RUNTIME/lib/mstsc-wine/"
echo "installed patched GnuTLS $DEB+mstsc1 into $RUNTIME/lib/mstsc-wine"
