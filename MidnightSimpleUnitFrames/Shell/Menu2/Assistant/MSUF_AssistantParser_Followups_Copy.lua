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

-- Follow-up parser for "do the same/copy that" replies.
-- It clones only plain action args from the previous context, then builds a fresh action
-- plan for the new target so undo/confirmation still see a normal assistant command.
local ContainsAny = P.ContainsAny
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups

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

local COPY_ACTION_FOLLOWUP_TERMS = {
    "copy that", "copy it", "copy the same", "copy same",
    "do that", "do it", "do the same", "same for", "same to",
    "apply that", "apply it", "apply the same", "also to", "also for",
    "repeat that", "repeat it",
    "das auch", "mach das", "mach das gleiche", "gleiches fuer", "gleiches fur",
    "auch fuer", "auch fur", "kopiere das", "uebernehme das",
}

local COPY_ACTION_EXPLICIT_FOLLOWUP_TERMS = {
    "copy that", "copy it", "copy the same", "copy same",
    "kopiere das", "uebernehme das",
}

function P.BuildCopyActionFollowup(text, ctx)
    if not ContainsAny(text, COPY_ACTION_FOLLOWUP_TERMS) then return nil end
    if ctx and type(ctx.lastChangeBundle) == "table" and #ctx.lastChangeBundle > 0 then return nil end
    local actionKey = ctx and ctx.lastAction
    if actionKey ~= "copy_unit" and actionKey ~= "copy_group" then
        if not ContainsAny(text, COPY_ACTION_EXPLICIT_FOLLOWUP_TERMS) then return nil end
        return {
            kind = "answer",
            status = "info",
            text = "I need a previous Assistant copy action before I can copy that somewhere else. Try a full command first, for example: copy target text to player, or copy party health and text to raid.",
            summary = "Explains missing copy follow-up context instead of guessing.",
        }
    end
    local previous = type(ctx.lastActionArgs) == "table" and ctx.lastActionArgs or nil
    local source = previous and previous.source
    if type(source) ~= "string" or source == "" then
        return {
            kind = "answer",
            status = "info",
            text = "I need a previous Assistant copy action before I can copy that somewhere else. Try a full command first, for example: copy target text to player, or copy party health and text to raid.",
            summary = "Explains missing copy source context instead of guessing.",
        }
    end
    local targets = CopyActionTargetsForFollowup(text, actionKey, source)
    if #targets == 0 then
        return {
            kind = "answer",
            status = "info",
            text = "Tell me where to copy the previous copy action, for example: copy that to target, or same for mythic raid.",
            summary = "Explains missing copy follow-up destination instead of guessing.",
        }
    end
    local action = Registry and Registry:GetAction(actionKey)
    if not action then return nil end
    local args = {
        source = source,
        targets = targets,
        scopes = CopyPlainArgs(previous.scopes or {}),
    }
    local labelSource = tostring((A.UnitLabels or {})[source] or source)
    return {
        kind = "action",
        action = action,
        args = args,
        label = actionKey == "copy_group" and ("Copy previous " .. labelSource .. " group settings") or ("Copy previous " .. labelSource .. " settings"),
        summary = "Repeats the last Assistant copy action with a new destination.",
    }
end
