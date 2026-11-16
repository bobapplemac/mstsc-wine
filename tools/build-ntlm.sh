#!/bin/bash
# Prepare the private NTLM helper (ADR-0042): fetch the pinned Debian packages, build the
# module-path shim, and stage samba/{bin,lib,smb.conf}. The library closure is collected
# by tools/assemble-appdir.sh, because it shares GnuTLS and Kerberos with Wine.
#   tools/build-ntlm.sh [STAGE]     (default $MSTSC_BUILD_DIR/stage/samba, MSTSC_BUILD_DIR default build/)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=${MSTSC_BUILD_DIR:-$ROOT/build}
STAGE=${1:-$BUILD/stage/samba}
DEB=$BUILD/debroot
"$ROOT/tools/fetch-debs.sh" "$DEB"
[[ -x $DEB/usr/bin/ntlm_auth ]] || { echo "build-ntlm: ntlm_auth missing from the winbind package" >&2; exit 1; }
rm -rf "$STAGE"; mkdir -p "$STAGE/bin" "$STAGE/lib/modules"
cp "$DEB/usr/bin/ntlm_auth" "$STAGE/bin/ntlm_auth.bin"
install -m 755 "$ROOT/packaging/samba/ntlm_auth.in" "$STAGE/bin/ntlm_auth"
install -m 644 "$ROOT/packaging/samba/smb.conf" "$STAGE/smb.conf"
${CC:-gcc} -O2 -g0 -shared -fPIC -Wall -Werror -o "$STAGE/lib/libmstsc-samba-paths.so" \
    "$ROOT/packaging/samba/mstsc-samba-paths.c" -ldl
echo "build-ntlm: staged $(grep '^winbind ' "$DEB/.packages" | cut -d' ' -f1-2) ntlm_auth in $STAGE"
