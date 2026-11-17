import os
from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
hooksecurefunc = hooksecurefunc or function() end
C_Spell = C_Spell or {}; C_Spell.GetSpellName = function(id) return ({[2575]="Mining",[2366]="Herb Gathering",[8613]="Skinning",[7620]="Fishing",[2656]="Smelting"})[id] end
C_Item = C_Item or {}; C_Item.GetItemIconByID = function(id) return "icon"..id end
LOOT_ITEM_SELF = "You receive loot: %s."; LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
CAST = nil
function UnitCastingInfo() if CAST then return CAST.name, "", 0, CAST.s * 1000, CAST.e * 1000, false, "g", false, CAST.id end end
function UnitChannelInfo() end
ALL_TEX = {}
local ct = RegionMethods.CreateTexture
RegionMethods.CreateTexture = function(self, ...) local t = ct(self, ...); t._parent = self; table.insert(ALL_TEX, t); return t end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('''
OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end
RegionMethods.EnableMouse = function(s, v) s._mouse = v end
RegionMethods.SetPoint = function(s, p, rel, rp, x, y) s._pt = { x = x, y = y } end
RegionMethods.SetTexCoord = function(s, l, r, t, b) s._mirror = (l or 0) > (r or 1) end
''')
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", lua.table())
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
RING = nil
RING_R = nil
for _, f in ipairs(allFrames) do if f.sqKey == "gather" and f.fill then RING = f end end
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
-- A distance to the nearest pixel, the same on every system: snapped to a fine grid first, so
-- one that lands on a half (the knife's tip sits on the ring's middle line, 49.5 out) can't
-- round up on one system's maths and down on another's.
function Px(v) return math.floor(math.floor(v * 1000 + 0.5) / 1000 + 0.5) end
-- What the effect shows: solid bits (fur strands, rock chips), sparks, how far out the furthest is, the cut, the glint.
function FX(label)
  if not RING._shown then P(string.format("%-28s (hidden)", label)) return end
  local bits, sparks, far, low, cut = 0, 0, 0, 0, 0
  for _, l in ipairs(ALL_LINES) do
    if l._parent == RING and l._shown ~= false and l._layer == "ARTWORK" and l._x1 then
      if (l._sub == 3 or l._sub == 5) and l._c and l._c[4] > 0.01 then
        if l._sub == 3 then bits = bits + 1 else sparks = sparks + 1 end
        far = math.max(far, math.sqrt(l._x1 ^ 2 + l._y1 ^ 2)); low = math.min(low, l._y1)
      elseif l._sub == 2 then cut = cut + 1 end
    end
  end
  local glint, tool = false, "-"
  for _, t in ipairs(ALL_TEX) do
    if t._parent == RING and t._shown and (t._alpha or 0) > 0.01 then
      local path = tostring(t._texpath)
      if path:match("star4") then glint = true
      elseif path:match("Cursor") or path == "4675625" then
        -- Where the working end (knife tip / pick point / shears' jaws) is: from the image's middle, turned.
        local which = path:match("Attack") and "knife" or path == "4675625" and "shears" or "pick"
        local tip = ({ knife = { 0.03, 0.03 }, pick = { 0.92, 0.06 }, shears = { 0.19, 0.19 } })[which]
        local grip = ({ knife = { 0.78, 0.78 }, pick = { 0.77, 0.875 }, shears = { 0.75, 0.75 } })[which]
        local tx = t._mirror and 1 - tip[1] or tip[1]
        local gx = t._mirror and 1 - grip[1] or grip[1]
        local vx, vy = (tx - 0.5) * t._w, (0.5 - tip[2]) * t._w
        local wx, wy = (gx - 0.5) * t._w, (0.5 - grip[2]) * t._w
        local r = t._rot or 0
        local x = t._pt.x + vx * math.cos(r) - vy * math.sin(r)
        local y = t._pt.y + vx * math.sin(r) + vy * math.cos(r)
        local hx = t._pt.x + wx * math.cos(r) - wy * math.sin(r)
        local hy = t._pt.y + wx * math.sin(r) + wy * math.cos(r)
        -- The working end and the hand: how far each is from the ring's middle.
        tool = string.format("%s%s end %3d hand %3d%s", which, t._mirror and "(m)" or "", Px(math.sqrt(x * x + y * y)),
          Px(math.sqrt(hx * hx + hy * hy)),
          (t._alpha or 1) < 0.99 and string.format(" a=%.2f", t._alpha) or "")
      end
    end
  end
  P(string.format("%-28s bits=%2d sparks=%2d far=%3d low=%4d cut=%2d glint=%-5s %-34s | %s", label, bits, sparks,
    Px(far), Px(low), cut, tostring(glint), tool, T(RING)))
end
function Cast(name, id, len) CAST = { name = name, s = NOW, e = NOW + len, id = id }; Fire("UNIT_SPELLCAST_START", "player", "g", id) end
function Done(id) CAST = nil; Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", id) end

-- Skinning: strokes along the edge, tufts flying, then the last cut and a spray.
Cast("Skinning", 8613, 3)
for i = 1, 10 do Advance(0.25); FX(string.format("skinning %.2fs", i * 0.25)) end
Advance(0.5); Done(8613); Advance(0.05); FX("done +0.05s")
Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2318::|h[Light Leather]|h|r.")
Advance(0.15); FX("done +0.2s (cut going round)")
Advance(0.3); FX("done +0.5s (spray)")
Advance(0.5); FX("done +1s")
Advance(1.5); FX("done +2.5s (fur gone)")
Advance(5)
-- Interrupted: no more strokes; the fur already off falls away.
Cast("Skinning", 8613, 3); Advance(1.5); CAST = nil; Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "g", 8613)
Advance(0.1); FX("interrupted +0.1s"); Advance(2); FX("interrupted +2.1s"); Advance(5)
-- Mining: the pick winds up, strikes (flash, crack, sparks and chips), again and again; the
-- vein breaks with a flash of the whole ring and a burst.
Cast("Mining", 2575, 2)
for i = 1, 12 do Advance(0.125); FX(string.format("mining %.3fs", i * 0.125)) end
Advance(0.5); Done(2575); Advance(0.05); FX("mined +0.05s (heavy strike)")
Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2770::|h[Copper Ore]|h|rx2.")
Advance(0.25); FX("mined +0.3s (burst)"); Advance(0.4); FX("mined +0.7s"); Advance(1); FX("mined +1.7s (all landed)")
Advance(5)
-- Herbalism: the shears move in, snip (a little flash, leaves and petals cut loose), pull back;
-- the last snip sends a gust of leaves off the whole ring.
Cast("Herb Gathering", 2366, 2)
for i = 1, 8 do Advance(0.15); FX(string.format("herb %.2fs", i * 0.15)) end
Advance(0.85); Done(2366); Advance(0.05); FX("picked +0.05s (last snip)")
Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2447::|h[Peacebloom]|h|rx3.")
Advance(0.35); FX("picked +0.4s (gust)"); Advance(0.8); FX("picked +1.2s"); Advance(1.2); FX("picked +2.4s (all landed)")
Advance(5)
-- The option turns them off.
CircletDB.gatherFx = false
Cast("Skinning", 8613, 3); Advance(1); FX("skinning, animations off"); Done(8613); Advance(5)
CircletDB.gatherFx = true
-- The preview: skinning, then mining.
Slash("gather"); Advance(1.5); FX("preview, skinning"); Advance(2); FX("preview, skinned")
Advance(3.5); FX("preview, mining"); Advance(3); FX("preview, mined")
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))

