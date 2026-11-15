#!/bin/sh
# Build the dialog layout fixtures into OUT (default ./out).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=${1:-$here/out}
mkdir -p "$out"
x86_64-w64-mingw32-gcc -O2 "$here/expand.c" -o "$out/expand.exe" -luser32 -lgdi32
x86_64-w64-mingw32-gcc -O2 "$here/toolbar.c" -o "$out/toolbar.exe" -lcomctl32 -luser32 -lgdi32
x86_64-w64-mingw32-gcc -O2 "$here/textwidth.c" -o "$out/textwidth.exe" -luser32 -lgdi32
