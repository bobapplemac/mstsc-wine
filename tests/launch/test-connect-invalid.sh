#!/bin/bash
# GUI smoke test (Xephyr): `mstsc /v:rdp-test.invalid` must reach name resolution
# of the target on port 3389 and not abort. On Windows, the user then sees "Remote Desktop
# can't find the computer". Needs imported components and an initialized prefix.
#   DISPLAY=:5 tests/launch/test-connect-invalid.sh   (env as for launcher/mstsc-wine)
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${DISPLAY:?run inside the nested display (tests/lib/xephyr.sh start :5)}"
export MSTSC_WINE_DLLOVERRIDES=${MSTSC_WINE_DLLOVERRIDES:-winedbg.exe=d}
export MSTSC_WINE_TRACE='+winsock'   # fake .invalid hostname only; no credentials involved
timeout 40 "$ROOT/launcher/mstsc-wine" /v:rdp-test.invalid >/dev/null 2>&1 &
pid=$!
log=""
for _ in $(seq 30); do
    sleep 1
    log=$(ls -t "${MSTSC_WINE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/mstsc-wine}"/logs/*-mstsc.log 2>/dev/null | head -1)
    [[ -n $log ]] && grep -aq 'GetAddrInfoW nodename L"rdp-test.invalid", servname L"3389"' "$log" && break
done
fails=0
if [[ -n $log ]] && grep -aq 'GetAddrInfoW nodename L"rdp-test.invalid", servname L"3389"' "$log"; then
    echo "ok   connect: resolves target on port 3389"
else echo "FAIL connect: target name was never resolved"; fails=1; fi
if [[ -n $log ]] && grep -aq 'unimplemented function' "$log"; then
    echo "FAIL connect: $(grep -a -m1 -o 'unimplemented function [^ ,]*' "$log")"; fails=1
else echo "ok   connect: no unimplemented function called"; fi
pkill -f '^C:.windows.system32.mstsc' 2>/dev/null; wait $pid 2>/dev/null
echo "$fails failure(s)"; exit $fails
