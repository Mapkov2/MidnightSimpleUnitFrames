-- Auras3 runtime: ConfigValues.
-- Shared configuration readers, native filter composition and lane finalization. Compile once per configuration generation, never per UNIT_AURA.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.ConfigValues = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local next = next
local pairs = pairs
local table_concat = table.concat
local table_sort = table.sort
local tonumber = tonumber
local tostring = tostring
local type = type
local AURA_BORDER_OPTIONS = dependencies.Appearance.AURA_BORDER_OPTIONS
local AURA_ICON_BASE_OFFSET = dependencies.Platform.AURA_ICON_BASE_OFFSET
local BOSS_FILTER_SCOPE_OWNER = dependencies.Schema.BOSS_FILTER_SCOPE_OWNER
local Clamp01 = dependencies.Platform.Clamp01
local ClampNumber = dependencies.Platform.ClampNumber
local DEFAULT_SHARED = dependencies.Schema.DEFAULT_SHARED
local LaneLayoutSignature = dependencies.Signatures.LaneLayoutSignature
local LaneStructuralSignature = dependencies.Signatures.LaneStructuralSignature
local LaneTrackingSignature = dependencies.Signatures.LaneTrackingSignature
local MANAGED_UNITS = dependencies.Schema.MANAGED_UNITS
local MAX_CONFIGURABLE_DEBUFF_DURATION = dependencies.Platform.MAX_CONFIGURABLE_DEBUFF_DURATION
local MAX_FINITE_AURA_DURATION = dependencies.Platform.MAX_FINITE_AURA_DURATION
local Round = dependencies.Platform.Round
local STYLE_SHARED_LAYOUT_KEYS = dependencies.Schema.STYLE_SHARED_LAYOUT_KEYS
local Shape = dependencies.Appearance.Shape
local UNIT_AURA_BASE_OFFSET = dependencies.Platform.UNIT_AURA_BASE_OFFSET
local UNIT_FLAG = dependencies.Schema.UNIT_FLAG
local issecretvalue = dependencies.Platform.issecretvalue

local function ReadRaw(primary, secondary, key)
    if type(primary) == "table" and primary[key] ~= nil then return primary[key] end
    if type(secondary) == "table" and secondary[key] ~= nil then return secondary[key] end
    return nil
end

local function ReadBool(primary, secondary, key, fallback)
    local value = ReadRaw(primary, secondary, key)
    if value == nil then return fallback == true end
    return value == true
end

local NormalizeDebuffTypeBorderMode = _G.MSUF_NormalizeAuraDebuffTypeBorderMode

local function ReadDebuffTypeBorderMode(primary, secondary)
    local mode
    if type(primary) == "table" then
        mode = primary.debuffTypeBorderMode
        if mode == nil then mode = primary.dispelBorderMode end
        if mode == nil and primary.useDebuffTypeBorders ~= nil then
            return primary.useDebuffTypeBorders == true and "SYMBOL" or "OFF"
        end
        if mode ~= nil and NormalizeDebuffTypeBorderMode(mode, "OFF") == "OFF" and primary.useDebuffTypeBorders == true then
            return "SYMBOL"
        end
    end
    if mode == nil and type(secondary) == "table" then
        mode = secondary.debuffTypeBorderMode
        if mode == nil then mode = secondary.dispelBorderMode end
        if mode == nil and secondary.useDebuffTypeBorders ~= nil then
            return secondary.useDebuffTypeBorders == true and "SYMBOL" or "OFF"
        end
        if mode ~= nil and NormalizeDebuffTypeBorderMode(mode, "OFF") == "OFF" and secondary.useDebuffTypeBorders == true then
            return "SYMBOL"
        end
    end
    return NormalizeDebuffTypeBorderMode(mode, "OFF")
end

local function ReadGroupDebuffTypeBorderMode(source)
    local mode = source and (source.debuffDispelBorderMode or source.debuffTypeBorderMode or source.dispelBorderMode)
    if mode == nil and source then
        if source.debuffShowDispelSymbol ~= nil then return source.debuffShowDispelSymbol == true and "SYMBOL" or "BORDER" end
        if source.debuffShowDispelBorder ~= nil then return source.debuffShowDispelBorder == true and "SYMBOL" or "OFF" end
        if type(source.blizzard) == "table" and source.blizzard.dispelBorder == true then return "SYMBOL" end
    end
    if source and NormalizeDebuffTypeBorderMode(mode, "OFF") == "OFF" and source.debuffShowDispelBorder == true then
        return "SYMBOL"
    end
    return NormalizeDebuffTypeBorderMode(mode, "OFF")
end

