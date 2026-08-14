--- Shell/Menu2/Assistant/MSUF_AssistantParser_Geometry.lua
--- Geometry/layout parser shard for natural-language frame edits.
---
--- Produces declarative move/size/anchor plans only; secure/combat-safe frame
--- application remains in the settings and edit-mode runtimes.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
local P = A.Parser or {}
A.Parser = P
local Data = A.ParserData or {}
A.ParserData = Data
local GeometryData = Data.GEOMETRY_PARSER or {}
local GeometryPhrases = GeometryData.PHRASES or {}
local Trim = P.Trim
local Normalize = P.Normalize
local HasPhrase = P.HasPhrase
local ContainsAny = P.ContainsAny
local UNIT_ORDER = P.UNIT_ORDER
local ALL_UNITFRAMES = P.ALL_UNITFRAMES
local ALL_GROUPS = P.ALL_GROUPS
local CLASS_POWER_TERMS = P.CLASS_POWER_TERMS
local AddUnique = P.AddUnique
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local DetectGlobalScope = P.DetectGlobalScope
local DetectBoolean = P.DetectBoolean
local FirstNumber = P.FirstNumber
local Compact = P.Compact
local DetectDirection = P.DetectDirection
local UnitPageKey = P.UnitPageKey
local RawAfterLastConnector = P.RawAfterLastConnector
local CleanCustomAnchorFrameName = P.CleanCustomAnchorFrameName
local RawCustomAnchorFrameName = P.RawCustomAnchorFrameName
local SettingMatchScore = P.SettingMatchScore
local EnumValueForText = P.EnumValueForText
local RelativeNumberDeltaForText = P.RelativeNumberDeltaForText

local HUMAN_ANCHOR_UNIT_TERMS = {
    targettarget = { "targettarget", "target of target", "tot", "ziel des ziels" },
    focustarget = { "focustarget", "focus target", "fokus ziel" },
    player = { "player", "player frame", "spieler", "spieler frame", "self", "ich" },
    target = { "target", "target frame", "ziel", "ziel frame" },
    focus = { "focus", "focus frame", "fokus", "fokus frame" },
    pet = { "pet", "pet frame", "begleiter", "begleiter frame" },
    boss = { "boss", "boss frame", "boss frames", "bossframe", "bossframes" },
}

local function UnitInHumanAnchorFragment(fragment)
    fragment = Normalize(fragment or "")
    if fragment == "" then return nil end
    for i = 1, #UNIT_ORDER do
        local unit = UNIT_ORDER[i]
        local terms = HUMAN_ANCHOR_UNIT_TERMS[unit] or { unit }
        for j = 1, #terms do
            if HasPhrase(fragment, terms[j]) then return unit end
        end
    end
    return nil
end

local function RelativeUnitAnchorFromText(text)
    text = Normalize(text)
    if text == "" then return nil, nil end
    local patterns = {
        "^.-%s+move%s+(.+)%s+below%s+(.+)$",
        "^.-%s+move%s+(.+)%s+under%s+(.+)$",
        "^.-%s+move%s+(.+)%s+beneath%s+(.+)$",
        "^.-%s+move%s+(.+)%s+above%s+(.+)$",
        "^.-%s+move%s+(.+)%s+over%s+(.+)$",
        "^.-%s+put%s+(.+)%s+below%s+(.+)$",
        "^.-%s+put%s+(.+)%s+under%s+(.+)$",
        "^.-%s+put%s+(.+)%s+next to%s+(.+)$",
        "^.-%s+place%s+(.+)%s+below%s+(.+)$",
        "^.-%s+place%s+(.+)%s+under%s+(.+)$",
        "^.-%s+place%s+(.+)%s+next to%s+(.+)$",
        "^.-%s+anchor%s+(.+)%s+to%s+(.+)$",
        "^.-%s+attach%s+(.+)%s+to%s+(.+)$",
        "^.-%s+dock%s+(.+)%s+to%s+(.+)$",
        "^.-%s+(.+)%s+below%s+(.+)$",
        "^.-%s+(.+)%s+under%s+(.+)$",
        "^.-%s+(.+)%s+next to%s+(.+)$",
        "^.-%s+(.+)%s+near%s+(.+)$",
    }
    for i = 1, #patterns do
        local before, after = text:match(patterns[i])
        local subject = UnitInHumanAnchorFragment(before)
        local anchor = UnitInHumanAnchorFragment(after)
        if subject and anchor and subject ~= anchor then return subject, anchor end
    end
    return nil, nil
end

local function BuildChanges(settings, value, relativeDelta, direction)
    local changes = {}
    for i = 1, #settings do
        changes[#changes + 1] = {
            setting = settings[i],
            value = value,
            relativeDelta = relativeDelta,
            direction = direction,
        }
    end
    return changes
end

-- Copying ONE dimension from another frame ("the same width as the target
-- frame"). Kept beside the both-dimension patterns inside the shortcut below,
-- which only ever matched requests naming the whole size.
local SINGLE_DIMENSION_MATCH_PATTERNS = {
    { dimension = "width",
        "^(.-)%s+the same width as%s+(.+)$",
        "^(.-)%s+same width as%s+(.+)$",
        "^(.-)%s+as wide as%s+(.+)$",
        "^(.-)%s+gleiche breite wie%s+(.+)$",
        "^(.-)%s+so breit wie%s+(.+)$" },
    { dimension = "height",
        "^(.-)%s+the same height as%s+(.+)$",
        "^(.-)%s+same height as%s+(.+)$",
        "^(.-)%s+as tall as%s+(.+)$",
        "^(.-)%s+as high as%s+(.+)$",
        "^(.-)%s+gleiche hoehe wie%s+(.+)$",
        "^(.-)%s+so hoch wie%s+(.+)$" },
}

function P.ParseUnitSizeMatchShortcut(text)
    -- "Make player as big as target" depends on current live setting values. Read them here
    -- to build an explicit width/height plan, then let the router apply the change normally.
    if not ContainsAny(text, GeometryPhrases[1]) then
        return nil
    end
    if DetectGroups(text)[1] or ContainsAny(text, GeometryPhrases[2]) then
        return nil
    end

    local unitTerms = {
        targettarget = { "targettarget", "target of target", "tot", "ziel des ziels" },
        focustarget = { "focustarget", "focus target", "fokus ziel" },
        player = { "player", "player frame", "spieler", "spieler frame", "self", "ich" },
        target = { "target", "target frame", "ziel", "ziel frame" },
        focus = { "focus", "focus frame", "fokus", "fokus frame" },
        pet = { "pet", "pet frame", "begleiter", "begleiter frame" },
        boss = { "boss", "boss frame", "boss frames", "bossframe", "bossframes" },
    }
    local function unitInFragment(fragment)
        fragment = Normalize(fragment or "")
        if fragment == "" then return nil end
        for i = 1, #UNIT_ORDER do
            local unit = UNIT_ORDER[i]
            local terms = unitTerms[unit] or { unit }
            for j = 1, #terms do
                if HasPhrase(fragment, terms[j]) then return unit end
            end
        end
        return nil
    end
    local target, source
    local patterns = {
        "^(.-)%s+as big as%s+(.+)$",
        "^(.-)%s+the same size as%s+(.+)$",
        "^(.-)%s+same size as%s+(.+)$",
        "^(.-)%s+same width and height as%s+(.+)$",
        "^(.-)%s+so gross wie%s+(.+)$",
        "^(.-)%s+gleich gross wie%s+(.+)$",
        "^(.-)%s+gleiche groesse wie%s+(.+)$",
        "^(.-)%s+dieselbe groesse wie%s+(.+)$",
    }
    for i = 1, #patterns do
        local before, after = text:match(patterns[i])
        target = unitInFragment(before)
        source = unitInFragment(after)
        if target and source and target ~= source then break end
        target, source = nil, nil
    end

    -- The patterns above match BOTH dimensions at once. A request naming a
    -- single one ("make the focus frame the same width as the target frame")
    -- matched none of them and fell through to a generic "I'm not confident
    -- enough to guess" -- even though it is the most precise form of the
    -- request, because it says exactly which value to copy and from where.
    local matchDimension
    if not target or not source then
        for i = 1, #SINGLE_DIMENSION_MATCH_PATTERNS do
            local entry = SINGLE_DIMENSION_MATCH_PATTERNS[i]
            for j = 1, #entry do
                local before, after = text:match(entry[j])
                if before then
                    local candidateTarget, candidateSource = unitInFragment(before), unitInFragment(after)
                    if candidateTarget and candidateSource and candidateTarget ~= candidateSource then
                        target, source, matchDimension = candidateTarget, candidateSource, entry.dimension
                        break
                    end
                end
            end
            if matchDimension then break end
        end
    end
    if not target or not source then return nil end

    if matchDimension then
        local setting = Registry and Registry:GetSetting(target .. "." .. matchDimension)
        local sourceSetting = Registry and Registry:GetSetting(source .. "." .. matchDimension)
        local sourceValue = sourceSetting and type(sourceSetting.get) == "function"
            and tonumber(sourceSetting.get()) or nil
        if not setting or sourceValue == nil then return nil end
        return {
            kind = "changes",
            changes = { { setting = setting, value = sourceValue, valueLabel = tostring(sourceValue) } },
            label = "Match unit frame " .. matchDimension,
            summary = "Sets one unit frame dimension to another unit frame's current value.",
            compoundComplete = true,
        }
    end

    local widthSetting = Registry and Registry:GetSetting(target .. ".width")
    local heightSetting = Registry and Registry:GetSetting(target .. ".height")
    if not widthSetting or not heightSetting then return nil end

    local sourceWidth = Registry and Registry:GetSetting(source .. ".width")
    sourceWidth = sourceWidth and type(sourceWidth.get) == "function" and tonumber(sourceWidth.get()) or nil
    local sourceHeight = Registry and Registry:GetSetting(source .. ".height")
    sourceHeight = sourceHeight and type(sourceHeight.get) == "function" and tonumber(sourceHeight.get()) or nil
    if sourceWidth == nil or sourceHeight == nil then return nil end

    return {
        kind = "changes",
        changes = {
            { setting = widthSetting, value = sourceWidth, valueLabel = tostring(sourceWidth) },
            { setting = heightSetting, value = sourceHeight, valueLabel = tostring(sourceHeight) },
        },
        label = "Match unit frame size",
        summary = "Sets the target unit frame width and height to the current source unit frame size.",
        bulkSafe = true,
        compoundComplete = true,
    }
end

local function ParseUnsupportedDetailShortcut(text)
    if ContainsAny(text, GeometryPhrases[3]) then
        return {
            kind = "unknown",
            text = "Combat Timer supports enable, size, position, anchor, lock, and colors in MSUF, but not opacity.",
            status = "failed",
        }
    end
    return nil
end

local function CurrentPageUnit()
    -- Commands issued from a unit page can omit the unit name. This keeps the assistant
    -- ergonomic without making global pages guess at a target frame.
    local page = M and M.activeKey
    if type(page) ~= "string" then return nil end
    for i = 1, #ALL_UNITFRAMES do
        local unit = ALL_UNITFRAMES[i]
        if UnitPageKey(unit) == page then return unit end
    end
    return nil
end

local function DetailUnitsOrCurrentPage(text)
    local units = DetectUnits(text)
    if #units > 0 then return units, false end
    local pageUnit = CurrentPageUnit()
    if pageUnit then return { pageUnit }, false end
    return {}, true
end

local function BuildUnitDetailChoices(attr, value, relativeDelta, direction)
    local settings = {}
    for i = 1, #ALL_UNITFRAMES do
        local setting = Registry and Registry:GetSetting(tostring(ALL_UNITFRAMES[i]) .. "." .. attr)
        if setting then settings[#settings + 1] = setting end
    end
    return {
        kind = "ambiguous",
        choices = BuildChanges(settings, value, relativeDelta, direction),
        label = "Multiple matching unit frame detail options",
    }
end

local function HasAllUnitDetailScopeIntent(text)
    return ContainsAny(text, GeometryPhrases[4])
end

local function AllUnitDetailUnits()
    local units = {}
    for i = 1, #ALL_UNITFRAMES do units[#units + 1] = ALL_UNITFRAMES[i] end
    return units
end

local function ParsePortraitDetailShortcut(text)
    if not ContainsAny(text, GeometryPhrases[5]) then return nil end
    if ContainsAny(text, GeometryPhrases[6]) then return nil end
    if ContainsAny(text, GeometryPhrases[7]) then return nil end
    if ContainsAny(text, GeometryPhrases[8]) and DetectDirection(text, {}) then return nil end
    local hasPanX = HasPhrase(text, "portrait zoom center x") or HasPhrase(text, "portrait pan x")
        or HasPhrase(text, "group frame portrait zoom center x") or HasPhrase(text, "group frame portrait pan x")
    local hasPanY = HasPhrase(text, "portrait zoom center y") or HasPhrase(text, "portrait pan y")
        or HasPhrase(text, "group frame portrait zoom center y") or HasPhrase(text, "group frame portrait pan y")
    local hasX = not hasPanX and (ContainsAny(text, GeometryPhrases[9]) or HasPhrase(text, "x"))
    local hasY = not hasPanY and (ContainsAny(text, GeometryPhrases[10]) or HasPhrase(text, "y"))
    if hasX and hasY then
        local numberCount = 0
        for _ in Normalize(text):gmatch("[-+]?%d+%.?%d*") do numberCount = numberCount + 1 end
        if numberCount >= 2 then return nil end
    end

    local attr
    local value
    local relativeDelta
    local direction

    if hasPanX then
        attr = "portraitPanX"
        value = FirstNumber(text)
    elseif hasPanY then
        attr = "portraitPanY"
        value = FirstNumber(text)
    elseif hasX then
        attr = "portraitOffsetX"
        value = FirstNumber(text)
    elseif hasY then
        attr = "portraitOffsetY"
        value = FirstNumber(text)
    elseif ContainsAny(text, GeometryPhrases[11]) then
        -- Portrait packs are media values, not free-form strings. Let the
        -- registry/media resolver translate display labels to their stable
        -- stored keys (for example Blizzard Class Icon -> BLIZZARD).
        return nil
    elseif ContainsAny(text, GeometryPhrases[13]) and not ContainsAny(text, GeometryPhrases[14]) then
        attr = "portraitRender"
        if ContainsAny(text, GeometryPhrases[15]) then
            value = "2D"
        elseif ContainsAny(text, GeometryPhrases[16]) then
            value = "CLASS"
        end
    elseif ContainsAny(text, GeometryPhrases[17]) then
        attr = "portraitShape"
        if ContainsAny(text, GeometryPhrases[18]) then
            value = "SQUARE"
        elseif ContainsAny(text, GeometryPhrases[19]) then
            value = "ROUNDED"
        elseif ContainsAny(text, GeometryPhrases[20]) then
            value = "CIRCLE"
        elseif ContainsAny(text, GeometryPhrases[21]) then
            value = "DIAMOND"
        elseif ContainsAny(text, GeometryPhrases[286]) then
            value = "BLIZZARD"
        end
    elseif ContainsAny(text, GeometryPhrases[22]) then
        attr = "portraitFillBorder"
        value = DetectBoolean(text)
        if value == nil and ContainsAny(text, GeometryPhrases[23]) then value = true end
    elseif ContainsAny(text, GeometryPhrases[24]) then
        attr = "portraitBgEnabled"
        value = DetectBoolean(text)
    elseif ContainsAny(text, GeometryPhrases[25]) then
        attr = "portraitBorderThickness"
        relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 1)
        if relativeDelta == nil then value = FirstNumber(text) end
    elseif ContainsAny(text, GeometryPhrases[26]) then
        attr = "portraitZoom"
        relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 10)
        if relativeDelta == nil then
            value = FirstNumber(text)
            if type(value) == "number" and value > 1 and value <= 2 then value = value * 100 end
        end
    elseif ContainsAny(text, GeometryPhrases[27]) then
        attr = "portraitSizeOverride"
        relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 4)
        if relativeDelta == nil then value = FirstNumber(text) end
    elseif ContainsAny(text, GeometryPhrases[28]) then
        attr = "portraitBorderStyle"
        if ContainsAny(text, GeometryPhrases[29]) then
            value = "NONE"
        elseif ContainsAny(text, GeometryPhrases[30]) then
            value = "SOLID"
        elseif ContainsAny(text, GeometryPhrases[31]) then
            value = "CLASS_COLOR"
        elseif ContainsAny(text, GeometryPhrases[32]) then
            value = "REACTION"
        elseif ContainsAny(text, GeometryPhrases[33]) then
            value = "CUSTOM"
        end
    else
        if ContainsAny(text, {
            "cast spell icon", "portrait cast icon", "portrait spell icon",
            "portrait width", "portrait height", "portrait placement",
            "portrait anchor", "attach to frame point", "detached portrait",
            "overlay alignment", "overlay align", "portrait layer", "portrait frame level",
            "portrait opacity", "portrait alpha", "portrait transparency",
            "portrait border color", "portrait border opacity", "portrait border alpha",
            "portrait border art", "portrait border direction", "portrait border rotation",
            "portrait background color", "portrait background opacity", "portrait background alpha",
        }) then
            return nil
        end
        attr = "portraitMode"
        if ContainsAny(text, GeometryPhrases[34]) then
            value = "OFF"
        elseif ContainsAny(text, GeometryPhrases[35]) then
            value = "RIGHT"
        elseif ContainsAny(text, GeometryPhrases[36]) then
            value = "LEFT"
        end
    end

    if not attr or (value == nil and relativeDelta == nil) then return nil end
    local explicitGroups = DetectGroups(text)
    local explicitUnits = DetectUnits(text)
    if #explicitGroups > 0 and #explicitUnits == 0 then
        local changes = {}
        for i = 1, #explicitGroups do
            local setting = Registry and Registry:GetSetting("gf_" .. tostring(explicitGroups[i]) .. "." .. attr)
            if setting then
                changes[#changes + 1] = {
                    setting = setting,
                    value = value,
                    relativeDelta = relativeDelta,
                    direction = direction,
                }
            end
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            label = "Group Frame Portrait detail",
            bulkSafe = #changes > 1,
            summary = "Changes a Group Frame portrait detail option.",
        }
    end

    local units, ambiguous
    if HasAllUnitDetailScopeIntent(text) then
        units = AllUnitDetailUnits()
        ambiguous = false
    else
        units, ambiguous = DetailUnitsOrCurrentPage(text)
    end
    if ambiguous then return BuildUnitDetailChoices(attr, value, relativeDelta, direction) end
    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Portrait detail",
        bulkSafe = #changes > 1,
        summary = "Changes a portrait detail option.",
    }
end

local DETAIL_MOVE_SPECS = {
    { terms = { "portrait" }, x = "portraitOffsetX", y = "portraitOffsetY", label = "Move portrait" },
    { terms = { "name text", "frame name text", "unit name text", "unitframe name", "unit name", "name label", "name labels", "names", "name" }, x = "nameOffsetX", y = "nameOffsetY", label = "Move name text" },
    { terms = { "hp text", "health text", "health value", "hp value", "hp number", "health number", "hp label", "health label", "life text", "hp", "health", "leben", "gesundheit", "lebenspunkte", "lebensanzeige" }, x = "hpOffsetX", y = "hpOffsetY", label = "Move HP text" },
    { terms = { "power text", "mana text", "power value", "mana value", "power number", "mana number", "power label", "mana label", "energie text", "energie", "ressource", "ressourcen", "power", "mana" }, x = "powerOffsetX", y = "powerOffsetY", label = "Move power text" },
}

