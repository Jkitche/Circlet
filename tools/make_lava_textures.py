"""Writes the lava sprites for the weapon imbue ring's Flametongue animation (Rings/Class/Shaman/Imbue.lua):
Textures/Lava1.tga .. Lava3.tga, irregular blobs of cooling lava on a transparent background:
plates of dark crust with molten cracks glowing between them.

They're drawn in their own colors (not tinted, normal blending, so the crust can be dark).
Each blob: a lumpy round outline, softened; plates from a Voronoi pattern (cracks where a
point is about as far from its two nearest seeds), the cracks white-hot in the middle and
red at their edges, the crust near black-red, warming where it borders a crack, mottled;
the blob's rim glows a little, as if the molten core shows round it. Supersampled.

    python tools/make_lava_textures.py
"""

import math, os, random, struct
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 64
SS = 4
BIG = SIZE * SS
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


def value_noise(rng, cells):
    grid = rng.random((cells + 1, cells + 1)).astype(np.float32)
    img = Image.fromarray((grid * 255).astype(np.uint8), 'L').resize((BIG, BIG), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255


def lava(seed):
    rng = np.random.default_rng(seed)
    pr = random.Random(seed)
    c = BIG / 2
    # Outline: lumpy and round.
    n = 14
    pts = []
    for i in range(n):
        a = i / n * 2 * math.pi
        r = BIG * 0.44 * pr.uniform(0.82, 1.0)
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    mask_img = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(mask_img).polygon(pts, fill=255)
    mask_img = mask_img.filter(ImageFilter.GaussianBlur(SS * 2.2))
    mask = np.asarray(mask_img, dtype=np.float32) / 255
    inner = (
        np.asarray(
            mask_img.point(lambda v: 255 if v > 127 else 0).filter(ImageFilter.GaussianBlur(SS * 6)), dtype=np.float32
        )
        / 255
    )

    # Plates: distance to the nearest and second-nearest of a scatter of seeds (warped a bit
    # so the cracks wander).
    yy, xx = np.mgrid[0:BIG, 0:BIG].astype(np.float32)
    wx = xx + (value_noise(rng, 5) - 0.5) * BIG * 0.12
    wy = yy + (value_noise(rng, 5) - 0.5) * BIG * 0.12
    seeds = rng.random((pr.randint(7, 10), 2)) * BIG * 0.9 + BIG * 0.05
    d = np.stack([np.hypot(wx - sx, wy - sy) for sx, sy in seeds])
    d.sort(axis=0)
    edge = (d[1] - d[0]) / BIG  # 0 on a crack
    crack = np.clip(1 - edge / 0.035, 0, 1) ** 1.5  # 1 in the crack, fading out
    halo = np.clip(1 - edge / 0.12, 0, 1) ** 2  # warmth spreading into the crust

    mottle = value_noise(rng, 7) * 0.6 + value_noise(rng, 15) * 0.4
    crust = np.array([0.10, 0.035, 0.02])[None, None, :] * (0.7 + 0.6 * mottle[..., None])
    warm = np.array([0.55, 0.10, 0.02])[None, None, :]
    rgb = crust * (1 - halo[..., None]) + warm * halo[..., None] * 0.8
    # Cracks: yellow-white in the middle, orange, red at the edge.
    hot = np.stack([np.ones_like(crack), 0.35 + 0.6 * crack, 0.05 + 0.45 * crack**2], axis=-1)
    rgb = rgb * (1 - crack[..., None]) + hot * crack[..., None]
    # The rim glows where the crust thins.
    rim = np.clip((1 - inner) * 1.4, 0, 1) * mask
    rgb = rgb * (1 - rim[..., None] * 0.6) + np.array([1.0, 0.32, 0.04])[None, None, :] * rim[..., None] * 0.6
    out = np.dstack([np.clip(rgb, 0, 1), mask]) * 255
    return Image.fromarray(out.astype(np.uint8), 'RGBA').resize((SIZE, SIZE), Image.LANCZOS)


if __name__ == '__main__':
    os.makedirs(out_dir, exist_ok=True)
    for i in range(1, 4):
        tga(lava(3000 + i * 41), os.path.join(out_dir, 'Lava%d.tga' % i))
