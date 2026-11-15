# MSTSC-Wine — Master Development Specification

**Specification version:** 1.0  
**Date:** 2026-10-27  
**Project:** `mstsc-wine`  
**Status:** Research and implementation specification; feasibility unproven  
**Primary implementation target:** Debian 13 (Trixie), x86-64  
**Primary application:** Genuine Microsoft Remote Desktop Connection (`mstsc.exe`)  
**Phase 2 candidate:** Sysinternals Remote Desktop Connection Manager (RDCMan) 3.22

## 0. Instructions to the coding agent

This document is the authoritative scope and acceptance specification. Implement incrementally, collecting executable evidence for each milestone. Do not replace the target with a FreeRDP-based clone, substitute a Windows VM, or declare success based merely on launching a GUI. Never silently weaken an acceptance criterion to work around an incompatibility. When a blocker is encountered, record a reproducible test, diagnostics, hypothesis, attempted fixes, and the next experimental step. Distinguish **verified behavior**, **inference**, and **untested hypothesis** in all technical documentation.

The agent is authorized to build original launchers, integration components, tests, Wine patches, and packaging scripts. It is **not** authorized to download arbitrary third-party copies of Microsoft binaries, obtain credentials, alter remote host security settings, bypass licensing/activation, or publish proprietary Microsoft DLLs. Microsoft files must be furnished from a legitimate source by the operator, stored outside the public repository, and validated by manifest and hash. Review applicable Microsoft terms before use and redistribution. Never put credentials or actual production hostnames into test fixtures or logs.

The source-first Wine approach is required for engineering and eventual packaging, but **an unmodified upstream Wine build is the baseline**. No Wine source patch is permitted until an observed issue has a minimal reproduction and a reasoned root-cause hypothesis. Prefer an upstream-compatible correct fix over application-name special cases; application-specific shims may be used when justified and isolated.

## 1. Product vision and non-goals

### 1.1 Product vision

Provide a Linux-native-feeling command named `mstsc` that launches Microsoft's real Windows RDP client via an isolated, purpose-built Wine runtime. A user should be able to open an app launcher, type “Remote Desktop Connection” or `mstsc`, enter a server, authenticate securely, and work in a responsive remote desktop without configuring codec flags, clipboard mappings, screen resolutions, or Linux-specific RDP settings.

The system must work on conventional Debian desktops such as KDE Plasma/Wayland, Cinnamon/X11, and Xfce/X11 without hard dependencies on one desktop environment. The project may employ XWayland initially; native Wine Wayland is a later enhancement if functionally superior.

### 1.2 The software being executed

The principal executable is the genuine Microsoft `mstsc.exe` and its matching Microsoft RDP client components (notably `mstscax.dll` where applicable). Wine implements the supporting Windows application APIs. The actual RDP session must be negotiated and transported by Microsoft's components. Using FreeRDP as the backend while copying the MSTSC interface does **not** satisfy the goal.

### 1.3 Phase 1 success definition

Phase 1 succeeds only when the release candidate passes every **P0** acceptance test in §7 on the primary Linux configuration, plus the portable baseline suite on at least one secondary desktop environment. P1 usability features must be resolved or explicitly documented as tolerable deviations; any deviation that routinely interrupts the described everyday workflow is effectively P0.

### 1.4 Explicit non-goals for Phase 1

- Running arbitrary Windows software through the bundled Wine runtime.
- Windows desktop/server virtualization, WinApps, VM-based RDP wrappers, or remote access via FreeRDP.
- Reimplementing the RDP protocol stack.
- Bundling or distributing Microsoft Windows system binaries without appropriate authorization.
- Microsoft Entra ID/AVD/Windows 365 workflows unless later added as independently specified requirements.
- RemoteApp support unless it comes for free and remains stable.
- Drive/folder redirection, printer redirection, smart-card redirection, USB redirection, webcam redirection, and microphone redirection as release gates.
- Full compatibility across all Linux distributions, CPU architectures, desktop environments, and Wine versions.
- RDCMan support in the Phase 1 release.

