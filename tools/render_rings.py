"""Renders each ring's /circ preview from the test mock into PNGs (docs/images/<ring>.png).

The mock records the lines and text a ring draws, so these show the ring itself: its fill,
track, border, segments and text. Game textures (item and spell icons, glows) aren't drawn.

    python3 tools/render_rings.py            # every ring
    python3 tools/render_rings.py quest xp   # just these
Needs: pip install lupa pillow, and the DejaVu fonts.
"""
import math, os, subprocess, sys
from lupa import LuaRuntime
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "tests")
OUT = os.path.join(ROOT, "docs", "images")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SCALE = 3          # pixels per UI unit
BG = (24, 26, 32)  # dark backdrop, like a night zone

# ring -> (slash command, class, seconds to let the preview run before the snapshot, setup lua)
RINGS = {
    "xp":      ("xp", "WARRIOR", 1.6, ""),
    "quest":   ("quest", "WARRIOR", 1.6, ""),
    "pins":    ("pins", "WARRIOR", 1.6, ""),
    "skill":   ("skill", "WARRIOR", 1.6, ""),
    "weapon":  ("weapon", "WARRIOR", 1.6, ""),
    "rep":     ("rep", "WARRIOR", 1.6, ""),
    "pet":     ("pet", "HUNTER", 1.6, ""),
    "ammo":    ("ammo", "HUNTER", 1.6, ""),
    "flight":  ("flight", "WARRIOR", 3.0, ""),
    "timed":   ("timed", "WARRIOR", 3.0, ""),
    "corpse":  ("corpse", "WARRIOR", 2.5, ""),
    "breath":  ("breath", "WARRIOR", 3.0, ""),
    "craft":   ("craft", "WARRIOR", 2.5, ""),
    "gather":  ("gather", "WARRIOR", 1.2, ""),
    "cast":    ("cast", "MAGE", 1.0, ""),
    "totems":  ("totems", "SHAMAN", 2.0, ""),
    "food":    ("food", "WARRIOR", 9.0, ""),
}

PRELUDE = r'''
local cf = CreateFrame
CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end
RegionMethods.SetFont = function(s, path, size) s._size = size end
RegionMethods.SetParent = function(s, p) s._parent = p end
local setPoint = RegionMethods.SetPoint
RegionMethods.SetPoint = function(s, p, rel, rp, x, y)
  setPoint(s, p, rel, rp, x, y)
  if type(rel) == "number" then rel, rp, x, y = nil, p, rel, rp
  elseif type(rp) == "number" then rp, x, y = p, rp, x end
  if type(rel) == "string" then rel = _G[rel] end
  s._anchor = { p = p, rel = rel, rp = rp or p, x = x or 0, y = y or 0 }
end
RegionMethods.SetColorTexture = function(s, r, g, b, a) s._solid = { r, g, b, a or 1 } end
RegionMethods.SetVertexColor = function(s, r, g, b, a) s._vc = { r, g, b, a } end
local cfx = RegionMethods.CreateTexture
RegionMethods.CreateTexture = function(self, ...) local t = cfx(self, ...); t._parent = self; ALL_TEX = ALL_TEX or {}; table.insert(ALL_TEX, t); return t end
RegionMethods.SetAllPoints = function(s, rel) s._anchor = { p = "CENTER", rel = rel, rp = "CENTER", x = 0, y = 0 } end
ERRORS = {}
local function guard(where, fn, ...) local ok, err = pcall(fn, ...)
  if not ok then local k = where .. ": " .. tostring(err); ERRORS[k] = (ERRORS[k] or 0) + 1 end end
function Fire(event, ...) for _, f in ipairs(allFrames) do
  if f._events and f._events[event] and f._scripts.OnEvent then guard("OnEvent " .. event, f._scripts.OnEvent, f, event, ...) end end end
function Adv(seconds) for _ = 1, math.floor(seconds * 30) do NOW = NOW + 1 / 30
  local due = {} for i = #pendingTimers, 1, -1 do if pendingTimers[i].at <= NOW then table.insert(due, table.remove(pendingTimers, i)) end end
  for _, t in ipairs(due) do guard("timer", t.fn) end
  for _, f in ipairs(allFrames) do if f._shown and f._scripts.OnUpdate then guard("OnUpdate", f._scripts.OnUpdate, f, 1 / 30) end end end end
'''

LAYER = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 4}


def visible(obj):
    """Shown, with every parent shown; returns the combined alpha (0 when hidden)."""
    a, o, depth = 1.0, obj, 0
    while o is not None and depth < 30:
        if not o._shown:
            return 0
        a *= o._alpha if o._alpha is not None else 1
        o, depth = o._parent, depth + 1
    return a


