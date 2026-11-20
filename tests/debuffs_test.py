from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame
CALLS = {}
local function Log(...) local t = {} for i = 1, select("#", ...) do local v = select(i, ...)
  t[i] = type(v) == "table" and (v._name or "table") or tostring(v) end table.insert(CALLS, table.concat(t, " ")) end
-- A fake aura container: logs the calls the debuff rings make. LOCKED: auras are secret
-- (combat), so calls on the aura button throw like the real forbidden buttons.
LOCKED = false
local function Button(unit)
  local b = cf("Button"); b._name = unit .. "Button"
  for _, m in ipairs({ "AddDispelTypeTexture", "ClearDispelTypeTextures", "SetDurationCooldown", "ClearDurationCooldown",
                       "SetDurationText", "ClearDurationText", "SetHideTooltipInCombat" }) do
    b[m] = function(self, ...) if LOCKED then error("forbidden") end Log(unit, m, ...) end
  end
  return b
end
CreateFrame = function(k, n, p, t)
  local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end
  if k == "AuraContainer" then
    f._name = "container"
    f.SetUnit = function(self, u) self._unit = u; Log("SetUnit", u) end
    f.AddAuraSlot = function(self, key, filter) Log(self._unit, "AddAuraSlot", key, filter); self._button = Button(self._unit); return self._button end
    f.SetAuraSlotFilterString = function(self, key, filter) Log(self._unit, "filter", filter) end
    f.SetEnabled = function(self, on) Log(self._unit, "SetEnabled", on) end
  end
  if k == "Cooldown" then
    f.SetCooldown = function(self, s, d) self._cd = d end
    f.SetSwipeTexture = function(self, t) self._swipe = t end
  end
  return f
end
PlayerFrame = CreateFrame("Frame", "PlayerFrame"); PlayerPortrait = PlayerFrame:CreateTexture(); PlayerPortrait._w = 64
TargetFrame = CreateFrame("Frame", "TargetFrame"); TargetFramePortrait = TargetFrame:CreateTexture(); TargetFramePortrait._w = 64
CreateColor = function(r, g, b) return { r = r, g = g, b = b, _name = string.format("color(%.1f,%.1f,%.1f)", r, g, b) } end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
NSX = lua.table(); lua.globals().NS = NSX; lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function Calls(label) P(label .. ": " .. (#CALLS == 0 and "(no calls)" or table.concat(CALLS, " / "))); CALLS = {} end
function Info()
  local live, samples = NS.DebuffRingsInfo()
  local t = {}
  for _, u in ipairs({ "player", "target" }) do
    local r = live[u]
    if r then table.insert(t, u .. " " .. (r.container._shown and "shown" or "hidden") .. " size=" .. r.container._w
      .. " tex=" .. tostring(r.ring and r.ring._tex) .. " swipe=" .. tostring(r.cd and r.cd._swipe)) end
  end
  return #t == 0 and "no rings" or table.concat(t, " | ")
end
RegionMethods.SetSize = function(s, w, h) s._w, s._h = w, h end
RegionMethods.SetTexture = function(s, t) s._tex = t end
RegionMethods.SetVertexColor = function(s, r, g, b) s._vc = string.format("%.1f,%.1f,%.1f", r, g, b) end

Calls("off by default"); P(Info())
CircletDB.debuffEnabled = true; Advance(1)
Calls("turned on"); P(Info())
Advance(2); Calls("nothing changed")
CircletDB.debuffThickness = 10; Advance(1); Calls("thicker"); P(Info())
-- In combat the buttons are forbidden: a change waits for combat to end.
IN_COMBAT = true; LOCKED = true
CircletDB.debuffColors.poison = { r = 0, g = 1, b = 0 }; CircletDB.debuffTargetFilter = "all"; Advance(1)
Calls("changed in combat")
IN_COMBAT = false; LOCKED = false; Fire("PLAYER_REGEN_ENABLED"); Advance(0.6); Calls("combat over")
CircletDB.debuffTarget = false; Advance(1); Calls("target off"); P(Info())
CircletDB.debuffDrain = false; CircletDB.debuffTime = true; Advance(1); Calls("no drain, time on")
-- Preview: our own sample rings, cycling colors.
local _, samples = NS.DebuffRingsInfo()
Slash("debuff"); Advance(0.6)
local function S(u) local s = samples[u]; if not (s and s._shown) then return "hidden" end
  local fx = {} for k, f in pairs(s.fx) do if f.tex._shown then table.insert(fx, k .. "@" .. tostring(f.tex._vc) .. "/" .. f.tex._w) end end
  table.sort(fx); return s.ring._vc .. " " .. tostring(s.text._text) .. " fx=" .. table.concat(fx, ",") end
P("preview: player " .. S("player") .. " | target " .. S("target"))
CircletDB.debuffTarget = true; Advance(6); P("6s later: player " .. S("player") .. " | target " .. S("target"))
Advance(8); P("preview over: player " .. S("player"))
CircletDB.debuffFx = false; Slash("debuff"); Advance(0.6); P("effects off: player " .. S("player")); Advance(14)
-- The asset map given to the game for the poison effect: its art for poison, blank otherwise.
local live = NS.DebuffRingsInfo(); local t = {}
for k, v in pairs(live.player.fx.poisonBubbles.tex) do end
P("poison fx asset: " .. tostring(NS.DebuffAssetFor and NS.DebuffAssetFor("poisonBubbles", "Poison")) .. " | curse: " .. tostring(NS.DebuffAssetFor and NS.DebuffAssetFor("poisonBubbles", "Curse")))
CircletDB.debuffEnabled = false; Advance(1); Calls("turned off"); P(Info())
Slash("debuffdebug")
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
