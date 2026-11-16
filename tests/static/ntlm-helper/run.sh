#!/bin/bash
# WINENTLMAUTH selects the exact NTLM helper (patch 0039, ADR-0042): the helper named by
# the variable runs, an ntlm_auth found through PATH does not, and a relative path is refused.
#   run.sh WINE CSSP_FIXTURE_DIR [REAL_NTLM_AUTH]
# Uses the CredSSP client fixture (tests/static/credssp-client) for a real NTLM exchange.
W=$1 CSSP=$2 REAL=${3:-$(command -v ntlm_auth)}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
python3 -c 'import spnego' 2>/dev/null || { echo "SKIP python3-pyspnego not installed"; exit 0; }
[[ -x $REAL ]] || { echo "SKIP no ntlm_auth to wrap"; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/poison" "$T/dir with space"
# A decoy on PATH that must never run.
printf '#!/bin/sh\ntouch "%s/poison-ran"\nexit 1\n' "$T" > "$T/poison/ntlm_auth"
# The selected helper, at a path containing a space; logs its argv[0] and execs the real one.
printf '#!/bin/sh\necho "$0 $1" >> "%s/helper.log"\nexec "%s" "$@"\n' "$T" "$REAL" > "$T/dir with space/helper"
chmod +x "$T/poison/ntlm_auth" "$T/dir with space/helper"
fail=0
PATH="$T/poison:$PATH" WINENTLMAUTH="$T/dir with space/helper" \
    "$ROOT/tests/static/credssp-client/run.sh" "$W" "$CSSP" 44360 > "$T/run.log" 2>&1 \
    && echo "PASS NTLM logon through the selected helper" || { echo "FAIL NTLM logon through the selected helper"; fail=1; }
grep -q 'ntlmssp-client-1' "$T/helper.log" 2>/dev/null \
    && echo "PASS selected helper ran in client mode" || { echo "FAIL selected helper did not run"; fail=1; }
[[ ! -e $T/poison-ran ]] && echo "PASS ntlm_auth on PATH ignored" || { echo "FAIL ntlm_auth from PATH ran"; fail=1; }
rm -f "$T/helper.log"
PATH="$T/poison:$PATH" WINENTLMAUTH="relative/helper" \
    "$ROOT/tests/static/credssp-client/run.sh" "$W" "$CSSP" 44370 > "$T/run2.log" 2>&1 \
    && { echo "FAIL relative WINENTLMAUTH accepted"; fail=1; } || echo "PASS relative WINENTLMAUTH refused"
[[ ! -e $T/poison-ran ]] && echo "PASS no PATH fallback for a bad WINENTLMAUTH" || { echo "FAIL fell back to PATH"; fail=1; }
exit $fail