def ring_of(obj):
    """The ring frame (one with .geom) an object belongs to."""
    o, depth = obj._parent, 0
    while o is not None and depth < 30:
        if o.geom is not None:
            return o
        o, depth = o._parent, depth + 1
    return None


POINT = {"CENTER": (0, 0), "TOP": (0, 1), "BOTTOM": (0, -1), "LEFT": (-1, 0), "RIGHT": (1, 0),
         "TOPLEFT": (-1, 1), "TOPRIGHT": (1, 1), "BOTTOMLEFT": (-1, -1), "BOTTOMRIGHT": (1, -1)}


class Layout:
    """Works out where regions sit relative to their ring's centre, in UI units."""

    def __init__(self, ring, tostr):
        self.ring, self.tostr, self.cache = tostr(ring), tostr, {}

    def size(self, r):
        if r._kind == "FontString":
            text = clean(str(r._text or ""))
            if not text:
                return 0, 0
            font = ImageFont.truetype(FONT, int((r._size or 12) * SCALE))
            box = ImageDraw.Draw(Image.new("L", (1, 1))).multiline_textbbox((0, 0), text, font=font, align="center")
            return (box[2] - box[0]) / SCALE, (r._size or 12) * (text.count("\n") + 1)
        return r._w or 0, r._h or 0

    def center(self, r, depth=0):
        if r is None or depth > 25:
            return 0, 0
        key = self.tostr(r)
        if key == self.ring:
            return 0, 0
        if key in self.cache:
            return self.cache[key]
        self.cache[key] = (0, 0)  # guards against anchor loops
        a = r._anchor
        rel = (a.rel if a is not None and a.rel is not None else r._parent)
        if a is None:
            c = self.center(rel, depth + 1)
        else:
            rx, ry = self.center(rel, depth + 1)
            rw, rh = self.size(rel) if rel is not None else (0, 0)
            px, py = POINT.get(str(a.rp).upper(), (0, 0))
            sx, sy = POINT.get(str(a.p).upper(), (0, 0))
            w, h = self.size(r)
            c = (rx + px * rw / 2 + (a.x or 0) - sx * w / 2, ry + py * rh / 2 + (a.y or 0) - sy * h / 2)
        self.cache[key] = c
        return c


def clean(text):
    import re
    text = text.replace("|n", "\n")
    return re.sub(r"\|c\w{8}|\|r|\|T[^|]*\|t", "", text)


def snapshot(name):
    slash, cls, wait, setup = RINGS[name]
    lua = LuaRuntime(unpack_returned_tuples=True)
    os.chdir(TESTS)
    lua.execute(open("mock.lua").read())
    lua.execute(PRELUDE)
    lua.execute(f'UnitClass = function() return "{cls.title()}", "{cls}", 1 end')
    subprocess.run([sys.executable, "make_bundle.py"], check=True)
    chunk = lua.eval('function(s) return load(s, "@Circlet.lua") end')(open("bundle.lua").read())
    chunk("Circlet", lua.table())
    lua.execute('Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD"); Adv(1)')
    lua.execute(setup)
    lua.execute(f'SlashCmdList.CIRCLET("{slash}"); Adv({wait})')
    errs = dict(lua.eval("ERRORS"))
    if errs:
        print(f"  {name}: errors {errs}")

    tostr = lua.globals().tostring
    rings = {}  # ring frame -> {"lines": [...], "texts": [...]}
    for l in lua.eval("ALL_LINES").values():
        if l._x1 is None or l._c is None:
            continue
        a = visible(l)
        if a <= 0.02:
            continue
        ring = ring_of(l)
        if ring is None:
            continue
        entry = rings.setdefault(tostr(ring), {"ring": ring, "lines": [], "texts": []})
        entry["lines"].append(l)
        entry.setdefault("alpha", []).append(a)
    for f in lua.eval("ALL_FS").values():
        if not f._text or str(f._text).strip() == "":
            continue
        a = visible(f)
        if a <= 0.02:
            continue
        ring = ring_of(f)
        if ring is not None and tostr(ring) in rings:
            rings[tostr(ring)]["texts"].append((f, a))
    for t in (lua.eval("ALL_TEX") or {}).values():
        if t._solid is None or t._pt is None:
            continue
        if max(t._solid[1], t._solid[2], t._solid[3]) < 0.1:
            continue  # a badge's dark backing: masked to a circle under the icon in game
        a = visible(t)
        if a <= 0.02:
            continue
        ring = ring_of(t)
        if ring is not None and tostr(ring) in rings:
            rings[tostr(ring)].setdefault("solids", []).append((t, a))
    for entry in rings.values():
        lay = Layout(entry["ring"], tostr)
        lines = []
        for l, a in zip(entry["lines"], entry["alpha"]):
            dx, dy = lay.center(l._parent)
            lines.append((l, a, dx, dy))
        entry["lines"] = lines
        entry["texts"] = [(f, a) + lay.center(f) for f, a in entry["texts"]]
        entry["solids"] = [(t, a) + lay.center(t) for t, a in entry.get("solids", [])]
    return rings


