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
local Data = A.ParserData or {}
A.ParserData = Data
local RegistryData = Data.REGISTRY_PARSER or {}
local RegistryPhrases = RegistryData.PHRASES or {}
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

local function SettingAllowsAnyIntentScope(setting, scopes)
    local allowed = type(setting) == "table" and setting.intentScopes or nil
    if type(allowed) ~= "table" or #(scopes or {}) == 0 then return false end
    for i = 1, #scopes do
        if ListContains(allowed, scopes[i]) then return true end
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
    if settingKey:find("bosstarget", 1, true) and ContainsAny(text, RegistryPhrases[1]) then return text end
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

function P.HasExactPhraseInList(text, phrases)
    for i = 1, #(phrases or {}) do
        if HasPhrase(text, phrases[i]) then return true end
    end
    return false
end

local function HasAllScopeIntent(text)
    -- Bulk scope is a write-safety boundary. A typo-tolerant fuzzy match must
    -- never turn an unrelated noun into permission to change every scope.
    return P.HasExactPhraseInList(text, RegistryPhrases[2])
end

P.ExplicitAuraFilterScope = P.ExplicitAuraFilterScope or function(text)
    if not (ContainsAny(text, RegistryPhrases[3]) and ContainsAny(text, RegistryPhrases[4])) then return nil end
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
    "dot", "dots", "ellipsis", "ellipses",
    "icon", "icons", "marker", "markers", "raid marker", "target marker", "symbol", "symbols",
    "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull",
    "portrait", "portraits", "power bar", "mana bar",
    "health bar", "hp bar", "castbar", "cast bar", "name", "names", "text", "border", "outline",
    "alpha", "opacity", "range fade", "offline", "solo", "sort", "sorting", "role", "scale", "scaling",
    -- ContainsAny matches whole words, so every singular above needed its
    -- plural too: "turn off borders for party frame" was not covered by
    -- "border" and disabled the party frames.
    "borders", "outlines", "texts", "castbars", "cast bars", "power bars", "mana bars",
    "health bars", "hp bars", "scales", "markers", "symbols",
    -- Parts of a frame that had no entry here at all, so a request about one of
    -- them could still be answered by switching the whole frame off.
    "highlight", "highlights", "aggro", "threat", "dispel", "purge",
    "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    "gradient", "texture", "color", "colour", "font",
    "round", "rounded", "corner", "corners", "shape",
    "spacing", "padding", "column", "columns", "growth", "position", "offset",
}

local function RootFrameEnabledBlockedByDetail(setting, text)
    if not (setting and setting.attribute == "enabled") then return false end
    if setting.frameType ~= "unitframe" and setting.frameType ~= "group" then return false end
    return ContainsAny(text, ROOT_FRAME_ENABLED_DETAIL_TERMS)
end

-- Shared with the followup lane. Two lanes can write a frame's root "enabled"
-- toggle, they each kept their own idea of "this sentence is about a detail,
-- not the frame", and the shorter list let "turn off highlight borders for
-- party frame" disable the player's party frames outright.
function P.TextNamesFrameDetail(text)
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
    if ContainsAny(text, RegistryPhrases[5])
        and not ContainsAny(text, RegistryPhrases[6])
    then
        return true
    end
    return false
end

local function ClassPowerMentionIsNegated(text)
    return ContainsAny(text, RegistryPhrases[7])
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
}

