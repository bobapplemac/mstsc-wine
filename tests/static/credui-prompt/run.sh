#!/bin/bash
# The credential prompt must return a user name typed without a domain unchanged; it must
# not be completed with the caption ("Enter your credentials\Administrator", EXP-035), and
# it must show a long message (mstsc's re-prompt) in full, wrapped. Asked again after a
# failed logon, the password field must be empty, as on Windows (EXP-039).
#   run.sh WINE OUT [DISPLAY]   (default :9, a private Xephyr)
W=$1 OUT=$2 D=${3:-:9}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
"$ROOT/tests/lib/xephyr.sh" start $D 1024x768 >/dev/null || exit 1
log=$OUT/credprompt.log
DISPLAY=$D timeout 40 "$W" "$OUT/credprompt.exe" > "$log" 2>/dev/null &
pid=$!
"$ROOT/tests/lib/enter-credentials.sh" $D 'Administrator' 'prompt-test-pass-1' 30
wait $pid
DISPLAY=$D timeout 40 "$W" "$OUT/credprompt.exe" reprompt > "$OUT/reprompt.log" 2>/dev/null
"$ROOT/tests/lib/xephyr.sh" stop $D >/dev/null
fail=0
check() { if [[ $2 == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
check "user name without a domain is returned as typed" $(tr -d "\r" < "$log" | grep -qx "USER Administrator" && echo 1 || echo 0)
check "long message is shown in full" $(tr -d "\r" < "$log" | grep -qx "MESSAGE FITS" && echo 1 || echo 0)
check "re-prompt after a failed logon leaves the password empty" $(tr -d "\r" < "$OUT/reprompt.log" | grep -qx "PASSWORD EMPTY" && echo 1 || echo 0)
grep -q '^USER' "$log" && grep -q '^MESSAGE FITS' "$log" || cat "$log"
grep -q '^PASSWORD EMPTY' "$OUT/reprompt.log" || cat "$OUT/reprompt.log"
exit $((fail > 0))
