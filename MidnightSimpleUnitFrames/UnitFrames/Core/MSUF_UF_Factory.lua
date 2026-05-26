local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local UF = MSUF.UF
UF.Factory = UF.Factory or {}
local Factory = UF.Factory

local type = type
local ipairs = ipairs
local tonumber = tonumber
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local RegisterUnitWatch = RegisterUnitWatch
local UnregisterUnitWatch = UnregisterUnitWatch
local UnitFrame_OnEnter = UnitFrame_OnEnter
local UnitFrame_OnLeave = UnitFrame_OnLeave
local UIParent = UIParent

local COOLDOWN_ANCHORS = {
    EssentialCooldownViewer = true,
    UtilityCooldownViewer = true,
    BuffIconCooldownViewer = true,
}

local function IsCooldownViewerAnchor(name)
    return COOLDOWN_ANCHORS[name] == true
end

local function ResolveNamedAnchor(name)
    if type(name) ~= "string" or name == "" then
        return nil, nil
    end
    if IsCooldownViewerAnchor(name) then
        local resolver = _G.MSUF_GetEffectiveCooldownFrame
        local frame = (type(resolver) == "function" and resolver(name)) or _G[name]
        if frame then
            return frame, nil, true
        end
        return nil, name, true
    end
    local frame = _G[name]
    if frame then
        return frame, nil
    end
    return nil, name
end

local function ResolveAnchor(spec, frame)
    local anchor = UIParent
    if type(spec.anchorFrameName) == "string" and spec.anchorFrameName ~= "" then
        local named, missing = ResolveNamedAnchor(spec.anchorFrameName)
        if named and named ~= frame then
            return named, nil, spec.anchorFrameName
        end
        return anchor, missing or spec.anchorFrameName, spec.anchorFrameName
    elseif type(spec.anchorToUnitframe) == "string"
        and spec.anchorToUnitframe ~= ""
        and spec.anchorToUnitframe ~= "GLOBAL"
        and spec.anchorToUnitframe ~= "global"
        and spec.anchorToUnitframe ~= "FREE" then
        local other = UF.frames[spec.anchorToUnitframe]
        local missing
        if not other then
            other, missing = ResolveNamedAnchor(spec.anchorToUnitframe)
        end
        if other and other ~= frame then
            return other, nil, spec.anchorToUnitframe
        end
        return anchor, missing or spec.anchorToUnitframe, spec.anchorToUnitframe
    end
    return anchor, nil, nil
end

local function ShouldCacheScreenPosition(spec, requestedAnchor)
    if type(spec.anchorFrameName) == "string" and spec.anchorFrameName ~= "" then
        return true
    end
    return COOLDOWN_ANCHORS[requestedAnchor] == true
end

local function ApplyPosition(frame, spec)
    if frame._msufDragActive == true then
        return true
    end
    if InCombatLockdown and InCombatLockdown() then
        UF.pendingApply[frame.unit] = true
        Factory.EnsureDeferredDriver()
        return false
    end
    local point = spec.point or "CENTER"
    local anchor, missingAnchorName, requestedAnchor, blockedMissingAnchor = ResolveAnchor(spec, frame)
    local relativePoint = spec.relativePoint or point
    local x = tonumber(spec.x) or 0
    local y = tonumber(spec.y) or 0
    local key = spec.key or (UF.ConfigKeyForUnit and UF.ConfigKeyForUnit(frame.unit)) or frame.unit

    if missingAnchorName then
        if not blockedMissingAnchor and type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
            _G.MSUF_ScheduleLateAnchorReanchor()
        end
        local applyCached = _G.MSUF_ApplyCachedUnitFrameScreenPosition
        if type(applyCached) == "function" and applyCached(frame, key, frame.unit) then
            return true
        end
        if frame._msufPositionInitialized == true then
            return true
        end
    end

    if frame._msufPoint ~= point
        or frame._msufAnchor ~= anchor
        or frame._msufRelativePoint ~= relativePoint
        or frame._msufX ~= x
        or frame._msufY ~= y then
        frame:ClearAllPoints()
        frame:SetPoint(point, anchor, relativePoint, x, y)
        frame._msufPoint, frame._msufAnchor, frame._msufRelativePoint = point, anchor, relativePoint
        frame._msufX, frame._msufY = x, y
    end
    frame._msufPositionInitialized = true
    frame._msufHardLockedToUIParent = nil
    if not missingAnchorName
        and ShouldCacheScreenPosition(spec, requestedAnchor)
        and type(_G.MSUF_CacheUnitFrameScreenPosition) == "function" then
        _G.MSUF_CacheUnitFrameScreenPosition(frame, key, frame.unit, point)
    end
    return true
end

local function ApplySize(frame, spec)
    if InCombatLockdown and InCombatLockdown() then
        UF.pendingApply[frame.unit] = true
        Factory.EnsureDeferredDriver()
        return false
    end
    local width = tonumber(spec.width) or 220
    local height = tonumber(spec.height) or 34
    if frame._msufWidth ~= width or frame._msufHeight ~= height then
        frame:SetSize(width, height)
        frame._msufWidth, frame._msufHeight = width, height
    end
    return true
