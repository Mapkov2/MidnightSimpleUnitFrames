-- build_corpus.lua -- builds one anonymized SavedVariables fixture of the
-- old-profile regression corpus (tools/fixtures/profiles/README.md).
--
--   lua tools/fixtures/profiles/build_corpus.lua <repo root> <entry id> <MidnightSimpleUnitFrames.lua>
--
-- Reads a real MSUF SavedVariables file (read-only; copy it out of the WTF
-- folder first), renames every character, realm and profile name to a stable
-- placeholder, keeps the profiles the entry selects and writes
-- tools/fixtures/profiles/sv/<entry id>.lua. The real-to-placeholder mapping is
-- printed to stdout for the operator and is never written to the repository.
--
-- The rewrite keeps structure, types, numbers and setting values. Only names
-- change: character keys ("Name-Realm") wherever they appear as a key or as a
-- whole value, profile names in the places the profile store keeps them, and
-- character or realm names inside free text. Placeholders are numbered in the
-- byte order of the original names, so a rebuild from the same file is
-- identical.
--
-- Plain Lua 5.1. Development tool only; the gate never runs it.

local root, entryId, sourcePath = arg[1], arg[2], arg[3]
assert(root and entryId and sourcePath, "usage: build_corpus.lua <repo root> <entry id> <SavedVariables file>")
root = root:gsub("\\", "/"):gsub("/$", "")

-- What each entry keeps. Profile names are the placeholders this script
-- assigns (run it once with keep = "all" to see them). maxChars bounds the
-- per-character records; the login character and every character bound to a
-- kept profile stay first.
local ENTRIES = {
    sv_retail_rev16_17 = { keep = { "Profile01", "Profile15" }, maxChars = 8 },
    sv_ptr_rev13 = { keep = { "Default" }, maxChars = 9 },
    sv_ptr_rev6 = { keep = { "Profile01" }, maxChars = 2 },
    sv_xptr_rev15 = { keep = { "Profile01" }, maxChars = 1 },
    sv_pre6_feb = { keep = "all", maxChars = 2 },
    sv_pre6_mar = { keep = "all", maxChars = 8 },
    sv_forever_beta_rev17 = { keep = { "Profile01" }, maxChars = 1 },
    sv_mists_rev15 = { keep = "all", maxChars = 1 },
    sv_era_rev15 = { keep = { "Profile01" }, maxChars = 3 },
    sv_tbcptr_rev14 = { keep = "all", maxChars = 2 },
    sv_anniversary_rev17 = { keep = { "Profile01" }, maxChars = 2 },
}
local entry = assert(ENTRIES[entryId], "unknown entry id " .. tostring(entryId))

-- Profile names the product itself creates; they carry no personal data.
local KEPT_PROFILE_NAMES = { "^Default$", "^None$", "^Modern Dark$", "^Modern Dark %d+$",
    "^MSUF Suite Forever$", "^MSUF Suite Forever %d+$" }
-- GlobalDB tables keyed by character key, then by profile name.
local CHARACTER_PROFILE_CACHES = { "classPowerLayoutCache", "detachedPowerBarLayoutCache", "unitFrameScreenCache" }

local function Load(path)
    local env = {}
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk()
    return env
end

local function SortedKeys(t)
    local keys = {}
    for key in pairs(t) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    return keys
end

