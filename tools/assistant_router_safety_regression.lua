_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

-- Some repository Lua files intentionally retain an UTF-8 BOM. WoW accepts
-- them, while the standalone Lua 5.1 loadfile does not, so the test loader
-- strips only that transport marker before compiling a chunk.
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

local function status(result)
    return result and (result.status or result.result)
end

local function lower(value)
    return tostring(value or ""):lower()
end

local function resetTask()
    A.StartNewTask()
    A.undoStack = {}
    A.redoStack = {}
end

local function patchSetting(key, initial)
    local setting = assert(Registry:GetSetting(key), "missing setting " .. key)
    local original = { get = setting.get, set = setting.set, apply = setting.apply }
    local box = { value = initial }
    setting.get = function() return box.value end
    setting.set = function(value) box.value = value end
    setting.apply = function() return true end
    return setting, box, original
end

local hideSetting, hideBox, hideOriginal = patchSetting(
    "auras3.player.buff.blacklist.hidePermanent", false)
local widthSetting, widthBox, widthOriginal = patchSetting("target.width", 275)

local refusalPrompts = {
    { "do not hide player buffs with no duration", true },
    { "never hide player buffs with no duration", false },
}
for i = 1, #refusalPrompts do
    resetTask()
    local prompt, initial = refusalPrompts[i][1], refusalPrompts[i][2]
    hideBox.value = initial
    local result = assert(A.Submit(prompt), prompt .. ": missing result")
    assert(status(result) == "info", prompt .. ": expected read-only info")
    assert(hideBox.value == initial, prompt .. ": changed Hide Permanent despite refusal")
    assert(#A.undoStack == 0, prompt .. ": created an undoable mutation")
    local output = lower(result.text)
    assert(output:find("unchanged", 1, true) or output:find("kept", 1, true)
        or output:find("did not", 1, true), prompt .. ": did not acknowledge unchanged state")
end

resetTask()
hideBox.value = false
local semanticFilter = assert(A.Submit("do not show player buffs that have no timer"))
assert(status(semanticFilter) == "applied" or status(semanticFilter) == "unchanged",
    "semantic no-timer filter was no longer actionable")
assert(hideBox.value == true, "semantic no-timer filter did not enable Hide Permanent")

local unsupported = {
    { "can you rotate player frame in 3D", "3d frame-rotation control" },
    { "can you add a weather radar", "weather data or a radar widget" },
    { "can you play chess", "cannot play chess" },
    { "is it possible to rotate player frame in 3D", "3d frame-rotation control" },
    { "could i add a weather radar", "weather data or a radar widget" },
}
for i = 1, #unsupported do
    resetTask()
    widthBox.value = 275
    local prompt, expected = unsupported[i][1], unsupported[i][2]
    local result = assert(A.Submit(prompt), prompt .. ": missing result")
    local output = lower(result.text)
    assert(status(result) == "info", prompt .. ": expected read-only info")
    assert(output:find(expected, 1, true), prompt .. ": missing honest capability boundary: " .. output)
    assert(not output:match("^yes[%s%p]"), prompt .. ": answered an unsupported capability with yes")
    assert(output:find("unchanged", 1, true), prompt .. ": did not say settings were unchanged")
    assert(widthBox.value == 275 and #A.undoStack == 0, prompt .. ": mutated MSUF state")
end

resetTask()
widthBox.value = 275
local supported = assert(A.Submit("is it possible to change target width to 300"))
assert(status(supported) == "info", "verified capability question did not stay read-only")
assert(tostring(supported.text):find("Target Width", 1, true), "verified capability omitted its real control")
assert(widthBox.value == 275 and #A.undoStack == 0, "verified capability question changed Target Width")

resetTask()
widthBox.value = 275
local directPoliteWrite = assert(A.Submit("can you set target width to 300"))
assert(status(directPoliteWrite) == "applied" or status(directPoliteWrite) == "unchanged",
    "ordinary polite setting command was mistaken for a capability question")
assert(widthBox.value == 300, "ordinary polite setting command no longer changed Target Width")

resetTask()
widthBox.value = 275
local politeNumericAdd = assert(A.Submit("can you add 5 to target width"))
assert(status(politeNumericAdd) == "applied" or status(politeNumericAdd) == "unchanged",
    "polite numeric add was mistaken for an unsupported capability")
assert(widthBox.value == 280, "polite numeric add no longer adjusted Target Width: value="
    .. tostring(widthBox.value) .. " status=" .. tostring(status(politeNumericAdd))
    .. " text=" .. tostring(politeNumericAdd.text))

resetTask()
local politeAuraAdd = assert(A.Submit("can you add Rejuvenation to target buff blacklist"))
local auraOutput = lower(politeAuraAdd.text)
assert(not auraOutput:find("could not verify that as an msuf capability", 1, true),
    "polite aura-list action was intercepted as an unsupported capability")
assert(auraOutput:find("rejuvenation", 1, true) or auraOutput:find("blacklist", 1, true),
    "polite aura-list action did not reach aura guidance")

hideSetting.get, hideSetting.set, hideSetting.apply = hideOriginal.get, hideOriginal.set, hideOriginal.apply
widthSetting.get, widthSetting.set, widthSetting.apply = widthOriginal.get, widthOriginal.set, widthOriginal.apply

io.write("assistant_router_safety_regression: ok cases=12\n")
