local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
local P = A.Parser or {}
A.Parser = P
local Trim = P.Trim
local Normalize = P.Normalize
local HasPhrase = P.HasPhrase
local ContainsAny = P.ContainsAny
local UNIT_ORDER = P.UNIT_ORDER
local GROUP_ORDER = P.GROUP_ORDER
local ALL_UNITFRAMES = P.ALL_UNITFRAMES
local ALL_GROUPS = P.ALL_GROUPS
local CLASS_POWER_TERMS = P.CLASS_POWER_TERMS
local GAMEPLAY_TERMS = P.GAMEPLAY_TERMS
local GLOBAL_BARS_TERMS = P.GLOBAL_BARS_TERMS
local CASTBAR_ROOT_DETAIL_TERMS = P.CASTBAR_ROOT_DETAIL_TERMS
local PAGE_TEXT_TARGETS = P.PAGE_TEXT_TARGETS
local AddUnique = P.AddUnique
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local DetectGlobalScope = P.DetectGlobalScope
local OFF_WORDS = P.OFF_WORDS
local ON_WORDS = P.ON_WORDS
local DetectBoolean = P.DetectBoolean
local FirstNumber = P.FirstNumber
local Compact = P.Compact
local AliasRelationText = P.AliasRelationText
local TextMatchesAlias = P.TextMatchesAlias
local ExtractColor = P.ExtractColor
local DetectFrameType = P.DetectFrameType
local DetectDirection = P.DetectDirection
local DetectAttribute = P.DetectAttribute
local PageForText = P.PageForText
local FrameTypeForPage = P.FrameTypeForPage
local UnitPageKey = P.UnitPageKey
local COPY_SCOPE_DEFAULTS = P.COPY_SCOPE_DEFAULTS
local UNIT_COPY_SCOPE_SPECS = P.UNIT_COPY_SCOPE_SPECS
local GROUP_COPY_SCOPE_DEFAULTS = P.GROUP_COPY_SCOPE_DEFAULTS
local GROUP_COPY_SCOPE_SPECS = P.GROUP_COPY_SCOPE_SPECS
local CopyScopeDefaults = P.CopyScopeDefaults
local CopyScopeMatches = P.CopyScopeMatches
local ApplyCopyScopeMatches = P.ApplyCopyScopeMatches
local CopyScopesForText = P.CopyScopesForText
local GroupCopyScopeDefaults = P.GroupCopyScopeDefaults
local GroupCopyScopesForText = P.GroupCopyScopesForText
local CleanProfileName = P.CleanProfileName
local RawAfterPrefix = P.RawAfterPrefix
local RawBetween = P.RawBetween
local RawCreateProfileName = P.RawCreateProfileName
local RawCopyProfileName = P.RawCopyProfileName
local RawRenameProfileNames = P.RawRenameProfileNames
local PROFILE_EXPORT_KIND_LABELS = P.PROFILE_EXPORT_KIND_LABELS
local ProfileExportKindForText = P.ProfileExportKindForText
local RawAfterLastConnector = P.RawAfterLastConnector
local CleanSpecName = P.CleanSpecName
local ImportNewProfileName = P.ImportNewProfileName
local BuildSpecAutoSwitch = P.BuildSpecAutoSwitch
local BuildSpecProfileAction = P.BuildSpecProfileAction
local ParseWorkflowLifecycle = P.ParseWorkflowLifecycle
local BuildMenuSelectorState = P.BuildMenuSelectorState
local ParseProfileStagingState = P.ParseProfileStagingState
local ParseGroupCopyScopeState = P.ParseGroupCopyScopeState
local ParseUnitCopyScopeState = P.ParseUnitCopyScopeState
local ParseProfile = P.ParseProfile

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

