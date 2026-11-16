#!/bin/bash
# Packaging release gates (packaging spec §9) that can run unattended on one Debian 13
# desktop. Each line is PASS, FAIL or SKIP (SKIP is never a PASS).
#   tests/portability/run.sh APPDIR [APPIMAGE [TARBALL]]
# Needs: bwrap (hiding the source tree and host Samba), Xephyr (GUI checks; display :7).
# Writes only below artifacts/pkgtest/ and /var/tmp/mstsc-wine-pkgtest-*; never touches the
# real ~/.wine, ~/.local or desktop. Uses a throwaway HOME for install tests.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APPDIR=$(cd "${1:?AppDir}" && pwd)
APPIMAGE=${2:-}; [[ -n $APPIMAGE ]] && APPIMAGE=$(readlink -f "$APPIMAGE")
TARBALL=${3:-}; [[ -n $TARBALL ]] && TARBALL=$(readlink -f "$TARBALL")
# test the package as a user runs it: no developer overrides from the caller's shell
# (e.g. a sourced artifacts/dev-patched.env sets MSTSC_WINE_RUNTIME and MSTSC_WINE_PREFIX)
for v in $(compgen -e); do [[ $v == MSTSC_WINE_* ]] && unset "$v"; done
W=$ROOT/artifacts/pkgtest; rm -rf "$W"; mkdir -p "$W"
VT=$(mktemp -d /var/tmp/mstsc-wine-pkgtest-XXXX)   # outside the repository, on disk
D=:7
pass=0 fail=0 skip=0
res() { # ID STATUS text
    printf '%-4s %-8s %s\n' "$2" "$1" "$3"
    case $2 in PASS) pass=$((pass+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; esac
}
check() { local id=$1 text=$2 rc; shift 2; echo "== $id $text" >>"$W/details.log"; "$@" >>"$W/details.log" 2>&1; rc=$?; case $rc in 0) res "$id" PASS "$text";; 77) res "$id" SKIP "$text";; *) res "$id" FAIL "$text";; esac; }
cleanup() {
    for p in "$W"/xdg-*/data/mstsc-wine/prefix "$VT"/xdg-*/data/mstsc-wine/prefix; do
        [[ -d $p ]] && WINEPREFIX=$p "$APPDIR/usr/lib/mstsc-wine/wine/bin/wineserver" -k 2>/dev/null
    done
    "$ROOT/tests/lib/xephyr.sh" stop $D >/dev/null 2>&1
    chmod -R u+w "$VT" 2>/dev/null; rm -rf "$VT"
}
trap cleanup EXIT
xdg() { # name -> env assignments for a fresh, private set of XDG directories
    local b=$1
    echo "XDG_DATA_HOME=$b/data XDG_STATE_HOME=$b/state XDG_CONFIG_HOME=$b/config XDG_CACHE_HOME=$b/cache"
}
POISON=(WINEPREFIX=/nonexistent/other-prefix WINELOADER=/bin/false WINESERVER=/bin/false
        WINEDLLPATH=/nonexistent WINEDLLOVERRIDES='*=n' WINEDEBUG=+all WINEARCH=win32 WINELOADERNOEXEC=1)
HAVE_BWRAP=0; command -v bwrap >/dev/null && bwrap --dev-bind / / true 2>/dev/null && HAVE_BWRAP=1
# hide the repository, host Samba and any host Wine; keeps everything else of the host
hidden() {
    local a=(--dev-bind / / --tmpfs "$ROOT")
    local p
    for p in /usr/lib/x86_64-linux-gnu/samba /etc/samba /var/lib/samba /run/samba /usr/lib/wine /usr/lib/x86_64-linux-gnu/wine /opt/wine-stable /opt/wine-devel; do
        [[ -d $p ]] && a+=(--tmpfs "$p")
    done
    for p in /usr/bin/ntlm_auth /usr/bin/wine /usr/bin/wineserver /usr/bin/wine64 /usr/sbin/winbindd; do
        [[ -e $p ]] && a+=(--ro-bind /dev/null "$p")
    done
    bwrap "${a[@]}" "$@"
}
"$ROOT/tests/lib/xephyr.sh" start $D 1024x768 >/dev/null 2>&1 || true
export DISPLAY=$D

