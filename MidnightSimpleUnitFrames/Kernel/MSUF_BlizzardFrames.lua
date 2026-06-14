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

local function ShouldUseMSUFUnitFrames()
    local g = General()
    return not (g and g.disableBlizzardUnitFrames == false)
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

local function ShouldUseMSUFUnitFrame(unit)
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

local function ResetParent(frame, parent)
    local hidden = HiddenParent()
    if parent == hidden then
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

local function BlizzardCastbarOnShow(frame)
    if frame and frame.MSUF_BackendAllowShown then
        return
    end
    Hide(frame)
end

local function KeepBlizzardCastbar(frame)
    if not (frame and frame.SetParent) then
        return
    end
    frame.MSUF_BackendAllowShown = true
    frame.showCastbar = true
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
    frame.MSUF_BackendAllowShown = false
    frame.showCastbar = false
    Hide(frame)
    if not frame.MSUF_BackendHideHooked and frame.HookScript then
        frame.MSUF_BackendHideHooked = true
        frame:HookScript("OnShow", BlizzardCastbarOnShow)
    end
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
    local keepCastbar = unit and ShouldUseBlizzardCastbar(unit)

    Unregister(health)
    Unregister(power)
    Unregister(altPower)
    Unregister(auraFrame)
    Unregister(petFrame)
    Unregister(totFrame)
    Unregister(ccFrame)
    Unregister(debuffFrame)
    Hide(health)
    Hide(power)
    Hide(altPower)
    Hide(auraFrame)
    Hide(petFrame)
    Hide(totFrame)
    Hide(ccFrame)
    Hide(debuffFrame)

    if keepCastbar then
        KeepBlizzardCastbar(castbar)
    else
        Unregister(castbar)
        HideBlizzardCastbar(castbar)
    end
end

local function DisableBlizzardFrames()
    if not ShouldUseMSUFUnitFrames() then
        return
    end

    if ShouldUseMSUFUnitFrame("player") then HandleFrame(_G.PlayerFrame, nil, "player") end
    if ShouldUseMSUFUnitFrame("pet") then HandleFrame(_G.PetFrame, nil, "pet") end
    if ShouldUseMSUFUnitFrame("target") then HandleFrame(_G.TargetFrame, nil, "target") end
    if ShouldUseMSUFUnitFrame("targettarget") then HandleFrame(_G.TargetFrameToT, nil, "targettarget") end
    if ShouldUseMSUFUnitFrame("focus") then HandleFrame(_G.FocusFrame, nil, "focus") end
    if ShouldUseMSUFUnitFrame("focustarget") and _G.FocusFrame and _G.FocusFrame.totFrame then
        HandleFrame(_G.FocusFrame.totFrame, nil, "focustarget")
    end

    if ShouldUseMSUFUnitFrame("boss") then
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
UF.ShouldUseMSUFUnitFrames = ShouldUseMSUFUnitFrames
UF.ShouldUseMSUFUnitFrame = ShouldUseMSUFUnitFrame
UF.ShouldUseMSUFCastbar = ShouldUseMSUFCastbar
UF.ShouldUseBlizzardCastbar = ShouldUseBlizzardCastbar
UF.ShouldHideCastbar = ShouldHideCastbar
UF.ShouldUseBlizzardUnitFrame = function(unit)
    return not ShouldUseMSUFUnitFrame(unit)
end
UF.SafeDisableMouse = SafeDisableMouse
UF.ClaimBlizzardCastbarOwnership = ClaimBlizzardCastbarOwnership
UF.GetBlizzardCastbarOwner = GetBlizzardCastbarOwner