## 2. Scope and priority vocabulary

- **P0 / required:** Mandatory for declaring Phase 1 complete.
- **P1 / desired:** Strongly preferred; may ship with documented limitations only if the total user experience remains genuinely comfortable.
- **P2 / optional:** Bonus integration, never a Phase 1 release blocker.
- **P3 / future:** Phase 2 or later.

### 2.1 Functional requirements

| ID | Priority | Requirement |
|---|---|---|
| F-001 | P0 | Run genuine Microsoft `mstsc.exe` with the genuine Microsoft RDP protocol implementation under the dedicated Wine runtime. |
| F-002 | P0 | Show a working connection dialog, accept hostnames/IPs/ports and invoke `.rdp` files. |
| F-003 | P0 | Establish encrypted, authenticated connections to supported Windows 10/11 and Windows Server targets using commonplace NLA/CredSSP configurations. |
| F-004 | P0 | Correctly show server identity/certificate prompts; never globally disable verification or suppress warnings without deliberate user choice. |
| F-005 | P0 | Enter and leave fullscreen cleanly, render without persistent corruption, recover after reconnect, and keep mouse input correctly mapped. |
| F-006 | P0 | Deliver ordinary text clipboard exchange both directions reliably, including UTF-8/Unicode and multiline text. |
| F-007 | P0 | Copy and paste files **both directions** between local Linux file managers and remote Windows Explorer, including normal files, multiple selections, and directories where supported by the Microsoft client. |
| F-008 | P0 | Exchange clipboard text and files between **two simultaneously open RDP sessions** through the local clipboard without corruption or deadlocks. |
| F-009 | P0 | Play remote desktop audio through the local desktop sound service. |
| F-010 | P0 | Preserve correct keyboard semantics for normal typing, modifiers, common shortcuts, and remote Windows key usage in fullscreen, subject to documented compositor-reserved shortcuts. |
| F-011 | P0 | Support the host’s normal DPI/fractional scaling, including 125% on the Framework 13, without unacceptable blurring, cursor offset, or clipping. |
| F-012 | P0 | Start from a normal app launcher or terminal command, present normal task-switcher entries, and close without leaving stray Wine windows/processes indefinitely. |
| F-013 | P0 | Clean user-profile isolation: no pollution of unrelated Wine installations or system Wine DLL preferences. |
| F-014 | P0 | Automated, noninteractive setup on a fresh supported Debian 13 system after operator supplies Microsoft binaries. |
| F-015 | P0 | Security-sensitive prompts remain visible and accessible; credential material never appears in logs, environment dumps, or generated crash reports. |
| F-016 | P1 | Preserve MSTSC’s familiar prompt-first, connect-second flow; allow saved `.rdp` settings and automatic/recommended connection settings. |
| F-017 | P1 | Connection bar, focus changes, alt-tab behavior, task switching, minimizing, and resuming feel predictable. |
| F-018 | P1 | Restore sessions following expected transient network interruptions, consistent with the client’s native capabilities. |
| F-019 | P1 | Clipboard interoperability with GTK and Qt text editors, terminals, file managers and browsers. |
| F-020 | P1 | Native Wayland backend where it demonstrably improves experience over XWayland; no forced migration if it regresses functionality. |
| F-021 | P1 | Desktop integration and setup that are independent of the selected window manager or desktop environment. |
| F-022 | P2 | Optional local folder and drive redirection, including Linux path mapping. |
| F-023 | P2 | Optional CUPS-backed printer redirection. |
| F-024 | P2 | Optional PC/SC smart-card redirection. |
| F-025 | P2 | Additional peripheral, USB, microphone, and camera redirection. |
| F-026 | P3 | RDCMan 3.22, including its `-mstsc` legacy-engine mode and independent investigation of its newer rendering engine. |

### 2.2 Nonfunctional requirements

