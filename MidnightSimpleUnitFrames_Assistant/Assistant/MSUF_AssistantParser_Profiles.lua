--- Shell/Menu2/Assistant/MSUF_AssistantParser_Profiles.lua
--- Profile command parser shard for Assistant plans.
---
--- Preserves user-authored profile names while staging profile actions; actual
--- import/export/copy writes remain in the profile/runtime layer.

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
local DetectUnits = P.DetectUnits
local DetectBoolean = P.DetectBoolean
local UnitPageKey = P.UnitPageKey
local Data = A.ParserData or {}
A.ParserData = Data
local ProfileData = Data.PROFILE_PARSER or {}

local COPY_SCOPE_DEFAULTS = ProfileData.COPY_SCOPE_DEFAULTS or {}
local UNIT_COPY_SCOPE_SPECS = ProfileData.UNIT_COPY_SCOPE_SPECS or {}
local GROUP_COPY_SCOPE_DEFAULTS = ProfileData.GROUP_COPY_SCOPE_DEFAULTS or {}
local GROUP_COPY_SCOPE_SPECS = ProfileData.GROUP_COPY_SCOPE_SPECS or {}

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

local COPY_SCOPE_NEGATIVE_PREFIXES = ProfileData.COPY_SCOPE_NEGATIVE_PREFIXES or {}

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

