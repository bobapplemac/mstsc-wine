#!/bin/bash
# PKG-001: a fresh checkout of the committed repository plus the operator's ZIP builds the
# AppDir with the documented `make` (Docker engine by default). Long: compiles Wine.
#   tests/portability/test-fresh-build.sh [make arguments...]   e.g. DOCKER='sudo docker'
# The clone lives in /var/tmp and is removed afterwards; the ZIP is passed by path
# (MICROSOFT_COMPONENTS), never copied into the clone. Exit 77 = skip.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ZIP=${MICROSOFT_COMPONENTS:-$(ls "$ROOT"/private-input/mstsc-components-*.zip 2>/dev/null | head -1)}
[[ -f $ZIP ]] || { echo "SKIP no component ZIP"; exit 77; }
T=$(mktemp -d /var/tmp/mstsc-fresh-XXXX); trap 'rm -rf "$T"' EXIT
git clone -q "$ROOT" "$T/mstsc-wine" || exit 1
cd "$T/mstsc-wine"
echo "fresh checkout of $(git rev-parse --short HEAD); untracked files: $(git status --porcelain | wc -l)"
start=$(date +%s)
make MICROSOFT_COMPONENTS="$ZIP" "$@" > "$T/make.log" 2>&1 || { tail -30 "$T/make.log"; echo "FAIL make"; exit 1; }
echo "make took $(( ($(date +%s) - start) / 60 )) min"
A=artifacts/MSTSC-Wine.AppDir
[[ -x $A/AppRun ]] || { echo "FAIL no AppDir"; exit 1; }
DISPLAY=${DISPLAY:-:0} XDG_DATA_HOME=$T/xdg/data XDG_STATE_HOME=$T/xdg/state "$A/AppRun" doctor || { echo "FAIL doctor"; exit 1; }
grep -q '"build_engine"' "$A/usr/share/mstsc-wine/metadata/build-info.json" && echo "PASS fresh checkout builds the AppDir"
WINEPREFIX=$T/xdg/data/mstsc-wine/prefix "$A/usr/lib/mstsc-wine/wine/bin/wineserver" -k 2>/dev/null
exit 0
