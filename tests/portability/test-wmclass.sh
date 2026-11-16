#!/bin/bash
# PKG-022 (automated part): the genuine mstsc main window has WM_CLASS "mstsc.exe", the value
# of StartupWMClass in the desktop entry, so docks group it under the menu entry.
#   test-wmclass.sh APPRUN DISPLAY   (exit 77 = skip)
set -uo pipefail
ENTRY=$(readlink -f "$1"); export DISPLAY=$2
APPDIR=$(dirname "$ENTRY")
command -v xprop >/dev/null && command -v xwininfo >/dev/null || { echo "SKIP xprop/xwininfo"; exit 77; }
T=$(mktemp -d /var/tmp/mstsc-wmclass-XXXX)
X="XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/state XDG_CONFIG_HOME=$T/config XDG_CACHE_HOME=$T/cache"
trap 'WINEPREFIX=$T/data/mstsc-wine/prefix "$APPDIR/usr/lib/mstsc-wine/wine/bin/wineserver" -k 2>/dev/null; rm -rf "$T"' EXIT
env $X timeout 90 "$ENTRY" >/dev/null 2>&1 &
cls=
for _ in $(seq 80); do
    sleep 1
    w=$(xwininfo -root -tree 2>/dev/null | grep -m1 '"Remote Desktop Connection"' | awk '{print $1}')
    [[ -n $w ]] || continue
    cls=$(xprop -id "$w" WM_CLASS 2>/dev/null | sed -n 's/.*= //p'); break
done
echo "WM_CLASS: ${cls:-none}"
grep -q '^Startup' "$APPDIR/org.mstscwine.RemoteDesktopConnection.desktop" || exit 1
want=$(sed -n 's/^StartupWMClass=//p' "$APPDIR/org.mstscwine.RemoteDesktopConnection.desktop")
grep -q "\"$want\"" <<<"$cls"
