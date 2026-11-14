#!/usr/bin/env python3
"""Dump the MUI resource configuration (type "MUI", id 1) of a PE file."""
import struct
import sys

import pefile

FIELDS = ("signature size version path_type file_type system_attributes fallback_location "
          "service_checksum checksum unk1a unk1b mui_path_off mui_path_size unk2a unk2b "
          "ln_type_name_off ln_type_name_size ln_type_id_off ln_type_id_size "
          "mui_type_name_off mui_type_name_size mui_type_id_off mui_type_id_size "
          "lang_off lang_size fallback_lang_off fallback_lang_size").split()
FMT = "<7I16s16s18I"


def find_mui(pe):
    for t in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        if t.name and str(t.name) == "MUI":
            for n in t.directory.entries:
                for l in n.directory.entries:
                    d = l.data.struct
                    return pe.get_memory_mapped_image()[d.OffsetToData:d.OffsetToData + d.Size]


def dump(path):
    pe = pefile.PE(path)
    data = find_mui(pe)
    if data is None:
        print(path, ": no MUI resource"); return
    h = dict(zip(FIELDS, struct.unpack_from(FMT, data)))
    print("==", path, "(%d bytes)" % len(data))
    for k in ("signature", "size", "version", "path_type", "file_type", "system_attributes", "fallback_location"):
        print("  %-18s %#x" % (k, h[k]))
    print("  service_checksum  ", h["service_checksum"].hex())
    print("  checksum          ", h["checksum"].hex())
    def ids(o, s): return list(struct.unpack_from("<%dI" % (s // 4), data, o)) if s else []
    def wstr(o, s): return data[o:o + s].decode("utf-16-le").rstrip("\0").replace("\0", "|") if s else ""
    print("  main(ln) type ids ", ids(h["ln_type_id_off"], h["ln_type_id_size"]))
    print("  main(ln) type names", wstr(h["ln_type_name_off"], h["ln_type_name_size"]))
    print("  mui type ids      ", ids(h["mui_type_id_off"], h["mui_type_id_size"]))
    print("  mui type names    ", wstr(h["mui_type_name_off"], h["mui_type_name_size"]))
    print("  language          ", wstr(h["lang_off"], h["lang_size"]))
    print("  fallback language ", wstr(h["fallback_lang_off"], h["fallback_lang_size"]))


for p in sys.argv[1:]:
    dump(p)