-- Blanks out one occurrence of a phrase so a later, broader spec cannot claim
-- the same words. Padded on both sides to match HasPhrase's word semantics.
local function RemovePhrase(text, phrase)
    phrase = tostring(phrase or "")
    if phrase == "" then return text end
    local padded = " " .. tostring(text or "") .. " "
    local needle = " " .. phrase .. " "
    local at = padded:find(needle, 1, true)
    if not at then return text end
    padded = padded:sub(1, at) .. padded:sub(at + #needle)
    return (padded:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function CopyScopeMatches(text, specs, negativeKeys)
    local matches = {}
    local seen = {}
    -- Specs are ordered most specific first, and a matched alias consumes the
    -- words it claimed. Without that, "copy target aura style to focus" matches
    -- Aura Style AND the broader Aura Options wording inside the same three
    -- words, so RC9's split collapses and a style copy overwrites content too.
    local remaining = tostring(text or "")
    for i = 1, #(specs or {}) do
        local spec = specs[i]
        if spec.key and not seen[spec.key] and not (negativeKeys and negativeKeys[spec.key]) then
            for j = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[j]
                if HasPhrase(remaining, alias) then
                    matches[#matches + 1] = spec.key
                    seen[spec.key] = true
                    remaining = RemovePhrase(remaining, alias)
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
    if ContainsAny(text, ProfileData.FULL_COPY_TERMS) or ContainsAny(text, ProfileData.FULL_UNIT_COPY_TERMS) then
        return true
    end
    if ContainsAny(text, ProfileData.UNIT_PROFILE_COPY_TERMS) then
        if not matches then
            matches = CopyScopeMatches(text, UNIT_COPY_SCOPE_SPECS, CopyScopeNegativeKeySet(text, UNIT_COPY_SCOPE_SPECS))
        end
        return #matches == 0
    end
    return false
end

local function WantsFullGroupCopy(text, matches)
    if ContainsAny(text, ProfileData.FULL_COPY_TERMS) or ContainsAny(text, ProfileData.FULL_GROUP_COPY_TERMS) then
        return true
    end
    if ContainsAny(text, ProfileData.GROUP_PROFILE_COPY_TERMS) then
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
        if matched and ContainsAny(text, ProfileData.COPY_SCOPE_SIZE_TERMS) then scopes.basics = true end
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
    return RawAfterPrefix(raw, {
            "create profile ", "new profile ",
            "create new profile ", "make profile ", "make new profile ",
            "erstelle profil ", "erstelle neues profil ", "neues profil ",
            "profil erstellen ", "profil anlegen ",
        })
        or RawBetween(raw, "create ", " profile")
        or RawBetween(raw, "new ", " profile")
        or RawBetween(raw, "erstelle ", " profil")
        or RawBetween(raw, "lege ", " profil an")
end

local function RawCopyProfileName(raw)
    return RawAfterPrefix(raw, {
            "copy current profile to ", "copy profile to ", "copy profile ", "duplicate profile ",
            "kopiere aktuelles profil nach ", "kopiere aktuelles profil zu ", "kopiere aktuelles profil als ",
            "kopiere profil nach ", "kopiere profil zu ", "kopiere profil als ", "kopiere profil ",
            "dupliziere aktuelles profil nach ", "dupliziere aktuelles profil als ",
            "dupliziere profil nach ", "dupliziere profil als ", "dupliziere profil ",
            "sichere aktuelles profil als ", "sichere profil als ",
        })
        or RawBetween(raw, "duplicate ", " profile")
        or RawBetween(raw, "dupliziere ", " profil")
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
    local connectors = {
        "%s+to%s+", "%s+as%s+", "%s+called%s+", "%s+named%s+",
        "%s+nach%s+", "%s+zu%s+", "%s+als%s+", "%s+genannt%s+", "%s+namens%s+",
    }
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
        "kopiere ",
        "kopiere profil ",
        "kopiere aktuelles profil ",
        "kopiere aktives profil ",
        "kopiere mein profil ",
        "dupliziere ",
        "dupliziere profil ",
        "dupliziere aktuelles profil ",
        "dupliziere aktives profil ",
        "sichere profil ",
        "sichere aktuelles profil ",
        "backup profil ",
        "backup aktuelles profil ",
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
        "kopiere aktuelles profil nach ",
        "kopiere aktuelles profil zu ",
        "kopiere aktuelles profil als ",
        "kopiere aktives profil nach ",
        "kopiere aktives profil zu ",
        "kopiere aktives profil als ",
        "kopiere mein profil nach ",
        "kopiere mein profil zu ",
        "kopiere mein profil als ",
        "dupliziere aktuelles profil nach ",
        "dupliziere aktuelles profil als ",
        "dupliziere aktives profil nach ",
        "dupliziere aktives profil als ",
        "sichere aktuelles profil als ",
        "backup aktuelles profil als ",
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
        "erstelle profil aus aktuellem profil namens ",
        "erstelle profil aus aktuellem profil als ",
        "erstelle neues profil aus aktuellem profil namens ",
        "erstelle neues profil aus aktuellem profil als ",
        "neues profil aus aktuellem profil namens ",
        "neues profil aus aktuellem profil als ",
    })
end

local function IsCurrentProfileName(name)
    name = Normalize(name)
    return name == "current" or name == "active" or name == "this"
        or name == "current profile" or name == "active profile" or name == "this profile"
        or name == "aktuell" or name == "aktuelle" or name == "aktuelles" or name == "aktives" or name == "dieses"
        or name == "aktuelles profil" or name == "aktives profil" or name == "dieses profil"
        or name == "mein profil" or name == "mein aktuelles profil" or name == "mein aktives profil"
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

local PROFILE_EXPORT_KIND_LABELS = ProfileData.PROFILE_EXPORT_KIND_LABELS or {}

local function ProfileExportKindForText(text)
    if ContainsAny(text, ProfileData.PROFILE_EXPORT_COLOR_TERMS) then return "colors" end
    if ContainsAny(text, ProfileData.PROFILE_EXPORT_CASTBAR_TERMS) then return "castbar" end
    if ContainsAny(text, ProfileData.PROFILE_EXPORT_GAMEPLAY_TERMS) then return "gameplay" end
    if ContainsAny(text, ProfileData.PROFILE_EXPORT_GROUPFRAME_TERMS) then return "groupframe" end
    if ContainsAny(text, ProfileData.PROFILE_EXPORT_UNITFRAME_TERMS) then return "unitframe" end
    return "all"
end

local function HasProfileExportIntent(text)
    if ContainsAny(text, ProfileData.PROFILE_RESTORE_ACTION_TERMS)
        and ContainsAny(text, ProfileData.PROFILE_BACKUP_TERMS)
    then
        return false
    end
    if ContainsAny(text, ProfileData.PROFILE_STRING_TERMS)
        and ContainsAny(text, ProfileData.PROFILE_EXPORT_ACTION_TERMS)
        and not ContainsAny(text, ProfileData.PROFILE_EXPORT_REJECT_TERMS)
    then
        return true
    end
    if ContainsAny(text, ProfileData.PROFILE_READONLY_QUERY_TERMS) then
        return false
    end
    if ContainsAny(text, ProfileData.PROFILE_EXPORT_TERMS) then
        return true
    end
    if ContainsAny(text, ProfileData.PROFILE_SIMPLE_BACKUP_TERMS)
        and not ContainsAny(text, ProfileData.PROFILE_NAME_CONNECTOR_TERMS)
    then
        return true
    end
    return false
end

local function HasProfileReadOnlyQueryIntent(text)
    return ContainsAny(text, ProfileData.PROFILE_READONLY_QUERY_TERMS)
end

local function IsBackupBeforeProfileImportIntent(text)
    return ContainsAny(text, ProfileData.BACKUP_BEFORE_IMPORT_TERMS)
end

local function IsSafeProfileImportIntent(text)
    return ContainsAny(text, ProfileData.SAFE_PROFILE_IMPORT_TERMS) or IsBackupBeforeProfileImportIntent(text)
end

local function BuildProfileBackupRestoreClarification(text)
    if not ContainsAny(text, ProfileData.PROFILE_BACKUP_RESTORE_TERMS) then
        return nil
    end
    return {
        kind = "answer",
        status = "info",
        text = "Which backup profile do you want me to restore? MSUF backups are either copied profile names or export strings. Give me the full profile name, for example 'switch profile Raid Backup', or paste an MSUF profile string to import.",
        summary = "Asks which backup profile to restore.",
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
    name = name:gsub("^spezialisierung%s+", "")
    name = name:gsub("^spezialisations%s+", "")
    name = name:gsub("%s+spec$", "")
    name = name:gsub("%s+specialization$", "")
    name = name:gsub("%s+spezialisierung$", "")
    name = name:gsub("^for%s+", "")
    name = name:gsub("^to%s+", "")
    name = name:gsub("^fuer%s+", "")
    name = name:gsub("^zu%s+", "")
    name = name:gsub("^auf%s+", "")
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
        local beforeName = RawAfterLastConnector(before, {
            " as ", " to new profile ", " new profile ", " named ", " called ",
            " als ", " als neues profil ", " in neues profil ", " neues profil ", " genannt ", " namens ",
        })
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
    if lower:sub(1, 17) == "als neues profil " then return CleanImportNewProfileName(StripProfileImportString(after:sub(18))) end
    if lower:sub(1, 11) == "als profil " then return CleanImportNewProfileName(StripProfileImportString(after:sub(12))) end
    if lower:sub(1, 4) == "als " then return CleanImportNewProfileName(StripProfileImportString(after:sub(5))) end
    if lower:sub(1, 16) == "in neues profil " then return CleanImportNewProfileName(StripProfileImportString(after:sub(17))) end
    if lower:sub(1, 13) == "neues profil " then return CleanImportNewProfileName(StripProfileImportString(after:sub(14))) end
    if startIndex then return nil end
    local name = StripProfileImportString(text:match("as%s+(.+)$")
        or text:match("to%s+new%s+profile%s+(.+)$")
        or text:match("new%s+profile%s+(.+)$")
        or text:match("als%s+(.+)$")
        or text:match("in%s+neues%s+profil%s+(.+)$")
        or text:match("neues%s+profil%s+(.+)$"))
    return CleanImportNewProfileName(name)
end

local function BuildMissingImportNewProfileNameAnswer(text)
    if not ContainsAny(text, ProfileData.IMPORT_NEW_PROFILE_PROMPT_TERMS) then return nil end
    return {
        kind = "answer",
        status = "info",
        text = "What should the new profile be called for this import? Example: import this as new profile Raid Import MSUF5:...",
        summary = "Clarifies safe new-profile import wording without treating safety words as a profile name.",
    }
end

local function BuildSpecAutoSwitch(text)
    if not ContainsAny(text, ProfileData.SPEC_AUTO_SWITCH_TERMS) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    local setting = Registry and Registry:GetSetting("profiles.specAutoSwitch")
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = (value and "Enable" or "Disable") .. " spec profile switching",
        summary = "Changes the MSUF Profiles spec auto-switch option.",
    } or nil
end

local function BuildSpecProfileAction(text)
    if not (ContainsAny(text, ProfileData.SPEC_PROFILE_TERMS)
        or ((HasPhrase(text, "profile") or HasPhrase(text, "profil"))
            and (HasPhrase(text, "spec") or HasPhrase(text, "specialization") or HasPhrase(text, "spezialisierung"))))
    then
        return nil
    end
    if ContainsAny(text, ProfileData.SPEC_PROFILE_CLEAR_TERMS) then
        local spec = text:match("clear%s+spec%s+profile%s+(.+)$")
            or text:match("clear%s+(.+)%s+spec%s+profile$")
            or text:match("remove%s+spec%s+profile%s+(.+)$")
            or text:match("unset%s+spec%s+profile%s+(.+)$")
            or text:match("remove%s+profile%s+from%s+(.+)%s+spec$")
            or text:match("loesche%s+spec%s+profil%s+(.+)$")
            or text:match("entferne%s+spec%s+profil%s+(.+)$")
            or text:match("entferne%s+profil%s+von%s+(.+)%s+spec$")
            or text:match("hebe%s+profil%s+fuer%s+(.+)%s+auf$")
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
    if ContainsAny(text, ProfileData.SPEC_PROFILE_ASSIGN_TERMS) then
        local spec, name = text:match("set%s+spec%s+profile%s+(.+)%s+to%s+(.+)$")
        if not spec then spec, name = text:match("set%s+(.+)%s+spec%s+profile%s+to%s+(.+)$") end
        if not spec then name, spec = text:match("assign%s+(.+)%s+profile%s+to%s+(.+)%s+spec$") end
        if not spec then name, spec = text:match("assign%s+profile%s+(.+)%s+to%s+spec%s+(.+)$") end
        if not spec then name, spec = text:match("assign%s+(.+)%s+to%s+(.+)%s+spec%s+profile$") end
        if not spec then spec, name = text:match("setze%s+spec%s+profil%s+(.+)%s+auf%s+(.+)$") end
        if not spec then spec, name = text:match("setze%s+profil%s+fuer%s+(.+)%s+auf%s+(.+)$") end
        if not spec then name, spec = text:match("setze%s+profil%s+(.+)%s+fuer%s+spec%s+(.+)$") end
        if not spec then name, spec = text:match("setze%s+profil%s+(.+)%s+fuer%s+spezialisierung%s+(.+)$") end
        if not spec then name, spec = text:match("setze%s+profil%s+(.+)%s+fuer%s+(.+)%s+spec$") end
        if not spec then name, spec = text:match("weise%s+profil%s+(.+)%s+(.+)%s+spec%s+zu$") end
        if not spec then name, spec = text:match("weise%s+profil%s+(.+)%s+spec%s+(.+)%s+zu$") end
        if not spec then name, spec = text:match("weise%s+profil%s+(.+)%s+spezialisierung%s+(.+)%s+zu$") end
        if not spec then name, spec = text:match("weise%s+(.+)%s+profil%s+zu%s+(.+)%s+spec$") end
        if not spec then name, spec = text:match("nutze%s+profil%s+(.+)%s+fuer%s+(.+)%s+spec$") end
        if not spec then name, spec = text:match("nutze%s+profil%s+(.+)%s+fuer%s+spec%s+(.+)$") end
        if not spec then name, spec = text:match("verwende%s+profil%s+(.+)%s+fuer%s+(.+)%s+spec$") end
        if not spec then name, spec = text:match("verwende%s+profil%s+(.+)%s+fuer%s+spec%s+(.+)$") end
        spec = CleanSpecName(spec)
        name = CleanProfileName(name)
        local action = Registry and Registry:GetAction("set_spec_profile")
        return spec and name and action and {
            kind = "action",
            action = action,
            args = { spec = spec, name = name },
            label = "Set spec profile",
            summary = "Assigns a saved profile to a specialization.",
        } or nil
    end
    return nil
end


local function ParseWorkflowLifecycle(text)
    if ContainsAny(text, ProfileData.WORKFLOW_STATUS_TERMS) then
        local action = Registry and Registry:GetAction("assistant.workflow.status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show Assistant current step",
            summary = "Shows current confirmations, open panels, guided steps, and Edit Mode status.",
        } or nil
    end
    if text == "back" or ContainsAny(text, ProfileData.WORKFLOW_BACK_TERMS) then
        local action = Registry and Registry:GetAction("dashboard_page_back")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Open previous Dashboard page",
            summary = "Goes back through the Assistant page history, then the MSUF menu history.",
        } or nil
    end
    if text == "forward" or text == "forwards" or text == "vorwaerts" or ContainsAny(text, ProfileData.WORKFLOW_FORWARD_TERMS) then
        local action = Registry and Registry:GetAction("dashboard_page_forward")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Open next Dashboard page",
            summary = "Goes forward through the MSUF menu history.",
        } or nil
    end
    if text == "cancel" or ContainsAny(text, ProfileData.WORKFLOW_CANCEL_TERMS) then
        local action = Registry and Registry:GetAction("assistant.workflow.cancel")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Cancel current Assistant step",
            summary = "Cancels the active Assistant confirmation, flow, panel, or guide when one is open.",
        } or nil
    end
    if ContainsAny(text, ProfileData.PROFILE_PANEL_CLOSE_TERMS) then
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
        label = label or "Choose profile menu option",
        summary = summary or "Selects or prepares a profile menu choice.",
    } or nil
