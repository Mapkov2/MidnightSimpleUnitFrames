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
local AURA_BLACKLIST_PRESETS = P.AURA_BLACKLIST_PRESETS
local AuraBlacklistScope = P.AuraBlacklistScope
local AURA_QUICK_PRESETS = P.AURA_QUICK_PRESETS
local AuraQuickPresetForText = P.AuraQuickPresetForText
local ParseAuraQuickPreset = P.ParseAuraQuickPreset
local AuraBlacklistPresetForText = P.AuraBlacklistPresetForText
local AuraGroupBlacklistScope = P.AuraGroupBlacklistScope
local AuraGroupBlacklistLane = P.AuraGroupBlacklistLane
local AuraGroupBlacklistCategoryForText = P.AuraGroupBlacklistCategoryForText
local ParseAuraGroupCategoryBlacklist = P.ParseAuraGroupCategoryBlacklist
local AuraBlacklistSpellValue = P.AuraBlacklistSpellValue
local ParseAuraBlacklist = P.ParseAuraBlacklist
local CopyTextParts = P.CopyTextParts
local RemoveUnit = P.RemoveUnit
local CopyTargetsForText = P.CopyTargetsForText
local CopyGroupTargetsForText = P.CopyGroupTargetsForText
local ParseGroupCopy = P.ParseGroupCopy
local ParseCopy = P.ParseCopy
local BuildContextReset = P.BuildContextReset
local GROUP_STATUS_ICON_ALIASES = P.GROUP_STATUS_ICON_ALIASES
local GroupStatusIconForText = P.GroupStatusIconForText
local GROUP_STATUS_ICON_TERMS = P.GROUP_STATUS_ICON_TERMS
local FirstGroupOrDefault = P.FirstGroupOrDefault
local AliasValueForText = P.AliasValueForText
local GROUP_SPELL_PLACED_ALIASES = P.GROUP_SPELL_PLACED_ALIASES
local GROUP_SPELL_FRAME_ALIASES = P.GROUP_SPELL_FRAME_ALIASES
local GROUP_SPELL_GROWTH_ALIASES = P.GROUP_SPELL_GROWTH_ALIASES
local GROUP_SPELL_ANCHOR_ALIASES = P.GROUP_SPELL_ANCHOR_ALIASES
local ParseGroupSpellIndicatorAction = P.ParseGroupSpellIndicatorAction
local ParseGroupCornerIndicatorReset = P.ParseGroupCornerIndicatorReset
local ParseGroupStatusIconReset = P.ParseGroupStatusIconReset
local ParseGroupStatusPreview = P.ParseGroupStatusPreview
local UNIT_STATUS_RESET_TERMS = P.UNIT_STATUS_RESET_TERMS
local ParseUnitStatusIndicatorReset = P.ParseUnitStatusIndicatorReset
local ParseUnitStatusPreview = P.ParseUnitStatusPreview
local ParseUnitStatusIndicatorMove = P.ParseUnitStatusIndicatorMove
local ParseCustomAnchorWorkflow = P.ParseCustomAnchorWorkflow
local CleanCustomAnchorFrameName = P.CleanCustomAnchorFrameName
local RawCustomAnchorFrameName = P.RawCustomAnchorFrameName
local ParseCustomAnchorSet = P.ParseCustomAnchorSet
local ParseCustomAnchorClear = P.ParseCustomAnchorClear
local ParseReset = P.ParseReset
local ParseOpen = P.ParseOpen
local DashboardPanelForText = P.DashboardPanelForText
local ParseDashboardPanelAction = P.ParseDashboardPanelAction
local NAV_SECTION_TEXT_TARGETS = P.NAV_SECTION_TEXT_TARGETS
local NavSectionForText = P.NavSectionForText
local ParseNavRailAction = P.ParseNavRailAction
local ParseMenuWindowAction = P.ParseMenuWindowAction

