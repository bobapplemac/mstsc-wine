#!/usr/bin/env python3
"""Own the CLIPBOARD selection on an X display and serve several targets, the way a
Linux file manager or editor does after "Copy" (xclip can offer only one target).
   xselown.py :5 TARGET=FILE [TARGET=FILE ...]
Serves until another client takes the selection over, or for 300 s.  Data must be
small enough for a single property (no INCR); test fixtures only."""
import sys, time
from Xlib import X, Xatom, display

d = display.Display(sys.argv[1])
targets = {}
for arg in sys.argv[2:]:
    name, path = arg.split('=', 1)
    targets[d.intern_atom(name)] = open(path, 'rb').read()
TARGETS = d.intern_atom('TARGETS')
TIMESTAMP = d.intern_atom('TIMESTAMP')
CLIPBOARD = d.intern_atom('CLIPBOARD')
w = d.screen().root.create_window(0, 0, 1, 1, 0, X.CopyFromParent)
w.change_property(Xatom.WM_NAME, Xatom.STRING, 8, b'xselown')
d.sync()
# a timestamp for the ownership: zero-length property change
w.change_attributes(event_mask=X.PropertyChangeMask)
w.change_property(Xatom.WM_NAME, Xatom.STRING, 8, b'xselown', X.PropModeAppend)
t = X.CurrentTime
while True:
    e = d.next_event()
    if e.type == X.PropertyNotify:
        t = e.time; break
w.set_selection_owner(CLIPBOARD, t)
d.sync()
if d.get_selection_owner(CLIPBOARD) != w:
    sys.exit("could not own CLIPBOARD")
print("owner", flush=True)
end = time.time() + 300
while time.time() < end:
    if not d.pending_events():
        time.sleep(0.02); continue
    e = d.next_event()
    if e.type == X.SelectionClear:
        break
    if e.type != X.SelectionRequest:
        continue
    prop = e.property or e.target
    if e.target == TARGETS:
        e.requestor.change_property(prop, Xatom.ATOM, 32, [TARGETS, TIMESTAMP] + list(targets))
    elif e.target == TIMESTAMP:
        e.requestor.change_property(prop, Xatom.INTEGER, 32, [t & 0xffffffff])
    elif e.target in targets:
        e.requestor.change_property(prop, e.target, 8, targets[e.target])
    else:
        prop = X.NONE
    ev = __import__('Xlib.protocol.event', fromlist=['SelectionNotify']).SelectionNotify(
        time=e.time, requestor=e.requestor, selection=e.selection, target=e.target, property=prop)
    e.requestor.send_event(ev)
    d.flush()
