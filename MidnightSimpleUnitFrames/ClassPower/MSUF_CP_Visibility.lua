-- Resource-only visibility. Geometry stays anchored to its configured source;
-- an opt-in parent change releases Player visibility without moving that source.
local _, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "ClassPower/MSUF_CP_Visibility.lua")
local V = {}
MSUF.ResourceVisibility = V
local entries, curves = {}, {}
local events, SyncEvents

local function Combat(event)
    if event == "PLAYER_REGEN_DISABLED" then return true end
    if event == "PLAYER_REGEN_ENABLED" then return false end
    return (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

local function NotSecret(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Curve(full, empty)
    local key = (full and 1 or 0) + (empty and 2 or 0)
    if curves[key] then return curves[key] end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step) then return nil end
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, empty and 0 or 1)
    if empty then curve:AddPoint(0.0000000000000001, 1) end
    curve:AddPoint(1, full and 0 or 1)
    curves[key] = curve
    return curve
end

local function Parent(entry, event)
    local region, owner = entry.region, entry.owner
    local independent = not entry.released and entry.independent
    if Combat(event) then entry.pending = true return end
    local parent = owner
    if independent then
        local uf = MSUF.UF
        parent = uf and uf.GetPetBattleFrameHider and uf.GetPetBattleFrameHider() or UIParent
    end
    local scale = entry.scale
    if independent and owner.GetEffectiveScale and parent.GetEffectiveScale then
        scale = scale * owner:GetEffectiveScale() / parent:GetEffectiveScale()
    end
    if region:GetParent() ~= parent then region:SetParent(parent) end
    if region.SetScale and region:GetScale() ~= scale then region:SetScale(scale) end
    entry.pending = nil
end

local function PowerType(entry)
    if entry.kind == "mana" then return 0 end
    local frame = entry.frame
    if frame and frame._msufPowerEbonMight == true then return nil end
    local common = MSUF.UFBarTextCommon
    local resolve = common and common.ResolveDisplayedPowerIdentity
    local power
    if resolve then power = resolve("player") else power = UnitPowerType("player") end
    if NotSecret(power) and type(power) == "number" then return power end
end

local function Paint(entry, event)
    if entry.released then return end
    if entry.kind == "class" then return end -- Class Resource owns its value rules.
    local region = entry.region
    if _G.MSUF_UnitEditModeActive == true then region:SetAlpha(1) return end
    if entry.hideOOC and not Combat(event) then region:SetAlpha(0) return end
    local full, empty = entry.hideFull, entry.hideEmpty
    if not (full or empty) or entry.kind == "extra" then region:SetAlpha(1) return end
    local power, current, maximum
    if entry.kind ~= "health" then
        power = PowerType(entry)
        if power == nil then region:SetAlpha(1) return end
    end
    local curve = Curve(full, empty)
    if curve and entry.kind == "health" and UnitHealthPercent then
        region:SetAlpha(UnitHealthPercent("player", false, curve))
        return
    elseif curve and entry.kind ~= "health" and UnitPowerPercent then
        region:SetAlpha(UnitPowerPercent("player", power, true, curve))
        return
    end
    if entry.kind == "health" then
        current, maximum = UnitHealth("player"), UnitHealthMax("player")
    else
        current, maximum = UnitPower("player", power), UnitPowerMax("player", power)
    end
    local hidden = false
    if NotSecret(current) and type(current) == "number" then
        hidden = empty and current <= 0
        if full and NotSecret(maximum) and type(maximum) == "number" then
            hidden = hidden or (maximum > 0 and current >= maximum)
        end
    end
    region:SetAlpha(hidden and 0 or 1)
end

-- The normal Core skips a hidden Player frame. Update only the detached power
-- and its text in that case, using the same runtime painters and value tuple.
local function UpdateHiddenPower(entry, event, token)
    local frame = entry.frame
    if not frame or frame:IsVisible() or not entry.independent then return end
    local spec = frame.MSUFSpec
    if not (spec and spec.enabled ~= false and spec.power and spec.power.enabled and spec.power.detached) then return end
    local elements = MSUF.UF and MSUF.UF.elements
    if not (elements and elements.Power) then return end
    local value, maximum, power, powerToken, changed, rejected = elements.Power.Update(frame, event, "player", token)
    if rejected or frame._msufPowerEbonMight == true then return end
    if elements.PowerText then
        elements.PowerText.Update(frame, event, "player", value, maximum, power, powerToken, changed)
    end
end

local function OnEvent(_, event, unit, token)
    if unit and unit ~= "player" then return end
    local powerEvent = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
        or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER"
    local healthEvent = event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
    for _, entry in pairs(entries) do
        if event == "PLAYER_REGEN_ENABLED" and entry.pending then
            Parent(entry, event)
            if entry.released and not entry.pending then entries[entry.region] = nil end
        end
        if not entry.released and entry.frame and powerEvent then UpdateHiddenPower(entry, event, token) end
        if (not powerEvent and not healthEvent) or (healthEvent and entry.kind == "health")
            or (powerEvent and (entry.kind == "power" or entry.kind == "mana")) then
            Paint(entry, event)
        end
    end
    if event == "PLAYER_REGEN_ENABLED" then SyncEvents() end