-- Detail movement is registry-driven: the parser finds which text/portrait detail was named
-- and maps the movement onto the corresponding X/Y attributes.
local GROUP_DETAIL_MOVE_SPECS = {
    { terms = { "name text", "frame name text", "unit name text", "unit name", "frame name", "name label", "name labels", "party name", "raid name", "group name", "names", "name" }, x = "nameOffsetX", y = "nameOffsetY", label = "Move group name text" },
    { terms = { "hp text", "health text", "health value", "hp value", "hp number", "health number", "hp label", "health label", "life text", "party hp", "party health", "raid hp", "raid health", "group hp", "group health", "hp", "health", "leben", "gesundheit", "lebenspunkte", "lebensanzeige" }, x = "hpOffsetX", y = "hpOffsetY", label = "Move group HP text" },
    { terms = { "power text", "mana text", "power value", "mana value", "power number", "mana number", "power label", "mana label", "energie text", "energie", "ressource", "ressourcen", "party power", "party mana", "raid power", "raid mana", "group power", "group mana", "power", "mana" }, x = "powerOffsetX", y = "powerOffsetY", label = "Move group power text" },
}

local OM = A._OffsetMoveHelpers or {}
A._OffsetMoveHelpers = OM

-- Offset parsing is called from several feature shortcuts. Keep the parsed text caches small
-- and local to this helper bundle; they are query accelerators, not persistent state.
OM.moveTerms = OM.moveTerms or {
    "move", "nudge", "shift", "verschiebe", "offset", "x offset", "y offset",
    "x position", "y position", "x pos", "y pos",
    "closer", "nearer", "farther", "further", "away from",
    "naeher", "weiter weg", "ran", "heran",
}

OM.excludeTerms = OM.excludeTerms or {
    "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    "cooldown spiral", "cooldown text", "stack text",
}

OM.closerTerms = OM.closerTerms or { "closer", "nearer", "naeher", "ran", "heran" }
OM.fartherTerms = OM.fartherTerms or { "farther", "further", "away from", "weiter weg" }

function OM.HasIntent(text)
    if ContainsAny(text, OM.excludeTerms) then return false end
    if ContainsAny(text, OM.moveTerms) then return true end
    return false
end

