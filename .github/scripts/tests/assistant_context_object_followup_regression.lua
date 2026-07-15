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
local Parser = assert(A.Parser, "Assistant parser missing")

local function status(result)
    return result and (result.status or result.result)
end

local defaults = {
    ["target.portraitMode"] = "OFF",
    ["target.portraitSizeOverride"] = 40,
    ["target.portraitOffsetY"] = 0,
    ["target.portraitShape"] = "SQUARE",
    ["target.portraitRender"] = "2D",
    ["target.portraitBorderStyle"] = "SOLID",
    ["target.portraitBorderThickness"] = 2,
    ["target.portraitZoom"] = 120,
    ["target.offsetX"] = 0,
    ["target.offsetY"] = 7,
    ["target.width"] = 250,
    ["target.height"] = 40,
    ["target.showRaidMarker"] = false,
    ["target.raidMarkerAnchor"] = "TOPLEFT",
    ["target.raidMarkerSize"] = 18,
    ["target.nameTextAnchor"] = "LEFT",
    ["target.nameFontSize"] = 12,
    ["general.castbarTargetIconPosition"] = "LEFT",
    ["general.castbarTargetIconSize"] = 20,
    ["general.castbarTargetOffsetX"] = 0,
    ["general.castbarTargetBarWidth"] = 200,
    ["general.castbarTargetBarHeight"] = 20,
    ["auras3.target.buff.anchor"] = "TOPLEFT",
    ["auras3.target.buff.size"] = 20,
    ["auras3.target.buff.visible"] = true,
    ["gf_party.readyCheckAnchor"] = "TOPLEFT",
    ["gf_party.readyCheckSize"] = 16,
    ["gf_party.groupBorderSize"] = 2,
    ["gf_party.groupBorderColor"] = { r = 1, g = 1, b = 1, label = "white" },
}

local boxes = {}
for key, initial in pairs(defaults) do
    local setting = assert(Registry:GetSetting(key), "missing setting " .. key)
    local box = { value = initial }
    boxes[key] = box
    setting.get = function() return box.value end
    setting.set = function(value) box.value = value end
    setting.apply = function() return true end
end

local function reset()
    for key, initial in pairs(defaults) do boxes[key].value = initial end
    A.StartNewTask()
    A.undoStack = {}
    A.redoStack = {}
end

local function submit(prompt)
    local result = assert(A.Submit(prompt), prompt .. ": missing result")
    assert(status(result) == "applied" or status(result) == "unchanged", prompt .. ": " .. tostring(result.text))
    return result
end

local function expectValue(key, expected, message)
    assert(boxes[key].value == expected, (message or key) .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(boxes[key].value))
end

reset()
submit("set target portrait position left")
submit("make it smaller")
expectValue("target.portraitSizeOverride", 39, "portrait follow-up did not resize the portrait")
expectValue("target.width", 250, "portrait follow-up resized the Target frame")

reset()
submit("set target portrait position left")
submit("move it down")
expectValue("target.portraitOffsetY", -10, "portrait movement did not use Portrait Y Offset")
expectValue("target.offsetY", 7, "portrait movement leaked into Target Y Position")

reset()
submit("set target portrait position left")
submit("make it circular")
expectValue("target.portraitShape", "CIRCLE")

reset()
submit("set target portrait position left")
submit("render it as class portrait")
expectValue("target.portraitRender", "CLASS")

reset()
submit("set target portrait position left")
submit("make its border thicker")
expectValue("target.portraitBorderThickness", 3)

reset()
submit("set target portrait position left")
submit("set its border style to class color")
expectValue("target.portraitBorderStyle", "CLASS_COLOR")

reset()
submit("set target portrait position left")
submit("hide it")
expectValue("target.portraitMode", "OFF", "portrait visibility follow-up did not stay on the portrait")

reset()
submit("show target raid marker")
submit("make it smaller")
expectValue("target.raidMarkerSize", 17)
expectValue("target.width", 250, "raid-marker follow-up resized the Target frame")

reset()
submit("set target castbar icon position right")
submit("make it smaller")
expectValue("general.castbarTargetIconSize", 19)
expectValue("general.castbarTargetBarWidth", 200, "castbar-icon follow-up resized the castbar")

reset()
submit("set target name text anchor right")
submit("make it smaller")
expectValue("target.nameFontSize", 11)
expectValue("target.width", 250, "name-text follow-up resized the Target frame")

reset()
submit("set target buff anchor top right")
submit("make it smaller")
expectValue("auras3.target.buff.size", 19)
submit("hide it")
expectValue("auras3.target.buff.visible", false)

reset()
submit("set party ready check anchor top right")
submit("make it smaller")
expectValue("gf_party.readyCheckSize", 15)

reset()
submit("move target frame left 10")
submit("make it smaller")
expectValue("target.width", 249)
expectValue("target.height", 39)
expectValue("target.offsetX", -10)

reset()
submit("move target castbar left 10")
submit("make it smaller")
expectValue("general.castbarTargetBarWidth", 199)
expectValue("general.castbarTargetBarHeight", 19)
expectValue("general.castbarTargetOffsetX", -10)

reset()
submit("set target portrait zoom to 120")
submit("make it smaller")
expectValue("target.portraitZoom", 119, "numeric follow-up abandoned the exact retained property")
expectValue("target.portraitSizeOverride", 40, "numeric zoom follow-up switched to portrait size")

reset()
submit("set party group border thickness to 3")
submit("make it red")
local borderColor = boxes["gf_party.groupBorderColor"].value
assert(type(borderColor) == "table" and tonumber(borderColor.r) == 1 and tonumber(borderColor.g) == 0
    and tonumber(borderColor.b) == 0, "color follow-up did not use the retained group-border object")

reset()
submit("set target portrait position left")
local widthBefore = boxes["target.width"].value
local unsupportedSibling = A.Submit("make it wider")
assert(status(unsupportedSibling) ~= "applied", "unsupported portrait width follow-up guessed another control")
expectValue("target.width", widthBefore, "unsupported portrait width fell back to Target Width")

local retainedContext = {
    turnSerial = 2,
    lastSubjectTurn = 1,
    lastChangeBundle = {
        { key = "target.portraitMode", unit = "target", frameType = "unitframe", attribute = "portraitMode", oldValue = "OFF", value = "LEFT" },
        { key = "target.raidMarkerAnchor", unit = "target", frameType = "unitframe", attribute = "raidmarkerAnchor", oldValue = "TOPLEFT", value = "TOPRIGHT" },
    },
}
local singular = assert(Parser.BuildFollowup("make it smaller", retainedContext), "singular multi-object follow-up missing")
assert(singular.kind == "ambiguous", "singular follow-up guessed across multiple retained objects")
local plural = assert(Parser.BuildFollowup("make them smaller", retainedContext), "plural multi-object follow-up missing")
assert(plural.kind == "changes" and #plural.changes == 2, "plural follow-up did not retain both named objects")

local staleContext = {
    turnSerial = 8,
    lastSubjectTurn = 1,
    lastChangeBundle = retainedContext.lastChangeBundle,
}
assert(Parser.BuildFollowup("make it smaller", staleContext) == nil, "stale context was reused as a mutation owner")

io.write("assistant_context_object_followup_regression: ok cases=20\n")
