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
local DetectBoolean = P.DetectBoolean

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
    if ContainsAny(text, { "copy", "preset", "blacklist", "category", "private aura", "private auras" }) then return nil end
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
    if ContainsAny(text, { "stack size", "stack text size", "stack font", "cooldown size", "cooldown text size", "cooldown font", "timer size", "timer text size", "timer font" })
        and not ContainsAny(text, { "icon size", "icons size" })
    then
        return nil
    end
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

local function AuraShortcutScopes(text, allowShared)
    local out = {}
    if allowShared and ContainsAny(text, { "shared", "global", "shared aura", "shared auras" }) then
        AddAuraGeometryScope(out, "unit", "shared")
    end

    local groups = DetectGroups(text)
    for i = 1, #groups do
        if groups[i] == "party" or groups[i] == "raid" or groups[i] == "mythicraid" then
            AddAuraGeometryScope(out, "group", groups[i])
        end
    end

    local units = DetectUnits(text)
    for i = 1, #units do
        local unit = units[i]
        if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
            AddAuraGeometryScope(out, "unit", unit)
        end
    end

    if #out == 0 and HasUnitAuraGeometryScope(text) then
        if allowShared then AddAuraGeometryScope(out, "unit", "shared") end
        AddAuraGeometryUnits(out)
    end
    if #out == 0 and HasAllAuraGeometryScope(text) then
        if allowShared then AddAuraGeometryScope(out, "unit", "shared") end
        AddAuraGeometryUnits(out)
        AddAuraGeometryGroups(out)
    end

    if #out > 0 then return out end

    local scope = AuraEditScopeForText(text)
    if scope == "party" or scope == "raid" then
        AddAuraGeometryScope(out, "group", scope)
    elseif scope == "shared" then
        if allowShared then AddAuraGeometryScope(out, "unit", "shared") end
    elseif scope == "player" or scope == "target" or scope == "focus" or scope == "boss" then
        AddAuraGeometryScope(out, "unit", scope)
    end
    return #out > 0 and out or nil
end

local function AuraScopeOverrideScopes(text)
    local scopes = AuraShortcutScopes(text, false)
    if not scopes then return nil end

    local out = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        if scope.kind == "unit" and (scope.key == "player" or scope.key == "target" or scope.key == "focus" or scope.key == "boss") then
            AddAuraGeometryScope(out, "unit", scope.key)
        end
    end
    return #out > 0 and out or nil
end

local function AuraEnumAliasValue(text, aliases)
    if type(aliases) ~= "table" then return nil end
    local compactText = Compact(text)
    local bestValue, bestLen
    for alias, value in pairs(aliases) do
        local compactAlias = Compact(alias)
        if compactAlias ~= "" and (HasPhrase(text, alias) or (#compactAlias >= 5 and compactText:find(compactAlias, 1, true))) then
            local len = #compactAlias
            if not bestLen or len > bestLen then
                bestValue, bestLen = value, len
            end
        end
    end
    return bestValue
end

local function AuraCooldownSwipeDirectionValue(text)
    local data = A.AurasRegistryData or {}
    return AuraEnumAliasValue(text, data.AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES)
end

local function AuraDurationBarPositionValue(text)
    local data = A.AurasRegistryData or {}
    return AuraEnumAliasValue(text, data.AURA_DURATION_BAR_POSITION_ALIASES)
end

local function AuraDurationBarDirectionValue(text)
    local data = A.AurasRegistryData or {}
    return AuraEnumAliasValue(text, data.AURA_DURATION_BAR_DIRECTION_ALIASES)
end

local function AuraDebuffBorderModeValue(text)
    if ContainsAny(text, { "symbol", "with symbol", "with icon", "border symbol", "border and symbol", "border plus symbol" }) then return "SYMBOL" end
    if ContainsAny(text, { "off", "none", "disabled", "hide", "hidden", "turn off" }) then return "OFF" end
    if ContainsAny(text, { "border only", "just border", "outline", "outline only" }) then return "BORDER" end
    if HasPhrase(text, "to border") or HasPhrase(text, "as border") or HasPhrase(text, "mode border") or HasPhrase(text, "use border") then return "BORDER" end
    return nil
end

local function AuraShortcutLanes(text)
    local lanes = AuraGeometryLanes(text)
    if lanes then return lanes end
    return { "buff", "debuff" }
end

local function AddAuraShortcutChange(changes, setting, value, label)
    if not setting then return end
    changes[#changes + 1] = {
        setting = setting,
        value = value,
        label = label,
    }
end

local UNIT_AURA_FILTER_KEYS = {
    buff = { "onlyMine", "raid", "raidInCombat", "includeNameplateOnly", "cancelable", "notCancelable", "externalDefensive", "bigDefensive" },
    debuff = { "onlyMine", "raid", "raidInCombat", "includeNameplateOnly", "includeDispellable", "crowdControl" },
}

local function AddAuraRegisteredChange(changes, key, value, label)
    local setting = Registry and Registry:GetSetting(key)
    AddAuraShortcutChange(changes, setting, value, label or (setting and setting.label) or key)
end

local function AuraBooleanValue(text)
    local value = DetectBoolean and DetectBoolean(text)
    if value ~= nil then return value end
    if ContainsAny(text, { "off", "disable", "disabled", "hide", "hidden", "without", "no ", "aus", "deaktivieren" }) then
        return false
    end
    return true
end

local function AuraDirectionValue(text)
    if ContainsAny(text, { "up", "oben", "hoch" }) then return "UP" end
    if ContainsAny(text, { "down", "unten", "runter" }) then return "DOWN" end
    if ContainsAny(text, { "left", "links" }) then return "LEFT" end
    if ContainsAny(text, { "right", "rechts" }) then return "RIGHT" end
    return nil
end

local function AuraDirectSettingChange(key, value, label)
    if value == nil then return nil end
    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, label = label or setting.label } },
        label = label or setting.label or "Aura setting",
        summary = "Changes the matched Aura option.",
    }
end

local AURA_STYLE_BOOL_SPECS = {
    { key = "showStackCount", label = "Show Stack Count", aliases = { "show stack count", "stack count", "stacks" } },
    { key = "showCooldownText", label = "Show Cooldown Text", aliases = { "show cooldown text", "cooldown text", "timer text" } },
    { key = "showCooldownSwipe", label = "Show Cooldown Swipe", aliases = { "show cooldown swipe", "cooldown swipe", "timer swipe" } },
    { key = "showDurationBar", label = "Show Duration Bar", aliases = { "show duration bar", "duration bar", "timer bar", "aura duration bar", "aura timer bar" } },
}

local function AuraStyleScopes(text)
    local scopes = AuraShortcutScopes(text, true)
    if scopes then
        local out = {}
        for i = 1, #scopes do
            local scope = scopes[i]
            if scope.kind == "unit"
                and (scope.key == "shared" or scope.key == "player" or scope.key == "target" or scope.key == "focus" or scope.key == "boss")
            then
                AddAuraGeometryScope(out, "unit", scope.key)
            elseif scope.kind == "group" and (scope.key == "party" or scope.key == "raid" or scope.key == "mythicraid") then
                AddAuraGeometryScope(out, "group", scope.key)
            end
        end
        if #out > 0 then return out end
    end
    if ContainsAny(text, { "shared", "global", "all unit auras", "unit auras", "unitframe auras" }) then
        return { { kind = "unit", key = "shared" } }
    end
    return nil
end

local function ParseAuraStyleBoolShortcut(text)
    if not ContainsAny(text, { "stack", "stacks", "cooldown text", "timer text", "cooldown swipe", "timer swipe", "duration bar", "timer bar" }) then
        return nil
    end
    if ContainsAny(text, {
        "anchor", "x offset", "offset x", " y offset", "offset y", "text x", "text y",
        "size", "font", "height", "position", "edge", "fill mode", "direction", "reverse",
        "decimals", "decimal", "seconds", "threshold", "filter", "exclusive", "color", "colors", "colour", "colours",
    }) then
        return nil
    end

    local spec
    for i = 1, #AURA_STYLE_BOOL_SPECS do
        if ContainsAny(text, AURA_STYLE_BOOL_SPECS[i].aliases) then
            spec = AURA_STYLE_BOOL_SPECS[i]
            break
        end
    end
    if not spec then return nil end

    local scopes = AuraStyleScopes(text)
    if not scopes then return nil end
    local lanes = nil
    if ContainsAny(text, { "debuff", "debuffs" }) then
        lanes = { "debuff" }
    elseif ContainsAny(text, { "buff", "buffs" }) then
        lanes = { "buff" }
    end

    local value = AuraBooleanValue(text)
    if value == nil then return nil end

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        if scope.kind == "group" then
            if lanes then
                for j = 1, #lanes do
                    AddAuraRegisteredChange(changes, AuraGeometrySettingKey(scope, lanes[j], spec.key), value, spec.label)
                end
            end
        elseif lanes then
            for j = 1, #lanes do
                AddAuraRegisteredChange(changes, "auras3." .. tostring(scope.key) .. "." .. lanes[j] .. "." .. spec.key, value, spec.label)
            end
        else
            AddAuraRegisteredChange(changes, "auras3." .. tostring(scope.key) .. "." .. spec.key, value, spec.label)
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = spec.label,
        summary = "Changes Aura display style toggles.",
    }
end

local AURA_STYLE_NUMBER_SPECS = {
    { key = "stackTextSize", label = "Stack Text Size", aliases = { "stack size", "stack text size", "stack count text size" }, root = true },
    { key = "cooldownTextSize", label = "Cooldown Text Size", aliases = { "cooldown size", "cooldown text size", "timer text size", "timer size" }, root = true },
    { key = "stackTextOffsetX", label = "Stack Text X Offset", aliases = { "stack x", "stack x offset", "stack text x", "stack text x offset" } },
    { key = "stackTextOffsetY", label = "Stack Text Y Offset", aliases = { "stack y", "stack y offset", "stack text y", "stack text y offset" } },
    { key = "cooldownTextOffsetX", label = "Cooldown Text X Offset", aliases = { "cooldown x", "cooldown x offset", "cooldown text x", "timer text x", "timer text x offset" } },
    { key = "cooldownTextOffsetY", label = "Cooldown Text Y Offset", aliases = { "cooldown y", "cooldown y offset", "cooldown text y", "timer text y", "timer text y offset" } },
    { key = "cooldownDecimalSeconds", label = "Cooldown Decimal Threshold", aliases = { "cooldown decimals", "cooldown decimal", "cooldown decimal threshold", "timer decimals", "timer decimal threshold", "decimal seconds" } },
    { key = "durationBarHeight", label = "Duration Bar Height", aliases = { "duration bar height", "timer bar height", "aura duration bar height", "aura timer bar height" } },
}

