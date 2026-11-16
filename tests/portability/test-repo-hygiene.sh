#!/bin/bash
# PKG-002: the public repository and the Docker build context contain no Microsoft binaries,
# component ZIPs, generated artifacts or credentials.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
fail=0
bad=$(git ls-files | grep -iE '\.(exe|dll|mui|mun|ttf|ttc|ocx|sys|cpl|drv|zip|appimage|ico|tar\.zst|squashfs)$' || true)
[[ -z $bad ]] || { echo "tracked proprietary/binary artifacts: $bad"; fail=1; }
# no tracked file is a PE image (MZ...PE header), whatever its name
while IFS= read -r -d '' f; do
    [[ -f $f ]] || continue
    head -c 2 "$f" 2>/dev/null | grep -q '^MZ' && python3 - "$f" <<'PY' && { echo "tracked PE file: $f"; fail=1; }
import struct, sys
d = open(sys.argv[1], 'rb').read(4096)
o = struct.unpack_from('<I', d, 0x3c)[0] if len(d) > 0x40 else 0
sys.exit(0 if d[o:o+4] == b'PE\0\0' else 1)
PY
done < <(git ls-files -z)
for p in private-input/mstsc-components-1-amd64.zip Windows/system32/mstsc.exe Windows/Fonts/segoeui.ttf \
         artifacts/mstsc-wine-x86_64.AppImage artifacts/MSTSC-Wine.AppDir/AppRun x/mstsc-wine-1-x86_64.tar.zst \
         some/where/mstsc.exe.mun build/docker/x; do
    git check-ignore -q "$p" || { echo "not ignored: $p"; fail=1; }
done
# Docker build context = docker/ with only the Dockerfile admitted
[[ $(ls -A docker | LC_ALL=C sort | tr "\n" " ") == ".dockerignore Dockerfile " ]] || { echo "unexpected files in docker/"; fail=1; }
grep -qx '\*' docker/.dockerignore && grep -qx '!Dockerfile' docker/.dockerignore || { echo ".dockerignore must exclude everything but Dockerfile"; fail=1; }
grep -nE '^(COPY|ADD) ' docker/Dockerfile && { echo "Dockerfile copies files into the image"; fail=1; }
# no obvious secrets in tracked text
git grep -nIE '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)|(password|passwd)\s*[:=]\s*["'"'"'][^"'"'"'$<{]{6,}' -- ':!tests/' ':!docs/' && { echo "possible secret"; fail=1; }
exit $fail
