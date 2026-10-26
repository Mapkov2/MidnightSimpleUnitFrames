-- castbar_interrupt_ready_geometry.lua <repoRoot> [client]
--
-- The interrupt-ready box lays itself out (Castbars/MSUF_InterruptReady.lua,
-- ApplyBoxLayout) on every cast start, interruptibility switch and cooldown
-- repaint; a restricted readiness, which is every combat read, never dedupes the
-- paint. The 2026-10-26 M+ trace counted 432 such calls rewriting a size and
-- anchors that only a castbar resize or a setting change moves. The layout now
-- writes the size when the size moved and the anchors when an anchor input
-- moved, and nothing else.
--
-- The real core runs in tools/tests/castbar_secret_world.lua. Every SetSize,
-- ClearAllPoints and SetPoint is counted per widget, and each step is checked
-- against the layout rule restated from its public inputs (Rule below):
--   * the box ends exactly where the rule puts it (behaviour unchanged);
--   * the step wrote the size only if the size moved and the anchors only if an
--     anchor input moved (no repeated write).
-- Steps: casts, channels and empowers with readable and restricted data,
-- interruptibility flips, cooldown repaints, a castbar resize, a settings sweep
-- through the profile refresh, a boss pool re-enable, a rebuilt status bar,
-- style and visibility toggles, and a write that raises (the next call repeats
-- it). Boss bars run where the client has them.
--
-- Plain Lua 5.1, repo root (absolute) as arg 1, optional client as arg 2.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
local CLIENTS = arg[2] and { arg[2] } or { "Mainline", "Forever", "Vanilla", "TBC", "Mists" }
local INTERRUPT_SPELL = 2139

-- A setting the profile no longer holds.
local NIL = {}

-- The layout rule from its public inputs: the castbar height (or the fixed
-- size), the clamp, the status bar the box hangs on, the anchor and offsets.
local function Rule(frame, general)
    local bar = frame.statusBar
    local height = bar and bar:GetHeight() or frame:GetHeight() or 16
    local size = general.kickReadyAutoSize == false and tonumber(general.kickReadySize) or height
    local anchor = general.kickReadyAnchor or "RIGHT"
    local relative = anchor == "RIGHT" and "LEFT"
        or anchor == "LEFT" and "RIGHT"
        or anchor == "TOP" and "BOTTOM"
        or anchor == "BOTTOM" and "TOP"
        or anchor
    return { size = math.max(8, math.min(size or 16, 80)), target = bar or frame, point = relative, anchor = anchor,
        x = tonumber(general.kickReadyOffsetX) or 4, y = tonumber(general.kickReadyOffsetY) or 0 }
end

-- Where a box really sits, read from the widget the harness keeps.
local function Live(box)
    if not box then return { count = 0 } end
    local point = box.points[1]
    return { size = box.width, height = box.height, count = #box.points, point = point and point.point,
        target = point and point.relativeTo, anchor = point and point.relativePoint, x = point and point.x,
        y = point and point.y }
end

local function SizeMoved(live, want) return live.size ~= want.size or live.height ~= want.size end
local function AnchorsMoved(live, want)
    return live.count ~= 1 or live.point ~= want.point or live.target ~= want.target or live.anchor ~= want.anchor
        or live.x ~= want.x or live.y ~= want.y
end