| ID | Priority | Requirement |
|---|---|---|
| N-001 | P0 | Reproducible source checkout, pinned upstream Wine commit/tag, recorded toolchain dependencies, lockable build inputs, and documented hashes of operator-supplied Microsoft components. |
| N-002 | P0 | Application-specific fixes have automated regression tests; each patch has rationale, scope, expected effect, test evidence, and upstreamability assessment. |
| N-003 | P0 | No unexpected root privileges, `sudo` runtime requirement, host-global DLL replacement, or mutation of system Wine installations. |
| N-004 | P0 | No embedded credentials or hard-coded target IPs; protect secrets and redact diagnostics by default. |
| N-005 | P0 | Clear startup/connection failure diagnostics without requiring users to parse raw Wine traces. |
| N-006 | P1 | Day-to-day startup and interaction are subjectively comparable to native MSTSC; capture quantitative latency and resource-use measurements for regressions. |
| N-007 | P1 | Resource overhead remains proportionate to a single remote client; no additional permanently running daemon unless empirically necessary. |
| N-008 | P1 | Reinstallation, cleanup, and rollback are reliable and do not damage unrelated home-directory state. |
| N-009 | P1 | Runtime and Microsoft component update strategy preserves known-good versions and regression test results. |
| N-010 | P2 | Packaging for other Debian-derived systems, signed releases, reproducible binary builds, and wider desktop test matrix. |

## 3. Baselines and platform matrix

### 3.1 Primary test machine

- Debian 13 Trixie, x86-64, fully updated.
- KDE Plasma 6.3 Wayland on the Framework 13 (11th-gen Intel); 125% scaling.
- Test XWayland-backed Wine before native Wayland Wine, unless initial evidence strongly supports the opposite.
- PipeWire/PulseAudio compatibility as provided by Debian's supported audio stack.
- Native Linux file manager Dolphin and a GTK file manager (e.g. Nemo/Thunar) for clipboard interoperability.

### 3.2 Secondary environments

1. LMDE/Cinnamon on X11 (or Cinnamon Wayland experimental session as a separate non-gating experiment).
2. Debian 13/Xfce on X11.
3. Optional KDE Plasma X11 to differentiate compositor from XWayland/Wayland differences.

### 3.3 Microsoft client candidates

- First candidate: **Windows 10 22H2 x64** `mstsc.exe` plus all matching required components.
- Second candidate: Windows 11 (24H2/25H2 or appropriately identified later release).
- Optional diagnostic control: Windows 7 SP1 RDP 8.1 client to establish whether older component assumptions work.

Do not mix `mstsc.exe`, `mstscax.dll`, and satellite binaries across Windows builds unless a dedicated experiment validates such a combination. Record product/build version, architecture, source OS, original path, signature metadata, and SHA-256 for every imported file. Architecture and dependency sets are **to be discovered**, not guessed.

### 3.4 Remote RDP test endpoints

- Windows 11 Pro or equivalent modern client OS with RDP enabled.
- Windows Server 2025 and optionally Server 2022.
- A disposable test endpoint with local user credentials; use a separate domain/NLA test when available.
- A reference Windows client machine running exactly the same Microsoft component set to establish expected behavior.

Never change production host security settings merely to make the test client connect. Use test machines and record the security configuration.

## 4. Proposed architecture

### 4.1 Components

1. **Linux launcher (`mstsc`):** Resolve runtime location, initialize or validate dedicated prefix, select X11/XWayland/native Wayland backend, safely pass arguments, show actionable errors, and launch the actual Microsoft executable. Do not implement RDP transport.
2. **Pinned Wine build:** Upstream Wine checkout plus small tracked patch series. Development builds retain symbols and traceability; production builds contain only validated required components.
3. **Wine prefix manager:** Deterministically create/update a per-application prefix; install and register Microsoft components when explicitly supplied; configure DLL loading and environment isolation.
4. **Microsoft binary store:** User-controlled non-repository storage of signed files; versioned manifests and hashes; no redistributable proprietary payloads in source control.
5. **Integration adapters:** Use Wine/platform APIs first; isolate any Linux-specific clipboard, input, scale, file transfer, audio, printer or smartcard work behind narrow, testable interfaces. Avoid DE-name branching unless a specific observed compositor quirk demands it.
6. **Diagnostics:** Structured events and opt-in Wine traces with automatic redaction; fixture-based reproduction reports.
7. **Test harness:** Host-side process checks, reference Windows comparisons, RDP endpoint automation and manual visual/interactive acceptance scripts.

