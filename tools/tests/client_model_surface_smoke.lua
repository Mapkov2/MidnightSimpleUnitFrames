-- The published surface of the client model, and the proof that routing the
-- duplicated client checks through it changed no answer on any client.
--
-- Part 1 loads the real Game/Shared/Initialize.lua once per client (Midnight,
-- WoW Forever, Classic Era, TBC, Mists and an unplaced client) and pins the
-- complete fact set: every key the model publishes, its value, and the absence
-- of the surface that was removed as dead (MSUF.Retail/Vanilla/Era/Mists/TBC/
-- Classic/Forever, MSUF.Compat.Client, Client.ProjectID, Client.IsEra).
--
-- Part 2 evaluates, for every site this pass touched, the expression as it read
-- before against the expression as it reads now, with the real model in scope,
-- and requires the same answer on all six clients. The Cooldown Manager sites
-- are the deliberate exception and carry their own note.
--
-- Plain Lua 5.1; arg[1] is the repo root.
local repo = assert(arg[1], "repo root required")
local loadChunk = loadstring or load
local chunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Shared/Initialize.lua"))

local PROJECT = { MAINLINE = 1, CLASSIC = 2, TBC = 5, MISTS = 19 }
local CORE_ADDON = "MidnightSimpleUnitFrames"

-- Real interface numbers from tools/classic-client-matrix.tsv.
local CASES = {
    {
        label = "Midnight", project = PROJECT.MAINLINE, interface = 120105, build = "12.1.5", version = "6.20",
        family = "Mainline", flavor = "Mainline", cooldownAddOn = true,
    },
    {
        label = "Forever", project = PROJECT.MAINLINE, interface = 16001, build = "1.60.1", version = "6.20",
        foreverVersion = "6.5-beta4", marker = true, family = "Mainline", flavor = "Mainline",
        cooldownAddOn = true,
    },
    {
        label = "Vanilla", project = PROJECT.CLASSIC, interface = 11509, build = "1.15.9", version = "6.5-beta4",
        tag = "Vanilla", family = "Classic", flavor = "Vanilla", cooldownAddOn = false,
    },
    {
        label = "TBC", project = PROJECT.TBC, interface = 20506, build = "2.5.6", version = "6.5-beta4",
        tag = "TBC", family = "Classic", flavor = "TBC", cooldownAddOn = false,
    },
    {
        label = "Mists", project = PROJECT.MISTS, interface = 50504, build = "5.5.4", version = "6.5-beta4",
        tag = "Mists", family = "Classic", flavor = "Mists", cooldownAddOn = false,
    },
    {
        -- An unplaced client: an untagged Mainline TOC under a project ID no
        -- constant matches. Detection fails closed and prints one login line.
        label = "Unplaced", project = 999, interface = 120105, build = "12.1.5", version = "6.20",
        family = "Unknown", flavor = "Unknown", cooldownAddOn = true, diagnostic = true,
    },
}

local printed = {}
local realPrint = print

