#!/bin/bash
# Assemble the canonical, relocatable MSTSC-Wine AppDir (ADR-0043) from built open-source
# components and the operator's Microsoft component ZIP. Runs on the host, never in Docker:
# the Microsoft files never enter a container or image (spec §6).
#
#   tools/assemble-appdir.sh BUILD_DIR COMPONENTS_ZIP OUT_APPDIR
#
# BUILD_DIR holds the outputs of tools/build-wine.sh dist, tools/build-gnutls.sh,
# tools/build-ntlm.sh (stage/wine-root, install-gnutls, debroot, stage/samba).
# Environment: BUILD_ENGINE (recorded in build-info.json), MSTSC_BUILD_IMAGE (docker image).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=$(cd "${1:?build dir}" && pwd)
ZIP=$(readlink -f "${2:?component zip}")
OUT=${3:?output AppDir}
fail() { echo "assemble-appdir: $*" >&2; exit 1; }
step() { echo "assemble-appdir: $*"; }
[[ -d $BUILD/stage/wine-root/usr/lib/mstsc-wine/wine ]] || fail "no Wine dist build in $BUILD (make wine)"
[[ -f $BUILD/install-gnutls/lib/libgnutls.so.30 ]] || fail "no patched GnuTLS in $BUILD (make gnutls)"
[[ -x $BUILD/stage/samba/bin/ntlm_auth.bin && -d $BUILD/debroot ]] || fail "no NTLM helper in $BUILD (make ntlm)"
case $OUT in *:*) fail "the AppDir path must not contain ':' (library search paths)";; esac
mkdir -p "$(dirname "$OUT")"
OUT=$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")
T=$OUT.tmp
rm -rf "$T"
U=$T/usr L=$T/usr/lib/mstsc-wine S=$T/usr/share/mstsc-wine M=$T/usr/share/mstsc-wine/metadata
mkdir -p "$U/bin" "$L" "$S" "$M/license-notices" "$M/source" "$U/share/applications"
DEB=$BUILD/debroot/usr/lib/x86_64-linux-gnu
STRIP=${STRIP:-strip}
PESTRIP=${PESTRIP:-x86_64-w64-mingw32-strip}
command -v "$PESTRIP" >/dev/null || PESTRIP=$ROOT/.deps/sysroot/usr/bin/x86_64-w64-mingw32-strip
REC=$T/libs.json; echo '[]' > "$REC"

# ---------------------------------------------------------------- Wine
step "Wine runtime"
cp -a "$BUILD/stage/wine-root/usr/lib/mstsc-wine/wine" "$L/wine"
W=$L/wine
rm -rf "$W/include" "$W/share/man" "$W/share/applications"
for t in winegcc wineg++ winecpp winebuild wrc widl wmc winedump winemaker function_grep.pl msidb; do rm -f "$W/bin/$t"; done
find "$W/lib/wine" -name '*.a' -delete
# debug info out (keeps symbols); no build paths remain in the binaries
find "$W/bin" "$W/lib/wine/x86_64-unix" -type f -exec sh -c 'file -b "$1" | grep -q ELF' _ {} \; -exec "$STRIP" --strip-debug {} +
if [[ -x $PESTRIP ]] || command -v "$PESTRIP" >/dev/null; then
    find "$W/lib/wine/x86_64-windows" -type f \( -name '*.dll' -o -name '*.exe' -o -name '*.drv' -o -name '*.sys' -o -name '*.ocx' -o -name '*.cpl' -o -name '*.acm' -o -name '*.ax' -o -name '*.tlb' -o -name '*.ds' -o -name '*.msstyles' -o -name '*.vxd' -o -name '*.com' \) \
        -exec "$PESTRIP" --strip-debug {} + 2>/dev/null || true
fi

# ---------------------------------------------------------------- native dependencies
step "patched GnuTLS and its libraries"
mkdir -p "$L/gnutls" "$L/deps"
cp "$(readlink -f "$BUILD/install-gnutls/lib/libgnutls.so.30")" "$L/gnutls/libgnutls.so.30"
"$STRIP" --strip-debug "$L/gnutls/libgnutls.so.30"
python3 "$ROOT/tools/collect-libs.py" --dest "$L/gnutls" --search "$DEB" --record "$REC" "$L/gnutls/libgnutls.so.30"
step "Kerberos, libunwind"
python3 "$ROOT/tools/collect-libs.py" --dest "$L/deps" --have "$L/gnutls" --search "$DEB" --record "$REC" \
    "$DEB/libgssapi_krb5.so.2" "$DEB/libkrb5.so.3" "$DEB/libunwind.so.8"