### 4.2 Display backends

- Baseline: Wine's X11 backend on X11 and XWayland.
- Follow-on: native Wine Wayland backend if viable.
- Never assume X11 behavior describes Wayland compositor policies. Track KWin/Muffin/Xfwm4, selected session protocol, scaling factor, Wine backend, monitor topology, and screen resolution in test results.
- Some global shortcuts are compositor-reserved under Wayland; attempt standards-based shortcuts inhibition where available, but do not require invasive compositor patches for Phase 1.

### 4.3 Native DLL override policy

- Allow native overrides only from a validated component set matched to the selected client version.
- Start with Microsoft's own application and RDP DLLs; retain Wine `ntdll`, core Win32, graphics and host integration layers unless evidence supports a different boundary.
- Every native override is declaratively documented and individually togglable for A/B tests.
- A failed override experiment is removed; never accumulate speculative DLL replacements.
- Keep license-constrained assets out of Git, published packages, sample CI artifacts, and issue reports.

### 4.4 Repository structure

```text
mstsc-wine/
  README.md
  SPEC.md                         # authoritative copy of this document
  AGENTS.md                       # coding-agent workflow contract
  .gitignore
  wine/                           # pinned upstream submodule OR tracked fork
  patches/                        # ordered patch set and manifest
  launcher/                       # Linux entrypoint and runtime logic
  runtime/                        # prefix templates, DLL policy, manifests
  packaging/                      # install/uninstall, desktop integration
  tools/                          # dependency analysis, reproducible builds
  tests/
    static/
    launch/
    connection/
    clipboard/
    display/
    audio/
    security/
    portability/
    manual/
  docs/
    architecture.md
    setup.md
    diagnostics.md
    binary-acquisition.md
    compatibility-matrix.md
    decisions/
    experiments/
    troubleshooting.md
  artifacts/                      # ignored logs, traces, reports
```

Do not vendor the entire Wine Git history inside the project's own tracked files. Prefer a pinned Git submodule or maintained fork and patch series. Keep temporary build objects separate from source. Do not use the ordinary `~/.wine` prefix.

## 5. Engineering and research protocol

### 5.1 Mandatory order of operations

1. Inventory available Linux toolchain, graphics stack, Wine support, test hosts, and legitimately provided client binaries.
2. Record hashes and static dependencies (PE import tables, architecture, resources, COM registration needs, manifest, MUI satellite files, indirect/delay-loaded modules).
3. Build **unmodified upstream Wine** from an identified stable tag/commit in a separate build directory.
4. Create a private prefix and attempt startup with minimal overrides.
5. Capture diagnostics: stage, symptom, exception, missing module/import/COM class, call stack, Wine debug categories, environment metadata.
6. Compare with matching client on native Windows and isolate the first causative divergence.
7. Create the smallest reproduction (ideally a tiny Windows test program/API probe) before editing Wine.
8. Patch, add regression test, compare before/after, verify unrelated basic Wine behavior.
9. Move to subsequent functionality in priority order; do not spend weeks packaging a client that cannot connect.

### 5.2 Diagnostic discipline

- Start with targeted `WINEDEBUG` channels (`+loaddll`, `+module`, `+ole`, `+seh`, etc.); escalate to selective `+relay` tracing only when necessary because traces are enormous and can expose sensitive arguments.
- Treat `fixme` messages as diagnostic leads, not proof of causality.
- Use Wine source-level debugging (`gdb`/symbols), `strace`, PE dependency tools and COM activation traces as appropriate.
- Perform differential testing between Wine versions and known-good Windows configurations.
- Test new patches with a fresh prefix as well as an upgraded persistent prefix.
- Keep a machine-readable experiment record: `ID`, date, host, Wine commit, client manifest, environment, hypothesis, steps, expected, observed, logs, conclusion and follow-up.
- Record the first reproducible failure, not merely the last cascading error.

