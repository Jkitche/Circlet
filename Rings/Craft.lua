-- Circlet: Crafting ring: progress through a batch of crafts ("Create All", x10...).
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing = ns.db, ns.IsSecret, ns.CreateLiveRing
local SafeCall = ns.SafeCall

---------------------------------------------------------------------------
-- Crafting ring
---------------------------------------------------------------------------
-- Picking how many to make (C_TradeSkillUI.CraftRecipe, or DoTradeSkill on older
-- clients) starts a batch; each successful cast counts one. The ring fills smoothly
-- through the batch, including the current cast, and shows "3 / 10". It finishes
-- with "Done!", or "Stopped" if the batch is interrupted.

local batch -- { total, done, name, spellID, castStart, castEnd, finished, stopped, endedAt }

local function StartBatch(count, icon)
    count = tonumber(count) or 1
    if IsSecret(count) then count = 1 end
    if IsSecret(icon) then icon = nil end
    batch = { total = math.max(1, count), done = 0, started = GetTime(), icon = icon }
end

-- Retail-style crafting API, and the older one. The icon is the item being made.
if hooksecurefunc then
    if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
        hooksecurefunc(C_TradeSkillUI, "CraftRecipe", function(recipeID, count)
            local info = C_TradeSkillUI.GetRecipeInfo and SafeCall(C_TradeSkillUI.GetRecipeInfo, recipeID)
            StartBatch(count, type(info) == "table" and info.icon or nil)
        end)
    end
    if DoTradeSkill then
        hooksecurefunc("DoTradeSkill", function(index, count)
            StartBatch(count, GetTradeSkillIcon and SafeCall(GetTradeSkillIcon, index))
        end)
    end
end

local function CastFraction(now)
    if not (batch and batch.castStart and batch.castEnd) then return 0 end
    local span = batch.castEnd - batch.castStart
    if span <= 0 then return 0 end
    return math.max(0, math.min(1, (now - batch.castStart) / span))
end

local function State(name, done, total, castFrac, finished, stopped, icon, lost, lostAt)
    local c = db.craftColors
    local st = { title = name or "Crafting", value = done .. " / " .. total, color = c.fill,
                 icon = db.craftIcon and icon or nil,
                 notches = total } -- segmented style: one notch per item
    if finished then
        st.frac, st.color = 1, c.done
        st.label, st.labelColor = "Done!", c.done
        st.hold = db.craftHold or 3
    elseif stopped then
        -- Back to the last finished craft; the part of the cast that was lost flashes white.
        st.frac = done / total
        st.label = "Stopped"
        st.hold = db.craftHold or 3
        if lost and lost > 0 then
            st.flashFrom, st.flashTo, st.flashAt = done / total, math.min(1, (done + lost) / total), lostAt
        end
    else
        st.frac = math.min(1, (done + castFrac) / total)
        local left = total - done
        st.label = total == 1 and "Crafting" or (left == 1 and "last one" or (left .. " to go"))
    end
    return st
end

local craftRing = CreateLiveRing({
    key = "craft",
    read = function(now)
        local b = batch
        if not b or not b.name then return nil end -- nothing has been cast yet
        if b.total < 2 and not db.craftSingle then return nil end
        if b.endedAt then
            if now - b.endedAt > 0.1 then return nil end -- show the end state once; the ring holds it
        end
        return State(b.name, b.done, b.total, CastFraction(now), b.finished, b.stopped, b.icon, b.lost, b.endedAt)
    end,
    sample = function(t)
        -- Alternates a batch that finishes and one interrupted partway through a cast.
        local total, castTime = 8, 1.5
        local cycleLen = total * castTime + 3
        local cycle, tt = math.floor(t / cycleLen), t % cycleLen
        local p = tt / castTime
        local icon = "Interface\\Icons\\INV_Misc_Bandage_18"
        local stopAt = 4.6
        if cycle % 2 == 0 and p >= stopAt then
            local at = GetTime() - (tt - stopAt * castTime)
            return State("Heavy Linen Bandage", 4, total, 0, false, true, icon, stopAt % 1, at)
        end
        if p >= total then return State("Heavy Linen Bandage", total, total, 0, true, false, icon) end
        return State("Heavy Linen Bandage", math.floor(p), total, p % 1, false, false, icon)
    end,
})

