# ADR-0050: Import the desktop DPI into the private Wine prefix

- Status: accepted
- Date: 2026-11-18
- Defect (V/I): Wine 11.0 reads its system DPI from
  `HKCU\Control Panel\Desktop\LogPixels` and otherwise uses 96 DPI (source review, V).
  The launcher did not set that value. On the operator's LMDE/Cinnamon laptop at 150%,
  genuine mstsc consequently rendered at an apparent 100% scale (operator report, V;
  causal attribution pending visual confirmation, I). mstsc opts into per-monitor DPI
  awareness, so treating it as a legacy application and relying on compositor bitmap
  scaling is not generally correct.
- Decision: in automatic mode, read `Xft.dpi` from the X resource manager and copy the
  rounded value to Wine's `LogPixels`. Cinnamon and KDE publish this resource for X11
  clients, including XWayland configurations where clients are expected to scale
  themselves. Store the effective DPI in the prefix state so a desktop scaling change
  causes a deterministic prefix update. Report the value and source through logs,
  `doctor`, and `--version`.
- Escape hatch: accept `MSTSC_WINE_DPI=48..480` from the environment or the parsed user
  configuration. This covers compositor/session combinations that do not publish an X
  resource. `auto` remains the default. Invalid values fail closed with an actionable
  error.
- Alternatives: patching Wine's X11 driver would affect all Wine applications and still
  need a desktop-policy source; parsing Cinnamon/KDE private configuration would add
  desktop-specific branches; inferring physical DPI from EDID does not represent the
  user's chosen scale. All were rejected.
- Portability: no desktop name is tested. Missing `xrdb`, a missing display, or an absent
  `Xft.dpi` preserves the existing 96-DPI behavior. On Wayland this project still uses
  Wine's X11 driver through XWayland; native Wine Wayland remains experimental.
- Risk/rollback: a compositor that already bitmap-scales XWayland clients could cause
  double scaling if it also publishes a scaled `Xft.dpi`. `doctor` exposes the decision,
  and `MSTSC_WINE_DPI=96` is the rollback. The Cinnamon X11, Cinnamon Wayland, KDE X11,
  and KDE Wayland matrix needs live visual verification.
- Test: `tests/launch/test-launcher-isolation.sh` supplies `Xft.dpi=144`, checks the prefix
  state, registry `LogPixels=144`, and diagnostic log. `tests/launch/test-dpi-detection.sh`
  covers automatic detection, explicit override, resource-manager failure, and
  invalid-value rejection through `mstsc-wine --version`.
