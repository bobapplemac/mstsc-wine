# Project status

_Last updated: 2026-11-19_

## Current milestone: M3 (first connection): **first interactive session achieved** (2026-11-14)
## Packaging (docs/MSTSC-Wine-Packaging-Implementation-Spec.md v1.1): P0–P6 implemented (2026-11-15)

| Packaging milestone | State |
|---|---|
| P0 baseline | **done**: both regression runs and the launch tests pass at `835c919` (EXP-056) |
| P1 relocatability | **done**: Wine is relocatable as built (R-027); neutral-prefix `dist` build; launcher finds the AppDir from its own location; runs from paths with spaces/`Ä`, read-only, source tree hidden (EXP-057) |
| P2 dependency closure | **done**: patched GnuTLS, MIT Kerberos, libunwind and Samba `ntlm_auth` (86 libraries) bundled from pinned, hash-checked Debian 13 inputs; patch 0039 `WINENTLMAUTH` (ADR-0042, ADR-0044); NTLM CredSSP verified offline with host Samba hidden (PKG-005) |
| P3 Microsoft input | **done**: `windows/Export-MstscComponents.ps1` (first successful run on Windows reported by the operator, EXP-063), `tools/mscomponents.py` verify/extract/from-dir/icon, policy file, Git hygiene (ADR-0046) |
| P4 reproducible build | **done**: pinned Debian 13 Docker image (digest + snapshot.debian.org), native engine, `Makefile` (ADR-0045); Docker and native builds produce the same Wine source tree and library set |
| P5 canonical AppDir | **done**: `tools/assemble-appdir.sh`, first-run prefix set-up under a lock with state marker and registry backups, `doctor`, metadata (ADR-0043) |
| P6 deliverables | **done**: AppImage (100 MB), `.tar.zst` (65 MB), install/uninstall/`--integrate` with manifest (ADR-0047); `make` builds the AppImage and `make install` installs it, `make install-appdir` for development (ADR-0049) |
| P7 quality and handoff | **in progress**: release gates 25/0/4 (`tests/portability/run.sh`); exporter verified on Server 2022 (EXP-063); **fresh Debian 13 KDE Plasma (X11) machine: built from a fresh clone and runs (EXP-064)**; updated there with `make install` (AppImage install) and NLA certificate warning confirmed (EXP-068). Open: KDE Plasma on Wayland, and a recorded checklist of live-host checks from the package (docs/PACKAGING.md §8) |

| Milestone | State |
|---|---|
| M0 research inventory | **done**: binaries inspected and hashed, dependency closure analysed, required satellites identified |
| M1 build foundation | **done**: pinned Wine 11.0 builds from source, both unmodified and patched; launcher; isolated prefix; benign PE runs |
| M2 genuine MSTSC launch | **done**: genuine dialog renders with images and fonts (patches 0001–0009); mstscax registers and instantiates; Connect resolves the target and reports unreachable hosts the way Windows does |
| M3 connection | **in progress**: TLS session to a Windows host works (EXP-023); certificate warning verified (EXP-026); **NLA/CredSSP with NTLM works against a real Windows host** (EXP-030/031, ADR-0016–0018); saved credentials (ADR-0020/0021); wrong-password re-prompt (ADR-0022–0024); **Kerberos without a domain join** (EXP-041, ADR-0025–0028) |
| M4–M8 | not started |

## Completed
- Environment inventory: LMDE 7 / Debian 13 base, Cinnamon **X11** (not the KDE/Wayland
  primary target), 8 CPUs, 11 GiB RAM, passwordless sudo since 2026-11-14 (builds stay rootless). Rootless build sysroot (ADR-0001).
- Wine 11.0 (`db11d0fe`) built out-of-tree with no modifications in about 6 min (`tools/build-wine.sh baseline`).
- Patch series (`patches/series`) built and tested (`tools/build-wine.sh patched`):
  - 0001 `devobj`: new builtin; unblocks loading `mstscax.dll` (verified).
  - 0002 `ntdll` MUI satellite loading: fixture passes; engages for mstsc.exe and
    mstscax.dll (verified by trace). Real satellites not yet available to test.
- Tools: `inspect-pe.py` (manifest inspector), `check-imports.py` (imports vs Wine
  exports), `mui-config.py`, `xshot.py`, `build-wine.sh`.
- Launcher `launcher/mstsc-wine`: init/import/run/exec/doctor/--version, hash-verified
  component store, private prefix, redacted deterministic logs.
- High-DPI prefix integration (ADR-0050): the launcher imports desktop `Xft.dpi` into
  Wine `LogPixels`, updates the prefix when it changes, reports the source in `doctor`,
  and provides a validated override. Registry behavior is automated; confirmed live on
  LMDE/Cinnamon at 150% (EXP-069). KDE and Wayland/XWayland checks remain.
- Remote audio: patch 0041 fixes mstsc's ACM driver-ID format queries; the genuine-mstsc
  local `rdpsnd` test reaches `waveOutWrite` (EXP-070). Live WPP then exposed a second
  Wine defect: the PCM-only ACM driver claimed it could decode the server's MPEG-4 AAC
  formats. Patch 0043 rejects non-PCM stream tags; focused and Wine conformance tests
  pass (ADR-0053/EXP-072). The operator confirms audible remote Windows audio after a
  fresh LMDE build (EXP-073), satisfying F-009 in the tested Cinnamon environment.
