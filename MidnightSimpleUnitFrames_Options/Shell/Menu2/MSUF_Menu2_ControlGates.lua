local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local Gates = M.ControlGates or {}
M.ControlGates = Gates
local type = type
local tostring = tostring
local function ForEachControl(parent, opts, callback)
    if not (parent and parent.GetChildren and type(callback) == "function") then return end
    opts = opts or {}
    local kindKey = opts.kindKey or "_msuf2ControlKind"
    local alwaysEnabledFlag = opts.alwaysEnabledFlag
    local children = { parent:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child[kindKey] and not (alwaysEnabledFlag and child[alwaysEnabledFlag]) then callback(child) end
        ForEachControl(child, opts, callback)
    end
end
function Gates.Apply(root, gateKey, enabled, opts)
    if not (root and gateKey and W.SetControlGateEnabled) then return false end
    opts = opts or {}
    gateKey = tostring(gateKey)
    local stateKey = tostring(opts.stateKey or gateKey)
    local state = root._msuf2ControlGateState
    if not state then
        state = {}
        root._msuf2ControlGateState = state
    end
    enabled = enabled and true or false
    local changed = state[stateKey] ~= enabled
    state[stateKey] = enabled
    local exclusivePrefix = opts.exclusivePrefix and tostring(opts.exclusivePrefix) or nil
    local stale = {}
    ForEachControl(root, opts, function(control)
        if exclusivePrefix and type(control._msuf2DisableGates) == "table" and W.ClearControlGate then
            local staleCount = 0
            for key in pairs(control._msuf2DisableGates) do
                if key ~= gateKey and key:sub(1, #exclusivePrefix) == exclusivePrefix then
                    staleCount = staleCount + 1
                    stale[staleCount] = key
                end
            end
            for i = 1, staleCount do
                W.ClearControlGate(control, stale[i], true)
                stale[i] = nil
            end
        end
        W.SetControlGateEnabled(control, gateKey, enabled)
    end)
    return changed
end
Gates.ForEachControl = ForEachControl