local function GetAuraBorderOptions(showIcon, preserveAsset)
    -- Border/BorderWithIcon let Blizzard supply its dispel border atlas, which
    -- is the intended art for the lane debuff-type border feature.
    local styles = _G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
    AURA_BORDER_OPTIONS.style = styles and (preserveAsset == true and styles.PreserveAsset
        or (showIcon == true and styles.BorderWithIcon or styles.Border)) or nil
    return A3.ApplyHarmfulDispelColorOptions(AURA_BORDER_OPTIONS)
end

local function ReadNumber(primary, secondary, key, fallback, minValue, maxValue)
    return ClampNumber(ReadRaw(primary, secondary, key), fallback, minValue, maxValue)
end

local function ReadAnchor(primary, secondary, key, fallback)
    local value = ReadRaw(primary, secondary, key)
    if value == "TOPLEFT" or value == "TOP" or value == "TOPRIGHT"
        or value == "LEFT" or value == "CENTER" or value == "RIGHT"
        or value == "BOTTOMLEFT" or value == "BOTTOM" or value == "BOTTOMRIGHT" then
        return value
    end
    return fallback or "CENTER"
end

-- Read Style values through the same ownership map exported to Menu_Model.
-- layout-owned values fall back only to the root Shared table; layoutShared-
-- owned values never consult layout. This makes stale/misplaced keys inert and
-- keeps a fresh runtime compile identical to the setting the menu displays.
local function ReadUnitStyleRaw(layout, laneLayout, rootShared, key)
    if STYLE_SHARED_LAYOUT_KEYS[key] then
        return ReadRaw(laneLayout, nil, key)
    end
    return ReadRaw(layout, nil, key)
end

local function ReadUnitStyleBool(layout, laneLayout, rootShared, key, fallback)
    local value = ReadUnitStyleRaw(layout, laneLayout, rootShared, key)
    if value == nil then return fallback == true end
    return value == true
end

local function ReadUnitStyleAnchor(layout, laneLayout, rootShared, key, fallback)
    local value = ReadUnitStyleRaw(layout, laneLayout, rootShared, key)
    if value == "TOPLEFT" or value == "TOP" or value == "TOPRIGHT"
        or value == "LEFT" or value == "CENTER" or value == "RIGHT"
        or value == "BOTTOMLEFT" or value == "BOTTOM" or value == "BOTTOMRIGHT" then
        return value
    end
    return fallback or "CENTER"
end

-- Buff and Debuff Style values are strict lane owners. Generic and root
-- Shared keys are legacy migration inputs only and never participate here.
local function ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, laneKey, genericKey)
    local laneLayoutOwned = STYLE_SHARED_LAYOUT_KEYS[laneKey] == true
    local localOwner = laneLayoutOwned and laneLayout or layout
    return ReadRaw(localOwner, nil, laneKey)
end

local function ReadUnitLaneStyleBool(layout, laneLayout, rootShared, laneKey, genericKey, fallback)
    local value = ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, laneKey, genericKey)
    if value == nil then return fallback == true end
    return value == true
end

local function ReadUnitLaneStyleNumber(layout, laneLayout, rootShared, laneKey, genericKey, fallback, minValue, maxValue)
    return ClampNumber(ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, laneKey, genericKey),
        fallback, minValue, maxValue)
end

local function ReadUnitLaneStyleAnchor(layout, laneLayout, rootShared, laneKey, genericKey, fallback)
    local value = ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, laneKey, genericKey)
    if value == "TOPLEFT" or value == "TOP" or value == "TOPRIGHT"
        or value == "LEFT" or value == "CENTER" or value == "RIGHT"
        or value == "BOTTOMLEFT" or value == "BOTTOM" or value == "BOTTOMRIGHT" then
        return value
    end
    return fallback or "CENTER"
end

local function NormalizeDurationBarPosition(value, fallback)
    value = tostring(value or fallback or "BOTTOM"):upper()
    if value == "TOP" then return "TOP" end
    return "BOTTOM"
end

local function NormalizeDurationBarDirection(value, fallback)
    value = tostring(value or fallback or "REMAINING"):upper()
    if value == "ELAPSED" or value == "ELAPSED_TIME" then return "ELAPSED" end
    return "REMAINING"
end

local function NormalizeDurationBarDisplay(value, fallback)
    value = tostring(value or fallback or "BAR_ONLY"):upper()
    if value == "ICON" or value == "ICONS" or value == "ICON_BAR" or value == "ICON+BAR" or value == "OVERLAY" then return "OVERLAY" end
    return "BAR_ONLY"
end

local function EnsureDB()
    if A3.EnsureDB then
        local auras, shared = A3.EnsureDB()
        if type(auras) == "table" then
            auras.shared = type(auras.shared) == "table" and auras.shared or {}
            return auras, auras.shared
        end
    end
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return {}, {} end
    db.auras3 = type(db.auras3) == "table" and db.auras3 or {}
    db.auras3.shared = type(db.auras3.shared) == "table" and db.auras3.shared or {}
    return db.auras3, db.auras3.shared
end

