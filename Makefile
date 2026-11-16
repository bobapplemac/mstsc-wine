# MSTSC-Wine: build a private, relocatable Remote Desktop Connection package from source
# and your own Microsoft component ZIP. `make help` lists the targets. See docs/PACKAGING.md.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:

ROOT          := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
# docker (default when usable) or native (Debian 13 host with the packages in packaging/build-deps.txt)
DOCKER        ?= docker
BUILD_ENGINE  ?= $(shell $(DOCKER) info >/dev/null 2>&1 && echo docker || echo docker-unavailable)
JOBS          ?= $(shell nproc)
ARTIFACTS     ?= $(ROOT)/artifacts
APPDIR        ?= $(ARTIFACTS)/MSTSC-Wine.AppDir
APPIMAGE      ?= $(ARTIFACTS)/mstsc-wine-x86_64.AppImage
VERSION       := $(shell sed -n 's/^VERSION=//p' $(ROOT)/launcher/mstsc-wine)
TARBALL       ?= $(ARTIFACTS)/mstsc-wine-$(VERSION)-x86_64.tar.zst
# Your Microsoft component ZIP (windows/Export-MstscComponents.ps1). Default: the single
# mstsc-components-*.zip in private-input/.
MICROSOFT_COMPONENTS ?= $(wildcard $(ROOT)/private-input/mstsc-components-*.zip)

ifeq ($(BUILD_ENGINE),native)
  B := $(ROOT)/build/native
else
  B := $(ROOT)/build/docker
endif
export JOBS DOCKER

WINE_OUT   := $(B)/stage/wine-build-info.txt
GNUTLS_OUT := $(B)/install-gnutls/gnutls-build-info.txt
NTLM_OUT   := $(B)/stage/samba/bin/ntlm_auth.bin

.PHONY: all verify-components wine gnutls ntlm appdir appimage package test test-portability doctor \
        install uninstall integrate-appimage clean distclean help check-engine

all: verify-components appdir

help:
	@echo 'MSTSC-Wine build (docs/PACKAGING.md)'
	@echo
	@echo '  make                    validate your component ZIP and build the AppDir ($(APPDIR))'
	@echo '  make verify-components  check the ZIP (structure, policy, one Windows build, SHA-256)'
	@echo '  make wine|gnutls|ntlm   build one open-source part (pinned Wine + patches, patched GnuTLS,'
	@echo '                          private Samba ntlm_auth)'
	@echo '  make appdir             assemble the relocatable AppDir'
	@echo '  make appimage           single-file AppImage ($(APPIMAGE)); local only'
	@echo '  make package            relocatable tarball ($(TARBALL))'
	@echo '  make test               regression and packaging tests'
	@echo '  make doctor             check the AppDir and this system'
	@echo '  make install            install for this user (~/.local/opt, menu entry, ~/.local/bin/mstsc)'
	@echo '  make uninstall          remove what install created; keeps your settings (PURGE=1 removes them)'
	@echo '  make clean              remove packaging outputs (keeps your ZIP, settings and dev builds)'
	@echo
	@echo 'Variables:'
	@echo '  MICROSOFT_COMPONENTS=/path/to/mstsc-components-<build>-amd64.zip   (default: private-input/)'
	@echo '  BUILD_ENGINE=docker|native   (now: $(BUILD_ENGINE))   DOCKER="sudo docker" or podman'
	@echo '  JOBS=$(JOBS)   ARTIFACTS=$(ARTIFACTS)'
	@echo '  PREFIX=/opt/mstsc-wine DESTDIR=...   system-style install (no privilege escalation)'
	@echo '  MSTSC_COMPONENTS_EXPERIMENTAL=1      accept a ZIP from an unverified Windows build'

check-engine:
ifeq ($(BUILD_ENGINE),docker-unavailable)
	@echo "error: Docker is not usable by you (not installed, daemon stopped, or no permission)." >&2
	@echo "  Use one of:  make DOCKER='sudo docker'   make DOCKER=podman" >&2
	@echo "               make BUILD_ENGINE=native     (Debian 13 with packaging/build-deps.txt installed)" >&2
	@exit 1
endif

