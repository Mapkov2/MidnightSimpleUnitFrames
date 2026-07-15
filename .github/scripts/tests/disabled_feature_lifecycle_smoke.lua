-- Regression coverage for menu features that must own no runtime routes while disabled.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function LoadAddon(path, namespace)
    local chunk, err = loadfile(root .. "/MidnightSimpleUnitFrames/" .. path)
    Check(chunk, err)
    return chunk("MidnightSimpleUnitFrames", namespace)
end

local function NewFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents()
        for event in pairs(self.events) do self.events[event] = nil end
    end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    return frame
end

local function NoEvents(frame, label)
    Check(frame and next(frame.events) == nil, label .. " retained an event while disabled")
end

-- Version check: live disable removes both bus routes and invalidates a queued broadcast.
do
    local registered = {}
    local timers = {}
    local sent = 0
    local module
    local bus = {}
    function bus:Register(event, key, callback)
        registered[event .. "|" .. key] = callback
    end
    function bus:Unregister(event, key)
        registered[event .. "|" .. key] = nil
    end

    _G.MSUF_DB = { general = { versionCheckEnabled = false } }
    _G.C_AddOns = { GetAddOnMetadata = function() return "9.9.9" end }
    _G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function() sent = sent + 1 end,
    }
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    _G.IsInGuild = function() return true end
    _G.IsInGroup = function() return false end
    _G.IsInRaid = function() return false end
    _G.LE_PARTY_CATEGORY_HOME = 1
    _G.LE_PARTY_CATEGORY_INSTANCE = 2

    local ns = { MSUF_EventBus = bus }
    function ns.MSUF_RegisterModule(_, value) module = value end
    LoadAddon("Features/Versioning/MSUF_VersionCheck.lua", ns)
    Check(module and module:IsEnabled() == false, "version module ignored disabled DB state")
    Check(next(registered) == nil, "disabled version module registered a bus route")

    _G.MSUF_DB.general.versionCheckEnabled = true
    module:Enable()
    local pew = registered["PLAYER_ENTERING_WORLD|MSUF_VersionCheck_PEW"]
    Check(type(pew) == "function", "enabled version module missed world route")
    pew()
    Check(#timers == 1, "version broadcast was not queued")

    _G.MSUF_DB.general.versionCheckEnabled = false
    module:Disable()
    Check(next(registered) == nil, "version disable retained a bus route")
    timers[1]()
    Check(sent == 0, "disabled version module sent a queued broadcast")
end

-- Focus interrupt tracker: disabled state owns no subscription, event frame, or queued work.
do
    local frame
    local timers = {}
    local subscriber
    local engine = {}
    function engine:Subscribe(key, callback)
        Check(key == "focus", "focus interrupt subscribed to wrong state key")
        subscriber = callback
        return true
    end
    function engine:Unsubscribe(key, callback)
        Check(key == "focus" and callback == subscriber, "focus interrupt unsubscribed wrong callback")
        subscriber = nil
        return true
    end
    _G.MSUF_DB = {
        general = { enableFocusKickIcon = false, enableFocusCastbar = true },
        focus = { enabled = true },
    }
    _G.MSUF_ShouldUseMSUFCastbar = function() return true end
    _G.CreateFrame = function()
        frame = NewFrame()
        return frame
    end
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    _G.MSUF_FocusCastBar = nil
    _G.MSUF_FocusCastbar = nil
    _G.FocusCastBar = nil

    LoadAddon("Castbars/MSUF_FocusKick_StateDriver.lua", { MSUF_CastbarEngine = engine })
    Check(frame == nil and subscriber == nil, "disabled focus interrupt tracker acquired runtime ownership")
    Check(#timers == 0, "disabled focus interrupt tracker queued startup work")

    _G.MSUF_DB.general.enableFocusKickIcon = true
    _G.MSUF_FocusKickDriver_ForceUpdate()
    Check(type(subscriber) == "function", "focus interrupt enable missed canonical state subscription")
    Check(#timers == 1, "focus interrupt enable did not queue refresh")
    timers[1]()

    _G.MSUF_DB.general.enableFocusKickIcon = false
    _G.MSUF_FocusKickDriver_ForceUpdate()
    Check(frame == nil and subscriber == nil, "focus interrupt teardown retained runtime ownership")
    Check(#timers == 1, "focus interrupt disable queued work instead of tearing down immediately")
end

print("PASS disabled feature lifecycle: version and focus routes fully detach, queued work invalidates")
