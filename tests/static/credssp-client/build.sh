#!/bin/sh
# Build the CredSSP client fixture into OUT (default ./out).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=${1:-$here/out}
mkdir -p "$out"
x86_64-w64-mingw32-gcc -O2 "$here/cssclient.c" -o "$out/cssclient.exe" -lsecur32 -lws2_32
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=localhost" \
    -addext "extendedKeyUsage=serverAuth" -keyout "$out/key.pem" -out "$out/cert.pem" 2>/dev/null
echo "TESTDOM:cssp-test:cssp-test-pass-1" > "$out/users"