define need_zip
	@zips=( $(MICROSOFT_COMPONENTS) ); \
	if [[ $${#zips[@]} -eq 0 ]]; then \
	  echo "error: no Microsoft component ZIP. Export one on Windows with windows/Export-MstscComponents.ps1," >&2; \
	  echo "  then put it in private-input/ or pass MICROSOFT_COMPONENTS=/path/to/zip (docs/binary-acquisition.md)" >&2; exit 1; \
	elif [[ $${#zips[@]} -gt 1 ]]; then \
	  echo "error: several ZIPs found; choose one with MICROSOFT_COMPONENTS=..." >&2; printf '  %s\n' "$${zips[@]}" >&2; exit 1; \
	fi
endef

verify-components:
	$(need_zip)
	@python3 $(ROOT)/tools/mscomponents.py verify "$(MICROSOFT_COMPONENTS)"

# ---------------------------------------------------------------- open-source builds
wine: $(WINE_OUT)
gnutls: $(GNUTLS_OUT)
ntlm: $(NTLM_OUT)

ifeq ($(BUILD_ENGINE),native)
$(WINE_OUT): $(ROOT)/patches/series $(wildcard $(ROOT)/patches/*.patch) $(ROOT)/tools/build-wine.sh
	MSTSC_BUILD_DIR=$(B) $(ROOT)/tools/build-wine.sh dist
$(GNUTLS_OUT): $(ROOT)/tools/build-gnutls.sh $(wildcard $(ROOT)/patches/gnutls/*.patch)
	MSTSC_BUILD_DIR=$(B) $(ROOT)/tools/build-gnutls.sh none
$(NTLM_OUT): $(ROOT)/packaging/debian-binaries.lock $(ROOT)/tools/build-ntlm.sh $(ROOT)/tools/fetch-debs.sh $(wildcard $(ROOT)/packaging/samba/*)
	MSTSC_BUILD_DIR=$(B) $(ROOT)/tools/build-ntlm.sh
else
$(WINE_OUT): $(ROOT)/patches/series $(wildcard $(ROOT)/patches/*.patch) $(ROOT)/tools/build-wine.sh $(ROOT)/docker/Dockerfile | check-engine
	$(ROOT)/tools/docker-build.sh wine
$(GNUTLS_OUT): $(ROOT)/tools/build-gnutls.sh $(wildcard $(ROOT)/patches/gnutls/*.patch) $(ROOT)/docker/Dockerfile | check-engine
	$(ROOT)/tools/docker-build.sh gnutls
$(NTLM_OUT): $(ROOT)/packaging/debian-binaries.lock $(ROOT)/tools/build-ntlm.sh $(ROOT)/tools/fetch-debs.sh $(wildcard $(ROOT)/packaging/samba/*) $(ROOT)/docker/Dockerfile | check-engine
	$(ROOT)/tools/docker-build.sh ntlm
endif

# ---------------------------------------------------------------- artifacts (host side)
appdir: $(WINE_OUT) $(GNUTLS_OUT) $(NTLM_OUT)
	$(need_zip)
	BUILD_ENGINE=$(BUILD_ENGINE) MSTSC_BUILD_IMAGE="$$(cat $(B)/build-image.txt 2>/dev/null || true)" \
	  $(ROOT)/tools/assemble-appdir.sh $(B) "$(MICROSOFT_COMPONENTS)" $(APPDIR)

appimage: appdir
	$(ROOT)/tools/build-appimage.sh $(APPDIR) $(APPIMAGE)

package: appdir
	@epoch=$$(stat -c %Y $(APPDIR)/usr/share/mstsc-wine/metadata/build-info.json); \
	tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@$$epoch \
	    -C $(dir $(APPDIR)) -I 'zstd -q -19 -T0' -cf $(TARBALL).part $(notdir $(APPDIR)) && mv -f $(TARBALL).part $(TARBALL)
	@echo "package: $(TARBALL) ($$(du -h $(TARBALL) | cut -f1)). Private: contains your Microsoft components."

# Regression suite on the package itself (through its launcher), on the development runtime
# too when one has been built (tools/build-wine.sh patched), then the release gates.
test:
	$(ROOT)/tests/portability/runtime-shim.sh $(APPDIR)/AppRun $(ROOT)/build/test-shim
	$(ROOT)/tests/run-regression.sh $(ROOT)/build/test-shim patched
	if [[ -x $(ROOT)/build/install-wine-patched/bin/wine ]]; then \
	  $(ROOT)/tests/run-regression.sh $(ROOT)/build/install-wine-patched patched; fi
	$(ROOT)/tests/portability/run.sh $(APPDIR) "$(wildcard $(APPIMAGE))" "$(wildcard $(TARBALL))"

test-portability:
	$(ROOT)/tests/portability/run.sh $(APPDIR) "$(wildcard $(APPIMAGE))" "$(wildcard $(TARBALL))"

doctor:
	$(APPDIR)/AppRun doctor

install:
	@[[ -x $(APPDIR)/AppRun ]] || { echo "error: no AppDir at $(APPDIR); run make first" >&2; exit 1; }
	$(APPDIR)/usr/lib/mstsc-wine/integrate.sh install --appdir $(APPDIR) $(if $(MIME),--mime)

uninstall:
	@MSTSC_WINE_PURGE_HINT='make uninstall PURGE=1' $(ROOT)/packaging/integrate.sh uninstall $(if $(PURGE),--purge)

integrate-appimage:
	$(ROOT)/packaging/integrate.sh install --appimage $(APPIMAGE)

clean:
	rm -rf $(ROOT)/build/docker $(ROOT)/build/native $(ROOT)/build/test-shim $(APPDIR) $(APPDIR).tmp $(APPIMAGE) $(TARBALL) \
	       $(ARTIFACTS)/*.squashfs.tmp $(ARTIFACTS)/*.part

distclean: clean
	rm -rf $(ROOT)/build/docker-cache
