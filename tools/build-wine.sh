#!/bin/bash
# Reproducibly build the mstsc-wine runtime: pinned upstream tag + patches/series.
#   tools/build-wine.sh baseline   -> build/install-wine-11.0   (unmodified upstream)
#   tools/build-wine.sh patched    -> build/install-wine-patched
# Requires Wine build dependencies (see docs/DECISIONS/0001); sources tools/build-env.sh
# when the rootless sysroot exists.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WINE_URL=https://gitlab.winehq.org/wine/wine.git
WINE_TAG=wine-11.0
WINE_COMMIT=db11d0fe6a169c457e23d007e20404643d067aa8
kind=${1:-patched}
[[ -d $ROOT/.deps/sysroot ]] && . "$ROOT/tools/build-env.sh"

if [[ ! -d $ROOT/wine-src/.git && ! -f $ROOT/wine-src/.git ]]; then
    git clone --depth 1 --branch $WINE_TAG $WINE_URL "$ROOT/wine-src"
fi
[[ $(git -C "$ROOT/wine-src" rev-parse $WINE_TAG^{commit}) == "$WINE_COMMIT" ]] || { echo "tag $WINE_TAG does not match pinned commit" >&2; exit 1; }

case $kind in
baseline) src=$ROOT/wine-src; name=wine-11.0 ;;
patched)
    src=$ROOT/wine-patched; name=wine-patched
    if [[ ! -e $src ]]; then
        git -C "$ROOT/wine-src" worktree add -q --detach "$src" $WINE_TAG
        while read -r p; do
            [[ -z $p || $p == \#* ]] && continue
            git -C "$src" -c user.name=mstsc-wine -c user.email=mstsc-wine@localhost am -q "$ROOT/patches/$p"
        done < "$ROOT/patches/series"
        (cd "$src" && autoconf -f ${SYSROOT:+-B $SYSROOT/usr/share/autoconf})
    fi ;;
*) echo "usage: $0 baseline|patched" >&2; exit 2 ;;
esac

b=$ROOT/build/$name; mkdir -p "$b"
cd "$b"
[[ -f Makefile ]] || "$src/configure" --prefix="$ROOT/build/install-$name" --enable-archs=x86_64 \
    CFLAGS="-g -O2" CROSSCFLAGS="-g -O2" > configure.out
make -j"$(nproc)" > make.out 2>&1 || { tail -30 make.out; exit 1; }
make install prefix="$ROOT/build/install-$name" > install.out 2>&1
"$ROOT/build/install-$name/bin/wine" --version
