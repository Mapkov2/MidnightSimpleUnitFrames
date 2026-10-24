-- profile_corpus_golden.lua -- the old-profile regression corpus: load every
-- corpus entry through the real State pipeline and compare the effective
-- settings with the golden files.
--
--   lua tools/profile_corpus_golden.lua <repo root> <flavor|all> [--write] [--entry <id>] [--verbose]
--
-- Check mode (the default) runs the entries that list <flavor> and fails with
-- the first differing paths per entry. --write regenerates the golden files;
-- it needs every client of an entry, so it takes "all" (or one --entry), and it
-- is allowed only for a deliberate, reviewed behaviour change
-- (tools/fixtures/profiles/README.md). The gate runs
-- tools/tests/profile_corpus_golden_smoke.lua, which is this check per client.
--
-- What one entry run does, per client (tools/tests/client_world.lua):
--   1. boots the client's core TOC graph (Options is load-on-demand and stays
--      unloaded, as at a login),
--   2. installs the SavedVariables globals and fires ADDON_LOADED (FirstLoad
--      settles, the pre-6 archive and the retired-data cleanup run),
--   3. fires PLAYER_LOGIN to every registered handler and runs the one-frame
--      timers they queued, each handler isolated the way the client's error
--      handler isolates it (the profile binds lazily inside these),
--   4. records the account table, the character bindings, the binding every
--      stored character resolves to, and for each profile in the pool the
--      effective settings after binding it with MSUF_SwitchProfile,
--   5. exports each profile ("all"), imports the string into a new profile and
--      asserts the import reproduces the same effective settings.
-- The factory entry starts from empty SavedVariables and adds a new profile,
-- resets and every profile string of the corpus (MSUF_ImportIntoNewProfile).
-- The runtime apply after a profile change runs for real; its frame steps and
-- the import's repaints run isolated (FRAME_STEPS), because the harness models
-- no real frames. Every error a run catches must match Corpus.HARNESS_ERRORS.
-- C_EncodingUtil is tools/tests/encoding_util_emulator.lua.
--
-- Golden files (tools/fixtures/profiles/golden/<entry>.golden) hold, per
-- recorded subtree, only the paths whose value differs from its reference:
-- the entry's input (the stored SavedVariables table), another recorded
-- subtree (a new profile against the first-login Default) or, after an
-- "@overlay" line, the stored or imported table over that base. "[common]"
-- lists the differences every client of the entry shares; "[<client>]" the
-- rest. A value of nil means the path is absent.
--
-- Plain Lua 5.1.

local Corpus = {}

local FIXTURES = "tools/fixtures/profiles"
-- The harness clock. FirstLoad, the guided tour and the upgrade highlights
-- stamp time(); a fixed clock keeps a run deterministic.
local FROZEN_TIME = 1790000000
local NEW_CHARACTER = "NewChar-NewRealm"

---------------------------------------------------------------------------
-- Effective settings
---------------------------------------------------------------------------

--- Effective(profile, defaults) -> the settings the client acts on for one
--- stored profile. This is the ONE definition of "effective" in the corpus.
---
--- Today State/MSUF_Defaults.lua materializes every default into the stored
--- profile when it binds (the heavy pass of MSUF_EnsureDB), so the stored
--- table already is the effective view and `defaults` is unused (nil). When
--- profiles become sparse, this returns defaults overlaid with the stored
--- values, the caller passes the client's defaults, and
--- nothing else in the corpus changes: the golden files keep comparing the
--- same effective settings.
function Corpus.Effective(profile, defaults)
    local _ = defaults
    return profile
end

-- The client's defaults for Effective. nil while profiles are materialized.
local function Defaults(_world)
    return nil
end

---------------------------------------------------------------------------
-- Exclusions
---------------------------------------------------------------------------

-- Volatile fields: not settings, and they change with the clock or with the
-- addon version rather than with what a profile says. Patterns match a whole
-- canonical path; they apply to the recorded state and its reference alike.
Corpus.VOLATILE = {
    { "^global%.firstLoad6%.firstSeenAt$", "first-load lifecycle timestamp (time())" },
    { "^global%.firstLoad6%.updatedAt$", "first-load lifecycle timestamp (time())" },
    { "^global%.firstLoad6%.completedAt$", "first-load lifecycle timestamp (time())" },
    { "^global%.firstLoad6%.dismissedAt$", "first-load lifecycle timestamp (time())" },
    { "^global%.firstLoad6%.firstSeenVersion$", "addon version of the first login; changes with every VERSION bump" },
    { "^global%.guidedTour6%.[%w]*At$", "guided tour timestamps (time())" },
    { "^global%.upgradeHighlights[%.%[]", "per-release What's New tracking, keyed by the addon version, with timestamps" },
    { "^global%.bindings[%.%[]", "observational copy of the client's live key bindings, re-read at every login"
        .. " (Kernel/MSUF_Keybinds.lua); the harness client has none" },
}

-- Round-trip differences the baseline shows (tools/fixtures/profiles/README.md,
-- "What the baseline shows"). Each rule is { id, pattern, kind }: the pattern
-- matches the path inside the profile, kind is "added" (absent in the exported
-- profile, present in the imported copy), "dropped" (the reverse) or "any".
-- The golden files count the differences per rule; any other difference fails
-- the corpus.
Corpus.ROUNDTRIP_EXCEPTIONS = {
    -- Blizzard Edit Mode layouts travel only while the Profiles page switch is
    -- on, and it is off by default.
    { "editModeOptIn", "^%.general%.blizzardEditModeSnapshot[%.%[]", "dropped" },
    -- Suite-owned root (State/MSUF_ProfileExternal.lua): MSUF strings never carry it.
    { "suiteOwned", "^%.suiteModules[%.%[]", "dropped" },
    -- Export stamps the current screen reference on positioned frames; the
    -- client rescales the offsets when it lays the frames out
    -- (UnitFrames/Engine/MSUF_UF_Config.lua AdaptScreenPosition).
    { "screenReference", "%.screenPosition[MH][%w]+$", "any" },
    -- The import's forced normalization fills keys the stored profile lacks:
    -- a profile stamped with the current defaults revision takes the persisted
    -- fast path and never receives defaults added later under that revision,
    -- and the export's group-frame normalization writes the buff lanes'
    -- trackedStrata, which no stored profile has (fresh installs included).
    { "filledOnImport", "^%.[%w_]+%.petHappinessIndicator[%w_]+$", "added" },
    { "filledOnImport", "^%.[%w_]+%.showPetHappinessIndicator$", "added" },
    { "filledOnImport", "^%.[%w_]+%.trinket[%w_]+$", "added" },
    { "filledOnImport", "^%.[%w_]+%.portraitDragon[%w_]+$", "added" },
    { "filledOnImport", "^%.[%w_]+%.portraitFlip$", "added" },
    { "filledOnImport", "^%.[%w_]+%.portraitInnerShadow$", "added" },
    { "filledOnImport", "^%.[%w_]+%.portraitBlizzardDirection$", "added" },
    { "filledOnImport", "^%.general%._msufForeverMutedHealth_v1$", "added" },
    { "filledOnImport", "^%.general%.gcdBar[%w_]+$", "added" },
    { "filledOnImport", "^%.general%.kickReadyTimeMarker$", "added" },
    { "filledOnImport", "^%.gf_[%w_]+%.auras%.buff%.trackedStrata$", "added" },
}