function OM.Clean(text)
    local raw = tostring(text or "")
    OM.cleanCache = OM.cleanCache or {}
    OM.cleanCacheOrder = OM.cleanCacheOrder or {}
    local cached = OM.cleanCache[raw]
    if cached then return cached end
    text = Normalize(raw)
    text = text:gsub("[^%w%s]", " ")
    text = Trim(text:gsub("%s+", " "))
    if raw ~= "" and #raw <= 320 then
        if not OM.cleanCache[raw] then OM.cleanCacheOrder[#OM.cleanCacheOrder + 1] = raw end
        OM.cleanCache[raw] = text
        while #OM.cleanCacheOrder > 1024 do
            local oldKey = table.remove(OM.cleanCacheOrder, 1)
            OM.cleanCache[oldKey] = nil
        end
    end
    return text
end

function OM.AxislessPhrase(text)
    local raw = tostring(text or "")
    OM.axislessCache = OM.axislessCache or {}
    OM.axislessCacheOrder = OM.axislessCacheOrder or {}
    local cached = OM.axislessCache[raw]
    if cached then return cached end
    text = " " .. OM.Clean(raw) .. " "
    text = text:gsub(" x ", " ")
    text = text:gsub(" y ", " ")
    text = text:gsub(" offset ", " ")
    text = text:gsub(" position ", " ")
    text = text:gsub(" pos ", " ")
    text = Trim(text:gsub("%s+", " "))
    if raw ~= "" and #raw <= 320 then
        if not OM.axislessCache[raw] then OM.axislessCacheOrder[#OM.axislessCacheOrder + 1] = raw end
        OM.axislessCache[raw] = text
        while #OM.axislessCacheOrder > 1024 do
            local oldKey = table.remove(OM.axislessCacheOrder, 1)
            OM.axislessCache[oldKey] = nil
        end
    end
    return text
end

function OM.RootDetailBlocked(setting, text)
    local attr = tostring(setting and setting.attribute or "")
    if attr ~= "offsetX" and attr ~= "offsetY" then return false end
    local label = OM.Clean(tostring(setting and setting.label or ""))
    for _, term in ipairs({
        "name", "health", "hp", "power", "mana", "portrait", "icon", "label", "text",
        "ready check", "group number", "raid marker", "kick", "interrupt", "status", "indicator",
        "leben", "gesundheit", "lebenspunkte", "lebensanzeige", "energie", "ressource", "ressourcen",
    }) do
        if ContainsAny(text, GeometryPhrases[37]) and not HasPhrase(label, term) then return true end
    end
    return false
end

function OM.ScopeBlocked(setting, text)
    if type(setting) ~= "table" then return true end
    local frameType = tostring(setting.frameType or "")
    -- For offset settings, broad words like "name" or "power" are not enough; explicit
    -- unit/group scope still wins so a party command cannot drift onto player text offsets.
    if frameType == "group" then
        local wanted
        if HasPhrase(text, "mythicraid") or HasPhrase(text, "mythic raid") then
            wanted = "mythicraid"
        elseif HasPhrase(text, "party") then
            wanted = "party"
        elseif HasPhrase(text, "raid") then
            wanted = "raid"
        end
        if wanted then return tostring(setting.unit or OM.UnitFromSetting(setting) or "") ~= wanted end
        return false
    end
    local units = DetectUnits(text)
    if #units == 0 then return false end
    local unit = tostring(setting.unit or OM.UnitFromSetting(setting) or "")
    if unit == "" or unit == "global" then return false end
    for i = 1, #units do
        if units[i] == unit then return false end
    end
    return true
end

function OM.PhraseScore(cleanText, phrase)
    phrase = OM.AxislessPhrase(phrase)
    if #phrase < 3 then return 0 end
    if HasPhrase(cleanText, phrase) then return #Compact(phrase) end
    local matched = 0
    for token in phrase:gmatch("%S+") do
        if #token >= 2 then
            if not HasPhrase(cleanText, token) then return 0 end
            matched = matched + 1
        end
    end
    return matched > 1 and #Compact(phrase) or 0
end

function OM.Axis(setting)
    if type(setting) ~= "table" or setting.type ~= "number" then return nil end
    local key = tostring(setting.key or "")
    local attr = tostring(setting.attribute or "")
    local label = tostring(setting.label or "")
    local hay = (key .. " " .. attr .. " " .. label):lower()
    if hay:find("offsetx", 1, true)
        or hay:find(" offset x", 1, true)
        or hay:find(" x offset", 1, true)
        or hay:find(" x position", 1, true)
        or hay:find("x pos", 1, true)
        or ((key:match("X$") or attr:match("X$")) and hay:find("offset", 1, true))
    then
        return "x"
    end
    if hay:find("offsety", 1, true)
        or hay:find(" offset y", 1, true)
        or hay:find(" y offset", 1, true)
        or hay:find(" y position", 1, true)
        or hay:find("y pos", 1, true)
        or ((key:match("Y$") or attr:match("Y$")) and hay:find("offset", 1, true))
    then
        return "y"
    end
    return nil
end

function OM.IsNonAuraSetting(setting)
    if type(setting) ~= "table" then return false end
    local frameType = tostring(setting.frameType or "")
    if frameType == "aura" or frameType == "groupAura" then return false end
    local key = tostring(setting.key or ""):lower()
    local label = tostring(setting.label or ""):lower()
    local category = tostring(setting.category or ""):lower()
    if key:find("aura", 1, true) or label:find("aura", 1, true) or category:find("aura", 1, true) then return false end
    return OM.Axis(setting) ~= nil
end

function OM.RegisteredSettings()
    if not (Registry and type(Registry.AllSettings) == "function") then return {} end
    local settings = Registry:AllSettings()
    local count = #(settings or {})
    if OM.cache and OM.cacheCount == count then return OM.cache end
    local out = {}
    local byAxisUnit = {}
    for i = 1, count do
        local setting = settings[i]
        local axis = OM.Axis(setting)
        if axis and OM.IsNonAuraSetting(setting) then
            local row = { setting = setting, axis = axis }
            out[#out + 1] = row
            local unit = tostring(OM.UnitFromSetting(setting) or "")
            if unit ~= "" then
                local key = axis .. ":" .. unit
                byAxisUnit[key] = byAxisUnit[key] or {}
                byAxisUnit[key][#byAxisUnit[key] + 1] = row
            end
        end
    end
    OM.cache = out
    OM.cacheByAxisUnit = byAxisUnit
    OM.cacheCount = count
    return out
end

function OM.AxisForDirection(direction)
    if direction == "left" or direction == "right" then return "x" end
    if direction == "up" or direction == "down" then return "y" end
    return nil
end

function OM.SignedDelta(text, direction, fallback)
    local amount = FirstNumber(text) or fallback or 10
    if direction == "left" or direction == "down" then amount = -amount end
    return amount
end

OM.unitRootFrameDetailTerms = OM.unitRootFrameDetailTerms or {
    "name", "name text", "hp", "health", "hp text", "health text", "power", "mana", "power text", "mana text",
    "portrait", "castbar", "cast bar", "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    "bar", "health bar", "power bar", "mana bar", "border", "outline", "icon", "label", "text",
    "ready check", "raid marker", "status", "indicator", "combat", "resting", "leader", "assist",
    "level", "level indicator", "level text", "pvp", "pvp flag", "pvp icon",
    "leben", "gesundheit", "lebenspunkte", "lebensanzeige", "energie", "ressource", "ressourcen",
}

function OM.UnitRootFrameMoveScopes(text)
    local units = DetectUnits(text)
    if #units > 0 then return units end
    if HasAllUnitDetailScopeIntent(text)
        and ContainsAny(text, GeometryPhrases[38])
        and not ContainsAny(text, GeometryPhrases[39])
    then
        return AllUnitDetailUnits()
    end
    local pageUnit = CurrentPageUnit()
    if pageUnit then return { pageUnit } end
    return {}
end

function OM.RootXYValues(text)
    local norm = Normalize(text)
    if DetectDirection(norm, {}) then return nil end
    local xPos = norm:find("%f[%w]x%f[%W]")
    local yPos = norm:find("%f[%w]y%f[%W]")
    if not xPos or not yPos then return nil end
    local numbers = {}
    for value in norm:gmatch("[-+]?%d+%.?%d*") do
        numbers[#numbers + 1] = tonumber(value)
        if #numbers >= 2 then break end
    end
    if numbers[1] == nil or numbers[2] == nil then return nil end
    if xPos < yPos then
        return { x = numbers[1], y = numbers[2] }
    end
    return { x = numbers[2], y = numbers[1] }
end

function OM.ParseUnitFrameRootMove(text)
    if ContainsAny(text, OM.unitRootFrameDetailTerms) then return nil end
    if not ContainsAny(text, GeometryPhrases[40]) then return nil end

    local horizontalDirection = HasPhrase(text, "left") or HasPhrase(text, "right")
    local verticalDirection = HasPhrase(text, "up") or HasPhrase(text, "down")
    if horizontalDirection and verticalDirection then
        local numberCount = 0
        for _ in Normalize(text):gmatch("[-+]?%d+%.?%d*") do numberCount = numberCount + 1 end
        -- Let DirectionPairs in the compound parser preserve both directional
        -- amounts. The single-axis shortcut below intentionally handles only
        -- one direction and would otherwise discard the second movement.
        if numberCount >= 2 then return nil end
    end

    local units = OM.UnitRootFrameMoveScopes(text)
    if #units == 0 then return nil end

    local xy = OM.RootXYValues(text)
    if xy then
        local changes = {}
        for i = 1, #units do
            local unit = tostring(units[i])
            local xSetting = Registry and Registry:GetSetting(unit .. ".offsetX")
            local ySetting = Registry and Registry:GetSetting(unit .. ".offsetY")
            if xSetting then changes[#changes + 1] = { setting = xSetting, value = xy.x, direction = "x" } end
            if ySetting then changes[#changes + 1] = { setting = ySetting, value = xy.y, direction = "y" } end
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            label = "Move unit frame",
            bulkSafe = #changes > 1,
            compoundComplete = true,
            summary = "Moves the unit frame X/Y position.",
        }
    end

    local direction = DetectDirection(text, {})
    local axis = OM.AxisForDirection(direction) or A._DetailOffsetAxis(text)
    local value
    local relativeDelta
    if direction then
        relativeDelta = OM.SignedDelta(text, direction, 10)
    elseif axis then
        value = FirstNumber(text)
        if value == nil then return nil end
    else
        return nil
    end

    local attr = axis == "y" and "offsetY" or "offsetX"
    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
                relativeDelta = relativeDelta,
                direction = direction or axis,
            }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Move unit frame",
        bulkSafe = #changes > 1,
        summary = "Moves the unit frame X/Y position.",
    }
end

function OM.ReadValue(setting)
    if setting and type(setting.get) == "function" then
        return setting.get()
    end
    return nil
end

function OM.UnitFromSetting(setting)
    local unit = setting and setting.unit
    if type(unit) == "string" and unit ~= "" and unit ~= "global" then return unit end
    local key = tostring(setting and setting.key or "")
    local prefix = key:match("^([^%.]+)")
    if prefix == "gf_party" then return "party" end
    if prefix == "gf_raid" then return "raid" end
    if prefix == "gf_mythicraid" then return "mythicraid" end
    return prefix
end

function OM.PortraitCloserDelta(setting, text)
    if not ContainsAny(text, OM.closerTerms) and not ContainsAny(text, OM.fartherTerms) then return nil end
    if not setting or tostring(setting.attribute or "") ~= "portraitOffsetX" then return nil end
    local unit = OM.UnitFromSetting(setting)
    local modeSetting = unit and Registry and Registry:GetSetting(tostring(unit) .. ".portraitMode")
    local mode = tostring(OM.ReadValue(modeSetting) or "LEFT")
    local leftSide = mode ~= "RIGHT"
    local closer = ContainsAny(text, OM.closerTerms)
    local amount = FirstNumber(text) or 10
    local delta = closer and (leftSide and amount or -amount) or (leftSide and -amount or amount)
    return delta, delta >= 0 and "right" or "left"
end

function OM.Score(row, text, axis)
    if not row or not row.setting or row.axis ~= axis then return 0 end
    if OM.ScopeBlocked(row.setting, text) then return 0 end
    if OM.RootDetailBlocked(row.setting, text) then return 0 end
    local suffix = axis == "x" and " x offset" or " y offset"
    local score = SettingMatchScore and SettingMatchScore(row.setting, text .. suffix) or 0
    if score == 0 then
        suffix = axis == "x" and " x position" or " y position"
        score = SettingMatchScore and SettingMatchScore(row.setting, text .. suffix) or 0
    end
    if score and score > 0 then return score end

    local cleanText = OM.Clean(text)
    local best = 0
    local aliases = row.setting.aliases or {}
    for i = 1, #aliases do
        local len = OM.PhraseScore(cleanText, aliases[i])
        if len > best then best = len end
    end
    if row.setting.matchLabel ~= false and row.setting.label then
        local len = OM.PhraseScore(cleanText, row.setting.label)
        if len > best then best = len end
    end
    return best
end

function OM.BestRows(text, axis)
    local rows = OM.RegisteredSettings()
    local scopedRows = {}
    local function addScoped(scope)
        local list = OM.cacheByAxisUnit and OM.cacheByAxisUnit[axis .. ":" .. tostring(scope or "")]
        for i = 1, #(list or {}) do scopedRows[#scopedRows + 1] = list[i] end
    end
    local units = DetectUnits(text)
    for i = 1, #units do addScoped(units[i]) end
    local groups = DetectGroups(text)
    for i = 1, #groups do addScoped(groups[i]) end
    if #scopedRows > 0 then rows = scopedRows end
    local best = 0
    local matches = {}
    for i = 1, #rows do
        local row = rows[i]
        local score = OM.Score(row, text, axis)
        if score > best then
            best = score
            matches = { row }
        elseif score > 0 and score == best then
            matches[#matches + 1] = row
        end
    end
    return matches, best
end

function OM.ExplicitMultiIntent(text)
    if HasAllUnitDetailScopeIntent(text) then return true end
    return #DetectUnits(text) + #DetectGroups(text) > 1
end

function OM.CurrentPageUnitRows(rows, text)
    if #(rows or {}) <= 1 or #DetectUnits(text) > 0 or HasAllUnitDetailScopeIntent(text) then return rows end
    local pageUnit = CurrentPageUnit()
    if not pageUnit then return rows end
    local filtered = {}
    for i = 1, #rows do
        local setting = rows[i] and rows[i].setting
        if tostring(setting and setting.frameType or "") ~= "unitframe" then return rows end
        if tostring(setting and setting.unit or OM.UnitFromSetting(setting) or "") == pageUnit then
            filtered[#filtered + 1] = rows[i]
        end
    end
    return #filtered > 0 and filtered or rows
end

local function ParseGenericOffsetMove(text)
    if not OM.HasIntent(text) then return nil end
    if text:find("focus kick", 1, true)
        and (text:find("tracker", 1, true) or text:find("icon", 1, true))
    then
        return nil
    end

    local direction = DetectDirection(text, {})
    local axis = OM.AxisForDirection(direction) or A._DetailOffsetAxis(text)
    local value
    local relativeDelta

    if direction then
        relativeDelta = OM.SignedDelta(text, direction, 10)
    elseif axis then
        value = FirstNumber(text)
        if value == nil then return nil end
    elseif ContainsAny(text, OM.closerTerms) or ContainsAny(text, OM.fartherTerms) then
        axis = "x"
    else
        return nil
    end

    local rows = {}
    local score = 0
    if axis then
        rows, score = OM.BestRows(text, axis)
        rows = OM.CurrentPageUnitRows(rows, text)
    end
    if score <= 0 or #rows == 0 then return nil end

    local changes = {}
    for i = 1, #rows do
        local setting = rows[i].setting
        local delta = relativeDelta
        local moveDirection = direction or axis
        if delta == nil and value == nil then
            delta, moveDirection = OM.PortraitCloserDelta(setting, text)
        end
        if value ~= nil or delta ~= nil then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
                relativeDelta = delta,
                direction = moveDirection,
            }
        end
    end
    if #changes == 0 then return nil end

    if #changes > 1 and not OM.ExplicitMultiIntent(text) then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Which position offset do you want me to move?",
            summary = "The request matched more than one non-Aura X/Y offset.",
        }
    end

    return {
        kind = "changes",
        changes = changes,
        label = "Move position offset",
        bulkSafe = #changes > 1,
        summary = "Moves the matching non-Aura X/Y offset option.",
    }
end

local function ParseUnitDetailMove(text)
    if ContainsAny(text, GeometryPhrases[41]) then return nil end
    if ContainsAny(text, GeometryPhrases[42]) then return nil end
    if not ContainsAny(text, GeometryPhrases[43]) then return nil end
    local direction = DetectDirection(text, {})
    if not direction then return nil end
    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then
            units = { pageUnit }
        else
            return nil
        end
    end
    local spec
    for i = 1, #DETAIL_MOVE_SPECS do
        if ContainsAny(text, DETAIL_MOVE_SPECS[i].terms) then
            spec = DETAIL_MOVE_SPECS[i]
            break
        end
    end
    if not spec then return nil end
    local attr = (direction == "left" or direction == "right") and spec.x or spec.y
    local amount = FirstNumber(text) or 10
    if direction == "left" or direction == "down" then amount = -amount end
    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = spec.label,
        summary = "Moves a unit frame detail option by pixels.",
    }
end

local function GroupScopesOrCurrentPage(text)
    local groups = DetectGroups(text)
    if #groups > 0 then return groups end
    local page = M and M.activeKey
    if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
        if M and (M.gfScope == "party" or M.gfScope == "raid" or M.gfScope == "mythicraid") then return { M.gfScope } end
        return { "party" }
    end
    return {}
end

function P.UnitPowerBarIsDetached(unit)
    local setting = Registry and Registry:GetSetting(tostring(unit or "") .. ".powerBarDetached")
    if setting and type(setting.get) == "function" then
        return setting.get() == true
    end
    return false
end

function P.ParseDetachedPowerBarMoveShortcut(text)
    if ContainsAny(text, GeometryPhrases[44]) then return nil end
    if ContainsAny(text, CLASS_POWER_TERMS) then return nil end
    if #DetectGroups(text) > 0 then return nil end
    if ContainsAny(text, GeometryPhrases[45]) then
        return nil
    end
    if not ContainsAny(text, GeometryPhrases[46]) then
        return nil
    end

    local direction = DetectDirection(text, {})
    local axis = OM.AxisForDirection(direction) or A._DetailOffsetAxis(text)
    if not direction and not axis then
        if ContainsAny(text, GeometryPhrases[47]) and (P.CooldownManagerAnchorValueForText(text) ~= nil or ContainsAny(text, GeometryPhrases[48])) then
            return {
                kind = "answer",
                status = "info",
                text = "Detached Power Bars use X/Y offsets instead of direct anchors. I can move one with requests like: move target detached power bar left 10; move target detached power bar up 4. To anchor the whole Target frame to Cooldown Manager, ask for 'anchor target to Cooldown Manager'.",
                summary = "Detached Power Bars move with offsets instead of direct anchors.",
            }
        end
        return nil
    end

    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then units = { pageUnit } end
    end
    if #units == 0 then return nil end

    local explicitDetached = ContainsAny(text, GeometryPhrases[49])
    local attr = axis == "y" and "detachedPowerBarOffsetY" or "detachedPowerBarOffsetX"
    local relativeDelta
    local value
    if direction then
        relativeDelta = OM.SignedDelta(text, direction, 10)
    else
        value = FirstNumber(text)
        if value == nil then return nil end
    end

    local changes = {}
    local skippedAttached = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        if explicitDetached or P.UnitPowerBarIsDetached(unit) then
            local setting = Registry and Registry:GetSetting(unit .. "." .. attr)
            if setting then
                changes[#changes + 1] = {
                    setting = setting,
                    value = value,
                    relativeDelta = relativeDelta,
                    direction = direction or axis,
                }
            end
        else
            skippedAttached[#skippedAttached + 1] = unit
        end
    end
    if #changes == 0 then
        local labels = A.UnitLabels or {}
        local unitLabel = labels[skippedAttached[1]] or skippedAttached[1] or "that unit"
        return {
            kind = "unknown",
            text = tostring(unitLabel) .. " Power Bar is attached to the unit frame, so the bar itself has no separate position. Detach it first, or say 'move " .. tostring(unitLabel):lower() .. " power text left' to move only the text.",
            status = "failed",
        }
    end
    return {
        kind = "changes",
        changes = changes,
        label = "Move detached Power Bar",
        bulkSafe = #changes > 1,
        summary = "Moves the Detached Power Bar X/Y offset options when the unit power bar is detached.",
    }
end

function P.PairwiseFrameSpacingMode(text)
    if ContainsAny(text, GeometryPhrases[50]) then return nil end
    if ContainsAny(text, CLASS_POWER_TERMS) then return nil end
    if ContainsAny(text, GeometryPhrases[51]) then
        return "closer"
    end
    if ContainsAny(text, GeometryPhrases[52]) then
        return "apart"
    end
    return nil
end

function P.PairwiseFrameSpacingTargets(text)
    local units = DetectUnits(text)
    local groups = DetectGroups(text)
    if #units == 2 and #groups == 0 then
        return "unit", { units[1], units[2] }
    end
    if #groups == 2 and #units == 0 then
        return "group", { groups[1], groups[2] }
    end
    return nil, nil
end

function P.PairwiseFrameSpacingAxis(text, firstSettingX, firstSettingY, secondSettingX, secondSettingY)
    if ContainsAny(text, GeometryPhrases[53]) then return "x" end
    if ContainsAny(text, GeometryPhrases[54]) then return "y" end
    local x1 = tonumber(OM.ReadValue(firstSettingX)) or 0
    local x2 = tonumber(OM.ReadValue(secondSettingX)) or 0
    local y1 = tonumber(OM.ReadValue(firstSettingY)) or 0
    local y2 = tonumber(OM.ReadValue(secondSettingY)) or 0
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    if dx == 0 and dy == 0 then return nil end
    if dx >= dy then return "x" end
    return "y"
end

function P.PairwiseFrameSpacingDirection(delta)
    if delta == nil then return nil end
    if delta > 0 then return "right" end
    if delta < 0 then return "left" end
    return nil
end

function P.PairwiseFrameSpacingChangeFor(kind, name, axis, delta)
    local prefix = kind == "group" and ("gf_" .. tostring(name)) or tostring(name)
    local attr = axis == "y" and "offsetY" or "offsetX"
    local setting = Registry and Registry:GetSetting(prefix .. "." .. attr)
    if not setting then return nil end
    return {
        setting = setting,
        relativeDelta = delta,
        direction = axis == "y" and (delta >= 0 and "up" or "down") or P.PairwiseFrameSpacingDirection(delta),
    }
end

function P.ParsePairwiseFrameSpacingShortcut(text)
    local mode = P.PairwiseFrameSpacingMode(text)
    if not mode then return nil end
    local kind, names = P.PairwiseFrameSpacingTargets(text)
    if not kind or not names or #names ~= 2 or names[1] == names[2] then return nil end

    local prefix1 = kind == "group" and ("gf_" .. tostring(names[1])) or tostring(names[1])
    local prefix2 = kind == "group" and ("gf_" .. tostring(names[2])) or tostring(names[2])
    local firstX = Registry and Registry:GetSetting(prefix1 .. ".offsetX")
    local firstY = Registry and Registry:GetSetting(prefix1 .. ".offsetY")
    local secondX = Registry and Registry:GetSetting(prefix2 .. ".offsetX")
    local secondY = Registry and Registry:GetSetting(prefix2 .. ".offsetY")
    if not (firstX and firstY and secondX and secondY) then return nil end

    local axis = P.PairwiseFrameSpacingAxis(text, firstX, firstY, secondX, secondY)
    if not axis then return nil end
    local firstValue = tonumber(OM.ReadValue(axis == "y" and firstY or firstX)) or 0
    local secondValue = tonumber(OM.ReadValue(axis == "y" and secondY or secondX)) or 0
    local diff = secondValue - firstValue
    if diff == 0 then return nil end

    local amount = FirstNumber(text) or 10
    if mode == "closer" then
        local half = math.abs(diff) / 2
        if amount > half then amount = half end
    end
    if amount == 0 then return nil end

    local sign = diff > 0 and 1 or -1
    local firstDelta
    local secondDelta
    if mode == "closer" then
        firstDelta = sign * amount
        secondDelta = -sign * amount
    else
        firstDelta = -sign * amount
        secondDelta = sign * amount
    end

    local firstChange = P.PairwiseFrameSpacingChangeFor(kind, names[1], axis, firstDelta)
    local secondChange = P.PairwiseFrameSpacingChangeFor(kind, names[2], axis, secondDelta)
    if not firstChange or not secondChange then return nil end
    return {
        kind = "changes",
        changes = { firstChange, secondChange },
        label = mode == "closer" and "Move frames closer together" or "Move frames farther apart",
        bulkSafe = true,
        compoundComplete = true,
        summary = "Moves two frame root offsets along their strongest separation axis.",
    }
end

function P.ParseBossFrameSpacingShortcut(text)
    if ContainsAny(text, GeometryPhrases[55]) then return nil end
    if ContainsAny(text, CLASS_POWER_TERMS) then return nil end
    if not ContainsAny(text, GeometryPhrases[56]) then return nil end

    local mode
    if ContainsAny(text, GeometryPhrases[57]) then
        mode = "closer"
    elseif ContainsAny(text, GeometryPhrases[58]) or (ContainsAny(text, GeometryPhrases[59]) and ContainsAny(text, GeometryPhrases[60])) then
        mode = "apart"
    else
        return nil
    end

    local setting = Registry and Registry:GetSetting("boss.spacing")
    if not setting then return nil end
    local amount = FirstNumber(text) or 10
    if mode == "apart" then amount = -amount end
    return {
        kind = "changes",
        changes = {
            {
                setting = setting,
                relativeDelta = amount,
                direction = mode == "closer" and "closer" or "apart",
            },
        },
        label = mode == "closer" and "Move boss frames closer together" or "Move boss frames farther apart",
        summary = "Adjusts boss-frame stack spacing.",
    }
end

function P.ParseGroupFrameSpacingShortcut(text)
    if ContainsAny(text, GeometryPhrases[61]) then return nil end
    if ContainsAny(text, CLASS_POWER_TERMS) then return nil end
    if ContainsAny(text, GeometryPhrases[62]) then
        return nil
    end

    local mode
    if ContainsAny(text, GeometryPhrases[63]) then
        mode = "closer"
    elseif ContainsAny(text, GeometryPhrases[64]) or (ContainsAny(text, GeometryPhrases[65]) and ContainsAny(text, GeometryPhrases[66])) then
        mode = "apart"
    else
        return nil
    end

    local groups = DetectGroups(text)
    if #groups == 0 then groups = GroupScopesOrCurrentPage(text) end
    if #groups ~= 1 then return nil end

    local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[1]) .. ".spacing")
    if not setting then return nil end
    local amount = FirstNumber(text) or 1
    if mode == "closer" then amount = -amount end
    return {
        kind = "changes",
        changes = {
            {
                setting = setting,
                relativeDelta = amount,
                direction = mode == "closer" and "decrease" or "increase",
            },
        },
        label = mode == "closer" and "Reduce group frame spacing" or "Increase group frame spacing",
        summary = "Adjusts group-frame layout spacing.",
    }
end

function P.CooldownManagerAnchorValueForText(text)
    if ContainsAny(text, GeometryPhrases[67]) then
        return "UtilityCooldownViewer"
    end
    if ContainsAny(text, GeometryPhrases[68]) then
        return "BuffIconCooldownViewer"
    end
    if ContainsAny(text, GeometryPhrases[69]) then
        return "EssentialCooldownViewer"
    end
    return nil
end

local HUMAN_ANCHOR_FRAME_NAME_CONNECTORS = {
    " to ", " near ", " next to ", " under ", " below ", " above ", " over ",
    " toward ", " towards ", " by ",
}

local function HumanAnchorFrameNameForText(text, raw)
    local cooldownFrame = P.CooldownManagerAnchorValueForText(text)
    if cooldownFrame then return cooldownFrame end
    local frameName
    if RawAfterLastConnector then
        frameName = RawAfterLastConnector(raw or text, HUMAN_ANCHOR_FRAME_NAME_CONNECTORS)
    end
    if not frameName and RawCustomAnchorFrameName then
        frameName = RawCustomAnchorFrameName(raw or text)
    end
    if CleanCustomAnchorFrameName then frameName = CleanCustomAnchorFrameName(frameName) end
    if frameName == "" then return nil end
    if type(frameName) ~= "string" or frameName == "" then return nil end
    if frameName:find("%s") then return nil end
    return frameName
end

local function BroadHumanAnchorAnswer(frameName)
    local target = frameName == "EssentialCooldownViewer" and "Cooldown Manager" or tostring(frameName or "that frame")
    return {
        kind = "answer",
        status = "info",
        text = table.concat({
            "I can anchor real MSUF frame families, but 'all frames' is too broad to change safely.",
            "Use a concrete target, for example: anchor unit frames to " .. target .. "; anchor party and raid frames to " .. target .. "; anchor class resources to " .. target .. ".",
        }, "\n"),
        summary = "Asks for a concrete frame anchor target.",
    }
end

function P.ParseBroadHumanAnchorTargetAnswer(text, raw)
    local externalFrameName = HumanAnchorFrameNameForText(text, raw)
    if externalFrameName == nil then return nil end
    if ContainsAny(text, GeometryPhrases[70])
        and ContainsAny(text, GeometryPhrases[71])
    then
        local target = externalFrameName == "EssentialCooldownViewer" and "Cooldown Manager" or tostring(externalFrameName)
        return {
            kind = "answer",
            status = "info",
            text = table.concat({
                tostring(target) .. " is an external custom anchor target, not a separate MSUF options page.",
                "Use a concrete MSUF frame request, for example: anchor target to " .. tostring(target) .. "; anchor player and target to " .. tostring(target) .. "; open target custom anchor picker.",
            }, "\n"),
            summary = "Shows how custom anchor frame names work.",
        }
    end
    local attachIntent = ContainsAny(text, GeometryPhrases[72]) or (HasPhrase(text, "anchor") and HasPhrase(text, "to"))
        or (HasPhrase(text, "attach") and HasPhrase(text, "to"))
        or (HasPhrase(text, "dock") and HasPhrase(text, "to"))
        or (HasPhrase(text, "snap") and HasPhrase(text, "to"))
    if not attachIntent then return nil end
    if #DetectUnits(text) > 0 or #DetectGroups(text) > 0 then return nil end
    if ContainsAny(text, GeometryPhrases[73]) then return nil end
    if not ContainsAny(text, GeometryPhrases[74]) then return nil end
    return BroadHumanAnchorAnswer(externalFrameName)
end

function P.ParseHumanAnchorTarget(text, raw)
    if ContainsAny(text, GeometryPhrases[75]) then return nil end
    if ContainsAny(text, GeometryPhrases[76]) then
        return nil
    end
    local externalFrameName = HumanAnchorFrameNameForText(text, raw)
    local attachIntent = ContainsAny(text, GeometryPhrases[77]) or (HasPhrase(text, "anchor") and HasPhrase(text, "to"))
        or (HasPhrase(text, "attach") and HasPhrase(text, "to"))
        or (HasPhrase(text, "dock") and HasPhrase(text, "to"))
        or (HasPhrase(text, "snap") and HasPhrase(text, "to"))
        or (externalFrameName ~= nil and HasPhrase(text, "use") and HasPhrase(text, "anchor"))
        or (externalFrameName ~= nil
            and ContainsAny(text, GeometryPhrases[78])
            and ContainsAny(text, GeometryPhrases[79]))
    local detachIntent = ContainsAny(text, GeometryPhrases[80])
    if not attachIntent and not detachIntent then return nil end

    local units = DetectUnits(text)
    local groups = DetectGroups(text)
    local explicitAnchorSubject, explicitAnchorValue = RelativeUnitAnchorFromText(text)
    if explicitAnchorSubject and explicitAnchorValue and not detachIntent then
        units = { explicitAnchorSubject }
    end
    local unitframeScope = ContainsAny(text, GeometryPhrases[81])
    if #units == 0 and #groups == 0 and not unitframeScope and externalFrameName ~= nil
        and ContainsAny(text, GeometryPhrases[82])
    then
        return BroadHumanAnchorAnswer(externalFrameName)
    end
    local unitPage = CurrentPageUnit()
    if #groups == 0 and (#units > 0 or unitframeScope or unitPage) then
        local probeUnit = (units and units[1]) or unitPage or "player"
        local valueSetting = Registry and Registry:GetSetting(tostring(probeUnit) .. ".anchorToUnitframe")
        if unitframeScope and #units == 0 then
            units = ALL_UNITFRAMES
        elseif #units == 0 and unitPage then
            units = { unitPage }
        end
        local enumValue = valueSetting and EnumValueForText(valueSetting, text)
        local cooldownValue = P.CooldownManagerAnchorValueForText(text)
        local value = detachIntent and "GLOBAL" or explicitAnchorValue or enumValue or cooldownValue
        if value ~= nil and #units == 1 and value == units[1] and cooldownValue then
            value = cooldownValue
        end
        local selfAnchor = value ~= nil and #units == 1 and value == units[1]
        if (value == nil or (selfAnchor and externalFrameName ~= nil and externalFrameName ~= units[1])) and externalFrameName ~= nil then
            local changes = {}
            for i = 1, #units do
                local setting = Registry and Registry:GetSetting(tostring(units[i]) .. ".anchorFrameName")
                if setting then changes[#changes + 1] = { setting = setting, value = externalFrameName } end
            end
            if #changes == 0 then return nil end
            return {
                kind = "changes",
                changes = changes,
                label = "Set unit custom anchor frame",
                bulkSafe = #changes > 1,
                compoundComplete = true,
                summary = "Sets the unit frame custom anchor from placement wording.",
            }
        end
        if value == nil then return nil end
        if #units == 1 and value == units[1] then return nil end
        if #units > 1 and (value == "player" or value == "target" or value == "targettarget" or value == "focustarget" or value == "focus" or value == "pet" or value == "boss") then
            local filtered = {}
            for i = 1, #units do
                if units[i] ~= value then filtered[#filtered + 1] = units[i] end
            end
            if #filtered > 0 then units = filtered end
        end
        local changes = {}
        for i = 1, #units do
            local setting = Registry and Registry:GetSetting(tostring(units[i]) .. ".anchorToUnitframe")
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            label = detachIntent and "Detach unit frame anchor target" or "Set unit frame anchor target",
            bulkSafe = #changes > 1,
            compoundComplete = true,
            summary = "Applies the unit frame Anchor To option for placement wording.",
        }
    end

    if #groups == 0 then
        groups = GroupScopesOrCurrentPage(text)
    end
    if #groups == 0 then return nil end
    local groupAnchorValue
    if detachIntent then
        groupAnchorValue = "FREE"
    else
        local probeGroup = groups[1] or "party"
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(probeGroup) .. ".anchorToFrame")
        groupAnchorValue = setting and EnumValueForText(setting, text)
    end

    local changes = {}
    if groupAnchorValue ~= nil then
        for i = 1, #groups do
            local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. ".anchorToFrame")
            if setting then changes[#changes + 1] = { setting = setting, value = groupAnchorValue } end
        end
    else
        local frameName = externalFrameName
        if not frameName then return nil end
        for i = 1, #groups do
            local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. ".customAnchorFrame")
            if setting then changes[#changes + 1] = { setting = setting, value = frameName } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = detachIntent and "Detach group frame anchor target" or "Set group frame anchor target",
        bulkSafe = #changes > 1,
        compoundComplete = true,
        summary = "Interprets human placement wording as the Group Layout anchor options.",
    }
end

function P.GroupScaleWordPlayerCountForText(text)
    local norm = Normalize(text):gsub("%-", " ")
    local counts = {
        { "forty", 40 }, { "thirty", 30 }, { "twenty nine", 29 }, { "twenty eight", 28 },
        { "twenty seven", 27 }, { "twenty six", 26 }, { "twenty five", 25 },
        { "twenty four", 24 }, { "twenty three", 23 }, { "twenty two", 22 },
        { "twenty one", 21 }, { "twenty", 20 }, { "nineteen", 19 }, { "eighteen", 18 },
        { "seventeen", 17 }, { "sixteen", 16 }, { "fifteen", 15 }, { "fourteen", 14 },
        { "thirteen", 13 }, { "twelve", 12 }, { "eleven", 11 }, { "ten", 10 },
        { "nine", 9 }, { "eight", 8 }, { "seven", 7 }, { "six", 6 }, { "five", 5 },
        { "four", 4 }, { "three", 3 }, { "two", 2 }, { "one", 1 },
    }
    local units = {
        "players", "player", "raiders", "raider", "people", "person",
        "raid members", "raid member", "members", "member",
        "player group", "player raid", "man raid", "m raid", "man",
    }
    local haystack = " " .. norm .. " "
    for i = 1, #counts do
        local phrase, value = counts[i][1], counts[i][2]
        for j = 1, #units do
            if haystack:find(" " .. phrase .. " " .. units[j] .. " ", 1, true) then return value end
        end
    end
    return nil
end

function P.GroupScaleWordValueForText(text)
    local norm = Normalize(text):gsub("%-", " ")
    local values = {
        { "one hundred", 100 }, { "hundred", 100 }, { "ninety five", 95 }, { "ninety", 90 },
        { "eighty five", 85 }, { "eighty", 80 }, { "seventy five", 75 }, { "seventy", 70 },
        { "sixty five", 65 }, { "sixty", 60 }, { "fifty five", 55 }, { "fifty", 50 },
    }
    local haystack = " " .. norm .. " "
    for i = 1, #values do
        local phrase, value = values[i][1], values[i][2]
        if haystack:find(" to " .. phrase .. " ", 1, true)
            or haystack:find(" at " .. phrase .. " percent ", 1, true)
            or haystack:find(" " .. phrase .. " percent ", 1, true)
            or haystack:find(" " .. phrase .. " scale ", 1, true)
            or haystack:find(" " .. phrase .. " scaling ", 1, true)
        then
            return value
        end
    end
    return nil
end

function P.GroupScaleBreakpointAttrForText(text)
    if ContainsAny(text, GeometryPhrases[83]) then
        return "scaleOver25", 26
    end
    local norm = Normalize(text):gsub("%-", " ")
    local number =
        norm:match("when%s+there%s+are%s+(%d+)%s+players")
        or norm:match("when%s+there%s+are%s+(%d+)%s+raiders")
        or norm:match("when%s+there%s+are%s+(%d+)%s+people")
        or norm:match("when%s+there%s+are%s+(%d+)%s+persons")
        or norm:match("when%s+there%s+are%s+(%d+)%s+raid%s+members")
        or norm:match("when%s+there%s+are%s+(%d+)%s+members")
        or norm:match("when%s+there%s+is%s+(%d+)%s+player")
        or norm:match("when%s+there%s+is%s+(%d+)%s+raider")
        or norm:match("when%s+there%s+is%s+(%d+)%s+person")
        or norm:match("when%s+there%s+is%s+(%d+)%s+raid%s+member")
        or norm:match("when%s+there%s+is%s+(%d+)%s+member")
        or norm:match("when%s+we%s+are%s+(%d+)")
        or norm:match("when%s+we%s+have%s+(%d+)")
        or norm:match("when%s+our%s+group%s+is%s+(%d+)")
        or norm:match("when%s+our%s+raid%s+is%s+(%d+)")
        or norm:match("when%s+(%d+)%s+players")
        or norm:match("when%s+(%d+)%s+player")
        or norm:match("when%s+(%d+)%s+raiders")
        or norm:match("when%s+(%d+)%s+raider")
        or norm:match("when%s+(%d+)%s+people")
        or norm:match("when%s+(%d+)%s+person")
        or norm:match("when%s+(%d+)%s+raid%s+members")
        or norm:match("when%s+(%d+)%s+raid%s+member")
        or norm:match("when%s+(%d+)%s+members")
        or norm:match("when%s+(%d+)%s+member")
        or norm:match("with%s+(%d+)%s+players")
        or norm:match("with%s+(%d+)%s+player")
        or norm:match("with%s+(%d+)%s+raiders")
        or norm:match("with%s+(%d+)%s+raider")
        or norm:match("with%s+(%d+)%s+people")
        or norm:match("with%s+(%d+)%s+person")
        or norm:match("with%s+(%d+)%s+raid%s+members")
        or norm:match("with%s+(%d+)%s+raid%s+member")
        or norm:match("with%s+(%d+)%s+members")
        or norm:match("with%s+(%d+)%s+member")
        or norm:match("with%s+us%s+at%s+(%d+)")
        or norm:match("with%s+the%s+group%s+at%s+(%d+)")
        or norm:match("with%s+the%s+raid%s+at%s+(%d+)")
        or norm:match("with%s+a%s+(%d+)%s+player%s+group")
        or norm:match("with%s+(%d+)%s+player%s+group")
        or norm:match("if%s+we%s+are%s+(%d+)")
        or norm:match("if%s+we%s+have%s+(%d+)")
        or norm:match("if%s+our%s+group%s+is%s+(%d+)")
        or norm:match("if%s+our%s+raid%s+is%s+(%d+)")
        or norm:match("for%s+(%d+)%s+players")
        or norm:match("for%s+(%d+)%s+player")
        or norm:match("for%s+(%d+)%s+raiders")
        or norm:match("for%s+(%d+)%s+raider")
        or norm:match("for%s+(%d+)%s+people")
        or norm:match("for%s+(%d+)%s+person")
        or norm:match("for%s+(%d+)%s+raid%s+members")
        or norm:match("for%s+(%d+)%s+raid%s+member")
        or norm:match("for%s+(%d+)%s+members")
        or norm:match("for%s+(%d+)%s+member")
        or norm:match("for%s+a%s+(%d+)%s+player%s+group")
        or norm:match("for%s+(%d+)%s+player%s+group")
        or norm:match("for%s+a%s+(%d+)%s+player%s+raid")
        or norm:match("for%s+(%d+)%s+player%s+raid")
        or norm:match("for%s+a%s+(%d+)%s+man%s+raid")
        or norm:match("for%s+(%d+)%s+man%s+raid")
        or norm:match("for%s+a%s+(%d+)%s*m%s+raid")
        or norm:match("for%s+(%d+)%s*m%s+raid")
        or norm:match("for%s+a%s+(%d+)%s*man%s+raid")
        or norm:match("for%s+(%d+)%s*man%s+raid")
        or norm:match("for%s+(%d+)%s*m%f[%W]")
        or norm:match("for%s+(%d+)%s*man%f[%W]")
        or norm:match("for%s+(%d+)%s*%+%s+players")
        or norm:match("for%s+(%d+)%s*%+%s+people")
        or norm:match("for%s+(%d+)%s*%+%s+raiders")
        or norm:match("for%s+(%d+)%s*%+%s+members")
        or norm:match("at%s+(%d+)%s+players")
        or norm:match("at%s+(%d+)%s+player")
        or norm:match("at%s+(%d+)%s+raiders")
        or norm:match("at%s+(%d+)%s+raider")
        or norm:match("at%s+(%d+)%s+people")
        or norm:match("at%s+(%d+)%s+person")
        or norm:match("at%s+(%d+)%s+raid%s+members")
        or norm:match("at%s+(%d+)%s+raid%s+member")
        or norm:match("at%s+(%d+)%s+members")
        or norm:match("at%s+(%d+)%s+member")
        or norm:match("raid%s+of%s+(%d+)")
        or norm:match("(%d+)%s+players")
        or norm:match("(%d+)%s+player%s+group")
        or norm:match("(%d+)%s+player%s+raid")
        or norm:match("(%d+)%s+raiders")
        or norm:match("(%d+)%s+raider")
        or norm:match("(%d+)%s+people")
        or norm:match("(%d+)%s+person")
        or norm:match("(%d+)%s+raid%s+members")
        or norm:match("(%d+)%s+raid%s+member")
        or norm:match("(%d+)%s+members")
        or norm:match("(%d+)%s+member")
        or norm:match("(%d+)%s+man%s+raid")
        or norm:match("(%d+)%s*m%s+raid")
        or norm:match("(%d+)%s*man%s+raid")
        or norm:match("(%d+)%s+man")
        or norm:match("(%d+)%s*m%f[%W]")
        or norm:match("(%d+)%s*man%f[%W]")
        or norm:match("(%d+)%s*%+%s+players")
        or norm:match("(%d+)%s*%+%s+people")
        or norm:match("(%d+)%s*%+%s+raiders")
        or norm:match("(%d+)%s*%+%s+members")
        or norm:match("scale%s+at%s+(%d+)")
        or norm:match("scaling%s+at%s+(%d+)")
    number = tonumber(number)
    if number == nil then
        number = P.GroupScaleWordPlayerCountForText(text)
    end
    if number == nil then
        if ContainsAny(text, GeometryPhrases[84]) then return "scaleAt10", 10 end
        if ContainsAny(text, GeometryPhrases[85]) then return "scaleAt20", 20 end
        if ContainsAny(text, GeometryPhrases[86]) then return "scaleAt25", 25 end
        return nil
    end
    if number <= 10 then return "scaleAt10", number end
    if number <= 20 then return "scaleAt20", number end
    if number <= 25 then return "scaleAt25", number end
    return "scaleOver25", number
end

function P.GroupScaleValueForText(text, playerCount)
    local norm = Normalize(text)
    local value =
        norm:match("scale%s+to%s+(%d+%.?%d*)")
        or norm:match("scaling%s+to%s+(%d+%.?%d*)")
        or norm:match("to%s+(%d+%.?%d*)%s*%%?%s+scale")
        or norm:match("to%s+(%d+%.?%d*)%s*$")
        or norm:match("(%d+%.?%d*)%s*%%?%s+scale")
        or norm:match("(%d+%.?%d*)%s*%%?%s+scaling")
    value = tonumber(value)
    if value ~= nil then return value end
    if ContainsAny(text, GeometryPhrases[87]) then
        return 100
    end
    value = P.GroupScaleWordValueForText(text)
    if value ~= nil then return value end
    if P.GroupScaleRelativeDeltaForText and P.GroupScaleRelativeDeltaForText(text) ~= nil then return nil end
    local fallback
    for token in norm:gmatch("%d+%.?%d*") do
        local number = tonumber(token)
        if number and (not playerCount or math.abs(number - playerCount) > 0.0001) then
            fallback = number
        end
    end
    return fallback
end

function P.GroupScaleRelativeDeltaForText(text)
    local direction
    if ContainsAny(text, GeometryPhrases[88]) then
        direction = -1
    elseif ContainsAny(text, GeometryPhrases[89]) then
        direction = 1
    end
    if not direction then return nil end

    local norm = Normalize(text)
    local amount = tonumber(norm:match("by%s+([-+]?%d+%.?%d*)"))
        or tonumber(norm:match("um%s+([-+]?%d+%.?%d*)"))
    if not amount then
        if ContainsAny(text, GeometryPhrases[90]) then
            amount = 2
        elseif ContainsAny(text, GeometryPhrases[91]) then
            amount = 10
        else
            amount = 5
        end
    end
    return direction * math.abs(amount)
end

local GROUP_SCALE_BREAKPOINT_LABELS = {
    scaleAt10 = "1-10 players",
    scaleAt20 = "11-20 players",
    scaleAt25 = "21-25 players",
    scaleOver25 = "26+ players",
}

local function GroupScaleMissingValueAnswer(groups, attr, playerCount)
    local scope = groups and groups[1] or nil
    local label = (P.FrameResizeGroupLabel and P.FrameResizeGroupLabel(scope)) or tostring(scope or "Group")
    local breakpoint = GROUP_SCALE_BREAKPOINT_LABELS[attr] or "that player count"
    local targetText = playerCount
        and ("at " .. tostring(playerCount) .. " players (" .. tostring(breakpoint) .. " breakpoint)")
        or ("for " .. tostring(breakpoint))
    local scopeText = scope == "mythicraid" and "mythic raid" or (scope or "raid")
    return table.concat({
        "Group frame scaling breakpoints",
        "I can change " .. tostring(label) .. " scaling " .. targetText .. ". Use a target percent, or say whether to make it larger or smaller.",
        "Examples: set " .. tostring(scopeText) .. " scale for 20 players to 80; make " .. tostring(scopeText) .. " frames smaller when 20 people; increase " .. tostring(scopeText) .. " scale for 20m by 5.",
    }, "\n")
end

function P.ParseGroupScaleBreakpointShortcut(text)
    if ContainsAny(text, GeometryPhrases[92]) then return nil end
    if not ContainsAny(text, GeometryPhrases[93]) then
        return nil
    end
    local attr, playerCount = P.GroupScaleBreakpointAttrForText(text)
    if not attr then return nil end
    local groups = DetectGroups(text)
    if #groups == 0 then groups = GroupScopesOrCurrentPage(text) end
    if #groups == 0 then return nil end
    local value = P.GroupScaleValueForText(text, playerCount)
    local relativeDelta
    if value == nil then
        relativeDelta = P.GroupScaleRelativeDeltaForText(text)
        if relativeDelta == nil then
            return {
                kind = "answer",
                status = "info",
                text = GroupScaleMissingValueAnswer(groups, attr, playerCount),
                summary = "Asks which group player-count scale value to use.",
            }
        end
    end
    local changes = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        local setting = Registry and Registry:GetSetting("gf_" .. scope .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
        local modeSetting = Registry and Registry:GetSetting("gf_" .. scope .. ".frameScaleMode")
        if modeSetting then changes[#changes + 1] = { setting = modeSetting, value = "auto" } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = value == nil and "Adjust group frame player-count scale" or "Set group frame player-count scale",
        bulkSafe = #changes > 1,
        compoundComplete = true,
        summary = "Adjusts group-frame player-count scaling.",
    }
end

function P.GroupGrowthDirectionForText(text)
    if ContainsAny(text, GeometryPhrases[94]) then
        return "RIGHT"
    end
    if ContainsAny(text, GeometryPhrases[95]) then
        return "LEFT"
    end
    if ContainsAny(text, GeometryPhrases[96]) then
        return "DOWN"
    end
    if ContainsAny(text, GeometryPhrases[97]) then
        return "UP"
    end
    return nil
end

function P.ParseGroupGrowthDirectionShortcut(text)
    if ContainsAny(text, GeometryPhrases[98]) then return nil end
    if not ContainsAny(text, GeometryPhrases[99]) then return nil end
    local groups = DetectGroups(text)
    if #groups == 0 then groups = GroupScopesOrCurrentPage(text) end
    if #groups == 0 then return nil end
    local value = P.GroupGrowthDirectionForText(text)
    if not value then return nil end
    local changes = {}
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. ".growth")
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set group frame growth direction",
        bulkSafe = #changes > 1,
        summary = "Changes group-frame growth direction.",
    }