local function ParseAuraStyleNumberShortcut(text)
    if not ContainsAny(text, {
        "stack size", "stack text size", "stack x", "stack y",
        "cooldown size", "cooldown text size", "timer size", "timer text size",
        "cooldown x", "cooldown y", "timer text x", "timer text y",
        "cooldown decimals", "cooldown decimal", "timer decimals", "timer decimal", "decimal seconds",
        "duration bar height", "timer bar height",
    }) then
        return nil
    end
    if ContainsAny(text, { "icon size", "icons size", "anchor", "position", "fill mode", "direction", "color", "colors", "colour", "colours", "filter", "exclusive" }) then
        return nil
    end

    local spec
    for i = 1, #AURA_STYLE_NUMBER_SPECS do
        if ContainsAny(text, AURA_STYLE_NUMBER_SPECS[i].aliases) then
            spec = AURA_STYLE_NUMBER_SPECS[i]
            break
        end
    end
    if not spec then return nil end

    local scopes = AuraStyleScopes(text)
    if not scopes then return nil end
    local lanes = nil
    if ContainsAny(text, { "debuff", "debuffs" }) then
        lanes = { "debuff" }
    elseif ContainsAny(text, { "buff", "buffs" }) then
        lanes = { "buff" }
    end

    local changes = {}
    local sawSetting = false
    for i = 1, #scopes do
        local scope = scopes[i]
        if scope.kind == "group" then
            if lanes then
                for j = 1, #lanes do
                    local setting = Registry and Registry:GetSetting(AuraGeometrySettingKey(scope, lanes[j], spec.key))
                    if setting then
                        sawSetting = true
                        local value = FirstNumber(text)
                        local relativeDelta = value == nil and P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text) or nil
                        if value ~= nil or relativeDelta ~= nil then
                            changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, label = tostring(setting.label or spec.label) }
                        end
                    end
                end
            end
        elseif scope.kind == "unit" and (scope.key == "shared" or scope.key == "player" or scope.key == "target" or scope.key == "focus" or scope.key == "boss") then
            if lanes then
                for j = 1, #lanes do
                    local setting = Registry and Registry:GetSetting("auras3." .. tostring(scope.key) .. "." .. lanes[j] .. "." .. spec.key)
                    if setting then
                        sawSetting = true
                        local value = FirstNumber(text)
                        local relativeDelta = value == nil and P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text) or nil
                        if value ~= nil or relativeDelta ~= nil then
                            changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, label = tostring(setting.label or spec.label) }
                        end
                    end
                end
            elseif spec.root then
                local setting = Registry and Registry:GetSetting("auras3." .. tostring(scope.key) .. "." .. spec.key)
                if setting then
                    sawSetting = true
                    local value = FirstNumber(text)
                    local relativeDelta = value == nil and P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text) or nil
                    if value ~= nil or relativeDelta ~= nil then
                        changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, label = tostring(setting.label or spec.label) }
                    end
                end
            end
        end
    end
    if #changes > 0 then
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = spec.label,
            summary = "Changes Aura text and timer numeric style options.",
        }
    end
    if sawSetting then
        return {
            kind = "answer",
            status = "missing_value",
            text = "Which number should I use for that Aura style option? Example: 'set target buff stack x to 0'.",
            summary = "Asks for a numeric Aura style value.",
        }
    end
    return nil
end

local function ParseAuraStyleAnchorShortcut(text)
    local attr
    local label
    if ContainsAny(text, { "stack anchor", "stack count anchor", "stack text anchor" }) then
        attr = "stackAnchor"
        label = "Stack Count Anchor"
    elseif ContainsAny(text, { "cooldown anchor", "cooldown text anchor", "timer anchor", "timer text anchor" }) then
        attr = "cooldownAnchor"
        label = "Cooldown Anchor"
    else
        return nil
    end
    if ContainsAny(text, { "x offset", "offset x", " y offset", "offset y", "text x", "text y", "size", "font", "color", "colors", "colour", "colours" }) then
        return nil
    end

    local scopes = AuraShortcutScopes(text, true)
    if not scopes then return nil end
    local lanes = nil
    if ContainsAny(text, { "debuff", "debuffs" }) then
        lanes = { "debuff" }
    elseif ContainsAny(text, { "buff", "buffs" }) then
        lanes = { "buff" }
    end

    local changes = {}
    local sawSetting = false
    local sawMissingValue = false
    for i = 1, #scopes do
        local scope = scopes[i]
        if scope.kind == "group" then
            if lanes then
                for j = 1, #lanes do
                    local setting = Registry and Registry:GetSetting(AuraGeometrySettingKey(scope, lanes[j], attr))
                    if setting then
                        sawSetting = true
                        local value = P.EnumValueForText and P.EnumValueForText(setting, text) or nil
                        if value ~= nil then
                            AddAuraShortcutChange(changes, setting, value, tostring(setting.label or label))
                        else
                            sawMissingValue = true
                        end
                    end
                end
            end
        elseif scope.kind == "unit" and (scope.key == "shared" or scope.key == "player" or scope.key == "target" or scope.key == "focus" or scope.key == "boss") then
            if lanes then
                for j = 1, #lanes do
                    local setting = Registry and Registry:GetSetting("auras3." .. tostring(scope.key) .. "." .. lanes[j] .. "." .. attr)
                    if setting then
                        sawSetting = true
                        local value = P.EnumValueForText and P.EnumValueForText(setting, text) or nil
                        if value ~= nil then
                            AddAuraShortcutChange(changes, setting, value, tostring(setting.label or label))
                        else
                            sawMissingValue = true
                        end
                    end
                end
            else
                local setting = Registry and Registry:GetSetting("auras3." .. tostring(scope.key) .. "." .. attr)
                if setting then
                    sawSetting = true
                    local value = P.EnumValueForText and P.EnumValueForText(setting, text) or nil
                    if value ~= nil then
                        AddAuraShortcutChange(changes, setting, value, tostring(setting.label or label))
                    else
                        sawMissingValue = true
                    end
                end
            end
        end
    end
    if #changes > 0 then
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = label,
            summary = "Changes Aura text anchor options.",
        }
    end
    if sawSetting and sawMissingValue then
        return {
            kind = "answer",
            status = "missing_value",
            text = "Use an anchor point such as TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT, or CENTER where that Aura option supports it.",
            summary = "Asks for a concrete Aura anchor value.",
        }
    end
    return nil
end

local function ParseUnitAuraTooltipShortcut(text)
    if not ContainsAny(text, { "show tooltip", "show tooltips", "tooltip", "tooltips", "aura tooltip", "aura tooltips" }) then return nil end
    if ContainsAny(text, { "group", "group aura", "party", "raid", "mythic", "native", "blizzard", "anchor", "position", "x offset", "offset x", "y offset", "offset y" }) then
        return nil
    end

    local scopes = AuraShortcutScopes(text, true)
    if not scopes then return nil end
    local value = AuraBooleanValue(text)
    if value == nil then return nil end

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        if scope.kind == "unit" and (scope.key == "player" or scope.key == "target" or scope.key == "focus" or scope.key == "boss") then
            AddAuraRegisteredChange(changes, "auras3." .. tostring(scope.key) .. ".showTooltip", value, "Aura Tooltips")
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Aura Tooltips",
        summary = "Changes unit Aura tooltip display.",
    }
end

local function ParseAuraExclusiveFilterShortcut(text)
    if not ContainsAny(text, { "exclusive filter", "exclusive aura filter" }) then return nil end

    local lane
    if ContainsAny(text, { "debuff", "debuffs" }) then
        lane = "debuff"
    elseif ContainsAny(text, { "buff", "buffs" }) then
        lane = "buff"
    end
    if not lane then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which Aura lane should use the exclusive filter: Buffs or Debuffs? Example: 'set target debuff exclusive filter to none'.",
            summary = "Asks for a concrete Aura lane before changing an exclusive filter.",
        }
    end

    local scopes = {}
    if ContainsAny(text, { "shared", "global", "shared aura", "shared auras" }) then
        scopes[#scopes + 1] = "shared"
    else
        local units = DetectUnits(text)
        for i = 1, #units do
            local unit = units[i]
            if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
                scopes[#scopes + 1] = unit
            end
        end
    end
    if #scopes == 0 then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which Aura scope should use that exclusive filter: Shared, Player, Target, Focus, or Boss?",
            summary = "Asks for a concrete Aura scope before changing an exclusive filter.",
        }
    end

    local changes = {}
    local sawSetting = false
    local sawMissingValue = false
    for i = 1, #scopes do
        local key = "auras3." .. tostring(scopes[i]) .. "." .. lane .. ".filter.exclusive"
        local setting = Registry and Registry:GetSetting(key)
        if setting then
            sawSetting = true
            local value = P.EnumValueForText and P.EnumValueForText(setting, text) or nil
            if value ~= nil then
                AddAuraShortcutChange(changes, setting, value, tostring(setting.label or "Exclusive Filter"))
            else
                sawMissingValue = true
            end
        end
    end
    if #changes > 0 then
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = "Aura Exclusive Filter",
            summary = "Changes a unit Aura exclusive filter.",
        }
    end
    if sawSetting and sawMissingValue then
        return {
            kind = "answer",
            status = "missing_value",
            text = lane == "debuff" and "Use none or raid for Debuff Exclusive Filter." or "Use none for Buff Exclusive Filter.",
            summary = "Asks for a concrete Aura exclusive filter value.",
        }
    end
    return nil
end

