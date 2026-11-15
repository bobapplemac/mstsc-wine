#!/bin/sh
# Type test credentials into the credential prompt on a nested display:
#   enter-credentials.sh :5 USER PASSWORD [TIMEOUT]
# Only for throwaway test accounts on local fixtures; never real credentials.
d=$1 user=$2 pass=$3 t=${4:-60}
root=$(cd "$(dirname "$0")/../.." && pwd)
py() { PYTHONPATH=$root/.deps/py python3 "$@"; }
geo=$(py "$root/tools/xwait.py" "$d" '^Enter your credentials$' "$t") || { echo "no credential prompt" >&2; exit 1; }
set -- $geo; x=$1 y=$2 b=$(($2 + $4))
sleep 0.5
# measured from the bottom edge: a long message grows the dialog above the fields
py "$root/tools/xclick.py" "$d" click $((x + 214)) $((b - 130))
py "$root/tools/xclick.py" "$d" type "$user"
py "$root/tools/xclick.py" "$d" click $((x + 214)) $((b - 102))
py "$root/tools/xclick.py" "$d" type "$pass"
py "$root/tools/xclick.py" "$d" click $((x + 182)) $((b - 23))
