#!/bin/bash
# Run tlsclient.exe against openssl s_server presenting the fixture certificate with
# ECDHE_RSA (the server signs the key exchange with a key not marked for signing).
#   run.sh WINE OUT [PORT]
W=$1 OUT=$2 PORT=${3:-44330}
openssl s_server -accept 127.0.0.1:$PORT -cert "$OUT/cert.pem" -key "$OUT/key.pem" \
    -tls1_2 -cipher ECDHE-RSA-AES256-GCM-SHA384 -naccept 1 -quiet </dev/null >/dev/null 2>&1 &
srv=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break; sleep 0.3; done
# the probe above consumed the single accept; restart for the real client
wait $srv 2>/dev/null
openssl s_server -accept 127.0.0.1:$PORT -cert "$OUT/cert.pem" -key "$OUT/key.pem" \
    -tls1_2 -cipher ECDHE-RSA-AES256-GCM-SHA384 -naccept 1 -quiet </dev/null >/dev/null 2>&1 &
srv=$!; sleep 0.5
timeout 30 "$W" "$OUT/tlsclient.exe" $PORT; rc=$?
kill $srv 2>/dev/null; wait $srv 2>/dev/null
exit $rc
