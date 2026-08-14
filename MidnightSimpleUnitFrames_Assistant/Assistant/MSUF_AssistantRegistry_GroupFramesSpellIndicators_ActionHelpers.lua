-- Assistant GroupFrames spell indicator action helpers.
-- Keeps field mutation logic separate from action registration.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildSpellIndicatorActionHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Scope = ctx.Scope
    local ResolveSpec = ctx.ResolveSpec
    local ResolveAura = ctx.ResolveAura
    local SpellEntry = ctx.SpellEntry
    local ApplySpell = ctx.ApplySpell
    local ClampNumber = ctx.ClampNumber
    local Clamp01 = ctx.Clamp01
    local Placed = ctx.Placed
    local FrameEffect = ctx.FrameEffect

    if type(Scope) ~= "function" or type(ResolveSpec) ~= "function" or type(ResolveAura) ~= "function" then return nil end
    if type(SpellEntry) ~= "function" or type(ApplySpell) ~= "function" then return nil end
    if type(ClampNumber) ~= "function" or type(Clamp01) ~= "function" then return nil end
    if type(Placed) ~= "function" or type(FrameEffect) ~= "function" then return nil end

    local function ActionTarget(args)
        local scope = Scope(args and args.scope)
        local specKey = ResolveSpec(args and args.spec)
        local auraName, resolvedSpec, display = ResolveAura(specKey, tostring(args and (args.aura or args.text) or ""))
        return scope, specKey or resolvedSpec, auraName, display or auraName
    end

    local function SetSpellField(scope, specKey, auraName, field, value)
        local entry = SpellEntry(scope, specKey, auraName, true)
        if not entry then return false end
        if field == "enabled" then entry.enabled = value and true or false
        elseif field == "onlyOwn" then entry.onlyOwn = value and true or false
        elseif field == "placedType" then
            if value == "none" then entry.placed = false else Placed(entry, true).type = value or "icon" end
        elseif field == "placedAnchor" then Placed(entry, true).anchor = value or "TOPLEFT"
        elseif field == "placedSize" then Placed(entry, true).size = ClampNumber(value, 6, 48, 1)
        elseif field == "placedX" then Placed(entry, true).x = ClampNumber(value, -100, 100, 1)
        elseif field == "placedY" then Placed(entry, true).y = ClampNumber(value, -100, 100, 1)
        elseif field == "placedBarWidth" then Placed(entry, true).barWidth = ClampNumber(value, 8, 120, 1)
        elseif field == "placedGrowth" then Placed(entry, true).growth = value or "RIGHTDOWN"
        elseif field == "placedMissing" then Placed(entry, true).missing = value and true or false
        elseif field == "placedCooldownSwipe" then Placed(entry, true).showCooldownSwipe = value and true or false
        elseif field == "placedCooldown" then Placed(entry, true).showCooldown = value and true or false
        elseif field == "placedCooldownSize" then Placed(entry, true).cooldownSize = ClampNumber(value, 6, 24, 1)
        elseif field == "placedBarSmoothFill" then Placed(entry, true).barSmoothFill = value and true or false
        elseif field == "placedBarShowTimer" then Placed(entry, true).barShowTimer = value and true or false
        elseif field == "placedBarTimerAnchor" then Placed(entry, true).barTimerAnchor = value or "CENTER"
        elseif field == "placedBarTimerX" then Placed(entry, true).barTimerX = ClampNumber(value, -100, 100, 1)
        elseif field == "placedBarTimerY" then Placed(entry, true).barTimerY = ClampNumber(value, -100, 100, 1)
        elseif field == "frameType" then
            if value == "none" then entry.frame = false else
                local frame = FrameEffect(entry, true)
                frame.type = value or "border"
                frame.priority = frame.priority or 5
                frame.color = frame.color or { 1, 1, 1, 0.8 }
            end
        elseif field == "framePriority" then FrameEffect(entry, true).priority = ClampNumber(value, 1, 10, 1)
        elseif field == "frameAlpha" then
            local frame = FrameEffect(entry, true)
            local alpha = Clamp01(value, 0.8)
            frame.alpha = alpha
            if type(frame.color) == "table" then frame.color[4] = alpha end
        elseif field == "frameThickness" then FrameEffect(entry, true).thickness = ClampNumber(value, 1, 8, 1)
        elseif field == "frameColor" then
            local frame = FrameEffect(entry, true)
            local alpha = (type(frame.color) == "table" and frame.color[4]) or frame.alpha or 0.8
            frame.color = { Clamp01(type(value) == "table" and (value.r or value[1]) or 1, 1), Clamp01(type(value) == "table" and (value.g or value[2]) or 1, 1), Clamp01(type(value) == "table" and (value.b or value[3]) or 1, 1), alpha }
        else return false end
        ApplySpell(scope)
        return true
    end

    return {
        ActionTarget = ActionTarget,
        SetSpellField = SetSpellField,
    }
end