local function AuraGeometryLanes(text)
    if ContainsAny(text, { "buff", "buffs" }) then return { "buff" } end
    if ContainsAny(text, { "debuff", "debuffs" }) then return { "debuff" } end
    if ContainsAny(text, { "aura", "auras", "aura icon", "aura icons" }) then return { "buff", "debuff" } end
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
    if ContainsAny(text, { "max icons", "maximum icons", "icon count", "aura count", "buff count", "debuff count", "count" }) then
        return "max"
    end
    if ContainsAny(text, { "per row", "icons per row", "wrap count", "row count" }) then
        return "perRow"
    end
    if ContainsAny(text, { "spacing", "gap", "icon gap" }) then
        return "spacing"
    end
    if ContainsAny(text, { "layer", "z order", "z-order", "frame level" }) then
        return "layer"
    end
    if ContainsAny(text, { "icon size", "icons size", "size", "bigger", "larger", "smaller", "shrink", "groesse", "grosse" }) then
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
    if not ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" }) then return nil end
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
        summary = "Maps natural Aura lane layout wording to registered Aura settings.",
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

local function ParseAuraEditScope(text)
    if not ContainsAny(text, { "aura", "auras", "aura scope", "aura editing scope" }) then return nil end
    if ContainsAny(text, { "reset", "preset", "blacklist", "filter", "icon", "size", "color", "colour", "growth", "buff reminder", "sated" }) then return nil end
    local explicitScopeWording = ContainsAny(text, { "aura editing scope", "editing aura scope", "aura scope", "edit aura scope", "scope to", "scope as" })
    local naturalEditWording = ContainsAny(text, { "edit player auras", "edit target auras", "edit focus auras", "edit boss auras", "edit party auras", "edit raid auras", "edit group auras", "edit shared auras", "select player auras", "select target auras", "select party auras", "select raid auras", "switch to player auras", "switch to target auras", "switch to party auras", "switch to raid auras" })
    if not (explicitScopeWording or naturalEditWording) then return nil end
    local scope = AuraEditScopeForText(text)
    if not scope then return nil end
    local action = Registry and Registry:GetAction("set_aura_edit_scope")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope },
        label = "Set aura editing scope",
        summary = "Selects the Aura page editing scope.",
    } or nil
end

local function ParseAuraReset(text)
    if not ContainsAny(text, { "aura", "auras" }) then return nil end
    if not ContainsAny(text, { "reset", "clear", "remove overrides", "reset overrides", "zuruecksetzen" }) then return nil end
    if ContainsAny(text, { "blacklist", "blacklisted", "blocked aura", "blocked auras", "ignore aura", "ignore auras" }) then return nil end
    if ContainsAny(text, { "color", "colors", "colour", "colours" }) then return nil end
    local all = ContainsAny(text, { "all aura overrides", "all auras overrides", "all overrides", "every aura override", "all aura custom", "reset all auras" })
    local action
    if all then
        action = Registry and Registry:GetAction("reset_all_aura_overrides")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Reset all aura overrides",
            summary = "Resets every per-scope Aura override.",
        } or nil
    end
    local scope = AuraEditScopeForText(text)
    if not scope or scope == "shared" then return nil end
    if not ContainsAny(text, { "scope", "override", "overrides", "custom", "settings", "target aura", "player aura", "focus aura", "boss aura" }) then return nil end
    action = Registry and Registry:GetAction("reset_aura_scope_overrides")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope },
        confirmRequired = true,
        label = "Reset aura scope overrides",
        summary = "Resets one Aura editing scope back to Shared.",
    } or nil
end

local function ParseAuraSettingsView(text)
    if not ContainsAny(text, { "aura settings", "aura setting", "aura view", "aura mode", "auras view", "auras mode" }) then return nil end
    if not ContainsAny(text, { "basic", "simple", "advanced", "all settings", "all options", "show all", "show basic" }) then return nil end
    local value
    if ContainsAny(text, { "advanced", "all settings", "all options", "show all" }) then
        value = "advanced"
    elseif ContainsAny(text, { "basic", "simple", "show basic" }) then
        value = "basic"
    end
    if not value then return nil end
    local setting = Registry and Registry:GetSetting("menu.aurasUXMode")
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Aura settings view",
        summary = "Changes the Aura page Basic/All Settings view.",
    } or nil
end

