#!/bin/bash
# Genuine mstsc: keyboard input reaching an RDP server under several XKB layouts (spec
# F-010; EXP-074, ADR-0054/0055).
#   test-keyboard.sh [RUNTIME] [LAYOUTS]
#   (defaults: build/install-wine-patched, "de-mac de us de-apple-im")
#   de-apple-im: model apple, layout de (dead keys) with Xlib's input method active, typing
#   dead-key sequences (´e ´a `o ´space `space ^a): every key must reach the server, down
#   and up, so that the server composes them (EXP-075, ADR-0056).
#   MSTSC_KBD_CLIENT_LANG=de_DE.UTF-8 runs mstsc (only) in that locale, to observe the
#   keyboard layout it advertises (Wine derives it from the locale); LOCPATH is honoured.
#   MSTSC_KBD_CLIENT_XIM=none|<name> runs mstsc (only) with XMODIFIERS=@im=<value>: "none"
#   selects Xlib's built-in input method, which composes dead keys like a desktop's would.
#   MSTSC_KBD_KEYS / MSTSC_KBD_SCANS replace the key list and the expected key-down scancodes.
# Endpoint: tests/keyboard/server/kbd-shadow.c, the FreeRDP shadow server logging the
# client's keyboard layout and every TS_KEYBOARD_EVENT / TS_UNICODE_KEYBOARD_EVENT. Only
# the server side is FreeRDP; the client is the genuine mstsc on Wine. For each layout a
# fresh mstsc connects, the test presses physical keys by X keycode in the session window,
# and the server must receive their physical set-1 scancodes (with the extended flag for
# Right Alt/AltGr), as a Windows client sends them: the server applies its own layout.
# Needs Xephyr, Xvfb, metacity, freerdp3-shadow-x11, freerdp3-dev, python3-xlib.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RT=${1:-$ROOT/build/install-wine-patched}
LAYOUTS=${2:-de-mac de us de-apple-im}
COMPONENTS=${MSTSC_WINE_COMPONENTS:-$ROOT/artifacts/MSTSC-Wine.AppDir/usr/share/mstsc-wine/Windows}
NTLM_AUTH=${MSTSC_WINE_NTLM_AUTH:-$ROOT/build/docker/stage/samba/bin/ntlm_auth}
OUT=$ROOT/artifacts/keyboard-test
D=:5 RD=:11 PORT=33895
py() { PYTHONPATH=$ROOT/.deps/py python3 "$@"; }

for t in Xvfb Xephyr metacity cc; do command -v $t >/dev/null || { echo "SKIP $t not installed"; exit 0; }; done
[[ -f /usr/include/freerdp3/freerdp/server/shadow.h ]] || { echo "SKIP freerdp3-dev not installed"; exit 0; }
[[ -x $RT/bin/wine ]] || { echo "SKIP no runtime at $RT"; exit 0; }
[[ -d $COMPONENTS/system32 ]] || { echo "SKIP no Microsoft components at $COMPONENTS"; exit 0; }

rm -rf "$OUT"; mkdir -p "$OUT"
cc -O1 -g -Wno-deprecated-declarations -I/usr/include/freerdp3 -I/usr/include/winpr3 \
    -o "$OUT/kbd-shadow" "$ROOT/tests/keyboard/server/kbd-shadow.c" \
    -lfreerdp-shadow3 -lfreerdp-shadow-subsystem3 -lfreerdp-server3 -lfreerdp3 -lwinpr3 \
    2>"$OUT/cc.log" || { echo "FAIL building the test server"; cat "$OUT/cc.log"; exit 1; }

pids=()
stop_mstsc() { WINEPREFIX=$OUT/pfx "$RT/bin/wineserver" -k >/dev/null 2>&1; sleep 1; }
cleanup() { stop_mstsc; kill "${pids[@]}" 2>/dev/null; "$ROOT/tests/lib/xephyr.sh" stop $D >/dev/null 2>&1; }
trap cleanup EXIT
for _ in $(seq 50); do ss -xl 2>/dev/null | grep -qE "X11-unix/X(${D#:}|${RD#:}) " || break; sleep 0.2; done

"$ROOT/tests/lib/xephyr.sh" start $D 1280x800 || exit 1
DISPLAY=$D setsid metacity --replace >"$OUT/wm.log" 2>&1 & pids+=($!)
Xvfb $RD -screen 0 1024x700x24 -nolisten tcp >"$OUT/xvfb.log" 2>&1 & pids+=($!)
for _ in $(seq 50); do DISPLAY=$RD xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done
# a throwaway local account (no domain, so that no backslash has to be typed under
# layouts that put it on AltGr)
NT=$(printf '%s' 'kbdtest-pass-1' | iconv -t UTF-16LE | openssl dgst -md4 -provider legacy -provider default | awk '{print $2}')
echo "kbdtest:::$NT:::" > "$OUT/SAM"
(cd "$OUT" && DISPLAY=$RD exec "$OUT/kbd-shadow" "$OUT/server" /port:$PORT /sam-file:"$OUT/SAM" \
    /bind-address:127.0.0.1 >"$OUT/server.log" 2>&1) & pids+=($!)
EV=$OUT/server/events.log
for _ in $(seq 50); do grep -q listening "$EV" 2>/dev/null && break; sleep 0.2; done
grep -q listening "$EV" 2>/dev/null || { echo "FAIL server did not start"; exit 1; }

