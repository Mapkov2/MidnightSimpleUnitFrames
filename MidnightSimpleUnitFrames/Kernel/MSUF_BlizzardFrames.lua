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
local blizzardAuraHiddenParent
local buffAuraOriginalParent
local buffAuraSuppressedByMSUF = false
local debuffAuraSuppressedByMSUF = false

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

--- Blizzard ownership is per unit: only an explicit useBlizzardFrame keeps the
--- native frame alive. Everything MSUF can own is suppressed by default.
local function ShouldHideBlizzardUnitFrame(unit)
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

--- The minimap-adjacent player BuffFrame and DebuffFrame are ordinary,
--- unprotected Blizzard Edit Mode frames on 12.1. Suppression is passive:
--- BuffFrame is parented below one permanently hidden frame, while the normal
--- Debuff AuraContainer is hidden without changing its hierarchy. Blizzard can
--- keep updating its own state without any MSUF hook, event, timer, or OnUpdate.
--- DebuffFrame's normal icons live below
--- AuraContainer while PrivateAuraAnchors are direct siblings. The container
--- itself must retain DebuffFrame as its parent because Blizzard's
--- AuraContainerMixin:UpdateGridLayout calls self:GetParent():UpdateSize().
local function BlizzardAuraHideSettings()
    local db = _G.MSUF_DB
    local auras = type(db) == "table" and type(db.auras3) == "table" and db.auras3 or nil
    local shared = type(auras) == "table" and type(auras.shared) == "table" and auras.shared or nil
    if not shared then return false, false end
    local legacy = shared.hideBlizzardAuraFrames == true
    return legacy or shared.hideBlizzardBuffFrame == true,
        legacy or shared.hideBlizzardDebuffFrame == true
end

local function EnsureBlizzardAuraHiddenParent()
    if blizzardAuraHiddenParent then return blizzardAuraHiddenParent end
    blizzardAuraHiddenParent = CreateFrame("Frame", nil, UIParent)
    blizzardAuraHiddenParent:Hide()
    return blizzardAuraHiddenParent
end

local function CanMutateBlizzardAuraFrame(frame)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return false end
    -- These frames are unprotected in Blizzard_BuffFrame on 12.1. If that ever
    -- changes, fail closed instead of adding a combat event or touching a
    -- protected frame. This keeps the feature at zero recurring MSUF CPU.
    if frame.IsProtected and frame:IsProtected() then return false end
    return true
end

local function SetPassiveBlizzardBuffSuppression(frame, suppress, originalParent, owned)
    if not CanMutateBlizzardAuraFrame(frame) then
        return originalParent, owned, nil
    end
    if not suppress and not owned then
        return originalParent, owned, nil
    end
    local hidden = EnsureBlizzardAuraHiddenParent()
    if suppress then
        if not owned then
            originalParent = frame:GetParent()
        end
        if frame:GetParent() ~= hidden then frame:SetParent(hidden) end
        return originalParent, true, "hidden"
    end

    if owned then
        if frame:GetParent() == hidden then frame:SetParent(originalParent or UIParent) end
        return nil, false, "restored"
    end
    return originalParent, owned, nil
end

local function SetPassiveBlizzardDebuffSuppression(container, suppress, owned)
    if not CanMutateBlizzardAuraFrame(container) then return owned end
    local shown = container.IsShown and container:IsShown() == true
    if suppress then
        if shown then
            container:Hide()
            return true
        end
        return owned
    end
    if owned then
        container:Show()
        return false
    end
    return owned
end

local function ApplyBlizzardAuraVisibility()
    local hideBuffs, hideDebuffs = BlizzardAuraHideSettings()
    local buffFrame = _G.BuffFrame
    local debuffFrame = _G.DebuffFrame

    buffAuraOriginalParent, buffAuraSuppressedByMSUF = SetPassiveBlizzardBuffSuppression(
        buffFrame, hideBuffs, buffAuraOriginalParent, buffAuraSuppressedByMSUF)

    local debuffContainer = debuffFrame and debuffFrame.AuraContainer
    debuffAuraSuppressedByMSUF = SetPassiveBlizzardDebuffSuppression(
        debuffContainer, hideDebuffs, debuffAuraSuppressedByMSUF)
    return buffAuraSuppressedByMSUF, debuffAuraSuppressedByMSUF
end

local function DisableBlizzardFrames()
    --- PlayerFrame owns no castbar on 12.x (Blizzard_UnitFrame/Mainline/
    --- PlayerFrame.lua), so suppressing it loses no castbar handling. Keep
    --- Blizzard's anchored resource bars by turning the player unit's
    --- useBlizzardFrame on instead.
    if ShouldHideBlizzardUnitFrame("player") then
        HandleFrame(_G.PlayerFrame, nil, "player")
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

    ApplyBlizzardAuraVisibility()
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
UF.ApplyBlizzardAuraVisibility = ApplyBlizzardAuraVisibility
UF.ShouldUseMSUFUnitFrame = ShouldUseMSUFUnitFrame
UF.ShouldHideBlizzardUnitFrame = ShouldHideBlizzardUnitFrame
UF.ShouldUseMSUFCastbar = ShouldUseMSUFCastbar
UF.ShouldUseBlizzardCastbar = ShouldUseBlizzardCastbar
UF.ShouldHideCastbar = ShouldHideCastbar
UF.ShouldUseBlizzardUnitFrame = ShouldUseBlizzardUnitFrame
UF.SafeDisableMouse = SafeDisableMouse
UF.ClaimBlizzardCastbarOwnership = ClaimBlizzardCastbarOwnership
UF.GetBlizzardCastbarOwner = GetBlizzardCastbarOwner

-- Blizzard_BuffFrame is a non-LoD Blizzard addon on 12.1, so its frames exist
-- before MSUF loads. Apply once at file load; profile/toggle changes call this
-- bridge explicitly. There is deliberately no late-load watcher or polling.
ApplyBlizzardAuraVisibility()
