#!/bin/bash
# Build the runtime's private GnuTLS: Debian's gnutls28 source (same version and security
# patches as Debian 13's libgnutls30t64) plus patches/gnutls/*.patch (ADR-0013).
# Installs into $MSTSC_BUILD_DIR/install-gnutls (default build/). For development it also
# copies libgnutls.so.30* into RUNTIME/lib/mstsc-wine/ (default build/install-wine-patched),
# where the development launcher puts it on LD_LIBRARY_PATH; pass "none" to skip that.
#   tools/build-gnutls.sh [RUNTIME_DIR|none]
# Environment: JOBS, MSTSC_BUILD_DIR, MSTSC_DL_DIR (download cache, default .deps/dl).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=${MSTSC_BUILD_DIR:-$ROOT/build}
RUNTIME=${1:-$ROOT/build/install-wine-patched}
JOBS=${JOBS:-$(nproc)}
VER=3.8.9 DEB=3.8.9-3+deb13u4
# Pinned: the .dsc's SHA-256 authenticates it even without a Debian keyring; the .dsc
# then pins the two tarballs.
DSC_SHA256=f1153e91212bdf60acf66cb62713ad4ed577f2e85f578a04df31a5619624c1e1
POOL=pool/main/g/gnutls28
MIRRORS=("${DEBIAN_MIRROR:-https://deb.debian.org/debian}" https://snapshot.debian.org/archive/debian/20261116T000000Z)
DL=${MSTSC_DL_DIR:-$ROOT/.deps/dl}/gnutls28
SRC=${MSTSC_SRC_DIR:-$ROOT/.deps/src}/gnutls-$VER
B=$BUILD/gnutls I=$BUILD/install-gnutls
fail() { echo "build-gnutls: $*" >&2; exit 1; }

mkdir -p "$DL"
for f in gnutls28_$DEB.dsc gnutls28_$VER.orig.tar.xz gnutls28_$DEB.debian.tar.xz; do
    [[ -f $DL/$f ]] && continue
    for m in "${MIRRORS[@]}"; do
        curl -sSfL --retry 2 --max-time 300 -o "$DL/$f.part" "$m/$POOL/$f" 2>/dev/null && { mv "$DL/$f.part" "$DL/$f"; break; }
        rm -f "$DL/$f.part"
    done
    [[ -f $DL/$f ]] || fail "cannot download $f (tried: ${MIRRORS[*]})"
done
echo "$DSC_SHA256  $DL/gnutls28_$DEB.dsc" | sha256sum -c --quiet || fail "gnutls28_$DEB.dsc does not match the pinned SHA-256"
# Signature on the .dsc as well, when a Debian keyring is available.
if [[ -f /usr/share/keyrings/debian-keyring.gpg ]]; then
    gpgv --keyring /usr/share/keyrings/debian-keyring.gpg "$DL/gnutls28_$DEB.dsc" 2>&1 | grep -q 'Good signature' \
        || fail "bad .dsc signature"
else echo "build-gnutls: note: debian-keyring not installed; the .dsc is authenticated by its pinned SHA-256" >&2; fi
(cd "$DL" && awk '/^Checksums-Sha256:/{f=1;next} /^[A-Z]/{f=0} f&&NF==3&&$3!~/\.asc$/{print $1"  "$3}' gnutls28_$DEB.dsc | sha256sum -c --quiet) \
    || fail "source hash mismatch"

stamp="$DEB $(cat "$ROOT"/patches/gnutls/*.patch | sha256sum | cut -c1-16)"
if [[ ! -f $SRC/.mstsc-prepared || $(cat "$SRC/.mstsc-prepared") != "$stamp" ]]; then
    rm -rf "$SRC"; mkdir -p "$(dirname "$SRC")"
    tar -C "$(dirname "$SRC")" -xf "$DL/gnutls28_$VER.orig.tar.xz"
    tar -C "$SRC" -xf "$DL/gnutls28_$DEB.debian.tar.xz"
    (cd "$SRC"
     grep -v '^#' debian/patches/series | while read -r p; do [[ -n $p ]] && patch -p1 -s < "debian/patches/$p"; done
     for p in "$ROOT"/patches/gnutls/*.patch; do patch -p1 -s < "$p" || exit 1; done
     grep -rl --null gettext-0.20 m4/ | xargs -0r rm
     env GTKDOCIZE="echo DISABLED gtkdocize" autoreconf -fi >/dev/null 2>&1) || fail "preparing the source failed"
    echo "$stamp" > "$SRC/.mstsc-prepared"
fi

[[ -d $ROOT/.deps/sysroot ]] && . "$ROOT/tools/build-env.sh"
rm -rf "$B"; mkdir -p "$B"
# Neutral install paths (no build-machine paths in the library). Like Debian's own
# libgnutls it reads the host's optional /etc/gnutls/config crypto policy.
(cd "$B" && "$SRC/configure" --prefix=/usr --libdir=/usr/lib/mstsc-wine/gnutls --sysconfdir=/etc \
    --enable-ld-version-script --disable-rpath --disable-doc --disable-manpages --disable-tools \
    --disable-tests --disable-cxx --disable-guile --disable-libdane --without-tpm --without-tpm2 \
    --without-zstd --disable-nls --with-default-trust-store-file=/etc/ssl/certs/ca-certificates.crt \
    --with-packager=mstsc-wine --with-packager-version="$DEB+mstsc1" \
    CFLAGS="-g -O2 -ffile-prefix-map=$SRC=/usr/src/gnutls -ffile-prefix-map=$B=/usr/src/gnutls-build" \
    >configure.out 2>&1) || { tail -20 "$B/configure.out"; fail "configure failed"; }
make -C "$B" -j"$JOBS" >"$B/make.out" 2>&1 || { tail -20 "$B/make.out"; fail "make failed"; }
rm -rf "$I"
make -C "$B" install DESTDIR="$I" >"$B/install.out" 2>&1 || fail "make install failed"
ln -s usr/lib/mstsc-wine/gnutls "$I/lib"
cp "$SRC/debian/copyright" "$I/gnutls.copyright"
echo "gnutls_version=$DEB+mstsc1" > "$I/gnutls-build-info.txt"
echo "gnutls_patches=$(cd "$ROOT/patches/gnutls" && ls *.patch | tr '\n' ' ')" >> "$I/gnutls-build-info.txt"
if [[ $RUNTIME != none ]]; then
    mkdir -p "$RUNTIME/lib/mstsc-wine"
    cp -P "$I"/lib/libgnutls.so.30* "$RUNTIME/lib/mstsc-wine/"
    echo "installed patched GnuTLS $DEB+mstsc1 into $RUNTIME/lib/mstsc-wine"
else
    echo "built patched GnuTLS $DEB+mstsc1 in $I"
fi
