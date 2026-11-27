"""Writes the rock sprites for the weapon imbue ring's Rockbiter animation (Rings/Class/Shaman/Imbue.lua):
Textures/Rock1.tga .. Rock4.tga, irregular shaded stones on a transparent background, lit
from the top left, in greys and browns (the ring draws them untinted, or barely tinted).

Each stone: a jagged outline (a polygon with jittered corners, softened), a height field
(a dome plus layered value noise for lumps and pits, a few cracks), shaded by its normals
against a light from the top left, with ambient occlusion toward the edge, flecks of
lighter mineral and a darker rim. Supersampled, then scaled down for smooth edges.

    python tools/make_rock_textures.py
"""

import math, os, random, struct
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 64  # in game
SS = 4  # supersampling
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


def value_noise(rng, cells):
    """Smooth noise in [0, 1] at BIG x BIG: random values on a cells x cells grid, bicubic."""
    grid = rng.random((cells + 1, cells + 1)).astype(np.float32)
    img = Image.fromarray((grid * 255).astype(np.uint8), 'L').resize((BIG, BIG), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255


def rock(seed, base):
    rng = np.random.default_rng(seed)
    pr = random.Random(seed)
    c = BIG / 2
    # Outline: a jagged polygon, wider than tall now and then.
    n = pr.randint(7, 11)
    rx, ry = BIG * pr.uniform(0.42, 0.47), BIG * pr.uniform(0.36, 0.45)
    tilt = pr.uniform(0, math.pi)
    pts = []
    for i in range(n):
        a = i / n * 2 * math.pi + pr.uniform(-0.25, 0.25)
        r = pr.uniform(0.72, 1.0)
        x, y = math.cos(a) * rx * r, math.sin(a) * ry * r
        pts.append((c + x * math.cos(tilt) - y * math.sin(tilt), c + x * math.sin(tilt) + y * math.cos(tilt)))
    mask_img = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(mask_img).polygon(pts, fill=255)
    mask_img = mask_img.filter(ImageFilter.GaussianBlur(SS * 0.7))
    mask = np.asarray(mask_img, dtype=np.float32) / 255

    # Height: distance in from the edge (a rounded dome), plus lumps and pits.
    inside = (
        np.asarray(
            mask_img.point(lambda v: 255 if v > 127 else 0).filter(ImageFilter.GaussianBlur(SS * 7)), dtype=np.float32
        )
        / 255
    )
    h = inside**0.6
    h += 0.30 * (value_noise(rng, 4) - 0.5) + 0.14 * (value_noise(rng, 9) - 0.5) + 0.04 * (value_noise(rng, 19) - 0.5)
    # Facets: a couple of flat planes cut across it (chipped faces).
    yy, xx = np.mgrid[0:BIG, 0:BIG].astype(np.float32) / BIG
    for _ in range(pr.randint(1, 3)):
        a = pr.uniform(0, 2 * math.pi)
        d = pr.uniform(0.15, 0.35)
        plane = (np.cos(a) * (xx - 0.5) + np.sin(a) * (yy - 0.5)) - d
        h = np.where(plane > 0, h - plane * 0.9, h)

    # Light from the top left (and toward the viewer).
    gy, gx = np.gradient(h * BIG * 0.22)
    nx, ny, nz = -gx, -gy, np.ones_like(h)
    ln = np.sqrt(nx**2 + ny**2 + nz**2)
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    L = np.array([-0.55, -0.6, 0.58])
    L = L / np.linalg.norm(L)
    diffuse = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
    shade = 0.18 + 1.05 * diffuse**1.2
    shade *= 0.55 + 0.45 * np.clip(inside * 1.6, 0, 1)  # occlusion toward the edge

    # Color: the base stone, mottled, with light mineral flecks and dark pits.
    mottle = value_noise(rng, 9)
    col = np.array(base, dtype=np.float32)[None, None, :] * (0.82 + 0.3 * mottle[..., None])
    flecks = (rng.random((BIG, BIG)) > 0.99965).astype(np.float32)
    flecks = (
        np.asarray(Image.fromarray((flecks * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)), dtype=np.float32)
        / 255
    )
    col = col * (1 - flecks[..., None] * 0.35) + flecks[..., None] * 0.35 * np.array([0.9, 0.86, 0.78])
    pits = np.clip((value_noise(rng, 17) - 0.78) * 3, 0, 1)
    col *= 1 - 0.45 * pits[..., None]
    # A crack or two.
    crack = Image.new('L', (BIG, BIG), 0)
    d = ImageDraw.Draw(crack)
    for _ in range(pr.randint(1, 2)):
        x, y = c + pr.uniform(-0.2, 0.2) * BIG, c + pr.uniform(-0.2, 0.2) * BIG
        a = pr.uniform(0, 2 * math.pi)
        line = [(x, y)]
        for _ in range(6):
            a += pr.uniform(-0.6, 0.6)
            x += math.cos(a) * BIG * 0.05
            y += math.sin(a) * BIG * 0.05
            line.append((x, y))
        d.line(line, fill=255, width=SS)
    crack = np.asarray(crack.filter(ImageFilter.GaussianBlur(SS * 0.5)), dtype=np.float32) / 255
    col *= 1 - 0.4 * crack[..., None]

    rgb = np.clip(col * shade[..., None], 0, 1)
    # A darker rim where the edge falls away.
    rim = np.clip(1 - inside * 3, 0, 1)
    rgb *= 1 - 0.35 * rim[..., None]
    out = np.dstack([rgb, mask]) * 255
    img = Image.fromarray(out.astype(np.uint8), 'RGBA').resize((SIZE, SIZE), Image.LANCZOS)
    return img


BASES = [
    (0.55, 0.47, 0.38),  # warm brown
    (0.50, 0.49, 0.47),  # grey granite
    (0.58, 0.44, 0.30),  # sandstone
    (0.42, 0.38, 0.34),  # dark basalt-brown
]
os.makedirs(out_dir, exist_ok=True)
for i, base in enumerate(BASES, 1):
    tga(rock(1000 + i * 17, base), os.path.join(out_dir, 'Rock%d.tga' % i))
