# ADR-0006: user32 ordinal 2598 as a no-op (patch 0003)

- Status: accepted (temporary, upstream candidate)
- Defect (V): mstsc.exe 10.0.20348 runs `GetProcAddress(LoadLibraryW(L"user32.dll"), 2598)`
  in its DPI helper. When the process becomes per-monitor aware, it calls the result with
  no arguments. Wine 11.0 exports 2598 as `stub @`, so mstsc aborts at startup.
- Evidence: winedbg backtrace returning to `mstsc+0x67029`. The helper's field table at
  `mstsc+0x68180` lists, in order: SetProcessDpiAwarenessContext, #2598,
  EnableNonClientDpiScaling. At the call site `eax` is overwritten immediately, so the
  result is ignored (V).
- Name (H): `EnablePerMonitorDialogScaling`. This is inferred from the context; no source
  I could reach confirms it.
- Fix: `2598 stdcall -noname EnablePerMonitorDialogScaling()` returning TRUE with a FIXME.
- Test: `tests/static/user32-ordinals/ord2598.c` fails on baseline and passes on patched.
- Risk: dialogs get no per-monitor DPI rescaling. That's acceptable, because Wine doesn't
  implement it either. Revisit during the DPI milestone (T-0xx DPI).