end

function P.GroupPowerBarSizeDelta(text, direction)
    local amount = FirstNumber(text)
    if not amount then
        if ContainsAny(text, GeometryPhrases[100]) then
            amount = 3
        else
            amount = 1
        end
    end
    amount = tonumber(amount) or 0
    if direction == "decrease" then amount = -amount end
    return amount
end

function P.ParseGroupPowerBarSizeShortcut(text)
    if not ContainsAny(text, GeometryPhrases[101]) then return nil end
    if ContainsAny(text, GeometryPhrases[102]) then
        return nil
    end
    local groups = DetectGroups(text)
    if #groups == 0 then groups = GroupScopesOrCurrentPage(text) end
    if #groups == 0 then return nil end

    local direction
    local widthIntent
    if ContainsAny(text, GeometryPhrases[103]) then
        widthIntent = true
        direction = "increase"
    elseif ContainsAny(text, GeometryPhrases[104]) then
        widthIntent = true
        direction = "decrease"
    elseif ContainsAny(text, GeometryPhrases[105]) then
        direction = "increase"
    elseif ContainsAny(text, GeometryPhrases[106]) then
        direction = "decrease"
    end

    if widthIntent then
        local label = groups[1] == "mythicraid" and "Mythic Raid" or ((P.FrameResizeGroupLabel and P.FrameResizeGroupLabel(groups[1])) or tostring(groups[1] or "Group"))
        return {
            kind = "answer",
            status = "info",
            text = tostring(label) .. " Power Bar width follows the group frame width. To make the Power Bar wider, resize the " .. tostring(label):lower() .. " frame width. To change only the Power Bar thickness, say 'set " .. tostring(label):lower() .. " power bar height to 5'.",
            summary = "Group Power Bars follow the group frame width.",
        }
    end

    local value
    if ContainsAny(text, GeometryPhrases[107]) then
        value = P.PowerBarSizeExactValue and P.PowerBarSizeExactValue(text, "height") or nil
    end
    if not direction and value == nil then return nil end

    local changes = {}
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. ".powerHeight")
        if setting then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
                relativeDelta = value == nil and P.GroupPowerBarSizeDelta(text, direction) or nil,
                direction = direction,
            }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Resize group Power Bar",
        bulkSafe = #changes > 1,
        summary = "Adjusts group Power Bar height.",
    }
end

P.GROUP_ROOT_FRAME_DETAIL_TERMS = {
    "name", "name text", "hp", "health", "hp text", "health text", "power", "mana", "power text", "mana text", "text slot",
    "status", "status text", "status icon", "indicator", "icon", "ready check", "raid marker",
    "summon", "resurrect", "resurrection", "ghost", "dead", "afk", "dnd", "group number",
    "pvp", "pvp flag",
    "aura", "auras", "buff", "buffs", "debuff", "debuffs", "castbar", "cast bar", "portrait",
    "bar", "health bar", "power bar", "mana bar", "border", "outline",
}

function P.ParseGroupFrameRootMove(text)
    if ContainsAny(text, P.GROUP_ROOT_FRAME_DETAIL_TERMS) then return nil end
    if not ContainsAny(text, GeometryPhrases[108]) then return nil end
    local groups = GroupScopesOrCurrentPage(text)
    if #groups == 0 then return nil end

    local direction = DetectDirection(text, {})
    local axis = OM.AxisForDirection(direction) or A._DetailOffsetAxis(text)
    local value
    local relativeDelta

    if direction then
        relativeDelta = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then relativeDelta = -relativeDelta end
    elseif axis then
        value = FirstNumber(text)
        if value == nil then return nil end
    else
        return nil
    end

    local attr = axis == "y" and "offsetY" or "offsetX"
    local changes = {}
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. attr)
        if setting then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
                relativeDelta = relativeDelta,
                direction = direction or axis,
            }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Move group frame",
        bulkSafe = #changes > 1,
        summary = "Moves the Group Frame root X/Y position options.",
    }
end

P.FRAME_RESIZE_INCREASE_TERMS = {
    "bigger", "larger", "grow", "make bigger", "make larger", "increase size",
    "bigger frame", "larger frame", "frame bigger", "frame larger",
    "groesser", "vergroessern", "groesser machen",
}

P.FRAME_RESIZE_DECREASE_TERMS = {
    "smaller", "shrink", "reduce size", "make smaller", "decrease size",
    "smaller frame", "frame smaller", "kleiner", "verkleinern", "kleiner machen",
}

P.FRAME_RESIZE_INTENT_TERMS = {
    "resize frame", "resize unitframe", "resize unit frame", "frame size", "unitframe size", "unit frame size",
    "make frame bigger", "make frame smaller", "make unitframe bigger", "make unitframe smaller",
    "make unit frame bigger", "make unit frame smaller",
}

P.FRAME_RESIZE_DETAIL_BLOCKERS = {
    "portrait", "castbar", "cast bar", "class power", "class resource", "class resources",
    "power bar", "mana bar", "health bar", "hp bar", "name", "names", "name text", "hp text",
    "health text", "power text", "mana text", "text", "font", "border", "outline",
    "corner", "corner dot", "corner dots", "indicator", "indicators", "status icon",
    "status indicator", "icon", "icons", "symbol", "symbols", "elite", "elite icon",
    "elite symbol", "rare icon", "rare symbol", "aura", "auras", "buff", "buffs", "debuff",
    "raid marker", "target marker", "ready check", "summon icon", "resurrect icon",
    "resurrection icon", "incoming rez", "incoming resurrection", "pvp flag", "pvp icon", "phase icon",
    "debuffs", "alpha", "opacity", "transparency", "range fade", "scale", "x offset",
    "y offset", "offset", "position", "move", "nudge", "shift", "growth",
    "grow right", "grow left", "grow up", "grow down",
}

