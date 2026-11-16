#!/usr/bin/env python3
"""Copy the shared-library closure of ELF files into a private directory (ADR-0044).

    collect-libs.py --dest DIR --search DIR [--search DIR ...] [--have DIR ...]
                    [--record FILE.json] ELF [ELF ...]

* Each DT_NEEDED soname is resolved, in order, in --have directories (already bundled
  elsewhere in the AppDir: not copied again) and --search directories (copied to --dest).
* Sonames on the host allowlist (packaging/host-libs.txt) are left to the host and never
  copied, even if found in a search directory.
* Anything else that cannot be resolved is an error: the build fails instead of silently
  depending on whatever the build or target host happens to have.
* --record appends one JSON object per copied library (soname, source, sha256, package).

Uses readelf only (no ldd: ldd would resolve against the build host).
"""
import argparse, fnmatch, hashlib, json, os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def needed(path):
    out = subprocess.run(["readelf", "-dW", path], capture_output=True, text=True, check=True).stdout
    return re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", out)


def host_patterns():
    pats = []
    with open(os.path.join(ROOT, "packaging", "host-libs.txt")) as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                pats.append(line.split()[0])
    return pats


def package_index(search):
    """Map real file paths to Debian packages using the .files lists from fetch-debs.sh."""
    idx = {}
    for d in search:
        root = d
        while root != "/" and not os.path.isdir(os.path.join(root, ".files")):
            root = os.path.dirname(root)
        fdir = os.path.join(root, ".files")
        if not os.path.isdir(fdir):
            continue
        vers = {}
        pk = os.path.join(root, ".packages")
        if os.path.exists(pk):
            for line in open(pk):
                p = line.split()
                if len(p) >= 2:
                    vers[p[0]] = p[1]
        for lst in os.listdir(fdir):
            pkg = lst[:-5]
            for rel in open(os.path.join(fdir, lst)):
                rel = rel.strip().lstrip("./")
                if rel:
                    idx[os.path.realpath(os.path.join(root, rel))] = f"{pkg} {vers.get(pkg, '?')}"
    return idx


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", required=True)
    ap.add_argument("--search", action="append", default=[])
    ap.add_argument("--have", action="append", default=[])
    ap.add_argument("--record")
    ap.add_argument("elf", nargs="+")
    a = ap.parse_args()
    hosts = host_patterns()
    pkgidx = package_index(a.search)
    os.makedirs(a.dest, exist_ok=True)
    todo, seen, copied, missing = list(a.elf), set(), [], []
    while todo:
        f = todo.pop()
        for so in needed(f):
            if so in seen:
                continue
            seen.add(so)
            if any(fnmatch.fnmatchcase(so, p) for p in hosts):
                continue
            hit = next((os.path.join(d, so) for d in a.have + [a.dest] if os.path.exists(os.path.join(d, so))), None)
            if hit:
                todo.append(hit)
                continue
            src = next((os.path.join(d, so) for d in a.search if os.path.exists(os.path.join(d, so))), None)
            if not src:
                missing.append((so, f))
                continue
            real = os.path.realpath(src)
            dst = os.path.join(a.dest, so)
            shutil.copy2(real, dst)
            os.chmod(dst, 0o755)
            copied.append({
                "soname": so,
                "source": os.path.relpath(real, ROOT) if real.startswith(ROOT) else real,
                "sha256": hashlib.sha256(open(dst, "rb").read()).hexdigest(),
                "package": pkgidx.get(real, "unknown"),
                "needed_by": os.path.basename(f),
            })
            todo.append(dst)
    if missing:
        for so, by in missing:
            print(f"collect-libs: unresolved {so} (needed by {by}); add its package to "
                  "packaging/debian-binaries.lock or the soname to packaging/host-libs.txt", file=sys.stderr)
        return 1
    if a.record:
        old = json.load(open(a.record)) if os.path.exists(a.record) else []
        json.dump(old + copied, open(a.record, "w"), indent=1)
    print(f"collect-libs: {len(copied)} librar{'y' if len(copied) == 1 else 'ies'} -> {a.dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