local function Load(case)
    WOW_PROJECT_MAINLINE = PROJECT.MAINLINE
    WOW_PROJECT_CLASSIC = PROJECT.CLASSIC
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC = PROJECT.TBC
    WOW_PROJECT_MISTS_CLASSIC = PROJECT.MISTS
    WOW_PROJECT_ID = case.project
    GetAddOnMetadata = nil
    C_AddOns = {
        GetAddOnMetadata = function(name, key)
            assert(name == CORE_ADDON, case.label .. ": a TOC other than the core was read: " .. tostring(name))
            if key == "X-MSUF-Client" then return case.tag end
            if key == "Version" then return case.version end
            if key == "X-MSUF-Version-Forever" then return case.foreverVersion end
            return nil
        end,
        -- Blizzard_CooldownViewer ships with the Mainline game types only.
        DoesAddOnExist = function(name)
            if name == "Blizzard_CooldownViewer" then return case.cooldownAddOn == true end
            return false
        end,
        IsAddOnLoaded = function() return false end,
        GetAddOnInfo = function() return nil, nil, nil, true end,
    }
    GetBuildInfo = function()
        return case.build, "70000", "Jan 1 2026", case.interface
    end
    -- The Cooldown Manager namespace lives in the shared engine: it exists on
    -- every client, which is exactly why it is not a client signal.
    C_CooldownViewer = { IsCooldownViewerAvailable = function() return true end }
    issecretvalue = function() return false end
    C_EventUtils = { IsEventValid = function(event) return event ~= "FAKE_EVENT" end }
    Enum = { GameMode = { Standard = 0, Plunderstorm = 1 }, EditModeSystem = {} }
    C_GameRules = { GetActiveGameMode = function() return 0 end }
    GameEvent = case.marker and { RegisterCamelotEvents = function() end } or nil
    CLASS_SORT_ORDER = {}
    MAX_ARENA_ENEMIES = nil
    MSUF_MAX_ARENA_FRAMES = 99
    MSUF, MSUF_NS = nil, nil
    CreateFrame = function()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(name, handler) self.scripts[name] = handler end
        return frame
    end
    printed = {}
    print = function(...) printed[#printed + 1] = tostring((...)) end
    local namespace = {}
    chunk(CORE_ADDON, namespace)
    print = realPrint
    return namespace
end

-- The complete published surface. A new fact has to be added here on purpose,
-- and a fact that was removed as dead cannot come back unnoticed.
local FUNCTION_KEYS = { "SupportsEvent", "SupportsUnit", "SupportsGroupKind", "SupportsClassResource", "SupportsClassResourceSetting", "IsGameRuleActive",
    "DescribeLines" }
local TABLE_KEYS = { "UnsupportedEvents", "UnsupportedUnits" }
local REMOVED_FIELDS = { "ProjectID", "IsEra" }
local REMOVED_ALIASES = { "Retail", "Vanilla", "Era", "Mists", "TBC", "Classic", "Forever" }

local function ExpectedFacts(case)
    local isForever = case.label == "Forever"
    local isVanilla = case.flavor == "Vanilla"
    local isClassic = case.family == "Classic"
    local isRetail = case.family == "Mainline"
    return {
        Interface = case.interface,
        Flavor = case.flavor,
        Family = case.family,
        IsRetail = isRetail,
        IsVanilla = isVanilla,
        IsMists = case.flavor == "Mists",
        IsTBC = case.flavor == "TBC",
        IsClassic = isClassic,
        IsForever = isForever,
        IsSupported = case.flavor ~= "Unknown",
        ProjectIDRecognized = case.label ~= "Unplaced",
        TOCFlavor = case.tag and case.tag:lower() or nil,
        SupportsPetHappiness = isVanilla or case.flavor == "TBC" or isForever,
        SupportsTapDenied = isClassic or isForever,
        SupportsThreatText = isVanilla or case.flavor == "TBC" or isForever,
        HasCharacterSurnames = isForever,
        HasEmpoweredCasts = isRetail and not isForever,
        SupportsOnboardingScenes = not isForever,
        DispellableDebuffFilter = isVanilla and "HARMFUL|RAID" or "HARMFUL|RAID_PLAYER_DISPELLABLE",
        SupportsEllesmereEditMode = isRetail,
        SupportsBlizzardEditMode = true,
        HasSecretValueAPI = true,
        -- Mainline ships Blizzard_CooldownViewer, no Classic client does.
        HostsCooldownManager = isRetail,
        GameMode = 0,
        GameModeName = "Standard",
        IsStandardGameMode = true,
        GameModeRecognized = true,
        AddonVersion = isForever and case.foreverVersion or case.version,
        MaxArenaOpponents = isForever and 0 or isVanilla and 0 or isClassic and 5 or isRetail and 3 or 0,
        Diagnostic = case.diagnostic and true or nil,
    }
end

local MODELS = {}
for _, case in ipairs(CASES) do
    local namespace = Load(case)
    local client = assert(namespace.Client, case.label .. ": the client model was not published")
    MODELS[case.label] = { client = client, namespace = namespace, case = case }

    local expected = ExpectedFacts(case)
    for key, want in pairs(expected) do
        local got = client[key]
        if key == "Diagnostic" then
            got = got ~= nil or nil
        end
        assert(got == want, string.format("%s: Client.%s is %s, expected %s",
            case.label, key, tostring(got), tostring(want)))
    end
    for _, key in ipairs(FUNCTION_KEYS) do
        assert(type(client[key]) == "function", case.label .. ": Client." .. key .. " is not a function")
    end
    for _, key in ipairs(TABLE_KEYS) do
        assert(type(client[key]) == "table", case.label .. ": Client." .. key .. " is not a table")
    end
    -- No key beyond the three lists above may be published.
    local known = {}
    for key in pairs(expected) do known[key] = true end
    for _, key in ipairs(FUNCTION_KEYS) do known[key] = true end
    for _, key in ipairs(TABLE_KEYS) do known[key] = true end
    for key in pairs(client) do
        assert(known[key], case.label .. ": Client." .. tostring(key)
            .. " is published but not pinned here; add it to the fact set on purpose")
    end
    for _, key in ipairs(REMOVED_FIELDS) do
        assert(client[key] == nil, case.label .. ": Client." .. key .. " had no reader and must stay removed")
    end
    for _, alias in ipairs(REMOVED_ALIASES) do
        assert(namespace[alias] == nil, case.label .. ": the dead alias MSUF." .. alias .. " is back")
    end
    assert(namespace.Compat == nil or namespace.Compat.Client == nil,
        case.label .. ": the dead MSUF.Compat.Client bridge is back")
    assert(type(namespace.GetAddonVersion) == "function",
        case.label .. ": the shared version accessor MSUF.GetAddonVersion is missing")
    assert(MSUF_MAX_ARENA_FRAMES == client.MaxArenaOpponents,
        case.label .. ": MSUF_MAX_ARENA_FRAMES differs from MaxArenaOpponents")
    -- Detection never prints at file load; the login diagnostic goes out on
    -- PLAYER_LOGIN, and only an unplaced client has one at all.
    assert(#printed == 0, case.label .. ": detection printed at file load: " .. tostring(printed[1]))
end

-- Part 2: old expression against new expression, with the real model in scope.
-- `old` and `new` are evaluated in the same sandbox; `_G` is the case's global
-- table so a raw project read still resolves the way it used to.
local function Evaluate(source, name, label)
    local model = MODELS[label]
    local env = {
        WOW_PROJECT_ID = model.case.project,
        WOW_PROJECT_MAINLINE = PROJECT.MAINLINE,
        WOW_PROJECT_CLASSIC = PROJECT.CLASSIC,
        WOW_PROJECT_BURNING_CRUSADE_CLASSIC = PROJECT.TBC,
        WOW_PROJECT_MISTS_CLASSIC = PROJECT.MISTS,
        C_CooldownViewer = { IsCooldownViewerAvailable = function() return true end },
        C_AddOns = { GetAddOnMetadata = function(addon, key)
            assert(addon == CORE_ADDON, label .. ": a TOC other than the core was read")
            if key == "Version" then return model.case.version end
            return nil
        end },
        GetBuildInfo = function()
            return model.case.build, "70000", "Jan 1 2026", model.case.interface
        end,
        type = type, tonumber = tonumber, tostring = tostring, select = select, math = math,
        string = string,
    }
    env._G = env
    local body = loadChunk("local MSUF, M, _G = ...\n" .. source .. "\nreturn " .. name)
    assert(body, label .. ": cannot compile the pinned expression for " .. name)
    setfenv(body, env)
    return body({ Client = model.client, GetAddonVersion = model.namespace.GetAddonVersion }, {}, env)
end

local function SameOnEveryClient(what, old, new, name)
    for _, case in ipairs(CASES) do
        local before = Evaluate(old, name, case.label)
        local after = Evaluate(new, name, case.label)
        assert(before == after, string.format("%s changed on %s: was %s, now %s",
            what, case.label, tostring(before), tostring(after)))
    end
end

-- A35: raw project reads routed through the client model.
SameOnEveryClient("the native aura runtime expectation (Auras3_Core)",
    "local expected\ndo\n  local client = MSUF.Client\n"
    .. "  local projectID, mainlineID = _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE\n"
    .. "  if type(client) == 'table' and client.IsForever == true then expected = true\n"
    .. "  elseif projectID ~= nil and mainlineID ~= nil and projectID ~= mainlineID then expected = false\n"
    .. "  else expected = true end\nend",
    "local expected\ndo\n  local client = MSUF.Client\n"
    .. "  if type(client) ~= 'table' then expected = true else expected = client.Family == 'Mainline' end\nend",
    "expected")

SameOnEveryClient("the legacy Era portrait gate (Portrait element and the Classic preview)",
    "local LEGACY_BLIZZARD_PORTRAIT = (MSUF.Client ~= nil and MSUF.Client.IsVanilla == true)\n"
    .. "  or (MSUF.Client == nil and _G.WOW_PROJECT_CLASSIC ~= nil and _G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC)",
    "local LEGACY_BLIZZARD_PORTRAIT = MSUF.Client ~= nil and MSUF.Client.IsVanilla == true",
    "LEGACY_BLIZZARD_PORTRAIT")

SameOnEveryClient("the reduced Classic aura filter set (Auras page)",
    "local reduced = MSUF.Client ~= nil and MSUF.Client.IsClassic == true\n"
    .. "  or MSUF.Client == nil and (_G.WOW_PROJECT_ID ~= nil and _G.WOW_PROJECT_ID ~= _G.WOW_PROJECT_MAINLINE)",
    "local reduced = MSUF.Client ~= nil and MSUF.Client.IsClassic == true",
    "reduced")

SameOnEveryClient("the Mainline-only Misc page gate",
    "local IS_MAINLINE = MSUF.Client ~= nil and MSUF.Client.Family == 'Mainline'\n"
    .. "  or MSUF.Client == nil and (_G.WOW_PROJECT_ID == nil or _G.WOW_PROJECT_MAINLINE == nil\n"
    .. "    or _G.WOW_PROJECT_ID == _G.WOW_PROJECT_MAINLINE)",
    "local IS_MAINLINE = MSUF.Client == nil or MSUF.Client.Family == 'Mainline'",
    "IS_MAINLINE")

SameOnEveryClient("the Cooldown Manager client gate (ThirdPartyAnchors)",
    "local hosts\ndo\n  local client = MSUF.Client\n"
    .. "  if client ~= nil then hosts = client.Family == 'Mainline'\n"
    .. "  else\n    local projectID, mainlineID = _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE\n"
    .. "    hosts = projectID == nil or mainlineID == nil or projectID == mainlineID\n  end\nend",
    "local hosts\ndo\n  local client = MSUF.Client\n"
    .. "  if client ~= nil then hosts = client.Family == 'Mainline' else hosts = true end\nend",
    "hosts")

-- A34: the nine namespace fallbacks. The shipped answer has always come from
-- Integrations (client family AND the engine namespace), because every TOC
-- loads MSUF_Integration_ThirdPartyAnchors.lua before any of those functions
-- can run; the bare namespace fallback was unreachable, and wrong wherever it
-- could have been reached. Client.HostsCooldownManager must equal the shipped
-- answer on every client, and must differ from the bare namespace on Classic.
SameOnEveryClient("Essential Cooldown anchor support",
    "local supported = (MSUF.Client ~= nil and MSUF.Client.Family == 'Mainline')\n"
    .. "  and type(_G.C_CooldownViewer) == 'table'",
    "local supported = MSUF.Client ~= nil and MSUF.Client.HostsCooldownManager == true",
    "supported")
for _, case in ipairs(CASES) do
    local bareNamespace = Evaluate("local ns = type(_G.C_CooldownViewer) == 'table'", "ns", case.label)
    assert(bareNamespace == true, case.label .. ": the test client must expose the engine namespace")
    if case.family ~= "Mainline" then
        assert(MODELS[case.label].client.HostsCooldownManager == false,
            case.label .. ": the namespace fallback would have claimed a Cooldown Manager here")
    end
end

-- A36: nine hand-rolled version lookups replaced by one shared accessor.
SameOnEveryClient("the addon version lookup",
    "local version = (MSUF.Client and MSUF.Client.AddonVersion)\n"
    .. "  or (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and _G.C_AddOns.GetAddOnMetadata('"
    .. CORE_ADDON .. "', 'Version')) or nil",
    "local version\ndo\n  local get = MSUF.GetAddonVersion\n"
    .. "  version = type(get) == 'function' and get() or nil\nend",
    "version")
-- WoW Forever shares the Mainline TOC, so its version can only come from the
-- model: the TOC lookup the nine copies used would report Midnight's number.
assert(MODELS.Forever.namespace.GetAddonVersion() == "6.5-beta4"
    and MODELS.Midnight.namespace.GetAddonVersion() == "6.20",
    "the shared accessor lost the per-client version split")

-- A37: GetBuildInfo re-reads routed to Client.Interface.
for _, case in ipairs(CASES) do
    local client = MODELS[case.label].client
    assert(client.Interface == case.interface,
        case.label .. ": Client.Interface is not the interface GetBuildInfo reports")
end
SameOnEveryClient("the client version warning's interface read",
    "local interfaceNumber\ndo\n  local getBuildInfo = _G.GetBuildInfo\n"
    .. "  if type(getBuildInfo) == 'function' then interfaceNumber = tonumber((select(4, getBuildInfo()))) end\nend",
    "local interfaceNumber\ndo\n  local client = MSUF.Client\n"
    .. "  local interface = type(client) == 'table' and client.Interface or nil\n"
    .. "  interfaceNumber = type(interface) == 'number' and interface or nil\nend",
    "interfaceNumber")
SameOnEveryClient("the welcome message's patch label",
    "local patch\ndo\n  local getBuildInfo = _G.GetBuildInfo\n"
    .. "  local version = type(getBuildInfo) == 'function' and getBuildInfo() or nil\n"
    .. "  patch = type(version) == 'string' and version:match('^(%d+%.%d+)') or '12.1'\nend",
    "local patch\ndo\n  local client = MSUF.Client\n"
    .. "  local interface = type(client) == 'table' and client.Interface or nil\n"
    .. "  if type(interface) ~= 'number' then patch = '12.1'\n"
    .. "  else patch = math.floor(interface / 10000) .. '.' .. (math.floor(interface / 100) % 100) end\nend",
    "patch")
SameOnEveryClient("the welcome message's 12.1 comparison",
    "local atLeast\ndo\n  local getBuildInfo = _G.GetBuildInfo\n"
    .. "  local version = type(getBuildInfo) == 'function' and getBuildInfo() or nil\n"
    .. "  local major, minor\n"
    .. "  if type(version) == 'string' then major, minor = version:match('^(%d+)%.(%d+)') end\n"
    .. "  major, minor = tonumber(major), tonumber(minor)\n"
    .. "  atLeast = (major ~= nil and minor ~= nil) and (major > 12 or (major == 12 and minor >= 1)) or false\nend",
    "local atLeast\ndo\n  local client = MSUF.Client\n"
    .. "  local interface = type(client) == 'table' and client.Interface or nil\n"
    .. "  atLeast = type(interface) == 'number' and interface >= 12 * 10000 + 1 * 100 or false\nend",
    "atLeast")

-- The Evaluate sandbox has no string library, so the version-string branches
-- above need `string.match` through the value's metatable; make sure that works
-- rather than silently returning nil on both sides.
assert(("12.1.5"):match("^(%d+%.%d+)") == "12.1", "the pinned version-string parse is broken")

print("client model surface smoke passed: " .. #CASES .. " clients")
