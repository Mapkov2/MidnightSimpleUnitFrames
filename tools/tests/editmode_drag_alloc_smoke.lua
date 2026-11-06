-- Review F7, F8, F9: the Edit Mode drag loop allocates nothing per frame.
--   F7  Snap.Apply (every drag frame with snapping on, the factory default)
--       builds no edge tables and no theme tables, with 20 shown movers.
--   F8  dragging onto an external anchor captures its rollback points into a
--       reused scratch array (and still rolls back a rectless anchor chain);
--       a boss or arena castbar drag positions its previews without a new
--       closure per tick.
--   F9  a wrapped preview pipeline call (colour wheel, slider drag) queues one
--       coalesced reforce instead of a result table, a closure and a timer per
--       call.
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
local function CheckUnitDragOffsets(Ticker, ui)
    local offsets = FindUpvalue(Ticker.EndDrag, "UnitDragOffsets")
        or FindUpvalue(Ticker.ApplyExternalDrag, "UnitDragOffsets")
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

-- F7 / F8 (Layout): the real Shell/EditMode/MSUF_EditMode_Layout*.lua ------
-- The Edit Mode layout family (Grid, Snap, Nudge, then the drag ticker) in
-- its MSUF_EditMode.xml order.
local function LoadLayoutFamily(addon, namespace)
    local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode.xml", "rb"))
    local xml = handle:read("*a")
    handle:close()
    local files = {}
    for file in xml:gmatch('<Script file="(MSUF_EditMode_Layout[%w_]*%.lua)"/>') do files[#files + 1] = file end
    assert(#files == 4, "the Edit Mode layout family changed; update this loader")
    -- Run the chunks outside the gmatch loop: chunks run from inside it leave
    -- the VM stack sized so that the first call after a full collect regrows
    -- it, which the allocation probes below would misread as drag cost.
    for _, file in ipairs(files) do
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/EditMode/" .. file))(addon, namespace)
    end
end
do
    local ns = { ExportPublic = function(name, value) _G[name] = value end }
    local general = { editModeSnapEnabled = true }
    _G.MSUF_GetGeneralDB = function() return general end
    _G.MSUF_RequestGroupGeometryApply = function() return false end
    _G.MSUF_THEME = {}
    _G.C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
    _G.InCombatLockdown = function() return false end
    local function Region()
        local r = {}
        function r:SetColorTexture() end
        function r:SetAlpha() end
        function r:Show() self.shown = true end
        function r:Hide() self.shown = false end
        function r:ClearAllPoints() end
        function r:SetSize() end
        function r:SetPoint() end
        function r:SetAllPoints() end
        function r:SetFrameStrata() end
        function r:SetFrameLevel() end
        function r:SetScript() end
        function r:CreateTexture() return Region() end
        function r:IsShown() return true end
        return r
    end
    _G.CreateFrame = function() return Region() end
    _G.UIParent = Region()
    function UIParent:GetWidth() return 1920 end
    function UIParent:GetHeight() return 1080 end
    function UIParent:GetEffectiveScale() return 1 end
    _G.WorldFrame = Region()
    local function Mover(l, b, w, h)
        local m = Region()
        function m:GetLeft() return l end
        function m:GetRight() return l + w end
        function m:GetTop() return b + h end
        function m:GetBottom() return b end
        function m:GetEffectiveScale() return 1 end
        return m
    end
    local movers = {}
    for i = 1, 20 do movers["m" .. i] = Mover(100 + i * 60, 200 + i * 20, 200, 40) end
    _G.MSUF_EM2 = {
        Util = {
            Round = function(n) return math.floor(n + 0.5) end,
            ThemeColor = function(_, fallback) return fallback end,
            IsConfigCombatLocked = function() return false end,
            BlockConfigCombatLocked = function() return false end,
        },
        Movers = { All = function() return movers end },
    }
    LoadLayoutFamily("MidnightSimpleUnitFrames", ns)
    local Snap = assert(_G.MSUF_EM2.Snap and _G.MSUF_EM2.Snap.Apply, "Snap.Apply missing")

    local snapped = 0
    local perCall = Allocated(1000, function(i)
        local x = Snap(500 + (i % 7), 400 + (i % 5), 100, 20, "dragged")
        if x ~= 500 + (i % 7) then snapped = snapped + 1 end
    end)
    Check(snapped > 0, "F7: the snap harness never snapped, so guides were not exercised")
    Check(perCall < 1, ("F7: Snap.Apply allocated %.1f bytes per drag frame with 20 shown movers"):format(perCall))

    -- F8: rollback capture for an external anchor, reused per tick.
    local Ticker = assert(_G.MSUF_EM2.Ticker, "Edit Mode ticker missing")
    local TryApplyFramePoint = FindUpvalue(Ticker.BeginDrag, "TryApplyFramePoint")
        or FindUpvalue(Ticker.EndDrag, "TryApplyFramePoint")
    if Check(type(TryApplyFramePoint) == "function", "F8: TryApplyFramePoint not reachable") then
        local external = Region()
        local rectless = Region()
        local frame = { points = { { "TOPLEFT", UIParent, "TOPLEFT", 10, -20 }, { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -5, 6 } } }
        function frame:GetNumPoints() return #self.points end
        function frame:GetPoint(i) local p = self.points[i]; if p then return p[1], p[2], p[3], p[4], p[5] end end
        function frame:ClearAllPoints() self.points = {} end
        function frame:SetPoint(point, anchor, relativePoint, x, y)
            self.points[#self.points + 1] = { point, anchor, relativePoint, x, y }
        end
        function frame:GetCenter()
            local p = self.points[1]
            if p and p[2] == rectless then return nil end
            return 1, 1
        end
        Check(TryApplyFramePoint(frame, "CENTER", rectless, "CENTER", 3, 4) == false,
            "F8: a rectless external anchor chain was accepted")
        local restored = frame.points
        Check(#restored == 2 and restored[1][1] == "TOPLEFT" and restored[1][4] == 10 and restored[1][5] == -20
            and restored[2][1] == "BOTTOMRIGHT" and restored[2][2] == UIParent and restored[2][5] == 6,
            "F8: the rollback did not restore both previous points")
        -- An allocation-free frame stand-in, so only the adapter's own work counts.
        local pointTable = { "CENTER", external, "CENTER", 0, 0 }
        frame.points = { pointTable }
        function frame:ClearAllPoints() self.points[1] = nil end
        function frame:SetPoint(point, anchor, relativePoint, x, y)
            pointTable[1], pointTable[2], pointTable[3], pointTable[4], pointTable[5] = point, anchor, relativePoint, x, y
            self.points[1] = pointTable
        end
        local captureCost = Allocated(1000, function(i)
            TryApplyFramePoint(frame, "CENTER", external, "CENTER", i % 9, 0)
        end)
        Check(captureCost < 1, ("F8: a drag tick onto an external anchor allocated %.1f bytes"):format(captureCost))
    end
    CheckUnitDragOffsets(Ticker, UIParent)
end

-- F8 (castbar previews) and F9 (pipeline wrappers): real client graphs ------
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
for _, flavor in ipairs({ "Mainline", "Mists" }) do
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local env = world.env
    env.MSUF_InitProfiles()
    local general = env.MSUF_DB.general

    -- Boss and arena castbar drags reposition every preview each tick.
    general.castbarPlayerPreviewEnabled = true
    env.MSUF_UnitEditModeActive = true
    local positioned = 0
    -- The drag path positions through each kind's preview object
    -- (Castbars/MSUF_CastbarPoolPreviews.lua); the instance field shadows the
    -- shared Position method.
    local previews = world.core.Castbars.Pools.previews
    local function CountPosition() positioned = positioned + 1 end
    previews.boss.Position = CountPosition
    previews.arena.Position = CountPosition
    for i = 1, 5 do
        env["MSUF_BossCastbarPreview" .. i] = env["MSUF_BossCastbarPreview" .. i] or env.CreateFrame("Frame")
        env["MSUF_ArenaCastbarPreview" .. i] = env["MSUF_ArenaCastbarPreview" .. i] or env.CreateFrame("Frame")
    end
    env.MSUF_BossCastbarPreview = env.MSUF_BossCastbarPreview1
    for _, unit in ipairs({ "boss", "arena" }) do
        positioned = 0
        Check(env.MSUF_PositionCastbarPreviewUnit(unit) == true and positioned > 0,
            flavor .. " F8: " .. unit .. " castbar previews were not positioned")
        local cost = Allocated(500, function() env.MSUF_PositionCastbarPreviewUnit(unit) end)
        Check(cost < 1, ("%s F8: a %s castbar drag tick allocated %.1f bytes"):format(flavor, unit, cost))
    end
    env.MSUF_UnitEditModeActive = false

    -- Wrapped pipeline calls during an Edit Mode preview: one queued reforce.
    world.core.UF.Apply = function() return true end
    local applied = 0
    local original = function() applied = applied + 1 end
    env.MSUF_ApplyAllAlpha = original
    local EM2 = env.MSUF_EM2
    Check(EM2.State.Enter("player") == true, flavor .. " F9: Edit Mode did not open")
    world.widgets:RunTimers()
    local wrapped = env.MSUF_ApplyAllAlpha
    if Check(env.MSUF_PreviewTestMode == true and wrapped ~= original,
        flavor .. " F9: the Edit Mode preview did not wrap the pipeline") then
        world.widgets:RunTimers()
        local timersBefore = world.widgets.afterCount
        for _ = 1, 60 do wrapped() end
        Check(applied == 60, flavor .. " F9: the wrapped pipeline call did not reach the original")
        Check(world.widgets.afterCount - timersBefore <= 1, flavor .. " F9: 60 wrapped calls scheduled "
            .. (world.widgets.afterCount - timersBefore) .. " preview reforces")
        local cost = Allocated(500, function() wrapped() end)
        Check(cost < 1, ("%s F9: a wrapped pipeline call allocated %.1f bytes"):format(flavor, cost))
    end
    EM2.State.Exit("test")
    world.widgets:RunTimers()
end

if #failures > 0 then
    error("editmode_drag_alloc_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_drag_alloc_smoke: ok (unit offsets, snap, external anchor rollback, castbar previews, pipeline reforce)")