### 5.3 Decision records

Every architectural change must record: alternatives considered, evidence, portability implications, attack surface, maintenance costs, rollback, and whether it could be submitted upstream to Wine. Third-party Wine patchsets are allowed only when their exact provenance and dependencies are recorded.

## 6. Development milestones and execution plan

| Milestone | Deliverable | Exit gate |
|---|---|---|
| M0 — Research inventory | Source/dependency manifest, source acquisition policy, test matrix, threat model | Exact target executable set and test host identified; no unknown proprietary file origins |
| M1 — Build foundation | Pinned, unmodified debug Wine build; launcher prototype; isolated prefix | Repeatably builds/starts simple Wine test app on Debian 13 |
| M2 — Genuine MSTSC launch | Actual connection dialog and argument parsing; startup dependency report | No unhandled startup errors; `mstsc.exe` UI functional without FreeRDP |
| M3 — First genuine connection | NLA/TLS negotiation, credentials, desktop rendering, clean disconnection | Actual encrypted RDP connection to test Windows host, confirmed server-side |
| M4 — Core usability | Fullscreen/windowed behavior, keyboard, dynamic scaling, rendering, audio | Relevant P0 display/input/audio tests pass on primary desktop |
| M5 — Clipboard interoperability | Text and file clipboard in both directions, Linux and Windows formats | All P0 clipboard tests pass, including simultaneous RDP sessions |
| M6 — Desktop integration | Launcher, MIME association, default behavior, diagnostics | Normal user can launch, connect and work without manual Wine steps |
| M7 — Portability and packaging | Scripted setup, regression suite, release artifacts sans proprietary binaries | Fresh Debian 13 install plus secondary DE passes acceptance suite |
| M8 — Stabilization | Known-good version matrix, rollback docs, security review, final manual | P0 gate complete; no critical defects or unexplained regressions |

Milestones M2 and M3 are **feasibility gates**. If blocked, do not silently pivot to FreeRDP; issue a clear technical blocker report with evidence and costed alternatives. Do not claim the product succeeded before M8.

### 6.1 Implementation order inside M4/M5

1. Keyboard/mouse mapping and fullscreen.
2. Display size, 125% scaling and connection resize behavior.
3. Audio output.
4. Bidirectional text clipboard.
5. Linux-to-Windows file clipboard.
6. Windows-to-Linux file clipboard.
7. Two-session remote-to-remote clipboard exchange.
8. Reconnection and mixed long-running workload stability.

Note: File clipboard integration is **mandatory**, even though mapped folder/drive redirection is not. If file clipboard transfer proves technically dependent on another subsystem, implement the minimum internally required pieces without exposing generalized folder redirection as a requirement.

## 7. Release acceptance tests

Automated tests should exercise behavior where practical; human-observed checks are permitted for UI fidelity, audio perception, and desktop interaction. All manual tests have scripted steps and preserved results, not an informal “looks fine.”

### 7.1 Required P0 test cases

