#!/bin/bash
# Genuine mstsc: fullscreen session -> connection-bar "Restore" -> window-manager Maximize
# must return to fullscreen (EXP-024, ADR-0019).
#   DISPLAY is not used; the test runs on its own nested displays.
#   test-fullscreen-restore.sh [SOURCE_PREFIX]   (default artifacts/prefixes/mstsc-patched)
# Endpoint: a local RDP *server* (FreeRDP shadow server sharing a private Xvfb) with an NLA
# test account. Only the server side is FreeRDP; the client is the genuine mstsc on Wine.
# Needs Xephyr, Xvfb, freerdp3-shadow-x11, a window manager (muffin or metacity), wmctrl.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SRC=${1:-$ROOT/artifacts/prefixes/mstsc-patched}
OUT=$ROOT/artifacts/fullscreen-restore; D=:6 RD=:7 PORT=33890
py() { PYTHONPATH=$ROOT/.deps/py python3 "$@"; }
[[ -f $SRC/drive_c/windows/system32/mstsc.exe ]] || { echo "SKIP no mstsc prefix at $SRC"; exit 0; }
for t in Xvfb freerdp-shadow-cli3 wmctrl; do command -v $t >/dev/null || { echo "SKIP $t not installed"; exit 0; }; done
WM=$(command -v muffin || command -v metacity) || { echo "SKIP no window manager"; exit 0; }
rm -rf "$OUT"; mkdir -p "$OUT"; cp -a --reflink=auto "$SRC" "$OUT/pfx"
cleanup() {
    WINEPREFIX=$OUT/pfx "$ROOT/build/install-wine-patched/bin/wineserver" -k 2>/dev/null
    kill ${pids[@]} 2>/dev/null; "$ROOT/tests/lib/xephyr.sh" stop $D
}
pids=(); trap cleanup EXIT

# client display with a window manager
"$ROOT/tests/lib/xephyr.sh" start $D 1280x800 || exit 1
DISPLAY=$D setsid "$WM" --replace >/dev/null 2>&1 & pids+=($!); sleep 3
read -r W H < <(DISPLAY=$D xdpyinfo | awk '/dimensions/{split($2,a,"x"); print a[1], a[2]}')

# server: private Xvfb of the same size, shared over RDP with an NLA test account
NT=$(printf '%s' 'fs-test-pass-1' | iconv -t UTF-16LE | openssl dgst -md4 -provider legacy -provider default | awk '{print $2}')
echo "fs-test:TESTDOM::$NT:::" > "$OUT/SAM"
Xvfb $RD -screen 0 ${W}x${H}x24 -nolisten tcp >/dev/null 2>&1 & pids+=($!); sleep 1
DISPLAY=$RD xsetroot -solid '#336699'
DISPLAY=$RD xlogo -geometry 300x300+100+100 >/dev/null 2>&1 & pids+=($!)
(cd "$OUT" && DISPLAY=$RD exec freerdp-shadow-cli3 /port:$PORT /sam-file:"$OUT/SAM" /bind-address:127.0.0.1 > "$OUT/server.log" 2>&1) & pids+=($!)
sleep 2

DISPLAY=$D MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state setsid \
    "$ROOT/launcher/mstsc-wine" run /v:127.0.0.1:$PORT >/dev/null 2>&1 &
fail=0
check() { if [[ ${2:-0} == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
state() { DISPLAY=$D xprop -id "$(DISPLAY=$D wmctrl -l | awk '/127.0.0.1:'$PORT' - Remote Desktop/{print $1; exit}')" _NET_WM_STATE 2>/dev/null; }
"$ROOT/tests/lib/enter-credentials.sh" $D 'TESTDOM\fs-test' 'fs-test-pass-1' 60 || { check "credential prompt" 0; exit 1; }
for _ in $(seq 60); do state | grep -q FULLSCREEN && break; sleep 0.5; done; sleep 3
check "session starts fullscreen" $(state | grep -q FULLSCREEN && echo 1)
py "$ROOT/tools/xshot.py" $D "$OUT/1-fullscreen.png"

py "$ROOT/tools/xclick.py" $D click $((W / 2 + 223)) 9      # connection bar: Restore
sleep 3
check "Restore leaves fullscreen" $(state | grep -q FULLSCREEN || echo 1)
check "pointer is not grabbed after Restore" $(py "$ROOT/tools/xgrabbed.py" $D >/dev/null || echo 1)
py "$ROOT/tools/xshot.py" $D "$OUT/2-restored.png"

# window manager Maximize button (top-right of the frame, as a user would click it)
read -r x y w h < <(py "$ROOT/tools/xwait.py" $D "^127.0.0.1:$PORT - Remote" 5)
py "$ROOT/tools/xclick.py" $D click $((x + w - 52)) $((y - 18))
for _ in $(seq 10); do state | grep -q FULLSCREEN && break; sleep 0.5; done
check "Maximize returns to fullscreen" $(state | grep -q FULLSCREEN && echo 1)
py "$ROOT/tools/xshot.py" $D "$OUT/3-maximized.png"
echo "$fail failure(s)"
exit $((fail > 0))
