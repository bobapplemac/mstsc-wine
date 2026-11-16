#!/usr/bin/env python3
"""Operator-supplied Microsoft component bundles (ADR-0046). Pure Python, no dependencies.

    mscomponents.py verify   ZIP                 validate structure, policy, versions, SHA-256
    mscomponents.py extract  ZIP DEST            verify, then unpack to DEST/Windows/... and
                                                 write DEST/manifest.sha256 + component-manifest.json
    mscomponents.py from-dir DIR OUT.zip         build a bundle from a folder that mirrors C:\\Windows
                                                 (Linux equivalent of windows/Export-MstscComponents.ps1)
    mscomponents.py icon     DEST PE [PE ...]    extract the first group icon as PNGs (+ .ico)
    mscomponents.py version  FILE                print a PE file's version

The bundle is never modified, never uploaded and never written into the Git checkout by
these commands (DEST is chosen by the caller). Exit status 0 = OK, 1 = invalid input.
Set MSTSC_COMPONENTS_EXPERIMENTAL=1 to accept a bundle whose manifest says "experimental".
"""
import datetime, hashlib, io, json, os, re, struct, sys, zipfile, zlib

SCHEMA = "mstsc-wine-components/1"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POLICY = json.load(open(os.path.join(ROOT, "packaging", "components-policy.json")))
MAX_FILE = 64 << 20          # no legitimate component is larger
MAX_TOTAL = 256 << 20


class Invalid(Exception):
    pass


# ---------------------------------------------------------------- PE parsing
class PE:
    def __init__(self, data):
        self.d = data
        if data[:2] != b"MZ":
            raise Invalid("not a PE file (no MZ header)")
        off = struct.unpack_from("<I", data, 0x3C)[0]
        if data[off:off + 4] != b"PE\0\0":
            raise Invalid("not a PE file (no PE signature)")
        self.machine, nsec, _, _, _, optsize, _ = struct.unpack_from("<HHIIIHH", data, off + 4)
        opt = off + 24
        magic = struct.unpack_from("<H", data, opt)[0]
        dd = opt + (112 if magic == 0x20B else 96)
        ndd = struct.unpack_from("<I", data, dd - 4)[0]
        self.res_rva = struct.unpack_from("<I", data, dd + 2 * 8)[0] if ndd > 2 else 0
        self.sections = []
        so = opt + optsize
        for i in range(nsec):
            _, vsize, va, rsize, raw = struct.unpack_from("<8sIIII", data, so + 40 * i)
            self.sections.append((va, max(vsize, rsize), raw))

    def off(self, rva):
        for va, size, raw in self.sections:
            if va <= rva < va + size:
                return rva - va + raw
        raise Invalid("RVA outside sections")

    def resources(self):
        """{type: {name: [(lang, bytes)]}} with int or str keys."""
        out = {}
        if not self.res_rva:
            return out
        base = self.off(self.res_rva)

        def name(v):
            if v & 0x80000000:
                o = base + (v & 0x7FFFFFFF)
                n = struct.unpack_from("<H", self.d, o)[0]
                return self.d[o + 2:o + 2 + 2 * n].decode("utf-16le")
            return v

        def entries(o):
            nn, ni = struct.unpack_from("<HH", self.d, o + 12)
            for i in range(nn + ni):
                yield struct.unpack_from("<II", self.d, o + 16 + 8 * i)

        for tn, to in entries(base):
            if not to & 0x80000000:
                continue
            for nn, no in entries(base + (to & 0x7FFFFFFF)):
                if not no & 0x80000000:
                    continue
                for ln, lo in entries(base + (no & 0x7FFFFFFF)):
                    rva, size = struct.unpack_from("<II", self.d, base + lo)
                    o = self.off(rva)
                    out.setdefault(name(tn), {}).setdefault(name(nn), []).append((ln, self.d[o:o + size]))
        return out

    def version(self):
        for _, items in self.resources().get(16, {}).items():
            for _, blob in items:
                i = blob.find(struct.pack("<I", 0xFEEF04BD))
                if i >= 0:
                    ms, ls = struct.unpack_from("<II", blob, i + 8)
                    return "%d.%d.%d.%d" % (ms >> 16, ms & 0xFFFF, ls >> 16, ls & 0xFFFF)
        return None


MACHINES = {0x14C: "x86", 0x8664: "x86-64", 0xAA64: "arm64"}


