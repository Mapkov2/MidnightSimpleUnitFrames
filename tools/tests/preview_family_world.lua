-- Compare the actual frozen original family owner with the shipped real graph.
local root, flavor, sourceRoot, oldRoot = ...
sourceRoot = sourceRoot or root
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
local oldFile = root .. "/tools/fixtures/preview/LoadConditions.baseline.lua"
-- Compile each exact source once, but instantiate it anew in every graph.
-- No namespace, tables, frames or executed chunk is shared between worlds.
local bytecode = {}
local function Compile(path)
    local binary = bytecode[path]
    if not binary then
        local chunk, message = loadfile(path)
        if not chunk then return nil, message end
        binary = string.dump(chunk)
        bytecode[path] = binary
    end
    return loadstring(binary)
end
-- Route only this fixture module's nested loads through the compilation cache.
-- Its widget/manifest chunks still execute anew for every fresh world.
local worldChunk = assert(Compile(root .. "/tools/tests/client_world.lua"))
setfenv(worldChunk, setmetatable({ loadfile = Compile }, { __index = getfenv(worldChunk) }))
local World = worldChunk()
local activeCalls
local queryHookActive, priorHook, priorMask, priorCount
local function Observe(name, native)
    return function(...)
        if activeCalls then
            local queries = activeCalls.queries
            queries[name] = (queries[name] or 0) + 1
            activeCalls.queryTotal = activeCalls.queryTotal + 1
        end
        return native(...)
    end
end
local function ObserveQueries(env)
    -- Model every client API and C library invocation reached by the graph.
    -- Observation is enabled only in the separate native process, never heap/VM.
    for name, value in pairs(env) do
        if type(value) == "function" and not name:find("MSUF", 1, true)
            and not ({ type = true, tonumber = true, tostring = true, pairs = true, ipairs = true,
                next = true, select = true, unpack = true })[name] then
            env[name] = Observe(name, value)
        end
    end
    for _, name in ipairs({ "type", "tonumber", "tostring", "pairs", "ipairs", "next", "select", "unpack" }) do
        env[name] = Observe(name, env[name] or _G[name])
    end
    for _, name in ipairs({ "math", "string", "table" }) do
        local library = {}
        for key, value in pairs(_G[name]) do
            library[key] = type(value) == "function" and Observe(name .. "." .. key, value) or value
        end
        env[name] = library
    end
    for name, value in pairs(env) do
        if type(value) == "table" and (name:match("^C_") or name == "bit") then
            for key, method in pairs(value) do
                if type(method) == "function" then value[key] = Observe(name .. "." .. key, method) end
            end
        end
    end
