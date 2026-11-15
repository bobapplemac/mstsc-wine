#!/bin/sh
# Build the ole-clipboard fixture into OUT (default ./out).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=${1:-$here/out}
mkdir -p "$out"
x86_64-w64-mingw32-gcc -O2 "$here/clipfix.c" -o "$out/clipfix.exe" -lole32 -luuid -lshell32 -luser32
