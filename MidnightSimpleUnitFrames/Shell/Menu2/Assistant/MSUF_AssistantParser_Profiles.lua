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

-- Profile parser shard.
-- Profile names are user-authored text, so helpers here preserve raw fragments where needed
-- and only normalize the command scaffolding around them. The parser stages profile actions;
-- actual import/export/copy writes remain in the profile/runtime layer.
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

local COPY_SCOPE_DEFAULTS = {
    basics = true,
    text = true,
    portrait = true,
    power = true,
    castbar = true,
    status = true,
    load = true,
    transparency = true,
    layout = false,
}

local UNIT_COPY_SCOPE_SPECS = {
    { key = "layout", aliases = { "layout", "position", "positioning", "placement", "location", "size", "anchoring", "anchor", "width", "height" } },
    { key = "text", aliases = { "text", "name", "hp", "health text", "hp text", "power text", "mana text", "energy text", "resource text", "font", "fonts" } },
    { key = "portrait", aliases = { "portrait", "portrait settings" } },
    { key = "power", aliases = { "power", "mana", "energy", "resource", "power settings", "mana settings", "energy settings", "resource settings", "power bar", "powerbar", "detached power", "detached power bar", "resource bar" } },
    { key = "castbar", aliases = { "castbar", "cast bar" } },
    { key = "status", aliases = { "status icon", "status icons", "status indicator", "status indicators", "indicator", "indicators", "level indicator", "raid marker" } },
    { key = "load", aliases = { "load condition", "load conditions", "hide mounted", "hide out of combat" } },
    { key = "transparency", aliases = { "transparency", "opacity", "alpha", "range fade" } },
    { key = "basics", aliases = { "frame basics", "basic settings", "basics", "enable state", "smooth fill", "reverse fill" } },
}

local GROUP_COPY_SCOPE_DEFAULTS = {
    general = true,
    health = true,
    text = true,
    font = true,
    border = true,
    range = true,
    indicators = true,
    auras = true,
    highlight = true,
    dstripe = true,
    features = true,
}

local GROUP_COPY_SCOPE_SPECS = {
    { key = "general", aliases = { "general", "basics", "basic settings", "layout", "position", "positioning", "placement", "size", "width", "height", "spacing", "growth", "sort", "sorting", "columns", "raid groups" } },
    { key = "health", aliases = { "health", "health bars", "bars", "power", "power bar", "power text", "bar texture", "dispel overlay" } },
    { key = "text", aliases = { "text", "name", "health text", "hp text", "text and name" } },
    { key = "font", aliases = { "font", "fonts", "font override", "font color", "font outline" } },
    { key = "border", aliases = { "background", "opacity", "alpha", "transparency", "background opacity" } },
    { key = "range", aliases = { "range", "range fade", "offline alpha" } },
    { key = "indicators", aliases = { "indicators", "status icons", "status icon", "role icon", "leader icon", "assist icon", "raid marker", "ready check", "summon icon" } },
    { key = "auras", aliases = { "auras", "aura", "buffs", "buff", "debuffs", "debuff" } },
    { key = "highlight", aliases = { "highlight", "aggro", "aggro highlight", "dispel border", "purge border" } },
    { key = "dstripe", aliases = { "debuff stripe", "stripe" } },
    { key = "features", aliases = { "corner", "corner indicator", "corner indicators", "corner dots", "spell indicator", "spell indicators", "corner spell" } },
}

local function CopyScopeDefaults()
    local UP = M and M.UnitPage
    if UP and type(UP.NewCopyScopeDefaults) == "function" then
        local scopes = UP.NewCopyScopeDefaults()
        if type(scopes) == "table" then return scopes end
    end

    local scopes = {}
    local cats = UP and type(UP.UF_COPY_CATEGORIES) == "table" and UP.UF_COPY_CATEGORIES or nil
    if cats then
        for i = 1, #cats do
            local cat = cats[i]
            if type(cat) == "table" and type(cat.key) == "string" then
                scopes[cat.key] = cat.default ~= false
            end
        end
        if next(scopes) then return scopes end
    end

    for key, value in pairs(COPY_SCOPE_DEFAULTS) do scopes[key] = value end
    return scopes
end

local COPY_SCOPE_NEGATIVE_PREFIXES = {
    "without ",
    "with no ",
    "except ",
    "except for ",
    "excluding ",
    "exclude ",
    "but not ",
    "not ",
    "no ",
    "minus ",
    "skip ",
    "leave out ",
    "ohne ",
    "ohne die ",
    "ohne den ",
    "ausser ",
    "ausser die ",
    "ausser den ",
    "nicht ",
}

local function ScopeAliasHasNegativePrefix(text, alias)
    if not alias or alias == "" then return false end
    for i = 1, #COPY_SCOPE_NEGATIVE_PREFIXES do
        if HasPhrase(text, COPY_SCOPE_NEGATIVE_PREFIXES[i] .. alias) then return true end
    end
    return false
end

local function CopyScopeNegativeKeySet(text, specs)
    local keys = {}
    for i = 1, #(specs or {}) do
        local spec = specs[i]
        if spec and spec.key then
            for j = 1, #(spec.aliases or {}) do
                if ScopeAliasHasNegativePrefix(text, spec.aliases[j]) then
                    keys[spec.key] = true
                    break
                end
            end
        end
    end
    return keys
end

