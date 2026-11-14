#!/usr/bin/env python3
"""Write a binary MUI resource configuration blob.

make-mui-config.py main|mui OUT CHECKSUM_HEX [--lang en-US] [--fallback en-US] [--mui-types 6,4]
Layout follows the structure Wine's kernelbase validates (GetFileMUIInfo).
"""
import argparse
import struct

ap = argparse.ArgumentParser()
ap.add_argument("kind", choices=["main", "mui"])
ap.add_argument("out")
ap.add_argument("checksum")
ap.add_argument("--lang", default="en-US")
ap.add_argument("--fallback", default="en-US")
ap.add_argument("--mui-types", default="6")
a = ap.parse_args()

HDR = 7 * 4 + 32 + 18 * 4
blobs = []
off = HDR


def add(data):
    global off
    o = off
    blobs.append(data)
    off += len(data)
    pad = (-off) % 8
    if pad:
        blobs.append(b"\0" * pad)
        off += pad
    return o, len(data)


mui_ids = [int(x) for x in a.mui_types.split(",")]
mui_id_off, mui_id_size = add(struct.pack("<%dI" % len(mui_ids), *mui_ids))
ln_id_off, ln_id_size = add(struct.pack("<2I", 16, 24))
if a.kind == "main":
    lang_off, lang_size = 0, 0
    fb_off, fb_size = add((a.fallback + "\0").encode("utf-16-le"))
    file_type = 0x11
else:
    lang_off, lang_size = add((a.lang + "\0").encode("utf-16-le"))
    fb_off, fb_size = 0, 0
    file_type = 0x12
checksum = bytes.fromhex(a.checksum)
assert len(checksum) == 16
hdr = struct.pack("<7I16s16s18I", 0xfecdfecd, off, 0x10000, 0, file_type, 0, 2,
                  b"\0" * 16, checksum, 0, 0, 0, 0, 0, 0,
                  0, 0, ln_id_off, ln_id_size, 0, 0, mui_id_off, mui_id_size,
                  lang_off, lang_size, fb_off, fb_size)
assert len(hdr) == HDR
open(a.out, "wb").write(hdr + b"".join(blobs))
