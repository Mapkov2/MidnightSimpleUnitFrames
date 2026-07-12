-- Assistant UnitFrame detached power bar helpers.
-- Loaded before MSUF_AssistantRegistry_Unitframes_Power.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

local function AddUniqueAlias(out, seen, value)
    value = tostring(value or "")
    if value == "" or seen[value] then return end
    seen[value] = true
    out[#out + 1] = value
end

local function AddDetachedPowerVerbAliases(out, unit, verbs, noun)
    local unitAliases = (A.UnitAliases and A.UnitAliases[unit]) or { unit }
    for v = 1, #(verbs or {}) do
        local verb = verbs[v]
        for i = 1, #unitAliases do
            local unitText = unitAliases[i]
            out[#out + 1] = tostring(verb) .. " " .. tostring(unitText) .. " " .. tostring(noun)
        end
    end
end

local function DetachedPowerMoveAliases(unit, axis)
    local out, seen = {}, {}
    local unitAliases = (A.UnitAliases and A.UnitAliases[unit]) or { unit }
    local nouns = { "powerbar", "power bar", "detached powerbar", "detached power bar" }
    local directions = axis == "y"
        and { "up", "down", "hoch", "runter", "oben", "unten" }
        or { "left", "right", "links", "rechts" }
    local axisTerms = axis == "y"
        and { "y offset", "y position", "vertical offset", "vertical position" }
        or { "x offset", "x position", "horizontal offset", "horizontal position" }

    for i = 1, #unitAliases do
        local unitText = tostring(unitAliases[i])
        for n = 1, #nouns do
            local noun = nouns[n]
            for d = 1, #directions do
                local dir = directions[d]
                AddUniqueAlias(out, seen, unitText .. " " .. noun .. " " .. dir)
                AddUniqueAlias(out, seen, "move " .. unitText .. " " .. noun .. " " .. dir)
                AddUniqueAlias(out, seen, "nudge " .. unitText .. " " .. noun .. " " .. dir)
                AddUniqueAlias(out, seen, "shift " .. unitText .. " " .. noun .. " " .. dir)
                if axis == "x" then
                    AddUniqueAlias(out, seen, unitText .. " " .. noun .. " to the " .. dir)
                    AddUniqueAlias(out, seen, "move " .. unitText .. " " .. noun .. " to the " .. dir)
                else
                    AddUniqueAlias(out, seen, unitText .. " " .. noun .. " " .. (dir == "up" and "higher" or (dir == "down" and "lower" or dir)))
                end
            end
            for t = 1, #axisTerms do
                local term = axisTerms[t]
                AddUniqueAlias(out, seen, unitText .. " " .. noun .. " " .. term)
                AddUniqueAlias(out, seen, "set " .. unitText .. " " .. noun .. " " .. term)
                AddUniqueAlias(out, seen, "move " .. unitText .. " " .. noun .. " " .. term)
            end
        end
    end
    return out
end

local function TextHasAny(text, terms)
    text = tostring(text or ""):lower()
    for i = 1, #(terms or {}) do
        if text:find(tostring(terms[i] or ""):lower(), 1, true) then return true end
    end
    return false
end

local function DetachedPowerMoveGuard(ctx, unit)
    return function(_, text)
        if TextHasAny(text, { "detached", "undocked", "separate", "separated", "abgekoppelt" }) then return nil end
        if ctx.UnitDB(unit).powerBarDetached == true then return nil end
        local unitLabel = A and type(A.DisplayUnitLabel) == "function" and A.DisplayUnitLabel(unit) or ((A.UnitLabels and A.UnitLabels[unit]) or unit or "That unit")
        return {
            kind = "unknown",
            status = "failed",
            text = tostring(unitLabel)
                .. " Power Bar is attached to the unit frame, so the bar itself has no separate position. Detach it first, or use 'move "
                .. tostring(unitLabel):lower()
                .. " power text left' to move only the text.",
        }
    end
end

local function InitDetachedPowerBar(ctx, unit)
    local conf = ctx.UnitDB(unit)
    conf.detachedPowerBarOffsetX = tonumber(conf.detachedPowerBarOffsetX) or 0
    conf.detachedPowerBarOffsetY = tonumber(conf.detachedPowerBarOffsetY) or -4
    conf.detachedPowerBarWidth = tonumber(conf.detachedPowerBarWidth) or tonumber(conf.width) or (unit == "focus" and 180 or 275)
    conf.detachedPowerBarHeight = tonumber(conf.detachedPowerBarHeight) or 6
    conf.detachedPowerBarFrameLevelOffset = tonumber(conf.detachedPowerBarFrameLevelOffset) or 6
    if unit == "player" and conf.detachedPowerBarSyncClassPower == nil then conf.detachedPowerBarSyncClassPower = true end
    if unit == "player" and conf.detachedPowerBarShape == nil then conf.detachedPowerBarShape = "BAR" end
    if unit == "player" and conf.detachedPowerOrbSize == nil then conf.detachedPowerOrbSize = 54 end
end

A.UnitframesRegistry.AddDetachedPowerVerbAliases = AddDetachedPowerVerbAliases
A.UnitframesRegistry.DetachedPowerMoveAliases = DetachedPowerMoveAliases
A.UnitframesRegistry.DetachedPowerMoveGuard = DetachedPowerMoveGuard
A.UnitframesRegistry.InitDetachedPowerBar = InitDetachedPowerBar