# ------------------------------------------------------------------ static checks
check PKG-002 "repository and Docker context contain no Microsoft files, ZIPs or secrets" "$ROOT/tests/portability/test-repo-hygiene.sh"
check PKG-003 "Wine built from the pinned commit with exactly patches/series" bash -c '
    m='"$APPDIR"'/usr/share/mstsc-wine/metadata/build-info.json
    grep -q "\"wine_commit\": \"db11d0fe6a169c457e23d007e20404643d067aa8\"" "$m" &&
    grep -q "\"patch_series_sha256\": \"$(sha256sum < '"$ROOT"'/patches/series | cut -d" " -f1)\"" "$m" &&
    grep -q "\"patch_count\": \"$(grep -vc "^#" '"$ROOT"'/patches/series)\"" "$m"'
check PKG-018 "provenance, dependency manifest, hashes, licence notices and sources accompany the artifact" bash -c '
    m='"$APPDIR"'/usr/share/mstsc-wine/metadata
    for f in build-info.json component-manifest.json dependency-manifest.json; do python3 -m json.tool "$m/$f" >/dev/null || exit 1; done
    [[ -s $m/SOURCES.md && -s $m/license-notices/wine-COPYING.LIB && -s $m/license-notices/gnutls28.copyright &&
       -s $m/license-notices/winbind.copyright && -s $m/source/patches/series ]] &&
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert all(l[\"sha256\"] and l[\"location\"] for l in d[\"bundled_libraries\"]); assert d[\"host_libraries\"]" "$m/dependency-manifest.json"'
check PKG-012 "Microsoft components verified against the manifest; corrupt, missing and mixed inputs rejected" "$ROOT/tests/portability/test-component-bundle.sh"

# ------------------------------------------------------------------ relocation
R1="$VT/one"; R2="$VT/two with space/Ä"
mkdir -p "$R1" "$R2"
cp -a "$APPDIR" "$R1/MSTSC-Wine.AppDir"; cp -a "$APPDIR" "$R2/MSTSC-Wine.AppDir"
chmod -R a-w "$R2/MSTSC-Wine.AppDir"          # read-only payload
runpkg() { # dir xdgname args...   (source tree, host Samba and host Wine hidden when bwrap works)
    local dir=$1 x=$2; shift 2
    if [[ $HAVE_BWRAP == 1 ]]; then
        hidden env $(xdg "$VT/xdg-$x") "${POISON[@]}" "$dir/MSTSC-Wine.AppDir/AppRun" "$@"
    else
        env $(xdg "$VT/xdg-$x") "${POISON[@]}" "$dir/MSTSC-Wine.AppDir/AppRun" "$@"
    fi
}
[[ $HAVE_BWRAP == 1 ]] || res PKG-008 SKIP "bwrap unusable: cannot hide the source tree (relocation still tested below)"
check PKG-008 "relocated AppDir works with the source tree hidden (doctor, Wine starts)" bash -c "
    $(declare -f runpkg hidden xdg); $(declare -p POISON HAVE_BWRAP ROOT VT); runpkg '$R1' a doctor && runpkg '$R1' a exec cmd /c echo ok"
check PKG-009 "AppDir under a path with a space and non-ASCII characters" bash -c "
    $(declare -f runpkg hidden xdg); $(declare -p POISON HAVE_BWRAP ROOT VT); runpkg '$R2' b exec cmd /c echo ok"
check PKG-007 "inherited WINEPREFIX/WINELOADER/WINESERVER/WINEDLLPATH/WINEDLLOVERRIDES ignored" bash -c "
    [[ -f '$VT/xdg-b/data/mstsc-wine/prefix/system.reg' && ! -e /nonexistent/other-prefix ]] &&
    grep -q 'WINEDLLOVERRIDES=winemenubuilder.exe=d;mscoree=d;mshtml=d$' '$VT'/xdg-b/state/mstsc-wine/logs/*-exec.log"
check PKG-010 "read-only payload: state only under XDG directories, nothing written into the AppDir" bash -c "
    [[ -z \$(find '$R2/MSTSC-Wine.AppDir' -newer '$W' -print -quit) ]] &&
    [[ -d '$VT/xdg-b/state/mstsc-wine/logs' && -f '$VT/xdg-b/data/mstsc-wine/prefix/.mstsc-wine-state' ]] &&
    [[ ! -e '$VT/xdg-b/config/mstsc-wine' || -d '$VT/xdg-b/config/mstsc-wine' ]]"
# relative .rdp argument from a working directory with a space: converted to a Windows path
check PKG-009 "relative .rdp file names are converted to Windows paths" bash -c "
    mkdir -p '$VT/cwd with space' && cd '$VT/cwd with space' && printf 'full address:s:rdp-test.invalid\\r\\n' > 'my file.rdp'
    env $(xdg "$VT/xdg-b") timeout 40 '$R2/MSTSC-Wine.AppDir/AppRun' 'my file.rdp' >/dev/null 2>&1 &
    c=; for i in \$(seq 40); do c=\$(pgrep -af 'mstsc\\.exe' | grep -F 'cwd with space' || true); [[ -n \$c ]] && break; sleep 1; done
    WINEPREFIX='$VT/xdg-b/data/mstsc-wine/prefix' '$APPDIR/usr/lib/mstsc-wine/wine/bin/wineserver' -k
    echo \"\$c\"; grep -qF 'Z:' <<<\"\$c\" && grep -qF 'cwd with space\\my file.rdp' <<<\"\$c\""

# ------------------------------------------------------------------ isolation and private helpers
check PKG-005 "bundled ntlm_auth answers in client mode with host Samba and the winbindd socket hidden" bash -c "
    $(declare -f hidden); $(declare -p ROOT)
    out=\$(printf 'PW cGtnCg==\nYR\n' | hidden env -i PATH=/usr/bin:/bin '$R1/MSTSC-Wine.AppDir/usr/lib/mstsc-wine/samba/bin/ntlm_auth' --helper-protocol=ntlmssp-client-1 --username=u --domain=D | tail -1)
    [[ \$out == 'YR '* ]] && hidden test ! -e /run/samba/winbindd/pipe"
check PKG-005 "NTLM CredSSP logon through the packaged runtime (host Samba hidden, decoy ntlm_auth on PATH)" \
    "$ROOT/tests/portability/test-private-ntlm.sh" "$R1/MSTSC-Wine.AppDir/AppRun"
check PKG-006 "a concurrent, different Wine (other prefix, own wineserver) is not affected" \
    "$ROOT/tests/portability/test-foreign-wine.sh" "$R1/MSTSC-Wine.AppDir/AppRun"
check PKG-013 "runs as a normal user with Docker's socket, sudo, host Wine, ntlm_auth and winbindd unreachable" bash -c "
    $(declare -f hidden xdg); $(declare -p ROOT VT)
    [[ \$(id -u) != 0 ]] || exit 1
    extra=(); for s in /run/docker.sock /var/run/docker.sock /usr/bin/sudo /usr/bin/docker; do [[ -e \$s ]] && extra+=(--ro-bind /dev/null \$s); done
    hidden \"\${extra[@]}\" env $(xdg "$VT/xdg-g") '$R1/MSTSC-Wine.AppDir/AppRun' exec cmd /c echo ok &&
    hidden \"\${extra[@]}\" env $(xdg "$VT/xdg-g") '$R1/MSTSC-Wine.AppDir/AppRun' doctor | grep -q 'ntlm_auth:  bundled'"
check PKG-014 "fresh prefix initialised exactly once under four concurrent launches" bash -c "
    for i in 1 2 3 4; do env $(xdg "$VT/xdg-c") '$R1/MSTSC-Wine.AppDir/AppRun' exec cmd /c echo ok >/dev/null 2>&1 & done; wait
    [[ \$(ls '$VT'/xdg-c/state/mstsc-wine/logs/*-init.log | wc -l) == 1 ]] &&
    [[ \$(ls '$VT'/xdg-c/state/mstsc-wine/logs/*-exec.log | wc -l) == 4 ]] &&
    ! grep -l '# exit: [1-9]' '$VT'/xdg-c/state/mstsc-wine/logs/*-exec.log"
check PKG-014 "runtime upgrade: registry backed up, prefix re-initialised once, saved data kept" bash -c "
    p='$VT/xdg-c/data/mstsc-wine/prefix'
    env $(xdg "$VT/xdg-c") '$R1/MSTSC-Wine.AppDir/AppRun' --wine-tool wine reg add 'HKCU\\Software\\Microsoft\\Terminal Server Client\\Default' /v MRU0 /d keep-me /f >/dev/null 2>&1
    sed -i 's/runtime=[0-9a-f]*/runtime=0000000000000000/' \"\$p/.mstsc-wine-state\"
    env $(xdg "$VT/xdg-c") '$R1/MSTSC-Wine.AppDir/AppRun' exec cmd /c echo ok >/dev/null 2>&1 &&
    ls '$VT'/xdg-c/data/mstsc-wine/backups/*/user.reg >/dev/null &&
    [[ \$(ls '$VT'/xdg-c/state/mstsc-wine/logs/*-init.log | wc -l) == 2 ]] &&
    grep -q keep-me \"\$p/user.reg\""
check PKG-019 "works with networking disabled after launch (diagnostics, local Wine)" bash -c "
    bwrap --dev-bind / / --unshare-net env $(xdg "$VT/xdg-a") '$R1/MSTSC-Wine.AppDir/AppRun' exec cmd /c echo ok &&
    bwrap --dev-bind / / --unshare-net env $(xdg "$VT/xdg-a") '$R1/MSTSC-Wine.AppDir/AppRun' doctor"
check PKG-020 "doctor reports a missing bundled library and a system-resolved one" bash -c "
    cp -a '$R1/MSTSC-Wine.AppDir' '$VT/broken' && chmod -R u+w '$VT/broken' &&
    rm '$VT/broken/usr/lib/mstsc-wine/gnutls/libnettle.so.8' &&
    out=\$(env $(xdg "$VT/xdg-d") '$VT/broken/AppRun' doctor 2>&1); rc=\$?;
    [[ \$rc != 0 ]] && grep -q 'SYSTEM-RESOLVED\|MISSING' <<<\"\$out\" && grep -q 'doctor: problems found' <<<\"\$out\""

# ------------------------------------------------------------------ GUI: the genuine client from the package
check PKG-015 "packaged genuine mstsc starts, resolves the target, no unimplemented calls (Xephyr)" bash -c "
    env $(xdg "$VT/xdg-a") MSTSC_WINE_TRACE=+winsock timeout 40 '$R1/MSTSC-Wine.AppDir/AppRun' /v:rdp-test.invalid >/dev/null 2>&1 &
    for i in \$(seq 40); do sleep 1; l=\$(ls -t '$VT'/xdg-a/state/mstsc-wine/logs/*-mstsc.log 2>/dev/null | head -1);
        [[ -n \$l ]] && grep -aq 'GetAddrInfoW nodename L\"rdp-test.invalid\", servname L\"3389\"' \"\$l\" && break; done
    WINEPREFIX='$VT/xdg-a/data/mstsc-wine/prefix' '$APPDIR/usr/lib/mstsc-wine/wine/bin/wineserver' -k
    grep -aq 'GetAddrInfoW nodename L\"rdp-test.invalid\", servname L\"3389\"' \"\$l\" && ! grep -aq 'unimplemented function' \"\$l\""
"$ROOT/tests/portability/runtime-shim.sh" "$R1/MSTSC-Wine.AppDir/AppRun" "$VT/shim" >/dev/null
check PKG-016 "packaged mstsc: NLA logon and clipboard text, files and pictures both ways (local cliprdr server)" \
    bash -c "out=\$('$ROOT/tests/launch/test-clipboard.sh' '$VT/xdg-a/data/mstsc-wine/prefix' '$VT/shim' '$R1/MSTSC-Wine.AppDir/AppRun' 2>&1); echo \"\$out\"
             grep -q '^SKIP' <<<\"\$out\" && exit 77; grep -q '^0 failure' <<<\"\$out\""
check PKG-022 "mstsc window class is mstsc.exe (desktop StartupWMClass)" "$ROOT/tests/portability/test-wmclass.sh" "$R1/MSTSC-Wine.AppDir/AppRun" $D

# ------------------------------------------------------------------ AppImage and tarball
if [[ -n $APPIMAGE && -f $APPIMAGE ]]; then
    check PKG-010 "AppImage: runs from its read-only mount, state only in XDG directories" bash -c "
        env $(xdg "$VT/xdg-e") '$APPIMAGE' exec cmd /c echo ok >/dev/null 2>&1 &&
        [[ -f '$VT/xdg-e/data/mstsc-wine/prefix/.mstsc-wine-state' ]] && env $(xdg "$VT/xdg-e") '$APPIMAGE' doctor"
    check PKG-010 "AppImage without FUSE: --appimage-extract-and-run" bash -c "
        cd '$VT' && env $(xdg "$VT/xdg-e") APPIMAGE_EXTRACT_AND_RUN=1 '$APPIMAGE' --version | grep -q 'mstsc-wine'"
    check PKG-017 "make install (the AppImage): exposes mstsc, switches from/to an AppDir install, uninstall keeps user data" \
        "$ROOT/tests/portability/test-install.sh" appimage "$APPIMAGE"
    check PKG-024 "AppImage --integrate/--unintegrate in a throwaway HOME, idempotent, no AppImageLauncher" \
        "$ROOT/tests/portability/test-install.sh" appimage "$APPIMAGE"
else
    res PKG-010 SKIP "no AppImage given (make appimage)"; res PKG-024 SKIP "no AppImage given"
fi
if [[ -n $TARBALL && -f $TARBALL ]]; then
    check PKG-011 ".tar.zst extracts and runs without AppImage tools or host Wine" bash -c "
        mkdir -p '$VT/tar x' && tar -C '$VT/tar x' -I zstd -xf '$TARBALL' && $(declare -f hidden); $(declare -p ROOT);
        hidden env $(xdg "$VT/xdg-f") '$VT/tar x/MSTSC-Wine.AppDir/AppRun' exec cmd /c echo ok"
else
    res PKG-011 SKIP "no tarball given (make package)"
fi

# ------------------------------------------------------------------ installation
check PKG-017 "make install-appdir exposes mstsc; uninstall removes only owned files, keeps user data" \
    "$ROOT/tests/portability/test-install.sh" appdir "$APPDIR"
res PKG-001 SKIP "fresh-checkout build: run tests/portability/test-fresh-build.sh (long; Docker)"
res PKG-021 SKIP "menu entry rendering under Cinnamon/KDE: manual (docs/PACKAGING.md checklist)"
res PKG-023 SKIP "fresh login shell PATH: covered for ~/.local/bin by test-install.sh; real login manual"
res PKG-025 SKIP "covered by test-install.sh (PKG-017/024 lines)"

echo "$pass passed, $fail failed, $skip skipped (details: artifacts/pkgtest/details.log)"
exit $((fail > 0))