P.FRAME_RESIZE_EXACT_DIMENSION_TERMS = {
    "width", "wide", "wider", "narrower", "breite", "breiter", "schmaler",
    "height", "tall", "taller", "shorter", "hoehe", "hoeher",
}

function P.FrameResizeDirection(text)
    if ContainsAny(text, P.FRAME_RESIZE_INCREASE_TERMS) then return "increase" end
    if ContainsAny(text, P.FRAME_RESIZE_DECREASE_TERMS) then return "decrease" end
    if ContainsAny(text, GeometryPhrases[109]) and ContainsAny(text, GeometryPhrases[110]) then return "increase" end
    if ContainsAny(text, GeometryPhrases[111]) and ContainsAny(text, GeometryPhrases[112]) then return "decrease" end
    return nil
end

function P.FrameResizeHasIntent(text)
    if P.FrameResizeDirection(text) then return true end
    return ContainsAny(text, P.FRAME_RESIZE_INTENT_TERMS)
end

function P.FrameResizeDelta(text, axis, direction)
    local amount = FirstNumber(text)
    if not amount then
        local subtle = ContainsAny(text, GeometryPhrases[113])
        local large = ContainsAny(text, GeometryPhrases[114])
        if axis == "width" then
            amount = large and 50 or (subtle and 10 or 25)
        else
            amount = large and 10 or (subtle and 2 or 5)
        end
    end
    amount = tonumber(amount) or 0
    if direction == "decrease" then amount = -amount end
    return amount
end

function P.FrameResizeActionLabel(direction)
    return direction == "decrease" and "Decrease" or "Increase"
end

function P.FrameResizeUnitLabel(unit)
    if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(unit) end
    local labels = A.UnitLabels or {}
    if labels[unit] ~= nil and tostring(labels[unit]) ~= "" then return tostring(labels[unit]) end
    if unit == "targettarget" then return "Target of Target" end
    if unit == "focustarget" then return "Focus Target" end
    if unit == "mythicraid" then return "Mythic Raid" end
    return tostring(unit or "Unit Frame")
end

function P.FrameResizeGroupLabel(scope)
    if A and type(A.DisplayGroupLabel) == "function" then return A.DisplayGroupLabel(scope) end
    if scope == "party" then return "Party" end
    if scope == "raid" then return "Raid" end
    if scope == "mythicraid" then return "Mythic Raid" end
    return tostring(scope or "Group")
end

function P.FrameResizeTargetLabel(kind, targets)
    targets = targets or {}
    if #targets == 1 then
        return kind == "group" and (P.FrameResizeGroupLabel(targets[1]) .. " frame") or (P.FrameResizeUnitLabel(targets[1]) .. " frame")
    end
    if kind == "group" then
        if #targets >= #ALL_GROUPS then return "all group frames" end
        return tostring(#targets) .. " group frames"
    end
    if #targets >= #ALL_UNITFRAMES then return "all unit frames" end
    return tostring(#targets) .. " unit frames"
end

function P.FrameResizeSettingKey(kind, target, attr)
    if kind == "group" then return "gf_" .. tostring(A._TextGroupScopeName and A._TextGroupScopeName(target) or target) .. "." .. attr end
    return tostring(target) .. "." .. attr
end

function P.ParseFrameSizeExactShortcut(text)
    if ContainsAny(text, P.FRAME_RESIZE_DETAIL_BLOCKERS) then return nil end
    if ContainsAny(text, GeometryPhrases[115]) then return nil end
    if ContainsAny(text, GeometryPhrases[116]) then return nil end
    local hasWidth = ContainsAny(text, GeometryPhrases[117])
    local hasHeight = ContainsAny(text, GeometryPhrases[118])
    -- Multi-axis commands belong to the compound parser, which preserves the
    -- number beside each axis. Taking this single-axis shortcut would use the
    -- final number for Width and silently drop Height.
    if hasWidth and hasHeight then return nil end
    local dimension
    if hasWidth then
        dimension = "width"
    elseif hasHeight then
        dimension = "height"
    else
        return nil
    end
    if ContainsAny(text, GeometryPhrases[119]) then return nil end

    local value = A._NumberValueForText and A._NumberValueForText(nil, text) or FirstNumber(text)
    if value == nil then return nil end

    local groups = DetectGroups(text)
    local units = {}
    local kind
    local targets
    if #groups > 0 then
        kind = "group"
        targets = groups
    else
        units = DetectUnits(text)
        if #units > 0 then
            kind = "unitframe"
            targets = units
        end
    end

    if not targets or #targets == 0 then
        local pageGroups = GroupScopesOrCurrentPage(text)
        if #pageGroups > 0 then
            kind = "group"
            targets = pageGroups
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then
                kind = "unitframe"
                targets = { pageUnit }
            end
        end
    end
    if not targets or #targets == 0 then return nil end
    if #targets > 1 then
        local numberCount = 0
        for _ in Normalize(text):gmatch("[-+]?%d+%.?%d*") do numberCount = numberCount + 1 end
        -- Multiple targets with multiple values are target/value pairs, not a
        -- bulk write of the first number to every frame.
        if numberCount >= #targets then return nil end
    end

    local changes = {}
    for i = 1, #targets do
        local setting = Registry and Registry:GetSetting(P.FrameResizeSettingKey(kind, targets[i], dimension))
        if setting then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
            }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = P.FrameResizeTargetLabel(kind, targets) .. " " .. (dimension == "width" and "width" or "height"),
        bulkSafe = #changes > 1,
        summary = "Sets the root frame width/height option directly.",
    }
end

-- A proportional resize ("20 percent bigger", "twice as big") cannot be one
-- pixel amount: a 275px width and a 40px height need different deltas to grow by
-- the same proportion. Returns the factor, or nil for a plain pixel request.
function P.FrameResizeFactor(text, direction)
    text = tostring(text or "")
    local percent = tonumber(text:match("(%d+%.?%d*)%s*%%")
        or text:match("(%d+%.?%d*)%s*percent")
        or text:match("(%d+%.?%d*)%s*prozent"))
    if percent == nil then
        if text:find("twice as", 1, true) or text:find("double", 1, true) then return 2 end
        if text:find("half as", 1, true) or text:find("halve", 1, true) then return 0.5 end
        return nil
    end
    if percent <= 0 then return nil end
    if direction == "decrease" then return 1 - percent / 100 end
    return 1 + percent / 100
end

function P.BuildFrameResizeChanges(kind, targets, dimension, widthDelta, heightDelta, factor)
    local changes = {}
    -- With a factor, each control's delta comes from its OWN current value.
    -- Without this, "make the player frame 20 percent bigger" added a flat 20px
    -- to both width and height (275 -> 295, 40 -> 60) instead of scaling them.
    local function DeltaFor(setting, fallback)
        if not factor or type(setting.get) ~= "function" then return fallback end
        local ok, current = pcall(setting.get)
        current = ok and tonumber(current) or nil
        if not current or current == 0 then return fallback end
        local delta = current * factor - current
        if delta == 0 then return fallback end
        return delta
    end
    for i = 1, #(targets or {}) do
        local target = targets[i]
        if dimension == "both" or dimension == "width" then
            local setting = Registry and Registry:GetSetting(P.FrameResizeSettingKey(kind, target, "width"))
            if setting then
                local delta = DeltaFor(setting, widthDelta)
                changes[#changes + 1] = { setting = setting, relativeDelta = delta, direction = delta < 0 and "decrease" or "increase" }
            end
        end
        if dimension == "both" or dimension == "height" then
            local setting = Registry and Registry:GetSetting(P.FrameResizeSettingKey(kind, target, "height"))
            if setting then
                local delta = DeltaFor(setting, heightDelta)
                changes[#changes + 1] = { setting = setting, relativeDelta = delta, direction = delta < 0 and "decrease" or "increase" }
            end
        end
    end
    return changes
end

function P.FrameResizeChoice(kind, targets, dimension, widthDelta, heightDelta, direction, factor)
    local changes = P.BuildFrameResizeChanges(kind, targets, dimension, widthDelta, heightDelta, factor)
    if #changes == 0 then return nil end
    local action = P.FrameResizeActionLabel(direction)
    local targetLabel = P.FrameResizeTargetLabel(kind, targets)
    local label
    if dimension == "both" then
        label = action .. " " .. targetLabel .. " width and height"
    elseif dimension == "width" then
        label = action .. " " .. targetLabel .. " width only"
    else
        label = action .. " " .. targetLabel .. " height only"
    end
    return {
        changes = changes,
        label = label,
        bulkSafe = #changes >= 6,
        summary = "Applies a relative frame size change to width/height options.",
    }
end

function P.ParseFrameResizeShortcut(text)
    if not P.FrameResizeHasIntent(text) then return nil end
    if ContainsAny(text, P.FRAME_RESIZE_DETAIL_BLOCKERS) then return nil end
    if ContainsAny(text, P.FRAME_RESIZE_EXACT_DIMENSION_TERMS) then return nil end

    local direction = P.FrameResizeDirection(text)
    local groups = DetectGroups(text)
    local units = {}
    local kind
    local targets
    if #groups > 0 then
        kind = "group"
        targets = groups
    else
        units = DetectUnits(text)
        if #units > 0 then
            kind = "unitframe"
            targets = units
        end
    end

    if not targets or #targets == 0 then
        local pageGroups = GroupScopesOrCurrentPage(text)
        if #pageGroups > 0 then
            kind = "group"
            targets = pageGroups
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then
                kind = "unitframe"
                targets = { pageUnit }
            end
        end
    end

    if not targets or #targets == 0 then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which frame do you want me to resize? For example: 'make player frame bigger', 'make target frame smaller', or 'make party frame bigger'.",
            summary = "Asks which frame should be resized.",
        }
    end
    if not direction then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Do you want me to make " .. P.FrameResizeTargetLabel(kind, targets) .. " bigger or smaller? You can also say 'width only' or 'height only'.",
            summary = "Asks which resize direction to use.",
        }
    end

    local widthDelta = P.FrameResizeDelta(text, "width", direction)
    local heightDelta = P.FrameResizeDelta(text, "height", direction)
    local factor = P.FrameResizeFactor(text, direction)
    local forceBoth = ContainsAny(text, GeometryPhrases[120])
    if forceBoth then
        local changes = P.BuildFrameResizeChanges(kind, targets, "both", widthDelta, heightDelta, factor)
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            label = P.FrameResizeActionLabel(direction) .. " frame width and height",
            bulkSafe = #changes >= 6,
            summary = "Applies a relative frame size change to width and height options.",
        }
    end

    local choices = {}
    local both = P.FrameResizeChoice(kind, targets, "both", widthDelta, heightDelta, direction, factor)
    local width = P.FrameResizeChoice(kind, targets, "width", widthDelta, heightDelta, direction, factor)
    local height = P.FrameResizeChoice(kind, targets, "height", widthDelta, heightDelta, direction, factor)
    if both then choices[#choices + 1] = both end
    if width then choices[#choices + 1] = width end
    if height then choices[#choices + 1] = height end
    if #choices == 0 then return nil end
    return {
        kind = "ambiguous",
        choices = choices,
        label = "Which frame size should change?",
        summary = "The request named a frame and a broad resize direction, so the Assistant asks which size options to adjust.",
    }
end

P.POWER_BAR_SIZE_TERMS = {
    "power bar", "mana bar", "power balken", "mana balken",
}

P.POWER_BAR_SIZE_TEXT_BLOCKERS = {
    "power text", "mana text", "energy text", "resource text", "power value", "mana value",
    "power number", "mana number", "power label", "mana label",
}

P.POWER_BAR_SIZE_DETAIL_BLOCKERS = {
    "border", "outline", "power border", "mana border", "aura", "auras", "buff", "debuff",
    "castbar", "cast bar", "class power", "class resource", "class resources",
}

P.POWER_BAR_WIDTH_INCREASE_TERMS = {
    "wider", "wide", "make wider", "increase width", "raise width", "larger width",
    "more width", "breiter",
}

P.POWER_BAR_WIDTH_DECREASE_TERMS = {
    "narrower", "make narrower", "decrease width", "reduce width", "smaller width",
    "less width", "schmaler",
}

P.POWER_BAR_HEIGHT_INCREASE_TERMS = {
    "taller", "higher", "thicker", "fatter", "make taller", "make thicker", "increase height",
    "raise height", "larger height", "more height", "hoeher", "dicker",
}

P.POWER_BAR_HEIGHT_DECREASE_TERMS = {
    "shorter", "lower", "thinner", "make shorter", "make thinner", "decrease height",
    "reduce height", "smaller height", "less height", "niedriger", "duenner",
}

P.POWER_BAR_SIZE_INCREASE_TERMS = {
    "bigger", "larger", "increase size", "make bigger", "make larger", "grow",
}

P.POWER_BAR_SIZE_DECREASE_TERMS = {
    "smaller", "decrease size", "reduce size", "make smaller", "shrink",
}

function P.PowerBarSizeDirection(text)
    if ContainsAny(text, P.POWER_BAR_WIDTH_INCREASE_TERMS) then return "increase", "width" end
    if ContainsAny(text, P.POWER_BAR_WIDTH_DECREASE_TERMS) then return "decrease", "width" end
    if ContainsAny(text, P.POWER_BAR_HEIGHT_INCREASE_TERMS) then return "increase", "height" end
    if ContainsAny(text, P.POWER_BAR_HEIGHT_DECREASE_TERMS) then return "decrease", "height" end
    if ContainsAny(text, P.POWER_BAR_SIZE_INCREASE_TERMS) then return "increase", "auto" end
    if ContainsAny(text, P.POWER_BAR_SIZE_DECREASE_TERMS) then return "decrease", "auto" end
    return nil, nil
end

function P.PowerBarSizeExactValue(text, dimension)
    local number = FirstNumber(text)
    if number == nil then return nil end
    if HasPhrase(text, "by") then return nil end
    if HasPhrase(text, "to") or tostring(text or ""):find("=", 1, true) then return number end
    if dimension == "height" and ContainsAny(text, GeometryPhrases[121]) then return number end
    if dimension == "width" and ContainsAny(text, GeometryPhrases[122]) then return number end
    return nil
end

function P.PowerBarSizeDelta(text, dimension, direction, detached)
    if dimension == "height" and not detached then
        local amount = FirstNumber(text)
        if not amount then
            local subtle = ContainsAny(text, GeometryPhrases[123])
            local large = ContainsAny(text, GeometryPhrases[124])
            amount = large and 5 or (subtle and 1 or 1)
        end
        amount = tonumber(amount) or 0
        if direction == "decrease" then amount = -amount end
        return amount
    end
    return P.FrameResizeDelta and P.FrameResizeDelta(text, dimension, direction) or (direction == "decrease" and -1 or 1)
end

function P.PowerBarSizeUnits(text)
    local units = DetectUnits(text)
    if #units > 0 then return units end
    if ContainsAny(text, GeometryPhrases[125]) then
        local allUnits = {}
        for i = 1, #ALL_UNITFRAMES do allUnits[#allUnits + 1] = ALL_UNITFRAMES[i] end
        return allUnits
    end
    local pageUnit = CurrentPageUnit()
    if pageUnit then return { pageUnit } end
    return {}
end

function P.ParsePowerBarSizeShortcut(text)
    if not ContainsAny(text, P.POWER_BAR_SIZE_TERMS) then return nil end
    if #DetectGroups(text) > 0 then return nil end
    if ContainsAny(text, P.POWER_BAR_SIZE_TEXT_BLOCKERS) then return nil end
    if ContainsAny(text, P.POWER_BAR_SIZE_DETAIL_BLOCKERS) then return nil end

    local direction, dimension = P.PowerBarSizeDirection(text)
    if not direction then
        if ContainsAny(text, GeometryPhrases[126]) then
            dimension = "height"
        elseif ContainsAny(text, GeometryPhrases[127]) then
            dimension = "width"
        else
            return nil
        end
        if ContainsAny(text, GeometryPhrases[128]) then
            direction = "increase"
        elseif ContainsAny(text, GeometryPhrases[129]) then
            direction = "decrease"
        end
    end
    if not direction and P.PowerBarSizeExactValue(text, dimension) == nil then return nil end

    local explicitUnits = DetectUnits(text)
    local allUnitPowerBars = ContainsAny(text, GeometryPhrases[130])
    if #explicitUnits == 0 and not allUnitPowerBars and not CurrentPageUnit() then return nil end

    local units = P.PowerBarSizeUnits(text)
    if #units == 0 then
        return {
            kind = "unknown",
            status = "failed",
            text = "Which unit Power Bar do you want me to resize? For example: 'make player power bar taller' or 'set target power bar height to 8'.",
            summary = "Asks which unit's Power Bar size to change.",
        }
    end

    local explicitDetached = ContainsAny(text, GeometryPhrases[131])
    local changes = {}
    local skippedAttachedWidth = {}

    for i = 1, #units do
        local unit = tostring(units[i])
        local detached = explicitDetached or (P.UnitPowerBarIsDetached and P.UnitPowerBarIsDetached(unit))
        local effectiveDimension = dimension == "auto" and (detached and "both" or "height") or dimension
        if effectiveDimension == "width" and not detached then
            skippedAttachedWidth[#skippedAttachedWidth + 1] = unit
        else
            if detached and (effectiveDimension == "width" or effectiveDimension == "both") then
                local setting = Registry and Registry:GetSetting(unit .. ".detachedPowerBarWidth")
                if setting then
                    local value = P.PowerBarSizeExactValue(text, "width")
                    changes[#changes + 1] = {
                        setting = setting,
                        value = value,
                        relativeDelta = value == nil and P.PowerBarSizeDelta(text, "width", direction, detached) or nil,
                        direction = direction,
                    }
                end
            end
            if effectiveDimension == "height" or effectiveDimension == "both" then
                local attr = detached and "detachedPowerBarHeight" or "powerBarHeight"
                local setting = Registry and Registry:GetSetting(unit .. "." .. attr)
                if setting then
                    local value = P.PowerBarSizeExactValue(text, "height")
                    changes[#changes + 1] = {
                        setting = setting,
                        value = value,
                        relativeDelta = value == nil and P.PowerBarSizeDelta(text, "height", direction, detached) or nil,
                        direction = direction,
                    }
                end
            end
        end
    end

    if #changes == 0 and #skippedAttachedWidth > 0 then
        local labels = A.UnitLabels or {}
        local unitLabel = labels[skippedAttachedWidth[1]] or skippedAttachedWidth[1] or "that unit"
        return {
            kind = "answer",
            status = "info",
            text = tostring(unitLabel) .. " Power Bar width follows the frame while it is attached. To make the bar wider, resize the " .. tostring(unitLabel):lower() .. " frame width, or detach the Power Bar and then resize the detached Power Bar width.",
            summary = "Attached unit Power Bars follow the unit frame width.",
        }
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Resize Power Bar",
        bulkSafe = #changes > 1,
        summary = "Adjusts Power Bar height or detached Power Bar size.",
    }
end

P.TEXT_VISIBILITY_VALUE_TERMS = {
    "current", "actual", "max", "maximum", "percent", "percentage", "pct", "%",
    "current max", "current maximum", "current percent", "current percentage",
    "current/max", "current / max", "current/percent", "current / percent",
    "deficit", "missing", "only percent", "only percentage", "only %",
    "just percent", "just percentage", "percent only", "percentage only",
    "left hp text", "hp left text", "hp text left", "right hp text", "hp right text", "hp text right",
    "center hp text", "centre hp text", "middle hp text", "hp center text", "hp centre text", "hp middle text",
    "left power text", "power left text", "power text left", "right power text", "power right text", "power text right",
    "center power text", "centre power text", "middle power text", "power center text", "power centre text", "power middle text",
    "left mana text", "mana left text", "mana text left", "right mana text", "mana right text", "mana text right",
    "center mana text", "centre mana text", "middle mana text", "mana center text", "mana centre text", "mana middle text",
    "slot", "slots", "text slot", "anchor", "anchoring", "side", "left side", "right side",
    "offset", "position", "pos", "x offset", "y offset", "move", "nudge", "shift",
    "layer", "size", "font", "font size", "decimal", "decimals", "color", "colour",
    -- Styling words name Font Outline / Bold Text, never the show-hide toggle.
    -- "set player name bold text on" otherwise matched on "name" plus "on" and
    -- silently toggled Player Name off instead of admitting it did not
    -- understand "bold".
    "bold", "italic", "outline", "shadow", "monochrome", "thickness",
    "fett", "kursiv", "umriss", "schatten",
    "shorten", "shortened", "shortening", "short names", "shorten names", "shorten group names",
    "dot", "dots", "ellipsis", "ellipses", "trailing dots", "three dots", "two dots",
    "raid group name", "raid group in name", "group name",
    "realtime", "real time", "real-time",
    "by health", "by power", "by resource", "by mana",
}

P.TEXT_VISIBILITY_VERBS = {
    "turn off", "turn on", "off", "on", "disable", "disabled", "enable", "enabled", "hide", "hidden",
    "show", "display", "visible", "aus", "deaktivieren", "deaktiviert", "ausschalten",
    "ausgeschaltet", "ausblenden", "verstecken", "an", "aktivieren", "aktiviert",
    "einschalten", "eingeschaltet", "anzeigen", "zeigen", "einblenden", "sichtbar",
}

function P.ParseTextVisibilityShortcut(text)
    text = tostring(text or "")
    local hasTerseToggle = ContainsAny(text, { "off", "on", "aus", "an" })
    if not (text:find("turn", 1, true) or text:find("disable", 1, true)
        or text:find("enable", 1, true) or text:find("hide", 1, true)
        or text:find("show", 1, true) or text:find("display", 1, true)
        or text:find("visible", 1, true) or text:find("deaktiv", 1, true)
        or text:find("aktiv", 1, true) or text:find("ausschalten", 1, true)
        or text:find("einschalten", 1, true) or text:find("ausblenden", 1, true)
        or text:find("verstecken", 1, true) or text:find("anzeigen", 1, true)
        or text:find("zeigen", 1, true) or text:find("einblenden", 1, true)
        or text:find("sichtbar", 1, true) or hasTerseToggle) then
        return nil
    end
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryPhrases[132]) then return nil end
    if ContainsAny(text, GeometryPhrases[133]) then return nil end
    if ContainsAny(text, GeometryPhrases[134]) then return nil end
    if ContainsAny(text, GeometryPhrases[135]) then return nil end
    if ContainsAny(text, P.TEXT_VISIBILITY_VALUE_TERMS) then return nil end
    if not ContainsAny(text, P.TEXT_VISIBILITY_VERBS) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    local spec
    if ContainsAny(text, GeometryPhrases[136]) then
        spec = { unitAttr = "showPowerText", groupAttr = "showPowerText", label = "Power Text" }
    elseif ContainsAny(text, GeometryPhrases[137]) then
        spec = { unitAttr = "showHP", groupAttr = "showHPText", label = "HP Text" }
    elseif ContainsAny(text, GeometryPhrases[138]) then
        spec = { unitAttr = "showName", groupAttr = "showName", label = "Name Text" }
    end
    if not spec then return nil end

    local allScope = ContainsAny(text, GeometryPhrases[139])
    local explicitUnits = DetectUnits(text)
    local explicitGroups = DetectGroups(text)
    local units = {}
    local groups = {}

    if allScope then
        if #explicitGroups > 0 and #explicitUnits == 0 then
            for i = 1, #ALL_GROUPS do groups[#groups + 1] = ALL_GROUPS[i] end
        else
            for i = 1, #ALL_UNITFRAMES do units[#units + 1] = ALL_UNITFRAMES[i] end
        end
    else
        for i = 1, #explicitUnits do units[#units + 1] = explicitUnits[i] end
        for i = 1, #explicitGroups do groups[#groups + 1] = explicitGroups[i] end
    end

    if #units == 0 and #groups == 0 and not allScope then
        local pageGroups = GroupScopesOrCurrentPage(text)
        if #pageGroups > 0 then
            for i = 1, #pageGroups do groups[#groups + 1] = pageGroups[i] end
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units[1] = pageUnit end
        end
    end

    local changes = {}
    local function AddTextVisibilityChange(key)
        local setting = Registry and Registry:GetSetting(key)
        if not setting then return end
        local valueLabel = value and "on" or "off"
        changes[#changes + 1] = {
            setting = setting,
            value = value,
            valueLabel = valueLabel,
            label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, valueLabel, "Text visibility") or (tostring(setting.label or "Text visibility") .. ": " .. valueLabel),
        }
    end
    if #units == 0 and #groups == 0 then
        for i = 1, #ALL_UNITFRAMES do
            AddTextVisibilityChange(tostring(ALL_UNITFRAMES[i]) .. "." .. spec.unitAttr)
        end
    else
        for i = 1, #units do
            AddTextVisibilityChange(tostring(units[i]) .. "." .. spec.unitAttr)
        end
        for i = 1, #groups do
            AddTextVisibilityChange("gf_" .. tostring(groups[i]) .. "." .. spec.groupAttr)
        end
    end
    if #changes == 0 then return nil end

    if (#units + #groups > 1 and not allScope) or (#units == 0 and #groups == 0) then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Which " .. spec.label .. "?",
            summary = "The request names more than one frame, so the Assistant asks which real text visibility toggle to change.",
        }
    end

    return {
        kind = "changes",
        changes = changes,
        label = spec.label .. " Visibility",
        bulkSafe = #changes > 1,
        summary = "Changes the text visibility toggle instead of a text-slot value or color mode.",
    }
end

function A._ParseGroupAnchorTargetShortcut(text)
    if ContainsAny(text, GeometryPhrases[140]) then return nil end
    if ContainsAny(text, GeometryPhrases[141]) then return nil end
    if not (ContainsAny(text, GeometryPhrases[142])
        or (HasPhrase(text, "anchor") and HasPhrase(text, "to")))
    then
        return nil
    end

    local groups = GroupScopesOrCurrentPage(text)
    local units = DetectUnits(text)
    local unitframeScope = ContainsAny(text, GeometryPhrases[143])
    local unitPage = CurrentPageUnit()
    if #groups == 0 and (#units > 0 or unitframeScope or unitPage) then
        local valueSetting = Registry and Registry:GetSetting(((units and units[1]) or unitPage or "player") .. ".anchorToUnitframe")
        local value = valueSetting and EnumValueForText(valueSetting, text)
        if value ~= nil then
            if unitframeScope and #units == 0 then
                units = ALL_UNITFRAMES
            elseif #units == 0 and unitPage then
                units = { unitPage }
            end
            if #units == 1 and value == units[1] then return nil end
            if #units > 1 and (value == "player" or value == "target" or value == "targettarget" or value == "focustarget" or value == "focus" or value == "pet" or value == "boss") then
                local filtered = {}
                for i = 1, #units do
                    if units[i] ~= value then filtered[#filtered + 1] = units[i] end
                end
                if #filtered > 0 then units = filtered end
            end
            local changes = {}
            for i = 1, #units do
                local unit = tostring(units[i])
                local setting = Registry and Registry:GetSetting(unit .. ".anchorToUnitframe")
                if setting then changes[#changes + 1] = { setting = setting, value = value } end
            end
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Set unit frame anchor target",
                    bulkSafe = #changes > 1,
                    summary = "Changes the unit frame Anchor To option.",
                }
            end
        end
    end

    if #groups == 0 then return nil end
    local changes = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        local setting = Registry and Registry:GetSetting("gf_" .. scope .. ".anchorToFrame")
        local value = setting and EnumValueForText(setting, text)
        if setting and value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set group anchor target",
        summary = "Changes the group layout Anchor To option.",
    }
end

local function ParseGroupDetailMove(text)
    if ContainsAny(text, GeometryPhrases[144]) then return nil end
    if not ContainsAny(text, GeometryPhrases[145]) then return nil end
    local direction = DetectDirection(text, {})
    if not direction then return nil end
    local groups = GroupScopesOrCurrentPage(text)
    if #groups == 0 then return nil end
    local spec
    for i = 1, #GROUP_DETAIL_MOVE_SPECS do
        if ContainsAny(text, GROUP_DETAIL_MOVE_SPECS[i].terms) then
            spec = GROUP_DETAIL_MOVE_SPECS[i]
            break
        end
    end
    if not spec then return nil end
    local attr = (direction == "left" or direction == "right") and spec.x or spec.y
    local amount = FirstNumber(text) or 10
    if direction == "left" or direction == "down" then amount = -amount end
    local changes = {}
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = spec.label,
        summary = "Moves a group-frame text option by pixels.",
    }
