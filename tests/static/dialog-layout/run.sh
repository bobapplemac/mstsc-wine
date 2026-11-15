#!/bin/bash
# Genuine mstsc dialog layout (EXP-042..044):
#  1. the "Show Options" expander toolbar draws its whole label (patch 0026)
#  2. a button moved into a still-invalid part of a dialog without WS_CLIPCHILDREN is
#     repainted, so "Connect"/"Help" stay visible after expanding (patch 0027)
#  3. text in hinted fonts is as wide as on Windows, so mstsc's message wraps like on
#     Windows (patch 0028; needs the genuine micross.ttf in Windows/Fonts, else skipped)
#   run.sh WINE OUT [DISPLAY]   (default :9, a private Xephyr)
W=$1 OUT=$2 D=${3:-:9}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
"$ROOT/tests/lib/xephyr.sh" start $D 1024x768 >/dev/null || exit 1
fail=0
check() { if [[ $2 == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
run() { DISPLAY=$D timeout 40 "$W" "$@" 2>/dev/null | tr -d '\r'; }
run "$OUT/toolbar.exe" > "$OUT/toolbar.log"
check "toolbar list button draws its whole label" $(grep -qx 'TEXT FULL' "$OUT/toolbar.log" && echo 1 || echo 0)
run "$OUT/expand.exe" > "$OUT/expand.log"
check "button moved during a dialog expansion is repainted" $(grep -qx 'BUTTON visible' "$OUT/expand.log" && echo 1 || echo 0)
font=$ROOT/Windows/Fonts/micross.ttf
if [[ -f $font ]]; then
    run "$OUT/textwidth.exe" "Z:$(tr / '\\' <<< "$font")" > "$OUT/textwidth.log"
    check "Microsoft Sans Serif 8pt text has Windows widths" $(grep -qx 'FITS' "$OUT/textwidth.log" && echo 1 || echo 0)
else
    echo "SKIP text width (no genuine micross.ttf in Windows/Fonts)"
fi
"$ROOT/tests/lib/xephyr.sh" stop $D >/dev/null
for f in toolbar expand textwidth; do [[ -f $OUT/$f.log ]] && grep -v '^[.#]' "$OUT/$f.log" | sed "s/^/  $f: /"; done
exit $((fail > 0))
