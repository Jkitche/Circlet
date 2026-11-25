"""Writes Textures/EliteWing.tga: one dragon wing for the elite marker on the health rings'
level badge (Rings/Vitals.lua). The left wing, spreading up and out from the bottom right
corner (where it meets the badge); the right one is the same texture flipped. Greyscale
with alpha, light, so the game can tint it gold (elite, boss) or silver (rare).

The wing: an arm bone arching up and out to a claw at the top, three finger spars fanning
down from it, and the membrane between them scalloped along its edge; shaded darker toward
the edges with a highlight along the bones.

    python tools/make_wing_texture.py
"""
import math, os, struct
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 64
SS = 4
BIG = SIZE * SS
here = os.path.dirname(os.path.abspath(__file__))
out_dir = os.path.join(os.path.dirname(here), 'Textures')


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


def P(x, y):
    """A point in 0..1 wing space (0,0 top left) to supersampled pixels."""
    return x * BIG, y * BIG


def wing():
    root = (0.92, 0.86)          # where it meets the badge
    wrist = (0.42, 0.14)         # the bend of the wing, up and out
    claw = (0.30, 0.02)
    tips = [(0.04, 0.30), (0.08, 0.58), (0.26, 0.82)]  # finger ends, fanning down
    # Membrane: root -> wrist -> each fingertip, scalloped between the tips.
    outline = [P(*root), P(*wrist)]
    prev = wrist
    for tip in tips:
        # A scallop: a curve bowing in toward the root between the spars.
        mx, my = (prev[0] + tip[0]) / 2, (prev[1] + tip[1]) / 2
        bx, by = mx + (root[0] - mx) * 0.16, my + (root[1] - my) * 0.16
        for t in np.linspace(0, 1, 10)[1:]:
            x = (1 - t) ** 2 * prev[0] + 2 * (1 - t) * t * bx + t ** 2 * tip[0]
            y = (1 - t) ** 2 * prev[1] + 2 * (1 - t) * t * by + t ** 2 * tip[1]
            outline.append(P(x, y))
        prev = tip
    # Back to the root along the bottom, bowing in.
    for t in np.linspace(0, 1, 10)[1:]:
        bx, by = 0.66, 0.74
        x = (1 - t) ** 2 * prev[0] + 2 * (1 - t) * t * bx + t ** 2 * root[0]
        y = (1 - t) ** 2 * prev[1] + 2 * (1 - t) * t * by + t ** 2 * root[1]
        outline.append(P(x, y))

    mem = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(mem).polygon(outline, fill=255)
    mem_soft = mem.filter(ImageFilter.GaussianBlur(SS * 0.6))

    # Shading: lighter near the bones and root, darker toward the scalloped edge.
    depth = np.asarray(mem.filter(ImageFilter.GaussianBlur(SS * 5)), dtype=np.float32) / 255
    shade = 0.45 + 0.4 * np.clip(depth * 1.5, 0, 1)

    bones = Image.new('L', (BIG, BIG), 0)
    d = ImageDraw.Draw(bones)
    w = int(SS * 2.6)
    d.line([P(*root), P(*wrist)], fill=255, width=w + SS)
    d.line([P(*wrist), P(*claw)], fill=255, width=w)
    for tip in tips:
        d.line([P(*wrist), P(*tip)], fill=255, width=max(SS, w - SS))
    d.ellipse([P(claw[0] - 0.03, claw[1] - 0.02), P(claw[0] + 0.03, claw[1] + 0.04)], fill=255)
    bones = bones.filter(ImageFilter.GaussianBlur(SS * 0.5))
    bone = np.asarray(bones, dtype=np.float32) / 255
    # The bones' highlight: bright along their top edge.
    hl = np.asarray(bones.filter(ImageFilter.GaussianBlur(SS * 1.2)), dtype=np.float32) / 255
    hl = np.clip(np.roll(hl, -SS, axis=0) - hl * 0.6, 0, 1)

    value = shade * (1 - bone) + (0.92 * bone) + 0.25 * hl
    # A darker line round the membrane's edge.
    edge = np.asarray(mem_soft, dtype=np.float32) / 255
    rim = np.clip(1 - np.asarray(mem.filter(ImageFilter.GaussianBlur(SS * 1.5)), dtype=np.float32) / 255 * 1.4, 0, 1)
    value *= (1 - 0.5 * rim)
    alpha = np.clip(np.maximum(edge, bone), 0, 1)
    v = np.clip(value, 0, 1) * 255
    rgba = np.dstack([v, v, v, alpha * 255]).astype(np.uint8)
    return Image.fromarray(rgba, 'RGBA').resize((SIZE, SIZE), Image.LANCZOS)


os.makedirs(out_dir, exist_ok=True)
tga(wing(), os.path.join(out_dir, 'EliteWing.tga'))