function Shape.SharedValue(shared, kind)
    local appearanceShapes = type(shared) == "table" and shared.appearanceIconShapes or nil
    if type(appearanceShapes) == "table" and appearanceShapes[kind] ~= nil then
        return appearanceShapes[kind]
    end
    return kind == "playerDefensives" and "FOLLOW_PORTRAIT" or "RECTANGLE"
end

local function NormalizeRuntimeUnit(unit)
    unit = tostring(unit or "")
    if unit == "boss" then return "boss1" end
    if MANAGED_UNITS[unit] then return unit end
    return nil
end

local function IsGroupFrame(frame)
    if not frame then return false end
    if frame._msufIsGroupFrame or frame._msufGFKind then return true end
    local unit = frame.MSUFUnitKey
    return type(unit) == "string" and (unit:match("^party%d+$") or unit:match("^raid%d+$")) and true or false
end

local function UnitAuraIconsEnabled(auras, unit)
    if not (type(auras) == "table" and auras.enabled == true) then return false end
    local flag = UNIT_FLAG[NormalizeRuntimeUnit(unit)]
    return flag and auras[flag] == true or false
end

local function EffectiveUnitTables(auras, unit)
    local perUnit = type(auras.perUnit) == "table" and auras.perUnit or nil
    local unitCfg = perUnit and perUnit[unit] or nil
    local filterCfg = perUnit and perUnit[BOSS_FILTER_SCOPE_OWNER[unit] or unit] or nil
    local layout = unitCfg and type(unitCfg.layout) == "table" and unitCfg.layout or {}
    local layoutShared = unitCfg and type(unitCfg.layoutShared) == "table" and unitCfg.layoutShared or {}
    local filters = filterCfg and type(filterCfg.filters) == "table" and filterCfg.filters or {}
    return layout, layoutShared, filters
end

local function EffectiveUnitBlacklist(auras, unit)
    if type(auras) ~= "table" then return nil end
    local perUnit = type(auras.perUnit) == "table" and auras.perUnit or nil
    local unitCfg = perUnit and perUnit[BOSS_FILTER_SCOPE_OWNER[unit] or unit] or nil
    return unitCfg and type(unitCfg.blacklist) == "table" and unitCfg.blacklist or nil
end

local function AuraSpellIDFromKey(value)
    -- Saved hashes and compiled catalogs normally already contain numeric IDs.
    -- Positive integers below Lua 5.1's scientific-notation boundary need no string or
    -- pattern work. Keep the legacy parser for links, tokens and all other values.
    if type(value) == "number" and value > 0 and value < 100000000000000 and value % 1 == 0 then
        return value
    end
    value = tostring(value or "")
    local id = tonumber(value:match("spell:(%d+)") or value:match("#(%d+)") or value:match("^(%d+)$"))
    return id and math_floor(id + 0.5) or nil
end

local function NormalizeCandidateSpellIDs(spellIDs, fieldName)
    if type(spellIDs) ~= "table" then return nil, nil end
    local addAliases = A3.AddAuraSpellIDAndAliases
    if type(addAliases) ~= "function" then addAliases = nil end
    local out
    for key, enabled in pairs(spellIDs) do
        local spellID
        if enabled == true or enabled == nil then
            spellID = AuraSpellIDFromKey(key)
        elseif enabled ~= false then
            local valueType = type(enabled)
            if valueType == "number" or valueType == "string" then
                spellID = AuraSpellIDFromKey(enabled) or AuraSpellIDFromKey(key)
            elseif valueType == "table" and enabled.enabled ~= false then
                spellID = AuraSpellIDFromKey(enabled.spellID or enabled.spellId or enabled.id or enabled[1]) or AuraSpellIDFromKey(key)
            end
        end
        if spellID then
            if not out then out = {} end
            if addAliases then
                addAliases(out, spellID)
            else
                out[spellID] = true
            end
        end
    end
    if not out then return nil, nil end
    local parts, count = {}, 0
    for spellID in pairs(out) do
        count = count + 1
        parts[count] = tostring(spellID)
    end
    if count == 0 then return nil, nil end
    table_sort(parts)
    return out, fieldName .. ":" .. table_concat(parts, ",")
end

local function CandidateFiltersFromSpellIDs(spellIDs, fieldName)
    fieldName = fieldName or "excludeSpellIDs"
    local ids, signature = NormalizeCandidateSpellIDs(spellIDs, fieldName)
    return ids and { [fieldName] = ids } or nil, signature
end

