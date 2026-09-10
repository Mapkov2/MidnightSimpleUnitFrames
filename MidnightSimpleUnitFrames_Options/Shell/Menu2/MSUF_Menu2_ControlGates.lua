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
-- Scope only setting sections: page/unit selectors and preview chrome remain
-- available so a disabled frame never traps the user on its page.
function Gates.ApplySections(ctx, gateKey, enabled, opts)
    local page = ctx and ctx.entry
    if not page then return end
    page._msuf2FrameGate = { key = gateKey, enabled = enabled, opts = opts }
    for id, section in pairs(page.sections or {}) do
        local entry = section._msuf2CollapsibleEntry
        if entry and not tostring(id):lower():find("preview", 1, true) then
            Gates.Apply(entry.outer, gateKey, enabled, opts)
            local primary = id == "frame_basics" or id == "general"
            entry.header:SetAlpha((enabled or primary) and 1 or 0.48)
            if primary and entry.label then
                local title = M.Tr("Frame Basics")
                if not enabled then title = title .. " - " .. M.Tr("Frame disabled") end
                entry.label:SetText(title)
                local color = enabled and M.Theme.colors.text or M.Theme.colors.disabled
                entry.label:SetTextColor(color[1], color[2], color[3], 1)
            end
        end
    end
end