| Test ID | Test | Pass criteria |
|---|---|---|
| T-001 | Launch from terminal and application launcher | The genuine MSTSC dialog appears promptly; no interactive Wine setup prompts after initial installation |
| T-002 | Direct host connection | Connect to a valid Windows host using hostname and IP; default NLA succeeds, authentication UI behaves correctly |
| T-003 | `.rdp` invocation | Open saved `.rdp` file through terminal and file manager; selected settings are honored |
| T-004 | Invalid endpoint | Display actionable timeout/host-resolution errors; no hang, crash, or silent bypass of security |
| T-005 | Certificate/identity mismatch | Warning remains visible, accurate, and user-controllable; never auto-accept insecure identity |
| T-006 | Fullscreen | Enter/exit fullscreen repeatedly, move mouse to edges, minimize, restore; correct focus and coordinates |
| T-007 | Local vs remote shortcuts | Verify Windows key, Ctrl+Esc, Alt+Tab, Ctrl+C/V, Ctrl+Alt+End and ordinary modifiers under documented modes; no stuck keys |
| T-008 | 125% scaling | On Framework at native panel resolution and 125%, text/UI are readable; no misaligned clicks, cut-off UI, or persistent blur beyond native-reference tolerance |
| T-009 | Display changes | Resize window/reconnect or dynamic-adjust where MSTSC supports it; no unusable blank/corrupt output |
| T-010 | Text clipboard | Paste ASCII, non-ASCII Unicode, multiline code and large text in both directions; content exact |
| T-011 | File clipboard local→remote | Copy/paste file and multi-file selection from Dolphin/Nemo/Thunar to Windows Explorer; hashes match |
| T-012 | File clipboard remote→local | Copy/paste file and multi-file selection from Windows Explorer into Linux file manager; hashes match |
| T-013 | Directory clipboard | Copy directory trees (nested + empty dirs + Unicode filenames) in both directions wherever native MSTSC supports them; compare manifest and file hashes |
| T-014 | Remote A→Remote B clipboard | Open two real Microsoft MSTSC sessions and transfer text and files between them via local clipboard; hashes match, no deadlock |
| T-015 | Audio output | Play reference speech/audio on remote host; audible on Linux output with correct start/stop and no runaway process |
| T-016 | Transient network interruption | Briefly interrupt test network; recover or reconnect using standard MSTSC semantics without application crash or corrupted state |
| T-017 | Session lifecycle | Close remote session and application repeatedly; no lingering windows, unmanaged processes, or leaked temporary files beyond documented tolerances |
| T-018 | Security/privacy | No passwords, tokens, session secrets or private keys in normal logs, launcher arguments stored in history, generated manifests or published artifacts |
| T-019 | Reproducible installation | New Debian 13 image, clean user account, supplied Microsoft artifacts, one documented install command → working app without manual DLL registration |
| T-020 | Secondary DE | Run connection, fullscreen, keyboard, text clipboard, file clipboard and audio smoke suite in Cinnamon/X11 or Xfce/X11 |
| T-021 | No hidden FreeRDP backend | Process/module inventory and connection traces confirm RDP session transport is from Microsoft components; FreeRDP is neither executed nor linked as protocol implementation |

### 7.2 Stability soak test

- Keep two connected sessions open for at least four continuous hours, exercising typing, scrolling, window manipulation, copying text and files, local focus switching, and audio at intervals.
- No crashes, deadlocks, runaway CPU/memory, permanently broken clipboard, unusable input state, or persistent image corruption.
- Record RAM, CPU, startup time, reconnect count and exception/crash count; compare to native Windows reference as context rather than imposing arbitrary resource thresholds before baselines exist.

### 7.3 Optional P2 tests

- Local-directory drive mapping, read/write access and path sanitation.
- Printing a test document through a locally attached or CUPS printer.
- Smart-card device discovery, authentication and hotplug behavior.
- Any additional peripheral redirection: separate feature-specific tests.

Failure of P2 tests does not prevent a Phase 1 release. P0 file clipboard behavior **must not** be reclassified as optional drive redirection.

## 8. Security and privacy requirements

- Use a dedicated Wine prefix with normal user permissions. Prefix is not a sandbox or hardened security boundary; document that Wine processes can access host files and network as the user.
- Use a narrowly scoped configuration and never request root at runtime. Installation may require packages installed by the administrator.
- Never automatically downgrade TLS/NLA, trust arbitrary certificates, disable endpoint identity checks or instruct the user to disable Windows host security.
- Do not store RDP passwords in plaintext configuration or expose them through command-line flags, environment variables, traces, crashes or CI. Support normal interactive Microsoft credential handling first.
- If secure credential persistence is implemented, use a documented Linux secret service / keyring approach only after threat-model review. Never create custom cryptographic storage.
- Redact usernames, IPs, hostnames, paths, clipboard contents and authentication payloads in issue-ready diagnostics. Offer opt-in raw tracing with explicit warnings.
- No telemetry by default. Do not phone home or automatically download Microsoft components.
- Protect update integrity: pin source commits, check signatures/checksums when available, and fail closed on manifest mismatches.
- Review packaging and use rights for proprietary binaries separately from the open-source Wine-derived runtime.