local function CandidateFiltersFromIncludeAndExcludeSpellIDs(includeSpellIDs, excludeSpellIDs, sharedIncludeSignature)
    local included, includeSignature
    if type(includeSpellIDs) == "table"
        and type(sharedIncludeSignature) == "string" and sharedIncludeSignature ~= "" then
        -- Versioned static catalogs are already normalized and immutable. Keep
        -- their hash shared instead of copying/sorting every ID for every raid
        -- unit config; Blizzard still secure-copies options at its API boundary.
        included = includeSpellIDs
        includeSignature = "includeSpellIDs@" .. sharedIncludeSignature
    else
        included, includeSignature = NormalizeCandidateSpellIDs(includeSpellIDs, "includeSpellIDs")
    end
    local excluded, excludeSignature = NormalizeCandidateSpellIDs(excludeSpellIDs, "excludeSpellIDs")
    if not included then return excluded and { excludeSpellIDs = excluded } or nil, excludeSignature end
    -- Only the versioned static include catalog is shared. Mutable saved maps
    -- and their expanded hashes stay private: auto-blacklists may extend them
    -- during compilation. Build one outer options table per lane.
    local filters = { includeSpellIDs = included }
    if excluded then
        filters.excludeSpellIDs = excluded
        includeSignature = includeSignature .. ";" .. excludeSignature
    end
    return filters, includeSignature
end

local function AddMaxDurationCandidateFilter(candidateFilters, candidateFilterSignature, maxDuration, hidePermanent)
    maxDuration = Round(ClampNumber(maxDuration, 0, 0, MAX_CONFIGURABLE_DEBUFF_DURATION))
    if maxDuration <= 0 then
        if hidePermanent ~= true then return candidateFilters, candidateFilterSignature end
        maxDuration = MAX_FINITE_AURA_DURATION
    end
    candidateFilters = candidateFilters or {}
    candidateFilters.maxDuration = maxDuration
    local part = "maxDuration:" .. tostring(maxDuration)
    candidateFilterSignature = candidateFilterSignature and (candidateFilterSignature .. ";" .. part) or part
    return candidateFilters, candidateFilterSignature
end

local function ApplyAuraIconZoom(texture, lane)
    if not (texture and texture.SetTexCoord) then return end
    local zoom = ClampNumber(lane and lane.iconZoom, 100, 100, 200)
    if texture._msufA3IconZoomKey == zoom then return end
    texture._msufA3IconZoomKey = zoom
    local visible = 100 / zoom
    local inset = (1 - visible) * 0.5
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end

local function AuraIconBaseOffset(parentFrame)
    -- Unit frames use the SAME element base as texts and status icons
    -- (frame + 10 + layer, see UF.Layers.UNIT_AURA_BASE_OFFSET), so the
    -- Layers popover's 0..30 values form one comparable scale: aura layer 7
    -- renders above a text at layer 5 and below one at layer 9. The old base
    -- of 0 shifted auras a full band below every text/status element, which
    -- made the aura layer slider look dead against them. Group frames keep
    -- the fixed foreground band (base 64) where icons never sink under
    -- effects.
    if parentFrame and parentFrame.MSUFSpec and parentFrame.MSUFSpec.scope == "group" then
        return AURA_ICON_BASE_OFFSET
    end
    return UNIT_AURA_BASE_OFFSET
end

local function AddHidePermanentCandidateFilter(candidateFilters, candidateFilterSignature, hidePermanent)
    return AddMaxDurationCandidateFilter(candidateFilters, candidateFilterSignature, nil, hidePermanent)
end

local function CandidateFiltersFromBlacklist(blacklist)
    local spells = type(blacklist) == "table" and blacklist.spells or nil
    local candidateFilters, candidateFilterSignature = CandidateFiltersFromSpellIDs(spells)
    return AddMaxDurationCandidateFilter(candidateFilters, candidateFilterSignature,
        type(blacklist) == "table" and blacklist.maxDuration,
        type(blacklist) == "table" and blacklist.hidePermanent == true)
end

local function CandidateFiltersFromBlacklistHash(hash)
    return CandidateFiltersFromSpellIDs(hash)
end

local function GrowthParts(growth, rowWrap)
    growth = tostring(growth or "RIGHT")
    rowWrap = tostring(rowWrap or "DOWN")
    if growth == "LEFTUP" then return "LEFT", "UP", -1, 1, false end
    if growth == "LEFTDOWN" then return "LEFT", "DOWN", -1, -1, false end
    if growth == "RIGHTUP" then return "RIGHT", "UP", 1, 1, false end
    if growth == "RIGHTDOWN" then return "RIGHT", "DOWN", 1, -1, false end
    if growth == "LEFT" then return "LEFT", rowWrap, -1, rowWrap == "UP" and 1 or -1, false end
    -- PTR 5-safe vertical growth: Blizzard's native flow remains row-major,
    -- but a one-icon row width makes every following aura start a new row.
    -- This preserves true single-column UP/DOWN without touching initialized
    -- AuraButtons. Multi-column column-major wrapping is intentionally absent.
    if growth == "UP" then return "RIGHT", "UP", 1, 1, true end
    if growth == "DOWN" then return "RIGHT", "DOWN", 1, -1, true end
    return "RIGHT", rowWrap, 1, rowWrap == "UP" and 1 or -1, false
