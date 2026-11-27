# Health rings, hidden values eased by the game (Rings/Health/Bands.lua, eased bands): each piece of the
# band is a texture masked to the ring's shape, to its own slice (two half-planes through the
# centre), and by a half-plane pinned to the end of an invisible status bar the game eases. This
# takes what the ring sets up (as the mock records it), rasterizes it, and compares it with the
# true arc for several fill values, shapes and directions; also how far the moving edge is from
# a cut towards the centre. Masks behave as the game showed (/circ masktest): SetRotation turns
# them counter-clockwise about their middle, the image clipped to its own square as it turns (so
# a mask reaches only half its size from its middle), and texture coordinates are ignored.
import math, sys
src = open('vitals_test.py').read()
head = src[:src.index("NSX = lua.table()")]
exec(head)
lua.execute('''
-- Record geometry calls.
local RM = RegionMethods
RM.SetPoint = function(s, p, rel, rp, x, y) s._pt = { p, rp, x or 0, y or 0, rel } end
RM.SetSize = function(s, w, h) s._w, s._h = w, h end
RM.SetOrientation = function(s, o) s._orient = o end
RM.SetReverseFill = function(s, r) s._rev = r end
RM.SetMinMaxValues = function(s, a, b) s._min, s._max = a, b end
RM.SetValue = function(s, v, mode) s._val = v; s._mode = mode end
RM.SetRotation = function(s, r) s._rot = r end
RM.SetTexCoord = function(s, ...) s._tc = { ... } end
-- As the game: a texture takes at most three masks.
RM.AddMaskTexture = function(s, m)
  s._masks = (s._masks or 0) + 1
  if s._masks > 3 then error("Texture:AddMaskTexture(): Texture already has the maximum number of mask textures (3)") end
end
RM.CreateMaskTexture = function(self) local m = RM.CreateTexture(self); m._kind = "Mask"; return m end
RM.GetStatusBarTexture = function(s) s._fillTex = s._fillTex or RM.CreateTexture(s); s._fillTex._bar = s; return s._fillTex end
Enum.StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }
''')
NSX = lua.table(); lua.globals().NS = NSX
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
UNITS.player = { hp = 900, max = 1000, power = 300, pmax = 1200, ptype = 0, token = "MANA", name = "Jaina", level = 20, player = true }
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
CircletDB.playerHpShow = "always"; CircletDB.playerHpPower = false; SECRET = true
function Ring(key) for _, f in ipairs(allFrames) do if f.sqKey == key and f._shown and f._alpha > 0 then return f end end end
local function M(m) return { x = m._pt[3], y = m._pt[4], rot = m._rot or 0, rel = m._pt[5], at = m._pt[2], w = m._w } end
function Capture()
  local f = Ring("playerHp"); local v = f.vit; local out = {}
  out.R, out.T = f.geom.R, f.geom.T
  for i = 1, v.eh.n or 0 do
    local e = v.eh[i]
    local b = e.bar
    local edge = M(e.masks.edge)
    table.insert(out, { from = M(e.masks.from), to = M(e.masks.to), edgeRot = edge.rot, edgeW = edge.w, edgeAt = edge.at,
      edgeOnFill = (edge.rel == b._fillTex), masks = e.tex._masks or 0, bx = b._pt[3], by = b._pt[4], bw = b._w, bh = b._h,
      orient = b._orient, rev = b._rev and true or false, max = b._max, val = b._val and b._val.v or -1, mode = b._mode })
  end
  return out
