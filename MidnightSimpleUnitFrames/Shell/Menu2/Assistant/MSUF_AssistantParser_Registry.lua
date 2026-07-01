--- Shell/Menu2/Assistant/MSUF_AssistantParser_Registry.lua
--- Registry-backed parser for Assistant setting-change plans.
---
--- Ranks declarative registry entries and returns planned changes only; do not
--- write SavedVariables or touch frames in this parser shard.

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
local Trim = P.Trim
local Normalize = P.Normalize
local HasPhrase = P.HasPhrase
local ContainsAny = P.ContainsAny
local ALL_UNITFRAMES = P.ALL_UNITFRAMES
local ALL_GROUPS = P.ALL_GROUPS
local CLASS_POWER_TERMS = P.CLASS_POWER_TERMS
local CASTBAR_ROOT_DETAIL_TERMS = P.CASTBAR_ROOT_DETAIL_TERMS
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local DetectGlobalScope = P.DetectGlobalScope
local DetectBoolean = P.DetectBoolean
local FirstNumber = P.FirstNumber
local Compact = P.Compact
local AliasRelationText = P.AliasRelationText
local TextMatchesAlias = P.TextMatchesAlias
local ActionableText = P.ActionableText
local ExtractColor = P.ExtractColor
local DetectDirection = P.DetectDirection
local UnitPageKey = P.UnitPageKey
local RawAfterLastConnector = P.RawAfterLastConnector

local explicitScopeCacheText
local explicitScopeCacheUnits
local explicitScopeCacheGroups

-- Scope detection is reused for every candidate setting during one parse. Cache the result
-- for the raw text so large registries do not repeatedly scan the same command.
local function ExplicitScopes(text)
    local key = tostring(text or "")
    if key == explicitScopeCacheText then return explicitScopeCacheUnits, explicitScopeCacheGroups end
    explicitScopeCacheText = key
    explicitScopeCacheUnits = DetectUnits(key)
    explicitScopeCacheGroups = DetectGroups(key)
    return explicitScopeCacheUnits, explicitScopeCacheGroups
end

local function ListContains(list, value)
    for i = 1, #(list or {}) do
        if list[i] == value then return true end
    end
    return false
end

local function SettingKeyScope(setting)
    local key = tostring(setting and setting.key or "")
    local prefix = key:match("^([^%.]+)")
    if not prefix or prefix == "" then return nil end
    if prefix == "barScope" or prefix == "fontScope" then
        prefix = key:match("^[^%.]+%.([^%.]+)") or prefix
    end
    if prefix == "gf_party" then return "party" end
    if prefix == "gf_raid" then return "raid" end
    if prefix == "gf_mythicraid" then return "mythicraid" end
    return prefix
end

local function GroupSettingAllowsWantedGroup(setting, wantedGroup)
    if not wantedGroup then return true end
    if tostring(setting and setting.unit or "") == wantedGroup then return true end
    return setting and setting.frameType == "groupAura" and setting.unit == "raid" and wantedGroup == "mythicraid"
end

local function RemoveScopeWord(text, scope)
    local aliases = A.UnitAliases or {}
    local list = aliases[scope] or { scope }
    local out = " " .. Normalize(text) .. " "
    for i = 1, #list do
        local alias = Normalize(list[i])
        if alias ~= "" then
            out = out:gsub(" " .. alias:gsub("([^%w%s])", "%%%1") .. " ", " ")
        end
    end
    return Normalize(out)
end

local function ScopeAdjustedTextForSetting(setting, text)
    if type(setting) ~= "table" or not setting.unit then return text end
    if setting.unit == "global" or setting.unit == "shared" or setting.frameType == "aura" or setting.frameType == "groupAura" then return text end
    -- When a sentence names several frames, remove the other frame names before matching a
    -- candidate. This lets "make player bigger than target" score the player width setting
    -- without target aliases making unrelated target settings look equally valid.
    local unit = tostring(setting.unit)
    local keyScope = SettingKeyScope(setting)
    local settingKey = tostring(setting.key or ""):lower()
    if settingKey:find("bosstarget", 1, true) and ContainsAny(text, { "boss target", "boss targets" }) then return text end
    local units, groups = ExplicitScopes(text)
    local adjusted = text
    if setting.frameType == "group" or setting.frameType == "groupAura" then
        if #groups <= 1 then return text end
        if not ListContains(groups, unit) and not ListContains(groups, keyScope) then return nil end
        if keyScope and ListContains(groups, keyScope) then unit = keyScope end
        for i = 1, #groups do
            if groups[i] ~= unit then adjusted = RemoveScopeWord(adjusted, groups[i]) end
        end
        return adjusted
    end
    if #units <= 1 then return text end
    if not ListContains(units, unit) and not ListContains(units, keyScope) then return nil end
    if keyScope and ListContains(units, keyScope) then unit = keyScope end
    for i = 1, #units do
        if units[i] ~= unit then adjusted = RemoveScopeWord(adjusted, units[i]) end
    end
    return adjusted
end

local function HasAllScopeIntent(text)
    return ContainsAny(text, {
        "all", "all of", "for all", "every", "everyone", "everything", "each",
        "alle", "alles", "fuer alle", "jede", "jeder", "jedes", "jeweils",
    })
end

