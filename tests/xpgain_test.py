# XP gain effect: a comet riding the fill as XP comes in, sparkles behind it, a flare where it lands.
from lupa import LuaRuntime
src = open('fx_test.py').read()
HEAD = eval(src[src.index('HEAD = ') + 7:src.index('\n', src.index('HEAD = '))])
HEAD = HEAD.replace('chunk("Circlet", lua.table())', 'NSX = lua.table(); lua.globals().NS = NSX; chunk("Circlet", NSX)')
exec(HEAD)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); XP = 300; XPMAX = 1000; Fire("PLAYER_ENTERING_WORLD"); Advance(1)
OUT = {}; function P(s) table.insert(OUT, s) end
function Fx()
  local g = NS.XPGainFxParts(); local n = 0
  for _, s in ipairs(g.sparkles) do if s.tex._shown then n = n + 1 end end
  return string.format("head=%s sparkles=%d", tostring(g.star._shown and true or false), n)
end
P("idle: " .. Fx())
XP = 450; Fire("PLAYER_XP_UPDATE", "player"); Advance(0.3); P("filling: " .. Fx())
Advance(1.2); P("just landed: " .. Fx())
Advance(1); P("settled: " .. Fx())
CircletDB.xpGainFx = false; XP = 600; Fire("PLAYER_XP_UPDATE", "player"); Advance(0.3); P("option off: " .. Fx())
CircletDB.xpGainFx = true; Advance(6)
XP = 900; Fire("PLAYER_XP_UPDATE", "player"); Advance(0.3); P("again: " .. Fx())
-- /circ showxp: the ring comes up at your current XP for a few seconds, and the numbers go to chat.
print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end P("chat: " .. table.concat(t, " ")) end
Advance(12); P("before showxp: " .. XPRingState())
Slash("showxp"); Advance(0.5); P("showxp: " .. XPRingState())
Advance(12); P("showxp later: " .. XPRingState())
''')
print("\n".join(lua.eval("OUT").values()))
errs = lua.eval('ERRORS'); print("ERRORS:", dict(errs) if list(errs.keys()) else "none")
