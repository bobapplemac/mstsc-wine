#!/bin/sh
# Build the Schannel key-usage fixture into OUT (default ./out):
#   tlsclient.exe, plus an RDP-style self-signed RSA certificate whose keyUsage is
#   keyEncipherment+dataEncipherment only (no digitalSignature).
set -e
here=$(cd "$(dirname "$0")" && pwd); out=${1:-$here/out}
mkdir -p "$out"
x86_64-w64-mingw32-gcc -O2 "$here/tlsclient.c" -o "$out/tlsclient.exe" -lsecur32 -lws2_32
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=localhost" \
    -addext "keyUsage=critical,keyEncipherment,dataEncipherment" \
    -addext "extendedKeyUsage=serverAuth" \
    -keyout "$out/key.pem" -out "$out/cert.pem" 2>/dev/null