local function DeepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not DeepEqual(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local sv = Load(sourcePath)
local globalDB = assert(sv.MSUF_GlobalDB, "no MSUF_GlobalDB in " .. sourcePath)

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
local characterKeys, names, realms, profileNames = {}, {}, {}, {}
local function NoteCharacterKey(key)
    local name, realm = tostring(key):match("^(.-)%-(.+)$")
    if name and name ~= "" then
        characterKeys[key] = true
        names[name] = true
        realms[realm] = true
    end
end
local guids = {}
local function CollectNames()
    for key in pairs(globalDB.char or {}) do NoteCharacterKey(key) end
    for _, cacheKey in ipairs(CHARACTER_PROFILE_CACHES) do
        for key, perProfile in pairs(globalDB[cacheKey] or {}) do
            NoteCharacterKey(key)
            if type(perProfile) == "table" then
                for profileName in pairs(perProfile) do profileNames[profileName] = true end
            end
        end
    end
    for name in pairs(globalDB.profiles or {}) do profileNames[name] = true end
    for name in pairs(globalDB.ignoredPre6Profiles or {}) do profileNames[name] = true end
    for _, binding in pairs(globalDB.char or {}) do
        if type(binding) == "table" then
            if type(binding.activeProfile) == "string" then profileNames[binding.activeProfile] = true end
            for _, mapped in pairs(type(binding.specProfileMap) == "table" and binding.specProfileMap or {}) do
                if type(mapped) == "string" then profileNames[mapped] = true end
            end
        end
    end
    local meta = type(globalDB.global) == "table" and globalDB.global or {}
    if type(meta.defaultProfileForNewChars) == "string" then profileNames[meta.defaultProfileForNewChars] = true end
    -- Other players appear as "Name-Realm" values (Priority Frames pins); any
    -- whole value that ends in a realm of this account counts as a character, and
    -- player GUIDs are renumbered.
    local function CollectStrings(value, seen)
        if type(value) == "string" then
            local name, realm = value:match("^([^%s%-]+)%-(.+)$")
            if name and realms[realm] then NoteCharacterKey(value) end
            if value:match("^Player%-%d+%-%x+$") then guids[value] = true end
            return
        end
        if type(value) ~= "table" or seen[value] then return end
        seen[value] = true
        for key, inner in pairs(value) do
            CollectStrings(key, seen)
            CollectStrings(inner, seen)
        end
    end
    CollectStrings(globalDB, {})
    CollectStrings(sv.MSUF_DB, {})
end
CollectNames()

local function Numbered(set, prefix, keepPatterns)
    local map, ordered = {}, SortedKeys(set)
    local index = 0
    for _, original in ipairs(ordered) do
        local kept = false
        for _, pattern in ipairs(keepPatterns or {}) do
            if tostring(original):match(pattern) then kept = true end
        end
        if kept then
            map[original] = original
        else
            index = index + 1
            map[original] = string.format("%s%02d", prefix, index)
        end
    end
    return map
end
local nameMap = Numbered(names, "Char")
local realmMap = Numbered(realms, "Realm")
local profileMap = Numbered(profileNames, "Profile", KEPT_PROFILE_NAMES)
local characterKeyMap, guidMap = {}, {}
local function NumberCharactersAndGuids()
    for key in pairs(characterKeys) do
        local name, realm = key:match("^(.-)%-(.+)$")
        characterKeyMap[key] = nameMap[name] .. "-" .. realmMap[realm]
    end
    for index, guid in ipairs(SortedKeys(guids)) do guidMap[guid] = string.format("Player-0-%08X", index) end
end
NumberCharactersAndGuids()

-- Free text: a character or realm name inside a longer string.
local textReplacements = {}
local function Escape(text) return (text:gsub("%p", "%%%0")) end
local function ReplaceNamesInText(text)
    if characterKeyMap[text] then return characterKeyMap[text] end
    if guidMap[text] then return guidMap[text] end
    local out = text
    for _, map in ipairs({ nameMap, realmMap }) do
        for original, placeholder in pairs(map) do
            if #original >= 3 then
                out = out:gsub("%f[%w\128-\255]" .. Escape(original) .. "%f[^%w\128-\255]", placeholder)
            end
        end
    end
    if out ~= text then textReplacements[#textReplacements + 1] = text .. "  ->  " .. out end
    return out
end

---------------------------------------------------------------------------
-- Rewrite
---------------------------------------------------------------------------
local function Rewrite(value)
    if type(value) == "string" then return ReplaceNamesInText(value) end
    if type(value) ~= "table" then return value end
    local out = {}
    for key, inner in pairs(value) do
        local newKey = key
        if type(key) == "string" and characterKeyMap[key] then newKey = characterKeyMap[key] end
        out[newKey] = Rewrite(inner)
    end
    return out
end

local function RenameProfileKeys(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for key, value in pairs(t) do out[profileMap[key] or key] = value end
    return out
end

-- The stored profile MSUF_DB repeats (the client saves both tables).
local function ProfileOfDB()
    for _, name in ipairs(SortedKeys(globalDB.profiles or {})) do
        if DeepEqual(globalDB.profiles[name], sv.MSUF_DB) then return name end
    end
end
local profileOfDB = ProfileOfDB()

local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, inner in pairs(value) do copy[key] = Copy(inner) end
    return copy
end
-- Profile names first, while the stored names are still the originals; the
-- free-text pass below then never sees a profile name as text.
local function Renamed()
    local out = Copy(globalDB)
    out.profiles = RenameProfileKeys(out.profiles)
    out.ignoredPre6Profiles = out.ignoredPre6Profiles and RenameProfileKeys(out.ignoredPre6Profiles) or nil
    for _, cacheKey in ipairs(CHARACTER_PROFILE_CACHES) do
        for characterKey, perProfile in pairs(out[cacheKey] or {}) do
            out[cacheKey][characterKey] = RenameProfileKeys(perProfile)
        end
    end
    for _, binding in pairs(out.char or {}) do
        if type(binding) == "table" then
            if binding.activeProfile ~= nil then binding.activeProfile = profileMap[binding.activeProfile] or binding.activeProfile end
            if type(binding.specProfileMap) == "table" then
                for slot, mapped in pairs(binding.specProfileMap) do binding.specProfileMap[slot] = profileMap[mapped] or mapped end
            end
        end
    end
    if type(out.global) == "table" and out.global.defaultProfileForNewChars ~= nil then
        out.global.defaultProfileForNewChars = profileMap[out.global.defaultProfileForNewChars] or out.global.defaultProfileForNewChars
    end
    local syncGroups = type(out.global) == "table" and out.global.profileSyncGroups or nil
    for _, group in pairs(type(syncGroups) == "table" and syncGroups or {}) do
        if type(group) == "table" and type(group.members) == "table" then group.members = RenameProfileKeys(group.members) end
    end
    -- Character keys (as keys or whole values) and names inside free text.
    return Rewrite(out)
end
local out = Renamed()

-- Retired Assistant data (profile.assistant, GlobalDB.assistant*,
-- global.assistant*) is deleted once per account when the SavedVariables load
-- (State/MSUF_RetiredData.lua). A few leaves of it keep that cleanup covered;
-- the rest is the player's own chat text and is dropped here.
local function KeepFirstLeaves(value, budget)
    if type(value) ~= "table" then return value, budget - 1 end
    local out = {}
    for _, key in ipairs(SortedKeys(value)) do
        if budget <= 0 then break end
        out[key], budget = KeepFirstLeaves(value[key], budget)
    end
    return out, budget
end
local function TrimRetired(store)
    if type(store) ~= "table" then return end
    for _, key in ipairs(SortedKeys(store)) do
        if type(key) == "string" and key:sub(1, 9) == "assistant" and type(store[key]) == "table" then
            store[key] = (KeepFirstLeaves(store[key], 3))
        end
    end
end
local function Trim()
    for _, profile in pairs(out.profiles or {}) do TrimRetired(profile) end
    TrimRetired(out)
    TrimRetired(out.global)
    -- profile.suiteModules belongs to the MSUF Suite (State/MSUF_ProfileExternal.lua):
    -- MSUF stores it untouched and strips it from profile strings. Three leaves per
    -- Suite module keep that covered without carrying the Suite's whole settings.
    for _, profile in pairs(out.profiles or {}) do
        local modules = profile.suiteModules
        if type(modules) == "table" then
            for _, key in ipairs(SortedKeys(modules)) do modules[key] = (KeepFirstLeaves(modules[key], 3)) end
        end
    end
end
Trim()

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------
local dbProfile = profileOfDB and profileMap[profileOfDB] or nil
local function Select()
    if entry.keep ~= "all" then
        local keep = {}
        for _, name in ipairs(entry.keep) do
            assert(out.profiles[name], entryId .. ": no profile " .. name .. " to keep")
            keep[name] = true
        end
        assert(dbProfile == nil or keep[dbProfile], entryId .. ": the selection must keep " .. tostring(dbProfile)
            .. ", the profile MSUF_DB repeats")
        for name in pairs(out.profiles) do if not keep[name] then out.profiles[name] = nil end end
        for _, cacheKey in ipairs(CHARACTER_PROFILE_CACHES) do
            for _, perProfile in pairs(out[cacheKey] or {}) do
                for name in pairs(perProfile) do if not keep[name] then perProfile[name] = nil end end
            end
        end
    end
    -- Characters: bound to a kept profile other than Default first, then those
    -- carrying Priority Frames pins, then the Default ones, then the rest; ties by
    -- placeholder order.
    local characters = {}
    for key, binding in pairs(out.char or {}) do
        local active = type(binding) == "table" and binding.activeProfile or nil
        local rank = 4
        if active ~= nil and active ~= "Default" and out.profiles[active] ~= nil then
            rank = 1
        elseif type(binding) == "table" and type(binding.priorityFrames) == "table" then
            rank = 2
        elseif active == "Default" and out.profiles.Default ~= nil then
            rank = 3
        end
        characters[#characters + 1] = { key = key, rank = rank }
    end
    table.sort(characters, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.key < b.key
    end)
    local keptCharacters = {}
    for index, character in ipairs(characters) do
        if index <= entry.maxChars then keptCharacters[character.key] = true end
    end
    for key in pairs(out.char or {}) do if not keptCharacters[key] then out.char[key] = nil end end
    for _, cacheKey in ipairs(CHARACTER_PROFILE_CACHES) do
        for key in pairs(out[cacheKey] or {}) do if not keptCharacters[key] then out[cacheKey][key] = nil end end
    end
end
Select()

---------------------------------------------------------------------------
-- Writer
---------------------------------------------------------------------------
local function Number(value)
    if value ~= value or value == math.huge or value == -math.huge then
        error(entryId .. ": a SavedVariables fixture cannot hold " .. tostring(value))
    end
    -- "%d" goes through a C long (32 bits on Windows); larger values use %g.
    if value % 1 == 0 and math.abs(value) < 2 ^ 31 then return string.format("%d", value) end
    local text
    for digits = 14, 17 do
        text = string.format("%." .. digits .. "g", value)
        if tonumber(text) == value then break end
    end
    return (text:gsub("e([%+%-])0*(%d)", "e%1%2"))
end
local function String(value)
    return '"' .. value:gsub('[%c"\\]', function(c)
        if c == "\n" then return "\\n" end
        if c == "\r" then return "\\r" end
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        return string.format("\\%03d", c:byte())
    end) .. '"'
end
local function Scalar(value)
    local kind = type(value)
    if kind == "string" then return String(value) end
    if kind == "number" then return Number(value) end
    if kind == "boolean" then return value and "true" or "false" end
    error(entryId .. ": cannot write a " .. kind)
end
local RESERVED = {}
local function Reserve(words)
    for word in words:gmatch("%a+") do RESERVED[word] = true end
end
Reserve("and break do else elseif end false for function if in local nil not or repeat return then true until while")
local function Key(key)
    if type(key) == "string" and key:match("^[%a_][%w_]*$") and not RESERVED[key] then return key end
    return "[" .. Scalar(key) .. "]"
end
local lines = {}
local function Write(value, indent, prefix, suffix)
    local keys = SortedKeys(value)
    local leafOnly = true
    for _, key in ipairs(keys) do if type(value[key]) == "table" then leafOnly = false end end
    if #keys == 0 then
        lines[#lines + 1] = indent .. prefix .. "{}" .. suffix
        return
    end
    if leafOnly then
        -- Leaf tables pack as many entries per line as fit in 150 columns.
        local current = indent .. prefix .. "{"
        for index, key in ipairs(keys) do
            local item = Key(key) .. "=" .. Scalar(value[key]) .. (index < #keys and "," or "")
            if #current + #item > 150 and current:sub(-1) ~= "{" then
                lines[#lines + 1] = current
                current = indent .. "  "
            end
            current = current .. item
        end
        lines[#lines + 1] = current .. "}" .. suffix
        return
    end
    lines[#lines + 1] = indent .. prefix .. "{"
    for index, key in ipairs(keys) do
        local inner = value[key]
        local comma = index < #keys and "," or ""
        if type(inner) == "table" then
            Write(inner, indent .. " ", Key(key) .. "=", comma)
        else
            lines[#lines + 1] = indent .. " " .. Key(key) .. "=" .. Scalar(inner) .. comma
        end
    end
    lines[#lines + 1] = indent .. "}" .. suffix
end

local function Emit()
    lines[#lines + 1] = "-- Anonymized MSUF SavedVariables fixture " .. entryId .. "."
    lines[#lines + 1] = "-- Generated by tools/fixtures/profiles/build_corpus.lua; provenance in tools/fixtures/profiles/README.md."
    lines[#lines + 1] = "-- MSUF_FIXTURE_COPY(t) is a deep copy: the client writes MSUF_DB and the active profile as two equal tables."
    Write(out, "", "MSUF_GlobalDB = ", "")
    if dbProfile then
        lines[#lines + 1] = string.format("MSUF_DB = MSUF_FIXTURE_COPY(MSUF_GlobalDB.profiles[%s])", String(dbProfile))
    elseif sv.MSUF_DB ~= nil then
        Write(Rewrite(sv.MSUF_DB), "", "MSUF_DB = ", "")
    end
    local target = root .. "/tools/fixtures/profiles/sv/" .. entryId .. ".lua"
    local handle = assert(io.open(target, "wb"))
    handle:write(table.concat(lines, "\r\n"), "\r\n")
    handle:close()

    -- Operator report (stdout only).
    print("wrote " .. target .. " (" .. #lines .. " lines)")
    print("MSUF_DB repeats profile: " .. tostring(dbProfile))
    for _, map in ipairs({ { "character", characterKeyMap }, { "profile", profileMap } }) do
        for _, original in ipairs(SortedKeys(map[2])) do
            print(string.format("  %s %s -> %s", map[1], original, map[2][original]))
        end
    end
    for _, line in ipairs(textReplacements) do print("  text " .. line) end
end
Emit()