local function HasAuraSettingIntent(text)
    -- "Debuff stripe" and "dispel overlay" belong to unitframe visuals, not aura filtering.
    -- Guard them here before broad buff/debuff words pull the command into the aura registry.
    if ContainsAny(text, P.NON_AURA_DEBUFF_CONTROL_TERMS) then return false end
    return ContainsAny(text, RegistryPhrases[8])
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
    for i = 1, #changes do
        if changes[i] and changes[i].mediaChoice == true then return false end
    end
    -- Bulk writes must be opt-in by language or by an unmistakable two-lane aura command.
    -- Ambiguous matches stay as choices so the user can pick before anything is applied.
    if HasAllScopeIntent(text) then return true end
    if P.ShouldApplyMultipleAuraLaneChanges and P.ShouldApplyMultipleAuraLaneChanges(text, changes) then return true end
    local units, groups = ExplicitScopes(text)
    return (#units + #groups) > 1
end

P.ShouldApplyMultipleAuraLaneChanges = P.ShouldApplyMultipleAuraLaneChanges or function(text, changes)
    if #(changes or {}) ~= 2 then return false end
    if not ContainsAny(text, RegistryPhrases[9]) then return false end
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

-- A generated frameType="general" fallback carries no unit, so the explicit
-- unit/group filter below never excludes it.  When the user names a frame
-- ("player frame") and a reviewed curated setting owns the same attribute for
-- that frame, the generic fallback must lose: otherwise a request for a real
-- per-frame control (for example the Player HP Text Delimiter enum) resolves to
-- the unconstrained generated general string and gets refused.  Only generated
-- generals are affected, so every genuinely global feature stays matchable.
function P.GeneratedGeneralShadowedByScopedSetting(setting, units, groups)
    if setting.generated ~= true or tostring(setting.frameType or "") ~= "general" then return false end
    if not (Registry and type(Registry.FindSettings) == "function") then return false end
    local attribute = tostring(setting.attribute or "")
    if attribute == "" then return false end
    local scopes = {}
    for i = 1, #(units or {}) do scopes[#scopes + 1] = units[i] end
    for i = 1, #(groups or {}) do scopes[#scopes + 1] = groups[i] end
    for i = 1, #scopes do
        local scoped = Registry:FindSettings({ unit = scopes[i], attribute = attribute })
        for j = 1, #(scoped or {}) do
            local candidate = scoped[j]
            if type(candidate) == "table" and candidate.generated ~= true
                and tostring(candidate.key or "") ~= tostring(setting.key or "")
            then
                return true
            end
        end
    end
    return false
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
    if setting.frameType == "aura" and ContainsAny(text, RegistryPhrases[13])
        and not tostring(setting.attribute or ""):lower():find("filter", 1, true) then
        return false
    end
    local auraFilterScope = P.ExplicitAuraFilterScope and P.ExplicitAuraFilterScope(text)
    if setting.frameType == "aura" and auraFilterScope then
        return unit == auraFilterScope or keyScope == auraFilterScope
    end
    if setting.frameType == "group" or setting.frameType == "groupAura" then
        if #groups > 0 then
            return ListContains(groups, unit) or ListContains(groups, keyScope)
                or SettingAllowsAnyIntentScope(setting, groups)
        end
        if #units > 0 then return false end
        return true
    end
    local settingKey = tostring(setting.key or ""):lower()
    if settingKey:find("bosstarget", 1, true) and ContainsAny(text, RegistryPhrases[15]) then return true end
    if (#units > 0 or #groups > 0)
        and P.GeneratedGeneralShadowedByScopedSetting(setting, units, groups)
    then
        return false
    end
    if #units > 0 and unit ~= "" and unit ~= "global"
        and not ListContains(units, unit) and not ListContains(units, keyScope)
        and not SettingAllowsAnyIntentScope(setting, units)
    then
        return false
    end
    if #groups > 0 and #units == 0 and unit ~= "" and unit ~= "global"
        and not ListContains(groups, unit) and not ListContains(groups, keyScope)
        and not SettingAllowsAnyIntentScope(setting, groups)
    then
        return false
    end
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

-- RC9 added the Pandemic warning controls (show state, style, colour,
-- thickness, padding, border/tint opacity, blend). They live only in the
-- generated catalog and their names are deliberately plain -- "Border
-- Opacity", "Thickness", "Style" -- so an unrelated registry setting whose
-- alias happens to be "border opacity" matched "set the target pandemic border
-- opacity to 80" and wrote Target Bar Outline Opacity instead.
--
-- No registry setting owns the word, so naming it means the catalog lane. Any
-- setting that does mention pandemic anywhere in its identity is exempt, which
-- keeps this from starving a future reviewed owner.
local function PandemicDetailBlocksSetting(setting, text)
    if not HasPhrase(text, "pandemic") then return false end
    local hay = table.concat({
        tostring(setting.key or ""), tostring(setting.label or ""),
        tostring(setting.attribute or ""), tostring(setting.category or ""),
    }, " "):lower()
    if hay:find("pandemic", 1, true) then return false end
    local aliases = setting.aliases or {}
    for i = 1, #aliases do
        if tostring(aliases[i]):lower():find("pandemic", 1, true) then return false end
    end
    return true
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
    if PandemicDetailBlocksSetting(setting, text) then return 0 end
    if not SettingAllowedByExplicitScopes(setting, text) then return 0 end
    if setting.frameType == "castbar" and setting.attribute == "enabled" and ContainsAny(text, CASTBAR_ROOT_DETAIL_TERMS) then
        return 0
    end
    if setting.frameType == "classPower" and ContainsAny(text, RegistryPhrases[16]) and not ContainsAny(text, CLASS_POWER_TERMS) then
        return 0
    end
    if setting.frameType == "classPower" and ContainsAny(text, RegistryPhrases[17]) and not ContainsAny(text, CLASS_POWER_TERMS) then
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

function P.ScoreSettingCandidates(candidates, features)
    if type(candidates) ~= "table" or #candidates <= 1 then return candidates end
    features = type(features) == "table" and features or {}
    local ctx = features.context
    if type(ctx) ~= "table" and A.ConversationContext then ctx = A.ConversationContext() end
    -- Context may break an otherwise real tie, but it must decay. Keeping an
    -- old unit/category bonus indefinitely lets a new, unrelated sentence be
    -- pulled back into a frame discussed many turns ago. Continuation parsing
    -- uses the same three-turn horizon.
    local ageTurns = type(ctx) == "table" and tonumber(ctx.ageTurns) or nil
    local contextFresh = ageTurns == nil or (ageTurns >= 0 and ageTurns <= 3)
    local subject = contextFresh and type(ctx) == "table" and ctx.subject or {}
    local subjectUnit = subject and subject.unit
    local subjectCategory = subject and subject.category
    local subjectTextArea = subject and subject.textArea

    local maxAlias = 1
    for i = 1, #candidates do
        local score = tonumber(candidates[i] and candidates[i].matchScore or candidates[i] and candidates[i].score) or 0
        if score > maxAlias then maxAlias = score end
        candidates[i]._contextScoreIndex = i
    end

    local bestScore
    local out = {}
    for i = 1, #candidates do
        local item = candidates[i]
        local setting = item and item.setting
        local aliasScore = tonumber(item and (item.matchScore or item.score)) or 0
        local score = aliasScore / maxAlias
        if setting and subjectUnit ~= nil and setting.unit == subjectUnit then score = score + 0.25 end
        if setting and subjectCategory ~= nil and setting.category == subjectCategory then score = score + 0.25 end
        if setting and subjectTextArea ~= nil then
            local area = tostring(subjectTextArea or "")
            local hay = tostring(setting.attribute or "") .. " " .. tostring(setting.key or "") .. " " .. tostring(setting.label or "")
            if area ~= "" and hay:lower():find(area:lower(), 1, true) then score = score + 0.15 end
        end
        if setting and setting.generated == true then score = score - 0.10 end
        if setting and item and item.value ~= nil and item.relativeDelta == nil and type(setting.get) == "function" then
            local ok, current = pcall(setting.get)
            if ok then
                local same
                if type(setting.sameValue) == "function" then
                    local sameOk, sameResult = pcall(setting.sameValue, current, item.value)
                    same = sameOk and sameResult == true
                elseif setting.type == "number" then
                    local oldNumber = tonumber(current)
                    local newNumber = tonumber(item.value)
                    same = oldNumber ~= nil and newNumber ~= nil and math.abs(oldNumber - newNumber) < 0.0001
                else
                    same = current == item.value
                end
                if same then score = score - 0.40 end
            end
        end
        item.contextScore = score
        if bestScore == nil or score > bestScore then
            bestScore = score
            out = { item }
        elseif score == bestScore then
            out[#out + 1] = item
        end
    end

    if #out <= 1 then return out end
    local bestAlias
    local aliasFiltered = {}
    for i = 1, #out do
        local aliasScore = tonumber(out[i] and (out[i].matchScore or out[i].score)) or 0
        if bestAlias == nil or aliasScore > bestAlias then
            bestAlias = aliasScore
            aliasFiltered = { out[i] }
        elseif aliasScore == bestAlias then
            aliasFiltered[#aliasFiltered + 1] = out[i]
        end
    end
    return aliasFiltered
end

local function RefreshRegistrySettingValues(setting)
    local refresh = setting and setting.refreshValues
    if type(refresh) ~= "function" then return false end
    local ok, values, labels = pcall(refresh, setting)
    if not ok or type(values) ~= "table" or #values == 0 then return false end
    setting.values = values
    if type(labels) == "table" then setting.valueLabels = labels end
    return true
end

P.RefreshRegistrySettingValues = RefreshRegistrySettingValues

-- Storage tokens keep their underscores through Normalize, so Compact leaves
-- "BLIZZARD_RING" as "blizzard_ring" while the player's "blizzard ring" compacts
-- to "blizzardring" -- the two never met, and only the one choice with no
-- underscore ("BLIZZARD") could be selected by name. Compare on a form where a
-- word separator is a word separator whether it was typed as a space or stored
-- as an underscore.
local function CompactToken(value)
    return (Compact(value):gsub("_", ""))
end

local function EnumValueForText(setting, text)
    local function matchSegment(segment)
        segment = Normalize(segment)
        if segment == "" then return nil end
        local aliases = setting and setting.valueAliases
        local compactText = CompactToken(segment)
        -- Exact choice keys and aliases always outrank fuzzy containment. This
        -- matters for values such as weapon_axes_crossed: the shorter alias
        -- "cross" must not redirect it to resurrection_cross.
        if type(aliases) == "table" then
            local bestValue, bestLen
            for alias, value in pairs(aliases) do
                local normalizedAlias = Normalize(alias)
                local compactAlias = CompactToken(alias)
                if segment == normalizedAlias or compactText == compactAlias then
                    local len = #compactAlias
                    if not bestLen or len > bestLen then bestValue, bestLen = value, len end
                end
            end
            if bestValue ~= nil then return bestValue end
        end
        local values = setting and setting.values
        if type(values) == "table" then
            for i = 1, #values do
                local value = values[i]
                if segment == Normalize(value) or compactText == CompactToken(value) then return value end
            end
        end
        local valueLabels = setting and setting.valueLabels
        if type(values) == "table" and type(valueLabels) == "table" then
            for i = 1, #values do
                local value = values[i]
                local label = valueLabels[value]
                if label ~= nil and (segment == Normalize(label) or compactText == CompactToken(label)) then return value end
            end
        end
        if type(aliases) == "table" then
            local bestValue
            local bestLen = 0
            for alias, value in pairs(aliases) do
                local compactAlias = CompactToken(alias)
                local normalizedAlias = Normalize(alias)
                local joinedPhrase = normalizedAlias:find(" ", 1, true)
                    and #compactAlias >= 5 and compactText:find(compactAlias, 1, true)
                if HasPhrase(segment, alias) or joinedPhrase then
                    local len = #CompactToken(alias)
                    if len > bestLen then
                        bestLen = len
                        bestValue = value
                    end
                end
            end
            if bestValue ~= nil then return bestValue end
        end
        -- Longest containment wins, exactly as the alias loop above does. A
        -- family whose choices share a stem ("BLIZZARD", "BLIZZARD_RING",
        -- "BLIZZARD_BORDER") otherwise resolves every one of them to whichever
        -- is registered first: "set Player Unit Dispel Symbol Style to blizzard
        -- ring" answered "already Blizzard" and the two longer choices could not
        -- be selected by name at all.
        if type(values) == "table" then
            local bestValue, bestLen = nil, 0
            for i = 1, #values do
                local value = values[i]
                local compactValue = CompactToken(value)
                if HasPhrase(segment, tostring(value)) or (#compactValue >= 5 and compactText:find(compactValue, 1, true)) then
                    if #compactValue > bestLen then bestValue, bestLen = value, #compactValue end
                end
            end
            if bestValue ~= nil then return bestValue end
        end
        if type(values) == "table" and type(valueLabels) == "table" then
            local bestValue, bestLen = nil, 0
            for i = 1, #values do
                local value = values[i]
                local label = valueLabels[value]
                if label ~= nil and HasPhrase(segment, tostring(label)) then
                    local len = #CompactToken(label)
                    if len > bestLen then bestValue, bestLen = value, len end
                end
            end
            if bestValue ~= nil then return bestValue end
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

-- Resolve a symbol-valued enum (text separator/delimiter) from the RAW text.
-- The user may type the literal symbol ("... to :"), which normalization would
-- strip.  We only accept values that are pure punctuation symbols so this can
-- never shadow a word-valued enum, and we require the symbol to appear after
-- the value connector so a colon elsewhere in the sentence is ignored.
P.SymbolEnumValueForRaw = P.SymbolEnumValueForRaw or function(setting, raw)
    local values = setting and setting.values
    if type(values) ~= "table" or type(raw) ~= "string" or raw == "" then return nil end
    -- Take the value part after the last "to"/"="/"as" connector, else the whole
    -- text, and trim surrounding whitespace.
    local tail = raw:match("[Tt][Oo]%s+(.-)%s*$")
        or raw:match("=%s*(.-)%s*$")
        or raw:match("[Aa][Ss]%s+(.-)%s*$")
        or raw:gsub("^%s+", ""):gsub("%s+$", "")
    tail = tostring(tail or "")
    -- The value part must be EXACTLY a symbol enum value.  Requiring an exact
    -- match (not a suffix) prevents "->" from matching a ">" or "-" value; a
    -- multi-character custom symbol like "->" is not an enum value and must fall
    -- through to the custom string field.
    for i = 1, #values do
        local value = tostring(values[i] or "")
        if value ~= "" and value:match("^[%p]+$") and #value <= 3 and tail == value then
            return values[i]
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
    LEFTDOWN = "left then down",
    LEFTUP = "left then up",
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
    RIGHTDOWN = "right then down",
    RIGHTUP = "right then up",
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
    if setting and type(setting.valueLabels) == "table" then
        local display = setting.valueLabels[value]
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
    if ContainsAny(text, RegistryPhrases[18]) then return "SHIFT" end
    if ContainsAny(text, RegistryPhrases[19]) then return "CTRL" end
    if ContainsAny(text, RegistryPhrases[20]) then return "ALT" end
    return nil
end

local function MissingValueResponse(matches, raw)
    if #matches == 0 then return nil end
    -- Media requests put the value in front of the control ("use the flat
    -- texture for the absorb bar"). The alias reader finds the control and no
    -- value, so before asking for one, re-read the sentence in the order the
    -- value parser understands.
    do
        local router = A.RouterPrivate
        -- The stated value may belong to a SIBLING of the control the words
        -- name: "make the frame outline red" names the outline family, whose
        -- bare words are the thickness slider, and states a colour.
        local siblingPlan = type(router) == "table"
            and type(router.StatedValueKindSiblingPlan) == "function"
            and router.StatedValueKindSiblingPlan(raw) or nil
        if siblingPlan then return siblingPlan end
        local reordered = type(router) == "table"
            and type(router.CanonicalValueBeforeControlCommand) == "function"
            and router.CanonicalValueBeforeControlCommand(raw, true) or nil
        if reordered then
            for i = 1, #matches do
                local candidate = matches[i] and matches[i].setting
                -- P.ValueForRegistrySetting, not the file-local upvalue: the
                -- local is declared further down and is still nil here.
                local value = candidate and type(P.ValueForRegistrySetting) == "function"
                    and P.ValueForRegistrySetting(candidate, Normalize(reordered), reordered) or nil
                if value ~= nil then
                    return {
                        kind = "changes",
                        changes = { { setting = candidate, value = value } },
                        label = candidate.label or "Assistant option change",
                        summary = "Changes the control named after its value.",
                        raw = raw,
                        sourceText = raw,
                    }
                end
            end
        end
    end
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
    RefreshRegistrySettingValues(setting)
    -- A texture request often names its value with no connector at all ("i
    -- want a solid looking bar texture", "make the empty part of the bar use
    -- the flat texture"). Before asking, scan the sentence against the known
    -- texture vocabulary; exactly one distinct target is the stated value.
    -- Aliases that also appear in the control's own label are skipped so
    -- "frame outline style" can never read its own name as the value.
    if setting.type == "string"
        and (setting.mediaType ~= nil
            or tostring(setting.label or ""):lower():find("texture", 1, true))
    then
        local barsData = A.GlobalBarRegistry and A.GlobalBarRegistry.Data
        local textureAliases = type(barsData) == "table" and barsData.TEXTURE_KEY_ALIASES or nil
        if type(textureAliases) == "table" then
            local padded = " " .. Normalize(raw) .. " "
            local labelPadded = " " .. Normalize(setting.label or "") .. " "
            local found
            for alias, target in pairs(textureAliases) do
                local phrase = " " .. tostring(alias) .. " "
                if padded:find(phrase, 1, true) and not labelPadded:find(phrase, 1, true) then
                    if found ~= nil and found ~= target then found = nil break end
                    found = target
                end
            end
            if type(found) == "string" and found ~= "" then
                return {
                    kind = "changes",
                    changes = { { setting = setting, value = found } },
                    label = setting.label or "Assistant option change",
                    summary = "Texture value named without a connector.",
                    raw = raw,
                    sourceText = raw,
                }
            end
        end
    end
    if (setting.type == "enum" or setting.type == "string")
        and type(setting.values) == "table" and #setting.values > 0 and #setting.values <= 24
    then
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
        pendingSetting = {
            settingKey = setting.key,
            expectedType = setting.type,
            label = setting.label,
        },
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
    if setting.frameType == "classPower" and ContainsAny(text, RegistryPhrases[21]) and not ContainsAny(text, CLASS_POWER_TERMS) then
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

-- Generational cache: two tables, no per-key deletes. Delete-based eviction
-- keeps a hash table at capacity under constant insert+delete, which drives
-- Lua into rehash storms (hundreds of microseconds per insert, measured on
-- the normalize cache with the same structure).
local candidateIndexTokenCacheHot = {}
local candidateIndexTokenCacheCold = {}
local candidateIndexTokenCacheHotCount = 0
local CANDIDATE_INDEX_TOKEN_CACHE_LIMIT = 8192

local function CacheCandidateIndexTokens(raw, tokens)
    if #raw > 180 then return tokens end
    if candidateIndexTokenCacheHot[raw] == nil then
        candidateIndexTokenCacheHotCount = candidateIndexTokenCacheHotCount + 1
        if candidateIndexTokenCacheHotCount > CANDIDATE_INDEX_TOKEN_CACHE_LIMIT then
            candidateIndexTokenCacheCold = candidateIndexTokenCacheHot
            candidateIndexTokenCacheHot = {}
            candidateIndexTokenCacheHotCount = 1
        end
    end
    candidateIndexTokenCacheHot[raw] = tokens
    return tokens
end

local function CandidateIndexTokens(text)
    local raw = tostring(text or "")
    if raw == "" then return nil end
    local cached = candidateIndexTokenCacheHot[raw]
    if cached ~= nil then return cached end
    cached = candidateIndexTokenCacheCold[raw]
    if cached ~= nil then
        -- Promote so the entry survives the next generation swap.
        return CacheCandidateIndexTokens(raw, cached)
    end
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
    return CacheCandidateIndexTokens(raw, tokens)
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
    P._registryCandidateFuzzyTokenCacheOrder = {}
    P._registryCandidateFuzzyTokenCacheHead = 1
    if P.ClearSettingMatchScoreCache then P.ClearSettingMatchScoreCache() end
end

local REGISTRY_FUZZY_TOKEN_CACHE_LIMIT = 2048

function P.ClearRegistryCandidateFuzzyCache()
    P._registryCandidateFuzzyTokenCache = {}
    P._registryCandidateFuzzyTokenCacheOrder = {}
    P._registryCandidateFuzzyTokenCacheHead = 1
end

local function RememberRegistryFuzzyToken(token, value)
    local cache = P._registryCandidateFuzzyTokenCache or {}
    local order = P._registryCandidateFuzzyTokenCacheOrder or {}
    local head = tonumber(P._registryCandidateFuzzyTokenCacheHead) or 1
    P._registryCandidateFuzzyTokenCache = cache
    P._registryCandidateFuzzyTokenCacheOrder = order
    if cache[token] == nil then
        order[#order + 1] = token
        if #order - head + 1 > REGISTRY_FUZZY_TOKEN_CACHE_LIMIT then
            cache[order[head]] = nil
            head = head + 1
            if head > REGISTRY_FUZZY_TOKEN_CACHE_LIMIT and head > (#order / 2) then
                local compact = {}
                for i = head, #order do compact[#compact + 1] = order[i] end
                order, head = compact, 1
                P._registryCandidateFuzzyTokenCacheOrder = order
            end
        end
    end
    cache[token] = value
    P._registryCandidateFuzzyTokenCacheHead = head
    return value
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
        RememberRegistryFuzzyToken(token, false)
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
                            RememberRegistryFuzzyToken(token, false)
                            return nil
                        end
                    end
                end
            end
        end
    end

    RememberRegistryFuzzyToken(token, #out > 0 and out or false)
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
    if #out == 0 and skippedValueToken and not includeAliases then
        return {}
    end
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

-- The English "deactivate"/"activate" pair must stay in step with the German
-- "deaktivieren"/"aktivieren" that has always been here. It was missing, and
-- these settings are named after a polarity word ("Hide Out of Combat"), so the
-- label itself put "hide" in the request: with no OFF term matching,
-- "deactivate Boss Hide Out of Combat" fell to HIDE_ON_TERMS and switched the
-- setting ON. OFF is tested first at every call site, which is what keeps
-- "deactivate" from also reading as "activate".
local SHOW_OFF_TERMS = {
    "turn off", "disable", "disabled", "deactivate", "deactivated", "off", "false", "no",
    "hide", "hidden", "not show", "dont show", "do not show", "never show",
    "aus", "deaktivieren", "deaktiviert", "ausschalten", "ausgeschaltet",
    "ausblenden", "verstecken", "nicht anzeigen", "nicht zeigen", "nicht einblenden", "nein",
}

local SHOW_ON_TERMS = {
    "turn on", "enable", "enabled", "activate", "activated", "on", "true", "yes",
    "show", "display", "visible",
    "an", "aktivieren", "aktiviert", "einschalten", "eingeschaltet",
    "anzeigen", "zeigen", "einblenden", "sichtbar", "ja",
}

local HIDE_OFF_TERMS = {
    "turn off", "disable", "disabled", "deactivate", "deactivated", "off", "false", "no",
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
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(text) or nil
    if target then
        if ContainsAny(target, SHOW_OFF_TERMS) then return false end
        if ContainsAny(target, SHOW_ON_TERMS) then return true end
    end
    if ContainsAny(text, SHOW_OFF_TERMS) then return false end
    if ContainsAny(text, SHOW_ON_TERMS) then return true end
    return DetectBoolean(text)
end

local function HideSettingValueForText(text, defaultValue)
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(text) or nil
    if target then
        if ContainsAny(target, RegistryPhrases[22]) then return true end
        if ContainsAny(target, HIDE_OFF_TERMS) then return false end
        if ContainsAny(target, HIDE_ON_TERMS) then return true end
    end
    if ContainsAny(text, RegistryPhrases[23]) then return true end
    if ContainsAny(text, HIDE_OFF_TERMS) then return false end
    if ContainsAny(text, HIDE_ON_TERMS) then return true end
    local value = DetectBoolean(text)
    if value ~= nil then return value end
    return defaultValue
end

local UNIT_LOAD_CONDITION_SPECS = {
    { key = "loadCondHideInHousing", label = "Hide in Housing", terms = { "housing", "house", "in housing", "while in housing", "when in housing", "player housing", "haus", "spielerhaus" } },
    { key = "loadCondHideInCombat", label = "Hide in Combat", terms = { "in combat", "combat", "fight", "while in combat", "when in combat", "im kampf", "kampf" } },
    { key = "loadCondHideInGroup", label = "Hide in Group", terms = { "in group", "while in group", "when in group", "grouped", "in party", "in raid", "in gruppe", "gruppe" } },
    { key = "loadCondHideInInstance", label = "Hide in Instance", terms = { "in instance", "instance", "dungeon", "while in instance", "when in instance", "instanz" } },
    { key = "loadCondHideInVehicle", label = "Hide in Vehicle", terms = { "in vehicle", "vehicle", "while in vehicle", "when in vehicle", "fahrzeug" } },
    { key = "loadCondHideMounted", label = "Hide Mounted", terms = { "mounted", "mount", "on mount", "while mounted", "when mounted", "gemountet", "reittier" } },
    { key = "loadCondHideNoTarget", label = "Hide with No Target", terms = { "no target", "without target", "when no target", "target selected", "has target", "with target", "kein ziel", "ohne ziel", "ziel ausgewählt", "hat ein ziel", "mit ziel" } },
    { key = "loadCondHideOutOfCombat", label = "Hide Out of Combat", terms = { "out of combat", "outside combat", "not in combat", "ooc", "while out of combat", "when out of combat", "ausserhalb kampf", "ausser kampf", "nicht im kampf" } },
    { key = "loadCondHideOutOfCombatNoTarget", label = "Hide Out of Combat with No Target", terms = { "out of combat and no target", "out of combat with no target", "no target while out of combat", "outside combat with no target", "target selected or in combat", "has target or in combat", "target or combat", "ausserhalb kampf und kein ziel", "kein ziel ausserhalb kampf", "ziel oder im kampf" } },
    { key = "loadCondHideResting", label = "Hide Resting", terms = { "resting", "rested", "rest area", "while resting", "when resting", "ruhend", "erholt" } },
    { key = "loadCondHideSolo", label = "Hide Solo", terms = { "solo", "alone", "while solo", "when solo", "allein" } },
    { key = "loadCondHideStealthed", label = "Hide Stealthed", terms = { "stealthed", "stealth", "in stealth", "while stealthed", "when stealthed", "getarnt", "verstohlen" } },
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
            and not ContainsAny(text, RegistryPhrases[24])
            and ContainsAny(text, RegistryPhrases[25])
    end
    return #units > 0 and HasVisibilityVerb(text)
end

P.TARGET_GATE_LOAD_CONDITIONS = {
    loadCondHideNoTarget = true,
    loadCondHideOutOfCombatNoTarget = true,
}
P.TARGET_GATE_OFF_TERMS = {
    "turn off", "disable", "disabled", "deactivate", "deactivated", "remove", "clear",
    "dont hide", "do not hide", "never hide", "always show",
    "deaktivieren", "deaktiviert", "ausschalten", "ausgeschaltet", "entfernen", "loeschen",
    "nicht verstecken", "nicht ausblenden", "immer anzeigen",
}

function P.UnitLoadConditionValueForText(text, spec)
    if spec and P.TARGET_GATE_LOAD_CONDITIONS[spec.key] == true then
        -- For target gates, "show with a target" describes enabling the Hide
        -- No Target rule rather than disabling a generic Hide setting. Only an
        -- explicit request to turn the rule off wins over that semantic form.
        if ContainsAny(text, P.TARGET_GATE_OFF_TERMS) then return false end
        return true
    end
    return HideSettingValueForText(text, true)
end

P.TARGET_GATE_INTENT_TERMS = {
    "no target", "without target", "target selected", "has target", "with target",
    "target or combat", "target selected or in combat", "has target or in combat",
    "kein ziel", "ohne ziel", "ziel ausgewählt", "hat ein ziel", "mit ziel", "ziel oder im kampf",
}

local function GroupAvailabilityAttributeForText(text)
    if ContainsAny(text, RegistryPhrases[26]) then
        return nil
    end
    if (ContainsAny(text, RegistryPhrases[27])
        and ContainsAny(text, RegistryPhrases[28])
        and ContainsAny(text, RegistryPhrases[29]))
        or ContainsAny(text, RegistryPhrases[30]) then
        return "hideOfflineInCombat", "hide"
    end
    if ContainsAny(text, RegistryPhrases[31]) then
        return "hideOfflineEnabled", "hide"
    end
    if ContainsAny(text, RegistryPhrases[32]) then
        return "hideInClientScene", "hide"
    end
    local groupScopesForHousing = DetectGroups(text)
    if #groupScopesForHousing > 0 and ContainsAny(text, RegistryPhrases[33]) then
        return "hideInHousing", "hide"
    end
    if ContainsAny(text, RegistryPhrases[34]) then
        return "showPlayer", "show"
    end
    if ContainsAny(text, RegistryPhrases[35]) then
        return "showSolo", "show"
    end
    if ContainsAny(text, RegistryPhrases[36]) and not ContainsAny(text, RegistryPhrases[37]) then
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
    "stronger", "strengthen", "rounder", "longer", "brighter", "turn it up", "turn up", "crank", "chunkier",
    "erhoehe", "erhoehen", "hoeher", "groesser", "mehr", "breiter", "dicker",
}
local RELATIVE_DECREASE_TERMS = {
    "decrease", "reduce", "lower", "less", "smaller", "narrower", "shorter", "thinner", "shrink", "subtract", "down",
    "weaker", "weaken", "subtler", "softer", "fainter", "dimmer", "transparent", "tone down", "turn it down",
    "verringere", "reduziere", "tiefer", "niedriger", "kleiner", "weniger", "schmaler", "duenner", "runter",
}

-- Some phrases pair an increase word with a decrease meaning and the other way
-- round: "more transparent" is LESS opacity, "less faded" is more. Checked
-- before the single words, which would otherwise see the "more" and turn the
-- slider the wrong way. "too <adjective>" states the complaint rather than the
-- direction, so it is listed with the direction it asks for.
local RELATIVE_PHRASE_SIGNS = {
    { "more transparent", -1 }, { "more see through", -1 }, { "more seethrough", -1 },
    { "less opaque", -1 }, { "more subtle", -1 }, { "more faded", -1 }, { "less visible", -1 },
    { "too strong", -1 }, { "too intense", -1 }, { "too bright", -1 }, { "too much", -1 },
    { "less transparent", 1 }, { "less see through", 1 }, { "more opaque", 1 },
    { "less subtle", 1 }, { "less faded", 1 }, { "more visible", 1 },
    { "too subtle", 1 }, { "too weak", 1 }, { "too faint", 1 }, { "too thin", 1 },
    { "too small", 1 }, { "too little", 1 },
}
local function RelativePhraseSign(text)
    text = tostring(text or ""):lower()
    for i = 1, #RELATIVE_PHRASE_SIGNS do
        local entry = RELATIVE_PHRASE_SIGNS[i]
        if text:find(entry[1], 1, true) then return entry[2] end
    end
    return nil
end

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

-- "by 20" / "um 20" states a delta; "to 20" / "auf 20" states the final value.
-- Both readings can carry an increase/decrease verb ("increase the width to 250"
-- means "make it 250", not "add 250"), so the connector decides, not the verb.
P.RELATIVE_AMOUNT_PATTERNS = {
    "%f[%w]by%f[%W]%s+[-+]?%d",
    "%f[%w]um%f[%W]%s+[-+]?%d",
}
P.ABSOLUTE_TARGET_PATTERNS = {
    "%f[%w]to%f[%W]%s+[-+]?%d",
    "%f[%w]auf%f[%W]%s+[-+]?%d",
    "%f[%w]at%f[%W]%s+[-+]?%d",
    "=%s*[-+]?%d",
}

P.HasAbsoluteNumberTarget = function(text)
    text = tostring(text or "")
    for i = 1, #P.RELATIVE_AMOUNT_PATTERNS do
        if text:find(P.RELATIVE_AMOUNT_PATTERNS[i]) then return false end
    end
    for i = 1, #P.ABSOLUTE_TARGET_PATTERNS do
        if text:find(P.ABSOLUTE_TARGET_PATTERNS[i]) then return true end
    end
    return false
end

-- Multiplier wording: the request states the RESULT as a factor of the current
-- value ("twice as tall"), not an amount to add.
local PROPORTIONAL_MULTIPLIER_WORDS = {
    { "twice as", 2 }, { "two times as", 2 }, { "double", 2 }, { "doppelt", 2 },
    { "three times as", 3 }, { "triple", 3 }, { "thrice", 3 },
    { "half as", 0.5 }, { "halve", 0.5 }, { "half the", 0.5 }, { "haelfte", 0.5 },
    -- "half transparent" states the result as a factor of full opacity; the
    -- step reader used to take it as one 0.05 decrease (1 -> 0.95).
    { "half transparent", 0.5 }, { "halb transparent", 0.5 },
}

-- "20% bigger" and "twice as tall" are changes RELATIVE TO THE CURRENT VALUE, so
-- the delta cannot be read off the text alone -- it has to be computed from what
-- the setting holds right now.
--
-- Without this, "make player width 20% bigger" fell through to the plain amount
-- reader, which sees the bare 20 and added 20 pixels instead of 20 percent
-- (275 -> 295 where the player asked for 330). "twice as tall" matched no
-- increase/decrease word at all, so it produced no value and the Assistant
-- asked the player to supply the number it had just been given.
function P.ProportionalNumberDeltaForSetting(setting, text)
    if type(setting) ~= "table" or type(setting.get) ~= "function" then return nil end
    text = tostring(text or "")
    -- "set width to 50 percent" states the value outright; that is absolute.
    if P.HasAbsoluteNumberTarget(text) then return nil end

    local factor
    for i = 1, #PROPORTIONAL_MULTIPLIER_WORDS do
        local entry = PROPORTIONAL_MULTIPLIER_WORDS[i]
        if text:find(entry[1], 1, true) then factor = entry[2] break end
    end
    if not factor then
        local percent = text:match("(%d+%.?%d*)%s*%%") or text:match("(%d+%.?%d*)%s*percent")
            or text:match("(%d+%.?%d*)%s*prozent")
        percent = tonumber(percent)
        if percent == nil then return nil end
        -- A bare percentage says nothing about direction; only pair it with an
        -- explicit increase/decrease word so "set scale to 90%" is left alone.
        local phraseSign = RelativePhraseSign(text)
        if phraseSign then factor = 1 + phraseSign * percent / 100
        elseif ContainsAny(text, RELATIVE_INCREASE_TERMS) then factor = 1 + percent / 100
        elseif ContainsAny(text, RELATIVE_DECREASE_TERMS) then factor = 1 - percent / 100
        else return nil end
    end

    local ok, current = pcall(setting.get)
    current = ok and tonumber(current) or nil
    if current == nil or current == 0 then return nil end
    local delta = current * factor - current
    if delta == 0 then return nil end
    return delta
end

RelativeNumberDeltaForText = function(setting, text, fallbackAmount)
    local directional = P.DirectionalNumberDeltaForSetting(setting, text, fallbackAmount)
    if directional ~= nil then return directional end
    -- Before the plain amount reader: it would take the 20 out of "20% bigger"
    -- and treat it as an absolute amount.
    local proportional = P.ProportionalNumberDeltaForSetting(setting, text)
    if proportional ~= nil then return proportional end
    local sign = RelativePhraseSign(text)
    if not sign then
        if ContainsAny(text, RELATIVE_INCREASE_TERMS) then sign = 1 end
        if ContainsAny(text, RELATIVE_DECREASE_TERMS) then sign = -1 end
    end
    if not sign then return nil end
    if P.HasAbsoluteNumberTarget(text) then return nil end
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
    if not ContainsAny(text, RegistryPhrases[38]) then return true end
    if P.HasVagueAuraIconSizeIntent(text) then return P.IsAuraIconSizeSetting(setting) end
    if ContainsAny(text, RegistryPhrases[39]) then
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
    local hasBooleanCue = ContainsAny(text, RegistryPhrases[40])
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
    if ContainsAny(text, RegistryPhrases[41]) then return nil end

    local hay = (tostring(setting.key or "") .. " " .. tostring(setting.label or "") .. " " .. tostring(setting.attribute or "")):lower()
    local customSetting = hay:find("custom", 1, true) ~= nil or hay:find("override", 1, true) ~= nil
    local sharedSetting = hay:find("useshared", 1, true) ~= nil
        or hay:find("use shared", 1, true) ~= nil
        or hay:find("shared", 1, true) ~= nil
        or hay:find("inherit", 1, true) ~= nil

    local customIntent = ContainsAny(text, RegistryPhrases[42])
    local sharedIntent = ContainsAny(text, RegistryPhrases[43])

    if customSetting and customIntent then return true end
    if customSetting and sharedIntent then return false end
    if sharedSetting and sharedIntent then return true end
    if sharedSetting and customIntent then return false end
    return nil
end

local function ToggleBooleanValueForRegistrySetting(setting, text)
    if type(setting) ~= "table" or setting.type ~= "boolean" then return nil end
    if not ContainsAny(text, RegistryPhrases[44]) then return nil end
    if type(setting.get) ~= "function" then return nil end
    local ok, current = pcall(setting.get)
    if not ok or type(current) ~= "boolean" then return nil end
    return not current
end

-- Unambiguous on/off command verbs. "show"/"hide" are deliberately absent:
-- they appear inside many setting names, where they describe the control
-- rather than the requested polarity, and the branches above already own them.
P.EXPLICIT_BOOLEAN_OFF_TERMS = {
    "turn off", "turned off", "switch off", "switched off", "toggle off",
    "disable", "disabled", "deactivate", "deactivated", "hide",
    "schalte aus", "ausschalten", "deaktiviere", "deaktivieren", "verstecken",
}
P.EXPLICIT_BOOLEAN_ON_TERMS = {
    "turn on", "turned on", "switch on", "switched on", "toggle on",
    "enable", "enabled", "activate", "activated", "show",
    "schalte ein", "einschalten", "aktiviere", "aktivieren", "anzeigen",
}

function P.ExplicitBooleanCommandValue(setting, text)
    text = tostring(text or "")
    -- "show me X" asks to be shown the control, not to switch it on. Without
    -- this, "show me Boss Absorb Bar Texture" was read as an explicit ON
    -- command and wrote to a texture setting. "hide me" is not a phrasing, so
    -- only the positive side needs the guard.
    if text:find("%f[%w]show%s+me%f[%W]") or text:find("%f[%w]zeig[e]?%s+mir%f[%W]") then
        return nil
    end
    -- "set X to off" states the value outright as the tail of the command.
    -- This is never ambiguous, so it is checked before anything else.
    local tail = text:match("%f[%w]to%s+(%a+)%s*$") or text:match("=%s*(%a+)%s*$")
    if tail == "off" or tail == "false" or tail == "aus" then return false end
    if tail == "on" or tail == "true" or tail == "an" or tail == "ein" then return true end

    local hay = (tostring(setting and setting.attribute or "") .. " "
        .. tostring(setting and setting.label or "")):lower()
    -- If the setting is itself named after the polarity word ("Disable
    -- Blizzard Frames", "Hide Permanent Auras"), the word describes the
    -- control, not the request. Leave those to the existing inference.
    local function stated(terms)
        for i = 1, #terms do
            local term = terms[i]
            if ContainsAny(text, { term }) and not hay:find(term, 1, true) then return true end
        end
        return false
    end
    if stated(P.EXPLICIT_BOOLEAN_OFF_TERMS) then return false end
    if stated(P.EXPLICIT_BOOLEAN_ON_TERMS) then return true end
    return nil
end

ValueForRegistrySetting = function(setting, text, raw)
    if not setting then return nil end
    if setting.type == "boolean" then
        local attr = tostring(setting.attribute or ""):lower()
        local key = tostring(setting.key or ""):lower()
        local label = Normalize(setting.label or "")
        local requestText = tostring(text or "")
        local labelStart = label ~= "" and requestText:find(label, 1, true) or nil
        if labelStart then
            requestText = requestText:sub(1, labelStart - 1) .. " "
                .. requestText:sub(labelStart + #label)
        end
        local bareEdit = requestText:find("^%s*change%f[%W]")
            or requestText:find("^%s*adjust%f[%W]")
            or requestText:find("^%s*modify%f[%W]")
            or requestText:find("^%s*aender%f[%W]")
            or requestText:find("^%s*aendere%f[%W]")
            or requestText:find("^%s*aendern%f[%W]")
        if bareEdit and DetectBoolean(requestText) == nil
            and not ContainsAny(requestText, RegistryPhrases[44])
        then
            return nil
        end
        -- A stated "to on"/"to off" tail is the literal value of the setting and
        -- must outrank every name-based inference below. The per-key branches
        -- that follow exist because those settings are NAMED after a polarity
        -- word, but they returned before any explicit value was consulted -- so
        -- "set Disable Blizzard Unit Frames to off" read the "disable" in the
        -- control's own name as the request and answered "already enabled",
        -- exactly inverting the order. The label is already stripped from
        -- requestText, so only a genuine trailing value is seen here.
        local statedTail = requestText:match("%f[%w]to%s+(%a+)%s*$")
            or requestText:match("=%s*(%a+)%s*$")
        if statedTail == "off" or statedTail == "false" or statedTail == "aus" then return false end
        if statedTail == "on" or statedTail == "true" or statedTail == "an" or statedTail == "ein" then
            return true
        end
        if attr == "powerbardetached" or key:find("%.powerbardetached", 1, true) then
            if ContainsAny(text, RegistryPhrases[45]) then return false end
            if ContainsAny(text, RegistryPhrases[46]) then return true end
        end
        if key == "general.disableblizzardunitframes" then
            if ContainsAny(text, RegistryPhrases[47]) then return true end
            if ContainsAny(text, RegistryPhrases[48]) then return false end
            return nil
        end
        if key == "general.hardkillblizzardplayerframe" then
            if ContainsAny(text, RegistryPhrases[47]) then return false end
            if ContainsAny(text, RegistryPhrases[48]) then return true end
            return DetectBoolean(text)
        end
        if key == "general.hideadvancedmenu" then
            if ContainsAny(text, RegistryPhrases[49]) then return false end
            if ContainsAny(text, RegistryPhrases[50]) then return true end
            return DetectBoolean(text)
        end
        if attr:find("^hide") or key:find("hide") then
            if ContainsAny(text, RegistryPhrases[51]) then return false end
            if ContainsAny(text, RegistryPhrases[52]) then return true end
        end
        -- An explicit on/off command states the polarity outright, so the
        -- inference below may only fill in a polarity that was never stated.
        -- "turn off Boss Custom Aura Filters" contains the setting's own alias
        -- ("custom aura filters"); the alias reader scored that as a positive
        -- mention and turned the setting ON -- the exact opposite of the order.
        local explicitValue = P.ExplicitBooleanCommandValue(setting, text)
        if explicitValue ~= nil then return explicitValue end
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
    if setting.type == "enum" then
        -- Symbol-valued enums (text separators/delimiters: ':', '-', '/', '|',
        -- '<', '>', '~', '\\') lose their value to normalization, which strips
        -- punctuation like the colon.  Look for the exact symbol in the raw text
        -- first so "set hp text separator to :" resolves the colon value.
        local symbolValue = P.SymbolEnumValueForRaw and P.SymbolEnumValueForRaw(setting, raw)
        if symbolValue ~= nil then return symbolValue end
        -- "turn it up" is intensity wording, never a direction value. For
        -- direction-valued enums, mask those phrases so "the bar gradient is
        -- too subtle, turn it up" cannot select Direction = up; the relative
        -- strength path owns that request.
        local enumText = text
        for i = 1, #(setting.values or {}) do
            local v = tostring(setting.values[i] or ""):lower()
            if v == "up" or v == "down" then
                enumText = tostring(text or "")
                    :gsub("turn%s+it%s+up", " "):gsub("turn%s+it%s+down", " ")
                    :gsub("turn%s+up", " "):gsub("turn%s+down", " ")
                    :gsub("crank%s+it%s+up", " "):gsub("tone%s+it%s+down", " ")
                break
            end
        end
        return EnumValueForText(setting, enumText)
    end
    if setting.type == "string" then
        -- Some native controls store their fixed choices as strings because
        -- their keys can be extended by MSUF at runtime (status icon packs are
        -- the main example).  Treat the registry's advertised choices exactly
        -- like enum choices: normalize friendly aliases to the canonical key,
        -- and never let arbitrary text pass a closed-choice contract.
        if type(setting.values) == "table" and #setting.values > 0 then
            local knownValue = EnumValueForText(setting, text)
            if knownValue ~= nil then return knownValue end
            if RefreshRegistrySettingValues(setting) then
                knownValue = EnumValueForText(setting, text)
                if knownValue ~= nil then return knownValue end
            end
            if setting.closedValues == true then return nil end
        end
        return StringValueForText(setting, text, raw)
    end
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
                mediaChoice = true,
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

local function MediaNoMatchResult(media)
    local resolver = A.MediaResolver
    local textOut = resolver and resolver.NoMatchMessage and resolver.NoMatchMessage(media and media.mediaType, media and media.query) or "That media entry is not in the current list."
    return { kind = "unknown", text = textOut, status = "failed" }
end

local function MediaAmbiguousResult(setting, media)
    local choices = {}
    local mediaChoices = media and media.choices or {}
    for i = 1, #mediaChoices do
        local item = mediaChoices[i]
        choices[#choices + 1] = {
            setting = setting,
            value = item.value,
            valueLabel = item.label or item.value,
            label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, item.label or item.value, "Option") or (tostring(setting.label or "Option") .. ": " .. tostring(item.label or item.value)),
            mediaType = media.mediaType,
            mediaChoice = true,
        }
    end
    if #choices == 0 then return nil end
    return {
        kind = "ambiguous",
        choices = choices,
        label = media.mediaType == "font" and "Which font?" or "Which texture?",
        summary = "Asks which matching media entry should be used.",
    }
end

local function ResolveMediaChange(setting, text, raw, explicitQuery)
    local resolver = A.MediaResolver
    if not (resolver and type(resolver.MediaTypeForSetting) == "function") then return nil end
    local mediaType = resolver.MediaTypeForSetting(setting)
    if not mediaType then return nil end
    local media
    if explicitQuery and explicitQuery ~= "" and type(resolver.Find) == "function" then
        media = resolver.Find(mediaType, explicitQuery, { limit = 8 })
    elseif type(resolver.ResolveSetting) == "function" then
        media = resolver.ResolveSetting(setting, text, raw)
    end
    if not media then return nil end
    if media.status == "exact" and media.value ~= nil then
        return {
            setting = setting,
            value = media.value,
            valueLabel = media.label or media.value,
            mediaType = media.mediaType,
        }
    end
    if media.status == "none" then return nil, MediaNoMatchResult(media) end
    if media.status == "choices" then return nil, MediaAmbiguousResult(setting, media) end
    return nil
end

local POWER_UNIT_ORDER = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
local POWER_GROUP_ORDER = { "party", "raid", "mythicraid" }
local CASTBAR_INTERRUPT_UNITS = { "player", "target", "focus", "boss" }

local function ParseGlobalFontFamilyShortcut(text, raw)
    if not ContainsAny(text, RegistryPhrases[53]) then return nil end
    if ContainsAny(text, RegistryPhrases[54]) then return nil end
    if ContainsAny(text, RegistryPhrases[55]) then return nil end
    if #(DetectUnits(text) or {}) > 0 or #(DetectGroups(text) or {}) > 0 then return nil end
    if not ContainsAny(text, RegistryPhrases[56]) then return nil end

    local setting = Registry and Registry:GetSetting("general.fontKey")
    if not setting then return nil end
    local value = RawAfterLastConnector and RawAfterLastConnector(raw, SET_VALUE_CONNECTORS) or nil
    if value == nil or Trim(value) == "" then return nil end
    value = Trim(value)
    local mediaChange, mediaResult = ResolveMediaChange(setting, text, raw, value)
    if mediaResult then return mediaResult end
    if mediaChange then
        return {
            kind = "changes",
            changes = { mediaChange },
            label = setting.label or "Global Font",
            summary = "Changes the global SharedMedia font family.",
        }
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, valueLabel = ValueDisplay(setting, value) } },
        label = setting.label or "Global Font",
        summary = "Changes the global SharedMedia font family.",
    }
end
P.ParseGlobalFontFamilyShortcut = ParseGlobalFontFamilyShortcut

local FONT_RENDERING_UNIT_SCOPES = {
    player = "player",
    target = "target",
    targettarget = "targettarget",
    focustarget = "focustarget",
    focus = "focus",
    pet = "pet",
    boss = "boss",
}

local FONT_RENDERING_GROUP_SCOPES = {
    party = "gf_party",
    raid = "gf_raid",
    mythicraid = "gf_raid",
}

local function FontRenderingValueForText(text)
    local boolValue = DetectBoolean(text)
    if tostring(text or ""):find("slug", 1, true) then
        if boolValue == false then return "SMOOTH" end
        return "SLUG"
    end
    if ContainsAny(text, RegistryPhrases[57]) then
        if boolValue == false then return "SMOOTH" end
        return "SHARP"
    end
    if ContainsAny(text, RegistryPhrases[58]) then
        if boolValue == false then return "SHARP" end
        return "SMOOTH"
    end
    return nil
end

local function ParseFontRenderingShortcut(text)
    if not ContainsAny(text, RegistryPhrases[59]) then return nil end
    if ContainsAny(text, RegistryPhrases[60]) then return nil end
    if not ContainsAny(text, RegistryPhrases[61]) then return nil end

    local value = FontRenderingValueForText(text)
    if value == nil then return nil end

    local scopes = {}
    local seen = {}
    local units = DetectUnits(text) or {}
    local groups = DetectGroups(text) or {}
    for i = 1, #units do
        local scope = FONT_RENDERING_UNIT_SCOPES[units[i]]
        if scope and not seen[scope] then
            seen[scope] = true
            scopes[#scopes + 1] = scope
        end
    end
    for i = 1, #groups do
        local scope = FONT_RENDERING_GROUP_SCOPES[groups[i]]
        if scope and not seen[scope] then
            seen[scope] = true
            scopes[#scopes + 1] = scope
        end
    end
    if #scopes == 0 then scopes[1] = "shared" end

    local changes = {}
    for i = 1, #scopes do
        local setting = Registry and Registry:GetSetting("fontScope." .. tostring(scopes[i]) .. ".fontMonochrome")
        if setting then
            changes[#changes + 1] = { setting = setting, value = value, valueLabel = ValueDisplay(setting, value) }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Font Rendering") or "Font Rendering",
        bulkSafe = #changes > 1,
        summary = "Changes font rendering between smooth, sharp monochrome, and Slug text.",
    }
end
P.ParseFontRenderingShortcut = ParseFontRenderingShortcut

local function FontScopeTargetsForText(text)
    local scopes = {}
    local seen = {}
    local units = DetectUnits(text) or {}
    local groups = DetectGroups(text) or {}
    for i = 1, #units do
        local scope = FONT_RENDERING_UNIT_SCOPES[units[i]]
        if scope and not seen[scope] then
            seen[scope] = true
            scopes[#scopes + 1] = scope
        end
    end
    for i = 1, #groups do
        local scope = FONT_RENDERING_GROUP_SCOPES[groups[i]]
        if scope and not seen[scope] then
            seen[scope] = true
            scopes[#scopes + 1] = scope
        end
    end
    if #scopes == 0 then scopes[1] = "shared" end
    return scopes
end

local function ParseFontTextOpacityShortcut(text)
    if not ContainsAny(text, RegistryPhrases[62]) then return nil end
    if ContainsAny(text, RegistryPhrases[63]) then return nil end
    if ContainsAny(text, RegistryPhrases[64]) then return nil end

    local value = FirstNumber(text)
    if value == nil then return nil end
    if value > 1 then value = value / 100 end

    local changes = {}
    local scopes = FontScopeTargetsForText(text)
    for i = 1, #scopes do
        local setting = Registry and Registry:GetSetting("fontScope." .. tostring(scopes[i]) .. ".fontTextAlpha")
        if setting then
            changes[#changes + 1] = { setting = setting, value = value, valueLabel = ValueDisplay(setting, value) }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Text Opacity") or "Text Opacity",
        bulkSafe = #changes > 1,
        summary = "Changes scoped font text opacity.",
    }
end
P.ParseFontTextOpacityShortcut = ParseFontTextOpacityShortcut

P._AddFontTextColorChange = function(changes, key, value)
    local setting = Registry and Registry:GetSetting(key)
    if setting then changes[#changes + 1] = { setting = setting, value = value } end
end

P._ParseAllTextWhiteShortcut = function(text)
    if not ContainsAny(text, RegistryPhrases[65]) then return nil end
    if not ContainsAny(text, RegistryPhrases[66]) then return nil end
    if ContainsAny(text, RegistryPhrases[67]) then return nil end

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
    local targetValue = P.TargetAfterLastConnector and P.TargetAfterLastConnector(text) or tostring(text or ""):match("%s+to%s+(.+)$")
    if targetValue and spec then
        if ContainsAny(targetValue, {
            "single color", "single colour", "solid color", "solid colour",
            "fixed color", "fixed colour", "one color", "one colour", "font color", "font colour",
        }) then return true end
        if ContainsAny(targetValue, RegistryPhrases[68]) then return true end
        if spec.key == "nameColorMode" and ContainsAny(targetValue, RegistryPhrases[69]) then return false end
        if spec.key == "colorHealthTextByHealth" and ContainsAny(targetValue, RegistryPhrases[70]) then return false end
        if spec.key == "colorPowerTextByType" and ContainsAny(targetValue, RegistryPhrases[71]) then return false end
        if spec.key == "npcNameRed" and ContainsAny(targetValue, RegistryPhrases[72]) then return false end
    end
    if boolValue == false or ContainsAny(text, RegistryPhrases[73]) then return true end
    if not spec then return false end
    if spec.key == "nameColorMode" then
        return ContainsAny(text, RegistryPhrases[74])
    end
    if spec.key == "colorHealthTextByHealth" then
        return ContainsAny(text, RegistryPhrases[75])
    end
    if spec.key == "colorPowerTextByType" then
        return ContainsAny(text, RegistryPhrases[76])
    end
    if spec.key == "npcNameRed" then
        return ContainsAny(text, RegistryPhrases[77])
    end
    return false
end

P.BARE_FONT_TEXT_COLOR_MODES = P.BARE_FONT_TEXT_COLOR_MODES or {
    {
        key = "colorHealthTextByHealth",
        subjects = { "hp color text", "hp text color", "health color text", "health text color" },
        label = "Choose Health Text Color Mode",
        summary = "Asks whether HP text should use the font color, class color, or health gradient.",
        choices = {
            { value = "DEFAULT", label = "Single color (Font Color)", summary = "Uses the configured fixed font color for HP text." },
            { value = "CLASS", label = "Class Color", summary = "Colors HP text by the unit's class." },
            { value = "HEALTH", label = "Health Gradient", summary = "Colors HP text dynamically by current health." },
        },
    },
    {
        key = "colorPowerTextByType",
        subjects = { "power color text", "power text color", "mana color text", "mana text color", "resource color text", "resource text color" },
        label = "Choose Power Text Color Mode",
        summary = "Asks whether power text should use one fixed font color or the unit's resource color.",
        choices = {
            { value = "DEFAULT", label = "Single color (Font Color)", summary = "Uses the configured fixed font color for power text." },
            { value = "RESOURCE", label = "Resource Type Color", summary = "Colors power text by the unit's current resource type." },
        },
    },
    {
        key = "nameColorMode",
        subjects = { "name color", "name text color" },
        label = "Choose Name Text Color Mode",
        summary = "Asks whether names should use one fixed font color or class colors.",
        choices = {
            { value = "DEFAULT", label = "Single color (Font Color)", summary = "Uses the configured fixed font color for names." },
            { value = "CLASS", label = "Class Color", summary = "Colors player names by class." },
        },
    },
    {
        key = "npcNameRed",
        subjects = { "npc name color", "npc name text color", "npc text color" },
        label = "Choose NPC Name Text Color Mode",
        summary = "Asks which supported color mode NPC names should use.",
        choices = {
            { value = "DEFAULT", label = "Single color (Font Color)", summary = "Uses the configured fixed font color for NPC names." },
            { value = "NPC", label = "NPC Reaction Color", summary = "Colors NPC names by reaction." },
            { value = "CLASS", label = "NPC Class Color", summary = "Uses the configured NPC class-color mode." },
        },
    },
}

P.BARE_FONT_SCOPE_PREFIXES = P.BARE_FONT_SCOPE_PREFIXES or {
    "target of target", "focus target", "mythic raid",
    "targettarget", "focustarget", "global", "shared", "player",
    "target", "focus", "pet", "boss", "party", "raid",
}

-- Value-less text-color commands are exact control requests, not permission to
-- guess a mode. Resolve their shared/scoped owner in constant time and retain
-- that exact setting while the user chooses one of its real enum values.
function P.ParseBareFontTextColorModeChoice(text)
    text = tostring(text or ""):lower()
    if not text:find("color", 1, true) and not text:find("colour", 1, true) then return nil end
    text = text:gsub("colour", "color"):gsub("[%p%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    text = text:gsub("^please%s+", "")
        :gsub("^can you%s+", "")
        :gsub("^could you%s+", "")
        :gsub("^would you%s+", "")
        :gsub("^i want to%s+", "")
        :gsub("^i would like to%s+", "")
    local action = text:match("^(%S+)%s+")
    if action ~= "set" and action ~= "change" and action ~= "adjust"
        and action ~= "modify" and action ~= "update"
    then
        return nil
    end
    text = text:sub(#action + 2)
    text = text:gsub("^the%s+", ""):gsub("%s+please$", "")

    local scope = DetectGlobalScope(text) or "shared"
    for _, prefix in ipairs(P.BARE_FONT_SCOPE_PREFIXES) do
        if text == prefix then return nil end
        if text:sub(1, #prefix + 1) == prefix .. " " then
            text = text:sub(#prefix + 2)
            break
        end
    end
    if scope == "gf_mythicraid" then scope = "gf_raid" end

    for _, spec in ipairs(P.BARE_FONT_TEXT_COLOR_MODES) do
        for _, subject in ipairs(spec.subjects) do
            if text == subject then
                local setting = Registry and Registry:GetSetting("fontScope." .. tostring(scope) .. "." .. spec.key)
                if not setting then return nil end
                local choices = {}
                for i = 1, #spec.choices do
                    local choice = spec.choices[i]
                    choices[i] = {
                        setting = setting,
                        value = choice.value,
                        label = tostring(setting.label or spec.label) .. ": " .. choice.label,
                        summary = choice.summary,
                    }
                end
                return {
                    kind = "ambiguous",
                    choices = choices,
                    label = spec.label,
                    summary = spec.summary,
                    textColorModeKey = spec.key,
                }
            end
        end
    end
    return nil
end

function P.ParseBareHPTextColorModeChoice(text)
    local plan = P.ParseBareFontTextColorModeChoice(text)
    return plan and plan.textColorModeKey == "colorHealthTextByHealth" and plan or nil
end

function P.ParseHPTextColorModePriority(text)
    local healthText = ContainsAny(text, { "hp text", "health text", "hp color text", "health color text" })
    if not healthText then return nil end
    local single = ContainsAny(text, {
        "single color", "single colour", "solid color", "solid colour",
        "fixed color", "fixed colour", "one color", "one colour", "font color", "font colour",
    })
    local gradient = ContainsAny(text, { "health gradient", "hp gradient", "by health" })
        or (text:find("gradient", 1, true) and not single)
    local class = ContainsAny(text, { "class color", "class colour", "by class" })
    if not single and not gradient and not class then return P.ParseBareHPTextColorModeChoice(text) end
    local scope = DetectGlobalScope(text) or "shared"
    if scope == "gf_mythicraid" then scope = "gf_raid" end
    if scope == "gf_party" or scope == "gf_raid" then scope = "shared" end
    local setting = Registry and Registry:GetSetting("fontScope." .. tostring(scope) .. ".colorHealthTextByHealth")
    if not setting then return nil end
    local changes = {}
    local override = scope ~= "shared" and Registry:GetSetting("fontScope." .. tostring(scope) .. ".override") or nil
    if override then changes[#changes + 1] = { setting = override, value = true } end
    local value = single and "DEFAULT" or (class and "CLASS" or "HEALTH")
    changes[#changes + 1] = { setting = setting, value = value }
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Health Text Color Mode",
        summary = single and "Changes HP text to the configured font color."
            or (class and "Colors HP text by the unit's class."
                or "Colors HP text dynamically with the health gradient."),
    }
end

local function ParseScopedFontTextColorShortcut(text)
    local allWhite = P._ParseAllTextWhiteShortcut(text)
    if allWhite then return allWhite end

    local scope = DetectGlobalScope(text)
    if ContainsAny(text, RegistryPhrases[78]) then return nil end
    if ContainsAny(text, RegistryPhrases[79]) then return nil end

    local spec
    if ContainsAny(text, RegistryPhrases[80]) or (
        ContainsAny(text, RegistryPhrases[81]) and ContainsAny(text, RegistryPhrases[82])
    ) or (
        ContainsAny(text, RegistryPhrases[83]) and ContainsAny(text, RegistryPhrases[84]) and not ContainsAny(text, RegistryPhrases[85])
    ) then
        spec = { key = "colorPowerTextByType", on = "RESOURCE", label = "Power Text Color Mode" }
    elseif ContainsAny(text, RegistryPhrases[86]) then
        local class = ContainsAny(text, { "class color", "class colour", "by class" })
        spec = { key = "colorHealthTextByHealth", on = class and "CLASS" or "HEALTH", label = "Health Text Color Mode" }
    elseif ContainsAny(text, RegistryPhrases[87]) then
        local npcClass = ContainsAny(text, RegistryPhrases[88])
        spec = {
            key = "npcNameRed",
            on = npcClass and "CLASS" or "NPC",
            label = "NPC Name Text Color",
        }
    elseif ContainsAny(text, RegistryPhrases[89]) then
        spec = { key = "nameColorMode", on = "CLASS", label = "Name Text Color Mode" }
    end
    if not spec then return nil end
    scope = scope or "shared"
    if scope == "gf_mythicraid" then scope = "gf_raid" end
    if (scope == "gf_party" or scope == "gf_raid") and spec.key ~= "nameColorMode" then return nil end

    local setting = Registry and Registry:GetSetting("fontScope." .. tostring(scope) .. "." .. spec.key)
    if not setting then return nil end
    -- This lane picks the value from the SPEC, not from the sentence: anything
    -- that is not a "back to default" request becomes spec.on. For Name Text
    -- Color Mode that is hardcoded CLASS, and the mode words below belong to
    -- sibling controls it cannot express -- so "set target name color to
    -- health" was silently written as Class colour, a value the player never
    -- named. Name Text Color Mode offers only Default and Class; stand down and
    -- let a lane that can answer the real question have the sentence.
    if spec.key == "nameColorMode"
        and ContainsAny(text, RegistryPhrases[428])
        and not P._FontTextColorDefaultIntent(text, spec)
    then
        return nil
    end
    local bareChoice = spec.key == "colorHealthTextByHealth" and P.ParseBareHPTextColorModeChoice(text)
    if bareChoice then return bareChoice end
    local value
    if P._FontTextColorDefaultIntent(text, spec) then
        value = "DEFAULT"
    else
        value = spec.on
    end

    local changes = {}
    local override = Registry and Registry:GetSetting("fontScope." .. tostring(scope) .. ".override")
    if ContainsAny(text, RegistryPhrases[90]) and override then
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

function P.ParseAmbiguousFontTextColorShortcut(text)
    if not ContainsAny(text, RegistryPhrases[91]) then return nil end
    if ContainsAny(text, RegistryPhrases[92]) then return nil end
    if ContainsAny(text, RegistryPhrases[93]) then return nil end

    local units = DetectUnits(text)
    local groups = DetectGroups(text)
    local scopeText
    if #units > 0 then
        scopeText = tostring(units[1]):gsub("^%l", string.upper)
    elseif #groups > 0 then
        scopeText = tostring(groups[1] == "mythicraid" and "Mythic Raid" or groups[1]):gsub("^%l", string.upper)
    else
        scopeText = "the frame"
    end

    return {
        kind = "answer",
        status = "ambiguous",
        result = "ambiguous",
        text = "Which " .. scopeText .. " text color do you mean: Name Text, Health Text, or Power Text?\nI did not change anything because those are separate MSUF settings.\nExamples: 'set target name text color to class', 'set target health text color to health', or 'set target power text color to default'.",
        summary = "Clarifies generic text color before changing a specific text-color mode.",
    }
end

function P.ParseAmbiguousColorShortcut(text, raw)
    if not ContainsAny(text, RegistryPhrases[94]) then return nil end
    if not ContainsAny(text, RegistryPhrases[95]) then return nil end
    if not (P.ColorShortcutValue and P.ColorShortcutValue(text, raw)) then return nil end
    if ContainsAny(text, RegistryPhrases[96]) then return nil end

    return {
        kind = "answer",
        status = "ambiguous",
        result = "ambiguous",
        text = "Which color do you want to change? MSUF has separate colors for health bar, power bar, name text, health text, power text, class resources, cast bars, group borders, aura borders, and status indicators.\nI did not change anything from the generic color request.\nExamples: 'set target health bar color to yellow', 'set target name text color to class', or 'set party group border color to yellow'.",
        summary = "Clarifies a color request without a setting target.",
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
    "bar", "bars", "bar gradient", "bar gradients", "gradient", "gradients", "gradient direction",
    "gradient strength", "texture", "textures", "foreground", "background",
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
    if ContainsAny(text, RegistryPhrases[97]) then return true end
    return ContainsAny(text, RegistryPhrases[98])
        and ContainsAny(text, RegistryPhrases[99])
end

function P.ParseInterruptReadyRegistryShortcut(text, raw)
    if ContainsAny(text, RegistryPhrases[100]) then return nil end
    if ContainsAny(text, RegistryPhrases[101]) then return nil end
    if not P.HasInterruptReadyIntent(text) then return nil end

    local key
    local relativeDelta
    local direction = DetectDirection(text, {})
    if ContainsAny(text, RegistryPhrases[102]) then
        key = "general.kickReadyAutoSize"
    elseif ContainsAny(text, RegistryPhrases[103]) then
        key = "general.kickReadyStyle"
    elseif ContainsAny(text, RegistryPhrases[104])
        and direction
        and not ContainsAny(text, RegistryPhrases[105])
    then
        key = "general.kickReadyAnchor"
    elseif ContainsAny(text, RegistryPhrases[106]) then
        key = "general.kickReadyOffsetX"
    elseif ContainsAny(text, RegistryPhrases[107]) then
        key = "general.kickReadyOffsetY"
    elseif ContainsAny(text, RegistryPhrases[108]) and (direction == "left" or direction == "right") then
        key = "general.kickReadyOffsetX"
    elseif ContainsAny(text, RegistryPhrases[109]) and (direction == "up" or direction == "down") then
        key = "general.kickReadyOffsetY"
    elseif ContainsAny(text, RegistryPhrases[110]) then
        key = "general.kickReadySize"
    elseif ContainsAny(text, RegistryPhrases[111]) then
        key = "general.kickReadyShowTarget"
    elseif ContainsAny(text, RegistryPhrases[112]) then
        key = "general.kickReadyShowFocus"
    elseif ContainsAny(text, RegistryPhrases[113]) then
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
            if ContainsAny(text, RegistryPhrases[114]) then value = true end
            if ContainsAny(text, RegistryPhrases[115]) then value = false end
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
    if ContainsAny(text, RegistryPhrases[116]) then return nil end
    if not ContainsAny(text, RegistryPhrases[117]) then return nil end
    if ContainsAny(text, RegistryPhrases[118]) then return nil end

    local changes = {}
    local direction = DetectDirection(text, {})
    if ContainsAny(text, RegistryPhrases[119]) and direction then
        local key = (direction == "left" or direction == "right") and "general.focusKickIconOffsetX" or "general.focusKickIconOffsetY"
        local amount = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then amount = -amount end
        AddRegisteredChange(changes, key, nil, amount, direction)
    elseif ContainsAny(text, RegistryPhrases[120]) then
        AddRegisteredChange(changes, "general.focusKickIconOffsetX", FirstNumber(text))
    elseif ContainsAny(text, RegistryPhrases[121]) then
        AddRegisteredChange(changes, "general.focusKickIconOffsetY", FirstNumber(text))
    elseif ContainsAny(text, RegistryPhrases[122]) then
        local setting = Registry and Registry:GetSetting("general.focusKickTextSize")
        local relativeDelta = setting and RelativeNumberDeltaForText(setting, text) or nil
        local value = relativeDelta == nil and FirstNumber(text) or nil
        AddRegisteredChange(changes, "general.focusKickTextSize", value, relativeDelta)
    elseif ContainsAny(text, RegistryPhrases[123]) then
        local width = Registry and Registry:GetSetting("general.focusKickIconWidth")
        local height = Registry and Registry:GetSetting("general.focusKickIconHeight")
        local relativeWidth = width and RelativeNumberDeltaForText(width, text) or nil
        local relativeHeight = height and RelativeNumberDeltaForText(height, text) or nil
        local value = (relativeWidth == nil and relativeHeight == nil) and FirstNumber(text) or nil
        if ContainsAny(text, RegistryPhrases[124]) and not ContainsAny(text, RegistryPhrases[125]) then
            AddRegisteredChange(changes, "general.focusKickIconWidth", value, relativeWidth)
        elseif ContainsAny(text, RegistryPhrases[126]) and not ContainsAny(text, RegistryPhrases[127]) then
            AddRegisteredChange(changes, "general.focusKickIconHeight", value, relativeHeight)
        else
            AddRegisteredChange(changes, "general.focusKickIconWidth", value, relativeWidth)
            AddRegisteredChange(changes, "general.focusKickIconHeight", value, relativeHeight)
        end
    else
        local value = DetectBoolean(text)
        if value == nil and ContainsAny(text, RegistryPhrases[128]) then value = true end
        if value == nil and ContainsAny(text, RegistryPhrases[129]) then value = false end
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
    if not ContainsAny(text, RegistryPhrases[130]) then return nil end
    if ContainsAny(text, RegistryPhrases[131]) then return nil end
    for i = 1, #(P.UNIT_STATUS_SYMBOL_SPECS or {}) do
        local spec = P.UNIT_STATUS_SYMBOL_SPECS[i]
        if ContainsAny(text, spec.terms) then return spec end
    end
    return nil
end

function P.ParseUnitStatusSymbolRegistryShortcut(text)
    if ContainsAny(text, RegistryPhrases[132]) then return nil end
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
        if value == nil and setting and ContainsAny(text, RegistryPhrases[133]) then value = "DEFAULT" end
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

local function ExplicitUnitAndGroupScopesForRegistry(text)
    local units, groups = ExplicitScopes(text)
    if #units == 0 then
        local pageUnit = CurrentRegistryPageUnit()
        if pageUnit then units = { pageUnit } end
    end
    return units, groups
end

local function ParseUnitTextBooleanDetailShortcut(text)
    if ContainsAny(text, RegistryPhrases[134]) then return nil end
    if not ContainsAny(text, RegistryPhrases[135]) then return nil end
    local value = DetectBoolean(text)
    if value == nil then value = true end
    local units, groups = ExplicitUnitAndGroupScopesForRegistry(text)
    local changes = {}
    for i = 1, #units do
        AddRegisteredChange(changes, tostring(units[i]) .. ".healthTextDecimals", value)
    end
    for i = 1, #groups do
        AddRegisteredChange(changes, "gf_" .. tostring(groups[i]) .. ".healthTextDecimals", value)
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Health Text Decimals",
        bulkSafe = #changes > 1,
        summary = "Changes Health Text Decimals for the matched frame scope.",
    }
end

local function ParseUnitCoreBooleanShortcut(text)
    if ContainsAny(text, RegistryPhrases[136]) then return nil end
    local attr
    local label
    if ContainsAny(text, RegistryPhrases[137]) then
        attr = "powerSmoothFill"
        label = "Power Bar Smooth Fill"
    elseif ContainsAny(text, RegistryPhrases[138]) then
        attr = "reverseFillBars"
        label = "Reverse Fill Direction"
    elseif ContainsAny(text, RegistryPhrases[139]) then
        attr = "smoothFill"
        label = "Smooth Health Fill"
    else
        return nil
    end
    local value = DetectBoolean(text)
    if value == nil then value = true end
    local units, groups = ExplicitUnitAndGroupScopesForRegistry(text)
    if #units == 0 and #groups == 0 then return nil end
    local changes = {}
    for i = 1, #units do
        AddRegisteredChange(changes, tostring(units[i]) .. "." .. attr, value)
    end
    for i = 1, #groups do
        AddRegisteredChange(changes, "gf_" .. tostring(groups[i]) .. "." .. attr, value)
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes the matching Unit Frame fill option.",
    }
end

local function RelativeLayerDeltaForRegistryText(text)
    local amount = FirstNumber(text) or 1
    if ContainsAny(text, RegistryPhrases[140]) then
        return -amount
    end
    if ContainsAny(text, RegistryPhrases[141]) then
        return amount
    end
    return nil
end

local function ParseUnitStatusDetailShortcut(text)
    if ContainsAny(text, RegistryPhrases[142]) then return nil end
    if not ContainsAny(text, RegistryPhrases[143]) then return nil end
    local wantsAnchor = ContainsAny(text, RegistryPhrases[144])
    local wantsX = ContainsAny(text, RegistryPhrases[145])
    local wantsY = ContainsAny(text, RegistryPhrases[146])
    local wantsSize = ContainsAny(text, RegistryPhrases[147])
    local wantsLayer = ContainsAny(text, RegistryPhrases[148])
    local wantsStyle = ContainsAny(text, RegistryPhrases[149])
    local wantsVisibility = ContainsAny(text, RegistryPhrases[150])
    if not (wantsAnchor or wantsX or wantsY or wantsSize or wantsLayer or wantsStyle or wantsVisibility) then return nil end

    local units = ExplicitUnitAndGroupScopesForRegistry(text)
    if #units == 0 then return nil end
    local changes = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        local spec = A.ResolveUnitStatusSpec and A.ResolveUnitStatusSpec(unit, text) or nil
        if spec then
            local attr
            if wantsX then
                attr = spec.x
            elseif wantsY then
                attr = spec.y
            elseif wantsAnchor then
                attr = spec.anchor
            elseif wantsSize then
                attr = spec.size
            elseif wantsLayer then
                attr = spec.layer
            elseif wantsStyle then
                attr = "raidGroupNameStyle"
            elseif wantsVisibility then
                attr = spec.show
            end
            local setting = attr and Registry and Registry:GetSetting(unit .. "." .. tostring(attr))
            if setting then
                local value
                local relativeDelta = wantsLayer and RelativeLayerDeltaForRegistryText(text) or nil
                if setting.type == "boolean" then
                    value = DetectBoolean(text)
                    if value == nil then value = true end
                elseif setting.type == "number" then
                    if relativeDelta == nil then
                        value = FirstNumber(text)
                    end
                elseif setting.type == "enum" then
                    value = EnumValueForText(setting, text)
                else
                    value = ValueForRegistrySetting(setting, text)
                end
                if value ~= nil or relativeDelta ~= nil then
                    changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, valueLabel = value ~= nil and ValueDisplay(setting, value) or nil }
                end
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Unit Frame Status Detail",
        bulkSafe = #changes > 1,
        summary = "Changes a unit-frame status indicator detail option.",
    }
end

local function ParseBossTargetHighlightShortcut(text)
    if ContainsAny(text, RegistryPhrases[151]) then return nil end
    if not ContainsAny(text, RegistryPhrases[152]) then return nil end
    local value = DetectBoolean(text)
    if value == nil then value = true end
    local changes = {}
    AddRegisteredChange(changes, "general.bossTargetHighlightEnabled", value)
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Boss Target Highlight",
        summary = "Changes Boss Target Highlight visibility.",
    }
end

local function ConcreteGroupScopesForPriority(text)
    local scopes = {}
    local hasMythic = ContainsAny(text, RegistryPhrases[153])
    if ContainsAny(text, RegistryPhrases[154]) then scopes[#scopes + 1] = "party" end
    if ContainsAny(text, RegistryPhrases[155]) and not hasMythic then scopes[#scopes + 1] = "raid" end
    if hasMythic then scopes[#scopes + 1] = "mythicraid" end
    return scopes
end

local function ParseGroupBorderColorShortcut(text, raw)
    if not ContainsAny(text, RegistryPhrases[156]) then return nil end
    if ContainsAny(text, RegistryPhrases[157]) then return nil end
    local scopes = ConcreteGroupScopesForPriority(text)
    if #scopes == 0 then return nil end
    local r, g, b, label = ExtractColor(raw, text)
    if r == nil then return nil end
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".groupBorderColor", { r = r, g = g, b = b, label = label })
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Group Border Color",
        bulkSafe = #changes > 1,
        summary = "Changes the matching group-frame border color.",
    }
end

local function ParseGroupTextureStringShortcut(text, raw)
    if not ContainsAny(text, RegistryPhrases[158]) then return nil end
    if ContainsAny(text, RegistryPhrases[159]) then return nil end
    local scopes = ConcreteGroupScopesForPriority(text)
    if #scopes == 0 then return nil end

    local keySuffix
    local label
    local useBarScope = false
    if ContainsAny(text, RegistryPhrases[160]) then
        keySuffix = "barBackgroundTexture"
        label = "Group Bar Background Texture"
        useBarScope = true
    elseif ContainsAny(text, RegistryPhrases[161]) then
        keySuffix = "barTexture"
        label = "Group Bar Texture"
        useBarScope = true
    elseif ContainsAny(text, RegistryPhrases[162]) then
        keySuffix = "barBgTexture"
        label = "Group Frame Background Texture"
    elseif ContainsAny(text, RegistryPhrases[163]) then
        keySuffix = "barTexture"
        label = "Group Frame Foreground Texture"
    else
        return nil
    end

    local changes = {}
    for i = 1, #scopes do
        local scope = tostring(scopes[i])
        local key = useBarScope and ("barScope.gf_" .. scope .. "." .. keySuffix) or ("gf_" .. scope .. "." .. keySuffix)
        local setting = Registry and Registry:GetSetting(key)
        local value = setting and ValueForRegistrySetting(setting, text, raw)
        if value ~= nil then
            changes[#changes + 1] = { setting = setting, value = value, valueLabel = ValueDisplay(setting, value) }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes the matching group texture setting.",
    }
end

local function ParseDispelOverlayHealthOnlyShortcut(text)
    if not ContainsAny(text, RegistryPhrases[164]) then return nil end
    if not ContainsAny(text, RegistryPhrases[165]) then return nil end
    if ContainsAny(text, RegistryPhrases[166]) then return nil end
    local value = DetectBoolean(text)
    if value == nil then value = true end
    local units, groups = ExplicitUnitAndGroupScopesForRegistry(text)
    local changes = {}
    for i = 1, #units do
        AddRegisteredChange(changes, "barScope." .. tostring(units[i]) .. ".unitDispelOverlayOnHealth", value)
    end
    for i = 1, #groups do
        AddRegisteredChange(changes, "gf_" .. tostring(groups[i]) .. ".dispelOverlayOnHealth", value)
    end
    if #changes == 0 and #units == 0 and #groups == 0 then
        AddRegisteredChange(changes, "general.unitDispelOverlayOnHealth", value)
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Dispel Overlay Current Health Only",
        bulkSafe = #changes > 1,
        summary = "Changes whether dispel overlays are drawn only over the current-health part of the bar.",
    }
end

local function HasClassPowerPriorityIntent(text)
    return ContainsAny(text, RegistryPhrases[167])
end

local function ParseClassPowerBooleanDetailShortcut(text)
    if not HasClassPowerPriorityIntent(text) then return nil end
    if ContainsAny(text, RegistryPhrases[168]) then return nil end
    if HasPhrase(text, "text x") or HasPhrase(text, "text y") or HasPhrase(text, "number x") or HasPhrase(text, "number y") then return nil end
    local value = DetectBoolean(text)
    if value == nil then value = true end

    local key
    local label
    if ContainsAny(text, RegistryPhrases[169]) then
        key = "bars.playerHPBarSmoothFill"
        label = "Class Resources Player HP Smooth Fill"
    elseif ContainsAny(text, RegistryPhrases[170]) then
        key = "bars.playerHPBarEnabled"
        label = "Class Resources Player HP Bar"
    elseif ContainsAny(text, RegistryPhrases[171]) then
        key = "bars.classPowerShowText"
        label = "Class Resource Text"
    elseif ContainsAny(text, RegistryPhrases[172]) then
        key = "bars.classPowerFillReverse"
        label = "Class Resource Fill Direction"
    else
        return nil
    end

    local changes = {}
    AddRegisteredChange(changes, key, value)
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        summary = "Changes the matching Class Resources option.",
    }
end

local function ParsePowerColorPriorityShortcut(text, raw)
    if ContainsAny(text, RegistryPhrases[173]) then return nil end
    if not ContainsAny(text, RegistryPhrases[174]) then return nil end
    return A._ParsePowerColorShortcut and A._ParsePowerColorShortcut(text, raw) or nil
end

P.ParseRegistryPriorityShortcut = function(text, raw)
    return ParseBossTargetHighlightShortcut(text)
        or ParseGroupBorderColorShortcut(text, raw)
        or ParseGroupTextureStringShortcut(text, raw)
        or ParseDispelOverlayHealthOnlyShortcut(text)
        or ParseClassPowerBooleanDetailShortcut(text)
        or ParsePowerColorPriorityShortcut(text, raw)
        or ParseUnitTextBooleanDetailShortcut(text)
        or ParseUnitStatusDetailShortcut(text)
        or ParseUnitCoreBooleanShortcut(text)
end

function P.ParseAlphaExcludeTextPortraitShortcut(text)
    if ContainsAny(text, RegistryPhrases[177]) then return nil end
    if not ContainsAny(text, RegistryPhrases[178]) then return nil end

    local value = DetectBoolean(text)
    if value == nil then value = true end
    local explicitUnits, explicitGroups = ExplicitScopes(text)
    local units = {}
    local groups = {}
    local concrete = false

    if HasAllScopeIntent(text) then
        if ContainsAny(text, RegistryPhrases[179]) or #explicitGroups > 0 then
            for i = 1, #ALL_GROUPS do groups[#groups + 1] = ALL_GROUPS[i] end
            concrete = true
        elseif ContainsAny(text, RegistryPhrases[180]) or #explicitUnits > 0 then
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
            elseif ContainsAny(text, RegistryPhrases[181]) then
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
    if not ContainsAny(text, RegistryPhrases[182]) then return false end
    if ContainsAny(text, RegistryPhrases[183]) then return false end
    if ContainsAny(text, CASTBAR_BACKEND_PROVIDER_TERMS) then return true end
    if ContainsAny(text, CASTBAR_BACKEND_BLOCKERS) then return false end
    if ContainsAny(text, RegistryPhrases[184]) then return true end
    if ContainsAny(text, RegistryPhrases[185]) then return true end
    return false
end

local function CastbarBackendValueForText(text)
    if ContainsAny(text, RegistryPhrases[186]) and not ContainsAny(text, RegistryPhrases[187]) then
        return "HIDE"
    end
    if ContainsAny(text, RegistryPhrases[188]) then
        return "BLIZZARD"
    end
    if ContainsAny(text, RegistryPhrases[189]) then
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
    if HasAllScopeIntent(text) or ContainsAny(text, RegistryPhrases[190]) then
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
    if not ContainsAny(text, RegistryPhrases[191]) then return nil end
    if ContainsAny(text, RegistryPhrases[192]) then return nil end
    if ContainsAny(text, RegistryPhrases[193]) then return nil end
    local direction = DetectDirection(text, {})
    local naturalPlacement = (direction or ContainsAny(text, RegistryPhrases[194]))
        and ContainsAny(text, RegistryPhrases[195])
    if not ContainsAny(text, RegistryPhrases[196]) and not naturalPlacement then return nil end
    if ContainsAny(text, RegistryPhrases[197]) then return nil end

    local field
    local label
    if ContainsAny(text, RegistryPhrases[198])
        or (naturalPlacement and ContainsAny(text, RegistryPhrases[199]))
    then
        field = "IconPosition"
        label = "Cast Bar Icon Position"
    elseif ContainsAny(text, RegistryPhrases[200])
        or (naturalPlacement and ContainsAny(text, RegistryPhrases[201]))
    then
        field = "SpellNamePosition"
        label = "Cast Bar Spell Name Position"
    elseif ContainsAny(text, RegistryPhrases[202])
        or (naturalPlacement and ContainsAny(text, RegistryPhrases[203]))
    then
        field = "TimePosition"
        label = "Cast Bar Time Position"
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
        if setting and value == nil and ContainsAny(text, RegistryPhrases[204]) then
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
    if ContainsAny(text, RegistryPhrases[205]) then return nil end
    if not ContainsAny(text, RegistryPhrases[206]) then return nil end

    local value = DetectBoolean(text)
    if value == nil then value = true end

    local explicitUnits, explicitGroups = ExplicitScopes(text)
    local units = {}
    local groups = {}
    local concrete = false

    if HasAllScopeIntent(text) then
        if ContainsAny(text, RegistryPhrases[207]) or #explicitGroups > 0 then
            for i = 1, #ALL_GROUPS do groups[#groups + 1] = ALL_GROUPS[i] end
            concrete = true
        elseif ContainsAny(text, RegistryPhrases[208]) or #explicitUnits > 0 then
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
    local only = ContainsAny(text, RegistryPhrases[209])
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

local BAR_GRADIENT_COLOR_TERMS = {
    "color", "colors", "colour", "colours", "farbe", "farben", "tint",
    "gradient color", "gradient colors", "gradient colour", "gradient colours",
    "gradient stop", "gradient stops", "low color", "mid color", "middle color",
    "high color", "low hp", "mid hp", "high hp", "low health", "mid health", "high health",
}

local function BarGradientDirectionValue(text)
    -- "turn it up" / "tone it down" is intensity wording: "the bar gradient
    -- is too subtle, turn it up" used to write Direction = UP instead of
    -- raising the gradient strength. Mask those phrases before the direction
    -- words are read; genuine direction requests ("gradient from the top",
    -- "gradient direction up") are untouched.
    text = tostring(text or "")
        :gsub("turn%s+it%s+up", " "):gsub("turn%s+it%s+down", " ")
        :gsub("turn%s+up", " "):gsub("turn%s+down", " ")
        :gsub("crank%s+it%s+up", " "):gsub("tone%s+it%s+down", " ")
    if ContainsAny(text, RegistryPhrases[210]) then return "RIGHT" end
    if ContainsAny(text, RegistryPhrases[211]) then return "LEFT" end
    if ContainsAny(text, RegistryPhrases[212]) then return "UP" end
    if ContainsAny(text, RegistryPhrases[213]) then return "DOWN" end
    return nil
end

-- The power bar reads `powerGradientDirection` / `powerGradientStrength` at
-- runtime, while the unsuffixed keys drive the health bar
-- (MSUF_UF_Core.lua:597-610 picks the prefix from `power`). So a request that
-- names the POWER gradient and only the power gradient must not be written to
-- the health key. Not every scope has the power pair; when it does not, the
-- caller keeps its existing barScope key.
function P.PowerGradientKeyForScope(scope, suffix, power, health)
    if not power or health then return nil end
    local key = tostring(scope) .. "." .. tostring(suffix)
    return Registry and Registry:GetSetting(key) and key or nil
end

function P.ParseBarGradientRegistryShortcut(text)
    if ContainsAny(text, RegistryPhrases[214]) then return nil end
    if ContainsAny(text, BAR_GRADIENT_COLOR_TERMS) then return nil end
    if not ContainsAny(text, RegistryPhrases[215]) then
        return nil
    end
    if ContainsAny(text, RegistryPhrases[216]) then return nil end

    local direction = BarGradientDirectionValue(text)
    local value = DetectBoolean(text)
    if value == nil and direction == nil then return nil end

    local power = ContainsAny(text, RegistryPhrases[217])
    local health = ContainsAny(text, RegistryPhrases[218])
    local both = ContainsAny(text, RegistryPhrases[219])
    if both then
        health = true
        power = true
    elseif not health and not power then
        health = true
    end

    local explicitUnits, explicitGroups = ExplicitScopes(text)
    local units = {}
    local groups = {}
    local concrete = false
    local hasUnitFrameIntent = ContainsAny(text, RegistryPhrases[220])
    local hasGroupFrameIntent = ContainsAny(text, RegistryPhrases[221])

    if HasAllScopeIntent(text) then
        if hasGroupFrameIntent and not hasUnitFrameIntent then
            for i = 1, #ALL_GROUPS do groups[#groups + 1] = ALL_GROUPS[i] end
            concrete = true
        elseif hasUnitFrameIntent and not hasGroupFrameIntent then
            for i = 1, #ALL_UNITFRAMES do units[#units + 1] = ALL_UNITFRAMES[i] end
            concrete = true
        elseif #explicitUnits > 0 or #explicitGroups > 0 then
            for i = 1, #explicitUnits do units[#units + 1] = explicitUnits[i] end
            for i = 1, #explicitGroups do groups[#groups + 1] = explicitGroups[i] end
            concrete = true
        elseif ContainsAny(text, RegistryPhrases[222]) then
            for i = 1, #ALL_UNITFRAMES do units[#units + 1] = ALL_UNITFRAMES[i] end
            for i = 1, #ALL_GROUPS do groups[#groups + 1] = ALL_GROUPS[i] end
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
    local only = ContainsAny(text, RegistryPhrases[223])
    local seenScopes = {}
    local function AddScopedBarGradient(scope)
        if scope == "gf_mythicraid" then scope = "gf_raid" end
        if seenScopes[scope] then return end
        seenScopes[scope] = true
        if only and scope ~= "shared" then AddRegisteredChange(changes, "barScope." .. tostring(scope) .. ".override", true) end
        if value ~= nil and health then AddRegisteredChange(changes, "barScope." .. tostring(scope) .. ".enableGradient", value) end
        if value ~= nil and power then AddRegisteredChange(changes, "barScope." .. tostring(scope) .. ".enablePowerGradient", value) end
        if direction then
            -- "Turn on the power bar gradient from the left" operates the
            -- barScope gradient as a whole, so its direction belongs to that
            -- system. Only a direction-only request ("set player power gradient
            -- direction to left") targets the power bar's own key.
            local directionOnly = value == nil
            AddRegisteredChange(changes,
                P.PowerGradientKeyForScope(scope, "powerGradientDirection", power and directionOnly, health)
                    or ("barScope." .. tostring(scope) .. ".gradientDirection"),
                direction)
        end
    end

    for i = 1, #units do AddScopedBarGradient(units[i]) end
    for i = 1, #groups do AddScopedBarGradient("gf_" .. tostring(groups[i])) end

    if #changes == 0 then
        if value ~= nil and health then AddRegisteredChange(changes, "general.enableGradient", value) end
        if value ~= nil and power then AddRegisteredChange(changes, "general.enablePowerGradient", value) end
        if direction then
            AddRegisteredChange(changes,
                P.PowerGradientKeyForScope("general", "powerGradientDirection", power, health)
                    or "general.gradientDirection",
                direction)
        end
    end

    if #changes == 0 then return nil end
    local label
    if direction and value == nil then
        label = "Bar Gradient Direction"
    elseif health and power then
        label = "Bar Gradients"
    elseif power then
        label = "Power Bar Gradient"
    else
        label = "HP Bar Gradient"
    end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = concrete and "Changes target-specific bar gradient options." or "Changes Global Bars gradient options.",
    }
end

P.GroupShortcutScopes = function(text)
    local scopes, concrete = GroupAvailabilityScopes(text)
    local allGroups = HasAllScopeIntent(text) or P.HasExactPhraseInList(text, RegistryPhrases[224])
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
    if ContainsAny(text, RegistryPhrases[225]) then return nil end
    if ContainsAny(text, RegistryPhrases[226]) then return nil end
    if not ContainsAny(text, RegistryPhrases[227]) then return nil end

    local attr
    local label
    if ContainsAny(text, RegistryPhrases[228]) then
        attr = "powerShowTank"
        label = "Tank Power"
    elseif ContainsAny(text, RegistryPhrases[229]) then
        attr = "powerShowHealer"
        label = "Healer Power"
    elseif ContainsAny(text, RegistryPhrases[230]) then
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
    if ContainsAny(text, RegistryPhrases[231]) then return nil end
    if not ContainsAny(text, RegistryPhrases[232]) then return nil end

    local attr
    local label
    if ContainsAny(text, RegistryPhrases[233]) then
        attr = "roleIconShowTank"
        label = "Tank Role Icon"
    elseif ContainsAny(text, RegistryPhrases[234]) then
        attr = "roleIconShowHealer"
        label = "Healer Role Icon"
    elseif ContainsAny(text, RegistryPhrases[235]) then
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
    if ContainsAny(text, RegistryPhrases[236]) then return nil end
    if not ContainsAny(text, RegistryPhrases[237]) then return nil end
    if ContainsAny(text, RegistryPhrases[238]) then return nil end
    if not ContainsAny(text, RegistryPhrases[239]) then
        return nil
    end

    local value
    local relativeDelta
    if ContainsAny(text, RegistryPhrases[240]) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = -amount
    elseif ContainsAny(text, RegistryPhrases[241]) then
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
    if ContainsAny(text, RegistryPhrases[242]) then return nil end
    if not ContainsAny(text, RegistryPhrases[243]) then
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
    local alphaIntent = ContainsAny(text, RegistryPhrases[244]) or (ContainsAny(text, RegistryPhrases[245]) and HasPhrase(text, "to"))
    local thresholdIntent = ContainsAny(text, RegistryPhrases[246]) or (value ~= nil and HasPhrase(text, "above")) or (value ~= nil and HasPhrase(text, "over")) or (value ~= nil and HasPhrase(text, "at") and not alphaIntent)

    if ContainsAny(text, RegistryPhrases[247]) then
        local amount = value or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = -amount
        alphaIntent = true
        thresholdIntent = false
    elseif ContainsAny(text, RegistryPhrases[248]) then
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
        if ContainsAny(text, RegistryPhrases[249]) then
            enabled = false
        elseif ContainsAny(text, RegistryPhrases[250]) then
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
    if ContainsAny(text, RegistryPhrases[251]) then return nil end
    if not ContainsAny(text, RegistryPhrases[252]) then return nil end
    if not ContainsAny(text, RegistryPhrases[253]) then return nil end
    local explicitUnits, explicitGroups = ExplicitScopes(text)
    if #explicitUnits > 0 and #explicitGroups == 0 then
        -- A visible Group page must not make an explicit Boss/Target/etc.
        -- request inherit the current Party scope.
        return {
            kind = "answer",
            status = "ambiguous",
            text = "I found multiple matches for that layout wording, but MSUF does not expose a columns setting for Boss or ordinary unit frames. Did you mean Boss Frame spacing/size, or Group Frames > Layout > Max Columns? I did not change anything.",
            summary = "Separates unit-frame layout from group-frame column controls without inheriting the visible Party scope.",
        }
    end
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
    if ContainsAny(text, RegistryPhrases[254]) then
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
    if ContainsAny(text, RegistryPhrases[255]) then return nil end
    if not ContainsAny(text, RegistryPhrases[256]) then
        return nil
    end

    local value = DetectBoolean(text)
    if value == nil then
        value = not ContainsAny(text, RegistryPhrases[257])
    end

    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".preserveRaidGroups", value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame Preserve Raid Groups", "Changes Group Layout raid-group preservation.")
end

P.ParseGroupPlayerFirstInRoleShortcut = function(text)
    if ContainsAny(text, RegistryPhrases[258]) then return nil end
    if not ContainsAny(text, RegistryPhrases[259]) then return nil end
    if not ContainsAny(text, RegistryPhrases[260]) then
        return nil
    end
    local value = DetectBoolean(text)
    if value == nil then value = not ContainsAny(text, RegistryPhrases[261]) end

    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    for i = 1, #scopes do
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".playerFirstInRole", value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame player first in role", "Changes the Player First in Role sorting toggle.")
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
    if ContainsAny(text, RegistryPhrases[269]) then
        return "NON_TANK"
    end
    if ContainsAny(text, RegistryPhrases[270]) then
        return "HEALER"
    end
    if ContainsAny(text, RegistryPhrases[271]) then
        return "TANK"
    end
    if ContainsAny(text, RegistryPhrases[272]) then
        return "ALL"
    end
    return nil
end

local function GroupAggroExplicitScopes(text)
    local scopes = {}
    local mythic = ContainsAny(text, RegistryPhrases[273])
    if mythic then scopes[#scopes + 1] = "mythicraid" end
    if ContainsAny(text, RegistryPhrases[274]) then scopes[#scopes + 1] = "party" end
    if ContainsAny(text, RegistryPhrases[275]) and not mythic then scopes[#scopes + 1] = "raid" end
    if #scopes > 0 then return scopes, true end
    if ContainsAny(text, RegistryPhrases[276]) then
        return { "party", "raid", "mythicraid" }, true
    end
    if ContainsAny(text, RegistryPhrases[277]) then return nil, false, true end
    return nil, false, false
end

P.ParseGroupAggroRoleFilterShortcut = function(text)
    if ContainsAny(text, RegistryPhrases[278]) then return nil end
    if ContainsAny(text, RegistryPhrases[279]) then return nil end
    if not ContainsAny(text, RegistryPhrases[280]) then return nil end
    if not ContainsAny(text, GROUP_AGGRO_ROLE_SCOPE_TERMS) then return nil end
    local roleValue = GroupAggroRoleValueForText(text)
    local hasRoleIntent = ContainsAny(text, GROUP_AGGRO_ROLE_INTENT_TERMS)
        or (roleValue ~= nil and not ContainsAny(text, RegistryPhrases[281]))
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
    if ContainsAny(text, RegistryPhrases[282]) then return nil end
    if not ContainsAny(text, RegistryPhrases[283]) then return nil end
    if DetectBoolean(text) ~= nil and ContainsAny(text, RegistryPhrases[284]) then return nil end
    if not ContainsAny(text, RegistryPhrases[285]) then return nil end

    local sortValue
    local roleOrderValue
    if ContainsAny(text, RegistryPhrases[286]) then
        sortValue = "GROUP_ROLE"
    elseif ContainsAny(text, RegistryPhrases[287]) then
        sortValue = "GROUP"
    elseif ContainsAny(text, RegistryPhrases[288]) then
        sortValue = "NAME"
    elseif ContainsAny(text, RegistryPhrases[289]) then
        sortValue = "ROLE"
    elseif ContainsAny(text, RegistryPhrases[290]) then
        sortValue = "ROLE"
        roleOrderValue = "TANK,HEALER,DAMAGER"
    elseif ContainsAny(text, RegistryPhrases[291]) then
        sortValue = "ROLE"
        roleOrderValue = "HEALER,TANK,DAMAGER"
    elseif ContainsAny(text, RegistryPhrases[292]) then
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
    if ContainsAny(text, RegistryPhrases[293]) then return nil end
    if not ContainsAny(text, RegistryPhrases[294]) then return nil end
    if FirstNumber(text) ~= nil then return nil end
    local explicitMode = ContainsAny(text, RegistryPhrases[295])

    local value
    if ContainsAny(text, RegistryPhrases[296]) then
        value = "auto"
    elseif ContainsAny(text, RegistryPhrases[297]) then
        value = "manual"
    elseif explicitMode and ContainsAny(text, RegistryPhrases[298]) then
        value = "off"
    elseif explicitMode and ContainsAny(text, RegistryPhrases[299]) then
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
    if ContainsAny(text, RegistryPhrases[300]) then return nil end
    if not ContainsAny(text, RegistryPhrases[301]) then return nil end
    if not ContainsAny(text, RegistryPhrases[302]) then return nil end
    local value = FirstNumber(text)
    if value == nil then return nil end

    local scopes, concrete = P.GroupShortcutScopes(text)
    local changes = {}
    local enableHide = ContainsAny(text, RegistryPhrases[303])
    for i = 1, #scopes do
        if enableHide then AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".hideOfflineEnabled", true) end
        AddRegisteredChange(changes, "gf_" .. tostring(scopes[i]) .. ".hideOfflineDelay", value)
    end
    return P.GroupShortcutResponse(text, changes, concrete, "Group frame offline delay", "Changes Group Frame offline-member hiding options.")
end

function P.ParseCastbarFillDirectionRegistryShortcut(text)
    local value
    if ContainsAny(text, RegistryPhrases[312]) then
        value = "LTR"
    elseif ContainsAny(text, RegistryPhrases[313]) or ContainsAny(text, RegistryPhrases[314]) then
        value = "RTL"
    elseif ContainsAny(text, RegistryPhrases[315]) then
        value = "LTR"
    end
    if value == nil then return nil end
    local setting = Registry and Registry:GetSetting("general.castbarFillDirection")
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, valueLabel = ValueDisplay(setting, value) } },
        label = setting.label or "Cast Bar Fill Direction",
        summary = "Changes the Cast Bar fill direction.",
    }
end

P.ParseMiscRegistryShortcut = function(text, raw)
    if ContainsAny(text, RegistryPhrases[304]) then return nil end
    if ContainsAny(text, RegistryPhrases[305]) and not ContainsAny(text, RegistryPhrases[306]) then return nil end
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
    local barGradient = P.ParseBarGradientRegistryShortcut and P.ParseBarGradientRegistryShortcut(text)
    if barGradient then return barGradient end
    local powerGradient = P.ParsePowerBarGradientRegistryShortcut and P.ParsePowerBarGradientRegistryShortcut(text)
    if powerGradient then return powerGradient end
    local globalFont = ParseGlobalFontFamilyShortcut(text, raw)
    if globalFont then return globalFont end
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
    local groupAggroRole = P.ParseGroupAggroRoleFilterShortcut and P.ParseGroupAggroRoleFilterShortcut(text)
    if groupAggroRole then return groupAggroRole end
    local groupBoolean = P.ParseGroupBooleanRegistryShortcut and P.ParseGroupBooleanRegistryShortcut(text)
    if groupBoolean then return groupBoolean end
    local groupNumber = P.ParseGroupNumberRegistryShortcut and P.ParseGroupNumberRegistryShortcut(text)
    if groupNumber then return groupNumber end
    local detachedPower = P.ParseDetachedPowerBarRegistryShortcut and P.ParseDetachedPowerBarRegistryShortcut(text, raw)
    if detachedPower then return detachedPower end
    local castbarFill = P.ParseCastbarFillDirectionRegistryShortcut(text)
    if castbarFill then return castbarFill end
    local key
    local forcedValue
    if ContainsAny(text, RegistryPhrases[307]) then
        if #DetectGroups(text) > 0 and #DetectUnits(text) == 0 then return nil end
        key = "general.statusIconsUseMidnightStyle"
        forcedValue = DetectBoolean(text)
        if forcedValue == nil then forcedValue = true end
    elseif ContainsAny(text, RegistryPhrases[308]) then
        key = "general.globalUiScaleEnabled"
    elseif ContainsAny(text, RegistryPhrases[309]) then
        key = "bars.realtimePowerText"
    elseif ContainsAny(text, RegistryPhrases[310]) then
        key = "gameplay.combatStateColorSync"
        forcedValue = DetectBoolean(text)
        if forcedValue == nil and ContainsAny(text, RegistryPhrases[311]) then forcedValue = true end
    elseif ContainsAny(text, RegistryPhrases[312]) then
        key = "general.castbarFillDirection"
        forcedValue = "LTR"
    elseif ContainsAny(text, RegistryPhrases[313]) then
        key = "general.castbarFillDirection"
        forcedValue = "RTL"
    elseif ContainsAny(text, RegistryPhrases[314]) then
        key = "general.castbarFillDirection"
        forcedValue = "RTL"
    elseif ContainsAny(text, RegistryPhrases[315]) then
        key = "general.castbarFillDirection"
        forcedValue = "LTR"
    elseif ContainsAny(text, RegistryPhrases[316]) then
        key = "gameplay.nameplateMeleeSpellID"
    elseif ContainsAny(text, RegistryPhrases[317]) then
        if ContainsAny(text, RegistryPhrases[318]) then return nil end
        key = "general.slashMenuSnapEnabled"
    elseif ContainsAny(text, RegistryPhrases[319]) then
        key = "general.hideAdvancedMenu"
    elseif ContainsAny(text, RegistryPhrases[320]) then
        key = "general.reduceMotion"
    elseif ContainsAny(text, RegistryPhrases[321]) then
        key = "general.showNavigationIcons"
    elseif ContainsAny(text, RegistryPhrases[322]) then
        key = "general.showWelcomeMessage"
    elseif ContainsAny(text, RegistryPhrases[323]) then
        key = "general.versionCheckEnabled"
    elseif ContainsAny(text, RegistryPhrases[324]) then
        key = "general.showMinimapIcon"
    elseif ContainsAny(text, RegistryPhrases[325]) then
        key = "general.playTargetSelectLostSounds"
    elseif ContainsAny(text, RegistryPhrases[328]) then
        key = "general.menuLocale"
    elseif ContainsAny(text, RegistryPhrases[329]) then
        key = "general.dropdownStyleMode"
    elseif ContainsAny(text, RegistryPhrases[330]) then
        if ContainsAny(text, RegistryPhrases[331]) then return nil end
        key = "general.styleEnabled"
    elseif ContainsAny(text, RegistryPhrases[332]) and ContainsAny(text, RegistryPhrases[333]) then
        key = "general.unitTooltipModifier"
    elseif ContainsAny(text, RegistryPhrases[334]) then
        key = "general.unitTooltipProvider"
        forcedValue = "MSUF"
    elseif ContainsAny(text, RegistryPhrases[335]) then
        key = "general.unitTooltipProvider"
        forcedValue = "GAME"
    elseif ContainsAny(text, RegistryPhrases[336]) then
        key = "general.unitTooltipProvider"
    elseif ContainsAny(text, RegistryPhrases[337])
        or (ContainsAny(text, RegistryPhrases[338]) and ContainsAny(text, RegistryPhrases[339])) then
        key = "general.unitTooltipAnchor"
    elseif ContainsAny(text, RegistryPhrases[340])
        or (ContainsAny(text, RegistryPhrases[341]) and ContainsAny(text, RegistryPhrases[342])) then
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
            text = "Which unit frame visibility rule do you want me to change? MSUF offers Housing, In combat, In group, In instance, In vehicle, Mounted, No target, Out of combat, Out of combat and no target, Resting, Solo, and Stealthed.",
            summary = "Asks which unit frame visibility rule to change.",
        }
    end

    local value = P.UnitLoadConditionValueForText(text, spec)
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

function P.ParseTargetGateLoadConditionShortcut(text)
    if not ContainsAny(text, P.TARGET_GATE_INTENT_TERMS) then return nil end
    local parsed = ParseUnitLoadConditionShortcut(text)
    local change = parsed and parsed.changes and parsed.changes[1]
    local key = change and change.setting and change.setting.attribute
    if key == "loadCondHideNoTarget" or key == "loadCondHideOutOfCombatNoTarget" then
        return parsed
    end
    return nil
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
    if ContainsAny(text, RegistryPhrases[343]) then
        return false
    end
    if ContainsAny(text, RegistryPhrases[344]) then
        return true
    end
    if ContainsAny(text, RegistryPhrases[345]) then
        return true
    end
    return DetectBoolean(text)
end

local function PowerBarBorderThicknessIntent(text)
    if ContainsAny(text, RegistryPhrases[346]) then
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
    if not ContainsAny(text, RegistryPhrases[347]) then return nil end
    if HasClassPowerIntent(text) then return nil end

    local attr
    local label
    local value
    local relativeDelta
    if ContainsAny(text, RegistryPhrases[348]) then
        attr = "detachedPowerBarTextOnBar"
        label = "Text On Detached Power Bar"
        value = DetectBoolean(text)
        if value == nil then value = true end
    elseif ContainsAny(text, RegistryPhrases[349]) then
        attr = "detachedPowerBarFrameLevelOffset"
        label = "Detached Power Bar Layer"
    elseif ContainsAny(text, RegistryPhrases[350]) and not ContainsAny(text, RegistryPhrases[351]) then
        attr = "detachedPowerBarWidth"
        label = "Detached Power Bar Width"
    elseif ContainsAny(text, RegistryPhrases[352]) then
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
    if not ContainsAny(text, RegistryPhrases[353]) then return nil end
    if HasClassPowerIntent(text) then return nil end

    local changes = {}
    local detachedDetail = P.ParseDetachedPowerBarRegistryShortcut(text, raw)
    if detachedDetail then return detachedDetail end

    if ContainsAny(text, RegistryPhrases[354]) then
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

    if ContainsAny(text, RegistryPhrases[355]) then
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

    if ContainsAny(text, RegistryPhrases[356]) then
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

    if ContainsAny(text, RegistryPhrases[357]) then
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

    if ContainsAny(text, RegistryPhrases[358]) then return nil end
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
    if not ContainsAny(text, RegistryPhrases[359]) then return nil end
    if ContainsAny(text, RegistryPhrases[360]) then return nil end
    local explicitUnits = {}
    local pageUnit
    if not HasAllScopeIntent(text) then
        explicitUnits = ExplicitScopes(text)
        pageUnit = CurrentRegistryPageUnit()
    end
    if not ContainsAny(text, RegistryPhrases[361]) and not explicitUnits[1] and not pageUnit then return nil end
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

P.BuildCastbarColorChoices = function(keys, value, valueLabel)
    local changes = {}
    for i = 1, #(keys or {}) do
        local change = P.BuildColorShortcutChange(keys[i], value, valueLabel)
        if change then changes[#changes + 1] = change end
    end
    return changes
end

P.ParseCastbarColorShortcut = function(text, raw)
    if ContainsAny(text, RegistryPhrases[366]) then return nil end
    if not ContainsAny(text, RegistryPhrases[367]) then return nil end

    local value, valueLabel = P.ColorShortcutValue(text, raw)
    if not value then return nil end
    local key
    if ContainsAny(text, RegistryPhrases[368])
        and ContainsAny(text, RegistryPhrases[369]) then
        key = "general.kickNotReadyColor"
    elseif ContainsAny(text, RegistryPhrases[370])
        and ContainsAny(text, RegistryPhrases[371]) then
        key = "general.kickReadyColor"
    elseif ContainsAny(text, RegistryPhrases[372]) then
        key = "general.castbarFontColor"
    elseif ContainsAny(text, RegistryPhrases[373]) then
        key = "general.castbarBorderColor"
    elseif ContainsAny(text, RegistryPhrases[374]) then
        key = "general.castbarBackgroundColor"
    elseif ContainsAny(text, RegistryPhrases[375]) then
        key = "general.playerCastbarOverrideColor"
    elseif ContainsAny(text, RegistryPhrases[376]) then
        key = "general.castbarNonInterruptibleColor"
    elseif ContainsAny(text, RegistryPhrases[377]) then
        key = "general.castbarInterruptFeedbackColor"
    elseif ContainsAny(text, RegistryPhrases[378]) then
        key = "general.castbarInterruptibleColor"
    end

    if key then
        return P.ColorShortcutResponse(P.BuildCastbarColorChoices({ key }, value, valueLabel), "Castbar color", true, "Changes the Castbar color option.")
    end
    if ContainsAny(text, RegistryPhrases[379]) then
        return P.ColorShortcutResponse(P.BuildCastbarColorChoices({
            "general.castbarInterruptibleColor",
            "general.castbarNonInterruptibleColor",
            "general.castbarInterruptFeedbackColor",
        }, value, valueLabel), "Which castbar interrupt color?", false, "The request mentions interrupt color, which maps to several real Castbar color options.")
    end
    if ContainsAny(text, RegistryPhrases[380]) then
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
    return ContainsAny(text, RegistryPhrases[381])
end

local function HasGroupFrameOutlineColorIntent(text)
    if not ContainsAny(text, RegistryPhrases[382]) then
        return false
    end
    if HasExplicitFullGroupBorderIntent(text) then return false end
    if ContainsAny(text, RegistryPhrases[383]) then
        return false
    end
    return ContainsAny(text, RegistryPhrases[384])
end

local function HasAmbiguousGroupFrameBorderSizeIntent(text)
    if HasExplicitFullGroupBorderIntent(text) then return false end
    if ContainsAny(text, RegistryPhrases[385]) then return false end
    if ContainsAny(text, RegistryPhrases[386]) then
        return false
    end
    if not ContainsAny(text, RegistryPhrases[387]) then
        return false
    end
    if not ContainsAny(text, RegistryPhrases[388]) then
        return false
    end
    if ContainsAny(text, RegistryPhrases[389]) then
        return false
    end
    return ContainsAny(text, RegistryPhrases[390])
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
    { key = "targetColor", title = "Target Highlight Color", terms = { "target highlight color", "target border color", "selected target border color" } },
    { key = "hlFocusColor", title = "Focus Highlight Color", terms = { "focus highlight color", "focus border color", "focus glow color" } },
    { key = "debuffStripeColor", title = "Debuff Stripe Color", terms = { "debuff stripe color", "stripe color" } },
    { key = "deadBgColor", title = "Dead Background Color", terms = { "dead background color", "dead member background color", "dead offline background color", "dead bg color" } },
    { key = "bgColor", title = "Backdrop Color", terms = { "group backdrop color", "group background color", "frame background color", "backdrop color", "background color", "bar background color", "hp track color", "health track color", "track color" } },
    { key = "healthCustomColor", title = "Custom Health Color", terms = { "custom health color", "health custom color", "health bar custom color" } },
    { key = "gfDarkColor", title = "Dark Bar Color", terms = { "dark health color", "dark bar color", "dark mode health color" } },
    { key = "gfUnifiedColor", title = "Unified Bar Color", terms = { "unified health color", "unified bar color", "unified color" } },
    { key = "healthBarColor", title = "Health Bar Color", terms = { "health bar color", "health color", "bar color", "hp color", "hp bar color" } },
}

P.HasGroupFrameColorIntent = function(text)
    if ContainsAny(text, RegistryPhrases[391]) then return false end
    if ContainsAny(text, RegistryPhrases[392]) and not ContainsAny(text, RegistryPhrases[393]) then return false end
    if not ContainsAny(text, RegistryPhrases[394]) then return false end
    return ContainsAny(text, RegistryPhrases[395])
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
    if ContainsAny(text, RegistryPhrases[396]) then
        return false
    end
    if ContainsAny(text, RegistryPhrases[397]) then
        return true
    end
    return nil
end

local function ParseStatusIconTestModeRegistryShortcut(text)
    if not ContainsAny(text, RegistryPhrases[398]) then return nil end
    if not ContainsAny(text, RegistryPhrases[399]) then return nil end
    if ContainsAny(text, RegistryPhrases[400]) then return nil end

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

P.ParseStatusIconTestModeRegistryShortcut = ParseStatusIconTestModeRegistryShortcut

function P.ParseGroupBooleanRegistryShortcut(text)
    if ContainsAny(text, RegistryPhrases[401]) then return nil end
    local explicitUnits = DetectUnits(text)
    local explicitGroups = DetectGroups(text)
    if #explicitUnits > 0 then return nil end
    local attr
    local label
    local value = DetectBoolean(text)

    if ContainsAny(text, RegistryPhrases[402]) then
        attr = "hideNameOnDeadOffline"
            label = "Hide Name on Dead or Offline"
        if ContainsAny(text, RegistryPhrases[403]) then
            value = false
        else
            value = true
        end
    elseif ContainsAny(text, RegistryPhrases[404]) then
        attr = "hpTextReverse"
        label = "Reverse HP Text"
        if value == nil then value = true end
    elseif ContainsAny(text, RegistryPhrases[405])
        and not ContainsAny(text, RegistryPhrases[406])
        and not ContainsAny(text, RegistryPhrases[407])
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
    if ContainsAny(text, RegistryPhrases[408]) then return nil end
    if not ContainsAny(text, RegistryPhrases[409]) then return nil end

    local explicitUnits, explicitGroups = ExplicitScopes(text)
    local hasUnitFrameIntent = ContainsAny(text, RegistryPhrases[410])
    local hasGroupFrameIntent = ContainsAny(text, RegistryPhrases[411])
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
    if ContainsAny(text, RegistryPhrases[412]) then return nil end
    local attr
    local label
    if ContainsAny(text, RegistryPhrases[413])
        and ContainsAny(text, RegistryPhrases[414])
    then
        attr = "groupNumberSize"
        label = "Group Number Size"
    elseif ContainsAny(text, RegistryPhrases[415]) then
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
        and ContainsAny(text, RegistryPhrases[416])
    then
        attr = "groupBorderSize"
        label = "Group Border Thickness"
    elseif ContainsAny(text, RegistryPhrases[417]) then
        attr = "powerHeight"
        label = "Power Bar Height"
    elseif ContainsAny(text, RegistryPhrases[418]) then
        attr = "debuffStripeHeight"
        label = "Debuff Stripe Height"
    else
        return nil
    end

    local explicitGroups = DetectGroups(text)
    local activePage = M and M.activeKey
    local groupPage = activePage == "gf_layout" or activePage == "gf_bars" or activePage == "gf_indicators"
    if #explicitGroups == 0 and not groupPage and not ContainsAny(text, RegistryPhrases[419]) then return nil end
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
        or ParseUnitTextBooleanDetailShortcut(text)
        or ParseUnitStatusDetailShortcut(text)
        or ParseUnitCoreBooleanShortcut(text)
        or P.ParseCastbarColorShortcut(text, raw)
        or P.ParseInterruptReadyRegistryShortcut(text, raw)
        or P.ParseUnitStatusSymbolRegistryShortcut(text)
        or P.ParseCastbarBackendShortcut(text)
        or P.ParseCastbarPositionRegistryShortcut(text)
        or (P.ParseFocusKickRegistryShortcut and P.ParseFocusKickRegistryShortcut(text))
        or (P.ParseBarGradientRegistryShortcut and P.ParseBarGradientRegistryShortcut(text))
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
        or ParseUnitLoadConditionShortcut(text)
        or P.ParseDependentTargetFrameVisibilityShortcut(text)
        or ParsePowerBarRegistryShortcut(text, raw)
        or ParseStatusIconTestModeRegistryShortcut(text)
        or ParseCastbarInterruptRegistryShortcut(text)
end

P.ParseRegistryAliasCandidates = function(text, raw, settings, suppressNoMatch)
    local changes = {}
    local missingValue = {}
    local bestScore = 0
    -- Resolved once for the whole candidate sweep: almost no request carries a
    -- styling qualifier, and testing every setting for one would tax the
    -- broadest matcher in the parser.
    local stylingQualifiers = P.StylingQualifiersInText(text)
    for i = 1, #settings do
        if i % 8 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local setting = settings[i]
        local score = SettingMatchScore(setting, text)
        -- "bold" names Bold Text / Font Outline. A candidate that owns neither
        -- is not what was asked for, however well the rest of the sentence
        -- scores against it.
        if score > 0 and stylingQualifiers
            and P.SettingDropsStylingQualifiers(setting, stylingQualifiers) then
            score = 0
        end
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
    local contextScored = false
    if #changes > 1 and A.ContextEngineEnabled ~= false and P.ScoreSettingCandidates then
        local scored = P.ScoreSettingCandidates(changes, { context = A.ConversationContext and A.ConversationContext() or nil })
        if type(scored) == "table" and #scored > 0 then
            changes = scored
            contextScored = true
        end
    end
    if not contextScored and #changes > 1 and bestScore > 0 then
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
    -- Lua 5.1 cannot yield through pcall/xpcall. Run the yieldable fuzzy scan in
    -- its own coroutine and proxy cooperative yields to the Assistant job
    -- coroutine. coroutine.resume is the error boundary, so the per-coroutine
    -- fuzzy scope is cleared on success and failure without leaking a shared
    -- flag when a job is cancelled between frames.
    local function PackValues(...)
        return { n = select("#", ...), ... }
    end
    if type(coroutine) ~= "table" or type(coroutine.create) ~= "function"
        or type(coroutine.resume) ~= "function" or type(coroutine.status) ~= "function"
        or type(P.SetFuzzyAliasCoroutineScope) ~= "function"
    then
        error("yield-safe fuzzy parser coroutine support is unavailable", 0)
    end

    local outer, outerIsMain = coroutine.running()
    local outerYieldable = outer ~= nil and outerIsMain ~= true
    local worker = coroutine.create(function()
        return P.ParseRegistryAliasCandidates(text, raw, settings)
    end)
    P.SetFuzzyAliasCoroutineScope(worker, true)

    local resumeValues = { n = 0 }
    while true do
        local resumed = PackValues(coroutine.resume(worker, unpack(resumeValues, 1, resumeValues.n)))
        if resumed[1] ~= true then
            P.SetFuzzyAliasCoroutineScope(worker, false)
            local detail = resumed[2]
            if type(debug) == "table" and type(debug.traceback) == "function" then
                local traced, value = pcall(debug.traceback, worker, tostring(detail), 0)
                if traced and type(value) == "string" and value ~= "" then detail = value end
            end
            error(detail, 0)
        end
        if coroutine.status(worker) == "dead" then
            P.SetFuzzyAliasCoroutineScope(worker, false)
            return unpack(resumed, 2, resumed.n)
        end
        if not outerYieldable or type(coroutine.yield) ~= "function" then
            P.SetFuzzyAliasCoroutineScope(worker, false)
            error("fuzzy parser yielded outside a deferred Assistant job", 0)
        end
        resumeValues = PackValues(coroutine.yield(unpack(resumed, 2, resumed.n)))
    end
end

local function ParseTargetInlinePartialAmbiguity(text)
    text = Normalize(text)
    if not ContainsAny(text, RegistryPhrases[420]) then return nil end
    if ContainsAny(text, RegistryPhrases[421]) then return nil end
    if not ContainsAny(text, RegistryPhrases[422]) then return nil end
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
    local priorityAlias = P.ParseRegistryPriorityShortcut and P.ParseRegistryPriorityShortcut(text, raw)
    if priorityAlias then return priorityAlias end
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
    if not ContainsAny(text, RegistryPhrases[423]) then return nil end
    if ContainsAny(text, RegistryPhrases[424]) then return nil end
    if ContainsAny(text, RegistryPhrases[425]) then return nil end
    if ContainsAny(text, RegistryPhrases[426]) then
        return "fonts"
    end
    if ContainsAny(text, RegistryPhrases[427]) then
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
P.NAME_DOT_EXACT_TERMS = P.NAME_DOT_EXACT_TERMS or {
    "dot", "dots", "ellipsis", "ellipses", "trailing dots", "three dots", "two dots",
}
P.NON_NAME_DOT_EXACT_TERMS = P.NON_NAME_DOT_EXACT_TERMS or {
    "corner", "status", "indicator", "spell indicator", "combo point", "class resource",
    "class power", "aura", "buff", "debuff", "castbar", "spell name",
}
P.RegistrySettingMayMatchExactAlias = function(setting, text)
    if RootFrameEnabledBlockedByDetail(setting, text) then return false end
    if AuraLaneVisibilityBlockedByDetail(setting, text) then return false end
    local exactKey = tostring(setting and setting.key or "")
    if (exactKey:match("%.showHP$") or exactKey:match("%.showHPText$")
            or exactKey:match("%.showPower$") or exactKey:match("%.showPowerText$"))
        and (tostring(text or ""):find("%", 1, true)
            or ContainsAny(text, { "percent", "percentage", "current", "actual", "max", "maximum", "deficit", "missing", "only", "color", "colour", "font" }))
    then
        -- Visibility toggles do not own the displayed value mode. Keep exact
        -- "HP Text" aliases from consuming slot-content requests.
        return false
    end
    if setting and setting.generated == true
        and (exactKey:match("%.hpTextMode$") or exactKey:match("%.powerTextMode$"))
        and ContainsAny(text, { "hp text", "health text", "power text" })
    then
        -- These legacy projection keys have no slot identity. The dedicated
        -- text parser owns the active left/center/right slot and understands
        -- symbolic values such as "%" without redirecting the write.
        return false
    end
    -- An exact alias may match only a trailing scope phrase ("party frame" or
    -- "party name") while ignoring the user's meaningful noun, "dots". Keep
    -- unrelated geometry/name-visibility settings out of that candidate set;
    -- explicit corner/status/resource/aura wording remains owned by its domain.
    if ContainsAny(text, P.NAME_DOT_EXACT_TERMS)
        and not ContainsAny(text, P.NON_NAME_DOT_EXACT_TERMS) then
        local hay = (tostring(setting and setting.key or "") .. " "
            .. tostring(setting and setting.label or "") .. " "
            .. tostring(setting and setting.attribute or "")):lower()
        if not hay:find("ellipsis", 1, true)
            and not hay:find("shorten", 1, true)
            and not hay:find("truncat", 1, true)
            and not hay:find("namedots", 1, true)
            and not hay:find("name dots", 1, true) then
            return false
        end
    end
    if P.ExactAliasDropsStylingQualifier(setting, text) then return false end
    return SettingAllowedByExplicitScopes(setting, text)
end

-- Each of these names a distinct control family, so a request containing one is
-- only satisfied by a setting that owns it. Same failure shape as the name-dots
-- rule above: an alias matched a trailing scope phrase ("player name") while the
-- meaningful qualifier ("bold") was ignored, and "set player name bold text on"
-- silently toggled Player Name instead of admitting it was not understood.
P.STYLING_QUALIFIER_TERMS = P.STYLING_QUALIFIER_TERMS or {
    { term = "bold", owns = { "bold", "outline" } },
    { term = "italic", owns = { "italic" } },
    { term = "outline", owns = { "outline" } },
    { term = "shadow", owns = { "shadow" } },
    { term = "monochrome", owns = { "monochrome" } },
    { term = "fett", owns = { "bold", "outline" } },
    { term = "kursiv", owns = { "italic" } },
    { term = "umriss", owns = { "outline" } },
    { term = "schatten", owns = { "shadow" } },
}

-- Returns the qualifier entries present in the request, or nil. Callers that
-- sweep many settings resolve this once instead of per candidate.
P.StylingQualifiersInText = function(text)
    local found
    for i = 1, #P.STYLING_QUALIFIER_TERMS do
        local entry = P.STYLING_QUALIFIER_TERMS[i]
        if ContainsAny(text, { entry.term }) then
            found = found or {}
            found[#found + 1] = entry
        end
    end
    return found
end

P.SettingDropsStylingQualifiers = function(setting, qualifiers)
    if not qualifiers then return false end
    local hay = (tostring(setting and setting.key or "") .. " "
        .. tostring(setting and setting.label or "") .. " "
        .. tostring(setting and setting.attribute or "")):lower()
    for i = 1, #qualifiers do
        local owns = qualifiers[i].owns
        local owned = false
        for j = 1, #owns do
            if hay:find(owns[j], 1, true) then
                owned = true
                break
            end
        end
        if not owned then return true end
    end
    return false
end

P.ExactAliasDropsStylingQualifier = function(setting, text)
    return P.SettingDropsStylingQualifiers(setting, P.StylingQualifiersInText(text))
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
