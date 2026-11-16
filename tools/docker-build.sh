#!/bin/bash
# Run open-source build steps inside the pinned Debian 13 build image (ADR-0045).
#   tools/docker-build.sh STEP...     STEP = wine | gnutls | ntlm | shell
# Only tools/, patches/ and packaging/ are mounted (read-only); outputs go to
# build/docker (owned by you), downloads to build/docker-cache. The Microsoft component
# ZIP, Windows/ and private-input/ are never mounted. No privileges, devices, X11 socket
# or host network are given to the container.
# Environment: DOCKER (default docker; e.g. "sudo docker" or podman), JOBS,
# DOCKER_SNAPSHOT (snapshot date; empty = current Debian mirrors).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DOCKER=${DOCKER:-docker}
JOBS=${JOBS:-$(nproc)}
SNAP=${DOCKER_SNAPSHOT-20261115T000000Z}
fail() { echo "docker-build: $*" >&2; exit 1; }
$DOCKER info >/dev/null 2>&1 || fail "'$DOCKER' is not usable (is the daemon running, and may you use it?).
  Options: add yourself to the 'docker' group, set DOCKER='sudo docker' or DOCKER=podman,
  or build natively on Debian 13 with BUILD_ENGINE=native (see docs/PACKAGING.md)."
tag=$( (cat "$ROOT/docker/Dockerfile"; echo "$SNAP") | sha256sum | cut -c1-12)
IMAGE=mstsc-wine-build:$tag
if ! $DOCKER image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "docker-build: building image $IMAGE (Debian 13, snapshot ${SNAP:-none})"
    $DOCKER build -t "$IMAGE" --build-arg SNAPSHOT="${SNAP:-x}" --build-arg USE_SNAPSHOT=$([[ -n $SNAP ]] && echo 1 || echo 0) \
        "$ROOT/docker" || fail "image build failed"
fi
digest=$($DOCKER image inspect "$IMAGE" --format '{{.Id}}')
OUT=$ROOT/build/docker CACHE=$ROOT/build/docker-cache
mkdir -p "$OUT" "$CACHE"
mirror=()
[[ -d $ROOT/wine-src/.git ]] && mirror=(-v "$ROOT/wine-src:/mirror/wine-src:ro" -e WINE_URL=file:///mirror/wine-src)
run() {
    $DOCKER run --rm --user "$(id -u):$(id -g)" --security-opt no-new-privileges \
        -e HOME=/tmp -e JOBS="$JOBS" -e MSTSC_BUILD_DIR=/work/build -e MSTSC_DL_DIR=/work/cache/dl \
        -e MSTSC_SRC_DIR=/work/cache/src -e WINE_SRC_DIR=/work/cache/wine-src -e GIT_CONFIG_COUNT=1 \
        -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
        -v "$ROOT/tools:/work/tools:ro" -v "$ROOT/patches:/work/patches:ro" -v "$ROOT/packaging:/work/packaging:ro" \
        -v "$OUT:/work/build" -v "$CACHE:/work/cache" "${mirror[@]}" \
        "$IMAGE" "$@"
}
for step in "$@"; do
    case $step in
        wine)   run /work/tools/build-wine.sh dist ;;
        gnutls) run /work/tools/build-gnutls.sh none ;;
        ntlm)   run /work/tools/build-ntlm.sh ;;
        shell)  run bash ;;
        *) fail "unknown step $step" ;;
    esac
done
echo "$IMAGE $digest" > "$OUT/build-image.txt"
run cat /usr/share/mstsc-wine-build-packages.txt > "$OUT/build-image-packages.txt"
