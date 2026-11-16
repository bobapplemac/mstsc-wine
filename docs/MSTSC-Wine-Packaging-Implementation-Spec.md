# MSTSC-Wine — Packaging, Isolation and Portability Implementation Specification

**Version:** 1.1 — 2026-11-15  
**Audience:** Claude Code or another autonomous coding agent  
**Existing repository:** `mstsc-wine`  
**Baseline:** Debian 13 Trixie, x86-64, glibc  
**Status:** Implementation brief grounded in the repository snapshot `835c919198a67e5232c1214ed61cd9a645b1b0ec`; the working tree may have advanced since this snapshot.

## 0. Agent instructions: read before acting

You are the principal engineer for the next phase of **MSTSC-Wine**. Your assignment is to transform the **existing working project** into a reproducible, locally built, relocatable, privately isolated Linux application. This is **not** a rewrite of Wine or MSTSC and **not** an invitation to replace the Microsoft RDP engine with FreeRDP. Preserve and build on the existing implementation.

Before modifying files:

1. Read the repository's `AGENTS.md`, `README.md`, `docs/STATUS.md`, `docs/COMPATIBILITY.md`, `docs/RESEARCH.md`, `docs/binary-acquisition.md`, the original master specification, all relevant ADRs, existing build scripts, the launcher, and test entry points.
2. Inspect the **current** Git working tree and history. The snapshot findings in this document are clues, not assertions that the latest checkout is unchanged.
3. Inventory the current build outputs, Wine patches, patched GnuTLS, native dependencies, prefix behavior, Microsoft-file handling, and existing manual test successes. Establish and record a passing baseline before invasive refactoring.
4. Preserve established repository conventions: pinned upstream inputs, ordered Wine patches, tests, ADRs, research evidence (verified/inferred/hypothesized), meaningful commits, and explicit blocker reporting.
5. Keep the proprietary Microsoft material and all sensitive authentication data out of Git, public artifacts, CI logs, Docker image layers, caches that could be published, and issue reports.

**Primary deliverable:** `make` builds an isolated, relocatable AppDir from source and operator-supplied Microsoft files; `make appimage` builds a runnable, single-file local AppImage; `make package` builds a relocatable tarball; `make install` installs the application without modifying system Wine/Samba. Users should run `mstsc /v:server01` (installed) or `./mstsc-wine-x86_64.AppImage /v:server01` (portable).

**Do not stop at a design document.** Implement, verify, commit, and continue through the milestones. Stop for user input only on genuine external blockers, scope-changing architectural choices, or irreversible actions.

## 1. Non-negotiable product decisions

1. **Source-only public distribution.** No project-published compiled binaries or bundled Microsoft components. Users compile the patched Wine runtime as part of the normal local build.
2. **Genuine Microsoft RDP implementation.** Run the user's original `mstsc.exe`/`mstscax.dll`; no FreeRDP client replacement or Windows VM.
3. **All-in-one privately generated artifact.** The user's locally generated AppDir/AppImage/tarball includes the user-supplied Microsoft files, required fonts and resources, private Wine, patched GnuTLS, and working NTLM support. Do not force users to maintain a second Microsoft component directory beside the final executable.
4. **No system Wine or Samba dependency.** Do not require the target machine to install Wine, Samba, Winbind, or `ntlm_auth`; do not execute system copies of those binaries or read unrelated configurations to supply project-private functionality.
5. **Complete Wine isolation.** The project's Wine runtime, DLL overrides, wineserver, registry, and prefix must not modify or interfere with the user's system Wine, Bottles, Lutris, or other Wine installations. Prefix isolation is a configuration boundary, **not** a security sandbox.
6. **Debian 13/glibc baseline.** Target Debian 13 Trixie on x86-64 initially; KDE Wayland via XWayland and Cinnamon/X11 are important runtime test configurations. Native Wayland and musl are research/future items, not release gates.
7. **Docker for reproducible building, not GUI runtime.** Build in a pinned Debian 13 container where feasible. The final application runs natively under the user's regular Linux desktop session.
8. **Canonical AppDir.** One relocatable AppDir tree underlies the AppImage, tarball, and installation. Do not create three different runtime layouts.
9. **Mutable state outside the artifact.** Keep prefix/registry, logs, caches, and user configuration under XDG paths. The AppImage/AppDir may be read-only.
9a. **Ordinary installed-app experience.** `make install` MUST register a standard freedesktop desktop application named **Remote Desktop Connection**, display an MSTSC-style icon extracted locally from operator-supplied Microsoft assets where the operator is authorized to use it, and expose a shell command named `mstsc` on the user's normal `PATH`. Running the AppImage without installation remains supported; a separate explicit user integration flow installs/removes its menu and command entries without requiring AppImageLauncher.
10. **No root at runtime.** Building may use Docker; runtime must not need root privileges, a background Samba/Winbind daemon, host-global changes, or a domain join for ordinary explicit-credential logons.
11. **Keep current compatibility behavior.** Existing functional NTLM, Kerberos, CredSSP, certificate prompts, clipboard formats, Windows file copy/paste, fullscreen, and UI rendering must not regress.
12. **Licensing clarity.** The project does not grant rights to use Microsoft components under Linux. Explain that self-extraction and absence of redistribution do not, by themselves, establish license compliance. Do not bypass licensing, activation, or Microsoft's security controls.

