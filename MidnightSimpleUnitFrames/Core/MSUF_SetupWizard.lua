local addonName, ns = ...
ns = ns or {}
-- Basically dead file just provides anchoring hook for cooldownmanager will clean up after release---
-- ------------------------------------------------------------
local function MSUF_UFDirty(frame, reason, urgent)
    if not frame then return end
    local md = _G.MSUF_UFCore_MarkDirty
    if type(md) == "function" then
        md(frame, nil, urgent, reason)
        return
    end
    -- Fallback for older builds (should be unused once UFCore is present)
    local upd = _G.UpdateSimpleUnitFrame
    if type(upd) == "function" then
        upd(frame)
    end
end

local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitName = UnitName
local pairs = pairs
local type = type
local tostring = tostring
local string = string
local table = table
local C_Timer = C_Timer

local g, ecv, key, char, frame, btn

local function HookCooldownViewer()
    EnsureDB()
    g = MSUF_DB.general or {}
    if not g.anchorToCooldown then
        return
    end
ecv = _G["EssentialCooldownViewer"]
    if not ecv then
        return
    end
    if ecv.MSUFHooked then
        return
    end
    ecv.MSUFHooked = true
        local function realign()
        if InCombatLockdown and InCombatLockdown() then
            return
        end

        -- We cannot call the main-file local PositionUnitFrame() from here.
        -- Instead, trigger a normal frame update which will re-apply positioning.
        local frames = _G.MSUF_UnitFrames
if not frames then
    return
end

-- Prefer the global apply helper so layout (PositionUnitFrame) is re-applied correctly.
local applyKey = _G.MSUF_ApplyUnitFrameKey_Immediate
if type(applyKey) == "function" then
    applyKey("player")
    applyKey("target")
    applyKey("targettarget")
    applyKey("focus")
    return
end

-- Fallback: dirty/flush only (should be rare)
if frames.player       then MSUF_UFDirty(frames.player, "SETUP", true)       end
if frames.target       then MSUF_UFDirty(frames.target, "SETUP", true)       end
if frames.targettarget then MSUF_UFDirty(frames.targettarget, "SETUP", true) end
if frames.focus        then MSUF_UFDirty(frames.focus, "SETUP", true)        end
end
    ecv:HookScript("OnSizeChanged", realign)
    ecv:HookScript("OnShow",        realign)
    ecv:HookScript("OnHide",        realign)
    realign()
end
function MSUF_SetCooldownViewerEnabled(enabled)
    if not SetCVar then
        return
    end
    if enabled then
        SetCVar("cooldownViewerEnabled", "1")
    else
        SetCVar("cooldownViewerEnabled", "0")
    end
end
-- Public (used by main at login)
_G.MSUF_HookCooldownViewer = HookCooldownViewer