local function ParseGroupPrivateAuraShortcut(text)
    if not ContainsAny(text, { "private aura", "private auras" }) then return nil end
    if ContainsAny(text, { "native", "blizzard", "copy", "blacklist", "whitelist", "spell id", "spellid" }) then return nil end

    local groups = DetectGroups(text)
    local scopes = {}
    for i = 1, #groups do
        local group = groups[i]
        if group == "party" or group == "raid" or group == "mythicraid" then
            scopes[#scopes + 1] = group
        end
    end
    if #scopes == 0 then return nil end

    local keySuffix
    local valueKind
    local label
    if ContainsAny(text, { "private aura countdown", "private aura timer", "private aura cooldown text" }) then
        keySuffix = "privateAuraCountdown"
        valueKind = "boolean"
        label = "Private Aura Countdown"
    elseif ContainsAny(text, { "private aura numbers", "private aura number text", "private aura stacks", "private aura stack text" }) then
        keySuffix = "privateAuras.showNumbers"
        valueKind = "boolean"
        label = "Private Aura Numbers"
    elseif ContainsAny(text, { "private aura max", "private aura count", "private aura limit", "private aura icons max" }) then
        keySuffix = "privateAuraMax"
        valueKind = "number"
        label = "Private Aura Max Icons"
    elseif ContainsAny(text, { "private aura size", "private aura icon size", "private aura icons size" }) then
        keySuffix = "privateAuraSize"
        valueKind = "number"
        label = "Private Aura Icon Size"
    elseif ContainsAny(text, { "private aura x offset", "private aura horizontal offset", "private aura x" }) then
        keySuffix = "privateAuraX"
        valueKind = "number"
        label = "Private Aura X Offset"
    elseif ContainsAny(text, { "private aura y offset", "private aura vertical offset", "private aura y" }) then
        keySuffix = "privateAuraY"
        valueKind = "number"
        label = "Private Aura Y Offset"
    elseif ContainsAny(text, { "private aura spacing", "private aura gap", "private aura icon spacing" }) then
        keySuffix = "privateAuras.spacing"
        valueKind = "number"
        label = "Private Aura Spacing"
    elseif ContainsAny(text, { "private aura growth", "private aura grow", "private auras grow", "private aura grow direction", "private aura direction" }) then
        keySuffix = "privateAuras.growth"
        valueKind = "enum"
        label = "Private Aura Growth"
    elseif ContainsAny(text, { "private aura anchor", "private aura position", "private aura corner" }) then
        keySuffix = "privateAuraAnchor"
        valueKind = "enum"
        label = "Private Aura Anchor"
    else
        keySuffix = "privateAurasEnabled"
        valueKind = "boolean"
        label = "Private Auras"
    end

    local changes = {}
    local sawSetting = false
    local sawMissingValue = false
    for i = 1, #scopes do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scopes[i]) .. "." .. keySuffix)
        if setting then
            sawSetting = true
            local value
            local relativeDelta
            if valueKind == "boolean" then
                value = AuraBooleanValue(text)
            elseif valueKind == "number" then
                value = FirstNumber(text)
                relativeDelta = value == nil and P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text) or nil
            elseif valueKind == "enum" then
                value = P.EnumValueForText and P.EnumValueForText(setting, text) or nil
            end
            if value ~= nil or relativeDelta ~= nil then
                changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, label = tostring(setting.label or label) }
            else
                sawMissingValue = true
            end
        end
    end
    if #changes > 0 then
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = label,
            summary = "Changes Group Frame private aura options.",
        }
    end
    if sawSetting and sawMissingValue then
        return {
            kind = "answer",
            status = "missing_value",
            text = "Which value should I use for that private aura option? Example: 'set party private aura y to 0' or 'set raid private aura growth to RIGHT'.",
            summary = "Asks for a concrete private aura value.",
        }
    end
    return nil
end

local function ParseGroupAuraLaneVisibilityDirectShortcut(text)
    if not ContainsAny(text, { "party buff", "party buffs", "party debuff", "party debuffs", "raid buff", "raid buffs", "raid debuff", "raid debuffs", "mythic raid buff", "mythic raid buffs", "mythicraid buff", "mythicraid buffs", "mythic raid debuff", "mythic raid debuffs", "mythicraid debuff", "mythicraid debuffs" }) then
        return nil
    end
    if ContainsAny(text, {
        "filter", "filters", "only", "show only", "private", "native", "blizzard", "blacklist", "whitelist",
        "stack", "cooldown", "timer", "duration", "x offset", "offset x", " y offset", "offset y",
        " x ", "x ", " y ", "y ", "per row", "layer", "swipe", "direction", "dispel", "border", "mode",
        "size", "max", "count", "spacing", "growth", "anchor", "position", "color", "colors", "colour", "colours", "stripe",
    }) then
        return nil
    end
    if FirstNumber(text) ~= nil then return nil end

    local lane
    if ContainsAny(text, { "debuff", "debuffs" }) then
        lane = "debuff"
    elseif ContainsAny(text, { "buff", "buffs" }) then
        lane = "buff"
    end
    if not lane then return nil end

    local groups = DetectGroups(text)
    local changes = {}
    local value = AuraBooleanValue(text)
    if value == nil then return nil end
    for i = 1, #groups do
        local group = groups[i]
        if group == "party" or group == "raid" or group == "mythicraid" then
            AddAuraRegisteredChange(changes, "gf_" .. tostring(group) .. ".auras." .. lane .. ".enabled", value)
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = lane == "buff" and "Group Buffs" or "Group Debuffs",
        summary = "Changes Group Aura lane visibility.",
    }
end

