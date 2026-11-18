#!/bin/bash
# F-011 / T-008: desktop-neutral DPI detection for X11 and XWayland sessions.
# Registry application is checked by test-launcher-isolation.sh under Xephyr.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RT=${1:-}
if [[ -z $RT ]]; then
    for candidate in "$ROOT/build/install-wine-patched" "$ROOT/artifacts/MSTSC-Wine.AppDir/usr/lib/mstsc-wine/wine"; do
        [[ -x $candidate/bin/wine ]] && { RT=$candidate; break; }
    done
fi
[[ -n $RT && -x $RT/bin/wine ]] || { echo "SKIP no Wine runtime"; exit 0; }

fails=0
check() { local name=$1 expected=$2; shift 2; local out; out=$("$@" 2>&1); if grep -qF "$expected" <<<"$out"; then echo "ok   $name"; else echo "FAIL $name: $out"; fails=$((fails+1)); fi; }
check_fail() { local name=$1 expected=$2 rc; shift 2; local out; out=$("$@" 2>&1); rc=$?; if [[ $rc != 0 ]] && grep -qF "$expected" <<<"$out"; then echo "ok   $name"; else echo "FAIL $name (exit $rc): $out"; fails=$((fails+1)); fi; }

xrdb() { printf 'Xft.dpi:\t144\n'; }
export -f xrdb
check "automatic Xft.dpi" "DisplayDPI: 144 source=Xft.dpi" env DISPLAY=:fixture MSTSC_WINE_RUNTIME="$RT" "$ROOT/launcher/mstsc-wine" --version
check "explicit override" "DisplayDPI: 120 source=config" env MSTSC_WINE_DPI=120 MSTSC_WINE_RUNTIME="$RT" "$ROOT/launcher/mstsc-wine" --version

xrdb() { return 1; }
export -f xrdb
check "unavailable resource manager falls back" "DisplayDPI: 96 source=default" env DISPLAY=:missing MSTSC_WINE_RUNTIME="$RT" "$ROOT/launcher/mstsc-wine" --version
check_fail "invalid override rejected" "MSTSC_WINE_DPI must be auto or an integer from 48 to 480" env MSTSC_WINE_DPI=invalid MSTSC_WINE_RUNTIME="$RT" "$ROOT/launcher/mstsc-wine" --version

echo "$fails failure(s)"
exit $((fails > 0))