def draw_ring(parts):
    lines = parts["lines"]
    ext = max(max(abs(l._x1 + dx), abs(l._x2 + dx), abs(l._y1 + dy), abs(l._y2 + dy)) + (l._t or 1)
              for l, a, dx, dy in lines)
    for t, a, tx, ty in parts.get("solids", []):
        ext = max(ext, abs(tx) + 4, abs(ty) + 4)
    half = ext + 8
    W = int(2 * half * SCALE)
    im = Image.new("RGBA", (W, W), BG + (255,))
    cx = cy = W / 2

    def P(x, y):
        return (cx + x * SCALE, cy - y * SCALE)

    for l, a, dx, dy in sorted(lines, key=lambda t: (LAYER.get(t[0]._layer, 2), t[0]._sub or 0)):
        x1, y1, x2, y2, T = l._x1 + dx, l._y1 + dy, l._x2 + dx, l._y2 + dy, l._t or 1
        c = l._c
        alpha = (c[4] if c[4] is not None else 1) * a
        L = math.hypot(x2 - x1, y2 - y1) or 1
        nx, ny = -(y2 - y1) / L * T / 2, (x2 - x1) / L * T / 2
        poly = [P(x1 + nx, y1 + ny), P(x2 + nx, y2 + ny), P(x2 - nx, y2 - ny), P(x1 - nx, y1 - ny)]
        ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
        ImageDraw.Draw(ov).polygon(poly, fill=(int(c[1] * 255), int(c[2] * 255), int(c[3] * 255), int(alpha * 255)))
        im = Image.alpha_composite(im, ov)

    for t, a, tx, ty in parts.get("solids", []):
        c = t._solid
        vc = t._vc
        r, g, b = c[1] * (vc[1] if vc else 1), c[2] * (vc[2] if vc else 1), c[3] * (vc[3] if vc else 1)
        half = (t._w or 2) / 2
        rot = t._rot or 0
        pts = []
        for px, py in [(-half, -half), (half, -half), (half, half), (-half, half)]:
            x = px * math.cos(rot) - py * math.sin(rot)
            y = px * math.sin(rot) + py * math.cos(rot)
            pts.append(P(tx + x, ty + y))
        ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
        fill = (int(r * 255), int(g * 255), int(b * 255), int(255 * a * (c[4] or 1)))
        if t._mask is not None:  # masked to a circle in game (badge rims)
            (x0, y0), (x1, y1) = P(tx - half, ty + half), P(tx + half, ty - half)
            ImageDraw.Draw(ov).ellipse([x0, y0, x1, y1], fill=fill)
        else:
            ImageDraw.Draw(ov).polygon(pts, fill=fill)
        im = Image.alpha_composite(im, ov)

    d = ImageDraw.Draw(im)
    for f, a, tx, ty in parts["texts"]:
        size = (f._size or 12) * SCALE
        font = ImageFont.truetype(FONT, int(size))
        x, y = P(tx, ty)
        tc = f._tc
        col = tuple(int(v * 255) for v in (tc[1], tc[2], tc[3])) if tc else (255, 255, 255)
        text = clean(str(f._text))
        d.multiline_text((x, y), text, font=font, fill=col + (int(255 * a),), anchor="mm", align="center",
                         stroke_width=max(1, int(size / 10)), stroke_fill=(0, 0, 0, int(255 * a)))
    return im


def render(name):
    rings = snapshot(name)
    if not rings:
        print(f"  {name}: nothing on screen")
        return None
    ims = [draw_ring(p) for p in rings.values()]
    h = max(i.height for i in ims)
    gap = 12
    out = Image.new("RGBA", (sum(i.width for i in ims) + gap * (len(ims) - 1), h), BG + (255,))
    x = 0
    for i in ims:
        out.paste(i, (x, (h - i.height) // 2))
        x += i.width + gap
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    out.convert("RGB").save(path)
    print(f"  {name}: {path} ({len(ims)} ring{'s' if len(ims) > 1 else ''})")
    return path


if __name__ == "__main__":
    for n in sys.argv[1:] or RINGS:
        render(n)