## 9. Packaging, installation and upgrade requirements

### 9.1 User experience

The end user should be able to perform an initial setup using one documented command after installing required Debian prerequisites and supplying approved Microsoft components. Subsequent launches must be as simple as `mstsc`, an application-menu click, or opening an `.rdp` file.

### 9.2 Required package behavior

- Keep runtime binaries, per-user configuration, component manifests, and cache separate using sensible filesystem paths (XDG where appropriate).
- Store only settings/data needing persistence in the prefix; use deterministic bootstrap for rest.
- Ship `.desktop` integration and RDP MIME association; use `Exec=` quoting safe for paths with spaces and malicious-looking filenames.
- Version runtime and Microsoft component sets independently, with compatibility validation.
- Provide `mstsc-wine doctor` for environment checks and `mstsc-wine --version` for full manifest reporting without secrets.
- Offer launch modes `--backend=auto|x11|wayland` when both backends are supported and keep overrides local to the process.
- Support export/import of non-sensitive configuration and uninstallation preserving user-owned `.rdp` files.
- Maintain previous known-good runtime for rollback; prefix migrations require backup or equivalent recovery.
- The proprietary component acquisition step is operator-directed, not built into open-source package downloads.

### 9.3 Versioning

Version the project using Semantic Versioning after the first release. Before 1.0, milestone tags may be `0.x`. Record exact `WineRevision`, `MicrosoftClientBuild`, `RuntimePatchSet`, `HostOS`, `DisplayBackend`, and `PackageRevision`. Unknown/unsupported combinations should warn without silently switching engines.

## 10. CI and reproducibility

- CI on Linux may compile all open-source code, run formatting/static analysis, basic Wine smoke tests with redistributable fixtures, and validate package assembly **without Microsoft binaries**.
- Full MSTSC integration tests run only on operator-managed runners with appropriately provided Microsoft components and isolated Windows RDP test targets.
- Publish test reports, not client binaries, credentials, registry secrets or complete raw traces.
- Require a clean-build test of pinned Wine source and deterministic application packaging.
- Run patch-level regression tests in every candidate; maintain a red/green matrix of known client build × Wine commit × backend × DE.
- Use timeout guards and process cleanup for headless test automation; repeated test failures must not leave remote sessions or hung Wine processes indefinitely.

## 11. Defect management and go/no-go rules

Each blocker gets severity (`blocking`, `degraded`, `optional`), affected features, reproducibility, evidence, ownership, and estimated effort. Clearly distinguish missing upstream Wine functionality, a mistaken prefix setup, undocumented Microsoft client behavior, and a compositor limitation.

**Stop-and-report conditions:**

- M2 cannot load genuine client components due to broad unsupported Windows subsystems after a bounded feasibility investigation.
- M3 cannot establish a genuine Microsoft-backed encrypted RDP session.
- A P0 feature fundamentally depends on a Windows kernel service that cannot be emulated within the reasonable compatibility scope.
- Client operation requires insecure defaults (e.g., mandatory verification bypass) or an unacceptable proprietary distribution model.
- Engineering progress depends on access to assets or credentials not explicitly furnished by the operator.

Never declare success or substitute FreeRDP under these conditions. Write a feasibility report with evidence and next choices. If only a narrow set of P0 behaviors remains broken, document them and continue targeted work; do not downgrade their priority without explicit operator approval.

## 12. Phase 2: RDCMan 3.22 (not Phase 1 acceptance)

RDCMan 3.22 is a future supported application using the same Wine runtime where possible. The phase begins **after** MSTSC 1.0 acceptance, except for inexpensive read-only binary reconnaissance.

Initial tasks:

