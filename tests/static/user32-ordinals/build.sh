#!/bin/sh
# Build user32 ordinal fixtures into OUT (default ./out).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=${1:-$here/out}
mkdir -p "$out"
x86_64-w64-mingw32-gcc -O2 "$here/ord2598.c" -o "$out/ord2598.exe"
