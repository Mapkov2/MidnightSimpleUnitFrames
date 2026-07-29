_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

local function TestLoadfile(path)
    local handle, openError = io.open(path, "rb")
    if not handle then return nil, openError end
    local source = handle:read("*a")
    handle:close()
    if source:sub(1, 3) == string.char(239, 187, 191) then source = source:sub(4) end
    return (loadstring or load)(source, "@" .. path)
end
loadfile = TestLoadfile

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant runtime missing")
local Registry = assert(A.Registry, "Assistant registry missing")

local defaults = {
    ["gf_party.portraitMode"] = "LEFT",
    ["gf_party.portraitRender"] = "2D",
    ["gf_party.portraitCastSpellIcon"] = false,
    ["gf_party.portraitShape"] = "SQUARE",
    ["gf_party.portraitSizeOverride"] = 0,
    ["gf_party.portraitWidth"] = 0,
    ["gf_party.portraitHeight"] = 0,
    ["gf_party.portraitOffsetX"] = 0,
    ["gf_party.portraitOffsetY"] = 0,
    ["gf_party.portraitZoom"] = 100,
    ["gf_party.portraitPanX"] = 0,
    ["gf_party.portraitPanY"] = 0,
    ["gf_party.portraitClassStyle"] = "BLIZZARD",
    ["gf_party.portraitPlacement"] = "ATTACHED",
    ["gf_party.portraitDetachedPoint"] = "RIGHT",
    ["gf_party.portraitDetachedTo"] = "LEFT",
    ["gf_party.portraitOverlayAlign"] = "LEFT",
    ["gf_party.portraitLevelOffset"] = 7,
    ["gf_party.portraitAlpha"] = 100,
    ["gf_party.portraitBorderStyle"] = "NONE",
    ["gf_party.portraitBorderThickness"] = 2,
    ["gf_party.portraitFillBorder"] = false,
    ["gf_party.portraitBorderArt"] = "FLAT",
    ["gf_party.portraitBorderDirection"] = "UP",
    ["gf_party.portraitBorderColor"] = { r = 1, g = 1, b = 1, label = "white" },
    ["gf_party.portraitBorderColorA"] = 1,
    ["gf_party.portraitBgEnabled"] = false,
    ["gf_party.portraitBgColor"] = { r = 0.05, g = 0.05, b = 0.05, label = "dark" },
    ["gf_party.portraitBgColorA"] = 0.85,
}

local unitModeDefaults = {
    ["player.portraitMode"] = "RIGHT",
    ["target.portraitMode"] = "RIGHT",
    ["targettarget.portraitMode"] = "RIGHT",
    ["focustarget.portraitMode"] = "RIGHT",
    ["focus.portraitMode"] = "RIGHT",
    ["pet.portraitMode"] = "RIGHT",
    ["boss.portraitMode"] = "RIGHT",
}

local boxes = {}
local function Bind(key, initial)
    local setting = assert(Registry:GetSetting(key), "missing setting " .. key)
    local box = { value = initial }
    boxes[key] = box
    local originalGet, originalSet = setting.get, setting.set
    setting.get = function() return box.value end
    setting.set = function(value)
        if setting.normalizesValue == true and type(originalSet) == "function" and type(originalGet) == "function" then
            originalSet(value)
            box.value = originalGet()
        else
            box.value = value
        end
    end
    setting.apply = function() return true end
end
for key, initial in pairs(defaults) do Bind(key, initial) end
for key, initial in pairs(unitModeDefaults) do Bind(key, initial) end

local function Reset()
    for key, initial in pairs(defaults) do boxes[key].value = initial end
    for key, initial in pairs(unitModeDefaults) do boxes[key].value = initial end
    A.StartNewTask()
    A.undoStack = {}
    A.redoStack = {}
end

local function Status(result)
    return result and (result.status or result.result)
end

local function Submit(prompt)
    Reset()
    local result = assert(A.Submit(prompt), prompt .. ": missing result")
    local status = Status(result)
    assert(status == "applied" or status == "unchanged",
        prompt .. ": expected a deterministic change, got " .. tostring(status) .. "\n" .. tostring(result.text))
    return result
end

local function ExpectValue(prompt, key, expected)
    local result = Submit(prompt)
    local actual = boxes[key].value
    assert(actual == expected, prompt .. ": expected " .. key .. "=" .. tostring(expected)
        .. ", got " .. tostring(actual) .. "\n" .. tostring(result.text))
