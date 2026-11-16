#!/bin/bash
# PKG-017/021/023/024/025 (automated parts): install, upgrade and uninstall in a throwaway
# HOME. Never touches the real ~/.local.
#   test-install.sh appdir APPDIR      make install-appdir path (integrate.sh install --appdir)
#   test-install.sh appimage APPIMAGE  make install path: mstsc --integrate / --unintegrate
#                                      from the AppImage, and switching from/to an AppDir install
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
mode=$1 SRC=$(readlink -f "$2")
T=$(mktemp -d /var/tmp/mstsc-install-XXXX); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export HOME=$T/home; mkdir -p "$HOME"
unset XDG_DATA_HOME XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME
export PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
fail=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
APP_ID=org.mstscwine.RemoteDesktopConnection
DESK=$HOME/.local/share/applications/$APP_ID.desktop
# unrelated files that must survive everything
mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/48x48/apps" "$HOME/.local/share/mstsc-wine/prefix"
echo "[Desktop Entry]" > "$HOME/.local/share/applications/other.desktop"
echo other > "$HOME/.local/share/icons/hicolor/48x48/apps/other.png"
echo "saved settings" > "$HOME/.local/share/mstsc-wine/prefix/user-data-marker"
# a new Debian user's login files (/etc/skel/.profile adds ~/.local/bin when it exists)
cp /etc/skel/.profile /etc/skel/.bashrc "$HOME/" 2>/dev/null
# mimeinfo.cache is the regenerated desktop database, not an installed file
snap() { find "$HOME" -path "$HOME/.local/opt" -prune -o \( -type f -o -type l \) ! -name mimeinfo.cache -print | sort; }

install_it() {
    if [[ $mode == appdir ]]; then "$SRC/usr/lib/mstsc-wine/integrate.sh" install --appdir "$SRC"
    else "$SRC" --integrate; fi
}
uninstall_it() {
    if [[ $mode == appdir ]]; then "$HOME/.local/opt/mstsc-wine/current/usr/lib/mstsc-wine/integrate.sh" uninstall "$@"
    else "$SRC" --unintegrate "$@"; fi
}

# 1. an unrelated `mstsc` already on PATH is not replaced
mkdir -p "$HOME/.local/bin"; printf '#!/bin/sh\necho mine\n' > "$HOME/.local/bin/mstsc"; chmod +x "$HOME/.local/bin/mstsc"
out=$(install_it 2>&1) || bad "install with a foreign mstsc present exits non-zero"
[[ $("$HOME/.local/bin/mstsc") == mine ]] && grep -q 'not installed by mstsc-wine' <<<"$out" && ok "existing unrelated mstsc kept and reported" || bad "foreign mstsc overwritten"
[[ -f $DESK ]] && ok "desktop entry installed anyway" || bad "desktop entry missing"
uninstall_it >/dev/null 2>&1
[[ $("$HOME/.local/bin/mstsc") == mine ]] && ok "uninstall leaves the foreign mstsc" || bad "foreign mstsc removed"
rm -f "$HOME/.local/bin/mstsc"

# 2. clean install
before=$(snap)
install_it > "$T/install.log" 2>&1 && ok "install succeeds" || { bad "install failed: $(tail -3 "$T/install.log")"; exit 1; }
[[ -L $HOME/.local/bin/mstsc ]] && ok "~/.local/bin/mstsc created" || bad "no ~/.local/bin/mstsc"
p=$(env -i HOME="$HOME" TERM=dumb bash -lc 'command -v mstsc')
[[ $p == "$HOME/.local/bin/mstsc" ]] && ok "fresh login shell resolves mstsc to the installed launcher" || bad "command -v mstsc -> '$p'"
v=$(env -i HOME="$HOME" PATH="$HOME/.local/bin:/usr/bin:/bin" mstsc --version 2>&1)
grep -q '(packaged)' <<<"$v" && grep -q "Runtime: ~/.local/opt/mstsc-wine\|Runtime: /tmp/.mount_\|Runtime: .*/usr/lib/mstsc-wine/wine" <<<"$v" && ok "installed mstsc runs the bundled runtime" || bad "mstsc --version: $v"
grep -qx 'Name=Remote Desktop Connection' "$DESK" && grep -qx 'GenericName=Remote Desktop Client' "$DESK" && grep -qx 'Terminal=false' "$DESK" \
    && grep -q '^Categories=Network;RemoteAccess;' "$DESK" && ok "menu entry is titled Remote Desktop Connection" || bad "desktop entry fields"