end

local function GroupGrowthParts(growthX, growthY)
    growthX = tostring(growthX or "RIGHT")
    growthY = tostring(growthY or "DOWN")
    if growthX == "UP" or growthX == "DOWN" then
        return "RIGHT", growthX, 1, growthX == "UP" and 1 or -1, true
    end
    local xSign = growthX == "LEFT" and -1 or 1
    local ySign = growthY == "UP" and 1 or -1
    return growthX == "LEFT" and "LEFT" or "RIGHT", growthY == "UP" and "UP" or "DOWN", xSign, ySign, false
end

local function ButtonAnchor(xSign, ySign)
    if xSign < 0 then
        return ySign > 0 and "BOTTOMRIGHT" or "TOPRIGHT"
    end
    return ySign > 0 and "BOTTOMLEFT" or "TOPLEFT"
end

local VALID_NATIVE_FILTER_TOKENS = {
    HELPFUL = true,
    HARMFUL = true,
    PLAYER = true,
    RAID = true,
    CANCELABLE = true,
    MAW = true,
    INCLUDE_NAME_PLATE_ONLY = true,
    EXTERNAL_DEFENSIVE = true,
    CROWD_CONTROL = true,
    RAID_IN_COMBAT = true,
    RAID_PLAYER_DISPELLABLE = true,
    BIG_DEFENSIVE = true,
    IMPORTANT = true,
    DISPELLABLE = true,
}

local LEGACY_NATIVE_FILTER_TOKENS = {
    ALL = false,
    NOT_CANCELABLE = "!CANCELABLE",
}