end

function A._DetailOffsetAxis(text)
    if ContainsAny(text, GeometryPhrases[146]) or HasPhrase(text, "x") then return "x" end
    if ContainsAny(text, GeometryPhrases[147]) or HasPhrase(text, "y") then return "y" end
    return nil
end

function A._DetailSpecForText(text, specs)
    for i = 1, #(specs or {}) do
        if ContainsAny(text, specs[i].terms) then return specs[i] end
    end
    return nil
end

function A._ParseTextDetailExactOffset(text)
    if ContainsAny(text, GeometryPhrases[148]) then return nil end
    if not ContainsAny(text, GeometryPhrases[149]) then return nil end
    local axis = A._DetailOffsetAxis(text)
    if not axis then return nil end
    local value = FirstNumber(text)
    if value == nil then return nil end

    local groupSpec = A._DetailSpecForText(text, GROUP_DETAIL_MOVE_SPECS)
    local unitSpec = A._DetailSpecForText(text, DETAIL_MOVE_SPECS)
    if not groupSpec and not unitSpec then return nil end

    local groups = groupSpec and DetectGroups(text) or {}
    local units = unitSpec and DetectUnits(text) or {}
    local useGroups = #groups > 0
    local useUnits = #units > 0

    if not useGroups and not useUnits then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
            useGroups = #groups > 0
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then
                units = { pageUnit }
                useUnits = true
            end
        end
    end

    local changes = {}
    if useGroups and groupSpec then
        local attr = axis == "x" and groupSpec.x or groupSpec.y
        for i = 1, #groups do
            local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value, direction = axis } end
        end
    elseif useUnits and unitSpec then
        local attr = axis == "x" and unitSpec.x or unitSpec.y
        for i = 1, #units do
            local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value, direction = axis } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set text offset",
        summary = "Sets a unit or group text offset.",
    }
end

local function OutlineScopeSettingForText(text)
    local explicitScope = DetectGlobalScope(text)
    local scope = explicitScope
    if not scope or scope == "shared" then
        local pageUnit = CurrentPageUnit()
        if pageUnit then scope = pageUnit end
    end
    if scope and scope ~= "shared" then
        local scoped = Registry and Registry:GetSetting("barScope." .. tostring(scope) .. ".barOutlineThickness")
        if scoped then return scoped, scope end
    end
    return Registry and Registry:GetSetting("bars.barOutlineThickness"), "shared"
end

local AMBIGUOUS_GROUP_OUTLINE_SCOPE_TERMS = {
    "group", "group frame", "group frames",
    "party", "party frame", "party frames",
    "raid", "raid frame", "raid frames",
    "mythic raid", "mythicraid", "mythic raid frame", "mythic raid frames",
}
local AMBIGUOUS_GROUP_OUTLINE_DETAIL_TERMS = {
    "outline", "frame border", "outline border", "border outline",
}
local EXPLICIT_GROUP_BAR_OUTLINE_TERMS = {
    "bar outline", "bar outlines", "bar border", "bar borders",
    "health bar outline", "healthbar outline", "hp bar outline", "member bar outline",
}
local EXPLICIT_FULL_GROUP_BORDER_TERMS = {
    "full group border", "whole group border", "outer group border", "group block border",
    "border around group", "border around frames", "entire group border",
}
local EXPLICIT_FONT_OUTLINE_TERMS = {
    "font outline", "font outlines", "text outline", "text outlines", "outline style",
}
local function IsAmbiguousGroupOutlineBorderIntent(text)
    if ContainsAny(text, EXPLICIT_GROUP_BAR_OUTLINE_TERMS) then return false end
    if ContainsAny(text, EXPLICIT_FULL_GROUP_BORDER_TERMS) then return false end
    if ContainsAny(text, EXPLICIT_FONT_OUTLINE_TERMS) then return false end
    if not ContainsAny(text, AMBIGUOUS_GROUP_OUTLINE_SCOPE_TERMS) then return false end
    return ContainsAny(text, AMBIGUOUS_GROUP_OUTLINE_DETAIL_TERMS)
end

local function ParseAmbiguousGroupOutlineBorderShortcut(text)
    if not IsAmbiguousGroupOutlineBorderIntent(text) then return nil end
    -- This lane exists to separate the per-member bar outline from the whole
    -- group border. Beta 44's "Frame Outline Texture" names one exact control,
    -- and neither reading of "outline/border" is a texture, so asking here just
    -- blocked a request the exact-alias lane already resolves.
    if ContainsAny(text, { "outline texture", "border texture", "frame outline texture" }) then
        return nil
    end
    return {
        kind = "answer",
        status = "ambiguous",
        text = "Which group outline/border do you mean: the bar outline on each Party/Raid member, or the full Group Border around the whole group frame? I did not change anything. Say 'turn off raid bar outline' or 'turn off raid group border'.",
        summary = "Clarifies ambiguous group outline or border request instead of changing the wrong option.",
    }
end

local function ParseBorderThicknessShortcut(text)
    if not ContainsAny(text, GeometryPhrases[150]) then return nil end
    local ambiguous = ParseAmbiguousGroupOutlineBorderShortcut(text)
    if ambiguous then return ambiguous end
    if ContainsAny(text, GeometryPhrases[151]) then return nil end
    if ContainsAny(text, GeometryPhrases[152]) then return nil end
    if ContainsAny(text, GeometryPhrases[153]) then return nil end

    local explicitDetail = ContainsAny(text, GeometryPhrases[154])
    local toggleIntent = DetectBoolean(text) ~= nil
    local numberIntent = FirstNumber(text) ~= nil
    if not (explicitDetail or toggleIntent or numberIntent) then return nil end

    local setting = OutlineScopeSettingForText(text)
    if not setting then return nil end

    local value
    local relativeDelta
    local bool = DetectBoolean(text)
    if bool ~= nil and not numberIntent and not ContainsAny(text, GeometryPhrases[155]) then
        value = bool and 1 or 0
    else
        relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 1)
        if relativeDelta == nil then value = FirstNumber(text) end
    end
    if value == nil and relativeDelta == nil then return nil end

    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = setting.label or "Frame outline thickness",
        summary = "Changes the frame/bar outline thickness option instead of toggling the whole unit frame.",
    }
end

local BAR_OUTLINE_HIGHLIGHT_BLOCK_TERMS = {
    "portrait", "castbar", "cast bar", "zauberleiste",
    "class power", "class resource", "class resources",
    "power bar", "powerbar", "mana bar", "mana border", "power border",
    "detached power", "detached mana",
    "group border", "full group border", "whole group border", "outer group border", "group block border",
    "group outline", "group frame outline", "group outline border", "group border outline",
    "party outline", "party frame outline", "raid outline", "raid frame outline",
    "boss target", "dead background", "dead bg",
    "dispel overlay", "unitframe dispel overlay", "unit frame dispel overlay", "debuff overlay",
    "heal absorb", "absorb bar", "heal prediction",
    "color", "colors", "colour", "colours", "farbe", "farben", "tint",
    "texture", "font", "text",
}

local function BarScopeForGroupScope(scope)
    if scope == "party" then return "gf_party" end
    if scope == "raid" or scope == "mythicraid" then return "gf_raid" end
    return nil
end

local function AddBarOutlineHighlightScope(scopes, seen, scope)
    scope = tostring(scope or "")
    if scope == "" or seen[scope] then return end
    seen[scope] = true
    scopes[#scopes + 1] = scope
end

local function BarOutlineHighlightScopes(text)
    local scopes, seen = {}, {}
    local groups = DetectGroups(text)
    for i = 1, #groups do
        AddBarOutlineHighlightScope(scopes, seen, BarScopeForGroupScope(groups[i]))
    end

    local units = DetectUnits(text)
    for i = 1, #units do
        AddBarOutlineHighlightScope(scopes, seen, units[i])
    end

    if #scopes == 0 and not ContainsAny(text, GeometryPhrases[156]) then
        local pageUnit = CurrentPageUnit()
        if pageUnit then AddBarOutlineHighlightScope(scopes, seen, pageUnit) end
    end
    return scopes
end

local function BarOutlineHighlightGlobalKey(attr)
    if attr == "barOutlineThickness" then return "bars.barOutlineThickness" end
    if attr == "barOutlineLayer" then return "bars.barOutlineLayer" end
    if attr == "barOutlineColorA" then return "general.barOutlineColorA" end
    if attr == "highlightBorderThickness" then return "general.highlightBorderThickness" end
    if attr == "hlPrioEnabled" then return "general.hlPrioEnabled" end
    return nil
end

-- [285] only lists contiguous wording ("frame outline layer"). Players split
-- the attribute off the subject with a preposition -- "draw the frame outline
-- on layer 5", "put the border at layer 3" -- and [160] then claimed the
-- sentence and wrote thickness. Inside a sentence this lane already owns, a
-- standalone layer word can only mean the layer control: no thickness or
-- opacity phrasing uses one, and "texture layer" never reaches here because
-- BAR_OUTLINE_HIGHLIGHT_BLOCK_TERMS blocks "texture".
local BAR_OUTLINE_LAYER_WORDS = { "layer", "layers", "strata", "sublevel" }
local function MentionsStandaloneLayerWord(text)
    for i = 1, #BAR_OUTLINE_LAYER_WORDS do
        if text:find("%f[%w]" .. BAR_OUTLINE_LAYER_WORDS[i] .. "%f[%W]") then return true end
    end
    return false
end

local function BarOutlineHighlightSpec(text)
    -- This lane owns broad edge wording -- "border opacity", "border alpha",
    -- "outline thickness". RC9 added Pandemic warning controls that reuse those
    -- plain names inside their own card, so "set the target pandemic border
    -- opacity to 80" landed here and wrote Target Bar Outline Opacity. The bar
    -- outline has nothing to do with Pandemic, so leave those to the catalog.
    if ContainsAny(text, { "pandemic" }) then return nil end
    if ContainsAny(text, GeometryPhrases[157]) then
        return "hlPrioEnabled", "Custom Highlight Priority"
    end
    if ContainsAny(text, GeometryPhrases[158]) then
        return "highlightBorderThickness", "Highlight Border Thickness"
    end
    -- After [158] so "highlight border thickness" keeps the size control, and
    -- only for a plain on/off: with a number the sentence is about a dimension,
    -- not about switching the highlight borders on or off.
    if ContainsAny(text, GeometryPhrases[287]) and FirstNumber(text) == nil
        and DetectBoolean(text) ~= nil
    then
        return "highlightBorderGroup", "Highlight Borders"
    end
    if ContainsAny(text, GeometryPhrases[159]) then
        return "barOutlineColorA", "Bar Outline Opacity"
    end
    -- Layer before thickness: the layer phrases in [285] are supersets of
    -- the thickness phrases in [160] ("bar outline strata" contains "bar
    -- outline"), so probing thickness first would never leave a layer match.
    if ContainsAny(text, GeometryPhrases[285]) or MentionsStandaloneLayerWord(text) then
        return "barOutlineLayer", "Bar Outline Layer"
    end
    if ContainsAny(text, GeometryPhrases[160]) then
        return "barOutlineThickness", "Bar Outline Thickness"
    end
    return nil, nil
end

local function BarOutlineHighlightValue(setting, attr, text)
    if attr == "hlPrioEnabled" then
        local bool = DetectBoolean(text)
        if bool == nil then return nil, nil end
        return bool, nil
    end

    local bool = DetectBoolean(text)
    local hasNumber = FirstNumber(text) ~= nil
    if bool ~= nil and not hasNumber and (attr == "barOutlineThickness" or attr == "barOutlineColorA") then
        return bool and 1 or 0, nil
    end

    local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, attr == "barOutlineThickness" and 1 or nil) or nil
    if relativeDelta ~= nil then return nil, relativeDelta end

    local value = A._NumberValueForText and A._NumberValueForText(setting, text) or FirstNumber(text)
    if value == nil then return nil, nil end
    if attr == "barOutlineColorA" and value > 1 then value = value / 100 end
    return value, nil
end

local function ParseBarOutlineHighlightShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if not ContainsAny(text, GeometryPhrases[161]) then return nil end
    local ambiguous = ParseAmbiguousGroupOutlineBorderShortcut(text)
    if ambiguous then return ambiguous end
    if ContainsAny(text, BAR_OUTLINE_HIGHLIGHT_BLOCK_TERMS) then return nil end

    local attr, label = BarOutlineHighlightSpec(text)
    if not attr then return nil end

    local scopes = BarOutlineHighlightScopes(text)
    -- "Highlight borders" is the page's name for the Aggro/Dispel/Purge trio
    -- (plus Boss Target on the shared control), so the umbrella phrase writes
    -- all of them for whichever scope was named.
    if attr == "highlightBorderGroup" then
        local on = DetectBoolean(text)
        if on == nil then return nil end
        local value = on and "on" or "off"
        local members = { "aggroOutlineMode", "dispelOutlineMode", "purgeOutlineMode" }
        local groupChanges = {}
        local function add(key)
            local setting = Registry and Registry:GetSetting(key)
            if setting then groupChanges[#groupChanges + 1] = { setting = setting, value = value } end
        end
        if #scopes == 0 then
            for i = 1, #members do add("general." .. members[i]) end
            add("general.bossTargetOutlineMode")
        else
            for i = 1, #scopes do
                for j = 1, #members do add("barScope." .. tostring(scopes[i]) .. "." .. members[j]) end
            end
        end
        if #groupChanges == 0 then return nil end
        return {
            kind = "changes",
            changes = groupChanges,
            label = label,
            bulkSafe = true,
            summary = "Changes the bar outline or highlight border option without falling back to broad registry matching.",
        }
    end
    local changes = {}
    if #scopes == 0 then
        local setting = Registry and Registry:GetSetting(BarOutlineHighlightGlobalKey(attr))
        local value, relativeDelta = setting and BarOutlineHighlightValue(setting, attr, text)
        if setting and (value ~= nil or relativeDelta ~= nil) then
            changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta }
        end
    else
        for i = 1, #scopes do
            local setting = Registry and Registry:GetSetting("barScope." .. tostring(scopes[i]) .. "." .. attr)
            local value, relativeDelta = setting and BarOutlineHighlightValue(setting, attr, text)
            if setting and (value ~= nil or relativeDelta ~= nil) then
                changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta }
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes the bar outline or highlight border option without falling back to broad registry matching.",
    }
