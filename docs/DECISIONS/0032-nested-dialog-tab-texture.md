# ADR-0032: Nested ETDT_ENABLE dialogs use a textured parent's texture (patch 0029)

- Status: accepted. 2026-11-15.
- Symptom (V, EXP-045): on mstsc's expanded General tab, the "Credentials" panel (user name
  field and message) is a grey box on the white tab page. On Windows Server 2022 it is white.
- Cause (V, relay trace of the genuine mstsc):
  - mstsc calls `EnableThemeDialogTexture(page, ETDT_ENABLETAB)` on the General page only.
  - The Credentials panel is a `DS_CONTROL` child dialog inside that page. It only gets
    `ETDT_ENABLE`, set by comctl32 on the parent of every themed button and static. Native
    comctl32 v6 does the same, so mstsc's calls and flags are the same on both systems.
  - The panel's dialog procedure does not paint its background (returns 0 for
    `WM_ERASEBKGND` and `WM_CTLCOLORDLG`).
  - Wine's `UXTHEME_DefDlgProc` uses the tab texture only for `ETDT_ENABLETAB`. With
    `ETDT_ENABLE` alone, the panel falls back to `COLOR_BTNFACE`.
  - Since mstsc behaves the same on both systems and Windows draws the panel white, native
    uxtheme must give such a nested dialog its textured parent's background (I).
- Decision:
  - A child dialog whose flag is exactly `ETDT_ENABLE` uses the texture brush of the nearest
    textured ancestor dialog. It walks up while the parents are also `ETDT_ENABLE` children.
  - The brush is aligned to that ancestor: the brush origin in `WM_ERASEBKGND`, and the
    origin set for the controls' `WM_CTLCOLOR*`.
  - Top-level dialogs and dialogs whose parent is the desktop are unchanged. Wine's uxtheme
    conformance tests (all on a desktop-parented dialog) still pass.
- Not verified on Windows (I): the inheritance rule for other nestings (several levels,
  `ETDT_USEAEROWIZARDTABTEXTURE`). `tests/static/dialog-layout/nested.exe` also runs on
  Windows and can confirm it.
- Tests:
  - `tests/static/dialog-layout` (nested.exe) builds mstsc's structure and compares the
    nested dialog's background and `WM_CTLCOLORSTATIC` brush with the page's. Fails on
    baseline, passes on patched.
  - Genuine mstsc: the panel is white and the other tabs are unchanged.
  - uxtheme `system` conformance: 22246 tests, 0 failures on both runtimes.
