#!/usr/bin/env python3
"""Click or type on an X display via XTEST (for nested Xephyr GUI tests).
   xclick.py :5 click X Y
   xclick.py :5 type TEXT
   xclick.py :5 key KEYSYM   (e.g. Return, Tab)"""
import sys, time
from Xlib import X, XK, display
from Xlib.ext import xtest

d = display.Display(sys.argv[1])
cmd = sys.argv[2]

def key(sym, shift=False):
    code = d.keysym_to_keycode(sym)
    sh = d.keysym_to_keycode(XK.XK_Shift_L)
    if shift: xtest.fake_input(d, X.KeyPress, sh)
    xtest.fake_input(d, X.KeyPress, code); xtest.fake_input(d, X.KeyRelease, code)
    if shift: xtest.fake_input(d, X.KeyRelease, sh)
    d.sync(); time.sleep(0.02)

if cmd == "click":
    x, y = int(sys.argv[3]), int(sys.argv[4])
    xtest.fake_input(d, X.MotionNotify, x=x, y=y); d.sync(); time.sleep(0.1)
    xtest.fake_input(d, X.ButtonPress, 1); d.sync(); time.sleep(0.05)
    xtest.fake_input(d, X.ButtonRelease, 1); d.sync()
elif cmd == "type":
    for ch in sys.argv[3]:
        sym = XK.string_to_keysym({'.': 'period', '-': 'minus', '/': 'slash', ':': 'colon', ' ': 'space', '\\': 'backslash'}.get(ch, ch))
        key(sym, ch.isupper() or ch == ':')
elif cmd == "key":
    key(XK.string_to_keysym(sys.argv[3]))
d.sync()
