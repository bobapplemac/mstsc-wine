#!/bin/sh
# Build the MUI fixture: muitest.exe (+ en-US/muitest.exe.mui, good checksum)
# bad/muitest.exe (+ bad/en-US/muitest.exe.mui, mismatched checksum) and
# i386/muitest.exe (+ i386/en-US/muitest.exe.mui, a resource-only *i386* satellite,
# like the real Windows ones that ship x86 MUI files for x64 binaries).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=${1:-$here/out}
CC=x86_64-w64-mingw32-gcc; WINDRES=x86_64-w64-mingw32-windres
mkdir -p "$out/en-US" "$out/bad/en-US" "$out/i386/en-US"; cd "$out"
python3 "$here/make-mui-config.py" main main.muicfg 00112233445566778899aabbccddeeff
python3 "$here/make-mui-config.py" mui sat.muicfg 00112233445566778899aabbccddeeff
cp "$here/main.rc" "$here/sat.rc" .
$WINDRES main.rc -O coff -o main.res.o
$WINDRES sat.rc -O coff -o sat.res.o
$CC -O2 "$here/muitest.c" main.res.o -o muitest.exe
$CC -shared -nostdlib -Wl,-e,DllMainCRTStartup "$here/satentry.c" sat.res.o -o en-US/muitest.exe.mui
# i386 resource-only satellite: windres + ld only (no i686 compiler needed).
$WINDRES -F pe-i386 sat.rc -O coff -o sat32.res.o
x86_64-w64-mingw32-ld -m i386pe --dll -e 0 -T "$here/rsrc-i386.ld" sat32.res.o -o i386/en-US/muitest.exe.mui
cp muitest.exe i386/muitest.exe
python3 "$here/make-mui-config.py" mui sat.muicfg ffffffffffffffffffffffffffffffff
$WINDRES sat.rc -O coff -o sat-bad.res.o
cp muitest.exe bad/muitest.exe
$CC -shared -nostdlib -Wl,-e,DllMainCRTStartup "$here/satentry.c" sat-bad.res.o -o bad/en-US/muitest.exe.mui
echo "built in $out"
