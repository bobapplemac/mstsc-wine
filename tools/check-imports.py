#!/usr/bin/env python3
"""Check a PE's imports against a Wine source tree's .spec export tables.

Usage: check-imports.py WINE_SRC FILE...
Reports, per imported function: missing DLL, missing export, or export that is
only a 'stub' in Wine.  API-set names are resolved via apisetschema.spec using
Windows-style matching (last version component ignored).
Requires pefile.
"""
import os
import re
import sys

import pefile


def load_apisets(src):
    sets = {}
    for line in open(os.path.join(src, "dlls/apisetschema/apisetschema.spec")):
        m = re.match(r"apiset\s+(\S+)\s*=\s*(\S+)", line)
        if m:
            sets[m.group(1).lower().rsplit("-", 1)[0]] = m.group(2).lower()
    return sets


_spec_cache = {}


def load_spec(src, dll):
    name = dll.lower()
    if name.endswith(".dll"):
        name = name[:-4]
    if name in _spec_cache:
        return _spec_cache[name]
    path = None
    for cand in (name, name + ".dll"):
        d = os.path.join(src, "dlls", cand)
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.endswith(".spec"):
                    path = os.path.join(d, f)
                    break
        if path:
            break
    if not path:
        _spec_cache[name] = None
        return None
    exports = {}
    for line in open(path):
        line = line.split("#", 1)[0].strip()
        if not line or not line[0].isdigit() and line[0] != "@":
            continue
        parts = line.split()
        kind = parts[1]
        rest = [p for p in parts[2:] if not p.startswith("-")]
        if not rest:
            continue
        fname = rest[0].split("(")[0]
        exports[fname] = kind
        if parts[0] != "@":
            exports["#" + parts[0]] = kind
    _spec_cache[name] = exports
    return exports


def main():
    src = sys.argv[1]
    apisets = load_apisets(src)
    for f in sys.argv[2:]:
        pe = pefile.PE(f)
        print("==", f)
        for attr, label in (("DIRECTORY_ENTRY_IMPORT", "static"), ("DIRECTORY_ENTRY_DELAY_IMPORT", "delay")):
            for e in getattr(pe, attr, []) or []:
                dll = e.dll.decode()
                target = dll.lower()
                if target.startswith("api-ms-") or target.startswith("ext-ms-"):
                    key = target[:-4].rsplit("-", 1)[0]
                    target = apisets.get(key)
                    if not target:
                        print("  [%s] %-45s NO APISET MAPPING" % (label, dll))
                        continue
                spec = load_spec(src, target)
                if spec is None:
                    print("  [%s] %-45s DLL NOT IN WINE (%d functions)" % (label, dll, len(e.imports)))
                    continue
                for imp in e.imports:
                    n = imp.name.decode() if imp.name else "#%d" % imp.ordinal
                    k = spec.get(n)
                    if k is None:
                        print("  [%s] %-45s %-40s MISSING (-> %s)" % (label, dll, n, target))
                    elif k == "stub":
                        print("  [%s] %-45s %-40s stub (-> %s)" % (label, dll, n, target))


if __name__ == "__main__":
    main()