for so in libgssapi_krb5.so.2 libkrb5.so.3 libunwind.so.8; do
    [[ -e $L/deps/$so ]] || { cp "$(readlink -f "$DEB/$so")" "$L/deps/$so"; python3 - "$REC" "$so" "$DEB" <<'EOF'
import hashlib, json, os, sys
rec, so, deb = sys.argv[1:]
d = json.load(open(rec)); real = os.path.realpath(os.path.join(deb, so))
d.append({"soname": so, "source": real, "sha256": hashlib.sha256(open(real, "rb").read()).hexdigest(),
          "package": "see debian-binaries.lock", "needed_by": "wine (dlopen)"})
json.dump(d, open(rec, "w"), indent=1)
EOF
    }
done
# Wine's own ELF files: everything they link must be bundled or on the host allowlist
python3 "$ROOT/tools/collect-libs.py" --dest "$L/deps" --have "$L/gnutls" --have "$W/lib/wine/x86_64-unix" \
    --search "$DEB" --record "$REC" "$W/bin/wine" "$W/bin/wineserver" $(find "$W/lib/wine/x86_64-unix" -name '*.so' -type f)
step "private NTLM helper (Samba ntlm_auth)"
cp -a "$BUILD/stage/samba" "$L/samba"
python3 "$ROOT/tools/collect-libs.py" --dest "$L/samba/lib" --have "$L/gnutls" --have "$L/deps" \
    --search "$DEB/samba" --search "$DEB" --record "$REC" "$L/samba/bin/ntlm_auth.bin" "$L/samba/lib/libmstsc-samba-paths.so"
# the helper must answer in client mode with only the bundle (no winbindd, no host Samba)
probe=$(printf 'PW YXNzZW1ibGU=\nYR\n' | env -u LD_LIBRARY_PATH "$L/samba/bin/ntlm_auth" \
        --helper-protocol=ntlmssp-client-1 --username=assemble --domain=CHECK 2>&1 | tail -1)
[[ $probe == "YR "* ]] || fail "bundled ntlm_auth self-test failed: $probe"
cp "$ROOT/packaging/integrate.sh" "$L/integrate.sh"; chmod 755 "$L/integrate.sh"

# ---------------------------------------------------------------- Microsoft components
step "Microsoft components (verified against their manifest)"
python3 "$ROOT/tools/mscomponents.py" extract "$ZIP" "$S" > "$T/components.out" || { cat "$T/components.out" >&2; fail "component bundle rejected"; }
cat "$T/components.out"
mv "$S/component-manifest.json" "$M/component-manifest.json"
client_version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verified"]["client_version"])' "$M/component-manifest.json")
client_lang=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source"]["language"])' "$M/component-manifest.json")

