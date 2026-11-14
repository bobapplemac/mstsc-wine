#!/bin/bash
# Run cssclient.exe against the fake NLA endpoint; both credential forms must pass and a
# wrong password must be rejected.   run.sh WINE OUT [PORT]
W=$1 OUT=$2 PORT=${3:-44340}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
python3 -c 'import spnego' 2>/dev/null || { echo "SKIP python3-pyspnego not installed"; exit 0; }
attempt() {   # attempt PORT PASSWORD [packed]
    NTLM_USER_FILE=$OUT/users FAKE_RDP_HOLD=1 "$ROOT/tests/security/credssp/fake-rdp-credssp.py" \
        "$1" "$OUT/cert.pem" "$OUT/key.pem" 20 > "$OUT/server-$1.log" 2>&1 &
    local srv=$!
    for _ in $(seq 20); do (exec 3<>/dev/tcp/127.0.0.1/$1) 2>/dev/null && break; sleep 0.2; done
    wait $srv 2>/dev/null   # the probe consumed a connection; restart for the client
    NTLM_USER_FILE=$OUT/users FAKE_RDP_HOLD=1 "$ROOT/tests/security/credssp/fake-rdp-credssp.py" \
        "$1" "$OUT/cert.pem" "$OUT/key.pem" 20 > "$OUT/server-$1.log" 2>&1 &
    srv=$!; sleep 0.5
    timeout 30 "$W" "$OUT/cssclient.exe" "$1" cssp-test TESTDOM "$2" $3; rc=$?
    kill $srv 2>/dev/null; wait $srv 2>/dev/null
    return $rc
}
attempt $PORT cssp-test-pass-1 || exit 1
grep -q 'password matches' "$OUT/server-$PORT.log" && grep -q 'CLIENT CONTINUED' "$OUT/server-$PORT.log" || { echo "FAIL server did not verify delegation"; exit 1; }
attempt $((PORT+1)) cssp-test-pass-1 packed || exit 1
grep -q 'password matches' "$OUT/server-$((PORT+1)).log" || { echo "FAIL packed credentials"; exit 1; }
if attempt $((PORT+2)) wrong-password >/dev/null; then echo "FAIL wrong password accepted"; exit 1; fi
echo "PASS wrong password rejected"