exe=$(sed -n 's/^Exec="\(.*\)" %f$/\1/p' "$DESK")
[[ -x $exe ]] && ok "Exec points at the installed launcher ($(sed "s|$HOME|~|" <<<"$exe"))" || bad "Exec target not executable: $exe"
if command -v desktop-file-validate >/dev/null; then desktop-file-validate "$DESK" && ok "desktop-file-validate" || bad "desktop-file-validate"; fi
ls "$HOME"/.local/share/icons/hicolor/*/apps/$APP_ID.* >/dev/null 2>&1 && ok "icon installed in the hicolor theme" || bad "no icon"
grep -q '^MimeType' "$DESK" && bad "MIME association added without --mime" || ok "no .rdp association by default"

# 3. idempotent
m1=$(cat "$HOME/.local/opt/mstsc-wine/install-manifest")
install_it >/dev/null 2>&1 && [[ $(cat "$HOME/.local/opt/mstsc-wine/install-manifest") == "$m1" ]] && ok "second install is idempotent" || bad "re-install changed the manifest"

# 4. upgrade to another build (AppDir mode): atomic switch, previous kept, unrelated files kept
if [[ $mode == appdir ]]; then
    cp -a "$SRC" "$T/appdir2"; chmod -R u+w "$T/appdir2"
    sed -i 's/"built": "[^"]*"/"built": "upgrade-test"/' "$T/appdir2/usr/share/mstsc-wine/metadata/build-info.json"
    old=$(readlink "$HOME/.local/opt/mstsc-wine/current")
    "$T/appdir2/usr/lib/mstsc-wine/integrate.sh" install --appdir "$T/appdir2" >/dev/null 2>&1
    new=$(readlink "$HOME/.local/opt/mstsc-wine/current")
    [[ $new != "$old" && -d $HOME/.local/opt/mstsc-wine/$old && -d $HOME/.local/opt/mstsc-wine/$new ]] \
        && ok "upgrade switches current atomically and keeps the previous version" || bad "upgrade: $old -> $new"
fi
# 4b. switching install modes (AppImage mode): AppDir -> AppImage -> AppDir leaves one copy
if [[ $mode == appimage ]]; then
    O=$HOME/.local/opt/mstsc-wine
    (cd "$T" && "$SRC" --appimage-extract >/dev/null 2>&1) && AD=$T/squashfs-root
    "$AD/usr/lib/mstsc-wine/integrate.sh" install --appdir "$AD" >/dev/null 2>&1
    [[ -L $O/current && ! -e $O/mstsc-wine-x86_64.AppImage && $(readlink "$HOME/.local/bin/mstsc") == "$O/current/usr/bin/mstsc" ]] \
        && ok "AppImage -> AppDir install: AppImage removed, mstsc points at the AppDir" || bad "AppImage -> AppDir switch"
    install_it >/dev/null 2>&1
    [[ -f $O/mstsc-wine-x86_64.AppImage && ! -e $O/current && ! -e $O/versions && $(readlink "$HOME/.local/bin/mstsc") == "$O/mstsc-wine-x86_64.AppImage" ]] \
        && grep -q 'mstsc-wine-x86_64.AppImage" %f$' "$DESK" \
        && ok "AppDir -> AppImage install: AppDir copies removed, mstsc and menu entry use the AppImage" || bad "AppDir -> AppImage switch"
    chmod -R u+w "$AD"; rm -rf "$AD"
fi
[[ -f $HOME/.local/share/applications/other.desktop && -f $HOME/.local/share/icons/hicolor/48x48/apps/other.png ]] \
    && ok "unrelated desktop entry and icon untouched" || bad "unrelated files changed"

# 5. uninstall: only owned files go, user data stays
uninstall_it >/dev/null 2>&1
after=$(snap)
[[ $before == "$after" ]] && ok "uninstall restores the previous file set exactly" || { bad "files left or removed:"; diff <(echo "$before") <(echo "$after") | head; }
[[ ! -e $HOME/.local/opt/mstsc-wine ]] && ok "application directory removed" || bad "~/.local/opt/mstsc-wine left behind"
[[ -f $HOME/.local/share/mstsc-wine/prefix/user-data-marker ]] && ok "user data (prefix) kept" || bad "user data removed"

# 6. --purge removes user data only when asked
install_it >/dev/null 2>&1; uninstall_it --purge >/dev/null 2>&1
[[ ! -e $HOME/.local/share/mstsc-wine && -f $HOME/.local/share/applications/other.desktop ]] && ok "uninstall --purge removes only mstsc-wine data" || bad "purge"
# a purge requested after the application was already removed still removes the data
mkdir -p "$HOME/.local/share/mstsc-wine/prefix"; echo x > "$HOME/.local/share/mstsc-wine/prefix/user-data-marker"
install_it >/dev/null 2>&1; uninstall_it >/dev/null 2>&1
[[ -f $HOME/.local/share/mstsc-wine/prefix/user-data-marker ]] || bad "plain uninstall removed data"
"$ROOT/packaging/integrate.sh" uninstall --purge >/dev/null 2>&1 && [[ ! -e $HOME/.local/share/mstsc-wine ]] \
    && ok "purge after uninstall removes the data" || bad "purge after uninstall"
exit $fail