end
local function New(original, cold, queries)
    local w = World.New(original and (oldRoot or sourceRoot) or sourceRoot, flavor)
    local env = w.env
    env.issecretvalue = Secrets.IsSecret
    env.MAX_BOSS_FRAMES = 5
    env.time = function(value) return value == nil and 1234567890 or os.time(value) end
    env.date = function(format, timestamp)
        return os.date(format == nil and "%c" or format, timestamp == nil and 1234567890 or timestamp)
    end
    local live = {}
    env.UnitExists = function(unit) return live[unit] == true end
    for name, value in pairs({ UnitHealth = 500000, UnitHealthMax = 1000000, UnitPower = 240000, UnitPowerMax = 240000,
        UnitPowerType = 0, UnitGetTotalAbsorbs = 0, UnitGetIncomingHeals = 0, UnitGetTotalHealAbsorbs = 0,
        UnitEffectiveLevel = 90, UnitHealthPercent = 50, UnitPowerPercent = 100,
        GetMaxPlayerLevel = 90, GetMaxLevelForPlayerExpansion = 90 }) do env[name] = function() return value end end
    env.GetRaidTargetIndex = function() return nil end
    env.hasanysecretvalues = function() return false end
    env.AbbreviateNumbers, env.AbbreviateLargeNumbers = tostring, tostring
    env.C_StringUtil = { AbbreviateNumbers = tostring, AbbreviateLargeNumbers = tostring }
    env.C_ClassColor = { GetClassColor = function() return nil end }
    env.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", ROGUE = "Rogue", PRIEST = "Priest", WARRIOR = "Warrior", DRUID = "Druid" }
    env.UnitReaction = function() return 2 end
    env.UnitClassification = function() return "normal" end
    env.UnitIsDeadOrGhost = function() return false end
    w.LoadFile = function(self, path, addonName, namespace)
        if original and path:find("MSUF_UF_PreviewFamilies.lua", 1, true) then return true end
        if original and path:find("MSUF_UF_Elements_LoadConditions.lua", 1, true) then path = oldFile end
        local chunk, message = Compile(path)
        if not chunk then return false, message end
        setfenv(chunk, self.env)
        self.loading = path
        local ok, result = pcall(chunk, addonName, namespace)
        self.loading = nil
        return ok, result
    end
    for _, name in ipairs({ "RegisterStateDriver", "UnregisterStateDriver", "RegisterAttributeDriver",
        "UnregisterAttributeDriver", "RegisterUnitWatch", "UnregisterUnitWatch" }) do
        local native = env[name]
        if type(native) == "function" then
            env[name] = function(...)
                if activeCalls then
                    activeCalls[name] = (activeCalls[name] or 0) + 1
                    activeCalls.order = (activeCalls.order or "") .. "|" .. name
                end
                return native(...)
            end
        end
    end
    if queries then ObserveQueries(env) end
    if original then
        -- The frozen original owner (tools/fixtures/preview/LoadConditions.baseline.lua) reads and writes the
        -- namespace-only names below as globals. It gets the legacy global view of the registry the providers
        -- publish to, so it sees (and, for the six preview request flags, updates) the same state the shipped
        -- graph does.
        local legacy = { MSUF_PreviewTestMode = true, MSUF_BossTestMode = true, MSUF_ArenaTestMode = true,
            MSUF2_BossUnitframePreviewActive = true, MSUF2_ArenaUnitframePreviewActive = true,
            MSUF_UnitPreviewActive = true }
        local readOnly = { MSUF_InCombat = true, MSUF_UFCore_RefreshHealthBarColor = true,
            MSUF_UF_RangeFade_Refresh = true }
        local meta = getmetatable(env)
        local inner = meta.__index
        meta.__index = function(table_, key)
            if legacy[key] or readOnly[key] then
                local owned = w.core.PublicGlobals
                local value = type(owned) == "table" and owned[key] or nil
                if value ~= nil then return value end
            end
            if type(inner) == "function" then return inner(table_, key) end
            return inner and inner[key]
        end
        meta.__newindex = function(table_, key, value)
            if legacy[key] and type(w.core.ExportPublic) == "function" then
                w.core.ExportPublic(key, value)
                return
            end
            rawset(table_, key, value)
        end
    end
    w:Boot()
    local failure = w:FirstFailure()
    assert(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
    -- The offline world deliberately has no Blizzard native AuraContainer addon.
    -- Keep that precise provider limitation visible; every other handler error fails.
    w.nativeAuraErrors = 0
    env.geterrorhandler = function()
        return function(message)
            if message == "MSUF Auras3: Blizzard_AuraContainer is not loaded: MISSING" then
                w.nativeAuraErrors = w.nativeAuraErrors + 1
                return
            end
            error(message)
        end
    end
    env.MSUF_InitProfiles()
    w.core.UF.Config.Refresh()
    for _, unit in ipairs(w.core.UF.unitOrder) do env[w.core.UF.FrameName(unit)] = false end
    if not cold then w.core.UF.Initialize() end
    w.live = live
    return w
end
-- Widget methods model native sinks without allocating fixture-only color tables.
local sinks = {
    SetAlpha = function(self, a) self.alpha = a end,
    SetText = function(self, text) self.text = text end,
    SetMinMaxValues = function(self, low, high) self.minimum, self.maximum = low, high end,
    SetValue = function(self, value) self.value = value end,
    SetStatusBarColor = function(self, r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end,
    SetVertexColor = function(self, r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end,
}
local function Instrument(methods, queries)
for name, sink in pairs(sinks) do
    methods[name] = function(...)
        if activeCalls then
            activeCalls[name] = (activeCalls[name] or 0) + 1
            activeCalls.order = (activeCalls.order or "") .. "|" .. name
        end
        return sink(...)
    end
end
for _, name in ipairs({ "Show", "Hide", "EnableMouse", "SetShown", "SetFormattedText", "SetPoint", "ClearAllPoints",
    "SetTexture", "SetSize", "SetWidth", "SetHeight", "GetStatusBarTexture", "IsShown", "SetParent",
    "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent", "UnregisterAllEvents" }) do
    local native = methods[name]
    if native then methods[name] = function(...)
        if activeCalls then
            activeCalls[name] = (activeCalls[name] or 0) + 1
            activeCalls.order = (activeCalls.order or "") .. "|" .. name
        end
        return native(...)
    end end
end
    if queries then
        for name, native in pairs(methods) do
            if type(native) == "function" then methods[name] = Observe("frame." .. name, native) end
        end
    end
end
-- Edit Mode copies the profile through a cycle map that inserts and deletes table identities.
-- Dead hash nodes make that map's capacity depend on process addresses, so equal source
-- allocates different bytes (an identical-parent control flakes without this). Heap samples
-- give every graph the same identity-free copy; preview, Edit Mode state and all other
-- operations execute unchanged, and VM/native samples keep the real copier.
local function TreeCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[TreeCopy(key)] = TreeCopy(item) end
    return copy
end
local function IdentityFreeSnapshots(w)
    w.core.ProfileFields.CopySnapshot = function(value) return TreeCopy(value), true end
end

local function EqualTables(a, b, label)
    for key, value in pairs(a) do
        if type(value) == "table" then EqualTables(value, assert(b[key], label .. ": missing " .. key), label .. ": " .. key)
        else assert(value == b[key], label .. ": " .. key .. " " .. tostring(value) .. " / " .. tostring(b[key])) end
    end
    for key in pairs(b) do assert(a[key] ~= nil, label .. ": extra " .. key) end
end
local function Snapshot(w)
    local out = {}
    local function Save(prefix, value)
        if value == nil or type(value) == "number" or type(value) == "string" or type(value) == "boolean" then out[prefix] = value end
    end
    for _, kind in ipairs({ "boss", "arena" }) do
        for i = 1, 6 do
            local unit = kind .. i
            local f = w.core.UF.frames[unit]
            if f then
                for _, key in ipairs({ "_msufBossPreviewForced", "_msufArenaPreviewForced", "_msufRangeMulApplied",
                    "_msufAlphaLastFrame", "_msufAlphaLastHP", "_msufAlphaLastFG", "shown", "alpha", "mouseEnabled", "template" }) do Save(unit .. "." .. key, f[key]) end
                for _, key in ipairs({ "exists", "existsKnown", "dead", "connected", "connectedKnown", "npcKind", "npcKindKnown",
                    "classToken", "isPlayer", "isPlayerKnown", "identityClassRead" }) do
                    Save(unit .. ".state." .. key, f._msufUnitState and f._msufUnitState[key])
                end
                for _, key in ipairs({ "hpBar", "powerBar", "targetPowerBar", "nameText", "levelText", "_msufHealthVisualRoot" }) do
                    local region = f[key]
                    if region then
                        for _, field in ipairs({ "text", "alpha", "shown", "value", "minimum", "maximum", "r", "g", "b", "a" }) do
                            Save(unit .. "." .. key .. "." .. field, region[field])
                        end
                    end
                end
                Save(unit .. ".registered", w.core.UF.attachedFrames[f])
                for event, value in pairs(f.events or {}) do Save(unit .. ".event." .. event, value) end
                local rt = f._msufTextRuntime
                if rt then
                    Save(unit .. ".absorb", rt.healthAbsorb)
                    for _, key in ipairs({ "healthSlots", "powerSlots", "healthAbsorbSlots" }) do
                        for slotIndex, slot in ipairs(rt[key] or {}) do
                            for _, field in ipairs({ "text", "alpha", "shown", "r", "g", "b", "a" }) do
                                Save(unit .. "." .. key .. slotIndex .. "." .. field, slot.fs and slot.fs[field])
                            end
                        end
                    end
                end
            end
        end
    end
    -- The preview request provider publishes these two flags to the namespace registry only;
    -- the frozen original world still keeps them as globals.
    local owned = type(w.core.PublicGlobals) == "table" and w.core.PublicGlobals or {}
    for _, name in ipairs({ "MSUF2_BossUnitframePreviewActive", "MSUF2_ArenaUnitframePreviewActive" }) do
        local value = owned[name]
        if value == nil then value = w.env[name] end
        Save(name, value)
    end
    Save("attachedFrames", #w.core.UF.attachedFrameList)
    Save("unitFrames", #w.core.UF.frameList)
    return out
end

return {
    New = New, Snapshot = Snapshot, Equal = EqualTables, Secrets = Secrets, IdentityFreeSnapshots = IdentityFreeSnapshots,
    Instrument = Instrument,
    Capture = function(calls, queries)
        if queryHookActive then
            debug.sethook(priorHook, priorMask, priorCount)
            queryHookActive = false
        end
        if calls then calls.queries, calls.queryTotal = {}, 0 end
        activeCalls = calls
        if calls and queries then
            priorHook, priorMask, priorCount = debug.gethook()
            queryHookActive = true
            debug.sethook(function()
                local called = debug.getinfo(2, "fS")
                if called.what ~= "C" then return end
                local caller = debug.getinfo(3, "S")
                local source = caller and caller.source or ""
                if source:find("/MidnightSimpleUnitFrames", 1, true)
                    or source:find("/fixtures/preview/LoadConditions.baseline.lua", 1, true) then
                    local name = "C:" .. tostring(called.func)
                    calls.queries[name] = (calls.queries[name] or 0) + 1
                    calls.queryTotal = calls.queryTotal + 1
                end
            end, "c")
        end
    end,
}
