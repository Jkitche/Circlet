"""Writes the debuff ring effect textures (Rings/Debuffs.lua): Textures/DebuffFx<Kind>.tga, one
per kind of debuff, and Textures/Blank.tga (fully transparent, for the types an effect isn't
for). White with alpha: the game tints them with the debuff type's color.

The effect texture is drawn 1.5x the ring's size, centered on it, so the ring's outer edge
sits at 1/1.5 of the texture's half-width (about 85 px of 128) with the band just inside;
effects sit on and around the band.

    python tools/make_debuff_fx.py
"""
import math, os, random, struct
from PIL import Image, ImageDraw, ImageFilter

SIZE = 256
SS = 4                      # supersampling
BIG = SIZE * SS
C = BIG / 2
R = SIZE / 2 / 1.5 * SS     # the ring's outer edge, in supersampled pixels
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


def canvas():
    return Image.new('L', (BIG, BIG), 0)


def finish(alpha, blur=0):
    if blur:
        alpha = alpha.filter(ImageFilter.GaussianBlur(blur * SS))
    alpha = alpha.resize((SIZE, SIZE), Image.LANCZOS)
    img = Image.new('RGBA', (SIZE, SIZE), (255, 255, 255, 0))
    img.putalpha(alpha)
    return img


def at(angle_deg, radius):
    """Point at angle (clockwise from the top) and radius from the centre."""
    a = math.radians(angle_deg)
    return C + math.sin(a) * radius, C - math.cos(a) * radius


def poison(rng):
    a = canvas(); d = ImageDraw.Draw(a)
    for i in range(18):
        ang = i * 20 + rng.uniform(-6, 6)
        rad = R * rng.uniform(0.86, 1.12)
        s = rng.uniform(3.5, 9) * SS
        x, y = at(ang, rad)
        d.ellipse((x - s, y - s, x + s, y + s), fill=55, outline=230, width=int(1.4 * SS))
        h = s * 0.32
        d.ellipse((x - s * 0.45 - h, y - s * 0.45 - h, x - s * 0.45 + h, y - s * 0.45 + h), fill=255)
    return finish(a)


def curse(rng):
    a = canvas(); d = ImageDraw.Draw(a)
    for arm in range(3):
        start = arm * 120
        steps = 90
        for k in range(steps):
            t = k / steps
            ang = start + t * 130
            rad = R * (1.22 - 0.36 * t)
            w = (1 - t) * 7 * SS + SS
            x, y = at(ang, rad)
            v = int(60 + 180 * (1 - t))
            d.ellipse((x - w, y - w, x + w, y + w), fill=v)
    soft = finish(a, blur=1.5)
    b = canvas(); d = ImageDraw.Draw(b)
    for i in range(14):
        x, y = at(rng.uniform(0, 360), R * rng.uniform(0.8, 1.25))
        s = rng.uniform(1.2, 2.6) * SS
        d.ellipse((x - s, y - s, x + s, y + s), fill=255)
    return Image.alpha_composite(soft, finish(b))


def star(d, x, y, s, v):
    t = s * 0.22
    d.polygon([(x, y - s), (x + t, y - t), (x + s, y), (x + t, y + t), (x, y + s), (x - t, y + t), (x - s, y), (x - t, y - t)], fill=v)


def magic(rng):
    glow = canvas(); dg = ImageDraw.Draw(glow)
    a = canvas(); d = ImageDraw.Draw(a)
    for i in range(12):
        ang = i * 30 + rng.uniform(-8, 8)
        x, y = at(ang, R * rng.uniform(0.84, 1.2))
        s = rng.uniform(5, 13) * SS
        star(d, x, y, s, 255)
        g = s * 0.6
        dg.ellipse((x - g, y - g, x + g, y + g), fill=140)
    for i in range(16):
        x, y = at(rng.uniform(0, 360), R * rng.uniform(0.85, 1.22))
        s = rng.uniform(0.8, 1.8) * SS
        d.ellipse((x - s, y - s, x + s, y + s), fill=230)
    return Image.alpha_composite(finish(glow, blur=3), finish(a))


def disease(rng):
    blobs = canvas(); db = ImageDraw.Draw(blobs)
    for i in range(11):
        x, y = at(i * 33 + rng.uniform(-10, 10), R * rng.uniform(0.9, 1.1))
        s = rng.uniform(6, 12) * SS
        db.ellipse((x - s, y - s, x + s, y + s), fill=150)
    dots = canvas(); dd = ImageDraw.Draw(dots)
    for i in range(30):
        x, y = at(rng.uniform(0, 360), R * rng.uniform(0.82, 1.28))
        s = rng.uniform(1.2, 3.2) * SS
        dd.ellipse((x - s, y - s, x + s, y + s), fill=235, outline=120, width=SS)
    return Image.alpha_composite(finish(blobs, blur=3.5), finish(dots))


def bleed(rng, angles=(128, 150, 166, 184, 203, 226), specks=True):
    a = canvas(); d = ImageDraw.Draw(a)
    for ang in angles:
        x, y = at(ang + rng.uniform(-4, 4), R * 0.97)
        ln = rng.uniform(10, 22) * SS
        w = rng.uniform(2.2, 3.6) * SS
        # A run down from the band ending in a round drop.
        d.polygon([(x - w * 0.5, y), (x + w * 0.5, y), (x + w * 0.35, y + ln), (x - w * 0.35, y + ln)], fill=240)
        d.ellipse((x - w, y + ln - w, x + w, y + ln + w * 1.2), fill=255)
    for i in range(14 if specks else 0):
        x, y = at(rng.uniform(100, 260), R * rng.uniform(1.02, 1.3))
        s = rng.uniform(1, 2.4) * SS
        d.ellipse((x - s, y - s, x + s, y + s), fill=220)
    return finish(a)


