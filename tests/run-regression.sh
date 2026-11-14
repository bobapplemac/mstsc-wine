#!/bin/bash
# Regression suite for mstsc-wine Wine patches.  Runs against one runtime:
#   tests/run-regression.sh RUNTIME_DIR [baseline|patched]
# For "baseline" the patch-specific tests are expected to FAIL (they document
# the upstream defect); for "patched" they must PASS.  Exit 0 if all expectations hold.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RT=${1:?runtime dir}; mode=${2:-patched}
W=$RT/bin/wine
export WINEPREFIX=$ROOT/artifacts/prefixes/regress-$(basename "$RT")
export WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe,mscoree,mshtml,winedbg.exe=d" WINEARCH=win64
mkdir -p "$WINEPREFIX"; "$RT/bin/wineboot" -u >/dev/null 2>&1; "$RT/bin/wineserver" -w
[[ -d $ROOT/.deps/sysroot ]] && . "$ROOT/tools/build-env.sh"
FIX=$ROOT/artifacts/mui-fixture
"$ROOT/tests/static/mui-fixture/build.sh" "$FIX" >/dev/null || { echo "fixture build failed"; exit 1; }
ORD=$ROOT/artifacts/user32-ordinals
"$ROOT/tests/static/user32-ordinals/build.sh" "$ORD" >/dev/null || { echo "ordinal fixture build failed"; exit 1; }

fails=0
check() { # name expected(pass|fail) cmd...
    local name=$1 exp=$2; shift 2
    if "$@" >/dev/null 2>&1; then got=pass; else got=fail; fi
    if [[ $got == "$exp" ]]; then echo "ok   $name ($got)"; else echo "FAIL $name (expected $exp, got $got)"; fails=$((fails+1)); fi
}
exp_fix=pass; [[ $mode == baseline ]] && exp_fix=fail
check "smoke: cmd /c echo"                     pass "$W" cmd /c echo ok
check "mui: string from en-US satellite"       $exp_fix "$W" "$FIX/muitest.exe"
check "mui: mismatched checksum is rejected"   pass "$W" "$FIX/bad/muitest.exe" expect-missing
check "mui: i386 resource-only satellite"    $exp_fix "$W" "$FIX/i386/muitest.exe"
check "user32: ordinal 2598 callable"         $exp_fix "$W" "$ORD/ord2598.exe"
if [[ -f $ROOT/build/$(basename "$RT" | sed 's/^install-//')/dlls/devobj/tests/x86_64-windows/devobj_test.exe ]]; then
    check "devobj: conformance test"           pass "$W" "$ROOT/build/$(basename "$RT" | sed 's/^install-//')/dlls/devobj/tests/x86_64-windows/devobj_test.exe" devobj
else
    check "devobj: dll present"                $exp_fix test -f "$RT/lib/wine/x86_64-windows/devobj.dll"
fi
ST=$ROOT/build/$(basename "$RT" | sed 's/^install-//')/dlls/shcore/tests/x86_64-windows/shcore_test.exe
[[ $mode == patched && -f $ST ]] && check "shcore: conformance (resource stream)" pass "$W" "$ST" shcore
"$RT/bin/wineserver" -k 2>/dev/null
echo "$fails unexpected result(s)"; exit $((fails > 0))
