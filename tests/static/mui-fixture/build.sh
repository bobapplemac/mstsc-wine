#!/bin/sh
# Build the MUI fixture: muitest.exe (+ en-US/muitest.exe.mui, good checksum)
# and bad/muitest.exe (+ bad/en-US/muitest.exe.mui, mismatched checksum).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=${1:-$here/out}
CC=x86_64-w64-mingw32-gcc; WINDRES=x86_64-w64-mingw32-windres
mkdir -p "$out/en-US" "$out/bad/en-US"; cd "$out"
python3 "$here/make-mui-config.py" main main.muicfg 00112233445566778899aabbccddeeff
python3 "$here/make-mui-config.py" mui sat.muicfg 00112233445566778899aabbccddeeff
cp "$here/main.rc" "$here/sat.rc" .
$WINDRES main.rc -O coff -o main.res.o
$WINDRES sat.rc -O coff -o sat.res.o
$CC -O2 "$here/muitest.c" main.res.o -o muitest.exe
$CC -shared -nostdlib -Wl,-e,DllMainCRTStartup "$here/satentry.c" sat.res.o -o en-US/muitest.exe.mui
python3 "$here/make-mui-config.py" mui sat.muicfg ffffffffffffffffffffffffffffffff
$WINDRES sat.rc -O coff -o sat-bad.res.o
cp muitest.exe bad/muitest.exe
$CC -shared -nostdlib -Wl,-e,DllMainCRTStartup "$here/satentry.c" sat-bad.res.o -o bad/en-US/muitest.exe.mui
echo "built in $out"
