#!/bin/bash
# Keyboard scancodes and characters under several XKB layouts (EXP-074/075, ADR-0054–0056).
#   run.sh WINE OUT [DISPLAY]    (default :6, a private Xephyr running metacity)
# For each layout the probe (kbdprobe.exe) records what Wine delivers for physical key
# presses injected by X keycode:
#   - scancodes (WH_KEYBOARD_LL, which is what an RDP client forwards) must be the
#     physical Windows set-1 scancodes, whatever the layout: on Windows a scancode names
#     a key position, the layout only turns it into characters;
#   - the characters (WM_CHAR) must still be those of the X layout (no change to local
#     typing, e.g. AltGr combinations keep producing their level-3 characters).
# Layouts: the reporter's Apple German (Macintosh, no dead keys) with Right Alt as AltGr,
# standard German (pc105), and US (pc105), without an X input method.
# With an X input method (Xlib's built-in one, XMODIFIERS=@im=none, as a desktop session
# normally has one): the second reporter's configuration (model apple, layout de, dead
# keys) types dead-key sequences. Every key, including the dead key and the key composed
# with it, must reach the low-level hook with its scancode, down and up, as on Windows;
# the window gets the consumed presses as VK_PROCESSKEY and the composed text exactly once.
# German Macintosh under the input method checks that ordinary keys are unaffected.
W=$1 OUT=$2 D=${3:-:6}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
command -v metacity >/dev/null || { echo "SKIP metacity not installed"; exit 0; }
python3 -c 'import Xlib' 2>/dev/null || { echo "SKIP python3-xlib not installed"; exit 0; }
"$ROOT/tests/lib/xephyr.sh" start $D 800x600 || exit 1
DISPLAY=$D setsid metacity --replace >/dev/null 2>&1 &
wm=$!; sleep 1.5

# physical keys (evdev keycode): a y/z-row z/y-row AD11 AC10 AC11 AE11 AE12 TLDE BKSL LSGT
# AD12 AB08 AB09 AB10 q, then Right Alt chords with q, l and 7
KEYS="38 52 29 34 47 48 20 21 49 51 94 35 59 60 61 24 108+24 108+46 108+16"
# expected LL key-down scancodes ("e" = extended), identical for every layout
SCANS="1e 2c 15 1a 27 28 0c 0d 29 2b 56 1b 33 34 35 10 38e 10 38e 26 38e 08"

NO_IM=@im=mstsc-wine-test-no-im   # an input method that does not exist: XIM stays off
fail=0
check() { if [[ $2 == 1 ]]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }

run_layout() { # name "setxkbmap args" "expected chars (hex, space separated)" [xkb option]
    # globals: IM (XMODIFIERS), RUN_KEYS, RUN_SCANS
    local name=$1 args=$2 chars=$3 log=$OUT/kbd-$1.log got
    DISPLAY=$D setxkbmap -rules evdev $args -option '' ${4:+-option $4} || { check "$name: setxkbmap" 0; return; }
    : > "$log"
    DISPLAY=$D XMODIFIERS=$IM LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
        timeout 60 "$W" "$OUT/kbdprobe.exe" 12 > "$log" 2>/dev/null &
    local pid=$!
    for _ in $(seq 200); do grep -q '^READY' "$log" && break; kill -0 $pid 2>/dev/null || break; sleep 0.1; done
    if ! grep -q '^READY' "$log"; then check "$name: probe started" 0; wait $pid; return; fi
    python3 "$ROOT/tools/xkeycodes.py" $D $RUN_KEYS
    sleep 0.5; kill $pid 2>/dev/null; wait $pid 2>/dev/null
    # scancode 0: the text an input method composed (VK_NONAME, unchanged Wine behaviour)
    got=$(awk '{ sub(/\r$/, "") } /^LL  down/ && $4 != "scan=00" { s=substr($4,6); if ($5=="ext=1") s=s "e"; printf "%s%s", sep, s; sep=" " }' "$log")
    [[ $got == "$RUN_SCANS" ]] && check "$name: physical scancodes" 1 || { check "$name: physical scancodes" 0; echo "  expected: $RUN_SCANS"; echo "  got:      $got"; }
    got=$(awk '{ sub(/\r$/, "") } /^LL  up/ { s=substr($4,6); if ($5=="ext=1") s=s "e"; printf "%s%s", sep, s; sep=" " }' "$log")
    [[ $(tr ' ' '\n' <<< "$got" | sort) == $(tr ' ' '\n' <<< "$RUN_SCANS" | sort) ]] && check "$name: every key released" 1 || { check "$name: every key released" 0; echo "  key-ups: $got"; }
    got=$(awk '{ sub(/\r$/, "") } /^CHAR/ { printf "%s%s", sep, tolower(substr($2,3)); sep=" " }' "$log")
    [[ $got == "$chars" ]] && check "$name: characters typed locally" 1 || { check "$name: characters typed locally" 0; echo "  expected: $chars"; echo "  got:      $got"; }
    if [[ -n ${PROCESSKEYS:-} ]]; then
        got=$(tr -d '\r' < "$log" | grep -c '^MSG WM_KEYDOWN vk=e5 ')
        [[ $got == "$PROCESSKEYS" ]] && check "$name: consumed keys reach the window as VK_PROCESSKEY" 1 || { check "$name: consumed keys reach the window as VK_PROCESSKEY" 0; echo "  expected $PROCESSKEYS, got $got"; }
    fi
    grep '^LAYOUT' "$log" | sed 's/^/  /'
}

