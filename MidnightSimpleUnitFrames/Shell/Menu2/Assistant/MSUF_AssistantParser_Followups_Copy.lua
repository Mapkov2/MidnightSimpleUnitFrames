-- Assistant copy-followup parser: resolves short copy/category replies into copy plans.
-- Kept separate from generic followups so copy workflow state stays explicit and testable.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
local P = A.Parser or {}
A.Parser = P
local Data = A.ParserData or {}

-- Follow-up parser for "do the same/copy that" replies.
-- It clones only plain action args from the previous context, then builds a fresh action
-- plan for the new target so undo/confirmation still see a normal assistant command.
local ContainsAny = P.ContainsAny
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups

local function CopySourceLabel(actionKey, source)
    if actionKey == "copy_group" and A and type(A.DisplayGroupLabel) == "function" then return A.DisplayGroupLabel(source) end
    if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(source) end
    local label = (A.UnitLabels or {})[source]
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    if source == "targettarget" then return "Target of Target" end
    if source == "focustarget" then return "Focus Target" end
    if source == "mythicraid" then return "Mythic Raid" end
    return tostring(source or "")
end

local function CopyPlainArgs(value, depth)
    -- Follow-up state can contain runtime tables; copy only simple serializable values so a
    -- later action cannot accidentally retain frames, functions, or deep cyclic structures.
    depth = (depth or 0) + 1
    if depth > 4 then return nil end
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then return value end
    if valueType ~= "table" then return nil end
    local out = {}
    for k, v in pairs(value) do
        local keyType = type(k)
        if keyType == "string" or keyType == "number" then
            local copied = CopyPlainArgs(v, depth)
            if copied ~= nil then out[k] = copied end
        end
    end
    return out
end

local function CopyActionTargetsForFollowup(text, actionKey, source)
    local detected = actionKey == "copy_group" and DetectGroups(text) or DetectUnits(text)
    local targets, seen = {}, {}
    for i = 1, #(detected or {}) do
        local target = detected[i]
        if target ~= source and not seen[target] then
            targets[#targets + 1] = target
            seen[target] = true
        end
    end
    return targets
end

local COPY_ACTION_FOLLOWUP_TERMS = Data.COPY_ACTION_FOLLOWUP_TERMS or {}
local COPY_ACTION_EXPLICIT_FOLLOWUP_TERMS = Data.COPY_ACTION_EXPLICIT_FOLLOWUP_TERMS or {}

function P.BuildCopyActionFollowup(text, ctx)
    if not ContainsAny(text, COPY_ACTION_FOLLOWUP_TERMS) then return nil end
    if ctx and type(ctx.lastChangeBundle) == "table" and #ctx.lastChangeBundle > 0 then return nil end
    local actionKey = ctx and ctx.lastAction
    if actionKey ~= "copy_unit" and actionKey ~= "copy_group" then
        if not ContainsAny(text, COPY_ACTION_EXPLICIT_FOLLOWUP_TERMS) then return nil end
        return {
            kind = "answer",
            status = "info",
            text = "Start with a full copy request first so I can reuse it somewhere else. For example: copy target text to player, or copy party health and text to raid.",
            summary = "Asks for copy context instead of guessing.",
        }
    end
    local previous = type(ctx.lastActionArgs) == "table" and ctx.lastActionArgs or nil
    local source = previous and previous.source
    if type(source) ~= "string" or source == "" then
        return {
            kind = "answer",
            status = "info",
            text = "Start with a full copy request first so I can reuse it somewhere else. For example: copy target text to player, or copy party health and text to raid.",
            summary = "Asks for the copy source instead of guessing.",
        }
    end
    local targets = CopyActionTargetsForFollowup(text, actionKey, source)
    if #targets == 0 then
        return {
            kind = "answer",
            status = "info",
            text = "Where do you want me to copy the previous change? For example: copy that to target, or same for mythic raid.",
            summary = "Asks for the copy destination instead of guessing.",
        }
    end
    local action = Registry and Registry:GetAction(actionKey)
    if not action then return nil end
    local args = {
        source = source,
        targets = targets,
        scopes = CopyPlainArgs(previous.scopes or {}),
    }
    local labelSource = CopySourceLabel(actionKey, source)
    return {
        kind = "action",
        action = action,
        args = args,
        label = actionKey == "copy_group" and ("Copy previous " .. labelSource .. " group options") or ("Copy previous " .. labelSource .. " options"),
        summary = "Repeats the last Assistant copy task with a new destination.",
    }
end
