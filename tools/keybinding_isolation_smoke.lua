-- Regression smoke: account-global MSUF SavedVariables must never overwrite
-- the active WoW account/character binding set on login.
--
-- Run from the repository root:
--   lua tools/keybinding_isolation_smoke.lua

local checks = 0

local function Equal(actual, expected, label)
    checks = checks + 1
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local eventFrame
local registered = {}
local setBindingCalls = 0
local bindings = {
    ["SHIFT-1"] = "ACTIONBUTTON6",
    ["SHIFT-2"] = "ACTIONBUTTON7",
    ["CTRL-O"] = "MSUF_TOGGLE_OPTIONS",
}

function _G.CreateFrame()
    local frame = {}
    function frame:RegisterEvent(event)
        registered[event] = true
    end
    function frame:SetScript(kind, callback)
        if kind == "OnEvent" then self.OnEvent = callback end
    end
    eventFrame = frame
    return frame
end

function _G.GetBindingKey(command)
    local keys = {}
    for key, action in pairs(bindings) do
        if action == command then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return unpack(keys)
end

function _G.SetBinding()
    setBindingCalls = setBindingCalls + 1
    error("MSUF must not mutate the active binding set", 2)
end

_G.MSUF_GlobalDB = {
    global = {
        bindings = {
            commands = {
                MSUF_TOGGLE_OPTIONS = {"SHIFT-1"},
                MSUF_TOGGLE_EDITMODE = {"SHIFT-2"},
            },
        },
    },
}

local chunk = assert(loadfile("MidnightSimpleUnitFrames/Foundation/MSUF_Util.lua"))
chunk("MidnightSimpleUnitFrames", {})

Equal(type(eventFrame and eventFrame.OnEvent), "function", "binding event handler")
Equal(registered.PLAYER_LOGIN, true, "PLAYER_LOGIN registration")
Equal(registered.UPDATE_BINDINGS, true, "UPDATE_BINDINGS registration")
Equal(registered.PLAYER_REGEN_ENABLED, nil, "no deferred binding apply registration")

eventFrame.OnEvent(eventFrame, "PLAYER_LOGIN")

Equal(setBindingCalls, 0, "login SetBinding calls")
Equal(bindings["SHIFT-1"], "ACTIONBUTTON6", "first action binding preserved")
Equal(bindings["SHIFT-2"], "ACTIONBUTTON7", "second action binding preserved")
Equal(bindings["CTRL-O"], "MSUF_TOGGLE_OPTIONS", "current MSUF binding preserved")

local stored = _G.MSUF_GlobalDB.global.bindings.commands
Equal(#stored.MSUF_TOGGLE_OPTIONS, 1, "stored options binding count")
Equal(stored.MSUF_TOGGLE_OPTIONS[1], "CTRL-O", "stored options binding mirrors current set")
Equal(#stored.MSUF_TOGGLE_EDITMODE, 0, "stale edit-mode binding removed")

bindings["CTRL-E"] = "MSUF_TOGGLE_EDITMODE"
eventFrame.OnEvent(eventFrame, "UPDATE_BINDINGS")

Equal(setBindingCalls, 0, "update SetBinding calls")
Equal(#stored.MSUF_TOGGLE_EDITMODE, 1, "updated edit-mode binding count")
Equal(stored.MSUF_TOGGLE_EDITMODE[1], "CTRL-E", "updated edit-mode binding mirrored")

print(string.format("keybinding_isolation_smoke: OK (%d checks)", checks))
