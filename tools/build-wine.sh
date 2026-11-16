#!/bin/bash
# Reproducibly build the mstsc-wine runtime: pinned upstream tag + patches/series.
#   tools/build-wine.sh baseline   -> build/install-wine-11.0   (unmodified upstream, development)
#   tools/build-wine.sh patched    -> build/install-wine-patched (development; wine-patched/ worktree)
#   tools/build-wine.sh dist       -> $MSTSC_BUILD_DIR/stage/wine-root/usr/lib/mstsc-wine/wine
#       Packaging build (ADR-0043, ADR-0045): a fresh worktree with exactly patches/series
#       applied, configured for the neutral prefix /usr/lib/mstsc-wine/wine (Wine finds its
#       files relative to ntdll.so, so the tree can live anywhere) and installed with DESTDIR.
#       Writes wine-build-info.txt (commit, series hash, source tree hash) next to it.
# Environment: JOBS (default nproc), MSTSC_BUILD_DIR (default build/), WINE_SRC_DIR,
# WINE_URL (e.g. a local mirror; the tag must still resolve to the pinned commit).
# Uses the rootless sysroot (tools/build-env.sh) when .deps/sysroot exists.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WINE_URL=${WINE_URL:-https://gitlab.winehq.org/wine/wine.git}
WINE_TAG=wine-11.0
WINE_COMMIT=db11d0fe6a169c457e23d007e20404643d067aa8
JOBS=${JOBS:-$(nproc)}
BUILD=${MSTSC_BUILD_DIR:-$ROOT/build}
WSRC=${WINE_SRC_DIR:-$ROOT/wine-src}
kind=${1:-patched}
fail() { echo "build-wine: $*" >&2; exit 1; }
[[ -d $ROOT/.deps/sysroot ]] && . "$ROOT/tools/build-env.sh"

if [[ ! -d $WSRC/.git && ! -f $WSRC/.git ]]; then
    git clone -q --depth 1 --branch $WINE_TAG "$WINE_URL" "$WSRC" || fail "cannot clone $WINE_TAG from $WINE_URL"
fi
[[ $(git -C "$WSRC" rev-parse $WINE_TAG^{commit}) == "$WINE_COMMIT" ]] || fail "tag $WINE_TAG does not match pinned commit $WINE_COMMIT"

apply_series() {   # worktree
    local p n=0
    while read -r p; do
        [[ -z $p || $p == \#* ]] && continue
        git -C "$1" -c user.name=mstsc-wine -c user.email=mstsc-wine@localhost am -q "$ROOT/patches/$p" \
            || fail "patch $p does not apply (patches/series line $((n+1)))"
        n=$((n+1))
    done < "$ROOT/patches/series"
    (cd "$1" && autoconf -f ${SYSROOT:+-B $SYSROOT/usr/share/autoconf} >/dev/null) || fail "autoconf failed"
    echo "$n"
}

case $kind in
baseline) src=$WSRC; name=wine-11.0 ;;
patched)
    src=$ROOT/wine-patched; name=wine-patched
    if [[ ! -e $src ]]; then
        git -C "$WSRC" worktree add -q --detach "$src" $WINE_TAG
        apply_series "$src" >/dev/null
    fi ;;
dist)
    src=$BUILD/wine-dist-src; name=wine-dist
    series_sha=$(sha256sum < "$ROOT/patches/series" | cut -d' ' -f1)
    patches_sha=$(grep -v '^#' "$ROOT/patches/series" | sed '/^$/d' | (cd "$ROOT/patches" && xargs cat) | sha256sum | cut -d' ' -f1)
    stamp="$WINE_COMMIT $series_sha $patches_sha"
    if [[ ! -f $src/.mstsc-series || $(cat "$src/.mstsc-series") != "$stamp" ]]; then
        # (re)create the worktree from the pinned tag: exactly the recorded patch set
        git -C "$WSRC" worktree remove --force "$src" 2>/dev/null || rm -rf "$src"
        git -C "$WSRC" worktree prune
        git -C "$WSRC" worktree add -q --detach "$src" $WINE_TAG
        count=$(apply_series "$src")
        echo "$stamp" > "$src/.mstsc-series"
        rm -rf "$BUILD/$name"   # configure must see the new tree
        echo "build-wine: applied $count patches to $WINE_TAG"
    fi ;;
*) echo "usage: $0 baseline|patched|dist" >&2; exit 2 ;;
esac

b=$BUILD/$name; mkdir -p "$b"
cd "$b"
if [[ $kind == dist ]]; then
    prefix=/usr/lib/mstsc-wine/wine
    # no build paths in the shipped binaries (privacy, reproducibility)
    map="-ffile-prefix-map=$src=/usr/src/wine -ffile-prefix-map=$b=/usr/src/wine-build"
    # Optional features are fixed explicitly so that every build engine produces the same
    # runtime whatever -dev packages happen to be installed (packaging/host-libs.txt).
    [[ -f Makefile ]] || "$src/configure" --prefix=$prefix --enable-archs=x86_64 \
        --without-wayland --without-dbus --without-gstreamer --without-ffmpeg --without-netapi \
        --without-opencl --without-pcap --without-sane --without-gphoto --without-capi --without-oss \
        CFLAGS="-g -O2 $map" CROSSCFLAGS="-g -O2 $map" > configure.out 2>&1 \
        || { tail -30 configure.out; fail "configure failed (see $b/configure.out)"; }
else
    prefix=$BUILD/install-$name
    [[ -f Makefile ]] || "$src/configure" --prefix="$prefix" --enable-archs=x86_64 \
        CFLAGS="-g -O2" CROSSCFLAGS="-g -O2" > configure.out \
        || fail "configure failed (see $b/configure.out)"
fi
make -j"$JOBS" > make.out 2>&1 || { tail -30 make.out; fail "make failed (see $b/make.out)"; }
if [[ $kind == dist ]]; then
    dest=$BUILD/stage/wine-root
    rm -rf "$dest"
    make install DESTDIR="$dest" > install.out 2>&1 || { tail -30 install.out; fail "make install failed"; }
    {
        echo "wine_tag=$WINE_TAG"
        echo "wine_commit=$WINE_COMMIT"
        echo "wine_version=$(cd "$dest$prefix" && ./bin/wine --version 2>/dev/null || echo unknown)"
        echo "patch_count=$(grep -vc '^#' "$ROOT/patches/series")"
        echo "patch_series_sha256=$series_sha"
        echo "patches_sha256=$patches_sha"
        echo "source_tree=$(git -C "$src" rev-parse HEAD^{tree})"
        echo "configure_prefix=$prefix"
        echo "compiler=$(${CC:-gcc} --version | head -1)"
        echo "cross_compiler=$(x86_64-w64-mingw32-gcc --version 2>/dev/null | head -1)"
    } > "$BUILD/stage/wine-build-info.txt"
    echo "build-wine: installed into $dest$prefix"
    exit 0
fi
make install prefix="$prefix" > install.out 2>&1
"$prefix/bin/wine" --version
