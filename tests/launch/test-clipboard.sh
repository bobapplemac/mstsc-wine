#!/bin/bash
# Genuine mstsc: clipboard redirection (cliprdr) between the X11 desktop and the remote
# session, both directions (spec F-006/F-007, T-010..T-012).
#   test-clipboard.sh [SOURCE_PREFIX] [RUNTIME] [LAUNCHER]
#   (defaults: artifacts/prefixes/mstsc-patched, build/install-wine-patched, launcher/mstsc-wine)
#   Packaged runtime (PKG-016): RUNTIME=<dir from tests/portability/runtime-shim.sh>,
#   LAUNCHER=<AppDir>/AppRun or the AppImage; the package's own launcher then runs mstsc.
# Endpoint: tests/clipboard/server/cliprdr-shadow.c, the FreeRDP shadow server with a
# cliprdr server channel attached. Only the server side is FreeRDP; the client is the
# genuine mstsc on Wine. The server stands in for rdpclip.exe on the remote host: it
# "pastes" whatever the client offers and "copies" what the test tells it to.
# Needs Xephyr, Xvfb, freerdp3-shadow-x11, freerdp3-dev (to build the server), xclip,
# python3-xlib, a window manager (muffin or metacity).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SRC=${1:-$ROOT/artifacts/prefixes/mstsc-patched}
RT=${2:-$ROOT/build/install-wine-patched}
LAUNCHER=${3:-}
OUT=$ROOT/artifacts/clipboard-test; D=:8 RD=:9 PORT=33892
py() { PYTHONPATH=$ROOT/.deps/py python3 "$@"; }
[[ -f $SRC/drive_c/windows/system32/mstsc.exe ]] || { echo "SKIP no mstsc prefix at $SRC"; exit 0; }
for t in Xvfb Xephyr xclip cc; do command -v $t >/dev/null || { echo "SKIP $t not installed"; exit 0; }; done
[[ -f /usr/include/freerdp3/freerdp/server/cliprdr.h ]] || { echo "SKIP freerdp3-dev not installed"; exit 0; }
WM=$(command -v muffin || command -v metacity) || { echo "SKIP no window manager"; exit 0; }
rm -rf "$OUT"; mkdir -p "$OUT"
SRV=$OUT/cliprdr-shadow
cc -O1 -g -Wno-deprecated-declarations -I/usr/include/freerdp3 -I/usr/include/winpr3 -o "$SRV" \
    "$ROOT/tests/clipboard/server/cliprdr-shadow.c" -lfreerdp-shadow3 -lfreerdp-shadow-subsystem3 \
    -lfreerdp-server3 -lfreerdp3 -lwinpr3 -lpthread 2>"$OUT/cc.log" || { echo "FAIL building the test server"; cat "$OUT/cc.log"; exit 1; }
cp -a --reflink=auto "$SRC" "$OUT/pfx"
find "$OUT/pfx/drive_c/users" -iname 'Default.rdp' -delete
cleanup() {
    WINEPREFIX=$OUT/pfx "$RT/bin/wineserver" -k 2>/dev/null
    kill ${pids[@]} 2>/dev/null; "$ROOT/tests/lib/xephyr.sh" stop $D
}
pids=(); trap cleanup EXIT
# a display from an earlier run may still be shutting down
for _ in $(seq 50); do ss -xl 2>/dev/null | grep -qE "X11-unix/X(${D#:}|${RD#:}) " || break; sleep 0.2; done

"$ROOT/tests/lib/xephyr.sh" start $D 1280x800 || exit 1
DISPLAY=$D setsid "$WM" --replace >/dev/null 2>&1 & pids+=($!); sleep 3
NT=$(printf '%s' 'clip-test-pass-1' | iconv -t UTF-16LE | openssl dgst -md4 -provider legacy -provider default | awk '{print $2}')
echo "clip-test:TESTDOM::$NT:::" > "$OUT/SAM"
Xvfb $RD -screen 0 1024x700x24 -nolisten tcp >/dev/null 2>&1 & pids+=($!)
for _ in $(seq 50); do DISPLAY=$RD xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done
(cd "$OUT" && DISPLAY=$RD exec "$SRV" "$OUT/ctl" "$OUT/srv" /port:$PORT /sam-file:"$OUT/SAM" /bind-address:127.0.0.1 > "$OUT/server.log" 2>&1) & pids+=($!)
for _ in $(seq 50); do grep -q listening "$OUT/srv/events.log" 2>/dev/null && break; sleep 0.2; done