end

local function ParseProfileStagingState(text, raw)
    if not ContainsAny(text, ProfileData.PROFILE_WORD_TERMS) then return nil end
    local hasStagingIntent = ContainsAny(text, ProfileData.PROFILE_STAGING_INTENT_TERMS)
    if not hasStagingIntent then return nil end

    if ContainsAny(text, ProfileData.PROFILE_EXPORT_KIND_SELECTOR_TERMS) then
        return BuildMenuSelectorState({
            selector = "profile_staging",
            field = "profileExportKind",
            kind = ProfileExportKindForText(text),
        }, "Select profile export kind", "Selects the Profiles export-kind dropdown without immediately exporting.")
    end

    if ContainsAny(text, ProfileData.PROFILE_IMPORT_CREATE_NEW_TERMS) then
        local value = DetectBoolean(text)
        if value == nil then value = not ContainsAny(text, ProfileData.PROFILE_IMPORT_CURRENT_PROFILE_TERMS) end
        return BuildMenuSelectorState({
            selector = "profile_staging",
            field = "profileImportCreateNew",
            value = value,
        }, "Set profile import mode", "Sets the Profiles import-and-create-new-profile toggle.")
    end

    if ContainsAny(text, ProfileData.PROFILE_IMPORT_NEW_NAME_TERMS)
        and ContainsAny(text, ProfileData.PROFILE_IMPORT_NAME_CONTEXT_TERMS)
    then
        local value = CleanProfileName(RawAfterLastConnector(raw, ProfileData.PROFILE_NAME_VALUE_CONNECTORS))
        if value then
            return BuildMenuSelectorState({
                selector = "profile_staging",
                field = "profileImportNewName",
                value = value,
            }, "Set profile import new-profile name", "Stages the Profiles new-profile import name field.")
        end
    end

    if ContainsAny(text, ProfileData.PROFILE_IMPORT_STRING_TERMS)
        and ContainsAny(text, ProfileData.PROFILE_IMPORT_STRING_FIELD_TERMS)
    then
        local value = RawAfterLastConnector(raw, ProfileData.PROFILE_IMPORT_STRING_CONNECTORS)
        if value then
            return BuildMenuSelectorState({
                selector = "profile_staging",
                field = "profileString",
                value = value,
            }, "Prepare profile import text", "Prepares the profile import text without importing yet.")
        end
    end

    if ContainsAny(text, ProfileData.PROFILE_CREATE_COPY_NAME_TERMS) then
        local value = CleanProfileName(RawAfterLastConnector(raw, ProfileData.PROFILE_NAME_VALUE_CONNECTORS))
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
    if not ContainsAny(text, ProfileData.GROUP_COPY_SCOPE_SELECTOR_TERMS) then return nil end
    if not ContainsAny(text, ProfileData.COPY_SCOPE_KIND_TERMS) then return nil end

    if ContainsAny(text, ProfileData.COPY_SCOPE_ALL_TERMS)
        or (ContainsAny(text, ProfileData.COPY_SCOPE_ALL_CONTEXT_TERMS) and ContainsAny(text, ProfileData.COPY_SCOPE_ENABLE_TERMS))
    then
        return BuildMenuSelectorState({
            selector = "group_copy_scope",
            command = "all",
        }, "Select all group copy categories", "Sets every Group Frames copy-popup category checkbox on.")
    end
    if ContainsAny(text, ProfileData.COPY_SCOPE_NONE_TERMS)
        or (ContainsAny(text, ProfileData.COPY_SCOPE_CLEAR_TERMS) and ContainsAny(text, ProfileData.COPY_SCOPE_KIND_TERMS))
    then
        return BuildMenuSelectorState({
            selector = "group_copy_scope",
            command = "none",
        }, "Clear group copy categories", "Sets every Group Frames copy-popup category checkbox off.")
    end

    local matches = CopyScopeMatches(text, GROUP_COPY_SCOPE_SPECS)
    if #matches == 0 then return nil end
    if ContainsAny(text, ProfileData.COPY_SCOPE_ONLY_TERMS) then
        return BuildMenuSelectorState({
            selector = "group_copy_scope",
            command = "only",
            categories = matches,
        }, "Select only group copy categories", "Sets the Group Frames copy-popup categories to exactly the requested category set.")
    end

    local value = DetectBoolean(text)
    if value == nil then
        if ContainsAny(text, ProfileData.COPY_SCOPE_FALSE_TERMS) then value = false else value = true end
    end
    return BuildMenuSelectorState({
        selector = "group_copy_scope",
        category = matches[1],
        value = value,
    }, "Set group copy category", "Sets one Group Frames copy-popup category checkbox.")
