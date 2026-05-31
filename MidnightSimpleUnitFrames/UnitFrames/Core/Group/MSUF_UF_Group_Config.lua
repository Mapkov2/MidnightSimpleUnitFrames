local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

local tonumber = tonumber
local type = type
local pairs = pairs
local floor = math.floor
local abs = math.abs
local GetNumGroupMembers = _G.GetNumGroupMembers
local GetTime = _G.GetTime
local wipe = _G.wipe or table.wipe

local WHITE = "Interface\\Buttons\\WHITE8x8"
local EMPTY_EVENTS = {}

local function Num(value, fallback)
    value = tonumber(value)
    if value == nil then
        return fallback
    end
    return value
end

local function Bool(value, fallback)
    if value == nil then
        return fallback
    end
    return value == true
end

local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then
        value = fallback or 1
    end
    if value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

local function Layer(value, fallback)
    value = floor((tonumber(value) or fallback or 5) + 0.5)
    if value < 0 then return 0 end
    if value > 30 then return 30 end
    return value
end

local _groupSizeCacheAt, _groupSizeCacheValue = 0, 0
local function CachedGroupSize()
    local now = GetTime and GetTime() or 0
    if now - _groupSizeCacheAt < 1 then return _groupSizeCacheValue end
    _groupSizeCacheAt = now
    _groupSizeCacheValue = GetNumGroupMembers and GetNumGroupMembers() or 0
    return _groupSizeCacheValue
end

function GF.InvalidateGroupSizeCache()
    _groupSizeCacheAt = 0
end

local function DynamicAuraScale(root)
    if not (root and root.dynamicScale == true) then return 1 end
    local n = CachedGroupSize()
    if n <= 15 then return 1 end
    if n <= 25 then return 0.85 end
    return 0.70
end

local function ScaleAuraValue(value, scale, minValue)
    value = tonumber(value) or 0
    if scale ~= 1 then
        value = value * scale
    end
    if value >= 0 then
        value = floor(value + 0.5)
    else
        value = -floor((-value) + 0.5)
    end
    if minValue ~= nil and value < minValue then value = minValue end
    return value
end

local function ResolveTexture(resolver, kind)
    if type(resolver) == "function" then
        local texture = resolver(kind)
        if type(texture) == "string" and texture ~= "" then
            return texture
        end
    end
    return WHITE
end

local function ResolveHighlightRGB()
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local color = general and general.highlightColor
    if type(color) == "table" then
        return Num(color[1], 1), Num(color[2], 1), Num(color[3], 1)
    end
    local key = type(color) == "string" and color:lower() or "white"
    local colors = _G.MSUF_FONT_COLORS
    local c = type(colors) == "table" and (colors[key] or colors.white)
    if type(c) == "table" then
        return Num(c[1], 1), Num(c[2], 1), Num(c[3], 1)
    end
    return 1, 1, 1
end

local function SettingsCache()
    local getter = _G.MSUF_UFCore_GetSettingsCache
    if type(getter) == "function" then
        local cache = getter()
        if type(cache) == "table" then
            return cache
        end
    end
    return nil
end

local function GeneralDB()
    local db = _G.MSUF_DB
    return type(db) == "table" and type(db.general) == "table" and db.general or nil
end

local function NormalizeHealthMode(value)
    if value == "GLOBAL" then
        return nil
    elseif value == "GRADIENT" or value == "gradient" then
        return "gradient"
    elseif value == "CUSTOM" or value == "custom" then
        return "custom"
    elseif value == "DARK" or value == "dark" then
        return "dark"
    elseif value == "UNIFIED" or value == "unified" then
        return "unified"
    elseif value == "CLASS" or value == "class" then
        return "class"
    end
    return nil
end

local function ResolveHealthVisual(conf)
    conf = conf or {}
    local cache = SettingsCache()
    local general = GeneralDB()
    local mode = NormalizeHealthMode(conf.gfBarMode)
    if not mode then
        local globalMode = cache and cache.barMode or general and general.barMode
        if globalMode == "dark" or globalMode == "unified" then
            mode = globalMode
        else
            mode = NormalizeHealthMode(conf.healthColorMode) or "class"
        end
    end

    local out = {
        mode = mode == "custom" and "unified" or mode,
        r = Num(conf.healthCustomR, 0.2),
        g = Num(conf.healthCustomG, 0.8),
        b = Num(conf.healthCustomB, 0.2),
        backgroundMatchHealth = (cache and cache.barBgMatchHPColor == true) or (general and general.barBgMatchHPColor == true) or false,
    }
    if mode == "dark" then
        local gray = Num(general and (general.darkBarGray or general.darkBgBrightness), 0.07)
        out.r = Num(conf.gfDarkR, cache and cache.darkBarR or general and general.darkBarR or gray)
        out.g = Num(conf.gfDarkG, cache and cache.darkBarG or general and general.darkBarG or gray)
        out.b = Num(conf.gfDarkB, cache and cache.darkBarB or general and general.darkBarB or gray)
    elseif mode == "unified" then
        out.r = Num(conf.gfUnifiedR, cache and cache.unifiedBarR or general and general.unifiedBarR or 0.10)
        out.g = Num(conf.gfUnifiedG, cache and cache.unifiedBarG or general and general.unifiedBarG or 0.60)
        out.b = Num(conf.gfUnifiedB, cache and cache.unifiedBarB or general and general.unifiedBarB or 0.90)
    elseif mode == "gradient" or mode == "class" then
        out.r = Num(cache and cache.unifiedBarR or general and general.unifiedBarR, out.r)
        out.g = Num(cache and cache.unifiedBarG or general and general.unifiedBarG, out.g)
        out.b = Num(cache and cache.unifiedBarB or general and general.unifiedBarB, out.b)
    end
    return out
end

local function NormalizeDispelOverlayTrigger(value)
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then
        return "DISPEL_TYPE"
    elseif value == "ANY_DEBUFF" or value == "DEBUFF" then
        return "ANY_DEBUFF"
    elseif value == "BY_ME" or value == "PLAYER" or value == "DISPELLABLE_BY_ME" then
        return "BY_ME"
    end
    return "BORDER"
end

local function NormalizeDispelDetectTrigger(value)
    value = tostring(value or ""):upper()
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then
        return "DISPEL_TYPE"
    elseif value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then
        return "ANY_DEBUFF"
    elseif value == "PLAYER_CAST" or value == "CAST_BY_ME" or value == "MY_DEBUFF" then
        return "PLAYER_CAST"
    end
    return "BY_ME"
end

local function NormalizeDispelOverlayStyle(value)
    if value == "TOP" or value == "BOTTOM" or value == "LEFT" or value == "RIGHT" then
        return value
    end
    return "FULL"
end

local function NormalizeRangeFadeLayerMode(value)
    if value == "health" or value == "hp" or value == "HP" then
        return "health"
    end
    return "frame"
