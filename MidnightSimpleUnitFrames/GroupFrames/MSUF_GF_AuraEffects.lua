-- MSUF_GF_AuraEffects.lua
-- Group Frame aura-effects runtime: UNIT_AURA dispatch, dispel scanning,
-- dispel overlay/glow, debuff stripe, and shared highlight-border refresh.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown or function() return false end
local UnitExists = _G.UnitExists
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local AuraUtil = _G.AuraUtil
local C_Timer = _G.C_Timer
local GetTime = _G.GetTime
local C_UnitAuras = _G.C_UnitAuras
local LCG = _G.LibStub and _G.LibStub("LibCustomGlow-1.0", true)
local math_max = math.max
local DISPEL_COLORS = {
    Magic   = { 0.25, 0.75, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    Bleed   = { 0.80, 0.10, 0.10 },
}

local function _MSUF_ScheduleOnce(key, fn)
    local sched = _G.MSUF_ScheduleOnce
    if sched then return sched(key, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(0, fn) end
    if type(fn) == "function" then return fn() end
end

local function _MSUF_ScheduleDelayOnce(key, delay, fn)
    local sched = _G.MSUF_ScheduleDelayOnce
    if sched then return sched(key, delay, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(delay or 0, fn) end
    if type(fn) == "function" then return fn() end
end

local function HLVal(kind, key)
    local fn = GF.HighlightValue
    if type(fn) == "function" then return fn(kind, key) end
    local conf = GF.GetConf and GF.GetConf(kind)
    return conf and conf[key]
end

local function _GF_IsBlizzardDispelRendererActive(conf)
    local fn = GF.IsBlizzardDispelRendererActive
    if type(fn) == "function" then return fn(conf) end
    return false
end

local _applyHighlightBorderStyle = GF.ApplyHighlightBorderStyle or _G.MSUF_GF_ApplyHLBorderStyle or function() end
local _NotifyRoundedGFHighlight = GF.NotifyRoundedHighlight or function(border)
    if _G.MSUF_RoundedUF_Active ~= true then return end
    local fn = _G.MSUF_RoundedUF_OnGroupHighlightChanged
    if type(fn) == "function" then fn(border) end
end

local function GetDispelColor(dispelName)
    -- DB per-type color takes priority (Colors > Dispel panel)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and type(dispelName) == "string" then
        local r = gen["dispelType" .. dispelName .. "R"]
        if type(r) == "number" then
            return r, gen["dispelType" .. dispelName .. "G"], gen["dispelType" .. dispelName .. "B"]
        end
    end
    -- Hardcoded fallback
    local c = DISPEL_COLORS[dispelName]
    if c then return c[1], c[2], c[3] end
    -- Blizzard color objects
    local obj = _G["DEBUFF_TYPE_" .. (dispelName or ""):upper() .. "_COLOR"]
    if obj then
        if obj.GetRGB then return obj:GetRGB() end
        if obj.r then return obj.r, obj.g, obj.b end
    end
    return nil
end

local function GetReadableDispelTypeName(dispelName)
    if dispelName == nil then return nil end
    if issecretvalue and issecretvalue(dispelName) then return nil end
    if type(dispelName) ~= "string" or dispelName == "" or dispelName == "None" or dispelName == "DISPELLABLE" then
        return nil
    end
    return dispelName
end

local function ExtractColorRGB(colorObj)
    if not colorObj then return nil end
    if colorObj.r ~= nil then
        return colorObj.r, colorObj.g, colorObj.b
    end
    if colorObj.GetRGBA then
        local rr, gg, bb = colorObj:GetRGBA()
        if rr ~= nil then return rr, gg, bb end
    end
    if colorObj.GetRGB then
        local rr, gg, bb = colorObj:GetRGB()
        if rr ~= nil then return rr, gg, bb end
    end
    return nil
end

local function ExtractColorRGBA(colorObj)
    if not colorObj then return nil end
    if colorObj.r ~= nil then
        return colorObj.r, colorObj.g, colorObj.b, colorObj.a or 1
    end
    if colorObj.GetRGBA then
        local rr, gg, bb, aa = colorObj:GetRGBA()
        if rr ~= nil then return rr, gg, bb, aa end
    end
    if colorObj.GetRGB then
        local rr, gg, bb = colorObj:GetRGB()
        if rr ~= nil then return rr, gg, bb, 1 end
    end
    return nil
end

local function GFDispelColorScopeValue(kind, key, legacyKey, fallback)
    local conf = kind and GF.GetConf and GF.GetConf(kind)
    if conf and conf.hlOverride then
        if conf[key] ~= nil then return conf[key] end
        if legacyKey and conf[legacyKey] ~= nil then return conf[legacyKey] end
    end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        if gen[key] ~= nil then return gen[key] end
        if legacyKey and gen[legacyKey] ~= nil then return gen[legacyKey] end
    end
    return fallback
end

GF.NormalizeDispelOverlayTrigger = GF.NormalizeDispelOverlayTrigger or function(value)
    local fn = _G.MSUF_NormalizeUnitDispelOverlayTrigger
    if type(fn) == "function" then return fn(value) end
    if value == "BORDER" or value == "INHERIT" or value == "SAME" then return "BORDER" end
    return GF.NormalizeDispelBorderTrigger(value)
end

GF.ResolveDispelOverlayTrigger = GF.ResolveDispelOverlayTrigger or function(c)
    local trigger = GF.NormalizeDispelOverlayTrigger(c and c.doTrigger)
    if trigger == "BORDER" then
        return GF.NormalizeDispelBorderTrigger(c and c.dispelBorderTrigger)
    end
    return trigger
end

------------------------------------------------------------------------
-- Secret-safe dispel color resolution.
--
-- SINGLE mode Ã¢â€ â€™ plain (r,g,b) triplet from the Colors panel.
-- TYPE mode   Ã¢â€ â€™ a *Color object* from C_UnitAuras.GetAuraDispelTypeColor.
--               The Color object carries secret-safe RGBA that can ONLY be
--               applied via texture:SetVertexColor(color:GetRGBA()). It
--               MUST NOT be unpacked into Lua locals and fed to
--               CreateColor / SetGradient / arithmetic Ã¢â‚¬â€ that taints the
--               values and breaks everything but flat fills (which is the
--               "only single-color works" bug in Beta 4/5).
--
-- Returns (colorObj, r, g, b):
--   colorObj ~= nil  Ã¢â€ â€™ TYPE mode resolved via curve. Apply via
--                      tex:SetVertexColor(colorObj:GetRGBA())
--   colorObj == nil  Ã¢â€ â€™ SINGLE/fallback. Use (r, g, b) directly.
------------------------------------------------------------------------
local GFHighlightUsesTypeLane, GFDispelOverlayUsesTypeLane

local function ResolveDispelColorObj(f, dispelName, useOverlay)
    local kind = (f and f._msufGFKind) or "party"
    local c = f and f._c
    local mode = (c and c.hlDispelColorMode) or GFDispelColorScopeValue(kind, "hlDispelColorMode", nil, "SINGLE")
    local fallbackType = GetReadableDispelTypeName(dispelName)
    local typedPriorityLane = false
    if fallbackType and fallbackType ~= "DISPELLABLE" then
        if useOverlay then
            typedPriorityLane = type(GFDispelOverlayUsesTypeLane) == "function"
                and GFDispelOverlayUsesTypeLane(kind, c) == true
        else
            typedPriorityLane = type(GFHighlightUsesTypeLane) == "function"
                and GFHighlightUsesTypeLane(kind, c) == true
        end
    end

    -- Bleed/Enrage are found from aura.dispelType and are not normal dispelName
    -- schools. Keep them on the direct RGB path instead of trusting
    -- GetAuraDispelTypeColor to return a useful Color object.
    if fallbackType == "Bleed" then
        local br, bg, bb = GetDispelColor(fallbackType)
        if br then return nil, br, bg, bb end
    end

    if mode ~= "TYPE" then
        if typedPriorityLane then
            local tr, tg, tb = GetDispelColor(fallbackType)
            if tr then return nil, tr, tg, tb end
        end
        return nil,
            (c and c.dispelR) or GFDispelColorScopeValue(kind, "hlDispelColorR", "dispelBorderColorR", 0.25),
            (c and c.dispelG) or GFDispelColorScopeValue(kind, "hlDispelColorG", "dispelBorderColorG", 0.75),
            (c and c.dispelB) or GFDispelColorScopeValue(kind, "hlDispelColorB", "dispelBorderColorB", 1.00)
    end

    -- TYPE mode: resolve Color object via shared dispel color curve.
    local CUA   = _G.C_UnitAuras
    local unit  = f and f.unit
    local curve = GF and GF._sharedDispelColorCurve

    if CUA and CUA.GetAuraDispelTypeColor and unit and curve then
        local cached = f and (useOverlay and f._msufGFDispelOverlayColorObj or f._msufGFDispelColorObj)
        local colorRev = _G.MSUF_ColorStyleRevision or 0
        local cachedRev = f and (useOverlay and f._msufGFDispelOverlayColorRev or f._msufGFDispelColorRev) or 0
        if cached and (cachedRev or 0) == colorRev then
            return cached
        end

        local aid = f and (useOverlay and f._msufGFDispelOverlayAuraID or f._msufGFDispelAuraID)
        if aid then
            local color = CUA.GetAuraDispelTypeColor(unit, aid, curve)
            if color then
                if f then
                    if useOverlay then
                        f._msufGFDispelOverlayColorObj = color
                        f._msufGFDispelOverlayColorRev = colorRev
                    else
                        f._msufGFDispelColorObj = color
                        f._msufGFDispelColorRev = colorRev
                    end
                end
                return color
            end
        end

        if useOverlay then
            if fallbackType then
                local fr, fg, fb = GetDispelColor(fallbackType)
                if fr then return nil, fr, fg, fb end
            end
            return nil, 0.25, 0.75, 1.00
        end

        -- If the lane already resolved a concrete dispel type but no stable
        -- aura id/color object is available, do not scan a different "top"
        -- dispellable aura for color. Border and overlay may intentionally
        -- prefer different dispel schools, so a fallback scan here can tint
        -- the border with the overlay/top aura's school.
        if fallbackType and fallbackType ~= "DISPELLABLE" then
            local fr, fg, fb = GetDispelColor(fallbackType)
            if fr then return nil, fr, fg, fb end
        end

        -- Grid2 path: query the top dispellable aura directly via GetAuraDataByIndex.
        local aura = CUA.GetAuraDataByIndex and CUA.GetAuraDataByIndex(unit, 1, "HARMFUL|RAID_PLAYER_DISPELLABLE")
        if aura and aura.auraInstanceID then
            if f then f._msufGFDispelAuraID = aura.auraInstanceID end
            fallbackType = fallbackType or GetReadableDispelTypeName(aura.dispelName)
            local color = CUA.GetAuraDispelTypeColor(unit, aura.auraInstanceID, curve)
            if color then
                if f then
                    f._msufGFDispelColorObj = color
                    f._msufGFDispelColorRev = colorRev
                end
                return color
            end
        end

        -- Recovery fallback for clients where GetAuraDataByIndex on this filter misbehaves.
        if CUA.GetAuraSlots and CUA.GetAuraDataBySlot then
            local _, slot = CUA.GetAuraSlots(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", 1)
            local auraBySlot = slot and CUA.GetAuraDataBySlot(unit, slot)
            if auraBySlot and auraBySlot.auraInstanceID then
                if f then f._msufGFDispelAuraID = auraBySlot.auraInstanceID end
                fallbackType = fallbackType or GetReadableDispelTypeName(auraBySlot.dispelName)
                local color = CUA.GetAuraDispelTypeColor(unit, auraBySlot.auraInstanceID, curve)
                if color then
                    if f then
                        f._msufGFDispelColorObj = color
                        f._msufGFDispelColorRev = colorRev
                    end
                    return color
                end
            end
        end
    end

    -- TYPE fallback: use the known dispel school if we have it, otherwise
    -- fall back to the neutral palette.
    if fallbackType then
        local fr, fg, fb = GetDispelColor(fallbackType)
        if fr then return nil, fr, fg, fb end
    end
    return nil, 0.25, 0.75, 1.00
end

------------------------------------------------------------------------
-- Legacy wrapper: keeps (r, g, b) shape for non-overlay callers (glow).
-- Glow APIs don't take a Color object, so we accept a *minor* loss of
-- secret-safety here Ã¢â‚¬â€ values feed into LCG's color table which is
-- only read by C-side SetVertexColor downstream, so it's still safe
-- in practice.
------------------------------------------------------------------------
local function ResolveDispelColor(dispelName, f)
    local colorObj, r, g, b = ResolveDispelColorObj(f, dispelName)
    if colorObj then
        local rr, gg, bb = ExtractColorRGB(colorObj)
        if rr ~= nil then return rr, gg, bb end
    end
    if r then return r, g, b end
    if type(dispelName) == "string" and dispelName ~= "DISPELLABLE" then
        local dr, dg, db = GetDispelColor(dispelName)
        if dr then return dr, dg, db end
    end
    return 0.25, 0.75, 1.00
end

------------------------------------------------------------------------
-- Dispel glow helpers (GF) Ã¢â‚¬â€ zero-alloc color table reuse
------------------------------------------------------------------------
-- Highlight priority helpers (GF).
local _GF_PRIORITY_DISPEL_TYPE_BY_KEY = {
    magic = "Magic",
    curse = "Curse",
    disease = "Disease",
    poison = "Poison",
    bleed = "Bleed",
}
local _GF_PRIORITY_KEY_BY_DISPEL_TYPE = {
    Magic = "magic",
    Curse = "curse",
    Disease = "disease",
    Poison = "poison",
    Bleed = "bleed",
}
local _GF_DISPEL_TYPE_BY_ENUM = {
    [1] = "Magic",
    [2] = "Curse",
    [3] = "Disease",
    [4] = "Poison",
    [5] = "Bleed",
    [9] = "Bleed",
    [11] = "Bleed",
}
local _GF_PRIORITY_KEY_ALIAS = {
    Dispel = "dispel",
    DISPEL = "dispel",
    dispellable = "dispel",
    Magic = "magic",
    MAGIC = "magic",
    Curse = "curse",
    CURSE = "curse",
    Disease = "disease",
    DISEASE = "disease",
    Poison = "poison",
    POISON = "poison",
    Bleed = "bleed",
    BLEED = "bleed",
    Aggro = "aggro",
    AGGRO = "aggro",
    Purge = "purge",
    PURGE = "purge",
    BossTarget = "bossTarget",
    Boss_Target = "bossTarget",
    ["Boss Target"] = "bossTarget",
    ["boss target"] = "bossTarget",
    boss_target = "bossTarget",
    bosstarget = "bossTarget",
    BOSS_TARGET = "bossTarget",
    Target = "target",
    TARGET = "target",
    Focus = "focus",
    FOCUS = "focus",
}
local _GF_DISPEL_TYPE_ID_CURVE
local _GF_DISPEL_TYPE_MARKER_G = 0.37
local _GF_DISPEL_TYPE_MARKER_B = 0.73
local _GF_DISPEL_TYPE_MARKER_R = {
    Magic   = 0.11,
    Curse   = 0.22,
    Disease = 0.33,
    Poison  = 0.44,
    Bleed   = 0.55,
}
local function GFNormalizePriorityKey(key)
    if type(key) ~= "string" then return nil end
    return _GF_PRIORITY_KEY_ALIAS[key] or key
end

local function GFBuildDispelTypeIDCurve()
    local CUA = _G.C_UnitAuras
    local CCU = _G.C_CurveUtil
    local C = _G.CreateColor
    if not (CUA and type(CUA.GetAuraDispelTypeColor) == "function"
        and CCU and type(CCU.CreateColorCurve) == "function"
        and type(C) == "function") then
        return nil
    end
    local curve = CCU.CreateColorCurve()
    if curve.SetType then
        curve:SetType(_G.Enum and _G.Enum.LuaCurveType and _G.Enum.LuaCurveType.Step or 0)
    end
    if not curve.AddPoint then return curve end
    curve:AddPoint(0, C(0, 0, 0, 1))
    curve:AddPoint(1, C(_GF_DISPEL_TYPE_MARKER_R.Magic, _GF_DISPEL_TYPE_MARKER_G, _GF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(2, C(_GF_DISPEL_TYPE_MARKER_R.Curse, _GF_DISPEL_TYPE_MARKER_G, _GF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(3, C(_GF_DISPEL_TYPE_MARKER_R.Disease, _GF_DISPEL_TYPE_MARKER_G, _GF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(4, C(_GF_DISPEL_TYPE_MARKER_R.Poison, _GF_DISPEL_TYPE_MARKER_G, _GF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(5, C(_GF_DISPEL_TYPE_MARKER_R.Bleed, _GF_DISPEL_TYPE_MARKER_G, _GF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(9, C(_GF_DISPEL_TYPE_MARKER_R.Bleed, _GF_DISPEL_TYPE_MARKER_G, _GF_DISPEL_TYPE_MARKER_B, 1))
    curve:AddPoint(11, C(_GF_DISPEL_TYPE_MARKER_R.Bleed, _GF_DISPEL_TYPE_MARKER_G, _GF_DISPEL_TYPE_MARKER_B, 1))
    return curve
end

local function GFDispelTypeFromIDColor(r, g, b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    local abs = math and math.abs
    if abs and abs(g - _GF_DISPEL_TYPE_MARKER_G) <= 0.04 and abs(b - _GF_DISPEL_TYPE_MARKER_B) <= 0.04 then
        local bestType, bestDelta = nil, 0.04
        for dispelType, markerR in pairs(_GF_DISPEL_TYPE_MARKER_R) do
            local delta = abs(r - markerR)
            if delta <= bestDelta then
                bestType, bestDelta = dispelType, delta
            end
        end
        if bestType then return bestType end
    end

    -- Some builds return Blizzard-style colors here instead of evaluating the
    -- supplied curve. Keep this fallback separate so Bleed red cannot be read as Magic.
    if r > 0.75 and g < 0.25 and b > 0.75 then return "Bleed" end -- legacy marker
    if r > 0.65 and g < 0.28 and b < 0.28 then return "Bleed" end
    if b > 0.70 and g > 0.35 and r < 0.45 then return "Magic" end
    if b > 0.65 and r > 0.45 and g < 0.30 then return "Curse" end
    if g > 0.45 and r < 0.30 and b < 0.30 then return "Poison" end
    if r > 0.45 and g > 0.25 and g < 0.65 and b < 0.30 then return "Disease" end
    return nil
end

local function GFDispelTypeFromAuraEnum(aura)
    local dispelType = aura and aura.dispelType
    if dispelType == nil then return nil end
    if issecretvalue and issecretvalue(dispelType) then return nil end
    return _GF_DISPEL_TYPE_BY_ENUM[tonumber(dispelType) or dispelType]
end

local function GFResolveAuraDispelPriorityType(unit, aura)
    if not aura then return nil end
    local dn = aura.dispelName
    if not (issecretvalue and issecretvalue(dn)) and _GF_PRIORITY_KEY_BY_DISPEL_TYPE[dn] then
        return dn
    end
    local enumType = GFDispelTypeFromAuraEnum(aura)
    if enumType then return enumType end
    local shared = _G.MSUF_ResolveAuraDispelPriorityType
    if type(shared) == "function" then
        local resolved = shared(unit, aura)
        if resolved then return resolved end
    end
    local aid = aura.auraInstanceID
    local CUA = _G.C_UnitAuras
    if not (unit and aid and CUA and type(CUA.GetAuraDispelTypeColor) == "function") then return nil end
    if not _GF_DISPEL_TYPE_ID_CURVE then
        _GF_DISPEL_TYPE_ID_CURVE = GFBuildDispelTypeIDCurve()
    end
    if not _GF_DISPEL_TYPE_ID_CURVE then return nil end
    local color = CUA.GetAuraDispelTypeColor(unit, aid, _GF_DISPEL_TYPE_ID_CURVE)
    local r, g, b = ExtractColorRGB(color)
    if issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then return nil end
    return GFDispelTypeFromIDColor(r, g, b)
end
local _GF_PRIORITY_SINGLE_DEFAULTS = { "dispel", "aggro" }
local _GF_PRIORITY_TYPE_DEFAULTS = { "magic", "curse", "disease", "poison", "bleed", "aggro" }
local _GF_PRIORITY_SINGLE_ALLOWED = { dispel = true, aggro = true }
local _GF_PRIORITY_TYPE_ALLOWED = {
    magic = true,
    curse = true,
    disease = true,
    poison = true,
    bleed = true,
    aggro = true,
}

local function GFPrioRawHasAllowedKey(prioOrder, allowed, key)
    if type(prioOrder) ~= "table" or not allowed[key] then return false end
    for i = 1, #prioOrder do
        if GFNormalizePriorityKey(prioOrder[i]) == key then return true end
    end
    return false
end

local function GFPrioOrderHasTypeKey(prioOrder)
    if type(prioOrder) ~= "table" then return false end
    for i = 1, #prioOrder do
        local key = GFNormalizePriorityKey(prioOrder[i])
        if key ~= "dispel" and _GF_PRIORITY_TYPE_ALLOWED[key] then return true end
    end
    return false
end

local _GF_DISPEL_TYPE_ORDER_KEYS = {
    magic = true,
    curse = true,
    disease = true,
    poison = true,
    bleed = true,
}
local _GF_DISPEL_PRIORITY_TYPE_KEYS = { "magic", "curse", "disease", "poison", "bleed" }

local function GFPrioOrderHasDispelTypeKey(prioOrder)
    if type(prioOrder) ~= "table" then return false end
    for i = 1, #prioOrder do
        if _GF_DISPEL_TYPE_ORDER_KEYS[GFNormalizePriorityKey(prioOrder[i])] then return true end
    end
    return false
end

local function GFOverlayUsesOwnPriority(c)
    return false
end

local function GFOverlayPriorityState(kind, c)
    if not c then return false, nil end
    if c.dispelOverlayCustomTypePriority ~= nil then
        return c.dispelOverlayCustomTypePriority == true, c.dispelOverlayPrioOrder
    end
    local enabled = c.hlPrioEnabled
    if enabled == nil then enabled = HLVal(kind, "hlPrioEnabled") end
    local order = c.hlPrioOrder
    if type(order) ~= "table" then order = HLVal(kind, "hlPrioOrder") end
    return enabled == true or enabled == 1, order
end

local function GFDispelTypePriorityState(kind, c, useOverlayPriority)
    if useOverlayPriority then
        return GFOverlayPriorityState(kind, c)
    end
    if c and c.dispelBorderCustomTypePriority ~= nil then
        return c.dispelBorderCustomTypePriority == true, c.dispelBorderPrioOrder
    end
    local enabled = c and c.hlPrioEnabled
    if enabled == nil then enabled = HLVal(kind, "hlPrioEnabled") end
    local order = c and c.hlPrioOrder
    if type(order) ~= "table" then order = HLVal(kind, "hlPrioOrder") end
    if (enabled == true or enabled == 1) and GFPrioOrderHasDispelTypeKey(order) then
        return true, order
    end
    return false, nil
end

local function GFDispelScanPriorityConfig(kind, c, useOverlayPriority)
    if c then
        local enabled = useOverlayPriority and c.dispelOverlayPriorityScan or c.dispelBorderPriorityScan
        if enabled ~= nil then
            return enabled == true, useOverlayPriority and c.dispelOverlayPrioOrder or c.dispelBorderPrioOrder
        end
    end
    local customEnabled, order = GFDispelTypePriorityState(kind, c, useOverlayPriority)
    local typeColorMode = ((c and c.hlDispelColorMode) or GFDispelColorScopeValue(kind, "hlDispelColorMode", nil, "SINGLE")) == "TYPE"
    local customTypeOrder = customEnabled and GFPrioOrderHasDispelTypeKey(order)
    if not typeColorMode and not customTypeOrder then
        return false, order
    end
    return true, customEnabled and order or nil
end

local function GFDispelScanCustomTypePriorityEnabled(kind, c, useOverlayPriority)
    if c then
        local enabled = useOverlayPriority and c.dispelOverlayCustomTypePriority or c.dispelBorderCustomTypePriority
        if enabled ~= nil then return enabled == true end
    end
    local enabled, order = GFDispelTypePriorityState(kind, c, useOverlayPriority)
    return enabled and GFPrioOrderHasDispelTypeKey(order)
end

local function GFDispelScanPriorityEnabled(kind, c, useOverlayPriority)
    local enabled = GFDispelScanPriorityConfig(kind, c, useOverlayPriority)
    return enabled == true
end

local function GFDispelScanResolveType(kind, c, triggerMode, useOverlayPriority)
    triggerMode = GF.NormalizeDispelBorderTrigger(triggerMode)
    if c then
        if useOverlayPriority then
            if c.dispelOverlayTrigger == triggerMode and c.dispelOverlayResolveType ~= nil then
                return c.dispelOverlayResolveType == true
            end
        elseif c.dispelBorderTrigger == triggerMode and c.dispelBorderResolveType ~= nil then
            return c.dispelBorderResolveType == true
        end
    end
    return GFDispelScanPriorityEnabled(kind, c, useOverlayPriority)
        or triggerMode == "DISPEL_TYPE"
        or ((c and c.hlDispelColorMode) or GFDispelColorScopeValue(kind, "hlDispelColorMode", nil, "SINGLE")) == "TYPE"
end

local function GFDispelTypePriorityRank(kind, c, dispelType, useOverlayPriority, forceDefaultOrder)
    local enabled, prioOrder = GFDispelScanPriorityConfig(kind, c, useOverlayPriority)
    if not enabled then
        if not forceDefaultOrder then return 999 end
        prioOrder = nil
    end
    if issecretvalue and issecretvalue(dispelType) then return 999 end
    -- dispelType may arrive as a capitalised dispelName ("Bleed") or as a
    -- lowercase priority key ("bleed") returned by GFResolveAuraDispelPriorityType.
    -- _GF_PRIORITY_KEY_BY_DISPEL_TYPE maps capitalised → lowercase, so a
    -- lowercase input will miss. Fall back to checking PRIORITY_TYPE_ALLOWED
    -- directly, which uses the same lowercase keys as the priority order.
    local allowed = _GF_DISPEL_TYPE_ORDER_KEYS
    local defaults = _GF_DISPEL_PRIORITY_TYPE_KEYS
    local wanted = _GF_PRIORITY_KEY_BY_DISPEL_TYPE[dispelType]
        or (allowed[dispelType] and dispelType)
    if not wanted then return 999 end

    local rank = 1
    if type(prioOrder) == "table" then
        for _, pk in ipairs(prioOrder) do
            pk = GFNormalizePriorityKey(pk)
            if allowed[pk] then
                if pk == wanted then return rank end
                rank = rank + 1
            end
        end
    end
    for i = 1, #defaults do
        local pk = defaults[i]
        if not GFPrioRawHasAllowedKey(prioOrder, allowed, pk) then
            if pk == wanted then return rank end
            rank = rank + 1
        end
    end
    return 999
end

local _GF_PRIORITY_SIGNATURE = {
    magic = 1,
    curse = 2,
    disease = 3,
    poison = 4,
    bleed = 5,
    dispel = 6,
    aggro = 7,
    purge = 8,
    bossTarget = 9,
    target = 10,
    focus = 11,
}

local function GFDispelScanPrioritySignature(kind, c, useOverlayPriority)
    if c then
        local sig = useOverlayPriority and c.dispelOverlayPrioritySig or c.dispelBorderPrioritySig
        if sig ~= nil then return sig end
    end
    local enabled, order = GFDispelScanPriorityConfig(kind, c, useOverlayPriority)
    local sig = enabled and 1 or 0
    if useOverlayPriority and GFOverlayUsesOwnPriority(c) then
        sig = sig + 10
    end
    if ((c and c.hlDispelColorMode) or GFDispelColorScopeValue(kind, "hlDispelColorMode", nil, "SINGLE")) == "TYPE" then
        sig = sig + 20
    end
    if type(order) == "table" then
        for i = 1, #order do
            sig = sig * 13 + (_GF_PRIORITY_SIGNATURE[GFNormalizePriorityKey(order[i])] or 0)
        end
    end
    return sig
end

local function GFDispelCachedPriorityEnabled(kind, c, useOverlayPriority)
    if c then
        local enabled = useOverlayPriority and c.dispelOverlayPriorityScan or c.dispelBorderPriorityScan
        if enabled ~= nil then return enabled == true end
    end
    return GFDispelScanPriorityEnabled(kind, c, useOverlayPriority)
end

local function GFDispelCachedResolveType(kind, c, triggerMode, useOverlayPriority)
    if c then
        triggerMode = GF.NormalizeDispelBorderTrigger(triggerMode)
        if useOverlayPriority then
            if c.dispelOverlayTrigger == triggerMode and c.dispelOverlayResolveType ~= nil then
                return c.dispelOverlayResolveType == true
            end
        elseif c.dispelBorderTrigger == triggerMode and c.dispelBorderResolveType ~= nil then
            return c.dispelBorderResolveType == true
        end
    end
    return GFDispelScanResolveType(kind, c, triggerMode, useOverlayPriority)
end

local _GF_LAYER_SINGLE_DEFAULTS = { "dispel", "aggro", "purge", "bossTarget", "target", "focus" }
local _GF_LAYER_TYPE_DEFAULTS = { "magic", "curse", "disease", "poison", "bleed", "aggro", "purge", "bossTarget", "target", "focus" }
local _GF_LAYER_SINGLE_ALLOWED = { dispel = true, aggro = true, purge = true, bossTarget = true, target = true, focus = true }
local _GF_LAYER_TYPE_ALLOWED = {
    magic = true,
    curse = true,
    disease = true,
    poison = true,
    bleed = true,
    dispel = true,
    aggro = true,
    purge = true,
    bossTarget = true,
    target = true,
    focus = true,
}

local function GFHighlightLayerKeyMatches(layerKind, orderKey, dispelType)
    if layerKind == "dispel" then
        return orderKey == "dispel" or _GF_DISPEL_TYPE_ORDER_KEYS[orderKey] == true
    end
    return orderKey == layerKind
end

local function GFDispelPriorityKey(dispelType)
    if issecretvalue and issecretvalue(dispelType) then return nil end
    return _GF_PRIORITY_KEY_BY_DISPEL_TYPE[dispelType]
        or (_GF_DISPEL_TYPE_ORDER_KEYS[dispelType] and dispelType)
end

GFHighlightUsesTypeLane = function(kind, c)
    local enabled = c and (c.hlPrioEnabled == true or c.hlPrioEnabled == 1)
    local order = enabled and c and c.hlPrioOrder or nil
    return ((c and c.hlDispelColorMode) or GFDispelColorScopeValue(kind, "hlDispelColorMode", nil, "SINGLE")) == "TYPE"
        or (enabled and GFPrioOrderHasTypeKey(order))
end

local function GFHighlightFrameKey(kind, c, layerKind, dispelType)
    return layerKind
end

local function GFHighlightLayerOffset(kind, c, layerKind, dispelType)
    local enabled = c and (c.hlPrioEnabled == true or c.hlPrioEnabled == 1)
    local order = enabled and c and c.hlPrioOrder or nil
    local typeMode = ((c and c.hlDispelColorMode) or GFDispelColorScopeValue(kind, "hlDispelColorMode", nil, "SINGLE")) == "TYPE"
        or (enabled and GFPrioOrderHasTypeKey(order))
    local allowed = typeMode and _GF_LAYER_TYPE_ALLOWED or _GF_LAYER_SINGLE_ALLOWED
    local defaults = typeMode and _GF_LAYER_TYPE_DEFAULTS or _GF_LAYER_SINGLE_DEFAULTS
    local pos, count = nil, 0

    local function consider(orderKey)
        orderKey = GFNormalizePriorityKey(orderKey)
        if not allowed[orderKey] then return end
        count = count + 1
        if not pos and GFHighlightLayerKeyMatches(layerKind, orderKey, dispelType) then
            pos = count
        end
    end

    if enabled and type(order) == "table" then
        for i = 1, #order do
            consider(order[i])
        end
    end
    for i = 1, #defaults do
        local orderKey = defaults[i]
        if not (enabled and GFPrioRawHasAllowedKey(order, allowed, orderKey)) then
            consider(orderKey)
        end
    end

    if not pos and layerKind == "dispel" then pos = 1 end
    if not pos then pos = count end
    if count < 1 then count, pos = 1, 1 end
    return (GF.LAYER_HIGHLIGHT_BORDER or 10) + (count - pos)
end

local function GFDispelOverlayLayerOffset(kind, c, dispelType)
    return GF.LAYER_DISPEL_OVERLAY or 6
end

GFDispelOverlayUsesTypeLane = function(kind, c)
    return false
end

local function GFDispelOverlayFrameKey(kind, c, dispelType)
    return "default"
end

local function GFEnsureHighlightBorder(f, layerKind)
    if not f then return nil end
    local borders = f._msufGFHighlightBorders
    if not borders then
        borders = {}
        f._msufGFHighlightBorders = borders
        if f._msufGFHighlightBorder then
            borders.dispel = f._msufGFHighlightBorder
            f._msufGFHighlightBorder._msufGFHLKey = "dispel"
            f._msufGFDispelHighlightBorder = f._msufGFHighlightBorder
        end
    end
    local border = borders[layerKind]
    if border then return border end

    local parent = f.barGroup or f
    local template = (BackdropTemplateMixin and "BackdropTemplate") or nil
    border = _G.CreateFrame("Frame", nil, parent, template)
    border:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    border:EnableMouse(false)
    border._msufGFHLKey = layerKind
    if GF.SyncFrameLayerAbove then
        GF.SyncFrameLayerAbove(border, f.health or parent, GF.LAYER_HIGHLIGHT_BORDER or 10)
    end
    border:Hide()
    borders[layerKind] = border
    if layerKind == "dispel" or (type(layerKind) == "string" and layerKind:sub(1, 7) == "dispel:") then
        f._msufGFDispelHighlightBorder = f._msufGFDispelHighlightBorder or border
    end
    return border
end

-- Dispel glow helpers (GF).
local _gfGlowColor = { 0, 0, 0, 1 }
local _gfProcGlowOptions = { color = _gfGlowColor, key = "msufDispel" }

local function _GF_DispelBorderTestApplies(f, kind)
    if not (f and _G.MSUF_BorderTestModesActive == true and _G.MSUF_DispelBorderTestMode == true) then
        return false
    end
    local testScope = _G.MSUF_DispelBorderTestScope or "shared"
    if testScope == "shared" then return true end
    local scopeKind = (testScope == "party" or testScope == "gf_party") and "party"
        or (testScope == "raid" or testScope == "gf_raid") and "raid"
        or (testScope == "mythicraid" or testScope == "gf_mythicraid") and "mythicraid"
        or nil
    return scopeKind ~= nil and scopeKind == (kind or f._msufGFKind or "party")
end

local function _GF_StartDispelGlow(f, r, g, b)
    local kind = f._msufGFKind or "party"
    local blizzardBlocksGlow = false
    local c = f and f._c
    local testMode = _GF_DispelBorderTestApplies(f, kind)
    if c and c.nativeBlizzardDispelsSuppressCustom ~= nil then
        blizzardBlocksGlow = c.nativeBlizzardDispelsSuppressCustom == true and not testMode
    else
        local blocksGlow = _G.MSUF_GroupBlizzardAuraRenderingBlocksDispelGlow
        if type(blocksGlow) == "function" then
            blizzardBlocksGlow = blocksGlow(kind) == true and not testMode
        end
    end
    if not LCG or blizzardBlocksGlow or not HLVal(kind, "hlDispelGlowEnabled") then
        if not f._msufGFDispelGlowActive
            and not f._msufGFDispelGlowAnchor
            and not f._msufGFDispelGlowStyle
        then
            return
        end
        f._msufGFDispelGlowActive = nil
        local offAnchor = f._msufGFDispelGlowAnchor
        f._msufGFDispelGlowAnchor = nil
        f._msufGFDispelGlowStyle = nil
        f._msufGFDispelGlowR = nil
        f._msufGFDispelGlowG = nil
        f._msufGFDispelGlowB = nil
        f._msufGFDispelGlowLines = nil
        f._msufGFDispelGlowFreq = nil
        f._msufGFDispelGlowThick = nil
        if LCG then
            if offAnchor then
                LCG.PixelGlow_Stop(offAnchor, "msufDispel")
                LCG.AutoCastGlow_Stop(offAnchor, "msufDispel")
                LCG.ProcGlow_Stop(offAnchor, "msufDispel")
            end
            local borders = f._msufGFHighlightBorders
            if borders then
                for _, offBorder in pairs(borders) do
                    if offBorder and offBorder ~= offAnchor then
                        LCG.PixelGlow_Stop(offBorder, "msufDispel")
                        LCG.AutoCastGlow_Stop(offBorder, "msufDispel")
                        LCG.ProcGlow_Stop(offBorder, "msufDispel")
                    end
                end
            else
                local offBorder = f._msufGFHighlightBorder
                if offBorder and offBorder ~= offAnchor then
                    LCG.PixelGlow_Stop(offBorder, "msufDispel")
                    LCG.AutoCastGlow_Stop(offBorder, "msufDispel")
                    LCG.ProcGlow_Stop(offBorder, "msufDispel")
                end
            end
            if f ~= offAnchor then
                LCG.PixelGlow_Stop(f, "msufDispel")
                LCG.AutoCastGlow_Stop(f, "msufDispel")
                LCG.ProcGlow_Stop(f, "msufDispel")
            end
        end
        return
    end
    local anchor = f._msufRGF_GlowAnchor or f._msufGFDispelHighlightBorder or f._msufGFHighlightBorder or f
    local style = HLVal(kind, "hlDispelGlowStyle") or "PIXEL"
    local lines = tonumber(HLVal(kind, "hlDispelGlowLines")) or 8
    local freq  = tonumber(HLVal(kind, "hlDispelGlowFrequency")) or 0.25
    local thick = tonumber(HLVal(kind, "hlDispelGlowThickness")) or 2
    local secretColor = issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b))
    if not secretColor
        and f._msufGFDispelGlowActive == true
        and f._msufGFDispelGlowAnchor == anchor
        and f._msufGFDispelGlowStyle == style
        and f._msufGFDispelGlowR == r
        and f._msufGFDispelGlowG == g
        and f._msufGFDispelGlowB == b
        and f._msufGFDispelGlowLines == lines
        and f._msufGFDispelGlowFreq == freq
        and f._msufGFDispelGlowThick == thick
    then
        return
    end
    local oldAnchor = f._msufGFDispelGlowAnchor
    if oldAnchor and (oldAnchor ~= anchor or f._msufGFDispelGlowStyle ~= style) then
        LCG.PixelGlow_Stop(oldAnchor, "msufDispel")
        LCG.AutoCastGlow_Stop(oldAnchor, "msufDispel")
        LCG.ProcGlow_Stop(oldAnchor, "msufDispel")
    end
    if anchor ~= f then
        LCG.PixelGlow_Stop(f, "msufDispel")
        LCG.AutoCastGlow_Stop(f, "msufDispel")
        LCG.ProcGlow_Stop(f, "msufDispel")
    end
    _gfGlowColor[1], _gfGlowColor[2], _gfGlowColor[3] = r, g, b
    if style == "AUTOCAST" then
        LCG.AutoCastGlow_Start(anchor, _gfGlowColor, lines, freq, nil, nil, nil, "msufDispel")
    elseif style == "PROC" then
        LCG.ProcGlow_Start(anchor, _gfProcGlowOptions)
    else
        LCG.PixelGlow_Start(anchor, _gfGlowColor, lines, freq, nil, thick, nil, nil, nil, "msufDispel")
    end
    f._msufGFDispelGlowActive = true
    f._msufGFDispelGlowAnchor = anchor
    f._msufGFDispelGlowStyle = style
    if not secretColor then
        f._msufGFDispelGlowR = r
        f._msufGFDispelGlowG = g
        f._msufGFDispelGlowB = b
    else
        f._msufGFDispelGlowR = nil
        f._msufGFDispelGlowG = nil
        f._msufGFDispelGlowB = nil
    end
    f._msufGFDispelGlowLines = lines
    f._msufGFDispelGlowFreq = freq
    f._msufGFDispelGlowThick = thick
end

local function _GF_StopDispelGlow(f)
    if not f then return end
    if not f._msufGFDispelGlowActive
        and not f._msufGFDispelGlowAnchor
        and not f._msufGFDispelGlowStyle
    then
        return
    end
    f._msufGFDispelGlowActive = nil
    local anchor = f._msufGFDispelGlowAnchor
    f._msufGFDispelGlowAnchor = nil
    f._msufGFDispelGlowStyle = nil
    f._msufGFDispelGlowR = nil
    f._msufGFDispelGlowG = nil
    f._msufGFDispelGlowB = nil
    f._msufGFDispelGlowLines = nil
    f._msufGFDispelGlowFreq = nil
    f._msufGFDispelGlowThick = nil
    if not LCG then return end
    if anchor then
        LCG.PixelGlow_Stop(anchor, "msufDispel")
        LCG.AutoCastGlow_Stop(anchor, "msufDispel")
        LCG.ProcGlow_Stop(anchor, "msufDispel")
    end

    local borders = f._msufGFHighlightBorders
    if borders then
        for _, border in pairs(borders) do
            if border and border ~= anchor then
                LCG.PixelGlow_Stop(border, "msufDispel")
                LCG.AutoCastGlow_Stop(border, "msufDispel")
                LCG.ProcGlow_Stop(border, "msufDispel")
            end
        end
    else
        local border = f._msufGFHighlightBorder
        if border and border ~= anchor then
            LCG.PixelGlow_Stop(border, "msufDispel")
            LCG.AutoCastGlow_Stop(border, "msufDispel")
            LCG.ProcGlow_Stop(border, "msufDispel")
        end
    end
    if f ~= anchor then
        LCG.PixelGlow_Stop(f, "msufDispel")
        LCG.AutoCastGlow_Stop(f, "msufDispel")
        LCG.ProcGlow_Stop(f, "msufDispel")
    end
end

------------------------------------------------------------------------
-- Debuff stripe: presence callback (must be before dispatchAura)
------------------------------------------------------------------------
local _QUESTION_MARK_ICON = 136243
local _PADLOCK_ICON = 134400
local _dsPresenceResult = false
local _dsPresenceAF = nil
local _dsPresenceBLHash = nil
local _FrameHasStripeDebuff

local function _DecodeStripeAuraIconFileID(icon)
    if icon == nil then return 0 end
    if issecretvalue and issecretvalue(icon) == true then return 0 end
    return tonumber(icon) or 0
end

local function _dsPresenceCallback(aura)
    if not aura then return false end

    local af = _dsPresenceAF
    local blHash = _dsPresenceBLHash
    if blHash and af then
        local sid = af.DecodeSpellId(aura)
        if af.IsBlacklisted(sid, blHash, aura) then
            return false
        end
    end

    local iconFileID = _DecodeStripeAuraIconFileID(aura.icon)
    if iconFileID == _QUESTION_MARK_ICON or iconFileID == _PADLOCK_ICON then
        return false
    end

    _dsPresenceResult = true
    return true  -- stop iteration
end

------------------------------------------------------------------------
-- Forward declarations (defined later in file)
local _GF_RefreshBorder
local _GF_ApplyDispelOverlay
local _GF_ApplyDebuffStripe
local _GF_ClearNativeSuppressedDispel

------------------------------------------------------------------------
-- UNIT_AURA: per-frame dispatch with burst-dedup (A2 P2 pattern)
-- Fast-paths (update-only 16Ã‚Âµs, remove-only-not-displayed) still fire
-- instantly. Full pipeline is gated: first event runs immediately,
-- subsequent same-frame events within 20ms are skipped.
-- Zero steady-state alloc: clear-callback allocated once per frame.
------------------------------------------------------------------------
-- Legacy _After0 removed from runtime hot paths; use central scheduler helpers above.

------------------------------------------------------------------------
-- PERF: Global per-frame budget for full aura scans.
-- AoE heal/damage Ã¢â€ â€™ 20 UNIT_AURA events in same frame Ã¢â€ â€™ 20 Ãƒâ€” 138Ã‚Âµs = 2.8ms spike.
-- Budget limits full scans to 8 per frame. Excess deferred to next frame via C_Timer.After(0).
-- Max spike capped to 8 Ãƒâ€” 138Ã‚Âµs Ã¢â€°Ë† 1.1ms.
------------------------------------------------------------------------
local _GF_AURA_BUDGET_MAX = 8
local _gfAuraBudget = 0
local _gfAuraDirtyPending = false
local _gfAuraBudgetFrame = 0  -- GetTime of last budget reset
local _gfAuraDirtyQueue = {}
local _gfAuraDirtyQueued = {}
local _gfAuraDirtyHead, _gfAuraDirtyTail = 1, 0

local function _gfQueueAuraDirty(f)
    if not f then return end
    f._msufGFAuraDirty = true
    if not _gfAuraDirtyQueued[f] then
        _gfAuraDirtyQueued[f] = true
        _gfAuraDirtyTail = _gfAuraDirtyTail + 1
        _gfAuraDirtyQueue[_gfAuraDirtyTail] = f
    end
end

-- Forward-declared; assigned after dispatchAura is defined.
local _gfFlushDirtyAuras
local function SpellIndicatorsNeedRefresh(f, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return true end

    if GF.SpellIndicatorsUnitAuraRelevant then
        return GF.SpellIndicatorsUnitAuraRelevant(f, f and f.unit, f and f._msufGFKind or "party", updateInfo)
    end

    local added = updateInfo.addedAuras
    if added and #added > 0 then
        return true
    end

    local tracked = f and f._msufSIDedupIDs
    if not tracked then return false end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated then
        for i = 1, #updated do
            if tracked[updated[i]] then return true end
        end
    end

    local removed = updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            if tracked[removed[i]] then return true end
        end
    end

    return false
end

local function NativeAuraContainerReady(f, unit)
    local container = f and f._msufGFNativeAuras
    if not (container and container._msufNativeAuraAnchorID) then return false end
    local Native = ns and ns.MSUF_AuraNative
    local effectiveUnit = Native and Native.ResolveUnitToken and Native.ResolveUnitToken(unit) or unit
    return container._msufNativeAuraUnit == effectiveUnit
end

function GF.FinishAuraVisuals(f, unit, c, updateInfo)
    if not (f and c) then return end
    if c.nativeBlizzardDispelsSuppressCustom and not GF.DispelScanActive(c) then
        if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
    elseif GF.DispelScanActive(c) then
        if GF._UpdateDispel then GF._UpdateDispel(f, unit) end
    elseif f._msufGFDispelType or f._msufGFMergedDispel
        or f._msufGFDispelAuraID or f._msufGFPrevDispelAuraID
        or f._msufGFDispelOverlayType or f._msufGFMergedDispelOverlay
        or f._msufGFDispelOverlayAuraID or f._msufGFPrevDispelOverlayAuraID
    then
        local mergedDispel = f._msufGFMergedDispel
        local mergedOverlay = f._msufGFMergedDispelOverlay
        local prevDispel = f._msufGFDispelType
        local prevOverlay = f._msufGFDispelOverlayType
        local dispelAid = f._msufGFDispelAuraID
        local overlayAid = f._msufGFDispelOverlayAuraID
        local prevAid = f._msufGFPrevDispelAuraID
        local prevOverlayAid = f._msufGFPrevDispelOverlayAuraID
        local colorRev = _G.MSUF_ColorStyleRevision or 0
        local prevColorRev = f._msufGFColorStyleRevision or 0
        local settingsSerial = (c and c._cacheSerial) or 0
        local prevSettingsSerial = f._msufGFAuraVisualSerial or 0
        local settingsChanged = settingsSerial ~= prevSettingsSerial
        local borderChanged = mergedDispel ~= prevDispel or dispelAid ~= prevAid or colorRev ~= prevColorRev or settingsChanged
        local overlayChanged = mergedOverlay ~= prevOverlay or overlayAid ~= prevOverlayAid or colorRev ~= prevColorRev or settingsChanged
        if borderChanged or overlayChanged then
            f._msufGFDispelType = mergedDispel
            f._msufGFPrevDispelAuraID = dispelAid
            f._msufGFDispelOverlayType = mergedOverlay
            f._msufGFPrevDispelOverlayAuraID = overlayAid
            f._msufGFColorStyleRevision = colorRev
            f._msufGFAuraVisualSerial = settingsSerial
            if borderChanged then _GF_RefreshBorder(f, unit) end
            if overlayChanged or borderChanged then _GF_ApplyDispelOverlay(f) end
        end
    end

    if c.dsEn then
        local scanStripe = not updateInfo or updateInfo.isFullUpdate or f._msufGFHasAnyDebuff == nil
        if not scanStripe then
            local added = updateInfo.addedAuras
            if added and #added > 0 then
                scanStripe = true
            else
                local removed = updateInfo.removedAuraInstanceIDs
                scanStripe = removed and #removed > 0
            end
        end
        if scanStripe then
            local hadDebuff = f._msufGFHasAnyDebuff or false
            local hasDebuff = (_FrameHasStripeDebuff and _FrameHasStripeDebuff(f, unit)) or false
            f._msufGFHasAnyDebuff = hasDebuff
            if hasDebuff ~= hadDebuff then
                _GF_ApplyDebuffStripe(f)
            end
        end
    end

    if GF.UpdateCornerIndicators and c.ciAura then
        GF.UpdateCornerIndicators(f, unit)
    end
end

local function dispatchAura(f, unit, updateInfo)
    local c = f._c
    if not c then return end
    local kind = f._msufGFKind or "party"
    -- PERF: use pre-cached flags from BuildFrameCache (was GF.GetConf per event)
    local aurasOn = c.anyAuraGrp
    local priorityWinnerScan = GF.DispelScanActive(c)
        and (GFDispelCachedPriorityEnabled(kind, c, false)
            or GFDispelScanCustomTypePriorityEnabled(kind, c, false)
            or GFDispelCachedPriorityEnabled(kind, c, true)
            or GFDispelScanCustomTypePriorityEnabled(kind, c, true))
    local winnerDelta = priorityWinnerScan and updateInfo and not updateInfo.isFullUpdate
        and ((updateInfo.addedAuras and #updateInfo.addedAuras > 0)
            or (updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0))
    if winnerDelta then
        f._msufGFDispelFindCache = nil
        updateInfo = nil
    end
    local siRefresh = c.siEn and SpellIndicatorsNeedRefresh(f, updateInfo) or false

    -- PERF: CornerIndicators only care about aura add/remove, not duration/stack
    -- updates. Skip CI when the event is a pure update (saves ~300ms/min in raids).
    local ciRelevant = not updateInfo or updateInfo.isFullUpdate
        or (updateInfo.addedAuras and #updateInfo.addedAuras > 0)
        or (updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0)

    if not aurasOn then
        local dispelChanged, dispelRelevant
        if GF.DispelScanActive(c) then
            -- EQoL dirty-flag: only rescan when dispel state may have changed
            local needDispelScan = false
            if not updateInfo or updateInfo.isFullUpdate then
                needDispelScan = true
            elseif priorityWinnerScan then
                needDispelScan = true
            else
                local added = updateInfo.addedAuras
                if added and #added > 0 then needDispelScan = true end
                if not needDispelScan then
                    local updated = updateInfo.updatedAuraInstanceIDs
                    if updated and #updated > 0 then
                        local trackedAid = f._msufGFDispelAuraID
                        local overlayTrackedAid = f._msufGFDispelOverlayAuraID
                        if trackedAid or overlayTrackedAid then
                            for ui = 1, #updated do
                                local aid = updated[ui]
                                if aid == trackedAid or aid == overlayTrackedAid then
                                    needDispelScan = true; break
                                end
                            end
                        end
                    end
                end
                if not needDispelScan then
                    local removed = updateInfo.removedAuraInstanceIDs
                    if removed and #removed > 0 then
                        local trackedAid = f._msufGFDispelAuraID
                        local overlayTrackedAid = f._msufGFDispelOverlayAuraID
                        if trackedAid or overlayTrackedAid then
                            for ri = 1, #removed do
                                local aid = removed[ri]
                                if aid == trackedAid or aid == overlayTrackedAid then
                                    needDispelScan = true; break
                                end
                            end
                        end
                    end
                end
            end
            if needDispelScan then
                if GF._UpdateDispelFromAuraDelta then
                    dispelChanged, dispelRelevant = GF._UpdateDispelFromAuraDelta(f, unit, updateInfo)
                else
                    GF._UpdateDispel(f, unit)
                    dispelChanged, dispelRelevant = true, true
                end
            end
        end
        if siRefresh and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if GF.UpdateCornerIndicators and ((c.ciCustom and ciRelevant)
            or (c.ciDispel and ((not GF.DispelScanActive(c) and ciRelevant) or dispelChanged or dispelRelevant)))
        then
            GF.UpdateCornerIndicators(f, unit)
        end
        return
    end

    -- c.anyAuraGrp already includes sub-group enabled check, no need for second pass
    if c.nativeBlizzardAuraOnly and not c.ciAura and not c.dsEn then
        if GF.DispelScanActive(c) then
            if GF._UpdateDispelFromAuraDelta then
                GF._UpdateDispelFromAuraDelta(f, unit, updateInfo)
            elseif GF._UpdateDispel then
                GF._UpdateDispel(f, unit)
            end
        end
        if siRefresh and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if not NativeAuraContainerReady(f, unit) and GF.UpdateFrameAuras then
            GF.UpdateFrameAuras(f, unit, updateInfo)
        end
        return
    end

    -- Full rescan required
    if not updateInfo or updateInfo.isFullUpdate then
        -- Throttle fullUpdate when out of combat (Blizzard fires these periodically)
        if updateInfo and updateInfo.isFullUpdate and not InCombatLockdown() then
            local now = GetTime()
            local last = f._msufGFLastFullAura
            if last and (now - last) < 0.5 then
                if siRefresh and GF.UpdateSpellIndicators then
                    GF.UpdateSpellIndicators(f, unit)
                end
                return
            end
            f._msufGFLastFullAura = now
        end
        -- fall through to full pipeline below
    else
        local added   = updateInfo.addedAuras
        local removed = updateInfo.removedAuraInstanceIDs
        local updated = updateInfo.updatedAuraInstanceIDs
        local hasAdd = added and #added > 0
        local hasRem = removed and #removed > 0
        local hasUpd = updated and #updated > 0

        -- Nothing relevant at all
        if not hasAdd and not hasRem and not hasUpd then
            if siRefresh and GF.UpdateSpellIndicators then
                GF.UpdateSpellIndicators(f, unit)
            end
            return
        end

        local displayed = f._msufDisplayedAuraIDs

        -- Update-only: direct icon refresh (16Ã‚Âµs vs 115Ã‚Âµs)
        if not hasAdd and not hasRem and hasUpd then
            if displayed and GF.RefreshAuraIcon then
                local needsDeltaPipeline = false
                for ui = 1, #updated do
                    local icon = displayed[updated[ui]]
                    if icon then
                        if GF.RefreshAuraIcon(icon, unit, updated[ui]) == false then
                            needsDeltaPipeline = true
                            break
                        end
                    end
                end
                if not needsDeltaPipeline then
                    if siRefresh and GF.UpdateSpellIndicators then
                        GF.UpdateSpellIndicators(f, unit)
                    end
                    return
                end
            end
        end

        -- Add/remove: handled below by the cache-backed delta pipeline.
    end

    if updateInfo and not updateInfo.isFullUpdate then
        if c.siEn and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if GF.UpdateFrameAuras then
            GF.UpdateFrameAuras(f, unit, updateInfo)
        elseif GF._UpdateDispel then
            GF._UpdateDispel(f, unit)
        end
        GF.FinishAuraVisuals(f, unit, c, updateInfo)
        return
    end

    -- Out-of-combat rate limit: max 2 full rescans/s per frame (idle optimization)
    -- In combat: unlimited (instant debuff detection)
    if not InCombatLockdown() then
        local now = GetTime()
        if f._msufGFLastFullAura and (now - f._msufGFLastFullAura) < 0.5 then
            if siRefresh and GF.UpdateSpellIndicators then
                GF.UpdateSpellIndicators(f, unit)
            end
            return
        end
        f._msufGFLastFullAura = now
    end

    -- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
    -- P1: In-combat burst-dedup (A2 P2 pattern)
    -- First event runs the full pipeline immediately (zero latency).
    -- Subsequent events for the SAME frame within 20ms are skipped.
    -- Saves N-1 full pipeline runs per AoE burst (N=simultaneous aura
    -- changes per unit). Clear-callback allocated once per frame.
    -- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
    if f._msufGFFullPending and not priorityWinnerScan then
        return
    end
    if not f._msufGFFullPending then
        f._msufGFFullPending = true
        local cb = f._msufGFPendClearCB
        if not cb then
            local frame = f
            cb = function() frame._msufGFFullPending = nil end
            f._msufGFPendClearCB = cb
        end
        local key = f._msufGFPendClearKey
        if not key then
            key = "GF_AURA_PEND_" .. tostring(f)
            f._msufGFPendClearKey = key
        end
        _MSUF_ScheduleDelayOnce(key, 0.02, cb)
    end

    -- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
    -- P2: Global per-frame budget (AoE spike limiter)
    -- AoE events fire 20+ UNIT_AURA for different units in one frame.
    -- Each full scan costs ~138Ã‚Âµs. 20 Ãƒâ€” 138Ã‚Âµs = 2.8ms spike.
    -- Budget caps to 8 scans/frame Ã¢â€ â€™ max ~1.1ms. Rest deferred.
    -- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
    _gfAuraBudget = _gfAuraBudget + 1
    local now = GetTime()
    if now ~= _gfAuraBudgetFrame then
        _gfAuraBudgetFrame = now
        _gfAuraBudget = 1
    end
    if _gfAuraBudget > _GF_AURA_BUDGET_MAX then
        _gfQueueAuraDirty(f)
        if not _gfAuraDirtyPending then
            _gfAuraDirtyPending = true
            _MSUF_ScheduleOnce("GF_AURA_BUDGET_FLUSH", _gfFlushDirtyAuras)
        end
        return
    end

    -- Full aura processing (add/remove/fullUpdate)
    -- SI runs first: populates dedup IDs before buff scan
    if c.siEn and GF.UpdateSpellIndicators then
        GF.UpdateSpellIndicators(f, unit)
    end
    if GF.UpdateFrameAuras then
        GF.UpdateFrameAuras(f, unit, updateInfo)
    else
        GF._UpdateDispel(f, unit)
    end
    GF.FinishAuraVisuals(f, unit, c, updateInfo)

end

------------------------------------------------------------------------
-- Deferred aura flush: processes frames that exceeded the per-frame budget.
-- Fires via C_Timer.After(0) Ã¢â€ â€™ runs at the start of the next frame.
------------------------------------------------------------------------
_gfFlushDirtyAuras = function()
    _gfAuraBudget = 0
    _gfAuraDirtyPending = false

    -- Process at most the same number of deferred full aura scans that the
    -- immediate path allows per frame. The previous loop walked the whole
    -- queue and relied on dispatchAura to re-queue overflow frames, which was
    -- correct but created extra Lua churn during large raid-wide aura bursts.
    local processed = 0
    local stopTail = _gfAuraDirtyTail
    while _gfAuraDirtyHead <= stopTail and processed < _GF_AURA_BUDGET_MAX do
        local f = _gfAuraDirtyQueue[_gfAuraDirtyHead]
        _gfAuraDirtyQueue[_gfAuraDirtyHead] = nil
        _gfAuraDirtyHead = _gfAuraDirtyHead + 1
        if f then
            _gfAuraDirtyQueued[f] = nil
            if f._msufGFAuraDirty then
                f._msufGFAuraDirty = nil
                local u = f.unit
                if u and UnitExists(u) then
                    -- This is the deferred full scan, so bypass the short
                    -- same-unit burst guard that scheduled the deferral.
                    f._msufGFFullPending = nil
                    dispatchAura(f, u, nil)
                end
            end
        end
        processed = processed + 1
    end
    if _gfAuraDirtyHead > _gfAuraDirtyTail then
        _gfAuraDirtyHead, _gfAuraDirtyTail = 1, 0
    elseif not _gfAuraDirtyPending then
        _gfAuraDirtyPending = true
        _MSUF_ScheduleOnce("GF_AURA_BUDGET_FLUSH", _gfFlushDirtyAuras)
    end
end
------------------------------------------------------------------------
-- Dispel overlay (color wash on health bar)
-- StatusBar-based: mirrors health value for "current health only" clip.
--
-- SECRET-SAFE COLOR APPLICATION (Midnight 12.0):
--   TYPE mode returns a Color object from C_UnitAuras.GetAuraDispelTypeColor.
--   Secret-tainted RGB values CAN pass through tex:SetVertexColor varargs
--   (C-side handles them) but CANNOT pass through CreateColor/SetGradient
--   (Lua-side taints). We therefore:
--     Ã¢â‚¬Â¢ use pre-baked gradient *textures* (Media/MSUF_Grad_*.tga) for the
--       TOP/BOTTOM/LEFT/RIGHT/EDGE styles Ã¢â‚¬â€ no SetGradient needed,
--     Ã¢â‚¬Â¢ apply the tint via tex:SetVertexColor(color:GetRGBA()) in a single
--       varargs passthrough Ã¢â‚¬â€ no Lua arithmetic on the tint values,
--     Ã¢â‚¬Â¢ use SetAlpha on the StatusBar frame for the user's doAlpha slider.
--
--   This replaces the Beta 5 path that called CreateColor(secret_r, ...)
--   in SetGradient branches Ã¢â‚¬â€ that was the "TYPE mode broken / only
--   SINGLE works" bug.
------------------------------------------------------------------------
local _MSUF_GRAD_PATH = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"
local _GRAD_TEXTURES = {
    FULL   = "Interface\\Buttons\\WHITE8x8",
    TOP    = _MSUF_GRAD_PATH .. "MSUF_Grad_V",      -- solid top,    fades down
    BOTTOM = _MSUF_GRAD_PATH .. "MSUF_Grad_V_Rev",  -- solid bottom, fades up
    LEFT   = _MSUF_GRAD_PATH .. "MSUF_Grad_H",      -- solid left,   fades right
    RIGHT  = _MSUF_GRAD_PATH .. "MSUF_Grad_H_Rev",  -- solid right,  fades left
}

local function GFEnsureDispelOverlay(f, frameKey)
    if not f then return nil end
    frameKey = frameKey or "default"
    local overlays = f._msufGFDispelOverlays
    if not overlays then
        overlays = {}
        f._msufGFDispelOverlays = overlays
        if f._msufGFDispelOverlay then
            overlays.default = f._msufGFDispelOverlay
            f._msufGFDispelOverlay._msufGFDOKey = "default"
        end
    end
    local overlay = overlays[frameKey]
    if overlay then return overlay end
    if InCombatLockdown and InCombatLockdown() then
        return f._msufGFDispelOverlay
    end

    local parent = f.barGroup or f
    overlay = _G.CreateFrame("StatusBar", nil, parent)
    overlay:SetStatusBarTexture(_GRAD_TEXTURES.FULL)
    overlay:SetMinMaxValues(0, 1)
    overlay:SetValue(1)
    overlay:SetAllPoints(f.health or parent)
    overlay:SetStatusBarColor(0, 0, 0, 0)
    overlay._msufGFDOKey = frameKey
    if GF.SyncFrameLayerAbove then
        GF.SyncFrameLayerAbove(overlay, f.health or parent, GF.LAYER_DISPEL_OVERLAY or 6)
    end
    overlay:Hide()
    overlays[frameKey] = overlay
    if not f._msufGFDispelOverlay then f._msufGFDispelOverlay = overlay end
    return overlay
end

local function GFHideDispelOverlays(f)
    if not f then return end
    local overlays = f._msufGFDispelOverlays
    if overlays then
        for _, overlay in pairs(overlays) do
            if overlay and overlay.Hide then overlay:Hide() end
            if overlay then
                overlay._msufDOSyncHP = nil
                overlay._msufDOFullValue = nil
            end
        end
    else
        local overlay = f._msufGFDispelOverlay
        if overlay and overlay.Hide then overlay:Hide() end
        if overlay then overlay._msufDOSyncHP = nil end
    end
end

local function GFPrimePriorityTypeLayers(f, kind, c)
    return
end

_GF_ApplyDispelOverlay = function(f)
    if not f then return end
    local c = f._c
    local kind = f._msufGFKind or "party"
    local dispelType = f._msufGFDispelOverlayType
    local frameKey = GFDispelOverlayFrameKey(kind, c, dispelType)
    local dov = GFEnsureDispelOverlay(f, frameKey)
    if not dov then
        return
    end
    if not c then return end
    GFPrimePriorityTypeLayers(f, kind, c)

    if not c.doEn or not dispelType then
        GFHideDispelOverlays(f)
        return
    end

    local overlays = f._msufGFDispelOverlays
    if overlays then
        for key, other in pairs(overlays) do
            if other and key ~= frameKey and other.Hide then other:Hide() end
        end
    end
    f._msufGFDispelOverlay = dov

    local layerOffset = GFDispelOverlayLayerOffset(kind, c, dispelType)

    -- Safety: anchor overlay to correct region based on style + doOnHP
    if f.health then
        local anchorTo = f.health
        if c.doStyle == "FULL" and not c.doOnHP and f.barGroup then
            anchorTo = f.barGroup
        end
        if dov._msufDOAnchorTo ~= anchorTo then
            dov:ClearAllPoints()
            dov:SetAllPoints(anchorTo)
            dov._msufDOAnchorTo = anchorTo
        end
        if GF.SyncFrameLayerAbove then
            GF.SyncFrameLayerAbove(dov, f.health, layerOffset)
        elseif dov.SetFrameLevel and f.health.GetFrameLevel then
            dov:SetFrameLevel(f.health:GetFrameLevel() + layerOffset)
        end
        dov._msufDOLayerOffset = layerOffset
    end

    -- Pick gradient texture for the style (cheap diff-gate to avoid spamming
    -- SetStatusBarTexture Ã¢â‚¬â€ Blizzard reloads the atlas every call).
    local style = c.doStyle or "FULL"
    local texPath = _GRAD_TEXTURES[style] or _GRAD_TEXTURES.FULL
    if dov._msufDOStylePath ~= texPath then
        dov:SetStatusBarTexture(texPath)
        dov._msufDOStylePath = texPath
    end
    local tex = dov:GetStatusBarTexture()

    -- Fill value: mirror current health ("current health only") or full bar.
    local unit = f.unit
    if c.doOnHP and unit then
        local hm = f._msufGFCachedHpMax or UnitHealthMax(unit)
        dov:SetMinMaxValues(0, hm)
        dov:SetValue(UnitHealth(unit))
        dov._msufDOSyncHP = true
        dov._msufDOFullValue = nil
    else
        if dov._msufDOFullValue ~= true then
            dov:SetMinMaxValues(0, 1)
            dov:SetValue(1)
            dov._msufDOFullValue = true
        end
        dov._msufDOSyncHP = nil
    end

    -- Resolve and apply tint (secret-safe path).
    local colorObj, r, g, b = ResolveDispelColorObj(f, dispelType, true)
    if tex then
        local rr, gg, bb, aa = ExtractColorRGBA(colorObj)
        rr, gg, bb, aa = rr or r or 0.25, gg or g or 0.75, bb or b or 1.00, aa or 1
        local secretColor = issecretvalue and (issecretvalue(rr) or issecretvalue(gg) or issecretvalue(bb) or issecretvalue(aa))
        if secretColor
            or dov._msufDOR ~= rr
            or dov._msufDOG ~= gg
            or dov._msufDOB ~= bb
            or dov._msufDOA ~= aa
        then
            tex:SetVertexColor(rr, gg, bb, aa)
            if not secretColor then
                dov._msufDOR, dov._msufDOG, dov._msufDOB, dov._msufDOA = rr, gg, bb, aa
            else
                dov._msufDOR, dov._msufDOG, dov._msufDOB, dov._msufDOA = nil, nil, nil, nil
            end
        end
    end
    -- User's alpha slider lives on the StatusBar frame, independent of tint.
    local userAlpha = c.doAlpha or 1
    if dov._msufDOAlphaCache ~= userAlpha then
        dov:SetAlpha(userAlpha)
        dov._msufDOAlphaCache = userAlpha
    end

    -- Reverse fill sync (match health bar direction)
    if dov.SetReverseFill then
        local reverse = c.reverseFill and true or false
        if dov._msufDOReverse ~= reverse then
            dov:SetReverseFill(reverse)
            dov._msufDOReverse = reverse
        end
    end

    if not dov:IsShown() then dov:Show() end
end

------------------------------------------------------------------------
-- Debuff stripe (thin edge indicator for a configured debuff match).
-- Independent from dispel overlay Ã¢â‚¬â€ honors the Debuffs filter/list and
-- still works for non-dispellable debuffs when that filter allows them.
------------------------------------------------------------------------
_GF_ApplyDebuffStripe = function(f)
    local stripe = f._msufGFDebuffStripe
    if not stripe then return end
    local c = f._c
    if not c then return end

    if not c.dsEn or not f._msufGFHasAnyDebuff then
        if stripe:IsShown() then stripe:Hide() end
        return
    end

    -- Anchor based on edge setting
    local edge = c.dsEdge
    local h = math_max(1, c.dsH or 3)
    if stripe._msufDSEdge ~= edge or stripe._msufDSH ~= h then
        stripe._msufDSEdge = edge
        stripe._msufDSH = h
        stripe:ClearAllPoints()
        stripe:SetHeight(h)
        local anchor = f.health or f
        if edge == "TOP" then
            stripe:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
            stripe:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
        else -- BOTTOM (default)
            stripe:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
            stripe:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
        end
    end
    if GF.SyncFrameLayerAbove and f.health then
        GF.SyncFrameLayerAbove(stripe, f.health, GF.LAYER_DEBUFF_STRIPE or 7)
    elseif stripe.SetFrameLevel and f.health and f.health.GetFrameLevel then
        stripe:SetFrameLevel(f.health:GetFrameLevel() + 7)
    end

    -- Color + alpha (diff-gated)
    local r, g, b, a = c.dsR, c.dsG, c.dsB, c.dsAlpha
    if stripe._msufDSR ~= r or stripe._msufDSG ~= g or stripe._msufDSB ~= b or stripe._msufDSA ~= a then
        stripe._msufDSR, stripe._msufDSG, stripe._msufDSB, stripe._msufDSA = r, g, b, a
        stripe:SetStatusBarColor(r, g, b, a)
    end

    -- Fill full width
    stripe:SetMinMaxValues(0, 1)
    stripe:SetValue(1)

    if not stripe:IsShown() then stripe:Show() end
end

_GF_RefreshBorder = function(f, unit)
    -- NOTE: Dispel overlay is fully decoupled from border highlight.
    -- Overlay lives in _GF_ApplyDispelOverlay and is called separately
    -- from dispel-change sites only Ã¢â‚¬â€ never from aggro/target/test paths.

    if not GFEnsureHighlightBorder(f, "dispel") then return end
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
    if not c then return end

    -- Resolve active states
    local kind = f._msufGFKind or "party"
    GFPrimePriorityTypeLayers(f, kind, c)
    local dispelType = f._msufGFDispelType
    local testMode = _GF_DispelBorderTestApplies(f, kind)
    local hasDispel  = dispelType and (c.dispelEn or testMode)
    local aggroLevel = f._msufGFAggroLevel
    local hasAggro   = aggroLevel and aggroLevel >= 1 and c.aggroEn
    local hasTarget  = f._msufGFIsTarget and c.targetEn
    local hasFocus   = f._msufGFIsFocus and c.focusEn

    -- Shared geometry for dispel/aggro/purge (all use Aggro size keys)
    local sz  = c.aggroSize or 2
    local ofs = c.aggroOfs or 0
    local tex = c.aggroTex
    local lay = c.aggroLayer or "DEFAULT"
    local fScale = c.frameScale or 1
    if fScale ~= 1 and GF.ScaleValue then
        sz = GF.ScaleValue(sz, fScale, 1)
        ofs = GF.ScaleValue(ofs, fScale)
    end

    -- Custom priority maps to strata/frame level; all active highlight lanes
    -- render on their own frames and compositing decides which one is on top.
    -- Maps "dispel"/"magic"/"curse"/etc Ã¢â€ â€™ dispel, "aggro" Ã¢â€ â€™ aggro.
    local active = {}
    local topBorder, topOffset, topPrio

    local function applyLayer(layerKind, prio, size, offset, texture, layer, r, g, b, layerDispelType)
        local frameKey = GFHighlightFrameKey(kind, c, layerKind, layerDispelType)
        local border = GFEnsureHighlightBorder(f, frameKey)
        if not border then return end
        local layerOffset = GFHighlightLayerOffset(kind, c, layerKind, layerDispelType)
        border._msufHLLayerOffset = layerOffset
        border._msufGFHLLogicalKey = layerKind
        _applyHighlightBorderStyle(border, nil, size, offset, texture, layer, r, g, b, 1)
        border._msufHLActivePrio = prio
        if not border:IsShown() then border:Show() end
        active[frameKey] = true
        if layerKind == "dispel" then
            f._msufGFDispelHighlightBorder = border
        end
        if not topBorder or layerOffset > topOffset or (layerOffset == topOffset and prio < topPrio) then
            topBorder, topOffset, topPrio = border, layerOffset, prio
        end
    end

    local dispelR, dispelG, dispelB
    if hasDispel then
        dispelR, dispelG, dispelB = ResolveDispelColor(dispelType, f)
        if dispelR then
            applyLayer("dispel", 1, sz, ofs, tex, lay, dispelR, dispelG, dispelB, dispelType)
        end
    end
    if hasAggro then
        applyLayer("aggro", 2, sz, ofs, tex, lay,
            c.aggroR or 1, c.aggroG or 0.55, c.aggroB or 0)
    end
    if hasTarget then
        applyLayer("target", 3,
            c.tgtSize or 2,
            c.tgtOfs or 0,
            c.tgtTex,
            c.tgtLayer or "DEFAULT",
            c.tgtR or 1,
            c.tgtG or 1,
            c.tgtB or 1)
    end
    if hasFocus then
        applyLayer("focus", 4,
            c.focSize or 2,
            c.focOfs or 0,
            c.focTex,
            c.focLayer or "DEFAULT",
            c.focR or 0.5,
            c.focG or 0.5,
            c.focB or 1.0)
    end

    local borders = f._msufGFHighlightBorders
    if borders then
        for layerKind, border in pairs(borders) do
            if border and not active[layerKind] then
                border._msufHLActivePrio = nil
                if border:IsShown() then border:Hide() end
            end
        end
    end

    local fallbackBorder = (borders and borders.dispel) or f._msufGFDispelHighlightBorder or f._msufGFHighlightBorder
    f._msufGFHighlightBorder = topBorder or fallbackBorder
    _NotifyRoundedGFHighlight(f._msufGFHighlightBorder)

    if _G.MSUF_RoundedUF_Active == true and borders then
        for _, border in pairs(borders) do
            if border and border:IsShown() then border:Hide() end
        end
    end

    if dispelR then
        _GF_StartDispelGlow(f, dispelR, dispelG, dispelB)
    else
        _GF_StopDispelGlow(f)
    end
end

_GF_ClearNativeSuppressedDispel = function(f, unit)
    if not f then return end
    f._msufGFDispelFindCache = nil
    local hadDispel = f._msufGFDispelType or f._msufGFMergedDispel or f._msufGFDispelAuraID
        or f._msufGFPrevDispelAuraID or f._msufGFDispelGlowActive
        or f._msufGFDispelOverlayType or f._msufGFMergedDispelOverlay or f._msufGFDispelOverlayAuraID
    local border = f._msufGFDispelHighlightBorder or (f._msufGFHighlightBorders and f._msufGFHighlightBorders.dispel) or f._msufGFHighlightBorder
    if border and border._msufHLActivePrio == 1 then hadDispel = true end

    f._msufGFMergedDispel = nil
    f._msufGFDispelType = nil
    f._msufGFDispelAuraID = nil
    f._msufGFPrevDispelAuraID = nil
    f._msufGFDispelColorObj = nil
    f._msufGFDispelColorRev = nil
    f._msufGFColorStyleRevision = nil
    f._msufGFMergedDispelOverlay = nil
    f._msufGFDispelOverlayType = nil
    f._msufGFDispelOverlayAuraID = nil
    f._msufGFPrevDispelOverlayAuraID = nil
    f._msufGFDispelOverlayColorObj = nil
    f._msufGFDispelOverlayColorRev = nil
    f._msufGFDispelVisualSerial = nil
    f._msufGFAuraVisualSerial = nil

    local overlays = f._msufGFDispelOverlays
    if overlays then
        for _, dov in pairs(overlays) do
            if dov then
                if dov:IsShown() then hadDispel = true end
                if dov.Hide then dov:Hide() end
                dov._msufDOSyncHP = nil
            end
        end
    else
        local dov = f._msufGFDispelOverlay
        if dov then
            if dov:IsShown() then hadDispel = true; dov:Hide() end
            dov._msufDOSyncHP = nil
        end
    end
    if GF.ApplyPrivateAuraContainerOverlay then
        GF.ApplyPrivateAuraContainerOverlay(f, unit or f.unit, { containerOverlay = { enabled = false } })
    elseif f._gfPrivOverlayFrame and f._gfPrivOverlayFrame:IsShown() then
        f._gfPrivOverlayFrame:Hide()
    end
    _GF_StopDispelGlow(f)
    if hadDispel and _GF_RefreshBorder then _GF_RefreshBorder(f, unit) end
end

-- Dispel border (zero-alloc direct C_UnitAuras slot scan)
-- Replaces AuraUtil.ForEachAura which allocates a table internally
-- every call ({C_UnitAuras.GetAuraSlots(...)}).
-- Module-level vararg scanner: zero closure, zero table per call.
------------------------------------------------------------------------
local _dispelScanUnit  -- module-level state for vararg scanner
local _gfDispelScanSlots = {}
local C_UnitAuras_GetAuraSlots    = C_UnitAuras and C_UnitAuras.GetAuraSlots
local C_UnitAuras_GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local C_UnitAuras_GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local C_UnitAuras_IsAuraFilteredOut = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local _DISPEL_SCAN_FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"
local _debuffStripeScanUnit
GF._DispelFallbackCallback = GF._DispelFallbackCallback or function(auraData)
    GF._dispelFallbackFoundDispel, GF._dispelFallbackFoundAid = GF.ReadDispelBorderAura(auraData, GF._dispelFallbackTriggerMode, GF._dispelFallbackUnit)
    return GF._dispelFallbackFoundDispel ~= nil
end

local function _DebuffStripeScanSlots(_, ...)
    local scanUnit = _debuffStripeScanUnit
    for i = 1, select("#", ...) do
        local slot = select(i, ...)
        local aura = scanUnit and C_UnitAuras_GetAuraDataBySlot and C_UnitAuras_GetAuraDataBySlot(scanUnit, slot)
        if _dsPresenceCallback(aura) then
            return true
        end
    end
    return false
end

_FrameHasStripeDebuff = function(f, unit)
    if not unit or not UnitExists(unit) then return false end

    local kind = (f and f._msufGFKind) or "party"
    local conf = GF.GetConf(kind)
    local debCfg = conf and conf.auras and conf.auras.debuff or nil
    local af = GF.AuraFilter or _G.MSUF_GF_AuraFilter
    local filter = af and af.ResolveDebuffFilter(debCfg and debCfg.filterToken) or "HARMFUL"

    _dsPresenceResult = false
    _dsPresenceAF = af
    _dsPresenceBLHash = (debCfg and af and af.BuildBlacklistHash(debCfg)) or nil

    if C_UnitAuras_GetAuraDataByIndex then
        local index = 1
        while true do
            local aura = C_UnitAuras_GetAuraDataByIndex(unit, index, filter)
            if not aura then break end
            if _dsPresenceCallback(aura) then break end
            index = index + 1
        end
    elseif C_UnitAuras_GetAuraSlots and C_UnitAuras_GetAuraDataBySlot then
        _debuffStripeScanUnit = unit
        _DebuffStripeScanSlots(C_UnitAuras_GetAuraSlots(unit, filter))
        _debuffStripeScanUnit = nil
    elseif AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura(unit, filter, nil, _dsPresenceCallback, true)
    end

    _dsPresenceAF = nil
    _dsPresenceBLHash = nil
    return _dsPresenceResult
end

local function _DispelScanSlots(cont, ...)
    local GetData = C_UnitAuras_GetAuraDataBySlot
    local u = _dispelScanUnit
    local iss = issecretvalue
    -- C-side: use RAID_PLAYER_DISPELLABLE filter directly
    -- If we got slots from that filter, the first slot IS dispellable
    for i = 1, select("#", ...) do
        local slot = select(i, ...)
        local data = GetData(u, slot)
        if data and data.auraInstanceID then
            local dn = data.dispelName
            if not (iss and iss(dn)) and type(dn) == "string" and dn ~= "" and dn ~= "None" then
                return dn, data.auraInstanceID
            end
            return "DISPELLABLE", data.auraInstanceID
        end
    end
    return nil, nil
end

local _GF_ReadDispelBorderAuraFallback = GF.ReadDispelBorderAura
GF.ReadDispelBorderAura = function(aura, triggerMode, unit, resolveType)
    if not unit and not resolveType and type(_GF_ReadDispelBorderAuraFallback) == "function" then
        return _GF_ReadDispelBorderAuraFallback(aura, triggerMode)
    end
    if not (aura and aura.auraInstanceID) then return nil, nil end
    triggerMode = GF.NormalizeDispelBorderTrigger(triggerMode)
    if triggerMode ~= "BY_ME" then
        local harmful = aura.isHarmful
        if issecretvalue and issecretvalue(harmful) then
            -- Continue through the dispelName path for secret-tagged aura data.
        elseif harmful == false then
            return nil, nil
        end
    end

    local resolvedType = resolveType and GFResolveAuraDispelPriorityType(unit, aura) or nil
    if resolvedType then
        return resolvedType, aura.auraInstanceID
    end

    local dn = aura.dispelName
    local secret = issecretvalue and issecretvalue(dn)
    if secret then
        if triggerMode == "DISPEL_TYPE" then
            return "DISPELLABLE", aura.auraInstanceID
        end
    elseif type(dn) == "string" and dn ~= "" and dn ~= "None" then
        if dn == "DISPELLABLE" then
            return "DISPELLABLE", aura.auraInstanceID
        end
        return dn, aura.auraInstanceID
    elseif triggerMode == "DISPEL_TYPE" then
        return nil, nil
    end

    if triggerMode == "ANY_DEBUFF" then
        return "DISPELLABLE", aura.auraInstanceID
    end
    return nil, nil
end

local _GF_FindDispelBorderAuraFallback = GF.FindDispelBorderAura
GF.FindDispelBorderAura = function(unit, triggerMode, kind, c, useOverlayPriority)
    if not kind and not c and type(_GF_FindDispelBorderAuraFallback) == "function" then
        return _GF_FindDispelBorderAuraFallback(unit, triggerMode)
    end
    triggerMode = GF.NormalizeDispelBorderTrigger(triggerMode)
    kind = kind or "party"
    if triggerMode == "BY_ME" and GFDispelScanCustomTypePriorityEnabled(kind, c, useOverlayPriority) then
        local typedDispel, typedAid = GF.FindDispelBorderAura(unit, "DISPEL_TYPE", kind, c, useOverlayPriority)
        if typedDispel then return typedDispel, typedAid end
    end
    local filter = (triggerMode == "ANY_DEBUFF" or triggerMode == "DISPEL_TYPE") and "HARMFUL" or _DISPEL_SCAN_FILTER
    local forceTypeRank = triggerMode == "DISPEL_TYPE" or triggerMode == "ANY_DEBUFF"
    local ranked = GFDispelCachedPriorityEnabled(kind, c, useOverlayPriority) or forceTypeRank
    local resolveType = GFDispelCachedResolveType(kind, c, triggerMode, useOverlayPriority)
    local bestDispel, bestAid, bestRank = nil, nil, 1000

    if C_UnitAuras_GetAuraSlots and C_UnitAuras_GetAuraDataBySlot then
        local cont = nil
        repeat
            _gfDispelScanSlots[1], _gfDispelScanSlots[2], _gfDispelScanSlots[3], _gfDispelScanSlots[4], _gfDispelScanSlots[5],
            _gfDispelScanSlots[6], _gfDispelScanSlots[7], _gfDispelScanSlots[8], _gfDispelScanSlots[9], _gfDispelScanSlots[10],
            _gfDispelScanSlots[11], _gfDispelScanSlots[12], _gfDispelScanSlots[13], _gfDispelScanSlots[14], _gfDispelScanSlots[15],
            _gfDispelScanSlots[16], _gfDispelScanSlots[17], _gfDispelScanSlots[18], _gfDispelScanSlots[19], _gfDispelScanSlots[20],
            _gfDispelScanSlots[21], _gfDispelScanSlots[22], _gfDispelScanSlots[23], _gfDispelScanSlots[24], _gfDispelScanSlots[25],
            _gfDispelScanSlots[26], _gfDispelScanSlots[27], _gfDispelScanSlots[28], _gfDispelScanSlots[29], _gfDispelScanSlots[30],
            _gfDispelScanSlots[31], _gfDispelScanSlots[32], _gfDispelScanSlots[33], _gfDispelScanSlots[34], _gfDispelScanSlots[35],
            _gfDispelScanSlots[36], _gfDispelScanSlots[37], _gfDispelScanSlots[38], _gfDispelScanSlots[39], _gfDispelScanSlots[40],
            _gfDispelScanSlots[41] = C_UnitAuras_GetAuraSlots(unit, filter, 40, cont)
            cont = _gfDispelScanSlots[1]
            for i = 2, 41 do
                local slot = _gfDispelScanSlots[i]
                if not slot then break end
                local aura = C_UnitAuras_GetAuraDataBySlot(unit, slot)
                local dispel, aid = GF.ReadDispelBorderAura(aura, triggerMode, unit, resolveType)
                if triggerMode == "BY_ME" and aura and aura.auraInstanceID then
                    dispel, aid = dispel or "DISPELLABLE", aura.auraInstanceID
                end
                if dispel then
                    if not ranked then return dispel, aid end
                    local rank = GFDispelTypePriorityRank(kind, c, dispel, useOverlayPriority, forceTypeRank)
                    if rank < bestRank then
                        bestDispel, bestAid, bestRank = dispel, aid, rank
                        if rank <= 1 then return bestDispel, bestAid end
                    end
                end
                if triggerMode == "BY_ME" and not ranked then return bestDispel, bestAid end
            end
        until not cont
        return bestDispel, bestAid
    end

    if AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura(unit, filter == "HARMFUL" and "HARMFUL" or "HARMFUL|RAID", nil, function(aura)
            local dispel, aid = GF.ReadDispelBorderAura(aura, triggerMode, unit, resolveType)
            if triggerMode == "BY_ME" and aura and aura.auraInstanceID then
                dispel, aid = dispel or "DISPELLABLE", aura.auraInstanceID
            end
            if not dispel then return false end
            if not ranked then
                bestDispel, bestAid = dispel, aid
                return true
            end
            local rank = GFDispelTypePriorityRank(kind, c, dispel, useOverlayPriority, forceTypeRank)
            if rank < bestRank then
                bestDispel, bestAid, bestRank = dispel, aid, rank
                if rank <= 1 then return true end
            end
            return false
        end, true)
        return bestDispel, bestAid
    end

    return nil, nil
end

function GF._UpdateDispel(f, unit)
    if f then f._msufGFDispelFindCache = nil end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf and GF.GetConf(kind)
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
    local triggerMode = GF.NormalizeDispelBorderTrigger(c and c.dispelBorderTrigger or HLVal(kind, "dispelBorderTrigger"))
    local overlayTrigger = c and GF.ResolveDispelOverlayTrigger and GF.ResolveDispelOverlayTrigger(c) or triggerMode

    local testMode = _GF_DispelBorderTestApplies(f, kind)

    local auras = conf and conf.auras
    if not testMode and (not auras or auras.enabled == false) then
        f._msufGFDispelKnown = true
        if _GF_ClearNativeSuppressedDispel then
            _GF_ClearNativeSuppressedDispel(f, unit)
        else
            f._msufGFMergedDispel = nil
            f._msufGFDispelType = nil
            f._msufGFDispelAuraID = nil
            f._msufGFPrevDispelAuraID = nil
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
            f._msufGFColorStyleRevision = nil
            f._msufGFMergedDispelOverlay = nil
            f._msufGFDispelOverlayType = nil
            f._msufGFDispelOverlayAuraID = nil
            f._msufGFPrevDispelOverlayAuraID = nil
            f._msufGFDispelOverlayColorObj = nil
            f._msufGFDispelOverlayColorRev = nil
        end
        return
    end

    local suppressBlizzardCustom
    if c then
        suppressBlizzardCustom = c.nativeBlizzardDispelsSuppressCustom == true
    else
        local nativeDispels = _GF_IsBlizzardDispelRendererActive(conf)
        local confAuras = conf and conf.auras
        suppressBlizzardCustom = nativeDispels and not (confAuras and confAuras.blizzardDispelBorder == true)
    end
    if not testMode and suppressBlizzardCustom and not (c and GF.DispelScanActive(c)) then
        if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
        f._msufGFDispelKnown = true
        return
    end

    local triggerBlocked = GF.DispelBorderTriggerNeedsPlayerDispel(triggerMode)
        and not GF._playerCanDispel
        and not GFDispelScanCustomTypePriorityEnabled(kind, c, false)
    local scanConsumerActive
    if c then
        scanConsumerActive = c.dispelBorderScanActive == true or c.dispelOverlayScanActive == true
    else
        scanConsumerActive = GF.DispelScanActive(c) and not triggerBlocked
    end
    if ((not GF.DispelScanActive(c)) or not scanConsumerActive or not unit)
        and not testMode
    then
        f._msufGFDispelKnown = true
        if f._msufGFDispelType or f._msufGFDispelOverlayType then
            f._msufGFDispelType = nil
            f._msufGFDispelAuraID = nil
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
            f._msufGFMergedDispelOverlay = nil
            f._msufGFDispelOverlayType = nil
            f._msufGFDispelOverlayAuraID = nil
            f._msufGFPrevDispelOverlayAuraID = nil
            f._msufGFDispelOverlayColorObj = nil
            f._msufGFDispelOverlayColorRev = nil
            _GF_RefreshBorder(f, unit)
            _GF_ApplyDispelOverlay(f)
        end
        return
    end

    local topDispel = nil
    local topAid = nil
    local overlayDispel = nil
    local overlayAid = nil
    f._msufGFDispelColorObj = nil
    f._msufGFDispelColorRev = nil
    f._msufGFDispelOverlayColorObj = nil
    f._msufGFDispelOverlayColorRev = nil
    if not testMode then
        if not UnitExists(unit) then
            f._msufGFDispelKnown = true
            if f._msufGFDispelType or f._msufGFDispelOverlayType then
                f._msufGFDispelType = nil
                f._msufGFDispelAuraID = nil
                f._msufGFDispelColorObj = nil
                f._msufGFDispelColorRev = nil
                f._msufGFMergedDispelOverlay = nil
                f._msufGFDispelOverlayType = nil
                f._msufGFDispelOverlayAuraID = nil
                f._msufGFPrevDispelOverlayAuraID = nil
                f._msufGFDispelOverlayColorObj = nil
                f._msufGFDispelOverlayColorRev = nil
                _GF_RefreshBorder(f, unit)
                _GF_ApplyDispelOverlay(f)
            end
            return
        end
        local borderNeedsScan = true
        if c and c.dispelBorderScanActive ~= nil then
            borderNeedsScan = c.dispelBorderScanActive == true
        end
        local overlayNeedsScan = c and c.dispelOverlayScanActive == true
        local canShareScan = borderNeedsScan and overlayNeedsScan
            and triggerMode == overlayTrigger
            and GFDispelScanPrioritySignature(kind, c, false) == GFDispelScanPrioritySignature(kind, c, true)
            and GFDispelCachedResolveType(kind, c, triggerMode, false) == GFDispelCachedResolveType(kind, c, overlayTrigger, true)
        if canShareScan then
            local sharedDispel, sharedAid, color
            if GF._FindFrameDispelAuraWithColor then
                sharedDispel, sharedAid, color = GF._FindFrameDispelAuraWithColor(f, unit, triggerMode, false)
            else
                sharedDispel, sharedAid = GF.FindDispelBorderAura(unit, triggerMode, kind, c, false)
                if sharedAid and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and GF and GF._sharedDispelColorCurve then
                    color = C_UnitAuras.GetAuraDispelTypeColor(unit, sharedAid, GF._sharedDispelColorCurve)
                end
            end
            topDispel, topAid = sharedDispel, sharedAid
            overlayDispel, overlayAid = sharedDispel, sharedAid
            f._msufGFDispelColorObj = color
            f._msufGFDispelColorRev = color and (_G.MSUF_ColorStyleRevision or 0) or nil
            f._msufGFDispelOverlayColorObj = color
            f._msufGFDispelOverlayColorRev = color and (_G.MSUF_ColorStyleRevision or 0) or nil
        else
            if borderNeedsScan then
                local color
                if GF._FindFrameDispelAuraWithColor then
                    topDispel, topAid, color = GF._FindFrameDispelAuraWithColor(f, unit, triggerMode, false)
                else
                    topDispel, topAid = GF.FindDispelBorderAura(unit, triggerMode, kind, c, false)
                    if topAid and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and GF and GF._sharedDispelColorCurve then
                        color = C_UnitAuras.GetAuraDispelTypeColor(unit, topAid, GF._sharedDispelColorCurve)
                    end
                end
                f._msufGFDispelColorObj = color
                f._msufGFDispelColorRev = color and (_G.MSUF_ColorStyleRevision or 0) or nil
            end
            if overlayNeedsScan then
                local color
                if GF._FindFrameDispelAuraWithColor then
                    overlayDispel, overlayAid, color = GF._FindFrameDispelAuraWithColor(f, unit, overlayTrigger, true)
                else
                    overlayDispel, overlayAid = GF.FindDispelBorderAura(unit, overlayTrigger, kind, c, true)
                    if overlayAid and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and GF and GF._sharedDispelColorCurve then
                        color = C_UnitAuras.GetAuraDispelTypeColor(unit, overlayAid, GF._sharedDispelColorCurve)
                    end
                end
                f._msufGFDispelOverlayColorObj = color
                f._msufGFDispelOverlayColorRev = color and (_G.MSUF_ColorStyleRevision or 0) or nil
            end
        end
    else
        topDispel = _G.MSUF_DispelBorderTestType or "Magic"
        overlayDispel = f._msufGFDispelOverlayType
        overlayAid = f._msufGFDispelOverlayAuraID
        f._msufGFDispelColorObj = nil
        f._msufGFDispelColorRev = nil
    end

    local prevDispel = f._msufGFDispelType
    local prevAid = f._msufGFPrevDispelAuraID
    local prevOverlay = f._msufGFDispelOverlayType
    local prevOverlayAid = f._msufGFPrevDispelOverlayAuraID
    local colorRev = _G.MSUF_ColorStyleRevision or 0
    local prevColorRev = f._msufGFColorStyleRevision or 0
    local settingsSerial = (c and c._cacheSerial) or 0
    local prevSettingsSerial = f._msufGFDispelVisualSerial or 0
    local settingsChanged = settingsSerial ~= prevSettingsSerial
    f._msufGFDispelKnown = true
    f._msufGFDispelType = topDispel
    f._msufGFDispelAuraID = topAid
    f._msufGFPrevDispelAuraID = topAid
    f._msufGFDispelOverlayType = overlayDispel
    f._msufGFDispelOverlayAuraID = overlayAid
    f._msufGFPrevDispelOverlayAuraID = overlayAid

    if topDispel == prevDispel and topAid == prevAid
        and overlayDispel == prevOverlay and overlayAid == prevOverlayAid
        and colorRev == prevColorRev and not settingsChanged and not testMode then return end

    f._msufGFColorStyleRevision = colorRev
    f._msufGFDispelVisualSerial = settingsSerial
    if topDispel ~= prevDispel or topAid ~= prevAid or colorRev ~= prevColorRev or settingsChanged or testMode then
        _GF_RefreshBorder(f, unit)
    end
    -- Overlay only for real dispels Ã¢â‚¬â€ border test mode is border-only
    if not testMode then
        _GF_ApplyDispelOverlay(f)
    end
end

function GF._UpdateDispelFromAuraDelta(f, unit, updateInfo)
    if not (f and unit) then return false, false end
    f._msufGFDispelFindCache = nil

    local prevDispel = f._msufGFDispelType
    local prevAid = f._msufGFDispelAuraID
    local prevColorRev = f._msufGFColorStyleRevision or 0
    local prevOverlay = f._msufGFDispelOverlayType
    local prevOverlayAid = f._msufGFDispelOverlayAuraID

    local function finishFull()
        GF._UpdateDispel(f, unit)
        return f._msufGFDispelType ~= prevDispel
            or f._msufGFDispelAuraID ~= prevAid
            or f._msufGFDispelOverlayType ~= prevOverlay
            or f._msufGFDispelOverlayAuraID ~= prevOverlayAid
            or (f._msufGFColorStyleRevision or 0) ~= prevColorRev, true
    end

    if not updateInfo or updateInfo.isFullUpdate then
        return finishFull()
    end

    local c = f._c
    local kind = f._msufGFKind or "party"
    local triggerMode = GF.NormalizeDispelBorderTrigger(c and c.dispelBorderTrigger or HLVal(kind, "dispelBorderTrigger"))
    local borderScanActive = not c or c.dispelBorderScanActive ~= false
    local overlayScanActive = c and c.dispelOverlayScanActive == true
    local overlayTrigger = overlayScanActive and GF.ResolveDispelOverlayTrigger and GF.ResolveDispelOverlayTrigger(c) or triggerMode
    local borderPriorityScan = GFDispelScanPriorityEnabled(kind, c, false)
    local overlayPriorityScan = GFDispelScanPriorityEnabled(kind, c, true)
    local borderCustomTypePriority = triggerMode == "BY_ME" and GFDispelScanCustomTypePriorityEnabled(kind, c, false)
    local overlayCustomTypePriority = overlayTrigger == "BY_ME" and GFDispelScanCustomTypePriorityEnabled(kind, c, true)
    local resolveType = GFDispelScanResolveType(kind, c, triggerMode, false)
    local overlayResolveType = GFDispelScanResolveType(kind, c, overlayTrigger, true)
    local borderWinnerScan = borderPriorityScan or borderCustomTypePriority
    local overlayWinnerScan = overlayPriorityScan or overlayCustomTypePriority

    local function addedAuraMatchesTrigger(aura, trigger, resolve, customTypePriority)
        local aid = aura and aura.auraInstanceID
        if not aid then return false, nil end
        if customTypePriority then
            local typedDispel = GF.ReadDispelBorderAura(aura, "DISPEL_TYPE", unit, true)
            if typedDispel then return true, typedDispel end
            if trigger == "BY_ME" and C_UnitAuras_IsAuraFilteredOut then
                return C_UnitAuras_IsAuraFilteredOut(unit, aid, _DISPEL_SCAN_FILTER) == false, nil
            end
        elseif trigger == "BY_ME" and C_UnitAuras_IsAuraFilteredOut then
            return C_UnitAuras_IsAuraFilteredOut(unit, aid, _DISPEL_SCAN_FILTER) == false, nil
        end
        local triggerDispel = GF.ReadDispelBorderAura(aura, trigger, unit, resolve)
        return triggerDispel ~= nil, triggerDispel
    end

    local trackedAid = f._msufGFDispelAuraID
    local overlayTrackedAid = f._msufGFDispelOverlayAuraID
    local removed = updateInfo.removedAuraInstanceIDs
    if removed and overlayTrackedAid then
        for i = 1, #removed do
            if removed[i] == overlayTrackedAid then
                return finishFull()
            end
        end
    end
    if removed and trackedAid then
        for i = 1, #removed do
            if removed[i] == trackedAid then
                return finishFull()
            end
        end
    end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated and #updated > 0 and ((borderScanActive and borderWinnerScan) or (overlayScanActive and overlayWinnerScan)) then
        return finishFull()
    end
    if updated and overlayTrackedAid then
        for i = 1, #updated do
            if updated[i] == overlayTrackedAid then
                if overlayTrigger ~= "BY_ME" or not C_UnitAuras_IsAuraFilteredOut
                    or C_UnitAuras_IsAuraFilteredOut(unit, overlayTrackedAid, _DISPEL_SCAN_FILTER) ~= false
                then
                    return finishFull()
                end
                return false, true
            end
        end
    end
    if updated and trackedAid then
        for i = 1, #updated do
            if updated[i] == trackedAid then
                if triggerMode ~= "BY_ME" or not C_UnitAuras_IsAuraFilteredOut
                    or C_UnitAuras_IsAuraFilteredOut(unit, trackedAid, _DISPEL_SCAN_FILTER) ~= false
                then
                    return finishFull()
                end
                return false, true
            end
        end
    end

    local added = updateInfo.addedAuras
    if overlayScanActive and added and (not overlayTrackedAid or overlayWinnerScan) then
        for i = 1, #added do
            local aura = added[i]
            local dispellable = addedAuraMatchesTrigger(aura, overlayTrigger, overlayResolveType, overlayCustomTypePriority)
            if dispellable then return finishFull() end
        end
    end

    if not borderScanActive then
        return false, overlayScanActive
    end

    if trackedAid and added and borderWinnerScan then
        for i = 1, #added do
            local aura = added[i]
            local dispellable = addedAuraMatchesTrigger(aura, triggerMode, resolveType, borderCustomTypePriority)
            if dispellable then return finishFull() end
        end
    end

    if trackedAid then
        return false, false
    end

    if not added then
        return false, false
    end

    for i = 1, #added do
        local aura = added[i]
        local aid = aura and aura.auraInstanceID
        if aid then
            local dispellable, triggerDispel = addedAuraMatchesTrigger(aura, triggerMode, resolveType, borderCustomTypePriority)
            if dispellable then
                if borderWinnerScan then
                    return finishFull()
                end
                local dn = aura.dispelName
                if triggerDispel then
                    f._msufGFDispelType = triggerDispel
                elseif not (issecretvalue and issecretvalue(dn)) and type(dn) == "string" and dn ~= "" and dn ~= "None" then
                    f._msufGFDispelType = dn
                else
                    f._msufGFDispelType = "DISPELLABLE"
                end
                f._msufGFDispelAuraID = aid
                f._msufGFPrevDispelAuraID = aid
                f._msufGFDispelKnown = true
                if C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and GF and GF._sharedDispelColorCurve then
                    f._msufGFDispelColorObj = C_UnitAuras.GetAuraDispelTypeColor(unit, aid, GF._sharedDispelColorCurve)
                    f._msufGFDispelColorRev = _G.MSUF_ColorStyleRevision or 0
                else
                    f._msufGFDispelColorObj = nil
                    f._msufGFDispelColorRev = nil
                end
                local colorRev = _G.MSUF_ColorStyleRevision or 0
                f._msufGFColorStyleRevision = colorRev
                _GF_RefreshBorder(f, unit)
                _GF_ApplyDispelOverlay(f)
                return true, true
            end
        end
    end

    return false, false
end

------------------------------------------------------------------------

GF.GetDispelColor = GetDispelColor
GF.ResolveDispelColor = ResolveDispelColor
GF.DispelScanPriorityEnabled = GFDispelScanPriorityEnabled
GF.DispelScanCustomTypePriorityEnabled = GFDispelScanCustomTypePriorityEnabled
GF.DispelScanResolveType = GFDispelScanResolveType
GF.DispelScanPrioritySignature = GFDispelScanPrioritySignature
GF.StartDispelGlow = _GF_StartDispelGlow
GF.StopDispelGlow = _GF_StopDispelGlow
GF.ApplyDispelOverlay = _GF_ApplyDispelOverlay
GF.ApplyDebuffStripe = _GF_ApplyDebuffStripe
GF.ClearNativeSuppressedDispel = _GF_ClearNativeSuppressedDispel
GF.RefreshBorder = _GF_RefreshBorder
GF.FrameHasStripeDebuff = _FrameHasStripeDebuff
GF.DispatchAura = dispatchAura
GF.FlushDirtyAuras = _gfFlushDirtyAuras
GF.UpdateDispel = GF._UpdateDispel
GF.UpdateDispelFromAuraDelta = GF._UpdateDispelFromAuraDelta
if GF._UnitDispatch then
    GF._UnitDispatch.UNIT_AURA = dispatchAura
end

function GF.RetireAuraEffectsState(f)
    if not f then return end
    if _GF_ClearNativeSuppressedDispel then
        _GF_ClearNativeSuppressedDispel(f, f.unit)
    else
        _GF_StopDispelGlow(f)
    end
    f._msufGFHasAnyDebuff = nil
    if f._msufGFDebuffStripe and f._msufGFDebuffStripe.Hide then
        f._msufGFDebuffStripe:Hide()
    end
    f._msufGFDispelFindCache = nil
    _gfAuraDirtyQueued[f] = nil
    f._msufGFAuraDirty = nil
    f._msufGFFullPending = nil
end

_G.MSUF_GF_UpdateDispel = GF._UpdateDispel
_G.MSUF_GF_StopDispelGlow = _GF_StopDispelGlow
_G.MSUF_GF_RefreshDispelOverlay = function()
    if not GF.frames then return end
    local each = GF.ForEachLiveGroupFrame
    if type(each) ~= "function" then return end
    each(function(f)
        if GF.BuildFrameCache then GF.BuildFrameCache(f) end
        local c = f and f._c
        if f and f.unit and c and GF.DispelScanActive and GF.DispelScanActive(c) and GF._UpdateDispel then
            GF._UpdateDispel(f, f.unit)
        else
            _GF_ApplyDispelOverlay(f)
        end
    end)
end
_G.MSUF_GF_ApplyDispelOverlay = _GF_ApplyDispelOverlay
_G.MSUF_GF_RefreshDebuffStripe = function()
    if not GF.frames then return end
    local each = GF.ForEachLiveGroupFrame
    if type(each) ~= "function" then return end
    each(function(f)
        if GF.BuildFrameCache then GF.BuildFrameCache(f) end
        _GF_ApplyDebuffStripe(f)
    end)
end
_G.MSUF_GF_ApplyDebuffStripe = _GF_ApplyDebuffStripe
_G.MSUF_GF_RefreshBorder = _GF_RefreshBorder
_G.MSUF_GF_DispatchAura = dispatchAura
