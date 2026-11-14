#!/bin/sh
# Build the fullscreen-clip fixture into OUT (default ./out).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=${1:-$here/out}
mkdir -p "$out"
x86_64-w64-mingw32-gcc -O2 "$here/fsclip.c" -o "$out/fsclip.exe" -luser32 -lgdi32
