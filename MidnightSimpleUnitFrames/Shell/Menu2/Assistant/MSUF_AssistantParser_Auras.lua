-- Assistant Aura parser: parses aura-specific natural language into setting plans.
-- Mutating aura commands must preserve combat safety, confirmation, and undo metadata.
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

-- Aura parser shard for quick presets, blacklist commands, and aura-lane bulk intent.
-- Keep the language matching here separate from Auras3 runtime code: this file decides what
-- the user likely meant, while Auras3 owns saved data and visual refresh.
local Trim = P.Trim
local Normalize = P.Normalize
local HasPhrase = P.HasPhrase
local ContainsAny = P.ContainsAny
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local FirstNumber = P.FirstNumber
local Compact = P.Compact
local DetectDirection = P.DetectDirection

local AURA_BLACKLIST_PRESETS = {
    { key = "RAID_BUFFS", aliases = { "raid buffs", "raid buff", "long term raid buffs", "raid buff preset" } },
    { key = "PRESERVATION_EVOKER", aliases = { "preservation evoker", "pres evoker" } },
    { key = "AUGMENTATION_EVOKER", aliases = { "augmentation evoker", "aug evoker" } },
    { key = "RESTO_DRUID", aliases = { "resto druid", "restoration druid" } },
    { key = "DISC_PRIEST", aliases = { "disc priest", "discipline priest" } },
    { key = "HOLY_PRIEST", aliases = { "holy priest" } },
    { key = "MISTWEAVER_MONK", aliases = { "mistweaver monk", "mw monk" } },
    { key = "RESTO_SHAMAN", aliases = { "resto shaman", "restoration shaman" } },
    { key = "HOLY_PALADIN", aliases = { "holy paladin", "holy pala" } },
    { key = "BLESSING_BRONZE", aliases = { "blessing of the bronze", "bronze blessing" } },
    { key = "SELF_BUFFS", aliases = { "self buffs", "self buff", "long term self buffs" } },
    { key = "ROGUE_POISONS", aliases = { "rogue poisons", "rogue poison", "poisons" } },
    { key = "SHAMAN_IMBUE", aliases = { "shaman imbues", "shaman imbue", "shaman imbuements", "imbues" } },
    { key = "RESOURCE_AURAS", aliases = { "resource auras", "resource aura", "resource buffs", "resource buff" } },
    { key = "COOLDOWNS", aliases = { "cooldowns", "cooldown aura", "cooldown auras" } },
    { key = "SATED", aliases = { "sated", "exhaustion", "heroism exhaustion", "bloodlust exhaustion" } },
    { key = "DESERTER", aliases = { "deserter", "deserteur" } },
}

local function AuraBlacklistScope(text)
    if ContainsAny(text, { "shared", "global", "all auras", "all aura" }) then return "shared" end
    local units = DetectUnits(text)
    for i = 1, #units do
        local unit = units[i]
        if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then return unit end
    end
    return "shared"
end

local AURA_QUICK_PRESETS = {
    { key = "clean", aliases = { "clean", "clean 6 12", "clean aura", "clean auras" } },
    { key = "focused", aliases = { "focused", "focused 10 16", "focused aura", "focused auras" } },
    { key = "performance", aliases = { "fast", "performance", "fast 4 8", "performance aura", "performance auras" } },
}

local AURA_GEOMETRY_UNITS = { "player", "target", "focus", "boss" }
local AURA_GEOMETRY_GROUPS = { "party", "raid", "mythicraid" }

