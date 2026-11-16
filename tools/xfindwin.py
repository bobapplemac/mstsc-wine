#!/usr/bin/env python3
"""Wait for a mapped window by exact name and minimum size; print "x y width height".
   xfindwin.py DISPLAY NAME MIN_WIDTH MIN_HEIGHT [TIMEOUT]   (exit 1 on timeout)
Used to find the genuine mstsc certificate warning, whose title equals the main dialog's."""
import sys, time
from Xlib import display, X

d = display.Display(sys.argv[1])
name, mw, mh = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
deadline = time.time() + float(sys.argv[5] if len(sys.argv) > 5 else 30)


def find(w):
    for c in w.query_tree().children:
        try:
            g = c.get_geometry()
            if (c.get_wm_name() == name and g.width >= mw and g.height >= mh
                    and c.get_attributes().map_state == X.IsViewable):
                t = c.translate_coords(d.screen().root, 0, 0)
                return -t.x, -t.y, g.width, g.height
            r = find(c)
            if r:
                return r
        except Exception:
            pass
    return None


while time.time() < deadline:
    r = find(d.screen().root)
    if r:
        print(*r)
        sys.exit(0)
    time.sleep(0.3)
sys.exit(1)
