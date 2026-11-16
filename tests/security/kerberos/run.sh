#!/bin/bash
# CredSSP with Kerberos, offline: cssclient.exe (tests/static/credssp-client) against
# fake-rdp-credssp.py holding the keytab of a throwaway MIT realm (kdc.sh). The realm has no
# default_realm configured, like a machine outside the domain.   run.sh WINE OUT [PORT]
#  - user principal name with a lower-case realm, and domain + user: Kerberos is used, the
#    server verifies the delegated password, RDP continues (ADR-0025/0026/0027)
#  - the user's default credential cache is not written (ADR-0028)
#  - Kerberos authenticates the server (CREDSSP_SERVER_AUTH_NEGOTIATE): no warning (ADR-0048)
#  - a wrong password is rejected with STATUS_LOGON_FAILURE as the last status (ADR-0022)
W=$1 OUT=$2 PORT=${3:-44620}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd); HERE=$ROOT/tests/security/kerberos
[[ -d $ROOT/.deps/sysroot ]] && . "$ROOT/tools/build-env.sh" >/dev/null   # mingw for the client
python3 -c 'import spnego, gssapi' 2>/dev/null || { echo "SKIP python3-pyspnego or python3-gssapi not installed"; exit 0; }
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
"$HERE/kdc.sh" start "$OUT/realm" $((PORT + 100)) >/dev/null; rc=$?
[[ $rc == 3 ]] && { echo "SKIP no MIT KDC (tools/fetch-krb5kdc.sh)"; exit 0; }
[[ $rc == 0 ]] || { echo "FAIL KDC did not start"; exit 1; }
trap '"$HERE/kdc.sh" stop "$OUT/realm"' EXIT
"$ROOT/tests/static/credssp-client/build.sh" "$OUT" >/dev/null 2>&1 || { echo "FAIL client build"; exit 1; }
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=localhost" -addext "extendedKeyUsage=serverAuth" \
    -keyout "$OUT/key.pem" -out "$OUT/cert.pem" 2>/dev/null
echo "MSTSC.TEST:nla-test:nla-test-pass-1" > "$OUT/users"
export KRB5_CONFIG=$OUT/realm/krb5.conf
fail=0
check() { if [[ $2 == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
attempt() {   # attempt N USER DOMAIN PASSWORD -> client output; server log in OUT/server-N.log
    local port=$((PORT + $1)) srv
    KRB5_KTNAME=$OUT/realm/server.keytab NTLM_USER_FILE=$OUT/users FAKE_RDP_HOLD=1 \
        "$ROOT/tests/security/credssp/fake-rdp-credssp.py" $port "$OUT/cert.pem" "$OUT/key.pem" 25 > "$OUT/server-$1.log" 2>&1 &
    srv=$!; sleep 1.5
    rm -f "$OUT/default-cc"
    KRB5CCNAME=FILE:$OUT/default-cc timeout 30 "$W" "$OUT/cssclient.exe" $port "$2" "$3" "$4" 2>/dev/null | tr -d '\r'
    kill $srv 2>/dev/null; wait $srv 2>/dev/null
}
kerberos_ok() { grep -q 'CREDSSP COMPLETE.*mechanism kerberos.*password matches' "$OUT/server-$1.log" &&
                grep -q 'CLIENT CONTINUED' "$OUT/server-$1.log" && echo 1; }
out=$(attempt 1 nla-test@mstsc.test '' nla-test-pass-1)
check "user principal name: Kerberos, password delegated" $(kerberos_ok 1)
# Kerberos authenticates the server: no certificate warning, as on Windows (ADR-0048)
check "Kerberos counts as server authentication (no certificate warning)" \
    $(grep -q 'server auth flags 0x1' <<< "$out" && ! grep -q 'refused before delegation' <<< "$out" && echo 1)
check "default credential cache left alone" $([[ -e $OUT/default-cc ]] || echo 1)
attempt 2 nla-test mstsc.test nla-test-pass-1 >/dev/null
check "domain + user name: Kerberos, password delegated" $(kerberos_ok 2)
out=$(attempt 3 nla-test MSTSC.TEST wrong-password-1)
check "wrong password: STATUS_LOGON_FAILURE" $(grep -q 'last status 0xc000006d' <<< "$out" && echo 1)
echo "$fail failure(s)"
exit $((fail > 0))
