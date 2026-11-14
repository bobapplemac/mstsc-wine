#!/usr/bin/env python3
"""Wait until a mapped top-level window whose title matches REGEX exists on an X display.
   xwait.py :5 REGEX [TIMEOUT_SECONDS]   -> exit 0 when found (prints its geometry), 1 on timeout"""
import re, sys, time
from Xlib import display

d = display.Display(sys.argv[1]); pat = re.compile(sys.argv[2])
deadline = time.time() + (float(sys.argv[3]) if len(sys.argv) > 3 else 30)
while time.time() < deadline:
    for w in d.screen().root.query_tree().children:
        try:
            name = w.get_wm_name()
            if name and pat.search(name) and w.get_attributes().map_state:
                g = w.get_geometry(); c = w.translate_coords(d.screen().root, 0, 0)
                print(f"{-c.x} {-c.y} {g.width} {g.height}"); sys.exit(0)
        except Exception:
            pass
    time.sleep(0.25)
sys.exit(1)