end

local function ResolveNameTextOptions(kind, conf)
    conf = conf or {}
    local text = {}
    local general = GeneralDB()
    if conf.fontOverride == true then
        local mode = conf.nameColorMode or "DEFAULT"
        if mode == "CLASS" then
            text.nameClassColor = true
        elseif mode == "CUSTOM" then
            text.nameColor = {
                r = Num(conf.nameColorR, 1),
                g = Num(conf.nameColorG, 1),
                b = Num(conf.nameColorB, 1),
                a = 1,
            }
        end
    else
        text.nameClassColor = general and general.nameClassColor == true
        text.nameNpcColor = general and general.npcNameRed == true
    end

    local maxChars, noEllipsis, side
    if GF.ResolveNameTruncation then
        maxChars, noEllipsis, side = GF.ResolveNameTruncation(kind)
    else
        maxChars, noEllipsis, side = Num(conf.nameMaxChars, 0), conf.nameNoEllipsis == true, conf.nameClipSide or "RIGHT"
    end
    maxChars = floor((tonumber(maxChars) or 0) + 0.5)
    if maxChars < 0 then maxChars = 0 end
    text.nameShorten = maxChars > 0
    text.nameShortenMax = maxChars
    text.nameShortenSide = side == "LEFT" and "LEFT" or "RIGHT"
    text.nameShortenDots = noEllipsis ~= true
    text.hideNameOnDeadOffline = conf.hideNameOnDeadOffline == true
    return text
end

local function TextSlots(conf)
    if GF.ResolveHealthTextSlots then
        local left, center, right = GF.ResolveHealthTextSlots(conf)
        return left or "NONE", center or "NONE", right or "NONE"
    end
    return conf.textLeft or "NONE", conf.textCenter or "NONE", conf.textRight or "NONE"
end

local function IsPowerTextEnabled(kind, conf)
    if GF.IsPowerTextEnabled then
        return GF.IsPowerTextEnabled(kind, conf)
    end
    return conf.showPowerText == true or conf.showPower == true
end

local function GetRole(unit)
    if GF.GetUnitGroupRole then
        return GF.GetUnitGroupRole(unit)
    end
    local role = UnitGroupRolesAssigned and unit and UnitGroupRolesAssigned(unit) or nil
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        return role
    end
    return "DAMAGER"
end

local function EffectivePowerHeight(kind, unit, role, conf)
    if conf.powerBarEnabled == false then
        return 0
    end
    if GF.GetEffectivePowerHeight then
        return GF.GetEffectivePowerHeight(kind, unit, role, conf)
    end
    return Num(conf.powerHeight, 4)
end

