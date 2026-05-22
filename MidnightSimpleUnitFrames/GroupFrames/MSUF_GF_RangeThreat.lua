-- MSUF_GF_RangeThreat.lua
-- Group Frame range-fade and threat-state runtime.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local UnitExists = _G.UnitExists
local UnitIsConnected = _G.UnitIsConnected
local UnitHealth = _G.UnitHealth
local UnitInRange = _G.UnitInRange
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local UnitThreatSituation = _G.UnitThreatSituation
local IsInGroup = _G.IsInGroup
local IsInRaid = _G.IsInRaid

local function _RuntimeEnabledForFrame(f)
    local fn = GF._RuntimeEnabledForFrame
    if type(fn) == "function" then return fn(f) end
    return f ~= nil
end

local _GF_RefreshBorder = GF.RefreshBorder or _G.MSUF_GF_RefreshBorder or function() end
local UpdateStatusText = GF.UpdateStatusText or _G.MSUF_GF_UpdateStatus or function() end

-- Range fade (1:1 EQoL pattern)
-- Secret-safe: NEVER compare/type()/conditional on inRange.
-- Pass raw value to SetAlphaFromBoolean (C-side accepts secrets).
-- 1:1 EQoL GF:UpdateRange pattern Ã¢â‚¬â€ NO extra UnitPhaseReason/UnitIsVisible.
------------------------------------------------------------------------