P.ExplicitAuraFilterScope = P.ExplicitAuraFilterScope or function(text)
    if not (ContainsAny(text, { "filter", "filters" }) and ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" })) then return nil end
    local scopes = {
        { scope = "shared", terms = { "shared", "global" } },
        { scope = "player", terms = { "player", "spieler", "self", "ich" } },
        { scope = "target", terms = { "target", "ziel" } },
        { scope = "focus", terms = { "focus", "fokus" } },
        { scope = "boss", terms = { "boss" } },
    }
    local lanes = { "buff", "buffs", "debuff", "debuffs", "aura", "auras" }
    for i = 1, #scopes do
        for t = 1, #scopes[i].terms do
            for l = 1, #lanes do
                if HasPhrase(text, scopes[i].terms[t] .. " " .. lanes[l]) then
                    return scopes[i].scope
                end
            end
        end
    end
    return nil
end

local ROOT_FRAME_ENABLED_DETAIL_TERMS = {
    "indicator", "indicators", "status icon", "status icons", "status indicator", "status indicators",
    "icon", "icons", "symbol", "symbols", "portrait", "portraits", "power bar", "mana bar",
    "health bar", "hp bar", "castbar", "cast bar", "name", "names", "text", "border", "outline",
    "alpha", "opacity", "range fade", "offline", "solo", "sort", "sorting", "role", "scale", "scaling",
}

local function RootFrameEnabledBlockedByDetail(setting, text)
    if not (setting and setting.attribute == "enabled") then return false end
    if setting.frameType ~= "unitframe" and setting.frameType ~= "group" then return false end
    return ContainsAny(text, ROOT_FRAME_ENABLED_DETAIL_TERMS)
end

local AURA_LANE_VISIBILITY_DETAIL_TERMS = {
    "stack text", "stack count", "count text", "stacks",
    "cooldown text", "timer text", "cooldown swipe", "timer swipe",
    "text size", "font size", "cooldown size", "stack size",
    "filter", "filters", "only my", "my buffs only", "my debuffs only", "only mine",
    "dispellable", "dispel", "blacklist", "whitelist", "hidden aura", "hidden spell",
    "spell id", "spell:", "spell ",
}

local function IsAuraLaneVisibilitySetting(setting)
    if type(setting) ~= "table" then return false end
    local frameType = tostring(setting.frameType or "")
    if frameType ~= "aura" and frameType ~= "groupAura" then return false end
    if setting.type ~= "boolean" then return false end
    local key = tostring(setting.key or ""):lower()
    local attr = tostring(setting.attribute or ""):lower()
    if key == "auras3.shared.showbuffs" or key == "auras3.shared.showdebuffs" then return true end
    if key:find("%.buff%.visible", 1, true) or key:find("%.debuff%.visible", 1, true) then return true end
    if key:find("%.auras%.buff%.enabled", 1, true) or key:find("%.auras%.debuff%.enabled", 1, true) then return true end
    return attr == "aurashowbuffs"
        or attr == "aurashowdebuffs"
        or attr == "aurabuffvisible"
        or attr == "auradebuffvisible"
        or attr == "gfaurabuffenabled"
        or attr == "gfauradebuffenabled"
end

local function AuraLaneVisibilityBlockedByDetail(setting, text)
    if not IsAuraLaneVisibilitySetting(setting) then return false end
    if ContainsAny(text, AURA_LANE_VISIBILITY_DETAIL_TERMS) then return true end
    if ContainsAny(text, { " icon", " icons" })
        and not ContainsAny(text, { "buff icons", "debuff icons", "aura icons", "buff icon", "debuff icon", "aura icon" })
    then
        return true
    end
    return false
end

local function ClassPowerMentionIsNegated(text)
    return ContainsAny(text, {
        "not class resource", "not class resources", "not class power", "not class bar", "not resource bar",
        "no class resource", "no class resources", "no class power", "no class bar", "no resource bar",
        "dont class resource", "do not class resource",
        "nicht class resource", "nicht class power", "nicht klassenressource", "keine class resource",
        "kein class resource", "keine klassenressource", "nicht ressourcenleiste",
    })
end

local function HasClassPowerIntent(text)
    return ContainsAny(text, CLASS_POWER_TERMS) and not ClassPowerMentionIsNegated(text)
end

local function ClassPowerBlockedByExplicitUnitPowerIntent(setting, text)
    if not (setting and setting.frameType == "classPower") then return false end
    if ClassPowerMentionIsNegated(text) then return true end
    if HasClassPowerIntent(text) then return false end
    local units, groups = ExplicitScopes(text)
    return (#units + #groups) > 0
end

P.NON_AURA_DEBUFF_CONTROL_TERMS = P.NON_AURA_DEBUFF_CONTROL_TERMS or {
    "debuff stripe", "debuff stripes",
    "dispel overlay", "dispel overlays", "unitframe dispel", "unit frame dispel",
    "unitframe dispel overlay", "unit frame dispel overlay",
    "debuff overlay", "debuff overlays",
    "dispellable overlay", "dispellable overlays", "dispellable debuff overlay", "dispellable debuff overlays",
    "dispel health overlay", "dispellable health overlay",
    "health bar dispel overlay", "healthbar dispel overlay",
    "debuff type color", "debuff type colors", "debuff type colour", "debuff type colours",
    "dispel color", "dispel colors", "dispel colour", "dispel colours",
    "magic debuff color", "magic debuff colour", "magic dispel color", "magic dispel colour",
    "curse debuff color", "curse debuff colour", "curse dispel color", "curse dispel colour",
    "disease debuff color", "disease debuff colour", "disease dispel color", "disease dispel colour",
    "poison debuff color", "poison debuff colour", "poison dispel color", "poison dispel colour",
    "bleed debuff color", "bleed debuff colour", "bleed dispel color", "bleed dispel colour",
}

local function HasAuraSettingIntent(text)
    -- "Debuff stripe" and "dispel overlay" belong to unitframe visuals, not aura filtering.
    -- Guard them here before broad buff/debuff words pull the command into the aura registry.
    if ContainsAny(text, P.NON_AURA_DEBUFF_CONTROL_TERMS) then return false end
    return ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" })
end

P.AURA_VAGUE_ICON_SIZE_TERMS = P.AURA_VAGUE_ICON_SIZE_TERMS or {
    "bigger", "larger", "smaller", "shrink", "groesser", "kleiner",
    "icon bigger", "icon larger", "icon smaller", "icons bigger", "icons larger", "icons smaller",
}

P.AURA_VAGUE_ICON_SIZE_BLOCKERS = P.AURA_VAGUE_ICON_SIZE_BLOCKERS or {
    "text", "font", "stack", "cooldown", "timer", "spacing", "gap",
    "offset", "x offset", "y offset", "left", "right", "up", "down",
    "per row", "icons per row", "max", "count", "filter", "exclusive",
    "layer", "z order",
}

P.HasVagueAuraIconSizeIntent = P.HasVagueAuraIconSizeIntent or function(text)
    if not HasAuraSettingIntent(text) then return false end
    if not ContainsAny(text, P.AURA_VAGUE_ICON_SIZE_TERMS) then return false end
    if ContainsAny(text, P.AURA_VAGUE_ICON_SIZE_BLOCKERS) then return false end
    return true
end

P.IsAuraIconSizeSetting = P.IsAuraIconSizeSetting or function(setting)
    if type(setting) ~= "table" then return false end
    local frameType = tostring(setting.frameType or "")
    if frameType ~= "aura" and frameType ~= "groupAura" then return false end
    if setting.type ~= "number" then return false end
    local hay = (tostring(setting.key or "") .. " " .. tostring(setting.label or "") .. " " .. tostring(setting.attribute or "")):lower()
    if not (hay:find("size", 1, true) or hay:find("iconsize", 1, true) or hay:find("icon size", 1, true)) then return false end
    return not (
        hay:find("stack", 1, true)
        or hay:find("cooldown", 1, true)
        or hay:find("timer", 1, true)
        or hay:find("text", 1, true)
        or hay:find("font", 1, true)
    )
end

local function NonAuraSettingBlockedByAuraIntent(setting, text)
    if not HasAuraSettingIntent(text) then return false end
    local frameType = tostring(setting and setting.frameType or "")
    if frameType == "aura" or frameType == "groupAura" then return false end
    if frameType == "classPower" and HasClassPowerIntent(text) then return false end
    local key = tostring(setting and setting.key or "")
    local attribute = tostring(setting and setting.attribute or ""):lower()
    local category = tostring(setting and setting.category or ""):lower()
    if key:find("^general%.auras") or key:find("^auras3%.") then return false end
    if attribute:find("aura", 1, true) or category:find("auras", 1, true) then return false end
    return true
end

local function ShouldApplyMultipleRegistryChanges(text, changes)
    if #(changes or {}) <= 1 then return false end
    -- Bulk writes must be opt-in by language or by an unmistakable two-lane aura command.
    -- Ambiguous matches stay as choices so the user can pick before anything is applied.
    if HasAllScopeIntent(text) then return true end
    if P.ShouldApplyMultipleAuraLaneChanges and P.ShouldApplyMultipleAuraLaneChanges(text, changes) then return true end
    local units, groups = ExplicitScopes(text)
    return (#units + #groups) > 1
end

P.ShouldApplyMultipleAuraLaneChanges = P.ShouldApplyMultipleAuraLaneChanges or function(text, changes)
    if #(changes or {}) ~= 2 then return false end
    if not ContainsAny(text, { "aura", "auras", "aura icon", "aura icons" }) then return false end
    local base
    local sawBuff, sawDebuff = false, false
    for i = 1, #changes do
        local setting = changes[i] and changes[i].setting
        local frameType = tostring(setting and setting.frameType or "")
        if frameType ~= "aura" and frameType ~= "groupAura" then return false end
        local key = tostring(setting and setting.key or "")
        if key:find(".buff.", 1, true) then
            sawBuff = true
        elseif key:find(".debuff.", 1, true) then
            sawDebuff = true
        else
            return false
        end
        local normalized = key:gsub("%.buff%.", ".lane."):gsub("%.debuff%.", ".lane.")
        if base and base ~= normalized then return false end
        base = normalized
    end
    return sawBuff and sawDebuff
end

P.AreBulkSafeAuraSettingChanges = P.AreBulkSafeAuraSettingChanges or function(changes)
    if #(changes or {}) <= 1 then return false end
    for i = 1, #changes do
        local setting = changes[i] and changes[i].setting
        if type(setting) ~= "table" or setting.confirmRequired == true then return false end
        local frameType = tostring(setting.frameType or "")
        if frameType ~= "aura" and frameType ~= "groupAura" then return false end
    end
    return true
end

local function SettingAllowedByExplicitScopes(setting, text)
    if type(setting) ~= "table" then return false end
    if ClassPowerBlockedByExplicitUnitPowerIntent(setting, text) then return false end
    if NonAuraSettingBlockedByAuraIntent(setting, text) then return false end
    local frameType = tostring(setting.frameType or "")
    if AuraLaneVisibilityBlockedByDetail(setting, text) then return false end
    if P.HasVagueAuraIconSizeIntent(text)
        and (frameType == "aura" or frameType == "groupAura")
        and not P.IsAuraIconSizeSetting(setting)
    then
        return false
    end
    local unit = tostring(setting.unit or "")
    local keyScope = SettingKeyScope(setting)
    local units, groups = ExplicitScopes(text)
    if frameType == "aura"
        and unit == "shared"
        and (#units > 0 or #groups > 0)
        and not ContainsAny(text, { "shared", "global", "all aura", "all auras", "all buffs", "all debuffs", "every aura", "every auras", "every buff", "every buffs", "every debuff", "every debuffs" })
    then
        return false
    end
    -- Shared aura controls can be valid for "all auras", but some lane-level shared growth
    -- options are deliberately excluded because they would fight the per-frame buff/debuff
    -- settings the user usually means.
    if frameType == "aura"
        and unit == "shared"
        and HasAllScopeIntent(text)
        and ContainsAny(text, { "growth", "grow", "growth direction", "grow direction" })
        and ContainsAny(text, { "all buffs", "all debuffs", "all aura", "all auras" })
    then
        local key = tostring(setting.key or ""):lower()
        if key == "auras3.shared.buffgrowth" or key == "auras3.shared.debuffgrowth" then return false end
    end
    if setting.frameType == "aura" and ContainsAny(text, { "filter", "filters" })
        and not tostring(setting.attribute or ""):lower():find("filter", 1, true) then
        return false
    end
    local auraFilterScope = P.ExplicitAuraFilterScope and P.ExplicitAuraFilterScope(text)
    if setting.frameType == "aura" and auraFilterScope then
        return unit == auraFilterScope or keyScope == auraFilterScope
    end
    if setting.frameType == "aura" and unit == "shared" and ContainsAny(text, { "shared", "global", "all auras", "all aura" }) then
        return true
    end
    if setting.frameType == "group" or setting.frameType == "groupAura" then
        if #groups > 0 then return ListContains(groups, unit) or ListContains(groups, keyScope) end
        if #units > 0 then return false end
        return true
    end
    local settingKey = tostring(setting.key or ""):lower()
    if settingKey:find("bosstarget", 1, true) and ContainsAny(text, { "boss target", "boss targets" }) then return true end
    if #units > 0 and unit ~= "" and unit ~= "global" and not ListContains(units, unit) and not ListContains(units, keyScope) then return false end
    if #groups > 0 and #units == 0 and unit ~= "" and unit ~= "global" and not ListContains(groups, unit) and not ListContains(groups, keyScope) then return false end
    return true
end

local function SettingMatchesText(setting, text)
    if type(setting) ~= "table" then return false end
    if RootFrameEnabledBlockedByDetail(setting, text) then return false end
    if AuraLaneVisibilityBlockedByDetail(setting, text) then return false end
    if not SettingAllowedByExplicitScopes(setting, text) then return false end
    if setting.frameType == "group" or setting.frameType == "groupAura" then
        local wantedGroup
        if HasPhrase(text, "mythicraid") or HasPhrase(text, "mythic raid") then
            wantedGroup = "mythicraid"
        elseif HasPhrase(text, "party") then
            wantedGroup = "party"
        elseif HasPhrase(text, "raid") then
            wantedGroup = "raid"
        end
        if not GroupSettingAllowsWantedGroup(setting, wantedGroup) then return false end
    end
    local matchText = ScopeAdjustedTextForSetting(setting, text)
    if not matchText then return false end
    local relationText = AliasRelationText(matchText)
    local aliases = setting.aliases or {}
    for i = 1, #aliases do
        if TextMatchesAlias(matchText, relationText, aliases[i]) then return true end
    end
    if setting.matchLabel ~= false and setting.label and TextMatchesAlias(matchText, relationText, setting.label) then return true end
    return false
end

local BOOLEAN_TOGGLE_TERMS = { "toggle", "switch", "flip", "invert", "umschalten", "wechseln" }
local BOOLEAN_ALIAS_STATE_WORDS = {
    "enabled", "disabled", "enable", "disable", "shown", "show", "hidden", "hide",
    "visible", "visibility", "displayed", "display",
    "aktiviert", "deaktiviert", "aktivieren", "deaktivieren", "anzeigen", "ausblenden", "sichtbar",
}

local function BooleanToggleMatchScore(setting, matchText, relationText)
    if type(setting) ~= "table" or setting.type ~= "boolean" then return 0 end
    if not ContainsAny(matchText, BOOLEAN_TOGGLE_TERMS) then return 0 end
    relationText = relationText or AliasRelationText(matchText)
    local best = 0
    local function consider(alias)
        alias = Normalize(alias)
        if alias == "" then return end
        for i = 1, #BOOLEAN_ALIAS_STATE_WORDS do
            alias = alias:gsub("%f[%w]" .. BOOLEAN_ALIAS_STATE_WORDS[i] .. "%f[%W]", " ")
        end
        alias = Trim(alias:gsub("%s+", " "))
        local compact = Compact(alias)
        if #compact < 5 then return end
        if TextMatchesAlias(matchText, relationText, alias) and #compact > best then best = #compact end
    end
    consider(setting.label)
    for i = 1, #(setting.aliases or {}) do consider(setting.aliases[i]) end
    return best
end

local function SettingMatchScore(setting, text)
    if type(setting) ~= "table" then return 0 end
    text = tostring(text or "")
    -- The score is based on the longest useful alias/label that survived scope filtering.
    -- This favors precise controls over broad page words like "bars" or "text".
    if type(P._settingMatchScoreCache) == "table" then
        local cached = P.SettingMatchScoreCacheGet and P.SettingMatchScoreCacheGet(setting, text)
        if cached ~= nil then return cached end
    end
    if RootFrameEnabledBlockedByDetail(setting, text) then return 0 end
    if AuraLaneVisibilityBlockedByDetail(setting, text) then return 0 end
    if not SettingAllowedByExplicitScopes(setting, text) then return 0 end
    if setting.frameType == "castbar" and setting.attribute == "enabled" and ContainsAny(text, CASTBAR_ROOT_DETAIL_TERMS) then
        return 0
    end
    if setting.frameType == "classPower" and ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) and not ContainsAny(text, CLASS_POWER_TERMS) then
        return 0
    end
    if setting.frameType == "classPower" and ContainsAny(text, { "portrait", "portrait border" }) and not ContainsAny(text, CLASS_POWER_TERMS) then
        return 0
    end
    if setting.frameType == "group" or setting.frameType == "groupAura" then
        local wantedGroup
        if HasPhrase(text, "mythicraid") or HasPhrase(text, "mythic raid") then
            wantedGroup = "mythicraid"
        elseif HasPhrase(text, "party") then
            wantedGroup = "party"
        elseif HasPhrase(text, "raid") then
            wantedGroup = "raid"
        end
        if not GroupSettingAllowsWantedGroup(setting, wantedGroup) then return 0 end
    end

    local matchText = ScopeAdjustedTextForSetting(setting, text)
    if not matchText then return 0 end
    local best = 0
    local relationText = AliasRelationText(matchText)
    local aliases = setting.aliases or {}
    for i = 1, #aliases do
        if TextMatchesAlias(matchText, relationText, aliases[i]) then
            local score = #Compact(aliases[i])
            if score > best then best = score end
        end
    end
    if setting.matchLabel ~= false and setting.label and TextMatchesAlias(matchText, relationText, setting.label) then
        local score = #Compact(setting.label)
        if score > best then best = score end
    end
    if best == 0 then
        best = BooleanToggleMatchScore(setting, matchText, relationText)
    end
    if best > 0 and P.SettingMatchScoreCachePut then return P.SettingMatchScoreCachePut(setting, text, best) end
    return best
end

local function EnumValueForText(setting, text)
    local function matchSegment(segment)
        segment = Normalize(segment)
        if segment == "" then return nil end
        local aliases = setting and setting.valueAliases
        local compactText = Compact(segment)
        if type(aliases) == "table" then
            local bestValue
            local bestLen = 0
            for alias, value in pairs(aliases) do
                local compactAlias = Compact(alias)
                if HasPhrase(segment, alias) or (#compactAlias >= 5 and compactText:find(compactAlias, 1, true)) then
                    local len = #Compact(alias)
                    if len > bestLen then
                        bestLen = len
                        bestValue = value
                    end
                end
            end
            if bestValue ~= nil then return bestValue end
        end
        local values = setting and setting.values
        if type(values) == "table" then
            for i = 1, #values do
                local value = values[i]
                local compactValue = Compact(value)
                if HasPhrase(segment, tostring(value)) or (#compactValue >= 5 and compactText:find(compactValue, 1, true)) then return value end
            end
        end
        return nil
    end
    local norm = Normalize(text)
    local padded = " " .. norm .. " "
    local connectors = { " to ", " as ", " is ", " be ", " = ", " auf ", " zu ", " als " }
    local bestEnd
    for i = 1, #connectors do
        local startAt = 1
        while true do
            local _, endPos = padded:find(connectors[i], startAt, true)
            if not endPos then break end
            if not bestEnd or endPos > bestEnd then bestEnd = endPos end
            startAt = endPos + 1
        end
    end
    local tail = bestEnd and Trim(padded:sub(bestEnd + 1)) or nil
    if tail then tail = Trim(tail:gsub("^the%s+", ""):gsub("^a%s+", "")) end
    local tailValue = tail and tail ~= "" and matchSegment(tail)
    if tailValue ~= nil then return tailValue end
    if tail and tail ~= "" then return nil end
    return matchSegment(norm)
end

P.BooleanAliasValueForText = P.BooleanAliasValueForText or function(setting, text)
    local aliases = setting and (setting.booleanAliases or setting.valueAliases)
    if type(aliases) ~= "table" then return nil end
    local compactText = Compact(text)
    local bestValue
    local bestLen = 0
    for alias, value in pairs(aliases) do
        local aliasValue
        if setting and setting.type == "number" then
            aliasValue = tonumber(value)
        else
            if value == true or value == "true" or value == 1 then
                aliasValue = true
            elseif value == false or value == "false" or value == 0 then
                aliasValue = false
            end
        end
        if aliasValue ~= nil then
            local compactAlias = Compact(alias)
            if HasPhrase(text, alias) or (#compactAlias >= 5 and compactText:find(compactAlias, 1, true)) then
                local len = #compactAlias
                if len > bestLen then
                    bestLen = len
                    bestValue = aliasValue
                end
            end
        end
    end
    return bestValue
end

P._ExactEnumValueForText = P._ExactEnumValueForText or function(setting, text)
    local segment = Normalize(text)
    if segment == "" then return nil end
    local compactText = Compact(segment)
    local values = setting and setting.values
    if type(values) == "table" then
        for i = 1, #values do
            local value = tostring(values[i] or "")
            if value ~= "" then
                if Normalize(value) == segment or Compact(value) == compactText then return values[i] end
            end
        end
    end
    return nil
end

P._StripExactValueConnector = P._StripExactValueConnector or function(text)
    text = Trim(text)
    text = text:gsub("^=%s*", "")
    text = text:gsub("^[Tt][Oo]%s+", "")
    text = text:gsub("^[Aa][Ss]%s+", "")
    text = text:gsub("^[Ii][Ss]%s+", "")
    text = text:gsub("^[Bb][Ee]%s+", "")
    text = text:gsub("^[Aa][Uu][Ff]%s+", "")
    text = text:gsub("^[Zz][Uu]%s+", "")
    text = text:gsub("^[Aa][Ll][Ss]%s+", "")
    return Trim(text)
end

local function StringValueForText(setting, text, raw)
    local rawText = tostring(raw or "")
    local quoted = rawText:match("\"([^\"]*)\"") or rawText:match("'([^']*)'")
    if quoted ~= nil then return quoted end
    local rawLower = rawText:lower()
    local prefixes = {}
    local seenPrefixes = {}
    local function addPrefix(value)
        value = Normalize(value)
        if value ~= "" and not seenPrefixes[value] then
            seenPrefixes[value] = true
            prefixes[#prefixes + 1] = value
        end
    end
    if setting then
        local source = setting.valuePrefixes or setting.aliases or {}
        for i = 1, #(source or {}) do addPrefix(source[i]) end
        for i = 1, #(setting.aliases or {}) do addPrefix(setting.aliases[i]) end
        if setting.matchLabel ~= false then addPrefix(setting.label) end
    end
    for i = 1, #(prefixes or {}) do
        local prefix = Normalize(prefixes[i])
        if prefix ~= "" then
            local rawStart, rawEnd = (" " .. rawLower .. " "):find(" " .. tostring(prefixes[i] or ""):lower() .. " ", 1, true)
            if rawStart then
                local value = Trim(rawText:sub(rawEnd))
                value = value:gsub("^%s*[Tt][Oo]%s+", ""):gsub("^%s*[Aa][Ss]%s+", ""):gsub("^%s*[Ii][Ss]%s+", ""):gsub("^%s*[Bb][Ee]%s+", "")
                value = value:gsub("^%s*[Aa][Uu][Ff]%s+", ""):gsub("^%s*[Zz][Uu]%s+", ""):gsub("^%s*[Aa][Ll][Ss]%s+", "")
                value = Trim(value)
                if value ~= "" then return value end
            end
            local startPos, endPos = (" " .. text .. " "):find(" " .. prefix .. " ", 1, true)
            if startPos then
                local value = Trim(text:sub(endPos))
                value = value:gsub("^to%s+", ""):gsub("^as%s+", ""):gsub("^is%s+", ""):gsub("^be%s+", "")
                value = value:gsub("^auf%s+", ""):gsub("^zu%s+", ""):gsub("^als%s+", "")
                value = Trim(value)
                if value ~= "" then return value end
            end
        end
    end
    return nil
end

local SET_VALUE_CONNECTORS = { " to ", " as ", " is ", " be ", " value ", " = ", " auf ", " zu ", " als ", " wert " }

local function ExplicitFreeformValue(raw)
    local value = RawAfterLastConnector and RawAfterLastConnector(raw, SET_VALUE_CONNECTORS) or nil
    if value == nil then value = tostring(raw or ""):match("=%s*(.+)$") end
    if value == nil then return nil end
    value = Trim(value)
    if value == "" then return nil end
    return value
end

local function CustomSiblingForSetting(setting)
    if not (Registry and setting and setting.type == "enum") then return nil end
    local settings = Registry:AllSettings() or {}
    local labelKey = Compact(tostring(setting.label or "")):gsub("custom", "")
    local attrKey = Compact(tostring(setting.attribute or "")):gsub("custom", "")
    local keyTail = tostring(setting.key or ""):match("%.([^%.]+)$") or tostring(setting.key or "")
    keyTail = Compact(keyTail):gsub("custom", "")
    for i = 1, #settings do
        local candidate = settings[i]
        if candidate ~= setting
            and candidate.type == "string"
            and candidate.unit == setting.unit
            and candidate.frameType == setting.frameType
            and (not setting.category or not candidate.category or candidate.category == setting.category) then
            local hay = Normalize(tostring(candidate.label or "") .. " " .. tostring(candidate.key or "") .. " " .. tostring(candidate.attribute or ""))
            if HasPhrase(hay, "custom") then
                local candidateLabel = Compact(tostring(candidate.label or "")):gsub("custom", "")
                local candidateAttr = Compact(tostring(candidate.attribute or "")):gsub("custom", "")
                local candidateTail = tostring(candidate.key or ""):match("%.([^%.]+)$") or tostring(candidate.key or "")
                candidateTail = Compact(candidateTail):gsub("custom", "")
                if (labelKey ~= "" and candidateLabel == labelKey)
                    or (attrKey ~= "" and candidateAttr == attrKey)
                    or (keyTail ~= "" and candidateTail == keyTail) then
                    return candidate
                end
            end
        end
    end
    return nil
end

local ENUM_VALUE_DISPLAY_LABELS = {
    ALr = "alt",
    ALWAYS = "always",
    AUTO = "auto",
    AUrO = "auto",
    BLIZZARD = "Blizzard",
    BOrrOM = "bottom",
    BOrrOMLEFr = "bottom left",
    BOrrOMRIGHr = "bottom right",
    BRACKEr = "brackets",
    CENrER = "center",
    CIRCLE = "circle",
    CLASS = "class",
    CLASS_COLOR = "class color",
    CrRL = "ctrl",
    CURSOR = "cursor",
    CUSrOM = "custom",
    DEFAULr = "default",
    DIAMOND = "diamond",
    EXrERNAL = "external",
    FIXED = "fixed",
    GAME = "GameTooltip",
    HARMFUL = "harmful",
    ["HARMFUL|PLAYER"] = "harmful player",
    HELPFUL = "helpful",
    ["HELPFUL|PLAYER"] = "helpful player",
    HORIZONrAL_LEFr = "horizontal left",
    HORIZONrAL_RIGHr = "horizontal right",
    LEFr = "left",
    LEFrDOWN = "left then down",
    LEFrUP = "left then up",
    LrR = "left to right",
    MODIFIER = "modifier key",
    MSUF = "MSUF",
    NAMELEFr = "left of name",
    NAMERIGHr = "right of name",
    NEVER = "never",
    NONE = "none",
    NPC = "NPC",
    OFF = "off",
    ON = "on",
    OOC = "out of combat",
    PAREN = "parentheses",
    REACrION = "reaction",
    RIGHr = "right",
    RIGHrDOWN = "right then down",
    RIGHrUP = "right then up",
    ROUNDED = "rounded",
    RrL = "right to left",
    SHIFr = "shift",
    SINGLE = "single",
    SOLID = "solid",
    SQUARE = "square",
    rARGEr_NAME = "target name",
    rOP = "top",
    rOPLEFr = "top left",
    rOPRIGHr = "top right",
    rOr_NAME = "target of target name",
    rYPE = "type",
    VERrICAL_DOWN = "vertical down",
    VERrICAL_UP = "vertical up",
}

local ENUM_WORD_DISPLAY_LABELS = {
    afk = "AFK",
    dnd = "DND",
    hp = "HP",
    id = "ID",
    msuf = "MSUF",
    npc = "NPC",
    ooc = "out of combat",
    pvp = "PvP",
    ui = "UI",
}

local function HumanizeEnumDisplay(value)
    local raw = tostring(value or "")
    if raw == "" then return nil end
    local exact = ENUM_VALUE_DISPLAY_LABELS[raw] or ENUM_VALUE_DISPLAY_LABELS[raw:upper()]
    if exact then return exact end
    if not raw:find("[A-Z_|]") then return nil end

    local text = raw:gsub("|", " "):gsub("_", " ")
    text = text:gsub("(%l)(%u)", "%1 %2")
    text = text:gsub("(%u)(%u%l)", "%1 %2")

    local out = {}
    for word in text:gmatch("%S+") do
        local lower = word:lower()
        out[#out + 1] = ENUM_WORD_DISPLAY_LABELS[lower] or lower
    end
    if #out == 0 then return nil end
    return table.concat(out, " ")
end

local function DirectEnumDisplay(setting, value)
    if not (setting and setting.type == "enum" and type(value) == "string") then return nil end
    local colorLabel = type(A.DisplayColorLabel) == "function" and A.DisplayColorLabel(value) or value
    if colorLabel ~= value then return colorLabel end
    if value:match("^[a-z][a-z0-9 %-]*$") then return value end
    return HumanizeEnumDisplay(value)
end

local GERMAN_DISPLAY_ALIAS_rOKENS = {
    aktuell = true, alt = true, an = true, anzeige = true, anzeigen = true, aus = true,
    ausblenden = true, ausserhalb = true, automatisch = true, balken = true, deaktivieren = true,
    dunkel = true, einblenden = true, einfaerben = true, eigenes = true, einheitlich = true,
    erzwingen = true, fest = true, fixiert = true, gelb = true, grau = true, gruen = true,
    heilung = true, hoch = true, immer = true, keine = true, keiner = true, klassisch = true,
    klassenfarben = true, kontrolliert = true, leuchten = true, links = true, lila = true,
    maus = true, mauszeiger = true, mitte = true, modernisiert = true, namensfarbe = true,
    neu = true, nie = true, niemals = true, nichts = true, oben = true, panel = true,
    platzierung = true, pulsieren = true, punkt = true, quadrat = true, rand = true,
    rechts = true, rahmen = true, rosa = true, rot = true, runter = true, schwarz = true,
    sichtbar = true, spiel = true, taste = true, tuer = true, tuerkis = true, unten = true,
    umschalt = true, umschalttaste = true, verstecken = true, verlauf = true, violett = true,
    weiss = true,
}

local function IsGermanDisplayAlias(alias)
    local text = Normalize(alias)
    if text == "" then return false end
    if GERMAN_DISPLAY_ALIAS_rOKENS[text] then return true end
    for token in text:gmatch("%S+") do
        if GERMAN_DISPLAY_ALIAS_rOKENS[token] then return true end
    end
    return false
end

local function ValueDisplay(setting, value)
    if value == nil then return "value" end
    if setting and setting.type == "boolean" then return value and "enabled" or "disabled" end
    if setting and setting.type == "color" and type(value) == "table" then
        if type(value.label) == "string" and value.label ~= "" then
            return type(A.DisplayColorLabel) == "function" and A.DisplayColorLabel(value.label) or value.label
        end
        local r = math.floor(((tonumber(value.r or value[1]) or 0) * 255) + 0.5)
        local g = math.floor(((tonumber(value.g or value[2]) or 0) * 255) + 0.5)
        local b = math.floor(((tonumber(value.b or value[3]) or 0) * 255) + 0.5)
        if r < 0 then r = 0 elseif r > 255 then r = 255 end
        if g < 0 then g = 0 elseif g > 255 then g = 255 end
        if b < 0 then b = 0 elseif b > 255 then b = 255 end
        return string.format("#%02X%02X%02X", r, g, b)
    end
    if tostring(value) == "" then return "blank" end
    if tostring(value) == "__CUSTOM__" then return "Custom" end
    if setting and type(setting.displayValues) == "table" then
        local display = setting.displayValues[value]
        if type(display) == "string" and display ~= "" then return display end
    end
    local directEnumDisplay = DirectEnumDisplay(setting, value)
    if directEnumDisplay then return directEnumDisplay end
    if setting and type(setting.valueAliases) == "table" then
        local bestAlias
        local bestLen = 999999
        for alias, aliasValue in pairs(setting.valueAliases) do
            if aliasValue == value and not IsGermanDisplayAlias(alias) then
                local len = #tostring(alias or "")
                if len < bestLen then
                    bestLen = len
                    bestAlias = alias
                end
            end
        end
        if bestAlias and bestAlias ~= "" then return tostring(bestAlias) end
    end
    if setting and (setting.type == "enum" or type(setting.values) == "table") and type(A.HumanizeDisplayKey) == "function" then
        return A.HumanizeDisplayKey(value)
    end
    return tostring(value)
end

local function TooltipModifierValueForText(text)
    if ContainsAny(text, { "shift", "umschalt", "umschalttaste", "shift taste" }) then return "SHIFT" end
    if ContainsAny(text, { "ctrl", "control", "strg", "steuerung", "strg taste" }) then return "CTRL" end
    if ContainsAny(text, { "alt", "option", "alt taste" }) then return "ALT" end
    return nil
end

local function MissingValueResponse(matches, raw)
    if #matches == 0 then return nil end
    local best
    for i = 1, #matches do
        if i % 16 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local item = matches[i]
        if not best
            or (tonumber(item.score) or 0) > (tonumber(best.score) or 0)
            or ((tonumber(item.score) or 0) == (tonumber(best.score) or 0)
                and tostring(item.setting and item.setting.label or "") < tostring(best.setting and best.setting.label or ""))
        then
            best = item
        end
    end
    local setting = best and best.setting
    if not setting then return nil end
    if setting.type == "enum" and type(setting.values) == "table" and #setting.values > 0 and #setting.values <= 12 then
        local choices = {}
        for i = 1, #setting.values do
            local value = setting.values[i]
            choices[#choices + 1] = {
                setting = setting,
                value = value,
                matchScore = best.score,
                valueLabel = ValueDisplay(setting, value),
                label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, ValueDisplay(setting, value), "Option") or (tostring(setting.label or "Option") .. ": " .. ValueDisplay(setting, value)),
            }
        end
        return {
            kind = "ambiguous",
            choices = choices,
            label = "Choose a value for " .. tostring(setting.label or "this option"),
            summary = "Value clarification for an MSUF option.",
        }
    end

    local hint = "Type the value after 'to'."
    if setting.type == "number" then
        local parts = {}
        if setting.min ~= nil then parts[#parts + 1] = "min " .. tostring(setting.min) end
        if setting.max ~= nil then parts[#parts + 1] = "max " .. tostring(setting.max) end
        if setting.step ~= nil then parts[#parts + 1] = "step " .. tostring(setting.step) end
        if #parts > 0 then hint = "Use a number (" .. table.concat(parts, ", ") .. ")." end
    elseif setting.type == "color" then
        hint = "Use a color name, RGB values, or #RRGGBB."
    elseif setting.type == "string" then
        hint = "Type the text after 'to'."
    end

    return {
        kind = "answer",
        status = "ambiguous",
        text = "What value do you want me to use for " .. tostring(setting.label or "this option") .. "? " .. hint,
        summary = "Value clarification for an MSUF option.",
    }
end

local RelativeNumberDeltaForText
local RelativeNumberDeltaAllowedForSetting
local ValueForRegistrySetting

local SUGGESTION_IGNORE_TOKENS = {
    turn = true, change = true, set = true, make = true, use = true, apply = true,
    enable = true, enabled = true, disable = true, disabled = true, show = true, hide = true,
    increase = true, decrease = true, raise = true, lower = true, higher = true, lower = true,
    more = true, less = true, larger = true, smaller = true, bigger = true, wider = true, taller = true, thicker = true, thinner = true,
    on = true, off = true, ["true"] = true, ["false"] = true, yes = true, no = true,
    to = true, as = true, is = true, be = true, value = true, with = true, without = true,
    ["for"] = true, of = true, from = true, into = true, onto = true,
    frame = true, frames = true, unitframe = true, unitframes = true, group = true, groups = true,
    setting = true, settings = true, option = true, options = true, control = true, controls = true,
    command = true, commands = true, help = true, please = true,
    assistant = true, msuf = true, can = true, could = true, would = true, will = true,
    you = true, i = true, im = true, id = true, want = true, wanna = true, need = true,
    like = true, trying = true, just = true, really = true, maybe = true, pls = true,
    all = true, every = true, everyone = true, everything = true, each = true,
    setze = true, stelle = true, aktivieren = true, aktiviert = true, deaktivieren = true, deaktiviert = true,
    einschalten = true, eingeschaltet = true, ausschalten = true, ausgeschaltet = true,
    erhoehe = true, erhoehen = true, hoeher = true, groesser = true, kleiner = true, senke = true, reduziere = true,
    anzeigen = true, einblenden = true, ausblenden = true, verstecken = true, versteckt = true,
    zeige = true, zeigen = true, hilfe = true, befehl = true, befehle = true, bitte = true, mir = true,
    kannst = true, koenntest = true, du = true, ich = true, moechte = true, will = true, brauche = true,
    an = true, aus = true, ja = true, nein = true, auf = true, zu = true, als = true, wert = true,
    fuer = true, fur = true, vom = true, von = true, nach = true, ["in"] = true,
    gruppe = true, gruppen = true, gruppenframes = true,
    alle = true, alles = true, jede = true, jeder = true, jedes = true, jeweils = true,
}

local REGISTRY_CANDIDATE_RARE_TOKEN_LIMIT = 260
local REGISTRY_FUZZY_CANDIDATE_LIST_LIMIT = 520
P.REGISTRY_COLOR_VALUE_TOKENS = P.REGISTRY_COLOR_VALUE_TOKENS or {
    white = true, black = true, red = true, green = true, blue = true, yellow = true,
    cyan = true, magenta = true, orange = true, purple = true, pink = true,
    turquoise = true, grey = true, gray = true, brown = true, gold = true,
    violet = true, weiss = true, schwarz = true, rot = true, gruen = true,
    blau = true, gelb = true, lila = true,
}

function P.IsRegistryCandidateValueToken(token)
    token = tostring(token or "")
    if token == "" then return false end
    if P.REGISTRY_COLOR_VALUE_TOKENS and P.REGISTRY_COLOR_VALUE_TOKENS[token] then return true end
    if token:match("^%x%x%x%x%x%x$") then return true end
    if A and type(A.ColorFromName) == "function" then
        local ok = A.ColorFromName(token)
        if ok then return true end
    end
    return false
end

local function MeaningTokens(text)
    text = tostring(text or "")
    P._meaningTokenCache = P._meaningTokenCache or {}
    P._meaningTokenCacheOrder = P._meaningTokenCacheOrder or {}
    local cached = P._meaningTokenCache[text]
    if cached then return cached.set, cached.list end
    local set = {}
    local list = {}
    local function add(word)
        if #word >= 2 and not word:match("^[-+]?%d") and not SUGGESTION_IGNORE_TOKENS[word] and not set[word] then
            set[word] = true
            list[#list + 1] = word
        end
    end
    for word in Normalize(text):gmatch("%S+") do
        add(word)
        local folded = P.PluralFoldWord and P.PluralFoldWord(word) or word
        if folded ~= word then
            add(folded)
        end
    end
    if text ~= "" and #text <= 320 then
        if not P._meaningTokenCache[text] then
            P._meaningTokenCacheOrder[#P._meaningTokenCacheOrder + 1] = text
        end
        P._meaningTokenCache[text] = { set = set, list = list }
        while #P._meaningTokenCacheOrder > 2048 do
            local oldKey = table.remove(P._meaningTokenCacheOrder, 1)
            P._meaningTokenCache[oldKey] = nil
        end
    end
    return set, list
end

local suggestionScopeAliasTable
local suggestionScopeTokens

local function SuggestionScopeTokenMap()
    local aliases = A.UnitAliases or {}
    if aliases == suggestionScopeAliasTable and suggestionScopeTokens then return suggestionScopeTokens end
    suggestionScopeAliasTable = aliases
    suggestionScopeTokens = {}
    for _, list in pairs(aliases) do
        for i = 1, #(list or {}) do
            for token in Normalize(list[i]):gmatch("%S+") do
                suggestionScopeTokens[token] = true
            end
        end
    end
    return suggestionScopeTokens
end

local function IsSuggestionScopeToken(word)
    word = Normalize(word)
    if word == "" then return false end
    return SuggestionScopeTokenMap()[word] == true
end

local function PartialPhraseScore(requestSet, requestList, phrase)
    if #requestList == 0 then return 0 end
    local phraseSet, phraseList = MeaningTokens(phrase)
    if #phraseList == 0 then return 0 end
    local common = 0
    for i = 1, #requestList do
        if phraseSet[requestList[i]] then common = common + 1 end
    end
    if common ~= #requestList then return 0 end
    if common < 2 and #phraseList > 1 then return 0 end
    local extra = 0
    for i = 1, #phraseList do
        local token = phraseList[i]
        if not requestSet[token] and not IsSuggestionScopeToken(token) then extra = extra + 1 end
    end
    return (common * 100) - extra
end

local function SettingPartialSuggestionScore(setting, text)
    if type(setting) ~= "table" then return 0 end
    if not SettingAllowedByExplicitScopes(setting, text) then return 0 end
    if setting.frameType == "castbar" and setting.attribute == "enabled" and ContainsAny(text, CASTBAR_ROOT_DETAIL_TERMS) then
        return 0
    end
    if setting.frameType == "classPower" and ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) and not ContainsAny(text, CLASS_POWER_TERMS) then
        return 0
    end
    if setting.frameType == "group" or setting.frameType == "groupAura" then
        local wantedGroup
        if HasPhrase(text, "mythicraid") or HasPhrase(text, "mythic raid") then
            wantedGroup = "mythicraid"
        elseif HasPhrase(text, "party") then
            wantedGroup = "party"
        elseif HasPhrase(text, "raid") then
            wantedGroup = "raid"
        end
        if not GroupSettingAllowsWantedGroup(setting, wantedGroup) then return 0 end
    end

    local matchText = ScopeAdjustedTextForSetting(setting, text)
    if not matchText then return 0 end
    local requestSet, requestList = MeaningTokens(AliasRelationText(matchText))
    local best = 0
    local aliases = setting.aliases or {}
    for i = 1, #aliases do
        local score = PartialPhraseScore(requestSet, requestList, aliases[i])
        if score > best then best = score end
    end
    if setting.matchLabel ~= false and setting.label then
        local score = PartialPhraseScore(requestSet, requestList, setting.label)
        if score > best then best = score end
    end
    return best
end

local candidateIndexTokenCache = {}
local candidateIndexTokenCacheCount = 0
local function CandidateIndexTokens(text)
    local raw = tostring(text or "")
    if raw == "" then return nil end
    local cached = candidateIndexTokenCache[raw]
    if cached ~= nil then return cached end
    local tokens = {}
    local seen = {}
    local function add(word)
        if #word >= 2 and not word:match("^[-+]?%d") and not SUGGESTION_IGNORE_TOKENS[word] then
            if not seen[word] then
                seen[word] = true
                tokens[#tokens + 1] = word
            end
        end
    end
    for word in Normalize(raw):gmatch("%S+") do
        add(word)
        local folded = P.PluralFoldWord and P.PluralFoldWord(word) or word
        if folded ~= word then add(folded) end
    end
    if #raw <= 180 then
        if candidateIndexTokenCacheCount > 4096 then
            candidateIndexTokenCache = {}
            candidateIndexTokenCacheCount = 0
        end
        candidateIndexTokenCache[raw] = tokens
        candidateIndexTokenCacheCount = candidateIndexTokenCacheCount + 1
    end
    return tokens
end

P._AddCandidateIndexTokens = function(tokenSet, text)
    if type(tokenSet) ~= "table" then return end
    local tokens = CandidateIndexTokens(text)
    for i = 1, #(tokens or {}) do
        tokenSet[tokens[i]] = true
    end
end

P._BuildRegistryCandidateIndex = function(settings, includeAliases)
    includeAliases = includeAliases == true
    local maybeYield = A and type(A.MaybeYield) == "function" and A.MaybeYield or nil
    local byToken = {}
    local all = {}
    for i = 1, #(settings or {}) do
        if maybeYield and i % 2 == 0 then maybeYield() end
        local setting = settings[i]
        if type(setting) == "table" then
            all[#all + 1] = setting
            local tokenSet = {}
            P._AddCandidateIndexTokens(tokenSet, setting.key)
            P._AddCandidateIndexTokens(tokenSet, setting.label)
            P._AddCandidateIndexTokens(tokenSet, setting.attribute)
            if includeAliases then
                local aliases = setting.aliases
                for j = 1, #(aliases or {}) do
                    if maybeYield and j % 4 == 0 then maybeYield() end
                    P._AddCandidateIndexTokens(tokenSet, aliases[j])
                end
                local prefixes = setting.valuePrefixes
                for j = 1, #(prefixes or {}) do
                    if maybeYield and j % 4 == 0 then maybeYield() end
                    P._AddCandidateIndexTokens(tokenSet, prefixes[j])
                end
            end
            for token in pairs(tokenSet) do
                byToken[token] = byToken[token] or {}
                byToken[token][#byToken[token] + 1] = setting
            end
        end
    end
    local fuzzyBuckets = {}
    for token in pairs(byToken) do
        if type(token) == "string"
            and #token >= 4
            and token:match("^[a-z]+$")
            and not SUGGESTION_IGNORE_TOKENS[token] then
            local first = token:sub(1, 1)
            local len = #token
            fuzzyBuckets[first] = fuzzyBuckets[first] or {}
            fuzzyBuckets[first][len] = fuzzyBuckets[first][len] or {}
            fuzzyBuckets[first][len][#fuzzyBuckets[first][len] + 1] = token
        end
    end
    P._registryCandidateIndexSettings = settings
    P._registryCandidateIndexCount = #(settings or {})
    P._registryCandidateIndexFull = includeAliases
    P._registryCandidateIndexByToken = byToken
    P._registryCandidateIndexFuzzyBuckets = fuzzyBuckets
    P._registryCandidateIndexAll = all
    P._registryCandidateCache = {}
    P._registryCandidateCacheOrder = {}
    P._registryCandidateFuzzyTokenCache = {}
    if P.ClearSettingMatchScoreCache then P.ClearSettingMatchScoreCache() end
end

P._EnsureRegistryCandidateIndex = function(settings, includeAliases)
    includeAliases = includeAliases == true
    if settings ~= P._registryCandidateIndexSettings
        or #(settings or {}) ~= (P._registryCandidateIndexCount or -1)
        or (includeAliases and P._registryCandidateIndexFull ~= true) then
        P._BuildRegistryCandidateIndex(settings, includeAliases)
    end
end

local function RegistryCandidateListForToken(token)
    token = Normalize(token)
    if token == "" then return nil end
    local byToken = P._registryCandidateIndexByToken
    local direct = byToken and byToken[token]
    if direct then return direct end
    if #token < 4 or not token:match("^[a-z]+$") or SUGGESTION_IGNORE_TOKENS[token] then return nil end
    local fuzzyWordMatch = P.FuzzyWordMatch or (A and A.FuzzyWordMatch)
    if type(fuzzyWordMatch) ~= "function" then return nil end

    P._registryCandidateFuzzyTokenCache = P._registryCandidateFuzzyTokenCache or {}
    local cached = P._registryCandidateFuzzyTokenCache[token]
    if cached ~= nil then return cached ~= false and cached or nil end

    local first = token:sub(1, 1)
    local buckets = P._registryCandidateIndexFuzzyBuckets
    local firstBuckets = buckets and buckets[first]
    if type(firstBuckets) ~= "table" then
        P._registryCandidateFuzzyTokenCache[token] = false
        return nil
    end

    local out, seenSettings, seenTokens = {}, {}, {}
    local len = #token
    for delta = -1, 1 do
        local bucket = firstBuckets[len + delta]
        for i = 1, #(bucket or {}) do
            local indexedToken = bucket[i]
            if not seenTokens[indexedToken] and fuzzyWordMatch(token, indexedToken) then
                seenTokens[indexedToken] = true
                local settings = byToken and byToken[indexedToken]
                for j = 1, #(settings or {}) do
                    local setting = settings[j]
                    if setting and not seenSettings[setting] then
                        seenSettings[setting] = true
                        out[#out + 1] = setting
                        if #out > REGISTRY_FUZZY_CANDIDATE_LIST_LIMIT then
                            P._registryCandidateFuzzyTokenCache[token] = false
                            return nil
                        end
                    end
                end
            end
        end
    end

    P._registryCandidateFuzzyTokenCache[token] = #out > 0 and out or false
    return #out > 0 and out or nil
end

P.RegistryCandidateSettings = function(text, settings, includeAliases)
    includeAliases = includeAliases == true
    P._EnsureRegistryCandidateIndex(settings, includeAliases)
    local cacheKey = (includeAliases and "full:" or "light:") .. Normalize(text)
    if type(P._registryCandidateCache) == "table" and P._registryCandidateCache[cacheKey] then
        return P._registryCandidateCache[cacheKey]
    end
    local _, tokens = MeaningTokens(text)
    if #tokens == 0 then return {} end
    local candidateTokens = {}
    local skippedValueToken = false
    for i = 1, #tokens do
        if P.IsRegistryCandidateValueToken(tokens[i]) then
            skippedValueToken = true
        else
            candidateTokens[#candidateTokens + 1] = tokens[i]
        end
    end
    if #candidateTokens == 0 then candidateTokens = tokens end
    local selectedTokens, selectedCount, hasRareToken = {}, 0, false
    for i = 1, #candidateTokens do
        local token = candidateTokens[i]
        local list = RegistryCandidateListForToken(token)
        if type(list) == "table" and #list > 0 and #list <= REGISTRY_CANDIDATE_RARE_TOKEN_LIMIT then
            selectedCount = selectedCount + 1
            selectedTokens[selectedCount] = token
            hasRareToken = true
        end
    end
    if not hasRareToken then
        selectedTokens = candidateTokens
        selectedCount = #candidateTokens
    end
    local out, seen = {}, {}
    if selectedCount >= 2 and (not includeAliases or skippedValueToken) then
        local counts = {}
        local ordered = {}
        for i = 1, selectedCount do
            if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
            local list = RegistryCandidateListForToken(selectedTokens[i])
            for j = 1, #(list or {}) do
                if j % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
                local setting = list[j]
                if setting then
                    if counts[setting] == nil then
                        ordered[#ordered + 1] = setting
                        counts[setting] = 0
                    end
                    counts[setting] = counts[setting] + 1
                end
            end
        end
        for i = 1, #ordered do
            local setting = ordered[i]
            if counts[setting] == selectedCount then
                out[#out + 1] = setting
                seen[setting] = true
            end
        end
    end
    if #out == 0 and skippedValueToken and not includeAliases then return {} end
    if #out == 0 then
        for i = 1, selectedCount do
            if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
            local list = RegistryCandidateListForToken(selectedTokens[i])
            for j = 1, #(list or {}) do
                if j % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
                local setting = list[j]
                if setting and not seen[setting] then
                    seen[setting] = true
                    out[#out + 1] = setting
                end
            end
        end
    end
    if type(P._registryCandidateCache) == "table" then
        if not P._registryCandidateCache[cacheKey] then
            P._registryCandidateCacheOrder[#P._registryCandidateCacheOrder + 1] = cacheKey
        end
        P._registryCandidateCache[cacheKey] = out
        while #P._registryCandidateCacheOrder > 64 do
            local oldKey = table.remove(P._registryCandidateCacheOrder, 1)
            P._registryCandidateCache[oldKey] = nil
        end
    end
    return out
end

local function AddUniqueSuggestion(out, seen, item)
    local setting = item and item.setting
    if not setting then return end
    local id = tostring(setting.key or "") .. "\031" .. tostring(item.value) .. "\031" .. tostring(item.relativeDelta)
    if seen[id] then return end
    seen[id] = true
    out[#out + 1] = item
end

local GROUP_AVAILABILITY_PAGES = { gf_layout = true, gf_bars = true, gf_indicators = true }

local function CurrentGroupScopeForRegistry()
    local scope = M and M.gfScope
    if scope == "party" or scope == "raid" or scope == "mythicraid" then return scope end
    if scope == "mythic" then return "mythicraid" end
    return nil
end

local function GroupAvailabilityScopes(text)
    local groups = {}
    if HasPhrase(text, "party") then groups[#groups + 1] = "party" end
    if HasPhrase(text, "mythicraid") or HasPhrase(text, "mythic raid") then groups[#groups + 1] = "mythicraid" end
    if #groups == 0 and (HasPhrase(text, "raid") or HasPhrase(text, "schlachtzug")) then groups[#groups + 1] = "raid" end
    if #groups > 0 then return groups, true end
    if GROUP_AVAILABILITY_PAGES[M and M.activeKey] then
        local current = CurrentGroupScopeForRegistry()
        if current then return { current }, true end
    end
    return { "party", "raid", "mythicraid" }, false
end

local SHOW_OFF_TERMS = {
    "turn off", "disable", "disabled", "off", "false", "no",
    "hide", "hidden", "not show", "dont show", "do not show", "never show",
    "aus", "deaktivieren", "deaktiviert", "ausschalten", "ausgeschaltet",
    "ausblenden", "verstecken", "nicht anzeigen", "nicht zeigen", "nicht einblenden", "nein",
}

local SHOW_ON_TERMS = {
    "turn on", "enable", "enabled", "on", "true", "yes",
    "show", "display", "visible",
    "an", "aktivieren", "aktiviert", "einschalten", "eingeschaltet",
    "anzeigen", "zeigen", "einblenden", "sichtbar", "ja",
}

local HIDE_OFF_TERMS = {
    "turn off", "disable", "disabled", "off", "false", "no",
    "remove", "clear", "dont hide", "do not hide", "never hide", "always show",
    "show", "display", "visible",
    "aus", "deaktivieren", "deaktiviert", "ausschalten", "ausgeschaltet",
    "entfernen", "loeschen", "nicht verstecken", "nicht ausblenden", "immer anzeigen",
    "anzeigen", "zeigen", "einblenden", "sichtbar", "nein",
}

local HIDE_ON_TERMS = {
    "turn on", "enable", "enabled", "on", "true", "yes",
    "hide", "hidden", "not show", "dont show", "do not show", "never show",
    "not visible",
    "an", "aktivieren", "aktiviert", "einschalten", "eingeschaltet",
    "ausblenden", "verstecken", "nicht anzeigen", "nicht zeigen", "nicht einblenden", "nicht sichtbar", "ja",
}

local function ShowSettingValueForText(text)
    if ContainsAny(text, SHOW_OFF_TERMS) then return false end
    if ContainsAny(text, SHOW_ON_TERMS) then return true end
    return DetectBoolean(text)
end

local function HideSettingValueForText(text, defaultValue)
    if ContainsAny(text, { "not show", "dont show", "do not show", "never show", "nicht anzeigen", "nicht zeigen", "nicht einblenden" }) then return true end
    if ContainsAny(text, HIDE_OFF_TERMS) then return false end
    if ContainsAny(text, HIDE_ON_TERMS) then return true end
    local value = DetectBoolean(text)
    if value ~= nil then return value end
    return defaultValue
end

local UNIT_LOAD_CONDITION_SPECS = {
    { key = "loadCondHideMounted", label = "Hide Mounted", terms = { "mounted", "mount", "on mount", "while mounted", "when mounted", "gemountet", "reittier" } },
    { key = "loadCondHideOutOfCombat", label = "Hide Out of Combat", terms = { "out of combat", "outside combat", "not in combat", "ooc", "while out of combat", "when out of combat", "ausserhalb kampf", "ausser kampf", "nicht im kampf" } },
    { key = "loadCondHideSolo", label = "Hide Solo", terms = { "solo", "alone", "while solo", "when solo", "allein" } },
    { key = "loadCondHideInVehicle", label = "Hide in Vehicle", terms = { "in vehicle", "vehicle", "while in vehicle", "when in vehicle", "fahrzeug" } },
    { key = "loadCondHideInGroup", label = "Hide in Group", terms = { "in group", "while in group", "when in group", "grouped", "in party", "in raid", "in gruppe", "gruppe" } },
    { key = "loadCondHideInInstance", label = "Hide in Instance", terms = { "in instance", "instance", "dungeon", "while in instance", "when in instance", "instanz" } },
    { key = "loadCondHideResting", label = "Hide Resting", terms = { "resting", "rested", "rest area", "while resting", "when resting", "ruhend", "erholt" } },
    { key = "loadCondHideInCombat", label = "Hide in Combat", terms = { "in combat", "combat", "fight", "while in combat", "when in combat", "im kampf", "kampf" } },
    { key = "loadCondHideStealthed", label = "Hide Stealthed", terms = { "stealthed", "stealth", "in stealth", "while stealthed", "when stealthed", "getarnt", "verstohlen" } },
    { key = "loadCondHideInHousing", label = "Hide in Housing", terms = { "housing", "house", "in housing", "while in housing", "when in housing", "player housing", "haus", "spielerhaus" } },
}

local LOAD_CONDITION_TERMS = {
    "load condition", "load conditions", "visibility condition", "visibility rule",
    "show condition", "hide condition", "when to show", "when to hide",
    "ladebedingung", "ladebedingungen", "sichtbarkeitsbedingung",
}

local function LoadConditionSpecForText(text)
    local bestSpec, bestLen
    for i = 1, #UNIT_LOAD_CONDITION_SPECS do
        local spec = UNIT_LOAD_CONDITION_SPECS[i]
        for j = 1, #(spec.terms or {}) do
            local term = spec.terms[j]
            if HasPhrase(text, term) then
                local len = #Compact(term)
                if not bestLen or len > bestLen then
                    bestLen = len
                    bestSpec = spec
                end
            end
        end
    end
    return bestSpec
end

local function HasLoadConditionPhrase(text)
    return ContainsAny(text, LOAD_CONDITION_TERMS)
end

local function HasVisibilityVerb(text)
    return ContainsAny(text, SHOW_OFF_TERMS) or ContainsAny(text, SHOW_ON_TERMS) or ContainsAny(text, HIDE_OFF_TERMS) or ContainsAny(text, HIDE_ON_TERMS)
end

local LOAD_CONDITION_DETAIL_BLOCKERS = {
    "name", "names", "text", "hp text", "health text", "power text", "mana text",
    "castbar", "cast bar", "power bar", "mana bar", "health bar", "status icon",
    "status icons", "status indicator", "status indicators", "indicator", "indicators",
    "icon", "icons", "symbol", "symbols", "portrait", "alpha", "opacity", "range fade",
}

local function HasUnitLoadConditionIntent(text, spec)
    local units, groups = ExplicitScopes(text)
    if #groups > 0 and #units == 0 then return false end
    if HasLoadConditionPhrase(text) then return true end
    if not spec or ContainsAny(text, LOAD_CONDITION_DETAIL_BLOCKERS) then return false end
    if #groups > 0 then
        return spec.key == "loadCondHideInGroup"
            and #units > 0
            and not ContainsAny(text, { "group frame", "group frames", "group when solo", "player in group when solo", "when solo", "while solo" })
            and ContainsAny(text, { "hide in group", "hide while in group", "hide when in group", "group load condition" })
    end
    return #units > 0 and HasVisibilityVerb(text)
end

local function GroupAvailabilityAttributeForText(text)
    if ContainsAny(text, { "tint offline", "tint offline members", "also tint offline members", "dead background offline", "dead background offline members", "dead offline tint" }) then
        return nil
    end
    if (ContainsAny(text, { "offline", "offline member", "offline members", "offline player", "offline players" })
        and ContainsAny(text, { "combat", "in combat" })
        and ContainsAny(text, { "hide", "hidden", "not show", "dont show", "do not show", "never show" }))
        or ContainsAny(text, {
        "offline in combat", "offline members in combat", "offline players in combat",
        "hide offline in combat", "hide offline members in combat", "hide offline players in combat",
        "only hide offline in combat", "only hide offline members in combat", "only hide offline players in combat",
        "combat offline hide", "offline im kampf",
    }) then
        return "hideOfflineInCombat", "hide"
    end
    if ContainsAny(text, { "offline members", "offline member", "offline players", "hide offline members", "offline spieler" }) then
        return "hideOfflineEnabled", "hide"
    end
    if ContainsAny(text, { "client scene", "client scenes", "hide during client scene", "hide in client scene", "client szene" }) then
        return "hideInClientScene", "hide"
    end
    local groupScopesForHousing = DetectGroups(text)
    if #groupScopesForHousing > 0 and ContainsAny(text, { "housing", "house", "in housing", "while in housing", "when in housing", "player housing", "haus", "spielerhaus" }) then
        return "hideInHousing", "hide"
    end
    if ContainsAny(text, {
        "player in group", "player in group frames", "show player in group",
        "show player in group frames", "show player when solo", "show player in group when solo",
        "hide player in group", "hide player in group frames", "player when solo",
        "spieler in gruppe", "spieler anzeigen",
    }) then
        return "showPlayer", "show"
    end
    if ContainsAny(text, {
        "show while solo", "show solo", "solo mode", "show group while solo",
        "show party frames while solo", "show raid frames while solo", "show mythic raid frames while solo",
        "show party frame while solo", "show raid frame while solo", "show mythic raid frame while solo",
        "show party frame when solo", "show raid frame when solo", "show mythic raid frame when solo",
        "show group frame while solo", "show group frame when solo",
        "show group frames while solo", "group while solo", "group frames while solo",
        "group frame while solo", "group frame when solo",
        "hide while solo", "hide solo", "not show while solo", "dont show while solo", "do not show while solo",
        "hide party frames while solo", "hide raid frames while solo", "hide mythic raid frames while solo",
        "hide party frame while solo", "hide raid frame while solo", "hide mythic raid frame while solo",
        "hide party frame when solo", "hide raid frame when solo", "hide mythic raid frame when solo",
        "hide group frame while solo", "hide group frame when solo",
        "solo anzeigen", "solo modus",
    }) then
        return "showSolo", "show"
    end
    if ContainsAny(text, {
        "use msuf group frames", "msuf group frames", "group frames enabled",
        "party frames enabled", "raid frames enabled", "enable group frames",
        "disable group frames", "turn on group frames", "turn off group frames",
    }) and not ContainsAny(text, { "preview", "power bar", "name", "text", "status icon", "indicator" }) then
        return "enabled", "show"
    end
    return nil
end

local function GroupAvailabilityUnsupportedAnswer(text)
    local groups = DetectGroups(text)
    if #groups == 0 then return nil end
    if not HasLoadConditionPhrase(text) and not LoadConditionSpecForText(text) then return nil end
    return {
        kind = "answer",
        status = "info",
        text = "That Group Frame situation has no load-condition toggle yet. I can still help with these visibility options: MSUF group frames, Show player, Show while solo, Hide during client scene, Offline Members, and Hide offline in combat.",
        summary = "Shows which Group Frame visibility options I can help with.",
    }
end

local function ParseGroupAvailabilityIntent(text)
    local attr, semantic = GroupAvailabilityAttributeForText(text)
    if not attr then return GroupAvailabilityUnsupportedAnswer(text) end

    local value
    if semantic == "hide" then
        value = HideSettingValueForText(text, true)
    else
        value = ShowSettingValueForText(text)
    end
    if value == nil then return nil end

    local scopes, concrete = GroupAvailabilityScopes(text)
    local changes = {}
    for i = 1, #scopes do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scopes[i]) .. "." .. attr)
        if setting then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
                valueLabel = ValueDisplay(setting, value),
                label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, ValueDisplay(setting, value), "Group option") or (tostring(setting.label or "Group option") .. ": " .. ValueDisplay(setting, value)),
            }
        end
    end
    if #changes == 0 then return nil end
    if concrete and #changes == 1 then
        return {
            kind = "changes",
            changes = changes,
            label = changes[1].setting and changes[1].setting.label or "Group availability",
            summary = "Changes group-frame visibility.",
        }
    end
    return {
        kind = "ambiguous",
        choices = changes,
        label = "Which group-frame target?",
        summary = "The request matched a real group-frame availability option but did not name Party, Raid, or Mythic Raid.",
    }
end

local function RegistrySuggestions(text, raw, settings)
    local boolValue = DetectBoolean(text)
    local choices = {}
    local seen = {}
    local bestScore = 0
    for i = 1, #(settings or {}) do
        local setting = settings[i]
        local score = SettingPartialSuggestionScore(setting, text)
        if score > 0 then
            local relativeDelta = setting.type == "number" and RelativeNumberDeltaForText(setting, text) or nil
            if not RelativeNumberDeltaAllowedForSetting(setting, text, relativeDelta) then relativeDelta = nil end
            local value
            if setting.type == "boolean" and boolValue ~= nil then
                value = boolValue
            elseif relativeDelta == nil then
                value = ValueForRegistrySetting(setting, text, raw)
            end
            if value ~= nil or relativeDelta ~= nil then
                if score > bestScore then bestScore = score end
                AddUniqueSuggestion(choices, seen, {
                    setting = setting,
                    value = value,
                    relativeDelta = relativeDelta,
                    matchScore = score,
                    valueLabel = ValueDisplay(setting, value),
                    label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, ValueDisplay(setting, value), "Option") or (tostring(setting.label or "Option") .. ": " .. ValueDisplay(setting, value)),
                })
            end
        end
    end
    if #choices == 0 then return nil end
    local filtered = {}
    for i = 1, #choices do
        if choices[i].matchScore == bestScore then filtered[#filtered + 1] = choices[i] end
    end
    if ShouldApplyMultipleRegistryChanges(text, filtered) then
        return {
            kind = "changes",
            changes = filtered,
            bulkSafe = P.AreBulkSafeAuraSettingChanges and P.AreBulkSafeAuraSettingChanges(filtered) or nil,
            label = "Multiple matching options",
            summary = "Changes multiple matched options.",
        }
    end
    if #filtered == 1 then
        local setting = filtered[1].setting
        return {
            kind = "changes",
            changes = filtered,
            label = setting and setting.label or "Assistant option change",
            summary = "Changes the best matching MSUF option.",
        }
    end
    table.sort(filtered, function(a, b)
        return tostring(a.label or "") < tostring(b.label or "")
    end)
    while #filtered > 6 do table.remove(filtered) end
    return {
        kind = "ambiguous",
        choices = filtered,
        label = "Suggested MSUF option",
        summary = "Suggests matching options.",
    }
end

local RELATIVE_INCREASE_TERMS = {
    "increase", "raise", "bump up", "more", "higher", "larger", "bigger", "wider", "taller", "thicker", "grow", "add",
    "erhoehe", "erhoehen", "hoeher", "groesser", "mehr", "breiter", "dicker",
}
local RELATIVE_DECREASE_TERMS = {
    "decrease", "reduce", "lower", "less", "smaller", "narrower", "shorter", "thinner", "shrink", "subtract", "down",
    "verringere", "reduziere", "tiefer", "niedriger", "kleiner", "weniger", "schmaler", "duenner", "runter",
}

P.DIRECTIONAL_MOVE_TERMS = {
    "move", "nudge", "shift", "position", "offset", "left", "right", "up", "down",
    "links", "rechts", "hoch", "runter", "oben", "unten", "verschiebe", "verschieben", "versatz",
}

P.AxisForRegistryDirection = function(direction)
    if direction == "left" or direction == "right" then return "x" end
    if direction == "up" or direction == "down" then return "y" end
    return nil
end

P.DirectionalNumberDeltaForSetting = function(setting, text, fallbackAmount)
    if type(setting) ~= "table" or not setting.moveAxis then return nil end
    if not ContainsAny(text, P.DIRECTIONAL_MOVE_TERMS) then return nil end
    local direction = DetectDirection and DetectDirection(text, {}) or nil
    local axis = P.AxisForRegistryDirection(direction)
    if not axis or axis ~= tostring(setting.moveAxis) then return nil end
    local amount = A._RelativeNumberAmountForText(text)
    if amount == nil then
        amount = fallbackAmount
            or tonumber(setting.moveStep)
            or tonumber(setting.moveAmount)
            or tonumber(setting.step)
            or 1
    end
    if setting.percent == true and amount > 1 then amount = amount / 100 end
    if direction == "left" or direction == "down" then amount = -amount end
    return amount
end

RelativeNumberDeltaForText = function(setting, text, fallbackAmount)
    local directional = P.DirectionalNumberDeltaForSetting(setting, text, fallbackAmount)
    if directional ~= nil then return directional end
    local sign
    if ContainsAny(text, RELATIVE_INCREASE_TERMS) then sign = 1 end
    if ContainsAny(text, RELATIVE_DECREASE_TERMS) then sign = -1 end
    if not sign then return nil end
    local amount = A._RelativeNumberAmountForText(text)
    if amount == nil then
        amount = fallbackAmount
            or (setting and tonumber(setting.relativeStep))
            or (setting and tonumber(setting.step))
            or 1
    end
    if setting and setting.percent == true and amount > 1 then amount = amount / 100 end
    return amount * sign
end

RelativeNumberDeltaAllowedForSetting = function(setting, text, relativeDelta)
    if relativeDelta == nil then return true end
    if not HasAuraSettingIntent(text) then return true end
    if not ContainsAny(text, { "bigger", "larger", "smaller", "shrink", "groesser", "kleiner" }) then return true end
    if P.HasVagueAuraIconSizeIntent(text) then return P.IsAuraIconSizeSetting(setting) end
    if ContainsAny(text, {
        "size", "icon size", "text size", "font size", "spacing", "gap", "offset", "x offset", "y offset",
        "x ", " y ", "layer", "per row", "icons per row", "max", "count", "stack", "cooldown", "timer",
    }) then
        return true
    end
    local hay = (tostring(setting and setting.key or "") .. " " .. tostring(setting and setting.label or "") .. " " .. tostring(setting and setting.attribute or "")):lower()
    return hay:find("size", 1, true) ~= nil or hay:find("iconsize", 1, true) ~= nil or hay:find("icon size", 1, true) ~= nil
end

local function NumberSettingSupportsBooleanToggle(setting)
    if type(setting) ~= "table" then return false end
    if setting.booleanOnValue ~= nil or setting.booleanOffValue ~= nil or type(setting.booleanAliases) == "table" then return true end
    local hay = (tostring(setting.key or "") .. " " .. tostring(setting.label or "") .. " " .. tostring(setting.attribute or "")):lower()
    return hay:find("outline", 1, true) ~= nil
        or hay:find("border", 1, true) ~= nil
        or hay:find("thickness", 1, true) ~= nil
end

local function BooleanValueForNumberSetting(setting, text)
    if not NumberSettingSupportsBooleanToggle(setting) then return nil end
    local hasBooleanCue = ContainsAny(text, { "on", "off", "enable", "disable", "show", "hide", "remove", "without", "no ", "with ", "an", "aus", "aktivieren", "deaktivieren" })
    if not hasBooleanCue then return nil end
    local aliasValue = P.BooleanAliasValueForText and P.BooleanAliasValueForText(setting, text)
    if aliasValue ~= nil then return aliasValue end
    local bool = DetectBoolean(text)
    if bool == nil then return nil end
    if bool == false then
        local offValue = tonumber(setting.booleanOffValue)
        if offValue ~= nil then return offValue end
        local minValue = tonumber(setting.min)
        if minValue ~= nil then return minValue end
        return 0
    end
    local onValue = tonumber(setting.booleanOnValue)
    if onValue ~= nil then return onValue end
    local step = tonumber(setting.step) or 1
    local minValue = tonumber(setting.min)
    local maxValue = tonumber(setting.max)
    local value = step
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function ContextualBooleanValueForRegistrySetting(setting, text)
    if type(setting) ~= "table" then return nil end
    if ContainsAny(text, { "what", "where", "why", "help", "explain", "how" }) then return nil end

    local hay = (tostring(setting.key or "") .. " " .. tostring(setting.label or "") .. " " .. tostring(setting.attribute or "")):lower()
    local customSetting = hay:find("custom", 1, true) ~= nil or hay:find("override", 1, true) ~= nil
    local sharedSetting = hay:find("useshared", 1, true) ~= nil
        or hay:find("use shared", 1, true) ~= nil
        or hay:find("shared", 1, true) ~= nil
        or hay:find("inherit", 1, true) ~= nil

    local customIntent = ContainsAny(text, {
        "use custom", "custom aura", "custom style", "custom filters", "custom rules",
        "custom layout", "custom caps", "override", "own aura", "own filters",
    })
    local sharedIntent = ContainsAny(text, {
        "use shared", "shared aura", "shared style", "shared filters", "shared rules",
        "inherit", "inherited", "follow shared", "use defaults", "default aura",
    })

    if customSetting and customIntent then return true end
    if customSetting and sharedIntent then return false end
    if sharedSetting and sharedIntent then return true end
    if sharedSetting and customIntent then return false end
    return nil
end

local function ToggleBooleanValueForRegistrySetting(setting, text)
    if type(setting) ~= "table" or setting.type ~= "boolean" then return nil end
    if not ContainsAny(text, { "toggle", "switch", "flip", "invert", "umschalten", "wechseln" }) then return nil end
    if type(setting.get) ~= "function" then return nil end
    local ok, current = pcall(setting.get)
    if not ok or type(current) ~= "boolean" then return nil end
    return not current
end

ValueForRegistrySetting = function(setting, text, raw)
    if not setting then return nil end
    if setting.type == "boolean" then
        local attr = tostring(setting.attribute or ""):lower()
        local key = tostring(setting.key or ""):lower()
        if attr == "powerbardetached" or key:find("%.powerbardetached", 1, true) then
            if ContainsAny(text, { "attach", "attached", "reattach", "dock", "docked", "anchor to frame", "back to frame", "into frame", "ankoppeln" }) then return false end
            if ContainsAny(text, { "detach", "detached", "undock", "undocked", "separate", "separated", "abkoppeln" }) then return true end
        end
        if key == "general.hardkillblizzardplayerframe" then
            if ContainsAny(text, { "turn off", "disable", "disabled", "off", "false", "no" }) then return false end
            if ContainsAny(text, { "fully hide", "hard hide", "hard kill", "enable", "enabled", "turn on", "on", "true", "yes" }) then return true end
            return DetectBoolean(text)
        end
        if key == "general.hideadvancedmenu" then
            if ContainsAny(text, { "hide", "hidden", "disable", "disabled", "turn off", "off", "false", "no" }) then return false end
            if ContainsAny(text, { "show", "visible", "enable", "enabled", "turn on", "on", "true", "yes" }) then return true end
            return DetectBoolean(text)
        end
        if attr:find("^hide") or key:find("hide") then
            if ContainsAny(text, { "turn off", "disable", "disabled", "off", "false", "no", "dont hide", "do not hide", "never hide", "always show", "show" }) then return false end
            if ContainsAny(text, { "hide", "enable", "enabled", "turn on", "on", "true", "yes" }) then return true end
        end
        local aliasValue = P.BooleanAliasValueForText and P.BooleanAliasValueForText(setting, text)
        if aliasValue ~= nil then return aliasValue end
        local contextualValue = ContextualBooleanValueForRegistrySetting(setting, text)
        if contextualValue ~= nil then return contextualValue end
        local toggleValue = ToggleBooleanValueForRegistrySetting(setting, text)
        if toggleValue ~= nil then return toggleValue end
        return DetectBoolean(text)
    end
    if setting.type == "number" then
        local boolValue = BooleanValueForNumberSetting(setting, text)
        if boolValue ~= nil then return boolValue end
        local value = A._NumberValueForText(setting, text)
        if value and setting.percent == true and value > 1 then value = value / 100 end
        return value
    end
    if setting.type == "enum" then return EnumValueForText(setting, text) end
    if setting.type == "string" then return StringValueForText(setting, text, raw) end
    if setting.type == "color" then
        local r, g, b, label = ExtractColor(raw, text)
        if r then return { r = r, g = g, b = b, label = label } end
    end
    return nil
end

local function AddMediaResolverChanges(changes, setting, text, raw, score)
    local resolver = A.MediaResolver
    if not (resolver and type(resolver.ResolveSetting) == "function") then return false end
    local media = resolver.ResolveSetting(setting, text, raw)
    if not media then return false end
    if media.status == "exact" and media.value ~= nil then
        changes[#changes + 1] = {
            setting = setting,
            value = media.value,
            matchScore = score,
            valueLabel = media.label or media.value,
            label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, media.label or media.value, "Option") or (tostring(setting.label or "Option") .. ": " .. tostring(media.label or media.value)),
            mediaType = media.mediaType,
        }
        return true
    end
    if media.status == "choices" and type(media.choices) == "table" and #media.choices > 0 then
        for i = 1, #media.choices do
            local item = media.choices[i]
            changes[#changes + 1] = {
                setting = setting,
                value = item.value,
                matchScore = score,
                valueLabel = item.label or item.value,
                label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, item.label or item.value, "Option") or (tostring(setting.label or "Option") .. ": " .. tostring(item.label or item.value)),
                mediaType = media.mediaType,
            }
        end
        return true
    end
    if media.status == "none" then
        changes[#changes + 1] = {
            setting = setting,
            value = nil,
            matchScore = score,
            mediaNoMatch = true,
            mediaType = media.mediaType,
            mediaQuery = media.query,
        }
        return true
    end
    return false
end

local POWER_UNIT_ORDER = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
local POWER_GROUP_ORDER = { "party", "raid", "mythicraid" }
local CASTBAR_INTERRUPT_UNITS = { "player", "target", "focus", "boss" }

P._AddFontTextColorChange = function(changes, key, value)
    local setting = Registry and Registry:GetSetting(key)
    if setting then changes[#changes + 1] = { setting = setting, value = value } end
end

P._ParseAllTextWhiteShortcut = function(text)
    if not ContainsAny(text, { "white", "weiss" }) then return nil end
    if not ContainsAny(text, {
        "everything", "all text", "all texts", "all font", "all fonts", "all names",
        "all unitframe text", "all unit frame text", "all msuf text", "make everything",
        "color everything", "colour everything", "text white", "font white",
    }) then return nil end
    if ContainsAny(text, {
        "bar", "bars", "castbar", "cast bar", "border", "outline", "background",
        "aura", "auras", "buff", "debuff", "class resource", "class resources",
        "class power", "resource bar",
    }) then return nil end

    local changes = {}
    P._AddFontTextColorChange(changes, "general.fontColor", "white")
    P._AddFontTextColorChange(changes, "general.customFontColor", { r = 1, g = 1, b = 1 })
    P._AddFontTextColorChange(changes, "fontScope.shared.nameColorMode", "DEFAULT")
    P._AddFontTextColorChange(changes, "fontScope.shared.npcNameRed", "DEFAULT")
    P._AddFontTextColorChange(changes, "fontScope.shared.colorHealthTextByHealth", "DEFAULT")
    P._AddFontTextColorChange(changes, "fontScope.shared.colorPowerTextByType", "DEFAULT")
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Text color white",
        bulkSafe = true,
        summary = "Sets text color to white and resets automatic text color modes.",
    }
end

P._FontTextColorDefaultIntent = function(text, spec)
    local boolValue = DetectBoolean(text)
    if boolValue == false or ContainsAny(text, { "default", "font color", "palette", "standard" }) then return true end
    if not spec then return false end
    if spec.key == "nameColorMode" then
        return ContainsAny(text, {
            "not by class", "not class color", "not class colored", "not colored by class",
            "without class color", "without class", "no class color", "no class colours",
            "dont color name by class", "do not color name by class",
            "dont use class color", "do not use class color", "disable class color names",
            "turn off class color names", "turn off name class color",
        })
    end
    if spec.key == "colorHealthTextByHealth" then
        return ContainsAny(text, {
            "not by health", "not health color", "without health color", "no health color",
            "dont color by health", "do not color by health", "disable health color",
        })
    end
    if spec.key == "colorPowerTextByType" then
        return ContainsAny(text, {
            "not by power", "not by resource", "not power color", "not resource color",
            "without power color", "without resource color", "no power color", "no resource color",
            "dont color by power", "do not color by power", "disable power color",
        })
    end
    if spec.key == "npcNameRed" then
        return ContainsAny(text, {
            "not red", "not npc red", "without npc red", "without red", "no npc red",
            "dont make npc red", "do not make npc red",
            "no npc color", "no npc name color", "without npc color", "disable npc color",
            "turn off npc color", "no npc class color", "disable npc class color",
        })
    end
    return false
end

local function ParseScopedFontTextColorShortcut(text)
    local allWhite = P._ParseAllTextWhiteShortcut(text)
    if allWhite then return allWhite end

    local scope = DetectGlobalScope(text)
    if ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end

    local spec
    if ContainsAny(text, {
        "color text by power", "text color by power", "color text by resource", "text color by resource",
        "color text by mana", "text color by mana", "color power text", "power color text",
        "mana color text", "resource color text", "power text color", "mana text color",
        "resource text color", "power text by type", "power text by power",
    }) or (
        ContainsAny(text, {
            "power text", "mana text", "resource text", "power value", "mana value", "resource value",
        }) and ContainsAny(text, {
            "power color", "power colour", "power colors", "power colours",
            "resource color", "resource colour", "mana color", "mana colour",
            "font color",
        })
    ) then
        spec = { key = "colorPowerTextByType", on = "RESOURCE", label = "Power Text Color Mode" }
    elseif ContainsAny(text, {
        "color text by health", "text color by health", "color health text", "health color text",
        "hp color text", "health text color", "hp text color", "health text by health",
    }) then
        spec = { key = "colorHealthTextByHealth", on = "HEALTH", label = "Health Text Color Mode" }
    elseif ContainsAny(text, {
        "name text color", "name color", "color name by class", "color name text by class",
        "color name not by class", "name text by class", "name text not by class",
        "name not by class", "names not by class", "unit name not by class",
        "class color name text", "class colored name text", "not class color name",
    }) then
        spec = { key = "nameColorMode", on = "CLASS", label = "Name Text Color Mode" }
    elseif ContainsAny(text, {
        "npc name color", "npc text color", "npc name red", "npc red name",
        "npc name class color", "npc class color name", "color npc name by class",
        "npc name by class", "npc class colored name",
    }) then
        local npcClass = ContainsAny(text, {
            "class color", "class colour", "by class", "class colored", "class coloured",
        })
        spec = {
            key = "npcNameRed",
            on = npcClass and "CLASS" or "NPC",
            label = "NPC Name Text Color",
        }
    end
    if not spec then return nil end
    scope = scope or "shared"
    if scope == "gf_mythicraid" then scope = "gf_raid" end
    if (scope == "gf_party" or scope == "gf_raid") and spec.key ~= "nameColorMode" then return nil end

    local setting = Registry and Registry:GetSetting("fontScope." .. tostring(scope) .. "." .. spec.key)
    if not setting then return nil end
    local value
    if P._FontTextColorDefaultIntent(text, spec) then
        value = "DEFAULT"
    else
        value = spec.on
    end

    local changes = {}
    local override = Registry and Registry:GetSetting("fontScope." .. tostring(scope) .. ".override")
    if ContainsAny(text, { "only", "nur", "just" }) and override then
        changes[#changes + 1] = { setting = override, value = true }
    end
    changes[#changes + 1] = { setting = setting, value = value }
    if scope ~= "shared" and spec.key == "colorPowerTextByType" and override and #changes == 1 then
        changes[#changes + 1] = { setting = override, value = true }
    end
    return {
        kind = "changes",
        changes = changes,
        label = spec.label,
        summary = "Changes the target-specific Font text color mode.",
    }
end

local function CurrentRegistryPageUnit()
    local page = M and M.activeKey
    if type(page) ~= "string" then return nil end
    for i = 1, #ALL_UNITFRAMES do
        local unit = ALL_UNITFRAMES[i]
        if UnitPageKey(unit) == page then return unit end
    end
    return nil
end

local function AddRegisteredChange(out, key, value, relativeDelta, direction)
    local setting = Registry and Registry:GetSetting(key)
    if not setting then return end
    out[#out + 1] = {
        setting = setting,
        value = value,
        relativeDelta = relativeDelta,
        direction = direction,
        valueLabel = ValueDisplay(setting, value),
    }
end

local DEPENDENT_TARGET_FRAME_VISIBILITY_SPECS = {
    { unit = "targettarget", label = "Target of Target", terms = { "target of target", "targettarget", "target target", "targets target", "tot" } },
    { unit = "focustarget", label = "Focus Target", terms = { "focus target", "focustarget" } },
}

local DEPENDENT_TARGET_FRAME_DETAIL_BLOCKERS = {
    "name", "names", "text", "inline", "inside target", "on target frame", "in target frame",
    "hp", "health", "power", "mana", "castbar", "cast bar", "buff", "buffs", "debuff", "debuffs",
    "aura", "auras", "icon", "icons", "indicator", "indicators", "portrait", "range fade",
    "alpha", "opacity", "width", "height", "size", "anchor", "position", "move", "offset",
    "load condition", "load conditions", "visibility condition", "when", "while", "in group",
    "grouped", "solo", "mounted", "vehicle", "instance", "combat", "resting", "stealth", "housing",
}

local function DependentTargetFrameVisibilitySpec(text)
    for i = 1, #DEPENDENT_TARGET_FRAME_VISIBILITY_SPECS do
        local spec = DEPENDENT_TARGET_FRAME_VISIBILITY_SPECS[i]
        if ContainsAny(text, spec.terms) then return spec end
    end
    return nil
end

P.ParseDependentTargetFrameVisibilityShortcut = function(text)
    if ContainsAny(text, DEPENDENT_TARGET_FRAME_DETAIL_BLOCKERS) then return nil end
    local spec = DependentTargetFrameVisibilitySpec(text)
    if not spec then return nil end
    local value = ShowSettingValueForText(text)
    if value == nil then return nil end
    local changes = {}
    AddRegisteredChange(changes, tostring(spec.unit) .. ".enabled", value)
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = tostring(spec.label) .. " Frame Enabled",
        summary = "Changes the " .. tostring(spec.label) .. " frame visibility toggle.",
    }
end

function P.HasInterruptReadyIntent(text)
    if ContainsAny(text, {
        "interrupt ready", "kick ready", "ready interrupt", "ready kick",
        "interrupt bereit", "kick bereit", "unterbrechung bereit", "unterbrechen bereit",
    }) then return true end
    return ContainsAny(text, { "interrupt", "kick", "unterbrechen", "unterbrechung" })
        and ContainsAny(text, {
            "ready indicator", "ready icon", "ready border", "ready box",
            "bereit anzeige", "bereit symbol", "bereit rand", "bereit box",
        })
end

function P.ParseInterruptReadyRegistryShortcut(text, raw)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if ContainsAny(text, { "color", "colors", "colour", "colours", "farbe", "farben", "tint" }) then return nil end
    if not P.HasInterruptReadyIntent(text) then return nil end

    local key
    local relativeDelta
    local direction = DetectDirection(text, {})
    if ContainsAny(text, { "auto size", "autosize", "automatic size", "automatic sizing", "auto-size", "automatische groesse", "automatisch groesse" }) then
        key = "general.kickReadyAutoSize"
    elseif ContainsAny(text, { "style", "border", "box", "fill", "outline", "square", "unavailable fill", "castbar fill", "stil", "rand", "kasten", "quadrat" }) then
        key = "general.kickReadyStyle"
    elseif ContainsAny(text, { "anchor", "anchor point", "anchor position", "position dropdown", "put", "place", "position", "anker", "ankerpunkt", "platzieren" })
        and direction
        and not ContainsAny(text, { "move", "nudge", "shift", "offset", "x offset", "y offset", "verschiebe", "verschieben", "versatz" })
    then
        key = "general.kickReadyAnchor"
    elseif ContainsAny(text, { "x offset", "horizontal offset", "offset x", "move left", "move right", "nudge left", "nudge right", "left by", "right by", "x versatz", "horizontaler versatz", "nach links", "nach rechts", "links um", "rechts um" }) then
        key = "general.kickReadyOffsetX"
    elseif ContainsAny(text, { "y offset", "vertical offset", "offset y", "move up", "move down", "nudge up", "nudge down", "up by", "down by", "y versatz", "vertikaler versatz", "nach oben", "nach unten", "hoch um", "runter um" }) then
        key = "general.kickReadyOffsetY"
    elseif ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "verschieben" }) and (direction == "left" or direction == "right") then
        key = "general.kickReadyOffsetX"
    elseif ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "verschieben" }) and (direction == "up" or direction == "down") then
        key = "general.kickReadyOffsetY"
    elseif ContainsAny(text, { "size", "scale", "groesse", "grosse", "bigger", "larger", "smaller", "grow", "shrink", "icon bigger", "icon smaller", "groesser", "kleiner", "symbol groesser", "symbol kleiner" }) then
        key = "general.kickReadySize"
    elseif ContainsAny(text, { "target", "target castbar", "target cast bar", "ziel", "ziel castbar", "ziel zauberleiste" }) then
        key = "general.kickReadyShowTarget"
    elseif ContainsAny(text, { "focus", "focus castbar", "focus cast bar", "fokus", "fokus castbar", "fokus zauberleiste" }) then
        key = "general.kickReadyShowFocus"
    elseif ContainsAny(text, { "boss", "bosses", "boss castbar", "boss castbars", "boss cast bar", "boss cast bars", "boss zauberleiste", "boss zauberleisten" }) then
        key = "general.kickReadyShowBoss"
    end
    if not key then return nil end

    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    local value
    if setting.type == "number" then
        relativeDelta = RelativeNumberDeltaForText(setting, text)
        if relativeDelta == nil and direction then
            local amount = FirstNumber(text) or 3
            if direction == "left" or direction == "down" then amount = -amount end
            relativeDelta = amount
        end
        if relativeDelta == nil then value = A._NumberValueForText(setting, text) end
    else
        if setting.type == "enum" and key == "general.kickReadyAnchor" and direction then
            value = direction == "left" and "LEFT"
                or direction == "right" and "RIGHT"
                or direction == "up" and "TOP"
                or direction == "down" and "BOTTOM"
                or nil
        end
        if value == nil then value = ValueForRegistrySetting(setting, text, raw) end
        if value == nil and setting.type == "boolean" then
            if ContainsAny(text, { "show", "enable", "enabled", "turn on", "on", "true", "yes", "anzeigen", "einblenden", "aktivieren", "an" }) then value = true end
            if ContainsAny(text, { "hide", "disable", "disabled", "turn off", "off", "false", "no", "ausblenden", "deaktivieren", "aus" }) then value = false end
        end
    end
    if value == nil and relativeDelta == nil then return nil end

    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta, valueLabel = value ~= nil and ValueDisplay(setting, value) or nil } },
        label = setting.label or "Interrupt Ready option",
        summary = "Changes the Cast Bar Interrupt Ready option.",
    }
end

function P.ParseFocusKickRegistryShortcut(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(text, {
        "focus kick", "focus interrupt tracker", "focus interrupt icon", "focus kick tracker", "focus kick icon",
        "fokus kick", "fokus interrupt tracker", "fokus interrupt symbol", "fokus kick tracker", "fokus kick symbol",
        "fokus kick anzeige", "fokus interrupt anzeige",
    }) then return nil end
    if ContainsAny(text, { "reset", "restore", "default", "defaults", "zuruecksetzen", "zurucksetzen", "standard" }) then return nil end

    local changes = {}
    local direction = DetectDirection(text, {})
    if ContainsAny(text, { "move", "nudge", "shift", "offset", "position", "x", "y", "horizontal", "vertical", "verschiebe", "verschieben", "versatz", "platzierung" }) and direction then
        local key = (direction == "left" or direction == "right") and "general.focusKickIconOffsetX" or "general.focusKickIconOffsetY"
        local amount = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then amount = -amount end
        AddRegisteredChange(changes, key, nil, amount, direction)
    elseif ContainsAny(text, { "x offset", "offset x", "horizontal", "x versatz", "horizontaler versatz" }) then
        AddRegisteredChange(changes, "general.focusKickIconOffsetX", FirstNumber(text))
    elseif ContainsAny(text, { "y offset", "offset y", "vertical", "y versatz", "vertikaler versatz" }) then
        AddRegisteredChange(changes, "general.focusKickIconOffsetY", FirstNumber(text))
    elseif ContainsAny(text, { "text size", "font size", "text bigger", "text smaller", "textgroesse", "schriftgroesse", "text groesser", "text kleiner", "schrift groesser", "schrift kleiner" }) then
        local setting = Registry and Registry:GetSetting("general.focusKickTextSize")
        local relativeDelta = setting and RelativeNumberDeltaForText(setting, text) or nil
        local value = relativeDelta == nil and FirstNumber(text) or nil
        AddRegisteredChange(changes, "general.focusKickTextSize", value, relativeDelta)
    elseif ContainsAny(text, { "size", "scale", "bigger", "larger", "smaller", "grow", "shrink", "width", "height", "groesse", "grosse", "groesser", "kleiner", "breite", "hoehe" }) then
        local width = Registry and Registry:GetSetting("general.focusKickIconWidth")
        local height = Registry and Registry:GetSetting("general.focusKickIconHeight")
        local relativeWidth = width and RelativeNumberDeltaForText(width, text) or nil
        local relativeHeight = height and RelativeNumberDeltaForText(height, text) or nil
        local value = (relativeWidth == nil and relativeHeight == nil) and FirstNumber(text) or nil
        if ContainsAny(text, { "width", "wide", "wider", "narrower", "breite", "breiter", "schmaler" }) and not ContainsAny(text, { "height", "tall", "taller", "shorter", "hoehe", "hoeher", "niedriger" }) then
            AddRegisteredChange(changes, "general.focusKickIconWidth", value, relativeWidth)
        elseif ContainsAny(text, { "height", "tall", "taller", "shorter", "hoehe", "hoeher", "niedriger" }) and not ContainsAny(text, { "width", "wide", "wider", "narrower", "breite", "breiter", "schmaler" }) then
            AddRegisteredChange(changes, "general.focusKickIconHeight", value, relativeHeight)
        else
            AddRegisteredChange(changes, "general.focusKickIconWidth", value, relativeWidth)
            AddRegisteredChange(changes, "general.focusKickIconHeight", value, relativeHeight)
        end
    else
        local value = DetectBoolean(text)
        if value == nil and ContainsAny(text, { "show", "enable", "turn on", "on", "anzeigen", "einblenden", "aktivieren", "an" }) then value = true end
        if value == nil and ContainsAny(text, { "hide", "disable", "turn off", "off", "ausblenden", "deaktivieren", "aus" }) then value = false end
        if value ~= nil then AddRegisteredChange(changes, "general.enableFocusKickIcon", value) end
    end

    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Focus Kick Tracker",
        bulkSafe = #changes > 1,
        summary = "Changes Focus Kick tracker options.",
    }
end

P.UNIT_STATUS_SYMBOL_SPECS = {
    {
        attr = "combatStateIndicatorSymbol",
        label = "Combat Indicator Symbol",
        terms = { "combat indicator", "combat state indicator", "combat status indicator", "combat icon", "combat state icon", "combat symbol", "combat state symbol" },
    },
    {
        attr = "restedStateIndicatorSymbol",
        label = "Rested Indicator Symbol",
        terms = { "rested indicator", "resting indicator", "rested icon", "resting icon", "rested symbol", "resting symbol" },
    },
    {
        attr = "incomingResIndicatorSymbol",
        label = "Incoming Rez Indicator Symbol",
        terms = { "incoming rez indicator", "incoming resurrection indicator", "incoming rez icon", "incoming resurrection icon", "incoming rez symbol", "incoming resurrection symbol", "rez indicator", "rez icon", "rez symbol", "resurrection indicator", "resurrection icon", "resurrection symbol" },
    },
}

function P.UnitStatusSymbolSpecForText(text)
    if not ContainsAny(text, { "symbol", "icon" }) then return nil end
    if ContainsAny(text, { "icon pack", "icon style", "midnight style", "classic style" }) then return nil end
    for i = 1, #(P.UNIT_STATUS_SYMBOL_SPECS or {}) do
        local spec = P.UNIT_STATUS_SYMBOL_SPECS[i]
        if ContainsAny(text, spec.terms) then return spec end
    end
    return nil
end

function P.ParseUnitStatusSymbolRegistryShortcut(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    local spec = P.UnitStatusSymbolSpecForText(text)
    if not spec then return nil end

    local units = {}
    if HasAllScopeIntent(text) then
        for i = 1, #ALL_UNITFRAMES do units[#units + 1] = ALL_UNITFRAMES[i] end
    else
        local explicitUnits = ExplicitScopes(text)
        for i = 1, #explicitUnits do units[#units + 1] = explicitUnits[i] end
        if #units == 0 then
            local pageUnit = CurrentRegistryPageUnit()
            if pageUnit then units[#units + 1] = pageUnit end
        end
    end
    if #units == 0 then return nil end

    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. spec.attr)
        local value = setting and EnumValueForText(setting, text) or nil
        if value == nil and setting and ContainsAny(text, { "default", "reset", "restore", "standard" }) then value = "DEFAULT" end
        if setting and value ~= nil then
            changes[#changes + 1] = { setting = setting, value = value, valueLabel = ValueDisplay(setting, value) }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = spec.label,
        bulkSafe = #changes > 1,
        summary = "Changes unit-frame status indicator symbols.",
    }
end

function P.ParseAlphaExcludeTextPortraitShortcut(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(text, {
        "keep text portrait visible", "keep text and portrait visible", "keep text & portrait visible",
        "keep text visible", "keep portrait visible", "exclude text from opacity", "exclude portrait from opacity",
        "text portrait opacity", "text and portrait opacity", "text & portrait opacity",
        "keep names visible when transparent", "keep name visible when transparent",
        "names visible when transparent", "name visible when transparent",
        "keep text visible when transparent", "text visible when transparent",
        "keep names visible when faded", "keep name visible when faded",
        "names visible when faded", "name visible when faded",
        "keep text visible when faded", "text visible when faded",
    }) then return nil end

    local value = DetectBoolean(text)
    if value == nil then value = true end
    local explicitUnits, explicitGroups = ExplicitScopes(text)
    local units = {}
    local groups = {}
    local concrete = false

    if HasAllScopeIntent(text) then
        if ContainsAny(text, { "group frame", "group frames", "all groups", "all group" }) or #explicitGroups > 0 then
            for i = 1, #ALL_GROUPS do groups[#groups + 1] = ALL_GROUPS[i] end
            concrete = true
        elseif ContainsAny(text, { "unitframe", "unit frame", "unitframes", "unit frames", "all units" }) or #explicitUnits > 0 then
            for i = 1, #ALL_UNITFRAMES do units[#units + 1] = ALL_UNITFRAMES[i] end
            concrete = true
        end
    else
        for i = 1, #explicitUnits do units[#units + 1] = explicitUnits[i] end
        for i = 1, #explicitGroups do groups[#groups + 1] = explicitGroups[i] end
        concrete = #units > 0 or #groups > 0
    end

    if #units == 0 and #groups == 0 then
        local pageUnit = CurrentRegistryPageUnit()
        if pageUnit then
            units[#units + 1] = pageUnit
            concrete = true
        else
            local groupScope = CurrentGroupScopeForRegistry()
            if groupScope and GROUP_AVAILABILITY_PAGES[M and M.activeKey] then
                groups[#groups + 1] = groupScope
                concrete = true
            elseif ContainsAny(text, { "group", "groups", "group frame", "group frames" }) then
                local scopeChoices = GroupAvailabilityScopes(text)
                for i = 1, #scopeChoices do groups[#groups + 1] = scopeChoices[i] end
            end
        end
    end

    local changes = {}
    if #units == 0 and #groups == 0 then
        for i = 1, #ALL_UNITFRAMES do AddRegisteredChange(changes, tostring(ALL_UNITFRAMES[i]) .. ".alphaExcludeTextPortrait", value) end
        if #changes == 0 then return nil end
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Which unit frame?",
            summary = "The request matched Keep Text & Portrait Visible but did not name a unit or group frame.",
        }
    end

    for i = 1, #units do AddRegisteredChange(changes, tostring(units[i]) .. ".alphaExcludeTextPortrait", value) end
    for i = 1, #groups do AddRegisteredChange(changes, "gf_" .. tostring(groups[i]) .. ".alphaExcludeTextPortrait", value) end
    if #changes == 0 then return nil end
    if concrete or #changes == 1 or ShouldApplyMultipleRegistryChanges(text, changes) then
        return {
            kind = "changes",
            changes = changes,
            label = "Keep Text & Portrait Visible",
            bulkSafe = #changes > 1,
            summary = "Changes unit/group transparency options.",
        }
    end
    return {
        kind = "ambiguous",
        choices = changes,
        label = "Which Group Frame?",
        summary = "The request matched Keep Text & Portrait Visible but did not name a concrete group frame.",
    }
end

local CASTBAR_BACKEND_UNITS = { "player", "target", "focus", "boss" }
local CASTBAR_BACKEND_ENABLE_KEYS = {
    player = "general.enablePlayerCastbar",
    target = "general.enableTargetCastbar",
    focus = "general.enableFocusCastbar",
    boss = "general.enableBossCastbar",
}
local CASTBAR_BACKEND_PROVIDER_KEYS = {
    player = "general.castbarPlayerBackend",
}
local CASTBAR_BACKEND_BLOCKERS = {
    "texture", "bar texture", "background texture", "sharedmedia", "color", "colour", "farbe",
    "font", "schrift", "size", "width", "height", "breite", "hoehe", "position", "placement",
    "offset", "x offset", "y offset", "versatz", "icon", "symbol", "text", "name", "castbar name", "cast bar name", "spell name",
    "time", "timer", "fill direction", "direction", "richtung", "spark", "glow", "latency",
    "interrupt", "kick", "tick", "ticks", "outline", "border", "rand",
}
local CASTBAR_BACKEND_PROVIDER_TERMS = {
    "provider", "backend", "source", "renderer", "owner",
    "anbieter", "quelle", "besitzer",
}

local function HasCastbarBackendIntent(text)
    if not ContainsAny(text, { "castbar", "cast bar", "zauberleiste", "zauberleisten" }) then return false end
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return false end
    if ContainsAny(text, CASTBAR_BACKEND_PROVIDER_TERMS) then return true end
    if ContainsAny(text, CASTBAR_BACKEND_BLOCKERS) then return false end
    if ContainsAny(text, { "blizzard", "msuf", "hide castbar", "hide cast bar", "hide zauberleiste", "verstecke zauberleiste", "zauberleiste ausblenden", "deaktiviere zauberleiste" }) then return true end
    if ContainsAny(text, {
        "hide", "disable", "disabled", "turn off", "off",
        "ausblenden", "verstecken", "verstecke", "deaktivieren", "deaktiviere", "ausschalten", "aus",
    }) then return true end
    return false
end

local function CastbarBackendValueForText(text)
    if ContainsAny(text, {
        "hide", "hidden", "disable", "disabled", "turn off", "off",
        "ausblenden", "verstecken", "verstecke", "deaktivieren", "deaktiviere", "ausschalten", "aus",
    }) and not ContainsAny(text, { "blizzard", "msuf" }) then
        return "HIDE"
    end
    if ContainsAny(text, {
        "blizzard", "blizzard castbar", "blizzard cast bar", "blizzard zauberleiste",
        "wow castbar", "wow zauberleiste", "standard castbar", "standard zauberleiste",
    }) then
        return "BLIZZARD"
    end
    if ContainsAny(text, {
        "msuf", "msuf castbar", "msuf cast bar", "msuf zauberleiste",
        "own castbar", "custom castbar", "eigene castbar", "eigene zauberleiste",
    }) then
        return "MSUF"
    end
    return nil
end

local function CastbarBackendUnitsForText(text, value)
    local explicitUnits = DetectUnits(text)
    local units = {}
    local concrete = false
    for i = 1, #explicitUnits do
        local unit = explicitUnits[i]
        if CASTBAR_BACKEND_ENABLE_KEYS[unit] then
            units[#units + 1] = unit
            concrete = true
        end
    end
    if #units > 0 then return units, concrete end
    if HasAllScopeIntent(text) or ContainsAny(text, { "all castbars", "all cast bars", "alle castbar", "alle castbars", "alle zauberleisten" }) then
        for i = 1, #CASTBAR_BACKEND_UNITS do units[#units + 1] = CASTBAR_BACKEND_UNITS[i] end
        return units, true
    end
    local pageUnit = CurrentRegistryPageUnit()
    if pageUnit and CASTBAR_BACKEND_ENABLE_KEYS[pageUnit] then
        units[#units + 1] = pageUnit
        return units, true
    end
    if value == "BLIZZARD" then
        return units, false
    end
    return units, false
end

P.ParseCastbarBackendShortcut = function(text)
    if not HasCastbarBackendIntent(text) then return nil end
    local value = CastbarBackendValueForText(text)
    if value == nil then return nil end
    local units, concrete = CastbarBackendUnitsForText(text, value)
    if #units == 0 then
        if value == "BLIZZARD" then
            return {
                kind = "answer",
                status = "ambiguous",
                text = "Player is the only cast bar that can switch between Blizzard and MSUF. For Blizzard, ask for 'use Blizzard player cast bar'. Target, Focus, and Boss cast bars can use MSUF or be hidden.",
                summary = "Explains which cast bars can use Blizzard mode.",
            }
        end
        return nil
    end
    if value == "BLIZZARD" then
        for i = 1, #units do
            if units[i] ~= "player" then
                return {
                    kind = "answer",
                    status = "unsupported",
                    text = "Only the Player cast bar can use Blizzard mode. For Target, Focus, and Boss, use the MSUF cast bar or hide the cast bar.",
                    summary = "Only the Player cast bar can use Blizzard mode.",
                }
            end
        end
    end
    local changes = {}
    for i = 1, #units do
        local unit = units[i]
        if unit == "player" and (value == "MSUF" or value == "BLIZZARD") then
            AddRegisteredChange(changes, CASTBAR_BACKEND_PROVIDER_KEYS.player, value)
        elseif value == "MSUF" then
            AddRegisteredChange(changes, CASTBAR_BACKEND_ENABLE_KEYS[unit], true)
        elseif value == "HIDE" then
            AddRegisteredChange(changes, CASTBAR_BACKEND_ENABLE_KEYS[unit], false)
        end
    end
    if #changes == 0 then return nil end
    if concrete or #changes == 1 or ShouldApplyMultipleRegistryChanges(text, changes) then
        return {
            kind = "changes",
            changes = changes,
            label = "Cast Bar Provider",
            bulkSafe = #changes > 1,
            summary = "Changes whether a cast bar uses MSUF, Blizzard, or is hidden.",
        }
    end
    return {
        kind = "ambiguous",
        choices = changes,
        label = "Which Cast Bar?",
        summary = "Which cast bar do you want me to change: Player, Target, Focus, or Boss?",
    }
end

function P.ParseCastbarPositionRegistryShortcut(text)
    if not ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if ContainsAny(text, {
        "alignment", "align", "text alignment", "text align",
        "spell name alignment", "spell text alignment", "castbar text alignment", "cast bar text alignment",
    }) then return nil end
    local direction = DetectDirection(text, {})
    local naturalPlacement = (direction or ContainsAny(text, { "middle", "center", "centre", "mitte" }))
        and ContainsAny(text, { "put", "place", "set", "position", "on the", "to the", "in the", "middle", "center", "centre", "mitte" })
    if not ContainsAny(text, { "position", "position preset", "placement" }) and not naturalPlacement then return nil end
    if ContainsAny(text, { "move", "nudge", "shift", "offset", "x offset", "y offset" }) then return nil end

    local field
    local label
    if ContainsAny(text, { "icon position", "spell icon position", "castbar icon position", "cast bar icon position" })
        or (naturalPlacement and ContainsAny(text, { "icon", "spell icon" }))
    then
        field = "IconPosition"
        label = "Cast Bar Icon Position"
    elseif ContainsAny(text, { "spell name position", "spell text position", "castbar text position", "cast bar text position", "castbar name position" })
        or (naturalPlacement and ContainsAny(text, { "spell name", "spell text", "castbar text", "cast bar text", "text", "name" }))
    then
        field = "SpellNamePosition"
        label = "Cast Bar Spell Name Position"
    elseif ContainsAny(text, { "time position", "time text position", "timer position", "cast time position", "castbar time position", "cast bar time position" })
        or (naturalPlacement and ContainsAny(text, { "time", "timer", "cast time" }))
    then
        field = "TimePosition"
        label = "Cast Bar rime Position"
    else
        return nil
    end

    local prefixes = {
        player = "castbarPlayer",
        target = "castbarTarget",
        focus = "castbarFocus",
        boss = "bossCast",
    }
    local explicitUnits = DetectUnits(text)
    local units = {}
    local concrete = false
    for i = 1, #explicitUnits do
        local unit = explicitUnits[i]
        if prefixes[unit] then units[#units + 1] = unit end
    end
    if #units > 0 then
        concrete = true
    elseif HasAllScopeIntent(text) then
        units = { "player", "target", "focus", "boss" }
        concrete = true
    else
        local pageUnit = CurrentRegistryPageUnit()
        if pageUnit and prefixes[pageUnit] then
            units[#units + 1] = pageUnit
            concrete = true
        else
            units = { "player", "target", "focus", "boss" }
        end
    end

    local changes = {}
    for i = 1, #units do
        local key = "general." .. tostring(prefixes[units[i]]) .. tostring(field)
        local setting = Registry and Registry:GetSetting(key)
        local value = setting and EnumValueForText(setting, text) or nil
        if setting and value == nil and direction then
            value = direction == "left" and "LEFT"
                or direction == "right" and "RIGHT"
                or direction == "up" and "ABOVE"
                or direction == "down" and "BELOW"
                or nil
        end
        if setting and value == nil and ContainsAny(text, { "middle", "center", "centre", "mitte" }) then
            value = "CENTER"
        end
        if setting and value ~= nil then
            changes[#changes + 1] = { setting = setting, value = value, valueLabel = ValueDisplay(setting, value) }
        end
    end
    if #changes == 0 then return nil end
    if concrete or #changes == 1 or ShouldApplyMultipleRegistryChanges(text, changes) then
        return {
            kind = "changes",
            changes = changes,
            label = label,
            bulkSafe = #changes > 1,
            summary = "Changes cast bar position options.",
        }
    end
    return {
        kind = "ambiguous",
        choices = changes,
        label = "Which Cast Bar?",
        summary = "The request matched a cast bar position option but did not name Player, Target, Focus, or Boss.",
    }
end

function P.ParsePowerBarGradientRegistryShortcut(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(text, { "power bar gradient", "power gradient", "mana gradient" }) then return nil end

    local value = DetectBoolean(text)
    if value == nil then value = true end

    local explicitUnits, explicitGroups = ExplicitScopes(text)
    local units = {}
    local groups = {}
    local concrete = false

    if HasAllScopeIntent(text) then
        if ContainsAny(text, { "group frame", "group frames", "all groups", "all group" }) or #explicitGroups > 0 then
            for i = 1, #ALL_GROUPS do groups[#groups + 1] = ALL_GROUPS[i] end
            concrete = true
        elseif ContainsAny(text, { "unitframe", "unit frame", "unitframes", "unit frames", "all units" }) or #explicitUnits > 0 then
            for i = 1, #ALL_UNITFRAMES do units[#units + 1] = ALL_UNITFRAMES[i] end
            concrete = true
        end
    else
        for i = 1, #explicitUnits do units[#units + 1] = explicitUnits[i] end
        for i = 1, #explicitGroups do groups[#groups + 1] = explicitGroups[i] end
        concrete = #units > 0 or #groups > 0
    end

    if #units == 0 and #groups == 0 then
        local pageUnit = CurrentRegistryPageUnit()
        if pageUnit then
            units[#units + 1] = pageUnit
            concrete = true
        elseif M and (M.activeKey == "gf_layout" or M.activeKey == "gf_bars" or M.activeKey == "gf_indicators") then
            local scope = CurrentGroupScopeForRegistry()
            if scope then
                groups[#groups + 1] = scope
                concrete = true
            end
        end
    end

    local changes = {}
    local only = ContainsAny(text, { "only", "just", "nur" })
    local seenScopes = {}
    local function AddScopedGradient(scope)
        if scope == "gf_mythicraid" then scope = "gf_raid" end
        if seenScopes[scope] then return end
        seenScopes[scope] = true
        local key = "barScope." .. tostring(scope) .. ".enablePowerGradient"
        if only and scope ~= "shared" then AddRegisteredChange(changes, "barScope." .. tostring(scope) .. ".override", true) end
        AddRegisteredChange(changes, key, value)
    end

    for i = 1, #units do AddScopedGradient(units[i]) end
    for i = 1, #groups do AddScopedGradient("gf_" .. tostring(groups[i])) end

    if #changes == 0 then
        local setting = Registry and Registry:GetSetting("general.enablePowerGradient")
        if not setting then return nil end
        return {
            kind = "changes",
            changes = { { setting = setting, value = value, valueLabel = ValueDisplay(setting, value) } },
            label = setting.label or "Power Bar Gradient",
            summary = "Changes the Power Bar Gradient option.",
        }
    end

    return {
        kind = "changes",
        changes = changes,
        label = "Power Bar Gradient",
        bulkSafe = #changes > 1,
        summary = "Changes target-specific Power Bar Gradient options.",
    }
end

P.GroupShortcutScopes = function(text)
    local scopes, concrete = GroupAvailabilityScopes(text)
    local allGroups = HasAllScopeIntent(text) or ContainsAny(text, {
        "all group frames", "all groups", "group frames", "party raid", "party and raid",
    })
    return scopes, concrete or allGroups
end

P.GroupShortcutResponse = function(text, changes, concrete, title, summary)
    if #changes == 0 then return nil end
    if concrete or #changes == 1 or ShouldApplyMultipleRegistryChanges(text, changes) then
        return {
            kind = "changes",
            changes = changes,
            label = title,
            bulkSafe = #changes > 1,
            summary = summary,
        }
    end
    return {
        kind = "ambiguous",
        choices = changes,
        label = title,
        summary = summary,
    }
end

P.ParseGroupRolePowerVisibilityShortcut = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff", "castbar", "cast bar" }) then return nil end
    if ContainsAny(text, { "role icon", "role indicator", "status icon", "status indicator", "symbol" }) then return nil end
    if not ContainsAny(text, { "power", "mana", "resource", "resources", "power bar", "power bars", "mana bar", "mana bars", "resource bar", "resource bars" }) then return nil end

    local attr
    local label
    if ContainsAny(text, { "tank", "tanks", "tank role", "tank players" }) then
        attr = "powerShowTank"
        label = "Tank Power"
    elseif ContainsAny(text, { "healer", "healers", "heal role", "healer role", "healer mana", "healer power" }) then
        attr = "powerShowHealer"
        label = "Healer Power"
    elseif ContainsAny(text, { "dps", "damage dealer", "damage dealers", "damager", "damagers", "damage role" }) then
        attr = "powerShowDamager"
        label = "DPS Power"
    else
        return nil
    end

    local value = ShowSettingValueForText(text)
    if value == nil then return nil end
    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. "." .. attr, value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame role power", "Changes role-specific Group Frame power visibility options for " .. label .. ".")
end

P.ParseGroupRoleIconVisibilityShortcut = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff", "castbar", "cast bar" }) then return nil end
    if not ContainsAny(text, { "role icon", "role icons", "role indicator", "role indicators", "role symbol", "role symbols" }) then return nil end

    local attr
    local label
    if ContainsAny(text, { "tank", "tanks", "tank role", "tank players" }) then
        attr = "roleIconShowTank"
        label = "Tank Role Icon"
    elseif ContainsAny(text, { "healer", "healers", "heal role", "healer role" }) then
        attr = "roleIconShowHealer"
        label = "Healer Role Icon"
    elseif ContainsAny(text, { "dps", "damage dealer", "damage dealers", "damager", "damagers", "damage role" }) then
        attr = "roleIconShowDPS"
        label = "DPS Role Icon"
    else
        return nil
    end

    local value = ShowSettingValueForText(text)
    if value == nil then return nil end
    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. "." .. attr, value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame role icon visibility", "Changes role-specific Group Frame role-icon visibility options for " .. label .. ".")
end

P.ParseGroupOfflineAlphaShortcut = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff", "castbar", "cast bar" }) then return nil end
    if not ContainsAny(text, { "offline", "offline member", "offline members", "offline player", "offline players" }) then return nil end
    if ContainsAny(text, { "delay", "after", "seconds", "in combat", "hide offline in combat", "offline members in combat", "offline players in combat" }) then return nil end
    if not ContainsAny(text, {
        "alpha", "opacity", "transparency", "transparent", "fade", "faded",
        "more visible", "less visible", "more transparent", "less transparent",
    }) then
        return nil
    end

    local value
    local relativeDelta
    if ContainsAny(text, { "more transparent", "less visible", "fade more", "more faded", "stronger fade" }) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = -amount
    elseif ContainsAny(text, { "less transparent", "more visible", "fade less", "less faded", "weaker fade" }) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = amount
    else
        value = FirstNumber(text)
        if value == nil then return nil end
        if value > 1 then value = value / 100 end
    end

    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".offlineAlpha", value, relativeDelta)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame offline opacity", "Changes the Group Frame Offline Opacity slider.")
end

P.ParseGroupHealthFadeShortcut = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff", "castbar", "cast bar" }) then return nil end
    if not ContainsAny(text, {
        "health fade", "healthy fade", "healer health fade",
        "fade healthy", "fade healthy members", "fade healthy frames",
        "dim healthy", "dim healthy members", "dim healthy frames",
        "fade full health", "dim full health",
    }) then
        return nil
    end

    local scopes, concrete = P.GroupShortcutScopes(text)
    if not concrete and #scopes > 1 then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which group frame Health Fade should I change: Party, Raid, or Mythic Raid? Examples: 'dim healthy raid frames', 'set party health fade threshold to 90', or 'set raid health fade opacity to 35%'.",
            summary = "Clarifies group Health Fade scope instead of changing every group scope.",
        }
    end

    local value = FirstNumber(text)
    local relativeDelta
    local alphaIntent = ContainsAny(text, {
        "opacity", "alpha", "transparent", "transparency", "visibility",
        "dimmed opacity", "dimmed health opacity", "healthy opacity",
    }) or (ContainsAny(text, {
        "dim healthy", "dim healthy members", "dim healthy frames",
        "fade healthy", "fade healthy members", "fade healthy frames",
        "dim full health", "fade full health",
    }) and HasPhrase(text, "to"))
    local thresholdIntent = ContainsAny(text, {
        "threshold", "percent", "health percent", "hp percent",
        "above health", "above health percent", "above hp", "above hp percent",
        "fade above", "dim above", "when above", "at health",
    }) or (value ~= nil and HasPhrase(text, "above")) or (value ~= nil and HasPhrase(text, "over")) or (value ~= nil and HasPhrase(text, "at") and not alphaIntent)

    if ContainsAny(text, { "more transparent", "less visible", "fade more", "more faded", "stronger fade", "dim more" }) then
        local amount = value or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = -amount
        alphaIntent = true
        thresholdIntent = false
    elseif ContainsAny(text, { "less transparent", "more visible", "fade less", "less faded", "weaker fade", "dim less" }) then
        local amount = value or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = amount
        alphaIntent = true
        thresholdIntent = false
    end

    local changes = {}
    if value ~= nil or relativeDelta ~= nil then
        local attr
        local label
        if alphaIntent and not thresholdIntent then
            attr = "healthFadeAlpha"
            label = "Group Health Fade Opacity"
            if value ~= nil and value > 1 then value = value / 100 end
        elseif thresholdIntent and not alphaIntent then
            attr = "healthFadeThreshold"
            label = "Group Health Fade Threshold"
            if value ~= nil and value > 0 and value <= 1 then value = value * 100 end
        else
            return {
                kind = "answer",
                status = "ambiguous",
                text = "For Health Fade, do you mean the health threshold or the dimmed opacity? Examples: 'set raid health fade threshold to 90' or 'set raid health fade opacity to 35%'.",
                summary = "Clarifies Health Fade numeric intent instead of guessing threshold or opacity.",
            }
        end
        for i = 1, #scopes do
            AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. "." .. attr, value, relativeDelta)
            if attr == "healthFadeThreshold" or (attr == "healthFadeAlpha" and (relativeDelta ~= nil or (value ~= nil and value < 1))) then
                AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".healthFadeEnabled", true)
            end
        end
        return P.GroupShortcutResponse(text, changes, concrete, label, "Changes group-frame Health Fade options.")
    end

    local enabled = ShowSettingValueForText(text)
    if enabled == nil then
        if ContainsAny(text, { "stop", "stop fading", "stop dimming", "do not dim", "dont dim", "don't dim", "never dim", "do not fade", "dont fade", "don't fade", "never fade" }) then
            enabled = false
        elseif ContainsAny(text, { "dim", "fade", "health fade", "healthy fade" }) then
            enabled = true
        end
    end
    if enabled == nil then return nil end

    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".healthFadeEnabled", enabled)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group Health Fade", "Changes the group-frame Health Fade toggle.")
end

P.ParseGroupColumnLayoutShortcut = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff", "castbar", "cast bar" }) then return nil end
    if not ContainsAny(text, { "column", "columns", "per column", "spalte", "spalten" }) then return nil end
    if not ContainsAny(text, { "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames", "frames", "member", "members", "players" }) then return nil end
    local value = FirstNumber(text)
    if value == nil then
        if HasPhrase(text, "one") then value = 1
        elseif HasPhrase(text, "two") then value = 2
        elseif HasPhrase(text, "three") then value = 3
        elseif HasPhrase(text, "four") then value = 4
        elseif HasPhrase(text, "five") then value = 5
        elseif HasPhrase(text, "six") then value = 6
        elseif HasPhrase(text, "seven") then value = 7
        elseif HasPhrase(text, "eight") then value = 8
        elseif HasPhrase(text, "nine") then value = 9
        elseif HasPhrase(text, "ten") then value = 10 end
    end
    if value == nil then return nil end

    local attr = "maxColumns"
    local label = "Group frame max columns"
    if ContainsAny(text, {
        "per column", "members per column", "players per column", "frames per column", "units per column",
        "new column after", "column after", "columns after", "start new column after", "break column after",
        "break columns after", "after players", "after members",
    }) then
        attr = "unitsPerColumn"
        label = "Group frame units per column"
    end

    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. "." .. attr, value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, label, "Changes Group Layout column options.")
end

P.ParseGroupPreserveRaidGroupsShortcut = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff", "castbar", "cast bar" }) then return nil end
    if not ContainsAny(text, {
        "preserve raid groups", "keep raid groups", "keep raid groups together",
        "keep groups together", "preserve groups", "preserve group order",
    }) then
        return nil
    end

    local value = DetectBoolean(text)
    if value == nil then
        value = not ContainsAny(text, { "do not", "dont", "don't", "disable", "turn off", "off", "false", "no", "stop" })
    end

    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".preserveRaidGroups", value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame Preserve Raid Groups", "Changes Group Layout raid-group preservation.")
end

P.ParseGroupPlayerFirstInRoleShortcut = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(text, { "role", "role sorting", "sort by role", "sorting" }) then return nil end
    if not ContainsAny(text, {
        "player first", "me first", "myself first", "put me first", "put myself first",
        "keep me first", "keep myself first", "me at top", "me at the top",
        "myself at top", "myself at the top", "put me at top", "put me at the top",
        "put myself at top", "put myself at the top", "keep me at top", "keep me at the top",
        "keep myself at top", "keep myself at the top",
    }) then
        return nil
    end
    local value = DetectBoolean(text)
    if value == nil then value = not ContainsAny(text, { "do not", "dont", "don't", "disable", "turn off", "off", "false", "no" }) end

    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".playerFirstInRole", value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame player first in role", "Changes the Player First in Role sorting toggle.")
end

local GROUP_BLIZZARD_FALLBACK_TERMS = {
    "blizzard fallback", "blizzard fallback mode", "fallback mode", "fallback modus",
    "if this switch is off", "when disabled", "when group frames are disabled",
    "disabled group frame behavior", "disabled group frame blizzard behavior",
    "wenn dieser schalter aus ist", "wenn der schalter aus ist", "wenn gruppenframes aus sind",
    "wenn gruppenframes deaktiviert sind", "wenn party aus ist", "wenn raid aus ist",
    "wenn party frames aus sind", "wenn raid frames aus sind",
}

local GROUP_BLIZZARD_FRAME_TERMS = {
    "blizzard group frames", "blizzard group frame", "blizzard party frames", "blizzard raid frames",
    "blizzard frames", "default group frames", "default party frames", "default raid frames",
    "standard group frames", "standard party frames", "standard raid frames",
    "blizzard gruppenframes", "blizzard gruppen frames",
    "standard gruppenframes", "standard gruppen frames", "standardrahmen", "standard rahmen",
}

local function HasGroupBlizzardFallbackIntent(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff", "castbar", "cast bar", "unitframe", "unit frame", "unitframes", "unit frames" }) then return false end
    local groups = DetectGroups(text)
    if ContainsAny(text, GROUP_BLIZZARD_FALLBACK_TERMS) then return true end
    if #groups == 0 then return false end
    if not ContainsAny(text, GROUP_BLIZZARD_FRAME_TERMS) then return false end
    return ContainsAny(text, {
        "show", "hide", "force", "auto", "automatic", "fallback", "when disabled", "if off",
        "anzeigen", "einblenden", "ausblenden", "verstecken", "erzwingen", "automatisch",
        "wenn aus", "wenn deaktiviert", "wenn ausgeschaltet",
    })
end

local function GroupBlizzardFallbackValueForText(text)
    if ContainsAny(text, {
        "auto", "automatic", "automatically", "blizzard default", "blizzard decides",
        "normal behavior", "default behavior", "automatisch", "blizzard entscheidet",
        "standard verhalten", "normales verhalten",
    }) then
        return "AUTO"
    end
    if ContainsAny(text, {
        "hide all", "hide both", "hide blizzard", "hide default", "hide standard",
        "none", "no blizzard", "no default frames", "no standard frames",
        "alles ausblenden", "alle verstecken", "beide ausblenden", "blizzard ausblenden",
        "blizzard verstecken", "standardrahmen ausblenden", "standard rahmen ausblenden",
        "keine blizzard frames", "keine standardrahmen", "nichts anzeigen",
    }) then
        return "NONE"
    end
    if ContainsAny(text, {
        "show blizzard", "show default", "show standard", "force blizzard",
        "restore blizzard", "use blizzard", "blizzard visible", "blizzard frames visible",
        "blizzard anzeigen", "blizzard einblenden", "standardrahmen anzeigen",
        "standard rahmen anzeigen", "standardframes anzeigen", "blizzard erzwingen",
        "blizzard sichtbar", "blizzard frames sichtbar",
    }) then
        return "SHOW"
    end
    if ContainsAny(text, { "show", "visible", "anzeigen", "einblenden", "sichtbar" }) and ContainsAny(text, GROUP_BLIZZARD_FRAME_TERMS) then return "SHOW" end
    if ContainsAny(text, { "hide", "hidden", "off", "ausblenden", "verstecken", "aus" }) and ContainsAny(text, GROUP_BLIZZARD_FRAME_TERMS) then return "NONE" end
    return nil
end

P.ParseGroupBlizzardFallbackShortcut = function(text)
    if not HasGroupBlizzardFallbackIntent(text) then return nil end
    local value = GroupBlizzardFallbackValueForText(text)
    if value == nil then return nil end
    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".blizzardFallbackMode", value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame Blizzard fallback", "Changes the Group Frame Blizzard Fallback Mode dropdown.")
end

local GROUP_AGGRO_ROLE_INTENT_TERMS = {
    "aggro shows for", "threat shows for", "aggro role filter", "threat role filter",
    "aggro non tank", "aggro non tanks", "aggro not tank", "aggro not tanks",
    "threat non tank", "threat non tanks", "threat not tank", "threat not tanks",
    "aggro only for", "threat only for", "aggro for", "threat for",
}

local GROUP_AGGRO_ROLE_SCOPE_TERMS = {
    "party", "party frame", "party frames", "partyframe", "partyframes",
    "raid", "raid frame", "raid frames", "raidframe", "raidframes",
    "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraid",
    "mythicraidframe", "mythicraidframes", "group", "groups", "group frame", "group frames",
}

local function GroupAggroRoleValueForText(text)
    if ContainsAny(text, { "non tank", "non tanks", "nontank", "nontanks", "not tank", "not tanks", "non-tank", "non-tanks" }) then
        return "NON_TANK"
    end
    if ContainsAny(text, { "healer", "healers", "heal role", "healer role", "healing role" }) then
        return "HEALER"
    end
    if ContainsAny(text, { "tank", "tanks", "tank role" }) then
        return "TANK"
    end
    if ContainsAny(text, {
        "shows for all", "show for all", "role filter to all", "filter to all",
        "for everyone", "for anyone", "all roles", "all players",
    }) then
        return "ALL"
    end
    return nil
end

local function GroupAggroExplicitScopes(text)
    local scopes = {}
    local mythic = ContainsAny(text, {
        "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraid",
        "mythicraidframe", "mythicraidframes",
    })
    if mythic then scopes[#scopes + 1] = "mythicraid" end
    if ContainsAny(text, { "party", "party frame", "party frames", "partyframe", "partyframes" }) then scopes[#scopes + 1] = "party" end
    if ContainsAny(text, { "raid", "raid frame", "raid frames", "raidframe", "raidframes" }) and not mythic then scopes[#scopes + 1] = "raid" end
    if #scopes > 0 then return scopes, true end
    if ContainsAny(text, { "all group frames", "all groups", "every group frame", "each group frame", "party and raid", "party raid" }) then
        return { "party", "raid", "mythicraid" }, true
    end
    if ContainsAny(text, { "group", "groups", "group frame", "group frames" }) then return nil, false, true end
    return nil, false, false
end

P.ParseGroupAggroRoleFilterShortcut = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff", "castbar", "cast bar", "boss target", "corner indicator", "spell indicator" }) then return nil end
    if ContainsAny(text, { "fallback aggro", "fallback threat", "group fallback aggro", "group fallback threat" }) then return nil end
    if not ContainsAny(text, { "aggro", "threat" }) then return nil end
    if not ContainsAny(text, GROUP_AGGRO_ROLE_SCOPE_TERMS) then return nil end
    local roleValue = GroupAggroRoleValueForText(text)
    local hasRoleIntent = ContainsAny(text, GROUP_AGGRO_ROLE_INTENT_TERMS)
        or (roleValue ~= nil and not ContainsAny(text, { "color", "colour", "opacity", "alpha", "thickness", "size" }))
    if not hasRoleIntent then return nil end

    local scopes, concrete, genericGroup = GroupAggroExplicitScopes(text)
    if genericGroup then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which group aggro role filter do you mean: Party, Raid, or Mythic Raid? You can also say 'all group frames'.",
            summary = "Clarifies the group-frame scope before changing the scoped Aggro Shows For setting.",
        }
    end
    if not scopes or #scopes == 0 then return nil end
    if roleValue == nil then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "For Aggro Shows For, choose all roles, non-tanks, healers, or tanks. Example: 'set raid aggro shows for non tanks'.",
            summary = "Clarifies the group aggro role filter value instead of guessing.",
        }
    end

    local changes = {}
    for i = 1, #scopes do
        local scope = "gf_" .. tostring(scopes[i])
        AddRegisteredChange(changes, "barScope." .. scope .. ".aggroMode", roleValue)
        AddRegisteredChange(changes, "barScope." .. scope .. ".aggroOutlineMode", "on")
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group Aggro Shows For", "Enables scoped Aggro Border and changes which group-member roles can show it.")
end

P.ParseGroupSortShortcut = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(text, { "sort", "sorting", "order", "first" }) then return nil end
    if DetectBoolean(text) ~= nil and ContainsAny(text, { "sort by role", "role sorting", "sort roles" }) then return nil end
    if not ContainsAny(text, {
        "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames", "frames",
        "role", "roles", "tank", "tanks", "healer", "healers", "heal", "dps", "damager", "name", "alphabetical", "group",
    }) then return nil end

    local sortValue
    local roleOrderValue
    if ContainsAny(text, {
        "sort by group and role", "sort by group role", "group and role", "group plus role",
        "group role", "group then role", "group then roles", "groups then role", "groups then roles",
        "by group then role", "by group then roles", "by groups then role", "by groups then roles",
        "raid groups then roles", "raid groups then role", "groups first then roles", "groups first then role",
    }) then
        sortValue = "GROUP_ROLE"
    elseif ContainsAny(text, { "sort by group", "raid group order", "by raid group", "by group" }) then
        sortValue = "GROUP"
    elseif ContainsAny(text, { "sort by name", "by name", "alphabetical", "alphabetically", "name order" }) then
        sortValue = "NAME"
    elseif ContainsAny(text, { "sort by role", "by role", "role sorting", "sort roles", "roles" }) then
        sortValue = "ROLE"
    elseif ContainsAny(text, {
        "tank first", "tanks first", "tank on top", "tanks on top", "tank at top", "tanks at top",
        "tank at the top", "tanks at the top", "with tanks at top", "with tanks at the top",
        "tank role first", "tanks role first",
    }) then
        sortValue = "ROLE"
        roleOrderValue = "TANK,HEALER,DAMAGER"
    elseif ContainsAny(text, { "healer first", "healers first", "heal first", "heals first", "healer on top", "healers on top" }) then
        sortValue = "ROLE"
        roleOrderValue = "HEALER,TANK,DAMAGER"
    elseif ContainsAny(text, { "dps first", "damage first", "damager first", "damagers first", "dps on top" }) then
        sortValue = "ROLE"
        roleOrderValue = "DAMAGER,TANK,HEALER"
    else
        return nil
    end

    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".sortMode", sortValue)
        if roleOrderValue then AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".roleOrder", roleOrderValue) end
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame sorting", "Changes Group Frame sort mode and role order options.")
end

P.ParseGroupScaleModeShortcut = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(text, { "scale", "scaling", "frame scale", "frame scaling", "group scale", "group scaling" }) then return nil end
    if FirstNumber(text) ~= nil then return nil end
    local explicitMode = ContainsAny(text, {
        "scale mode", "scaling mode", "frame scale mode", "frame scaling mode",
        "group scale mode", "group scaling mode",
    })

    local value
    if ContainsAny(text, {
        "auto", "automatic", "automatically", "breakpoint", "breakpoints", "dynamic",
        "by player count", "by players", "by group size", "by raid size",
        "based on player count", "based on players", "based on group size", "based on raid size",
        "depending on player count", "depending on players", "depending on group size", "depending on raid size",
        "scale by player count", "scale by raid size", "scale by group size",
    }) then
        value = "auto"
    elseif ContainsAny(text, { "manual", "custom" }) then
        value = "manual"
    elseif explicitMode and ContainsAny(text, { "off", "disable", "disabled", "turn off", "none", "no scaling" }) then
        value = "off"
    elseif explicitMode and ContainsAny(text, { "on", "enable", "enabled", "turn on" }) then
        value = "manual"
    end
    if value == nil then return nil end

    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".frameScaleMode", value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame scaling mode", "Changes the Group Layout Frame Scaling Mode option.")
end

P.ParseGroupOfflineDelayShortcut = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(text, { "offline", "offline members", "offline players" }) then return nil end
    if not ContainsAny(text, { "delay", "after", "seconds", "sec", "hide offline" }) then return nil end
    local value = FirstNumber(text)
    if value == nil then return nil end

    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    local enableHide = ContainsAny(text, { "hide", "hide offline", "offline members", "offline players" })
    for i = 1, #scopes do
        if enableHide then AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".hideOfflineEnabled", true) end
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".hideOfflineDelay", value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame offline delay", "Changes Group Frame offline-member hiding options.")
end

P.ParseMiscRegistryShortcut = function(text, raw)
    if ContainsAny(text, { "aura", "auras", "buff" }) then return nil end
    if ContainsAny(text, { "debuff" }) and not ContainsAny(text, { "debuff stripe" }) then return nil end
    local interruptReady = P.ParseInterruptReadyRegistryShortcut and P.ParseInterruptReadyRegistryShortcut(text, raw)
    if interruptReady then return interruptReady end
    local focusKick = P.ParseFocusKickRegistryShortcut and P.ParseFocusKickRegistryShortcut(text)
    if focusKick then return focusKick end
    local unitStatusSymbol = P.ParseUnitStatusSymbolRegistryShortcut and P.ParseUnitStatusSymbolRegistryShortcut(text)
    if unitStatusSymbol then return unitStatusSymbol end
    local castbarBackend = P.ParseCastbarBackendShortcut and P.ParseCastbarBackendShortcut(text)
    if castbarBackend then return castbarBackend end
    local castbarPosition = P.ParseCastbarPositionRegistryShortcut and P.ParseCastbarPositionRegistryShortcut(text)
    if castbarPosition then return castbarPosition end
    local powerGradient = P.ParsePowerBarGradientRegistryShortcut and P.ParsePowerBarGradientRegistryShortcut(text)
    if powerGradient then return powerGradient end
    local alphaExclude = P.ParseAlphaExcludeTextPortraitShortcut and P.ParseAlphaExcludeTextPortraitShortcut(text)
    if alphaExclude then return alphaExclude end
    local unitHPTextReverse = P.ParseUnitHPTextReverseShortcut and P.ParseUnitHPTextReverseShortcut(text)
    if unitHPTextReverse then return unitHPTextReverse end
    local groupRolePower = P.ParseGroupRolePowerVisibilityShortcut and P.ParseGroupRolePowerVisibilityShortcut(text)
    if groupRolePower then return groupRolePower end
    local groupRoleIcon = P.ParseGroupRoleIconVisibilityShortcut and P.ParseGroupRoleIconVisibilityShortcut(text)
    if groupRoleIcon then return groupRoleIcon end
    local groupOfflineAlpha = P.ParseGroupOfflineAlphaShortcut and P.ParseGroupOfflineAlphaShortcut(text)
    if groupOfflineAlpha then return groupOfflineAlpha end
    local groupHealthFade = P.ParseGroupHealthFadeShortcut and P.ParseGroupHealthFadeShortcut(text)
    if groupHealthFade then return groupHealthFade end
    local groupColumns = P.ParseGroupColumnLayoutShortcut and P.ParseGroupColumnLayoutShortcut(text)
    if groupColumns then return groupColumns end
    local groupPreserveRaidGroups = P.ParseGroupPreserveRaidGroupsShortcut and P.ParseGroupPreserveRaidGroupsShortcut(text)
    if groupPreserveRaidGroups then return groupPreserveRaidGroups end
    local groupPlayerFirst = P.ParseGroupPlayerFirstInRoleShortcut and P.ParseGroupPlayerFirstInRoleShortcut(text)
    if groupPlayerFirst then return groupPlayerFirst end
    local groupBlizzardFallback = P.ParseGroupBlizzardFallbackShortcut and P.ParseGroupBlizzardFallbackShortcut(text)
    if groupBlizzardFallback then return groupBlizzardFallback end
    local groupAggroRole = P.ParseGroupAggroRoleFilterShortcut and P.ParseGroupAggroRoleFilterShortcut(text)
    if groupAggroRole then return groupAggroRole end
    local groupBoolean = P.ParseGroupBooleanRegistryShortcut and P.ParseGroupBooleanRegistryShortcut(text)
    if groupBoolean then return groupBoolean end
    local groupNumber = P.ParseGroupNumberRegistryShortcut and P.ParseGroupNumberRegistryShortcut(text)
    if groupNumber then return groupNumber end
    local detachedPower = P.ParseDetachedPowerBarRegistryShortcut and P.ParseDetachedPowerBarRegistryShortcut(text, raw)
    if detachedPower then return detachedPower end
    local key
    local forcedValue
    if ContainsAny(text, { "midnight status icons", "status icons midnight style", "status icon midnight style", "midnight status icon style", "use midnight status icons" }) then
        if #DetectGroups(text) > 0 and #DetectUnits(text) == 0 then return nil end
        key = "general.statusIconsUseMidnightStyle"
        forcedValue = DetectBoolean(text)
        if forcedValue == nil then forcedValue = true end
    elseif ContainsAny(text, { "global ui scale", "global ui scale override", "wow ui scale", "wow ui scale override", "ui scale override" }) then
        key = "general.globalUiScaleEnabled"
    elseif ContainsAny(text, { "realtime power text", "real time power text", "live power text", "instant power text" }) then
        key = "bars.realtimePowerText"
    elseif ContainsAny(text, { "sync combat state colors", "sync combat enter leave colors", "same combat state colors", "combat state color sync" }) then
        key = "gameplay.combatStateColorSync"
        forcedValue = DetectBoolean(text)
        if forcedValue == nil and ContainsAny(text, { "sync", "same" }) then forcedValue = true end
    elseif ContainsAny(text, { "castbar fill left to right", "cast bar fill left to right", "castbar fills left to right", "cast bar fills left to right", "castbar direction left to right", "cast bar direction left to right" }) then
        key = "general.castbarFillDirection"
        forcedValue = "LTR"
    elseif ContainsAny(text, { "castbar fill right to left", "cast bar fill right to left", "castbar fills right to left", "cast bar fills right to left", "castbar direction right to left", "cast bar direction right to left" }) then
        key = "general.castbarFillDirection"
        forcedValue = "RTL"
    elseif ContainsAny(text, {
        "castbar fill backwards", "cast bar fill backwards", "castbar fills backwards", "cast bar fills backwards",
        "castbar fill backward", "cast bar fill backward", "castbar reverse fill", "cast bar reverse fill",
        "reverse castbar fill", "reverse cast bar fill", "castbar reverse direction", "cast bar reverse direction",
    }) then
        key = "general.castbarFillDirection"
        forcedValue = "RTL"
    elseif ContainsAny(text, {
        "castbar fill normal", "cast bar fill normal", "castbar normal fill", "cast bar normal fill",
        "castbar normal direction", "cast bar normal direction", "castbar fill forward", "cast bar fill forward",
        "castbar forward fill", "cast bar forward fill",
    }) then
        key = "general.castbarFillDirection"
        forcedValue = "LTR"
    elseif ContainsAny(text, { "nameplate melee spell id", "melee nameplate spell id", "melee range spell id", "crosshair melee spell id", "crosshair spell id" }) then
        key = "gameplay.nameplateMeleeSpellID"
    elseif ContainsAny(text, { "snap", "snapping", "edge snap", "window snap", "menu snap", "snapping feature", "snap feature", "menue snap", "menue einrasten", "menue andocken", "fenster einrasten", "fenster andocken", "kante andocken" }) then
        if ContainsAny(text, { "edit mode", "grid snap", "snap to grid", "snap frames", "mover snap", "raster snap" }) then return nil end
        key = "general.slashMenuSnapEnabled"
    elseif ContainsAny(text, { "advanced menu", "advanced menu section", "advanced section", "erweitertes menu", "erweitertes menue", "advanced menue" }) then
        key = "general.hideAdvancedMenu"
    elseif ContainsAny(text, { "reduce motion", "menu motion", "reduce animations", "menu animations", "bewegung reduzieren", "menue bewegung reduzieren", "animationen reduzieren", "weniger bewegung", "weniger animationen", "reduzierte bewegung" }) then
        key = "general.reduceMotion"
    elseif ContainsAny(text, { "navigation icons", "nav icons", "menu icons", "sidebar icons", "rail icons", "navigation symbols", "nav symbols", "menu symbols", "sidebar symbols", "rail symbols", "navi symbole", "navigationssymbole", "navigation symbole", "menue symbole", "menu symbole", "navi icons" }) then
        key = "general.showNavigationIcons"
    elseif ContainsAny(text, { "welcome message", "startup welcome", "startup message", "start message", "willkommensnachricht", "willkommens nachricht", "willkommens meldung", "willkommen nachricht", "login nachricht", "start meldung" }) then
        key = "general.showWelcomeMessage"
    elseif ContainsAny(text, { "version check", "peer version check", "peer-to-peer version check", "update check", "versionscheck", "versions pruefung", "version pruefung", "versionspruefung", "peer versionspruefung", "update pruefung" }) then
        key = "general.versionCheckEnabled"
    elseif ContainsAny(text, { "minimap icon", "minimap button", "msuf minimap icon", "msuf minimap button", "minikarten symbol", "minimap symbol", "minimap knopf", "minikarten icon", "minikarten button", "minikarten knopf" }) then
        key = "general.showMinimapIcon"
    elseif ContainsAny(text, { "target sounds", "target sound", "target lost sound", "target lost sounds", "target select sound", "target select sounds", "target select lost sounds", "play sound on target", "play sound on target lost", "play sound on target select", "ziel sound", "ziel sounds", "zielauswahl sound", "ziel verloren sound", "ziel verloren sounds", "sound bei ziel", "sound bei zielwechsel", "spiele sound bei ziel" }) then
        key = "general.playTargetSelectLostSounds"
    elseif ContainsAny(text, { "fully hide blizzard playerframe", "fully hide blizzard player frame", "hard hide blizzard playerframe", "hard hide blizzard player frame", "hard kill blizzard playerframe", "hard kill blizzard player frame", "resource bar compatibility", "blizzard spieler rahmen komplett verstecken", "blizzard spieler frame komplett verstecken", "playerframe hart verstecken", "spieler frame hart verstecken", "ressourcenleisten kompatibilitaet" }) then
        key = "general.hardKillBlizzardPlayerFrame"
    elseif ContainsAny(text, { "blizzard unitframes", "blizzard unit frames", "blizzard frames", "standard frames", "default frames", "blizzard unitframe", "blizzard rahmen", "standardrahmen", "standard rahmen", "wow unitframes", "wow rahmen", "original frames" }) then
        key = "general.disableBlizzardUnitFrames"
    elseif ContainsAny(text, { "menu language", "msuf language", "menu locale", "locale", "language", "sprache", "menue sprache", "menuesprache", "msuf sprache", "optionen sprache" }) then
        key = "general.menuLocale"
    elseif ContainsAny(text, { "dropdown style", "dropdown style mode", "dropdown module style", "menu dropdown style", "dropdown skin", "dropdown design", "dropdown stil", "menue dropdown stil", "dropdown modus", "dropdown aussehen", "auswahlmenue stil", "menue auswahl stil" }) then
        key = "general.dropdownStyleMode"
    elseif ContainsAny(text, { "msuf style", "msuf style module", "midnight style", "midnight design", "style module", "module style", "msuf skin", "msuf stil", "midnight stil", "stil modul", "style modul", "design modul", "msuf design", "skin modul" }) then
        if ContainsAny(text, {
            "status icon", "status icons", "status indicator", "status indicators", "indicator", "indicators",
            "ready check", "readycheck", "combat icon", "combat indicator", "rested icon", "resting icon",
            "leader icon", "assist icon", "role icon", "raid marker", "pvp flag", "phase icon", "summon icon",
            "party", "party frame", "raid", "raid frame", "group frame", "group frames",
        }) then return nil end
        key = "general.styleEnabled"
    elseif ContainsAny(text, { "tooltip modifier", "tooltip modifier key", "unit tooltip modifier", "unitframe tooltip modifier", "modifier key", "tooltip taste", "tooltip modifier taste", "tooltip hotkey", "tooltip aktivierungstaste" }) and ContainsAny(text, { "tooltip", "tooltips" }) then
        key = "general.unitTooltipModifier"
    elseif ContainsAny(text, { "use msuf tooltip", "use msuf tooltips", "use msuf unitframe tooltip", "nutze msuf tooltip", "nutze msuf tooltips", "verwende msuf tooltip", "verwende msuf tooltips" }) then
        key = "general.unitTooltipProvider"
        forcedValue = "MSUF"
    elseif ContainsAny(text, { "use gametooltip", "use game tooltip", "use game tooltips", "use blizzard tooltip", "nutze gametooltip", "nutze game tooltip", "verwende gametooltip", "verwende blizzard tooltip" }) then
        key = "general.unitTooltipProvider"
        forcedValue = "GAME"
    elseif ContainsAny(text, { "tooltip source", "unitframe tooltip source", "unit tooltip source", "group frame tooltip source", "game tooltip source", "gametooltip source", "tooltip quelle", "tooltip anbieter", "unitframe tooltip quelle", "einheiten tooltip quelle", "gruppen tooltip quelle", "game tooltip quelle", "msuf tooltip quelle" }) then
        key = "general.unitTooltipProvider"
    elseif ContainsAny(text, { "tooltip anchor", "unitframe tooltip anchor", "unit tooltip anchor", "tooltip position", "tooltip location", "tooltip anker", "unitframe tooltip anker", "tooltip ort", "tooltip platzierung" })
        or (ContainsAny(text, { "tooltip", "tooltips" }) and ContainsAny(text, { "cursor", "mouse", "maus", "mauszeiger", "fixed", "fest", "fixiert", "external", "extern", "addon kontrolliert", "am cursor", "an der maus" })) then
        key = "general.unitTooltipAnchor"
    elseif ContainsAny(text, { "unitframe tooltips", "unit frame tooltips", "unit tooltips", "group frame tooltips", "show tooltips", "tooltips", "tooltip mode", "tooltip visibility", "tooltip anzeigen", "tooltips anzeigen", "tooltip modus", "tooltip sichtbarkeit", "unitframe tooltip anzeigen", "einheiten tooltips", "gruppen tooltips" })
        or (ContainsAny(text, { "tooltip", "tooltips" }) and ContainsAny(text, { "always", "immer", "ooc", "out of combat", "ausserhalb kampf", "modifier", "alt", "ctrl", "strg", "shift", "umschalt", "never", "nie", "niemals", "aus", "an" })) then
        key = "general.unitTooltipMode"
    end
    if not key then return nil end

    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    local value = forcedValue
    if value == nil then value = ValueForRegistrySetting(setting, text, raw) end
    if value == nil then return nil end
    if key == "general.unitTooltipMode" and value == "MODIFIER" then
        local modifierValue = TooltipModifierValueForText(text)
        local modifierSetting = modifierValue and Registry and Registry:GetSetting("general.unitTooltipModifier") or nil
        if modifierSetting then
            return {
                kind = "changes",
                changes = {
                    { setting = setting, value = value, valueLabel = ValueDisplay(setting, value) },
                    { setting = modifierSetting, value = modifierValue, valueLabel = ValueDisplay(modifierSetting, modifierValue) },
                },
                label = "Unit Frame tooltip behavior",
                summary = "Changes the Unit Frame Tooltip mode and modifier key together.",
            }
        end
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, valueLabel = ValueDisplay(setting, value) } },
        label = setting.label or "Miscellaneous option",
        summary = "Changes a Miscellaneous option in MSUF.",
    }
end

local function UnitLoadConditionScopes(text)
    local units = {}
    if HasAllScopeIntent(text) then
        for i = 1, #ALL_UNITFRAMES do units[#units + 1] = ALL_UNITFRAMES[i] end
        return units, true
    end

    local explicitUnits, explicitGroups = ExplicitScopes(text)
    if #explicitGroups > 0 and #explicitUnits == 0 then return units, false end
    for i = 1, #explicitUnits do units[#units + 1] = explicitUnits[i] end
    if #units == 0 then
        local pageUnit = CurrentRegistryPageUnit()
        if pageUnit then
            units[#units + 1] = pageUnit
            return units, true
        end
    end
    return units, #units > 0
end

local function UnitLoadConditionChoices(spec, value)
    local choices = {}
    for i = 1, #ALL_UNITFRAMES do
        local unit = ALL_UNITFRAMES[i]
        local setting = Registry and Registry:GetSetting(tostring(unit) .. "." .. tostring(spec.key))
        if setting then
            choices[#choices + 1] = {
                setting = setting,
                value = value,
                valueLabel = ValueDisplay(setting, value),
                label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, ValueDisplay(setting, value), spec.label) or (tostring(setting.label or spec.label) .. ": " .. ValueDisplay(setting, value)),
            }
        end
    end
    return choices
end

local function ParseUnitLoadConditionShortcut(text)
    local spec = LoadConditionSpecForText(text)
    if not HasUnitLoadConditionIntent(text, spec) then return nil end
    if not spec then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which unit frame visibility rule do you want me to change? MSUF offers Mounted, Out of combat, Solo, In vehicle, In group, In instance, Resting, In combat, and Stealthed.",
            summary = "Asks which unit frame visibility rule to change.",
        }
    end

    local value = HideSettingValueForText(text, true)
    local units, concrete = UnitLoadConditionScopes(text)
    if #units == 0 then
        local choices = UnitLoadConditionChoices(spec, value)
        if #choices == 0 then return nil end
        return {
            kind = "ambiguous",
            choices = choices,
            label = "Which unit frame?",
            summary = "The request matched a unit frame visibility rule but did not name a unit.",
        }
    end

    local changes = {}
    for i = 1, #units do
        AddRegisteredChange(changes, tostring(units[i]) .. "." .. tostring(spec.key), value)
    end
    if #changes == 0 then return nil end
    if #changes > 1 or concrete then
        return {
            kind = "changes",
            changes = changes,
            label = "Unit frame " .. tostring(spec.label),
            bulkSafe = true,
            summary = "Changes unit frame visibility rules.",
        }
    end
    return {
        kind = "ambiguous",
        choices = changes,
        label = "Which unit frame?",
        summary = "The request matched a unit frame visibility rule but did not name a unit.",
    }
end

local function PowerBarScopes(text, unitOnly)
    local units, groups = {}, {}
    if HasAllScopeIntent(text) then
        for i = 1, #POWER_UNIT_ORDER do units[#units + 1] = POWER_UNIT_ORDER[i] end
        if not unitOnly then
            for i = 1, #POWER_GROUP_ORDER do groups[#groups + 1] = POWER_GROUP_ORDER[i] end
        end
        return units, groups, true
    end

    local explicitUnits, explicitGroups = ExplicitScopes(text)
    for i = 1, #explicitUnits do units[#units + 1] = explicitUnits[i] end
    if not unitOnly then
        for i = 1, #explicitGroups do groups[#groups + 1] = explicitGroups[i] end
    end
    if #units == 0 and #groups == 0 then
        local pageUnit = CurrentRegistryPageUnit()
        if pageUnit then units[#units + 1] = pageUnit end
    end
    if #units == 0 and #groups == 0 and not unitOnly and (M and (M.activeKey == "gf_layout" or M.activeKey == "gf_bars" or M.activeKey == "gf_indicators")) then
        local scope = CurrentGroupScopeForRegistry()
        if scope then groups[#groups + 1] = scope end
    end
    return units, groups, (#units + #groups) > 0
end

local function PowerBarBorderBooleanValue(text)
    if ContainsAny(text, {
        "remove border", "remove outline", "without border", "without outline",
        "no border", "no outline", "turn off border", "turn off outline",
        "disable border", "disable outline", "hide border", "hide outline",
        "border off", "outline off", "border aus", "outline aus", "rand aus",
        "ohne rand", "rand entfernen", "rand ausschalten",
    }) then
        return false
    end
    if ContainsAny(text, {
        "add border", "add outline", "with border", "with outline",
        "turn on border", "turn on outline", "enable border", "enable outline",
        "show border", "show outline", "border on", "outline on",
        "border enabled", "outline enabled", "border an", "outline an",
        "rand an", "rand aktivieren", "rand einschalten", "mit rand",
    }) then
        return true
    end
    if ContainsAny(text, { "add", "give", "with", "enable", "show", "an", "aktivieren", "einschalten", "mit" }) then
        return true
    end
    return DetectBoolean(text)
end

local function PowerBarBorderThicknessIntent(text)
    if ContainsAny(text, {
        "thickness", "size", "width", "border thickness", "border size", "border width",
        "outline thickness", "outline size", "outline width",
        "thicker", "thinner", "increase", "decrease", "raise", "lower", "more", "less",
        "bigger", "smaller", "dicker", "duenner", "groesser", "kleiner",
    }) then
        return true
    end
    return FirstNumber(text) ~= nil
end

P.POWER_BAR_EMBED_FALSE_TERMS = {
    "unembed", "unembedded", "do not embed", "dont embed", "not embed", "not embedded",
    "turn off embed", "disable embed", "embed off", "remove embed",
    "outside health", "outside hp", "out of health", "out of hp",
    "separate from health", "separate from hp",
    "aus health", "aus hp",
}

P.POWER_BAR_EMBED_TRUE_TERMS = {
    "embed", "embedded", "embed power bar", "embed power into health",
    "embed power bar into health", "embed power bar into hp",
    "into health", "into hp", "inside health", "inside hp", "within health", "within hp",
}

function P.PowerBarEmbedValue(text)
    if ContainsAny(text, P.POWER_BAR_EMBED_FALSE_TERMS) then return false end
    if ContainsAny(text, P.POWER_BAR_EMBED_TRUE_TERMS) then return true end
    return DetectBoolean(text)
end

function P.ParseDetachedPowerBarRegistryShortcut(text, raw)
    if not ContainsAny(text, { "detached power", "detached power bar", "detached mana", "detached mana bar" }) then return nil end
    if HasClassPowerIntent(text) then return nil end

    local attr
    local label
    local value
    local relativeDelta
    if ContainsAny(text, { "text on bar", "text on detached", "text on detached power", "text on detached power bar", "detached power text on bar" }) then
        attr = "detachedPowerBarTextOnBar"
        label = "Text On Detached Power Bar"
        value = DetectBoolean(text)
        if value == nil then value = true end
    elseif ContainsAny(text, { "frame level", "framelevel", "layer", "strata offset" }) then
        attr = "detachedPowerBarFrameLevelOffset"
        label = "Detached Power Bar Layer"
    elseif ContainsAny(text, { "width", "wide", "wider", "narrower" }) and not ContainsAny(text, { "width mode", "width source" }) then
        attr = "detachedPowerBarWidth"
        label = "Detached Power Bar Width"
    elseif ContainsAny(text, { "height", "tall", "higher", "lower" }) then
        attr = "detachedPowerBarHeight"
        label = "Detached Power Bar Height"
    else
        return nil
    end

    local units = PowerBarScopes(text, true)
    if #units == 0 then return nil end
    local changes = {}
    for i = 1, #units do
        local key = tostring(units[i]) .. "." .. tostring(attr)
        local setting = Registry and Registry:GetSetting(key)
        if setting then
            if setting.type == "number" then
                relativeDelta = RelativeNumberDeltaForText(setting, text)
                value = nil
                if relativeDelta == nil then value = A._NumberValueForText(setting, text) end
            end
            if value ~= nil or relativeDelta ~= nil then AddRegisteredChange(changes, key, value, relativeDelta) end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes detached Power Bar detail options.",
    }
end

local function ParsePowerBarRegistryShortcut(text, raw)
    if not ContainsAny(text, { "power bar", "mana bar", "power border", "mana border", "power outline", "mana outline", "power balken", "mana balken" }) then return nil end
    if HasClassPowerIntent(text) then return nil end

    local changes = {}
    local detachedDetail = P.ParseDetachedPowerBarRegistryShortcut(text, raw)
    if detachedDetail then return detachedDetail end

    if ContainsAny(text, { "detach", "detached", "undock", "attach", "reattach", "dock", "abkoppeln", "ankoppeln" }) then
        local units = PowerBarScopes(text, true)
        for i = 1, #units do
            local setting = Registry and Registry:GetSetting(tostring(units[i]) .. ".powerBarDetached")
            local value = setting and ValueForRegistrySetting(setting, text, raw)
            if value ~= nil then AddRegisteredChange(changes, tostring(units[i]) .. ".powerBarDetached", value) end
        end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = "Detach Power Bar",
                bulkSafe = true,
                summary = "Changes whether the selected Power Bar is detached.",
            }
        end
        return nil
    end

    if ContainsAny(text, { "embed", "embedded", "unembed", "unembedded", "into health", "into hp", "inside health", "inside hp", "within health", "within hp", "outside health", "outside hp", "out of health", "out of hp" }) then
        local value = P.PowerBarEmbedValue(text)
        if value == nil then return nil end
        local units = PowerBarScopes(text, true)
        for i = 1, #units do AddRegisteredChange(changes, tostring(units[i]) .. ".embedPowerBarIntoHealth", value) end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = "Embed Power Bar",
                bulkSafe = #changes > 1,
                summary = "Changes whether the selected Power Bar sits inside the health bar.",
            }
        end
        return nil
    end

    if ContainsAny(text, { "border", "outline", "rand" }) then
        local units = PowerBarScopes(text, true)
        if PowerBarBorderThicknessIntent(text) then
            for i = 1, #units do
                local key = tostring(units[i]) .. ".powerBarBorderThickness"
                local setting = Registry and Registry:GetSetting(key)
                if setting then
                    local relativeDelta = RelativeNumberDeltaForText(setting, text)
                    local value
                    if relativeDelta == nil then value = A._NumberValueForText(setting, text) end
                    if value ~= nil or relativeDelta ~= nil then AddRegisteredChange(changes, key, value, relativeDelta) end
                end
            end
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = "Power Bar border thickness",
                    bulkSafe = true,
                    summary = "Changes per-unit Power Bar Border Thickness.",
                }
            end
        end

        local value = PowerBarBorderBooleanValue(text)
        if value == nil then return nil end
        for i = 1, #units do AddRegisteredChange(changes, tostring(units[i]) .. ".powerBarBorderEnabled", value) end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = "Power Bar border",
                bulkSafe = true,
                summary = "Changes per-unit Power Bar Border toggles.",
            }
        end
        return nil
    end

    if ContainsAny(text, { "height", "hoehe", "higher", "lower", "increase", "decrease", "raise", "reduce", "hoeher", "erhoehe", "erhoehen", "senke", "reduziere" }) then
        local units, groups = PowerBarScopes(text, false)
        for i = 1, #units do
            local setting = Registry and Registry:GetSetting(tostring(units[i]) .. ".powerBarHeight")
            if setting then
                local relativeDelta = RelativeNumberDeltaForText(setting, text)
                local value
                if relativeDelta == nil then value = A._NumberValueForText(setting, text) end
                if value ~= nil or relativeDelta ~= nil then AddRegisteredChange(changes, tostring(units[i]) .. ".powerBarHeight", value, relativeDelta) end
            end
        end
        for i = 1, #groups do
            local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. ".powerHeight")
            if setting then
                local relativeDelta = RelativeNumberDeltaForText(setting, text)
                local value
                if relativeDelta == nil then value = A._NumberValueForText(setting, text) end
                if value ~= nil or relativeDelta ~= nil then AddRegisteredChange(changes, "gf_" .. tostring(groups[i]) .. ".powerHeight", value, relativeDelta) end
            end
        end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = "Power Bar height",
                bulkSafe = true,
                summary = "Changes Power Bar Height.",
            }
        end
        return nil
    end

    if ContainsAny(text, { "smooth", "embed", "embedded", "text", "sync", "anchor", "width", "x", "y", "layer" }) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    local units, groups = PowerBarScopes(text, false)
    for i = 1, #units do AddRegisteredChange(changes, tostring(units[i]) .. ".showPowerBar", value) end
    for i = 1, #groups do AddRegisteredChange(changes, "gf_" .. tostring(groups[i]) .. ".powerBarEnabled", value) end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Power Bar visibility",
        bulkSafe = true,
        summary = "Changes root Power Bar visibility options.",
    }
end

local function ParseCastbarInterruptRegistryShortcut(text)
    if not ContainsAny(text, { "interrupt", "interruptible", "kick", "kickable", "unterbrechen" }) then return nil end
    if ContainsAny(text, { "ready", "tracker", "focus kick", "indicator" }) then return nil end
    local explicitUnits = {}
    local pageUnit
    if not HasAllScopeIntent(text) then
        explicitUnits = ExplicitScopes(text)
        pageUnit = CurrentRegistryPageUnit()
    end
    if not ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) and not explicitUnits[1] and not pageUnit then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end

    local units = {}
    if HasAllScopeIntent(text) then
        for i = 1, #CASTBAR_INTERRUPT_UNITS do units[#units + 1] = CASTBAR_INTERRUPT_UNITS[i] end
    else
        for i = 1, #explicitUnits do units[#units + 1] = explicitUnits[i] end
        if #units == 0 then
            if pageUnit then units[#units + 1] = pageUnit end
        end
    end
    if #units == 0 then return nil end

    local changes = {}
    for i = 1, #units do AddRegisteredChange(changes, tostring(units[i]) .. ".showInterrupt", value) end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Cast Bar interrupt visibility",
        bulkSafe = true,
        summary = "Changes per-unit Show Cast Bar Interrupt options.",
    }
end

P.ColorShortcutValue = function(text, raw)
    local r, g, b, label = ExtractColor(raw, text)
    if not r then return nil end
    return { r = r, g = g, b = b, label = label }, label or "color"
end

P.BuildColorShortcutChange = function(key, value, valueLabel)
    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    return {
        setting = setting,
        value = value,
        valueLabel = valueLabel,
        label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, valueLabel or "color", "MSUF color") or (tostring(setting.label or "MSUF color") .. ": " .. tostring(valueLabel or "color")),
    }
end

P.ColorShortcutResponse = function(changes, title, concrete, summary)
    if #(changes or {}) == 0 then return nil end
    if concrete or #changes == 1 then
        return {
            kind = "changes",
            changes = changes,
            label = title or (changes[1].setting and changes[1].setting.label) or "MSUF color",
            bulkSafe = #changes > 1,
            summary = summary or "Changes an MSUF color option.",
        }
    end
    return {
        kind = "ambiguous",
        choices = changes,
        label = title or "Which MSUF color?",
        summary = summary or "The color request matched multiple MSUF color options.",
    }
end

local DISPEL_TYPE_COLOR_SPECS = {
    { key = "Magic", label = "Magic", terms = { "magic" } },
    { key = "Curse", label = "Curse", terms = { "curse" } },
    { key = "Disease", label = "Disease", terms = { "disease" } },
    { key = "Poison", label = "Poison", terms = { "poison" } },
    { key = "Bleed", label = "Bleed", terms = { "bleed" } },
}

local function DispelTypeColorSpecForText(text)
    for i = 1, #DISPEL_TYPE_COLOR_SPECS do
        local spec = DISPEL_TYPE_COLOR_SPECS[i]
        if ContainsAny(text, spec.terms) then return spec end
    end
    return nil
end

P.ParseDispelTypeColorShortcut = function(text, raw)
    if not ContainsAny(text, { "color", "colors", "colour", "colours" }) then return nil end
    local specificType = DispelTypeColorSpecForText(text)
    local typeColorIntent = ContainsAny(text, {
        "debuff type color", "debuff type colors", "debuff type colour", "debuff type colours",
        "magic debuff color", "magic debuff colour", "magic dispel color", "magic dispel colour",
        "curse debuff color", "curse debuff colour", "curse dispel color", "curse dispel colour",
        "disease debuff color", "disease debuff colour", "disease dispel color", "disease dispel colour",
        "poison debuff color", "poison debuff colour", "poison dispel color", "poison dispel colour",
        "bleed debuff color", "bleed debuff colour", "bleed dispel color", "bleed dispel colour",
    })
    local singleDispelIntent = ContainsAny(text, {
        "dispel color", "dispel colour", "dispel border color", "dispel border colour",
        "single dispel color", "single dispel colour", "all dispel color", "all dispel colour",
    }) and not ContainsAny(text, { "debuff type", "magic", "curse", "disease", "poison", "bleed" })
    if not typeColorIntent and not singleDispelIntent then return nil end

    local value, valueLabel = P.ColorShortcutValue(text, raw)
    if not value then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which color should I use? Examples: 'set magic debuff color blue' or 'set dispel color #33ccff'.",
            summary = "Asks for a concrete dispel color value.",
        }
    end

    local changes = {}
    if specificType then
        AddRegisteredChange(changes, "general.hlDispelColorMode", "TYPE")
        local change = P.BuildColorShortcutChange("general.dispelType" .. specificType.key, value, valueLabel)
        if change then changes[#changes + 1] = change end
        return P.ColorShortcutResponse(changes, specificType.label .. " Dispel Color", true, "Sets Dispel Color Mode to per-type colors and changes that debuff-type color.")
    end

    if typeColorIntent then
        if not HasAllScopeIntent(text) then
            return {
                kind = "answer",
                status = "ambiguous",
                text = "Which debuff type color do you mean: Magic, Curse, Disease, Poison, or Bleed? You can also say 'set all debuff type colors blue'.",
                summary = "Clarifies the debuff type before changing a dispel type color.",
            }
        end
        AddRegisteredChange(changes, "general.hlDispelColorMode", "TYPE")
        for i = 1, #DISPEL_TYPE_COLOR_SPECS do
            local change = P.BuildColorShortcutChange("general.dispelType" .. DISPEL_TYPE_COLOR_SPECS[i].key, value, valueLabel)
            if change then changes[#changes + 1] = change end
        end
        return P.ColorShortcutResponse(changes, "Dispel Type Colors", true, "Sets Dispel Color Mode to per-type colors and changes every debuff-type color.")
    end

    AddRegisteredChange(changes, "general.hlDispelColorMode", "SINGLE")
    local change = P.BuildColorShortcutChange("general.hlDispelColor", value, valueLabel)
    if change then changes[#changes + 1] = change end
    return P.ColorShortcutResponse(changes, "Dispel Color", true, "Sets Dispel Color Mode to single color and changes the shared dispel color.")
end

P.BuildCastbarColorChoices = function(keys, value, valueLabel)
    local changes = {}
    for i = 1, #(keys or {}) do
        local change = P.BuildColorShortcutChange(keys[i], value, valueLabel)
        if change then changes[#changes + 1] = change end
    end
    return changes
end

P.ParseCastbarColorShortcut = function(text, raw)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(text, {
        "castbar", "cast bar", "cast color", "cast colour", "zauberleiste",
        "interrupt color", "interrupt colour", "interrupt feedback", "interrupted cast", "after interrupt",
        "interruptible", "kickable", "unkickable",
        "non interruptible", "noninterruptible", "uninterruptible", "kick ready", "kick not ready",
    }) then return nil end

    local value, valueLabel = P.ColorShortcutValue(text, raw)
    if not value then return nil end
    local key
    if ContainsAny(text, { "not ready", "notready", "cooldown", "on cooldown", "kick cooldown", "interrupt cooldown" })
        and ContainsAny(text, { "kick", "interrupt" }) then
        key = "general.kickNotReadyColor"
    elseif ContainsAny(text, { "ready", "available", "kick ready", "interrupt ready" })
        and ContainsAny(text, { "kick", "interrupt" }) then
        key = "general.kickReadyColor"
    elseif ContainsAny(text, { "text color", "font color", "spell name color", "spell text color", "castbar text", "cast bar text" }) then
        key = "general.castbarFontColor"
    elseif ContainsAny(text, { "border color", "outline color", "castbar border", "cast bar border" }) then
        key = "general.castbarBorderColor"
    elseif ContainsAny(text, { "background color", "bg color", "castbar background", "cast bar background" }) then
        key = "general.castbarBackgroundColor"
    elseif ContainsAny(text, { "player castbar override color", "player castbar custom color", "player cast custom color", "custom player castbar color" }) then
        key = "general.playerCastbarOverrideColor"
    elseif ContainsAny(text, { "non interruptible", "noninterruptible", "not interruptible", "uninterruptible", "unkickable", "not kickable", "cannot interrupt", "cant interrupt" }) then
        key = "general.castbarNonInterruptibleColor"
    elseif ContainsAny(text, { "interrupt feedback", "interrupted cast", "interrupted castbar", "after interrupt", "interrupt color all castbars", "interrupt color for all castbars" }) then
        key = "general.castbarInterruptFeedbackColor"
    elseif ContainsAny(text, { "interruptible", "kickable", "interrupt castbar", "castbar interrupt", "interrupt cast color" }) then
        key = "general.castbarInterruptibleColor"
    end

    if key then
        return P.ColorShortcutResponse(P.BuildCastbarColorChoices({ key }, value, valueLabel), "Castbar color", true, "Changes the Castbar color option.")
    end
    if ContainsAny(text, { "interrupt color", "interrupt colour" }) then
        return P.ColorShortcutResponse(P.BuildCastbarColorChoices({
            "general.castbarInterruptibleColor",
            "general.castbarNonInterruptibleColor",
            "general.castbarInterruptFeedbackColor",
        }, value, valueLabel), "Which castbar interrupt color?", false, "The request mentions interrupt color, which maps to several real Castbar color options.")
    end
    if ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then
        return P.ColorShortcutResponse(P.BuildCastbarColorChoices({
            "general.castbarInterruptibleColor",
            "general.castbarNonInterruptibleColor",
            "general.castbarInterruptFeedbackColor",
            "general.castbarFontColor",
            "general.castbarBorderColor",
            "general.castbarBackgroundColor",
        }, value, valueLabel), "Which castbar color?", false, "The request mentions Castbar color but not the exact Castbar color option.")
    end
    return nil
end

local function HasExplicitFullGroupBorderIntent(text)
    return ContainsAny(text, {
        "group border", "full group border", "whole group border", "outer group border", "group block border",
    })
end

local function HasGroupFrameOutlineColorIntent(text)
    if not ContainsAny(text, {
        "border color", "border colour", "outline color", "outline colour",
        "frame border color", "frame outline color", "bar border color", "bar outline color",
    }) then
        return false
    end
    if HasExplicitFullGroupBorderIntent(text) then return false end
    if ContainsAny(text, {
        "aura", "auras", "buff", "debuff",
        "castbar", "cast bar", "portrait", "power bar", "mana bar",
        "aggro", "threat", "focus", "target", "dispel", "dispellable", "purge", "purgeable", "highlight",
    }) then
        return false
    end
    return ContainsAny(text, {
        "group", "group frame", "group frames",
        "party", "party frame", "party frames",
        "raid", "raid frame", "raid frames", "mythic raid", "mythicraid",
    })
end

local function HasAmbiguousGroupFrameBorderSizeIntent(text)
    if HasExplicitFullGroupBorderIntent(text) then return false end
    if ContainsAny(text, { "opacity", "alpha", "transparent", "transparency", "color", "colour" }) then return false end
    if ContainsAny(text, {
        "bar outline", "frame outline", "outline thickness", "outline size", "outline width",
        "bar border thickness", "bar border size", "bar border width",
        "party frame border", "raid frame border", "mythic raid frame border",
    }) then
        return false
    end
    if not ContainsAny(text, {
        "thickness", "size", "width", "thicker", "thinner", "bigger", "smaller",
        "increase", "decrease", "reduce", "dicker", "duenner",
    }) then
        return false
    end
    if not ContainsAny(text, {
        "group frame border", "group frame outline", "frame border", "frame outline",
        "border thickness", "outline thickness", "border size", "outline size",
        "border width", "outline width",
    }) then
        return false
    end
    if ContainsAny(text, {
        "aura", "auras", "buff", "debuff",
        "castbar", "cast bar", "portrait", "power bar", "mana bar",
        "aggro", "threat", "focus", "target", "dispel", "dispellable", "purge", "purgeable", "highlight",
    }) then
        return false
    end
    return ContainsAny(text, {
        "group", "group frame", "group frames",
        "party", "party frame", "party frames",
        "raid", "raid frame", "raid frames", "mythic raid", "mythicraid",
    })
end

local function BarOutlineScopeForGroup(scope)
    if scope == "party" then return "gf_party" end
    if scope == "raid" or scope == "mythicraid" then return "gf_raid" end
    return nil
end

local function UniqueBarOutlineScopes(groups)
    local out, seen = {}, {}
    for i = 1, #(groups or {}) do
        local scope = BarOutlineScopeForGroup(groups[i])
        if scope and not seen[scope] then
            seen[scope] = true
            out[#out + 1] = scope
        end
    end
    return out
end

P.GROUP_COLOR_TARGETS = {
    { key = "groupBorderColor", title = "Group Border Color", terms = { "group border color", "full group border color", "whole group border color", "outer group border color", "group block border color" } },
    { key = "hlFocusColor", title = "Focus Highlight Color", terms = { "focus highlight color", "focus border color", "focus glow color" } },
    { key = "deadBgColor", title = "Dead Background Color", terms = { "dead background color", "dead member background color", "dead offline background color", "dead bg color" } },
    { key = "bgColor", title = "Backdrop Color", terms = { "group backdrop color", "group background color", "frame background color", "backdrop color", "background color", "bar background color", "hp track color", "health track color", "track color" } },
    { key = "healthCustomColor", title = "Custom Health Color", terms = { "custom health color", "health custom color", "health bar custom color" } },
    { key = "gfDarkColor", title = "Dark Bar Color", terms = { "dark health color", "dark bar color", "dark mode health color" } },
    { key = "gfUnifiedColor", title = "Unified Bar Color", terms = { "unified health color", "unified bar color", "unified color" } },
    { key = "healthBarColor", title = "Health Bar Color", terms = { "health bar color", "health color", "bar color", "hp color", "hp bar color" } },
}

P.HasGroupFrameColorIntent = function(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return false end
    if not ContainsAny(text, { "color", "colors", "colour", "colours", "farbe", "farben", "tint" }) then return false end
    return ContainsAny(text, {
        "group", "group frame", "group frames", "groupframe", "groupframes", "gruppenframe", "gruppenframes",
        "party", "party frame", "party frames", "raid", "raid frame", "raid frames", "mythic raid", "mythicraid",
    })
end

P.GroupColorTargetForText = function(text)
    for i = 1, #P.GROUP_COLOR_TARGETS do
        local row = P.GROUP_COLOR_TARGETS[i]
        if ContainsAny(text, row.terms) then return row end
    end
    return nil
end

P.GroupColorScopesForText = function(text)
    if HasAllScopeIntent(text) then return { "party", "raid", "mythicraid" }, true end
    local groups = {}
    if HasPhrase(text, "party") or HasPhrase(text, "party frame") or HasPhrase(text, "party frames") then groups[#groups + 1] = "party" end
    local mythic = HasPhrase(text, "mythicraid") or HasPhrase(text, "mythic raid") or HasPhrase(text, "mythic raid frame") or HasPhrase(text, "mythic raid frames")
    if mythic then groups[#groups + 1] = "mythicraid" end
    if (HasPhrase(text, "raid") or HasPhrase(text, "raid frame") or HasPhrase(text, "raid frames") or HasPhrase(text, "schlachtzug")) and not mythic then
        groups[#groups + 1] = "raid"
    end
    if #groups > 0 then return groups, true end
    if GROUP_AVAILABILITY_PAGES[M and M.activeKey] then
        local current = CurrentGroupScopeForRegistry()
        if current then return { current }, true end
    end
    return { "party", "raid", "mythicraid" }, false
end

P.ParseGroupFrameOutlineColorShortcut = function(text, raw)
    if not HasGroupFrameOutlineColorIntent(text) then return nil end
    local value, valueLabel = P.ColorShortcutValue(text, raw)
    if not value then return nil end

    local groups = DetectGroups(text)
    local concrete = #groups > 0
    if not concrete and HasAllScopeIntent(text) then
        groups, concrete = { "party", "raid" }, true
    end

    if not concrete then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which group frame border color do you mean: Party or Raid/Mythic Raid bar outline? If you meant the optional border around the whole group block, say 'set raid group border color to red'.",
            summary = "Clarifies group frame border color instead of guessing Party.",
        }
    end

    local barScopes = UniqueBarOutlineScopes(groups)
    local changes = {}
    for i = 1, #barScopes do
        local change = P.BuildColorShortcutChange("barScope." .. tostring(barScopes[i]) .. ".barOutlineColor", value, valueLabel)
        if change then changes[#changes + 1] = change end
    end
    return P.ColorShortcutResponse(changes, "Group Frame Outline Color", concrete, "Changes scoped Bar Outline Color for group frames.")
end

P.ParseGroupFrameColorShortcut = function(text, raw)
    if not P.HasGroupFrameColorIntent(text) then return nil end
    local target = P.GroupColorTargetForText(text)
    if not target then return nil end
    local value, valueLabel = P.ColorShortcutValue(text, raw)
    if not value then return nil end
    local scopes, concrete = P.GroupColorScopesForText(text)
    local changes = {}
    for i = 1, #(scopes or {}) do
        local change = P.BuildColorShortcutChange("gf_" .. tostring(scopes[i]) .. "." .. target.key, value, valueLabel)
        if change then changes[#changes + 1] = change end
    end
    return P.ColorShortcutResponse(changes, target.title, concrete, "Changes a Group Frame color option.")
end

local STATUS_TEST_UNITS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }

local function StatusTestModeValue(text)
    if ContainsAny(text, { "off", "disable", "disabled", "hide", "stop", "clear", "aus", "deaktivieren", "ausschalten", "ausblenden" }) then
        return false
    end
    if ContainsAny(text, { "on", "enable", "enabled", "show", "test", "preview", "an", "aktivieren", "einschalten", "anzeigen" }) then
        return true
    end
    return nil
end

local function ParseStatusIconTestModeRegistryShortcut(text)
    if not ContainsAny(text, {
        "status icon", "status icons", "status indicator", "status indicators",
        "status preview", "test status", "test mode",
    }) then return nil end
    if not ContainsAny(text, { "test", "preview", "test mode", "status preview" }) then return nil end
    if ContainsAny(text, { "show all", "all indicators", "all status icons", "preview all", "current indicator", "preview current" }) then return nil end

    local value = StatusTestModeValue(text)
    if value == nil then return nil end
    local units = {}
    if HasAllScopeIntent(text) then
        for i = 1, #STATUS_TEST_UNITS do units[#units + 1] = STATUS_TEST_UNITS[i] end
    else
        local explicitUnits = ExplicitScopes(text)
        for i = 1, #explicitUnits do units[#units + 1] = explicitUnits[i] end
        if #units == 0 then
            local pageUnit = CurrentRegistryPageUnit()
            if pageUnit then units[#units + 1] = pageUnit end
        end
    end
    if #units == 0 then return nil end

    local changes = {}
    for i = 1, #units do AddRegisteredChange(changes, tostring(units[i]) .. ".stateIconsTestMode", value) end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Status Icon Test Mode",
        bulkSafe = true,
        summary = "Changes per-unit Status Icon Test Mode toggles.",
    }
end

function P.ParseGroupBooleanRegistryShortcut(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    local explicitUnits = DetectUnits(text)
    local explicitGroups = DetectGroups(text)
    if #explicitUnits > 0 then return nil end
    local attr
    local label
    local value = DetectBoolean(text)

    if ContainsAny(text, {
        "hide name on dead", "hide name when dead", "hide name on offline", "hide name when offline",
        "hide name on dead or offline", "hide name when dead or offline", "dead or offline",
    }) then
        attr = "hideNameOnDeadOffline"
            label = "Hide Name on Dead or Offline"
        if ContainsAny(text, { "turn off", "disable", "disabled", "deactivate", "deactivated", "ausschalten", "deaktivieren" }) then
            value = false
        else
            value = true
        end
    elseif ContainsAny(text, { "reverse hp text", "hp text reverse", "reverse health text", "health text reverse" }) then
        attr = "hpTextReverse"
        label = "Reverse HP Text"
        if value == nil then value = true end
    elseif ContainsAny(text, { "group number", "group index", "group number label" })
        and not ContainsAny(text, { "size", "font size", "anchor", "x offset", "y offset", "offset", "color", "colour", "style" })
        and not ContainsAny(text, {
            "move", "nudge", "shift", "position", "right", "left", "up", "down", "oben", "unten", "links", "rechts",
            "bigger", "larger", "smaller", "increase", "decrease", "reduce", "grow", "shrink", "groesser", "kleiner",
        })
        and FirstNumber(text) == nil
    then
        attr = "showGroupNumber"
        label = "Group Number"
        if value == nil then value = true end
    else
        return nil
    end

    if value == nil then return nil end
    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. "." .. attr, value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, label, "Changes a Group Frame boolean option.")
end

function P.ParseUnitHPTextReverseShortcut(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(text, {
        "reverse hp text", "hp text reverse", "reverse health text", "health text reverse",
        "reverse hp text order", "hp text reverse order", "reverse health text order", "health text reverse order",
    }) then return nil end

    local explicitUnits, explicitGroups = ExplicitScopes(text)
    local hasUnitFrameIntent = ContainsAny(text, { "unitframe", "unit frame", "unitframes", "unit frames" })
    local hasGroupFrameIntent = ContainsAny(text, { "group frame", "group frames", "groupframe", "groupframes" })
    if #explicitUnits == 0 and hasGroupFrameIntent and not hasUnitFrameIntent then return nil end
    if #explicitGroups > 0 and #explicitUnits == 0 and not hasUnitFrameIntent then return nil end

    local value = DetectBoolean(text)
    if value == nil then value = true end

    local units = {}
    local concrete = false
    if HasAllScopeIntent(text) and hasUnitFrameIntent then
        for i = 1, #POWER_UNIT_ORDER do units[#units + 1] = POWER_UNIT_ORDER[i] end
        concrete = true
    else
        for i = 1, #explicitUnits do units[#units + 1] = explicitUnits[i] end
        concrete = #units > 0
        if #units == 0 then
            local pageUnit = CurrentRegistryPageUnit()
            if pageUnit then
                units[#units + 1] = pageUnit
                concrete = true
            end
        end
    end

    local changes = {}
    if #units == 0 then
        for i = 1, #POWER_UNIT_ORDER do
            AddRegisteredChange(changes, tostring(POWER_UNIT_ORDER[i]) .. ".hpTextReverse", value)
        end
        if #changes == 0 then return nil end
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Which unit frame?",
            summary = "The request matched reverse HP text order but did not name a unit frame.",
        }
    end

    for i = 1, #units do
        AddRegisteredChange(changes, tostring(units[i]) .. ".hpTextReverse", value)
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Unit frame reverse HP text order",
        bulkSafe = #changes > 1,
        summary = "Changes reverse HP text order for unit frames.",
    }
end

function P.LooksLikeExactKeyLookup(text)
    local norm = Normalize(text)
    if norm == "" then return false end
    return norm:find("what is ", 1, true) == 1
        or norm:find("what are ", 1, true) == 1
        or norm:find("explain ", 1, true) == 1
        or norm:find("where is ", 1, true) == 1
        or norm:find("where are ", 1, true) == 1
        or norm:find("where ", 1, true) == 1
        or norm:find("find ", 1, true) == 1
        or norm:find("search ", 1, true) == 1
        or norm:find("help ", 1, true) == 1
        or norm:find("how do ", 1, true) == 1
        or norm:find("how ", 1, true) == 1
        or norm:find("why ", 1, true) == 1
        or norm:find("wo ist ", 1, true) == 1
        or norm:find("wo ", 1, true) == 1
        or norm:find("suche ", 1, true) == 1
        or norm:find("finde ", 1, true) == 1
        or norm:find("hilfe ", 1, true) == 1
        or norm:find("erklaere ", 1, true) == 1
        or norm:find("warum ", 1, true) == 1
        or norm:find("wie ", 1, true) == 1
end

function P.ParseExactRegistryKeyShortcut(text, raw)
    if P.LooksLikeExactKeyLookup(raw or text) then return nil end
    local hay = tostring(raw or text or ""):lower()
    if not hay:find("[%a_][%w_]*%.") then return nil end
    local settings = Registry and Registry:AllSettings() or {}
    local bestSetting
    local bestKeyLen = 0
    local bestKeyEnd
    for i = 1, #settings do
        local setting = settings[i]
        local key = tostring(setting and setting.key or "")
        local keyLower = key:lower()
        local startPos = keyLower ~= "" and hay:find(keyLower, 1, true) or nil
        local before = startPos == nil or startPos == 1 or not hay:sub(startPos - 1, startPos - 1):match("[%w_]")
        local afterIndex = startPos and (startPos + #keyLower) or nil
        local after = afterIndex == nil or afterIndex > #hay or not hay:sub(afterIndex, afterIndex):match("[%w_]")
        if startPos and before and after then
            local frameType = tostring(setting.frameType or "")
            local attrLower = tostring(setting.attribute or ""):lower()
            if frameType ~= "aura" and frameType ~= "groupAura"
                and not keyLower:find("shape", 1, true)
                and not keyLower:find("rounded", 1, true)
                and not attrLower:find("shape", 1, true)
                and not attrLower:find("rounded", 1, true)
            then
                if #keyLower > bestKeyLen then
                    bestSetting = setting
                    bestKeyLen = #keyLower
                    bestKeyEnd = startPos + #keyLower - 1
                end
            end
        end
    end
    if bestSetting then
        local rawText = tostring(raw or text or "")
        local exactTail = bestKeyEnd and P._StripExactValueConnector(rawText:sub(bestKeyEnd + 1)) or ""
        local value
        if bestSetting.type == "enum" then value = P._ExactEnumValueForText(bestSetting, exactTail) end
        if value == nil then value = ValueForRegistrySetting(bestSetting, text, raw) end
        if value == nil and bestSetting.type == "string" then value = ExplicitFreeformValue(raw or text) end
        local relativeDelta
        if value == nil and bestSetting.type == "number" then
            relativeDelta = RelativeNumberDeltaForText(bestSetting, text)
            if not RelativeNumberDeltaAllowedForSetting(bestSetting, text, relativeDelta) then relativeDelta = nil end
        end
        if value ~= nil or relativeDelta ~= nil then
            return {
                kind = "changes",
                changes = {
                    {
                        setting = bestSetting,
                        value = value,
                        relativeDelta = relativeDelta,
                        valueLabel = value ~= nil and ValueDisplay(bestSetting, value) or nil,
                    },
                },
                label = type(A.DisplaySettingLabel) == "function" and A.DisplaySettingLabel(bestSetting) or bestSetting.label or "MSUF option",
                summary = "Changes the matching MSUF option.",
            }
        end
        return MissingValueResponse({ { setting = bestSetting, score = 100 } }, raw)
    end
    return nil
end

function P.ParseGroupNumberRegistryShortcut(text)
    if ContainsAny(text, { "aura", "auras", "buff" }) then return nil end
    local attr
    local label
    if ContainsAny(text, { "group number", "group index", "group number label" })
        and ContainsAny(text, { "size", "font size", "scale", "bigger", "larger", "smaller", "increase", "decrease", "reduce", "grow", "shrink", "groesser", "kleiner" })
    then
        attr = "groupNumberSize"
        label = "Group Number Size"
    elseif ContainsAny(text, { "group border padding", "border padding", "padding around", "padding around frames", "padding around group", "frame padding" }) then
        attr = "groupBorderPadding"
        label = "Group Border Padding"
    elseif HasAmbiguousGroupFrameBorderSizeIntent(text) then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Group frame border thickness can mean the scoped bar outline or the optional border around the whole group block. Say 'set raid frame outline thickness to 2' for the bar outline, or 'set raid group border thickness to 2' for the full group border.",
            summary = "Clarifies group frame border thickness instead of changing the wrong border.",
        }
    elseif HasExplicitFullGroupBorderIntent(text)
        and ContainsAny(text, { "thickness", "size", "border size", "border thickness", "thicker", "thinner", "increase", "decrease", "reduce", "bigger", "smaller", "dicker", "duenner" })
    then
        attr = "groupBorderSize"
        label = "Group Border Thickness"
    elseif ContainsAny(text, { "power height", "power bar height", "mana height", "mana bar height" }) then
        attr = "powerHeight"
        label = "Power Bar Height"
    elseif ContainsAny(text, { "debuff stripe height", "debuff stripe size" }) then
        attr = "debuffStripeHeight"
        label = "Debuff Stripe Height"
    else
        return nil
    end

    local explicitGroups = DetectGroups(text)
    local activePage = M and M.activeKey
    local groupPage = activePage == "gf_layout" or activePage == "gf_bars" or activePage == "gf_indicators"
    if #explicitGroups == 0 and not groupPage and not ContainsAny(text, { "group frame", "group frames", "all group", "all groups" }) then return nil end
    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        local key = "gf_" .. tostring(scopes[i]) .. "." .. attr
        local setting = Registry and Registry:GetSetting(key)
        local relativeDelta = setting and setting.type == "number" and RelativeNumberDeltaForText(setting, text) or nil
        if not RelativeNumberDeltaAllowedForSetting(setting, text, relativeDelta) then relativeDelta = nil end
        local value
        if relativeDelta == nil then value = FirstNumber(text) end
        if value ~= nil or relativeDelta ~= nil then AddRegisteredChange(changes, key, value, relativeDelta) end
    end
    return P.GroupShortcutResponse(text, changes, concrete, label, "Changes a Group Frame numeric option.")
end

local function ParseRepeatedRegistryShortcut(text, raw)
    return P.ParseExactRegistryKeyShortcut(text, raw)
        or ParseScopedFontTextColorShortcut(text)
        or P.ParseDispelTypeColorShortcut(text, raw)
        or P.ParseCastbarColorShortcut(text, raw)
        or P.ParseInterruptReadyRegistryShortcut(text, raw)
        or P.ParseUnitStatusSymbolRegistryShortcut(text)
        or P.ParseCastbarBackendShortcut(text)
        or P.ParseCastbarPositionRegistryShortcut(text)
        or (P.ParseFocusKickRegistryShortcut and P.ParseFocusKickRegistryShortcut(text))
        or P.ParsePowerBarGradientRegistryShortcut(text)
        or P.ParseGroupFrameOutlineColorShortcut(text, raw)
        or P.ParseGroupFrameColorShortcut(text, raw)
        or P.ParseAlphaExcludeTextPortraitShortcut(text)
        or P.ParseUnitHPTextReverseShortcut(text)
        or P.ParseGroupRolePowerVisibilityShortcut(text)
        or P.ParseGroupRoleIconVisibilityShortcut(text)
        or P.ParseGroupOfflineAlphaShortcut(text)
        or P.ParseGroupHealthFadeShortcut(text)
        or P.ParseGroupColumnLayoutShortcut(text)
        or P.ParseGroupPreserveRaidGroupsShortcut(text)
        or P.ParseGroupPlayerFirstInRoleShortcut(text)
        or P.ParseGroupAggroRoleFilterShortcut(text)
        or P.ParseGroupBooleanRegistryShortcut(text)
        or P.ParseGroupNumberRegistryShortcut(text)
        or P.ParseGroupSortShortcut(text)
        or P.ParseGroupScaleModeShortcut(text)
        or P.ParseGroupOfflineDelayShortcut(text)
        or P.ParseDependentTargetFrameVisibilityShortcut(text)
        or ParseUnitLoadConditionShortcut(text)
        or ParsePowerBarRegistryShortcut(text, raw)
        or ParseStatusIconTestModeRegistryShortcut(text)
        or ParseCastbarInterruptRegistryShortcut(text)
end

P.ParseRegistryAliasCandidates = function(text, raw, settings, suppressNoMatch)
    local changes = {}
    local missingValue = {}
    local bestScore = 0
    for i = 1, #settings do
        if i % 8 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local setting = settings[i]
        local score = SettingMatchScore(setting, text)
        if score > 0 and A.Knowledge and type(A.Knowledge.SettingPageBoost) == "function" then
            score = score + A.Knowledge.SettingPageBoost(setting)
        end
        if score > 0 then
            local handledMedia = false
            if setting.type == "string" then
                handledMedia = AddMediaResolverChanges(changes, setting, text, raw, score)
            end
            if not handledMedia then
                local relativeDelta = setting.type == "number" and RelativeNumberDeltaForText(setting, text) or nil
                if not RelativeNumberDeltaAllowedForSetting(setting, text, relativeDelta) then relativeDelta = nil end
                local value
                if relativeDelta == nil then value = ValueForRegistrySetting(setting, text, raw) end
                if value ~= nil or relativeDelta ~= nil then
                    changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, matchScore = score }
                    if score > bestScore then bestScore = score end
                else
                    local freeform = setting.type == "enum" and ExplicitFreeformValue(raw) or nil
                    local customSetting = freeform and CustomSiblingForSetting(setting) or nil
                    if customSetting then
                        changes[#changes + 1] = {
                            setting = customSetting,
                            value = freeform,
                            matchScore = score,
                            valueLabel = freeform,
                            label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(customSetting, freeform, setting and setting.label or "Custom option") or (tostring(customSetting.label or setting.label or "Custom option") .. ": " .. tostring(freeform)),
                        }
                        if score > bestScore then bestScore = score end
                    elseif setting.type ~= "boolean" then
                        missingValue[#missingValue + 1] = { setting = setting, score = score }
                    end
                end
            else
                if score > bestScore then bestScore = score end
            end
        end
    end
    if #changes == 0 then
        if suppressNoMatch then return nil end
        return MissingValueResponse(missingValue, raw) or RegistrySuggestions(text, raw, settings)
    end
    if #changes == 1 and changes[1].mediaNoMatch then
        local resolver = A.MediaResolver
        local textOut = resolver and resolver.NoMatchMessage and resolver.NoMatchMessage(changes[1].mediaType, changes[1].mediaQuery) or "That media entry is not in the current list."
        return { kind = "unknown", text = textOut, status = "failed" }
    end
    local usable = {}
    for i = 1, #changes do
        if not changes[i].mediaNoMatch then usable[#usable + 1] = changes[i] end
    end
    changes = usable
    if #changes == 0 then return nil end
    if #changes > 1 and ShouldApplyMultipleRegistryChanges(text, changes) then
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = P.AreBulkSafeAuraSettingChanges and P.AreBulkSafeAuraSettingChanges(changes) or nil,
            label = "Multiple matching options",
            summary = "Changes multiple matched options.",
        }
    end
    if #changes > 1 and bestScore > 0 then
        local filtered = {}
        for i = 1, #changes do
            if changes[i].matchScore == bestScore then filtered[#filtered + 1] = changes[i] end
        end
        if #filtered == 1 then changes = filtered end
        if #filtered > 1 and ShouldApplyMultipleRegistryChanges(text, filtered) then changes = filtered end
    end
    if #changes > 1 and ShouldApplyMultipleRegistryChanges(text, changes) then
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = P.AreBulkSafeAuraSettingChanges and P.AreBulkSafeAuraSettingChanges(changes) or nil,
            label = "Multiple matching options",
            summary = "Changes multiple matched options.",
        }
    end
    if #changes > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching options",
        }
    end
    local setting = changes[1].setting
    return {
        kind = "changes",
        changes = changes,
        label = setting and setting.label or "Assistant option change",
        summary = "MSUF options change.",
    }
end

local FULL_REGISTRY_ALIAS_FALLBACK_TERMS = {
    "player", "target", "focus", "pet", "boss", "party", "raid", "mythicraid", "mythic raid",
    "unitframe", "unitframes", "unit frame", "unit frames", "frame", "frames", "group", "group frames",
    "castbar", "cast bar", "aura", "buff", "debuff", "profile", "class power", "class resource",
    "health", "hp", "power", "mana", "name", "text", "font", "bar", "portrait", "indicator", "status icon",
    "width", "height", "size", "scale", "opacity", "alpha", "color", "colour", "offset", "x offset", "y offset",
    "position", "anchor", "spacing", "gap", "layer", "z layer", "filter", "cooldown", "stack", "border",
    "show", "hide", "enable", "disable", "turn on", "turn off", "move", "set", "change", "make",
}

local FULL_REGISTRY_ALIAS_SUBJECT_TERMS = {
    "player", "target", "focus", "pet", "boss", "party", "raid", "mythicraid", "mythic raid",
    "unitframe", "unitframes", "unit frame", "unit frames", "frame", "frames", "group", "group frames",
    "castbar", "cast bar", "aura", "auras", "buff", "buffs", "debuff", "debuffs", "profile",
    "class power", "class resource", "resource", "gameplay", "crosshair", "totem",
    "health", "hp", "power", "mana", "name", "text", "font", "bar", "bars", "portrait",
    "indicator", "status icon", "icon", "tooltip", "minimap", "language", "module",
    "width", "height", "size", "scale", "opacity", "alpha", "offset", "x offset", "y offset",
    "position", "anchor", "spacing", "gap", "layer", "z layer", "filter", "cooldown", "stack", "border",
}

local function ShouldTryFullRegistryAliasFallback(text)
    if FirstNumber(text) ~= nil then return true end
    if not ContainsAny(text, FULL_REGISTRY_ALIAS_FALLBACK_TERMS) then return false end
    return ContainsAny(text, FULL_REGISTRY_ALIAS_SUBJECT_TERMS)
end

local function ParseRegistryAliasCandidatesWithFuzzy(text, raw, settings)
    local previous = P._allowFuzzyAliasMatch
    P._allowFuzzyAliasMatch = true
    local ok, result = pcall(P.ParseRegistryAliasCandidates, text, raw, settings)
    P._allowFuzzyAliasMatch = previous
    if not ok then error(result) end
    return result
end

local function ParseTargetInlinePartialAmbiguity(text)
    text = Normalize(text)
    if not ContainsAny(text, { "inline" }) then return nil end
    if ContainsAny(text, { "inline text", "target target inline text", "target of target inline text", "separator", "seperator", "delimiter" }) then return nil end
    if not ContainsAny(text, { "target of target", "targettarget", "target inline", "target target", "tot" }) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    local setting = Registry and Registry.GetSetting and Registry:GetSetting("targettarget.showToTInTargetName") or nil
    if not setting then return nil end
    return {
        kind = "ambiguous",
        choices = {
            {
                setting = setting,
                value = value,
                label = "Target Target Inline Text: " .. (value and "enabled" or "disabled"),
            },
        },
        label = "Target of Target inline option needs clarification",
        summary = "Asks before applying a partial Target of Target inline request.",
    }
end

local function ParseRegistryAlias(text, raw)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(raw or text) then return nil end
    local partialInline = ParseTargetInlinePartialAmbiguity(text)
    if partialInline then return partialInline end
    local exactAlias = P.ParseRegistryExactAliasShortcut and P.ParseRegistryExactAliasShortcut(text, raw)
    if exactAlias then return exactAlias end
    local repeated = ParseRepeatedRegistryShortcut(text, raw)
    if repeated then return repeated end
    local groupAvailability = ParseGroupAvailabilityIntent(text)
    if groupAvailability then return groupAvailability end

    local allSettings = Registry and Registry:AllSettings() or {}
    local lightSettings = P.RegistryCandidateSettings(text, allSettings, false)
    local result = P.ParseRegistryAliasCandidates(text, raw, lightSettings)
    if result then return result end
    local actionable = ActionableText and ActionableText(text) or text
    if actionable ~= text then
        local actionableLightSettings = P.RegistryCandidateSettings(actionable, allSettings, false)
        result = P.ParseRegistryAliasCandidates(actionable, raw, actionableLightSettings, true)
        if result then return result end
    end
    if (tonumber(P._compoundDepth) or 0) > 0 then return nil end

    local fallbackText = actionable ~= text and actionable or text
    local _, fallbackTokens = MeaningTokens(AliasRelationText(fallbackText))
    if #fallbackTokens == 0 then return nil end
    if not (ShouldTryFullRegistryAliasFallback(text) or (actionable ~= text and ShouldTryFullRegistryAliasFallback(actionable))) then return nil end

    local fullSettings = P.RegistryCandidateSettings(fallbackText, allSettings, true)
    if fullSettings ~= lightSettings then
        return ParseRegistryAliasCandidatesWithFuzzy(fallbackText, raw, fullSettings)
    end
    return nil
end

local function ScopedOnlyKind(text)
    if not ContainsAny(text, { "only", "nur", "just" }) then return nil end
    if ContainsAny(text, { "current health only", "on current health only", "on health only" }) then return nil end
    if ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end
    if ContainsAny(text, {
        "font", "fonts", "schrift", "text outline", "font outline", "text shadow",
        "name color", "name text color", "name shortening", "text size",
        "text color", "color text", "health text color", "hp text color",
        "power text color", "mana text color", "resource text color",
        "color text by power", "color text by health",
    }) then
        return "fonts"
    end
    if ContainsAny(text, { "bars", "bar", "bar texture", "health bar", "hp bar", "power bar", "gradient", "absorb", "outline", "border", "dispel", "aggro", "purge" }) then
        return "globalBars"
    end
    return nil
end

local function ScopedOnlyOverrideKey(kind, scope)
    if kind == "fonts" then return "fontScope." .. tostring(scope or "") .. ".override" end
    if kind == "globalBars" then return "barScope." .. tostring(scope or "") .. ".override" end
    return nil
end

local function ParseScopedOnlyOverride(text, raw)
    local kind = ScopedOnlyKind(text)
    if not kind then return nil end
    local scope = DetectGlobalScope(text)
    if not scope or scope == "shared" then return nil end
    local matchText = " " .. text .. " "
    matchText = matchText:gsub(" only ", " "):gsub(" just ", " "):gsub(" nur ", " ")
    if kind == "globalBars" then
        matchText = matchText:gsub(" bars ", " ")
    elseif kind == "fonts" then
        matchText = matchText:gsub(" fonts ", " font ")
    end
    matchText = Normalize(matchText)

    local candidates = Registry and Registry:FindSettings({ unit = scope, frameType = kind }) or {}
    local changes = {}
    local bestScore = 0
    local overrideKey = ScopedOnlyOverrideKey(kind, scope)
    local overrideSetting = overrideKey and Registry and Registry:GetSetting(overrideKey)

    for i = 1, #candidates do
        local setting = candidates[i]
        if setting and setting.key ~= overrideKey then
            local score = math.max(SettingMatchScore(setting, text), SettingMatchScore(setting, matchText))
            if score > 0 then
                local relativeDelta = setting.type == "number" and RelativeNumberDeltaForText(setting, matchText) or nil
                if not RelativeNumberDeltaAllowedForSetting(setting, text, relativeDelta) then relativeDelta = nil end
                local value
                if relativeDelta == nil then value = ValueForRegistrySetting(setting, matchText, raw) end
                if value ~= nil or relativeDelta ~= nil then
                    changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, matchScore = score }
                    if score > bestScore then bestScore = score end
                end
            end
        end
    end

    if #changes > 1 and bestScore > 0 then
        local filtered = {}
        for i = 1, #changes do
            if changes[i].matchScore == bestScore then filtered[#filtered + 1] = changes[i] end
        end
        changes = filtered
    end

    if #changes == 0 then
        local value = DetectBoolean(text)
        if value == nil then return nil end
        if not overrideSetting then return nil end
        return {
            kind = "changes",
            changes = { { setting = overrideSetting, value = value } },
            label = overrideSetting.label or "Scoped override",
            summary = "Uses ONLY for target-specific Bars or Fonts.",
        }
    end

    if #changes > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching target-specific options",
        }
    end

    if overrideSetting then
        table.insert(changes, 1, { setting = overrideSetting, value = true })
    end
    local setting = changes[#changes].setting
    return {
        kind = "changes",
        changes = changes,
        label = setting and setting.label or "Scoped override option",
        summary = "Enables the target-specific Bars or Fonts override before applying the requested option.",
    }
end

P.SettingMatchesText = SettingMatchesText
P.SettingMatchScore = SettingMatchScore
P.RegistrySettingMayMatchExactAlias = function(setting, text)
    if RootFrameEnabledBlockedByDetail(setting, text) then return false end
    if AuraLaneVisibilityBlockedByDetail(setting, text) then return false end
    return SettingAllowedByExplicitScopes(setting, text)
end
P.EnumValueForText = EnumValueForText
P.StringValueForText = StringValueForText
P.ExplicitFreeformValue = ExplicitFreeformValue
P.CustomSiblingForSetting = CustomSiblingForSetting
P.ValueDisplay = ValueDisplay
P.MissingValueResponse = MissingValueResponse
P.MeaningTokens = MeaningTokens
P.PartialPhraseScore = PartialPhraseScore
P.SettingPartialSuggestionScore = SettingPartialSuggestionScore
P.ParseGroupAvailabilityIntent = ParseGroupAvailabilityIntent
P.RegistrySuggestions = RegistrySuggestions
P.RELATIVE_INCREASE_TERMS = RELATIVE_INCREASE_TERMS
P.RELATIVE_DECREASE_TERMS = RELATIVE_DECREASE_TERMS
P.RelativeNumberDeltaForText = RelativeNumberDeltaForText
P.NumberSettingSupportsBooleanToggle = NumberSettingSupportsBooleanToggle
P.BooleanValueForNumberSetting = BooleanValueForNumberSetting
P.ValueForRegistrySetting = ValueForRegistrySetting
P.AddMediaResolverChanges = AddMediaResolverChanges
P.ParseUnitLoadConditionShortcut = ParseUnitLoadConditionShortcut
P.ParseRegistryAlias = ParseRegistryAlias
P.ParseScopedFontTextColorShortcut = ParseScopedFontTextColorShortcut
P.ScopedOnlyKind = ScopedOnlyKind
P.ScopedOnlyOverrideKey = ScopedOnlyOverrideKey
P.ParseScopedOnlyOverride = ParseScopedOnlyOverride