local function ParseAuraDirectSettingShortcut(text, raw)
    if not ContainsAny(text, {
        "aura", "auras", "buff", "buffs", "debuff", "debuffs", "sated", "exhaustion", "reminder",
        "swipe darkens", "cooldown swipe darkens", "dispel type border", "dispel type borders", "debuff type border", "debuff type borders",
        "stack count", "show stack", "stack anchor", "stack size", "stack x", "stack y",
        "cooldown anchor", "timer anchor", "cooldown text", "timer text", "cooldown size", "timer size",
        "cooldown x", "cooldown y", "cooldown decimal", "cooldown decimals", "timer decimal", "timer decimals",
        "cooldown swipe", "timer swipe",
        "duration bar", "timer bar", "show tooltip", "tooltip",
        "exclusive filter",
        "shared filters", "global filters", "player filters", "target filters", "focus filters", "boss filters", "unit filters",
        "sort order",
    }) then return nil end
    if ContainsAny(text, { "aura blacklist spell", "hidden aura spell", "blacklist spell" }) then
        local value = P.RawAfterLastConnector and P.RawAfterLastConnector(raw or text, { " to ", " as ", " = " }) or nil
        if not value or value == "" then
            value = tostring(raw or text):match("[Ss][Pp][Ee][Ll][Ll]%s+(.+)$")
        end
        if value and value ~= "" then
            return AuraDirectSettingChange("menu.auraBlacklistSpell", value, "Hidden Aura Spell")
        end
    end
    if ContainsAny(text, { "blacklist", "whitelist", "spell id", "spellid", "spell:" })
        and not ContainsAny(text, { "aura blacklist preset", "blacklist preset", "hidden aura preset" })
    then
        return nil
    end

    if ContainsAny(text, { "unit auras", "aura system", "auras system", "all unit auras", "unitframe auras" }) then
        local value = AuraBooleanValue(text)
        if value ~= nil then return AuraDirectSettingChange("auras3.enabled", value, "Unit Auras") end
    end
    if ContainsAny(text, { "aura editing scope", "editing aura scope", "aura scope", "edit aura scope" }) then
        local setting = Registry and Registry:GetSetting("menu.auraScope")
        local value = setting and P.EnumValueForText and P.EnumValueForText(setting, text) or nil
        return AuraDirectSettingChange("menu.auraScope", value, "Aura Editing Scope")
    end
    if ContainsAny(text, { "aura style lane", "aura style tab", "aura buffs tab", "aura debuffs tab" }) then
        local setting = Registry and Registry:GetSetting("menu.auraStyleGFLane")
        local value = setting and P.EnumValueForText and P.EnumValueForText(setting, text) or nil
        return AuraDirectSettingChange("menu.auraStyleGFLane", value, "Aura Style Lane")
    end
    if ContainsAny(text, { "aura filter lane", "aura filter tab", "aura buff filters tab", "aura debuff filters tab" }) then
        local setting = Registry and Registry:GetSetting("menu.auraFilterLane")
        local value = setting and P.EnumValueForText and P.EnumValueForText(setting, text) or nil
        return AuraDirectSettingChange("menu.auraFilterLane", value, "Aura Filter Lane")
    end
    if ContainsAny(text, { "aura settings view", "aura view", "aura settings mode", "basic aura settings", "advanced aura settings", "all aura settings" }) then
        local setting = Registry and Registry:GetSetting("menu.aurasUXMode")
        local value = setting and P.EnumValueForText and P.EnumValueForText(setting, text) or nil
        return AuraDirectSettingChange("menu.aurasUXMode", value, "Aura Options View")
    end
    if ContainsAny(text, { "aura blacklist preset", "blacklist preset", "hidden aura preset" }) then
        local compactText = Compact(text)
        for i = 1, #AURA_BLACKLIST_PRESETS do
            local spec = AURA_BLACKLIST_PRESETS[i]
            local compactKey = Compact(tostring(spec.key or ""))
            if ContainsAny(text, spec.aliases)
                or ContainsAny(text, { tostring(spec.key or ""):lower():gsub("_", " ") })
                or (compactKey ~= "" and compactText:find(compactKey, 1, true))
            then
                return AuraDirectSettingChange("menu.auraBlacklistPreset", spec.key, "Aura Blacklist Preset")
            end
        end
    end
    if ContainsAny(text, { "custom aura caps", "custom caps", "aura caps override", "aura limits override", "custom aura layout", "custom layout", "aura layout override", "custom aura ignore", "custom ignore", "aura ignore list override" }) then
        local attr
        if ContainsAny(text, { "custom aura caps", "custom caps", "aura caps override", "aura limits override" }) then
            attr = "overrideSharedLayout"
        elseif ContainsAny(text, { "custom aura layout", "custom layout", "aura layout override" }) then
            attr = "overrideLayout"
        elseif ContainsAny(text, { "custom aura ignore", "custom ignore", "aura ignore list override" }) then
            attr = "overrideIgnore"
        end
        local value = AuraBooleanValue(text)
        if attr and value ~= nil then
            local scopes = AuraScopeOverrideScopes(text)
            local changes = {}
            if scopes then
                for i = 1, #scopes do
                    local scope = scopes[i]
                    local setting = Registry and Registry:GetSetting("auras3." .. tostring(scope.key) .. "." .. tostring(attr))
                    AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or "Aura override"))
                end
            end
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    bulkSafe = #changes > 1,
                    label = "Change Aura scope override",
                    summary = "Adjusts Aura scope override settings.",
                }
            end
        end
    end
    local laneUnits = DetectUnits(text)
    if #laneUnits > 0 and ContainsAny(text, { "filters", "aura filters" })
        and not ContainsAny(text, { "custom", "buff", "buffs", "debuff", "debuffs", "raid", "dispellable", "exclusive", "only", "player only", "nameplate", "crowd control" })
    then
        local value = AuraBooleanValue(text)
        if value ~= nil then
            local changes = {}
            for i = 1, #laneUnits do
                local unit = laneUnits[i]
                if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
                    AddAuraRegisteredChange(changes, "auras3." .. tostring(unit) .. ".filtersEnabled", value)
                end
            end
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    bulkSafe = #changes > 1,
                    label = "Unit Aura Filters",
                    summary = "Changes per-unit Aura Filters toggles.",
                }
            end
        end
    end
    do
        local result = ParseAuraExclusiveFilterShortcut(text)
        if result then return result end
    end
    do
        local result = ParseGroupPrivateAuraShortcut(text)
        if result then return result end
    end
    do
        local result = ParseGroupAuraLaneVisibilityDirectShortcut(text)
        if result then return result end
    end
    if #laneUnits > 0 and ContainsAny(text, { "filter", "filters" })
        and ContainsAny(text, {
            "buff", "buffs", "debuff", "debuffs", "raid", "dispellable", "purgeable",
            "crowd control", "cc debuff", "nameplate", "cancelable", "cancellable",
            "external defensive", "big defensive",
        })
    then
        return nil
    end
    do
        local result = ParseAuraStyleBoolShortcut(text)
        if result then return result end
    end
    do
        local result = ParseAuraStyleNumberShortcut(text)
        if result then return result end
    end
    do
        local result = ParseAuraStyleAnchorShortcut(text)
        if result then return result end
    end
    do
        local result = ParseUnitAuraTooltipShortcut(text)
        if result then return result end
    end
    if #laneUnits > 0 and ContainsAny(text, { "buff", "buffs", "debuff", "debuffs" })
        and ContainsAny(text, { " x", "x ", "x offset", "offset x", " y", "y ", "y offset", "offset y", "left", "right", "up", "down", "links", "rechts", "oben", "unten" })
        and not ContainsAny(text, {
            "cooldown", "timer", "stack", "duration", "filter", "exclusive", "custom",
            "size", "max", "per row", "growth", "anchor", "spacing", "layer", "color", "colour",
        })
    then
        local lane
        if ContainsAny(text, { "debuff", "debuffs" }) then
            lane = "debuff"
        elseif ContainsAny(text, { "buff", "buffs" }) then
            lane = "buff"
        end
        local direction = DetectDirection(text, {})
        local attr
        if ContainsAny(text, { "x offset", "offset x", " x", "x ", "left", "right", "links", "rechts" }) or direction == "left" or direction == "right" then
            attr = "offsetX"
        elseif ContainsAny(text, { "y offset", "offset y", " y", "y ", "up", "down", "oben", "unten" }) or direction == "up" or direction == "down" then
            attr = "offsetY"
        end
        if lane and attr then
            local value = FirstNumber(text)
            local relativeDelta
            if ContainsAny(text, { "move", "nudge", "shift", "verschiebe" }) and direction then
                local amount = value or 10
                if direction == "left" or direction == "down" then amount = -amount end
                value = nil
                relativeDelta = amount
            end
            if value ~= nil or relativeDelta ~= nil then
                local changes = {}
                for i = 1, #laneUnits do
                    local unit = laneUnits[i]
                    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
                        local setting = Registry and Registry:GetSetting("auras3." .. tostring(unit) .. "." .. lane .. "." .. attr)
                        if setting then
                            changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta }
                        end
                    end
                end
                if #changes > 0 then
                    return {
                        kind = "changes",
                        changes = changes,
                        bulkSafe = #changes > 1,
                        label = "Unit Aura Lane Offset",
                        summary = "Changes unit Buff/Debuff X/Y offset.",
                    }
                end
            end
        end
    end
    if #laneUnits > 0 and ContainsAny(text, { "buff", "buffs", "debuff", "debuffs" })
        and not ContainsAny(text, {
            "filter", "filters", "raid", "dispellable", "exclusive", "only", "custom",
            "cooldown", "stack", "duration", "timer", "x ", " y ", "offset", "size", "max",
            "per row", "growth", "anchor", "spacing", "layer", "swipe", "direction", "color", "colour",
        })
    then
        local lane
        if ContainsAny(text, { "debuff", "debuffs" }) then
            lane = "debuff"
        elseif ContainsAny(text, { "buff", "buffs" }) then
            lane = "buff"
        end
        local value = lane and AuraBooleanValue(text) or nil
        if value ~= nil then
            local changes = {}
            for i = 1, #laneUnits do
                local unit = laneUnits[i]
                if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
                    AddAuraRegisteredChange(changes, "auras3." .. tostring(unit) .. "." .. lane .. ".visible", value)
                end
            end
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    bulkSafe = #changes > 1,
                    label = "Unit Aura Lane Visibility",
                    summary = "Changes unit Buff/Debuff visibility.",
                }
            end
        end
    end
    if ContainsAny(text, { "aura filters", "auras filters", "aura filtering", "filter auras", "filter buffs", "filter debuffs" })
        and not ContainsAny(text, { "custom", "player", "target", "focus", "boss", "party", "raid", "mythic" })
    then
        local value = AuraBooleanValue(text)
        if value ~= nil then return AuraDirectSettingChange("auras3.shared.filters.enabled", value, "Shared Aura Filters") end
    end
    if ContainsAny(text, { "shared filters", "global filters", "shared aura filters", "global aura filters" }) then
        local value = AuraBooleanValue(text)
        if value ~= nil then return AuraDirectSettingChange("auras3.shared.filtersEnabled", value, "Shared Filters") end
    end
    if ContainsAny(text, { "buff reminders", "buff reminder", "aura reminders", "aura reminder" })
        and not ContainsAny(text, { "expiry warning", "threshold", "grow direction", "growth", "grow", "direction" })
    then
        local value = AuraBooleanValue(text)
        if value ~= nil then return AuraDirectSettingChange("auras3.shared.showReminders", value, "Buff Reminders") end
    end
    if ContainsAny(text, { "buff reminder expiry warning", "buff reminder threshold", "reminder expiry warning", "reminder threshold" }) then
        local value = FirstNumber(text)
        if value ~= nil then return AuraDirectSettingChange("auras3.shared.reminderThreshold", value, "Buff Reminder Expiry Warning") end
    end
    do
        local data = A.AurasRegistryData or {}
        local reminderSpecs = data.AURA_REMINDER_SPECS or {}
        local bestSpec
        local bestLen = 0
        for i = 1, #reminderSpecs do
            local spec = reminderSpecs[i]
            local aliases = type(spec.aliases) == "table" and spec.aliases or {}
            for j = 1, #aliases do
                local alias = tostring(aliases[j] or "")
                if alias ~= "" and ContainsAny(text, { alias }) then
                    local len = #Compact(alias)
                    if len > bestLen then
                        bestSpec = spec
                        bestLen = len
                    end
                end
            end
        end
        if bestSpec then
            local value = AuraBooleanValue(text)
            if value ~= nil then
                return AuraDirectSettingChange("auras3.shared.reminders." .. tostring(bestSpec.key), value, tostring(bestSpec.label or "Buff Reminder"))
            end
        end
    end
    local explicitUnits = DetectUnits(text)
    local explicitGroups = DetectGroups(text)
    if #explicitUnits == 0 and #explicitGroups == 0 and not ContainsAny(text, { "color", "colors", "colour", "colours", "farbe", "farben" }) then
        if ContainsAny(text, { "highlight own buffs", "highlight my buffs", "own buff highlight", "my buff highlight" }) then
            local value = AuraBooleanValue(text)
            if value ~= nil then return AuraDirectSettingChange("auras3.shared.highlightOwnBuffs", value, "Highlight Own Buffs") end
        end
        if ContainsAny(text, { "highlight own debuffs", "highlight my debuffs", "own debuff highlight", "my debuff highlight" }) then
            local value = AuraBooleanValue(text)
            if value ~= nil then return AuraDirectSettingChange("auras3.shared.highlightOwnDebuffs", value, "Highlight Own Debuffs") end
        end
        if ContainsAny(text, { "show aura buffs", "show buffs", "aura buffs", "buff auras" }) then
            local value = AuraBooleanValue(text)
            if value ~= nil then return AuraDirectSettingChange("auras3.shared.showBuffs", value, "Show Buffs") end
        end
        if ContainsAny(text, { "show aura debuffs", "show debuffs", "aura debuffs", "debuff auras" }) then
            local value = AuraBooleanValue(text)
            if value ~= nil then return AuraDirectSettingChange("auras3.shared.showDebuffs", value, "Show Debuffs") end
        end
        local data = A.AurasRegistryData or {}
        local sharedSpecs = data.AURA_SHARED_BOOLEAN_SPECS or {}
        for i = 1, #sharedSpecs do
            local spec = sharedSpecs[i]
            if spec.attr ~= "showBuffs" and spec.attr ~= "showDebuffs"
                and spec.attr ~= "highlightOwnBuffs" and spec.attr ~= "highlightOwnDebuffs"
                and ContainsAny(text, spec.aliases)
            then
                local value = AuraBooleanValue(text)
                if value ~= nil then
                    return AuraDirectSettingChange("auras3.shared." .. tostring(spec.attr), value, spec.label)
                end
            end
        end
    end

    if ContainsAny(text, { "click through auras", "click-through auras", "aura click through", "aura click-through" }) then
        return AuraDirectSettingChange("auras3.shared.clickThroughAuras", AuraBooleanValue(text), "Click-through Auras")
    end
    if ContainsAny(text, { "aura edit preview", "edit mode auras", "preview auras in edit mode", "show auras in edit mode", "edit preview auras" }) then
        return AuraDirectSettingChange("auras3.shared.showInEditMode", AuraBooleanValue(text), "Aura Edit Preview")
    end
    if ContainsAny(text, { "aura timer bucket colors", "aura timer color buckets", "aura cooldown bucket colors", "aura cooldown color buckets", "aura cooldown buckets", "aura timer buckets", "color aura timers by remaining time" }) then
        return AuraDirectSettingChange("general.aurasCooldownTextUseBuckets", AuraBooleanValue(text), "Aura Timer Color Buckets")
    end
    if ContainsAny(text, { "show sated", "show exhaustion", "sated exhaustion", "sated buffs", "exhaustion buffs" }) then
        return AuraDirectSettingChange("auras3.shared.showSated", AuraBooleanValue(text), "Show Sated/Exhaustion")
    end

    local direction = AuraDirectionValue(text)
    if direction and ContainsAny(text, { "buff reminder grow direction", "buff reminder growth", "reminder grow direction", "reminder growth" }) then
        return AuraDirectSettingChange("auras3.shared.reminderGrowth", direction, "Buff Reminder Growth")
    end
    if direction and ContainsAny(text, { "buff growth", "buff grow direction", "buff direction", "buff aura growth" }) then
        return AuraDirectSettingChange("auras3.shared.buffGrowth", direction, "Buff Growth")
    end
    if direction and ContainsAny(text, { "debuff growth", "debuff grow direction", "debuff direction", "debuff aura growth" }) then
        return AuraDirectSettingChange("auras3.shared.debuffGrowth", direction, "Debuff Growth")
    end
    if direction and ContainsAny(text, { "buff wrap rows", "buff row wrap", "buff wrap direction", "buff wrap" }) then
        return AuraDirectSettingChange("auras3.shared.buffRowWrap", direction, "Buff Row Wrap")
    end
    if direction and ContainsAny(text, { "debuff wrap rows", "debuff row wrap", "debuff wrap direction", "debuff wrap" }) then
        return AuraDirectSettingChange("auras3.shared.debuffRowWrap", direction, "Debuff Row Wrap")
    end

    local number = FirstNumber(text)
    if number ~= nil then
        if ContainsAny(text, { "sort order", "aura sort order", "buff sort order", "debuff sort order" }) then
            return AuraDirectSettingChange("auras3.shared.sortOrder", number, "Aura Sort Order")
        end
        if ContainsAny(text, { "sated threshold", "sated show at", "sated show seconds", "exhaustion threshold", "exhaustion show at" }) then
            return AuraDirectSettingChange("auras3.shared.satedShowAtSeconds", number, "Sated Threshold")
        end
        if ContainsAny(text, { "aura cooldown safe seconds", "aura timer safe seconds", "aura safe seconds", "safe aura seconds", "safe aura timer threshold", "aura safe timer threshold" }) then
            return AuraDirectSettingChange("general.aurasCooldownTextSafeSeconds", number, "Aura Safe Timer Threshold")
        end
        if ContainsAny(text, { "aura cooldown warning seconds", "aura timer warning seconds", "aura warning seconds", "warning aura seconds", "warning aura timer threshold", "aura warning timer threshold" }) then
            return AuraDirectSettingChange("general.aurasCooldownTextWarningSeconds", number, "Aura Warning Timer Threshold")
        end
    end

    if ContainsAny(text, { "aura cooldown safe color", "aura cooldown safe text color", "cooldown text safe color", "aura timer safe color", "aura safe timer color", "safe aura timer color" }) then
        local setting = Registry and Registry:GetSetting("general.aurasCooldownTextSafeColor")
        local value = setting and P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, text, text)
        return AuraDirectSettingChange("general.aurasCooldownTextSafeColor", value, "Aura Safe Timer Color")
    end
    if ContainsAny(text, { "aura cooldown warning color", "aura cooldown warning text color", "cooldown text warning color", "aura timer warning color", "aura warning timer color", "warning aura timer color" }) then
        local setting = Registry and Registry:GetSetting("general.aurasCooldownTextWarningColor")
        local value = setting and P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, text, text)
        return AuraDirectSettingChange("general.aurasCooldownTextWarningColor", value, "Aura Warning Timer Color")
    end
    if ContainsAny(text, { "aura cooldown urgent color", "aura cooldown urgent text color", "cooldown text urgent color", "aura timer urgent color", "aura urgent timer color", "urgent aura timer color" }) then
        local setting = Registry and Registry:GetSetting("general.aurasCooldownTextUrgentColor")
        local value = setting and P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, text, text)
        return AuraDirectSettingChange("general.aurasCooldownTextUrgentColor", value, "Aura Urgent Timer Color")
    end

    return nil
