#!/bin/bash
# Turn the canonical AppDir into a single-file AppImage, locally (ADR-0047). Never uploads.
#   tools/build-appimage.sh APPDIR OUT.AppImage
# The AppImage is the pinned AppImage type 2 runtime followed by a SquashFS image of the
# AppDir (the AppImage format); no appimagetool is needed. The runtime is downloaded once
# from the AppImage project's tagged release and checked against its pinned SHA-256.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APPDIR=$(cd "${1:?AppDir}" && pwd)
OUT=${2:?output}
RUNTIME_TAG=20251108
RUNTIME_SHA256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
RUNTIME_URL=https://github.com/AppImage/type2-runtime/releases/download/$RUNTIME_TAG/runtime-x86_64
DL=${MSTSC_DL_DIR:-$ROOT/.deps/dl}/appimage
RT=$DL/runtime-x86_64-$RUNTIME_TAG
fail() { echo "build-appimage: $*" >&2; exit 1; }
command -v mksquashfs >/dev/null || fail "mksquashfs not found (Debian: apt install squashfs-tools)"
[[ -x $APPDIR/AppRun && -f $APPDIR/org.mstscwine.RemoteDesktopConnection.desktop ]] || fail "$APPDIR is not an MSTSC-Wine AppDir"
if command -v desktop-file-validate >/dev/null; then
    desktop-file-validate "$APPDIR/org.mstscwine.RemoteDesktopConnection.desktop" || fail "desktop entry does not validate"
fi
mkdir -p "$DL"
if [[ ! -f $RT ]] || ! echo "$RUNTIME_SHA256  $RT" | sha256sum -c --quiet 2>/dev/null; then
    curl -sSfL --retry 2 --max-time 300 -o "$RT.part" "$RUNTIME_URL" || fail "cannot download $RUNTIME_URL"
    echo "$RUNTIME_SHA256  $RT.part" | sha256sum -c --quiet || { rm -f "$RT.part"; fail "AppImage runtime SHA-256 mismatch"; }
    mv "$RT.part" "$RT"
fi
mkdir -p "$(dirname "$OUT")"
SQ=$OUT.squashfs.tmp
rm -f "$SQ"
# reproducible image: fixed owner and timestamps (SOURCE_DATE_EPOCH or the build-info date)
epoch=${SOURCE_DATE_EPOCH:-$(stat -c %Y "$APPDIR/usr/share/mstsc-wine/metadata/build-info.json")}
mksquashfs "$APPDIR" "$SQ" -root-owned -noappend -no-xattrs -comp zstd -Xcompression-level 15 -b 1M \
    -mkfs-time "$epoch" -all-time "$epoch" -quiet -no-progress >/dev/null || fail "mksquashfs failed"
cat "$RT" "$SQ" > "$OUT.part"
rm -f "$SQ"
chmod 755 "$OUT.part"
mv -f "$OUT.part" "$OUT"
echo "build-appimage: $OUT ($(du -h "$OUT" | cut -f1)); runtime $RUNTIME_TAG"
echo "build-appimage: private artifact: it contains your Microsoft components. Do not publish it."