end

local function ApplyElements(frame, spec)
    for i = 1, #UF.elementOrder do
        local name = UF.elementOrder[i]
        local element = UF.elements[name]
        local enabled = UF.ElementEnabled(element, frame, spec)
        if not enabled then
            if not frame:DisableElement(name) and element and element.Disable then
                element.Disable(frame)
            end
        else
            if element and element.Create and not frame._msufCreatedElements[name] then
                element.Create(frame, spec)
                frame._msufCreatedElements[name] = true
            end
            if element and element.Apply then
                element.Apply(frame, spec)
            end
            frame:EnableElement(name)
        end
    end
end

local function ApplyFrame(frame, spec)
    if not (frame and spec) then
        return false
    end
    frame.MSUFSpec = spec
    frame.cachedConfig = spec
    frame.configKey = spec.key
    frame.unitKey = spec.unit
    ApplySize(frame, spec)
    ApplyPosition(frame, spec)
    ApplyElements(frame, spec)

    if frame._msufVisibilityManaged == true then
        -- Secure visibility is owned by the LoadConditions element.
    elseif spec.enabled ~= false then
        if frame.Enable then
            frame:Enable()
        elseif RegisterUnitWatch then
            RegisterUnitWatch(frame)
        else
            frame:Show()
        end
    else
        if frame.Disable then
            frame:Disable()
        elseif UnregisterUnitWatch then
            UnregisterUnitWatch(frame)
            frame:Hide()
        else
            frame:Hide()
        end
    end
    frame:ForceUpdate("MSUF_APPLY")
    return true
end