end
''')


def capture():
    t = lua.eval('Capture()')
    out = {'R': t['R'], 'T': t['T'], 'pieces': []}
    i = 1
    while t[i] is not None:
        p = dict(t[i])
        for k in ('from', 'to'):
            p[k] = dict(p[k])
        out['pieces'].append(p); i += 1
    return out


def solid(px, py, cx, cy, rot, size):
    # Textures/HalfPlane (solid left half) on a square `size` across centred on (cx, cy), turned
    # counter-clockwise by rot: the point, turned back by rot, must land inside the image (the
    # turned image is clipped to its square) and on its left half.
    dx, dy = px - cx, py - cy
    c, s_ = math.cos(-rot), math.sin(-rot)
    ix, iy = dx * c - dy * s_, dx * s_ + dy * c
    h = size / 2
    return abs(ix) <= h and abs(iy) <= h and ix <= 0


def lead(p):
    v = max(0.0, min(1.0, p['val'] / p['max']))
    x, y, w, h = p['bx'], p['by'], p['bw'], p['bh']
    if p['orient'] == 'HORIZONTAL':
        return (x + w - w * v, y + h / 2) if p['rev'] else (x + w * v, y + h / 2)
    return (x + w / 2, y + h - h * v) if p['rev'] else (x + w / 2, y + h * v)


def render(cap, start, sweep, rev):
    R, T = cap['R'], cap['T']; rin, rout = R - T / 2, R + T / 2
    S = 3; N = int((rout + 4) * 2 * S)
    bad = band = 0
    v = cap['pieces'][0]['val'] / cap['pieces'][0]['max']
    for j in range(N):
        for i in range(N):
            x = (i + 0.5) / S - N / (2 * S); y = N / (2 * S) - (j + 0.5) / S
            r = math.hypot(x, y)
            if r < rin or r > rout: continue
            turn = (math.atan2(x, y) / (2 * math.pi)) % 1
            d = ((start + sweep - turn) if rev else (turn - start)) % 1
            if d > sweep: continue
            band += 1
            want = d / sweep <= v
            covered = False
            for p in cap['pieces']:
                ex, ey = lead(p)
                if (solid(x, y, p['from']['x'], p['from']['y'], p['from']['rot'], p['from']['w'])
                        and solid(x, y, p['to']['x'], p['to']['y'], p['to']['rot'], p['to']['w'])
                        and solid(x, y, ex, ey, p['edgeRot'], p['edgeW'])):
                    covered = True; break
            if covered != want: bad += 1
    return bad, band


def edge_angle(cap, start, sweep, rev):
    # The moving edge's line vs. the true radial line where it crosses the band's centreline.
    v = cap['pieces'][0]['val'] / cap['pieces'][0]['max']
    turn = (start + sweep - v * sweep) if rev else (start + v * sweep)
    cx, cy = cap['R'] * math.sin(2 * math.pi * turn), cap['R'] * math.cos(2 * math.pi * turn)
    for p in cap['pieces']:
        if (solid(cx, cy, p['from']['x'], p['from']['y'], p['from']['rot'], p['from']['w'])
                and solid(cx, cy, p['to']['x'], p['to']['y'], p['to']['rot'], p['to']['w'])):
            line = p['edgeRot'] + math.pi / 2  # the half-plane's edge runs at rot + 90 degrees
            radial = math.atan2(cy, cx)
            return abs((math.degrees(line - radial) + 90) % 180 - 90)
    return -1


for shape, rot, rev in [('ring', 180, False), ('ring', 0, False), ('ring', 180, True), ('arc', 180, False), ('ring', 33, False)]:
    for hp in (900, 610, 270):
        lua.execute(f'CircletDB.playerHpShape = "{shape}"; CircletDB.playerHpRotation = {rot}; '
                    f'CircletDB.playerHpReverse = {"true" if rev else "false"}; UNITS.player.hp = {hp}; '
                    f'Fire("UNIT_HEALTH", "player"); Advance(0.3)')
        cap = capture()
        g = lua.eval('Ring("playerHp").geom')
        bad, band = render(cap, g['start'] % 1, g['sweep'], bool(g['reverse']))
        ang = edge_angle(cap, g['start'] % 1, g['sweep'], bool(g['reverse']))
        mode = sorted(set(p['mode'] for p in cap['pieces']))
        pinned = all(p['edgeOnFill'] for p in cap['pieces'])
        most = max(p['masks'] for p in cap['pieces'])
        print(f"{shape} rot {rot} {'ccw' if rev else 'cw'} hp {hp / 10:.0f}%: {len(cap['pieces'])} pieces, "
              f"{'eased' if mode == [1] else 'set at once'}, edge pinned to the bar: {pinned}, masks {most}, "
              f"off by {100 * bad / max(band, 1):.1f}% of the band, edge {ang:.1f} deg from radial")
print("ERRORS:", dict(lua.eval("ERRORS")))
