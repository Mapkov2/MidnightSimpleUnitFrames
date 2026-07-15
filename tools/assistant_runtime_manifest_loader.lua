local Loader = {}

local function exists(path)
    local handle = io.open(path, "rb")
    if handle then handle:close(); return true end
    return false
end

local function dirname(path)
    path = tostring(path or ""):gsub("[/\\]+$", "")
    return path:match("^(.*)[/\\][^/\\]+$") or "."
end

local function join(left, right)
    left = tostring(left or ""):gsub("[/\\]+$", "")
    right = tostring(right or ""):gsub("^[/\\]+", "")
    if left == "" or left == "." then return left == "." and ("./" .. right) or right end
    return left .. "/" .. right
end

local function addCandidate(out, seen, path)
    path = tostring(path or ""):gsub("[/\\]+$", "")
    if path ~= "" and not seen[path] then
        seen[path] = true
        out[#out + 1] = path
    end
end

function Loader.ResolveCompanionRoot(root)
    local candidates, seen = {}, {}
    root = tostring(root or ""):gsub("[/\\]+$", "")
    if root ~= "" then
        addCandidate(candidates, seen, root)
        addCandidate(candidates, seen, join(root, "MidnightSimpleUnitFrames_Assistant"))
        addCandidate(candidates, seen, join(dirname(root), "MidnightSimpleUnitFrames_Assistant"))
    end
    addCandidate(candidates, seen, "MidnightSimpleUnitFrames_Assistant")
    addCandidate(candidates, seen, "../MidnightSimpleUnitFrames_Assistant")
    addCandidate(candidates, seen, "../../MidnightSimpleUnitFrames_Assistant")

    for i = 1, #candidates do
        if exists(join(candidates[i], "MidnightSimpleUnitFrames_Assistant.toc"))
            and exists(join(candidates[i], "MSUF_AssistantRuntime.xml")) then
            return candidates[i]
        end
    end
    error("MSUF Assistant LoD companion root not found (expected MidnightSimpleUnitFrames_Assistant.toc and MSUF_AssistantRuntime.xml)")
end

function Loader.ResolveRuntimeXml(root)
    return join(Loader.ResolveCompanionRoot(root), "MSUF_AssistantRuntime.xml")
end

function Loader.ReadRuntimeEntries(root)
    local xmlPath = Loader.ResolveRuntimeXml(root)
    local handle = assert(io.open(xmlPath, "rb"))
    local xml = handle:read("*a") or ""
    handle:close()

    local companionRoot = dirname(xmlPath)
    local entries, seen = {}, {}
    for relative in xml:gmatch('<Script%s+file="([^"]+)"') do
        relative = tostring(relative or ""):gsub("\\", "/")
        assert(relative ~= "" and not relative:find("..", 1, true), "unsafe Assistant runtime entry: " .. relative)
        assert(not seen[relative], "duplicate Assistant runtime entry: " .. relative)
        seen[relative] = true
        local path = join(companionRoot, relative)
        assert(exists(path), "missing Assistant runtime file: " .. path)
        entries[#entries + 1] = { relative = relative, path = path }
    end
    assert(#entries >= 3, "Assistant V1 LoD manifest is incomplete")
    assert(entries[1].relative == "Assistant/MSUF_AssistantLOD_Bootstrap.lua", "Assistant bootstrap must load first")
    assert(entries[#entries - 1].relative == "MSUF_Menu2_AssistantDialogLocale_Data.lua"
        and entries[#entries].relative == "MSUF_Menu2_AssistantDialogLocale.lua",
        "Assistant dialog locale data and adapter must load last")
    return entries, xmlPath, companionRoot
end

function Loader.LoadAssistantRuntime(MSUF, options)
    options = options or {}
    MSUF = MSUF or _G.MSUF_NS
    assert(type(MSUF) == "table", "MSUF namespace is required")

    local entries = Loader.ReadRuntimeEntries(options.root)
    local loaded, loadedSet = {}, {}
    local skip = options.skip or {}
    local includeDashboard = options.includeDashboard == true
    local includeDialogLocale = options.includeDialogLocale == true
    local private = options.private
    if type(private) ~= "table" then
        private = options.useCompanionPrivate == true and {} or MSUF
    end
    local addonName = options.addonName or "MidnightSimpleUnitFrames_Assistant"

    local expected = 0
    for i = 1, #entries do
        local entry = entries[i]
        local relative = entry.relative
        local base = relative:match("([^/]+)$") or relative
        local isAssistant = relative:match("^Assistant/.+%.lua$") ~= nil
        local isDashboard = base == "MSUF_AssistantDashboard.lua"
        local isDialogLocale = relative:match("^MSUF_Menu2_AssistantDialogLocale.-%.lua$") ~= nil
        local selected = (isAssistant and (includeDashboard or not isDashboard))
            or (isDialogLocale and includeDialogLocale)

        if selected and not skip[base] and not skip[relative] and not loadedSet[relative] then
            expected = expected + 1
            local chunk, err = loadfile(entry.path)
            assert(chunk, err)
            local ok, result = pcall(chunk, addonName, private)
            assert(ok, entry.path .. ": " .. tostring(result))
            loadedSet[relative] = true
            loaded[#loaded + 1] = relative
        end
    end

    assert(#loaded == expected, string.format("Assistant V1 loader expected %d files, loaded %d", expected, #loaded))
    return loaded, private
end

local FINGERPRINT_MOD_A = 4294967291
local FINGERPRINT_MOD_B = 4294967279

function Loader.RegistryInventoryFingerprintFromLists(settings, actions)
    local rows = {}
    for i = 1, #(settings or {}) do
        local key = tostring(settings[i] and settings[i].key or "")
        assert(key ~= "", "Registry setting inventory contains an empty key")
        rows[#rows + 1] = "setting\t" .. key
    end
    for i = 1, #(actions or {}) do
        local key = tostring(actions[i] and actions[i].key or "")
        assert(key ~= "", "Registry action inventory contains an empty key")
        rows[#rows + 1] = "action\t" .. key
    end
    table.sort(rows)

    local hashA, hashB = 2166136261, 5381
    for i = 1, #rows do
        local row = rows[i] .. "\n"
        for j = 1, #row do
            local byte = row:byte(j)
            -- Both products remain below Lua 5.1's exact integer range before
            -- the modulus. Decimal output also avoids C integer-width-specific
            -- hexadecimal formatting between Windows Lua and CI runtimes.
            hashA = (hashA * 131 + byte) % FINGERPRINT_MOD_A
            hashB = (hashB * 65599 + byte) % FINGERPRINT_MOD_B
        end
    end
    return string.format("v1-%.0f-%.0f", hashA, hashB)
end

function Loader.RegistryInventoryFingerprint(registry)
    assert(type(registry) == "table", "Registry is required for inventory fingerprint")
    local settings = assert(type(registry.AllSettings) == "function" and registry:AllSettings(),
        "Registry settings inventory is unavailable")
    local actions = assert(type(registry.AllActions) == "function" and registry:AllActions(),
        "Registry actions inventory is unavailable")
    return Loader.RegistryInventoryFingerprintFromLists(settings, actions)
end

function Loader.AssertRegistryInventoryFingerprintContract()
    local baseline = Loader.RegistryInventoryFingerprintFromLists(
        { { key = "general.alpha" }, { key = "player.enabled" } },
        { { key = "open_page" }, { key = "reset_profile" } })
    local reordered = Loader.RegistryInventoryFingerprintFromLists(
        { { key = "player.enabled" }, { key = "general.alpha" } },
        { { key = "reset_profile" }, { key = "open_page" } })
    assert(baseline == reordered, "Registry fingerprint depends on registration order")

    local sameCountReplacement = Loader.RegistryInventoryFingerprintFromLists(
        { { key = "general.alpha" }, { key = "target.enabled" } },
        { { key = "open_page" }, { key = "reset_profile" } })
    assert(baseline ~= sameCountReplacement,
        "Registry fingerprint did not detect a same-count setting replacement")

    local kindReplacement = Loader.RegistryInventoryFingerprintFromLists(
        { { key = "general.alpha" }, { key = "player.enabled" }, { key = "open_page" } },
        { { key = "reset_profile" } })
    assert(baseline ~= kindReplacement,
        "Registry fingerprint did not distinguish setting and action identities")
    return true
end

return Loader
