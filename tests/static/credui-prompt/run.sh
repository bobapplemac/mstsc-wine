#!/bin/bash
# The credential prompt must return a user name typed without a domain unchanged; it must
# not be completed with the caption ("Enter your credentials\Administrator", EXP-035).
#   run.sh WINE OUT [DISPLAY]   (default :9, a private Xephyr)
W=$1 OUT=$2 D=${3:-:9}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
"$ROOT/tests/lib/xephyr.sh" start $D 1024x768 >/dev/null || exit 1
log=$OUT/credprompt.log
DISPLAY=$D timeout 40 "$W" "$OUT/credprompt.exe" > "$log" 2>/dev/null &
pid=$!
"$ROOT/tests/lib/enter-credentials.sh" $D 'Administrator' 'prompt-test-pass-1' 30
wait $pid
"$ROOT/tests/lib/xephyr.sh" stop $D >/dev/null
fail=0
check() { if [[ $2 == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
check "user name without a domain is returned as typed" $(tr -d "\r" < "$log" | grep -qx "USER Administrator" && echo 1 || echo 0)
grep -q '^USER' "$log" || cat "$log"
exit $((fail > 0))
