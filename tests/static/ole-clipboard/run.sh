#!/bin/bash
# Clipboard redirection the way mstscax.dll does it (EXP-048, ADR-0035):
# 1. WIL feature probes resolve ntdll!RtlQueryFeatureConfiguration without leaving
#    ERROR_PROC_NOT_FOUND behind; mstscax checks GetLastError() after a successful
#    GlobalAlloc and refused every remote clipboard format list because of it.
# 2. OleSetClipboard with a delayed-render data object: an X11 client pastes the text.
# 3. An X11 client copies text: OleGetClipboard returns it.
#   run.sh WINE OUT [DISPLAY]   (default :10, a private Xephyr; needs xclip)
W=$1 OUT=$2 D=${3:-:10}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fail=0
check() { if [[ $2 == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
"$W" "$OUT/clipfix.exe" probe > "$OUT/probe.log" 2>/dev/null
check "feature probe leaves no stale last error" $(grep -q "^PROBE OK" "$OUT/probe.log" && echo 1 || echo 0)
if command -v xclip >/dev/null; then
    "$ROOT/tests/lib/xephyr.sh" start $D 800x600 || exit 1
    export DISPLAY=$D
    # the X11 clipboard lives in the prefix's explorer.exe: restart it on this display
    "$(dirname "$W")/wineserver" -k 2>/dev/null; "$(dirname "$W")/wineserver" -w 2>/dev/null
    "$W" "$OUT/clipfix.exe" set 20 > "$OUT/set.log" 2>/dev/null &
    pid=$!
    for _ in $(seq 150); do grep -q OleIsCurrentClipboard "$OUT/set.log" && break; sleep 0.1; done
    got=$(timeout 10 xclip -o -selection clipboard -t UTF8_STRING 2>/dev/null)
    exp=$'remote ÄÖü € 中文\nline 2'
    check "OleSetClipboard delayed rendering pastes in X11" $([[ $got == "$exp" ]] && echo 1 || echo 0)
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    printf 'local éè 日本' | timeout 20 xclip -i -selection clipboard -t UTF8_STRING &
    sleep 0.5
    "$W" "$OUT/clipfix.exe" get > "$OUT/get.log" 2>/dev/null
    check "X11 text reaches OleGetClipboard" $(tr -d "\r" < "$OUT/get.log" | grep -q "^TEXT $(printf 'local éè 日本' | od -An -tx1 | tr -d ' \n')$" && echo 1 || echo 0)
    "$ROOT/tests/lib/xephyr.sh" stop $D
else
    echo "SKIP X11 round trip (xclip not installed)"
fi
exit $((fail > 0))
