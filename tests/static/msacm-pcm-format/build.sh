#!/bin/sh
# Build the PCM ACM format-validation fixture into OUT (default ./out).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=${1:-$here/out}
mkdir -p "$out"
x86_64-w64-mingw32-gcc -O2 "$here/msacm-pcm-format.c" -o "$out/msacm-pcm-format.exe" -lmsacm32 -lwinmm