- Tests: regression A/B suite (incl. CredSSP client), launcher isolation test,
  server-certificate warning test (`tests/security/cert-prompt/run.sh`), NLA end-to-end
  (`tests/security/credssp/run.sh`; needs `python3-pyspnego`), fullscreen Restore/Maximize
  (`tests/launch/test-fullscreen-restore.sh`), and remote-audio negotiation
  (`tests/launch/test-audio.sh`). At the patch-0043 checkpoint both regression modes
  report 0 unexpected and every launch test passes (EXP-072); the regression harness
  uses the bundled private NTLM helper when no host `ntlm_auth` is installed.
- "Remember my password": saved credentials are delegated on reconnect (patch 0018, ADR-0020), and user names without a domain are kept as typed (patch 0017, ADR-0021). Verified offline and confirmed by the operator against `<test-host>` (EXP-037).
- Wrong password: "Your credentials did not work" re-prompt, as on Windows, instead of a retry without NLA (patch 0019, ADR-0022). Verified offline with the genuine mstsc and confirmed by the operator against `<test-host>`.
- Kerberos: works without joining the domain (patches 0022–0025, ADR-0025–0028), offline against an MIT realm and live against `<domain-rdp-host>` in `<test-domain>`. Sign in as `user@dns.domain` (or `dns.domain\user`). No certificate warning then, as on Windows.
- Certificate warning over NLA: mstsc now shows its genuine warning for an untrusted server over CredSSP, before any credentials are delegated, and connects after "Yes" (patch 0040, ADR-0048). It never worked before; EXP-031 was corrected. Verified offline and live by the operator (EXP-065/066). Kerberos logons still show no warning, as on Windows.
- Re-prompt dialog: the whole message is shown, wrapped, and the password field is empty, as on Windows (patches 0020–0021, ADR-0023/0024). Verified offline with the genuine mstsc and confirmed by the operator against `<test-host>`.
- Fullscreen → windowed: Restore then Maximize works under muffin and metacity (patch 0016, ADR-0019), confirmed by the operator on the real Cinnamon desktop against the Windows host. KDE/XWayland still to test.
- Connection dialog looks like Windows Server 2022 (EXP-042–047, R-025; patches 0026–0031):
  - "Show Options"/"Hide Options" are no longer cut off (patch 0026, ADR-0029).
  - Connect and Help stay visible after expanding (patch 0027, ADR-0030; a wineserver repaint bug, also in unmodified Wine 11.0).
  - Text is as wide as on Windows, so the message wraps as on Windows (patch 0028, ADR-0031). The fonts were already right: Microsoft Sans Serif for the body, Tahoma for the banner, as on Windows.
  - The credentials panel on the General tab is white like the tab page, not a grey box (patch 0029, ADR-0032).
  - Test: `tests/static/dialog-layout` (in the regression suite).
  - Hovering over Show/Hide Options draws the whole frame (patch 0030, ADR-0033). The group box frames leave space around their captions (patch 0031, ADR-0034).
  - Remaining differences (cosmetic, not fixed): Windows 10 button face and tab row drawing details.
- Clipboard redirection works offline with the genuine mstsc (EXP-048–054, R-026; patches 0032–0038, ADR-0035–0041):
  - Text in both directions: remote → local was refused by mstsc (stale last error from missing ntdll feature
    exports), and Wine → X11 was never flushed.
  - Files in both directions. Remote files are written to the prefix's `%TEMP%\Clipboard` on paste and offered as
    `text/uri-list` and `x-special/gnome-copied-files`.
  - Pictures (CF_DIB ↔ `image/bmp`) in both directions.
  - Test: `tests/launch/test-clipboard.sh` (15 checks against a local cliprdr server); fixture
    `tests/static/ole-clipboard` (in the regression suite).
  - Confirmed by the operator on the real Cinnamon desktop against a real Windows host (EXP-055): text and files
    copied both ways. Pictures and every other scenario not yet checked live.

## Blockers (need human input)
1. The remaining live DPI matrix needs real scaled desktops: KDE on X11, and Cinnamon
   and KDE on Wayland (Wine through XWayland), especially at 125% and 150%. Cinnamon X11
   at 150% is confirmed (EXP-069); KDE Plasma X11 at 100% works (EXP-064).

## Next actions
1. Complete T-015 audio follow-up: verify repeated start/stop, reconnect, and process
   cleanup, then repeat the audio smoke test on KDE and Wayland/XWayland.
2. Clipboard follow-ups: pictures on a live session, T-013 (directory trees), T-014 (two sessions), Dolphin
   (KDE). Wine imports one X11 copy twice (two cliprdr format lists).
3. NLA follow-ups: server with NLA *required*; Kerberos with a NetBIOS domain (`DOMAIN\user` falls back to NTLM; ADR-0026).
4. Certificate prompt with a CA-trusted certificate (expect no prompt, flags `CREDSSP_SERVER_AUTH_CERTIFICATE`).
5. DPI: visually verify 100%, 125%, and 150% on Cinnamon and KDE, on both X11 and
   Wayland/XWayland; check dialog size, session surface, pointer coordinates, and moving
   between differently scaled monitors. Then continue keyboard and display work.
6. Packaging: bundle the patched GnuTLS (`tools/build-gnutls.sh`) and `ntlm_auth` dependency; Wine Mono not needed.
