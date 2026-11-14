# Agent workflow contract

1. The spec (`MSTSC-Wine-Master-Specification.md`) is authoritative. Never substitute
   FreeRDP/VMs, and never weaken an acceptance criterion silently.
2. Never commit Microsoft binaries (`.gitignore` enforces this), credentials or real hostnames.
3. Wine changes: reproduce on the unmodified baseline first (`build/install-wine-11.0`),
   add a fixture or test, then patch on branch `mstsc-wine` in `wine-patched/`, then
   `git format-patch wine-11.0..HEAD -o patches/` and update `patches/series`.
   Write an ADR for every patch.
4. Run `tests/run-regression.sh` against both runtimes and `tests/launch/*.sh` before committing.
5. Record experiments in `docs/COMPATIBILITY.md` and findings with confidence levels
   (V/I/H) in `docs/RESEARCH.md`. Update `docs/STATUS.md` at each checkpoint.
6. GUI tests run in a nested display: `tests/lib/xephyr.sh start :5`, `DISPLAY=:5`.
7. Traces are opt-in (`MSTSC_WINE_TRACE`) and may contain sensitive data. Do not publish them raw.
