#!/bin/sh
# Build the dialog layout fixtures into OUT (default ./out).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=${1:-$here/out}
mkdir -p "$out"
x86_64-w64-mingw32-gcc -O2 "$here/expand.c" -o "$out/expand.exe" -luser32 -lgdi32
x86_64-w64-mingw32-gcc -O2 "$here/toolbar.c" -o "$out/toolbar.exe" -lcomctl32 -luser32 -lgdi32
x86_64-w64-mingw32-gcc -O2 "$here/textwidth.c" -o "$out/textwidth.exe" -luser32 -lgdi32
(cd "$here" && x86_64-w64-mingw32-windres nested.rc -O coff -o "$out/nested-res.o")
x86_64-w64-mingw32-gcc -O2 "$here/nested.c" "$out/nested-res.o" -o "$out/nested.exe" -luxtheme -lcomctl32 -luser32 -lgdi32
x86_64-w64-mingw32-gcc -O2 "$here/tbmargin.c" "$out/nested-res.o" -o "$out/tbmargin.exe" -lcomctl32 -luser32 -lgdi32
x86_64-w64-mingw32-gcc -O2 "$here/groupbox.c" "$out/nested-res.o" -o "$out/groupbox.exe" -luxtheme -lcomctl32 -luser32 -lgdi32