end

local function ParseUnitCopyScopeState(text)
    if ContainsAny(text, ProfileData.GROUP_COPY_SCOPE_REJECT_TERMS) then return nil end
    if not ContainsAny(text, ProfileData.COPY_SCOPE_KIND_TERMS) then return nil end
    -- "category"/"categories" only ever names this popup's checkboxes, but
    -- "scope" is an ordinary word: "reset target aura scope" ticked the Unit
    -- Copy popup's Auras box for Target. A scope-only sentence must therefore
    -- also be about copying, or name the popup outright -- the group variant
    -- above has always required its selector terms for the same reason.
    if not ContainsAny(text, { "category", "categories" })
        and not ContainsAny(text, ProfileData.UNIT_COPY_SCOPE_SELECTOR_TERMS)
        and not ContainsAny(text, ProfileData.COPY_SCOPE_INTENT_TERMS)
    then
        return nil
    end
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
    local explicit = ContainsAny(text, ProfileData.UNIT_COPY_SCOPE_SELECTOR_TERMS)
    if not explicit and #units == 0 and not pageUnit then return nil end
    if ContainsAny(text, ProfileData.COPY_SCOPE_ALL_TERMS)
        or (ContainsAny(text, ProfileData.COPY_SCOPE_ALL_CONTEXT_TERMS) and ContainsAny(text, ProfileData.COPY_SCOPE_ENABLE_TERMS))
    then
        return BuildMenuSelectorState({
            selector = "unit_copy_scope",
            unit = units[1] or pageUnit,
            command = "all",
        }, "Select all unit copy categories", "Sets every Unit Copy popup category checkbox on.")
    end
    if ContainsAny(text, ProfileData.COPY_SCOPE_NONE_TERMS)
        or (ContainsAny(text, ProfileData.COPY_SCOPE_CLEAR_TERMS) and ContainsAny(text, ProfileData.COPY_SCOPE_KIND_TERMS))
    then
        return BuildMenuSelectorState({
            selector = "unit_copy_scope",
            unit = units[1] or pageUnit,
            command = "none",
        }, "Clear unit copy categories", "Sets every Unit Copy popup category checkbox off.")
    end

    local matches = CopyScopeMatches(text, UNIT_COPY_SCOPE_SPECS)
    if #matches == 0 then return nil end
    if ContainsAny(text, ProfileData.COPY_SCOPE_ONLY_TERMS) then
        return BuildMenuSelectorState({
            selector = "unit_copy_scope",
            unit = units[1] or pageUnit,
            command = "only",
            categories = matches,
        }, "Select only unit copy categories", "Sets the Unit Copy popup categories to exactly the requested category set.")
    end

    local value = DetectBoolean(text)
    if value == nil then
        if ContainsAny(text, ProfileData.COPY_SCOPE_FALSE_TERMS) then value = false else value = true end
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
    local hasProfileWord = ContainsAny(text, ProfileData.PROFILE_WORD_TERMS)
    local hasExportIntent = HasProfileExportIntent(text)
    local safeImportIntent = IsSafeProfileImportIntent(text)
    local hasProfile = hasProfileWord or hasExportIntent or safeImportIntent
    local rawLower = tostring(raw or ""):lower()
    local implicitSwitchName
    if not hasProfile and ContainsAny(text, ProfileData.PROFILE_SWITCH_SHORT_TERMS) then
        local maybeName = CleanProfileName(RawAfterPrefix(rawText, ProfileData.PROFILE_SWITCH_SHORT_PREFIXES)
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
    if compact and (hasProfileWord or ContainsAny(text, ProfileData.PROFILE_IMPORT_ACTION_TERMS) or rawLower:find("^msuf%d+:")) then
        local legacy = ContainsAny(text, ProfileData.PROFILE_LEGACY_IMPORT_TERMS)
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
    if not hasProfile then return nil end

    if ContainsAny(text, ProfileData.PROFILE_MAPPING_TERMS) and ContainsAny(text, ProfileData.PROFILE_MAPPING_CLEAN_TERMS) then
        local action = Registry and Registry:GetAction("clear_broken_spec_profile_mappings")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Clear broken spec profile links",
            summary = "Removes specialization profile links that point to profiles that no longer exist.",
        } or nil
    end

    local specSwitch = BuildSpecAutoSwitch(text)
    if specSwitch then return specSwitch end

    local specProfile = BuildSpecProfileAction(text)
    if specProfile then return specProfile end

    if ContainsAny(text, ProfileData.WAGO_PROFILE_TERMS) then
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

    if ContainsAny(text, ProfileData.PROFILE_IMPORT_ACTION_TERMS) and not HasProfileReadOnlyQueryIntent(text) then
        local action = Registry and Registry:GetAction("open_profile_import")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Open profile import",
            summary = "Opens the Profiles import UI.",
        } or nil
    end

    if ContainsAny(text, ProfileData.PROFILE_RESET_TERMS)
        and not ContainsAny(text, ProfileData.PROFILE_COPY_TERMS)
        and not HasProfileReadOnlyQueryIntent(text)
    then
        local name = RawAfterPrefix(rawText, ProfileData.PROFILE_RESET_PREFIXES)
            or text:match("reset%s+current%s+profile%s*(.*)$")
            or text:match("reset%s+active%s+profile%s*(.*)$")
            or text:match("reset%s+profile%s*(.*)$")
            or text:match("aktuelles%s+profil%s+zuruecksetzen%s*(.*)$")
            or text:match("aktives%s+profil%s+zuruecksetzen%s*(.*)$")
            or text:match("profil%s+zuruecksetzen%s*(.*)$")
            or text:match("profil%s+(.+)%s+zuruecksetzen$")
            or text:match("profil%s+(.+)%s+zurucksetzen$")
            or text:match("(.+)%s+profil%s+zuruecksetzen$")
            or text:match("(.+)%s+profil%s+zurucksetzen$")
        name = CleanProfileName(name)
        if not name or IsCurrentProfileName(name) then
            local action = Registry and Registry:GetAction("reset_profile")
            return action and {
                kind = "action",
                action = action,
                args = {},
                confirmRequired = true,
                label = "Reset active profile",
                summary = "Resets the active MSUF profile.",
            } or nil
        end
        return {
            kind = "answer",
            status = "info",
        text = "I can reset the active profile with confirmation. To reset another profile, switch to it first or use the Profiles page so the target profile is visible.",
            summary = "Keeps profile reset limited to the active profile.",
        }
    end

    if ContainsAny(text, ProfileData.PROFILE_DELETE_TERMS) then
        local name = RawAfterPrefix(rawText, ProfileData.PROFILE_DELETE_PREFIXES)
            or text:match("delete%s+profile%s+(.+)$")
            or text:match("delete%s+the%s+profile%s+(.+)$")
            or text:match("delete%s+(.+)%s+profile$")
            or text:match("remove%s+profile%s+(.+)$")
            or text:match("remove%s+the%s+profile%s+(.+)$")
            or text:match("remove%s+(.+)%s+profile$")
            or text:match("loesche%s+profil%s+(.+)$")
            or text:match("profil%s+(.+)%s+loeschen$")
            or text:match("entferne%s+profil%s+(.+)$")
            or text:match("profil%s+(.+)%s+entfernen$")
        name = CleanProfileName(name)
        if name then
            local action = Registry and Registry:GetAction("delete_profile")
            return action and {
                kind = "action",
                action = action,
                args = { name = name },
                confirmRequired = true,
                label = "Delete profile " .. tostring(name),
                summary = "Deletes the selected MSUF profile.",
            } or nil
        end
    end

    if implicitSwitchName or ContainsAny(text, ProfileData.PROFILE_SWITCH_TERMS) then
        local name = implicitSwitchName or RawAfterPrefix(rawText, ProfileData.PROFILE_SWITCH_PREFIXES)
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
            or text:match("wechsle%s+zu%s+(.+)$")
            or text:match("nutze%s+profil%s+(.+)$")
            or text:match("verwende%s+profil%s+(.+)$")
            or text:match("aktiviere%s+profil%s+(.+)$")
            or text:match("lade%s+profil%s+(.+)$")
            or text:match("waehle%s+profil%s+(.+)$")
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

    if ContainsAny(text, ProfileData.PROFILE_CREATE_TERMS) then
        local name = RawCreateProfileName(rawText)
            or text:match("create%s+profile%s+(.+)$")
            or text:match("create%s+(.+)%s+profile$")
            or text:match("new%s+profile%s+(.+)$")
            or text:match("new%s+(.+)%s+profile$")
            or text:match("erstelle%s+profil%s+(.+)$")
            or text:match("erstelle%s+neues%s+profil%s+(.+)$")
            or text:match("neues%s+profil%s+(.+)$")
            or text:match("profil%s+(.+)%s+erstellen$")
            or text:match("lege%s+profil%s+(.+)%s+an$")
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

    if ContainsAny(text, ProfileData.PROFILE_RENAME_TERMS) then
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
                summary = "Renames a profile when profile rename support is ready.",
            } or nil
        end
        if source then
            local action = Registry and Registry:GetAction("start_profile_rename_flow")
            return action and {
                kind = "action",
                action = action,
                args = { source = source },
                label = "Start profile rename flow",
                summary = "Asks which destination profile name to use.",
            } or nil
        end
    end

    if ContainsAny(text, ProfileData.PROFILE_COPY_TERMS) then
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
        if not source then source, dest = text:match("kopiere%s+profil%s+(.+)%s+nach%s+(.+)$") end
        if not source then source, dest = text:match("kopiere%s+profil%s+(.+)%s+als%s+(.+)$") end
        if not source then source, dest = text:match("dupliziere%s+profil%s+(.+)%s+nach%s+(.+)$") end
        if not source then source, dest = text:match("dupliziere%s+profil%s+(.+)%s+als%s+(.+)$") end
        if not source then source, dest = text:match("sichere%s+profil%s+(.+)%s+als%s+(.+)$") end
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
            or text:match("kopiere%s+aktuelles%s+profil%s+nach%s+(.+)$")
            or text:match("kopiere%s+aktuelles%s+profil%s+als%s+(.+)$")
            or text:match("kopiere%s+profil%s+nach%s+(.+)$")
            or text:match("dupliziere%s+aktuelles%s+profil%s+nach%s+(.+)$")
            or text:match("dupliziere%s+aktuelles%s+profil%s+als%s+(.+)$")
            or text:match("sichere%s+aktuelles%s+profil%s+als%s+(.+)$")
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

        local sourceOnly = RawAfterPrefix(rawText, ProfileData.PROFILE_COPY_SOURCE_PREFIXES)
            or text:match("^copy%s+from%s+profile%s+(.+)$")
            or text:match("^copy%s+existing%s+profile%s+(.+)$")
            or text:match("^copy%s+source%s+profile%s+(.+)$")
            or text:match("^kopiere%s+von%s+profil%s+(.+)$")
            or text:match("^kopiere%s+vorhandenes%s+profil%s+(.+)$")
            or text:match("^kopiere%s+quellprofil%s+(.+)$")
        sourceOnly = CleanProfileName(sourceOnly)
        if sourceOnly and not text:match("%s+to%s+") then
            local action = Registry and Registry:GetAction("start_profile_copy_flow")
            return action and {
                kind = "action",
                action = action,
                args = { source = sourceOnly },
                label = "Start profile copy flow",
                summary = "Asks which destination profile name to use.",
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

    if ContainsAny(text, ProfileData.PROFILE_SUMMARY_TERMS) and not ContainsAny(text, ProfileData.PROFILE_SUMMARY_REJECT_TERMS) then
        local action = Registry and Registry:GetAction("profile_summary")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show profile summary",
            summary = "Shows the current profile and specialization profile links.",
        } or nil
    end
    return nil
end

function P.ParseProfileRepairShortcut(text)
    if not ContainsAny(text, ProfileData.PROFILE_MAPPING_TERMS) then
        return nil
    end
    if not ContainsAny(text, ProfileData.PROFILE_MAPPING_CLEAN_TERMS) then return nil end
    local action = Registry and Registry:GetAction("clear_broken_spec_profile_mappings")
    return action and {
        kind = "action",
        action = action,
        args = {},
        label = "Clear broken spec profile links",
        summary = "Removes specialization profile links that point to profiles that no longer exist.",
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