local function EndBatch(how)
    if not batch or batch.endedAt then return end
    local now = GetTime()
    if how == "stopped" then batch.lost = CastFraction(now) end -- the part of the cast that's gone
    batch[how] = true
    batch.endedAt = now
end

ns.Listen({ "UNIT_SPELLCAST_START:player", "UNIT_SPELLCAST_SUCCEEDED:player", "UNIT_SPELLCAST_INTERRUPTED:player", "UNIT_SPELLCAST_FAILED:player" }, function(event, unit, castGUID, spellID)
    if not batch or batch.endedAt then return end
    local now = GetTime()
    if event == "UNIT_SPELLCAST_START" then
        local name, _, castIcon, startMS, endMS, _, _, _, castSpell = SafeCall(UnitCastingInfo, "player")
        if not name or IsSecret(name) then return end
        castSpell = castSpell or spellID
        if batch.spellID and castSpell and castSpell ~= batch.spellID then
            EndBatch("stopped") -- casting something else: the batch is over
            return
        end
        if now - batch.started > 5 and not batch.name then
            batch = nil -- the craft never started (no materials, etc.)
            return
        end
        batch.name, batch.spellID = name, castSpell
        if not batch.icon and castIcon and not IsSecret(castIcon) then batch.icon = castIcon end
        if type(startMS) == "number" and type(endMS) == "number" and not IsSecret(startMS) then
            batch.castStart, batch.castEnd = startMS / 1000, endMS / 1000
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if batch.spellID and spellID ~= batch.spellID then return end
        if not batch.name then return end
        batch.done = batch.done + 1
        batch.castStart, batch.castEnd = nil, nil
        if ns.SessionAdd then ns.SessionAdd("crafts", nil, 1) end
        if batch.done >= batch.total then EndBatch("finished") end
    elseif batch.name and (batch.spellID == nil or spellID == batch.spellID) then
        -- Interrupted or failed (moved, ran out of materials, ...).
        EndBatch("stopped")
    end
end)

local function PreviewCraftRing() craftRing.Preview(15) end

-- Shared with the files loaded after this one.
ns.craftRing = craftRing
ns.CraftActive = function() return batch ~= nil and batch.endedAt == nil end
ns.PreviewCraftRing = PreviewCraftRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "craft", name = "Crafting", order = 12,
    ring = craftRing,
    preview = PreviewCraftRing, slash = { "craft", "crafting" }, help = "preview the crafting ring",
    toggle = { "Crafting ring", "Progress through a batch of crafts." },
    gameBar = "the game's cast bar while crafting",
    defaults = {
        -- Crafting ring: progress through a batch of crafts.
        craftEnabled   = true,
        craftSingle    = true,  -- also for one-off crafts (not just batches)
        craftIcon      = true,  -- the item's icon as a badge on the ring
        craftSize      = 110,
        craftThickness = 11,
        craftOpacity   = 100,
        craftX         = 0,
        craftFromTop   = 260,
        craftHold      = 3,
        craftStyle     = "segmented",
        craftBorder    = 2, -- black border width (0 = none)
        craftColors = {
            fill = { r = 0.95, g = 0.65, b = 0.25 },
            done = { r = 0.35, g = 0.90, b = 0.40 },
        },
    },
    page = { folder = "professions", order = 1, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(11, "Crafting", "Crafting Ring",
                "When you craft several at once (Create All, or a count), the ring fills through the batch, "
                .. "including the current cast, and shows how many are done. It ends with Done! (or Stopped).",
                MergeTop(TopRow("craft", "crafting ring", ns.PreviewCraftRing,
                    "Show a sample batch of eight. Also /sq craft."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "craftEnabled", "Show crafting ring", "Show the ring while crafting a batch."),
                        single = Toggle(2, "craftSingle", "Single crafts too",
                            "Also show it when you make just one, not only for batches."),
                        icon = Toggle(3, "craftIcon", "Show item icon",
                            "The icon of what you're crafting as a round badge on the ring's top edge, "
                            .. "bordered in the ring color."),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "craftColors", "fill", "Crafting", "Ring color while the batch is going."),
                        done = Color(2, "craftColors", "done", "Done", "Ring and label color when the batch finishes."),
                    }),
                    size = SizeBox(4, "craft", "crafting ring", "Offset from the center of the screen."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after the batch ends."
            return tab
        end },
})
