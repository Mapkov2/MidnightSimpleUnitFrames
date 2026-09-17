-- WoW Forever shell gates. Forever runs the Mainline load graph, and its project
-- ID is only known at hour 0, so every Mainline-only shell gate must follow
-- MSUF.Client instead of the raw project ID:
--   * the Auras page filter reduction, the Misc page aura tooltip switches and
--     the legacy Era portrait keep their Mainline answer on a Mainline-family
--     client under any project ID, and give the old answer on the four shipped
--     clients and in harnesses without MSUF.Client;
--   * the cooldown anchor support probe follows the client family, and the
--     missing-anchor login warning stays quiet on Forever while Blizzard itself
--     reports the Cooldown Manager unavailable (unchanged everywhere else);
--   * a failed MSUF Options load on Forever names the client's load reason.
-- Plain Lua 5.1; arg[1] is the repo root.
local repo = assert(arg[1], "repo root required")
local loadChunk = loadstring or load

local function Read(relative)
    local handle = assert(io.open(repo .. "/" .. relative, "rb"), "cannot open " .. relative)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

local PROJECT = { Mainline = 1, Vanilla = 2, TBC = 5, Mists = 19 }
local CLIENTS = {
    Mainline = { Family = "Mainline", Flavor = "Mainline", IsRetail = true, IsClassic = false, IsVanilla = false, IsForever = false },
    Vanilla = { Family = "Classic", Flavor = "Vanilla", IsRetail = false, IsClassic = true, IsVanilla = true, IsForever = false },
    TBC = { Family = "Classic", Flavor = "TBC", IsRetail = false, IsClassic = true, IsVanilla = false, IsForever = false },
    Mists = { Family = "Classic", Flavor = "Mists", IsRetail = false, IsClassic = true, IsVanilla = false, IsForever = false },
    Forever = { Family = "Mainline", Flavor = "Mainline", IsRetail = true, IsClassic = false, IsVanilla = false, IsForever = true },
}

-- 1. File-scope client gates, evaluated from the shipped statements. -----------
local function Statement(relative, first, stop)
    local source = Read(relative)
    local start = assert(source:find(first, 1, true), relative .. " lost its gate statement: " .. first)
    local finish = assert(source:find(stop, start, true), relative .. " gate statement lost its terminator: " .. stop)
    return source:sub(start, finish - 1)
end

local function Evaluate(statement, name, client, projectID)
    local env = {
        WOW_PROJECT_ID = projectID,
        WOW_PROJECT_MAINLINE = PROJECT.Mainline,
        WOW_PROJECT_CLASSIC = PROJECT.Vanilla,
    }
    env._G = env
    local chunk = assert(loadChunk("local MSUF, M, _G = ...\n" .. statement .. "\nreturn " .. name))
    setfenv(chunk, env)
    local value = chunk({ Client = client }, {}, env)
    assert(type(value) == "boolean", name .. " must be a boolean, got " .. type(value))
    return value
end

-- The gate expressions as they read before client-model routing. On the four
-- shipped clients and in harnesses without MSUF.Client the new gates must agree.
local LEGACY = {
    reduced = "M.CLASSIC_AURA_FILTERS_REDUCED = MSUF.Client and MSUF.Client.IsClassic == true\n"
        .. "    or (_G.WOW_PROJECT_ID ~= nil and _G.WOW_PROJECT_ID ~= _G.WOW_PROJECT_MAINLINE)",
    mainline = "local IS_MAINLINE = _G.WOW_PROJECT_ID == nil or _G.WOW_PROJECT_MAINLINE == nil\n"
        .. "    or _G.WOW_PROJECT_ID == _G.WOW_PROJECT_MAINLINE",
    portrait = "local LEGACY_BLIZZARD_PORTRAIT = (MSUF.Client and MSUF.Client.IsVanilla == true)\n"
        .. "  or (_G.WOW_PROJECT_CLASSIC ~= nil and _G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC)",
}
local GATES = {
    {
        key = "reduced", name = "M.CLASSIC_AURA_FILTERS_REDUCED",
        statement = Statement("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua",
            "M.CLASSIC_AURA_FILTERS_REDUCED = ", "\nlocal Tr = "),
        forever = false,
    },
    {
        key = "mainline", name = "IS_MAINLINE",
        statement = Statement("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua",
            "local IS_MAINLINE = ", "\nlocal function NormalizeTooltipMode"),
        forever = true,
    },
    {
        key = "portrait", name = "LEGACY_BLIZZARD_PORTRAIT",
        statement = Statement("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua",
            "local LEGACY_BLIZZARD_PORTRAIT = ", "\n\nlocal V = "),
        forever = false,
    },
}

