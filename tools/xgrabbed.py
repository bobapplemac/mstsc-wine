#!/usr/bin/env python3
"""Report whether another X client holds the pointer grab on DISPLAY.
   xgrabbed.py :9   -> prints "grabbed" (exit 0) or "free" (exit 1)"""
import sys
from Xlib import display, X

d = display.Display(sys.argv[1])
root = d.screen().root
r = root.grab_pointer(False, X.ButtonPressMask, X.GrabModeAsync, X.GrabModeAsync, X.NONE, X.NONE, X.CurrentTime)
if r == X.GrabSuccess:
    d.ungrab_pointer(X.CurrentTime); d.sync()
    print("free"); sys.exit(1)
print("grabbed"); sys.exit(0)
