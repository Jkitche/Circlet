"""Writes the health rings' effect textures (Rings/Health/Fx/), white with alpha so the
game tints them:

  Textures/GlowRing.tga   a soft halo band, its peak at 0.70 of the half-width (so drawn
                          2R/0.70 across it sits on a ring of radius R)
  Textures/Cracks.tga     cracks across a band at the same radius (death)
  Textures/Shield.tga     a heater shield with a highlight (block)

    python tools/make_vitals_fx.py
"""
import math, os, random, struct
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

here = os.path.dirname(os.path.abspath(__file__))
out_dir = os.path.join(os.path.dirname(here), 'Textures')
SS = 4


def tga(img, path):
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


def white(alpha, size):
    """A white RGBA image of size from an L alpha image (supersampled)."""
    a = alpha.resize((size, size), Image.LANCZOS)
    img = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    img.putalpha(a)
    return img


def glow_ring():
    S = 256
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    c = (S - 1) / 2
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (S / 2)
    a = np.exp(-((r - 0.70) / 0.11) ** 2)
    a[r > 0.99] *= np.clip((1 - r[r > 0.99]) * 100, 0, 1)
    return Image.fromarray(np.dstack([np.full((S, S, 3), 255, np.uint8), (a * 255).astype(np.uint8)]), 'RGBA')


def cracks():
    S = 256
    B = S * SS
    c = B / 2
    img = Image.new('L', (B, B), 0)
    d = ImageDraw.Draw(img)
    rng = random.Random(7)
    R = 0.70 * B / 2
    for i in range(14):
        a = i / 14 * 2 * math.pi + rng.uniform(-0.15, 0.15)
        r0 = R * rng.uniform(0.80, 0.9)
        x, y = c + math.cos(a) * r0, c + math.sin(a) * r0
        pts = [(x, y)]
        ang = a + rng.uniform(-0.4, 0.4)
        steps = rng.randint(4, 7)
        for k in range(steps):
            ang += rng.uniform(-0.6, 0.6)
            step = R * rng.uniform(0.04, 0.07)
            x, y = x + math.cos(ang) * step, y + math.sin(ang) * step
            pts.append((x, y))
            if rng.random() < 0.35:  # a branch
                ba = ang + rng.choice((-1, 1)) * rng.uniform(0.6, 1.1)
                bx, by = x + math.cos(ba) * step * 0.8, y + math.sin(ba) * step * 0.8
                d.line([(x, y), (bx, by)], fill=200, width=SS)
        d.line(pts, fill=255, width=int(SS * 1.6), joint='curve')
    img = img.filter(ImageFilter.GaussianBlur(SS * 0.4))
    return white(img, S)


def shield():
    S = 64
    B = S * SS
    c = B / 2
    outline = [(B * 0.18, B * 0.14), (c, B * 0.08), (B * 0.82, B * 0.14), (B * 0.80, B * 0.50)]
    for t in np.linspace(0, 1, 20):
        outline.append((B * 0.80 - (B * 0.30) * t, B * 0.50 + B * 0.42 * math.sin(t * math.pi / 2)))
    for t in np.linspace(1, 0, 20):
        outline.append((B * 0.20 + (B * 0.30) * t, B * 0.50 + B * 0.42 * math.sin(t * math.pi / 2)))
    outline.append((B * 0.18, B * 0.14))
    base = Image.new('L', (B, B), 0)
    ImageDraw.Draw(base).polygon(outline, fill=150)
    # Shading: brighter on the left half, a rim and a boss.
    d = ImageDraw.Draw(base)
    d.line(outline, fill=255, width=int(SS * 2.5))
    left = Image.new('L', (B, B), 0)
    ImageDraw.Draw(left).polygon([(B * 0.18, B * 0.14), (c, B * 0.08), (c, B * 0.92), (B * 0.20, B * 0.5)], fill=60)
    arr = np.clip(np.asarray(base, dtype=np.int32) + np.asarray(left, dtype=np.int32) * (np.asarray(base) > 0), 0, 255)
    img = Image.fromarray(arr.astype(np.uint8), 'L')
    ImageDraw.Draw(img).ellipse((c - B * 0.07, B * 0.40, c + B * 0.07, B * 0.54), fill=255)
    return white(img.filter(ImageFilter.GaussianBlur(SS * 0.3)), S)


os.makedirs(out_dir, exist_ok=True)
tga(glow_ring(), os.path.join(out_dir, 'GlowRing.tga'))
tga(cracks(), os.path.join(out_dir, 'Cracks.tga'))
tga(shield(), os.path.join(out_dir, 'Shield.tga'))
