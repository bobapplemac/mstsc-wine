#!/usr/bin/env python3
"""Screenshot an X display (e.g. nested Xephyr) to PNG: xshot.py :5 out.png"""
import sys
from PIL import ImageGrab
ImageGrab.grab(xdisplay=sys.argv[1]).save(sys.argv[2])