local function CopyScopeMatches(text, specs, negativeKeys)
    local matches = {}
    local seen = {}
    for i = 1, #(specs or {}) do
        local spec = specs[i]
        if spec.key and not seen[spec.key] and not (negativeKeys and negativeKeys[spec.key]) then
            for j = 1, #(spec.aliases or {}) do
                if HasPhrase(text, spec.aliases[j]) then
                    matches[#matches + 1] = spec.key
                    seen[spec.key] = true
                    break
                end
            end
        end
    end
    return matches
end

local function ApplyCopyScopeMatches(scopes, matches)
    if not matches or #matches == 0 then return false end
    for key in pairs(scopes) do scopes[key] = false end
    for i = 1, #matches do scopes[matches[i]] = true end
    return true
end

local function WantsFullUnitCopy(text, matches)
    if ContainsAny(text, { "all settings", "all categories", "everything", "complete settings", "entire unit", "whole unit", "copy to function", "copy-to function", "copyto function", "copy to workflow" }) then
        return true
    end
    if ContainsAny(text, { "profile", "profil", "unit profile", "unitframe profile", "unit frame profile", "frame profile" }) then
        if not matches then
            matches = CopyScopeMatches(text, UNIT_COPY_SCOPE_SPECS, CopyScopeNegativeKeySet(text, UNIT_COPY_SCOPE_SPECS))
        end
        return #matches == 0
    end
    return false
end

local function WantsFullGroupCopy(text, matches)
    if ContainsAny(text, { "all settings", "all categories", "everything", "complete settings", "entire group", "whole group", "copy to function", "copy-to function", "copyto function", "copy to workflow" }) then
        return true
    end
    if ContainsAny(text, { "profile", "profil", "group profile", "groupframe profile", "group frame profile", "frame profile" }) then
        if not matches then
            matches = CopyScopeMatches(text, GROUP_COPY_SCOPE_SPECS, CopyScopeNegativeKeySet(text, GROUP_COPY_SCOPE_SPECS))
        end
        return #matches == 0
    end
    return false
end

local function ApplyCopyScopeExclusions(scopes, negativeKeys)
    for key in pairs(negativeKeys or {}) do
        if scopes[key] ~= nil then scopes[key] = false end
    end
end

local function CopyScopesForText(text)
    local scopes = CopyScopeDefaults()
    local negativeKeys = CopyScopeNegativeKeySet(text, UNIT_COPY_SCOPE_SPECS)
    local matches = CopyScopeMatches(text, UNIT_COPY_SCOPE_SPECS, negativeKeys)
    if WantsFullUnitCopy(text, matches) then
        for key in pairs(scopes) do scopes[key] = true end
    else
        local matched = ApplyCopyScopeMatches(scopes, matches)
        if matched and ContainsAny(text, { "size", "width", "height" }) then scopes.basics = true end
    end
    ApplyCopyScopeExclusions(scopes, negativeKeys)
    return scopes
end

local function GroupCopyScopeDefaults()
    local GP = M and M.GroupPage
    if GP and type(GP.NewGFCopyScopes) == "function" then
        local scopes = GP.NewGFCopyScopes()
        if type(scopes) == "table" then return scopes end
    end

    local scopes = {}
    local cats = GP and type(GP.GF_COPY_CATEGORIES) == "table" and GP.GF_COPY_CATEGORIES or nil
    if cats then
        for i = 1, #cats do
            local cat = cats[i]
            if type(cat) == "table" and type(cat.key) == "string" then scopes[cat.key] = true end
        end
        if next(scopes) then return scopes end
    end

    for key, value in pairs(GROUP_COPY_SCOPE_DEFAULTS) do scopes[key] = value end
    return scopes
end

local function GroupCopyScopesForText(text)
    local scopes = GroupCopyScopeDefaults()
    local negativeKeys = CopyScopeNegativeKeySet(text, GROUP_COPY_SCOPE_SPECS)
    local matches = CopyScopeMatches(text, GROUP_COPY_SCOPE_SPECS, negativeKeys)
    if WantsFullGroupCopy(text, matches) then
        for key in pairs(scopes) do scopes[key] = true end
    else
        ApplyCopyScopeMatches(scopes, matches)
    end
    ApplyCopyScopeExclusions(scopes, negativeKeys)
    return scopes
end

local function CleanProfileName(name)
    name = Trim(tostring(name or ""))
    name = name:gsub("^profile%s+", "")
    name = name:gsub("^profil%s+", "")
    name = name:gsub("^the%s+profile%s+", "")
    name = name:gsub("^the%s+", "")
    name = name:gsub("^my%s+", "")
    name = name:gsub("%s+profile$", "")
    name = name:gsub("%s+profil$", "")
    name = name:gsub("^named%s+", "")
    name = name:gsub("^called%s+", "")
    name = name:gsub("^genannt%s+", "")
    name = name:gsub("^namens%s+", "")
    name = name:gsub("^heisst%s+", "")
    name = name:gsub("^to%s+", "")
    name = name:gsub("^as%s+", "")
    name = name:gsub("^zu%s+", "")
    name = name:gsub("^in%s+", "")
    name = name:gsub("^nach%s+", "")
    name = name:gsub("^als%s+", "")
    name = name:gsub("%s+umbenennen$", "")
    name = name:gsub("%s+um$", "")
    name = Trim(name)
    if name == "" then return nil end
    return name
end

local function CleanImportNewProfileName(name)
    name = CleanProfileName(name)
    if not name then return nil end
    name = name:gsub("%s+safely$", "")
    name = name:gsub("%s+after%s+backup$", "")
    name = name:gsub("^after%s+backup%s+", "")
    name = name:gsub("^backup%s+first%s+", "")
    name = Trim(name)
    local normalized = Normalize(name)
    if normalized == "" or normalized == "safe" or normalized == "safely"
        or normalized == "after backup" or normalized == "backup first"
        or normalized == "backup" or normalized == "first"
    then
        return nil
    end
    return CleanProfileName(name)
end

local function RawAfterPrefix(raw, prefixes)
    raw = tostring(raw or "")
    local lower = raw:lower()
    for i = 1, #(prefixes or {}) do
        local prefix = prefixes[i]
        if lower:sub(1, #prefix) == prefix then
            return CleanProfileName(raw:sub(#prefix + 1))
        end
    end
    return nil
end

local function RawBetween(raw, prefix, suffix)
    raw = tostring(raw or "")
    local lower = raw:lower()
    if lower:sub(1, #prefix) == prefix and lower:sub(-#suffix) == suffix then
        return CleanProfileName(raw:sub(#prefix + 1, #raw - #suffix))
    end
    return nil
end

local function RawCreateProfileName(raw)
    return RawAfterPrefix(raw, { "create profile ", "new profile " })
        or RawBetween(raw, "create ", " profile")
        or RawBetween(raw, "new ", " profile")
end

local function RawCopyProfileName(raw)
    return RawAfterPrefix(raw, { "copy current profile to ", "copy profile to ", "copy profile ", "duplicate profile " })
        or RawBetween(raw, "duplicate ", " profile")
end

local function SplitRawProfileBody(body, connectors)
    body = tostring(body or "")
    local lower = body:lower()
    for i = 1, #(connectors or {}) do
        local sepStart, sepEnd = lower:find(connectors[i])
        if sepStart then
            return CleanProfileName(body:sub(1, sepStart - 1)), CleanProfileName(body:sub(sepEnd + 1))
        end
    end
    return nil, nil
end

local function RawCopyProfileSourceDestination(raw)
    raw = tostring(raw or "")
    local lower = raw:lower()
    local connectors = { "%s+to%s+", "%s+as%s+", "%s+called%s+", "%s+named%s+" }
    local prefixes = {
        "clone ",
        "clone profile ",
        "clone current profile ",
        "clone active profile ",
        "clone my profile ",
        "clone my active profile ",
        "dupe ",
        "dupe profile ",
        "dupe current profile ",
        "dupe active profile ",
        "dupe my profile ",
        "dupe my active profile ",
        "copy profile ",
        "copy current profile ",
        "copy active profile ",
        "copy my profile ",
        "copy my active profile ",
        "duplicate profile ",
        "duplicate current profile ",
        "duplicate active profile ",
        "duplicate my profile ",
        "duplicate my active profile ",
        "make backup of ",
        "make a backup of ",
        "save backup of ",
        "save a backup of ",
        "backup profile ",
        "backup current profile ",
        "backup active profile ",
        "backup my profile ",
        "backup my current profile ",
        "backup my active profile ",
        "make a copy of profile ",
        "make a copy of this profile ",
        "make a copy of current profile ",
        "make a copy of active profile ",
        "make a copy of my profile ",
        "make a copy of my current profile ",
        "make a copy of my active profile ",
        "make copy of profile ",
        "make copy of this profile ",
        "make copy of current profile ",
        "make copy of active profile ",
        "make copy of my profile ",
        "make copy of my current profile ",
        "make copy of my active profile ",
        "create a copy of profile ",
        "create a copy of this profile ",
        "create a copy of current profile ",
        "create a copy of active profile ",
        "create a copy of my profile ",
        "create a copy of my current profile ",
        "create a copy of my active profile ",
        "create copy of profile ",
        "create copy of this profile ",
        "create copy of current profile ",
        "create copy of active profile ",
        "create copy of my profile ",
        "create copy of my current profile ",
        "create copy of my active profile ",
    }
    for i = 1, #prefixes do
        local prefix = prefixes[i]
        if lower:sub(1, #prefix) == prefix then
            return SplitRawProfileBody(raw:sub(#prefix + 1), connectors)
        end
    end
    return nil, nil
end

local function RawCurrentProfileCopyName(raw)
    raw = tostring(raw or "")
    local lower = raw:lower()
    local prefixes = {
        "copy current profile called ",
        "copy current profile named ",
        "clone current profile to ",
        "clone current profile as ",
        "clone current profile called ",
        "clone current profile named ",
        "clone active profile to ",
        "clone active profile as ",
        "clone active profile called ",
        "clone active profile named ",
        "clone my profile to ",
        "clone my profile as ",
        "clone my profile called ",
        "clone my profile named ",
        "clone my active profile to ",
        "clone my active profile as ",
        "clone my active profile called ",
        "clone my active profile named ",
        "dupe current profile to ",
        "dupe current profile as ",
        "dupe current profile called ",
        "dupe current profile named ",
        "dupe active profile to ",
        "dupe active profile as ",
        "dupe active profile called ",
        "dupe active profile named ",
        "dupe my profile to ",
        "dupe my profile as ",
        "dupe my profile called ",
        "dupe my profile named ",
        "dupe my active profile to ",
        "dupe my active profile as ",
        "dupe my active profile called ",
        "dupe my active profile named ",
        "copy current profile to ",
        "copy current profile as ",
        "copy active profile called ",
        "copy active profile named ",
        "copy active profile to ",
        "copy active profile as ",
        "copy my current profile called ",
        "copy my current profile named ",
        "copy my profile to ",
        "copy my profile as ",
        "copy my profile called ",
        "copy my profile named ",
        "copy my active profile to ",
        "copy my active profile as ",
        "copy my active profile called ",
        "copy my active profile named ",
        "duplicate current profile to ",
        "duplicate current profile as ",
        "duplicate current profile called ",
        "duplicate current profile named ",
        "duplicate active profile to ",
        "duplicate active profile as ",
        "duplicate active profile called ",
        "duplicate active profile named ",
        "duplicate my profile to ",
        "duplicate my profile as ",
        "duplicate my profile called ",
        "duplicate my profile named ",
        "duplicate my active profile to ",
        "duplicate my active profile as ",
        "duplicate my active profile called ",
        "duplicate my active profile named ",
        "make backup of current profile called ",
        "make backup of current profile named ",
        "make a backup of current profile called ",
        "make a backup of current profile named ",
        "save backup of current profile as ",
        "save a backup of current profile as ",
        "save current profile as ",
        "save active profile as ",
        "save my profile as ",
        "save my current profile as ",
        "save my active profile as ",
        "backup current profile to ",
        "backup current profile as ",
        "backup active profile to ",
        "backup active profile as ",
        "backup my profile to ",
        "backup my profile as ",
        "backup my current profile to ",
        "backup my current profile as ",
        "backup my active profile to ",
        "backup my active profile as ",
        "make a copy of this profile called ",
        "make a copy of this profile named ",
        "make a copy of this profile as ",
        "make a copy of current profile called ",
        "make a copy of current profile named ",
        "make a copy of current profile as ",
        "make a copy of active profile called ",
        "make a copy of active profile named ",
        "make a copy of active profile as ",
        "make a copy of my profile called ",
        "make a copy of my profile named ",
        "make a copy of my profile as ",
        "make a copy of my current profile called ",
        "make a copy of my current profile named ",
        "make a copy of my current profile as ",
        "make a copy of my active profile called ",
        "make a copy of my active profile named ",
        "make a copy of my active profile as ",
    }
    for i = 1, #prefixes do
        local prefix = prefixes[i]
        if lower:sub(1, #prefix) == prefix then
            return CleanProfileName(raw:sub(#prefix + 1))
        end
    end
    return nil
end

local function RawCreateProfileFromCurrentCopyName(raw)
    return RawAfterPrefix(raw, {
        "create profile from current called ",
        "create profile from current named ",
        "create profile from current as ",
        "create profile from active called ",
        "create profile from active named ",
        "create profile from active as ",
        "create new profile from current called ",
        "create new profile from current named ",
        "create new profile from current as ",
        "make profile from current called ",
        "make profile from current named ",
        "make profile from current as ",
        "make new profile from current called ",
        "make new profile from current named ",
        "make new profile from current as ",
        "make a new profile from current called ",
        "make a new profile from current named ",
        "make a new profile from current as ",
        "new profile from current called ",
        "new profile from current named ",
        "new profile from current as ",
    })
end

local function IsCurrentProfileName(name)
    name = Normalize(name)
    return name == "current" or name == "active" or name == "this"
        or name == "current profile" or name == "active profile" or name == "this profile"
end

local function RawRenameProfileNames(raw)
    raw = tostring(raw or "")
    local lower = raw:lower()
    local function splitBody(body, connectors)
        body = tostring(body or "")
        local lowerBody = body:lower()
        for i = 1, #(connectors or {}) do
            local sepStart, sepEnd = lowerBody:find(connectors[i], 1)
            if sepStart then
                return CleanProfileName(body:sub(1, sepStart - 1)), CleanProfileName(body:sub(sepEnd + 1))
            end
        end
        return nil, nil
    end
    local function splitAfterPrefix(prefix, connectors)
        if lower:sub(1, #prefix) ~= prefix then return nil, nil end
        local start = #prefix + 1
        return splitBody(raw:sub(start), connectors)
    end
    local englishConnectors = { "%s+to%s+" }
    local germanConnectors = { "%s+um%s+in%s+", "%s+um%s+zu%s+", "%s+in%s+", "%s+zu%s+" }

    local source, dest = splitAfterPrefix("rename profile ", englishConnectors)
    if source and dest then return source, dest end

    dest = RawAfterPrefix(raw, { "rename current profile to ", "rename profile to " })
    if dest then return nil, dest end

    source, dest = splitAfterPrefix("benenne profil ", germanConnectors)
    if source and dest then return source, dest end
    source, dest = splitAfterPrefix("benenne profile ", germanConnectors)
    if source and dest then return source, dest end
    local body = RawBetween(raw, "profil ", " umbenennen") or RawBetween(raw, "profile ", " umbenennen")
    if body then
        source, dest = splitBody(body, germanConnectors)
        if source and dest then return source, dest end
        return CleanProfileName(body), nil
    end

    dest = RawAfterPrefix(raw, {
        "benenne aktuelles profil in ",
        "benenne aktuelles profil zu ",
        "benenne profil in ",
        "benenne profil zu ",
        "aktuelles profil in ",
        "aktuelles profil zu ",
    })
    if dest then return nil, dest end

    source = RawAfterPrefix(raw, { "rename profile " })
    if source then return CleanProfileName(source), nil end

    source = RawAfterPrefix(raw, { "benenne profil ", "benenne profile ", "profil " })
    if source then return CleanProfileName(source), nil end

    source, dest = splitAfterPrefix("rename ", englishConnectors)
    if source and dest then
        source = CleanProfileName((source:gsub("%s+profile$", "")))
        return source, dest
    end

    source = RawAfterPrefix(raw, { "rename " })
    if source then
        source = CleanProfileName((source:gsub("%s+profile$", "")))
        if source ~= "" then return source, nil end
    end

    return nil, nil
end

local PROFILE_EXPORT_KIND_LABELS = {
    all = "Full profile",
    unitframe = "Unitframes",
    castbar = "Castbars",
    colors = "Colors",
    gameplay = "Gameplay",
    groupframe = "Group Frames",
}

local function ProfileExportKindForText(text)
    if ContainsAny(text, { "colors", "color palette", "color settings" }) then return "colors" end
    if ContainsAny(text, { "castbar", "castbars" }) then return "castbar" end
    if ContainsAny(text, { "gameplay", "combat timer", "crosshair", "totem frame" }) then return "gameplay" end
    if ContainsAny(text, { "group frame", "group frames", "groupframe", "party", "raid", "mythicraid" }) then return "groupframe" end
    if ContainsAny(text, { "unitframe", "unitframes", "unit frame", "unit frames", "player", "target", "focus", "boss", "pet" }) then return "unitframe" end
    return "all"
end

local function HasProfileExportIntent(text)
    if ContainsAny(text, { "restore", "recover", "rollback", "use backup", "use last backup", "load backup", "load last backup", "switch to backup", "switch to last backup" })
        and ContainsAny(text, { "backup", "backup profile", "profile backup", "last backup" })
    then
        return false
    end
    if ContainsAny(text, {
        "profile string", "export string", "profile export string", "copy profile string",
    }) and ContainsAny(text, {
        "show", "show me", "copy", "export", "share", "give me", "generate",
    }) and not ContainsAny(text, {
        "where", "paste", "import", "how", "how do", "how to", "why",
    }) then
        return true
    end
    if ContainsAny(text, {
        "where", "where is", "where are", "find", "search", "show me",
        "help", "hilfe", "explain", "erklaere", "what is", "what are", "what can",
        "how", "how do", "how to", "why", "faq", "broken", "not working", "doesnt work",
        "does not work", "won't work", "wont work", "fails", "failed", "failure", "error", "errors", "stuck",
    }) then
        return false
    end
    if ContainsAny(text, {
        "export", "exportieren", "share profile", "share current profile", "share active profile",
        "share my profile", "share msuf profile", "share my msuf profile",
        "copy string", "copy profile string", "profile string", "export string", "profile export string",
        "save backup", "save a backup", "save profile backup",
        "backup msuf settings", "backup my msuf settings", "backup settings", "backup my settings",
        "backup current settings", "backup my current settings", "make backup before import",
        "make a backup before import", "backup before import",
        "make backup before importing", "make a backup before importing", "backup before importing",
        "backup before profile import", "backup before importing profile",
        "backup raid profile", "backup party profile", "backup group profile",
        "backup group frame profile", "backup group frames profile",
        "backup raid settings", "backup party settings", "backup group frame settings", "backup group frames settings",
    }) then
        return true
    end
    if ContainsAny(text, { "backup profile", "backup current profile", "backup active profile", "profile backup" })
        and not ContainsAny(text, { " as ", " to ", " named ", " called " })
    then
        return true
    end
    return false
end

local function HasProfileReadOnlyQueryIntent(text)
    return ContainsAny(text, {
        "where", "where is", "where are", "find", "search", "show me",
        "help", "hilfe", "explain", "erklaere", "what is", "what are", "what can",
        "how", "how do", "how to", "why", "faq", "broken", "not working", "doesnt work",
        "does not work", "won't work", "wont work", "fails", "failed", "failure", "error", "errors", "stuck",
    })
end

local function IsBackupBeforeProfileImportIntent(text)
    return ContainsAny(text, {
        "make backup before import", "make a backup before import", "backup before import",
        "make backup before importing", "make a backup before importing", "backup before importing",
        "backup before profile import", "backup before importing profile",
        "backup first then import", "backup first and import", "backup then import",
        "make backup then import", "make a backup then import",
        "make backup first then import", "make a backup first then import",
    })
end

local function IsSafeProfileImportIntent(text)
    return ContainsAny(text, {
        "import safely", "import safe", "safe import", "safe profile import",
        "import profile safely", "import profile safe", "profile import safely",
        "import after backup", "import after backing up", "paste safely", "paste this safely",
        "paste profile safely", "paste profile after backup",
    }) or IsBackupBeforeProfileImportIntent(text)
end

local function BuildProfileBackupRestoreClarification(text)
    if not ContainsAny(text, {
        "restore backup", "restore my backup", "restore my backup profile",
        "restore backup profile", "restore profile backup",
        "restore last backup", "restore last backup profile",
        "recover backup", "recover my backup", "recover my backup profile",
        "use backup profile", "use my backup profile", "use last backup profile",
        "load backup profile", "load my backup profile", "load last backup profile",
        "switch to backup profile", "switch to last backup profile",
    }) then
        return nil
    end
    return {
        kind = "answer",
        status = "info",
        text = "I cannot safely know which backup profile you mean. MSUF backups are either copied profile names or export strings. Use the exact profile name, for example 'switch profile Raid Backup', or paste an MSUF profile string to import.",
        summary = "Clarifies ambiguous profile backup restore wording instead of guessing a profile name.",
    }
end

local function RawAfterLastConnector(raw, connectors)
    raw = tostring(raw or "")
    local lower = raw:lower()
    local bestEnd
    for i = 1, #(connectors or {}) do
        local connector = connectors[i]
        local start = 1
        while true do
            local s, e = lower:find(connector, start, true)
            if not s then break end
            if not bestEnd or e > bestEnd then bestEnd = e end
            start = e + 1
        end
    end
    if not bestEnd then return nil end
    local value = Trim(raw:sub(bestEnd + 1))
    if value == "" then return nil end
    return value
end

local function CleanSpecName(name)
    name = Trim(tostring(name or ""))
    name = name:gsub("^spec%s+", "")
    name = name:gsub("^specialization%s+", "")
    name = name:gsub("%s+spec$", "")
    name = name:gsub("%s+specialization$", "")
    name = name:gsub("^for%s+", "")
    name = name:gsub("^to%s+", "")
    name = Trim(name)
    if name == "" then return nil end
    return name
end

local function StripProfileImportString(value)
    value = tostring(value or "")
    value = value:gsub("%s+[Mm][Ss][Uu][Ff]%d+:%S+.*$", "")
    value = value:gsub("%s+![Uu][Uu][Ff]_%S+.*$", "")
    return value
end

local function ImportNewProfileName(raw, startIndex, endIndex, text)
    if text == nil then
        text = endIndex
        endIndex = startIndex
        startIndex = nil
    end
    raw = tostring(raw or "")
    if startIndex then
        local before = StripProfileImportString(Trim(raw:sub(1, startIndex - 1)))
        local beforeName = RawAfterLastConnector(before, { " as ", " to new profile ", " new profile ", " named ", " called " })
        beforeName = CleanImportNewProfileName(beforeName)
        if beforeName then return beforeName end
    end
    local after = Trim(tostring(raw or ""):sub((endIndex or 0) + 1))
    local lower = after:lower()
    if lower:sub(1, 15) == "as new profile " then return CleanImportNewProfileName(StripProfileImportString(after:sub(16))) end
    if lower:sub(1, 11) == "as profile " then return CleanImportNewProfileName(StripProfileImportString(after:sub(12))) end
    if lower:sub(1, 3) == "as " then return CleanImportNewProfileName(StripProfileImportString(after:sub(4))) end
    if lower:sub(1, 15) == "to new profile " then return CleanImportNewProfileName(StripProfileImportString(after:sub(16))) end
    if lower:sub(1, 12) == "new profile " then return CleanImportNewProfileName(StripProfileImportString(after:sub(13))) end
    if startIndex then return nil end
    local name = StripProfileImportString(text:match("as%s+(.+)$")
        or text:match("to%s+new%s+profile%s+(.+)$")
        or text:match("new%s+profile%s+(.+)$"))
    return CleanImportNewProfileName(name)
end

local function BuildMissingImportNewProfileNameAnswer(text)
    if not ContainsAny(text, { "new profile", "new-profile", "as new profile", "to new profile" }) then return nil end
    return {
        kind = "answer",
        status = "info",
        text = "I need a new profile name to import into a new profile. Example: import this as new profile Raid Import MSUF5:...",
        summary = "Clarifies safe new-profile import wording without treating safety words as a profile name.",
    }
end

local function UUFBestEffortConfirmText()
    return "This is an UnhaltedUnitFrames profile. MSUF will translate it as a best-effort import. Auras are not imported, and unsupported UUF-only settings may not map 1:1. Type 'yes', 'do it', or 'mach das' to import anyway, or 'cancel'."
end

local function BuildSpecAutoSwitch(text)
    if not ContainsAny(text, {
        "auto switch profile", "auto-switch profile", "profile auto switch",
        "profile by specialization", "profile by spec", "spec profile switching",
        "specialization profile switching",
    }) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    local setting = Registry and Registry:GetSetting("profiles.specAutoSwitch")
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = (value and "Enable" or "Disable") .. " spec profile switching",
        summary = "Uses the MSUF Profiles spec auto-switch setting.",
    } or nil
end

local function BuildSpecProfileAction(text)
    if not (ContainsAny(text, { "spec profile", "specialization profile", "profile by spec", "profile by specialization" })
        or (HasPhrase(text, "profile") and (HasPhrase(text, "spec") or HasPhrase(text, "specialization"))))
    then
        return nil
    end
    if ContainsAny(text, { "clear", "remove", "unset" }) then
        local spec = text:match("clear%s+spec%s+profile%s+(.+)$")
            or text:match("clear%s+(.+)%s+spec%s+profile$")
            or text:match("remove%s+spec%s+profile%s+(.+)$")
            or text:match("unset%s+spec%s+profile%s+(.+)$")
            or text:match("remove%s+profile%s+from%s+(.+)%s+spec$")
        spec = CleanSpecName(spec)
        local action = Registry and Registry:GetAction("clear_spec_profile")
        return spec and action and {
            kind = "action",
            action = action,
            args = { spec = spec },
            label = "Clear spec profile",
            summary = "Clears the selected specialization profile assignment.",
        } or nil
    end
    if ContainsAny(text, { "assign", "set" }) then
        local spec, name = text:match("set%s+spec%s+profile%s+(.+)%s+to%s+(.+)$")
        if not spec then spec, name = text:match("set%s+(.+)%s+spec%s+profile%s+to%s+(.+)$") end
        if not spec then name, spec = text:match("assign%s+(.+)%s+profile%s+to%s+(.+)%s+spec$") end
        if not spec then name, spec = text:match("assign%s+profile%s+(.+)%s+to%s+spec%s+(.+)$") end
        if not spec then name, spec = text:match("assign%s+(.+)%s+to%s+(.+)%s+spec%s+profile$") end
        spec = CleanSpecName(spec)
        name = CleanProfileName(name)
        local action = Registry and Registry:GetAction("set_spec_profile")
        return spec and name and action and {
            kind = "action",
            action = action,
            args = { spec = spec, name = name },
            label = "Set spec profile",
            summary = "Assigns an existing profile to a specialization.",
        } or nil
    end
    return nil
end


local function ParseWorkflowLifecycle(text)
    if ContainsAny(text, { "workflow status", "assistant workflow status", "pending workflow", "pending flow", "active workflow", "what workflow", "what is pending" }) then
        local action = Registry and Registry:GetAction("assistant.workflow.status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show Assistant workflow status",
            summary = "Shows pending confirmations, panels, flows, and Edit Mode lifecycle status.",
        } or nil
    end
    if text == "back" or ContainsAny(text, { "go back", "open previous page", "previous page", "return to previous page", "back to previous page" }) then
        local action = Registry and Registry:GetAction("dashboard_page_back")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Open previous Dashboard page",
            summary = "Uses the Assistant page stack first, then native Menu2 page history when available.",
        } or nil
    end
    if text == "forward" or text == "forwards" or text == "vorwaerts" or ContainsAny(text, {
        "go forward", "open next page", "next page", "forward page", "return forward", "page forward",
        "go to next page", "naechste seite", "seite vorwaerts",
    }) then
        local action = Registry and Registry:GetAction("dashboard_page_forward")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Open next Dashboard page",
            summary = "Uses native Menu2 page history when available.",
        } or nil
    end
    if text == "cancel" or ContainsAny(text, { "cancel workflow", "cancel current workflow", "cancel assistant workflow", "stop assistant workflow", "abort workflow" }) then
        local action = Registry and Registry:GetAction("assistant.workflow.cancel")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Cancel active Assistant workflow",
            summary = "Cancels the active Assistant confirmation, flow, panel, or guide when available.",
        } or nil
    end
    if ContainsAny(text, { "close import", "cancel import", "close export", "close assistant panel", "close profile import", "cancel profile import", "close profile export" }) then
        local action = Registry and Registry:GetAction("assistant.panel.close")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Close Assistant panel",
            summary = "Closes the current Assistant import/export/text panel.",
        } or nil
    end
    return nil
end

local function BuildMenuSelectorState(args, label, summary)
    local action = Registry and Registry:GetAction("set_menu_selector_state")
    return action and {
        kind = "action",
        action = action,
        args = args,
        label = label or "Set menu selector state",
        summary = summary or "Selects or stages a Menu2 UI state.",
    } or nil
end

local function ParseProfileStagingState(text, raw)
    if not ContainsAny(text, { "profile", "profiles", "profil" }) then return nil end
    local hasStagingIntent = ContainsAny(text, {
        "field", "input", "text box", "textbox", "staging", "stage", "select", "choose", "set", "fill", "paste into",
        "turn on", "turn off", "enable", "disable",
    })
    if not hasStagingIntent then return nil end

    if ContainsAny(text, { "export kind", "export type", "export dropdown", "profile export kind", "profile export type" }) then
        return BuildMenuSelectorState({
            selector = "profile_staging",
            field = "profileExportKind",
            kind = ProfileExportKindForText(text),
        }, "Select profile export kind", "Selects the Profiles export-kind dropdown without immediately exporting.")
    end

    if ContainsAny(text, { "import and create new profile", "import create new", "new profile import", "new-profile import", "import into new profile", "create new profile import" }) then
        local value = DetectBoolean(text)
        if value == nil then value = not ContainsAny(text, { "off", "disable", "disabled", "current profile", "active profile" }) end
        return BuildMenuSelectorState({
            selector = "profile_staging",
            field = "profileImportCreateNew",
            value = value,
        }, "Set profile import mode", "Sets the Profiles import-and-create-new-profile toggle.")
    end

    if ContainsAny(text, { "new profile name", "new-profile name", "import new profile name", "import profile name" })
        and ContainsAny(text, { "import", "new profile", "new-profile" })
    then
        local value = CleanProfileName(RawAfterLastConnector(raw, { " to ", " as ", " named ", " called ", " name ", " value " }))
        if value then
            return BuildMenuSelectorState({
                selector = "profile_staging",
                field = "profileImportNewName",
                value = value,
            }, "Set profile import new-profile name", "Stages the Profiles new-profile import name field.")
        end
    end

    if ContainsAny(text, { "profile string", "import string", "profile import string" })
        and ContainsAny(text, { "field", "input", "text box", "textbox", "stage", "staging", "set", "fill", "paste into" })
    then
        local value = RawAfterLastConnector(raw, { " to ", " with ", " value ", " text ", " string ", " paste " })
        if value then
            return BuildMenuSelectorState({
                selector = "profile_staging",
                field = "profileString",
                value = value,
            }, "Set profile string field", "Stages the Profiles profile-string field without importing.")
        end
    end

    if ContainsAny(text, { "profile name field", "profile name input", "create copy name", "create/copy name", "profile create name", "profile copy name", "profile name for create", "profile name for copy" }) then
        local value = CleanProfileName(RawAfterLastConnector(raw, { " to ", " as ", " named ", " called ", " name ", " value " }))
        if value then
            return BuildMenuSelectorState({
                selector = "profile_staging",
                field = "profileCreateCopyName",
                value = value,
            }, "Set profile create/copy name", "Stages the Profiles create/copy name field.")
        end
    end

    return nil
end

local function ParseGroupCopyScopeState(text)
    if not ContainsAny(text, { "group copy", "group frame copy", "group frames copy", "copy category", "copy categories", "copy scope", "copy scopes" }) then return nil end
    if not ContainsAny(text, { "category", "categories", "scope", "scopes" }) then return nil end

    if ContainsAny(text, { "all categories", "select all", "turn on all", "enable all" })
        or (ContainsAny(text, { "all" }) and ContainsAny(text, { "turn on", "enable", "select" }))
    then
        return BuildMenuSelectorState({
            selector = "group_copy_scope",
            command = "all",
        }, "Select all group copy categories", "Sets every Group Frames copy-popup category checkbox on.")
    end
    if ContainsAny(text, { "no categories", "none", "select none", "clear categories", "turn off all", "disable all" })
        or (ContainsAny(text, { "clear", "disable" }) and ContainsAny(text, { "category", "categories", "scope", "scopes" }))
    then
        return BuildMenuSelectorState({
            selector = "group_copy_scope",
            command = "none",
        }, "Clear group copy categories", "Sets every Group Frames copy-popup category checkbox off.")
    end

    local matches = CopyScopeMatches(text, GROUP_COPY_SCOPE_SPECS)
    if #matches == 0 then return nil end
    if ContainsAny(text, { "only", "only these", "just" }) then
        return BuildMenuSelectorState({
            selector = "group_copy_scope",
            command = "only",
            categories = matches,
        }, "Select only group copy categories", "Sets the Group Frames copy-popup categories to exactly the requested category set.")
    end

    local value = DetectBoolean(text)
    if value == nil then
        if ContainsAny(text, { "exclude", "without", "remove", "disable" }) then value = false else value = true end
    end
    return BuildMenuSelectorState({
        selector = "group_copy_scope",
        category = matches[1],
        value = value,
    }, "Set group copy category", "Sets one Group Frames copy-popup category checkbox.")
end

local function ParseUnitCopyScopeState(text)
    if ContainsAny(text, { "group copy", "group frame copy", "group frames copy", "group copy category", "group copy categories", "group copy scope", "group copy scopes" }) then return nil end
    if not ContainsAny(text, { "category", "categories", "scope", "scopes" }) then return nil end
    local units = DetectUnits(text)
    local pageUnit
    local page = M and M.activeKey
    for i = 1, #ALL_UNITFRAMES do
        local unit = ALL_UNITFRAMES[i]
        if UnitPageKey(unit) == page then
            pageUnit = unit
            break
        end
    end
    local explicit = ContainsAny(text, { "unit copy", "unit frame copy", "unit frames copy", "unitframe copy", "unitframes copy", "frame copy" })
    if not explicit and #units == 0 and not pageUnit then return nil end
    if ContainsAny(text, { "all categories", "select all", "turn on all", "enable all" })
        or (ContainsAny(text, { "all" }) and ContainsAny(text, { "turn on", "enable", "select" }))
    then
        return BuildMenuSelectorState({
            selector = "unit_copy_scope",
            unit = units[1] or pageUnit,
            command = "all",
        }, "Select all unit copy categories", "Sets every Unit Copy popup category checkbox on.")
    end
    if ContainsAny(text, { "no categories", "none", "select none", "clear categories", "turn off all", "disable all" })
        or (ContainsAny(text, { "clear", "disable" }) and ContainsAny(text, { "category", "categories", "scope", "scopes" }))
    then
        return BuildMenuSelectorState({
            selector = "unit_copy_scope",
            unit = units[1] or pageUnit,
            command = "none",
        }, "Clear unit copy categories", "Sets every Unit Copy popup category checkbox off.")
    end

    local matches = CopyScopeMatches(text, UNIT_COPY_SCOPE_SPECS)
    if #matches == 0 then return nil end
    if ContainsAny(text, { "only", "only these", "just" }) then
        return BuildMenuSelectorState({
            selector = "unit_copy_scope",
            unit = units[1] or pageUnit,
            command = "only",
            categories = matches,
        }, "Select only unit copy categories", "Sets the Unit Copy popup categories to exactly the requested category set.")
    end

    local value = DetectBoolean(text)
    if value == nil then
        if ContainsAny(text, { "exclude", "without", "remove", "disable" }) then value = false else value = true end
    end
    return BuildMenuSelectorState({
        selector = "unit_copy_scope",
        unit = units[1] or pageUnit,
        category = matches[1],
        value = value,
    }, "Set unit copy category", "Sets one Unit Copy popup category checkbox.")
end

local function ParseProfile(text, raw)
    local rawText = tostring(raw or "")
    local compactStart, endIndex, compact = rawText:find("(MSUF%d+:%S+)")
    local uufStart, uufEndIndex, uufCompact = rawText:find("(!UUF_%S+)")
    local hasProfileWord = ContainsAny(text, { "profile", "profiles", "profil" })
    local hasExportIntent = HasProfileExportIntent(text)
    local safeImportIntent = IsSafeProfileImportIntent(text)
    local hasProfile = hasProfileWord or hasExportIntent or safeImportIntent
    local rawLower = tostring(raw or ""):lower()
    local implicitSwitchName
    if not hasProfile and ContainsAny(text, { "switch to", "wechsel zu" }) then
        local maybeName = CleanProfileName(RawAfterPrefix(rawText, { "switch to ", "wechsel zu " })
            or text:match("^switch%s+to%s+(.+)$")
            or text:match("^wechsel%s+zu%s+(.+)$"))
        if maybeName then
            local resolved, how
            if type(A.ResolveProfileName) == "function" then resolved, how = A.ResolveProfileName(maybeName) end
            if how == "exact" or how == "partial" or M.activeKey == "profiles" then
                implicitSwitchName = resolved or maybeName
                hasProfile = true
            end
        end
    end
    local backupRestoreClarification = BuildProfileBackupRestoreClarification(text)
    if backupRestoreClarification then return backupRestoreClarification end
    if compact and (hasProfileWord or ContainsAny(text, { "import", "importiere", "paste" }) or rawLower:find("^msuf%d+:")) then
        local legacy = ContainsAny(text, { "legacy import", "import legacy", "old profile import", "legacy profile" })
        local newName = ImportNewProfileName(rawText, compactStart, endIndex, text)
        if not newName then
            local missingName = BuildMissingImportNewProfileNameAnswer(text)
            if missingName then return missingName end
        end
        local action = Registry and Registry:GetAction(legacy and "import_legacy_profile_string" or (newName and "import_profile_string_new" or "import_profile_string"))
        return action and {
            kind = "action",
            action = action,
            args = newName and { value = compact, name = newName } or { value = compact },
            confirmRequired = true,
            label = legacy and "Import legacy profile string" or (newName and ("Import profile string as " .. tostring(newName)) or "Import profile string"),
            summary = newName and "Imports profile data into a new profile." or "Imports profile data into the active profile.",
        } or nil
    end
    if uufCompact and (hasProfileWord or ContainsAny(text, { "import", "importiere", "paste" }) or rawLower:find("^%s*!uuf_")) then
        local newName = ImportNewProfileName(rawText, uufStart, uufEndIndex, text)
        if not newName then
            local missingName = BuildMissingImportNewProfileNameAnswer(text)
            if missingName then return missingName end
        end
        local action = Registry and Registry:GetAction(newName and "import_profile_string_new" or "import_profile_string")
        return action and {
            kind = "action",
            action = action,
            args = newName
                and { value = uufCompact, name = newName, uufBestEffortAccepted = true }
                or { value = uufCompact, uufBestEffortAccepted = true },
            confirmRequired = true,
            confirmText = UUFBestEffortConfirmText(),
            label = newName and ("Import UnhaltedUnitFrames profile string as " .. tostring(newName)) or "Import UnhaltedUnitFrames profile string",
            summary = newName and "Imports translated UUF profile data into a new profile." or "Imports translated UUF profile data into the active profile.",
        } or nil
    end
    if not hasProfile then return nil end

    if ContainsAny(text, {
        "profile mapping", "profile mappings", "spec profile mapping", "spec profile mappings",
        "broken profile mapping", "broken profile mappings", "broken spec mapping", "broken spec mappings",
    }) and ContainsAny(text, { "clear", "fix", "repair", "remove", "clean" }) then
        local action = Registry and Registry:GetAction("clear_broken_spec_profile_mappings")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Clear broken spec profile mappings",
            summary = "Removes specialization profile assignments that point to missing profiles.",
        } or nil
    end

    local specSwitch = BuildSpecAutoSwitch(text)
    if specSwitch then return specSwitch end

    local specProfile = BuildSpecProfileAction(text)
    if specProfile then return specProfile end

    if ContainsAny(text, { "wago profile", "wago profiles", "browse wago profiles", "profile hub" }) then
        local action = Registry and Registry:GetAction("copy_wago_profiles_link")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Copy Wago profiles link",
            summary = "Opens a copyable Wago MSUF profiles link.",
        } or nil
    end

    if IsBackupBeforeProfileImportIntent(text) then
        local action = Registry and Registry:GetAction("export_profile")
        return action and {
            kind = "action",
            action = action,
            args = { kind = "all" },
            label = "Export current profile",
            summary = "Creates a copyable profile export string before opening/importing another profile.",
        } or nil
    end

    if ContainsAny(text, { "import", "importieren", "paste" }) and not HasProfileReadOnlyQueryIntent(text) then
        local action = Registry and Registry:GetAction("open_profile_import")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Open profile import",
            summary = "Opens the Profiles import UI.",
        } or nil
    end

    if ContainsAny(text, { "delete", "remove", "loeschen", "profil loeschen" }) then
        local name = RawAfterPrefix(rawText, { "delete profile ", "delete the profile ", "remove profile ", "remove the profile " })
            or text:match("delete%s+profile%s+(.+)$")
            or text:match("delete%s+the%s+profile%s+(.+)$")
            or text:match("delete%s+(.+)%s+profile$")
            or text:match("remove%s+profile%s+(.+)$")
            or text:match("remove%s+the%s+profile%s+(.+)$")
            or text:match("remove%s+(.+)%s+profile$")
            or text:match("loesche%s+profil%s+(.+)$")
            or text:match("profil%s+(.+)%s+loeschen$")
        name = CleanProfileName(name)
        if name then
            local action = Registry and Registry:GetAction("delete_profile")
            return action and {
                kind = "action",
                action = action,
                args = { name = name },
                confirmRequired = true,
                label = "Delete profile " .. tostring(name),
                summary = "Deletes an MSUF profile through the existing profile helper.",
            } or nil
        end
    end

    if implicitSwitchName or ContainsAny(text, { "switch", "wechsel", "change profile", "use", "use profile", "use the", "use my", "activate", "load", "select profile" }) then
        local name = implicitSwitchName or RawAfterPrefix(rawText, {
                "switch to profile ",
                "switch profile to ",
                "switch profile ",
                "switch to ",
                "use profile ",
                "use the ",
                "use my ",
                "use ",
                "activate profile ",
                "activate ",
                "load profile ",
                "load ",
                "select profile ",
            })
            or text:match("switch%s+to%s+(.+)$")
            or text:match("switch%s+profile%s+to%s+(.+)$")
            or text:match("switch%s+profile%s+(.+)$")
            or text:match("use%s+profile%s+(.+)$")
            or text:match("use%s+the%s+(.+)%s+profile$")
            or text:match("use%s+my%s+(.+)%s+profile$")
            or text:match("use%s+(.+)%s+profile$")
            or text:match("activate%s+profile%s+(.+)$")
            or text:match("activate%s+(.+)%s+profile$")
            or text:match("load%s+profile%s+(.+)$")
            or text:match("load%s+(.+)%s+profile$")
            or text:match("select%s+profile%s+(.+)$")
            or text:match("select%s+(.+)%s+profile$")
            or text:match("wechsel%s+zu%s+(.+)$")
        name = CleanProfileName(name)
        if name then
            local action = Registry and Registry:GetAction("switch_profile")
            return action and {
                kind = "action",
                action = action,
                args = { name = name },
                label = "Switch profile",
                summary = "Switches the active MSUF profile.",
            } or nil
        end
    end

    do
        local name = RawCreateProfileFromCurrentCopyName(rawText)
            or text:match("create%s+profile%s+from%s+current%s+called%s+(.+)$")
            or text:match("create%s+profile%s+from%s+current%s+named%s+(.+)$")
            or text:match("create%s+profile%s+from%s+current%s+as%s+(.+)$")
        name = CleanProfileName(name)
        if name then
            local action = Registry and Registry:GetAction("copy_profile")
            return action and {
                kind = "action",
                action = action,
                args = { name = name },
                confirmRequired = true,
                label = "Copy current profile",
                summary = "Copies the active profile to a new profile name.",
            } or nil
        end
    end

    if ContainsAny(text, { "create", "new profile", "erstellen" }) then
        local name = RawCreateProfileName(rawText)
            or text:match("create%s+profile%s+(.+)$")
            or text:match("create%s+(.+)%s+profile$")
            or text:match("new%s+profile%s+(.+)$")
            or text:match("new%s+(.+)%s+profile$")
            or text:match("profile%s+(.+)$")
        name = CleanProfileName(name)
        if name then
            local action = Registry and Registry:GetAction("create_profile")
            return action and {
                kind = "action",
                action = action,
                args = { name = name, switch = true },
                label = "Create profile",
                summary = "Creates a new MSUF profile and switches to it.",
            } or nil
        end
    end

    if ContainsAny(text, { "rename", "umbenennen", "benenne", "benenn", "profile rename" }) then
        local source, dest = RawRenameProfileNames(rawText)
        if not source and not dest then source, dest = text:match("rename%s+profile%s+(.+)%s+to%s+(.+)$") end
        if not source then source, dest = text:match("rename%s+(.+)%s+profile%s+to%s+(.+)$") end
        if not source then source, dest = text:match("rename%s+(.+)%s+to%s+(.+)$") end
        if not source then dest = text:match("rename%s+current%s+profile%s+to%s+(.+)$") or text:match("rename%s+profile%s+to%s+(.+)$") end
        source = CleanProfileName(source)
        dest = CleanProfileName(dest)
        if dest then
            local action = Registry and Registry:GetAction("rename_profile")
            return action and {
                kind = "action",
                action = action,
                args = { source = source, name = dest },
                confirmRequired = true,
                label = "Rename profile",
                summary = "Renames a profile through a shared helper if one exists.",
            } or nil
        end
        if source then
            local action = Registry and Registry:GetAction("start_profile_rename_flow")
            return action and {
                kind = "action",
                action = action,
                args = { source = source },
                label = "Start profile rename flow",
                summary = "Asks for the missing destination profile name.",
            } or nil
        end
    end

    if ContainsAny(text, {
        "copy", "duplicate", "clone", "dupe", "backup", "duplizieren",
        "save current profile", "save active profile", "save my profile",
        "save my current profile", "save my active profile",
    }) then
        local source, dest = RawCopyProfileSourceDestination(rawText)
        if not source then source, dest = text:match("copy%s+profile%s+(.+)%s+to%s+(.+)$") end
        if not source then source, dest = text:match("copy%s+profile%s+(.+)%s+as%s+(.+)$") end
        if not source then source, dest = text:match("copy%s+(.+)%s+profile%s+to%s+(.+)$") end
        if not source then source, dest = text:match("duplicate%s+profile%s+(.+)%s+to%s+(.+)$") end
        if not source then source, dest = text:match("duplicate%s+profile%s+(.+)%s+as%s+(.+)$") end
        if not source then source, dest = text:match("clone%s+profile%s+(.+)%s+to%s+(.+)$") end
        if not source then source, dest = text:match("clone%s+profile%s+(.+)%s+as%s+(.+)$") end
        if not source then source, dest = text:match("dupe%s+profile%s+(.+)%s+to%s+(.+)$") end
        if not source then source, dest = text:match("dupe%s+profile%s+(.+)%s+as%s+(.+)$") end
        if not source then source, dest = text:match("backup%s+profile%s+(.+)%s+to%s+(.+)$") end
        if not source then source, dest = text:match("backup%s+profile%s+(.+)%s+as%s+(.+)$") end
        source = CleanProfileName(source)
        dest = CleanProfileName(dest)
        if source and dest then
            if IsCurrentProfileName(source) then
                local action = Registry and Registry:GetAction("copy_profile")
                return action and {
                    kind = "action",
                    action = action,
                    args = { name = dest },
                    confirmRequired = true,
                    label = "Copy current profile",
                    summary = "Copies the active profile to a new profile name.",
                } or nil
            end
            local action = Registry and Registry:GetAction("copy_profile_from_to")
            return action and {
                kind = "action",
                action = action,
                args = { source = source, name = dest },
                confirmRequired = true,
                label = "Copy profile " .. tostring(source) .. " to " .. tostring(dest),
                summary = "Copies a named source profile to a destination profile.",
            } or nil
        end

        local name = RawCurrentProfileCopyName(rawText)
            or RawCopyProfileName(rawText)
            or text:match("copy%s+current%s+profile%s+to%s+(.+)$")
            or text:match("copy%s+current%s+profile%s+as%s+(.+)$")
            or text:match("copy%s+profile%s+to%s+(.+)$")
            or text:match("copy%s+profile%s+(.+)$")
            or text:match("duplicate%s+current%s+profile%s+to%s+(.+)$")
            or text:match("duplicate%s+current%s+profile%s+as%s+(.+)$")
            or text:match("clone%s+current%s+profile%s+to%s+(.+)$")
            or text:match("clone%s+current%s+profile%s+as%s+(.+)$")
            or text:match("clone%s+profile%s+(.+)$")
            or text:match("dupe%s+current%s+profile%s+to%s+(.+)$")
            or text:match("dupe%s+current%s+profile%s+as%s+(.+)$")
            or text:match("dupe%s+profile%s+(.+)$")
            or text:match("duplicate%s+profile%s+(.+)$")
            or text:match("duplicate%s+(.+)%s+profile$")
            or text:match("backup%s+current%s+profile%s+to%s+(.+)$")
            or text:match("backup%s+current%s+profile%s+as%s+(.+)$")
            or text:match("backup%s+profile%s+to%s+(.+)$")
        name = CleanProfileName(name)
        if name then
            local action = Registry and Registry:GetAction("copy_profile")
            return action and {
                kind = "action",
                action = action,
                args = { name = name },
                confirmRequired = true,
                label = "Copy current profile",
                summary = "Copies the active profile to a new profile name.",
            } or nil
        end

        local sourceOnly = RawAfterPrefix(rawText, {
                "copy from profile ",
                "copy existing profile ",
                "copy source profile ",
            })
            or text:match("^copy%s+from%s+profile%s+(.+)$")
            or text:match("^copy%s+existing%s+profile%s+(.+)$")
            or text:match("^copy%s+source%s+profile%s+(.+)$")
        sourceOnly = CleanProfileName(sourceOnly)
        if sourceOnly and not text:match("%s+to%s+") then
            local action = Registry and Registry:GetAction("start_profile_copy_flow")
            return action and {
                kind = "action",
                action = action,
                args = { source = sourceOnly },
                label = "Start profile copy flow",
                summary = "Asks for the missing destination profile name.",
            } or nil
        end
    end

    if hasExportIntent then
        local kind = ProfileExportKindForText(text)
        local action = Registry and Registry:GetAction("export_profile")
        return action and {
            kind = "action",
            action = action,
            args = { kind = kind },
            label = "Export current profile",
            summary = "Creates a copyable profile export string.",
        } or nil
    end

    if ContainsAny(text, {
        "list profiles", "show profiles", "profile list", "profile summary",
        "profile status", "current profile", "active profile", "which profile",
        "what profile", "what profile am i using", "which profile am i using",
        "profile am i using", "profile i am using",
        "spec profiles", "specialization profiles",
    }) and not ContainsAny(text, {
        "reset", "delete", "remove", "switch", "wechsel", "copy", "duplicate", "clone", "dupe",
        "create", "new profile", "import", "export", "backup",
    }) then
        local action = Registry and Registry:GetAction("profile_summary")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show profile summary",
            summary = "Shows current profile status and spec profile mappings.",
        } or nil
    end
    return nil
end

function P.ParseProfileRepairShortcut(text)
    if not ContainsAny(text, {
        "profile mapping", "profile mappings", "spec profile mapping", "spec profile mappings",
        "broken profile mapping", "broken profile mappings", "broken spec mapping", "broken spec mappings",
    }) then
        return nil
    end
    if not ContainsAny(text, { "clear", "fix", "repair", "remove", "clean" }) then return nil end
    local action = Registry and Registry:GetAction("clear_broken_spec_profile_mappings")
    return action and {
        kind = "action",
        action = action,
        args = {},
        label = "Clear broken spec profile mappings",
        summary = "Removes specialization profile assignments that point to missing profiles.",
    } or nil
end

P.COPY_SCOPE_DEFAULTS = COPY_SCOPE_DEFAULTS
P.UNIT_COPY_SCOPE_SPECS = UNIT_COPY_SCOPE_SPECS
P.GROUP_COPY_SCOPE_DEFAULTS = GROUP_COPY_SCOPE_DEFAULTS
P.GROUP_COPY_SCOPE_SPECS = GROUP_COPY_SCOPE_SPECS
P.CopyScopeDefaults = CopyScopeDefaults
P.CopyScopeMatches = CopyScopeMatches
P.ApplyCopyScopeMatches = ApplyCopyScopeMatches
P.WantsFullUnitCopy = WantsFullUnitCopy
P.CopyScopesForText = CopyScopesForText
P.GroupCopyScopeDefaults = GroupCopyScopeDefaults
P.WantsFullGroupCopy = WantsFullGroupCopy
P.GroupCopyScopesForText = GroupCopyScopesForText
P.CleanProfileName = CleanProfileName
P.RawAfterPrefix = RawAfterPrefix
P.RawBetween = RawBetween
P.RawCreateProfileName = RawCreateProfileName
P.RawCopyProfileName = RawCopyProfileName
P.RawRenameProfileNames = RawRenameProfileNames
P.PROFILE_EXPORT_KIND_LABELS = PROFILE_EXPORT_KIND_LABELS
P.ProfileExportKindForText = ProfileExportKindForText
P.RawAfterLastConnector = RawAfterLastConnector
P.CleanSpecName = CleanSpecName
P.ImportNewProfileName = ImportNewProfileName
P.BuildSpecAutoSwitch = BuildSpecAutoSwitch
P.BuildSpecProfileAction = BuildSpecProfileAction
P.ParseWorkflowLifecycle = ParseWorkflowLifecycle
P.BuildMenuSelectorState = BuildMenuSelectorState
P.ParseProfileStagingState = ParseProfileStagingState
P.ParseGroupCopyScopeState = ParseGroupCopyScopeState
P.ParseUnitCopyScopeState = ParseUnitCopyScopeState
P.ParseProfile = ParseProfile
