#!/bin/bash
# Regression suite for mstsc-wine Wine patches.  Runs against one runtime:
#   tests/run-regression.sh RUNTIME_DIR [baseline|patched]
# For "baseline" the patch-specific tests are expected to FAIL (they document
# the upstream defect); for "patched" they must PASS.  Exit 0 if all expectations hold.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RT=${1:?runtime dir}; mode=${2:-patched}
W=$RT/bin/wine
export WINEPREFIX=$ROOT/artifacts/prefixes/regress-$(basename "$RT")
export WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe,mscoree,mshtml,winedbg.exe=d" WINEARCH=win64
mkdir -p "$WINEPREFIX"; "$RT/bin/wineboot" -u >/dev/null 2>&1; "$RT/bin/wineserver" -w
[[ -d $ROOT/.deps/sysroot ]] && . "$ROOT/tools/build-env.sh"
FIX=$ROOT/artifacts/mui-fixture
"$ROOT/tests/static/mui-fixture/build.sh" "$FIX" >/dev/null || { echo "fixture build failed"; exit 1; }
ORD=$ROOT/artifacts/user32-ordinals
"$ROOT/tests/static/user32-ordinals/build.sh" "$ORD" >/dev/null || { echo "ordinal fixture build failed"; exit 1; }
WPP=$ROOT/artifacts/wpp-trace
"$ROOT/tests/static/wpp-trace/build.sh" "$WPP" >/dev/null || { echo "WPP fixture build failed"; exit 1; }
ACM=$ROOT/artifacts/msacm-pcm-format
"$ROOT/tests/static/msacm-pcm-format/build.sh" "$ACM" >/dev/null || { echo "MSACM fixture build failed"; exit 1; }

