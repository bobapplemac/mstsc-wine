#!/bin/sh
# Click "Yes" in mstsc's certificate warning on a nested display (ADR-0048): the local test
# servers use self-signed certificates, so over NLA mstsc asks before delegating.
#   accept-cert-warning.sh :N [TIMEOUT]     exit 1 if no warning appeared
d=$1 t=${2:-40}
root=$(cd "$(dirname "$0")/../.." && pwd)
py() { PYTHONPATH=$root/.deps/py python3 "$@"; }
# the warning has the main dialog's title but is taller than it
geo=$(py "$root/tools/xfindwin.py" "$d" 'Remote Desktop Connection' 350 300 "$t") || exit 1
set -- $geo
sleep 1
# "Yes" sits left of "No" in the bottom-right corner
py "$root/tools/xclick.py" "$d" click $(( $1 + $3 - 131 )) $(( $2 + $4 - 25 ))
