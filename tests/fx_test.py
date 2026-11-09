HEAD = 'import math\nfrom lupa import LuaRuntime\nfrom PIL import Image, ImageDraw, ImageFont\nlua = LuaRuntime(unpack_returned_tuples=True)\nlua.execute(open(\'mock.lua\').read())\nlua.execute(\'\'\'\nUIParent._w, UIParent._h = 1920, 1080\nRegionMethods.GetCenter = function(s) return s._cx, s._cy end\nUNDEF = {}\nsetmetatable(_G, { __index = function(t, k) UNDEF[k] = (UNDEF[k] or 0) + 1 end })\nERRORS = {}\nlocal function guard(where, fn, ...) local ok, err = pcall(fn, ...); if not ok then local k = where..": "..tostring(err); ERRORS[k] = (ERRORS[k] or 0) + 1 end end\nGUARD = guard\nfunction Fire(event, ...) for _, f in ipairs(allFrames) do if f._events and f._events[event] and f._scripts.OnEvent then guard("OnEvent "..event, f._scripts.OnEvent, f, event, ...) end end end\nfunction Advance(seconds, fps) fps = fps or 30\n  for _ = 1, math.floor(seconds * fps) do NOW = NOW + 1 / fps\n    local due = {} for i = #pendingTimers, 1, -1 do if pendingTimers[i].at <= NOW then table.insert(due, table.remove(pendingTimers, i)) end end\n    for _, t in ipairs(due) do guard("timer", t.fn) end\n    for _, f in ipairs(allFrames) do if f._shown and f._scripts.OnUpdate then guard("OnUpdate", f._scripts.OnUpdate, f, 1 / fps) end end\n  end end\nfunction Slash(c) guard("slash "..c, SlashCmdList.CIRCLET, c) end\nfunction XPRingState()\n  for _, f in ipairs(ALL_FS) do\n    if f._text and tostring(f._text):match("^Level %d+$") or (f._text == "LEVEL UP!") then\n      local p = f._parent\n      local texts = {}\n      for _, g in ipairs(ALL_FS) do if g._parent == p then table.insert(texts, tostring(g._text or "")) end end\n      return string.format("shown=%s alpha=%.2f | %s", tostring(p._shown), p._alpha, table.concat(texts, " | "))\n    end\n  end\n  return "no xp ring text yet"\nend\n\'\'\')\nlua.execute("""\nALL_TEX = {}\nlocal orig = RegionMethods.CreateTexture\nRegionMethods.CreateTexture = function(self, ...) local t = orig(self, ...); t._parent = self; table.insert(ALL_TEX, t); return t end\n""")\nchunk = lua.eval(\'function(s) return load(s, "@SideQuest.lua") end\')(open(\'bundle.lua\').read())\nchunk("Circlet", lua.table())\n'
import math
from lupa import LuaRuntime
from PIL import Image, ImageDraw, ImageFont
exec(HEAD)
lua.execute('Fire("ADDON_LOADED", "Circlet"); XP = 850; XPMAX = 1000; Fire("PLAYER_ENTERING_WORLD"); Advance(1)')
lua.execute('''
function Visible(r) while r do if not r._shown then return false end; r = r._parent end; return true end
function Scene()
  local lines, sparks, texts = {}, {}, {}
  for _, l in ipairs(ALL_LINES) do
    local p = l._parent
    if l._shown and l._x1 and p and Visible(p) and (p._alpha or 1) > 0 then
      table.insert(lines, { l = l, a = (p._alpha or 1) * ((p._parent and p._parent._alpha) or 1) })
    end
  end
  return lines
end
''')
# collect spark textures: the fx frame's textures (created via CreateTexture -> not tracked); track via frames list
LAYER = {"BACKGROUND":0,"BORDER":1,"ARTWORK":2,"OVERLAY":3}
def frame_img(label):
    W=320; S=2
    im = Image.new("RGB",(W*S,W*S),(40,32,26)).convert("RGBA")
    entries = sorted(lua.eval('Scene()').values(), key=lambda e:(LAYER.get(e.l._layer,0), e.l._sub or 0))
    for e in entries:
        l = e.l; a = e.a
        x1,y1,x2,y2,T = l._x1,l._y1,l._x2,l._y2,l._t; c = l._c
        dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy) or 1; nx,ny=-dy/L*T/2,dx/L*T/2
        pts=[((W/2+px)*S,(W/2-py)*S) for px,py in [(x1+nx,y1+ny),(x2+nx,y2+ny),(x2-nx,y2-ny),(x1-nx,y1-ny)]]
        ov = Image.new("RGBA", im.size, (0,0,0,0)); ImageDraw.Draw(ov).polygon(pts, fill=(int(c[1]*255),int(c[2]*255),int(c[3]*255),int(255*a*(c[4] if c[4] else 1))))
        im = Image.alpha_composite(im, ov)
    d = ImageDraw.Draw(im)
    for t in lua.eval('ALL_TEX').values():
        p = t._parent
        if t._shown and t._pt and p and p._shown and t._vc:
            x, y = t._pt.x, t._pt.y; r = (t._w or 10)/2; a = t._alpha if t._alpha is not None else 1
            cx, cy = (W/2+x)*S, (W/2-y)*S
            col = (255, int(210), int(60))
            for k in range(4):   # star-ish
                ang = k*math.pi/4
                d.line([(cx-math.cos(ang)*r*S, cy-math.sin(ang)*r*S),(cx+math.cos(ang)*r*S, cy+math.sin(ang)*r*S)], fill=col+(int(255*a),), width=3)
    d.text((8,8), label, fill=(230,230,230), font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20))
    return im.convert("RGB")
# Level up: 85% -> next level 20%
lua.execute('XP = 220; XPMAX = 1100; Fire("PLAYER_XP_UPDATE", "player")')
# step until the effect starts (fill crosses the level), then capture over time
frames = []
for step in range(200):
    lua.execute('Advance(1/30)')
    if lua.eval('(function() for _, f in ipairs(allFrames) do if f.waves and f._shown then return true end end return false end)()'):
        break
start = step
for t, label in [(0.05,"t=0.05s"),(0.25,"t=0.3s"),(0.3,"t=0.6s"),(0.4,"t=1.0s"),(0.5,"t=1.5s (done)")]:
    lua.execute(f'Advance({t})')
    frames.append(frame_img(label))
out = Image.new("RGB",(sum(f.width for f in frames), frames[0].height))
x=0
for f in frames: out.paste(f,(x,0)); x+=f.width
out = out.resize((out.width//2, out.height//2))
out.save('/tmp/levelup_fx.png')
print("effect started after", round(start/30, 2), "s of fill animation")
lua.execute('CircletDB.xpLevelFx = false; Advance(8); XP = 300; XPMAX = 1200; Fire("PLAYER_XP_UPDATE", "player"); Advance(0.1)')
lua.execute('XP = 1150; Fire("PLAYER_XP_UPDATE", "player"); Advance(8); XP = 50; Fire("PLAYER_XP_UPDATE", "player"); Advance(1.5)')
print("with option off, effect shown:", lua.eval('(function() for _, f in ipairs(allFrames) do if f.waves and f._shown then return true end end return false end)()'))
errs = lua.eval('ERRORS'); print("ERRORS:", dict(errs) if list(errs.keys()) else "none")
