#!/bin/bash
# Fullscreen -> windowed must release Wine's fullscreen pointer grab (EXP-024, ADR-0019).
#   run.sh WINE OUT [DISPLAY]   (default :9, a private Xephyr running metacity; Wine only
#   grabs the pointer while X focus is on one of its windows, which needs a window manager)
# 1. fullscreen + click: Wine grabs the pointer (precondition)
# 2. same window restored to a normal window: grab released, so the window manager
#    (title-bar buttons) and other clients receive input again
# 3. an application's own ClipCursor rectangle survives the same transition
W=$1 OUT=$2 D=${3:-:9}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
py() { PYTHONPATH=$ROOT/.deps/py python3 "$@"; }
command -v metacity >/dev/null || { echo "SKIP metacity not installed"; exit 0; }
"$ROOT/tests/lib/xephyr.sh" start $D 1024x768 || exit 1
DISPLAY=$D setsid metacity --replace >/dev/null 2>&1 &
wm=$!; sleep 1.5
log=$OUT/fsclip.log; : > "$log"
DISPLAY=$D timeout 40 "$W" "$OUT/fsclip.exe" 4 > "$log" 2>/dev/null &
pid=$!
wait_for() { for _ in $(seq 150); do grep -q "^$1" "$log" && return 0; kill -0 $pid 2>/dev/null || return 1; sleep 0.1; done; return 1; }
fail=0
check() { if [[ $2 == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
grabbed() { sleep 1; py "$ROOT/tools/xgrabbed.py" $D >/dev/null && echo 1 || echo 0; }
if wait_for FULLSCREEN; then
    check "fullscreen window grabs the pointer (precondition)" $(grabbed)
    wait_for WINDOWED
    check "restored window releases the fullscreen grab" $(( 1 - $(grabbed) ))
    wait_for APPCLIP
    check "application ClipCursor rectangle survives restore" $(grep -q '^APPCLIP clip 10,10-512,384' "$log" && echo 1 || echo 0)
    check "application ClipCursor still confines the pointer" $(grabbed)
else
    check "fixture reached fullscreen" 0
fi
wait $pid 2>/dev/null
kill $wm 2>/dev/null
"$ROOT/tests/lib/xephyr.sh" stop $D
sed 's/^/  /' "$log"
exit $((fail > 0))