end

local function BarOverlayScopes(text, groupOnly)
    local scopes, seen = {}, {}
    local groups = DetectGroups(text)
    for i = 1, #groups do
        AddBarOutlineHighlightScope(scopes, seen, BarScopeForGroupScope(groups[i]))
    end
    if not groupOnly then
        local units = DetectUnits(text)
        for i = 1, #units do
            AddBarOutlineHighlightScope(scopes, seen, units[i])
        end
    end
    if #scopes == 0 and not groupOnly and not ContainsAny(text, GeometryPhrases[162]) then
        local pageUnit = CurrentPageUnit()
        if pageUnit then AddBarOutlineHighlightScope(scopes, seen, pageUnit) end
    end
    return scopes
end

local function AbsorbBarGlobalKey(attr)
    if attr == "absorbTextMode" then return "general.absorbTextMode" end
    if attr == "absorbAnchorMode" then return "general.absorbAnchorMode" end
    if attr == "fullHealthAbsorbStripe" then return "general.fullHealthAbsorbStripe" end
    if attr == "overAbsorbOverlay" then return "general.overAbsorbOverlay" end
    if attr == "showSelfHealPrediction" then return "general.showSelfHealPrediction" end
    if attr == "healPredAnchorMode" then return "general.healPredAnchorMode" end
    if attr == "absorbBarOpacity" then return "general.absorbBarOpacity" end
    if attr == "absorbBarTexture" then return "general.absorbBarTexture" end
    if attr == "healAbsorbBarTexture" then return "general.healAbsorbBarTexture" end
    if attr == "healAbsorbBarOpacity" then return "general.healAbsorbBarOpacity" end
    return nil
end

local function AbsorbBarSpec(text)
    if ContainsAny(text, GeometryPhrases[163]) then
        return "healPredAnchorMode", "Heal Prediction Anchor", "enum", true
    end
    if ContainsAny(text, GeometryPhrases[164]) then
        return "showSelfHealPrediction", "Heal Prediction Overlay", "boolean", true
    end
    if ContainsAny(text, GeometryPhrases[165]) then
        return "healAbsorbBarTexture", "Heal Absorb Bar Texture", "string", false
    end
    if ContainsAny(text, GeometryPhrases[166]) then
        return "healAbsorbBarOpacity", "Heal Absorb Bar Opacity", "number", false
    end
    if ContainsAny(text, GeometryPhrases[167]) then
        return "absorbTextMode", "Absorb Display Mode", "enum", false
    end
    if ContainsAny(text, GeometryPhrases[168]) then
        return "absorbAnchorMode", "Absorb Bar Anchor", "enum", false
    end
    if ContainsAny(text, GeometryPhrases[284]) then
        return "fullHealthAbsorbStripe", "Full-Health Absorb Stripe", "boolean", false
    end
    if ContainsAny(text, GeometryPhrases[169]) then
        return "overAbsorbOverlay", "Over-Absorb Overlay", "boolean", false
    end
    if ContainsAny(text, GeometryPhrases[170]) then
        return "absorbBarTexture", "Absorb Bar Texture", "string", false
    end
    if ContainsAny(text, GeometryPhrases[171]) then
        return "absorbBarOpacity", "Absorb Bar Opacity", "number", false
    end
    return nil, nil, nil, nil
end

local function AbsorbStringValue(text, raw)
    local source = raw or text
    local value = RawAfterLastConnector and RawAfterLastConnector(source, { " to ", " as ", " value ", " texture ", " = ", " auf ", " zu ", " als ", " wert " }) or nil
    value = Trim(value or "")
    value = value:gsub("^texture%s+", ""):gsub("^to%s+", ""):gsub("^as%s+", "")
    if value == "" then return nil end
    return value
end

local function AbsorbBarValue(setting, attrType, text, raw)
    if attrType == "boolean" then
        local bool = DetectBoolean(text)
        if bool == nil then return nil, nil end
        return bool, nil
    end
    if attrType == "enum" then
        local value = setting and EnumValueForText and EnumValueForText(setting, text) or nil
        return value, nil
    end
    if attrType == "string" then
        return AbsorbStringValue(text, raw), nil
    end
    if attrType == "number" then
        local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text) or nil
        if relativeDelta ~= nil then return nil, relativeDelta end
        local value = A._NumberValueForText and A._NumberValueForText(setting, text) or FirstNumber(text)
        if value ~= nil and value > 1 then value = value / 100 end
        return value, nil
    end
    return nil, nil
end

local function ParseAbsorbBarShortcut(text, raw)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if not ContainsAny(text, GeometryPhrases[172]) then return nil end
    if ContainsAny(text, GeometryPhrases[173]) then return nil end

    local attr, label, attrType, groupOnly = AbsorbBarSpec(text)
    if not attr then return nil end
    local scopes = BarOverlayScopes(text, groupOnly)
    local changes = {}
    if #scopes == 0 then
        local setting = Registry and Registry:GetSetting(AbsorbBarGlobalKey(attr))
        local value, relativeDelta = setting and AbsorbBarValue(setting, attrType, text, raw)
        if setting and (value ~= nil or relativeDelta ~= nil) then
            changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta }
        end
    else
        local scopedAttr = attr == "showSelfHealPrediction" and "healPredEnabled" or attr
        for i = 1, #scopes do
            local setting = Registry and Registry:GetSetting("barScope." .. tostring(scopes[i]) .. "." .. scopedAttr)
            local value, relativeDelta = setting and AbsorbBarValue(setting, attrType, text, raw)
            if setting and (value ~= nil or relativeDelta ~= nil) then
                changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta }
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes absorb bar or heal-prediction bar settings directly.",
    }
end

local function BarBorderEnumSpec(text)
    if ContainsAny(text, GeometryPhrases[174]) then
        return "bossTargetOutlineMode", "Boss Target Border"
    end
    if ContainsAny(text, GeometryPhrases[175]) then
        return "aggroMode", "Aggro Shows For"
    end
    if ContainsAny(text, GeometryPhrases[176]) then
        return "dispelBorderTrigger", "Dispel Border Detects"
    end
    if ContainsAny(text, GeometryPhrases[177]) then
        return "aggroOutlineMode", "Aggro Border"
    end
    if ContainsAny(text, GeometryPhrases[178]) then
        return "dispelOutlineMode", "Dispel Border"
    end
    if ContainsAny(text, GeometryPhrases[179]) then
        return "purgeOutlineMode", "Purge Border"
    end
    return nil, nil
end

local function BarBorderEnumGlobalKey(attr)
    if attr == "aggroOutlineMode" then return "general.aggroOutlineMode" end
    if attr == "aggroMode" then return "general.aggroMode" end
    if attr == "dispelOutlineMode" then return "general.dispelOutlineMode" end
    if attr == "dispelBorderTrigger" then return "general.dispelBorderTrigger" end
    if attr == "purgeOutlineMode" then return "general.purgeOutlineMode" end
    if attr == "bossTargetOutlineMode" then return "general.bossTargetOutlineMode" end
    return nil
end

local function ParseBarBorderEnumShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if not ContainsAny(text, GeometryPhrases[180]) then return nil end
    if ContainsAny(text, GeometryPhrases[181]) then return nil end

    local attr, label = BarBorderEnumSpec(text)
    if not attr then return nil end
    local changes = {}
    if attr == "bossTargetOutlineMode" then
        local setting = Registry and Registry:GetSetting(BarBorderEnumGlobalKey(attr))
        local value = setting and EnumValueForText and EnumValueForText(setting, text) or nil
        if setting and value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
    else
        local scopes = BarOverlayScopes(text, false)
        if #scopes == 0 then
            local setting = Registry and Registry:GetSetting(BarBorderEnumGlobalKey(attr))
            local value = setting and EnumValueForText and EnumValueForText(setting, text) or nil
            if setting and value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
        else
            for i = 1, #scopes do
                local setting = Registry and Registry:GetSetting("barScope." .. tostring(scopes[i]) .. "." .. attr)
                local value = setting and EnumValueForText and EnumValueForText(setting, text) or nil
                if setting and value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes aggro, dispel, purge, or boss-target border settings directly.",
    }
end

