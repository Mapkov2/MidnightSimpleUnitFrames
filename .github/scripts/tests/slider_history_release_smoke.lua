-- Regression: a slider drag previews every value, but Undo/Redo records only
-- the value before the drag and the final value after releasing the slider.

_G = _G or _ENV

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(item, seen)
    end
    return copy
end

local function KeySet(...)
    local out = {}
    for i = 1, select("#", ...) do out[select(i, ...)] = true end
    return out
end

local function Words(text, asSet)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do
        if asSet then out[word] = true else out[#out + 1] = word end
    end
    return out
end

local profile = { general = { sliderValue = 10 } }
_G.MSUF_DB = profile
_G.MSUF_ActiveProfile = "Default"
_G.MSUF_GlobalDB = {
    profiles = { Default = profile },
    char = { ["Tester-Realm"] = { specProfileMap = {} } },
}
_G.MSUF_GetCharKey = function() return "Tester-Realm" end

local queuedTimers = {}
_G.C_Timer = {
    After = function(_, callback)
        queuedTimers[#queuedTimers + 1] = callback
    end,
}

local function FlushTimers()
    while #queuedTimers > 0 do
        local callbacks = queuedTimers
        queuedTimers = {}
        for i = 1, #callbacks do callbacks[i]() end
    end
end

local mouseDown = false
local mouseOver = false
_G.IsMouseButtonDown = function(button)
    return button == "LeftButton" and mouseDown
end

local namespace = { MSUF2 = {} }
namespace.ExportPublic = function(name, value) _G[name] = value; return value end
local M = namespace.MSUF2
local liveApplyCount = 0
M.KeySet = KeySet
M.KeySetFromWords = function(text) return Words(text, true) end
M.WordList = function(text) return Words(text, false) end
M.DeepCopy = DeepCopy
M.IsConfigCombatLocked = function() return false end
M.CallIf = function(fn, ...) if type(fn) == "function" then return fn(...) end end
M.ApplyService = {
    SafeInvoke = function(fn, ...)
        local ok, a, b, c = pcall(fn, ...)
        return ok, a, b, c
    end,
    CallGlobal = function() return false end,
    RequestGeneral = function()
        liveApplyCount = liveApplyCount + 1
        return true
    end,
    Flush = function() end,
}

assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Bindings.lua"))(
    "MidnightSimpleUnitFrames", namespace)

local slider = {
    _value = 10,
    _hooks = {},
    _msuf2Step = 1,
    _msuf2ControlKind = "slider",
    _msuf2Title = { GetText = function() return "Release history" end },
}

function slider:GetMinMaxValues() return 0, 100 end
function slider:GetValue() return self._value end
function slider:SetValue(value) self._value = value end
function slider:IsMouseOver() return mouseOver end
function slider:HookScript(script, callback)
    local callbacks = self._hooks[script]
    if not callbacks then
        callbacks = {}
        self._hooks[script] = callbacks
    end
    callbacks[#callbacks + 1] = callback
end
function slider:Fire(script, ...)
    local callbacks = self._hooks[script] or {}
    for i = 1, #callbacks do callbacks[i](self, ...) end
end

local ctx = { key = "slider_history_test", refreshers = {} }
M.BindSlider(ctx, slider,
    function() return profile.general.sliderValue end,
    function(value)
        profile.general.sliderValue = value
        slider._value = value
        -- Real Menu2 setters immediately refresh their preview through an
        -- apply helper. Its differently named checkpoint must stay nested in
        -- the slider transaction instead of committing every value tick.
        M.RequestGeneralApply("MSUF2_SLIDER_HISTORY_TEST", { preview = true })
        return true
    end)

assert(M.StartHistorySession("menu") == true, "history session did not start")

-- Native sliders can emit the first value before a post-registered MouseDown
-- hook. The binding must still recognize it as part of the active pointer drag.
mouseDown = true
mouseOver = true
slider:Fire("OnValueChanged", 20)
slider:Fire("OnMouseDown", "LeftButton")
slider:Fire("OnValueChanged", 35)
slider:Fire("OnValueChanged", 50)
slider:Fire("OnMouseUp", "LeftButton")

-- Keep the transaction alive until the entire MouseUp dispatch is complete.
mouseDown = false
slider:Fire("OnValueChanged", 65)

assert(profile.general.sliderValue == 65, "slider live preview did not apply the final value")
assert(liveApplyCount == 4, "slider did not keep live-applying intermediate preview values")
assert(M.GetHistoryState().undoCount == 0, "slider committed before release processing finished")
assert(#queuedTimers == 1, "slider release did not queue exactly one deferred commit")

FlushTimers()
assert(M.GetHistoryState().undoCount == 1, "one slider drag did not create exactly one history step")
assert(M.Undo() == true and profile.general.sliderValue == 10,
    "slider Undo did not restore the value from before the drag")
assert(M.Redo() == true and profile.general.sliderValue == 65,
    "slider Redo did not restore the final released value")

print("slider history release smoke: OK")
