#!/bin/bash
# Regenerate packaging/debian-binaries.lock from APT's signature-verified package indices
# (run on Debian 13 with up-to-date trixie and trixie-security sources, after `apt update`).
# Each line: PACKAGE VERSION SHA256 POOL_PATH. The build fetches exactly these files and
# checks the hashes (tools/fetch-debs.sh); this script is the only place versions change.
#   tools/update-debian-lock.sh            -> rewrite the lock with the candidate versions
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK=$ROOT/packaging/debian-binaries.lock
pkgs=$(sed -n 's/^#pkg //p' "$LOCK")
{
    sed -n '/^#/{/^#snapshot /d;p}' "$LOCK"
    echo "#snapshot $(date -u +%Y%m%dT%H%M%SZ)"
    for p in $pkgs; do
        v=$(apt-cache policy "$p" | awk '/Candidate:/{print $2}')
        [[ -n $v && $v != "(none)" ]] || { echo "no candidate for $p" >&2; exit 1; }
        apt-cache show "$p=$v" | awk -v p="$p" -v v="$v" '
            /^Filename:/{f=$2} /^SHA256:/{h=$2} /^$/{if(f&&h){print p, v, h, f; exit}}
            END{if(f&&h)print p, v, h, f}' | head -1
    done
} > "$LOCK.new"
mv "$LOCK.new" "$LOCK"
echo "updated $LOCK"
