local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

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
        if child and child[kindKey] and not (alwaysEnabledFlag and child[alwaysEnabledFlag]) then
            callback(child)
        end
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
    elseif state[stateKey] == (enabled and true or false) then
        return false
    end

    enabled = enabled and true or false
    state[stateKey] = enabled
    ForEachControl(root, opts, function(control)
        W.SetControlGateEnabled(control, gateKey, enabled)
    end)
    return true
end

Gates.ForEachControl = ForEachControl
