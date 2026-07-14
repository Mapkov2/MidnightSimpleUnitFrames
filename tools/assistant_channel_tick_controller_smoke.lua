-- Focused channel-tick Assistant ownership/runtime/transaction regression.
_G = _G or _ENV
package.path = "tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path

require("wow_stubs")
local Loader = require("assistant_runtime_manifest_loader")
local MSUF = assert(_G.MSUF_NS, "WoW stubs did not create MSUF_NS")

local function LoadProduct(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    local ok, result = pcall(chunk, "MidnightSimpleUnitFrames", MSUF)
    assert(ok, path .. ": " .. tostring(result))
end

local function Equal(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do if not Equal(value, right[key], seen) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local function Status(result)
    return type(result) == "table" and (result.status or result.result) or nil
end

local function AssertRejected(fn, label)
    local ok = pcall(fn)
    assert(not ok, label .. " was accepted")
end

LoadProduct("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
local db = assert(_G.MSUF_EnsureDB(true), "defaults did not seed a profile")
local castbar = assert(db.player and db.player.castbar, "player castbar defaults missing")
assert(rawget(castbar, "channelTickPreviewDuration") == nil,
    "fresh profile still seeds retired channelTickPreviewDuration")
assert(rawget(castbar, "channelTickPreviewLoop") == nil,
    "fresh profile still seeds retired channelTickPreviewLoop")

-- Existing legacy values are deliberately preserved rather than migrated or
-- cleared by the fresh-profile cleanup.
castbar.channelTickPreviewDuration = 4.25
castbar.channelTickPreviewLoop = false
assert(_G.MSUF_EnsureDB(true) == db, "EnsureDB replaced the active profile")
assert(castbar.channelTickPreviewDuration == 4.25 and castbar.channelTickPreviewLoop == false,
    "EnsureDB damaged existing retired preview state")

Loader.LoadAssistantRuntime(MSUF, {
    root = ".",
    includeDashboard = true,
    includeDialogLocale = true,
    useCompanionPrivate = true,
})
LoadProduct("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarChannelTicks.lua")

local A = assert(MSUF.Assistant, "Assistant runtime missing")
local Registry = assert(A.Registry, "Assistant Registry missing")
local visible = assert(Registry:GetSetting("general.castbarShowChannelTicks"), "global tick setting missing")
local custom = assert(Registry:GetSetting("player.castbar.channelTickUseCustom"), "custom tick setting missing")
local count = assert(Registry:GetSetting("player.castbar.channelTickCount"), "tick count setting missing")
local positions = assert(Registry:GetSetting("player.castbar.channelTickPosPct"), "tick positions setting missing")

assert(visible.type == "boolean" and custom.type == "boolean", "tick gates are not typed booleans")
assert(count.type == "number" and count.min == 0 and count.max == 10 and count.step == 1,
    "tick count numeric contract drifted")
assert(positions.type == "string" and positions.orderedList == true
    and positions.elementType == "number" and positions.elementMin == 0 and positions.elementMax == 100
    and positions.maxCount == 10 and positions.countSettingKey == count.key,
    "tick position ordered-list metadata drifted")
assert(type(positions.captureTransactionState) == "function"
    and type(positions.restoreTransactionState) == "function",
    "tick position deep transaction adapter missing")
for _, setting in ipairs({ custom, count, positions }) do
    assert(setting.page == "opt_castbar" and setting.menuControlDisposition == "standalone"
        and type(setting.menuControlDispositionReason) == "string" and setting.menuControlDispositionReason ~= ""
        and type(setting.menuControlDispositionEvidence) == "string" and setting.menuControlDispositionEvidence ~= "",
        tostring(setting.key) .. " lacks its reviewed no-widget navigation disposition")
end

local function Owns(setting, scope, dbKey)
    for i = 1, #(setting.dbScopes or {}) do
        local row = setting.dbScopes[i]
        if row.scope == scope and row.dbKey == dbKey then return true end
    end
    return false
end
assert(Owns(custom, "player", "castbar.channelTickUseCustom"), "custom gate physical owner missing")
assert(Owns(count, "player", "castbar.channelTickCount"), "count physical owner missing")
assert(Owns(positions, "player", "castbar.channelTickPosPct"), "positions physical owner missing")

local applyCalls = 0
local realApply = assert(_G.MSUF_UpdateCastbarChannelTicks, "channel tick runtime apply hook missing")
_G.MSUF_UpdateCastbarChannelTicks = function(...)
    applyCalls = applyCalls + 1
    return realApply(...)
end

castbar.channelTickUseCustom = true
castbar.channelTickCount = 3
castbar.channelTickPosPct = { 20, 50, 80 }
db.general.castbarShowChannelTicks = true
assert(_G.MSUF_IsChannelTickLinesEnabled() == true, "enabled custom tick configuration is not live")

-- The Assistant's visible Off write must be authoritative even when the old
-- hidden custom switch remains enabled.
A.undoStack, A.redoStack = {}, {}
local result = A.ExecutePlan({
    kind = "changes",
    changes = { { setting = visible, value = false } },
    label = "Disable channel ticks",
})
assert(Status(result) == "applied", "global tick off transaction failed: " .. tostring(result and result.text))
assert(visible.get() == false and _G.MSUF_IsChannelTickLinesEnabled() == false,
    "Assistant reported Off while custom ticks remained effective")
assert(A.UndoLast() == true and _G.MSUF_IsChannelTickLinesEnabled() == true,
    "global tick Off undo did not restore effective runtime state")
assert(A.RedoLast() == true and _G.MSUF_IsChannelTickLinesEnabled() == false,
    "global tick Off redo did not restore effective runtime state")
visible.set(true)

-- Scalar and list setters reject unsafe direct writes. ExecuteChanges still
-- performs the standard number clamp/step normalization before count.set.
AssertRejected(function() count.set(2.5) end, "fractional tick count")
AssertRejected(function() count.set(0 / 0) end, "NaN tick count")
AssertRejected(function() count.set(math.huge) end, "infinite tick count")
AssertRejected(function() positions.set("10, 90") end, "wrong-length position list")
AssertRejected(function() positions.set("10, nan, 90") end, "non-finite position list")
AssertRejected(function() positions.set("-1, 40, 90") end, "out-of-range position list")
AssertRejected(function() positions.set("10, 10, 90") end, "non-increasing position list")

local supplied = { 10, 40, 90 }
positions.set(supplied)
supplied[1] = 99
assert(castbar.channelTickPosPct[1] == 10, "position setter retained the caller's mutable table")
positions.set("20, 50, 80")

-- The transaction captures both the before and after arrays deeply. Mutating
-- obsolete/current table references cannot corrupt later undo or redo.
A.undoStack, A.redoStack = {}, {}
local beforeReference = castbar.channelTickPosPct
result = A.ExecutePlan({
    kind = "changes",
    changes = { { setting = positions, value = "10%, 40%, and 90%" } },
    label = "Set custom channel tick positions",
})
assert(Status(result) == "applied", "position transaction failed: " .. tostring(result and result.text))
assert(Equal(castbar.channelTickPosPct, { 10, 40, 90 }), "position transaction stored the wrong order")
local afterReference = castbar.channelTickPosPct
beforeReference[1] = 99
afterReference[2] = 41
assert(A.UndoLast() == true, "position undo failed")
assert(Equal(castbar.channelTickPosPct, { 20, 50, 80 }), "position undo did not restore the deep before-state")
assert(A.RedoLast() == true, "position redo failed")
assert(Equal(castbar.channelTickPosPct, { 10, 40, 90 }), "position redo did not restore the deep after-state")
assert(applyCalls >= 5, "channel tick transactions did not use the focused runtime apply hook")

positions.set("auto")
assert(type(castbar.channelTickPosPct) == "table" and #castbar.channelTickPosPct == 0
    and positions.get() == "auto", "Auto did not select deterministic even spacing")

-- Confirm the public conversational surface resolves the three new owners.
local function FindChange(plan, key)
    for i = 1, #(plan and plan.changes or {}) do
        local change = plan.changes[i]
        if change.setting and change.setting.key == key then return change end
    end
end

local parsed = A.Parse("turn on custom channel tick layout")
local change = FindChange(parsed, custom.key)
assert(change and change.value == true, "natural custom-layout request did not resolve its owner")
parsed = A.Parse("set custom channel tick count to 3")
change = FindChange(parsed, count.key)
assert(change and change.value == 3, "natural custom-count request did not resolve its owner")
parsed = A.Parse("set custom channel tick positions to 10, 40, 90")
change = FindChange(parsed, positions.key)
assert(change and change.value == "10, 40, 90", "natural position-list request did not resolve atomically")

print(string.format("assistant_channel_tick_controller_smoke: ok owners=3 apply_calls=%d", applyCalls))
