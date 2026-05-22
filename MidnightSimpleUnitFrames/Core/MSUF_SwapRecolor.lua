-- Swap Recolor Driver (event-only, ultra cheap)
-- Fixes HP bar color/gradient/background sticking after target/focus/ToT swap.
-- The HeavyVisual bridge stays in MidnightSimpleUnitFrames.lua because it needs
-- that file's local MSUF_UFStep_HeavyVisual.

local G = _G
local dirtyTarget, dirtyToT, dirtyFocus = false, false, false
local pendingDriver = nil

local function DoRecolor()
    local dt, dtt, df = dirtyTarget, dirtyToT, dirtyFocus
    dirtyTarget, dirtyToT, dirtyFocus = false, false, false
    local force = G.MSUF_ForceReapplyHPBarColor
    if type(force) ~= "function" then return end

    if dt then
        local f = G.MSUF_target
        if f and f.unit == "target" then
            force(f, "target")
        end
    end
    if dtt then
        local tot = G.MSUF_targettarget
        if tot and tot.unit == "targettarget" then
            force(tot, "targettarget")
        end
    end
    if df then
        local fo = G.MSUF_focus
        if fo and fo.unit == "focus" then
            force(fo, "focus")
        end
    end
end

local function Flush()
    local driver = pendingDriver
    pendingDriver = nil
    if driver then
        driver._msufSwapRecolorQueued = false
    end
    DoRecolor()
end

local function Schedule(driver)
    if not driver or driver._msufSwapRecolorQueued then return end
    driver._msufSwapRecolorQueued = true
    if C_Timer and C_Timer.After then
        pendingDriver = driver
        C_Timer.After(0, Flush)
    else
        driver._msufSwapRecolorQueued = false
        DoRecolor()
    end
end

local function OnTargetChanged()
    dirtyTarget = true
    dirtyToT = true
    Schedule(G.MSUF_SwapRecolorDriver)
end

local function OnFocusChanged()
    dirtyFocus = true
    Schedule(G.MSUF_SwapRecolorDriver)
end

G.MSUF_SwapRecolor_OnUnitTargetChanged = G.MSUF_SwapRecolor_OnUnitTargetChanged or function()
    dirtyToT = true
    Schedule(G.MSUF_SwapRecolorDriver)
end

G.MSUF_EnsureSwapRecolorDriver = G.MSUF_EnsureSwapRecolorDriver or function()
    if G.MSUF_SwapRecolorDriver then return G.MSUF_SwapRecolorDriver end

    local d = CreateFrame("Frame", "MSUF_SwapRecolorDriver", UIParent)
    d._msufSwapRecolorQueued = false
    G.MSUF_SwapRecolorDriver = d

    MSUF_EventBus_Register("PLAYER_TARGET_CHANGED", "MSUF_SWAP_RECOLOR", OnTargetChanged)
    MSUF_EventBus_Register("PLAYER_FOCUS_CHANGED", "MSUF_SWAP_RECOLOR_FOCUS", OnFocusChanged)

    return d
end

if G.MSUF_EnsureSwapRecolorDriver then
    G.MSUF_EnsureSwapRecolorDriver()
end