local function ParseUnitDetailOffsetShortcut(text)
    if ContainsAny(text, GeometryPhrases[182]) then return nil end
    if not ContainsAny(text, GeometryPhrases[183]) then return nil end
    if DetectDirection(text, {}) then return nil end
    local value = FirstNumber(text)
    if value == nil then return nil end
    local spec
    for i = 1, #DETAIL_MOVE_SPECS do
        if ContainsAny(text, DETAIL_MOVE_SPECS[i].terms) then
            spec = DETAIL_MOVE_SPECS[i]
            break
        end
    end
    if not spec then return nil end
    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then
            units = { pageUnit }
        else
            units = ALL_UNITFRAMES
        end
    end
    local changes = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        local sx = Registry and Registry:GetSetting(unit .. "." .. spec.x)
        local sy = Registry and Registry:GetSetting(unit .. "." .. spec.y)
        if sx then changes[#changes + 1] = { setting = sx, value = value, direction = "x" } end
        if sy then changes[#changes + 1] = { setting = sy, value = value, direction = "y" } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "ambiguous",
        choices = changes,
        label = "Which " .. tostring(spec.label or "detail") .. " offset do you want me to set?",
        summary = "The request names an offset but not X/Y or a movement direction.",
    }
end

local CASTBAR_DETAIL_PREFIXES = {
    player = "castbarPlayer",
    target = "castbarTarget",
    focus = "castbarFocus",
    boss = "bossCast",
}

local CASTBAR_ROOT_FIELDS = {
    player = { width = "castbarPlayerBarWidth", height = "castbarPlayerBarHeight", x = "castbarPlayerOffsetX", y = "castbarPlayerOffsetY" },
    target = { width = "castbarTargetBarWidth", height = "castbarTargetBarHeight", x = "castbarTargetOffsetX", y = "castbarTargetOffsetY" },
    focus = { width = "castbarFocusBarWidth", height = "castbarFocusBarHeight", x = "castbarFocusOffsetX", y = "castbarFocusOffsetY" },
    boss = { width = "bossCastbarWidth", height = "bossCastbarHeight", x = "bossCastbarOffsetX", y = "bossCastbarOffsetY" },
}

local function CastbarDetailUnitsOrCurrentPage(text)
    local units = DetectUnits(text)
    local filtered = {}
    for i = 1, #units do
        local unit = units[i]
        if CASTBAR_DETAIL_PREFIXES[unit] then filtered[#filtered + 1] = unit end
    end
    if #filtered > 0 then return filtered end
    local pageUnit = CurrentPageUnit()
    if pageUnit and CASTBAR_DETAIL_PREFIXES[pageUnit] then return { pageUnit } end
    return { "player", "target", "focus", "boss" }
end

local function CastbarRootUnitsOrCurrentPage(text)
    local units = DetectUnits(text)
    local filtered = {}
    for i = 1, #units do
        local unit = units[i]
        if CASTBAR_ROOT_FIELDS[unit] then filtered[#filtered + 1] = unit end
    end
    if #filtered > 0 then return filtered end
    local pageUnit = CurrentPageUnit()
    if pageUnit and CASTBAR_ROOT_FIELDS[pageUnit] then return { pageUnit } end
    return { "player", "target", "focus", "boss" }
end

local function CastbarSizeDirection(text)
    if ContainsAny(text, GeometryPhrases[184]) then return "increase", "width" end
    if ContainsAny(text, GeometryPhrases[185]) then return "decrease", "width" end
    if ContainsAny(text, GeometryPhrases[186]) then return "increase", "height" end
    if ContainsAny(text, GeometryPhrases[187]) then return "decrease", "height" end
    if ContainsAny(text, GeometryPhrases[188]) then return "increase", "both" end
    if ContainsAny(text, GeometryPhrases[189]) then return "decrease", "both" end
    return nil, nil
end

function P.ParseCastbarSizeShortcut(text)
    if not ContainsAny(text, GeometryPhrases[190]) then return nil end
    if ContainsAny(text, GeometryPhrases[191]) then return nil end
    if ContainsAny(text, GeometryPhrases[192]) then
        return nil
    end
    local direction, dimension = CastbarSizeDirection(text)
    if not direction then return nil end

    local widthDelta = P.FrameResizeDelta and P.FrameResizeDelta(text, "width", direction) or (direction == "decrease" and -25 or 25)
    local heightDelta = P.FrameResizeDelta and P.FrameResizeDelta(text, "height", direction) or (direction == "decrease" and -5 or 5)
    local units = CastbarRootUnitsOrCurrentPage(text)
    local changes = {}
    for i = 1, #units do
        local fields = CASTBAR_ROOT_FIELDS[units[i]]
        if fields and (dimension == "width" or dimension == "both") then
            local setting = Registry and Registry:GetSetting("general." .. fields.width)
            if setting then changes[#changes + 1] = { setting = setting, relativeDelta = widthDelta, direction = direction } end
        end
        if fields and (dimension == "height" or dimension == "both") then
            local setting = Registry and Registry:GetSetting("general." .. fields.height)
            if setting then changes[#changes + 1] = { setting = setting, relativeDelta = heightDelta, direction = direction } end
        end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #DetectUnits(text) == 0 and not CurrentPageUnit() then
        return { kind = "ambiguous", choices = changes, label = "Which cast bar do you want me to resize?" }
    end
    return {
        kind = "changes",
        changes = changes,
        label = "Resize Cast Bar",
        bulkSafe = #changes > 1,
        summary = "Adjusts cast bar width or height.",
    }
end

function P.ParseCastbarPlacementShortcut(text)
    if not ContainsAny(text, GeometryPhrases[193]) then return nil end
    if ContainsAny(text, GeometryPhrases[194]) then return nil end
    if ContainsAny(text, GeometryPhrases[195]) then return nil end
    if not ContainsAny(text, GeometryPhrases[196]) then return nil end

    local direction
    if ContainsAny(text, GeometryPhrases[197]) then
        direction = "down"
    elseif ContainsAny(text, GeometryPhrases[198]) then
        direction = "up"
    else
        return nil
    end

    local amount = FirstNumber(text) or 20
    if direction == "down" then amount = -math.abs(amount) else amount = math.abs(amount) end
    local units = CastbarRootUnitsOrCurrentPage(text)
    local changes = {}
    for i = 1, #units do
        local fields = CASTBAR_ROOT_FIELDS[units[i]]
        local setting = fields and Registry and Registry:GetSetting("general." .. fields.y)
        if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #DetectUnits(text) == 0 and not CurrentPageUnit() then
        return { kind = "ambiguous", choices = changes, label = "Which cast bar do you want me to move?" }
    end
    return {
        kind = "changes",
        changes = changes,
        label = direction == "down" and "Move cast bar below frame" or "Move cast bar above frame",
        bulkSafe = #changes > 1,
        summary = "Moves the cast bar above or below its frame.",
    }
end

function P.ParseCastbarTextSizeShortcut(text)
    if not ContainsAny(text, GeometryPhrases[199]) then return nil end
    if ContainsAny(text, GeometryPhrases[200]) then return nil end
    if ContainsAny(text, GeometryPhrases[201]) then return nil end
    if not ContainsAny(text, GeometryPhrases[202]) then
        return nil
    end
    if not ContainsAny(text, GeometryPhrases[203]) then
        return nil
    end

    local field
    local label
    if ContainsAny(text, GeometryPhrases[204]) then
        field = "TimeFontSize"
        label = "Cast Bar time text size"
    elseif ContainsAny(text, GeometryPhrases[205]) then
        field = "SpellNameFontSize"
        label = "Cast Bar spell text size"
    else
        return nil
    end

    local relativeDelta
    if ContainsAny(text, GeometryPhrases[206]) then
        relativeDelta = FirstNumber(text) or 1
    elseif ContainsAny(text, GeometryPhrases[207]) then
        relativeDelta = -(FirstNumber(text) or 1)
    end
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
    end

    local units = CastbarDetailUnitsOrCurrentPage(text)
    local changes = {}
    for i = 1, #units do
        local prefix = CASTBAR_DETAIL_PREFIXES[units[i]]
        local setting = prefix and Registry and Registry:GetSetting("general." .. prefix .. field)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #DetectUnits(text) == 0 and not CurrentPageUnit() then
        return { kind = "ambiguous", choices = changes, label = "Which cast bar text do you want me to resize?" }
    end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Adjusts cast bar text size.",
    }
end

local function ParseCastbarTextMoveShortcut(text)
    if not ContainsAny(text, GeometryPhrases[208]) then return nil end
    if not ContainsAny(text, GeometryPhrases[209]) then return nil end
    local direction = DetectDirection(text, {})
    if not direction then return nil end
    local field
    local label
    if ContainsAny(text, GeometryPhrases[210]) then
        field = (direction == "left" or direction == "right") and "TimeOffsetX" or "TimeOffsetY"
        label = "Move cast bar time text"
    elseif ContainsAny(text, GeometryPhrases[211]) then
        field = (direction == "left" or direction == "right") and "TextOffsetX" or "TextOffsetY"
        label = "Move cast bar spell text"
    else
        return nil
    end
    local amount = FirstNumber(text) or 5
    if direction == "left" or direction == "down" then amount = -amount end
    local units = CastbarDetailUnitsOrCurrentPage(text)
    local changes = {}
    for i = 1, #units do
        local prefix = CASTBAR_DETAIL_PREFIXES[units[i]]
        local setting = prefix and Registry and Registry:GetSetting("general." .. prefix .. field)
        if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #DetectUnits(text) == 0 and not CurrentPageUnit() then
        return { kind = "ambiguous", choices = changes, label = "Which cast bar text do you want me to move?" }
    end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        summary = "Moves Cast Bar text by pixels.",
    }
end

local function ParseUnitOpacityShortcut(text)
    if not ContainsAny(text, GeometryPhrases[212]) then return nil end
    if ContainsAny(text, GeometryPhrases[213]) then return nil end
    if ContainsAny(text, GeometryPhrases[214]) then return nil end
    if ContainsAny(text, GeometryPhrases[215])
        and not ContainsAny(text, GeometryPhrases[216])
    then
        local relativeDelta
        if ContainsAny(text, GeometryPhrases[217]) then
            local amount = FirstNumber(text) or 0.05
            if amount > 1 then amount = amount / 100 end
            relativeDelta = -amount
        elseif ContainsAny(text, GeometryPhrases[218]) then
            local amount = FirstNumber(text) or 0.05
            if amount > 1 then amount = amount / 100 end
            relativeDelta = amount
        else
            relativeDelta = RelativeNumberDeltaForText({ percent = true, step = 0.05 }, text)
        end
        local value
        if relativeDelta == nil then
            value = FirstNumber(text)
            if value == nil then return nil end
            if value > 1 then value = value / 100 end
        end
        local setting = Registry and Registry:GetSetting("player.hpBarAlpha")
        if not setting then return nil end
        return {
            kind = "changes",
            changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
            label = "Set player HP bar opacity",
            summary = "Sets the Player unit-frame HP bar opacity.",
        }
    end
    if ContainsAny(text, GeometryPhrases[219]) then return nil end
    if DetectGroups(text)[1] then return nil end
    local powerOpacity = ContainsAny(text, GeometryPhrases[220])
    local backgroundOpacity = ContainsAny(text, GeometryPhrases[221])
    if ContainsAny(text, GeometryPhrases[222]) then return nil end
    local relativeDelta
    if ContainsAny(text, GeometryPhrases[223]) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = -amount
    elseif ContainsAny(text, GeometryPhrases[224]) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = amount
    else
        relativeDelta = RelativeNumberDeltaForText({ percent = true, step = 0.05 }, text)
    end
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
        if value > 1 then value = value / 100 end
    end
    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then
            units = { pageUnit }
        else
            return {
                kind = "unknown",
                text = "Which unit frame alpha do you want me to change? For example: 'set player alpha to 50', or open a unit page and use 'set alpha to 50'.",
                status = "failed",
            }
        end
    end
    local changes = {}
    local attr = powerOpacity and backgroundOpacity and "powerBarBgAlpha"
        or powerOpacity and "powerBarAlpha"
        or backgroundOpacity and "hpBgAlpha"
        or "hpBarAlpha"
    for i = 1, #units do
        local unit = tostring(units[i])
        local hp = Registry and Registry:GetSetting(unit .. "." .. attr)
        if hp then changes[#changes + 1] = { setting = hp, value = value, relativeDelta = relativeDelta } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = powerOpacity and backgroundOpacity and "Set unit resource background opacity"
            or powerOpacity and "Set unit power bar opacity"
            or backgroundOpacity and "Set unit background opacity"
            or "Set unit opacity",
        summary = powerOpacity and backgroundOpacity and "Sets the resource bar background opacity for the requested unit frame."
            or powerOpacity and "Sets the power bar opacity for the requested unit frame."
            or backgroundOpacity and "Sets the bar background opacity for the requested unit frame."
            or "Sets the HP bar opacity for the requested unit frame.",
    }
end

function A._ParseGroupOpacityShortcut(text)
    if not ContainsAny(text, GeometryPhrases[225]) then return nil end
    if ContainsAny(text, GeometryPhrases[226]) then return nil end
    if ContainsAny(text, GeometryPhrases[227]) then return nil end
    local backgroundOpacity = ContainsAny(text, GeometryPhrases[228])
    if ContainsAny(text, GeometryPhrases[229]) then return nil end
    if ContainsAny(text, GeometryPhrases[230]) then return nil end

    local groups = DetectGroups(text)
    if #groups == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        end
    end
    if #groups == 0 then return nil end

    local relativeDelta
    if ContainsAny(text, GeometryPhrases[231]) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = -amount
    elseif ContainsAny(text, GeometryPhrases[232]) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = amount
    else
        relativeDelta = RelativeNumberDeltaForText({ percent = true, step = 0.05 }, text)
    end
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
        if value > 1 then value = value / 100 end
    end

    local changes = {}
    local attr = backgroundOpacity and "hpBgAlpha" or "hpBarAlpha"
    for i = 1, #groups do
        local scope = tostring(groups[i])
        local hp = Registry and Registry:GetSetting("gf_" .. scope .. "." .. attr)
        if hp then changes[#changes + 1] = { setting = hp, value = value, relativeDelta = relativeDelta } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = backgroundOpacity and "Set group background opacity" or "Set group opacity",
        summary = backgroundOpacity and "Sets the bar background opacity for the requested group-frame target." or "Sets the HP bar opacity for the requested group-frame target.",
    }
end

function P.ParseUnitRangeFadeShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryPhrases[233]) then return nil end
    if ContainsAny(text, GeometryPhrases[234]) then return nil end
    if not ContainsAny(text, GeometryPhrases[235]) then
        return nil
    end

    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then units[1] = pageUnit end
    end
    if #units == 0 then return nil end

    local number = FirstNumber(text)
    local alphaIntent = ContainsAny(text, GeometryPhrases[236]) or number ~= nil
    local layerIntent = ContainsAny(text, GeometryPhrases[237])

    local value
    local relativeDelta
    if alphaIntent then
        if ContainsAny(text, GeometryPhrases[238]) then
            local amount = number or 0.05
            if amount > 1 then amount = amount / 100 end
            relativeDelta = -amount
        elseif ContainsAny(text, GeometryPhrases[239]) then
            local amount = number or 0.05
            if amount > 1 then amount = amount / 100 end
            relativeDelta = amount
        else
            relativeDelta = RelativeNumberDeltaForText({ percent = true, step = 0.05 }, text)
            if relativeDelta == nil then
                if number == nil then return nil end
                value = number
                if value > 1 then value = value / 100 end
            end
        end
    end

    local bool = DetectBoolean(text)
    local enableIntent = not alphaIntent and not layerIntent and (bool ~= nil
        or ContainsAny(text, GeometryPhrases[240]))

    local changes = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        if enableIntent then
            local setting = Registry and Registry:GetSetting(unit .. ".rangeFadeEnabled")
            if setting then
                changes[#changes + 1] = {
                    setting = setting,
                    value = bool ~= false,
                }
            end
        end
        if alphaIntent then
            local setting = Registry and Registry:GetSetting(unit .. ".rangeFadeAlpha")
            if setting then
                changes[#changes + 1] = {
                    setting = setting,
                    value = value,
                    relativeDelta = relativeDelta,
                }
            end
        end
        if layerIntent then
            local setting = Registry and Registry:GetSetting(unit .. ".rangeFadeLayerMode")
            local enumValue = setting and EnumValueForText and EnumValueForText(setting, text) or nil
            if enumValue == nil and ContainsAny(text, GeometryPhrases[241]) then
                enumValue = "health"
            elseif enumValue == nil and ContainsAny(text, GeometryPhrases[242]) then
                enumValue = "frame"
            end
            if setting and enumValue ~= nil then
                changes[#changes + 1] = {
                    setting = setting,
                    value = enumValue,
                }
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Range Fade",
        bulkSafe = #changes > 1,
        summary = "Changes unit-frame Range Fade settings.",
    }
end

function P.ParseUnitHealthColorSchemeShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if not ContainsAny(text, GeometryPhrases[243]) then
        return nil
    end
    if ContainsAny(text, GeometryPhrases[244]) then return nil end

    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then units[1] = pageUnit end
    end
    if #units == 0 then return nil end

    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. ".healthColorMode")
        local value = setting and EnumValueForText and EnumValueForText(setting, text) or nil
        if setting and value ~= nil then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
            }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Health Color Scheme",
        bulkSafe = #changes > 1,
        summary = "Changes the unit-frame health color scheme.",
    }
end

function P.ParseUnitAnchorTargetShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if not ContainsAny(text, GeometryPhrases[245]) then return nil end
    if ContainsAny(text, GeometryPhrases[246]) then return nil end
    if ContainsAny(text, GeometryPhrases[247]) then return nil end

    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then units[1] = pageUnit end
    end
    if #units == 0 then return nil end

    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. ".anchorToUnitframe")
        local value = setting and EnumValueForText and EnumValueForText(setting, text) or nil
        if setting and value ~= nil then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
            }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Anchor Target",
        bulkSafe = #changes > 1,
        summary = "Changes the unit-frame anchor target.",
    }
end

function P.ParseUnitAnchorPointShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if not ContainsAny(text, GeometryPhrases[248]) then return nil end
    if ContainsAny(text, GeometryPhrases[249]) then return nil end

    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then units[1] = pageUnit end
    end
    if #units == 0 then return nil end

    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. ".point")
        local value = setting and EnumValueForText and EnumValueForText(setting, text) or nil
        if setting and value ~= nil then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
            }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Anchor Point",
        bulkSafe = #changes > 1,
        summary = "Changes the unit-frame anchor point.",
    }
end

function P.ParseUnitPowerBarBorderThicknessShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if not ContainsAny(text, GeometryPhrases[250]) then
        return nil
    end
    if ContainsAny(text, GeometryPhrases[251]) then return nil end

    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then units[1] = pageUnit end
    end
    if #units == 0 then return nil end

    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. ".powerBarBorderThickness")
        if setting then
            local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text) or nil
            local value
            if relativeDelta == nil then
                value = A._NumberValueForText and A._NumberValueForText(setting, text) or FirstNumber(text)
            end
            if value ~= nil or relativeDelta ~= nil then
                changes[#changes + 1] = {
                    setting = setting,
                    value = value,
                    relativeDelta = relativeDelta,
                }
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Power Bar Border Thickness",
        bulkSafe = #changes > 1,
        summary = "Changes the unit Power Bar Border Thickness option.",
    }
end

function P.ParseUnitPowerBarBooleanShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if not ContainsAny(text, GeometryPhrases[252]) then return nil end
    if ContainsAny(text, GeometryPhrases[253]) then return nil end

    local attr = "showPowerBar"
    local label = "Power Bar"
    local value
    if ContainsAny(text, GeometryPhrases[254]) then
        attr = "powerBarBorderEnabled"
        label = "Power Bar Border"
        value = DetectBoolean(text)
    elseif ContainsAny(text, GeometryPhrases[255]) then
        attr = "embedPowerBarIntoHealth"
        label = "Embed Power Bar"
        value = DetectBoolean(text)
        if value == nil then value = true end
    elseif ContainsAny(text, GeometryPhrases[256]) then
        if ContainsAny(text, GeometryPhrases[257]) then return nil end
        attr = "powerBarDetached"
        label = "Detach Power Bar"
        value = true
    elseif ContainsAny(text, GeometryPhrases[258]) then
        attr = "powerBarDetached"
        label = "Attach Power Bar"
        value = false
    else
        value = DetectBoolean(text)
    end
    if value == nil then return nil end

    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then units[1] = pageUnit end
    end
    if #units == 0 then return nil end

    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
            }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes a unit Power Bar toggle.",
    }
end

function P.ParsePlayerPowerBarShapeShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if not ContainsAny(text, GeometryPhrases[259]) then
        return nil
    end
    if ContainsAny(text, GeometryPhrases[260]) then return nil end

    local setting = Registry and Registry:GetSetting("player.detachedPowerBarShape")
    local value = setting and EnumValueForText and EnumValueForText(setting, text) or nil
    if not setting or value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Detached Power Bar Shape",
        summary = "Changes the Player detached Power Bar shape.",
    }
end

function P.ParsePlayerPowerOrbSizeShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryPhrases[261]) then return nil end
    if not ContainsAny(text, GeometryPhrases[262]) then
        return nil
    end

    local setting = Registry and Registry:GetSetting("player.detachedPowerOrbSize")
    if not setting then return nil end
    local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, 4) or nil
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = "Detached Power Orb Size",
        summary = "Changes the Player detached Power Bar orb size.",
    }
end

function A._ParseGroupRangeFadeShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, GeometryPhrases[263]) then return nil end
    if ContainsAny(text, GeometryPhrases[264]) then return nil end
    if ContainsAny(text, GeometryPhrases[265]) then return nil end
    if not ContainsAny(text, GeometryPhrases[266]) then
        return nil
    end

    local groups = DetectGroups(text)
    if #groups == 0 then groups = GroupScopesOrCurrentPage(text) end
    if #groups == 0 then return nil end

    local value
    local relativeDelta
    local number = FirstNumber(text)
    local alphaIntent = ContainsAny(text, GeometryPhrases[267]) or number ~= nil
    if alphaIntent then
        if ContainsAny(text, GeometryPhrases[268]) then
            local amount = number or 0.05
            if amount > 1 then amount = amount / 100 end
            relativeDelta = -amount
        elseif ContainsAny(text, GeometryPhrases[269]) then
            local amount = number or 0.05
            if amount > 1 then amount = amount / 100 end
            relativeDelta = amount
        else
            if number ~= nil then
                value = number
                if value > 1 then value = value / 100 end
            end
        end
    end

    local bool = DetectBoolean(text)
    local enableIntent = not alphaIntent and (bool ~= nil
        or ContainsAny(text, GeometryPhrases[270]))

    local changes = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if enableIntent then
            local enabled = Registry and Registry:GetSetting("gf_" .. scope .. ".rangeFadeEnabled")
            if enabled then changes[#changes + 1] = { setting = enabled, value = bool ~= false } end
        end
        if value ~= nil or relativeDelta ~= nil then
            local alpha = Registry and Registry:GetSetting("gf_" .. scope .. ".rangeFadeAlpha")
            if alpha then changes[#changes + 1] = { setting = alpha, value = value, relativeDelta = relativeDelta } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set group range fade",
        bulkSafe = #changes > 1,
        summary = "Adjusts group-frame range fade.",
    }
end

local function GroupColorModeScopes(text)
    local scopes = {}
    local explicitGroupGeneric = ContainsAny(text, GeometryPhrases[271])
    local explicitNamed = false
    if ContainsAny(text, GeometryPhrases[272]) then AddUnique(scopes, "party"); explicitNamed = true end
    if ContainsAny(text, GeometryPhrases[273]) then AddUnique(scopes, "mythicraid"); explicitNamed = true end
    if ContainsAny(text, GeometryPhrases[274]) and not ContainsAny(text, GeometryPhrases[275]) then
        AddUnique(scopes, "raid")
        explicitNamed = true
    end
    if not explicitNamed and explicitGroupGeneric then
        return { "party", "raid", "mythicraid" }
    end
    if #scopes == 0 then
        local detected = DetectGroups(text)
        for i = 1, #detected do AddUnique(scopes, detected[i]) end
    end
    return scopes
end

local function GroupBarColorModeForText(text)
    local bool = DetectBoolean(text)
    if ContainsAny(text, GeometryPhrases[276]) then
        return bool == false and "GLOBAL" or "CLASS"
    end
    if ContainsAny(text, GeometryPhrases[277]) then return bool == false and "GLOBAL" or "GRADIENT" end
    if ContainsAny(text, GeometryPhrases[278]) then return bool == false and "GLOBAL" or "CUSTOM" end
    if ContainsAny(text, GeometryPhrases[279]) then return bool == false and "GLOBAL" or "dark" end
    if ContainsAny(text, GeometryPhrases[280]) then return bool == false and "GLOBAL" or "unified" end
    if ContainsAny(text, GeometryPhrases[281]) then return "GLOBAL" end
    return nil
end

local function ParseGroupFrameColorMode(text)
    if not ContainsAny(text, GeometryPhrases[282]) then
        return nil
    end
    if not ContainsAny(text, GeometryPhrases[283]) then
        return nil
    end
    local value = GroupBarColorModeForText(text)
    if not value then return nil end
    local scopes = GroupColorModeScopes(text)
    if #scopes == 0 then return nil end

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. ".gfBarMode")
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set group-frame bar color mode",
        summary = "Changes the Group Frame Bar Color Mode instead of the global unit frame bar mode.",
    }
end

P.BuildChanges = BuildChanges
P.ParseUnsupportedDetailShortcut = ParseUnsupportedDetailShortcut
P.CurrentPageUnit = CurrentPageUnit
P.DetailUnitsOrCurrentPage = DetailUnitsOrCurrentPage
P.BuildUnitDetailChoices = BuildUnitDetailChoices
P.ParsePortraitDetailShortcut = ParsePortraitDetailShortcut
P.DETAIL_MOVE_SPECS = DETAIL_MOVE_SPECS
P.GROUP_DETAIL_MOVE_SPECS = GROUP_DETAIL_MOVE_SPECS
P.ParseUnitFrameRootMove = OM.ParseUnitFrameRootMove
P.ParseGenericOffsetMove = ParseGenericOffsetMove
P.ParseUnitDetailMove = ParseUnitDetailMove
P.GroupScopesOrCurrentPage = GroupScopesOrCurrentPage
P.ParseGroupDetailMove = ParseGroupDetailMove
P.OutlineScopeSettingForText = OutlineScopeSettingForText
P.ParseAmbiguousGroupOutlineBorderShortcut = ParseAmbiguousGroupOutlineBorderShortcut
P.ParseBorderThicknessShortcut = ParseBorderThicknessShortcut
P.ParseBarOutlineHighlightShortcut = ParseBarOutlineHighlightShortcut
P.ParseAbsorbBarShortcut = ParseAbsorbBarShortcut
P.ParseBarBorderEnumShortcut = ParseBarBorderEnumShortcut
P.ParseUnitDetailOffsetShortcut = ParseUnitDetailOffsetShortcut
P.CASTBAR_DETAIL_PREFIXES = CASTBAR_DETAIL_PREFIXES
P.CastbarDetailUnitsOrCurrentPage = CastbarDetailUnitsOrCurrentPage
P.ParseCastbarTextMoveShortcut = ParseCastbarTextMoveShortcut
P.ParseUnitOpacityShortcut = ParseUnitOpacityShortcut
P.GroupColorModeScopes = GroupColorModeScopes
P.GroupBarColorModeForText = GroupBarColorModeForText
P.ParseGroupFrameColorMode = ParseGroupFrameColorMode