IM=$NO_IM RUN_KEYS=$KEYS RUN_SCANS=$SCANS PROCESSKEYS=
# a y z u-umlaut o-umlaut a-umlaut sharp-s acute circumflex # < + , . - q, AltGr+q/l/7
run_layout de-mac "-model macbook79 -layout de -variant mac_nodeadkeys" \
    "0061 0079 007a 00fc 00f6 00e4 00df 00b4 005e 0023 003c 002b 002c 002e 002d 0071 00ab 0040 007c" lv3:ralt_switch
# a y z ü ö ä ß, dead acute then dead circumflex (no input method: Wine emits both, ´ ^),
# # < + , . - q,
# AltGr+q -> @, AltGr+l -> ł (U+0142), AltGr+7 -> {
run_layout de "-model pc105 -layout de" \
    "0061 0079 007a 00fc 00f6 00e4 00df 00b4 005e 0023 003c 002b 002c 002e 002d 0071 0040 0142 007b"
# a z y [ ; ' - = ` \ < ] , . / q, Right Alt is plain Alt: q l 7 (WM_SYSCHAR)
run_layout us "-model pc105 -layout us" \
    "0061 007a 0079 005b 003b 0027 002d 003d 0060 005c 003c 005d 002c 002e 002f 0071 0071 006c 0037"

# The same keys under the input method: nothing composes, nothing changes.
IM=@im=none PROCESSKEYS=0
run_layout de-mac-im "-model macbook79 -layout de -variant mac_nodeadkeys" \
    "0061 0079 007a 00fc 00f6 00e4 00df 00b4 005e 0023 003c 002b 002c 002e 002d 0071 00ab 0040 007c" lv3:ralt_switch

# Dead keys under the input method (model apple, layout de, as reported): acute+e, acute+a,
# Shift+acute (grave)+o, acute+space, Shift+acute+space, circumflex+a, then ä.
RUN_KEYS="21 26 21 38 50+21 32 21 65 50+21 65 49 38 48"
RUN_SCANS="0d 12 0d 1e 2a 0d 18 0d 39 2a 0d 39 29 1e 28"
PROCESSKEYS=12   # six dead keys and the six keys composed with them
# é á ò, then what X's Compose table gives for acute/grave + space (' and `), â, ä
run_layout de-apple-im "-model apple -layout de" \
    "00e9 00e1 00f2 0027 0060 00e2 00e4" terminate:ctrl_alt_bksp

kill $wm 2>/dev/null
"$ROOT/tests/lib/xephyr.sh" stop $D
exit $((fail > 0))