end

local function UnitAuraFilterExplicitScope(text)
    if ContainsAny(text, { "shared", "global", "shared aura", "shared auras", "all unit auras" }) then return "shared" end
    local units = DetectUnits(text)
    local playerIsFilterValue = ContainsAny(text, {
        "player filter", "only my", "my buffs", "my debuffs", "player buffs only", "player debuffs only",
        "own buffs", "own debuffs",
    })
    for i = 1, #units do
        local unit = units[i]
        if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
            if not (unit == "player" and playerIsFilterValue and #units > 1) then return unit end
        end
    end
    if M then
        local scope = M.auraScope
        if scope == "shared" or scope == "player" or scope == "target" or scope == "focus" or scope == "boss" then return scope end
    end
    return nil
end

local function UnitAuraFilterLaneFromSpec(text, spec)
    if ContainsAny(text, { "buff", "buffs" }) then return "buff" end
    if ContainsAny(text, { "debuff", "debuffs" }) then return "debuff" end
    return spec and spec.lane or nil
end

local function UnitAuraFilterSpecForText(text)
    local data = A.AurasRegistryData or {}
    local specs = data.AURA_FILTER_BOOLEAN_SPECS or {}
    local compactText = Compact(text)
    local scopeStripped = " " .. Normalize(text) .. " "
    for _, word in ipairs({ "shared", "global", "target", "focus", "boss" }) do
        scopeStripped = scopeStripped:gsub(" " .. word .. " ", " ")
    end
    scopeStripped = Trim(scopeStripped:gsub("%s+", " "))
    local compactScopeStripped = Compact(scopeStripped)
    local bestSpec, bestLen
    for i = 1, #specs do
        local spec = specs[i]
        local words = type(spec.words) == "table" and spec.words or {}
        for j = 1, #words do
            local alias = tostring(words[j] or "")
            local compactAlias = Compact(alias)
            if compactAlias ~= "" and (
                HasPhrase(text, alias)
                or HasPhrase(scopeStripped, alias)
                or (#compactAlias >= 5 and compactText:find(compactAlias, 1, true))
                or (#compactAlias >= 5 and compactScopeStripped:find(compactAlias, 1, true))
            ) then
                local len = #compactAlias
                if not bestLen or len > bestLen then
                    bestSpec, bestLen = spec, len
                end
            end
        end
    end
    return bestSpec
end

local function UnitAuraFilterHasIntent(text)
    if ContainsAny(text, { "corner", "corner indicator", "corner indicators", "corner custom", "custom corner" }) then return false end
    if ContainsAny(text, { "dispel overlay", "unitframe dispel overlay", "unit frame dispel overlay", "debuff overlay", "dispellable overlay", "dispellable debuff overlay" }) then return false end
    if ContainsAny(text, { "aura custom settings", "custom aura settings", "aura override", "aura overrides", "aura scope" })
        and ContainsAny(text, { "reset", "clear", "remove", "restore" })
    then
        return false
    end
    if ContainsAny(text, { "blacklist", "whitelist", "category", "spell id", "spellid", "spell:" }) then return false end
    if ContainsAny(text, { "filter", "filters", "only", "show only", "just show", "display only" }) then return true end
    if ContainsAny(text, {
        "show all", "show everything", "all buffs", "all debuffs", "all auras",
        "no filter", "clear filter", "clear filters", "remove filter", "remove filters",
        "filter off", "filters off", "normal filter", "default filter",
    }) then return true end
    return ContainsAny(text, {
        "dispellable", "dispelable", "purgeable",
        "crowd control", "cc debuff", "cc debuffs",
        "raid buff", "raid buffs", "raid debuff", "raid debuffs",
        "raid in combat", "combat raid",
        "nameplate only", "nameplate-only", "include nameplate", "include nameplate-only",
        "external defensive", "external defensives", "big defensive", "big defensives", "major defensive", "major defensives",
        "cancelable buff", "cancelable buffs", "cancellable buff", "cancellable buffs",
        "not cancelable buff", "not cancelable buffs", "not cancellable buff", "not cancellable buffs",
        "non cancelable buff", "non cancelable buffs", "uncancelable buff", "uncancelable buffs",
    })
end

local function HasNativeGroupAuraRootIntent(text)
    if not ContainsAny(text, { "native", "blizzard" }) then return false end
    if not ContainsAny(text, {
        "party", "raid", "mythic raid", "mythicraid",
        "group aura", "group auras", "group frame", "group frames",
    }) then
        return false
    end
    return ContainsAny(text, {
        "aura", "auras", "buff", "buffs", "debuff", "debuffs",
        "dispel", "dispels", "dispellable", "external", "externals",
        "private aura", "private auras",
    })
end

local function AddUnitAuraFiltersEnabled(changes, scope)
    AddAuraRegisteredChange(changes, "auras3." .. tostring(scope) .. ".filtersEnabled", true, "Enable Aura Filters")
end

local function AddUnitAuraFilterClearLaneChanges(changes, scope, lane)
    local keys = UNIT_AURA_FILTER_KEYS[lane] or {}
    for i = 1, #keys do
        AddAuraRegisteredChange(changes, "auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter." .. tostring(keys[i]), false)
    end
    AddAuraRegisteredChange(changes, "auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter.exclusive", "none")
end

local function AddUnitAuraFilterSetChange(changes, scope, lane, key, value, conflicts)
    AddAuraRegisteredChange(changes, "auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter." .. tostring(key), value)
    if value == true and type(conflicts) == "table" then
        for i = 1, #conflicts do
            AddAuraRegisteredChange(changes, "auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter." .. tostring(conflicts[i]), false)
        end
    end
end

local function GroupAuraFilterExplicitScopes(text, value)
    if #DetectUnits(text) > 0 then return nil, false, false end

    local explicitAll = ContainsAny(text, {
        "all group auras", "all group aura", "all group buffs", "all group debuffs",
        "all group frames", "all groups", "every group aura", "every group buff", "every group debuff",
    })
    if explicitAll then return { "party", "raid", "mythicraid" }, true end

    local scopes = {}
    local hasParty = ContainsAny(text, { "party", "party frame", "party frames", "party aura", "party auras", "party buff", "party buffs", "party debuff", "party debuffs" })
    local hasMythic = ContainsAny(text, { "mythic raid", "mythicraid", "mythic raid frame", "mythic raid frames", "mythic raid aura", "mythic raid auras", "mythic raid buff", "mythic raid buffs", "mythic raid debuff", "mythic raid debuffs" })
    local hasRaidFrameScope = ContainsAny(text, { "raid frame", "raid frames", "raid aura", "raid auras" })
    local hasRaidLanePhrase = ContainsAny(text, { "raid buff", "raid buffs", "raid debuff", "raid debuffs" })
    local hasRaidScope = not hasMythic and ContainsAny(text, { "raid", "raid frame", "raid frames", "raid aura", "raid auras", "raid buff", "raid buffs", "raid debuff", "raid debuffs" })
    if hasParty then scopes[#scopes + 1] = "party" end
    if hasMythic then scopes[#scopes + 1] = "mythicraid" end
    if hasRaidScope then
        local raidPhraseLooksLikeFilterValue = value == "RAID" and hasRaidLanePhrase and not hasRaidFrameScope and (hasParty or hasMythic)
        if not raidPhraseLooksLikeFilterValue then scopes[#scopes + 1] = "raid" end
    end
    if #scopes > 0 then return scopes, true end
    if HasGenericGroupAuraGeometryScope(text) or ContainsAny(text, { "group frame", "group frames", "group debuff", "group debuffs", "group buff", "group buffs" }) then
        return nil, false, true
    end
    return nil, false, false
end

local function GroupAuraFilterLaneForText(text, value)
    if ContainsAny(text, { "buff", "buffs" }) and not ContainsAny(text, { "debuff", "debuffs" }) then return "buff" end
    if ContainsAny(text, { "debuff", "debuffs" }) then return "debuff" end
    if value == "CANCELABLE" or value == "NOT_CANCELABLE" or value == "EXTERNAL_DEFENSIVE" or value == "BIG_DEFENSIVE" then return "buff" end
    if value == "RAID_PLAYER_DISPELLABLE" or value == "CROWD_CONTROL" then return "debuff" end
    return nil
end

local function GroupAuraFilterValueForText(text)
    if ContainsAny(text, {
        "show all", "show everything", "all buffs", "all debuffs", "all auras",
        "no filter", "clear filter", "clear filters", "remove filter", "remove filters",
        "filter off", "filters off", "normal filter", "default filter",
    }) or (ContainsAny(text, { "clear", "remove", "reset", "default", "normal" }) and ContainsAny(text, { "filter", "filters" }))
        or ((HasPhrase(text, "to all") or HasPhrase(text, "all filter") or HasPhrase(text, "filter all")) and ContainsAny(text, { "filter", "filters" }))
    then
        return "ALL"
    end
    local data = A.AurasRegistryData or {}
    return AuraEnumAliasValue(text, data.GF_AURA_FILTER_ALIASES)
end

local function ParseGroupAuraLiveFilterShortcut(text)
    if not UnitAuraFilterHasIntent(text) then return nil end
    if ContainsAny(text, { "shared", "global", "shared aura", "shared auras", "all unit auras" }) then return nil end
    local explicitFilterIntent = ContainsAny(text, {
        "filter", "filters", "only", "show only", "just show", "display only",
        "no filter", "clear filter", "clear filters", "remove filter", "remove filters",
    })
    if not explicitFilterIntent and ContainsAny(text, {
        "max", "maximum", "size", "per row", "spacing", "layer", "x", "y", "anchor", "growth",
        "cooldown", "timer", "stack", "duration", "swipe", "dispel type border", "debuff type border",
        "stripe", "debuff stripe",
        "turn on", "turn off", "enable", "disable",
    }) then
        return nil
    end
    local value = GroupAuraFilterValueForText(text)
    if not value then return nil end
    local scopes, concrete, genericGroup = GroupAuraFilterExplicitScopes(text, value)
    if genericGroup then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which group aura scope should use that filter: Party, Raid, Mythic Raid, or all group frames? Example: 'show only dispellable raid debuffs'.",
            summary = "Asks for a concrete group aura scope before changing the live filter.",
        }
    end
    if not scopes or #scopes == 0 then return nil end

    local lane = GroupAuraFilterLaneForText(text, value)
    if not lane then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which group aura lane should use that filter: Buffs or Debuffs? Example: 'show only dispellable raid debuffs'.",
            summary = "Asks for a group aura lane before changing the live filter.",
        }
    end

    local values = (A.AurasRegistryData and A.AurasRegistryData.GF_AURA_FILTER_VALUES and A.AurasRegistryData.GF_AURA_FILTER_VALUES[lane]) or {}
    local allowed = false
    for i = 1, #values do
        if values[i] == value then
            allowed = true
            break
        end
    end
    if not allowed then return nil end

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        AddAuraRegisteredChange(changes, "gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".filterToken", value)
        AddAuraRegisteredChange(changes, "gf_" .. tostring(scope) .. ".auras.enabled", true)
        AddAuraRegisteredChange(changes, "gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".enabled", true)
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = lane == "buff" and "Group Buff Filter" or "Group Debuff Filter",
        summary = "Enables the requested Group Aura lane and changes its live filter dropdown.",
    }
end

local function ParseUnitAuraLiveFilterShortcut(text)
    if not UnitAuraFilterHasIntent(text) then return nil end
    if ContainsAny(text, { "aura filter lane", "aura filter tab", "aura filter type", "aura buff filters tab", "aura debuff filters tab" }) then return nil end
    if ContainsAny(text, { "aura filters", "auras filters", "aura filtering", "filter auras", "filter buffs", "filter debuffs" })
        and not ContainsAny(text, {
            "player filter", "raid filter", "raid in combat", "nameplate", "cancelable", "not cancelable",
            "dispellable", "crowd control", "external defensive", "big defensive", "only", "show only",
        })
    then
        return nil
    end
    if HasNativeGroupAuraRootIntent(text) then return nil end
    local explicitUnitAuraScope = ContainsAny(text, { "shared", "global", "shared aura", "shared auras", "all unit auras" })
    if not explicitUnitAuraScope
        and (HasGenericGroupAuraGeometryScope(text)
            or HasConcreteGroupAuraGeometryScope(text)
            or ContainsAny(text, { "party", "raid frame", "raid frames", "group frame", "group frames", "mythic raid" }))
    then
        return nil
    end

    local scope = UnitAuraFilterExplicitScope(text)
    if not scope then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which aura scope should use that live filter: Shared, Player, Target, Focus, Boss, Party, Raid, or Mythic Raid? Examples: 'show only dispellable target debuffs' or 'show only dispellable raid debuffs'.",
            summary = "Asks for a unit aura scope before changing live filters.",
        }
    end

    local clearAll = ContainsAny(text, {
        "show all", "show everything", "all buffs", "all debuffs", "all auras",
        "no filter", "clear filter", "clear filters", "remove filter", "remove filters",
        "filter off", "filters off", "normal filter", "default filter",
    })
    if clearAll then
        local lanes = AuraShortcutLanes(text)
        local changes = {}
        AddUnitAuraFiltersEnabled(changes, scope)
        for i = 1, #lanes do AddUnitAuraFilterClearLaneChanges(changes, scope, lanes[i]) end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = "Show all Aura filter results",
            summary = "Clears live unit aura filters for the requested lane.",
        }
    end

    local spec = UnitAuraFilterSpecForText(text)
    if not spec then return nil end
    local lane = UnitAuraFilterLaneFromSpec(text, spec)
    if not lane then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which aura lane should use that filter: Buffs or Debuffs? Example: 'show only my target buffs' or 'show only my target debuffs'.",
            summary = "Asks for a unit aura lane before changing live filters.",
        }
    end

    local value = DetectBoolean and DetectBoolean(text)
    if value == nil then
        if ContainsAny(text, { "off", "disable", "disabled", "turn off", "remove", "clear", "without", "no ", "aus", "deaktivieren" }) then
            value = false
        else
            value = true
        end
    end

    local directChanges = {}
    AddUnitAuraFilterSetChange(directChanges, scope, lane, spec.key, value, spec.conflicts)
    AddUnitAuraFiltersEnabled(directChanges, scope)
    if #directChanges == 0 then return nil end

    local wantsOnly = value == true and ContainsAny(text, { "only", "show only", "just", "just show", "display only" })
    if wantsOnly then
        local replaceChanges = {}
        AddUnitAuraFilterClearLaneChanges(replaceChanges, scope, lane)
        AddUnitAuraFilterSetChange(replaceChanges, scope, lane, spec.key, true, spec.conflicts)
        AddUnitAuraFiltersEnabled(replaceChanges, scope)
        if #replaceChanges > #directChanges then
            return {
                kind = "ambiguous",
                choices = {
                    {
                        changes = directChanges,
                        label = "Enable " .. tostring(spec.label or "that filter"),
                        bulkSafe = #directChanges > 1,
                        summary = "Enables one live Aura filter without changing other filters.",
                    },
                    {
                        changes = replaceChanges,
                        label = "Use only " .. tostring(spec.label or "that filter"),
                        bulkSafe = true,
                        summary = "Clears the lane's other live Aura filters first.",
                    },
                },
                label = "How should I apply that Aura filter?",
                summary = "Clarifies whether to replace other live Aura filters.",
            }
        end
    end

    return {
        kind = "changes",
        changes = directChanges,
        bulkSafe = #directChanges > 1,
        label = "Change live Aura filter",
    summary = "Changes a live unit Aura filter.",
    }
end

local function ParseUnitAuraFilterBooleanShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, { "blacklist", "whitelist", "category", "spell id", "spellid", "spell:" }) then return nil end
    if ContainsAny(text, { "only", "show only", "just show", "display only", "clear filter", "clear filters", "remove filter", "remove filters", "show all", "show everything" }) then return nil end
    if HasNativeGroupAuraRootIntent(text) then return nil end
    local explicitUnits = DetectUnits(text)
    local explicitShared = ContainsAny(text, { "shared", "global", "shared aura", "shared auras", "all unit auras" })
    if #explicitUnits == 0 and not explicitShared and (HasGenericGroupAuraGeometryScope(text) or HasConcreteGroupAuraGeometryScope(text)
        or ContainsAny(text, { "party", "raid frame", "raid frames", "group frame", "group frames", "mythic raid" }))
    then
        return nil
    end
    if (#explicitUnits > 0 or explicitShared) and ContainsAny(text, { "party", "raid frame", "raid frames", "group frame", "group frames", "mythic raid" }) then
        return nil
    end
    if #explicitUnits == 0 and not explicitShared then return nil end

    local lane
    if ContainsAny(text, { "buff", "buffs" }) and not ContainsAny(text, { "debuff", "debuffs" }) then
        lane = "buff"
    elseif ContainsAny(text, { "debuff", "debuffs" }) then
        lane = "debuff"
    end
    if not lane then return nil end

    local key
    local conflicts
    local label
    if ContainsAny(text, { "raid in combat", "combat raid" }) then
        key = "raidInCombat"
        label = lane == "buff" and "Buff Raid In Combat Filter" or "Debuff Raid In Combat Filter"
    elseif ContainsAny(text, { "raid filter", "raid buff", "raid buffs", "raid debuff", "raid debuffs" }) then
        key = "raid"
        label = lane == "buff" and "Buff Raid Filter" or "Debuff Raid Filter"
    elseif ContainsAny(text, { "nameplate only", "nameplate-only", "include nameplate", "include nameplate-only" }) then
        key = "includeNameplateOnly"
        label = lane == "buff" and "Buff Include Nameplate-only Filter" or "Debuff Include Nameplate-only Filter"
    elseif lane == "debuff" and ContainsAny(text, { "dispellable", "dispelable", "purgeable" }) then
        key = "includeDispellable"
        label = "Debuff Dispellable Filter"
    elseif lane == "debuff" and ContainsAny(text, { "crowd control", "cc debuff", "cc debuffs" }) then
        key = "crowdControl"
        label = "Debuff Crowd Control Filter"
    elseif lane == "buff" and ContainsAny(text, { "not cancelable", "not cancellable", "non cancelable", "uncancelable" }) then
        key = "notCancelable"
        conflicts = { "cancelable" }
        label = "Buff Not Cancelable Filter"
    elseif lane == "buff" and ContainsAny(text, { "cancelable", "cancellable" }) then
        key = "cancelable"
        conflicts = { "notCancelable" }
        label = "Buff Cancelable Filter"
    elseif lane == "buff" and ContainsAny(text, { "external defensive", "external defensives", "external buffs" }) then
        key = "externalDefensive"
        label = "Buff External Defensive Filter"
    elseif lane == "buff" and ContainsAny(text, { "big defensive", "big defensives", "major defensive", "major defensives" }) then
        key = "bigDefensive"
        label = "Buff Big Defensive Filter"
    elseif ContainsAny(text, { "player filter", "only my", "my buffs", "my debuffs", "player buffs only", "player debuffs only", "own buffs", "own debuffs" }) then
        key = "onlyMine"
        label = lane == "buff" and "Buff Player Filter" or "Debuff Player Filter"
    else
        return nil
    end

    local scope = UnitAuraFilterExplicitScope(text)
    if not scope then return nil end
    local value = DetectBoolean and DetectBoolean(text)
    if value == nil then
        value = not ContainsAny(text, { "off", "disable", "disabled", "turn off", "remove", "without", "no ", "aus", "deaktivieren" })
    end

    local changes = {}
    AddUnitAuraFilterSetChange(changes, scope, lane, key, value, conflicts)
    AddUnitAuraFiltersEnabled(changes, scope)
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = label,
        summary = "Changes a live unit Aura filter directly.",
    }
