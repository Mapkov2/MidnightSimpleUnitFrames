local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

MSUF.UF = MSUF.UF or {}
local UF = MSUF.UF

-- Blizzard unitframe ownership bridge.
-- Hides or restores Blizzard unit/cast frames according to MSUF settings while respecting
-- combat lockdown. MSUF frame creation lives elsewhere; this file only manages Blizzard frame
-- visibility/parenting hooks and compatibility globals.
local type = type
local next = next
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local UIParent = UIParent

local MAX_BOSS_FRAMES = _G.MAX_BOSS_FRAMES or 5
local hiddenParent
local hookedFrames = {}
local hookedShowFrames = {}
local softHiddenFrames = {}
local looseFrames = {}
local visibleFrames = {}
local watcher

local CASTBAR_KEYS = {
    player = "enablePlayerCastbar",
    target = "enableTargetCastbar",
    focus = "enableFocusCastbar",
    boss = "enableBossCastbar",
}

local UNIT_KEYS = {
    player = "player",
    pet = "pet",
    target = "target",
    targettarget = "targettarget",
    focus = "focus",
    focustarget = "focustarget",
    boss = "boss",
}

local function General()
    local db = _G.MSUF_DB
    return type(db) == "table" and type(db.general) == "table" and db.general or nil
end

local function ShouldHideBlizzardUnitFrames()
    local g = General()
    return not (g and g.disableBlizzardUnitFrames == false)
end

--- Blizzard's player resource bars (class resource, alt power) are anchored to
--- PlayerFrame and driven by its events. Hard-hiding that frame -- unregister
--- plus reparent onto the hidden parent -- takes them down with it. Compat mode
--- therefore only hides the frame and keeps it on UIParent with its events
--- intact. Default stays the hard hide, so existing profiles do not change
--- behaviour. Matches the hard/soft split in MSUF_UF_Group_Blizzard.lua.
local function HardKillBlizzardPlayerFrame()
    local g = General()
    return not (g and g.hardKillBlizzardPlayerFrame == false)
end

local function UnitGroup(unit)
    if type(unit) == "string" and unit:match("^boss%d*$") then
        return "boss"
    end
    if unit == "targetoftarget" or unit == "tot" then
        return "targettarget"
    end
    if unit == "focus_target" then
        return "focustarget"
    end
    return unit
end

local function ShouldHideBlizzardUnitFrame(unit)
    local g = General()
    if g and g.disableBlizzardUnitFrames == false then
        return false
    end
    local key = UNIT_KEYS[UnitGroup(unit)]
    if not key then
        return true
    end
    local db = _G.MSUF_DB
    local conf = type(db) == "table" and type(db[key]) == "table" and db[key] or nil
    return not (conf and conf.useBlizzardFrame == true)
end

-- MSUF frame creation is intentionally independent from Blizzard ownership.
-- The actual MSUF enabled state is applied by the unitframe factory spec.
local function ShouldUseMSUFUnitFrame()
    return true
end

local function ShouldUseBlizzardUnitFrame(unit)
    return not ShouldHideBlizzardUnitFrame(unit)
end

local function CastbarUnit(unit)
    if type(unit) == "string" and unit:match("^boss%d*$") then
        return "boss"
    end
    return unit
end

local function CastbarBackend(unit)
    unit = CastbarUnit(unit)
    local fn = _G.MSUF_GetCastbarBackend
    if type(fn) == "function" then
        return fn(unit)
    end
    local g = General()
    if not g then
        return "MSUF"
    end
    local key = CASTBAR_KEYS[unit]
    if not key then
        return nil
    end
    return (g[key] == false) and ((unit == "player") and "BLIZZARD" or "HIDE") or "MSUF"
end

local function ShouldUseMSUFCastbar(unit)
    return CastbarBackend(unit) == "MSUF"
end

local function ShouldUseBlizzardCastbar(unit)
    if CastbarUnit(unit) ~= "player" then
        return false
    end
    return CastbarBackend(unit) == "BLIZZARD"
end

local function ShouldHideCastbar(unit)
    return CastbarBackend(unit) == "HIDE"
end

local function HiddenParent()
    if hiddenParent then
        return hiddenParent
    end
    hiddenParent = CreateFrame("Frame", nil, UIParent)
    hiddenParent:SetAllPoints()
    hiddenParent:Hide()
    return hiddenParent
end

