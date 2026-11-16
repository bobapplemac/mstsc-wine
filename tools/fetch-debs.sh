#!/bin/bash
# Fetch the Debian 13 binary packages pinned in packaging/debian-binaries.lock, verify each
# file's SHA-256 and unpack them into one tree (ADR-0045). Resumable: verified downloads are kept.
#   tools/fetch-debs.sh [DEST]        (default build/debroot)
# Mirrors (override with DEBIAN_MIRROR / DEBIAN_SECURITY_MIRROR); snapshot.debian.org is the fallback.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK=$ROOT/packaging/debian-binaries.lock
DEST=${1:-$ROOT/build/debroot}
DL=${MSTSC_DL_DIR:-$ROOT/.deps/dl}/debs
MIRROR=${DEBIAN_MIRROR:-https://deb.debian.org/debian}
SECMIRROR=${DEBIAN_SECURITY_MIRROR:-https://security.debian.org/debian-security}
SNAP=$(sed -n 's/^#snapshot //p' "$LOCK")
mkdir -p "$DL"
fetch() { # pool-path sha256 out
    local pool=$1 sum=$2 out=$3 urls u
    if [[ $pool == pool/updates/* ]]; then
        urls=("$SECMIRROR/$pool" ${SNAP:+"https://snapshot.debian.org/archive/debian-security/$SNAP/$pool"})
    else
        urls=("$MIRROR/$pool" ${SNAP:+"https://snapshot.debian.org/archive/debian/$SNAP/$pool"})
    fi
    for u in "${urls[@]}"; do
        if curl -sSfL --retry 2 --max-time 600 -o "$out.part" "$u" 2>/dev/null; then
            if echo "$sum  $out.part" | sha256sum -c --quiet 2>/dev/null; then mv "$out.part" "$out"; return 0; fi
            echo "fetch-debs: SHA-256 mismatch for $u" >&2
        fi
        rm -f "$out.part"
    done
    echo "fetch-debs: cannot download $(basename "$pool") with the pinned hash (tried: ${urls[*]})" >&2
    return 1
}
unpack() { # deb dest list
    if command -v dpkg-deb >/dev/null; then
        dpkg-deb -x "$1" "$2"; dpkg-deb --fsys-tarfile "$1" | tar -t > "$3"; return
    fi
    local t; t=$(mktemp -d); (cd "$t" && ar x "$1" && tar -C "$2" -xf data.tar.* && tar -tf data.tar.* > "$3"); rm -rf "$t"
}
rm -rf "$DEST.tmp"; mkdir -p "$DEST.tmp/.files"
: > "$DEST.tmp/.packages"
grep -v '^#' "$LOCK" | while read -r pkg ver sum pool; do
    [[ -n $pkg ]] || continue
    f=$DL/$(basename "$pool")
    if [[ ! -f $f ]] || ! echo "$sum  $f" | sha256sum -c --quiet 2>/dev/null; then
        fetch "$pool" "$sum" "$f"
    fi
    unpack "$f" "$DEST.tmp" "$DEST.tmp/.files/$pkg.list"
    echo "$pkg $ver $sum $pool" >> "$DEST.tmp/.packages"
done
rm -rf "$DEST"; mv "$DEST.tmp" "$DEST"
echo "fetch-debs: $(wc -l < "$DEST/.packages") package(s) verified and unpacked into $DEST"