end

local function AddGroupAuraVisibilityChoice(choices, scope, lane, value)
    local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".enabled")
    if not setting then return end
    local laneLabel = lane == "buff" and "Buffs" or "Debuffs"
    local verb = value and "show" or "hide"
    choices[#choices + 1] = {
        setting = setting,
        value = value,
        label = tostring(setting.label or laneLabel) .. " -> " .. verb,
        summary = "Changes " .. tostring(setting.label or laneLabel) .. " visibility.",
    }
end

local function AddGroupAuraVisibilityChange(changes, scope, lane, value)
    local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".enabled")
    AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or "Group Aura Visibility"))
end

local function AddGroupAuraRootVisibilityChoice(choices, scope, value)
    local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. ".auras.enabled")
    if not setting then return end
    local verb = value and "show" or "hide"
    choices[#choices + 1] = {
        setting = setting,
        value = value,
        label = tostring(setting.label or "Group Auras Enabled") .. " -> " .. verb,
        summary = "Changes the whole Group Aura system for that scope.",
    }
end

local function ParseGroupAuraRootSettingShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, { "blacklist", "blocklist", "filter token", "live filter", "spell id", "spellid" }) then return nil end
    if not ContainsAny(text, {
        "group aura", "group auras", "party aura", "party auras", "raid aura", "raid auras",
        "mythicraid aura", "mythic raid aura", "mythicraid auras", "mythic raid auras",
        "aura tooltip", "aura tooltips", "prefer player auras", "prefer my auras",
        "sort auras by duration", "aura duration sort",
        "dynamic aura scale", "dynamic icon scale", "native aura", "native auras",
        "native group aura", "native group auras", "blizzard aura", "blizzard auras",
        "native group private auras", "blizzard group private auras", "native private auras",
    }) then
        return nil
    end

    local key
    local label
    if ContainsAny(text, { "prefer player auras", "prefer my auras" }) then
        key = "preferPlayer"
        label = "Prefer Player Auras"
    elseif ContainsAny(text, { "dynamic aura scale", "dynamic icon scale" }) then
        key = "dynamicScale"
        label = "Dynamic Aura Scale"
    elseif ContainsAny(text, { "aura tooltip", "aura tooltips" }) then
        key = "showTooltip"
        label = "Aura Tooltips"
    elseif ContainsAny(text, { "sort auras by duration", "aura duration sort" }) then
        key = "sortByDuration"
        label = "Sort Auras by Duration"
    elseif ContainsAny(text, { "native group aura dispel border", "blizzard group aura dispel border", "native dispel border", "native dispellable border", "native aura debuff border" }) then
        key = "blizzardDispelBorder"
        label = "Native Dispel Border"
    elseif ContainsAny(text, { "native group aura buffs", "blizzard group aura buffs", "native buffs", "native aura buffs" }) then
        key = "blizzardTypes.buffs"
        label = "Native Buffs"
    elseif ContainsAny(text, { "native group aura debuffs", "blizzard group aura debuffs", "native debuffs", "native aura debuffs" }) then
        key = "blizzardTypes.debuffs"
        label = "Native Debuffs"
    elseif ContainsAny(text, { "native group aura dispels", "blizzard group aura dispels", "native dispel auras", "native dispels", "dispellable auras" }) then
        key = "blizzardTypes.dispels"
        label = "Native Dispel Auras"
    elseif ContainsAny(text, { "native group aura externals", "blizzard group aura externals", "native external auras", "native externals", "external auras" }) then
        key = "blizzardTypes.externals"
        label = "Native External Auras"
    elseif ContainsAny(text, { "native group private auras", "blizzard group private auras", "native private auras", "native private aura icons" }) then
        key = "blizzardTypes.privateAuras"
        label = "Native Private Auras"
    elseif ContainsAny(text, { "all group auras", "all group aura", "group aura system", "group auras enabled", "native group auras", "native group aura" }) then
        key = "enabled"
        label = "Group Auras Enabled"
    else
        return nil
    end

    local scopes = {}
    local groups = DetectGroups(text)
    for i = 1, #groups do
        local scope = groups[i]
        if scope == "party" or scope == "raid" or scope == "mythicraid" then
            scopes[#scopes + 1] = scope
        end
    end
    if #scopes == 0 then
        if ContainsAny(text, { "all group", "all group auras", "every group", "group aura system", "group auras" }) then
            scopes = { "party", "raid", "mythicraid" }
        else
            return nil
        end
    end

    local value = AuraBooleanValue(text)
    local changes = {}
    for i = 1, #scopes do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scopes[i]) .. ".auras." .. key)
        AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or label))
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes a Group Aura root option directly.",
    }