-- EQoL UnsecretBool equivalent
local function _UnsecretBool(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function _NormalizeRangeFadeLayerMode(mode)
    if mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then
        return "health"
    end
    return "frame"
end

local function _GF_GetFrameAlpha(kind, conf)
    local fn = GF.GetEffectiveFrameAlpha
    if type(fn) == "function" then return fn(kind, conf) end
    return 1
end

local function _GF_ApplyFrameAlpha(f, kind, conf)
    local target = (f and f.barGroup) or f
    if target and target.SetAlpha then
        local c = f._c
        local a = c and c.frameAlpha
        if type(a) ~= "number" then
            a = _GF_GetFrameAlpha(kind, conf or GF.GetConf(kind))
        end
        target:SetAlpha(a)
    end
end

local function _ClearHealthRangeFade(f, kind)
    if not f then return end
    if f._msufGFHealthAlphaDynamic or f._msufGFHealthAlphaMul or type(f._msufGFHealthAlphaBool) ~= "nil" then
        f._msufGFHealthAlphaDynamic = nil
        f._msufGFHealthAlphaMul = nil
        f._msufGFHealthAlphaBool = nil
        f._msufGFHealthAlphaFalseMul = nil
        if GF.ApplyHealthBarAlpha then
            GF.ApplyHealthBarAlpha(f, kind or f._msufGFKind or "party")
        elseif f.health and f.health.SetAlpha then
            f.health:SetAlpha(1)
        end
    end
end

local function _ApplyHealthRangeFade(f, kind, boolValue, fadeMul, numericMul)
    if not f then return end
    local m = tonumber(fadeMul) or 1
    if m < 0 then m = 0 elseif m > 1 then m = 1 end

    f._msufGFHealthAlphaDynamic = true
    f._msufGFHealthAlphaFalseMul = m
    if type(boolValue) ~= "nil" then
        f._msufGFHealthAlphaBool = boolValue
        f._msufGFHealthAlphaMul = nil
    else
        local nm = tonumber(numericMul)
        if nm == nil then nm = m end
        if nm < 0 then nm = 0 elseif nm > 1 then nm = 1 end
        f._msufGFHealthAlphaBool = nil
        f._msufGFHealthAlphaMul = nm
    end

    _GF_ApplyFrameAlpha(f, kind or f._msufGFKind or "party")
    if GF.ApplyHealthBarAlpha then
        GF.ApplyHealthBarAlpha(f, kind or f._msufGFKind or "party")
    elseif f.health and f.health.SetAlpha and type(boolValue) == "nil" then
        f.health:SetAlpha(f._msufGFHealthAlphaMul or 1)
    end
end

local ApplyRangeFade
do
    ApplyRangeFade = function(f, unit, inRange)
        local c = f._c
        local kind = f._msufGFKind or "party"
        if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
        if f._msufGFRangeFadeUnit ~= unit then
            f._msufGFRangeFadeUnit = unit
        end
        local conf
        if not c then conf = GF.GetConf(kind) end
        local frameAlpha = (c and c.frameAlpha) or _GF_GetFrameAlpha(kind, conf)
        if (c and not c.rfEn) or (conf and conf.rangeFadeEnabled == false) then
            f._msufGFRangeFadeUnit = nil
            _ClearHealthRangeFade(f, kind)
            local target = (f and f.barGroup) or f
            if target and target.SetAlpha then target:SetAlpha(frameAlpha) end
            return
        end
        local fadeAlpha = (c and c.rfAlpha) or (conf and conf.rangeFadeAlpha) or 0.4
        local hpMode = ((c and c.rfLayerMode) or (conf and _NormalizeRangeFadeLayerMode(conf.rangeFadeLayerMode)) or "frame") == "health"

        if IsInGroup and IsInRaid then
            local inGroup = IsInGroup()
            local inRaid = IsInRaid()
            if not inGroup and not inRaid then
                f._msufGFRangeFadeUnit = nil
                _ClearHealthRangeFade(f, kind)
                local target = (f and f.barGroup) or f
                if target and target.SetAlpha then target:SetAlpha(frameAlpha) end
                return
            end
        end

        local connected = unit and UnitIsConnected and _UnsecretBool(UnitIsConnected(unit)) or nil
        if connected == false then
            f._msufGFRangeFadeUnit = nil
            local offA = (c and c.offAlpha) or (conf and conf.offlineAlpha) or fadeAlpha
            if hpMode then
                _ApplyHealthRangeFade(f, kind, nil, offA, offA)
            else
                _ClearHealthRangeFade(f, kind)
                local target = (f and f.barGroup) or f
                if target and target.SetAlpha then target:SetAlpha(frameAlpha * offA) end
            end
            return
        end

        if not hpMode then
            _ClearHealthRangeFade(f, kind)
        end
        if inRange == nil and unit and UnitInRange then inRange = UnitInRange(unit) end
        if type(inRange) ~= "nil" then
            if hpMode then
                _ApplyHealthRangeFade(f, kind, inRange, fadeAlpha)
            else
                local target = (f and f.barGroup) or f
                if target and target.SetAlphaFromBoolean then
                    target:SetAlphaFromBoolean(inRange, frameAlpha, frameAlpha * fadeAlpha)
                elseif target and target.SetAlpha then
                    local boolValue = _UnsecretBool(inRange)
                    if type(boolValue) ~= "nil" then
                        target:SetAlpha((boolValue and frameAlpha) or (frameAlpha * fadeAlpha))
                    end
                end
            end
        end
    end
end

function GF.RefreshGroupAlphas()
    local frames = GF.frames
    if frames then
        local list = GF.frameList
        if list then
            for i = 1, #list do
                local f = list[i]
                if f and _RuntimeEnabledForFrame(f) then
                    local kind = f._msufGFKind or "party"
                    if GF.BuildFrameCache then GF.BuildFrameCache(f) end
                    if GF.ApplyHealthBarAlpha then GF.ApplyHealthBarAlpha(f, kind) end
                    if GF.ApplyPowerBarAlpha then GF.ApplyPowerBarAlpha(f, kind) end
                    if GF.ApplyBackgroundAlpha then GF.ApplyBackgroundAlpha(f, kind) end
                    if f.unit and UnitExists(f.unit) then
                        ApplyRangeFade(f, f.unit)
                    else
                        _GF_ApplyFrameAlpha(f, kind)
                    end
                end
            end
        else
            for f in pairs(frames) do
                if f and _RuntimeEnabledForFrame(f) then
                    local kind = f._msufGFKind or "party"
                    if GF.BuildFrameCache then GF.BuildFrameCache(f) end
                    if GF.ApplyHealthBarAlpha then GF.ApplyHealthBarAlpha(f, kind) end
                    if GF.ApplyPowerBarAlpha then GF.ApplyPowerBarAlpha(f, kind) end
                    if GF.ApplyBackgroundAlpha then GF.ApplyBackgroundAlpha(f, kind) end
                    if f.unit and UnitExists(f.unit) then
                        ApplyRangeFade(f, f.unit)
                    else
                        _GF_ApplyFrameAlpha(f, kind)
                    end
                end
            end
        end
    end
    -- Runtime alpha transitions are already applied above. Do not dirty the
    -- visual pipeline here: in combat, MarkAllDirty promotes to a post-combat
    -- RefreshVisuals fan-out, turning alpha-only state changes into full
    -- frame/aura refreshes.
end

local function _GF_ShouldApplyRangeOrFrameAlpha(f, c, kind)
    if c and c.rfEn then return true end
    if f and f._msufGFHealthAlphaDynamic then return true end
    local cachedAlpha = c and c.frameAlpha
    if type(cachedAlpha) == "number" then return cachedAlpha < 0.999 end
    local fn = GF.GetEffectiveFrameAlpha
    if type(fn) ~= "function" then return false end
    kind = kind or (f and f._msufGFKind) or "party"
    local a = fn(kind, GF.GetConf(kind))
    return type(a) == "number" and a < 0.999
end

------------------------------------------------------------------------
function GF._RefreshAggroConsumers(f, unit, c)
    _GF_RefreshBorder(f, unit)
    if c and c.ciThreat and GF.UpdateCornerIndicators then
        f._msufCILastAt = nil
        GF.UpdateCornerIndicators(f, unit)
    end
end

local function UpdateAggro(f, unit)
    local kind = f._msufGFKind or "party"
    local prevLevel = f._msufGFAggroLevel
    -- PERF: pre-resolved flags on _c cache (populated in BuildFrameCache).
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end

    local testMode = (_G.MSUF_BorderTestModesActive == true) and _G.MSUF_AggroBorderTestMode
    -- Scope filtering
    if testMode then
        local testScope = _G.MSUF_AggroBorderTestScope or "shared"
        if testScope ~= "shared" then
            local scopeKind = (testScope == "party" or testScope == "gf_party") and "party"
                or (testScope == "raid" or testScope == "gf_raid") and "raid"
                or (testScope == "mythicraid" or testScope == "gf_mythicraid") and "mythicraid" or nil
            if scopeKind ~= kind then testMode = false end
        end
    end
    local wantsAggroState = c and (c.aggroEn or c.ciThreat)
    if ((not wantsAggroState) or not unit) and not testMode then
        if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
        return
    end

    if not testMode then
        if not UnitExists(unit) then
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
            return
        end
        local aggroMode = (c and c.aggroMode) or "ALL"
        if aggroMode ~= "ALL" then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            if aggroMode == "HEALER_ONLY" and role ~= "HEALER" then
                if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
                return
            end
            if aggroMode == "TANK_ONLY" and role ~= "TANK" then
                if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
                return
            end
        end
        local status = UnitThreatSituation and UnitThreatSituation(unit)
        if issecretvalue and issecretvalue(status) then
            -- Secret: can't diff-gate, but only refresh if we had aggro before
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
            return
        end
        local s = tonumber(status)
        if not s or s < 1 then
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
            return
        end
        -- Diff-gate: only refresh border when threat level actually changes
        if s == prevLevel then return end
        f._msufGFAggroLevel = s
    else
        f._msufGFAggroLevel = 3
    end
    GF._RefreshAggroConsumers(f, unit, c)
end
GF._UpdateAggro = UpdateAggro

------------------------------------------------------------------------

GF.ApplyRangeFade = ApplyRangeFade
GF.ShouldApplyRangeOrFrameAlpha = _GF_ShouldApplyRangeOrFrameAlpha
GF.UpdateAggro = UpdateAggro
GF._UpdateAggro = UpdateAggro
if GF._UnitDispatch then
    GF._UnitDispatch.UNIT_IN_RANGE_UPDATE = function(f, u, inRange)
        local c = f and f._c
        if c and c.statusTextEn then
            local state = f._msufGFStatusState or 0
            if state ~= 0 then
                UpdateStatusText(f, u)
            elseif UnitHealth then
                local hp = UnitHealth(u)
                if not (issecretvalue and issecretvalue(hp)) and hp == 0 then
                    UpdateStatusText(f, u)
                end
            end
        end
        ApplyRangeFade(f, u, inRange)
    end
    GF._UnitDispatch.UNIT_THREAT_SITUATION_UPDATE = UpdateAggro
    GF._UnitDispatch.UNIT_THREAT_LIST_UPDATE = UpdateAggro
    GF._UnitDispatch.UNIT_PHASE = function(f, u)
        local c = f and f._c
        if c and c.phaseEn then
            local updateAll = _G.MSUF_GF_UpdateAll
            if type(updateAll) == "function" then return updateAll(f, u) end
        end
        ApplyRangeFade(f, u)
    end
    GF._UnitDispatch.UNIT_CTR_OPTIONS = ApplyRangeFade
    GF._UnitDispatch.UNIT_OTHER_PARTY_CHANGED = ApplyRangeFade
end
_G.MSUF_GF_UpdateAggro = UpdateAggro
