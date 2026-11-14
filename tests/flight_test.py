from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end
ON_TAXI = false
function UnitOnTaxi() return ON_TAXI end
-- The flight map, by slot. Node IDs come from the names (Data/FlightPaths.lua's FLIGHT_NODES):
-- Stormwind 2, Ironforge 6, Sentinel Hill 4, Lakeshire 5. "Nowhere" isn't in the data.
NODES = { { name = "Stormwind, Elwynn", type = "CURRENT" }, { name = "Ironforge, Dun Morogh", type = "REACHABLE" },
          { name = "Sentinel Hill, Westfall", type = "REACHABLE" }, { name = "Lakeshire, Redridge", type = "REACHABLE" },
          { name = "Nowhere, Testland", type = "REACHABLE" } }
function NumTaxiNodes() return #NODES end
function TaxiNodeName(i) return NODES[i].name end
function TaxiNodeGetType(i) return NODES[i].type end
-- The hops the game would fly to each slot: { from slot, to slot } per hop.
HOPS = { [2] = { { 1, 2 } }, [4] = { { 1, 3 }, { 3, 4 } }, [5] = { { 1, 5 } } }
function GetNumRoutes(i) return HOPS[i] and #HOPS[i] or 0 end
function TaxiGetNodeSlot(i, hop, source) return HOPS[i][hop][source and 1 or 2] end
HOOKS = {}
function TakeTaxiNode(i) end
hooksecurefunc = hooksecurefunc or function(name, fn) local orig = _G[name]; _G[name] = function(...) orig(...) fn(...) end end
wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end; RegionMethods.EnableMouse = function(s, v) s._mouse = v end')
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", lua.table())
lua.execute('''
DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME or {}; DEFAULT_CHAT_FRAME.AddMessage = function(_, m) P("chat: " .. tostring(m)) end
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD"); Advance(1)
function FR() for _, f in ipairs(allFrames) do if f.editHint and f.fill2 then return f end end end
local F = FR()
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function S(l) local n = 0 for _, x in ipairs(F.fill) do if x._shown ~= false and x._x1 then n = n + 1 end end
  P(string.format("%-26s shown=%s a=%.2f fill=%d | %s", l, tostring(F._shown), F._alpha or 0, n, T(F))) end
S("idle")
-- Direct: Stormwind -> Ironforge, 7757 yards at 33.6 yd/s = 231 s, from the very first flight.
TakeTaxiNode(2); Advance(0.5); ON_TAXI = true; Advance(1); S("direct, 1s")
Advance(120); S("direct, 121s")
Advance(115); S("direct, overdue")
ON_TAXI = false; Advance(0.5); S("landed")
Advance(6); S("after hold")
P("learned anything: " .. tostring(CircletDB.flightTimes ~= nil and next(CircletDB.flightTimes) ~= nil) .. " factor=" .. tostring(CircletDB.flightFactor))
-- Two hops: Stormwind -> Sentinel Hill -> Lakeshire, 2329 + 3890 yards = 185 s.
TakeTaxiNode(4); Advance(0.3); ON_TAXI = true; Advance(5.2); S("two hops, 5s")
ON_TAXI = false; Advance(6)
-- Not in the data: counts up.
TakeTaxiNode(5); Advance(0.3); ON_TAXI = true; Advance(4); S("no route data")
ON_TAXI = false; Advance(6)
ON_TAXI = true; Advance(3); S("flight w/o map click")
ON_TAXI = false; Advance(6)
Slash("flight"); Advance(2); S("preview")
Advance(10); S("preview no-data part")
Advance(10); Slash("edit flight"); Advance(1); S("editing"); Slash("edit flight"); Advance(3); S("edit off")
CircletDB.flightEnabled = false; TakeTaxiNode(2); ON_TAXI = true; Advance(2); S("disabled")
ON_TAXI = false; Advance(3)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
