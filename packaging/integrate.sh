#!/usr/bin/env bash
# MSTSC-Wine installation and desktop integration (ADR-0047). Shipped in the AppDir as
# usr/lib/mstsc-wine/integrate.sh; used by `make install`/`make uninstall` and by
# `mstsc --integrate`/`--unintegrate` (AppImage or extracted AppDir).
#
#   integrate.sh install   [--appdir DIR] [--appimage FILE] [--mime] [--force]
#   integrate.sh uninstall [--purge]
#   integrate.sh status
#
# install --appdir DIR   copy the AppDir to $OPT/versions/<build> and switch $OPT/current
#                        to it atomically (running sessions keep their old files)
# install --appimage F   copy the AppImage to $OPT/mstsc-wine-x86_64.AppImage atomically
# install (no source)    from inside the AppImage use $APPIMAGE, else the AppDir it runs from
# Then: desktop entry "Remote Desktop Connection", hicolor icons and the `mstsc` command.
#
# Locations (user install by default; an explicit PREFIX means a system-style install):
#   PREFIX unset: OPT=~/.local/opt/mstsc-wine, BINDIR=~/.local/bin,
#                 DATADIR=${XDG_DATA_HOME:-~/.local/share}
#   PREFIX=/opt/mstsc-wine: OPT=$PREFIX, BINDIR=/usr/local/bin, DATADIR=/usr/local/share
#   BINDIR, DATADIR and DESTDIR can be set explicitly. Root is never requested here.
#
# Only files listed in the install manifest ($OPT/install-manifest) are ever replaced or
# removed. Existing files we do not own (another `mstsc`, desktop entry or icon) are left
# alone and reported, unless --force. User data (prefix, settings, saved credentials,
# logs) is kept unless `uninstall --purge`. --mime adds an .rdp file association to the
# desktop entry (opt-in; the default .rdp handler is never changed).
set -euo pipefail
umask 022
APP_ID=org.mstscwine.RemoteDesktopConnection
SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
DESTDIR=${DESTDIR:-}
if [[ -n ${PREFIX:-} ]]; then
    OPT=$PREFIX; BINDIR=${BINDIR:-/usr/local/bin}; DATADIR=${DATADIR:-/usr/local/share}; SCOPE=system
else
    OPT=$HOME/.local/opt/mstsc-wine; BINDIR=${BINDIR:-$HOME/.local/bin}
    DATADIR=${DATADIR:-${XDG_DATA_HOME:-$HOME/.local/share}}; SCOPE=user
fi
D_OPT=$DESTDIR$OPT D_BIN=$DESTDIR$BINDIR D_DATA=$DESTDIR$DATADIR
MANIFEST=$D_OPT/install-manifest
die() { echo "mstsc-wine install: error: $*" >&2; exit 1; }
say() { echo "mstsc-wine install: $*"; }

cmd=${1:-}; shift || true
APPDIR_SRC= APPIMAGE_SRC= MIME=0 FORCE=0 PURGE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --appdir) APPDIR_SRC=$(cd "$2" && pwd); shift;;
        --appimage) APPIMAGE_SRC=$(readlink -f "$2"); shift;;
        --mime) MIME=1;;
        --force) FORCE=1;;
        --purge) PURGE=1;;
        *) die "unknown option $1";;
    esac
    shift
done

# ---------------------------------------------------------------- manifest helpers
declare -A OWNED=()
load_manifest() {
    [[ -f $MANIFEST ]] || return 0
    local kind path
    while IFS=$'\t' read -r kind path _; do OWNED[$path]=$kind; done < "$MANIFEST"
}
NEWMAN=()
record() { NEWMAN+=("$1"$'\t'"$2"); }   # kind path
owned_or_absent() {   # may we write PATH?
    local p=$1
    [[ ! -e $p && ! -L $p ]] && return 0
    [[ -n ${OWNED[$p]:-} ]] && return 0
    [[ $FORCE == 1 ]] && { say "replacing $p (--force)"; return 0; }
    return 1
}
put_file() {   # src dest mode
    if ! owned_or_absent "$2"; then say "skipped $2: it exists and was not installed by mstsc-wine (use --force to replace it)"; SKIPPED=1; return 0; fi
    mkdir -p "$(dirname "$2")"
    install -m "$3" "$1" "$2.mstsc-tmp" && mv -f "$2.mstsc-tmp" "$2"
    record file "$2"
}
put_link() {   # target dest
    if ! owned_or_absent "$2"; then say "skipped $2: it exists and was not installed by mstsc-wine (use --force to replace it)"; SKIPPED=1; return 0; fi
    mkdir -p "$(dirname "$2")"
    ln -sfn "$1" "$2.mstsc-tmp" && mv -Tf "$2.mstsc-tmp" "$2"
    record link "$2"
}

