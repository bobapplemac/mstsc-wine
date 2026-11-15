#!/bin/bash
# Throwaway MIT Kerberos realm for offline tests (no root, nothing installed system-wide).
#   kdc.sh start OUT [PORT]   -> OUT/krb5.conf, OUT/server.keytab, KDC on 127.0.0.1:PORT
#   kdc.sh stop OUT
# Realm MSTSC.TEST; principals: nla-test (password nla-test-pass-1, test account only)
# and TERMSRV/localhost (key in OUT/server.keytab). Uses the MIT KDC unpacked under
# .deps/krb5kdc/root (tools/fetch-krb5kdc.sh).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
K=$ROOT/.deps/krb5kdc/root
cmd=$1 OUT=$(mkdir -p "$2" && cd "$2" && pwd) PORT=${3:-18888}   # absolute: the KDC changes to /
export LD_LIBRARY_PATH=$K/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export KRB5_CONFIG=$OUT/krb5.conf KRB5_KDC_PROFILE=$OUT/kdc.conf
case $cmd in
stop)
    [[ -f $OUT/kdc.pid ]] && kill "$(cat "$OUT/kdc.pid")" 2>/dev/null; rm -f "$OUT/kdc.pid"; exit 0;;
start) ;;
*) echo "usage: kdc.sh start|stop OUT [PORT]" >&2; exit 2;;
esac
[[ -x $K/usr/sbin/krb5kdc ]] || { echo "SKIP no MIT KDC under $K (run tools/fetch-krb5kdc.sh)"; exit 3; }
mkdir -p "$OUT/db"
cat > "$OUT/krb5.conf" <<CONF
[libdefaults]
    # no default_realm, like a machine outside the domain (ADR-0027)
    dns_lookup_kdc = false
    dns_lookup_realm = false
    rdns = false
    udp_preference_limit = 1
[realms]
    MSTSC.TEST = {
        kdc = 127.0.0.1:$PORT
    }
[domain_realm]
    localhost = MSTSC.TEST
[dbmodules]
    db_module_dir = $K/usr/lib/x86_64-linux-gnu/krb5/plugins/kdb
CONF
cat > "$OUT/kdc.conf" <<CONF
[kdcdefaults]
    kdc_listen = 127.0.0.1:$PORT
    kdc_tcp_listen = 127.0.0.1:$PORT
[realms]
    MSTSC.TEST = {
        database_name = $OUT/db/principal
        key_stash_file = $OUT/db/stash
        acl_file = $OUT/db/kadm5.acl
        supported_enctypes = aes256-cts-hmac-sha1-96:normal aes128-cts-hmac-sha1-96:normal
    }
[dbmodules]
    db_module_dir = $K/usr/lib/x86_64-linux-gnu/krb5/plugins/kdb
[logging]
    kdc = FILE:$OUT/kdc.log
CONF
touch "$OUT/db/kadm5.acl"
"$K/usr/sbin/kdb5_util" -r MSTSC.TEST -P kdc-master-test-1 create -s >"$OUT/setup.log" 2>&1 || { cat "$OUT/setup.log"; exit 1; }
ka() { "$K/usr/sbin/kadmin.local" -r MSTSC.TEST -q "$1" >>"$OUT/setup.log" 2>&1; }
ka "addprinc -pw nla-test-pass-1 nla-test"
ka "addprinc -randkey TERMSRV/localhost"
ka "ktadd -k $OUT/server.keytab TERMSRV/localhost"
"$K/usr/sbin/krb5kdc" -r MSTSC.TEST -P "$OUT/kdc.pid" >>"$OUT/setup.log" 2>&1 || { cat "$OUT/setup.log"; exit 1; }
for _ in $(seq 20); do [[ -s $OUT/kdc.pid ]] && break; sleep 0.2; done
echo "KDC MSTSC.TEST on 127.0.0.1:$PORT"