local function AddEvent(list, event)
    if not list then
        list = {}
    end
    list[#list + 1] = event
    return list
end

-- Build event subscription lists conditionally so a disabled indicator
-- registers ZERO events with the framework (and the event-driver never sees
-- the event for that frame at all — true zero combat overhead). Each `if`
-- below gates a feature; disabled features add no entries.
local function CompileStatusRuntimeEvents(leader, assist, readyCheck, summon, phase, raidMarker, raidGroup, statusTextHealth, statusTextFlags, incomingRes)
    local events, unitlessEvents
    if phase then
        events = AddEvent(events, "UNIT_PHASE")
        events = AddEvent(events, "UNIT_OTHER_PARTY_CHANGED")
    end
    if statusTextHealth then
        events = AddEvent(events, "UNIT_HEALTH")
        events = AddEvent(events, "UNIT_CONNECTION")
    end
    if statusTextFlags then
        events = AddEvent(events, "UNIT_FLAGS")
        unitlessEvents = AddEvent(unitlessEvents, "PLAYER_FLAGS_CHANGED")
    end
    if incomingRes then
        events = AddEvent(events, "INCOMING_RESURRECT_CHANGED")
    end
    if raidMarker then
        unitlessEvents = AddEvent(unitlessEvents, "RAID_TARGET_UPDATE")
    end
    if raidGroup or leader or assist then
        unitlessEvents = AddEvent(unitlessEvents, "GROUP_ROSTER_UPDATE")
    end
    if leader or assist then
        unitlessEvents = AddEvent(unitlessEvents, "PARTY_LEADER_CHANGED")
    end
    if readyCheck then
        unitlessEvents = AddEvent(unitlessEvents, "READY_CHECK")
        unitlessEvents = AddEvent(unitlessEvents, "READY_CHECK_CONFIRM")
        unitlessEvents = AddEvent(unitlessEvents, "READY_CHECK_FINISHED")
    end
    if summon then
        unitlessEvents = AddEvent(unitlessEvents, "INCOMING_SUMMON_CHANGED")
    end
    return events or EMPTY_EVENTS, unitlessEvents or EMPTY_EVENTS
end

local function CompileStatus(kind, conf)
    local roleEnabled = conf.roleIcon ~= false
    local raidMarkerEnabled = conf.raidMarker ~= false
    local leaderEnabled = conf.leaderIcon ~= false
    local assistEnabled = conf.assistIcon ~= false
    local readyCheckEnabled = conf.readyCheckIcon ~= false
    local summonEnabled = conf.summonIcon ~= false
    local incomingResEnabled = conf.resurrectIcon ~= false
    local phaseEnabled = conf.phaseIcon ~= false
    local statusHealthTextEnabled = conf.statusText ~= false or conf.statusGhostText ~= false
    local statusFlagTextEnabled = conf.statusAFKText ~= false
    local statusTextEnabled = statusHealthTextEnabled or statusFlagTextEnabled
    local raidGroupEnabled = conf.showGroupNumber == true
    local runtimeEvents, runtimeUnitlessEvents = CompileStatusRuntimeEvents(
        leaderEnabled, assistEnabled, readyCheckEnabled, summonEnabled, phaseEnabled,
        raidMarkerEnabled, raidGroupEnabled, statusHealthTextEnabled, statusFlagTextEnabled, incomingResEnabled
    )
    local runtimeEnabled = roleEnabled or leaderEnabled or assistEnabled
        or readyCheckEnabled or summonEnabled or phaseEnabled
        or raidMarkerEnabled or raidGroupEnabled or statusTextEnabled or incomingResEnabled

    return {
        enabled = roleEnabled or raidMarkerEnabled or leaderEnabled or assistEnabled
            or readyCheckEnabled or summonEnabled or incomingResEnabled
            or phaseEnabled or statusTextEnabled or raidGroupEnabled,
        group = true,
        groupRuntimeEnabled = runtimeEnabled,
        groupRuntimeEvents = runtimeEvents,
        groupRuntimeUnitlessEvents = runtimeUnitlessEvents,
        runtimeLeaderPair = leaderEnabled or assistEnabled,
        runtimeReadyCheck = readyCheckEnabled,
        runtimeSummon = summonEnabled,
        runtimePhase = phaseEnabled,
        runtimeRaidMarker = raidMarkerEnabled,
        runtimeRaidGroup = raidGroupEnabled,
        runtimeStatusText = statusTextEnabled,
        runtimeIncomingRes = incomingResEnabled,
        kind = kind,
        alpha = 1,
        useMidnight = conf.useMidnightIcons == true,
        role = {
            enabled = roleEnabled,
            style = conf.roleIconStyle,
            showTank = conf.roleIconShowTank ~= false,
            showHealer = conf.roleIconShowHealer ~= false,
            showDPS = conf.roleIconShowDPS ~= false,
            size = Num(conf.roleIconSize, 12),
            anchor = conf.roleIconAnchor or "TOPLEFT",
            x = Num(conf.roleIconX, 0),
            y = Num(conf.roleIconY, 0),
            layer = Layer(conf.roleIconLayer, 1),
        },
        raidMarker = {
            enabled = raidMarkerEnabled,
            size = Num(conf.raidMarkerSize, 14),
            anchor = conf.raidMarkerAnchor or "CENTER",
            x = Num(conf.raidMarkerX, 0),
            y = Num(conf.raidMarkerY, 0),
            layer = Layer(conf.raidMarkerLayer, 3),
        },
        leader = {
            enabled = leaderEnabled,
            style = conf.leaderIconStyle,
            size = Num(conf.leaderIconSize, 12),
            anchor = conf.leaderIconAnchor or "TOPRIGHT",
            x = Num(conf.leaderIconX, 0),
            y = Num(conf.leaderIconY, 0),
            layer = Layer(conf.leaderIconLayer, 2),
        },
        assist = {
            enabled = assistEnabled,
            style = conf.assistIconStyle,
            size = Num(conf.assistIconSize, 12),
            anchor = conf.assistIconAnchor or "TOPRIGHT",
            x = Num(conf.assistIconX, 14),
            y = Num(conf.assistIconY, 0),
            layer = Layer(conf.assistIconLayer, 2),
        },
        readyCheck = {
            enabled = readyCheckEnabled,
            size = Num(conf.readyCheckSize, 16),
            anchor = conf.readyCheckAnchor or "CENTER",
            x = Num(conf.readyCheckX, 0),
            y = Num(conf.readyCheckY, 0),
            layer = Layer(conf.readyCheckLayer, 4),
        },
        summon = {
            enabled = summonEnabled,
            size = Num(conf.summonIconSize, 16),
            anchor = conf.summonAnchor or "CENTER",
            x = Num(conf.summonX, 0),
            y = Num(conf.summonY, 0),
            layer = Layer(conf.summonLayer, 4),
        },
        incomingRes = {
            enabled = incomingResEnabled,
            size = Num(conf.resurrectIconSize, 16),
            anchor = conf.resurrectAnchor or "CENTER",
            x = Num(conf.resurrectX, 0),
            y = Num(conf.resurrectY, 0),
            layer = Layer(conf.resurrectLayer, 4),
        },
        phase = {
            enabled = phaseEnabled,
            size = Num(conf.phaseIconSize, 14),
            anchor = conf.phaseAnchor or "TOPLEFT",
            x = Num(conf.phaseX, 0),
            y = Num(conf.phaseY, 0),
            layer = Layer(conf.phaseLayer, 3),
        },
        statusText = {
            enabled = statusTextEnabled,
            size = Num(conf.statusTextSize, 14),
            anchor = conf.statusTextAnchor or "CENTER",
            x = Num(conf.statusOffsetX, 0),
            y = Num(conf.statusOffsetY, 0),
            layer = Layer(conf.statusTextLayer, 7),
            showDead = conf.statusText ~= false,
            showGhost = conf.statusGhostText ~= false,
            showAFK = conf.statusAFKText ~= false,
            showDND = conf.statusAFKText ~= false,
            dead = {
                enabled = conf.statusText ~= false,
                size = Num(conf.statusTextSize, 14),
                anchor = conf.statusTextAnchor or "CENTER",
                x = Num(conf.statusOffsetX, 0),
                y = Num(conf.statusOffsetY, 0),
                layer = Layer(conf.statusTextLayer, 7),
            },
            ghost = {
                enabled = conf.statusGhostText ~= false,
                size = Num(conf.statusGhostTextSize, 14),
                anchor = conf.statusGhostTextAnchor or "CENTER",
                x = Num(conf.statusGhostOffsetX, 0),
                y = Num(conf.statusGhostOffsetY, 0),
                layer = Layer(conf.statusGhostTextLayer, 7),
            },
            afk = {
                enabled = conf.statusAFKText ~= false,
                size = Num(conf.statusAFKTextSize, 14),
                anchor = conf.statusAFKTextAnchor or "CENTER",
                x = Num(conf.statusAFKOffsetX, 0),
                y = Num(conf.statusAFKOffsetY, 0),
                layer = Layer(conf.statusAFKTextLayer, 7),
            },
        },
        raidGroup = {
            enabled = raidGroupEnabled,
            size = Num(conf.groupNumberSize, 10),
            anchor = conf.groupNumberAnchor or "BOTTOMRIGHT",
            x = Num(conf.groupNumberX, -2),
            y = Num(conf.groupNumberY, 2),
            layer = Layer(conf.statusTextLayer, 7),
            style = conf.groupNumberStyle or "PAREN",
        },
    }
end

local function GroupScopeValue(kind, conf, general, key, fallback)
    if conf and conf.hlOverride == true and conf[key] ~= nil then
        return conf[key]
    end
    if general and general[key] ~= nil then
        return general[key]
    end
    return fallback
end

local function NormalizePredictionTestScope(scope)
    scope = tostring(scope or "shared"):lower()
    scope = scope:gsub("%s+", "")
    scope = scope:gsub("%-", "_")
    if scope == "" or scope == "all" or scope == "global" then
        return "shared"
    elseif scope == "gf_party" or scope == "group_party" or scope == "gfparty" then
        return "party"
    elseif scope == "gf_raid" or scope == "gf_mythicraid" or scope == "group_raid" or scope == "gfraid" or scope == "mythic" or scope == "mythicraid" then
        return "raid"
    end
    return scope
end

local function PredictionTestEnabledForKind(kind)
    if _G.MSUF_AbsorbTextureTestMode ~= true then
        return false
    end
    local scope = NormalizePredictionTestScope(_G.MSUF_AbsorbTextureTestScope)
    kind = NormalizePredictionTestScope(kind)
    return scope == "shared" or scope == kind
end

local function CompilePrediction(kind, conf, texture)
    local general = _G.MSUF_DB and _G.MSUF_DB.general or {}
    local absorbMode = Num(GroupScopeValue(kind, conf, general, "absorbTextMode", nil), nil)
    local absorb
    if absorbMode then
        absorb = absorbMode == 2 or absorbMode == 3
    else
        local absorbEnabled = GroupScopeValue(kind, conf, general, "enableAbsorbBar", nil)
        if absorbEnabled == nil and conf and conf.hlOverride == true and conf.absorbEnabled ~= nil then
            absorbEnabled = conf.absorbEnabled
        end
        if absorbEnabled == nil then absorbEnabled = true end
        absorb = absorbEnabled ~= false
    end
    local heal = GF.IsHealPredictionEnabled and GF.IsHealPredictionEnabled(kind, conf) or conf.healPredEnabled == true
    local healAbsorb = absorb == true and GroupScopeValue(kind, conf, general, "healAbsorbEnabled", true) ~= false
    local test = PredictionTestEnabledForKind(kind)
    if test == true then
        heal = true
        absorb = true
        healAbsorb = true
    end
    return {
        enabled = heal == true or absorb == true or healAbsorb == true,
        heal = heal == true,
        absorb = absorb == true,
        healAbsorb = healAbsorb == true,
        test = test == true,
        healAnchorMode = Num(GroupScopeValue(kind, conf, general, "healPredAnchorMode", 3), 3),
        absorbAnchorMode = Num(GroupScopeValue(kind, conf, general, "absorbAnchorMode", 2), 2),
        texture = texture,
        absorbTexture = GroupScopeValue(kind, conf, general, "absorbBarTexture", nil),
        healAbsorbTexture = GroupScopeValue(kind, conf, general, "healAbsorbBarTexture", nil),
        healR = Num(general.healPredictionColorR, 0),
        healG = Num(general.healPredictionColorG, 1),
        healB = Num(general.healPredictionColorB, 0),
        healA = Clamp01(general.healPredictionColorA, 0.45),
        absorbR = Num(general.absorbBarColorR, 1),
        absorbG = Num(general.absorbBarColorG, 1),
        absorbB = Num(general.absorbBarColorB, 1),
        absorbA = Clamp01(GroupScopeValue(kind, conf, general, "absorbBarOpacity", general.absorbBarColorA), 0.75),
        healAbsorbR = Num(general.healAbsorbBarColorR, 0.7),
        healAbsorbG = Num(general.healAbsorbBarColorG, 0),
        healAbsorbB = Num(general.healAbsorbBarColorB, 0),
        healAbsorbA = Clamp01(GroupScopeValue(kind, conf, general, "healAbsorbBarOpacity", general.healAbsorbBarColorA), 1),
    }
end

local function CompileDispelVisual(kind, conf)
    local general = GeneralDB() or {}
    local mode = GroupScopeValue(kind, conf, general, "hlDispelColorMode", "SINGLE")
    return {
        colorMode = mode == "TYPE" and "TYPE" or "SINGLE",
        r = Num(GroupScopeValue(kind, conf, general, "hlDispelColorR", general.dispelBorderColorR), 0.25),
        g = Num(GroupScopeValue(kind, conf, general, "hlDispelColorG", general.dispelBorderColorG), 0.75),
        b = Num(GroupScopeValue(kind, conf, general, "hlDispelColorB", general.dispelBorderColorB), 1),
        a = 1,
        typeMagicR = Num(general.dispelTypeMagicR, 0.20),
        typeMagicG = Num(general.dispelTypeMagicG, 0.60),
        typeMagicB = Num(general.dispelTypeMagicB, 1.00),
        typeCurseR = Num(general.dispelTypeCurseR, 0.60),
        typeCurseG = Num(general.dispelTypeCurseG, 0.00),
        typeCurseB = Num(general.dispelTypeCurseB, 1.00),
        typeDiseaseR = Num(general.dispelTypeDiseaseR, 0.60),
        typeDiseaseG = Num(general.dispelTypeDiseaseG, 0.40),
        typeDiseaseB = Num(general.dispelTypeDiseaseB, 0.00),
        typePoisonR = Num(general.dispelTypePoisonR, 0.00),
        typePoisonG = Num(general.dispelTypePoisonG, 0.60),
        typePoisonB = Num(general.dispelTypePoisonB, 0.00),
        typeBleedR = Num(general.dispelTypeBleedR, 0.80),
        typeBleedG = Num(general.dispelTypeBleedG, 0.10),
        typeBleedB = Num(general.dispelTypeBleedB, 0.10),
    }
end

local function CompileGroupVisuals(kind, conf)
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local hoverR, hoverG, hoverB = ResolveHighlightRGB()
    local hoverSize = GF.GetHighlightVal and GF.GetHighlightVal(kind, "hlHoverSize") or conf.hlHoverSize
    return {
        kind = kind,
        rangeFadeEnabled = conf.rangeFadeEnabled ~= false,
        rangeFadeAlpha = Clamp01(conf.rangeFadeAlpha, 0.4),
        rangeFadeLayerMode = NormalizeRangeFadeLayerMode(conf.rangeFadeLayerMode),
        offlineAlpha = Clamp01(conf.offlineAlpha, 0.5),
        hideOfflineEnabled = conf.hideOfflineEnabled == true,
        hideOfflineInCombat = conf.hideOfflineInCombat == true,
        hideOfflineDelay = Num(conf.hideOfflineDelay, 0),
        healthFadeEnabled = conf.healthFadeEnabled == true,
        healthFadeThreshold = Num(conf.healthFadeThreshold, 95),
        healthFadeAlpha = Clamp01(conf.healthFadeAlpha, 0.45),
        hpBarAlpha = Clamp01(conf.hpBarAlpha, 1),
        hpBgAlpha = Clamp01(conf.hpBgAlpha, Num(conf.bgA, 0.85)),
        hpTextIgnoreAlpha = conf.hpTextIgnoreAlpha ~= false,
        hoverHighlightEnabled = not (general and general.highlightEnabled == false),
        hoverHighlightSize = Num(hoverSize, 1),
        hoverHighlightR = hoverR,
        hoverHighlightG = hoverG,
        hoverHighlightB = hoverB,
        targetIndicator = conf.targetIndicator ~= false,
        targetR = Num(conf.targetR, 1),
        targetG = Num(conf.targetG, 1),
        targetB = Num(conf.targetB, 1),
        focusIndicator = conf.hlFocusEnabled ~= false,
        focusR = Num(conf.hlFocusColorR, 0.5),
        focusG = Num(conf.hlFocusColorG, 0.5),
        focusB = Num(conf.hlFocusColorB, 1),
        focusSize = Num(conf.hlFocusSize, 2),
        focusOffset = Num(conf.hlFocusOffset, 0),
        dispelOverlayEnabled = conf.dispelOverlayEnabled == true,
        dispelOverlayStyle = NormalizeDispelOverlayStyle(conf.dispelOverlayStyle),
        dispelOverlayAlpha = Clamp01(conf.dispelOverlayAlpha, 0.35),
        dispelOverlayTrigger = NormalizeDispelOverlayTrigger(conf.dispelOverlayTrigger),
        dispelOverlayOnHealth = conf.dispelOverlayOnHealth ~= false,
        debuffStripeEnabled = conf.debuffStripeEnabled == true,
        debuffStripeEdge = conf.debuffStripeEdge or "BOTTOM",
        debuffStripeHeight = Num(conf.debuffStripeHeight, 3),
        debuffStripeAlpha = Clamp01(conf.debuffStripeAlpha, 0.6),
        debuffStripeColorR = Num(conf.debuffStripeColorR, 0.8),
        debuffStripeColorG = Num(conf.debuffStripeColorG, 0.2),
        debuffStripeColorB = Num(conf.debuffStripeColorB, 0.2),
    }
end

local function SplitAuraGrowth(value, fallback)
    value = value or fallback or "RIGHTDOWN"
    if value == "LEFTUP" then
        return "LEFT", "UP"
    elseif value == "LEFTDOWN" then
        return "LEFT", "DOWN"
    elseif value == "RIGHTUP" then
        return "RIGHT", "UP"
    elseif value == "UP" then
        return "UP", "UP"
    elseif value == "DOWN" then
        return "DOWN", "DOWN"
    end
    return "RIGHT", "DOWN"
end

local function BlizzardOwnsAuraGroup(root, nativeKey)
    if not root or root.renderer == "CUSTOM" then
        return false
    end
    local types = root.blizzardTypes
    return type(types) ~= "table" or types[nativeKey] ~= false
end

function GF.IsBlizzardAuraTypeEnabled(confOrRoot, nativeKey)
    local root = confOrRoot and confOrRoot.auras or confOrRoot
    return BlizzardOwnsAuraGroup(root, nativeKey)
end

function GF.GetBlizzardAuraTypeFlags(conf)
    return GF.IsBlizzardAuraTypeEnabled(conf, "buffs"),
        GF.IsBlizzardAuraTypeEnabled(conf, "debuffs"),
        GF.IsBlizzardAuraTypeEnabled(conf, "dispels"),
        GF.IsBlizzardAuraTypeEnabled(conf, "externals"),
        GF.IsBlizzardAuraTypeEnabled(conf, "privateAuras")
end

local function AuraBlacklistHash(kind, groupKey, group)
    local filter = GF.AuraFilter
    if filter and filter.GetBlacklistHashForGroup then
        return filter.GetBlacklistHashForGroup(kind, groupKey)
    end
    if filter and filter.BuildBlacklistHash and type(group) == "table" then
        return filter.BuildBlacklistHash(group)
    end
    return nil
end

local function AuraFilterString(groupKey, group)
    local filter = GF.AuraFilter
    local token = group and group.filterToken
    if groupKey == "buff" then
        return filter and filter.ResolveBuffFilter and filter.ResolveBuffFilter(token) or "HELPFUL|RAID"
    elseif groupKey == "externals" then
        return filter and filter.EXTERNALS_TOKEN or "HELPFUL|BIG_DEFENSIVE"
    end
    return filter and filter.ResolveDebuffFilter and filter.ResolveDebuffFilter(token) or "HARMFUL"
end

local function AuraTextAnchor(value, fallback)
    if value == "TOPLEFT" or value == "TOP" or value == "TOPRIGHT"
        or value == "LEFT" or value == "CENTER" or value == "RIGHT"
        or value == "BOTTOMLEFT" or value == "BOTTOM" or value == "BOTTOMRIGHT" then
        return value
    end
    return fallback or "CENTER"
end

local function LaneAlpha(group)
    return Clamp01(Num(group and group.behindBarAlpha, 85) / 100, 0.85)
end

local function CompileCoreAuras(kind, conf)
    local root = type(conf.auras) == "table" and conf.auras or nil
    local buff = root and type(root.buff) == "table" and root.buff or {}
    local debuff = root and type(root.debuff) == "table" and root.debuff or {}
    local externals = root and type(root.externals) == "table" and root.externals or {}
    local private = type(conf.privateAuras) == "table" and conf.privateAuras or {}
    local rootEnabled = root == nil or root.enabled ~= false
    local showBuffs = rootEnabled and buff.enabled ~= false and not BlizzardOwnsAuraGroup(root, "buffs")
    local showDebuffs = rootEnabled and debuff.enabled ~= false and not BlizzardOwnsAuraGroup(root, "debuffs")
    local showExternals = rootEnabled and externals.enabled ~= false and not BlizzardOwnsAuraGroup(root, "externals")
    local privateEnabled = private.enabled
    if privateEnabled == nil then privateEnabled = conf.privateAurasEnabled ~= false end
    local showPrivate = rootEnabled and privateEnabled ~= false and not BlizzardOwnsAuraGroup(root, "privateAuras")
    local buffGrowthX, buffGrowthY = SplitAuraGrowth(buff.growth, "LEFTUP")
    local debuffGrowthX, debuffGrowthY = SplitAuraGrowth(debuff.growth, "RIGHTDOWN")
    local externalGrowthX, externalGrowthY = SplitAuraGrowth(externals.growth, "RIGHTDOWN")
    local auraScale = DynamicAuraScale(root)
    local defaultBuffSize = (kind == "raid" or kind == "mythicraid") and 16 or 22
    local defaultDebuffSize = (kind == "raid" or kind == "mythicraid") and 16 or 20
    local defaultExternalSize = (kind == "raid" or kind == "mythicraid") and 22 or 28
    local function S(value, fallback, minValue)
        return ScaleAuraValue(Num(value, fallback), auraScale, minValue)
    end
    return {
        enabled = showBuffs == true or showDebuffs == true or showExternals == true,
        group = true,
        kind = kind,
        renderer = root and root.renderer or "BLIZZARD",
        blizzard = {
            buffs = BlizzardOwnsAuraGroup(root, "buffs"),
            debuffs = BlizzardOwnsAuraGroup(root, "debuffs"),
            dispels = BlizzardOwnsAuraGroup(root, "dispels"),
            externals = BlizzardOwnsAuraGroup(root, "externals"),
            privateAuras = BlizzardOwnsAuraGroup(root, "privateAuras"),
            iconSize = Num(root and root.blizzardIconSize, 20),
            organizationType = root and root.blizzardOrganizationType or "default",
            strata = root and root.blizzardContainerStrata or "AUTO",
            frameLevelOffset = Layer(root and root.blizzardContainerFrameLevel, 1),
            showCooldownText = not (root and root.blizzardShowCooldownText == false),
            dispelBorder = root and root.blizzardDispelBorder == true,
            privateLayerFix = root == nil or root.blizzardPrivateLayerFix ~= false,
        },
        showBuffs = showBuffs,
        showDebuffs = showDebuffs,
        showExternals = showExternals,
        showTooltip = root == nil or root.showTooltip ~= false,
        clickThrough = false,
        showSwipe = true,
        showStacks = true,
        stackAnchor = "BOTTOMRIGHT",
        sortByDuration = root and root.sortByDuration == true,
        preferPlayer = root == nil or root.preferPlayer ~= false,
        dynamicScale = root and root.dynamicScale == true,
        dynamicScaleValue = auraScale,
        masqueEnabled = conf.masqueEnabled == true,
        cooldownSwipeDarkenOnLoss = conf.cooldownSwipeDarkenOnLoss == true,
        maxBuffs = Num(buff.max, Num(conf.auraMaxIcons, 4)),
        maxDebuffs = Num(debuff.max, Num(conf.auraMaxIcons, 4)),
        maxExternals = Num(externals.max, 2),
        iconSize = S(conf.auraIconSize, 20, 1),
        buffIconSize = S(buff.size, defaultBuffSize, 1),
        debuffIconSize = S(debuff.size, defaultDebuffSize, 1),
        externalIconSize = S(externals.size, defaultExternalSize, 1),
        spacing = 1,
        buffSpacing = S(buff.spacing, 1, 0),
        debuffSpacing = S(debuff.spacing, 1, 0),
        externalSpacing = S(externals.spacing, 1, 0),
        perRow = 4,
        buffPerRow = Num(buff.perRow, 4),
        debuffPerRow = Num(debuff.perRow, 3),
        externalPerRow = Num(externals.perRow, 3),
        growth = "RIGHT",
        rowWrap = "DOWN",
        buffGrowthX = buffGrowthX,
        buffGrowthY = buffGrowthY,
        debuffGrowthX = debuffGrowthX,
        debuffGrowthY = debuffGrowthY,
        externalGrowthX = externalGrowthX,
        externalGrowthY = externalGrowthY,
        buffAnchor = buff.anchor or "BOTTOMRIGHT",
        debuffAnchor = debuff.anchor or "TOPLEFT",
        externalAnchor = externals.anchor or "CENTER",
        buffOffsetX = S(buff.x, 0),
        buffOffsetY = S(buff.y, 0),
        debuffOffsetX = S(debuff.x, 0),
        debuffOffsetY = S(debuff.y, 0),
        externalOffsetX = S(externals.x, 0),
        externalOffsetY = S(externals.y, 0),
        buffLayer = Layer(buff.layer, 5),
        debuffLayer = Layer(debuff.layer, 6),
        externalLayer = Layer(externals.layer, 7),
        buffAlpha = buff.behindBar == true and LaneAlpha(buff) or 1,
        debuffAlpha = debuff.behindBar == true and LaneAlpha(debuff) or 1,
        externalAlpha = externals.behindBar == true and LaneAlpha(externals) or 1,
        buffFilter = AuraFilterString("buff", buff),
        debuffFilter = AuraFilterString("debuff", debuff),
        externalFilter = AuraFilterString("externals", externals),
        buffBlacklistHash = AuraBlacklistHash(kind, "buff", buff),
        debuffBlacklistHash = AuraBlacklistHash(kind, "debuff", debuff),
        buffShowCooldownSwipe = buff.showCooldownSwipe ~= false,
        debuffShowCooldownSwipe = debuff.showCooldownSwipe ~= false,
        externalShowCooldownSwipe = externals.showCooldownSwipe ~= false,
        buffShowCooldown = buff.showCooldown ~= false,
        debuffShowCooldown = debuff.showCooldown ~= false,
        externalShowCooldown = externals.showCooldown ~= false,
        buffShowStacks = buff.showStacks ~= false,
        debuffShowStacks = debuff.showStacks ~= false,
        externalShowStacks = externals.showStacks == true,
        buffCooldownSize = S(buff.cooldownSize, 8, 6),
        debuffCooldownSize = S(debuff.cooldownSize, 8, 6),
        externalCooldownSize = S(externals.cooldownSize, 10, 6),
        buffCooldownAnchor = AuraTextAnchor(buff.cooldownAnchor, "CENTER"),
        debuffCooldownAnchor = AuraTextAnchor(debuff.cooldownAnchor, "CENTER"),
        externalCooldownAnchor = AuraTextAnchor(externals.cooldownAnchor, "CENTER"),
        buffStackSize = S(buff.stackSize, 10, 6),
        debuffStackSize = S(debuff.stackSize, 10, 6),
        externalStackSize = S(externals.stackSize, 10, 6),
        debuffShowDispelBorder = debuff.showDispelBorder ~= false,
        showStealableBuffs = false,
        private = {
            enabled = showPrivate,
            num = Num(private.max, Num(conf.privateAuraMax, 4)),
            size = S(private.size, Num(conf.privateAuraSize, 20), 1),
            spacing = S(private.spacing, 1, 0),
            anchor = private.anchor or conf.privateAuraAnchor or "TOPRIGHT",
            growth = private.growth or "RIGHT",
            x = S(private.x, Num(conf.privateAuraX, 0)),
            y = S(private.y, Num(conf.privateAuraY, 0)),
            showCountdown = private.showCountdown ~= false and conf.privateAuraCountdown ~= false,
            showNumbers = private.showNumbers == true,
        },
    }
end

local function AlphaPair(conf, mode)
    if GF.GetAlphaPair then
        return GF.GetAlphaPair(conf, mode)
    end
    local aIn = Clamp01(conf and conf.alphaInCombat, 1)
    local aOut = Clamp01(conf and conf.alphaOutOfCombat, 1)
    if conf and (conf.alphaSyncBoth == true or conf.alphaSync == true) then
        aOut = aIn
    end
    return aIn, aOut
end

local function NormalizeAlphaLayerMode(mode)
    if GF.NormalizeAlphaLayerMode then
        return GF.NormalizeAlphaLayerMode(mode)
    end
    if mode == true or mode == 1 or mode == "background" then
        return "background"
    elseif mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then
        return "health"
    end
    return "foreground"
end

local function CompileAlpha(conf)
    local frameIn, frameOut = AlphaPair(conf, "foreground")
    local fgIn, fgOut = AlphaPair(conf, "foreground")
    local bgIn, bgOut = AlphaPair(conf, "background")
    local hpIn, hpOut = AlphaPair(conf, "health")
    local layered = conf.alphaExcludeTextPortrait == true
    local active = layered == true
        or abs((frameIn or 1) - 1) > 0.0001
        or abs((frameOut or 1) - 1) > 0.0001

    return {
        active = active,
        inCombat = frameIn,
        outCombat = frameOut,
        layered = layered,
        layerMode = NormalizeAlphaLayerMode(conf.alphaLayerMode),
        foregroundInCombat = fgIn,
        foregroundOutOfCombat = fgOut,
        backgroundInCombat = bgIn,
        backgroundOutOfCombat = bgOut,
        healthInCombat = hpIn,
        healthOutOfCombat = hpOut,
        preserveHPColor = conf.alphaPreserveHPColor == true,
        combatEvents = GF.HasCombatAlpha and GF.HasCombatAlpha() or abs((frameIn or 1) - (frameOut or 1)) > 0.0001,
        rangeEnabled = false,
    }
end

local compiledSpecCache = GF._compiledSpec or {}
GF._compiledSpec = compiledSpecCache
GF._compiledSpecSerial = GF._compiledSpecSerial or 1

local function CompileSpecUncached(kind, frame, unit, conf)
    kind = kind or "party"
    if not conf then
        if GF.EnsureDB then
            GF.EnsureDB()
        end
        conf = GF.GetConf and GF.GetConf(kind) or {}
    end
    unit = unit or (frame and frame.unit)

    local w, h = 80, 32
    if GF.GetScaledFrameMetrics then
        w, h = GF.GetScaledFrameMetrics(kind)
    else
        w, h = Num(conf.width, w), Num(conf.height, h)
    end

    local role = GetRole(unit)
    local powerHeight = EffectivePowerHeight(kind, unit, role, conf)
    local texture = ResolveTexture(GF.ResolveBarTexture, kind)
    local bgTexture = ResolveTexture(GF.ResolveBarBgTexture, kind)
    local font = GF.ResolveFontPath and GF.ResolveFontPath(kind) or "Fonts\\FRIZQT__.TTF"
    local fontFlags = GF.ResolveFontFlags and GF.ResolveFontFlags(kind) or "OUTLINE"
    local tr, tg, tb = 1, 1, 1
    if GF.ResolveFontColor then
        tr, tg, tb = GF.ResolveFontColor(kind)
    end

    local healthLeft, healthCenter, healthRight = TextSlots(conf)
    local healthVisual = ResolveHealthVisual(conf)
    local nameTextOptions = ResolveNameTextOptions(kind, conf)
    local hpX, hpY = Num(conf.hpOffsetX, 0), Num(conf.hpOffsetY, 0)
    local powerX, powerY = Num(conf.powerOffsetX, 0), Num(conf.powerOffsetY, 0)
    local status = CompileStatus(kind, conf)
    local group = CompileGroupVisuals(kind, conf)
    local alpha = CompileAlpha(conf)
    local dispelBorderEnabled = GF.GetHighlightVal and GF.GetHighlightVal(kind, "hlDispelEnabled")
    if dispelBorderEnabled == nil then
        dispelBorderEnabled = conf.dispelEnabled == true
    end
    local general = GeneralDB() or {}
    local aggroBorderMode = GF.GetHighlightVal and GF.GetHighlightVal(kind, "hlAggroEnabled")
    if aggroBorderMode == nil and GF.GetHighlightVal then
        aggroBorderMode = GF.GetHighlightVal(kind, "aggroOutlineMode")
    end
    if aggroBorderMode == nil then
        aggroBorderMode = GroupScopeValue(kind, conf, general, "aggroOutlineMode", nil)
    end
    local aggroBorderEnabled
    if aggroBorderMode == nil then
        aggroBorderEnabled = conf.aggroEnabled == true
    else
        aggroBorderEnabled = tonumber(aggroBorderMode) == 1 or aggroBorderMode == true
    end
    local highlightThickness = GF.GetHighlightVal and GF.GetHighlightVal(kind, "highlightBorderThickness")
    if highlightThickness == nil and GF.GetHighlightVal then
        highlightThickness = GF.GetHighlightVal(kind, "hlAggroSize")
    end
    if highlightThickness == nil then
        highlightThickness = GroupScopeValue(kind, conf, general, "highlightBorderThickness", nil)
            or GroupScopeValue(kind, conf, general, "hlAggroSize", nil)
    end
    local dispelBorderTrigger = GroupScopeValue(kind, conf, general, "dispelBorderTrigger", "BY_ME")

    return {
        _msufGFCompileSerial = GF._compiledSpecSerial or 1,
        scope = "group",
        key = "gf_" .. kind,
        unit = unit,
        groupKind = kind,
        width = w,
        height = h,
        texture = texture,
        backgroundTexture = bgTexture,
        backgroundAlpha = Num(conf.bgA, 0.85),
        font = font,
        fontFlags = fontFlags,
        fontSize = Num(conf.nameFontSize, 12),
        nameFontSize = Num(conf.nameFontSize, 12),
        healthFontSize = Num(conf.hpFontSize, 10),
        powerFontSize = Num(conf.powerFontSize, 9),
        textColor = { r = tr or 1, g = tg or 1, b = tb or 1, a = 1 },
        showName = conf.showName ~= false,
        showHealthText = conf.showHPText ~= false,
        showPowerText = IsPowerTextEnabled(kind, conf),
        health = {
            mode = healthVisual.mode,
            r = healthVisual.r,
            g = healthVisual.g,
            b = healthVisual.b,
            texture = texture,
            backgroundTexture = bgTexture,
            background = {
                r = Num(conf.bgR, 0.1),
                g = Num(conf.bgG, 0.1),
                b = Num(conf.bgB, 0.1),
                a = Num(conf.hpBgAlpha, Num(conf.bgA, 0.85)),
            },
            backgroundMatchHealth = healthVisual.backgroundMatchHealth == true,
            reverse = conf.reverseFill == true,
            smooth = conf.smoothFill ~= false,
        },
        power = {
            enabled = powerHeight > 0,
            height = powerHeight,
            texture = texture,
            backgroundTexture = bgTexture,
            background = {
                r = Num(conf.bgR, 0.1),
                g = Num(conf.bgG, 0.1),
                b = Num(conf.bgB, 0.1),
                a = Num(conf.bgA, 0.85),
            },
            backgroundMatchHealth = false,
            embed = true,
            detached = false,
            mode = conf.powerColorMode or "type",
            smooth = conf.powerSmoothFill == true,
        },
        text = {
            nameClassColor = nameTextOptions.nameClassColor == true,
            nameNpcColor = nameTextOptions.nameNpcColor == true,
            nameColor = nameTextOptions.nameColor,
            nameAnchor = conf.nameAnchor or "LEFT",
            nameX = Num(conf.nameOffsetX, 0),
            nameY = Num(conf.nameOffsetY, 0),
            nameLayer = Layer(conf.nameTextLayer, 5),
            nameShorten = nameTextOptions.nameShorten == true,
            nameShortenMax = nameTextOptions.nameShortenMax,
            nameShortenSide = nameTextOptions.nameShortenSide,
            nameShortenDots = nameTextOptions.nameShortenDots,
            hideNameOnDeadOffline = nameTextOptions.hideNameOnDeadOffline == true,
            healthLeft = healthLeft,
            healthCenter = healthCenter,
            healthRight = healthRight,
            healthDelimiter = conf.textDelimiter or " / ",
            healthReverse = conf.hpTextReverse == true,
            healthLayer = Layer(conf.textLayer, 5),
            healthX = hpX,
            healthY = hpY,
            healthLeftX = hpX + Num(conf.hpTextLeftOffsetX, 0),
            healthLeftY = hpY + Num(conf.hpTextLeftOffsetY, 0),
            healthCenterX = hpX + Num(conf.hpTextCenterOffsetX, 0),
            healthCenterY = hpY + Num(conf.hpTextCenterOffsetY, 0),
            healthRightX = hpX + Num(conf.hpTextRightOffsetX, 0),
            healthRightY = hpY + Num(conf.hpTextRightOffsetY, 0),
            powerLeft = conf.powerTextLeft or "NONE",
            powerCenter = conf.powerTextCenter or "NONE",
            powerRight = conf.powerTextRight or "NONE",
            powerDelimiter = conf.powerTextDelimiter or " / ",
            powerLayer = Layer(conf.powerTextLayer, 2),
            powerLeftX = powerX + Num(conf.powerTextLeftOffsetX, 0),
            powerLeftY = powerY + Num(conf.powerTextLeftOffsetY, 0),
            powerCenterX = powerX + Num(conf.powerTextCenterOffsetX, 0),
            powerCenterY = powerY + Num(conf.powerTextCenterOffsetY, 0),
            powerRightX = powerX + Num(conf.powerTextRightOffsetX, 0),
            powerRightY = powerY + Num(conf.powerTextRightOffsetY, 0),
            shortNumbers = true,
        },
        prediction = CompilePrediction(kind, conf, texture),
        dispel = CompileDispelVisual(kind, conf),
        status = status,
        border = {
            enabled = conf.borderEnabled ~= false,
            thickness = GF.GetBarOutlineThickness and GF.GetBarOutlineThickness(kind) or Num(conf.borderSize, 1),
            r = Num(conf.borderR, 0),
            g = Num(conf.borderG, 0),
            b = Num(conf.borderB, 0),
            a = Num(conf.borderA, 1),
            highlightThickness = Num(highlightThickness, GF.GetBarOutlineThickness and GF.GetBarOutlineThickness(kind) or Num(conf.borderSize, 1)),
            aggro = aggroBorderEnabled == true,
            aggroMode = conf.aggroMode or general.aggroMode or "ALL",
            aggroR = Num(GroupScopeValue(kind, conf, general, "hlAggroColorR", general.aggroBorderColorR or general.aggroBorderR), 1.00),
            aggroG = Num(GroupScopeValue(kind, conf, general, "hlAggroColorG", general.aggroBorderColorG or general.aggroBorderG), 0.55),
            aggroB = Num(GroupScopeValue(kind, conf, general, "hlAggroColorB", general.aggroBorderColorB or general.aggroBorderB), 0.00),
            purgeR = Num(GroupScopeValue(kind, conf, general, "hlPurgeColorR", general.purgeBorderColorR), 1.00),
            purgeG = Num(GroupScopeValue(kind, conf, general, "hlPurgeColorG", general.purgeBorderColorG), 0.85),
            purgeB = Num(GroupScopeValue(kind, conf, general, "hlPurgeColorB", general.purgeBorderColorB), 0.00),
            dispel = dispelBorderEnabled == true,
            dispelTrigger = NormalizeDispelDetectTrigger(dispelBorderTrigger),
        },
        alpha = alpha,
        auras = CompileCoreAuras(kind, conf),
        group = group,
        groupLayout = {
            tooltipMode = conf.tooltipMode or "ALWAYS",
            tooltipModifier = conf.tooltipModifier or "ALT",
            clickCastEnabled = conf.clickCastEnabled ~= false,
            hideInClientScene = conf.hideInClientScene ~= false,
        },
        cornerIndicators = GF.CompileCornerIndicators and GF.CompileCornerIndicators(conf) or { enabled = false },
        spellIndicators = GF.CompileSpellIndicators and GF.CompileSpellIndicators(conf) or { enabled = false, items = {} },
    }
end

function GF.InvalidateCompiledSpecs(kind)
    GF._compiledSpecSerial = (GF._compiledSpecSerial or 1) + 1
    if kind then
        compiledSpecCache[kind] = nil
    else
        wipe(compiledSpecCache)
    end
end

local function CopyShallow(dst, src)
    wipe(dst)
    for k, v in pairs(src) do
        dst[k] = v
    end
    return dst
end

local function PatchFrameSpec(base, kind, frame, unit, conf)
    local spec = frame._msufGFSpec
    if not spec then
        spec = {}
        frame._msufGFSpec = spec
    end
    if frame._msufGFSpecBase ~= base then
        CopyShallow(spec, base)
        frame._msufGFSpecBase = base
    end
    spec.unit = unit
    spec.key = "gf_" .. kind
    spec.groupKind = kind

    local role = GetRole(unit)
    local powerHeight = EffectivePowerHeight(kind, unit, role, conf)
    local power = frame._msufGFPowerSpec
    if not power then
        power = {}
        frame._msufGFPowerSpec = power
    end
    if frame._msufGFPowerSpecBase ~= base.power then
        CopyShallow(power, base.power)
        frame._msufGFPowerSpecBase = base.power
    end
    power.enabled = powerHeight > 0
    power.height = powerHeight
    spec.power = power

    local status = frame._msufGFStatusSpec
    if not status then
        status = {}
        frame._msufGFStatusSpec = status
    end
    if frame._msufGFStatusSpecBase ~= base.status then
        CopyShallow(status, base.status)
        frame._msufGFStatusSpecBase = base.status
    end
    status.roleValue = role
    spec.status = status
    return spec
end

function GF.CompileSpec(kind, frame, unit)
    kind = kind or "party"
    local base = compiledSpecCache[kind]
    local conf = base and base._msufGFConf
    if not base then
        if GF.EnsureDB then
            GF.EnsureDB()
        end
        conf = GF.GetConf and GF.GetConf(kind) or {}
        base = CompileSpecUncached(kind, nil, nil, conf)
        base._msufGFConf = conf
        compiledSpecCache[kind] = base
    elseif not conf then
        if GF.EnsureDB then
            GF.EnsureDB()
        end
        conf = GF.GetConf and GF.GetConf(kind) or {}
        base._msufGFConf = conf
    end
    unit = unit or (frame and frame.unit)
    if frame then
        return PatchFrameSpec(base, kind, frame, unit, conf)
    end
    return base
end

function GF.GetCompiledSpec(kind, frame, unit)
    return GF.CompileSpec(kind, frame, unit)
end
