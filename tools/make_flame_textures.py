"""Writes the flame sprites for the weapon imbue ring's Flametongue animation (Rings/Class/Shaman/Imbue.lua):
Textures/Flame1.tga .. Flame3.tga, tongues of flame standing on their base, pointing up, on a
transparent background.

They're white (the ring tints them: red-orange for a flame's body, yellow-white for its heart)
and drawn additively, so alpha is brightness: brightest low in the middle, fading out up the
tongue and toward its edges. Each: a teardrop outline (round at the bottom, drawn out to a
point) whose middle line wavers, with ragged licks up its sides and a split tip now and then,
softened. Supersampled, then scaled down for smooth edges.

    python tools/make_flame_textures.py
"""
import math, os, random, struct
import numpy as np
from PIL import Image, ImageFilter

W, H = 64, 128  # in game: twice as tall as wide
SS = 4
BW, BH = W * SS, H * SS
here = os.path.dirname(os.path.abspath(__file__))
out_dir = os.path.join(os.path.dirname(here), 'Textures')


def tga(img, path):
    """32-bit uncompressed TGA (as tools/make_rock_textures.py writes them)."""
    img = img.convert('RGBA')
    w, h = img.size
    px = img.load()
    rows = []
    for y in range(h):
        row = bytearray()
        for x in range(w):
            r, g, b, a = px[x, y]
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, 'wb') as f:
        f.write(header + b''.join(reversed(rows)))
    print('wrote', os.path.relpath(path, os.path.dirname(here)))


def flame(seed):
    pr = random.Random(seed)
    yy, xx = np.mgrid[0:BH, 0:BW].astype(np.float32)
    # t: 0 at the base (bottom of the image, a little above the edge) to 1 at the tip.
    base_y, tip_y = BH * 0.93, BH * 0.04
    t = (base_y - yy) / (base_y - tip_y)
    x = (xx - BW / 2) / (BW / 2)  # -1..1 across
    # The middle line wavers more toward the tip.
    a1, a2 = pr.uniform(0, 2 * math.pi), pr.uniform(0, 2 * math.pi)
    k1, k2 = pr.uniform(1.0, 1.8), pr.uniform(2.5, 4.0)
    mid = np.clip(t, 0, 1) ** 1.3 * (0.16 * np.sin(t * math.pi * k1 + a1) + 0.07 * np.sin(t * math.pi * k2 + a2))
    # Half-width: a round bottom swelling quickly, then drawn out to a point.
    tc = np.clip(t, 0, 1)
    half = 0.86 * np.sqrt(np.clip(t * 3.2 + 0.08, 0, 1)) * (1 - tc) ** pr.uniform(0.9, 1.25)
    # Ragged licks up the sides.
    lick = 1 + 0.16 * np.sin(t * pr.uniform(14, 20) + pr.uniform(0, 6)) * tc \
             + 0.08 * np.sin(t * pr.uniform(27, 35) + pr.uniform(0, 6)) * tc
    half = half * lick
    d = np.abs(x - mid) / np.maximum(half, 1e-3)  # 0 on the middle line, 1 at the edge
    # A split tip: a notch down from the top, now and then.
    if pr.random() < 0.6:
        notch = np.clip((tc - 0.72) * 4, 0, 1) * np.clip(1 - np.abs(x - mid - pr.uniform(-0.05, 0.05)) / 0.09, 0, 1)
        d = d + notch * 1.2
    inside = np.clip(1 - d, 0, 1) * (t >= -0.06) * (t <= 1)
    # Brightness: soft toward the edges, fading up the tongue, a dimmer rim at the very base.
    body = inside ** 0.7
    rise = np.clip(1 - tc ** 1.6, 0, 1)
    foot = np.clip((t + 0.06) / 0.14, 0, 1)
    alpha = body * (0.35 + 0.65 * rise) * foot
    img = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8), 'L')
    img = img.filter(ImageFilter.GaussianBlur(SS * 0.8)).resize((W, H), Image.LANCZOS)
    white = Image.new('L', (W, H), 255)
    return Image.merge('RGBA', (white, white, white, img))


if __name__ == '__main__':
    os.makedirs(out_dir, exist_ok=True)
    for i in range(1, 4):
        tga(flame(2000 + i * 31), os.path.join(out_dir, 'Flame%d.tga' % i))
