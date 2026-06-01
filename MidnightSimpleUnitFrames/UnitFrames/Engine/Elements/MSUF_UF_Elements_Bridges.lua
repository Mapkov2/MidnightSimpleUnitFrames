local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local UF = MSUF.UF
local type = type

local function CastbarUnit(unit)
    if type(unit) == "string" and unit:match("^boss%d+$") then
        return "boss"
    end
    return unit
end

local function IsCastbarUnit(unit)
    unit = CastbarUnit(unit)
    return unit == "player" or unit == "target" or unit == "focus" or unit == "boss"
end

local function HideFrame(frame)
    if frame and frame.Hide then
        frame:Hide()
    end
end

local function Queue(fn, tokenName)
    if type(fn) ~= "function" then
        return
    end
    if UF[tokenName] then
        return
    end
    UF[tokenName] = true
    local timer = _G.C_Timer
    local function flush()
        UF[tokenName] = nil
        fn()
    end
    if timer and timer.After then
        timer.After(0, flush)
    else
        flush()
    end
end

local function QueueCastbarRefresh()
    Queue(function()
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            _G.MSUF_UpdateCastbarVisuals()
        end
        if type(_G.MSUF_ApplyPlayerChannelTickMarkers) == "function" then
            _G.MSUF_ApplyPlayerChannelTickMarkers()
        end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            _G.MSUF_UpdateBossCastbarPreview()
        end
    end, "_msufCastbarRefreshQueued")
end

local function HideMSUFCastbar(unit)
    unit = CastbarUnit(unit)
    if unit == "player" then
        HideFrame(_G.MSUF_PlayerCastBar)
        HideFrame(_G.MSUF_PlayerCastbar)
        HideFrame(_G.MSUF_PlayerCastBarFrame)
        HideFrame(_G.MSUF_PlayerCastbarFrame)
    elseif unit == "target" then
        HideFrame(_G.MSUF_TargetCastbar)
        HideFrame(_G.MSUF_TargetCastBar)
        HideFrame(_G.TargetCastBar)
    elseif unit == "focus" then
        HideFrame(_G.MSUF_FocusCastbar)
        HideFrame(_G.MSUF_FocusCastBar)
        HideFrame(_G.FocusCastBar)
    elseif unit == "boss" then
        for i = 1, 10 do
            HideFrame(_G["MSUF_boss" .. i .. "CastBar"])
            HideFrame(_G["MSUF_Boss" .. i .. "CastBar"])
        end
    end
end

local Castbars = {}

function Castbars.IsEnabled(frame, spec)
    return IsCastbarUnit(frame.unit) and spec and spec.castbar and spec.castbar.enabled == true
end

function Castbars.Enable(frame)
    if not IsCastbarUnit(frame.unit) then
        return
    end
    local unit = CastbarUnit(frame.unit)
    if type(UF.ClaimBlizzardCastbarOwnership) == "function" then
        UF.ClaimBlizzardCastbarOwnership("MSUF", unit)
    end
    if unit == "player" and type(_G.MSUF_SuppressBlizzardPlayerCastbars) == "function" then
        _G.MSUF_SuppressBlizzardPlayerCastbars()
    end
    QueueCastbarRefresh()
end

function Castbars.Disable(frame)
    if not IsCastbarUnit(frame.unit) then
        return
    end
    HideMSUFCastbar(frame.unit)
    QueueCastbarRefresh()
end

function Castbars.Apply(frame, spec)
    if not IsCastbarUnit(frame.unit) then
        return
    end
    if spec and spec.castbar and spec.castbar.enabled == true then
        Castbars.Enable(frame, spec)
    else
        Castbars.Disable(frame)
    end
end

local ClassPower = {}

function ClassPower.IsEnabled(frame, spec)
    return frame.unit == "player" and spec and spec.classPower and spec.classPower.enabled == true
end

function ClassPower.Enable(frame)
    if frame and frame.unit ~= "player" then
        return
    end
    Queue(function()
        if type(_G.MSUF_ClassPower_Refresh) == "function" then
            _G.MSUF_ClassPower_Refresh()
        end
        if type(_G.MSUF_ClassPower_RefreshCDMWidthBindings) == "function" then
            _G.MSUF_ClassPower_RefreshCDMWidthBindings(false)
        end
        if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then
            _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player")
        end
    end, "_msufClassPowerRefreshQueued")
end

function ClassPower.Disable(frame)
    if frame and frame.unit ~= "player" then
        return
    end
    HideFrame(_G.MSUF_ClassPowerContainer)
    if type(_G.MSUF_ClassPower_IsRuntimeActive) == "function" and not _G.MSUF_ClassPower_IsRuntimeActive() then
        return
    end
    Queue(function()
        if type(_G.MSUF_ClassPower_Refresh) == "function" then
            _G.MSUF_ClassPower_Refresh()
        end
        if type(_G.MSUF_ClassPower_RefreshCDMWidthBindings) == "function" then
            _G.MSUF_ClassPower_RefreshCDMWidthBindings(false)
        end
    end, "_msufClassPowerRefreshQueued")
end

function ClassPower.Apply(frame, spec)
    if frame.unit ~= "player" then
        return
    end
    if ClassPower.IsEnabled(frame, spec) then
        ClassPower.Enable(frame, spec)
    else
        ClassPower.Disable(frame)
    end
end

UF.RegisterElement("Castbars", Castbars)
UF.RegisterElement("ClassPower", ClassPower)

do
    local order = UF.elementOrder
    if type(order) == "table" then
        for i = 1, #order do
            if order[i] == "Alpha" then
                table.remove(order, i)
                order[#order + 1] = "Alpha"
                break
            end
        end
    end
end