local function ParseAuraQuickPreset(text)
    if not ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" }) then return nil end
    if not ContainsAny(text, { "preset", "quick setup", "quicksetup", "setup", "apply", "use" }) then return nil end
    local preset = AuraQuickPresetForText(text)
    if not preset then return nil end
    local action = Registry and Registry:GetAction("apply_aura_quick_preset")
    return action and {
        kind = "action",
        action = action,
        args = { scope = AuraBlacklistScope(text), preset = preset },
        confirmRequired = true,
        label = "Apply aura quick preset",
        summary = "Applies the shared Auras quick setup helper.",
    } or nil
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

local function ParseAuraGroupCategoryBlacklist(text)
    if ContainsAny(text, { "copy category", "copy categories", "group copy", "unit copy" }) then return nil end
    local categoryIntent = ContainsAny(text, {
        "category", "categories", "public category", "public categories",
        "category blacklist", "category blacklists", "blacklisted category", "blacklisted categories",
    })
    if not categoryIntent then return nil end
    if not ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs", "group", "party", "raid", "mythic raid", "mythicraid" }) then return nil end

    local category = AuraGroupBlacklistCategoryForText(text)
    local summaryIntent = ContainsAny(text, { "list", "summary", "current", "what is", "whats" })
        or (ContainsAny(text, { "show" }) and ContainsAny(text, { "blacklist", "category blacklist", "blacklisted category", "blacklisted categories" }))
    if summaryIntent then
        local action = Registry and Registry:GetAction("aura_group_category_blacklist_summary")
        return action and {
            kind = "action",
            action = action,
            args = { scope = AuraGroupBlacklistScope(text), lane = AuraGroupBlacklistLane(text) },
            label = "Show group aura category blacklist",
            summary = "Shows the public aura category blacklist for group-frame auras.",
        } or nil
    end

    local clearAllIntent = ContainsAny(text, { "clear all", "allow all", "unblacklist all", "remove all", "reset", "empty" })
        or (ContainsAny(text, { "clear", "allow", "unblacklist", "remove", "reset", "empty" }) and ContainsAny(text, { "all categories", "every category", "categories" }))
    if clearAllIntent then
        local action = Registry and Registry:GetAction("aura_group_category_blacklist_clear")
        return action and {
            kind = "action",
            action = action,
            args = { scope = AuraGroupBlacklistScope(text), lane = AuraGroupBlacklistLane(text) },
            label = "Clear group aura category blacklist",
            summary = "Allows all public aura categories for the selected group-frame aura lane.",
        } or nil
    end

    if not category then return nil end
    local value
    if ContainsAny(text, { "allow", "unblacklist", "remove", "clear", "include", "show", "anzeigen", "entfernen", "loeschen" }) then
        value = false
    elseif ContainsAny(text, { "blacklist", "hide", "block", "exclude", "disable", "ausblenden", "verstecken", "deaktivieren" }) then
        value = true
    end
    if value == nil then return nil end

    local action = Registry and Registry:GetAction("aura_group_category_blacklist_set")
    return action and {
        kind = "action",
        action = action,
        args = {
            scope = AuraGroupBlacklistScope(text),
            lane = AuraGroupBlacklistLane(text),
            category = category,
            value = value,
        },
        label = "Set group aura category blacklist",
        summary = "Edits the group-frame public aura category blacklist through the Auras3 MenuModel.",
    } or nil
end

local function CleanAuraBlacklistSpellValue(value)
    value = Trim(tostring(value or ""))
    value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
    value = value:gsub("^spell%s+", "")
    value = value:gsub("^named%s+", "")
    value = value:gsub("^called%s+", "")
    value = value:gsub("^#%s*", "")
    value = value:gsub("[%s%.%,%;%!%?]+$", "")
    value = Trim(value)
    local normalized = Normalize(value)
    if normalized == "" or normalized == "all" or normalized == "all spell" or normalized == "all spells"
        or normalized == "all aura" or normalized == "all auras" or normalized == "every spell"
        or normalized == "every aura" then
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
        "[Rr]emove%s+(.+)%s+from%s+.+[Bb]lacklist",
        "[Rr]emove%s+(.+)%s+from%s+.+[Aa]uras?",
        "[Aa]llow%s+(.+)%s+[Ff]or%s+.+[Aa]uras?",
        "[Aa]llow%s+(.+)%s+[Oo]n%s+.+[Aa]uras?",
        "[Uu]nblacklist%s+(.+)%s+[Ff]or%s+",
        "[Uu]nblacklist%s+(.+)%s+[Oo]n%s+",
        "[Uu]nblock%s+(.+)%s+[Ff]or%s+",
        "[Uu]nblock%s+(.+)%s+[Oo]n%s+",
    }
    for i = 1, #patterns do
        value = CleanAuraBlacklistSpellValue(raw:match(patterns[i]))
        if value then return value end
    end
    return nil