local function FlushLooseFrames()
    -- Protected Blizzard frames cannot always be reparented while combat is
    -- active. Queue the intended parent changes and replay them on regen.
    local parent = HiddenParent()
    for frame in next, looseFrames do
        if frame and frame.SetParent then
            frame:SetParent(parent)
        end
        looseFrames[frame] = nil
    end
    for frame in next, visibleFrames do
        if frame and frame.SetParent then
            frame:SetParent(UIParent)
        end
        visibleFrames[frame] = nil
    end
    if watcher then
        watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function EnsureWatcher()
    if watcher then
        return watcher
    end
    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", FlushLooseFrames)
    return watcher
end

-- A second unitframe addon can own the same Blizzard frame and lock it to its
-- own hidden parent. Re-asserting ours would bounce the frame between both
-- SetParent hooks until the stack overflows, so any already-hidden parent is
-- accepted: the frame stays invisible, which is all this hook has to guarantee.
-- UIParent is excluded because that is exactly the restore this hook defends
-- against. Mirrors IsHiddenFrameParent in MSUF_UF_Group_Blizzard.lua.
local function IsHiddenFrameParent(parent)
    return parent
        and parent ~= UIParent
        and parent.IsShown
        and not parent:IsShown()
end

local function ResetParent(frame, parent)
    local hidden = HiddenParent()
    if parent == hidden or IsHiddenFrameParent(parent) then
        return
    end
    if frame.GetParent and IsHiddenFrameParent(frame:GetParent()) then
        return
    end
    -- Blizzard code may restore parents after our initial hide. Protected
    -- frames are re-hidden after combat; unprotected frames can be moved now.
    if InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        looseFrames[frame] = true
        EnsureWatcher():RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        frame:SetParent(hidden)
    end
end

local function Unregister(frame)
    if frame and frame.UnregisterAllEvents then
        frame:UnregisterAllEvents()
    end
end

local function Hide(frame)
    if frame and frame.Hide then
        frame:Hide()
    end
end

local function KeepBlizzardCastbar(frame)
    if not (frame and frame.SetParent) then
        return
    end
    if InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        -- Player castbar can be intentionally handed back to Blizzard. Delay
        -- the parent restore if the castbar is protected during combat.
        visibleFrames[frame] = true
        EnsureWatcher():RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    frame:SetParent(UIParent)
end

local function HideBlizzardCastbar(frame)
    if not frame then
        return
    end
    Hide(frame)
end

local function HideIfSoftHidden(frame)
    if softHiddenFrames[frame] and frame and frame.Hide then
        frame:Hide()
    end
end

--- Compat mode for PlayerFrame: hide only. Events stay registered so Blizzard
--- keeps driving the resource bars that anchor to this frame, and the parent
--- stays UIParent so their placement survives. Blizzard re-shows PlayerFrame on
--- vehicle/art transitions, so an OnShow hook re-hides it -- the soft-path
--- counterpart to the SetParent hook the hard path installs.
local function SoftHideFrame(frame)
    if type(frame) == "string" then
        frame = _G[frame]
    end
    if not frame then
        return
    end
    softHiddenFrames[frame] = true
    Hide(frame)
    if frame.HookScript and not hookedShowFrames[frame] then
        frame:HookScript("OnShow", HideIfSoftHidden)
        hookedShowFrames[frame] = true
    end
    return frame
end

local function HandleFrame(frame, doNotReparent, unit)
    if type(frame) == "string" then
        frame = _G[frame]
    end
    if not frame then
        return
    end

    Unregister(frame)
    Hide(frame)

    if not doNotReparent and frame.SetParent then
        local parent = HiddenParent()
        if InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
            looseFrames[frame] = true
            EnsureWatcher():RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            frame:SetParent(parent)
        end
        if not hookedFrames[frame] then
            -- Hook SetParent once so later Blizzard layout refreshes cannot
            -- silently pull hidden frames back onto UIParent.
            hooksecurefunc(frame, "SetParent", ResetParent)
            hookedFrames[frame] = true
        end
    end

    local health = frame.healthBar or frame.healthbar or frame.HealthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
    local power = frame.manabar or frame.ManaBar or frame.PowerBar
    local castbar = frame.castBar or frame.spellbar or frame.CastingBarFrame
    local altPower = frame.powerBarAlt or frame.PowerBarAlt
    local auraFrame = frame.BuffFrame or frame.AurasFrame
    local petFrame = frame.petFrame or frame.PetFrame
    local totFrame = frame.totFrame or frame.TargetFrameToT
    local ccFrame = frame.CcRemoverFrame
    local debuffFrame = frame.DebuffFrame
    local pingFrame = frame.pingIconFrame or frame.PingIconFrame
    local keepCastbar = unit and ShouldUseBlizzardCastbar(unit)

    Unregister(health)
    Unregister(power)
    Unregister(altPower)
    Unregister(auraFrame)
    Unregister(petFrame)
    Unregister(totFrame)
    Unregister(ccFrame)
    Unregister(debuffFrame)
    Unregister(pingFrame)
    Hide(health)
    Hide(power)
    Hide(altPower)
    Hide(auraFrame)
    Hide(petFrame)
    Hide(totFrame)
    Hide(ccFrame)
    Hide(debuffFrame)
    Hide(pingFrame)

    if keepCastbar then
        KeepBlizzardCastbar(castbar)
    else
        Unregister(castbar)
        HideBlizzardCastbar(castbar)
    end