for _, gate in ipairs(GATES) do
    for flavor, projectID in pairs(PROJECT) do
        local expected = Evaluate(LEGACY[gate.key], gate.name, CLIENTS[flavor], projectID)
        assert(Evaluate(gate.statement, gate.name, CLIENTS[flavor], projectID) == expected,
            gate.name .. " changed on the shipped " .. flavor .. " client")
        assert(Evaluate(gate.statement, gate.name, nil, projectID) == Evaluate(LEGACY[gate.key], gate.name, nil, projectID),
            gate.name .. " changed for a harness without MSUF.Client under project " .. projectID)
    end
    assert(Evaluate(gate.statement, gate.name, nil, nil) == Evaluate(LEGACY[gate.key], gate.name, nil, nil),
        gate.name .. " changed for a harness without MSUF.Client or project constants")
    -- Forever under every project ID it could report, including an unknown one.
    for _, projectID in ipairs({ PROJECT.Mainline, PROJECT.Vanilla, PROJECT.TBC, PROJECT.Mists, 99 }) do
        assert(Evaluate(gate.statement, gate.name, CLIENTS.Forever, projectID) == gate.forever,
            gate.name .. " on WoW Forever depends on project ID " .. projectID)
    end
end

-- 2. Cooldown anchor support probe and the missing-anchor login warning. --------
local ANCHORS = repo .. "/MidnightSimpleUnitFrames/Integrations/MSUF_Integration_ThirdPartyAnchors.lua"

