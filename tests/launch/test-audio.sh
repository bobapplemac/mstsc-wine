#!/bin/bash
# Genuine mstsc: negotiate rdpsnd with a local FreeRDP server and receive a PCM tone.
# FreeRDP is only the server-side fixture; the client under test is Microsoft mstsc on Wine.
#   test-audio.sh [RUNTIME] [LAUNCHER] [COMPONENTS]
# RUNTIME is used only with the source launcher. With LAUNCHER, pass an AppRun/AppImage.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RT=${1:-$ROOT/build/install-wine-patched}
LAUNCHER=${2:-}
COMPONENTS=${3:-$ROOT/artifacts/MSTSC-Wine.AppDir/usr/share/mstsc-wine/Windows}
NTLM_AUTH=${MSTSC_WINE_NTLM_AUTH:-$ROOT/build/docker/stage/samba/bin/ntlm_auth}
TRACE=${MSTSC_AUDIO_TRACE:-+winmm,+driver,+mmdevapi,+pulse}
OUT=$ROOT/artifacts/audio-test
D=:5
RD=:9
PORT=33894

for tool in Xvfb Xephyr metacity cc; do
    command -v "$tool" >/dev/null || { echo "SKIP $tool not installed"; exit 0; }
done
[[ -f /usr/include/freerdp3/freerdp/server/rdpsnd.h ]] || {
    echo "SKIP freerdp3-dev not installed"
    exit 0
}
[[ -n $LAUNCHER || -x $RT/bin/wine ]] || { echo "SKIP no runtime at $RT"; exit 0; }

rm -rf "$OUT"
mkdir -p "$OUT"
{
    printf '\xff\xfe'
    printf '%s\r\n' \
        'screen mode id:i:1' \
        'desktopwidth:i:1024' \
        'desktopheight:i:700' \
        "full address:s:127.0.0.1:$PORT" \
        'username:s:TESTDOM\audio-test' \
        'prompt for credentials:i:1' \
        'audiomode:i:0' \
        'audioqualitymode:i:2' | iconv -t UTF-16LE
} > "$OUT/audio.rdp"
if [[ ${MSTSC_AUDIO_USE_RDP:-0} == 1 ]]; then
    CONNECT_ARGS=("$OUT/audio.rdp")
else
    CONNECT_ARGS=(/v:127.0.0.1:$PORT /w:1024 /h:700)
fi
cc -O1 -g -Wno-deprecated-declarations -I/usr/include/freerdp3 -I/usr/include/winpr3 \
    -o "$OUT/rdpsnd-shadow" "$ROOT/tests/audio/server/rdpsnd-shadow.c" \
    -lfreerdp-shadow3 -lfreerdp-shadow-subsystem3 -lfreerdp-server3 -lfreerdp3 \
    -lwinpr3 -lpthread -lm || exit 1

pids=()
cleanup() {
    if [[ -n $LAUNCHER ]]; then
        MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state "$LAUNCHER" --wine-tool wineserver -k >/dev/null 2>&1
    else
        WINEPREFIX=$OUT/pfx "$RT/bin/wineserver" -k >/dev/null 2>&1
    fi
    kill "${pids[@]}" 2>/dev/null
    "$ROOT/tests/lib/xephyr.sh" stop "$D" >/dev/null 2>&1
}
trap cleanup EXIT

"$ROOT/tests/lib/xephyr.sh" start "$D" 1280x800 || exit 1
DISPLAY=$D setsid metacity --replace >"$OUT/wm.log" 2>&1 & pids+=($!)
Xvfb $RD -screen 0 1024x700x24 -nolisten tcp >"$OUT/xvfb.log" 2>&1 & pids+=($!)
for _ in $(seq 50); do DISPLAY=$RD xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done

NT=$(printf '%s' 'audio-test-pass-1' | iconv -t UTF-16LE | \
    openssl dgst -md4 -provider legacy -provider default | awk '{print $2}')
