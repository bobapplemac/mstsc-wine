#!/bin/sh
# Type test credentials into the credential prompt on a nested display:
#   enter-credentials.sh :5 USER PASSWORD [TIMEOUT]
# Only for throwaway test accounts on local fixtures; never real credentials.
d=$1 user=$2 pass=$3 t=${4:-60}
root=$(cd "$(dirname "$0")/../.." && pwd)
py() { PYTHONPATH=$root/.deps/py python3 "$@"; }
geo=$(py "$root/tools/xwait.py" "$d" '^Enter your credentials$' "$t") || { echo "no credential prompt" >&2; exit 1; }
set -- $geo; x=$1 y=$2
sleep 0.5
py "$root/tools/xclick.py" "$d" click $((x + 214)) $((y + 112))
py "$root/tools/xclick.py" "$d" type "$user"
py "$root/tools/xclick.py" "$d" click $((x + 214)) $((y + 140))
py "$root/tools/xclick.py" "$d" type "$pass"
py "$root/tools/xclick.py" "$d" click $((x + 182)) $((y + 219))