DISPLAY=$D MSTSC_WINE_RUNTIME=$RT MSTSC_WINE_COMPONENTS=$COMPONENTS MSTSC_WINE_NTLM_AUTH=$NTLM_AUTH \
    MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state \
    "$ROOT/launcher/mstsc-wine" init >/dev/null 2>&1 || { echo "FAIL launcher init"; exit 1; }

# physical keys (evdev keycode) and the scancodes a Windows client sends for them, whatever
# the layout: a, the Y and Z positions, ü ö ä ß ´ positions, ^ # < + , . - q,
# then AltGr (Right Alt) with q, l and 7
KEYS=${MSTSC_KBD_KEYS:-"38 52 29 34 47 48 20 21 49 51 94 35 59 60 61 24 108+24 108+46 108+16"}
SCANS=${MSTSC_KBD_SCANS:-"1e 2c 15 1a 27 28 0c 0d 29 2b 56 1b 33 34 35 10 38e 10 38e 26 38e 08"}

fail=0
check() { if [[ ${2:-0} == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }

run_layout() { # name "setxkbmap args" [xkb option]
    local name=$1 args=$2 opt=${3:-} geo start got n
    DISPLAY=$D setxkbmap -rules evdev $args -option '' ${opt:+-option $opt} || { check "$name: setxkbmap" 0; return; }
    n=$(grep -c '^client-keyboard' "$EV")
    DISPLAY=$D MSTSC_WINE_RUNTIME=$RT MSTSC_WINE_COMPONENTS=$COMPONENTS MSTSC_WINE_NTLM_AUTH=$NTLM_AUTH \
        MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state \
        env ${MSTSC_KBD_CLIENT_LANG:+LANG=$MSTSC_KBD_CLIENT_LANG LC_ALL=$MSTSC_KBD_CLIENT_LANG} \
        ${MSTSC_KBD_CLIENT_XIM:+XMODIFIERS=@im=$MSTSC_KBD_CLIENT_XIM} \
        setsid "$ROOT/launcher/mstsc-wine" /v:127.0.0.1:$PORT /w:1024 /h:700 >/dev/null 2>&1 &
    "$ROOT/tests/lib/enter-credentials.sh" $D 'kbdtest' 'kbdtest-pass-1' 60 >/dev/null 2>&1 || { check "$name: credential prompt" 0; stop_mstsc; return; }
    "$ROOT/tests/lib/accept-cert-warning.sh" $D 40 || { check "$name: certificate warning" 0; stop_mstsc; return; }
    for _ in $(seq 150); do [[ $(grep -c '^client-keyboard' "$EV") -gt $n ]] && break; sleep 0.2; done
    geo=$(py "$ROOT/tools/xwait.py" $D '127\.0\.0\.1.*Remote Desktop Connection' 30) || { check "$name: session window" 0; stop_mstsc; return; }
    set -- $geo
    sleep 3
    py "$ROOT/tools/xclick.py" $D click $(( $1 + $3 / 2 )) $(( $2 + $4 / 2 ))   # focus the session
    sleep 1
    start=$(wc -l < "$EV")
    python3 "$ROOT/tools/xkeycodes.py" $D $KEYS
    sleep 2
    tail -n +$((start + 1)) "$EV" > "$OUT/$name.events"
    grep '^client-keyboard' "$EV" | tail -1 | sed "s/^/  $name: /"
    got=$(awk '/^key down/ { s=substr($3,6); if ($4=="ext=1") s=s "e"; printf "%s%s", sep, s; sep=" " }' "$OUT/$name.events")
    if [[ $got == "$SCANS" ]]; then check "$name: server receives physical scancodes" 1
    else check "$name: server receives physical scancodes" 0; echo "  expected: $SCANS"; echo "  got:      $got"; fi
    got=$(awk '/^key up/ { s=substr($3,6); if ($4=="ext=1") s=s "e"; printf "%s%s", sep, s; sep=" " }' "$OUT/$name.events")
    check "$name: server receives every key release" $([[ $(tr ' ' '\n' <<< "$got" | sort) == $(tr ' ' '\n' <<< "$SCANS" | sort) ]] && echo 1 || echo 0)
    check "$name: no unicode key events" $([[ $(grep -c '^unicode' "$OUT/$name.events") == 0 ]] && echo 1 || echo 0)
    stop_mstsc
}

for l in $LAYOUTS; do
    case $l in
    de-mac) run_layout de-mac "-model macbook79 -layout de -variant mac_nodeadkeys" lv3:ralt_switch ;;
    de)     run_layout de "-model pc105 -layout de" ;;
    de-apple) run_layout de-apple "-model apple -layout de" terminate:ctrl_alt_bksp ;;
    de-apple-im)
        KEYS="21 26 21 38 50+21 32 21 65 50+21 65 49 38" SCANS="0d 12 0d 1e 2a 0d 18 0d 39 2a 0d 39 29 1e" \
        MSTSC_KBD_CLIENT_XIM=none run_layout de-apple-im "-model apple -layout de" terminate:ctrl_alt_bksp ;;
    us)     run_layout us "-model pc105 -layout us" ;;
    *) echo "unknown layout $l"; fail=$((fail+1)) ;;
    esac
done
echo "$fail failure(s)"; exit $((fail > 0))
