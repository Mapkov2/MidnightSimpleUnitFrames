local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local UF = MSUF.UF
if not UF then return end

local RegisterStateDriver = _G.RegisterStateDriver
local UnregisterStateDriver = _G.UnregisterStateDriver
local SecureCmdOptionParse = _G.SecureCmdOptionParse
local InCombatLockdown = _G.InCombatLockdown
local UnitAffectingCombat = _G.UnitAffectingCombat
local IsInInstance = _G.IsInInstance
local Secrets = MSUF.Secrets or {}
local UnitExistsPlain = Secrets.UnitExistsPlain or function(_) return true end
local type = type
local tonumber = tonumber

local EMPTY_EVENTS = {}
local FALLBACK_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "UNIT_ENTERED_VEHICLE",
    "UNIT_EXITED_VEHICLE",
    "PLAYER_UPDATE_RESTING",
    "GROUP_ROSTER_UPDATE",
    "UPDATE_STEALTH",
    "ZONE_CHANGED_NEW_AREA",
}
local PREVIEW_UNITS = {
    target = true,
    focus = true,
    targettarget = true,
    focustarget = true,
    pet = true,
}
local BOSS_PREVIEW_UNITS = {
    boss1 = true,
    boss2 = true,
    boss3 = true,
    boss4 = true,
    boss5 = true,
}
local BOSS_PREVIEW_REFRESH_ELEMENTS = {
    "Power",
    "Text",
    "NameText",
    "HealthText",
    "PowerText",
    "Portrait",
    "Borders",
}

local LoadConditions = {}

local function BossPreviewCombatLocked()
    return (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player"))
        or _G.MSUF_InCombat == true
end

local function InInstance()
    if not IsInInstance then
        return false
    end
    local inside = IsInInstance()
    return inside == true or inside == 1
end

local function ShouldForcePreview(frame)
    if not frame then
        return false
    end
    local unit = frame.unit
    if PREVIEW_UNITS[unit] == true then
        return _G.MSUF_PreviewTestMode == true
    end
    if BOSS_PREVIEW_UNITS[unit] == true then
        return _G.MSUF_BossTestMode == true
            or _G.MSUF2_BossUnitframePreviewActive == true
            or _G.MSUF_PreviewTestMode == true
    end
    return false
end

local function BuildVisibility(frame, spec)
    if not (frame and spec) or spec.enabled == false then
        return "hide"
    end
    if ShouldForcePreview(frame) then
        return "show"
    end

    local load = spec.load
    if load and load.hideInInstance == true and InInstance() then
        return "hide"
    end

    local unit = spec.unit or frame.unit
    if type(unit) ~= "string" or unit == "" then
        unit = "player"
    end

    local rules = frame._msufLoadRules
    if not rules then
        rules = {}
        frame._msufLoadRules = rules
    end
    local n = 0
    if load then
        if load.hideMounted == true then n = n + 1; rules[n] = "[mounted] hide" end
        if load.hideInVehicle == true then
            n = n + 1; rules[n] = "[@player,unithasvehicleui] hide"
            n = n + 1; rules[n] = "[vehicleui] hide"
        end
        if load.hideResting == true then n = n + 1; rules[n] = "[resting] hide" end
        if load.hideInCombat == true then n = n + 1; rules[n] = "[combat] hide" end
        if load.hideOutOfCombat == true then n = n + 1; rules[n] = "[nocombat] hide" end
        if load.hideStealthed == true then n = n + 1; rules[n] = "[stealth] hide" end
        if load.hideSolo == true then n = n + 1; rules[n] = "[nogroup] hide" end
        if load.hideInGroup == true then n = n + 1; rules[n] = "[group] hide" end
    end
    n = n + 1
    rules[n] = "[@" .. unit .. ",exists] show"
    n = n + 1
    rules[n] = "hide"
    for i = n + 1, #rules do
        rules[i] = nil
    end
    return table.concat(rules, "; ")
end

local function RegisterVisibility(frame, spec)
    local visibility = BuildVisibility(frame, spec)
    frame._msufVisibilityManaged = true
    if RegisterStateDriver then
        if frame._msufVisibilityExpr ~= visibility then
            if InCombatLockdown and InCombatLockdown() then
                UF.MarkDirty(frame.unit)
                if UF.Factory and UF.Factory.EnsureDeferredDriver then
                    UF.Factory.EnsureDeferredDriver()
                end
                return false
            end
            RegisterStateDriver(frame, "visibility", visibility)
            frame._msufVisibilityExpr = visibility
        end
        return true
    end

    local show = visibility == "show"
    if visibility ~= "hide" and SecureCmdOptionParse then
        show = SecureCmdOptionParse(visibility) == "show"
    elseif visibility ~= "hide" then
        show = UnitExistsPlain(frame.unit)
    end
    if frame._msufLoadShown ~= show then
        frame:SetShown(show)
        frame._msufLoadShown = show
    end
    return true
end

function LoadConditions.GetUnitlessEvents(frame, spec)
    local load = spec and spec.load
    if not load or load.active ~= true then
        return EMPTY_EVENTS
    end
    if not RegisterStateDriver then
        return FALLBACK_EVENTS
    end
    return load.unitlessEvents or EMPTY_EVENTS
end

function LoadConditions.Apply(frame, spec)
    RegisterVisibility(frame, spec)
end

function LoadConditions.Update(frame)
    RegisterVisibility(frame, frame and frame.MSUFSpec)
end

function LoadConditions.Disable(frame)
    if not frame then
        return
    end
    frame._msufVisibilityManaged = nil
    frame._msufVisibilityExpr = nil
    if UnregisterStateDriver then
        UnregisterStateDriver(frame, "visibility")
    end
end

UF.RegisterElement("LoadConditions", LoadConditions)

function UF.RefreshVisibilityDrivers(unit)
    return UF.RefreshElements(unit, { "LoadConditions" }, "MSUF_LOAD_CONDITIONS")
end

_G.MSUF_RefreshAllUnitVisibilityDrivers = function()
    return UF.RefreshVisibilityDrivers(nil)
end

local function SetShown(frame, shown)
    if not frame then
        return
    end
    if frame.SetShown then
        frame:SetShown(shown == true)
    elseif shown then
        frame:Show()
    else
        frame:Hide()
    end
end

local function SetBarPreview(bar, value, maxValue, r, g, b)
    if not bar then
        return
    end
    if bar.SetMinMaxValues then
        bar:SetMinMaxValues(0, maxValue)
    end
    if bar.SetValue then
        bar:SetValue(value)
    end
    if bar.SetStatusBarColor then
        bar:SetStatusBarColor(r, g, b, 1)
    end
    SetShown(bar, true)
end

local function BossPreviewPercent(unit)
    return unit == "boss1" and 55 or 72
end

local function BossPreviewPowerPercent()
    return 100
end

local function ApplyBossPreviewText(frame, hp, hpMax, power, powerMax)
    if not frame then
        return
    end
    if frame.nameText then
        frame.nameText:SetText("Boss Preview")
        SetShown(frame.nameText, true)
    end
    if frame.levelText then
        frame.levelText:SetText("??")
        SetShown(frame.levelText, true)
    end

    local text = MSUF and MSUF.UFText
    local rt = frame._msufTextRuntime
    if not (text and text.UpdateTextSlots and rt) then
        return
    end
    rt.healthMissing = nil
    rt.healthTextPending = nil
    rt.nextHealthTextTime = nil
    text.UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.unit, BossPreviewPercent, rt.healthNeedsPercent, rt)

    rt.powerTextPending = nil
    rt.nextPowerTextTime = nil
    text.UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.unit, BossPreviewPowerPercent, rt.powerNeedsPercent, rt)
