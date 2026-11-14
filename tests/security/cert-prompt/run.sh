#!/bin/bash
# Server-certificate warning test (ADR-0015, ADR-0019), offline against fake-rdp-tls.py.
#   run.sh [SOURCE_PREFIX]   (default: artifacts/prefixes/mstsc-patched; needs mstsc installed)
# Works on a throwaway copy of the prefix. Needs Xephyr (tests/lib/xephyr.sh).
#  1. default settings + untrusted cert: mstsc must not continue past TLS (it warns)
#  2. Default.rdp saved with level 0 by the user is respected
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd); HERE=$ROOT/tests/security/cert-prompt
SRC=${1:-$ROOT/artifacts/prefixes/mstsc-patched}
OUT=$ROOT/artifacts/cert-prompt; rm -rf "$OUT"; mkdir -p "$OUT"
[[ -f $SRC/drive_c/windows/system32/mstsc.exe ]] || { echo "SKIP no mstsc prefix at $SRC"; exit 0; }
cp -a --reflink=auto "$SRC" "$OUT/pfx"
DOC=$OUT/pfx/drive_c/users/$USER/Documents
rm -f "$DOC/Default.rdp"
WINEPREFIX=$OUT/pfx WINEDEBUG=-all "$ROOT/build/install-wine-patched/bin/wine" reg delete \
    'HKCU\Software\Microsoft\Terminal Server Client\Servers' /f >/dev/null 2>&1
WINEPREFIX=$OUT/pfx "$ROOT/build/install-wine-patched/bin/wineserver" -w
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=localhost" \
    -addext "extendedKeyUsage=serverAuth" -keyout "$OUT/key.pem" -out "$OUT/cert.pem" 2>/dev/null
"$ROOT/tests/lib/xephyr.sh" start :5 || exit 1
fail=0
attempt() {   # attempt NAME PORT -> server log in $OUT/NAME.log
    "$HERE/fake-rdp-tls.py" "$2" "$OUT/cert.pem" "$OUT/key.pem" 25 > "$OUT/$1.log" 2>&1 &
    local srv=$!; sleep 1
    DISPLAY=:5 MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state-$1 timeout 22 \
        "$ROOT/launcher/mstsc-wine" run "/v:localhost:$2" >/dev/null 2>&1
    wait $srv
    WINEPREFIX=$OUT/pfx "$ROOT/build/install-wine-patched/bin/wineserver" -k 2>/dev/null
}
check() { if [[ ${2:-0} == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }

attempt default 44480
check "default settings: no data sent after TLS with untrusted cert (warning shown)" \
    $(grep -q 'TLS established' "$OUT/default.log" && ! grep -q 'CLIENT CONTINUED' "$OUT/default.log" && echo 1)

{ printf '\xff\xfe'; printf 'authentication level:i:0\r\n' | iconv -t UTF-16LE; } > "$DOC/Default.rdp"
attempt userzero 44481
check "user-saved level 0 respected (client continues without warning)" \
    $(grep -q 'CLIENT CONTINUED' "$OUT/userzero.log" && echo 1)
echo "$fail failure(s)"
exit $((fail > 0))