local explicitScopeCacheText
local explicitScopeCacheUnits
local explicitScopeCacheGroups

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
    local unit = tostring(setting.unit)
    local keyScope = SettingKeyScope(setting)
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
    "alpha", "opacity", "range fade",
}

local function RootFrameEnabledBlockedByDetail(setting, text)
    if not (setting and setting.attribute == "enabled") then return false end
    if setting.frameType ~= "unitframe" and setting.frameType ~= "group" then return false end
    return ContainsAny(text, ROOT_FRAME_ENABLED_DETAIL_TERMS)
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

local function ShouldApplyMultipleRegistryChanges(text, changes)
    if #(changes or {}) <= 1 then return false end
    if HasAllScopeIntent(text) then return true end
    local units, groups = ExplicitScopes(text)
    return (#units + #groups) > 1
end

local function SettingAllowedByExplicitScopes(setting, text)
    if type(setting) ~= "table" then return false end
    if ClassPowerBlockedByExplicitUnitPowerIntent(setting, text) then return false end
    local unit = tostring(setting.unit or "")
    local keyScope = SettingKeyScope(setting)
    local units, groups = ExplicitScopes(text)
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
    if #units > 0 and unit ~= "" and unit ~= "global" and not ListContains(units, unit) and not ListContains(units, keyScope) then return false end
    if #groups > 0 and #units == 0 and unit ~= "" and unit ~= "global" and not ListContains(groups, unit) and not ListContains(groups, keyScope) then return false end
    return true
end

local function SettingMatchesText(setting, text)
    if type(setting) ~= "table" then return false end
    if RootFrameEnabledBlockedByDetail(setting, text) then return false end
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

local function SettingMatchScore(setting, text)
    if type(setting) ~= "table" then return 0 end
    if RootFrameEnabledBlockedByDetail(setting, text) then return 0 end
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
    return matchSegment(norm)
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

local function ValueDisplay(setting, value)
    if value == nil then return "value" end
    if setting and setting.type == "boolean" then return value and "enabled" or "disabled" end
    if tostring(value) == "" then return "blank" end
    if tostring(value) == "__CUSTOM__" then return "Custom" end
    if setting and type(setting.valueAliases) == "table" then
        local bestAlias
        local bestLen = 999999
        for alias, aliasValue in pairs(setting.valueAliases) do
            if aliasValue == value then
                local len = #tostring(alias or "")
                if len < bestLen then
                    bestLen = len
                    bestAlias = alias
                end
            end
        end
        if bestAlias and bestAlias ~= "" then return tostring(bestAlias) end
    end
    return tostring(value)
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
                label = tostring(setting.label or "Setting") .. " -> " .. ValueDisplay(setting, value),
            }
        end
        return {
            kind = "ambiguous",
            choices = choices,
            label = "Choose a value for " .. tostring(setting.label or "this setting"),
            summary = "Registry-backed value clarification.",
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
        text = "What should " .. tostring(setting.label or "this setting") .. " be set to? " .. hint,
        summary = "Registry-backed value clarification.",
    }
end

local RelativeNumberDeltaForText
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
    all = true, every = true, everyone = true, everything = true, each = true,
    setze = true, stelle = true, aktivieren = true, aktiviert = true, deaktivieren = true, deaktiviert = true,
    einschalten = true, eingeschaltet = true, ausschalten = true, ausgeschaltet = true,
    erhoehe = true, erhoehen = true, hoeher = true, groesser = true, kleiner = true, senke = true, reduziere = true,
    anzeigen = true, einblenden = true, ausblenden = true, verstecken = true, versteckt = true,
    an = true, aus = true, ja = true, nein = true, auf = true, zu = true, als = true, wert = true,
    fuer = true, fur = true, vom = true, von = true, nach = true, ["in"] = true,
    gruppe = true, gruppen = true, gruppenframes = true,
    alle = true, alles = true, jede = true, jeder = true, jedes = true, jeweils = true,
}