end

local function DisableBlizzardFrames()
    if not ShouldHideBlizzardUnitFrames() then
        return
    end

    if ShouldHideBlizzardUnitFrame("player") then
        --- PlayerFrame owns no castbar on 12.x (Blizzard_UnitFrame/Mainline/
        --- PlayerFrame.lua), so the compat path loses no castbar handling; it
        --- only skips the unregister/reparent that would take the anchored
        --- resource bars down with the frame.
        if HardKillBlizzardPlayerFrame() then
            HandleFrame(_G.PlayerFrame, nil, "player")
        else
            SoftHideFrame(_G.PlayerFrame)
        end
    end
    if ShouldHideBlizzardUnitFrame("pet") then HandleFrame(_G.PetFrame, nil, "pet") end

    -- Blizzard Target-of-Target and Focus-Target are children of their parent
    -- frames. Keeping either child therefore also keeps its Blizzard parent.
    -- A parent can still be kept while its child is suppressed independently.
    local hideTarget = ShouldHideBlizzardUnitFrame("target")
    local hideTargetTarget = ShouldHideBlizzardUnitFrame("targettarget")
    if hideTargetTarget then
        HandleFrame(_G.TargetFrameToT or (_G.TargetFrame and _G.TargetFrame.totFrame), nil, "targettarget")
    end
    if hideTarget and hideTargetTarget then
        HandleFrame(_G.TargetFrame, nil, "target")
    end

    local hideFocus = ShouldHideBlizzardUnitFrame("focus")
    local hideFocusTarget = ShouldHideBlizzardUnitFrame("focustarget")
    if hideFocusTarget then
        HandleFrame(_G.FocusFrameToT or (_G.FocusFrame and _G.FocusFrame.totFrame), nil, "focustarget")
    end
    if hideFocus and hideFocusTarget then
        HandleFrame(_G.FocusFrame, nil, "focus")
    end

    if ShouldHideBlizzardUnitFrame("boss") then
        HandleFrame(_G.BossTargetFrameContainer, nil, "boss")
        for i = 1, MAX_BOSS_FRAMES do
            HandleFrame(_G["Boss" .. i .. "TargetFrame"], true, "boss")
        end
    end
end

local function SafeDisableMouse(frame)
    if frame and frame.EnableMouse and not (frame.IsForbidden and frame:IsForbidden()) then
        frame:EnableMouse(false)
    end
end

local function ClaimBlizzardCastbarOwnership(tag, unit)
    unit = CastbarUnit(unit or "player")
    if tag == nil then
        tag = "MSUF_Unknown"
    end
    if not ShouldUseMSUFCastbar(unit) then
        UF.blizzardCastbarOwner = ShouldUseBlizzardCastbar(unit) and "Blizzard" or "Hidden"
        return false
    end
    local cur = UF.blizzardCastbarOwner
    if cur and cur ~= tag then
        return false
    end
    UF.blizzardCastbarOwner = tag
    return true
end

local function GetBlizzardCastbarOwner()
    return UF.blizzardCastbarOwner
end

UF.DisableBlizzardFrames = DisableBlizzardFrames
UF.ShouldUseMSUFUnitFrames = ShouldHideBlizzardUnitFrames
UF.ShouldUseMSUFUnitFrame = ShouldUseMSUFUnitFrame
UF.ShouldHideBlizzardUnitFrame = ShouldHideBlizzardUnitFrame
UF.ShouldUseMSUFCastbar = ShouldUseMSUFCastbar
UF.ShouldUseBlizzardCastbar = ShouldUseBlizzardCastbar
UF.ShouldHideCastbar = ShouldHideCastbar
UF.ShouldUseBlizzardUnitFrame = ShouldUseBlizzardUnitFrame
UF.SafeDisableMouse = SafeDisableMouse
UF.ClaimBlizzardCastbarOwnership = ClaimBlizzardCastbarOwnership
UF.GetBlizzardCastbarOwner = GetBlizzardCastbarOwner
