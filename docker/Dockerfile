# MSTSC-Wine build environment (ADR-0045): Debian 13 (trixie), pinned by image digest and
# by a snapshot.debian.org date, so the toolchain and -dev packages are fixed.
# The build context is this directory only (see .dockerignore): no repository files and
# never any Microsoft component enter the image. Sources are bind-mounted read-only at
# run time by tools/docker-build.sh; the image itself contains only Debian packages.
FROM debian:trixie@sha256:9c6e381421d0f48d1b8133e573f33c185ee16cbf505eda9c4a8a4791b25ea8a6

ARG SNAPSHOT=20261115T000000Z
ARG USE_SNAPSHOT=1
RUN set -eu; \
    if [ "$USE_SNAPSHOT" = 1 ]; then \
      rm -f /etc/apt/sources.list.d/debian.sources; \
      printf '%s\n' \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/$SNAPSHOT trixie main" \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/$SNAPSHOT trixie-updates main" \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/$SNAPSHOT trixie-security main" \
        > /etc/apt/sources.list.d/snapshot.list; \
    fi; \
    echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80retries; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git file binutils make gcc g++ gcc-mingw-w64-x86-64 \
      flex bison autoconf automake libtool autopoint gettext pkgconf python3 xz-utils patch \
      libx11-dev libxext-dev libxrender-dev libxrandr-dev libxi-dev libxcursor-dev libxinerama-dev \
      libxcomposite-dev libxfixes-dev libxxf86vm-dev libfreetype-dev libfontconfig-dev \
      libgnutls28-dev libkrb5-dev libpulse-dev libasound2-dev libudev-dev libusb-1.0-0-dev \
      libpcsclite-dev libunwind-dev libvulkan-dev libgl-dev libegl-dev libsdl2-dev libcups2-dev \
      libv4l-dev \
      nettle-dev libgmp-dev libtasn1-6-dev libidn2-dev libunistring-dev libp11-kit-dev; \
    rm -rf /var/lib/apt/lists/*; \
    dpkg-query -W -f='${Package} ${Version}\n' > /usr/share/mstsc-wine-build-packages.txt
ENV LANG=C.UTF-8
WORKDIR /work