# ---------------------------------------------------------------- launcher, desktop entry, icon
step "launcher, desktop entry and icon"
install -m 755 "$ROOT/launcher/mstsc-wine" "$U/bin/mstsc"
install -m 755 "$ROOT/packaging/appdir/AppRun" "$T/AppRun"
APP_ID=org.mstscwine.RemoteDesktopConnection
install -m 644 "$ROOT/packaging/appdir/$APP_ID.desktop" "$U/share/applications/$APP_ID.desktop"
cp "$U/share/applications/$APP_ID.desktop" "$T/$APP_ID.desktop"
ICONS=$T/icons.tmp
if icon_json=$(python3 "$ROOT/tools/mscomponents.py" icon "$ICONS" "$S/Windows/system32/mstsc.exe" "$S/Windows/SystemResources/mstsc.exe.mun" 2>/dev/null); then
    icon_src="Microsoft (generated locally from the operator's $(sed 's/.*"source": "\([^"]*\)".*/\1/' <<<"$icon_json"); not redistributable)"
    for f in "$ICONS"/mstsc-wine-*.png; do
        n=$(basename "$f" .png); n=${n#mstsc-wine-}
        mkdir -p "$U/share/icons/hicolor/${n}x${n}/apps"
        cp "$f" "$U/share/icons/hicolor/${n}x${n}/apps/$APP_ID.png"
    done
    big=$(ls "$ICONS"/mstsc-wine-*.png | sed 's/.*-\([0-9]*\)\.png/\1 &/' | sort -n | tail -1 | cut -d' ' -f2)
    cp "$big" "$T/$APP_ID.png"
    ln -s "$APP_ID.png" "$T/.DirIcon"
else
    icon_src="project fallback (packaging/icons, MIT)"
    mkdir -p "$U/share/icons/hicolor/scalable/apps"
    cp "$ROOT/packaging/icons/$APP_ID.svg" "$U/share/icons/hicolor/scalable/apps/$APP_ID.svg"
    cp "$ROOT/packaging/icons/$APP_ID.svg" "$T/$APP_ID.svg"
    ln -s "$APP_ID.svg" "$T/.DirIcon"
fi
rm -rf "$ICONS"

# ---------------------------------------------------------------- metadata
step "metadata, licences and source information"
launcher_version=$(sed -n 's/^VERSION=//p' "$ROOT/launcher/mstsc-wine")
. <(sed 's/^\([a-z_0-9]*\)=\(.*\)$/\1="\2"/' "$BUILD/stage/wine-build-info.txt")
gnutls_version=$(sed -n 's/^gnutls_version=//p' "$BUILD/install-gnutls/gnutls-build-info.txt")
winbind=$(grep '^winbind ' "$BUILD/debroot/.packages" | cut -d' ' -f2)
git_rev=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
git -C "$ROOT" diff --quiet HEAD -- launcher tools packaging patches 2>/dev/null || git_rev="$git_rev+local-changes"
python3 - "$M/build-info.json" <<EOF
import json, sys
json.dump({
  "schema": "mstsc-wine-build-info/1",
  "mstsc_wine_version": "$launcher_version",
  "mstsc_wine_revision": "$git_rev",
  "built": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "build_engine": "${BUILD_ENGINE:-native}",
  "build_image": "${MSTSC_BUILD_IMAGE:-}",
  "target": "Debian 13 (trixie) x86-64, glibc",
  "wine_tag": "$wine_tag",
  "wine_commit": "$wine_commit",
  "wine_version": "$wine_version",
  "patch_count": "$patch_count",
  "patch_series_sha256": "$patch_series_sha256",
  "patches_sha256": "$patches_sha256",
  "wine_source_tree": "$source_tree",
  "compiler": "$compiler",
  "cross_compiler": "$cross_compiler",
  "gnutls_version": "$gnutls_version",
  "ntlm_helper": "Samba ntlm_auth from Debian winbind $winbind",
  "client_version": "$client_version",
  "client_language": "$client_lang",
  "icon": "$icon_src"
}, open(sys.argv[1], "w"), indent=1)
EOF
python3 "$ROOT/tools/dependency-manifest.py" --build "$BUILD" --libs "$REC" --appdir "$T" --out "$M/dependency-manifest.json" \
    --notices "$M/license-notices"
rm -f "$REC" "$T/components.out"
cp "$ROOT/LICENSE" "$M/license-notices/mstsc-wine-LICENSE"
cp -r "$ROOT/patches" "$M/source/patches"
cp "$ROOT/packaging/debian-binaries.lock" "$ROOT/packaging/components-policy.json" "$M/source/"
cp "$ROOT/docs/SOURCES.md" "$M/SOURCES.md"

# ---------------------------------------------------------------- checks
step "checks"
# no path of this machine's build tree in any shipped text file or ELF string table
leak=$(grep -rlF --binary-files=text -e "$ROOT" -e "$BUILD" "$T" 2>/dev/null | grep -v '/metadata/' || true)
[[ -z $leak ]] || fail "build paths embedded in: $(sed "s|$T/||" <<<"$leak" | head -5 | tr '\n' ' ')"
find "$T" -type d -exec chmod 755 {} +
chmod -R go-w "$T"
rm -rf "$OUT.old"; [[ -e $OUT ]] && mv "$OUT" "$OUT.old"
mv "$T" "$OUT"; rm -rf "$OUT.old"
step "done: $OUT ($(du -sh "$OUT" | cut -f1), mstsc $client_version)"