local function LoadAnchors(client, projectID, state)
    local frames, timers, popups = {}, {}, {}
    _G.MSUF_NS = nil
    WOW_PROJECT_MAINLINE = PROJECT.Mainline
    WOW_PROJECT_ID = projectID
    ArcUI_Public, SCM_GroupAnchorProxy_1, SCM_GroupAnchor_1, CoolinatorPrimaryGroupAnchor, _ECME_GetBarFrame = nil, nil, nil, nil, nil
    EventRegistry, CVarCallbackRegistry, GetCVarBool, issecretvalue = nil, nil, nil, nil
    C_CooldownViewer = state.noNamespace and nil or {
        IsCooldownViewerAvailable = function()
            state.availabilityAsked = (state.availabilityAsked or 0) + 1
            return state.available == true, state.available and "" or "Unavailable"
        end,
    }
    EssentialCooldownViewer = state.viewer and { visibleSetting = 0 } or nil
    Enum = { CooldownViewerVisibleSetting = { Always = 0, Hidden = 2 } }
    C_CVar = { GetCVarBool = function(name)
        assert(name == "cooldownViewerEnabled", "unexpected CVar read: " .. tostring(name))
        return state.cvar == true
    end }
    C_AddOns = { IsAddOnLoaded = function() return false, false end }
    C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    InCombatLockdown = function() return false end
    UIParent = {}
    CreateFrame = function()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(script, callback) self.scripts[script] = callback end
        frames[#frames + 1] = frame
        return frame
    end
    StaticPopupDialogs = {}
    StaticPopup_Show = function(name) popups[#popups + 1] = name; return {} end
    StaticPopup_Hide = function() end
    MSUF_DB = { general = { anchorToCooldown = state.anchor ~= false } }
    MSUF_GlobalDB = {}
    local namespace = { Client = client }
    assert(loadfile(ANCHORS))("MidnightSimpleUnitFrames", namespace)
    return namespace, frames, timers, popups
end

local function LoginWarnings(client, projectID, state)
    local namespace, frames, timers, popups = LoadAnchors(client, projectID, state)
    local watcher
    for i = 1, #frames do
        if frames[i].events.PLAYER_LOGIN then watcher = frames[i] end
    end
    assert(watcher and watcher.scripts.OnEvent, "cooldown anchor watcher was not installed")
    watcher.scripts.OnEvent(watcher, "PLAYER_LOGIN")
    for i = 1, #timers do timers[i]() end
    local shown = 0
    for i = 1, #popups do
        if popups[i] == "MSUF_COOLDOWN_ANCHOR_MISSING" then shown = shown + 1 end
    end
    return shown, namespace
end

local function Supported(client, projectID)
    local namespace = LoadAnchors(client, projectID, { anchor = false, viewer = true, available = true, cvar = true })
    return namespace.IsCooldownAnchorSupported()
end

assert(Supported(CLIENTS.Mainline, PROJECT.Mainline) == true, "Retail lost cooldown anchor support")
assert(Supported(CLIENTS.Vanilla, PROJECT.Vanilla) == false, "Classic Era gained cooldown anchor support")
assert(Supported(CLIENTS.TBC, PROJECT.TBC) == false, "TBC gained cooldown anchor support")
assert(Supported(CLIENTS.Mists, PROJECT.Mists) == false, "Mists gained cooldown anchor support")
for _, projectID in ipairs({ PROJECT.Mainline, PROJECT.Vanilla, 99 }) do
    assert(Supported(CLIENTS.Forever, projectID) == true,
        "WoW Forever loads Blizzard_CooldownViewer (camelot), yet anchor support failed under project " .. projectID)
end
assert(Supported(nil, nil) == true, "a harness without MSUF.Client or project constants models Mainline")
assert(Supported(nil, PROJECT.Mainline) == true, "harness Mainline project fallback changed")
assert(Supported(nil, PROJECT.Vanilla) == false, "harness Classic project fallback changed")

-- Blizzard reports the Cooldown Manager unavailable (for example below its
-- level), anchoring is on and no layout addon is installed.
local unavailable = { viewer = true, available = false, cvar = true }
assert(LoginWarnings(CLIENTS.Mainline, PROJECT.Mainline, unavailable) == 1,
    "Retail must keep warning when the Cooldown Manager is unavailable")
local foreverUnavailable = { viewer = true, available = false, cvar = true }
assert(LoginWarnings(CLIENTS.Forever, PROJECT.Mainline, foreverUnavailable) == 0,
    "WoW Forever warned while Blizzard reports the Cooldown Manager unavailable")
assert((foreverUnavailable.availabilityAsked or 0) >= 1, "the Forever quiet path must ask Blizzard's availability API")
assert(LoginWarnings(CLIENTS.Forever, PROJECT.Vanilla, { viewer = true, available = false, cvar = true }) == 0,
    "WoW Forever warned under a non-Mainline project ID while the Cooldown Manager is unavailable")
-- No Blizzard viewer frame at all.
assert(LoginWarnings(CLIENTS.Mainline, PROJECT.Mainline, { viewer = false, available = true, cvar = true }) == 1,
    "Retail must keep warning without EssentialCooldownViewer")
assert(LoginWarnings(CLIENTS.Forever, PROJECT.Mainline, { viewer = false, available = true, cvar = true }) == 0,
    "WoW Forever warned although this client has no EssentialCooldownViewer")
-- User-fixable states still warn on Forever.
assert(LoginWarnings(CLIENTS.Forever, PROJECT.Mainline, { viewer = true, available = true, cvar = false }) == 1,
    "WoW Forever must still warn when cooldownViewerEnabled is off")
-- An active Blizzard viewer is an anchor on both clients; no warning.
assert(LoginWarnings(CLIENTS.Forever, PROJECT.Mainline, { viewer = true, available = true, cvar = true }) == 0,
    "WoW Forever warned with an active Blizzard Cooldown Manager")
assert(LoginWarnings(CLIENTS.Mainline, PROJECT.Mainline, { viewer = true, available = true, cvar = true }) == 0,
    "Retail warned with an active Blizzard Cooldown Manager")
-- Anchoring off never warns, and Classic never warns.
assert(LoginWarnings(CLIENTS.Forever, PROJECT.Mainline, { anchor = false, viewer = false, available = false }) == 0,
    "WoW Forever warned with anchoring off")
assert(LoginWarnings(CLIENTS.Vanilla, PROJECT.Vanilla, { viewer = false, available = false }) == 0,
    "Classic Era warned about a Cooldown Manager it cannot host")

-- 3. MSUF Options LoadOnDemand failure reason. ----------------------------------
local LOADER = repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_OptionsLoader.lua"
local realPrint = print

local function OpenOptions(client, loadResult, reason)
    local lines, wrapperCalls, directCalls = {}, 0, 0
    local loaded = false
    local namespace = { Client = client }
    namespace.ExportPublic = function(name, value) _G[name] = value end
    _G.MSUF_NS, _G.MSUF2 = nil, nil
    SlashCmdList = {}
    InCombatLockdown = function() return false end
    ADDON_DISABLED = "Disabled"
    MSUF_ShowConfigCombatLockMessage = nil
    C_AddOns = {
        IsAddOnLoaded = function() return loaded, loaded end,
        LoadAddOn = function(name)
            assert(name == "MidnightSimpleUnitFrames_Options", "unexpected addon load: " .. tostring(name))
            directCalls = directCalls + 1
            if loadResult then
                loaded = true
                namespace.OptionsLODReady = true
                return true, nil
            end
            return false, reason
        end,
    }
    LoadAddOn = nil
    MSUF_EnsureAddonLoaded = function(name)
        wrapperCalls = wrapperCalls + 1
        local _, _ = C_AddOns.LoadAddOn(name)
        return loaded
    end
    print = function(message) lines[#lines + 1] = tostring(message) end
    assert(loadfile(LOADER))("MidnightSimpleUnitFrames", namespace)
    -- The loader exports MSUF_EnsureAddonLoaded-independent entry points; the
    -- wrapper above stands in for Kernel/MSUF_Libs.lua.
    local result = MSUF_EnsureOptionsLoaded("smoke")
    print = realPrint
    return result, table.concat(lines, "\n"), wrapperCalls, directCalls
end

local result, output, wrapperCalls = OpenOptions(CLIENTS.Mainline, false, "DISABLED")
assert(result == false and wrapperCalls == 1, "Retail must keep loading through MSUF_EnsureAddonLoaded")
assert(output:find("(incomplete load).", 1, true), "Retail Options failure text changed:\n" .. output)
result, output = OpenOptions(nil, false, "DISABLED")
assert(result == false and output:find("(incomplete load).", 1, true),
    "a harness without MSUF.Client must keep the old Options failure text:\n" .. output)

local directCalls
result, output, wrapperCalls, directCalls = OpenOptions(CLIENTS.Forever, false, "DISABLED")
assert(result == false and wrapperCalls == 0 and directCalls == 1, "WoW Forever must ask the client loader once, directly")
assert(output:find("(Disabled).", 1, true), "WoW Forever Options failure must name Blizzard's reason label:\n" .. output)
result, output = OpenOptions(CLIENTS.Forever, false, "INTERFACE_VERSION")
assert(result == false and output:find("(INTERFACE_VERSION).", 1, true),
    "WoW Forever Options failure must fall back to the raw reason token:\n" .. output)
result, output = OpenOptions(CLIENTS.Forever, true)
assert(result == true and output == "", "WoW Forever Options load must succeed silently:\n" .. output)

print("forever shell project gates smoke passed")