end

local function ExpectColor(prompt, key, r, g, b)
    Submit(prompt)
    local actual = boxes[key].value
    assert(type(actual) == "table", prompt .. ": expected a color table")
    assert(actual.r == r and actual.g == g and actual.b == b,
        prompt .. ": wrong color " .. tostring(actual.r) .. "," .. tostring(actual.g) .. "," .. tostring(actual.b))
end

ExpectValue("turn off group frame portrait", "gf_party.portraitMode", "OFF")
for key, initial in pairs(unitModeDefaults) do
    assert(boxes[key].value == initial, "Group Frame portrait command leaked into " .. key)
end
ExpectValue("turn on group frame portrait", "gf_party.portraitMode", "LEFT")
ExpectValue("set group frame portrait position right", "gf_party.portraitMode", "RIGHT")
ExpectValue("set group frame portrait render to class", "gf_party.portraitRender", "CLASS")
ExpectValue("show cast spell icon in group frame portrait", "gf_party.portraitCastSpellIcon", true)
ExpectValue("set group frame portrait shape to circle", "gf_party.portraitShape", "CIRCLE")
ExpectValue("set group frame portrait size to 44", "gf_party.portraitSizeOverride", 44)
ExpectValue("set group frame portrait width to 52", "gf_party.portraitWidth", 52)
ExpectValue("set group frame portrait height to 38", "gf_party.portraitHeight", 38)
ExpectValue("set group frame portrait x to 7", "gf_party.portraitOffsetX", 7)
ExpectValue("set group frame portrait y to -3", "gf_party.portraitOffsetY", -3)
ExpectValue("set group frame portrait zoom to 130", "gf_party.portraitZoom", 130)
ExpectValue("set group frame portrait zoom center x to 15", "gf_party.portraitPanX", 15)
ExpectValue("set group frame portrait zoom center y to -10", "gf_party.portraitPanY", -10)
ExpectValue("set group frame portrait class style to Blizzard Class Icon", "gf_party.portraitClassStyle", "BLIZZARD")
ExpectValue("set group frame portrait placement to detached", "gf_party.portraitPlacement", "DETACHED")
ExpectValue("set group frame portrait anchor point to top right", "gf_party.portraitDetachedPoint", "TOPRIGHT")
ExpectValue("set group frame portrait attach to frame point to bottom left", "gf_party.portraitDetachedTo", "BOTTOMLEFT")
ExpectValue("set group frame portrait overlay alignment to full", "gf_party.portraitOverlayAlign", "FULL")
ExpectValue("set group frame portrait layer to 12", "gf_party.portraitLevelOffset", 12)
ExpectValue("set group frame portrait opacity to 65", "gf_party.portraitAlpha", 65)
ExpectValue("set group frame portrait border to custom", "gf_party.portraitBorderStyle", "CUSTOM")
ExpectValue("set group frame portrait border thickness to 4", "gf_party.portraitBorderThickness", 4)
ExpectValue("turn on group frame portrait fill border", "gf_party.portraitFillBorder", true)
ExpectValue("set group frame portrait border art to relief", "gf_party.portraitBorderArt", "RELIEF")
ExpectValue("set group frame portrait border direction to right", "gf_party.portraitBorderDirection", "RIGHT")
ExpectColor("set group frame portrait border color to red", "gf_party.portraitBorderColor", 1, 0, 0)
ExpectValue("set group frame portrait border opacity to 50%", "gf_party.portraitBorderColorA", 0.5)
ExpectValue("turn on group frame portrait background", "gf_party.portraitBgEnabled", true)
ExpectColor("set group frame portrait background color to blue", "gf_party.portraitBgColor", 0, 0, 1)
ExpectValue("set group frame portrait background opacity to 75%", "gf_party.portraitBgColorA", 0.75)

for key in pairs(defaults) do
    local setting = assert(Registry:GetSetting(key))
    local found = false
    for i = 1, #(setting.aliases or {}) do
        if tostring(setting.aliases[i]):find("^group frame portrait") then
            found = true
            break
        end
    end
    assert(found, key .. " lacks a group frame portrait alias")
end

print("PASS Assistant Group Frame portrait routing: full Party-only control matrix")
