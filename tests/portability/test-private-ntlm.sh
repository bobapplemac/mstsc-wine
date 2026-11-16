#!/bin/bash
# PKG-005: an NTLM CredSSP logon through the packaged runtime uses the bundled ntlm_auth:
# host Samba (ntlm_auth, its libraries, smb.conf, winbindd) is hidden with bwrap and a decoy
# ntlm_auth that would fail is first on PATH.   test-private-ntlm.sh APPRUN_OR_APPIMAGE
# Uses tests/static/credssp-client (fake NLA server, needs python3-pyspnego). Exit 77 = skip.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ENTRY=$(readlink -f "$1")
python3 -c 'import spnego' 2>/dev/null || { echo "SKIP python3-pyspnego"; exit 77; }
command -v bwrap >/dev/null || { echo "SKIP bwrap"; exit 77; }
[[ -d $ROOT/.deps/sysroot ]] && . "$ROOT/tools/build-env.sh" >/dev/null
CSSP=$ROOT/artifacts/credssp-client
"$ROOT/tests/static/credssp-client/build.sh" "$CSSP" >/dev/null 2>&1 || { echo "SKIP fixture build failed"; exit 77; }
T=$(mktemp -d /var/tmp/mstsc-ntlm-XXXX); trap 'WINEPREFIX=$T/pfx "$T/shim/bin/wineserver" -k 2>/dev/null; rm -rf "$T"' EXIT
"$ROOT/tests/portability/runtime-shim.sh" "$ENTRY" "$T/shim"
mkdir -p "$T/decoy"; printf '#!/bin/sh\ntouch %s/decoy-ran\nexit 1\n' "$T" > "$T/decoy/ntlm_auth"; chmod +x "$T/decoy/ntlm_auth"
a=(--dev-bind / /)
for p in /usr/lib/x86_64-linux-gnu/samba /etc/samba /var/lib/samba /run/samba; do [[ -d $p ]] && a+=(--tmpfs "$p"); done
for p in /usr/bin/ntlm_auth /usr/sbin/winbindd; do [[ -e $p ]] && a+=(--ro-bind /dev/null "$p"); done
WINEPREFIX=$T/pfx PATH="$T/decoy:$PATH" WINEDEBUG=-all WINEDLLOVERRIDES=winedbg.exe=d \
    bwrap "${a[@]}" "$ROOT/tests/static/credssp-client/run.sh" "$T/shim/bin/wine" "$CSSP" 44460 || exit 1
[[ ! -e $T/decoy-ran ]] || { echo "FAIL the decoy ntlm_auth ran"; exit 1; }
echo "PASS NTLM through the bundled helper, host Samba hidden"