-- Errors a run may catch: frame code of the fake client failing where the
-- harness answers a frame size, scale or count read with a stub table (it
-- models no real frames). Each row is { context, file, message, clients }:
-- where the error was caught (an event, "timer", or the frame step of
-- FRAME_STEPS), the file it was raised in, its message without the line, and
-- the clients it occurs on ("*" for all five). Any other error fails the
-- corpus, a profile operation's error or refusal always does, and so does a
-- row that no longer occurs on a client it names (a full run of the client).
local ALL_CLIENTS = "*"
local MIDNIGHT = { Mainline = true }
local MAINLINE_FAMILY = { Mainline = true, Forever = true }
local CLASSIC_CLIENTS = { Vanilla = true, TBC = true, Mists = true }
local NUMBER_WITH_TABLE = "attempt to compare number with table"
local TABLE_WITH_NUMBER = "attempt to compare table with number"
Corpus.HARNESS_ERRORS = {
    { "PLAYER_LOGIN", "MSUF_UF_Text_Runtime.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
    { "PLAYER_LOGIN", "MSUF_UF_Group_Headers.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
    { "PLAYER_LOGIN", "MSUF_UF_Runtime.lua", TABLE_WITH_NUMBER, MAINLINE_FAMILY },
    { "timer", "MSUF_UF_Highlight.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
    { "timer", "MSUF_UF_RoundedSurface.lua", "'for' initial value must be a number", ALL_CLIENTS },
    { "Highlight.Refresh", "MSUF_UF_Highlight.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
    { "MSUF_UFCore_NotifyConfigChanged", "MSUF_UF_Text_Runtime.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
    { "MSUF_UFCore_NotifyConfigChanged", "MSUF_UF_Runtime.lua", TABLE_WITH_NUMBER, MAINLINE_FAMILY },
    { "MSUF_ApplyModules", "MSUF_UF_RoundedSurface.lua", "'for' initial value must be a number", ALL_CLIENTS },
    { "MSUF_ApplyModules", "MSUF_CP_Controller.lua", "bad argument #1 to 'math_floor' (number expected, got table)",
        MIDNIGHT },
    { "MSUF_GF_RebuildAll", "MSUF_UF_Group_Headers.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
    { "MSUF_ClassPower_Apply", "MSUF_CP_Controller.lua", "bad argument #1 to 'math_floor' (number expected, got table)",
        MIDNIGHT },
    { "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_UF_Text_Runtime.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
    { "MSUF_Castbars_OnSettingsChanged", "MSUF_CastbarAnchors.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
    { "MSUF_ApplyAllCastbarsAndSync", "MSUF_CastbarAnchors.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
    { "MSUF_RefreshAllUnitAlphas", "MSUF_UF_Text_Runtime.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
    { "MSUF_Auras3.RefreshAll", "MSUF_UF_Text_Runtime.lua", NUMBER_WITH_TABLE, CLASSIC_CLIENTS },
    { "GF.Rebuild", "MSUF_UF_Group_Headers.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
    { "GF.RefreshVisuals", "MSUF_UF_Group_Headers.lua", NUMBER_WITH_TABLE, ALL_CLIENTS },
}

local function ErrorText(caught)
    return caught.context .. " | " .. caught.file .. " | " .. caught.message
end

-- The allowlist row a caught error matches on this client, or nil.
local function AllowedError(flavor, caught)
    for index, row in ipairs(Corpus.HARNESS_ERRORS) do
        if row[1] == caught.context and row[2] == caught.file and row[3] == caught.message
            and (row[4] == ALL_CLIENTS or row[4][flavor]) then
            return index
        end
    end
    return nil
end

local function IsVolatile(path)
    for _, rule in ipairs(Corpus.VOLATILE) do
        if path:find(rule[1]) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Canonical serialization
---------------------------------------------------------------------------

-- The shortest text that reads back as the same double. "%d" only below 2^31
-- (Lua 5.1 formats it through a C long, 32 bits on Windows); the exponent loses
-- its leading zeros so Windows ("e+015") and other C runtimes ("e+15") agree.
local function FormatNumber(value)
    if value ~= value then return "nan" end
    if value == math.huge then return "inf" end
    if value == -math.huge then return "-inf" end
    if value % 1 == 0 and math.abs(value) < 2 ^ 31 then return string.format("%d", value) end
    local text
    for digits = 14, 17 do
        text = string.format("%." .. digits .. "g", value)
        if tonumber(text) == value then break end
    end
    return (text:gsub("e([%+%-])0*(%d)", "e%1%2"))
end

local function FormatString(value)
    return '"' .. value:gsub('[%c"\\]', function(c)
        if c == "\n" then return "\\n" end
        if c == "\r" then return "\\r" end
        if c == "\t" then return "\\t" end
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        return string.format("\\%03d", c:byte())
    end) .. '"'
end

local function FormatScalar(value)
    local kind = type(value)
    if kind == "string" then return FormatString(value) end
    if kind == "number" then return FormatNumber(value) end
    if kind == "boolean" then return value and "true" or "false" end
    return nil
end
Corpus.FormatScalar = FormatScalar

local function KeyText(key)
    if type(key) == "string" and key:match("^[%a_][%w_]*$") then return "." .. key end
    return "[" .. (FormatScalar(key) or ("<" .. type(key) .. ">")) .. "]"
end

local function SortedKeys(t)
    local keys = {}
    for key in pairs(t) do
        local kind = type(key)
        if kind == "string" or kind == "number" or kind == "boolean" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "boolean" then return (a and 1 or 0) < (b and 1 or 0) end
        return a < b
    end)
    return keys
end
Corpus.SortedKeys = SortedKeys

-- value -> { [relative path] = literal }, plus the paths in canonical order.
-- Functions and userdata are skipped; an empty table is the literal "{}".
local function Flatten(value)
    local map, order = {}, {}
    local active = {}
    local function Visit(node, path)
        local kind = type(node)
        if kind ~= "table" then
            local literal = FormatScalar(node)
            if literal then
                map[path], order[#order + 1] = literal, path
            end
            return
        end
        if active[node] then
            map[path], order[#order + 1] = "<cycle>", path
            return
        end
        local keys = SortedKeys(node)
        local written = 0
        active[node] = true
        for _, key in ipairs(keys) do
            local inner = node[key]
            local innerKind = type(inner)
            if innerKind == "table" or FormatScalar(inner) then
                written = written + 1
                Visit(inner, path .. KeyText(key))
            end
        end
        active[node] = nil
        if written == 0 then map[path], order[#order + 1] = "{}", path end
    end
    if value ~= nil then Visit(value, "") end
    return map, order
end
Corpus.Flatten = Flatten

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, inner in pairs(value) do out[key] = Copy(inner) end
    return out
end
Corpus.Copy = Copy

---------------------------------------------------------------------------
-- Files
---------------------------------------------------------------------------

local function ReadFile(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end

local function WriteFile(path, text)
    local handle = assert(io.open(path, "wb"), "cannot write " .. path)
    handle:write(text)
    handle:close()
end

-- A SavedVariables fixture: a Lua chunk that assigns MSUF_DB/MSUF_GlobalDB.
-- MSUF_FIXTURE_COPY(t) is a deep copy (the client writes MSUF_DB and the
-- active profile as two equal tables).
function Corpus.LoadSavedVariablesFixture(root, relative)
    local env = { MSUF_FIXTURE_COPY = Copy }
    local chunk = assert(loadfile(root .. "/" .. relative))
    setfenv(chunk, env)
    chunk()
    env.MSUF_FIXTURE_COPY = nil
    local saved = {}
    for name, value in pairs(env) do saved[name] = value end
    return saved
end

-- A profile-string fixture: the string wrapped at 120 characters; the line
-- breaks are not part of it.
function Corpus.ReadImportFixture(root, relative)
    local text = assert(ReadFile(root .. "/" .. relative), "missing import fixture " .. relative)
    return (text:gsub("[\r\n]", ""))
end

function Corpus.Manifest(root)
    return assert(loadfile(root .. "/" .. FIXTURES .. "/corpus.lua"))()
end

---------------------------------------------------------------------------
-- The client world
---------------------------------------------------------------------------

local chunkCache, graphCache = {}, {}
local World, Emulator

local function LoadCachedFile(world, path, addonName, namespace)
    local chunk = chunkCache[path]
    if chunk == nil then
        local compiled, compileError = loadfile(path)
        if not compiled then return false, "does not compile: " .. tostring(compileError) end
        chunk = compiled
        chunkCache[path] = chunk
    end
    setfenv(chunk, world.env)
    world.loading = path
    local ok, runError = pcall(chunk, addonName, namespace)
    world.loading = nil
    if not ok then return false, tostring(runError) end
    if path:match("/State/MSUF_ProfileRuntime%.lua$") then
        -- The runtime apply after a profile change runs for real; this only
        -- counts its calls. State/MSUF_Profiles.lua keeps the function it finds
        -- here when it loads, so the counter goes in before that file runs.
        local runtime = namespace.ProfileRuntime
        local apply = runtime.Apply
        world.runtimeApplies = {}
        runtime.Apply = function(reason, ...)
            world.runtimeApplies[#world.runtimeApplies + 1] = tostring(reason)
            return apply(reason, ...)
        end
    end
    return true
end

-- An error a run caught: where it was caught (context), the file it was
-- raised in and its message without the line number (lines move with any
-- edit; the file and the message identify the failure).
local function NoteError(world, context, message)
    message = tostring(message)
    local file, text = message:match("^.-([%w_]+%.lua):%d+: (.*)$")
    world.isolated[#world.isolated + 1] = { context = context, file = file or "?", message = text or message }
end

-- Every handler of one event, each isolated like the client's error handler.
local function Dispatch(world, event, ...)
    local frames = world.widgets.frames
    for index = 1, #frames do
        local frame = frames[index]
        local events = rawget(frame, "events")
        local scripts = rawget(frame, "scripts")
        local handler = scripts and scripts.OnEvent
        if handler and events and (events[event] or events["*"]) then
            local ok, message = pcall(handler, frame, event, ...)
            if not ok then NoteError(world, event, message) end
        end
    end
end

-- The next frame: every queued C_Timer callback (and the ones they queue).
local function RunFrameTimers(world)
    local timers = world.widgets.timers
    local ran = 0
    while #timers > 0 and ran < 500 do
        local entry = table.remove(timers, 1)
        ran = ran + 1
        if not entry.cancelled and type(entry.callback) == "function" then
            local ok, message = pcall(entry.callback)
            if not ok then NoteError(world, "timer", message) end
        end
    end
end

function Corpus.NewWorld(root, flavor, character)
    World = World or assert(loadfile(root .. "/tools/tests/client_world.lua"))()
    Emulator = Emulator or assert(loadfile(root .. "/tools/tests/encoding_util_emulator.lua"))()
    local world = World.New(root, flavor)
    world.isolated = {}
    world.LoadFile = LoadCachedFile
    -- A frame parented to a global the harness does not model has the
    -- permissive stub as its parent, whose parent is the stub again; the
    -- shared widget's walk up the parent chain would never end. Stop at the
    -- first parent that is not a harness widget.
    world.widgets.Methods.GetEffectiveScale = function(self)
        local scale, parent, seen = rawget(self, "scale") or 1, rawget(self, "parent"), {}
        while type(parent) == "table" and rawget(parent, "__env") ~= nil and not seen[parent] do
            seen[parent] = true
            scale = scale * (rawget(parent, "scale") or 1)
            parent = rawget(parent, "parent")
        end
        return scale
    end
    local env = world.env
    -- Globals the login handlers read that the harness leaves as stubs.
    env.MAX_TOTEMS, env.MAX_BOSS_FRAMES = 4, 5
    env.TotemFrame = false
    env.time = function() return FROZEN_TIME end
    env.GetServerTime = env.time
    env.C_EncodingUtil = Emulator.New()
    env.Enum = setmetatable({
        CompressionMethod = Emulator.CompressionMethod,
        CompressionLevel = Emulator.CompressionLevel,
    }, { __index = function() return World.Stub end })
    local name, realm = character:match("^(.-)%-(.*)$")
    env.UnitName = function() return name, nil end
    env.GetRealmName = function() return realm end
    local suffix = world.client.tocSuffix or flavor
    local graphKey = suffix .. (world.client.isForever and "/camelot" or "")
    graphCache[graphKey] = graphCache[graphKey]
        or World.Graph(world.root, World.CoreTOC(suffix), "enUS", world.client.isForever and "camelot" or nil)
    world.corePaths = graphCache[graphKey]
    world:LoadGraph("MidnightSimpleUnitFrames", world.corePaths, world.core)
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": core load failed in " .. tostring(failure and failure.file)
        .. ": " .. tostring(failure and failure.message))
    assert(world.runtimeApplies, flavor .. ": State/MSUF_ProfileRuntime.lua did not load; the corpus records"
        .. " MSUF.ProfileRuntime.Apply instead of fanning out to frames (LoadCachedFile)")
    return world
end

-- Frame steps of the profile paths: the runtime apply after a profile change
-- (State/MSUF_ProfileRuntime.lua) and the repaints the import calls after its
-- commit. They run for real, and so do the lazy defaults inside them (class
-- power config, aura and group frame fills), but each runs isolated, the way
-- the client's error handler isolates a failing frame script: the harness
-- models no real frames, so some of them fail part way. Every failure is
-- checked against Corpus.HARNESS_ERRORS. The State steps of the apply (variant
-- resolution, sync activation, cache invalidation, number format, locale) are
-- not wrapped: their errors fail the profile operation that ran them.
local FRAME_STEPS = {
    { nil, { "MSUF_ApplyMsufScale", "MSUF_ApplyCurrentProfileGlobalUiScale", "MSUF_TargetSoundDriver_ApplySetting",
        "MSUF_NSRTNicknames_ApplySetting", "MSUF_EllesmereEditMode_SetEnabled", "MSUF_Grid2EditMode_SetEnabled",
        "MSUF_DetailsEditMode_SetEnabled", "MSUF_DominosEditMode_SetEnabled", "MSUF_DandersEditMode_SetEnabled",
        "MSUF_BlizzardEditMode_SetEnabled", "MSUF_UFCore_NotifyConfigChanged", "MSUF_ApplyModules", "MSUF_GF_RebuildAll",
        "MSUF_ClassPower_Apply", "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_Castbars_OnSettingsChanged",
        "MSUF_ApplyAllCastbarsAndSync", "MSUF_UpdateAllFonts_Immediate", "MSUF_RefreshAllUnitAlphas",
        "MSUF_RequestAlphaRefresh", "MSUF_BlizzardEditMode_ApplyProfileSnapshot" } },
    { "UF", { "DisableBlizzardFrames" } },
    { "Tooltips", { "Refresh" } },
    { "Highlight", { "Refresh" } },
    { "TooltipSpellIDs", { "Apply", "ApplyCasterNames" } },
    { "SwingTimer", { "Apply" } },
    { "MinimapButton", { "RefreshProfileBinding" } },
    { "", { "MSUF_ApplyGameplayVisuals" } },
    { "MSUF_Auras3", { "ApplyFontsFromGlobal", "RequestScope", "RefreshUnit", "RefreshAll" } },
    { "GF", { "Rebuild", "RefreshGeometry", "RefreshUnitBindings", "RefreshVisuals", "RequestAuraRefresh", "MarkAllDirty" } },
}

local function InstallFrameIsolation(world)
    local function Isolated(label, fn)
        return function(...)
            local results = { pcall(fn, ...) }
            if not results[1] then
                NoteError(world, label, results[2])
                return
            end
            return unpack(results, 2, table.maxn(results))
        end
    end
    for _, step in ipairs(FRAME_STEPS) do
        local owner, names = step[1], step[2]
        local target = owner == nil and world.env or (owner == "" and world.core or world.core[owner])
        if type(target) == "table" then
            for _, name in ipairs(names) do
                -- Bootstrap's ExportPublic semantics: every export lives in the
                -- namespace registry (MSUF.PublicGlobals[name] and MSUF.Public[key],
                -- which Require/Optional and direct readers use) and in the global
                -- table only when its keep policy publishes it there. Wrap every
                -- place that holds the same export.
                local registry = owner == nil and world.core.PublicGlobals or nil
                local public = owner == nil and world.core.Public or nil
                local key = name:sub(1, 5) == "MSUF_" and name:sub(6) or name
                local fn = owner == nil and (rawget(target, name) or (type(registry) == "table" and rawget(registry, name)))
                    or target[name]
                if type(fn) == "function" then
                    local label = (owner and owner ~= "" and owner .. "." or "") .. name
                    if owner == nil then
                        local wrapped = Isolated(label, fn)
                        if rawget(target, name) == fn then rawset(target, name, wrapped) end
                        if type(registry) == "table" and rawget(registry, name) == fn then registry[name] = wrapped end
                        if type(public) == "table" and rawget(public, key) == fn then public[key] = wrapped end
                    else
                        target[name] = Isolated(label, fn)
                    end
                end
            end
        end
    end
end

-- The pass export and variant recording run before they read a profile
-- (State/MSUF_Profiles.lua MSUF_ProfileIO_EnsureCompleteProfileDB): the
-- defaults pass plus the lazily filled domains (unit alpha, group frames,
-- auras). In the client the frames run these fills when they build; here they
-- run explicitly after every bind, so a recorded profile is complete whether
-- or not a frame was built.
local function CompleteBoundProfile(world)
    local complete = world.core.ProfileIOEnsureCompleteProfileDB
    assert(type(complete) == "function", "MSUF.ProfileIOEnsureCompleteProfileDB is missing")
    local ok, message = pcall(complete)
    if not ok then NoteError(world, "complete pass", message) end
end

-- ADDON_LOADED with the saved globals, then PLAYER_LOGIN and the next frame.
function Corpus.Login(world, saved)
    -- The native client isolates every frame's ADDON_LOADED handler too.
    -- Keep failures observable through NoteError, as for PLAYER_LOGIN below.
    for name, value in pairs(saved or {}) do rawset(world.env, name, value) end
    Dispatch(world, "ADDON_LOADED", "MidnightSimpleUnitFrames", false)
    Dispatch(world, "PLAYER_LOGIN")
    RunFrameTimers(world)
    InstallFrameIsolation(world)
    CompleteBoundProfile(world)
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

-- One recorded subtree: name (the path prefix), value, and its reference (see
-- ReferenceMap): nil, { record = <subtree> }, { input = <table>, fallback = ... }
-- or { choice = { <reference>, <reference> } }.
local function Subtree(run, name, value, reference)
    run.subtrees[#run.subtrees + 1] = { name = name, value = value, reference = reference }
    run.byName[name] = run.subtrees[#run.subtrees]
end

local function ProfileName(name) return "profile[" .. FormatString(name) .. "]" end

local function Pool(env)
    local names = {}
    for name, profile in pairs(env.MSUF_GlobalDB.profiles or {}) do
        if type(name) == "string" and type(profile) == "table" then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

-- A profile API call, isolated: { ok, results... }. Its chat lines stay in
-- world.prints (the client_world sandbox's print).
local function Call(fn, ...)
    return { pcall(fn, ...) }
end

-- A profile operation that must succeed (create, switch, reset, delete): an
-- error or a refusal is a run error, and no allowlist entry covers it.
local function Must(world, label, fn, ...)
    local results = Call(fn, ...)
    if not results[1] then
        NoteError(world, label, results[2])
    elseif results[2] ~= true then
        NoteError(world, label, "refused: " .. tostring(results[3]))
    end
    return results
end

-- Export the bound profile, import the string into a new profile, compare.
local function RoundTrip(world, run, name)
    local env = world.env
    local source = env.MSUF_GlobalDB.profiles[name]
    local before = Flatten(Corpus.Effective(source, Defaults(world)))
    -- Namespace-only exports (Kernel/MSUF_Bootstrap.lua keep policy): the registry.
    local exported = Call(world.core.PublicGlobals.MSUF_ExportSelectionToString, "all")
    local result = {}
    if not exported[1] or type(exported[2]) ~= "string" then
        result.export = "failed: " .. tostring(exported[2])
        run.roundTripFailures[#run.roundTripFailures + 1] = name .. ": export " .. result.export
        return result
    end
    local after = Flatten(Corpus.Effective(source, Defaults(world)))
    local mutated = 0
    for path, literal in pairs(after) do if before[path] ~= literal then mutated = mutated + 1 end end
    for path in pairs(before) do if after[path] == nil then mutated = mutated + 1 end end
    if mutated > 0 then result.exportChangedSource = mutated end
    local imported = Call(world.core.PublicGlobals.MSUF_ImportIntoNewProfile, "__roundtrip", exported[2])
    if not imported[1] or imported[2] ~= true then
        result.import = "failed: " .. tostring(imported[3] or imported[2])
        run.roundTripFailures[#run.roundTripFailures + 1] = name .. ": import " .. result.import
    else
        CompleteBoundProfile(world)
        local copy = Flatten(Corpus.Effective(env.MSUF_GlobalDB.profiles.__roundtrip, Defaults(world)))
        local differences = {}
        for path, literal in pairs(after) do
            if copy[path] ~= literal then
                differences[path] = { kind = copy[path] == nil and "dropped" or "changed",
                    text = literal .. " -> " .. tostring(copy[path] or "nil") }
            end
        end
        for path, literal in pairs(copy) do
            if after[path] == nil then differences[path] = { kind = "added", text = "nil -> " .. literal } end
        end
        for path, difference in pairs(differences) do
            local rule
            for _, candidate in ipairs(Corpus.ROUNDTRIP_EXCEPTIONS) do
                if not rule and path:find(candidate[2]) and (candidate[3] == "any" or candidate[3] == difference.kind) then
                    rule = candidate[1]
                end
            end
            if rule then
                result.excepted = result.excepted or {}
                result.excepted[path] = rule .. " " .. difference.kind .. ": " .. difference.text
            else
                run.roundTripFailures[#run.roundTripFailures + 1] = name .. path .. ": " .. difference.text
                result.differences = result.differences or {}
                result.differences[path] = difference.text
            end
        end
    end
    Must(world, "MSUF_SwitchProfile", env.MSUF_SwitchProfile, name)
    if env.MSUF_GlobalDB.profiles.__roundtrip then Must(world, "MSUF_DeleteProfile", env.MSUF_DeleteProfile, "__roundtrip") end
    if next(result) == nil then return "identical" end
    return result
end

-- Account table, bindings and resolutions right after the login.
local function RecordAccount(world, run, input, character)
    local env = world.env
    local globalDB = env.MSUF_GlobalDB
    local inputDB = input.MSUF_GlobalDB or {}
    local pool = Pool(env)
    Subtree(run, "login", {
        character = character,
        activeProfile = env.MSUF_ActiveProfile,
        boundDBIsActiveProfile = env.MSUF_DB == globalDB.profiles[env.MSUF_ActiveProfile],
        pool = Copy(pool),
    })
    local archive = type(globalDB.ignoredPre6Profiles) == "table" and globalDB.ignoredPre6Profiles or {}
    -- What exists after the login: every account key, archived profile and
    -- profile, listed in full, so a table that disappears is a difference.
    Subtree(run, "exists", { account = SortedKeys(globalDB), archive = SortedKeys(archive), profiles = Copy(pool) })
    Subtree(run, "global", Copy(globalDB.global), { input = inputDB.global })
    Subtree(run, "char", Copy(globalDB.char), { input = inputDB.char })
    -- Every account key of the input or the output: a key the login dropped
    -- lists the values it lost.
    local keys = {}
    for _, source in ipairs({ globalDB, inputDB }) do
        for _, key in ipairs(SortedKeys(source)) do keys[key] = true end
    end
    for _, key in ipairs(SortedKeys(keys)) do
        if key ~= "profiles" and key ~= "char" and key ~= "global" and key ~= "ignoredPre6Profiles" then
            Subtree(run, "account" .. KeyText(key), Copy(globalDB[key]), { input = inputDB[key] })
        end
    end
    for _, name in ipairs(SortedKeys(archive)) do
        local original = name == "__standalone" and input.MSUF_DB or (inputDB.profiles or {})[name]
        Subtree(run, "archive[" .. FormatString(name) .. "]", Copy(archive[name]), { input = original })
    end
    local resolved = {}
    local characters = SortedKeys(globalDB.char or {})
    characters[#characters + 1] = NEW_CHARACTER
    -- The profile name a login of each character binds, and the stored table
    -- it starts from (a missing name is created from that table).
    for _, key in ipairs(characters) do
        local name, source = world.core.ResolveStartupProfile(globalDB, env.MSUF_DB, key)
        local sourceName = "none"
        for profileName, profile in pairs(globalDB.profiles or {}) do
            if profile == source then sourceName = profileName end
        end
        if source ~= nil and source == env.MSUF_DB and sourceName == "none" then sourceName = "MSUF_DB" end
        resolved[key] = tostring(name) .. " <- " .. sourceName
    end
    Subtree(run, "resolve", resolved)
    return pool
end

-- Bind each profile with the real switch API, then round-trip it. The profile
-- the login bound goes first, the others in name order.
local function RecordProfiles(world, run, pool, referenceOf, roundTripsFor)
    local env = world.env
    local login = env.MSUF_ActiveProfile
    local loginView = login and Flatten(Corpus.Effective(env.MSUF_DB, Defaults(world))) or nil
    local roundTrips = {}
    local ordered = {}
    for _, name in ipairs(pool) do if name == login then ordered[#ordered + 1] = name end end
    for _, name in ipairs(pool) do if name ~= login then ordered[#ordered + 1] = name end end
    for _, name in ipairs(ordered) do
        Must(world, "MSUF_SwitchProfile", env.MSUF_SwitchProfile, name)
        CompleteBoundProfile(world)
        Subtree(run, ProfileName(name), Copy(Corpus.Effective(env.MSUF_GlobalDB.profiles[name], Defaults(world))),
            referenceOf(name))
        if name == login and loginView then
            local now = Flatten(Corpus.Effective(env.MSUF_GlobalDB.profiles[name], Defaults(world)))
            local changed = 0
            for path, literal in pairs(now) do if loginView[path] ~= literal then changed = changed + 1 end end
            for path in pairs(loginView) do if now[path] == nil then changed = changed + 1 end end
            run.byName.login.value.rebindChangedPaths = changed
        end
        if roundTripsFor == nil or roundTripsFor(name) then roundTrips[name] = RoundTrip(world, run, name) end
    end
    Subtree(run, "roundtrip", roundTrips)
end

local function NewRun(root, entry, flavor)
    return { root = root, entry = entry, flavor = flavor, subtrees = {}, byName = {}, roundTripFailures = {} }
end

-- A stored profile has two candidate references, and the golden file uses
-- the one that lists fewer lines (an "@overlay" line names the second): its
-- stored table alone, or its stored values over the values a fresh install of
-- the same client has (the factory entry's first-login Default, read from
-- factory.golden). The second lists what loading did beyond "keep what was
-- stored, fill the rest like a new install".
local FACTORY_DEFAULT = { golden = "factory", subtree = 'profile["Default"]' }

local function RunSavedVariablesEntry(root, entry, flavor)
    local input = Corpus.LoadSavedVariablesFixture(root, entry.file)
    local world = Corpus.NewWorld(root, flavor, entry.login)
    Corpus.Login(world, Corpus.LoadSavedVariablesFixture(root, entry.file))
    local run = NewRun(root, entry, flavor)
    run.world = world
    local pool = RecordAccount(world, run, input, entry.login)
    local stored = (input.MSUF_GlobalDB or {}).profiles or {}
    local archive = world.env.MSUF_GlobalDB.ignoredPre6Profiles or {}
    RecordProfiles(world, run, pool, function(name)
        -- A pre-6 profile of the same name went to the archive; this one is new.
        local own = archive[name] == nil and stored[name] or nil
        return { choice = { { input = own }, { input = own, fallback = FACTORY_DEFAULT } } }
    end)
    return run
end

local FACTORY_CHARACTER = "Char01-Realm01"

-- LibDeflate's print-safe alphabet (6 bits a character, least significant
-- first), the Wago transport an MSUF2 string may use.
local PRINT_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz()"
local function DecodeForPrint(text)
    local out, accumulator, bits = {}, 0, 0
    for index = 1, #text do
        local value = PRINT_ALPHABET:find(text:sub(index, index), 1, true)
        if not value then return nil end
        accumulator = accumulator + (value - 1) * 2 ^ bits
        bits = bits + 6
        while bits >= 8 do
            local low = accumulator % 256
            out[#out + 1] = string.char(low)
            accumulator = (accumulator - low) / 256
            bits = bits - 8
        end
    end
    return table.concat(out)
end

-- The table an import string carries, decoded by the corpus itself (the
-- emulator's raw codecs, never the addon's codec), so a codec change cannot
-- move the reference along with the result. The text form is read as a Lua
-- table constructor in an empty environment (the fixture is trusted test data).
local function DecodeImportString(text)
    text = text:gsub("%s+", "")
    if text:sub(1, 1) == "{" then
        local chunk = loadstring("return " .. text)
        if not chunk then return nil end
        setfenv(chunk, {})
        local ok, value = pcall(chunk)
        return ok and value or nil
    end
    local prefix, body = text:match("^(MSUF[234]):(.*)$")
    if not prefix then return nil end
    local function FromBlob(blob)
        local inflated, plain = pcall(Emulator.Container.Decompress, blob, 0)
        if inflated then
            local ok, value = pcall(Emulator.CBOR.Deserialize, plain)
            if ok then return value end
        end
        local ok, value = pcall(Emulator.CBOR.Deserialize, blob)
        return ok and value or nil
    end
    local padded = body .. string.rep("=", (4 - #body % 4) % 4)
    local blob = #body % 4 ~= 1 and Emulator.Base64.Decode(padded) or nil
    local value = blob and FromBlob(blob)
    if value == nil and prefix == "MSUF2" then
        local raw = DecodeForPrint(body)
        value = raw and FromBlob(raw)
    end
    return value
end

-- The profile table of a decoded import: the native section of a portable
-- envelope, a snapshot's payload, or a bare profile.
local function ImportPayload(text)
    local decoded = DecodeImportString(text)
    if type(decoded) ~= "table" then return nil end
    local native = decoded.msuf6
    if type(native) == "table" and tonumber(native.schema) == 600 and type(native.payload) == "table" then
        return native.payload
    end
    if decoded.addon == "MSUF" and type(decoded.payload) == "table" then return decoded.payload end
    return decoded
end

-- The digest that pins an import's reference table in the golden file: the
-- number of canonical paths and the Adler-32 of "path = value" lines.
local function PayloadDigest(payload)
    if payload == nil then return "undecodable" end
    local map, order = Flatten(payload)
    local lines = {}
    for _, path in ipairs(order) do lines[#lines + 1] = path .. " = " .. map[path] end
    return string.format("%d paths, Adler-32 %08x", #lines, Emulator.Checksums.Adler32(table.concat(lines, "\n")))
end

local function RunFactoryEntry(root, entry, flavor)
    local world = Corpus.NewWorld(root, flavor, FACTORY_CHARACTER)
    Corpus.Login(world, {})
    local env = world.env
    local run = NewRun(root, entry, flavor)
    run.world = world
    RecordAccount(world, run, {}, FACTORY_CHARACTER)
    local relativeToDefault = { record = ProfileName("Default") }
    -- A new profile, and a reset of the active and of a stored profile.
    Must(world, "MSUF_CreateProfile", env.MSUF_CreateProfile, "Created")
    Must(world, "MSUF_CreateProfile", env.MSUF_CreateProfile, "Reset Stored")
    Must(world, "MSUF_SwitchProfile", env.MSUF_SwitchProfile, "Default")
    Must(world, "MSUF_ResetProfile", env.MSUF_ResetProfile, "Reset Stored")
    local imports, payloads, digests = {}, {}, {}
    for _, import in ipairs(entry.imports or {}) do
        local text = Corpus.ReadImportFixture(root, import.file)
        local name = "Import " .. import.id
        payloads[name] = ImportPayload(text)
        digests[import.id] = PayloadDigest(payloads[name])
        local results = Call(world.core.PublicGlobals.MSUF_ImportIntoNewProfile, name, text)
        local outcome = { ok = results[1] and results[2] == true }
        if not results[1] then
            outcome.error = tostring(results[2])
        elseif results[2] ~= true then
            outcome.why, outcome.stage = tostring(results[3]), tostring(results[4])
        end
        outcome.created = type(env.MSUF_GlobalDB.profiles[name]) == "table"
        imports[import.id] = outcome
    end
    Subtree(run, "import", imports)
    Subtree(run, "importPayload", digests)
    local pool = Pool(env)
    run.byName.login.value.poolAfterImports = Copy(pool)
    -- Default first: every other profile of this entry is compared with it.
    Must(world, "MSUF_SwitchProfile", env.MSUF_SwitchProfile, "Default")
    -- An imported profile: the first-login Default, or the string's own
    -- profile table over that Default, whichever lists fewer lines. Imported
    -- profiles are not exported again (the stored profiles cover the round trip).
    RecordProfiles(world, run, pool, function(name)
        if name == "Default" then return nil end
        if payloads[name] == nil then return relativeToDefault end
        return { choice = { relativeToDefault, { input = payloads[name], fallback = relativeToDefault } } }
    end, function(name) return payloads[name] == nil end)
    -- Reset of the active profile last: it starts over from the factory profile.
    Must(world, "MSUF_SwitchProfile", env.MSUF_SwitchProfile, "Default")
    Must(world, "MSUF_ResetProfile", env.MSUF_ResetProfile, "Default")
    CompleteBoundProfile(world)
    Subtree(run, "resetActive", Copy(Corpus.Effective(env.MSUF_GlobalDB.profiles.Default, Defaults(world))),
        relativeToDefault)
    return run
end

-- One entry may take at most this many CPU seconds: product code that loops
-- on a harness stub must fail the smoke, not hang the gate.
local ENTRY_CPU_LIMIT = 60

function Corpus.RunEntry(root, entry, flavor)
    local runner = entry.kind == "sv" and RunSavedVariablesEntry or entry.kind == "factory" and RunFactoryEntry
    if not runner then error("unknown corpus entry kind " .. tostring(entry.kind)) end
    local deadline = os.clock() + ENTRY_CPU_LIMIT
    debug.sethook(function()
        if os.clock() > deadline then
            debug.sethook()
            error(entry.id .. " on " .. flavor .. " ran longer than " .. ENTRY_CPU_LIMIT .. " s of CPU", 2)
        end
    end, "", 1000000)
    local ok, run = pcall(runner, root, entry, flavor)
    debug.sethook()
    if not ok then error(run, 0) end
    return run
end

---------------------------------------------------------------------------
-- Golden files
---------------------------------------------------------------------------

-- The segments of a canonical path (".key", "[\"text\"]", "[3]"): returns the
-- path of every proper ancestor and a sort key per segment.
local function PathSegments(path)
    local ancestors, keys = {}, {}
    local index, length = 1, #path
    while index <= length do
        local first = index
        local char = path:sub(index, index)
        if char == "." then
            index = index + 1
            while index <= length and path:sub(index, index):match("[%w_]") do index = index + 1 end
            keys[#keys + 1] = { 2, path:sub(first + 1, index - 1) }
        elseif char == "[" then
            index = index + 1
            if path:sub(index, index) == '"' then
                index = index + 1
                while index <= length do
                    local inner = path:sub(index, index)
                    if inner == "\\" then
                        index = index + 2
                    elseif inner == '"' then
                        index = index + 1
                        break
                    else
                        index = index + 1
                    end
                end
                keys[#keys + 1] = { 2, path:sub(first + 2, index - 2) }
            else
                while index <= length and path:sub(index, index) ~= "]" do index = index + 1 end
                local text = path:sub(first + 1, index - 1)
                keys[#keys + 1] = tonumber(text) and { 1, tonumber(text) } or { 0, text }
            end
            index = index + 1
        else
            index = index + 1
        end
        if first > 1 then ancestors[#ancestors + 1] = path:sub(1, first - 1) end
    end
    return ancestors, keys
end

local function SortPaths(paths)
    local keyed = {}
    for _, path in ipairs(paths) do
        local _, keys = PathSegments(path)
        keyed[#keyed + 1] = { path = path, keys = keys }
    end
    table.sort(keyed, function(a, b)
        local ka, kb = a.keys, b.keys
        for index = 1, math.min(#ka, #kb) do
            local x, y = ka[index], kb[index]
            if x[1] ~= y[1] then return x[1] < y[1] end
            if x[2] ~= y[2] then return x[2] < y[2] end
        end
        if #ka ~= #kb then return #ka < #kb end
        return a.path < b.path
    end)
    for index, item in ipairs(keyed) do paths[index] = item.path end
    return paths
end

-- Stored values first; a fallback path enters only where the stored map has
-- neither that path, nor a value at one of its ancestors, nor a table below it.
local function Overlay(stored, fallback)
    local out, tables = {}, {}
    for path, literal in pairs(stored) do
        out[path] = literal
        for _, ancestor in ipairs((PathSegments(path))) do tables[ancestor] = true end
    end
    for path, literal in pairs(fallback) do
        if stored[path] == nil and not tables[path] then
            local covered = false
            for _, ancestor in ipairs((PathSegments(path))) do
                if stored[ancestor] ~= nil then covered = true end
            end
            if not covered then out[path] = literal end
        end
    end
    return out
end

local goldenCache = {}

-- Golden lines that apply to one client: { [full path] = literal }, and the
-- reference choices ("@overlay <subtree>" lines) as a set.
local function ReadGolden(root, id, client)
    local cacheKey = id .. "\0" .. client
    if goldenCache[cacheKey] then return goldenCache[cacheKey].lines, nil, goldenCache[cacheKey].choices end
    local text = ReadFile(root .. "/" .. FIXTURES .. "/golden/" .. id .. ".golden")
    if not text then return nil, "missing golden file golden/" .. id .. ".golden" end
    local lines, choices, section = {}, {}, nil
    for line in text:gsub("\r\n", "\n"):gmatch("[^\n]+") do
        if line:sub(1, 1) ~= "#" then
            local header = line:match("^%[([%w_]+)%]$")
            local choice = line:match("^@overlay (.+)$")
            if header then
                section = header
            elseif choice then
                choices[choice] = true
            elseif section == "common" or section == client then
                local path, literal = line:match("^(.-) = (.*)$")
                if not path then return nil, "unreadable golden line: " .. line end
                lines[path] = literal
            end
        end
    end
    goldenCache[cacheKey] = { lines = lines, choices = choices }
    return lines, nil, choices
end

-- The expected map of a self-contained subtree (no reference of its own) of
-- another golden file, e.g. the factory entry's first-login Default.
local function GoldenSubtree(root, id, client, name)
    local lines, problem = ReadGolden(root, id, client)
    assert(lines, problem)
    local map = {}
    for path, literal in pairs(lines) do
        if path:sub(1, #name) == name and literal ~= "nil" then
            local rest = path:sub(#name + 1)
            local nextChar = rest:sub(1, 1)
            if rest == "" or nextChar == "." or nextChar == "[" then map[rest] = literal end
        end
    end
    return map
end

-- Flattened reference of one subtree: none, an earlier subtree of this run,
-- or the input table, optionally over a fallback (a self-contained subtree of
-- another golden file, or an earlier subtree of this run). A reference with a
-- choice has two candidates; useSecond picks between them.
local function ReferenceMap(run, name, reference, expectedByName, useSecond)
    if reference == nil then return {} end
    if reference.choice then
        return ReferenceMap(run, name, reference.choice[useSecond and 2 or 1], expectedByName, false)
    end
    local function Recorded(other)
        return Copy(assert(expectedByName[other], name .. ": reference " .. other .. " was not recorded before it"))
    end
    if reference.record then return Recorded(reference.record) end
    local map = {}
    if reference.input ~= nil then
        map = Flatten(reference.input)
        if map[""] == "{}" then map[""] = nil end
    end
    local fallback = reference.fallback
    if fallback and fallback.record then
        map = Overlay(map, Recorded(fallback.record))
    elseif fallback then
        map = Overlay(map, GoldenSubtree(run.root, fallback.golden, run.flavor, fallback.subtree))
    end
    return map
end

local function Prune(map, prefix)
    for path in pairs(map) do
        if IsVolatile(prefix .. path) then map[path] = nil end
    end
    return map
end

-- Deltas of every subtree of a run against its reference, and, given golden
-- lines, the differences between the expected and the recorded maps. Without
-- lines (write mode) the expected map of a subtree is the recorded one.
-- useSecond(name) picks the second candidate of a reference with a choice.
local function Compare(run, lines, useSecond)
    local names = {}
    for _, subtree in ipairs(run.subtrees) do names[#names + 1] = subtree.name end
    table.sort(names, function(a, b) return #a > #b end)
    local bySubtree, differences = {}, {}
    for path, literal in pairs(lines or {}) do
        local owner
        for _, name in ipairs(names) do
            if not owner and path:sub(1, #name) == name then
                local nextChar = path:sub(#name + 1, #name + 1)
                if nextChar == "" or nextChar == "." or nextChar == "[" then owner = name end
            end
        end
        if not owner then
            differences[#differences + 1] = path .. ": in the golden file, but this run recorded no such subtree"
        else
            bySubtree[owner] = bySubtree[owner] or {}
            bySubtree[owner][path:sub(#owner + 1)] = literal
        end
    end
    local expectedByName, deltas = {}, {}
    for _, subtree in ipairs(run.subtrees) do
        local reference = Prune(ReferenceMap(run, subtree.name, subtree.reference, expectedByName,
            useSecond(subtree.name)), subtree.name)
        local actual, order = Flatten(subtree.value)
        actual = Prune(actual, subtree.name)
        local delta, size = {}, 0
        for path, literal in pairs(actual) do
            if reference[path] ~= literal then delta[path], size = literal, size + 1 end
        end
        for path in pairs(reference) do
            if actual[path] == nil then delta[path], size = "nil", size + 1 end
        end
        deltas[subtree.name] = { delta = delta, size = size }
        deltas[#deltas + 1] = subtree.name
        if lines then
            local expected = reference
            for path, literal in pairs(bySubtree[subtree.name] or {}) do
                if literal == "nil" then expected[path] = nil else expected[path] = literal end
            end
            local seen = {}
            for _, path in ipairs(order) do
                if actual[path] ~= nil then
                    seen[path] = true
                    if expected[path] ~= actual[path] then
                        differences[#differences + 1] = subtree.name .. path .. ": expected "
                            .. tostring(expected[path] or "nil") .. ", got " .. actual[path]
                    end
                end
            end
            local missing = {}
            for path in pairs(expected) do if not seen[path] then missing[#missing + 1] = path end end
            for _, path in ipairs(SortPaths(missing)) do
                differences[#differences + 1] = subtree.name .. path .. ": expected " .. expected[path] .. ", got nil"
            end
            expectedByName[subtree.name] = expected
        else
            expectedByName[subtree.name] = actual
        end
    end
    return differences, deltas
end

local function Always() return true end
local function Never() return false end

-- Write one entry's golden file from the runs of all its clients. A subtree
-- whose reference has a choice uses the candidate that lists fewer lines over
-- all clients.
function Corpus.WriteGolden(root, entry, runs)
    local byFirst, bySecond, order, seenName = {}, {}, {}, {}
    for _, client in ipairs(entry.clients) do
        local run = assert(runs[client], entry.id .. ": no run for " .. client)
        local _, firstCandidate = Compare(run, nil, Never)
        local _, secondCandidate = Compare(run, nil, Always)
        byFirst[client], bySecond[client] = firstCandidate, secondCandidate
        for _, name in ipairs(firstCandidate) do
            if not seenName[name] then
                seenName[name] = true
                order[#order + 1] = name
            end
        end
    end
    local first = entry.clients[1]
    local choices, deltas = {}, {}
    for _, client in ipairs(entry.clients) do deltas[client] = {} end
    for _, name in ipairs(order) do
        local firstSize, secondSize = 0, 0
        for _, client in ipairs(entry.clients) do
            firstSize = firstSize + ((byFirst[client][name] or {}).size or 0)
            secondSize = secondSize + ((bySecond[client][name] or {}).size or 0)
        end
        local useSecond = secondSize < firstSize
        if useSecond then choices[#choices + 1] = "@overlay " .. name end
        for _, client in ipairs(entry.clients) do
            local source = useSecond and bySecond[client][name] or byFirst[client][name]
            deltas[client][name] = source and source.delta or {}
        end
    end
    local commonLines, clientLines = {}, {}
    for _, client in ipairs(entry.clients) do clientLines[client] = {} end
    for _, name in ipairs(order) do
        local union = {}
        for _, client in ipairs(entry.clients) do
            for path in pairs(deltas[client][name]) do union[#union + 1] = path end
        end
        local done = {}
        for _, path in ipairs(SortPaths(union)) do
            if not done[path] then
                done[path] = true
                local literal = deltas[first][name][path]
                local shared = literal ~= nil
                for _, client in ipairs(entry.clients) do
                    if deltas[client][name][path] ~= literal then shared = false end
                end
                if shared then
                    commonLines[#commonLines + 1] = name .. path .. " = " .. literal
                else
                    for _, client in ipairs(entry.clients) do
                        local own = deltas[client][name][path]
                        if own ~= nil then clientLines[client][#clientLines[client] + 1] = name .. path .. " = " .. own end
                    end
                end
            end
        end
    end
    local out = {
        "# Golden effective settings of corpus entry " .. entry.id .. " (tools/fixtures/profiles/README.md).",
        "# Generated by tools/profile_corpus_golden.lua --write; regenerate only for a reviewed behaviour change.",
        "# A line is a path whose value differs from its reference (see the README); nil means absent.",
        "# @overlay <profile>: its reference is its own stored (or imported) table over the base it would",
        "# otherwise be compared with (a fresh install's Default).",
        "# [common] holds what every client of the entry shares, [<client>] the rest.",
    }
    for _, line in ipairs(choices) do out[#out + 1] = line end
    out[#out + 1] = "[common]"
    for _, line in ipairs(commonLines) do out[#out + 1] = line end
    local counts = {}
    for _, client in ipairs(entry.clients) do
        out[#out + 1] = "[" .. client .. "]"
        for _, line in ipairs(clientLines[client]) do out[#out + 1] = line end
        counts[#counts + 1] = client .. " " .. #clientLines[client]
    end
    -- CRLF, the line ending of the repository's worktree files.
    WriteFile(root .. "/" .. FIXTURES .. "/golden/" .. entry.id .. ".golden", table.concat(out, "\r\n") .. "\r\n")
    for key in pairs(goldenCache) do goldenCache[key] = nil end
    return #commonLines, table.concat(counts, ", ")
end

-- Compare one run with its golden file. Returns a list of differences.
function Corpus.Check(root, entry, run)
    local lines, problem, choices = ReadGolden(root, entry.id, run.flavor)
    if not lines then return { problem } end
    choices = choices or {}
    return (Compare(run, lines, function(name) return choices[name] == true end))
end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------

function Corpus.EntriesFor(root, flavor, only)
    local selected = {}
    for _, entry in ipairs(Corpus.Manifest(root)) do
        local runsHere = flavor == "all"
        for _, client in ipairs(entry.clients) do if client == flavor then runsHere = true end end
        if runsHere and (only == nil or only == entry.id) then selected[#selected + 1] = entry end
    end
    return selected
end

-- The errors of a run no allowlist row covers; marks the rows it used.
local function UnexpectedErrors(run, used)
    local unexpected, seen = {}, {}
    for _, caught in ipairs(run.world.isolated) do
        local index = AllowedError(run.flavor, caught)
        if index then
            used[index] = true
        elseif not seen[ErrorText(caught)] then
            seen[ErrorText(caught)] = true
            unexpected[#unexpected + 1] = ErrorText(caught)
        end
    end
    return unexpected
end
Corpus.UnexpectedErrors = UnexpectedErrors

local function Report(run, verbose)
    if not verbose then return end
    local world = run.world
    print(string.format("    %d runtime applies, %d caught errors, %d chat lines",
        #(world.runtimeApplies or {}), #world.isolated, #world.prints))
    for _, caught in ipairs(world.isolated) do print("    caught: " .. ErrorText(caught)) end
end

-- Check mode for one client. Returns the number of failing entries.
function Corpus.CheckClient(root, flavor, options)
    options = options or {}
    local failures, used = 0, {}
    for _, entry in ipairs(Corpus.EntriesFor(root, flavor, options.entry)) do
        local started = os.clock()
        local run = Corpus.RunEntry(root, entry, flavor)
        local differences = Corpus.Check(root, entry, run)
        local unexpected = UnexpectedErrors(run, used)
        local ok = #differences == 0 and #run.roundTripFailures == 0 and #unexpected == 0
        print(string.format("  %-28s %-8s %s (%.1f s)", entry.id, flavor, ok and "ok" or "FAILED", os.clock() - started))
        Report(run, options.verbose)
        if not ok then
            failures = failures + 1
            for index = 1, math.min(#differences, 40) do print("    " .. differences[index]) end
            if #differences > 40 then print("    ... and " .. (#differences - 40) .. " more differing paths") end
            for index = 1, math.min(#run.roundTripFailures, 40) do
                print("    round trip not identical: " .. run.roundTripFailures[index])
            end
            for _, text in ipairs(unexpected) do print("    error not in Corpus.HARNESS_ERRORS: " .. text) end
        end
    end
    -- A full run of the client must still meet every allowlist row it names.
    if options.entry == nil then
        for index, row in ipairs(Corpus.HARNESS_ERRORS) do
            if not used[index] and (row[4] == ALL_CLIENTS or row[4][flavor]) then
                failures = failures + 1
                print("  stale Corpus.HARNESS_ERRORS row on " .. flavor .. ": " .. row[1] .. " | " .. row[2] .. " | " .. row[3])
            end
        end
    end
    return failures
end

function Corpus.WriteAll(root, options)
    options = options or {}
    for _, entry in ipairs(Corpus.EntriesFor(root, "all", options.entry)) do
        local runs = {}
        local refusals = {}
        for _, client in ipairs(entry.clients) do
            runs[client] = Corpus.RunEntry(root, entry, client)
            Report(runs[client], options.verbose)
            for _, failure in ipairs(runs[client].roundTripFailures) do
                refusals[#refusals + 1] = client .. " round trip not identical: " .. failure
            end
            for _, text in ipairs(UnexpectedErrors(runs[client], {})) do
                refusals[#refusals + 1] = client .. " error not in Corpus.HARNESS_ERRORS: " .. text
            end
        end
        if #refusals > 0 then
            for index = 1, math.min(#refusals, 40) do print("    " .. refusals[index]) end
            error(entry.id .. ": fix these, or except or allow them on purpose, before writing", 0)
        end
        local common, counts = Corpus.WriteGolden(root, entry, runs)
        print(string.format("  wrote %-28s common %d; %s", entry.id, common, counts))
    end
end

local function Main(arguments)
    local root = assert(arguments[1], "usage: profile_corpus_golden.lua <repo root> <flavor|all> [--write] [--entry <id>] [--verbose]")
    root = root:gsub("\\", "/"):gsub("/$", "")
    local flavor = assert(arguments[2], "flavor required (a matrix client, Forever, or all)")
    local options = {}
    local index = 3
    while arguments[index] do
        local flag = arguments[index]
        if flag == "--write" then options.write = true
        elseif flag == "--verbose" then options.verbose = true
        elseif flag == "--entry" then
            index = index + 1
            options.entry = arguments[index]
        else error("unknown argument " .. flag) end
        index = index + 1
    end
    if options.write then
        assert(flavor == "all", "--write regenerates every client of an entry; pass all")
        Corpus.WriteAll(root, options)
        return 0
    end
    local flavors = { flavor }
    if flavor == "all" then
        World = World or assert(loadfile(root .. "/tools/tests/client_world.lua"))()
        flavors = World.Flavors(root)
    end
    local failures = 0
    for _, client in ipairs(flavors) do failures = failures + Corpus.CheckClient(root, client, options) end
    return failures
end
Corpus.Main = Main

-- Run as a script (not when another file loads this one as a module).
if arg and arg[0] and arg[0]:match("profile_corpus_golden%.lua$") then
    local failures = Main(arg)
    if failures > 0 then
        print("profile corpus: " .. failures .. " entr" .. (failures == 1 and "y" or "ies") .. " differ from the golden files")
        os.exit(1)
    end
end

return Corpus
