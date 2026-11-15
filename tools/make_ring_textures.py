"""Writes Textures/RingNN.tga: white anti-aliased rings for the target cast ring's game
timer (Rings/TargetCast.lua), one per band width; NN is the hollow's radius as a % of the
outer edge (40, 44 ... 96). 256x256, 32-bit uncompressed TGA, alpha = coverage, rows stored
bottom-up (the TGA layout games read most reliably).

    python tools/make_ring_textures.py
"""
import math, os, struct

SIZE = 256
SAMPLES = 4  # per axis, for smooth edges

here = os.path.dirname(os.path.abspath(__file__))
out_dir = os.path.join(os.path.dirname(here), 'Textures')
os.makedirs(out_dir, exist_ok=True)

def ring(inner_frac):
    c = SIZE / 2
    r_out = SIZE / 2 - 0.5
    r_in = r_out * inner_frac
    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            hit = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    dx = x + (sx + 0.5) / SAMPLES - c
                    dy = y + (sy + 0.5) / SAMPLES - c
                    d = math.hypot(dx, dy)
                    if r_in <= d <= r_out:
                        hit += 1
            a = round(hit * 255 / (SAMPLES * SAMPLES))
            row += bytes((255, 255, 255, a))  # B, G, R, A
        rows.append(bytes(row))
    # Header: no ID, no color map, type 2 (true color), origin 0,0, size, 32 bpp,
    # descriptor 8 (8 alpha bits, bottom-left origin: rows bottom-up).
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    return header + b''.join(reversed(rows))

for pct in range(40, 97, 4):
    path = os.path.join(out_dir, 'Ring%d.tga' % pct)
    with open(path, 'wb') as f:
        f.write(ring(pct / 100))
    print('wrote', os.path.relpath(path, os.path.dirname(here)))
