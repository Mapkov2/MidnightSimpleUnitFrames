_G = _G or _ENV

package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
require("wow_stubs")

local Loader = require("assistant_runtime_manifest_loader")
assert(Loader.LoadAssistantRuntime(_G.MSUF_NS, { useCompanionPrivate = true }))

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant)
local Registry = assert(A.Registry)

local function FakeSetting(setting, initial)
    local original = { get = setting.get, set = setting.set, apply = setting.apply }
    local value = initial
    setting.get = function() return value end
    setting.set = function(nextValue) value = nextValue end
    setting.apply = function() return true end
    return function() setting.get, setting.set, setting.apply = original.get, original.set, original.apply end,
        function() return value end
end

local unitCount, groupCount = 0, 0
for _, setting in ipairs(Registry:AllSettings()) do
    local scope = tostring(setting.key or ""):match("^auras3%.([^.]+)%.[^.]+%.filter%.")
    if scope and scope ~= "shared" then
        local own = assert(Registry:GetSetting("auras3." .. scope .. ".useSharedRules"))
        local gate = assert(Registry:GetSetting("auras3." .. scope .. ".filtersEnabled"))
        local desired = setting.type == "enum" and ((setting.values and setting.values[2]) or "raid") or true
        local restoreOwn, readOwn = FakeSetting(own, true)
        local restoreGate, readGate = FakeSetting(gate, false)
        local restoreTarget, readTarget = FakeSetting(setting, setting.type == "enum" and "none" or false)
        A.undoStack, A.redoStack = {}, {}
        local result = A.ExecutePlan({ kind = "changes", changes = { { setting = setting, value = desired } }, label = setting.label })
        assert(result and result.status == "applied", tostring(setting.key) .. ": " .. tostring(result and result.text))
        assert(readOwn() == false, tostring(setting.key) .. " did not activate Own filters")
        assert(readGate() == true, tostring(setting.key) .. " did not enable the filter master gate")
        assert(readTarget() == desired, tostring(setting.key) .. " did not apply its requested value")
        restoreTarget(); restoreGate(); restoreOwn()
        unitCount = unitCount + 1
    end

    local lanePrefix = tostring(setting.key or ""):match("^(gf_[^.]+%.auras%.[^.]+)%.filterToken$")
    if lanePrefix then
        local enabled = assert(Registry:GetSetting(lanePrefix .. ".enabled"))
        local desired = (setting.values and setting.values[2]) or "PLAYER"
        local restoreEnabled, readEnabled = FakeSetting(enabled, false)
        local restoreTarget, readTarget = FakeSetting(setting, setting.values and setting.values[1] or "ALL")
        A.undoStack, A.redoStack = {}, {}
        local result = A.ExecutePlan({ kind = "changes", changes = { { setting = setting, value = desired } }, label = setting.label })
        assert(result and result.status == "applied", tostring(setting.key) .. ": " .. tostring(result and result.text))
        assert(readEnabled() == true, tostring(setting.key) .. " did not enable its Group Aura lane")
        assert(readTarget() == desired, tostring(setting.key) .. " did not apply its requested value")
        restoreTarget(); restoreEnabled()
        groupCount = groupCount + 1
    end
end

assert(unitCount > 0 and groupCount > 0, "Aura filter registry families were not discovered")
print(string.format("assistant_aura_filter_transaction_smoke: ok unit_filters=%d group_filters=%d", unitCount, groupCount))
