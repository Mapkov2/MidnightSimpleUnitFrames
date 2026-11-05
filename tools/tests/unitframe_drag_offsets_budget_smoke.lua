-- The unit drag coordinate helper has no per-tick allocations.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Allocated(calls, fn)
    for i = 1, 50 do fn(i) end
    collectgarbage("collect")
    collectgarbage("stop")
    -- A full collect may halve the VM stack, and the first deep call after it
    -- regrows the stack once. Two identical passes with the collector stopped
    -- (the stack cannot shrink again until it runs) and only the second one
    -- counted keep that one-time regrowth out of the per-call figure.
    local before
    for _ = 1, 2 do
        before = collectgarbage("count")
        for i = 1, calls do fn(i) end
    end
    local after = collectgarbage("count")
    collectgarbage("restart")
    return (after - before) * 1024 / calls
end

-- Finds a local function by name through the upvalue chain of `fn`.
local function FindUpvalue(fn, name, seen)
    seen = seen or {}
    if type(fn) ~= "function" or seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 255 do
        local upName, value = debug.getupvalue(fn, i)
        if not upName then break end
        if upName == name then return value end
        local found = type(value) == "function" and FindUpvalue(value, name, seen)
        if found then return found end
    end
end

-- UnitDragOffsets converts the current screen position into a live anchor.
-- Budgets cover this helper only: CENTER/UIParent needs one anchor center
-- read, CENTER/foreign also needs its scale. Non-center points read the
-- dimensions/edges they use. Native stand-ins allocate nothing themselves.
local function CheckUnitDragOffsets(Ticker, ui, move)
    local offsets = FindUpvalue(Ticker.EndDrag, "UnitDragOffsets")
        or FindUpvalue(Ticker.ApplyExternalDrag, "UnitDragOffsets")
        or FindUpvalue(move, "UnitDragOffsets")
    assert(type(offsets) == "function", "UnitDragOffsets not reachable")
    local calls, centers, scales, dimensions, edges = 0, 0, 0, 0, 0
    local function Center(self)
        calls, centers = calls + 1, centers + 1
        return self.cx, self.cy
    end
    local function Scale(self)
        calls, scales = calls + 1, scales + 1
        return self.scale
    end
    local function Width(self)
        calls, dimensions = calls + 1, dimensions + 1
        return self.width
    end
    local function Height(self)
        calls, dimensions = calls + 1, dimensions + 1
        return self.height
    end
    local function Left(self)
        calls, edges = calls + 1, edges + 1
        return self.cx - self.width / 2
    end
    local function Right(self)
        calls, edges = calls + 1, edges + 1
        return self.cx + self.width / 2
    end
    local function Top(self)
        calls, edges = calls + 1, edges + 1
        return self.cy + self.height / 2
    end
    local function Bottom(self)
        calls, edges = calls + 1, edges + 1
        return self.cy - self.height / 2
    end
    local function Native(frame)
        frame.GetCenter, frame.GetEffectiveScale = Center, Scale
        frame.GetWidth, frame.GetHeight = Width, Height
        frame.GetLeft, frame.GetRight, frame.GetTop, frame.GetBottom = Left, Right, Top, Bottom
        return frame
    end
    Native(ui)
    local foreign, bar = Native({}), Native({})
    local d = { bar = bar, unitCenterDX = 11, unitCenterDY = -7, unitBaseX = 19, unitBaseY = -13,
        unitBiasX = .25, unitBiasY = -.25, unitStartX = -200.25, unitStartY = 80.25 }
    local scenarios = {
        { name = "CENTER/UIParent", anchor = ui, point = "CENTER", relative = "CENTER",
            calls = 1, centers = 1, scales = 0, dimensions = 0, edges = 0 },
        { name = "CENTER/foreign", anchor = foreign, point = "CENTER", relative = "CENTER",
            calls = 2, centers = 1, scales = 1, dimensions = 0, edges = 0 },
        { name = "TOPLEFT/UIParent", anchor = ui, point = "TOPLEFT", relative = "CENTER",
            calls = 3, centers = 1, scales = 0, dimensions = 2, edges = 0 },
        { name = "TOPLEFT/foreign BOTTOMRIGHT", anchor = foreign, point = "TOPLEFT", relative = "BOTTOMRIGHT",
            calls = 7, centers = 0, scales = 1, dimensions = 2, edges = 4 },
    }
    for _, scenario in ipairs(scenarios) do
        d.anchor, d.point, d.relativePoint = scenario.anchor, scenario.point, scenario.relative
        calls, centers, scales, dimensions, edges = 0, 0, 0, 0, 0
        local ticks, changed, wrong, lastX, lastY = 0, 0, 0
        local function Tick(i)
            local uiScale, frameScale = .6 + (i % 5) * .1, .8 + (i % 7) * .15
            ui.cx, ui.cy, ui.scale, ui.width, ui.height = 720 + i % 11, 480 - i % 13, uiScale, 1440, 960
            foreign.cx, foreign.cy, foreign.scale = 400 - i % 17, 300 + i % 19, .75 + (i % 3) * .2
            foreign.width, foreign.height = 200 + i % 5, 90 + i % 7
            bar.width, bar.height = 160 + (i % 3) * 13, 40 + (i % 4) * 7
            local mouseX, mouseY = 600 + i % 23, 350 - i % 29
            local x, y = offsets(d, mouseX, mouseY, uiScale, frameScale)
            ticks = ticks + 1
            if x ~= lastX or y ~= lastY then changed = changed + 1 end
            lastX, lastY = x, y
            -- Scalar oracle uses fixture fields, so its arithmetic introduces
            -- no native calls and cannot hide an extra read by the helper.
            local anchorX, anchorY = d.anchor.cx, d.anchor.cy
            if scenario.relative == "BOTTOMRIGHT" then
                anchorX, anchorY = anchorX + foreign.width / 2, anchorY - foreign.height / 2
            end
            local ownX, ownY = 0, 0
            if scenario.point == "TOPLEFT" then ownX, ownY = -bar.width / 2, bar.height / 2 end
            local expectedX = (mouseX * uiScale - anchorX * d.anchor.scale) / frameScale + 11 + ownX - 19 + .25
            local expectedY = (mouseY * uiScale - anchorY * d.anchor.scale) / frameScale - 7 + ownY + 13 - .25
            -- 6.5's isolated fixture and the real 7.0 controller use different
            -- tie rules. Both must stay within half a unit of this raw position.
            if math.abs(x - expectedX) > .500001 or math.abs(y - expectedY) > .500001 then wrong = wrong + 1 end
        end
        -- Keep the smaller of two runs: full collection can shrink VM state.
        local cost = math.min(Allocated(2000, Tick), Allocated(2000, Tick))
        Check(wrong == 0 and changed > 2000, scenario.name .. ": changing geometry was not exercised correctly")
        Check(cost == 0, ("%s: UnitDragOffsets allocated %.3f bytes/tick"):format(scenario.name, cost))
        Check(calls == ticks * scenario.calls and centers == ticks * scenario.centers
            and scales == ticks * scenario.scales and dimensions == ticks * scenario.dimensions and edges == ticks * scenario.edges,
            ("%s: native reads/tick %.1f (center %.1f, scale %.1f, dimensions %.1f, edges %.1f), budget %d")
                :format(scenario.name, calls / ticks, centers / ticks, scales / ticks, dimensions / ticks, edges / ticks, scenario.calls))
        print(("UnitDragOffsets %s: %.3f bytes/tick, %.1f native reads/tick"):format(scenario.name, cost, calls / ticks))
    end
end

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, "Forever"):Boot()
local failure = world:FirstFailure()
assert(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local EM2 = world.core.EditModeController or world.core.PublicGlobals.MSUF_EM2 or world.env.MSUF_EM2
CheckUnitDragOffsets(assert(EM2 and EM2.Ticker), world.env.UIParent, world.core.EditModeKinds.unit.move)
if #failures > 0 then error("unitframe_drag_offsets_budget_smoke failed:\n  " .. table.concat(failures, "\n  ")) end
print("unitframe_drag_offsets_budget_smoke: PASS")