end

local function ParseGroupAuraVisibilityShortcut(text)
    local hasBuff = ContainsAny(text, { "buff", "buffs" })
    local hasDebuff = ContainsAny(text, { "debuff", "debuffs" })
    if not ContainsAny(text, { "aura", "auras", "auren" }) and not (hasBuff and hasDebuff) then return nil end
    if not ContainsAny(text, {
        "show", "enable", "enabled", "turn on", "on",
        "hide", "disable", "disabled", "turn off", "off",
        "anzeigen", "einblenden", "aktivieren", "an",
        "ausblenden", "verstecken", "deaktivieren", "aus",
    }) then return nil end
    if ContainsAny(text, { "size", "count", "max", "maximum", "cap", "limit", "spacing", "gap", "growth", "anchor", "position", "offset", "filter", "blacklist", "cooldown", "timer", "duration", "stack", "copy", "preset" }) then
        return nil
    end
    if ContainsAny(text, {
        "all group auras", "all group aura", "group aura system", "group auras enabled",
        "aura tooltip", "aura tooltips", "prefer player auras", "prefer my auras",
        "dynamic aura scale", "dynamic icon scale", "native group", "native private",
        "private aura", "private auras",
    }) then
        return nil
    end
    if ContainsAny(text, {
        "aura system", "group aura system", "native aura", "native auras", "native group aura", "native group auras",
        "blizzard aura", "blizzard auras", "blizzard group aura", "blizzard group auras",
    }) then
        return nil
    end

    local scopes = {}
    local groups = DetectGroups(text)
    for i = 1, #groups do
        local group = groups[i]
        if group == "party" or group == "raid" or group == "mythicraid" then
            AddAuraGeometryScope(scopes, "group", group)
        end
    end

    if #scopes == 0 then
        if HasGenericGroupAuraGeometryScope(text) or ContainsAny(text, { "group", "group frame", "group frames" }) then
            return {
                kind = "answer",
                status = "ambiguous",
                text = "Which group aura scope do you mean: Party or Raid? Also say Buffs, Debuffs, or both. Example: 'hide party debuffs' or 'hide both raid buffs and debuffs'.",
                summary = "Asks for a concrete group aura scope before changing visibility.",
            }
        end
        return nil
    end

    local value = DetectBoolean and DetectBoolean(text)
    if value == nil then
        if ContainsAny(text, { "show", "enable", "enabled", "turn on", "on", "anzeigen", "einblenden", "aktivieren", "an" }) then value = true end
        if ContainsAny(text, { "hide", "disable", "disabled", "turn off", "off", "ausblenden", "verstecken", "deaktivieren", "aus" }) then value = false end
    end
    if value == nil then return nil end

    local explicitBothLanes = hasBuff and hasDebuff
        or ContainsAny(text, { "both", "both lanes", "buffs and debuffs", "buff and debuff", "buffs debuffs" })
    local broadAllAuras = ContainsAny(text, { "all auras", "all aura", "all party auras", "all raid auras", "all mythic raid auras", "all group auras" })
    local wantsBoth = explicitBothLanes or broadAllAuras
    if hasBuff ~= hasDebuff then
        local lane = hasBuff and "buff" or "debuff"
        local changes = {}
        for i = 1, #scopes do
            AddGroupAuraVisibilityChange(changes, scopes[i].key, lane, value)
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = lane == "buff" and "Group Buff visibility" or "Group Debuff visibility",
            summary = "Changes one Group Aura lane visibility.",
        }
    end
    if wantsBoth then
        if broadAllAuras and not explicitBothLanes and #scopes == 1 then
            local scope = scopes[1].key
            local choices = {}
            local bothChanges = {}
            AddGroupAuraVisibilityChange(bothChanges, scope, "buff", value)
            AddGroupAuraVisibilityChange(bothChanges, scope, "debuff", value)
            if #bothChanges == 2 then
                local verb = value and "show" or "hide"
                choices[#choices + 1] = {
                    changes = bothChanges,
                    label = "Buff and Debuff lanes -> " .. verb,
                    bulkSafe = true,
                    summary = "Changes only the Group Aura Buff and Debuff lanes.",
                }
            end
            AddGroupAuraRootVisibilityChoice(choices, scope, value)
            if #choices > 1 then
                return {
                    kind = "ambiguous",
                    choices = choices,
                    label = "How much should I change?",
                    summary = "Clarifies whether to change visible lanes or the whole Group Aura system.",
                }
            end
        end
        local changes = {}
        for i = 1, #scopes do
            local scope = scopes[i].key
            AddGroupAuraVisibilityChange(changes, scope, "buff", value)
            AddGroupAuraVisibilityChange(changes, scope, "debuff", value)
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = "Group Aura visibility",
            summary = "Changes Group Aura Buff and Debuff visibility.",
        }
    end

    if #scopes == 1 then
        local scope = scopes[1].key
        local choices = {}
        AddGroupAuraVisibilityChoice(choices, scope, "buff", value)
        AddGroupAuraVisibilityChoice(choices, scope, "debuff", value)
        local bothChanges = {}
        AddGroupAuraVisibilityChange(bothChanges, scope, "buff", value)
        AddGroupAuraVisibilityChange(bothChanges, scope, "debuff", value)
        if #bothChanges == 2 then
            local verb = value and "show" or "hide"
            choices[#choices + 1] = {
                changes = bothChanges,
                label = "Both Group Aura lanes -> " .. verb,
                bulkSafe = true,
                summary = "Changes both Group Aura Buff and Debuff visibility.",
            }
        end
        if #choices == 0 then return nil end
        return {
            kind = "ambiguous",
            choices = choices,
            label = "Which group aura lane?",
            summary = "Asks whether to change group buffs, group debuffs, or both.",
        }
    end

    return {
        kind = "answer",
        status = "ambiguous",
        text = "Which group aura lane do you mean for those scopes: Buffs, Debuffs, or both? Example: 'hide both party and raid buffs and debuffs'.",
        summary = "Asks for a concrete group aura lane before changing multiple scopes.",
    }