local REGISTRY_CANDIDATE_RARE_TOKEN_LIMIT = 260

local function MeaningTokens(text)
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

P._AddCandidateIndexTokens = function(tokenSet, text)
    local _, tokens = MeaningTokens(text)
    for i = 1, #tokens do
        tokenSet[tokens[i]] = true
    end
end

P._BuildRegistryCandidateIndex = function(settings, includeAliases)
    includeAliases = includeAliases == true
    local byToken = {}
    local all = {}
    for i = 1, #(settings or {}) do
        if i % 8 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
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
                    if j % 16 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
                    P._AddCandidateIndexTokens(tokenSet, aliases[j])
                end
                local prefixes = setting.valuePrefixes
                for j = 1, #(prefixes or {}) do
                    if j % 16 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
                    P._AddCandidateIndexTokens(tokenSet, prefixes[j])
                end
            end
            for token in pairs(tokenSet) do
                byToken[token] = byToken[token] or {}
                byToken[token][#byToken[token] + 1] = setting
            end
        end
    end
    P._registryCandidateIndexSettings = settings
    P._registryCandidateIndexCount = #(settings or {})
    P._registryCandidateIndexFull = includeAliases
    P._registryCandidateIndexByToken = byToken
    P._registryCandidateIndexAll = all
    P._registryCandidateCache = {}
    P._registryCandidateCacheOrder = {}
end

P._EnsureRegistryCandidateIndex = function(settings, includeAliases)
    includeAliases = includeAliases == true
    if settings ~= P._registryCandidateIndexSettings
        or #(settings or {}) ~= (P._registryCandidateIndexCount or -1)
        or (includeAliases and P._registryCandidateIndexFull ~= true) then
        P._BuildRegistryCandidateIndex(settings, includeAliases)
    end
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
    local selectedTokens, selectedCount, hasRareToken = {}, 0, false
    for i = 1, #tokens do
        local list = P._registryCandidateIndexByToken and P._registryCandidateIndexByToken[tokens[i]]
        if type(list) == "table" and #list > 0 and #list <= REGISTRY_CANDIDATE_RARE_TOKEN_LIMIT then
            selectedCount = selectedCount + 1
            selectedTokens[selectedCount] = tokens[i]
            hasRareToken = true
        end
    end
    if not hasRareToken then
        selectedTokens = tokens
        selectedCount = #tokens
    end
    local out, seen = {}, {}
    if selectedCount >= 2 and not includeAliases then
        local counts = {}
        local ordered = {}
        for i = 1, selectedCount do
            if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
            local list = P._registryCandidateIndexByToken and P._registryCandidateIndexByToken[selectedTokens[i]]
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
    if #out == 0 then
        for i = 1, selectedCount do
            if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
            local list = P._registryCandidateIndexByToken and P._registryCandidateIndexByToken[selectedTokens[i]]
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
    { key = "loadCondHideOutOfCombat", label = "Hide Out Of Combat", terms = { "out of combat", "outside combat", "not in combat", "ooc", "while out of combat", "when out of combat", "ausserhalb kampf", "ausser kampf", "nicht im kampf" } },
    { key = "loadCondHideSolo", label = "Hide Solo", terms = { "solo", "alone", "while solo", "when solo", "allein" } },
    { key = "loadCondHideInVehicle", label = "Hide In Vehicle", terms = { "in vehicle", "vehicle", "while in vehicle", "when in vehicle", "fahrzeug" } },
    { key = "loadCondHideInGroup", label = "Hide In Group", terms = { "in group", "while in group", "when in group", "grouped", "in party", "in raid", "in gruppe", "gruppe" } },
    { key = "loadCondHideInInstance", label = "Hide In Instance", terms = { "in instance", "instance", "dungeon", "while in instance", "when in instance", "instanz" } },
    { key = "loadCondHideResting", label = "Hide Resting", terms = { "resting", "rested", "rest area", "while resting", "when resting", "ruhend", "erholt" } },
    { key = "loadCondHideInCombat", label = "Hide In Combat", terms = { "in combat", "combat", "fight", "while in combat", "when in combat", "im kampf", "kampf" } },
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
    if #groups > 0 then return false end
    return #units > 0 and HasVisibilityVerb(text)
end

local function GroupAvailabilityAttributeForText(text)
    if ContainsAny(text, { "tint offline", "tint offline members", "also tint offline members", "dead background offline", "dead background offline members", "dead offline tint" }) then
        return nil
    end
    if ContainsAny(text, { "offline in combat", "combat offline hide", "hide offline in combat", "offline im kampf" }) then
        return "hideOfflineInCombat", "hide"
    end
    if ContainsAny(text, { "offline members", "offline member", "offline players", "hide offline members", "offline spieler" }) then
        return "hideOfflineEnabled", "hide"
    end
    if ContainsAny(text, { "client scene", "client scenes", "hide during client scene", "hide in client scene", "client szene" }) then
        return "hideInClientScene", "hide"
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
        "show group frames while solo", "group while solo", "group frames while solo",
        "hide while solo", "hide solo", "not show while solo", "dont show while solo", "do not show while solo",
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
        text = "Group Frames do not have a real load-condition toggle for that situation yet. I can change the real Group Frame availability options MSUF exposes: Use MSUF group frames, Show player, Show while solo, Hide during client scene, Offline Members, and Hide offline in combat.",
        summary = "Explains unsupported Group Frame load-condition request without faking a setting.",
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
                label = tostring(setting.label or "Group setting") .. " -> " .. ValueDisplay(setting, value),
            }
        end
    end
    if #changes == 0 then return nil end
    if concrete and #changes == 1 then
        return {
            kind = "changes",
            changes = changes,
            label = changes[1].setting and changes[1].setting.label or "Group availability",
            summary = "Registry-backed group-frame availability change.",
        }
    end
    return {
        kind = "ambiguous",
        choices = changes,
        label = "Which group-frame scope?",
        summary = "The command matched a real group-frame availability option but did not name Party, Raid, or Mythic Raid.",
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
                    label = tostring(setting.label or "Setting") .. " -> " .. ValueDisplay(setting, value),
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
            label = "Multiple matching settings",
            summary = "Registry-backed multi-scope setting change.",
        }
    end
    table.sort(filtered, function(a, b)
        return tostring(a.label or "") < tostring(b.label or "")
    end)
    while #filtered > 6 do table.remove(filtered) end
    return {
        kind = "ambiguous",
        choices = filtered,
        label = "Suggested MSUF setting",
        summary = "Registry-backed partial setting suggestion.",
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

RelativeNumberDeltaForText = function(setting, text, fallbackAmount)
    local sign
    if ContainsAny(text, RELATIVE_INCREASE_TERMS) then sign = 1 end
    if ContainsAny(text, RELATIVE_DECREASE_TERMS) then sign = -1 end
    if not sign then return nil end
    local amount = A._RelativeNumberAmountForText(text)
    if amount == nil then
        amount = fallbackAmount
            or (setting and tonumber(setting.step))
            or 1
    end
    if setting and setting.percent == true and amount > 1 then amount = amount / 100 end
    return amount * sign
end

local function NumberSettingSupportsBooleanToggle(setting)
    if type(setting) ~= "table" then return false end
    local hay = (tostring(setting.key or "") .. " " .. tostring(setting.label or "") .. " " .. tostring(setting.attribute or "")):lower()
    return hay:find("outline", 1, true) ~= nil
        or hay:find("border", 1, true) ~= nil
        or hay:find("thickness", 1, true) ~= nil
end

local function BooleanValueForNumberSetting(setting, text)
    if not NumberSettingSupportsBooleanToggle(setting) then return nil end
    if not ContainsAny(text, { "on", "off", "enable", "disable", "show", "hide", "an", "aus", "aktivieren", "deaktivieren" }) then return nil end
    local bool = DetectBoolean(text)
    if bool == nil then return nil end
    if bool == false then
        local minValue = tonumber(setting.min)
        if minValue ~= nil then return minValue end
        return 0
    end
    local step = tonumber(setting.step) or 1
    local minValue = tonumber(setting.min)
    local maxValue = tonumber(setting.max)
    local value = step
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
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
            label = tostring(setting.label or "Setting") .. " → " .. tostring(media.label or media.value),
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
                label = tostring(setting.label or "Setting") .. " → " .. tostring(item.label or item.value),
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
        summary = "Sets shared text color to white and resets automatic text color modes.",
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
    }) then
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
    }) then
        spec = { key = "npcNameRed", on = "NPC", label = "NPC Name Text Color" }
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
    return {
        kind = "changes",
        changes = changes,
        label = spec.label,
        summary = "Changes the registered scoped Font text color mode.",
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

P.ParseMiscRegistryShortcut = function(text, raw)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    local key
    if ContainsAny(text, { "snap", "snapping", "edge snap", "window snap", "menu snap", "snapping feature", "snap feature" }) then
        if ContainsAny(text, { "edit mode", "grid snap", "snap to grid", "snap frames", "mover snap", "raster snap" }) then return nil end
        key = "general.slashMenuSnapEnabled"
    elseif ContainsAny(text, { "advanced menu", "advanced menu section", "advanced section", "erweitertes menu" }) then
        key = "general.hideAdvancedMenu"
    elseif ContainsAny(text, { "reduce motion", "menu motion", "reduce animations", "menu animations", "bewegung reduzieren" }) then
        key = "general.reduceMotion"
    elseif ContainsAny(text, { "welcome message", "startup welcome", "startup message", "start message", "willkommensnachricht" }) then
        key = "general.showWelcomeMessage"
    elseif ContainsAny(text, { "version check", "peer version check", "peer-to-peer version check", "update check", "versionscheck" }) then
        key = "general.versionCheckEnabled"
    elseif ContainsAny(text, { "minimap icon", "minimap button", "msuf minimap icon", "msuf minimap button", "minikarten symbol" }) then
        key = "general.showMinimapIcon"
    elseif ContainsAny(text, { "target sounds", "target sound", "target lost sound", "target lost sounds", "target select sound", "target select sounds", "target select lost sounds", "play sound on target", "play sound on target lost", "play sound on target select", "ziel sound", "ziel sounds" }) then
        key = "general.playTargetSelectLostSounds"
    elseif ContainsAny(text, { "fully hide blizzard playerframe", "fully hide blizzard player frame", "hard hide blizzard playerframe", "hard hide blizzard player frame", "hard kill blizzard playerframe", "hard kill blizzard player frame", "resource bar compatibility" }) then
        key = "general.hardKillBlizzardPlayerFrame"
    elseif ContainsAny(text, { "blizzard unitframes", "blizzard unit frames", "blizzard frames", "standard frames", "default frames" }) then
        key = "general.disableBlizzardUnitFrames"
    elseif ContainsAny(text, { "menu language", "msuf language", "menu locale", "locale", "language", "sprache" }) then
        key = "general.menuLocale"
    elseif ContainsAny(text, { "tooltip modifier", "tooltip modifier key", "unit tooltip modifier", "unitframe tooltip modifier", "modifier key" }) and ContainsAny(text, { "tooltip", "tooltips" }) then
        key = "general.unitTooltipModifier"
    elseif ContainsAny(text, { "tooltip source", "unitframe tooltip source", "unit tooltip source", "group frame tooltip source", "game tooltip source", "gametooltip source" }) then
        key = "general.unitTooltipProvider"
    elseif ContainsAny(text, { "tooltip anchor", "unitframe tooltip anchor", "unit tooltip anchor", "tooltip position", "tooltip location" }) then
        key = "general.unitTooltipAnchor"
    elseif ContainsAny(text, { "unitframe tooltips", "unit frame tooltips", "unit tooltips", "group frame tooltips", "show tooltips", "tooltips", "tooltip mode", "tooltip visibility" }) then
        key = "general.unitTooltipMode"
    end
    if not key then return nil end

    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    local value = ValueForRegistrySetting(setting, text, raw)
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, valueLabel = ValueDisplay(setting, value) } },
        label = setting.label or "Miscellaneous setting",
        summary = "Changes a registered Miscellaneous setting through the real MSUF control.",
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
                label = tostring(setting.label or spec.label) .. " -> " .. ValueDisplay(setting, value),
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
            text = "Which Unit Frame load condition should I change? MSUF exposes Mounted, Out of combat, Solo, In vehicle, In group, In instance, Resting, In combat, and Stealthed.",
            summary = "Asks for the real Unit Frame load-condition option.",
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
            label = "Which Unit Frame?",
            summary = "The command matched a real Unit Frame load condition but did not name a unit.",
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
            label = "Unit Frame " .. tostring(spec.label),
            bulkSafe = true,
            summary = "Changes registered Unit Frame load-condition controls.",
        }
    end
    return {
        kind = "ambiguous",
        choices = changes,
        label = "Which Unit Frame?",
        summary = "The command matched a real Unit Frame load condition but did not name a unit.",
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

local function ParsePowerBarRegistryShortcut(text, raw)
    if not ContainsAny(text, { "power bar", "mana bar", "power balken", "mana balken" }) then return nil end
    if HasClassPowerIntent(text) then return nil end

    local changes = {}
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
                label = "Power Bar detached state",
                bulkSafe = true,
                summary = "Changes registered per-unit Power Bar detach controls.",
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
                label = "Power Bar embed state",
                bulkSafe = #changes > 1,
                summary = "Changes registered per-unit Power Bar embed-into-health controls.",
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
                    summary = "Changes registered per-unit Power Bar Border Thickness sliders.",
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
                summary = "Changes registered per-unit Power Bar Border toggles.",
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
                summary = "Changes registered Power Bar Height sliders.",
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
        summary = "Changes registered root Power Bar visibility controls.",
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
        label = "Castbar interrupt visibility",
        bulkSafe = true,
        summary = "Changes registered per-unit Show Castbar Interrupt controls.",
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
        label = tostring(setting.label or "MSUF color") .. " -> " .. tostring(valueLabel or "color"),
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
            summary = summary or "Changes a registered MSUF color setting.",
        }
    end
    return {
        kind = "ambiguous",
        choices = changes,
        label = title or "Which MSUF color?",
        summary = summary or "The color command matched multiple registered MSUF color settings.",
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
    if not ContainsAny(text, { "color", "colors", "colour", "colours", "farbe", "farben", "tint" }) then return nil end
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
        return P.ColorShortcutResponse(P.BuildCastbarColorChoices({ key }, value, valueLabel), "Castbar color", true, "Changes the registered Castbar color setting.")
    end
    if ContainsAny(text, { "interrupt color", "interrupt colour" }) then
        return P.ColorShortcutResponse(P.BuildCastbarColorChoices({
            "general.castbarInterruptibleColor",
            "general.castbarNonInterruptibleColor",
            "general.castbarInterruptFeedbackColor",
        }, value, valueLabel), "Which castbar interrupt color?", false, "The command mentions interrupt color, which maps to several real Castbar color controls.")
    end
    if ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then
        return P.ColorShortcutResponse(P.BuildCastbarColorChoices({
            "general.castbarInterruptibleColor",
            "general.castbarNonInterruptibleColor",
            "general.castbarInterruptFeedbackColor",
            "general.castbarFontColor",
            "general.castbarBorderColor",
            "general.castbarBackgroundColor",
        }, value, valueLabel), "Which castbar color?", false, "The command mentions Castbar color but not the exact registered Castbar color control.")
    end
    return nil
end

P.GROUP_COLOR_TARGETS = {
    { key = "groupBorderColor", title = "Group Border Color", terms = { "group border color", "group frame border color", "frame border color", "border color" } },
    { key = "hlFocusColor", title = "Focus Highlight Color", terms = { "focus highlight color", "focus border color", "focus glow color" } },
    { key = "deadBgColor", title = "Dead Background Color", terms = { "dead background color", "dead member background color", "dead offline background color", "dead bg color" } },
    { key = "bgColor", title = "Backdrop Color", terms = { "group backdrop color", "group background color", "frame background color", "backdrop color", "background color" } },
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
    return P.ColorShortcutResponse(changes, target.title, concrete, "Changes a registered Group Frame color setting.")
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
        summary = "Changes registered per-unit Status Icon Test Mode toggles.",
    }
end

local function ParseRepeatedRegistryShortcut(text, raw)
    return ParseScopedFontTextColorShortcut(text)
        or P.ParseCastbarColorShortcut(text, raw)
        or P.ParseGroupFrameColorShortcut(text, raw)
        or ParseUnitLoadConditionShortcut(text)
        or ParsePowerBarRegistryShortcut(text, raw)
        or ParseStatusIconTestModeRegistryShortcut(text)
        or ParseCastbarInterruptRegistryShortcut(text)
end

P.ParseRegistryAliasCandidates = function(text, raw, settings)
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
                            label = tostring(customSetting.label or setting.label or "Custom setting") .. " -> " .. tostring(freeform),
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
        return MissingValueResponse(missingValue, raw) or RegistrySuggestions(text, raw, settings)
    end
    if #changes == 1 and changes[1].mediaNoMatch then
        local resolver = A.MediaResolver
        local textOut = resolver and resolver.NoMatchMessage and resolver.NoMatchMessage(changes[1].mediaType, changes[1].mediaQuery) or "I could not find that media entry."
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
            label = "Multiple matching settings",
            summary = "Registry-backed multi-scope setting change.",
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
            label = "Multiple matching settings",
            summary = "Registry-backed multi-scope setting change.",
        }
    end
    if #changes > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching settings",
        }
    end
    local setting = changes[1].setting
    return {
        kind = "changes",
        changes = changes,
        label = setting and setting.label or "Assistant setting change",
        summary = "Registry-backed settings change.",
    }