end

SyncEvents = function()
    local combat, power, health, frequent = false, false, false, false
    for _, entry in pairs(entries) do
        if entry.released then
            combat = combat or entry.pending
        else
            combat = combat or entry.pending or entry.hideOOC
            local values = entry.hideFull or entry.hideEmpty
            health = health or (entry.kind == "health" and values)
            local independent = entry.frame and entry.independent
            power = power or ((entry.kind == "power" or entry.kind == "mana") and (values or independent))
            frequent = frequent or (independent and entry.frame.MSUFSpec.power.frequent == true)
        end
    end
    if not events and not (combat or power or health) then return end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:UnregisterAllEvents()
    if combat then
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    if power then
        events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
        if frequent then events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player") end
    end
    if health then
        events:RegisterUnitEvent("UNIT_HEALTH", "player")
        events:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    end
end

function V.Bind(region, owner, b, prefix, kind, frame)
    if not region then return end
    local entry = entries[region]
    local wanted = b[prefix .. "IndependentVisibility"] == true or b[prefix .. "HideOOC"] == true
        or b[prefix .. "HideWhenFull"] == true or b[prefix .. "HideWhenEmpty"] == true
    if kind == "class" then wanted = b.classPowerIndependentVisibility == true end
    if not wanted then V.Unbind(region) return end
    if not entry then
        entry = { region = region, scale = region.GetScale and region:GetScale() or 1 }
        entries[region] = entry
    end
    entry.owner, entry.b, entry.prefix, entry.kind, entry.frame = owner, b, prefix, kind, frame
    entry.released = nil
    entry.independent = b[prefix .. "IndependentVisibility"] == true
    entry.hideOOC = kind ~= "class" and b[prefix .. "HideOOC"] == true
    entry.hideFull = kind ~= "class" and b[prefix .. "HideWhenFull"] == true
    entry.hideEmpty = kind ~= "class" and b[prefix .. "HideWhenEmpty"] == true
    Parent(entry)
    Paint(entry)
    SyncEvents()
end

function V.Unbind(region)
    if not region or not entries[region] then return end
    local entry = entries[region]
    if entry.kind ~= "class" then region:SetAlpha(1) end
    entry.released = true
    Parent(entry)
    if not entry.pending then entries[region] = nil end
    SyncEvents()
end

local function Reparent(region, parent)
    if region and region:GetParent() ~= parent then region:SetParent(parent) end
end

function V.ConfigurePower(frame)
    if frame.MSUFUnitKey ~= "player" or Combat() then return end
    local b = MSUF_DB and MSUF_DB.bars or {}
    local power = frame.MSUFSpec and frame.MSUFSpec.power
    local detached = power and power.enabled == true and power.detached == true
    local wanted = detached and (b.playerPowerIndependentVisibility == true or b.playerPowerHideOOC == true
        or b.playerPowerHideWhenFull == true or b.playerPowerHideWhenEmpty == true)
    local host = frame._msufPowerVisibilityHost
    if not wanted and not host then return end
    local owner = frame._msufHealthVisualRoot or frame
    if not host then
        host = PixelLayoutRegion(CreateFrame("Frame", nil, owner))
        host:SetAllPoints(frame)
        host:EnableMouse(false)
        frame._msufPowerVisibilityHost = host
    end
    local parent = wanted and host or owner
    Reparent(frame.targetPowerBar, parent)
    Reparent(frame.powerBarBG, parent)
    Reparent(frame.targetPowerBar and frame.targetPowerBar.MSUFPowerBorderHost, parent)
    Reparent(frame.MSUFPowerTextLayer, parent)
    local trail = frame.powerLossTrail
    if trail and trail._msufLossTrailPool then
        for i = 1, #trail._msufLossTrailPool do Reparent(trail._msufLossTrailPool[i], parent) end
    else
        Reparent(trail, parent)
    end
    frame._msufPowerVisibilityParent = wanted and host or nil
    if wanted then V.Bind(host, owner, b, "playerPower", "power", frame) else V.Unbind(host) end
end

function V.BindExtra(region, owner, b)
    V.Bind(region, owner, b, "resourceExtra", "extra")
end

function V.ClearExtras()
    for region, entry in pairs(entries) do
        if entry.kind == "extra" then V.Unbind(region) end
    end
end

if type(_G.MSUF_RegisterAnyEditModeListener) == "function" then
    _G.MSUF_RegisterAnyEditModeListener(function()
        for _, entry in pairs(entries) do Paint(entry) end
    end)
end