1. Inspect 3.22 binaries, runtime dependencies, UI technology, COM use, graphics engines and credential storage.
2. Test `RDCMan.exe -mstsc` as the likely compatibility bridge to the traditional Microsoft engine; confirm actual module loading rather than assuming it.
3. Test normal `RDCMan.exe` newer engine separately; do not conflate the two implementations.
4. Support `.rdg` files, connection trees, grouped sessions, embedded session display, credential profiles, clipboard and window focus.
5. Use separate prefixes initially if needed; share a common patched runtime and regression infrastructure.
6. Back up existing `.rdg` files before testing version migration; newer RDCMan file formats may not be backward compatible.

RDCMan 3.22 must not block, delay, or redefine MSTSC Phase 1 success.

## 13. First coding-agent work order

Begin **only** with M0 and M1, then report before attempting invasive fixes:

1. Inspect Debian 13 environment, toolchain, display session, Wine state, available RDP test hosts and operator-supplied Microsoft binary bundle.
2. Create repository structure, `AGENTS.md`, architecture decision log, and minimal README with explicit assumptions.
3. Establish official Wine Git upstream and pin a baseline (Wine 11.0 stable is one candidate; choose and document actual selected commit).
4. Set up out-of-tree debug build and demonstrate it runs a redistributable benign Windows test program in a fresh isolated prefix.
5. Implement component-manifest inspector reporting SHA-256, file version, architecture, imports and required associated resources without copying the binaries to tracked files.
6. Build a minimal launcher that runs a supplied executable in a private prefix with deterministic logging.
7. Produce an `M0-M1-REPORT.md` listing what is verified, the exact remaining inputs needed, and the next M2 launch command.

Once M0/M1 is reviewed, proceed autonomously milestone by milestone within the approved development environment. Never claim an untested compatibility feature works. Every milestone concludes with running tests, updated evidence and a concise handoff.

## 14. Source references and evidence status

The specification deliberately does not presume that modern MSTSC is Wine-compatible. The following primary references guide implementation; technical claims must be independently verified against pinned versions:

- WineHQ source: <https://gitlab.winehq.org/wine/wine>
- Wine 11.0 release announcement: <https://www.winehq.org/news/2026011301>
- WineHQ bug 52215 (historical MSTSC/MUI behavior): <https://bugs.winehq.org/show_bug.cgi?id=52215>
- WineHQ bug 25343 (historical RDP 7 client behavior): <https://bugs.winehq.org/show_bug.cgi?id=25343>
- Microsoft `mstsc` command documentation: <https://learn.microsoft.com/windows-server/administration/windows-commands/mstsc>
- Microsoft RDP client ActiveX classes: <https://learn.microsoft.com/en-us/windows/win32/termserv/remote-desktop-activex-control-classes>
- Microsoft `MsTscAx` control: <https://learn.microsoft.com/en-us/windows/win32/termserv/mstscax>
- Microsoft RDP clipboard protocol documentation: <https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdsod/e4c9d4d6-c025-497d-9981-ece9848fa91e>
- Microsoft RDP resource redirection: <https://learn.microsoft.com/en-us/azure/virtual-desktop/redirection-remote-desktop-protocol>
- RDCMan: <https://learn.microsoft.com/en-us/sysinternals/downloads/rdcman>
- RDCMan newer/legacy engine discussion: <https://learn.microsoft.com/en-nz/answers/questions/5985091/rdcman-v3-21-remote-desktop-connection-manager-bug>

**Known unknowns requiring experimentation:** exact modern MSTSC dependency closure; Wine COM/RDP component initialization; genuine transport setup under Wine; clipboard file-transfer semantics across Wine and X11/Wayland; Microsoft audio device integration; latest-client authentication dependencies; feasibility of seamless Wayland keyboard capture; exact licensing boundaries for the operator's intended installation.

---

**Definition of done:** A user on Debian 13 launches the genuine Microsoft `mstsc.exe` as a normal desktop application, connects securely to Windows machines, operates fullscreen with readable 125% scaling and reliable keyboard/mouse/audio, copies text and files between Linux and Windows and between two RDP sessions, and can reproduce the setup on a clean installation without special manual intervention. Folder/drive, printer and smart-card redirection are optional. RDCMan is Phase 2.