end

local function ParseAuraBlacklist(text, raw)
    if not ContainsAny(text, { "blacklist", "blocked aura", "blocked auras", "ignore aura", "ignore auras", "block", "unblock", "unblacklist" })
        and not (ContainsAny(text, { "allow", "remove" }) and ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs", "spell" })) then
        return nil
    end
    if not ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs", "spell" }) then return nil end

    local scope = AuraBlacklistScope(text)
    if ContainsAny(text, { "show", "list", "summary", "current", "what is", "whats" }) then
        local action = Registry and Registry:GetAction("aura_blacklist_summary")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope },
            label = "Show aura blacklist",
            summary = "Shows the prepared aura blacklist for the selected scope.",
        } or nil
    end

    local preset = AuraBlacklistPresetForText(text)
    if preset then
        local action = Registry and Registry:GetAction("aura_blacklist_add_preset")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, preset = preset },
            label = "Add aura blacklist preset",
            summary = "Adds a curated public spell-ID preset to the selected aura blacklist.",
        } or nil
    end

    local value = AuraBlacklistSpellValue(raw)
    local clearAllIntent = ContainsAny(text, { "clear all", "allow all", "remove all", "delete all", "unblacklist all", "empty", "reset" })
        or (ContainsAny(text, { "clear", "allow", "remove", "delete", "unblacklist" }) and ContainsAny(text, { "all spells", "all auras", "every spell", "every aura" }))
        or (not value and ContainsAny(text, { "clear", "remove", "delete" }) and ContainsAny(text, { "blacklist", "blocked aura", "blocked auras", "ignore aura", "ignore auras" }))
    if clearAllIntent and not ContainsAny(text, { "preset", "category", "categories" }) then
        local action = Registry and Registry:GetAction("aura_blacklist_clear_spells")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope },
            label = "Clear aura blacklist",
            summary = "Allows all spell entries for the selected aura blacklist scope.",
        } or nil
    end

    if not value then return nil end
    local remove = ContainsAny(text, { "remove", "delete", "unblacklist", "allow", "unblock", "loeschen", "entfernen" })
    local action = Registry and Registry:GetAction(remove and "aura_blacklist_remove_spell" or "aura_blacklist_add_spell")
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope, value = value },
        label = remove and "Remove aura blacklist spell" or "Add aura blacklist spell",
        summary = "Edits the prepared aura blacklist through the Auras3 MenuModel.",
    } or nil
end

P.AURA_BLACKLIST_PRESETS = AURA_BLACKLIST_PRESETS
P.AuraBlacklistScope = AuraBlacklistScope
P.AURA_QUICK_PRESETS = AURA_QUICK_PRESETS
P.AuraQuickPresetForText = AuraQuickPresetForText
P.AuraEditScopeForText = AuraEditScopeForText
P.ParseAuraEditScope = ParseAuraEditScope
P.ParseAuraReset = ParseAuraReset
P.ParseAuraSettingsView = ParseAuraSettingsView
P.ParseAuraGeometryShortcut = ParseAuraGeometryShortcut
P.ParseAuraQuickPreset = ParseAuraQuickPreset
P.AuraBlacklistPresetForText = AuraBlacklistPresetForText
P.AuraGroupBlacklistScope = AuraGroupBlacklistScope
P.AuraGroupBlacklistLane = AuraGroupBlacklistLane
P.AuraGroupBlacklistCategoryForText = AuraGroupBlacklistCategoryForText
P.ParseAuraGroupCategoryBlacklist = ParseAuraGroupCategoryBlacklist
P.AuraBlacklistSpellValue = AuraBlacklistSpellValue
P.ParseAuraBlacklist = ParseAuraBlacklist
