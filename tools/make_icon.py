"""Draws Circlet's logo: three nested progress rings (XP, quest, skill) on a dark tile.
python3 tools/make_icon.py  ->  docs/images/logo.png (512x512)"""
import math, os
from PIL import Image, ImageDraw, ImageFilter

SS = 4                      # supersampling
N = 512 * SS
C = N / 2
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "images", "logo.png")

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def arc(img, r, w, start, frac, c0, c1, steps=720):
    """A thick arc from `start` degrees (0 = bottom, clockwise), `frac` of the circle,
    colour fading c0 -> c1 along it. Its starting end is cut straight across, as the game
    draws it; the head is rounded."""
    d = ImageDraw.Draw(img)
    n = max(2, int(steps * frac))
    ri, ro = r - w / 2, r + w / 2
    def pt(rad, t):
        a = math.radians(start + 360 * frac * t)
        return (C - math.sin(a) * rad, C + math.cos(a) * rad)
    for i in range(n):
        t0, t1 = i / n, min(1, (i + 1.6) / n)  # overlap a little so the quads leave no seams
        d.polygon([pt(ri, t0), pt(ro, t0), pt(ro, t1), pt(ri, t1)], fill=lerp(c0, c1, i / n) + (255,))
    x, y = pt(r, 1)
    d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=c1 + (255,))

def ring_track(img, r, w, col):
    d = ImageDraw.Draw(img)
    d.ellipse([C - r - w / 2, C - r - w / 2, C + r + w / 2, C + r + w / 2], outline=col + (255,), width=int(w))

img = Image.new("RGBA", (N, N), (0, 0, 0, 0))

# Tile: rounded square, deep blue-violet with a soft radial glow.
tile = Image.new("RGBA", (N, N), (0, 0, 0, 0))
m = 18 * SS
ImageDraw.Draw(tile).rounded_rectangle([m, m, N - m, N - m], radius=96 * SS, fill=(22, 20, 34, 255))
glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([C - 200 * SS, C - 200 * SS, C + 200 * SS, C + 200 * SS], fill=(70, 50, 120, 150))
glow = glow.filter(ImageFilter.GaussianBlur(70 * SS))
mask = tile.split()[3]
tile = Image.alpha_composite(tile, Image.composite(glow, Image.new("RGBA", (N, N)), mask))
img = Image.alpha_composite(img, tile)

rings = [  # radius, width, fraction, colour start, colour end
    (162, 42, 0.78, (95, 40, 120), (190, 80, 230)),    # XP: purple
    (108, 36, 0.62, (150, 110, 10), (255, 205, 40)),   # quest: gold (segmented)
    (60, 30, 0.42, (30, 110, 45), (90, 220, 100)),     # skill: green
]
START = 180  # Circlet's default rotation: fill starts at the top

layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
for r, w, frac, c0, c1 in rings:
    r, w = r * SS, w * SS
    ring_track(layer, r, w + 10 * SS, (5, 5, 8))          # black border
    ring_track(layer, r, w, (34, 32, 46))                 # empty track
    arc(layer, r, w, START, frac, c0, c1)
    if c0 == (150, 110, 10):  # notch the quest ring into segments, like the segmented style
        d = ImageDraw.Draw(layer)
        for k in range(12):
            a = math.radians(START + 30 * k)
            dx, dy = -math.sin(a), math.cos(a)
            d.line([(C + dx * (r - w / 2 - 2), C + dy * (r - w / 2 - 2)), (C + dx * (r + w / 2 + 2), C + dy * (r + w / 2 + 2))],
                   fill=(5, 5, 8, 255), width=int(7 * SS))
# Rested band ahead of the XP fill.
arc(layer, 162 * SS, 42 * SS, START + 360 * 0.78, 0.09, (45, 85, 150), (70, 120, 200), 200)
arc(layer, 162 * SS, 42 * SS, START, 0.78, (95, 40, 120), (190, 80, 230))  # XP on top of the band's cap

# Soft shadow under the rings.
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
shadow.paste((0, 0, 0, 170), mask=layer.split()[3])
shadow = shadow.filter(ImageFilter.GaussianBlur(8 * SS))
img = Image.alpha_composite(img, shadow)
img = Image.alpha_composite(img, layer)

# Sparkle at the head of the XP ring.
a = math.radians(START + 360 * 0.78)
sx, sy = C - math.sin(a) * 162 * SS, C + math.cos(a) * 162 * SS
spark = Image.new("RGBA", (N, N), (0, 0, 0, 0))
sd = ImageDraw.Draw(spark)
sd.ellipse([sx - 34 * SS, sy - 34 * SS, sx + 34 * SS, sy + 34 * SS], fill=(255, 230, 255, 120))
spark = spark.filter(ImageFilter.GaussianBlur(14 * SS))
sd = ImageDraw.Draw(spark)
for ang, ln in [(0, 40), (90, 40), (45, 18), (135, 18)]:
    t = math.radians(ang)
    dx, dy = math.cos(t) * ln * SS, math.sin(t) * ln * SS
    sd.polygon([(sx - dx, sy - dy), (sx + dy * 0.12, sy - dx * 0.12), (sx + dx, sy + dy), (sx - dy * 0.12, sy + dx * 0.12)], fill=(255, 250, 255, 255))
img = Image.alpha_composite(img, spark)

img = img.resize((512, 512), Image.LANCZOS)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT)
print(OUT)