local function CorePath(world, suffix)
    for index = 1, #world.corePaths do
        local path = world.corePaths[index]
        if path:sub(-#suffix) == suffix then return path end
    end
end

local function RunClient(flavor)
    local world = World.New(root, { flavor = flavor })
    local ns, env = world.core, world.env
    local Castbars = ns.Castbars
    local KickReady, Config = Castbars.KickReady, Castbars.Config
    ns.Require("MSUF_EnsureDB", "interrupt-ready geometry test")(true)
    -- Read fresh: the profile code may replace the table.
    local function Profile() return env.MSUF_DB.general end

    -- Counted before the first layout: the boxes are built by the settings pass.
    local writes = setmetatable({}, { __mode = "k" })
    local Methods = world.widgets.Methods
    for _, name in ipairs({ "SetSize", "ClearAllPoints", "SetPoint" }) do
        local plain = Methods[name]
        Methods[name] = function(self, ...)
            local count = writes[self]
            if not count then
                count = { SetSize = 0, ClearAllPoints = 0, SetPoint = 0 }
                writes[self] = count
            end
            count[name] = count[name] + 1
            return plain(self, ...)
        end
    end
    local function Writes(box)
        local count = box and writes[box]
        if not count then return 0, 0, 0 end
        return count.SetSize, count.ClearAllPoints, count.SetPoint
    end

    -- Profile edits as the menu makes them, then the refresh it triggers.
    local function Apply(changes)
        local profile = Profile()
        for key, value in pairs(changes) do
            if value == NIL then profile[key] = nil else profile[key] = value end
        end
        Config.Invalidate()
    end
    Apply({ kickReadyShowTarget = true, kickReadyShowBoss = true, kickReadyStyle = "box", showGCDBar = false })
    ns.Require("MSUF_Castbars_OnSettingsChanged", "interrupt-ready geometry test")()
    world:Advance(0.5)
    for index = #world.errors, 1, -1 do world.errors[index] = nil end

    local readyFrame = assert(world:Named("MSUF_InterruptReady_EventFrame"), "interrupt-ready event frame missing")
    local context = flavor
    local function Expect(ok, message)
        if not ok then error(context .. ": " .. message, 0) end
    end

    -- One step: run it, then check the box end state and the writes it made.
    local function Step(label, frame, run)
        context = ("%s %s %s"):format(flavor, frame.unit, label)
        local before = Live(frame.kickReadyBox)
        local size0, clear0, point0 = Writes(frame.kickReadyBox)
        run()
        local box = frame.kickReadyBox
        Expect(box, "no box built")
        local want, live = Rule(frame, Profile()), Live(box)
        Expect(live.size == want.size and live.height == want.size, ("box size %s x %s, rule says %s"):format(
            tostring(live.size), tostring(live.height), tostring(want.size)))
        Expect(not AnchorsMoved(live, want), ("box anchors %s/%s/%s %s,%s x%d, rule says %s/%s/%s %s,%s"):format(
            tostring(live.point), tostring(live.target), tostring(live.anchor), tostring(live.x), tostring(live.y),
            live.count, tostring(want.point), tostring(want.target), tostring(want.anchor), tostring(want.x),
            tostring(want.y)))
        local size1, clear1, point1 = Writes(box)
        local sizeWrites, clearWrites, pointWrites = size1 - size0, clear1 - clear0, point1 - point0
        local wantSize, wantAnchors = SizeMoved(before, want) and 1 or 0, AnchorsMoved(before, want) and 1 or 0
        Expect(sizeWrites == wantSize and clearWrites == wantAnchors and pointWrites == wantAnchors,
            ("SetSize/ClearAllPoints/SetPoint ran %d/%d/%d times, expected %d/%d/%d"):format(
                sizeWrites, clearWrites, pointWrites, wantSize, wantAnchors, wantAnchors))
    end

    -- A step that must not touch the box geometry at all.
    local function Quiet(label, frame, run)
        context = ("%s %s %s"):format(flavor, frame.unit, label)
        local size0, clear0, point0 = Writes(frame.kickReadyBox)
        run()
        local size1, clear1, point1 = Writes(frame.kickReadyBox)
        Expect(size1 == size0 and clear1 == clear0 and point1 == point0,
            ("SetSize/ClearAllPoints/SetPoint ran %d/%d/%d times"):format(size1 - size0, clear1 - clear0, point1 - point0))
    end

    local EVENTS = {
        cast = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP" },
        channel = { "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" },
        empower = { "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP" },
    }
    local castID = 100
    local function Begin(frame, kind)
        castID = castID + 1
        local unit = frame.unit
        if kind == "cast" then
            world:StartCast(unit, "Frostbolt", 3, castID)
        elseif kind == "channel" then
            world:StartChannel(unit, "Drain Life", 3, castID)
        else
            world:StartChannel(unit, "Fire Breath", 3, castID, { empowered = true, spellID = 357208 })
        end
        world:Fire(frame, EVENTS[kind][1], world:Payload(EVENTS[kind][1], unit, castID))
        world:Advance(0.1)
        return castID
    end
    local function Finish(frame, kind, id)
        local unit = frame.unit
        world.casting[unit], world.channeling[unit] = nil, nil
        world:Fire(frame, EVENTS[kind][2], world:Payload(EVENTS[kind][2], unit, id))
        world:Advance(0.6)
    end

    -- One whole cast; `during` runs while it is up. The indicator shows for the
    -- cast (it is a child of the castbar, which hides with the cast's end).
    local function Cast(frame, kind, during)
        local id = Begin(frame, kind)
        local box = frame.kickReadyBox
        Expect(box and box.shown == true, kind .. " did not show the indicator")
        if during then during(frame, box) end
        Finish(frame, kind, id)
    end

    local function Layout(frame) KickReady.KickReady_ApplyLayout(frame) end

    -- Not interruptible hides the indicator, interruptible shows it again.
    local function Flip(frame, box)
        local unit = frame.unit
        world:Fire(frame, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", world:Payload("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unit))
        Expect(box.shown == false, "not interruptible left the indicator up")
        world:Fire(frame, "UNIT_SPELLCAST_INTERRUPTIBLE", world:Payload("UNIT_SPELLCAST_INTERRUPTIBLE", unit))
        Expect(box.shown == true, "interruptible did not show the indicator again")
    end

    -- The interrupt's cooldown events repaint every active indicator.
    local function Repaints()
        for _ = 1, 5 do
            world:Fire(readyFrame, "SPELL_UPDATE_COOLDOWN", INTERRUPT_SPELL, INTERRUPT_SPELL)
            world:Advance(0.02)
        end
    end

    -- Readable data only: the interrupt goes on cooldown and recovers mid-cast,
    -- repainting the indicator both ways.
    local function Recovery()
        world.cooldowns[INTERRUPT_SPELL] = { startTime = world.clock, total = 0.4 }
        world:Fire(readyFrame, "SPELL_UPDATE_COOLDOWN", INTERRUPT_SPELL, INTERRUPT_SPELL)
        world:Advance(0.5)
        world.cooldowns[INTERRUPT_SPELL] = nil
    end

    local function Restricted(on) world.secretCasts, world.secretCooldowns = on, on end

    local function Everything(frame, restricted)
        Restricted(restricted)
        local tag = restricted and "restricted" or "readable"
        Step(tag .. " layout pass", frame, function() Layout(frame) end)
        for round = 1, 3 do
            Step(("%s cast %d"):format(tag, round), frame, function() Cast(frame, "cast") end)
        end
        Step(tag .. " channel", frame, function() Cast(frame, "channel") end)
        if ns.Client.HasEmpoweredCasts == true then
            Step(tag .. " empower", frame, function() Cast(frame, "empower") end)
        end
        Step(tag .. " interruptibility flips", frame, function()
            Cast(frame, "cast", function(bar, box)
                Flip(bar, box)
                Flip(bar, box)
            end)
        end)
        Step(tag .. " cooldown repaints", frame, function() Cast(frame, "cast", Repaints) end)
        if not restricted then
            Step("cooldown recovery", frame, function() Cast(frame, "cast", Recovery) end)
        end
    end

    local function Resize(frame)
        Restricted(false)
        local bar = frame.statusBar
        local height = bar:GetHeight()
        for _, grown in ipairs({ height + 7, height + 7, 4, height }) do
            Step("castbar height " .. grown, frame, function()
                bar:SetHeight(grown)
                Layout(frame)
                Cast(frame, "cast")
                Cast(frame, "cast")
            end)
        end
        -- The first cast after a resize with no layout pass in between. Only a
        -- restricted readiness repaints every cast (a readable one dedupes the
        -- unchanged paint, as it always did, and waits for the layout pass).
        Restricted(true)
        Step("castbar height found by a cast", frame, function()
            bar:SetHeight(height + 3)
            Cast(frame, "cast")
        end)
        Restricted(false)
        Step("castbar height restored", frame, function()
            bar:SetHeight(height)
            Layout(frame)
        end)
    end

    -- Deterministic walk through the setting domains, a few settings at a time;
    -- the profile refresh (Apply) comes before every step.
    local DOMAINS = {
        kickReadyAutoSize = { NIL, true, false },
        kickReadySize = { NIL, 2, 8, 16, 20, 22.5, "24", 80, 500, "bad" },
        kickReadyAnchor = { NIL, "RIGHT", "LEFT", "TOP", "BOTTOM", "CENTER" },
        kickReadyOffsetX = { NIL, 4, -7, "9", 12.5, "x" },
        kickReadyOffsetY = { NIL, 0, 3, "-2", "y" },
    }
    local KEYS = { "kickReadyAutoSize", "kickReadySize", "kickReadyAnchor", "kickReadyOffsetX", "kickReadyOffsetY" }
    local HEIGHTS = { 8, 12, 16, 18, 24, 100 }
    local function Sweep(frame, seed, steps)
        Restricted(true)
        local bar = frame.statusBar
        local original = bar:GetHeight()
        local function Next(limit)
            seed = (seed * 16807) % 2147483647
            return seed % limit + 1
        end
        for index = 1, steps do
            local changes = {}
            for _ = 1, Next(3) - 1 do
                local key = KEYS[Next(#KEYS)]
                changes[key] = DOMAINS[key][Next(#DOMAINS[key])]
            end
            local height = Next(4) == 1 and HEIGHTS[Next(#HEIGHTS)] or nil
            Apply(changes)
            Step("sweep step " .. index, frame, function()
                if height then bar:SetHeight(height) end
                if index % 3 == 0 then Cast(frame, "cast") else Layout(frame) end
            end)
        end
        bar:SetHeight(original)
        Apply({ kickReadyAutoSize = NIL, kickReadySize = NIL, kickReadyAnchor = NIL, kickReadyOffsetX = NIL,
            kickReadyOffsetY = NIL })
        Step("sweep back to the defaults", frame, function() Layout(frame) end)
    end

    -- The refresh a menu change runs: it re-anchors the castbars and repaints.
    local function ProfileRefresh(frame)
        Restricted(true)
        local apply = Castbars.Core.ApplyAllCastbarsAndSync
        Step("unchanged profile refresh", frame, function() apply() end)
        for _, changes in ipairs({
            { kickReadyAutoSize = false, kickReadySize = 22 },
            { kickReadyAnchor = "TOP" },
            { kickReadyOffsetX = 9 },
            { kickReadyOffsetX = 9 },
            { kickReadyAutoSize = NIL, kickReadyAnchor = NIL, kickReadyOffsetX = NIL, kickReadySize = NIL },
        }) do
            Apply(changes)
            Step("profile refresh " .. tostring((next(changes))), frame, function() apply(true) end)
        end
        Step("settled profile refresh", frame, function() apply() end)
    end

    local function Toggles(frame)
        Restricted(false)
        Step("settled before toggles", frame, function()
            Layout(frame)
            Cast(frame, "cast")
        end)
        Apply({ kickReadyStyle = "border" })
        Step("border style layout", frame, function() Layout(frame) end)
        Quiet("border style cast", frame, function()
            local id = Begin(frame, "cast")
            Expect(frame.kickReadyBox.shown == false, "the border style showed the box")
            Finish(frame, "cast", id)
        end)
        Apply({ kickReadyStyle = "box" })
        Quiet("back to the box style", frame, function()
            Layout(frame)
            Cast(frame, "cast")
        end)
        local key = frame.unit == "target" and "kickReadyShowTarget" or "kickReadyShowBoss"
        Apply({ [key] = false })
        Quiet("indicator off", frame, function()
            local id = Begin(frame, "cast")
            Expect(frame.kickReadyBox.shown == false, "the box showed with its setting off")
            Finish(frame, "cast", id)
            Layout(frame)
        end)
        Apply({ [key] = true })
        Quiet("indicator on again", frame, function()
            Layout(frame)
            Cast(frame, "cast")
        end)
    end

    -- A write that raises leaves the remembered inputs alone: the next call
    -- repeats it.
    local function Raising(frame)
        Restricted(false)
        local box = frame.kickReadyBox
        for _, case in ipairs({
            { "SetPoint", { kickReadyOffsetX = 31 } },
            { "SetSize", { kickReadyAutoSize = false, kickReadySize = 31 } },
        }) do
            Apply(case[2])
            rawset(box, case[1], function() error("write failed") end)
            local ok = pcall(KickReady.KickReady_ApplyLayout, frame)
            rawset(box, case[1], nil)
            context = ("%s %s %s raising"):format(flavor, frame.unit, case[1])
            Expect(not ok, "the failing write did not reach the caller")
            Step(case[1] .. " retried", frame, function() Layout(frame) end)
        end
        Apply({ kickReadyAutoSize = NIL, kickReadySize = NIL, kickReadyOffsetX = NIL })
        Step("raising writes undone", frame, function() Layout(frame) end)
    end

    -- A pooled bar keeps its box through a disable and enable; a status bar
    -- rebuilt on the frame takes the box over.
    local function Reuse(frame)
        Restricted(false)
        local kind = frame.unit:gsub("%d+$", "")
        local pools = Castbars.Pools.order
        for index = 1, #pools do
            if pools[index].kind == kind then
                local box = frame.kickReadyBox
                Step("pool disabled and enabled", frame, function()
                    pools[index].SetEnabled(false)
                    pools[index].SetEnabled(true)
                    world:Advance(0.2)
                end)
                Expect(frame.kickReadyBox == box, "the pool built a second box")
                Step("cast after the pool re-enable", frame, function() Cast(frame, "cast") end)
            end
        end
        local old = frame.statusBar
        local bar = world.widgets:CreateFrame("StatusBar", nil, frame)
        bar:SetSize(old:GetWidth() or 100, old:GetHeight() + 5)
        frame.statusBar = bar
        Step("rebuilt status bar", frame, function() Layout(frame) end)
        Step("cast on the rebuilt status bar", frame, function() Cast(frame, "cast") end)
        frame.statusBar = old
        Step("original status bar", frame, function()
            Layout(frame)
            Cast(frame, "cast")
        end)
    end

    -- The line watcher flags a compare or truth test of a restricted value.
    local stop = world:Watch({ assert(CorePath(world, "/Castbars/MSUF_InterruptReady.lua")) })
    -- Fetched when its turn comes: a pool may have rebuilt the boss bar meanwhile.
    for _, slot in ipairs({ { "target" }, { "boss", 1 } }) do
        local frame = Castbars.Frames.Get(slot[1], slot[2])
        Expect(frame or slot[1] == "boss", "target castbar missing")
        if not frame then break end
        Everything(frame, false)
        Everything(frame, true)
        Resize(frame)
        Sweep(frame, 20261026, 60)
        ProfileRefresh(frame)
        Toggles(frame)
        Raising(frame)
        Reuse(frame)
    end
    local violations = stop()
    Expect(#violations == 0, "restricted value misuse: " .. table.concat(violations, " | "))
    Expect(#world.errors == 0, "castbar errors: " .. table.concat(world.errors, " | "))
end

for _, flavor in ipairs(CLIENTS) do RunClient(flavor) end
print(("PASS castbar_interrupt_ready_geometry (%s)"):format(table.concat(CLIENTS, ", ")))
