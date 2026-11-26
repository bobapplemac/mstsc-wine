#!/usr/bin/env python3
"""Press physical keys by X keycode on an X display via XTEST (layout-independent).
   xkeycodes.py :5 48 24 108+24 ...
   Each argument is a keycode or a chord of keycodes joined by '+': pressed in order,
   released in reverse order."""
import sys, time
from Xlib import X, display
from Xlib.ext import xtest

d = display.Display(sys.argv[1])
for arg in sys.argv[2:]:
    codes = [int(c) for c in arg.split('+')]
    for c in codes:
        xtest.fake_input(d, X.KeyPress, c); d.sync(); time.sleep(0.04)
    for c in reversed(codes):
        xtest.fake_input(d, X.KeyRelease, c); d.sync(); time.sleep(0.04)
    time.sleep(0.12)
d.sync()