# RENDER=dir: draw a few frames of a gather to PNGs, to look at (RENDER_KIND=skinning or mining).
out = os.environ.get('RENDER')
if out:
    from PIL import Image, ImageDraw
    kind = os.environ.get('RENDER_KIND', 'skinning')
    spell = {'skinning': ('Skinning', 8613), 'mining': ('Mining', 2575), 'herb': ('Herb Gathering', 2366)}[kind]
    lua.execute('Advance(20); Cast("%s", %d, 3)' % spell)
    for n, step in enumerate([0.9, 0.12, 0.12, 0.12, 0.6]):
        lua.execute('Advance(%f)' % step)
        if n == 4: lua.execute('Done(%d); Advance(0.12)' % spell[1])
        img = Image.new('RGB', (320, 320), (40, 44, 52)); d = ImageDraw.Draw(img)
        for row in lua.eval('''(function()
          local t = {}
          for _, l in ipairs(ALL_LINES) do
            if l._parent == RING and l._shown ~= false and l._x1 and l._c then
              table.insert(t, { l._layer, l._sub, l._x1, l._y1, l._x2, l._y2, l._t or 1, l._c[1], l._c[2], l._c[3], l._c[4] or 1 })
            end
          end
          return t end)()''').values():
            layer, sub, x1, y1, x2, y2, w, r, g, b, a = [row[i] for i in range(1, 12)]
            if a < 0.02: continue
            if layer == 'BACKGROUND': col = (18, 18, 23)
            elif layer == 'ARTWORK' and sub == 0: col = (110, 210, 90)
            elif layer == 'ARTWORK' and sub == 5: col = tuple(min(255, int(44 + 255 * v * a)) for v in (r, g, b))
            elif layer == 'ARTWORK': col = tuple(int(255 * v * a + 44 * (1 - a)) for v in (r, g, b))
            else: continue
            d.line([(160 + x1, 160 - y1), (160 + x2, 160 - y2)], fill=col, width=max(1, int(round(w))))
        tool = lua.eval('''(function()
          for _, t in ipairs(ALL_TEX) do
            if t._parent == RING and t._shown and (tostring(t._texpath):match("Cursor") or tostring(t._texpath) == "4675625") and t._pt then
              return { tostring(t._texpath), t._pt.x, t._pt.y, t._w, t._rot or 0, t._alpha or 1, t._mirror or false }
            end
          end end)()''')
        if tool:
            import math
            path, cx, cy, size, rot, alpha, mirror = [tool[i] for i in range(1, 8)]
            name = 'ch_Attack' if 'Attack' in path else 'shears' if path == '4675625' else 'ch_Mine'
            spr = Image.open(os.path.join(os.environ.get('SPRITES', out), name + '_raw.png')).convert('RGBA')
            if mirror: spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
            spr = spr.resize((int(size), int(size)), Image.LANCZOS).rotate(math.degrees(rot), expand=True, resample=Image.BICUBIC)
            if alpha < 1: spr.putalpha(spr.getchannel('A').point(lambda v: int(v * alpha)))
            img = img.convert('RGBA'); img.alpha_composite(spr, (int(160 + cx - spr.size[0] / 2), int(160 - cy - spr.size[1] / 2)))
            img = img.convert('RGB')
        img.save(os.path.join(out, '%s%d.png' % (kind, n)))