if [[ -n $LAUNCHER ]]; then
    # the packaged launcher sets the prefix up once (new runtime): before the prompt is timed
    DISPLAY=$D MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state "$LAUNCHER" init >/dev/null 2>&1
    DISPLAY=$D MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state setsid \
        "$LAUNCHER" /v:127.0.0.1:$PORT /w:1024 /h:700 >/dev/null 2>&1 &
else
DISPLAY=$D MSTSC_WINE_RUNTIME=$RT MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state setsid \
    "$ROOT/launcher/mstsc-wine" run /v:127.0.0.1:$PORT /w:1024 /h:700 >/dev/null 2>&1 &
fi
fail=0
check() { if [[ ${2:-0} == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
ev() { grep -c -- "$1" "$OUT/srv/events.log" 2>/dev/null; }
waitev() { for _ in $(seq $((${2:-10} * 5))); do [[ $(ev "$1") -gt ${3:-0} ]] && return 0; sleep 0.2; done; return 1; }
"$ROOT/tests/lib/enter-credentials.sh" $D 'TESTDOM\clip-test' 'clip-test-pass-1' 60 || { check "credential prompt" 0; exit 1; }
"$ROOT/tests/lib/accept-cert-warning.sh" $D 40 || { check "certificate warning (self-signed test server)" 0; exit 1; }
check "clipboard channel starts" $(waitev "client-caps" 30 && echo 1)
waitev "client-formats" 10
py "$ROOT/tools/xshot.py" $D "$OUT/1-session.png"

# remote -> local: the server copies Unicode multi-line text; X11 clients paste it
EXP=$'Hello from the remote side ÄÖü € 中文 \U0001F600\nsecond line\n\tindented'
printf 'text %s\n' "$(printf '%s' "$EXP" | sed 's/\\/\\\\/g' | awk 'BEGIN{ORS="\\n"} {print}' | sed 's/\\n$//')" > "$OUT/ctl"
waitev "client-format-list-response" 10
check "remote->local: mstsc accepts the remote format list" $(grep -q "client-format-list-response ok" "$OUT/srv/events.log" && echo 1)
GOT=$(DISPLAY=$D timeout 10 xclip -o -selection clipboard -t UTF8_STRING 2>/dev/null)
check "remote->local: UTF-8 text pastes in X11 exactly" $([[ "$GOT" == "$EXP" ]] && echo 1)
[[ "$GOT" == "$EXP" ]] || { printf 'expected: %q\n     got: %q\n' "$EXP" "$GOT"; }

# local -> remote: an X11 client copies text; the server pastes it
n=$(ev "client-text")
EXP2=$'Copied on Linux éè 日本語\nline two\r\nline three'
printf '%s' "$EXP2" | DISPLAY=$D xclip -i -selection clipboard -t UTF8_STRING &
pids+=($!)
check "local->remote: mstsc announces the X11 text" $(waitev "client-text" 15 $n && echo 1)
GOT2=$(cat "$OUT/srv/text.txt" 2>/dev/null)
# Windows text uses CRLF; compare with LF normalised
check "local->remote: text arrives exactly (CRLF-normalised)" $([[ "${GOT2//$'\r'/}" == "${EXP2//$'\r'/}" ]] && echo 1)
[[ "${GOT2//$'\r'/}" == "${EXP2//$'\r'/}" ]] || printf 'expected: %q\n     got: %q\n' "$EXP2" "$GOT2"

if [[ ${CLIP_FILES:-1} == 1 ]]; then
# local -> remote file: a file manager copies two files (text/uri-list + gnome list)
mkdir -p "$OUT/local"; head -c 300000 /dev/urandom > "$OUT/local/data.bin"; printf 'héllo\n' > "$OUT/local/nöte.txt"
f1=$OUT/local/data.bin f2=$OUT/local/n$'ö'te.txt
enc() { python3 -c 'import sys,urllib.parse;print("file://"+urllib.parse.quote(sys.argv[1]))' "$1"; }
printf '%s\r\n%s\r\n' "$(enc "$f1")" "$(enc "$f2")" > "$OUT/uris"
printf 'copy\n%s\n%s' "$(enc "$f1")" "$(enc "$f2")" > "$OUT/gnome"
n=$(ev "client-files-done")
py "$ROOT/tools/xselown.py" $D text/uri-list="$OUT/uris" x-special/gnome-copied-files="$OUT/gnome" > /dev/null &
pids+=($!)
check "local->remote: mstsc offers the copied files" $(waitev "client-files-done" 30 $n && echo 1)
check "local->remote: file 1 content matches" $(cmp -s "$f1" "$OUT/srv/files/data.bin" && echo 1)
check "local->remote: file 2 (Unicode name) matches" $(cmp -s "$f2" "$OUT/srv/files/n"$'ö'"te.txt" && echo 1)

# remote -> local file: the server copies a file; a file manager pastes text/uri-list
head -c 200000 /dev/urandom > "$OUT/remote.bin"
echo "file remote-file.bin $OUT/remote.bin" > "$OUT/ctl"
waitev "server-formats" 5 1
sleep 2
URIS=$(DISPLAY=$D timeout 20 xclip -o -selection clipboard -t text/uri-list 2>/dev/null | tr -d '\r')
P=$(python3 -c 'import sys,urllib.parse;u=sys.argv[1].split("\n")[0];print(urllib.parse.unquote(u[7:]) if u.startswith("file://") else "")' "$URIS")
check "remote->local: X11 sees a file URI" $([[ -n $P ]] && echo 1)
check "remote->local: pasted file content matches" $([[ -n $P ]] && cmp -s "$OUT/remote.bin" "$P" && echo 1)
check "remote->local: pasted file keeps its name" $([[ $(basename "$P") == remote-file.bin ]] && echo 1)
fi

if [[ ${CLIP_FILES:-1} == 1 ]]; then
G=$(DISPLAY=$D timeout 20 xclip -o -selection clipboard -t x-special/gnome-copied-files 2>/dev/null)
# GTK resolves URIs with GLib, which refuses escaped path separators
GP=$(python3 -c 'import sys
from gi.repository import GLib
l = sys.argv[1].split("\n")
print(GLib.filename_from_uri(l[1])[0] if len(l) == 2 and l[0] == "copy" else "")' "$G" 2>/dev/null)
check "remote->local: GTK file managers get x-special/gnome-copied-files" $([[ $GP == */remote-file.bin ]] && cmp -s "$OUT/remote.bin" "$GP" && echo 1)
[[ $GP == */remote-file.bin ]] || printf 'got: %q\n' "$G"
GU=$(python3 -c 'import sys
from gi.repository import GLib
print(GLib.filename_from_uri(sys.argv[1].split("\n")[0])[0])' "$URIS" 2>/dev/null)
check "remote->local: GLib accepts the text/uri-list URI" $([[ $GU == "$P" ]] && echo 1)
fi

# images: CF_DIB <-> image/bmp (a 3x2 24-bit picture with distinct pixels)
BMP=$ROOT/tests/clipboard/bmpcheck.py
python3 "$BMP" make "$OUT/pic.bmp"
echo "dib $OUT/pic.bmp.dib" > "$OUT/ctl"
waitev "server-formats 8" 5
sleep 2
DISPLAY=$D timeout 20 xclip -o -selection clipboard -t image/bmp > "$OUT/pasted.bmp" 2>/dev/null
check "remote->local: picture pastes in X11 as image/bmp" $(python3 "$BMP" bmp "$OUT/pasted.bmp" "$OUT/pic.bmp.dib" && echo 1)
n=$(ev "client-dib")
py "$ROOT/tools/xselown.py" $D image/bmp="$OUT/pic.bmp" > /dev/null 2>&1 &
pids+=($!)
waitev "client-dib" 20 $n
check "local->remote: X11 picture reaches the server as CF_DIB" $(python3 "$BMP" dib "$OUT/srv/dib.bin" "$OUT/pic.bmp.dib" && echo 1)

py "$ROOT/tools/xshot.py" $D "$OUT/2-end.png"
echo "$fail failure(s)"
exit $((fail > 0))
