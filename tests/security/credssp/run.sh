#!/bin/bash
# NLA end to end with the genuine mstsc (ADR-0018), offline against fake-rdp-credssp.py.
#   run.sh [SOURCE_PREFIX]   (default: artifacts/prefixes/mstsc-patched; needs mstsc installed)
# Works on a throwaway copy of the prefix. Needs Xephyr and python3-pyspnego.
#  1. mstsc requests HYBRID, shows the credential prompt, completes CredSSP; the server
#     verifies the delegated password and receives the MCS Connect Initial.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd); HERE=$ROOT/tests/security/credssp
SRC=${1:-$ROOT/artifacts/prefixes/mstsc-patched}
OUT=$ROOT/artifacts/credssp-gui; rm -rf "$OUT"; mkdir -p "$OUT"
[[ -f $SRC/drive_c/windows/system32/mstsc.exe ]] || { echo "SKIP no mstsc prefix at $SRC"; exit 0; }
python3 -c 'import spnego' 2>/dev/null || { echo "SKIP python3-pyspnego not installed"; exit 0; }
cp -a --reflink=auto "$SRC" "$OUT/pfx"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=localhost" \
    -addext "extendedKeyUsage=serverAuth" -keyout "$OUT/key.pem" -out "$OUT/cert.pem" 2>/dev/null
echo "TESTDOM:nla-test:nla-test-pass-1" > "$OUT/users"
"$ROOT/tests/lib/xephyr.sh" start :5 || exit 1
PORT=44490
NTLM_USER_FILE=$OUT/users FAKE_RDP_HOLD=3 "$HERE/fake-rdp-credssp.py" $PORT "$OUT/cert.pem" "$OUT/key.pem" 60 > "$OUT/server.log" 2>&1 &
srv=$!; sleep 1
DISPLAY=:5 MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state timeout 55 \
    "$ROOT/launcher/mstsc-wine" run "/v:localhost:$PORT" >/dev/null 2>&1 &
cli=$!
fail=0
"$ROOT/tests/lib/enter-credentials.sh" :5 'TESTDOM\nla-test' 'nla-test-pass-1' 45 || fail=1
for _ in $(seq 40); do grep -q 'CLIENT CONTINUED\|connection ended' "$OUT/server.log" && break; sleep 0.5; done
kill $cli 2>/dev/null; WINEPREFIX=$OUT/pfx "$ROOT/build/install-wine-patched/bin/wineserver" -k 2>/dev/null
kill $srv 2>/dev/null; wait 2>/dev/null
check() { if [[ ${2:-0} == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
req=$(grep -o 'requestedProtocols=[0-9]*' "$OUT/server.log" | head -1 | cut -d= -f2)
check "client offered HYBRID (CredSSP)" $(( ${req:-0} & 2 ? 1 : 0 ))
check "CredSSP completed and delegated the right password" $(grep -q 'CREDSSP COMPLETE.*password matches' "$OUT/server.log" && echo 1)
check "RDP continued over the CredSSP channel (MCS Connect Initial)" $(grep -q 'CLIENT CONTINUED.*first byte 0x03' "$OUT/server.log" && echo 1)
echo "$fail failure(s)"
exit $((fail > 0))