## 2. Verified source-review findings to account for

The reviewed snapshot already contains:

- `tools/build-wine.sh`: pinned upstream Wine 11.0 (`db11d0fe6a169c457e23d007e20404643d067aa8`), baseline/patched worktrees, ordered `patches/series` (~38 Wine patches), out-of-tree build and install.
- `tools/build-gnutls.sh`: Debian GnuTLS 3.8.9 source with Debian patches plus a project-specific key-usage patch; current `VER`/`DEB` inputs are version-specific.
- `launcher/mstsc-wine`: Bash entry point with `run`, `init`, `import`, `doctor`, `exec`, `--version`; XDG state locations; hashed private component store; project-path-based runtime fallback.
- `docs/DECISIONS/0001–0041`: rationale for authentication, TLS, UI and clipboard changes; preserve them.
- `tests/run-regression.sh`, `tests/launch/`, `tests/security/`, `tests/static/`: existing tests and custom protocol fixtures.

**Packaging obstacles observed in the snapshot:**

1. Wine configure/install embeds a path within `$ROOT/build/install-*`. Portability and any embedded absolute paths require verification and possibly refactoring.
2. Launcher runtime lookup expects either an override, a user data runtime path, or `$PROJECT_DIR/build/install-wine-patched`; installed AppDir needs its own stable relative lookup.
3. The runtime prepends a custom GnuTLS library to `LD_LIBRARY_PATH`, yet other dependency paths and indirect `dlopen()` dependencies need a complete audit.
4. `doctor` checks host `libgnutls`, `libgssapi_krb5`, `libpulse`, `libX11`, FreeType and Fontconfig availability; packaged-mode diagnostics must inspect the actual runtime resolution rather than assume host packages.
5. `doctor` looks for `ntlm_auth` through `PATH`; the helper and its dependencies are not yet private.
6. The component import process installs Microsoft files into a mutable Wine prefix, duplicating files from the component store. Determine whether this staging behavior is best retained, symlinked, or initialized as a versioned copy; it must work when AppDir is read-only.
7. The README presently says Microsoft files are never packaged. Rewrite to distinguish **public repository/releases** (never include them) from **private user-generated output** (may include them if allowed by the user's license).
8. `.gitignore` covers individual `*.exe`, `*.dll`, `*.mui`, fonts, and some directories but not a private `*.zip` bundle; explicitly exclude all known private input/staging paths and validate staged Git content.
9. The launcher `wait` of an MSTSC child runs under `set -e`; handle nonzero exit codes without bypassing exit-status logging.
10. Source-level evidence is not runtime certification: do not claim cross-distribution portability or clean-host operation until tested.

## 3. User experience and commands

### 3.1 Desired end-to-end workflow

On a supported Windows machine, a user invokes a documented PowerShell exporter (download-and-run shortcut optional; also support local, inspectable script execution). The exporter creates `mstsc-components-<OS-build>-amd64.zip` with the exact required Microsoft components and a signed/hashed manifest where applicable. User copies the ZIP to Linux.

On Debian 13:

```bash
git clone <repository-url> mstsc-wine
cd mstsc-wine
cp /path/to/mstsc-components-*.zip ./private-input/
make
make appimage
./artifacts/mstsc-wine-x86_64.AppImage /v:server01
```

The public repository MUST NOT already contain or download the Microsoft content. Support a clear `MICROSOFT_COMPONENTS=/absolute/path.zip` override so users need not put the ZIP in the checkout. Default paths must be safe and intuitive.

### 3.2 Make targets

| Target | Contract |
|---|---|
| `make` / `make all` | Validate inputs and build complete canonical AppDir using the documented default build engine. |
| `make verify-components` | Validate input ZIP structure, provenance/build consistency and SHA-256 integrity; never mutate Git files. |
| `make wine` | Build pinned, patched Wine source. |
| `make gnutls` | Build the patched private GnuTLS. |
| `make ntlm` | Build or acquire-from-verified-source the private NTLM helper and its dependency closure. |
| `make appdir` | Assemble relocatable, self-contained directory from successful component builds. |
| `make appimage` | Produce local AppImage from AppDir; do not publish/upload. |
| `make package` | Produce relocatable `.tar.zst` archive. |
| `make test` | Execute automated and available GUI/functional regression tests. |
| `make doctor` | Check generated AppDir, private dependencies, and target-system integration. |
| `make install` | Install for current user by default; allow explicit prefix/DESTDIR selection. |
| `make uninstall` | Remove only files installed from that manifest, leaving user data unless explicit purge. |
| `make clean` | Remove only known generated outputs; preserve supplied ZIP and pre-existing user state. |
| `make help` | Explain common targets and configuration variables. |

`make` should use Docker/Podman by default **if present and usable**; a native Debian 13 build option may be supported to reduce barriers. Emit actionable errors if prerequisites are missing. Don't silently fall back to an unpinned host toolchain.

### 3.3 Windows exporter requirements

- Provide `windows/Export-MstscComponents.ps1` as readable, versioned source.
- Detect Windows edition/build/architecture, culture, paths, missing files, and file-version consistency. Enforce explicit supported-version policy; reject unsupported OS builds with a useful error unless operator deliberately selects an experimental mode.
- Export required files from the same Windows installation/build, preserving `Windows/system32`, `en-US` or actual language-specific satellite files, `Windows/SystemResources`, and `Windows/Fonts` layout.
- Starting known list: `mstsc.exe`, `mstscax.dll`, `dui70.dll` plus `.mui`; optionally `duser.dll` where required by the selected build; `.mun` files for MSTSC; Segoe UI/symbol, Tahoma and Microsoft Sans Serif fonts; preserve any other dependencies confirmed by current tests. The supplied source-review example also included `credssp.dll`, `TSpkg.dll` and `devobj.dll`, but the project must classify these based on actual use/override behavior, not blindly install them.
- Generate a machine-readable `manifest.json` with schema version, source build, language, architecture, component path, file version and SHA-256 for each file; ensure source path and machine-identifying fields do not leak unnecessarily.
- Zip without including credentials, registry secrets, domain configuration, unrelated Windows DLLs, or any whole-system copies.
- Never automatically upload the ZIP. Display a concise statement about proprietary content and applicable license terms.
- Support a reviewed download command such as `irm <version-pinned-url> -OutFile Export-MstscComponents.ps1; .\Export-MstscComponents.ps1`; a documented `irm | iex` convenience variant may be offered but should not be the sole option or silently execute mutable `main`.

## 4. Canonical artifact layout

Create an AppImage-compatible AppDir similar to the following; exact internal paths may be adjusted based on runtime probing, but **all paths must be relative or otherwise relocatable**:

```text
MSTSC-Wine.AppDir/
  AppRun
  mstsc-wine.desktop
  mstsc-wine.png
  usr/
    bin/mstsc
    lib/mstsc-wine/
      wine/                   # patched private Wine binaries and libraries
      gnutls/                 # patched private GnuTLS and its needed libraries
      samba/bin/ntlm_auth     # exact helper used by this Wine build
      samba/lib/             # private Samba dependency closure as needed
      deps/                  # approved privately bundled native dependencies
    share/mstsc-wine/
      Windows/
        system32/            # user-supplied Microsoft files and language satellites
        Fonts/
        SystemResources/
      metadata/
        build-info.json
        component-manifest.json
        dependency-manifest.json
        license-notices/
```

Do not add a generic `/usr/bin/wine` symlink, make the private Wine install visible globally, register host-wide file associations, or install system services. The only exposed command is the Linux-native `mstsc` launcher, with optional separate developer diagnostic command under a namespaced name. Preserve normal MSTSC argument forwarding.

### 4.1 Persistent state

- `XDG_DATA_HOME/mstsc-wine/prefix`: dedicated persistent Wine prefix and registry.
- `XDG_CONFIG_HOME/mstsc-wine`: user configuration; do not conflate config with prefix.
- `XDG_STATE_HOME/mstsc-wine`: redacted logs and diagnostics.
- `XDG_CACHE_HOME/mstsc-wine`: disposable caches.
- Default XDG locations if env vars are absent. Never create or alter `~/.wine`.
- The launcher must not assume that `$HOME` or a writable current directory exists within the AppDir. It must handle spaces/unicode in paths and symlinks.
- Parallel launches must serialize first-run prefix migration/init to avoid half-initialized registry or conflicting file-copy operations. Subsequent MSTSC windows should normally share the dedicated prefix and its wineserver.
- Avoid copying the Windows components on every invocation. Detect component/runtime version and initialize or migrate once, using atomic markers and checksums. A future upgrade must not inadvertently erase saved MSTSC settings or credentials.
- For AppImage launches, resolve AppDir root from the AppImage entry environment or a robust `AppRun` launcher without assuming the mounted path is stable across launches.

### 4.2 Runtime isolation and environment sanitation

- Always invoke the private `wine`, `wineserver`, helper binaries and native dependencies using controlled paths; verify actual processes in tests.
- Set explicit `WINEPREFIX` and other relevant Wine environment variables only in a child scope; do not persist env changes into parent shells.
- Ignore or deliberately neutralize inherited `WINEPREFIX`, `WINELOADER`, `WINESERVER`, `WINEDLLPATH`, `WINEDLLOVERRIDES`, and other conflicting Wine settings. Retain only documented project-specific overrides for developers.
- Carefully control `PATH`, ELF RPATH/RUNPATH, linker search, `dlopen()` lookup, and private helper resolution; avoid accidental loading of system Wine/Samba/GnuTLS libraries. Do not globally override host process environments.
- Use verified `$ORIGIN`-relative linker paths or a scoped wrapper where appropriate. Do not indiscriminately bundle glibc, graphics-driver libraries, or low-level host-specific libraries.
- No host-global registry, `/etc/samba/smb.conf`, `/usr/bin/wine`, `/usr/bin/ntlm_auth`, `/usr/lib/wine`, service configuration, NSS/PAM configuration, or system trust-store modification.
- System Wine may be installed, uninstalled, different-versioned, or running concurrently without impacting MSTSC-Wine.

## 5. Native dependency and NTLM authentication closure

**Mandatory target:** NTLM and Kerberos logons must work on clean Debian 13 without installing Samba, Winbind, Wine, or an NTLM helper via `apt`. The application may consume documented foundational host facilities (kernel, compatible glibc, display server/compositor, drivers, DNS, audio integration and system trust store), but all application-specific helpers must be private.

### 5.1 Inspect before selecting an implementation

1. Locate the exact `ntlm_auth` invocation within the pinned/patched Wine source (executable lookup, arguments, helper protocol, environment, stdin/stdout interaction, error behavior).
2. Determine whether it uses the `ntlmssp-client-1` client protocol; test this helper mode without any `winbindd` service. Do not assume *every* Samba helper mode is daemon-independent. Samba documentation distinguishes client helper protocols from daemon-dependent server-side operations.
3. Measure the smallest correct Samba-derived dependency closure (`ntlm_auth`, required shared objects, dynamically loaded private modules, plugin search paths, configuration/data files). Prefer a narrowly built Samba helper from pinned source, preserving upstream licensing and security updates.
4. Bundle dependencies privately and prove the helper executes without host Samba packages or system Samba configuration. If `winbindd` is genuinely required for the chosen operation, pause and report alternatives; do not install or launch a host daemon as a hidden workaround.
5. Make Wine invoke the private helper deterministically. A narrowly scoped Wine source patch or explicit private lookup is acceptable; changing global `PATH` without verifying the invoked executable is not sufficient.
6. Preserve NTLMv2/NTLMSSP functionality and correct protection of plaintext credentials, challenge-response material, and session keys. Never log these values.

### 5.2 Other dependencies

- Build the patched GnuTLS from pinned, verified Debian source including current Debian security patches and the project's existing compatibility patch; verify each dependency and runtime loader path.
- Keep the GnuTLS certificate key-usage compatibility behavior narrowly scoped to the proven RDP interop case. Do not relax trust-chain, hostname, validity, or warning/approval behavior. Include security regression tests and note that the patch broadens acceptance of a particular invalid key-usage case.
- Inventory Kerberos/GSSAPI, libpulse/PipeWire, X11/XWayland, FreeType, Fontconfig and any delayed/dynamically loaded modules. Specify what remains host-provided and why.
- Use `readelf`, `objdump`, `ldd` in an appropriate controlled environment and runtime traces to verify actual resolution. Static analysis alone is insufficient because Wine and Samba load some components dynamically.
- Produce a machine-readable `dependency-manifest.json` with origin (source URL/revision/package version), license, hash, bundled/host classification, reason, and security update guidance.

## 6. Dockerized build design

- Create a pinned `docker/Dockerfile` based on a specified Debian 13 image digest; record the build image and build tool versions. Prefer a multistage builder if it genuinely simplifies artifact collection.
- Build all native components from pinned, integrity-verified source inputs. Reuse `tools/build-wine.sh`, `tools/build-gnutls.sh`, and `patches/series` rather than inventing a parallel patch system.
- Support parallel compilation (`JOBS`, sensible defaults), build caching and incremental developer rebuilds. Distinguish cached source/build outputs from immutable shipped binaries.
- Use an isolated writable output/build directory; do not write root-owned files into a developer's checkout when Docker is used.
- The Microsoft ZIP must **not** be sent in the Docker image build context or embedded in any reusable Docker image layer. Preferred approach: compile the open-source runtime in Docker, export to local staging, then validate and assemble Microsoft files on the host. If container-based assembly is necessary, use a read-only bind mount at run time and document cache/log hygiene.
- Never `COPY` the repository indiscriminately into a Docker image if private inputs might be present; use an explicit `.dockerignore`, predictable build context, and audited instructions.
- Docker must not be required to run the finished application. No X11 socket mounts, privileged containers, host networking or sound-device mounts are needed merely to compile.
- Support source-only offline/rebuild workflows when source tarballs and build images are pre-cached; do not promise fully offline first build.
- Build scripts must be resumable and provide precise error reporting when a source download, integrity check, patch application or compilation fails.

## 7. Portability and AppImage

1. Build and test the canonical AppDir first. It must run from at least two unrelated absolute paths, including one containing spaces, with the original repository unavailable.
2. Use an AppImage-compatible `AppRun` entry point and `.desktop` metadata; choose appropriate project-owned icon assets (do not redistribute Microsoft's proprietary artwork without permission).
3. Build AppImage locally via a pinned packaging tool. Do not publish the generated AppImage through the repository CI.
4. Test both an installed/extracted AppDir and the actual AppImage. Read-only mounted AppImage, no writable application directory, correct persistent XDG prefix.
5. Provide extraction/no-FUSE fallback instructions and ideally an alternative tarball for environments where AppImage execution is unavailable.
6. The glibc baseline is Debian 13; do not claim universal Linux portability. Avoid bundling host graphics drivers and glibc. Later experiments with older glibc and musl are out of scope unless requested.
7. Compare behavior on Cinnamon/X11 and KDE Plasma/Wayland via XWayland; native Wayland Wine is not required.
8. Determine AppImage packaging implications of host GSSAPI, display, audio, fontconfig and CA trust; document any unavoidable foundational host requirements explicitly.

## 8. Installation and upgrade contracts

- `make install` default: user-local installation under `~/.local/opt/mstsc-wine` with `~/.local/bin/mstsc` launcher or an equivalent documented XDG location. Never overwrite an existing unrelated executable without clear consent.
- Optional `PREFIX=/opt/mstsc-wine` or `DESTDIR=` for explicit system/packaging use; do not silently escalate privilege.
- Install one desktop entry under `${XDG_DATA_HOME:-$HOME/.local/share}/applications/` (or the corresponding system prefix for an explicit system install), application icons under the normal `hicolor` icon theme hierarchy, and the `mstsc` command. `make uninstall` uses an installation manifest and removes only owned files/links. Do not purge user prefix/config/logs without a separate explicit command.
- Set the desktop entry's visible `Name=Remote Desktop Connection` (not `MSTSC-Wine`), `GenericName=Remote Desktop Client`, `Type=Application`, appropriate `Categories` (such as `Network;RemoteAccess;` after validating against freedesktop categories), `Terminal=false`, and `Exec` targeting the **installed** app's launch path with proper freedesktop argument-field handling. Use a stable, namespaced desktop ID such as `org.mstscwine.RemoteDesktopConnection.desktop` to avoid collisions. Match `StartupWMClass` only if verified against the real Wine MSTSC windows; avoid duplicate taskbar icons.
- The preferred icon is the recognizable Microsoft Remote Desktop Connection icon, **generated locally during assembly** from the operator-supplied `mstsc.exe` or an appropriate matching resource. Extract embedded group-icon variants correctly, preserving transparency and rendering appropriate sizes (e.g. 16/32/48/64/128/256 px where available). If the supplied Microsoft components lack a usable icon, use a project-created redistributable fallback, not an unofficial downloaded icon. Never commit or publicly distribute the extracted Microsoft icon or derivatives where rights are absent. Include it only in the operator's locally generated artifact, subject to their license.
- A raw AppImage does not automatically register a menu item or shell command. Provide an explicit `mstsc --integrate` or an installer command such as `make install` / `scripts/install-appimage.sh` (choose a clear documented interface) that places or links the AppImage in a stable user-local application directory, creates/updates the `.desktop` file and icon, and installs a `~/.local/bin/mstsc` wrapper or symlink. Do not require AppImageLauncher or modify the shell's global startup files silently.
- Detect whether `~/.local/bin` is in the user's `PATH`; explain how to enable it if necessary. Never overwrite an existing unrelated `mstsc` binary, symlink, desktop entry, or icon without explicit approval. Installation must be idempotent, and uninstallation must remove only integration artifacts owned by this installation.
- The desktop entry and `mstsc` command must invoke the **same packaged runtime** and support the same command-line arguments; no distinct installed-system Wine invocation is permitted. Opening `.rdp` files by clicking them is a desirable optional MIME association, but must be opt-in if it changes the user's default RDP handler.
- Support running the portable AppImage without installation and without root.
- The launcher reports application version, Wine revision/patch hash, GnuTLS version, NTLM helper version, Microsoft component build and relevant runtime paths with `--version`/`doctor`; never reveal usernames, passwords or target server identities in shared diagnostics by default.
- Upgrades must be atomic enough to prevent half-replaced runtime trees; existing running processes should continue to reference their own runtime and not be corrupted by replacement.
- Prefix migration must be explicit, tested and reversible when incompatibility is possible. Use per-application locking. Do not require regeneration of a working prefix for every version.
- The binary named `mstsc` must pass MSTSC arguments verbatim, including `/v:host`, `/f`, and `.rdp` files (converting existing Linux paths when needed).

## 9. Acceptance tests (release gates)

Implement tests with clear PASS/FAIL/SKIP states and documented prerequisites. SKIP is never a PASS. Separate headless automated checks from end-to-end GUI/network checks requiring operator environments.

| ID | Mandatory proof |
|---|---|
| PKG-001 | A fresh Debian 13 source checkout plus authorized user ZIP can execute documented `make` and produce AppDir. |
| PKG-002 | The source-only repository and Docker build context contain no Microsoft binaries/ZIPs, credentials or production host secrets. |
| PKG-003 | Wine source is built from the pinned upstream revision with precisely the recorded ordered patch set. |
| PKG-004 | Patched GnuTLS is included and its intended DLL/load paths and certificate behavior are verified. |
| PKG-005 | Private `ntlm_auth` is invoked by Wine and works with **no host Samba/Winbind** installed or running. |
| PKG-006 | Host has system Wine/Samba (possibly incompatible versions) and concurrent Wine apps; MSTSC-Wine ignores and does not alter them. |
| PKG-007 | Launch succeeds even if inherited `WINEPREFIX`, Wine loader and DLL override variables reference unrelated installs. |
| PKG-008 | AppDir operates after relocation and after original repository/build directories become unavailable. |
| PKG-009 | AppDir operates from paths containing whitespace; relative `.rdp` filenames work. |
| PKG-010 | Actual AppImage launches with read-only payload and writes user state only under appropriate XDG locations. |
| PKG-011 | `.tar.zst` extract-and-run bundle works independently of AppImage tools and without preinstalled Wine. |
| PKG-012 | Private Microsoft components are verified against manifest and integrated into locally generated artifacts; corrupt/missing/inconsistent inputs fail clearly. |
| PKG-013 | No application runtime requires root privileges, Docker, a preinstalled `wine`, `ntlm_auth`, `winbindd`, or user configuration of Samba. |
| PKG-014 | Fresh prefix initializes exactly once and concurrent launches do not corrupt it. |
| PKG-015 | Standard MSTSC arguments, fullscreen, keyboard, audio, certificate warnings, NTLM and Kerberos login keep working. |
| PKG-016 | Clipboard text, pictures, and file transfer both directions retain the existing test coverage and live behavior. |
| PKG-017 | `make install` exposes `mstsc`; uninstall changes only owned application files and preserves user data. |
| PKG-018 | Build provenance, native dependencies, hashes, license notices and source-rebuild instructions accompany the artifact. |
| PKG-019 | Application remains operational with network disabled *after* launch for local diagnostics, except for actual RDP connections; no unexpected install-time network requests at runtime. |
| PKG-020 | Running `doctor` accurately distinguishes bundled, host-provided, missing and accidentally system-resolved components. |
| PKG-021 | `make install` creates an application menu entry visibly titled **Remote Desktop Connection** with the correctly rendered MSTSC icon (or documented fallback), including under Cinnamon and KDE Plasma. |
| PKG-022 | The installed application starts by selecting that menu entry, appears as one coherent taskbar/dock application, and uses the bundled runtime. |
| PKG-023 | From a fresh normal interactive terminal, `command -v mstsc` resolves the installed launcher and `mstsc /v:server01` runs the packaged Microsoft client. |
| PKG-024 | A portable AppImage remains independently executable without desktop integration; an explicit integration/unintegration command works without AppImageLauncher and is idempotent. |
| PKG-025 | Upgrading or uninstalling desktop integration preserves unrelated launcher/icon files, existing RDP defaults and application user data. |

Also add tests for: first-run dialog and COM registration, bad password reprompt, NLA-required host (if available), credential storage persistence, CA-trusted vs self-signed certificate behavior, multiple simultaneous sessions, graceful/nonzero child exit, and application update/migration. Preserve all existing regression fixtures and label any previously untested master-spec acceptance criteria honestly.

### 9.1 Clean test environment

- Provide a reproducible Debian 13 VM/test-host checklist. A container can test linker resolution and isolated CLI startup but is **not** a substitute for real graphical/display/authentication tests.
- Prove tests on a host where Wine/Samba/Winbind are absent, then separately on one where these are present.
- Execute actual AppImage/relocated AppDir against disposable Windows RDP endpoints provided by the operator; do not modify real production host authentication settings.
- Capture redacted logs and exact build/version identifiers with each result.

## 10. Licensing, provenance and release hygiene

- Project-owned launcher/build code can keep the repository's current MIT license. Wine patches remain Wine-derivative under LGPL 2.1-or-later as documented. Respect Samba, GnuTLS, and other third-party licenses in the private bundle and source build documentation.
- Document how the user can obtain/build corresponding source for the runtime that they generate. Provide license notices and patch/source versions in output. Avoid claiming that a privately built binary is exempt from licenses for its constituent components.
- The exporter must copy **only** the explicitly enumerated files needed for operation. There is no automatic sourcing from third-party download sites.
- The user is responsible for confirming that their Microsoft license allows extracting, running and incorporating those components into the locally generated artifact. The project cannot guarantee this, and Windows Server terms may restrict running constituent files in other operating systems.
- No public GitHub Actions artifact, release, container registry push, cached layer, or diagnostic attachment may contain Microsoft components. Source-only CI may compile/test open-source portions and use original, distributable test fixtures.
- Never store passwords, Kerberos tickets, credential-cache files, NTLM exchanges, server names or personal paths unredacted in public logs. Consider private GnuTLS's certificate-use exception a security-relevant deviation requiring continued tests and clear disclosure.

## 11. Implementation milestones and stop conditions

**P0 — Baseline:** Inventory current checkout and pass existing regression tests; record exact working versions, host dependencies, and operator-confirmed functionality. No refactoring before a checkpoint commit.

**P1 — Relocatability:** Refactor Wine configure/install and launcher paths; implement AppDir-local runtime lookup; demonstrate directory relocation with source tree hidden. Resolve any hardcoded paths with evidence, not speculative binary patching.

**P2 — Dependency closure:** Bundle patched GnuTLS and make native runtime dependencies deterministic. Integrate private Samba `ntlm_auth` and demonstrate client mode without host daemon; verify NTLM and Kerberos remain functional.

**P3 — User Microsoft input:** Implement PowerShell exporter, structured manifest, ZIP validation/import and local-only assembly. Update legal and Git hygiene documentation.

**P4 — Build reproducibility:** Dockerize Debian 13 build, pin source revisions/toolchains, cache safely, integrate Make targets and error reporting.

**P5 — Canonical AppDir:** Assemble complete read-only-safe runtime; implement first-run prefix init, runtime diagnostics, locks, versioning and full relocation tests.

**P6 — Deliverables:** Produce AppImage and `.tar.zst`; validate executable, desktops and clean-host portability. Add optional user install/uninstall.

**P7 — Quality and handoff:** Regression suite, real-host user testing, security/license audit, documentation, source-only CI, final operator-facing quick start.

At every milestone: update `docs/STATUS.md` and `docs/COMPATIBILITY.md`, add ADRs for material design decisions, run relevant tests, and commit a stable checkpoint. Preserve working behavior ahead of optimizing package size or aesthetics. If a phase is blocked, publish an evidence-backed finding and continue with independent work when possible; do not silently reduce a mandatory gate. Ask the operator before any step requiring access to actual proprietary files, external RDP hosts, or security-sensitive credentials that are unavailable.

## 12. Recommended initial agent execution sequence

1. Summarize the current checkout and differences from the snapshot findings (§2).
2. Run or report the existing baseline test suite without changing behavior.
3. Inspect `tools/build-wine.sh`, `tools/build-gnutls.sh`, `launcher/mstsc-wine`, and Wine's `ntlm_auth` invocation to determine the minimum safe refactor.
4. Write concise ADRs for **canonical AppDir, native dependency policy, private NTLM helper, build inputs and component-import pipeline**.
5. Implement P1 relocatability first with a direct runnable AppDir (not AppImage), then P2 private dependencies. Keep the current development launcher working throughout.
6. Implement extraction/validation/build automation and only then the AppImage wrapper.
7. Run the release gates and report what is verified, still skipped, and blocked.

**Success means:** a user on supported Debian 13 can provide their own authorized Windows component ZIP, compile the patched runtime with `make`, produce one locally assembled portable AppImage, copy it to another suitable Debian 13 desktop with no system Wine/Samba installation, and run **the genuine Microsoft MSTSC client** with functioning NTLM, Kerberos, display, audio and clipboard integration. The private runtime must neither depend on nor alter unrelated Wine/Samba installations.

