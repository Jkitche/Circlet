"""Writes Textures/HalfPlane.tga: a mask that's solid on its left half and clear on its right,
with a soft 1-pixel edge down the middle. It only changes from left to right, so it's 1024 wide
and 8 tall: drawn on a square, the edge stays sharp even when the square is made very big (the
moving edge's mask has to reach right along its bar). The health rings' eased bands (Rings/Health/Bands.lua) turn
copies of it about its middle so its edge lies along a line through the ring's centre (a radial
cut): to keep each piece of the band to its own slice of the ring, and as the fill's moving edge.

    python tools/make_mask_textures.py
"""
import os, struct

W, H = 1024, 8
here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(os.path.dirname(here), 'Textures', 'HalfPlane.tga')


def tga(w, h, pixel, path):
    rows = []
    for y in range(h):
        row = bytearray()
        for x in range(w):
            r, g, b, a = pixel(x, y)
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, 'wb') as f:
        f.write(header + b''.join(reversed(rows)))
    print('wrote', os.path.relpath(path, os.path.dirname(here)))


def pixel(x, y):
    # Solid left of the middle, clear right of it, the edge pixel half-and-half.
    centre = x + 0.5 - W / 2
    a = max(0.0, min(1.0, 0.5 - centre))
    return 255, 255, 255, int(round(a * 255))


if __name__ == '__main__':
    tga(W, H, pixel, out)
