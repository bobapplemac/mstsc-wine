# ADR-0042: Private NTLM helper, selected by WINENTLMAUTH (patch 0039)

- Status: accepted. 2026-11-15.
- Context (V, Wine 11.0 source):
  - `msv1_0` (NTLM, also used by Negotiate and CredSSP) runs Samba's `ntlm_auth` with
    `--helper-protocol=ntlmssp-client-1 --username=U --domain=D` (`dlls/msv1_0/main.c`)
    and talks the squid-style line protocol over stdin/stdout (`YR`, `PW`, `KK`, `AF`, `GK`, `GF`).
  - The helper is started with `posix_spawnp("ntlm_auth")`, so whatever `ntlm_auth` is first
    on `PATH` runs (`dlls/msv1_0/unixlib.c`). It inherits Wine's environment.
  - `--use-cached-creds` (single sign-on through winbindd) is used only when no explicit
    credentials and no saved credential exist. mstsc always passes explicit or saved credentials.
  - The server mode (`squid-2.5-ntlmssp`) is not used by an RDP client.
- Finding (V, strace of Debian 13's `ntlm_auth` 4.22.11, `--configfile=/dev/null`): the
  client helper mode answers `PW`/`YR`/`KK` with no `winbindd`, opens no socket, and reads
  no Samba state. It reads its configuration file (default `/etc/samba/smb.conf`) and scans
  the compiled-in module directory `…/samba/gensec`; both are optional.
- Decision:
  1. Patch 0039: when `WINENTLMAUTH` is set, Wine runs exactly that file (absolute path
     required, no `PATH` fallback; a relative value is refused and logged). Unset, behaviour
     is unchanged (upstream lookup through `PATH`), so the development runtime and the
     baseline comparisons keep working.
  2. The packaged runtime ships `ntlm_auth` and its library closure from Debian 13's signed
     binary packages, pinned by version and SHA-256 in `packaging/debian-binaries.lock`
     (ADR-0045), under `usr/lib/mstsc-wine/samba/`.
  3. Wine runs `samba/bin/ntlm_auth`, a small wrapper script. It sets a library path that
     reaches only the private Samba, GnuTLS and dependency directories and runs the real
     binary with `--configfile` pointing at the bundled, empty `samba/smb.conf`. The host's
     `smb.conf` is never read.
  4. The launcher sets `WINENTLMAUTH` only for the Wine child; it is never exported to the
     user's shell.
- Not chosen:
  - Prepending a directory to `PATH`: not deterministic (spec §5.1.5) and leaks into every
    process Wine starts.
  - Building Samba from source for one helper: possible later; Debian's packages already
    carry Debian's security fixes, and their provenance is checkable (signed archive, pinned hashes).
  - Reimplementing NTLMSSP inside Wine: large, security sensitive, and not needed.
- Security: the helper receives the password over a pipe (`PW` line), exactly as before.
  Nothing is logged by the wrapper. Trace channels (`MSTSC_WINE_TRACE=+ntlm`) can still
  print protocol lines and stay opt-in (AGENTS.md rule 7).
- Tests: `tests/static/ntlm-helper/run.sh` (regression suite): logon through a helper at a
  path with a space, a decoy `ntlm_auth` on `PATH` never runs, relative value refused,
  no fallback. Baseline: fails (decoy runs), as expected.
  `tests/portability/test-ntlm-private.sh`: the bundled helper with host Samba hidden.
