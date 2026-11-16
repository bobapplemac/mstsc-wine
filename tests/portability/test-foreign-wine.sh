#!/bin/bash
# PKG-006: another Wine installation (a different build, its own prefix and wineserver,
# running at the same time) is neither used nor disturbed by the packaged runtime, even
# when WINEPREFIX/WINESERVER point at it.   test-foreign-wine.sh APPRUN   (exit 77 = skip)
# The "foreign" Wine is the unmodified Wine 11.0 development build (build/install-wine-11.0).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ENTRY=$(readlink -f "$1"); APPDIR=$(dirname "$ENTRY")
FW=$ROOT/build/install-wine-11.0
[[ -x $FW/bin/wine ]] || { echo "SKIP no foreign Wine build"; exit 77; }
T=$(mktemp -d /var/tmp/mstsc-foreign-XXXX)
cleanup() { WINEPREFIX=$T/foreign "$FW/bin/wineserver" -k 2>/dev/null; WINEPREFIX=$T/xdg/data/mstsc-wine/prefix "$APPDIR/usr/lib/mstsc-wine/wine/bin/wineserver" -k 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
export WINEDEBUG=-all
WINEPREFIX=$T/foreign "$FW/bin/wineboot" -u >/dev/null 2>&1; WINEPREFIX=$T/foreign "$FW/bin/wineserver" -w
# keep the foreign wineserver alive while the package runs
WINEPREFIX=$T/foreign "$FW/bin/wineserver" -p60 >/dev/null 2>&1
# Wine starts wineserver with a bare argv[0]: find it by its executable
srv_pid() { local p; for p in /proc/[0-9]*; do [[ $(readlink "$p/exe" 2>/dev/null) == "$1" ]] && { basename "$p"; return; }; done; }
fpid=$(srv_pid "$(readlink -f "$FW/bin/wineserver")")
[[ -n $fpid ]] || { echo "FAIL foreign wineserver did not start"; exit 1; }
before=$(sha256sum "$T/foreign/system.reg" "$T/foreign/user.reg" | sha256sum)
fail=0
env XDG_DATA_HOME=$T/xdg/data XDG_STATE_HOME=$T/xdg/state XDG_CONFIG_HOME=$T/xdg/config XDG_CACHE_HOME=$T/xdg/cache \
    WINEPREFIX=$T/foreign WINESERVER=$FW/bin/wineserver WINELOADER=$FW/bin/wine WINEDLLPATH=$FW/lib/wine \
    "$ENTRY" exec cmd /c echo ok >/dev/null 2>&1 || { echo "FAIL packaged exec"; fail=1; }
# the package's own server ran for its own prefix (persistent server for the check)
env XDG_DATA_HOME=$T/xdg/data "$ENTRY" --wine-tool wineserver -p30 >/dev/null 2>&1
ppid=$(srv_pid "$(readlink -f "$APPDIR/usr/lib/mstsc-wine/wine/bin/wineserver")")
[[ -n $ppid ]] && echo "ok   packaged wineserver is the bundled one ($(readlink /proc/$ppid/exe | sed "s|$APPDIR|<AppDir>|"))" || { echo "FAIL no bundled wineserver"; fail=1; }
kill -0 "$fpid" 2>/dev/null && echo "ok   foreign wineserver still running" || { echo "FAIL foreign wineserver gone"; fail=1; }
after=$(sha256sum "$T/foreign/system.reg" "$T/foreign/user.reg" | sha256sum)
[[ $before == "$after" ]] && echo "ok   foreign prefix untouched" || { echo "FAIL foreign prefix changed"; fail=1; }
[[ -f $T/xdg/data/mstsc-wine/prefix/system.reg ]] && echo "ok   package used its own prefix" || { echo "FAIL own prefix missing"; fail=1; }
exit $fail