fails=0
check() { # name expected(pass|fail) cmd...
    local name=$1 exp=$2; shift 2
    if "$@" >/dev/null 2>&1; then got=pass; else got=fail; fi
    if [[ $got == "$exp" ]]; then echo "ok   $name ($got)"; else echo "FAIL $name (expected $exp, got $got)"; fails=$((fails+1)); fi
}
exp_fix=pass; [[ $mode == baseline ]] && exp_fix=fail
check "smoke: cmd /c echo"                     pass "$W" cmd /c echo ok
check "ntdll: opt-in classic WPP diagnostics" $exp_fix "$ROOT/tests/static/wpp-trace/run.sh" "$W" "$WPP"
check "msacm32: PCM converter rejects non-PCM input" $exp_fix "$W" "$ACM/msacm-pcm-format.exe"
check "mui: string from en-US satellite"       $exp_fix "$W" "$FIX/muitest.exe"
check "mui: mismatched checksum is rejected"   pass "$W" "$FIX/bad/muitest.exe" expect-missing
check "mui: i386 resource-only satellite"    $exp_fix "$W" "$FIX/i386/muitest.exe"
mkdir -p "$WINEPREFIX/drive_c/windows/SystemResources" && cp -f "$FIX"/mun/SystemResources/*.mun "$WINEPREFIX/drive_c/windows/SystemResources/"
check "mun: IMAGE from SystemResources .mun"  $exp_fix "$W" "$FIX/mun/muntest.exe"
check "mun: mismatched checksum is rejected"  pass "$W" "$FIX/mun/muntestbad.exe" expect-missing
TLS=$ROOT/artifacts/schannel-keyusage
"$ROOT/tests/static/schannel-keyusage/build.sh" "$TLS" >/dev/null 2>&1 || { echo "tls fixture build failed"; exit 1; }
# the patched runtime carries its own GnuTLS (ADR-0013); the baseline uses the system one
LDP=; [[ -e $RT/lib/mstsc-wine/libgnutls.so.30 ]] && LDP=$RT/lib/mstsc-wine
check "schannel: RDP-style server cert (no digitalSignature)" $exp_fix env ${LDP:+LD_LIBRARY_PATH=$LDP} "$ROOT/tests/static/schannel-keyusage/run.sh" "$W" "$TLS"
CSSP=$ROOT/artifacts/credssp-client
"$ROOT/tests/static/credssp-client/build.sh" "$CSSP" >/dev/null 2>&1 || { echo "credssp fixture build failed"; exit 1; }
NTLM_AUTH=${MSTSC_WINE_NTLM_AUTH:-}
[[ -n $NTLM_AUTH ]] || NTLM_AUTH=$(command -v ntlm_auth 2>/dev/null || true)
[[ -n $NTLM_AUTH ]] || NTLM_AUTH=$ROOT/build/docker/stage/samba/bin/ntlm_auth
ntlm_env=(); ntlm_arg=()
if [[ -x $NTLM_AUTH ]]; then
    ntlm_arg=("$NTLM_AUTH")
    [[ $mode == patched ]] && ntlm_env=(WINENTLMAUTH=$NTLM_AUTH)
fi
check "credssp: NLA client (delegation, saved credentials, server auth flags, bad password)" $exp_fix env ${LDP:+LD_LIBRARY_PATH=$LDP} "${ntlm_env[@]}" "$ROOT/tests/static/credssp-client/run.sh" "$W" "$CSSP"
if [[ -f $RT/.mstsc-wine-shim ]]; then
    # a packaged runtime (tests/portability/runtime-shim.sh): its launcher always selects the
    # bundled helper, so the raw WINENTLMAUTH check does not apply; check that instead
    check "msv1_0: packaged runtime uses its bundled NTLM helper" pass "$ROOT/tests/portability/test-private-ntlm.sh" "$(cat "$RT/.mstsc-wine-shim")"
else
    check "msv1_0: WINENTLMAUTH selects the NTLM helper, no PATH fallback" $exp_fix env ${LDP:+LD_LIBRARY_PATH=$LDP} "$ROOT/tests/static/ntlm-helper/run.sh" "$W" "$CSSP" "${ntlm_arg[@]}"
fi
KRB=$ROOT/artifacts/kerberos-check; rm -rf "$KRB"
[[ -x $ROOT/.deps/krb5kdc/root/usr/sbin/krb5kdc ]] && \
check "kerberos: CredSSP with Kerberos (UPN, realm case, no default realm, memory ticket cache)" $exp_fix "$ROOT/tests/security/kerberos/run.sh" "$W" "$KRB"
CUP=$ROOT/artifacts/credui-prompt
"$ROOT/tests/static/credui-prompt/build.sh" "$CUP" >/dev/null 2>&1 || { echo "credui-prompt fixture build failed"; exit 1; }
check "credui: prompt keeps the user name, wraps long messages, clears the password on re-prompt" $exp_fix "$ROOT/tests/static/credui-prompt/run.sh" "$W" "$CUP"
FSC=$ROOT/artifacts/fullscreen-clip
"$ROOT/tests/static/fullscreen-clip/build.sh" "$FSC" >/dev/null 2>&1 || { echo "fullscreen-clip fixture build failed"; exit 1; }
check "winex11: leaving fullscreen releases the pointer grab" $exp_fix "$ROOT/tests/static/fullscreen-clip/run.sh" "$W" "$FSC"
KBD=$ROOT/artifacts/keyboard-layout
"$ROOT/tests/static/keyboard-layout/build.sh" "$KBD" >/dev/null 2>&1 || { echo "keyboard-layout fixture build failed"; exit 1; }
check "winex11: physical scancodes for national keys, AltGr and dead keys under an input method (de Macintosh, de, de apple, us)" $exp_fix "$ROOT/tests/static/keyboard-layout/run.sh" "$W" "$KBD"
DLG=$ROOT/artifacts/dialog-layout
"$ROOT/tests/static/dialog-layout/build.sh" "$DLG" >/dev/null 2>&1 || { echo "dialog-layout fixture build failed"; exit 1; }
check "dialog layout: toolbar label and margin, child repaint, nested tab texture, text widths, group box caption" $exp_fix "$ROOT/tests/static/dialog-layout/run.sh" "$W" "$DLG"
OCB=$ROOT/artifacts/ole-clipboard
"$ROOT/tests/static/ole-clipboard/build.sh" "$OCB" >/dev/null 2>&1 || { echo "ole-clipboard fixture build failed"; exit 1; }
check "clipboard: feature probe, predefined format names, OLE <-> X11 text" $exp_fix "$ROOT/tests/static/ole-clipboard/run.sh" "$W" "$OCB"
check "user32: ordinal 2598 callable"         $exp_fix "$W" "$ORD/ord2598.exe"
if [[ -f $ROOT/build/$(basename "$RT" | sed 's/^install-//')/dlls/devobj/tests/x86_64-windows/devobj_test.exe ]]; then
    check "devobj: conformance test"           pass "$W" "$ROOT/build/$(basename "$RT" | sed 's/^install-//')/dlls/devobj/tests/x86_64-windows/devobj_test.exe" devobj
else
    check "devobj: dll present"                $exp_fix test -f "$RT/lib/wine/x86_64-windows/devobj.dll"
fi
ST=$ROOT/build/$(basename "$RT" | sed 's/^install-//')/dlls/shcore/tests/x86_64-windows/shcore_test.exe
[[ $mode == patched && -f $ST ]] && check "shcore: conformance (resource stream)" pass "$W" "$ST" shcore
SC=$ROOT/build/$(basename "$RT" | sed 's/^install-//')/dlls/secur32/tests/x86_64-windows/secur32_test.exe
[[ $mode == patched && -f $SC ]] && check "secur32: conformance (SspiPrepareForCredRead)" pass "$W" "$SC" secur32
B=$ROOT/build/$(basename "$RT" | sed 's/^install-//')/dlls
if [[ $mode == patched ]]; then
    [[ -f $B/ws2_32/tests/x86_64-windows/ws2_32_test.exe ]] && check "ws2_32: conformance (NS_NLA lookup)" pass "$W" "$B/ws2_32/tests/x86_64-windows/ws2_32_test.exe" protocol
    [[ -f $B/advapi32/tests/x86_64-windows/advapi32_test.exe ]] && check "advapi32: conformance (CredReadW types)" pass "$W" "$B/advapi32/tests/x86_64-windows/advapi32_test.exe" cred
    [[ -f $B/msxml3/tests/x86_64-windows/msxml3_test.exe ]] && check "msxml3: conformance (attribute typed value)" pass "$W" "$B/msxml3/tests/x86_64-windows/msxml3_test.exe" domdoc
fi
"$RT/bin/wineserver" -k 2>/dev/null
echo "$fails unexpected result(s)"; exit $((fails > 0))
