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

local apiHandle = assert(io.open("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_API.lua", "r"))
local apiSource = apiHandle:read("*a")
apiHandle:close()
assert(apiSource:find("MSUF_OpenExactColorSettingPicker", 1, true), "public color-picker bridge missing")
assert(apiSource:find("catalog.FindBySettingKey", 1, true), "color-picker bridge does not resolve the exact setting")
assert(apiSource:find("OpenColorContextPicker", 1, true), "color-picker bridge does not open Color Painter")

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant runtime missing")
local Registry = assert(A.Registry, "Assistant registry missing")
local targetColor = assert(Registry:GetSetting("general.castbarTargetNameColor"), "target-name color setting missing")
local textColor = assert(Registry:GetSetting("general.castbarFontColor"), "castbar text color setting missing")

local targetValue = { r = 1, g = 1, b = 1, label = "white" }
local textValue = { r = 1, g = 1, b = 1, label = "white" }
targetColor.get = function() return targetValue end
targetColor.set = function(value) targetValue = value end
targetColor.apply = function() return true end
textColor.get = function() return textValue end
textColor.set = function(value) textValue = value end
textColor.apply = function() return true end

local calls = {}
_G.MSUF_OpenExactColorSettingPicker = function(settingKey, label, page)
    calls[#calls + 1] = { settingKey = settingKey, label = label, page = page }
    return true, "Opened Color Painter for " .. tostring(label) .. "."
end

local function Reset()
    calls = {}
    A.StartNewTask()
    A.undoStack, A.redoStack = {}, {}
end

Reset()
local applied = assert(A.Submit("set castbar target name color to red"), "explicit color result missing")
assert(applied.status == "applied" or applied.status == "unchanged", tostring(applied.text))
assert(applied.colorPickerOpened == true, "explicit color change did not report the picker")
assert(#calls == 1, "explicit color change should open one picker")
assert(calls[1].settingKey == "general.castbarTargetNameColor", "picker opened the wrong setting")
assert(calls[1].page == "opt_colors", "picker opened the wrong page")

Reset()
local before = targetValue
local valueLess = assert(A.Submit("change castbar target name color"), "value-less color result missing")
assert(valueLess.status == "navigated", tostring(valueLess.text))
assert(valueLess.colorPickerOpened == true, "value-less color request did not open the picker")
assert(#calls == 1 and calls[1].settingKey == "general.castbarTargetNameColor",
    "value-less request opened the wrong picker")
assert(targetValue == before, "value-less color request mutated the setting before picker input")

Reset()
local multi = assert(A.ExecutePlan({
    kind = "changes",
    changes = {
        { setting = targetColor, value = { r = 0, g = 1, b = 0, label = "green" } },
        { setting = textColor, value = { r = 0, g = 0, b = 1, label = "blue" } },
    },
    label = "Two castbar colors",
    summary = "Changes two different color settings.",
}))
assert(multi.status == "applied" or multi.status == "unchanged", tostring(multi.text))
assert(#calls == 0, "multi-color changes must not guess which picker setting to select")

print("assistant color picker bridge smoke: ok")
