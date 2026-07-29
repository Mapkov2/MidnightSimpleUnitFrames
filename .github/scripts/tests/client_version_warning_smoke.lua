local root = arg and arg[1] or "."
local realPrint = print

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local SOURCE = root .. "/MidnightSimpleUnitFrames/Features/Versioning/MSUF_ClientVersionWarning.lua"

local function Load(tocVersion)
    local state = {
        registered = {},
        popups = {},
        shown = {},
        timers = {},
        prints = {},
        module = nil,
    }

    state.buildReads = 0
    state.frames = 0

    local bus = {}
    function bus:Register(event, key, callback, _, once)
        state.registered[event .. "|" .. key] = { callback = callback, once = once }
    end

    _G.GetBuildInfo = function()
        state.buildReads = state.buildReads + 1
        return "12.1.0", "70001", "Jul 29 2026", tocVersion
    end
    _G.CreateFrame = function()
        state.frames = state.frames + 1
        return {
            RegisterEvent = function() end,
            UnregisterEvent = function() end,
            SetScript = function() end,
        }
    end
    _G.OKAY = "Okay"
    _G.StaticPopupDialogs = state.popups
    _G.StaticPopup_Show = function(key, text)
        state.shown[#state.shown + 1] = { key = key, text = text }
    end
    _G.C_Timer = { After = function(delay, fn) state.timers[#state.timers + 1] = { delay = delay, fn = fn } end }
    _G.MSUF2 = nil
    _G.print = function(text) state.prints[#state.prints + 1] = text end

    local ns = { MSUF_EventBus = bus }
    function ns.MSUF_RegisterModule(name, value)
        Check(name == "ClientVersionWarning", "unexpected module registration: " .. tostring(name))
        state.module = value
    end
    ns.ExportPublic = function(name, value) state.exported = state.exported or {}; state.exported[name] = value; return value end

    local chunk = assert(loadfile(SOURCE))
    chunk("MidnightSimpleUnitFrames", ns)
    state.ns = ns
    return state
end

--- 12.0 client: the module arms, fires once per login and stays acknowledge-only.
--- Nothing in the addon calls MSUF_InitModules, so the wiring must happen at
--- file load; the smoke deliberately never calls Init itself.
local legacy = Load(120007)
Check(legacy.module and type(legacy.module.Init) == "function", "module was not registered on a 12.0 client")
Check(legacy.ns.ClientVersionWarning.IsLegacyClient() == true, "12.0 client was not detected as legacy")

local pew = legacy.registered["PLAYER_ENTERING_WORLD|MSUF_ClientVersionWarning_PEW"]
Check(pew and type(pew.callback) == "function", "login hook was not registered at load on a 12.0 client")
Check(pew.once == true, "login hook must be a one-shot registration")

--- A redundant registry Init must not double-wire anything.
legacy.module.Init()
local pewCount = 0
for _ in pairs(legacy.registered) do pewCount = pewCount + 1 end
Check(pewCount == 1, "a second Init call re-wired the login hook")

pew.callback()
Check(#legacy.timers == 1, "login hook did not defer the popup")
legacy.timers[1].fn()
Check(#legacy.shown == 1, "popup was not shown on a 12.0 client")
Check(legacy.shown[1].key == "MSUF_CLIENT_VERSION_WARNING", "unexpected popup key")
Check(type(legacy.shown[1].text) == "string" and legacy.shown[1].text:find("12.1", 1, true),
    "popup text does not name the required client version")

local spec = legacy.popups["MSUF_CLIENT_VERSION_WARNING"]
Check(type(spec) == "table", "popup dialog was not installed")
Check(spec.button1 == "Okay", "popup must offer a single acknowledge button")
Check(spec.button2 == nil, "popup must not offer a second button")
Check(spec.timeout == 0 and spec.whileDead == true, "popup must persist until acknowledged")

--- Session guard: one popup per login, never a repeat within the same session.
legacy.timers[1].fn()
Check(#legacy.shown == 1, "popup was shown twice in one session")
Check(#legacy.timers == 1, "the login path scheduled more than one timer")

--- Cost profile on the client that actually gets the popup: exactly one build
--- read for the whole session, no frame of our own, and no leftover work.
Check(legacy.buildReads == 1, "GetBuildInfo was read more than once: " .. tostring(legacy.buildReads))
Check(legacy.frames == 0, "the bus path must not create a frame")
Check(legacy.ns.ClientVersionWarning.IsLegacyClient() == true, "cached detection changed after the popup")
Check(legacy.buildReads == 1, "a later IsLegacyClient call re-queried GetBuildInfo")

--- 12.1 client: no detection, no registration, no hook, no popup — ever.
local current = Load(120100)
Check(current.ns.ClientVersionWarning.IsLegacyClient() == false, "12.1 client was flagged as legacy")
Check(next(current.registered) == nil, "12.1 client registered a login hook")
Check(current.module == nil, "12.1 client added a dead entry to the module registry")
Check(current.frames == 0, "12.1 client created a frame")
Check(current.buildReads == 1, "12.1 client read GetBuildInfo more than once")
Check(current.ns.ClientVersionWarning.Show() == false, "12.1 client showed the warning")
Check(#current.shown == 0, "12.1 client showed a popup")
Check(next(current.popups) == nil, "12.1 client installed a popup dialog")

--- Later builds stay silent too.
local future = Load(120205)
Check(future.ns.ClientVersionWarning.IsLegacyClient() == false, "post-12.1 build was flagged as legacy")
Check(next(future.registered) == nil, "post-12.1 build registered a login hook")
Check(future.module == nil, "post-12.1 build registered a module")

--- An unreadable build never warns: no popup the user could not act on.
local unknown = Load("not-a-number")
Check(unknown.ns.ClientVersionWarning.IsLegacyClient() == false, "unreadable build was flagged as legacy")
Check(next(unknown.registered) == nil, "unreadable build registered a login hook")
Check(unknown.module == nil, "unreadable build registered a module")

--- The forced debug entry point still works on any client.
local forced = Load(120100)
Check(forced.exported and type(forced.exported.MSUF_ShowClientVersionWarning) == "function",
    "debug entry point was not exported")
forced.exported.MSUF_ShowClientVersionWarning()
Check(#forced.shown == 1, "forced debug popup did not show on a 12.1 client")

--- Source contract: no construct that could ever cost anything in combat.
local handle = assert(io.open(SOURCE, "rb"))
local source = handle:read("*a"):gsub("\r\n", "\n")
handle:close()
--- Comments describe the cost profile in prose; scan code only.
local code = source:gsub("%-%-[^\n]*", "")
for _, forbidden in ipairs({ "OnUpdate", "hooksecurefunc", "NewTicker", "GetTime" }) do
    Check(not code:find(forbidden, 1, true),
        "client version warning must stay off any repeating path, found: " .. forbidden)
end
Check(select(2, code:gsub("GetBuildInfo", "")) == 1, "GetBuildInfo must be referenced exactly once")

realPrint("PASS client version warning: 12.0 warns once per login with one build read and no frame, "
    .. "12.1+ arms nothing at all, no repeating path anywhere")