echo "audio-test:TESTDOM::$NT:::" > "$OUT/SAM"
(cd "$OUT" && DISPLAY=$RD exec "$OUT/rdpsnd-shadow" "$OUT/server" \
    /port:$PORT /sam-file:"$OUT/SAM" /bind-address:127.0.0.1 >"$OUT/server.log" 2>&1) & pids+=($!)
for _ in $(seq 50); do grep -q listening "$OUT/server/events.log" 2>/dev/null && break; sleep 0.2; done
grep -q listening "$OUT/server/events.log" 2>/dev/null || { echo "FAIL server did not start"; exit 1; }

if [[ -n $LAUNCHER ]]; then
    DISPLAY=$D MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state \
        "$LAUNCHER" init >/dev/null 2>&1 || exit 1
    if [[ $TRACE == *+relay* ]]; then
        DISPLAY=$D MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state \
            "$LAUNCHER" --wine-tool reg add 'HKCU\Software\Wine\Debug' \
            /v RelayInclude /d 'winmm.*' /f >/dev/null 2>&1 || exit 1
    fi
    DISPLAY=$D MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state \
        MSTSC_WINE_TRACE="$TRACE" setsid "$LAUNCHER" "${CONNECT_ARGS[@]}" \
        >/dev/null 2>&1 & pids+=($!)
else
    DISPLAY=$D MSTSC_WINE_RUNTIME=$RT MSTSC_WINE_COMPONENTS=$COMPONENTS \
        MSTSC_WINE_NTLM_AUTH=$NTLM_AUTH \
        MSTSC_WINE_PREFIX=$OUT/pfx MSTSC_WINE_STATE=$OUT/state \
        "$ROOT/launcher/mstsc-wine" init >/dev/null 2>&1 || exit 1
    if [[ $TRACE == *+relay* ]]; then
        WINEPREFIX=$OUT/pfx "$RT/bin/wine" reg add 'HKCU\Software\Wine\Debug' \
            /v RelayInclude /d 'winmm.*' /f >/dev/null 2>&1 || exit 1
    fi
    DISPLAY=$D MSTSC_WINE_RUNTIME=$RT MSTSC_WINE_PREFIX=$OUT/pfx \
        MSTSC_WINE_COMPONENTS=$COMPONENTS MSTSC_WINE_NTLM_AUTH=$NTLM_AUTH \
        MSTSC_WINE_STATE=$OUT/state \
        MSTSC_WINE_TRACE="$TRACE" \
        setsid "$ROOT/launcher/mstsc-wine" "${CONNECT_ARGS[@]}" \
        >/dev/null 2>&1 & pids+=($!)
fi

"$ROOT/tests/lib/enter-credentials.sh" "$D" 'TESTDOM\audio-test' 'audio-test-pass-1' 60 || exit 1
"$ROOT/tests/lib/accept-cert-warning.sh" "$D" 40 || exit 1

for _ in $(seq 100); do
    log=$(ls -t "$OUT/state/logs/"*-mstsc.log 2>/dev/null | head -1)
    [[ -n ${log:-} ]] && grep -q 'trace:winmm:waveOutWrite' "$log" && break
    sleep 0.2
done
log=$(ls -t "$OUT/state/logs/"*-mstsc.log 2>/dev/null | head -1)
grep -E 'client-audio|client-format|sent-frames|send-failed' "$OUT/server/events.log" || true
if [[ -n ${log:-} ]] && grep -q 'trace:winmm:waveOutWrite' "$log"; then
    echo "PASS rdpsnd PCM reaches waveOutWrite"
    exit 0
fi
echo "FAIL rdpsnd PCM never reaches waveOutWrite"
[[ -n ${log:-} ]] && grep -aE 'trace:(winmm|driver):.*(DriverCallback|waveOut(Open|Close|Write|PrepareHeader)|WOD_)' "$log" || true
exit 1