end

local function ParseAuraCooldownSwipeDirectionShortcut(text)
    if not ContainsAny(text, { "cooldown swipe direction", "timer swipe direction", "reverse cooldown swipe", "swipe direction" }) then return nil end
    if not ContainsAny(text, { "swipe" }) then return nil end

    local scopes = AuraShortcutScopes(text, true)
    if not scopes then return nil end

    local value = AuraCooldownSwipeDirectionValue(text)
    if not value then
        return {
            kind = "answer",
            status = "missing_value",
            text = "Use normal or reverse for Aura Cooldown Swipe Direction. Example: set raid cooldown swipe direction to reverse.",
        }
    end

    local lanes = AuraShortcutLanes(text)
    local changes = {}
    for i = 1, #scopes do
        for j = 1, #lanes do
            local key = AuraGeometrySettingKey(scopes[i], lanes[j], "cooldownSwipeReverse")
            local setting = Registry and Registry:GetSetting(key)
            AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or "Aura Cooldown Swipe Direction"))
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Change Aura cooldown swipe direction",
        summary = "Adjusts Aura cooldown swipe direction.",
    }
end

local function ParseAuraDurationBarShortcut(text)
    if not ContainsAny(text, { "duration bar", "timer bar" }) then return nil end

    local attr, value, missingText, label, summary
    local wantsPosition = ContainsAny(text, {
        "duration bar position", "timer bar position", "duration bar edge",
        "top", "upper", "on top", "at top", "top edge", "above",
        "bottom", "lower", "on bottom", "at bottom", "bottom edge", "below",
    })
    local wantsDirection = ContainsAny(text, {
        "duration bar fill mode", "duration bar direction", "timer bar fill mode", "timer bar direction",
        "fill mode", "remaining", "elapsed", "count up", "count down", "countdown", "deplete", "depletion", "drain", "progress",
    })

    if wantsPosition and not wantsDirection then
        attr = "durationBarPosition"
        value = AuraDurationBarPositionValue(text)
        missingText = "Use top or bottom for Aura Duration Bar Position. Example: put target buff duration bar on top."
        label = "Change Aura duration bar position"
        summary = "Adjusts Aura Duration Bar Position."
    elseif wantsDirection then
        attr = "durationBarDirection"
        value = AuraDurationBarDirectionValue(text)
        missingText = "Use remaining or elapsed for Aura Duration Bar Fill Mode. Example: set raid duration bar fill mode to elapsed."
        label = "Change Aura duration bar fill mode"
        summary = "Adjusts Aura Duration Bar Fill Mode."
    else
        return nil
    end

    if not value then
        return {
            kind = "answer",
            status = "missing_value",
            text = missingText,
        }
    end

    local scopes = AuraShortcutScopes(text, true)
    if not scopes then return nil end

    local lanes = AuraShortcutLanes(text)
    local changes = {}
    for i = 1, #scopes do
        for j = 1, #lanes do
            local key = AuraGeometrySettingKey(scopes[i], lanes[j], attr)
            local setting = Registry and Registry:GetSetting(key)
            AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or "Aura Duration Bar"))
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = label,
        summary = summary,
    }
end

local function ParseAuraDebuffBorderModeShortcut(text)
    if not ContainsAny(text, { "debuff type border", "dispel type border", "debuff border mode", "dispel border mode", "aura debuff border" }) then return nil end

    local scopes = AuraShortcutScopes(text, true)
    if not scopes then return nil end

    local boolValue = DetectBoolean and DetectBoolean(text)
    if boolValue ~= nil
        and not ContainsAny(text, { "mode", "symbol", "with symbol", "with icon", "border symbol", "border only", "just border", "outline only", "to border", "as border", "use border", "to off", "as off", "use off" })
    then
        local changes = {}
        for i = 1, #scopes do
            local scope = scopes[i]
            local key
            if scope.kind == "group" then
                key = "gf_" .. tostring(scope.key) .. ".auras.debuff.showDispelBorder"
            else
                key = "auras3." .. tostring(scope.key) .. ".useDebuffTypeBorders"
            end
            local setting = Registry and Registry:GetSetting(key)
            AddAuraShortcutChange(changes, setting, boolValue, tostring(setting and setting.label or "Debuff Dispel-type Border"))
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = "Debuff Dispel-type Border",
            summary = "Changes Debuff Dispel-type Border visibility.",
        }
    end

    local value = AuraDebuffBorderModeValue(text)
    if not value then
        return {
            kind = "answer",
            status = "missing_value",
            text = "Use off, border, or symbol for Debuff Dispel-type Border Mode. Example: set raid debuff dispel border mode to border.",
        }
    end

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        local key
        if scope.kind == "group" then
            key = "gf_" .. tostring(scope.key) .. ".auras.debuff.dispelBorderMode"
        else
            key = "auras3." .. tostring(scope.key) .. ".debuffTypeBorderMode"
        end
        local setting = Registry and Registry:GetSetting(key)
        AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or "Debuff Dispel-type Border Mode"))
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Change Aura debuff border mode",
        summary = "Adjusts Debuff Dispel-type Border Mode.",
    }
end

local function ParseAuraScopeOverrideShortcut(text)
    if ContainsAny(text, { "what", "where", "why", "help", "explain", "how" }) then return nil end
    if not ContainsAny(text, {
        "custom aura style", "use custom aura style", "aura style override", "custom aura visuals",
        "use shared style", "shared aura style", "inherit style", "follow shared style",
        "custom aura filters", "custom filters", "use custom aura filters", "use custom filters", "aura filter override", "aura filters override", "custom filter override",
        "use shared filters", "shared filters", "shared aura filters", "inherit filters", "follow shared filters",
        "use shared rules", "shared aura rules", "inherit rules", "follow shared rules",
    }) then return nil end

    local attr, value
    local bool = DetectBoolean and DetectBoolean(text)
    if ContainsAny(text, { "custom aura style", "use custom aura style", "aura style override", "custom aura visuals" }) then
        attr = "customStyle"
        value = bool == nil and true or bool
    elseif ContainsAny(text, { "use shared style", "shared aura style", "inherit style", "follow shared style" }) then
        attr = "useSharedStyle"
        value = bool == nil and true or bool
    elseif ContainsAny(text, { "custom aura filters", "custom filters", "use custom aura filters", "use custom filters", "aura filter override", "aura filters override", "custom filter override" }) then
        attr = "overrideFilters"
        value = bool == nil and true or bool
    elseif ContainsAny(text, { "use shared filters", "shared filters", "shared aura filters", "inherit filters", "follow shared filters" }) then
        attr = "overrideFilters"
        if bool == nil then
            value = false
        else
            value = not bool
        end
    elseif ContainsAny(text, { "use shared rules", "shared aura rules", "inherit rules", "follow shared rules" }) then
        attr = "useSharedRules"
        value = bool == nil and true or bool
    end
    if not attr or value == nil then return nil end

    local scopes = AuraScopeOverrideScopes(text)
    if not scopes then return nil end

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        local setting = Registry and Registry:GetSetting("auras3." .. tostring(scope.key) .. "." .. tostring(attr))
        AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or "Aura override"))
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Change Aura scope override",
        summary = "Adjusts Aura scope override settings.",
    }
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
        "[Hh]ide%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Hh]idden%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Gg]roup%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Pp]arty%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Rr]aid%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Pp]arty%s+[Bb]uff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Rr]aid%s+[Bb]uff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Pp]arty%s+[Dd]ebuff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Rr]aid%s+[Dd]ebuff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
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
        "[Aa]llow%s+[Hh]idden%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Gg]roup%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Pp]arty%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Rr]aid%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Pp]arty%s+[Bb]uff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Rr]aid%s+[Bb]uff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Pp]arty%s+[Dd]ebuff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Rr]aid%s+[Dd]ebuff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
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
P.ParseGroupAuraLiveFilterShortcut = ParseGroupAuraLiveFilterShortcut
P.ParseUnitAuraFilterBooleanShortcut = ParseUnitAuraFilterBooleanShortcut
P.ParseUnitAuraLiveFilterShortcut = ParseUnitAuraLiveFilterShortcut
P.ParseAuraDirectSettingShortcut = ParseAuraDirectSettingShortcut
P.ParseGroupAuraRootSettingShortcut = ParseGroupAuraRootSettingShortcut
P.ParseGroupAuraVisibilityShortcut = ParseGroupAuraVisibilityShortcut
P.ParseAuraCooldownSwipeDirectionShortcut = ParseAuraCooldownSwipeDirectionShortcut
P.ParseAuraDurationBarShortcut = ParseAuraDurationBarShortcut
P.ParseAuraDebuffBorderModeShortcut = ParseAuraDebuffBorderModeShortcut
P.ParseAuraScopeOverrideShortcut = ParseAuraScopeOverrideShortcut
P.AuraBlacklistPresetForText = AuraBlacklistPresetForText
P.AuraGroupBlacklistScope = AuraGroupBlacklistScope
P.AuraGroupBlacklistLane = AuraGroupBlacklistLane
P.AuraGroupBlacklistCategoryForText = AuraGroupBlacklistCategoryForText
P.AuraBlacklistSpellValue = AuraBlacklistSpellValue
