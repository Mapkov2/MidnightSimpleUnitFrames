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
    { key = "RAID_BUFFS", aliases = { "raid buffs", "long term raid buffs", "raid buff preset" } },
    { key = "PRESERVATION_EVOKER", aliases = { "preservation evoker", "pres evoker" } },
    { key = "AUGMENTATION_EVOKER", aliases = { "augmentation evoker", "aug evoker" } },
    { key = "RESTO_DRUID", aliases = { "resto druid", "restoration druid" } },
    { key = "DISC_PRIEST", aliases = { "disc priest", "discipline priest" } },
    { key = "HOLY_PRIEST", aliases = { "holy priest" } },
    { key = "MISTWEAVER_MONK", aliases = { "mistweaver monk", "mw monk" } },
    { key = "RESTO_SHAMAN", aliases = { "resto shaman", "restoration shaman" } },
    { key = "HOLY_PALADIN", aliases = { "holy paladin", "holy pala" } },
    { key = "BLESSING_BRONZE", aliases = { "blessing of the bronze", "bronze blessing" } },
    { key = "SELF_BUFFS", aliases = { "self buffs", "long term self buffs" } },
    { key = "ROGUE_POISONS", aliases = { "rogue poisons", "poisons" } },
    { key = "SHAMAN_IMBUE", aliases = { "shaman imbues", "shaman imbuements", "imbues" } },
    { key = "RESOURCE_AURAS", aliases = { "resource auras", "resource buffs" } },
    { key = "COOLDOWNS", aliases = { "cooldowns", "cooldown auras" } },
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

local function AuraQuickPresetForText(text)
    for i = 1, #AURA_QUICK_PRESETS do
        local preset = AURA_QUICK_PRESETS[i]
        if ContainsAny(text, preset.aliases) then return preset.key end
    end
    return nil
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

local function AuraBlacklistSpellValue(raw)
    raw = tostring(raw or "")
    local value = raw:match("(spell:%d+)") or raw:match("#%s*(%d+)") or raw:match("(%d%d+)")
    if value then return value end
    value = raw:match("[Aa]dd%s+(.+)%s+to%s+.+[Bb]lacklist")
        or raw:match("[Bb]lacklist%s+(.+)%s+for%s+")
        or raw:match("[Rr]emove%s+(.+)%s+from%s+.+[Bb]lacklist")
    value = CleanProfileName(value)
    if value and value ~= "" then return value end
    return nil
end

local function ParseAuraBlacklist(text, raw)
    if not ContainsAny(text, { "blacklist", "blocked aura", "blocked auras", "ignore aura", "ignore auras" }) then return nil end
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
    if not value then return nil end
    local remove = ContainsAny(text, { "remove", "delete", "unblacklist", "allow", "loeschen", "entfernen" })
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
P.ParseAuraQuickPreset = ParseAuraQuickPreset
P.AuraBlacklistPresetForText = AuraBlacklistPresetForText
P.AuraGroupBlacklistScope = AuraGroupBlacklistScope
P.AuraGroupBlacklistLane = AuraGroupBlacklistLane
P.AuraGroupBlacklistCategoryForText = AuraGroupBlacklistCategoryForText
P.ParseAuraGroupCategoryBlacklist = ParseAuraGroupCategoryBlacklist
P.AuraBlacklistSpellValue = AuraBlacklistSpellValue
P.ParseAuraBlacklist = ParseAuraBlacklist