# ---------------------------------------------------------------- install
cmd_install() {
    [[ $SCOPE == system && -z $DESTDIR && ! -w $(dirname "$OPT") && ! -w $OPT ]] \
        && die "$OPT is not writable; run with the privileges you intend (this script never escalates)"
    load_manifest
    SKIPPED=0
    local srcdir="" launcher
    if [[ -z $APPDIR_SRC && -z $APPIMAGE_SRC ]]; then
        if [[ -n ${APPIMAGE:-} && -f ${APPIMAGE:-} ]]; then APPIMAGE_SRC=$(readlink -f "$APPIMAGE")
        else APPDIR_SRC=$(cd "$SELF_DIR/../../.." && pwd); fi
    fi
    mkdir -p "$D_OPT"
    [[ -f $D_OPT/.mstsc-wine-install || ! -e $MANIFEST && -z $(ls -A "$D_OPT" 2>/dev/null | grep -v '^\.mstsc-wine-install$' || true) ]] \
        || die "$D_OPT exists and is not an mstsc-wine installation"
    touch "$D_OPT/.mstsc-wine-install"
    if [[ -n $APPDIR_SRC ]]; then
        [[ -x $APPDIR_SRC/usr/bin/mstsc && -f $APPDIR_SRC/usr/share/mstsc-wine/metadata/build-info.json ]] \
            || die "$APPDIR_SRC is not an MSTSC-Wine AppDir"
        local id; id=$(sha256sum < "$APPDIR_SRC/usr/share/mstsc-wine/metadata/build-info.json" | cut -c1-12)
        local v=$D_OPT/versions/$id
        if [[ ! -d $v ]]; then
            rm -rf "$v.tmp"; mkdir -p "$D_OPT/versions"
            cp -a "$APPDIR_SRC/." "$v.tmp/"
            mv "$v.tmp" "$v"
        fi
        local prev; prev=$(cat "$D_OPT/.current-id" 2>/dev/null || true)
        ln -sfn "versions/$id" "$D_OPT/current.mstsc-tmp" && mv -Tf "$D_OPT/current.mstsc-tmp" "$D_OPT/current"
        record link "$D_OPT/current"
        if [[ -n $prev && $prev != "$id" ]]; then echo "$prev" > "$D_OPT/.previous"; fi
        prev=$(cat "$D_OPT/.previous" 2>/dev/null || true)
        echo "$id" > "$D_OPT/.current-id"
        # keep this version and the previous one (sessions may still run from it)
        local d
        for d in "$D_OPT"/versions/*/; do
            d=${d%/}; [[ $(basename "$d") == "$id" || $(basename "$d") == "$prev" ]] || rm -rf "$d"
        done
        launcher=$OPT/current/usr/bin/mstsc
        srcdir=$APPDIR_SRC
    else
        [[ -f $APPIMAGE_SRC ]] || die "AppImage not found: $APPIMAGE_SRC"
        local dst=$D_OPT/mstsc-wine-x86_64.AppImage
        if [[ $APPIMAGE_SRC != "$(readlink -f "$dst" 2>/dev/null)" ]]; then
            cp "$APPIMAGE_SRC" "$dst.mstsc-tmp" && chmod 755 "$dst.mstsc-tmp" && mv -f "$dst.mstsc-tmp" "$dst"
        fi
        record file "$dst"
        launcher=$OPT/mstsc-wine-x86_64.AppImage
        srcdir=$(cd "$SELF_DIR/../../.." && pwd)   # the mounted AppDir: icons and desktop file
    fi
    record dir "$D_OPT/versions"

    # the `mstsc` command
    put_link "$launcher" "$D_BIN/mstsc"

    # icons (generated locally from the operator's mstsc.exe, or the project fallback)
    local icons=$srcdir/usr/share/icons/hicolor f rel
    if [[ -d $icons ]]; then
        while IFS= read -r -d '' f; do
            rel=${f#"$icons"/}
            put_file "$f" "$D_DATA/icons/hicolor/$rel" 644
        done < <(find "$icons" -name "$APP_ID.*" -type f -print0)
    fi

    # desktop entry: Exec is the installed launcher, quoted per the desktop entry spec
    local tmp line; tmp=$(mktemp)
    local q=$launcher
    q=${q//\\/\\\\}; q=${q//\"/\\\"}; q=${q//\$/\\\$}; q=${q//\`/\\\`}   # quote for Exec=
    q=${q//\\/\\\\}                                                          # string escaping
    while IFS= read -r line; do
        case $line in
            Exec=*) printf 'Exec="%s" %%f\n' "$q";;
            TryExec=*) printf 'TryExec=%s\n' "${launcher//\\/\\\\}";;
            *) printf '%s\n' "$line";;
        esac
    done < "$srcdir/usr/share/applications/$APP_ID.desktop" > "$tmp"
    [[ $MIME == 1 ]] && echo "MimeType=application/x-rdp;" >> "$tmp"
    put_file "$tmp" "$D_DATA/applications/$APP_ID.desktop" 644
    rm -f "$tmp"

    # write the manifest: everything owned now, plus older entries still present
    local e p
    { printf '%s\n' "${NEWMAN[@]}"
      for p in "${!OWNED[@]}"; do
          printf '%s\n' "${NEWMAN[@]}" | cut -f2 | grep -qxF "$p" && continue
          [[ -e $p || -L $p ]] && printf '%s\t%s\n' "${OWNED[$p]}" "$p"
      done
    } | sort -u > "$MANIFEST.tmp"
    mv -f "$MANIFEST.tmp" "$MANIFEST"

    if [[ -z $DESTDIR ]]; then
        command -v update-desktop-database >/dev/null && update-desktop-database -q "$D_DATA/applications" 2>/dev/null || true
        command -v gtk-update-icon-cache >/dev/null && [[ -f $D_DATA/icons/hicolor/index.theme ]] \
            && gtk-update-icon-cache -q -t "$D_DATA/icons/hicolor" 2>/dev/null || true
    fi
    say "installed: $launcher"
    say "menu entry: Remote Desktop Connection ($D_DATA/applications/$APP_ID.desktop)"
    if [[ -z $DESTDIR ]]; then
        case ":$PATH:" in
            *":$BINDIR:"*) say "command: mstsc ($BINDIR/mstsc)";;
            *) say "command: $BINDIR/mstsc. $BINDIR is not on your PATH yet."
               say "  Debian adds ~/.local/bin to PATH at login when it exists: log out and in again,"
               say "  or add this line to ~/.profile:  PATH=\"\$HOME/.local/bin:\$PATH\"";;
        esac
    fi
    [[ $SKIPPED == 0 ]] || say "some files were skipped (see above); nothing that was not ours was changed"
}

# ---------------------------------------------------------------- uninstall
cmd_uninstall() {
    [[ -f $MANIFEST ]] || { say "nothing to uninstall ($MANIFEST not found)"; return 0; }
    local kind p
    while IFS=$'\t' read -r kind p _; do
        case $kind in
            file|link) [[ -e $p || -L $p ]] && rm -f "$p";;
            dir) rm -rf "$p";;
        esac
    done < "$MANIFEST"
    rm -f "$D_OPT/current" "$D_OPT/.current-id" "$D_OPT/.previous" "$MANIFEST" "$D_OPT/.mstsc-wine-install"
    rmdir "$D_OPT" 2>/dev/null || true
    if [[ -z $DESTDIR ]]; then
        command -v update-desktop-database >/dev/null && update-desktop-database -q "$D_DATA/applications" 2>/dev/null || true
    fi
    say "removed the application and its menu entry, icons and command"
    if [[ $PURGE == 1 ]]; then
        local x
        for x in "${XDG_DATA_HOME:-$HOME/.local/share}/mstsc-wine" "${XDG_CONFIG_HOME:-$HOME/.config}/mstsc-wine" \
                 "${XDG_STATE_HOME:-$HOME/.local/state}/mstsc-wine" "${XDG_CACHE_HOME:-$HOME/.cache}/mstsc-wine"; do
            [[ -d $x ]] && { rm -rf "$x"; say "purged $x"; }
        done
    else
        say "kept your settings, saved credentials and logs (uninstall --purge removes them)"
    fi
}

cmd_status() {
    [[ -f $MANIFEST ]] || { echo "not installed in $OPT"; return 0; }
    echo "installed in $OPT ($(cat "$D_OPT/.current-id" 2>/dev/null || echo AppImage))"
    cut -f1,2 "$MANIFEST"
}

case $cmd in
    install) cmd_install;;
    uninstall) cmd_uninstall;;
    status) cmd_status;;
    *) sed -n '2,26p' "$0"; exit 2;;
esac