end

local function ParseRegistryAlias(text, raw)
    local repeated = ParseRepeatedRegistryShortcut(text, raw)
    if repeated then return repeated end
    local groupAvailability = ParseGroupAvailabilityIntent(text)
    if groupAvailability then return groupAvailability end

    local allSettings = Registry and Registry:AllSettings() or {}
    local lightSettings = P.RegistryCandidateSettings(text, allSettings, false)
    local result = P.ParseRegistryAliasCandidates(text, raw, lightSettings)
    if result then return result end

    local fullSettings = P.RegistryCandidateSettings(text, allSettings, true)
    if fullSettings ~= lightSettings then
        return P.ParseRegistryAliasCandidates(text, raw, fullSettings)
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
            summary = "Uses ONLY as a scoped Bars/Fonts override command.",
        }
    end

    if #changes > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching scoped settings",
        }
    end

    if overrideSetting then
        table.insert(changes, 1, { setting = overrideSetting, value = true })
    end
    local setting = changes[#changes].setting
    return {
        kind = "changes",
        changes = changes,
        label = setting and setting.label or "Scoped override setting",
        summary = "Uses ONLY to enable the scoped Bars/Fonts override before applying the requested setting.",
    }
end

P.SettingMatchesText = SettingMatchesText
P.SettingMatchScore = SettingMatchScore
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
