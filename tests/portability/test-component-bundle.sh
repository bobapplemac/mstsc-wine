#!/bin/bash
# PKG-012: component bundles are verified against their manifest; corrupt, missing,
# extra, mixed-build, unsafe and unverified inputs are rejected with a clear message.
# Needs the operator's ZIP (private-input/ or MICROSOFT_COMPONENTS); exit 77 (skip) otherwise.
# Works on copies in a private temporary directory, deleted afterwards.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ZIP=${MICROSOFT_COMPONENTS:-$(ls "$ROOT"/private-input/mstsc-components-*.zip 2>/dev/null | head -1)}
[[ -f $ZIP ]] || { echo "SKIP no component ZIP"; exit 77; }
T=$(mktemp -d /var/tmp/mstsc-bundle-test-XXXX); chmod 700 "$T"; trap 'rm -rf "$T"' EXIT
V="python3 $ROOT/tools/mscomponents.py verify"
fail=0
expect_ok() { if $V "$1" >/dev/null 2>"$T/err"; then echo "ok   $2"; else echo "FAIL $2: $(cat "$T/err")"; fail=1; fi; }
expect_bad() { # zip description pattern
    if $V "$1" >/dev/null 2>"$T/err"; then echo "FAIL accepted: $2"; fail=1
    elif grep -qiE "$3" "$T/err"; then echo "ok   rejected: $2"
    else echo "FAIL unclear message for $2: $(cat "$T/err")"; fail=1; fi
}
variant() { # name python-code (gets z_in, z_out, m)
    python3 - "$ZIP" "$T/$1.zip" <<PY
import json, sys, zipfile
src, dst = sys.argv[1:]
zi = zipfile.ZipFile(src); m = json.loads(zi.read("manifest.json"))
files = {n: zi.read(n) for n in zi.namelist() if n != "manifest.json"}
$2
with zipfile.ZipFile(dst, "w") as zo:
    zo.writestr("manifest.json", json.dumps(m))
    for n, d in files.items(): zo.writestr(n, d)
PY
}
expect_ok "$ZIP" "the operator's bundle verifies"
variant corrupt 'n = next(k for k in files if k.endswith("mstscax.dll")); b = bytearray(files[n]); b[5000] ^= 1; files[n] = bytes(b)'
expect_bad "$T/corrupt.zip" "one flipped byte" "SHA-256 mismatch"
variant missing 'n = next(k for k in files if k.endswith("/mstsc.exe")); del files[n]; m["files"] = [f for f in m["files"] if f["path"] != n]'
expect_bad "$T/missing.zip" "required file absent" "required component missing"
variant extra 'files["Windows/System32/evil.dll"] = b"MZ"'
expect_bad "$T/extra.zip" "unlisted extra file" "not in manifest"
variant notallowed 'files["Windows/System32/devobj.dll"] = files[next(k for k in files if k.endswith("mstscax.dll"))]; import hashlib; m["files"].append({"path": "Windows/System32/devobj.dll", "sha256": hashlib.sha256(files["Windows/System32/devobj.dll"]).hexdigest()})'
expect_bad "$T/notallowed.zip" "file outside the policy" "not an allowed component"
variant mixed 'n = next(f for f in m["files"] if f["path"].endswith("mstscax.dll")); n["file_version"] = "10.0.19041.1"'
expect_bad "$T/mixed.zip" "manifest version disagrees with the file" "file_version mismatch"
variant unverified 'm["source"]["os_build"] = "26100.1"; m["support"] = "experimental"'
expect_bad "$T/unverified.zip" "unverified Windows build" "not a verified source"
variant schema 'm["schema"] = "something-else/9"'
expect_bad "$T/schema.zip" "unknown manifest schema" "unsupported manifest schema"
variant arch 'm["source"]["architecture"] = "arm64"'
expect_bad "$T/arch.zip" "wrong architecture" "not supported"
python3 - "$T/unsafe.zip" <<'PY'
import zipfile, sys
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("manifest.json", "{}"); z.writestr("../../etc/x", "x")
PY
expect_bad "$T/unsafe.zip" "path traversal entry" "unsafe path"
printf 'not a zip' > "$T/garbage.zip"
expect_bad "$T/garbage.zip" "not a ZIP" "not a valid ZIP"
expect_bad "$T/absent.zip" "missing file" "not found"
# extraction writes the files and a manifest.sha256 that verifies
python3 "$ROOT/tools/mscomponents.py" extract "$ZIP" "$T/out" >/dev/null 2>&1 && (cd "$T/out/Windows" && sha256sum --quiet -c manifest.sha256) \
    && echo "ok   extract + manifest.sha256" || { echo "FAIL extract"; fail=1; }
exit $fail