end

local function ApplyBossPreviewFrameData(frame, index)
    if not frame then
        return
    end
    index = tonumber(index) or 1
    local hpMax = 1000000
    local hp = index == 1 and 550000 or 720000
    local powerMax = 240000
    local power = powerMax

    frame._msufBossPreviewForced = true
    local state = frame._msufUnitState
    if type(state) == "table" then
        state.exists = true
        state.existsKnown = true
        state.dead = false
        state.connected = true
        state.npcKind = "npcBoss"
        state.npcKindKnown = true
    end

    SetBarPreview(frame.hpBar or frame.Health, hp, hpMax, 0.74, 0.11, 0)
    SetBarPreview(frame.targetPowerBar or frame.powerBar or frame.Power, power, powerMax, 0.05, 0.64, 0.92)
    ApplyBossPreviewText(frame, hp, hpMax, power, powerMax)
end

local function RefreshBossAuras()
    local A3 = MSUF and MSUF.MSUF_Auras3 or _G.MSUF_Auras3
    local refreshUnit = (A3 and A3.RefreshUnit) or _G.MSUF_Auras3_RefreshUnit or _G.MSUF_A3_RefreshUnit
    if type(refreshUnit) == "function" then
        for i = 1, 5 do
            refreshUnit("boss" .. i)
        end
        return
    end
    if A3 and type(A3.RefreshAll) == "function" then
        A3.RefreshAll()
    elseif type(_G.MSUF_Auras3_RefreshAll) == "function" then
        _G.MSUF_Auras3_RefreshAll()
    end
end

function UF.ApplyBossPreviewState(active, reason)
    active = active == true
    if BossPreviewCombatLocked() then
        return false
    end

    local refreshReason = reason or "MSUF_BOSS_PREVIEW"
    UF.RefreshVisibilityDrivers("boss")
    if active and type(UF.RefreshElements) == "function" then
        UF.RefreshElements("boss", BOSS_PREVIEW_REFRESH_ELEMENTS, refreshReason)
    end
    UF.UpdateRuntime("boss", refreshReason)

    for i = 1, 5 do
        local frame = UF.frames and UF.frames["boss" .. i]
        if frame and active then
            frame:Show()
            if frame.SetAlpha then frame:SetAlpha(1) end
            if frame.EnableMouse then frame:EnableMouse(true) end
            ApplyBossPreviewFrameData(frame, i)
        elseif frame then
            frame._msufBossPreviewForced = nil
        end
    end

    RefreshBossAuras()
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end
    local em2 = _G.MSUF_EM2
    if em2 and em2.Movers and type(em2.Movers.SyncAll) == "function" then
        em2.Movers.SyncAll()
    end
    return true
end

_G.MSUF_ApplyBossUnitframePreviewState = function(active, reason)
    if BossPreviewCombatLocked() then
        _G.MSUF2_BossUnitframePreviewActive = nil
        return false
    end
    _G.MSUF2_BossUnitframePreviewActive = active == true and true or nil
    return UF.ApplyBossPreviewState(active, reason or "MSUF_BOSS_PREVIEW")
end

_G.MSUF_SyncBossUnitframePreviewWithUnitEdit = function()
    if BossPreviewCombatLocked() then
        return false
    end
    local editActive = _G.MSUF_UnitEditModeActive == true
    local active = _G.MSUF2_BossUnitframePreviewActive == true
        or (_G.MSUF_BossTestMode == true and editActive)
        or (_G.MSUF_PreviewTestMode == true and editActive)
    return UF.ApplyBossPreviewState(active, active and "MSUF_BOSS_PREVIEW_SYNC" or "MSUF_BOSS_PREVIEW_OFF")
end