# ---------------------------------------------------------------- icons
def _png(w, h, rgba):
    raw = b"".join(b"\0" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def dib_to_png(dib):
    """RT_ICON DIB (BITMAPINFOHEADER + XOR + AND mask) -> PNG bytes."""
    hs, w, h2, _, bpp, comp = struct.unpack_from("<IiiHHI", dib, 0)
    h = h2 // 2
    if comp not in (0, 3):
        raise Invalid("unsupported icon compression")
    ncol = struct.unpack_from("<I", dib, 32)[0] or (1 << bpp if bpp <= 8 else 0)
    pal = [dib[hs + 4 * i:hs + 4 * i + 4] for i in range(ncol)]
    o = hs + 4 * ncol + (12 if comp == 3 and hs == 40 else 0)
    stride = ((w * bpp + 31) // 32) * 4
    mstride = ((w + 31) // 32) * 4
    mask_o = o + stride * h
    out = bytearray(w * h * 4)
    has_alpha = False
    for y in range(h):
        row = o + (h - 1 - y) * stride
        for x in range(w):
            if bpp == 32:
                b, g, r, a = dib[row + 4 * x:row + 4 * x + 4]
                has_alpha |= a != 0
            elif bpp == 24:
                b, g, r = dib[row + 3 * x:row + 3 * x + 3]; a = 255
            elif bpp in (8, 4, 1):
                bit = x * bpp
                v = (dib[row + bit // 8] >> (8 - bpp - bit % 8)) & ((1 << bpp) - 1)
                b, g, r = pal[v][:3]; a = 255
            else:
                raise Invalid("unsupported icon depth %d" % bpp)
            out[(y * w + x) * 4:(y * w + x) * 4 + 4] = bytes((r, g, b, a))
    if not has_alpha:   # apply the AND mask
        for y in range(h):
            row = mask_o + (h - 1 - y) * mstride
            for x in range(w):
                if mask_o + mstride * h <= len(dib) and (dib[row + x // 8] >> (7 - x % 8)) & 1:
                    out[(y * w + x) * 4 + 3] = 0
    return _png(w, h, bytes(out))


def extract_icon(paths, dest):
    """Write mstsc-wine-<N>.png per size and mstsc-wine.ico from the first group icon found."""
    for p in paths:
        if not os.path.exists(p):
            continue
        res = PE(open(p, "rb").read()).resources()
        groups, icons = res.get(14, {}), res.get(3, {})
        if not groups or not icons:
            continue
        gname = sorted(groups, key=lambda k: (isinstance(k, str), k))[0]
        grp = groups[gname][0][1]
        _, _, count = struct.unpack_from("<HHH", grp, 0)
        os.makedirs(dest, exist_ok=True)
        written, ico_entries = [], []
        for i in range(count):
            bw, bh, _, _, _, bpp, _, iid = struct.unpack_from("<BBBBHHIH", grp, 6 + 14 * i)
            if iid not in icons:
                continue
            data = icons[iid][0][1]
            png = data if data[:8] == b"\x89PNG\r\n\x1a\n" else dib_to_png(data)
            w = struct.unpack(">I", png[16:20])[0]
            ico_entries.append((w, bpp, data))
            name = os.path.join(dest, "mstsc-wine-%d.png" % w)
            # keep the deepest variant of each size
            if w not in [x[0] for x in written] or bpp >= max(b for s, b in written if s == w):
                open(name, "wb").write(png)
                written.append((w, bpp))
        if not written:
            continue
        ico = struct.pack("<HHH", 0, 1, len(ico_entries))
        off = 6 + 16 * len(ico_entries)
        body = b""
        for w, bpp, data in ico_entries:
            ico += struct.pack("<BBBBHHII", w % 256, w % 256, 0, 0, 1, bpp, len(data), off + len(body))
            body += data
        open(os.path.join(dest, "mstsc-wine.ico"), "wb").write(ico + body)
        return {"source": os.path.basename(p), "group": str(gname), "sizes": sorted({s for s, _ in written})}
    return None


# ---------------------------------------------------------------- policy
def classify(path, lang):
    """Return (role, rule) for a bundle path like 'Windows/System32/en-US/mstsc.exe.mui'."""
    low = path.lower()
    for role in ("required", "recommended"):
        for rule in POLICY[role]:
            if low == ("windows/" + rule.replace("<lang>", lang)).lower():
                return role, rule
    return None, None


def check_path(p):
    if p.startswith("/") or "\\" in p or ".." in p.split("/") or not re.fullmatch(r"[A-Za-z0-9_./ -]+", p):
        raise Invalid("unsafe path in bundle: %r" % p)


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def load_zip(path):
    if not os.path.isfile(path):
        raise Invalid("component bundle not found: %s" % path)
    try:
        z = zipfile.ZipFile(path)
    except zipfile.BadZipFile as e:
        raise Invalid("not a valid ZIP file: %s (%s)" % (path, e))
    total = 0
    for i in z.infolist():
        check_path(i.filename.rstrip("/"))
        if i.file_size > MAX_FILE:
            raise Invalid("file too large in bundle: %s" % i.filename)
        total += i.file_size
    if total > MAX_TOTAL:
        raise Invalid("bundle too large (%d bytes)" % total)
    if "manifest.json" not in z.namelist():
        raise Invalid("manifest.json missing: not an mstsc-wine component bundle")
    try:
        m = json.loads(z.read("manifest.json"))
    except ValueError as e:
        raise Invalid("manifest.json is not valid JSON: %s" % e)
    return z, m


def verify(path, quiet=False):
    z, m = load_zip(path)
    errs, warns = [], []
    if m.get("schema") != SCHEMA:
        raise Invalid("unsupported manifest schema %r (expected %s)" % (m.get("schema"), SCHEMA))
    src = m.get("source", {})
    lang = src.get("language", "")
    if not re.fullmatch(r"[a-z]{2,3}(-[A-Za-z0-9]{2,8})*", lang):
        raise Invalid("manifest: invalid or missing source.language")
    if src.get("architecture") != "amd64":
        raise Invalid("manifest: architecture %r is not supported (amd64 only)" % src.get("architecture"))
    support = m.get("support")
    build = str(src.get("os_build", ""))
    major = build.split(".")[0] if build else ""
    if major in POLICY["verified_builds"]:
        support_ok = True
    elif os.environ.get("MSTSC_COMPONENTS_EXPERIMENTAL") == "1":
        support_ok = True
        warns.append("OS build %s is not verified; accepted because MSTSC_COMPONENTS_EXPERIMENTAL=1" % build)
    else:
        support_ok = False
        errs.append("OS build %s is not a verified source (verified: %s); set MSTSC_COMPONENTS_EXPERIMENTAL=1 "
                    "to try it anyway" % (build or "?", ", ".join(POLICY["verified_builds"])))
    if support not in ("verified", "experimental"):
        errs.append("manifest: support must be 'verified' or 'experimental'")
    files = m.get("files")
    if not isinstance(files, list) or not files:
        raise Invalid("manifest: no files listed")
    names = set(n for n in z.namelist() if not n.endswith("/")) - {"manifest.json"}
    listed, versions, roles = set(), {}, {}
    for f in files:
        p = f.get("path", "")
        check_path(p)
        if p in listed:
            errs.append("duplicate entry %s" % p); continue
        listed.add(p)
        role, _ = classify(p, lang)
        if role is None:
            errs.append("not an allowed component: %s" % p); continue
        roles[p] = role
        if p not in names:
            errs.append("listed in manifest but missing from ZIP: %s" % p); continue
        data = z.read(p)
        if sha256(data) != str(f.get("sha256", "")).lower():
            errs.append("SHA-256 mismatch: %s" % p); continue
        if "size" in f and f["size"] != len(data):
            errs.append("size mismatch: %s" % p)
        if p.lower().endswith((".exe", ".dll", ".mui", ".mun")):
            try:
                pe = PE(data)
            except Invalid as e:
                errs.append("%s: %s" % (p, e)); continue
            v = pe.version()
            if f.get("file_version") and v and f["file_version"] != v:
                errs.append("file_version mismatch for %s (manifest %s, file %s)" % (p, f["file_version"], v))
            if p.lower().endswith((".exe", ".dll")) and pe.machine != 0x8664:
                errs.append("%s is %s, not x86-64" % (p, MACHINES.get(pe.machine, hex(pe.machine))))
            versions[p] = v
        elif p.lower().endswith((".ttf", ".ttc")) and data[:4] not in (b"\0\1\0\0", b"true", b"ttcf", b"OTTO"):
            errs.append("%s is not a TrueType/OpenType font" % p)
    for extra in sorted(names - listed):
        errs.append("file in ZIP but not in manifest: %s" % extra)
    for rule in POLICY["required"]:
        p = "Windows/" + rule.replace("<lang>", lang)
        if not any(x.lower() == p.lower() for x in listed):
            errs.append("required component missing: %s" % p)
    for rule in POLICY["recommended"]:
        p = "Windows/" + rule.replace("<lang>", lang)
        if not any(x.lower() == p.lower() for x in listed):
            warns.append("recommended component absent: %s" % p)
    # all binaries from one build: same major.minor.build as mstsc.exe and the OS
    exe = next((v for p, v in versions.items() if p.lower().endswith("system32/mstsc.exe")), None)
    ax = next((v for p, v in versions.items() if p.lower().endswith("system32/mstscax.dll")), None)
    if exe and ax and exe != ax:
        errs.append("mstsc.exe (%s) and mstscax.dll (%s) come from different builds" % (exe, ax))
    if exe:
        b3 = ".".join(exe.split(".")[:3])
        for p, v in versions.items():
            if v and ".".join(v.split(".")[:3]) != b3:
                errs.append("%s version %s does not match mstsc.exe %s (mixed Windows builds)" % (p, v, exe))
        if build and ".".join(build.split(".")[:1]) != exe.split(".")[2]:
            errs.append("manifest os_build %s does not match mstsc.exe build %s" % (build, exe))
    if not quiet:
        for w in warns:
            print("warning: " + w, file=sys.stderr)
    if errs:
        raise Invalid("component bundle %s is invalid:\n  - " % os.path.basename(path) + "\n  - ".join(errs))
    return z, m, {"client_version": exe, "language": lang, "warnings": warns, "roles": roles,
                  "support_ok": support_ok}


WINDIR = {"system32": "system32", "fonts": "Fonts", "systemresources": "SystemResources"}


def extract(path, dest):
    z, m, info = verify(path)
    win = os.path.join(dest, "Windows")
    lines = []
    for f in sorted(m["files"], key=lambda f: f["path"]):
        parts = f["path"].split("/")[1:]           # drop "Windows"
        parts[0] = WINDIR[parts[0].lower()]
        rel = "/".join(parts)
        out = os.path.join(win, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        data = z.read(f["path"])
        with open(out, "wb") as fh:
            fh.write(data)
        os.chmod(out, 0o644)
        lines.append("%s  %s\n" % (sha256(data), rel))
    open(os.path.join(win, "manifest.sha256"), "w").writelines(lines)
    rec = dict(m)
    rec["bundle"] = {"file": os.path.basename(path), "sha256": sha256(open(path, "rb").read())}
    rec["verified"] = {"client_version": info["client_version"], "warnings": info["warnings"]}
    json.dump(rec, open(os.path.join(dest, "component-manifest.json"), "w"), indent=1, sort_keys=True)
    print("components: %s %s (%d files) -> %s" % (info["client_version"], info["language"], len(lines), win))
    return info


def from_dir(src, out):
    """Collect the policy's files from a folder mirroring C:\\Windows (case-insensitive)."""
    index = {}
    for dp, _, fns in os.walk(src):
        for fn in fns:
            rel = os.path.relpath(os.path.join(dp, fn), src).replace(os.sep, "/")
            index[rel.lower()] = rel
    langs = sorted({r.split("/")[1] for r in index if re.fullmatch(r"system32/[a-z]{2,3}-[a-z0-9-]+/mstsc\.exe\.mui", r)})
    if not langs:
        raise Invalid("no system32/<lang>/mstsc.exe.mui under %s" % src)
    lang = "en-US" if "en-us" in langs else index["system32/%s/mstsc.exe.mui" % langs[0]].split("/")[1]
    files = []
    for role in ("required", "recommended"):
        for rule in POLICY[role]:
            want = rule.replace("<lang>", lang)
            hit = index.get(want.lower())
            if not hit:
                if role == "required":
                    raise Invalid("required file missing: %s" % want)
                continue
            data = open(os.path.join(src, hit), "rb").read()
            e = {"path": "Windows/" + want, "role": role, "size": len(data), "sha256": sha256(data)}
            if want.lower().endswith((".exe", ".dll", ".mui", ".mun")):
                e["file_version"] = PE(data).version()
            files.append(e)
    exe = next(f["file_version"] for f in files if f["path"].lower().endswith("system32/mstsc.exe"))
    build = ".".join(exe.split(".")[2:4])
    m = {"schema": SCHEMA, "created": datetime.date.today().isoformat(),
         "exporter": "mscomponents.py from-dir",
         "source": {"os_build": build, "architecture": "amd64", "language": lang,
                    "product": "unknown (built from a copied folder)"},
         "support": "verified" if build.split(".")[0] in POLICY["verified_builds"] else "experimental",
         "files": files}
    tmp = out + ".part"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("manifest.json", json.dumps(m, indent=1))
        for f in files:
            z.write(os.path.join(src, index[f["path"][8:].lower()]), f["path"])
    os.replace(tmp, out)
    print("wrote %s (%d files, build %s, %s)" % (out, len(files), build, lang))


def main(argv):
    try:
        if len(argv) >= 2 and argv[0] == "verify":
            _, m, info = verify(argv[1])
            print("OK %s: mstsc %s, %s, %d files" % (os.path.basename(argv[1]), info["client_version"],
                                                       info["language"], len(m["files"])))
        elif len(argv) >= 3 and argv[0] == "extract":
            extract(argv[1], argv[2])
        elif len(argv) >= 3 and argv[0] == "from-dir":
            from_dir(argv[1], argv[2])
        elif len(argv) >= 3 and argv[0] == "icon":
            r = extract_icon(argv[2:], argv[1])
            if not r:
                print("no icon resources found", file=sys.stderr)
                return 1
            print(json.dumps(r))
        elif len(argv) >= 2 and argv[0] == "version":
            print(PE(open(argv[1], "rb").read()).version())
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except Invalid as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