def glow(rng):
    """A soft halo on and around the band."""
    a = canvas(); d = ImageDraw.Draw(a)
    w = R * 0.16
    d.ellipse((C - R - w, C - R - w, C + R + w, C + R + w), outline=200, width=int(w * 2))
    return finish(a, blur=7)


def small_stars(rng):
    a = canvas(); d = ImageDraw.Draw(a)
    glow_l = canvas(); dg = ImageDraw.Draw(glow_l)
    for i in range(16):
        x, y = at(i * 22.5 + 11 + rng.uniform(-6, 6), R * rng.uniform(0.78, 1.3))
        s = rng.uniform(2.5, 7) * SS
        star(d, x, y, s, 255)
        dg.ellipse((x - s * 0.7, y - s * 0.7, x + s * 0.7, y + s * 0.7), fill=120)
    return Image.alpha_composite(finish(glow_l, blur=2), finish(a))


def runes(rng):
    """Arcane glyphs in a band outside the ring, between two thin circles."""
    a = canvas(); d = ImageDraw.Draw(a)
    lw = int(1.1 * SS)
    for rr in (R * 1.12, R * 1.36):
        d.ellipse((C - rr, C - rr, C + rr, C + rr), outline=150, width=lw)
    n = 14
    for i in range(n):
        cx, cy = at(i * 360 / n, R * 1.24)
        h = R * 0.085
        pts = [(cx + rng.uniform(-h, h), cy + rng.uniform(-h, h)) for _ in range(4)]
        d.line(pts, fill=255, width=int(1.4 * SS), joint='curve')
        if rng.random() < 0.6:
            q = h * 0.35
            px, py = cx + rng.uniform(-h, h) * 0.6, cy + rng.uniform(-h, h) * 0.6
            d.ellipse((px - q, py - q, px + q, py + q), outline=255, width=int(1.2 * SS))
    return finish(a)


def rise(rng, n=22, lo=0.85, hi=1.2, smin=1.5, smax=4.2, ring=True):
    """Small bubbles or motes all round the ring (the animation carries them upward)."""
    a = canvas(); d = ImageDraw.Draw(a)
    for i in range(n):
        x, y = at(rng.uniform(0, 360), R * rng.uniform(lo, hi))
        s = rng.uniform(smin, smax) * SS
        if ring:
            d.ellipse((x - s, y - s, x + s, y + s), fill=40, outline=235, width=int(1.1 * SS))
        else:
            d.ellipse((x - s, y - s, x + s, y + s), fill=230)
    return finish(a, blur=0.3 if ring else 0.8)


def thin_wisps(rng):
    a = canvas(); d = ImageDraw.Draw(a)
    for arm in range(5):
        start = arm * 72 + rng.uniform(-10, 10)
        steps = 70
        for k in range(steps):
            t = k / steps
            x, y = at(start - t * 90, R * (0.9 + 0.38 * t))
            w = (1 - t) * 2.6 * SS + 0.6 * SS
            d.ellipse((x - w, y - w, x + w, y + w), fill=int(70 + 170 * (1 - t)))
    return finish(a, blur=0.8)


def flies(rng):
    a = canvas(); d = ImageDraw.Draw(a)
    for cluster in range(5):
        base = cluster * 72 + rng.uniform(-15, 15)
        for i in range(5):
            x, y = at(base + rng.uniform(-10, 10), R * rng.uniform(1.08, 1.32))
            s = rng.uniform(1.1, 1.9) * SS
            d.ellipse((x - s, y - s * 0.8, x + s, y + s * 0.8), fill=255)
            # wings
            d.ellipse((x - s * 1.6, y - s * 1.9, x - s * 0.2, y - s * 0.5), fill=110)
            d.ellipse((x + s * 0.2, y - s * 1.9, x + s * 1.6, y - s * 0.5), fill=110)
    return finish(a)


def splatter(rng):
    a = canvas(); d = ImageDraw.Draw(a)
    for i in range(26):
        x, y = at(rng.uniform(0, 360), R * rng.uniform(0.98, 1.34))
        s = rng.uniform(0.9, 3.2) * SS
        d.ellipse((x - s, y - s, x + s, y + s), fill=230)
    return finish(a)


os.makedirs(out_dir, exist_ok=True)
ART = {
    'Glow': glow,
    'MagicStars': magic, 'MagicStarsSmall': small_stars, 'MagicRunes': runes,
    'PoisonBubbles': poison, 'Rise': rise,
    'CurseWisps': curse, 'CurseWispsThin': thin_wisps,
    'Motes': lambda rng: rise(rng, n=26, lo=0.8, hi=1.3, smin=1.2, smax=2.8, ring=False),
    'DiseaseSpores': disease, 'Flies': flies,
    'Drip': bleed, 'DripB': lambda rng: bleed(rng, angles=(118, 140, 158, 176, 195, 214, 236), specks=False),
    'Splatter': splatter,
}
for name, fn in ART.items():
    tga(fn(random.Random(name)), os.path.join(out_dir, 'DebuffFx%s.tga' % name))
tga(Image.new('RGBA', (8, 8), (0, 0, 0, 0)), os.path.join(out_dir, 'Blank.tga'))
