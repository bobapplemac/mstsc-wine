#!/bin/bash
# Wine normally leaves classic ETW/WPP providers disabled. The mstsc-wine diagnostic
# patch enables them only with +wpp and writes event IDs and arguments to Wine's log.
set -euo pipefail
W=${1:?wine executable}; OUT=${2:?fixture output directory}
log=$OUT/wpp-trace.log
WINEDEBUG=+wpp "$W" "$OUT/wpp-trace.exe" >"$log" 2>&1
tr -d '\r' <"$log" | grep -qx 'CALLBACK code=4 handle=deadbeef flags=ffffffff level=5'
grep -q 'trace:wpp:EtwTraceMessageVa .*provider {12345678-1234-5678-90ab-cdef01020304} event 42 ' "$log"
grep -q 'trace:wpp:EtwTraceMessageVa   arg 0 size 4 data ' "$log"
