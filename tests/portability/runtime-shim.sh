#!/bin/bash
# Make a runtime directory whose bin/wine, bin/wineserver, ... run a packaged MSTSC-Wine
# (AppDir, extracted tarball or AppImage) through its launcher (`mstsc --wine-tool`), with
# exactly the environment the packaged mstsc gets (private GnuTLS, Kerberos, NTLM helper,
# sanitised WINE* variables). The existing suites take such a directory as RUNTIME:
#   tests/portability/runtime-shim.sh APPRUN_OR_APPIMAGE OUTDIR
#   tests/run-regression.sh OUTDIR patched
# The caller's WINEPREFIX, WINEDLLOVERRIDES and WINEDEBUG are passed on as MSTSC_WINE_PREFIX,
# MSTSC_WINE_DLLOVERRIDES and MSTSC_WINE_TRACE. For an AppDir, lib/ points at its Wine
# libraries (for checks that look for builtin DLLs).
set -euo pipefail
ENTRY=$(readlink -f "${1:?AppRun or AppImage}") OUT=${2:?outdir}
rm -rf "$OUT"; mkdir -p "$OUT/bin"
for t in wine wineserver wineboot winepath msiexec regedit regsvr32 winecfg winedbg; do
    cat > "$OUT/bin/$t" <<SH
#!/bin/sh
MSTSC_WINE_PREFIX=\${WINEPREFIX:-\${MSTSC_WINE_PREFIX:-}}
[ -n "\$MSTSC_WINE_PREFIX" ] || unset MSTSC_WINE_PREFIX
export MSTSC_WINE_PREFIX
[ -n "\${WINEDLLOVERRIDES:-}" ] && export MSTSC_WINE_DLLOVERRIDES="\$WINEDLLOVERRIDES"
[ -n "\${WINEDEBUG:-}" ] && export MSTSC_WINE_TRACE="\$WINEDEBUG"
exec "$ENTRY" --wine-tool $t "\$@"
SH
    chmod +x "$OUT/bin/$t"
done
echo "$ENTRY" > "$OUT/.mstsc-wine-shim"
[[ -d $(dirname "$ENTRY")/usr/lib/mstsc-wine/wine/lib ]] && ln -s "$(dirname "$ENTRY")/usr/lib/mstsc-wine/wine/lib" "$OUT/lib"
true
