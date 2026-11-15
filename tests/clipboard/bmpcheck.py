#!/usr/bin/env python3
"""Picture fixtures for the clipboard test.
   bmpcheck.py make BMP        write a 3x2 24-bit BMP and BMP.dib (CF_DIB: no file header)
   bmpcheck.py bmp FILE DIB    FILE is a BMP file with DIB's size, depth and pixels
   bmpcheck.py dib FILE DIB    FILE is a CF_DIB with DIB's size, depth and pixels"""
import struct, sys

W, H = 3, 2

def pixels_of(dib):
    """(width, height) and the BGR colour of every pixel, whatever the depth (24 or 32)"""
    hs = struct.unpack('<I', dib[:4])[0]
    w, h = struct.unpack('<ii', dib[4:12])
    bpp, = struct.unpack('<H', dib[14:16])
    comp, = struct.unpack('<I', dib[16:20])
    off = hs + (12 if comp == 3 and hs == 40 else 0)   # BI_BITFIELDS masks
    stride = (w * bpp // 8 + 3) & ~3
    rows = [dib[off + y * stride: off + y * stride + w * bpp // 8] for y in range(abs(h))]
    if h < 0: rows.reverse()                            # top-down
    px = tuple(bytes(r[x * bpp // 8: x * bpp // 8 + 3]) for r in rows for x in range(w))
    return (w, abs(h)), px

cmd = sys.argv[1]
if cmd == 'make':
    row = lambda y: b''.join(bytes([x * 80, y * 120, 200]) for x in range(W)) + b'\0' * ((4 - W * 3 % 4) % 4)
    pix = b''.join(row(y) for y in range(H))
    dib = struct.pack('<IiiHHIIiiII', 40, W, H, 1, 24, 0, len(pix), 2835, 2835, 0, 0) + pix
    open(sys.argv[2], 'wb').write(b'BM' + struct.pack('<IHHI', 14 + len(dib), 0, 0, 54) + dib)
    open(sys.argv[2] + '.dib', 'wb').write(dib)
    sys.exit(0)
got = open(sys.argv[2], 'rb').read()
exp = pixels_of(open(sys.argv[3], 'rb').read())
if cmd == 'bmp':
    if got[:2] != b'BM': sys.exit(1)
    got = got[14:]
ok = len(got) > 40 and pixels_of(got) == exp
if not ok: print('picture differs:', pixels_of(got) if len(got) > 40 else got, 'expected', exp, file=sys.stderr)
sys.exit(0 if ok else 1)
