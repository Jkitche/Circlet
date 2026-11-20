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
    -- WoW Forever's containers: groups, no slots. The button only exists once a debuff shows.
    f.AddAuraSlot = false; f.GetAuraSlotFrame = false
    f.AddAuraGroup = function(self, key, filter, opts) Log(self._unit, "AddAuraGroup", key, filter); self._opts = opts end
    f.SetAuraGroupFilterString = function(self, key, filter) Log(self._unit, "groupFilter", filter) end
    f.SetAuraGroupMaxFrameCount = function(self, key, n) Log(self._unit, "max", n) end
    f.SetAuraGroupLayout = function(self, key, o) Log(self._unit, "layout", o.elementWidth) end
    f.GetAuraGroupFrame = function(self, key, i) return self._button end
    f.DebuffAppears = function(self) if not self._button then self._button = Button(self._unit); self._opts.initializeFrame(self._button) end end
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
RegionMethods.SetSize = function(s, w, h) s._w, s._h = w, h end
RegionMethods.SetTexture = function(s, t) s._tex = t end
local live = NS.DebuffRingsInfo()
function B(u) local r = live[u]; return r and (tostring(r.kind) .. " button=" .. tostring(r.button and r.button._name) .. " dressed=" .. tostring(r.dressed)) or "none" end
CircletDB.debuffEnabled = true; Advance(1)
Calls("turned on"); P("player: " .. B("player") .. " | target: " .. B("target"))
-- Rend lands in combat: the game makes the target's button; it's forbidden until combat ends.
IN_COMBAT = true; LOCKED = true
live.target.container:DebuffAppears(); Advance(1)
Calls("debuff in combat"); P("target: " .. B("target"))
IN_COMBAT = false; LOCKED = false; Fire("PLAYER_REGEN_ENABLED"); Advance(1)
Calls("combat over"); P("target: " .. B("target"))
-- Out of combat the player's button is dressed straight away.
live.player.container:DebuffAppears(); Advance(1)
Calls("player debuff"); P("player: " .. B("player"))
Slash("debuffdebug")
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
