-- MSUF_UpdateCastbarEditInfo (quality program W-C6): castbar code calls it
-- after it moves a castbar (MSUF_ApplyCastbarUnitAndSync, behind the menu, the
-- castbar popup and the castbar preview drag). It used to do nothing, so with
-- Edit Mode open a castbar moved from the menu left its mover and the
-- toolbar's X/Y readout at the old place. On the real core and Options graphs
-- (tools/tests/client_world.lua):
--   * outside Edit Mode it does nothing;
--   * in Edit Mode the castbar's mover goes back onto the moved castbar and the
--     toolbar readout follows when that castbar is selected;
--   * a call allocates nothing (the castbar preview drag calls it per tick).
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Allocated(calls, fn)
    for i = 1, 50 do fn(i) end
    collectgarbage("collect")
    collectgarbage("stop")
    -- Two identical passes with the collector stopped; only the second counts,
    -- so a one-time VM stack regrowth after the collect is not read as cost.
    local before
    for _ = 1, 2 do
        before = collectgarbage("count")
        for i = 1, calls do fn(i) end
    end
    local after = collectgarbage("count")
    collectgarbage("restart")
    return (after - before) * 1024 / calls
end

local function MoverLeft(mover)
    local point, _, _, x = mover:GetPoint(1)
    return point == "TOPLEFT" and x or nil
end

local function Run(flavor)
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local env, core = world.env, world.core
    core.UF.Apply = function() return true end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    core.FinalizeLocale()
    env.MSUF_InitProfiles()
    env.MSUF2.ApplyService.Flush = function() return true end
    local EM2 = env.MSUF_EM2
    local context = flavor .. " castbar edit info"
    local update = env.MSUF_UpdateCastbarEditInfo
    if not Check(type(update) == "function", context .. ": MSUF_UpdateCastbarEditInfo is not published") then return end
    Check(update("player") == false, context .. ": it acted outside Edit Mode")

    if not Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open") then return end
    world.widgets:RunTimers()
    local cfg = EM2.Registry.Get("castbar_player")
    local castbar = cfg and cfg.getFrame and cfg.getFrame()
    local mover = EM2.Movers.Get("castbar_player")
    if not Check(castbar ~= nil and mover ~= nil, context .. ": no player castbar mover in Edit Mode") then return end

    -- The castbar module moves the castbar; its frame rect is what the mover
    -- and the readout measure.
    castbar.left, castbar.bottom = (castbar.left or 0) + 41, (castbar.bottom or 0) - 23
    EM2.State.SetUnitKey("castbar_player")
    EM2.HUD.RefreshControls(true)
    local readout = EM2.HUDDock.inspectorMetricFS[1]
    castbar.left = castbar.left + 37
    env.MSUF_ApplyCastbarUnitAndSync("player")
    Check(MoverLeft(mover) == math.floor(castbar.left + 0.5), context .. ": the mover stayed at "
        .. tostring(MoverLeft(mover)) .. " after the castbar moved to " .. tostring(castbar.left))
    local x = EM2.Util.FramePositionValues(castbar)
    Check(readout and readout:GetText() == "X " .. tostring(x), context .. ": the toolbar readout shows "
        .. tostring(readout and readout:GetText()) .. ", not X " .. tostring(x))

    -- Its own cost, with the castbar not selected (the readout refresh is the
    -- toolbar's) and allocation-free stand-ins for the harness's point setters
    -- (the stub records each SetPoint in a new table; the client does not).
    EM2.State.SetUnitKey("player")
    local point = { "TOPLEFT", env.UIParent, "TOPLEFT", 0, 0 }
    function mover:ClearAllPoints() self.points[1] = nil end
    function mover:SetPoint(p, relativeTo, relativePoint, px, py)
        point[1], point[2], point[3], point[4], point[5] = p, relativeTo, relativePoint, px, py
        self.points[1] = point
    end
    function mover:GetPoint() return point[1], point[2], point[3], point[4], point[5] end
    function mover:SetSize() end
    local cost = Allocated(500, function() update("player") end)
    Check(cost < 1, ("%s: a call allocated %.1f bytes"):format(context, cost))
    Check(MoverLeft(mover) == math.floor(castbar.left + 0.5), context .. ": the measured calls stopped placing the mover")

    EM2.State.Exit("test")
    world.widgets:RunTimers()
    Check(update("player") == false, context .. ": it acted after Edit Mode closed")
end

for _, flavor in ipairs({ "Mainline", "Vanilla" }) do
    Run(flavor)
end

if #failures > 0 then
    error("editmode_castbar_edit_info_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_castbar_edit_info_smoke: ok (castbar mover and readout follow on Mainline and Vanilla)")
