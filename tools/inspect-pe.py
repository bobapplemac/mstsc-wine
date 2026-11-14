#!/usr/bin/env python3
"""Component-manifest inspector for operator-supplied Microsoft binaries.

Reports SHA-256, version resources, architecture, subsystem, signature
presence, imports (normal / delay / api-set), exports summary, embedded
manifests and MUI hints.  Never copies the binaries anywhere.

Usage: inspect-pe.py [--json] FILE...
Requires: pefile (pip install pefile)
"""
import hashlib
import json
import re
import sys

import pefile

MACHINES = {0x14c: "x86", 0x8664: "x86-64", 0xaa64: "arm64", 0x1c4: "armnt"}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def version_info(pe):
    out = {}
    if hasattr(pe, "VS_FIXEDFILEINFO") and pe.VS_FIXEDFILEINFO:
        ffi = pe.VS_FIXEDFILEINFO[0]
        out["FileVersionBinary"] = "%d.%d.%d.%d" % (
            ffi.FileVersionMS >> 16, ffi.FileVersionMS & 0xFFFF,
            ffi.FileVersionLS >> 16, ffi.FileVersionLS & 0xFFFF)
    for fi in getattr(pe, "FileInfo", []) or []:
        for entry in fi:
            for st in getattr(entry, "StringTable", []) or []:
                for k, v in st.entries.items():
                    out[k.decode(errors="replace")] = v.decode(errors="replace")
    return out


def imports(pe, attr):
    res = {}
    for entry in getattr(pe, attr, []) or []:
        dll = entry.dll.decode(errors="replace")
        names = []
        for imp in entry.imports:
            names.append(imp.name.decode(errors="replace") if imp.name else "#%d" % imp.ordinal)
        res[dll] = names
    return res


def manifests(pe):
    found = []
    if not hasattr(pe, "DIRECTORY_ENTRY_RESOURCE"):
        return found
    for t in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        if t.id != 24:  # RT_MANIFEST
            continue
        for n in t.directory.entries:
            for lang in n.directory.entries:
                d = lang.data.struct
                data = pe.get_memory_mapped_image()[d.OffsetToData:d.OffsetToData + d.Size]
                found.append({"id": n.id, "lang": lang.id,
                              "xml": data.decode("utf-8", errors="replace")})
    return found


def resource_types(pe):
    types = []
    if hasattr(pe, "DIRECTORY_ENTRY_RESOURCE"):
        for t in pe.DIRECTORY_ENTRY_RESOURCE.entries:
            types.append(str(t.name) if t.name else pefile.RESOURCE_TYPE.get(t.id, t.id))
    return types


def strings_hint(path, patterns):
    data = open(path, "rb").read()
    text = data.decode("utf-16-le", errors="ignore") + "\n" + data.decode("latin-1")
    hits = set()
    for p in patterns:
        for m in re.finditer(p, text, re.I):
            hits.add(m.group(0))
    return sorted(hits)


def inspect(path):
    pe = pefile.PE(path, fast_load=False)
    sec_dir = pe.OPTIONAL_HEADER.DATA_DIRECTORY[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_SECURITY"]]
    clr_dir = pe.OPTIONAL_HEADER.DATA_DIRECTORY[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_COM_DESCRIPTOR"]]
    exports = []
    if hasattr(pe, "DIRECTORY_ENTRY_EXPORT"):
        exports = [(e.name.decode() if e.name else "#%d" % e.ordinal)
                   for e in pe.DIRECTORY_ENTRY_EXPORT.symbols]
    imp = imports(pe, "DIRECTORY_ENTRY_IMPORT")
    dimp = imports(pe, "DIRECTORY_ENTRY_DELAY_IMPORT")
    return {
        "file": path,
        "sha256": sha256(path),
        "size": pe.__data__.size() if hasattr(pe.__data__, "size") else len(pe.__data__),
        "machine": MACHINES.get(pe.FILE_HEADER.Machine, hex(pe.FILE_HEADER.Machine)),
        "subsystem": pefile.SUBSYSTEM_TYPE.get(pe.OPTIONAL_HEADER.Subsystem, pe.OPTIONAL_HEADER.Subsystem),
        "is_dll": pe.is_dll(),
        "dotnet": clr_dir.Size > 0,
        "authenticode_embedded": sec_dir.Size > 0,
        "timestamp": pe.FILE_HEADER.TimeDateStamp,
        "version": version_info(pe),
        "imports": imp,
        "delay_imports": dimp,
        "exports_count": len(exports),
        "exports": exports,
        "resource_types": resource_types(pe),
        "manifests": manifests(pe),
        "string_hints": strings_hint(path, [r"[A-Za-z0-9_\-]+\.(?:dll|mui|ocx|cpl)\b",
                                            r"\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}"]),
    }


def main(argv):
    as_json = "--json" in argv
    files = [a for a in argv if a != "--json"]
    reports = [inspect(f) for f in files]
    if as_json:
        json.dump(reports, sys.stdout, indent=1)
        return
    for r in reports:
        print("=" * 72)
        print(r["file"])
        for k in ("sha256", "machine", "subsystem", "is_dll", "dotnet", "authenticode_embedded"):
            print("  %-22s %s" % (k, r[k]))
        for k in ("FileVersion", "ProductVersion", "FileVersionBinary", "OriginalFilename", "FileDescription"):
            if k in r["version"]:
                print("  %-22s %s" % (k, r["version"][k]))
        print("  imports:")
        for d, n in sorted(r["imports"].items(), key=lambda x: x[0].lower()):
            print("    %-50s %d" % (d, len(n)))
        print("  delay imports:")
        for d, n in sorted(r["delay_imports"].items(), key=lambda x: x[0].lower()):
            print("    %-50s %d" % (d, len(n)))
        print("  exports: %d" % r["exports_count"])
        print("  resources: %s" % ", ".join(map(str, r["resource_types"])))
        for m in r["manifests"]:
            print("  manifest id=%s lang=%s:" % (m["id"], m["lang"]))
            print("    " + m["xml"].strip().replace("\n", "\n    "))


if __name__ == "__main__":
    main(sys.argv[1:])
