#!/bin/sh
# Build the keyboard probe into OUT (default ./out).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=${1:-$here/out}
mkdir -p "$out"
x86_64-w64-mingw32-gcc -O2 -Wall "$here/kbdprobe.c" -o "$out/kbdprobe.exe" -luser32