local function AddNativeFilterToken(out, seen, token, baseToken)
    token = tostring(token or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")
    local negated = token:sub(1, 1) == "!"
    if negated then
        token = token:sub(2):gsub("^%s+", ""):gsub("%s+$", "")
    end
    local legacy = LEGACY_NATIVE_FILTER_TOKENS[token]
    if legacy ~= nil then
        if legacy == false then return end
        token = legacy
        negated = token:sub(1, 1) == "!"
        if negated then
            token = token:sub(2):gsub("^%s+", ""):gsub("%s+$", "")
        end
    end
    if token == "" or not VALID_NATIVE_FILTER_TOKENS[token] then return end
    if negated and (token == "HELPFUL" or token == "HARMFUL") then return end
    if (token == "HELPFUL" or token == "HARMFUL") and token ~= baseToken then return end
    if negated then token = "!" .. token end
    if seen[token] then return end
    seen[token] = true
    out[#out + 1] = token
end

local function NormalizeNativeFilterString(filter, fallback)
    fallback = tostring(fallback or "")
    filter = tostring(filter or "")
    local baseToken = (fallback:find("HARMFUL", 1, true) or filter:find("HARMFUL", 1, true)) and "HARMFUL" or "HELPFUL"
    local out, seen = {}, {}
    AddNativeFilterToken(out, seen, baseToken, baseToken)
    for token in fallback:gmatch("[^|]+") do AddNativeFilterToken(out, seen, token, baseToken) end
    for token in filter:gmatch("[^|]+") do AddNativeFilterToken(out, seen, token, baseToken) end
    return table_concat(out, "|")
end

local function GridShape(maxCount, perRow, verticalGrowth)
    maxCount = Round(maxCount)
    perRow = math_max(Round(perRow), 1)
    if maxCount <= 0 then return 1, 1 end
    if verticalGrowth then return 1, maxCount end
    local major = math_min(perRow, maxCount)
    local minor = math_floor((maxCount + perRow - 1) / perRow)
    return major, minor
end

-- Appearance icon style (static border + soft shadow) is global per Aura
-- product: Buff, Debuff, Player Defensives, or Dots on Target. Compiled once
-- per product/runtime generation and stamped by reference onto each lane.
local APPEARANCE_KIND = {
    buff = true, debuff = true, playerDefensives = true, targetDots = true,
}
local function NormalizeAppearanceKind(kind)
    return APPEARANCE_KIND[kind] and kind or "buff"
end

local _iconStyleCompiled, _iconStyleCompiledGen = {}, nil
local function SharedIconStyle(kind)
    kind = NormalizeAppearanceKind(kind)
    local gen = A3._runtimeConfigGen or 1
    if _iconStyleCompiledGen ~= gen then
        _iconStyleCompiled, _iconStyleCompiledGen = {}, gen
    elseif _iconStyleCompiled[kind] then
        return _iconStyleCompiled[kind]
    end
    local _, shared = EnsureDB()
    local styles = type(shared.appearanceIconStyles) == "table" and shared.appearanceIconStyles or nil
    local source = type(styles) == "table" and styles[kind] or nil
    source = type(source) == "table" and source or nil
    local function Read(key, fallback)
        if source and source[key] ~= nil then return source[key] end
        return fallback
    end
    local bc = Read("styleBorderColor", DEFAULT_SHARED.styleBorderColor)
    local sc = Read("styleShadowColor", DEFAULT_SHARED.styleShadowColor)
    bc = type(bc) == "table" and bc or DEFAULT_SHARED.styleBorderColor
    sc = type(sc) == "table" and sc or DEFAULT_SHARED.styleShadowColor
    local BorderStyles = MSUF.BorderStyles
    local borderStyle = BorderStyles and BorderStyles.Normalize(Read("styleBorderStyle", "SOLID")) or "SOLID"
    local style = {
        borderEnabled = Read("styleBorderEnabled", false) == true,
        borderStyle = borderStyle,
        -- nil for SOLID (and for a style whose media went missing), which keeps
        -- the flat single-quad ring as the fallback everywhere downstream.
        borderTexture = BorderStyles and BorderStyles.Resolve(borderStyle) or nil,
        borderThickness = Round(ClampNumber(Read("styleBorderThickness", DEFAULT_SHARED.styleBorderThickness), DEFAULT_SHARED.styleBorderThickness, 1, 8)),
        borderR = Clamp01(bc[1] or bc.r, 0),
        borderG = Clamp01(bc[2] or bc.g, 0),
        borderB = Clamp01(bc[3] or bc.b, 0),
        borderA = Clamp01(bc[4] or bc.a, 1),
        shadowEnabled = Read("styleShadowEnabled", false) == true,
        shadowSize = Round(ClampNumber(Read("styleShadowSize", DEFAULT_SHARED.styleShadowSize), DEFAULT_SHARED.styleShadowSize, 1, 16)),
        shadowR = Clamp01(sc[1] or sc.r, 0),
        shadowG = Clamp01(sc[2] or sc.g, 0),
        shadowB = Clamp01(sc[3] or sc.b, 0),
        shadowA = Clamp01(sc[4] or sc.a, 0.8),
    }
    style.borderEdge = style.borderTexture and BorderStyles.EdgeSize(borderStyle, style.borderThickness) or nil
    -- "inner" styles shade the icon from on top; "outer" ones frame it from
    -- behind. The renderer needs this before it creates the textures.
    style.borderPlacement = style.borderTexture and BorderStyles.Placement(borderStyle) or nil
    style.signature = table_concat({
        style.borderEnabled and "B" or "b", style.borderStyle, tostring(style.borderPlacement),
        tostring(style.borderTexture), style.borderThickness,
        style.borderR, style.borderG, style.borderB, style.borderA,
        style.shadowEnabled and "S" or "s", style.shadowSize,
        style.shadowR, style.shadowG, style.shadowB, style.shadowA,
    }, ":")
    _iconStyleCompiled[kind] = style
    return style
end

local function AddNonPlayerCandidateFilter(candidateFilters, candidateFilterSignature, enabled)
    if enabled ~= true then return candidateFilters, candidateFilterSignature end
    candidateFilters = candidateFilters or {}
    candidateFilters.isFromPlayerOrPlayerPet = false
    local part = "isFromPlayerOrPlayerPet:false"
    candidateFilterSignature = candidateFilterSignature and (candidateFilterSignature .. ";" .. part) or part
    return candidateFilters, candidateFilterSignature
end

local function RemoveNativeFilterToken(filter, removeToken, fallback)
    removeToken = tostring(removeToken or ""):upper()
    local kept = {}
    for token in tostring(filter or ""):gmatch("[^|]+") do
        local normalized = token:upper():gsub("^%s+", ""):gsub("%s+$", "")
        if normalized ~= removeToken then kept[#kept + 1] = token end
    end
    return NormalizeNativeFilterString(table_concat(kept, "|"), fallback)
end

local function ConfigureCuratedBigDefensiveLane(lane)
    if not (lane and tostring(lane.nativeFilter or ""):find("BIG_DEFENSIVE", 1, true)) then return lane end
    local getHash = A3.GetBigDefensiveSpellIDHash
    if type(getHash) ~= "function" then return lane end
    local spellIDs, spellIDSignature = getHash()
    if type(spellIDs) ~= "table" or not next(spellIDs) then return lane end

    local candidateFilters = {}
    for key, value in pairs(type(lane.candidateFilters) == "table" and lane.candidateFilters or {}) do
        candidateFilters[key] = value
    end
    candidateFilters.includeSpellIDs = spellIDs
    lane._msufA3BigDefensiveFilter = RemoveNativeFilterToken(lane.nativeFilter, "BIG_DEFENSIVE", "HELPFUL")
    lane._msufA3BigDefensiveCandidateFilters = candidateFilters
    lane._msufA3BigDefensiveCandidateSignature = lane.candidateFilterSignature
        and (lane.candidateFilterSignature .. ";" .. spellIDSignature) or spellIDSignature
    return lane
end

local function UnitCanAssistForAuraIdentity(unit)
    local unitCanAssist = _G.UnitCanAssist
    if type(unitCanAssist) ~= "function" then return nil end
    if type(_G.UnitIsPlayerControlledOrGroupMember) == "function" then
        -- Retail 12.1 added the same two identity flags AuraContainerUtil uses.
        return unitCanAssist("player", unit, true, true)
    end
    -- Classic-family clients still expose the historical two-argument API.
    return unitCanAssist("player", unit)
end

local function UnitSupportsCuratedBigDefensive(unit)
    unit = tostring(unit or "")
    if unit == "player" or unit:match("^party%d+$") or unit:match("^raid%d+$") then return true end
    if unit ~= "target" and unit ~= "focus" then return false end
    -- Match AuraContainerUtil's identity-candidate check: immunity and temporary
    -- interaction locks must not turn an otherwise friendly Unit into an
    -- unrestricted HELPFUL parse.
    local canAssist = UnitCanAssistForAuraIdentity(unit)
    if issecretvalue(canAssist) == true then return false end
    return canAssist == true
end

local function EffectiveLaneFilters(lane)
    if lane and lane._msufA3BigDefensiveFilter and UnitSupportsCuratedBigDefensive(lane.unit) then
        return lane._msufA3BigDefensiveFilter,
            lane._msufA3BigDefensiveCandidateFilters,
            lane._msufA3BigDefensiveCandidateSignature
    end
    return lane and lane.nativeFilter,
        lane and lane.candidateFilters,
        lane and lane.candidateFilterSignature
end
A3._EffectiveBigDefensiveLaneFilters = EffectiveLaneFilters

local function FinalizeLane(lane, appearanceKind)
    if lane then
        ConfigureCuratedBigDefensiveLane(lane)
        lane.appearanceKind = NormalizeAppearanceKind(appearanceKind or lane.appearanceKind or lane.kind)
        lane.iconStyle = SharedIconStyle(lane.appearanceKind)
        -- Aura visibility is lane-local. The global Unitframe tooltip mode
        -- (Always/OOC/Modifier/Never) owns unit/group-frame mouseover only;
        -- native AuraButtons reuse just the compatible cursor placement and
        -- the shared Blizzard/MSUF look applied by ApplyAuraTooltipStyle().
        local general = _G.MSUF_DB and _G.MSUF_DB.general
        lane.auraTooltipAnchor = (general and general.unitTooltipAnchor == "CURSOR")
            and "ANCHOR_CURSOR" or "ANCHOR_BOTTOMRIGHT"
        lane._msufA3TrackingSignature = LaneTrackingSignature(lane)
        lane._msufA3StructuralSignature = LaneStructuralSignature(lane)
        lane._msufA3LayoutSignature = LaneLayoutSignature(lane)
    end
    return lane
end

local function NativeFilter(baseFilter, filters)
    filters = type(filters) == "table" and filters or nil
    local filter = tostring(baseFilter or "")
    local helpful = filter:find("HELPFUL", 1, true) ~= nil
    local harmful = filter:find("HARMFUL", 1, true) ~= nil
    if filters and filters.enabled ~= false then
        local playerScoped = filters.onlyMine == true
        if filters.exclusive == "raid" then filter = filter .. "|RAID" end
        if filters.raid == true then filter = filter .. "|RAID" end
        if filters.includeNameplateOnly == true then filter = filter .. "|INCLUDE_NAME_PLATE_ONLY" end
        if filters.cancelable == true and helpful then filter = filter .. "|CANCELABLE" end
        if filters.notCancelable == true and helpful then filter = filter .. "|!CANCELABLE" end
        if filters.raidInCombat == true then filter = filter .. "|RAID_IN_COMBAT" end
        if filters.includeDispellable == true then filter = filter .. "|RAID_PLAYER_DISPELLABLE" end
        if filters.dispellable == true then filter = filter .. "|RAID_PLAYER_DISPELLABLE" end
        if filters.dispellableAny == true then filter = filter .. "|DISPELLABLE" end
        if filters.onlyImportant == true then filter = filter .. "|IMPORTANT" end
        if filters.crowdControl == true and harmful then filter = filter .. "|CROWD_CONTROL" end
        if filters.externalDefensive == true and helpful then filter = filter .. "|EXTERNAL_DEFENSIVE" end
        if filters.bigDefensive == true and helpful then filter = filter .. "|BIG_DEFENSIVE" end
        if playerScoped then filter = filter .. "|PLAYER" end
    end
    local normalized = NormalizeNativeFilterString(filter, baseFilter)
    -- Cold-path safety net: MSUF's token whitelist normalizes user input, but
    -- Blizzard's validator is the final authority. A token Blizzard rejects
    -- would hard-assert inside AddAuraGroup and kill the lane, so fall back to
    -- the plain base filter instead and surface the reason.
    local auraUtil = _G.AuraUtil
    if auraUtil and type(auraUtil.IsValidFilterString) == "function"
        and auraUtil.IsValidFilterString(normalized) ~= true then
        A3._RecordNativeAuraRuntimeError("invalid native filter: " .. tostring(normalized))
        return NormalizeNativeFilterString(baseFilter, baseFilter)
    end
    return normalized
end

local function NormalizeDispelSensorTrigger(value, fallback)
    value = tostring(value or fallback or "BY_ME"):upper()
    if value == "BORDER" or value == "INHERIT" or value == "SAME" then return "BORDER" end
    if value == "BY_RAID" or value == "RAID" or value == "GROUP" or value == "BY_GROUP" then return "BY_RAID" end
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
    -- True any-debuff highlighting is not representable without reading aura
    -- payloads. Migrate the old UI value to PTR 5's exact type-only filter.
    if value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "DISPEL_TYPE" end
    if value == "PLAYER_CAST" or value == "CAST_BY_ME" or value == "MY_DEBUFF" then return "PLAYER_CAST" end
    return "BY_ME"
end

local function DispelSensorNativeFilter(trigger)
    trigger = NormalizeDispelSensorTrigger(trigger, "BY_ME")
    if trigger == "DISPEL_TYPE" then
        return "HARMFUL|DISPELLABLE", 3
    end
    if trigger == "BY_RAID" then
        return "HARMFUL|RAID_PLAYER_DISPELLABLE", 1
    end
    if trigger == "PLAYER_CAST" then
        return "HARMFUL|PLAYER", 3
    end
    return "HARMFUL|RAID", 1
end

return {
    AddHidePermanentCandidateFilter = AddHidePermanentCandidateFilter,
    AddMaxDurationCandidateFilter = AddMaxDurationCandidateFilter,
    AddNonPlayerCandidateFilter = AddNonPlayerCandidateFilter,
    ApplyAuraIconZoom = ApplyAuraIconZoom,
    AuraIconBaseOffset = AuraIconBaseOffset,
    ButtonAnchor = ButtonAnchor,
    CandidateFiltersFromBlacklist = CandidateFiltersFromBlacklist,
    CandidateFiltersFromBlacklistHash = CandidateFiltersFromBlacklistHash,
    CandidateFiltersFromIncludeAndExcludeSpellIDs = CandidateFiltersFromIncludeAndExcludeSpellIDs,
    CandidateFiltersFromSpellIDs = CandidateFiltersFromSpellIDs,
    DispelSensorNativeFilter = DispelSensorNativeFilter,
    EffectiveLaneFilters = EffectiveLaneFilters,
    EffectiveUnitBlacklist = EffectiveUnitBlacklist,
    EffectiveUnitTables = EffectiveUnitTables,
    EnsureDB = EnsureDB,
    FinalizeLane = FinalizeLane,
    GetAuraBorderOptions = GetAuraBorderOptions,
    GridShape = GridShape,
    GroupGrowthParts = GroupGrowthParts,
    GrowthParts = GrowthParts,
    IsGroupFrame = IsGroupFrame,
    NativeFilter = NativeFilter,
    NormalizeDebuffTypeBorderMode = NormalizeDebuffTypeBorderMode,
    NormalizeDispelSensorTrigger = NormalizeDispelSensorTrigger,
    NormalizeDurationBarDirection = NormalizeDurationBarDirection,
    NormalizeDurationBarDisplay = NormalizeDurationBarDisplay,
    NormalizeDurationBarPosition = NormalizeDurationBarPosition,
    NormalizeNativeFilterString = NormalizeNativeFilterString,
    NormalizeRuntimeUnit = NormalizeRuntimeUnit,
    ReadAnchor = ReadAnchor,
    ReadBool = ReadBool,
    ReadDebuffTypeBorderMode = ReadDebuffTypeBorderMode,
    ReadGroupDebuffTypeBorderMode = ReadGroupDebuffTypeBorderMode,
    ReadNumber = ReadNumber,
    ReadRaw = ReadRaw,
    ReadUnitLaneStyleAnchor = ReadUnitLaneStyleAnchor,
    ReadUnitLaneStyleBool = ReadUnitLaneStyleBool,
    ReadUnitLaneStyleNumber = ReadUnitLaneStyleNumber,
    ReadUnitLaneStyleRaw = ReadUnitLaneStyleRaw,
    ReadUnitStyleAnchor = ReadUnitStyleAnchor,
    ReadUnitStyleBool = ReadUnitStyleBool,
    ReadUnitStyleRaw = ReadUnitStyleRaw,
    SharedIconStyle = SharedIconStyle,
    UnitAuraIconsEnabled = UnitAuraIconsEnabled,
    UnitCanAssistForAuraIdentity = UnitCanAssistForAuraIdentity,
}
end
