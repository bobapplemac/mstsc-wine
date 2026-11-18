#!/bin/bash
# F-013 / N-003: the launcher creates a private prefix without touching ~/.wine,
# host menus/MIME associations, or symlinking prefix folders into $HOME.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "$ROOT/artifacts/launcher-test.XXXX")
export HOME_SNAPSHOT=$(ls -la "$HOME/.local/share/applications" 2>/dev/null | md5sum)
export MSTSC_WINE_HOME=$T/home MSTSC_WINE_STATE=$T/state MSTSC_WINE_PREFIX=$T/home/prefix
# A scaled Cinnamon/KDE X11 or XWayland session publishes this resource. Wine does
# not consume it itself, so the launcher must copy it into the private registry.
xrdb() { printf 'Xft.dpi:\t144\n'; }
export -f xrdb
wine_before=$(stat -c %Y "$HOME/.wine" 2>/dev/null || echo none)
fails=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fails=$((fails+1)); }
"$ROOT/launcher/mstsc-wine" init >/dev/null 2>&1 && ok "init succeeds" || bad "init succeeds"
[[ -f $MSTSC_WINE_PREFIX/system.reg ]] && ok "prefix created at configured path" || bad "prefix path"
[[ $(stat -c %Y "$HOME/.wine" 2>/dev/null || echo none) == "$wine_before" ]] && ok "~/.wine untouched" || bad "~/.wine modified"
links=$(find "$MSTSC_WINE_PREFIX/drive_c/users" -maxdepth 2 -type l -lname "$HOME*" 2>/dev/null | wc -l)
[[ $links == 0 ]] && ok "no prefix folders symlinked into \$HOME" || bad "$links symlinks into \$HOME"
[[ $(ls -la "$HOME/.local/share/applications" 2>/dev/null | md5sum) == "$HOME_SNAPSHOT" ]] && ok "no host .desktop entries created" || bad "host applications dir changed"
ls "$MSTSC_WINE_STATE"/logs/*-init.log >/dev/null 2>&1 && ok "init log written" || bad "init log"
grep -q 'dpi=144' "$MSTSC_WINE_PREFIX/.mstsc-wine-state" && ok "Xft.dpi recorded in prefix state" || bad "DPI prefix state"
grep -q '"LogPixels"=dword:00000090' "$MSTSC_WINE_PREFIX/user.reg" && ok "Wine LogPixels follows Xft.dpi" || bad "Wine LogPixels"
grep -q '# dpi: 144 (Xft.dpi)' "$MSTSC_WINE_STATE"/logs/*-init.log && ok "DPI source recorded in log" || bad "DPI log"
v=$("$ROOT/launcher/mstsc-wine" --version); grep -q WineRevision <<<"$v" && ok "--version reports manifest" || bad "--version"
WINEPREFIX=$MSTSC_WINE_PREFIX "$("$ROOT/launcher/mstsc-wine" --version | sed -n 's/.*(\(.*\))$/\1/p')/bin/wineserver" -k 2>/dev/null
rm -rf "$T"
echo "$fails failure(s)"; exit $((fails > 0))
