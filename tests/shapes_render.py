import math
from lupa import LuaRuntime
from PIL import Image, ImageDraw
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end; UnitClass = function() return "Hunter", "HUNTER" end')
chunk = lua.eval('function(s) return load(s, "@SideQuest.lua") end')((__import__('subprocess').run(['python3','make_bundle.py']), open('bundle.lua').read())[1])
chunk("Circlet", lua.table())
lua.execute("ROT = 180")
lua.execute('''Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD")
function Adv(sec) for _ = 1, sec*30 do NOW = NOW + 1/30
  local due = {} for i = #pendingTimers, 1, -1 do if pendingTimers[i].at <= NOW then table.insert(due, table.remove(pendingTimers, i)) end end
  for _, t in ipairs(due) do t.fn() end
  for _, f in ipairs(allFrames) do if f._shown and f._scripts.OnUpdate then f._scripts.OnUpdate(f, 1/30) end end end end''')
LAYER = {"BACKGROUND":0,"BORDER":1,"ARTWORK":2,"OVERLAY":3}
def render(frame_pat):
    lines = lua.eval('ALL_LINES')
    W=160; S=3
    im = Image.new("RGB",(W*S,W*S),(50,40,30))
    items=[]
    for i in range(1, len(lines)+1):
        l = lines[i]
        if not l._shown or l._x1 is None: continue
        p = l._parent
        if p is None or not p.editHint: continue
        if not p._shown: continue
        items.append((LAYER.get(l._layer,0), l._sub or 0, l))
    items.sort(key=lambda t:(t[0],t[1]))
    for _,_,l in items:
        x1,y1,x2,y2,T = l._x1,l._y1,l._x2,l._y2,l._t
        r,g,b,a = l._c[1],l._c[2],l._c[3],l._c[4]
        dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy) or 1; nx,ny=-dy/L*T/2,dx/L*T/2
        pts=[((W/2+px)*S,(W/2-py)*S) for px,py in [(x1+nx,y1+ny),(x2+nx,y2+ny),(x2-nx,y2-ny),(x1-nx,y1-ny)]]
        ov = Image.new("RGBA", im.size, (0,0,0,0)); ImageDraw.Draw(ov).polygon(pts, fill=(int(r*255),int(g*255),int(b*255),int(a*255)))
        im = Image.alpha_composite(im.convert("RGBA"), ov).convert("RGB")
    return im
out = Image.new("RGB", (3*480, 3*480))
for row, shape in enumerate(["ring","arc","half"]):
  for col, style in enumerate(["smooth","segmented","thin"]):
    lua.execute(f'CircletDB.questStyle = "{style}"; CircletDB.questShape = "{shape}"; CircletDB.questBorder = 2; CircletDB.questRotation = ROT; CircletDB.questFill = ("{style}" == "thin") and "solid" or "gradient"')
    lua.execute('Slash = SlashCmdList.CIRCLET; Slash("quest"); Adv(1.2)')
    out.paste(render("quest"), (col*480, row*480))
    lua.execute('Adv(25)')
out.save('/tmp/shapes.png'); print("saved", dict(lua.eval("ERRORS")) if lua.eval("ERRORS") else "")