local function RegisterGlobals(unit, frame)
    UF.frames[unit] = frame
    _G.MSUF_UnitFrames = UF.frames
    _G[UF.FrameName(unit)] = frame
    if unit == "targettarget" then
        _G.MSUF_tot = frame
    end

    local found = false
    for i = 1, #UF.frameList do
        if UF.frameList[i] == frame then
            found = true
            break
        end
    end
    if not found then
        UF.frameList[#UF.frameList + 1] = frame
    end
    _G.MSUF_UnitFramesList = UF.frameList
end

local function SpawnFrame(unit)
    if not UF.IsManagedUnit(unit) then
        return nil
    end
    if UF.ShouldUseMSUFUnitFrame and UF.ShouldUseMSUFUnitFrame(unit) == false then
        return nil
    end

    local name = UF.FrameName(unit)
    local frame = _G[name]
    if not frame then
        frame = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate, PingableUnitFrameTemplate")
    end

    UF.AttachFrameMethods(frame)
    frame.unit = unit
    frame.MSUFUnitKey = unit
    frame:SetAttribute("unit", unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:SetAttribute("toggleForVehicle", true)
    frame:RegisterForClicks("AnyUp")
    frame.Enable = RegisterUnitWatch
    frame.Disable = function(self)
        if UnregisterUnitWatch then
            UnregisterUnitWatch(self)
        end
        self:Hide()
    end
    if UnitFrame_OnEnter and UnitFrame_OnLeave and not frame._msufTooltipHooked then
        frame:HookScript("OnEnter", UnitFrame_OnEnter)
        frame:HookScript("OnLeave", UnitFrame_OnLeave)
        frame._msufTooltipHooked = true
    end

    RegisterGlobals(unit, frame)
    return frame
end

local function ApplyOne(unit)
    if not UF.IsManagedUnit(unit) then
        return false
    end
    if UF.ShouldUseMSUFUnitFrame and UF.ShouldUseMSUFUnitFrame(unit) == false then
        local frame = UF.frames[unit]
        if frame then
            frame:Hide()
        end
        return true
    end
    local frame = UF.frames[unit]
    if not frame then
        frame = SpawnFrame(unit)
    end
    if not frame then
        return false
    end
    return ApplyFrame(frame, UF.Config.GetSpec(unit))
end

function Factory.SpawnAll()
    if UF.spawned then
        return true
    end
    if InCombatLockdown and InCombatLockdown() then
        Factory.EnsureDeferredDriver()
        return false
    end

    if UF.Config and UF.Config.Refresh then
        UF.Config.Refresh()
    end
    if UF.DisableBlizzardFrames then
        UF.DisableBlizzardFrames()
    end

    for i = 1, #UF.unitOrder do
        local unit = UF.unitOrder[i]
        local frame = SpawnFrame(unit)
        if frame then
            ApplyFrame(frame, UF.Config.GetSpec(unit))
        end
    end

    UF.spawned = true
    if type(MSUF.RegisterThirdPartyAnchors) == "function" then
        MSUF.RegisterThirdPartyAnchors()
    end
    return true
end

function Factory.Apply(unit)
    if not UF.spawned then
        return Factory.SpawnAll()
    end
    if unit then
        local units = UF.UnitsForConfigKey(unit)
        if not units then
            return false
        end
        if UF.Config and UF.Config.RefreshUnit then
            for i = 1, #units do
                UF.Config.RefreshUnit(units[i])
            end
        elseif UF.Config and UF.Config.Refresh then
            UF.Config.Refresh()
        end
        local ok = false
        for i = 1, #units do
            ok = ApplyOne(units[i]) or ok
        end
        return ok
    end
    if UF.Config and UF.Config.Refresh then
        UF.Config.Refresh()
    end
    for i = 1, #UF.unitOrder do
        ApplyOne(UF.unitOrder[i])
    end
    return true
end

local function DeferredOnEvent(self)
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if not UF.spawned then
        Factory.SpawnAll()
        return
    end
    for unit in pairs(UF.pendingApply) do
        UF.pendingApply[unit] = nil
        local frame = UF.frames[unit]
        if frame then
            ApplyFrame(frame, UF.Config.GetSpec(unit))
        end
    end
end

function Factory.EnsureDeferredDriver()
    if not Factory.deferredDriver then
        Factory.deferredDriver = CreateFrame("Frame")
        Factory.deferredDriver:SetScript("OnEvent", DeferredOnEvent)
    end
    Factory.deferredDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local LATE_ANCHOR_RETRY_DELAYS = { 0, 0.05, 0.20, 0.60, 1.20, 2.00 }
local LATE_ANCHOR_KEYS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss" }

local function HasClassPowerLateAnchor()
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    return bars and bars.classPowerAnchorToCooldown == true and false
end

local function HasLateAnchorConfig()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return false end
    local general = db.general
    if general and general.anchorToCooldown == true then return false end
    if HasClassPowerLateAnchor() then return true end
    for i = 1, #LATE_ANCHOR_KEYS do
        local conf = db[LATE_ANCHOR_KEYS[i]]
        if type(conf) == "table" then
            if type(conf.anchorFrameName) == "string" and conf.anchorFrameName ~= "" and not IsCooldownViewerAnchor(conf.anchorFrameName) then
                return true
            end
            local anchorTo = conf.anchorToUnitframe
            if type(anchorTo) == "string"
                and anchorTo ~= ""
                and anchorTo ~= "GLOBAL"
                and anchorTo ~= "global"
                and anchorTo ~= "FREE"
                and not IsCooldownViewerAnchor(anchorTo) then
                return true
            end
        end
    end
    return false
end

local function FlushLateAnchorReanchor()
    if InCombatLockdown and InCombatLockdown() then
        UF.RequestReanchorAfterCombat()
        return false
    end
    Factory.Apply()
    if HasClassPowerLateAnchor() and type(_G.MSUF_ClassPower_Refresh) == "function" then
        _G.MSUF_ClassPower_Refresh()
    end
    return true
end

function _G.MSUF_ScheduleLateAnchorReanchor()
    _G.MSUF_CDMBridgeDirty = true
    if InCombatLockdown and InCombatLockdown() then
        UF.RequestReanchorAfterCombat()
        return false
    end

    local state = _G.MSUF_LateAnchorReanchorState
    if type(state) ~= "table" then
        state = { pending = false, attempts = 0 }
        _G.MSUF_LateAnchorReanchorState = state
    end
    if state.pending then return false end
    state.pending = true
    state.attempts = 0

    if not (_G.C_Timer and _G.C_Timer.After) then
        FlushLateAnchorReanchor()
        state.pending = false
        return true
    end

    for i = 1, #LATE_ANCHOR_RETRY_DELAYS do
        _G.C_Timer.After(LATE_ANCHOR_RETRY_DELAYS[i], function()
            if not state.pending then return end
            state.attempts = i
            FlushLateAnchorReanchor()
            if i == #LATE_ANCHOR_RETRY_DELAYS then
                state.pending = false
            end
        end)
    end
    return true
end

function _G.MSUF_ForceReanchorAllUnitFrames_Once()
    if InCombatLockdown and InCombatLockdown() then
        UF.RequestReanchorAfterCombat()
        return false
    end
    return Factory.Apply()
end

do
    local function ScheduleFromEvent()
        local function run()
            if HasLateAnchorConfig() and type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
                _G.MSUF_ScheduleLateAnchorReanchor()
            end
        end
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, run)
        else
            run()
        end
    end

    local lateAnchorEvents = CreateFrame("Frame")
    lateAnchorEvents:RegisterEvent("PLAYER_LOGIN")
    lateAnchorEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
    lateAnchorEvents:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    lateAnchorEvents:RegisterEvent("ADDON_LOADED")
    lateAnchorEvents:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" then
            if type(addon) ~= "string" then return end
            if addon ~= "Blizzard_EditMode" then return end
        end
        ScheduleFromEvent()
    end)
end

function UF.Initialize()
    if UF.initialized then
        return
    end
    UF.initialized = true
    Factory.SpawnAll()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    UF.Initialize()
end)