local function AddAuraGeometryScope(out, kind, key)
    for i = 1, #out do
        local scope = out[i]
        if scope.kind == kind and scope.key == key then return end
    end
    out[#out + 1] = { kind = kind, key = key }
end

local function AddAuraGeometryUnits(out)
    for i = 1, #AURA_GEOMETRY_UNITS do
        AddAuraGeometryScope(out, "unit", AURA_GEOMETRY_UNITS[i])
    end
end

local function AddAuraGeometryGroups(out)
    for i = 1, #AURA_GEOMETRY_GROUPS do
        AddAuraGeometryScope(out, "group", AURA_GEOMETRY_GROUPS[i])
    end
end

local function HasAllAuraGeometryScope(text)
    return HasPhrase(text, "all auras")
        or HasPhrase(text, "all aura icons")
        or HasPhrase(text, "all aura icon")
        or HasPhrase(text, "all buff icons")
        or HasPhrase(text, "all buff icon")
        or HasPhrase(text, "all buffs")
        or HasPhrase(text, "all debuff icons")
        or HasPhrase(text, "all debuff icon")
        or HasPhrase(text, "all debuffs")
        or HasPhrase(text, "every aura")
        or HasPhrase(text, "every aura icon")
        or HasPhrase(text, "every buff")
        or HasPhrase(text, "every debuff")
        or HasPhrase(text, "aura icons everywhere")
        or HasPhrase(text, "auras everywhere")
        or HasPhrase(text, "buffs everywhere")
        or HasPhrase(text, "debuffs everywhere")
        or HasPhrase(text, "alle auren")
        or HasPhrase(text, "alle aura icons")
        or HasPhrase(text, "alle buffs")
        or HasPhrase(text, "alle debuffs")
        or HasPhrase(text, "auren ueberall")
end

local function HasUnitAuraGeometryScope(text)
    return HasPhrase(text, "unit auras")
        or HasPhrase(text, "unit aura")
        or HasPhrase(text, "unit aura icons")
        or HasPhrase(text, "unit aura icon")
        or HasPhrase(text, "unitframe auras")
        or HasPhrase(text, "unitframe aura")
        or HasPhrase(text, "unitframe aura icons")
        or HasPhrase(text, "unit frame auras")
        or HasPhrase(text, "unit frame aura")
        or HasPhrase(text, "unit frame aura icons")
        or HasPhrase(text, "all unit auras")
        or HasPhrase(text, "all unit aura")
        or HasPhrase(text, "all unit aura icons")
        or HasPhrase(text, "all unitframe auras")
        or HasPhrase(text, "all unitframe aura")
        or HasPhrase(text, "all unitframe aura icons")
        or HasPhrase(text, "all unit frame auras")
        or HasPhrase(text, "all unit frame aura")
        or HasPhrase(text, "all unit frame aura icons")
        or HasPhrase(text, "alle unitframe auren")
        or HasPhrase(text, "alle unit frame auren")
end

local function HasGenericGroupAuraGeometryScope(text)
    return ContainsAny(text, {
        "group aura", "group auras", "group aura icon", "group aura icons",
        "group buff", "group buffs", "group buff icon", "group buff icons",
        "group debuff", "group debuffs", "group debuff icon", "group debuff icons",
        "group frame aura", "group frame auras", "group frame buff", "group frame buffs",
        "group frame debuff", "group frame debuffs",
        "gruppen aura", "gruppen auren", "gruppen buff", "gruppen buffs",
        "gruppen debuff", "gruppen debuffs", "gruppenframe aura", "gruppenframe auren",
    })
end

local function HasConcreteGroupAuraGeometryScope(text)
    return ContainsAny(text, {
        "party", "party frame", "party frames", "party aura", "party auras",
        "party buff", "party buffs", "party debuff", "party debuffs",
        "raid", "raid frame", "raid frames", "raid aura", "raid auras",
        "raid buff", "raid buffs", "raid debuff", "raid debuffs",
        "mythic", "mythic raid", "mythicraid", "mythic raid aura", "mythic raid auras",
        "all group", "all group aura", "all group auras", "all group buffs", "all group debuffs",
        "alle gruppen aura", "alle gruppen auren", "alle gruppen buffs", "alle gruppen debuffs",
        "every group aura", "every group buff", "every group debuff",
    })
end
local function AuraGeometryLanes(text)
    if ContainsAny(text, { "buff", "buffs" }) then return { "buff" } end
    if ContainsAny(text, { "debuff", "debuffs" }) then return { "debuff" } end
    if ContainsAny(text, { "aura", "auras", "auren", "aura icon", "aura icons", "aura symbole", "auren symbole" }) then return { "buff", "debuff" } end
    return nil
end

local function AuraGeometryScopes(text)
    local groups = DetectGroups(text)
    if #groups > 0 then
        local out = {}
        for i = 1, #groups do
            if groups[i] == "party" or groups[i] == "raid" or groups[i] == "mythicraid" then
                AddAuraGeometryScope(out, "group", groups[i])
            end
        end
        if #out > 0 then return out end
    end

    local units = DetectUnits(text)
    local out = {}
    for i = 1, #units do
        for j = 1, #AURA_GEOMETRY_UNITS do
            if units[i] == AURA_GEOMETRY_UNITS[j] then out[#out + 1] = { kind = "unit", key = units[i] } end
        end
    end
    if #out > 0 then return out end

    if HasUnitAuraGeometryScope(text) then
        AddAuraGeometryUnits(out)
        return out
    end
    if HasAllAuraGeometryScope(text) then
        AddAuraGeometryUnits(out)
        AddAuraGeometryGroups(out)
        return out
    end
    return nil
end

local function AuraGeometrySettingKey(scope, lane, attr)
    if scope.kind == "group" then
        local groupAttr = attr == "offsetX" and "x" or attr == "offsetY" and "y" or attr
        return "gf_" .. tostring(scope.key) .. ".auras." .. tostring(lane) .. "." .. tostring(groupAttr)
    end
    return "auras3." .. tostring(scope.key) .. "." .. tostring(lane) .. "." .. tostring(attr)
end

local function AuraGeometryAxis(text, direction)
    if ContainsAny(text, { "x offset", "offset x", "horizontal offset", "left", "right", "links", "rechts" }) then return "offsetX" end
    if ContainsAny(text, { "y offset", "offset y", "vertical offset", "up", "down", "oben", "unten", "hoch", "runter" }) then return "offsetY" end
    if direction == "left" or direction == "right" then return "offsetX" end
    if direction == "up" or direction == "down" then return "offsetY" end
    return nil
end

local function AuraGeometryAttribute(text, direction)
    if ContainsAny(text, { "cooldown anchor", "timer anchor", "cooldown text anchor", "timer text anchor" }) then
        return "cooldownAnchor"
    end
    if ContainsAny(text, { "filter token", "filter type", "inclusive filter" })
        or (ContainsAny(text, { "filter" }) and not ContainsAny(text, { "exclusive", "category", "blacklist" })) then
        return "filterToken"
    end
    if ContainsAny(text, { "growth direction", "growth", "grow direction" })
        or (ContainsAny(text, { "grow", "grows" }) and direction) then
        return "growth"
    end
    if ContainsAny(text, { "anchor", "anchor point", "position anchor", "bottom left", "bottom right", "top left", "top right", "bottomleft", "bottomright", "topleft", "topright" }) then
        return "anchor"
    end
    local hasSizeIntent = ContainsAny(text, { "icon size", "icons size", "size", "bigger", "larger", "smaller", "shrink", "groesse", "grosse" })
    if not hasSizeIntent and ContainsAny(text, {
        "max", "maximum", "max icons", "maximum icons", "max count", "maximum count",
        "icon count", "aura count", "buff count", "debuff count", "count",
        "cap", "caps", "capped", "aura cap", "buff cap", "debuff cap",
        "limit", "limits", "limited", "icon limit", "aura limit", "buff limit", "debuff limit",
    }) then
        return "max"
    end
    if ContainsAny(text, { "per row", "icons per row", "wrap count", "row count" }) then
        return "perRow"
    end
    if ContainsAny(text, { "spacing", "gap", "icon gap" }) then
        return "spacing"
    end
    if ContainsAny(text, { "layer", "z", "z layer", "z level", "z-level", "z order", "z-order", "z index", "z-index", "draw layer", "frame level", "strata", "frame strata" }) then
        return "layer"
    end
    if hasSizeIntent then
        return "size"
    end
    if ContainsAny(text, { "move", "nudge", "shift", "offset", "left", "right", "up", "down", "verschiebe", "links", "rechts", "oben", "unten" }) then
        return AuraGeometryAxis(text, direction)
    end
    return nil
end

local function AuraGeometryEnumValue(text, setting, attr, direction)
    local aliases = setting and setting.valueAliases
    local compactText = Compact(text)
    local bestValue, bestLen
    if type(aliases) == "table" then
        for alias, value in pairs(aliases) do
            local compactAlias = Compact(alias)
            if compactAlias ~= "" and compactText:find(compactAlias, 1, true) and (not bestLen or #compactAlias > bestLen) then
                bestValue, bestLen = value, #compactAlias
            end
        end
    end
    if bestValue ~= nil then return bestValue end
    if attr == "growth" and direction then
        local dir = tostring(direction):upper()
        if dir == "LEFT" or dir == "RIGHT" or dir == "UP" or dir == "DOWN" then
            if setting and setting.values then
                for i = 1, #setting.values do
                    if setting.values[i] == dir then return dir end
                end
            end
            if dir == "LEFT" then return "LEFTDOWN" end
            if dir == "UP" then return "RIGHTUP" end
            return "RIGHTDOWN"
        end
    end
    return nil
end

local function AuraGeometryDelta(text, setting, attr, direction)
    if setting and setting.type == "enum" then
        return AuraGeometryEnumValue(text, setting, attr, direction), nil
    end
    local relative = P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text)
    if relative ~= nil then return nil, relative end
    if attr == "max" or attr == "perRow" or attr == "spacing" or attr == "layer" then
        return FirstNumber(text), nil
    end
    if attr == "size" then
        local value = FirstNumber(text)
        if value ~= nil then return value, nil end
        if ContainsAny(text, { "bigger", "larger", "grow", "increase", "raise", "more", "groesser", "mehr" }) then return nil, 1 end
        if ContainsAny(text, { "smaller", "shrink", "decrease", "lower", "less", "kleiner", "weniger" }) then return nil, -1 end
        return nil, nil
    end
    if direction then
        local amount = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then amount = -amount end
        return nil, amount
    end
    return FirstNumber(text), nil
end

local function ParseAuraGeometryShortcut(text)
    if not ContainsAny(text, { "aura", "auras", "auren", "buff", "buffs", "debuff", "debuffs" }) then return nil end
    if ContainsAny(text, { "copy", "preset", "blacklist", "category" }) then return nil end
    local explicitNonGroupAuraScope = ContainsAny(text, {
        "shared", "shared aura", "shared auras", "global", "all aura", "all auras",
        "player aura", "player auras", "player buff", "player buffs", "player debuff", "player debuffs",
        "target aura", "target auras", "target buff", "target buffs", "target debuff", "target debuffs",
        "focus aura", "focus auras", "focus buff", "focus buffs", "focus debuff", "focus debuffs",
        "pet aura", "pet auras", "pet buff", "pet buffs", "pet debuff", "pet debuffs",
        "boss aura", "boss auras", "boss buff", "boss buffs", "boss debuff", "boss debuffs",
    })
    local groupFastIntent = not explicitNonGroupAuraScope
        and ContainsAny(text, { "party", "party frame", "party frames", "raid", "raid frame", "raid frames", "mythic raid", "group frame", "group frames" })
        and (ContainsAny(text, { "cooldown anchor", "timer anchor", "filter token", "filter type", "inclusive filter" })
            or (ContainsAny(text, { "filter" }) and not ContainsAny(text, { "exclusive", "category", "blacklist" })))
    if ContainsAny(text, { "filter" }) and not groupFastIntent then return nil end
    if not groupFastIntent and ContainsAny(text, { "stack", "stacks", "stack count", "cooldown text", "timer text", "cooldown", "timer" })
        and ContainsAny(text, { "text", "font", "anchor", "x offset", "offset x", "y offset", "offset y", "text x", "text y" }) then
        return nil
    end
    if HasGenericGroupAuraGeometryScope(text) and not HasConcreteGroupAuraGeometryScope(text) then return nil end

    local lanes = AuraGeometryLanes(text)
    local scopes = AuraGeometryScopes(text)
    if not lanes or not scopes then return nil end

    local direction = DetectDirection(text, {})
    local attr = AuraGeometryAttribute(text, direction)
    if not attr then return nil end

    local changes = {}
    for i = 1, #scopes do
        for j = 1, #lanes do
            local key = AuraGeometrySettingKey(scopes[i], lanes[j], attr)
            local setting = Registry and Registry:GetSetting(key)
            if setting then
                local value, relativeDelta = AuraGeometryDelta(text, setting, attr, direction)
                if value ~= nil or relativeDelta ~= nil then
                    changes[#changes + 1] = {
                        setting = setting,
                        value = value,
                        relativeDelta = relativeDelta,
                        direction = direction,
                    }
                end
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Change Aura layout",
        summary = "Adjusts Aura layout options.",
    }
end

local function AuraQuickPresetForText(text)
    for i = 1, #AURA_QUICK_PRESETS do
        local preset = AURA_QUICK_PRESETS[i]
        if ContainsAny(text, preset.aliases) then return preset.key end
    end
    return nil
end

local function AuraEditScopeForText(text)
    if ContainsAny(text, { "shared", "global", "all auras", "shared auras" }) then return "shared" end
    if ContainsAny(text, { "player aura", "player auras", "spieler aura", "spieler auren" }) then return "player" end
    if ContainsAny(text, { "target aura", "target auras", "ziel aura", "ziel auren" }) then return "target" end
    if ContainsAny(text, { "focus aura", "focus auras", "fokus aura", "fokus auren" }) then return "focus" end
    if ContainsAny(text, { "boss aura", "boss auras", "boss1 aura", "boss1 auras", "boss 1 aura", "boss 1 auras" }) then return "boss" end
    if ContainsAny(text, { "party aura", "party auras", "party frame aura", "party frame auras", "group aura", "group auras", "gruppen aura", "gruppen auren" }) then return "party" end
    if ContainsAny(text, { "raid aura", "raid auras", "raid frame aura", "raid frame auras", "mythic raid aura", "mythic raid auras", "schlachtzug aura", "schlachtzug auren" }) then return "raid" end
    local units = DetectUnits(text)
    for i = 1, #units do
        if units[i] == "player" or units[i] == "target" or units[i] == "focus" or units[i] == "boss" then return units[i] end
    end
    local groups = DetectGroups(text)
    for i = 1, #groups do
        if groups[i] == "party" then return "party" end
        if groups[i] == "raid" or groups[i] == "mythicraid" then return "raid" end
    end
    local scope = M and M.auraScope
    if scope == "player" or scope == "target" or scope == "focus" or scope == "boss" or scope == "party" or scope == "raid" or scope == "shared" then return scope end
    return nil
end

local function AuraBlacklistPresetForText(text)
    for i = 1, #AURA_BLACKLIST_PRESETS do
        local spec = AURA_BLACKLIST_PRESETS[i]
        if ContainsAny(text, spec.aliases) then return spec.key end
    end
    return nil
end

local function AuraGroupBlacklistScope(text)
    if ContainsAny(text, { "party", "party frames", "gruppe" }) then return "party" end
    if ContainsAny(text, { "raid", "raid frames", "mythic raid", "mythicraid", "schlachtzug" }) then return "raid" end
    if ContainsAny(text, { "group frames", "gruppenframes", "all groups" }) then return "raid" end
    local groups = DetectGroups(text)
    for i = 1, #groups do
        if groups[i] == "party" then return "party" end
    end
    for i = 1, #groups do
        if groups[i] == "raid" or groups[i] == "mythicraid" then return "raid" end
    end
    return "raid"
end

local function AuraGroupBlacklistLane(text)
    if ContainsAny(text, { "debuff", "debuffs" }) then return "debuff" end
    return "buff"
end

local function AuraGroupBlacklistCategoryForText(text)
    if A.ResolveAuraGroupCategory then
        local resolved = A.ResolveAuraGroupCategory(text)
        if resolved then return resolved end
    end
    return AuraBlacklistPresetForText(text)
end

local function CleanAuraBlacklistSpellValue(value)
    value = Trim(tostring(value or ""))
    local spellID = value:match("[Hh]spell:(%d+)") or value:match("spell:(%d+)")
    if spellID then return "spell:" .. tostring(spellID) end
    local linkedName = value:match("|h%[(.-)%]|h")
    if linkedName and linkedName ~= "" then value = linkedName end
    value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
    value = value:gsub("^%[", ""):gsub("%]$", "")
    value = value:gsub("^spell%s+", "")
    value = value:gsub("^named%s+", "")
    value = value:gsub("^called%s+", "")
    value = value:gsub("^#%s*", "")
    value = value:gsub("[%s%.%,%;%!%?]+$", "")
    value = Trim(value)
    local normalized = Normalize(value)
    if normalized == "" or normalized == "all" or normalized == "all spell" or normalized == "all spells"
        or normalized == "all aura" or normalized == "all auras" or normalized == "every spell"
        or normalized == "every aura" or normalized == "aura" or normalized == "auras"
        or normalized == "buff" or normalized == "buffs" or normalized == "debuff"
        or normalized == "debuffs" or normalized == "spell" or normalized == "spells" then
        return nil
    end
    return value
end

local function AuraBlacklistSpellValue(raw)
    raw = tostring(raw or "")
    local value = raw:match("(spell:%d+)") or raw:match("#%s*(%d+)") or raw:match("(%d%d+)")
    if value then return value end

    local patterns = {
        "[Aa]dd%s+(.+)%s+to%s+.+[Bb]lacklist",
        "[Aa]dd%s+(.+)%s+to%s+.+[Aa]uras?",
        "[Bb]lacklist%s+(.+)%s+[Ff]or%s+",
        "[Bb]lacklist%s+(.+)%s+[Oo]n%s+",
        "[Bb]lock%s+(.+)%s+[Ff]or%s+",
        "[Bb]lock%s+(.+)%s+[Oo]n%s+",
        "[Ii]gnore%s+(.+)%s+[Ff]or%s+",
        "[Ii]gnore%s+(.+)%s+[Oo]n%s+",
        "[Hh]ide%s+(.+)%s+[Ff]or%s+",
        "[Hh]ide%s+(.+)%s+[Oo]n%s+",
        "[Vv]erstecke%s+(.+)%s+[Aa]uf%s+",
        "[Vv]erstecke%s+(.+)%s+[Ff]uer%s+",
        "[Aa]usblenden%s+(.+)%s+[Aa]uf%s+",
        "[Aa]usblenden%s+(.+)%s+[Ff]uer%s+",
        "[Ss]uppress%s+(.+)%s+[Ff]or%s+",
        "[Ss]uppress%s+(.+)%s+[Oo]n%s+",
        "[Ss]top%s+showing%s+(.+)%s+[Ff]or%s+",
        "[Ss]top%s+showing%s+(.+)%s+[Oo]n%s+",
        "[Rr]emove%s+(.+)%s+from%s+.+[Bb]lacklist",
        "[Rr]emove%s+(.+)%s+from%s+.+[Aa]uras?",
        "[Aa]llow%s+(.+)%s+[Ff]or%s+.+[Aa]uras?",
        "[Aa]llow%s+(.+)%s+[Oo]n%s+.+[Aa]uras?",
        "[Aa]llow%s+(.+)%s+[Ff]or%s+.+[Bb]lacklist",
        "[Aa]llow%s+(.+)%s+[Oo]n%s+.+[Bb]lacklist",
        "[Uu]nblacklist%s+(.+)%s+[Ff]or%s+",
        "[Uu]nblacklist%s+(.+)%s+[Oo]n%s+",
        "[Uu]nblock%s+(.+)%s+[Ff]or%s+",
        "[Uu]nblock%s+(.+)%s+[Oo]n%s+",
        "[Uu]nhide%s+(.+)%s+[Ff]or%s+",
        "[Uu]nhide%s+(.+)%s+[Oo]n%s+",
        "[Ss]top%s+hiding%s+(.+)%s+[Ff]or%s+",
        "[Ss]top%s+hiding%s+(.+)%s+[Oo]n%s+",
        "[Ss]how%s+(.+)%s+again%s+[Ff]or%s+",
        "[Ss]how%s+(.+)%s+again%s+[Oo]n%s+",
        "[Ll]et%s+(.+)%s+show%s+[Ff]or%s+",
        "[Ll]et%s+(.+)%s+show%s+[Oo]n%s+",
    }
    for i = 1, #patterns do
        value = CleanAuraBlacklistSpellValue(raw:match(patterns[i]))
        if value then return value end
    end
    return nil
end

P.AURA_BLACKLIST_PRESETS = AURA_BLACKLIST_PRESETS
P.AuraBlacklistScope = AuraBlacklistScope
P.AURA_QUICK_PRESETS = AURA_QUICK_PRESETS
P.AuraQuickPresetForText = AuraQuickPresetForText
P.AuraEditScopeForText = AuraEditScopeForText
P.ParseAuraGeometryShortcut = ParseAuraGeometryShortcut
P.AuraGeometryShortcut = ParseAuraGeometryShortcut
P.AuraBlacklistPresetForText = AuraBlacklistPresetForText
P.AuraGroupBlacklistScope = AuraGroupBlacklistScope
P.AuraGroupBlacklistLane = AuraGroupBlacklistLane
P.AuraGroupBlacklistCategoryForText = AuraGroupBlacklistCategoryForText
P.AuraBlacklistSpellValue = AuraBlacklistSpellValue
