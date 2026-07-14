-- Assistant follow-up parser: resolves short replies against stored conversation context.
-- It should produce plans or safe prompts only; execution remains in Assistant runtime.
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
A.ParserData = Data
local FollowupData = Data.FOLLOWUPS_PARSER or {}

-- Follow-up parser for multi-step assistant flows.
-- These handlers interpret short replies like "yes", "party only", or a copied profile name
-- in the context of the pending assistant state. They should be conservative because the
-- original command may have been parsed in a previous frame or after a yield.
local Normalize = P.Normalize
local HasPhrase = P.HasPhrase
local ContainsAny = P.ContainsAny
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local DetectBoolean = P.DetectBoolean
local FirstNumber = P.FirstNumber
local DetectFrameType = P.DetectFrameType
local DetectDirection = P.DetectDirection
local DetectAttribute = P.DetectAttribute
local PowerColorTokenForText = P.PowerColorTokenForText
local ClassPowerColorTokenForText = P.ClassPowerColorTokenForText
local BuildChanges = P.BuildChanges
local Compact = P.Compact

local function RelativeNumberDeltaForText(setting, text, fallbackAmount)
    local fn = P and P.RelativeNumberDeltaForText
    if type(fn) == "function" then return fn(setting, text, fallbackAmount) end
    return nil
end

local function ContextUnits(ctx)
    local units = {}
    if ctx and type(ctx.lastUnit) == "string" then units[#units + 1] = ctx.lastUnit end
    return units
end

local GROUP_CONTEXT_UNITS = { party = true, raid = true, mythicraid = true }

local function IsGroupContextUnit(unit)
    return type(unit) == "string" and GROUP_CONTEXT_UNITS[unit] == true
end

local function ContextGroups(ctx)
    local groups = {}
    if ctx and IsGroupContextUnit(ctx.lastUnit) then groups[#groups + 1] = ctx.lastUnit end
    return groups
end

local function ShouldUseLastUnitContext(text)
    return ContainsAny(text, FollowupData.LAST_UNIT_CONTEXT_TERMS)
end

local function ContextSubjectRecent(ctx, maxTurns)
    if type(ctx) ~= "table" then return false end
    local currentTurn = tonumber(ctx.turnSerial or ctx.lastTurnSerial) or 0
    local subjectTurn = tonumber(ctx.lastSubjectTurn or ctx.lastMentionedTurn)
    if not subjectTurn then return false end
    local age = currentTurn - subjectTurn
    return age >= 0 and age <= (tonumber(maxTurns) or 3)
end

local function FollowupValueDisplay(setting, value)
    if P and type(P.ValueDisplay) == "function" then
        local label = P.ValueDisplay(setting, value)
        if label ~= nil then return tostring(label) end
    end
    if value == nil then return "not set" end
    if setting and setting.type == "boolean" then return value and "enabled" or "disabled" end
    if setting and setting.type == "color" and type(value) == "table" then
        if type(value.label) == "string" and value.label ~= "" and type(A.DisplayColorLabel) == "function" then
            return A.DisplayColorLabel(value.label)
        end
        local r = math.floor(((tonumber(value.r or value[1]) or 0) * 255) + 0.5)
        local g = math.floor(((tonumber(value.g or value[2]) or 0) * 255) + 0.5)
        local b = math.floor(((tonumber(value.b or value[3]) or 0) * 255) + 0.5)
        if r < 0 then r = 0 elseif r > 255 then r = 255 end
        if g < 0 then g = 0 elseif g > 255 then g = 255 end
        if b < 0 then b = 0 elseif b > 255 then b = 255 end
        return string.format("#%02X%02X%02X", r, g, b)
    end
    if setting and (setting.type == "enum" or type(setting.values) == "table") and type(A.HumanizeDisplayKey) == "function" then
        return A.HumanizeDisplayKey(value)
    end
    return tostring(value)
end

function A._FollowupValueLabelForAnswer(setting, value, explicitLabel)
    if explicitLabel ~= nil then
        if setting and setting.type == "enum" and value ~= nil then return FollowupValueDisplay(setting, value) end
        if setting and setting.type == "color" and type(A.DisplayColorLabel) == "function" then
            return A.DisplayColorLabel(explicitLabel)
        end
        return tostring(explicitLabel)
    end
    return FollowupValueDisplay(setting, value)
end

function A._FollowupChangeLineForAnswer(index, setting, previous)
    if not setting then return nil end
    local label = type(A.DisplaySettingLabel) == "function" and A.DisplaySettingLabel(setting) or tostring(setting.label or "MSUF option")
    local oldLabel = A._FollowupValueLabelForAnswer(setting, previous and previous.oldValue)
    local newValue = previous and previous.value
    if newValue == nil and type(setting.get) == "function" then newValue = setting.get() end
    local newLabel = A._FollowupValueLabelForAnswer(setting, newValue, previous and previous.valueLabel)
    local prefix = index and (tostring(index) .. ". ") or ""
    if previous and previous.unchanged == true then return prefix .. label .. " was already " .. newLabel .. "." end
    return prefix .. label .. " from " .. oldLabel .. " to " .. newLabel .. "."
end

local function IsTroubleshootingWhyQuestion(text)
    text = Normalize(text)
    if text == "" then return false end
    if text:match("^why%s+are%s+") or text:match("^why%s+is%s+") then
        if ContainsAny(text, FollowupData.TROUBLESHOOTING_WHY_REFERENCE_TERMS) then
            return false
        end
        return ContainsAny(text, FollowupData.TROUBLESHOOTING_STATE_TERMS)
    end

    if text:match("^why%s+cant%s+") or text:match("^why%s+cannot%s+")
        or text:match("^why%s+can%s+not%s+") or text:match("^why%s+doesnt%s+")
        or text:match("^why%s+does%s+not%s+") or text:match("^why%s+dont%s+")
        or text:match("^why%s+do%s+not%s+") then
        return ContainsAny(text, FollowupData.TROUBLESHOOTING_ACTION_TERMS)
    end

    return false
end

local function IsPageExplanationQuestion(text)
    text = Normalize(text)
    if text == "" then return false end
    if ContainsAny(text, FollowupData.PAGE_EXPLANATION_TERMS) then
        return true
    end
    return false
end

local function HasNormalizedPhrase(text, phrase)
    text = Normalize(text)
    phrase = Normalize(phrase)
    if phrase == "" then return false end
    return (" " .. tostring(text or "") .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

local function HasExplicitValueSubject(text)
    local norm = Normalize(text)
    if not HasNormalizedPhrase(norm, "current value") and not HasNormalizedPhrase(norm, "value now") then return false end
    if norm:find(" of ", 1, true)
        and not ContainsAny(norm, FollowupData.VALUE_SUBJECT_OF_GUARD_TERMS)
    then
        return true
    end
    if norm:find(" for ", 1, true)
        and not ContainsAny(norm, FollowupData.VALUE_SUBJECT_FOR_GUARD_TERMS)
    then
        return true
    end
    return false
end

function A._ParseFollowupAnswer(text, ctx)
    if IsTroubleshootingWhyQuestion(text) or IsPageExplanationQuestion(text) then return nil end
    if HasExplicitValueSubject(text) then return nil end
    local asksWhatChanged = ContainsAny(text, FollowupData.ASK_WHAT_CHANGED_TERMS)
    local asksWhy = ContainsAny(text, FollowupData.ASK_WHY_TERMS)
    if not asksWhatChanged and not asksWhy then return nil end
    if not ctx then return nil end

    if type(ctx.lastChangeBundle) == "table" and #ctx.lastChangeBundle > 0 then
        local bundle = ctx.lastChangeBundle
        local lines = {}
        if #bundle == 1 then
            local previous = bundle[1]
            local setting = previous and previous.key and Registry and Registry:GetSetting(previous.key) or nil
            local line = A._FollowupChangeLineForAnswer(nil, setting, previous)
            if line then
                if asksWhy then
                    lines[#lines + 1] = "Why I did that: your last request matched " .. tostring(ctx.lastActionLabel or "that MSUF option") .. "."
                    lines[#lines + 1] = "Change recorded: " .. line
                else
                    lines[#lines + 1] = "Last change I made: " .. line
                end
                if not (previous and previous.unchanged == true) then
                    lines[#lines + 1] = "Ask for 'undo' to revert it."
                end
                return {
                    kind = "answer",
                    status = "info",
                    text = table.concat(lines, "\n"),
                    summary = "Reports the last Assistant option change from context.",
                }
            end
        elseif #bundle > 1 then
            if asksWhy then
                lines[#lines + 1] = "Why I did that: your last request matched " .. tostring(ctx.lastActionLabel or "several MSUF options") .. "."
                lines[#lines + 1] = "The recorded change touched " .. tostring(#bundle) .. " MSUF options:"
            else
                lines[#lines + 1] = "Last change I made touched " .. tostring(#bundle) .. " MSUF options:"
            end
            local visible = math.min(#bundle, 5)
            local hasChangedOption = false
            for i = 1, visible do
                local previous = bundle[i]
                local setting = previous and previous.key and Registry and Registry:GetSetting(previous.key) or nil
                local line = A._FollowupChangeLineForAnswer(i, setting, previous)
                if line then lines[#lines + 1] = line end
                if not (previous and previous.unchanged == true) then hasChangedOption = true end
            end
            if #bundle > visible then lines[#lines + 1] = "And " .. tostring(#bundle - visible) .. " more." end
            if hasChangedOption then lines[#lines + 1] = "Ask for 'undo' to revert it." end
            return {
                kind = "answer",
                status = "info",
                text = table.concat(lines, "\n"),
                summary = "Reports the last Assistant option change from context.",
            }
        end
        local key = ctx.lastSetting
        if type(key) ~= "string" or key == "" then
            local first = bundle[1]
            key = first and first.key
        end
        local setting = key and Registry and Registry:GetSetting(key) or nil
        if setting then
            local value = type(setting.get) == "function" and setting.get() or ctx.lastValue
            local valueLabel = A._FollowupValueLabelForAnswer(setting, value)
            return {
                kind = "answer",
                status = "info",
                text = (type(A.DisplaySettingLabel) == "function" and A.DisplaySettingLabel(setting) or tostring(setting.label or "Last option")) .. " is " .. tostring(valueLabel) .. ".",
                summary = "Reports the last Assistant option and current value from context.",
            }
        end
    end

    local actionKey = type(ctx.lastAction) == "string" and ctx.lastAction or nil
    if actionKey and actionKey ~= "" and actionKey ~= "change" then
        local action = Registry and type(Registry.GetAction) == "function" and Registry:GetAction(actionKey) or nil
        local label = ctx.lastActionLabel or (action and action.label) or actionKey
        local message = tostring(ctx.lastActionMessage or "")
        local lines = asksWhy
            and { "Why I did that: your last request matched the MSUF task " .. tostring(label) .. "." }
            or { "Last thing I did: " .. tostring(label) .. "." }
        if message ~= "" then lines[#lines + 1] = "Result: " .. message end
        if ctx.lastActionUndoable == true then
            lines[#lines + 1] = "Ask for 'undo' to revert it."
        end
        return {
            kind = "answer",
            status = "info",
            text = table.concat(lines, "\n"),
            summary = "Reports the last Assistant task from context.",
        }
    end

    if actionKey == "change" then
        return {
            kind = "answer",
            status = "info",
            text = "I don't have an earlier option change to repeat yet.",
            summary = "Reports the last Assistant change from context.",
        }
    end
    return nil
end

function A._FollowupCopyColorValue(value)
    if type(value) ~= "table" then return nil end
    local r = value.r or value[1]
    local g = value.g or value[2]
    local b = value.b or value[3]
    if tonumber(r) == nil or tonumber(g) == nil or tonumber(b) == nil then return nil end
    local out = { r = r, g = g, b = b }
    local a = value.a or value[4]
    if tonumber(a) ~= nil then out.a = a end
    return out
end

function A._FollowupComboPointSlotToken(text, previousToken)
    if type(previousToken) ~= "string" or not previousToken:match("^COMBO_POINTS_%d+$") then return nil end
    local normalized = Normalize and Normalize(text) or tostring(text or ""):lower()
    local slot = normalized:match("^%s*(%d+)%s*$")
        or normalized:match("combo%s+point%s+slot%s+(%d+)")
        or normalized:match("combo%s+point%s+(%d+)")
        or normalized:match("slot%s+(%d+)")
        or normalized:match("same%s+for%s+(%d+)")
        or normalized:match("same%s+to%s+(%d+)")
        or normalized:match("same%s+on%s+(%d+)")
        or normalized:match("also%s+(%d+)")
        or normalized:match("too%s+(%d+)")
        or normalized:match("for%s+(%d+)")
        or normalized:match("fuer%s+(%d+)")
        or normalized:match("fur%s+(%d+)")
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > 7 then return nil end
    return "COMBO_POINTS_" .. tostring(slot)
end

function A._FollowupAddColorTokenChange(changes, seen, key, color)
    if not (Registry and type(key) == "string" and key ~= "" and color) then return end
    if seen[key] then return end
    local setting = Registry:GetSetting(key)
    if not setting or setting.type ~= "color" then return end
    seen[key] = true
    changes[#changes + 1] = { setting = setting, value = color }
end

function A._BuildColorTokenFollowup(text, ctx)
    if not (ctx and type(ctx.lastChangeBundle) == "table") then return nil end
    local powerToken = PowerColorTokenForText and PowerColorTokenForText(text) or nil
    local classToken = ClassPowerColorTokenForText and ClassPowerColorTokenForText(text) or nil
    local changes = {}
    local seen = {}
    for i = 1, #ctx.lastChangeBundle do
        local prev = ctx.lastChangeBundle[i]
        local key = tostring((prev and prev.key) or "")
        local color = A._FollowupCopyColorValue(prev and prev.value)
        local previousPower = key:match("^general%.powerColorOverrides%.([%w_]+)$")
        if previousPower and powerToken then
            A._FollowupAddColorTokenChange(changes, seen, "general.powerColorOverrides." .. powerToken, color)
        end
        local previousClass = key:match("^general%.classPowerColorOverrides%.([%w_]+)$")
        if previousClass then
            local token = classToken or A._FollowupComboPointSlotToken(text, previousClass)
            if token then
                A._FollowupAddColorTokenChange(changes, seen, "general.classPowerColorOverrides." .. token, color)
            end
        end
        local previousClassBg = key:match("^general%.classPowerBgColorOverrides%.([%w_]+)$")
        if previousClassBg then
            local token = classToken or A._FollowupComboPointSlotToken(text, previousClassBg)
            if token then
                A._FollowupAddColorTokenChange(changes, seen, "general.classPowerBgColorOverrides." .. token, color)
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Apply previous color to another color slot",
        summary = "Applies the last color change to another power or Class Resource color.",
    }
end

local CONTINUATION_TOKEN_STOPWORDS = {
    a = true, an = true, ["and"] = true, also = true, bit = true, by = true,
    change = true, down = true, even = true, farther = true, further = true,
    going = true, keep = true, left = true, little = true, lower = true,
    more = true, much = true, next = true, now = true, nudge = true, ok = true,
    push = true, raise = true, right = true, shift = true, slightly = true,
    the = true, ["then"] = true, tiny = true, to = true, up = true, way = true,
    move = true, moving = true, moved = true,
}

local function ContinuationHasMarker(text)
    text = tostring(text or "")
    if text:match("^now%s+") or text:match("^then%s+") or text:match("^also%s+") or text:match("^next%s+") then return true end
    return ContainsAny(text, FollowupData.CONTINUATION_MARKER_TERMS)
end

local function ContinuationHasMovementVerb(text)
    if A.HasNudgeMovementVerb and A.HasNudgeMovementVerb(text) then return true end
    return HasPhrase(text, "move")
        or HasPhrase(text, "nudge")
        or HasPhrase(text, "shift")
        or HasPhrase(text, "push")
        or HasPhrase(text, "raise")
        or HasPhrase(text, "lower")
end

local function ContinuationDirection(text)
    local direction = A.ExtractNudgeDirection and A.ExtractNudgeDirection(text) or nil
    if direction then return direction end
    if HasPhrase(text, "left") or HasPhrase(text, "leftwards") or HasPhrase(text, "to the left") then return "left" end
    if HasPhrase(text, "right") or HasPhrase(text, "rightwards") or HasPhrase(text, "to the right") then return "right" end
    if HasPhrase(text, "up") or HasPhrase(text, "upwards") or HasPhrase(text, "higher") then return "up" end
    if HasPhrase(text, "down") or HasPhrase(text, "downwards") or HasPhrase(text, "lower") then return "down" end
    return nil
end

local function ContinuationNormalizeToken(token)
    token = tostring(token or ""):lower()
    if #token > 3 and token:sub(-1) == "s" then token = token:sub(1, -2) end
    return token
end

local function ContinuationTokenSet(text)
    local set = {}
    text = Normalize(text)
    for token in tostring(text or ""):gmatch("%w+") do
        token = ContinuationNormalizeToken(token)
        if token ~= "" then set[token] = true end
    end
    return set
end

local function ContinuationSubjectTokens(text)
    local out, seen = {}, {}
    text = Normalize(text)
    for token in tostring(text or ""):gmatch("%w+") do
        token = ContinuationNormalizeToken(token)
        if token ~= "" and not CONTINUATION_TOKEN_STOPWORDS[token] and not token:match("^%d+$") and not seen[token] then
            seen[token] = true
            out[#out + 1] = token
        end
    end
    return out
end

local function ContinuationSubjectMatches(text, setting)
    local subjectTokens = ContinuationSubjectTokens(text)
    if #subjectTokens == 0 then return false, subjectTokens end
    local labelTokens = ContinuationTokenSet(tostring(setting and setting.label or "") .. " " .. tostring(setting and setting.category or ""))
    for i = 1, #subjectTokens do
        if not labelTokens[subjectTokens[i]] then return false, subjectTokens end
    end
    return true, subjectTokens
end

local function ContinuationAmount(setting, text)
    if A.RuntimePrivate and type(A.RuntimePrivate.ContextEscalationAmount) == "function" then
        return A.RuntimePrivate.ContextEscalationAmount(setting, text)
    end
    local amount = tonumber(setting and (setting.moveStep or setting.moveAmount)) or 10
    if A.HasSmallNudgeIntent and A.HasSmallNudgeIntent(text) then
        amount = amount / 2
        if amount < 2 then amount = 2 end
    end
    return amount
end

local function ContinuationAxisSuffix(direction)
    if direction == "left" or direction == "right" then return "X" end
    if direction == "up" or direction == "down" then return "Y" end
    return nil
end

local function ContinuationOffsetCandidate(setting, axisSuffix, subjectTokens)
    if not (setting and setting.type == "number") then return false end
    local attr = tostring(setting.attribute or "")
    local offsetSuffix = "Offset" .. axisSuffix
    if not (attr:sub(-#offsetSuffix) == offsetSuffix or attr:sub(-#axisSuffix) == axisSuffix) then return false end
    local labelTokens = ContinuationTokenSet(tostring(setting.label or "") .. " " .. tostring(setting.category or ""))
    for i = 1, #(subjectTokens or {}) do
        if not labelTokens[subjectTokens[i]] then return false end
    end
    return true
end

local function ContinuationFindAxisSetting(lastSetting, direction, subjectTokens)
    local axisSuffix = ContinuationAxisSuffix(direction)
    if not axisSuffix then return nil end

    local axisSetting = A.ResolveContextAxisSetting and A.ResolveContextAxisSetting(lastSetting, direction) or nil
    if axisSetting and axisSetting.type == "number" and axisSetting.unit == lastSetting.unit and axisSetting.category == lastSetting.category then
        return axisSetting
    end

    if not (Registry and type(Registry.FindSettings) == "function") then return nil end
    local candidates = Registry:FindSettings({ unit = lastSetting.unit })
    local match
    for i = 1, #(candidates or {}) do
        local candidate = candidates[i]
        if candidate and candidate.category == lastSetting.category and ContinuationOffsetCandidate(candidate, axisSuffix, subjectTokens) then
            if match and match.key ~= candidate.key then return nil end
            match = candidate
        end
    end
    return match
end

local function BuildContinuationFollowup(text, ctx)
    if A.ContextEngineEnabled == false then return nil end
    if not ctx then return nil end
    -- An explicit semantic switch to draw layer/strata must never be treated
    -- as another movement along the previous X/Y axis.
    if ContainsAny(text, FollowupData.LAYER_TERMS) then return nil end
    if not ContinuationHasMarker(text) then return nil end
    if not ContinuationHasMovementVerb(text) then return nil end
    local direction = ContinuationDirection(text)
    if not direction then return nil end

    local currentTurn = tonumber(ctx.turnSerial or ctx.lastTurnSerial) or 0
    local subjectTurn = tonumber(ctx.lastSubjectTurn) or -1000
    if currentTurn - subjectTurn > 3 then return nil end

    local lastSetting = Registry and type(Registry.GetSetting) == "function" and Registry:GetSetting(ctx.lastSetting) or nil
    if not lastSetting then return nil end
    local subjectMatches, subjectTokens = ContinuationSubjectMatches(text, lastSetting)
    if not subjectMatches then return nil end

    local axisSetting = ContinuationFindAxisSetting(lastSetting, direction, subjectTokens)
    if not axisSetting then return nil end
    local delta = ContinuationAmount(axisSetting, text)
    if direction == "left" or direction == "down" then delta = -math.abs(delta) else delta = math.abs(delta) end
    if delta == 0 then return nil end

    return {
        kind = "changes",
        changes = {
            {
                setting = axisSetting,
                relativeDelta = delta,
                direction = direction,
            },
        },
        label = "Continue " .. tostring(lastSetting.label or "Assistant setting"),
        summary = "Continues the previous MSUF subject by adjusting its placement.",
        sourceText = text,
    }
end

local function BuildExplicitTextLayerFollowup(text, ctx)
    if not (ctx and type(ctx.lastChangeBundle) == "table") then return nil end
    if not ContainsAny(text, FollowupData.LAYER_TERMS) then return nil end
    local delta
    if ContainsAny(text, FollowupData.FORCE_NEGATIVE_TERMS) or ContainsAny(text, FollowupData.NEGATIVE_TERMS) then
        delta = -1
    elseif ContainsAny(text, FollowupData.FORCE_POSITIVE_TERMS) or ContainsAny(text, FollowupData.POSITIVE_TERMS) then
        delta = 1
    end
    local exact = FirstNumber(text)
    if delta == nil and exact == nil then return nil end

    local changes, seen = {}, {}
    for i = 1, #ctx.lastChangeBundle do
        local previous = ctx.lastChangeBundle[i]
        local key = tostring(previous and previous.key or "")
        local prefix, attr = key:match("^(.-)%.([^%.]+)$")
        local layerAttr
        if attr == "powerOffsetX" or attr == "powerOffsetY" or attr == "powerTextLayer" then
            layerAttr = "powerTextLayer"
        elseif attr == "hpOffsetX" or attr == "hpOffsetY" or attr == "hpTextLayer" then
            layerAttr = prefix and prefix:match("^gf_") and "textLayer" or "hpTextLayer"
        elseif attr == "nameOffsetX" or attr == "nameOffsetY" or attr == "nameTextLayer" then
            layerAttr = "nameTextLayer"
        end
        local layerKey = prefix and layerAttr and (prefix .. "." .. layerAttr) or nil
        local setting = layerKey and not seen[layerKey] and Registry and Registry:GetSetting(layerKey) or nil
        if setting then
            seen[layerKey] = true
            changes[#changes + 1] = { setting = setting, value = delta == nil and exact or nil, relativeDelta = delta }
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Change previous text strata",
        summary = "Switches from the previous text position control to its matching text-layer control.",
    }
end

local function BuildFollowup(text, ctx)
    if not ctx then return nil end
    if IsPageExplanationQuestion(text) then return nil end
    local explicitTextLayer = BuildExplicitTextLayerFollowup(text, ctx)
    if explicitTextLayer then return explicitTextLayer end
    local copyActionFollowup = P.BuildCopyActionFollowup and P.BuildCopyActionFollowup(text, ctx)
    if copyActionFollowup then return copyActionFollowup end
    if ContainsAny(text, FollowupData.PREVIOUS_COPY_QUERY_TERMS) and ctx.lastAction ~= "copy_unit" and ctx.lastAction ~= "copy_group" then
        return {
            kind = "answer",
            status = "info",
            text = "I don't have an earlier copy task to repeat yet.",
            summary = "Reports that there is no previous copy task yet.",
        }
    end
    if type(ctx.lastChangeBundle) ~= "table" then return nil end
    local positiveTerms = FollowupData.POSITIVE_TERMS
    local negativeTerms = FollowupData.NEGATIVE_TERMS
    local neutralTerms = FollowupData.NEUTRAL_TERMS
    local oppositeTerms = FollowupData.OPPOSITE_TERMS
    local reverseCorrectionTerms = FollowupData.REVERSE_CORRECTION_TERMS
    local tooPositiveTerms = FollowupData.TOO_POSITIVE_TERMS
    local tooNegativeTerms = FollowupData.TOO_NEGATIVE_TERMS
    local notEnoughTerms = FollowupData.NOT_ENOUGH_TERMS
    local replayTerms = FollowupData.REPLAY_TERMS
    local rightIntent = ContainsAny(text, FollowupData.RIGHT_TERMS)
    local leftIntent = ContainsAny(text, FollowupData.LEFT_TERMS)
    local upIntent = ContainsAny(text, FollowupData.UP_TERMS)
    local downIntent = ContainsAny(text, FollowupData.DOWN_TERMS)
    local followDirection = rightIntent and "right" or (leftIntent and "left" or (upIntent and "up" or (downIntent and "down" or nil)))
    local forcePositive = ContainsAny(text, FollowupData.FORCE_POSITIVE_TERMS)
    local forceNegative = ContainsAny(text, FollowupData.FORCE_NEGATIVE_TERMS)
    local positiveIntent = forcePositive or (ContainsAny(text, positiveTerms) and not forceNegative)
    local negativeIntent = forceNegative or (ContainsAny(text, negativeTerms) and not forcePositive)
    local neutralIntent = ContainsAny(text, neutralTerms)
    local neutralIncreaseIntent = ContainsAny(text, FollowupData.NEUTRAL_INCREASE_TERMS)
    local oppositeIntent = ContainsAny(text, oppositeTerms)
    local reverseCorrectionIntent = ContainsAny(text, reverseCorrectionTerms)
    local tooPositiveIntent = ContainsAny(text, tooPositiveTerms)
    local tooNegativeIntent = ContainsAny(text, tooNegativeTerms)
    local notEnoughIntent = ContainsAny(text, notEnoughTerms)
    local targetReplayIntent = ContainsAny(text, replayTerms)
    local explicitAuraBulkScope = ContainsAny(text, FollowupData.EXPLICIT_AURA_BULK_SCOPE_TERMS)
    local pureNumberIntent = tostring(text or ""):match("^[-+]?%d+%.?%d*$") ~= nil
    local bareExactValueIntent = tostring(text or ""):match("^to%s+[-+]?%d+%.?%d*$") ~= nil
        or tostring(text or ""):match("^move%s+to%s+[-+]?%d+%.?%d*$") ~= nil
        or tostring(text or ""):match("^set%s+to%s+[-+]?%d+%.?%d*$") ~= nil
        or tostring(text or ""):match("^change%s+to%s+[-+]?%d+%.?%d*$") ~= nil
        or tostring(text or ""):match("^auf%s+[-+]?%d+%.?%d*$") ~= nil
        or tostring(text or ""):match("^zu%s+[-+]?%d+%.?%d*$") ~= nil
    local exactValueReference = ContainsAny(text, FollowupData.EXACT_VALUE_REFERENCE_TERMS)
    local pluralExactValueReference = ContainsAny(text, FollowupData.PLURAL_EXACT_VALUE_REFERENCE_TERMS)
    local relativeNumberIntent = ContainsAny(text, P.RELATIVE_INCREASE_TERMS or {})
        or ContainsAny(text, P.RELATIVE_DECREASE_TERMS or {})
    local exactValueIntent = pureNumberIntent
        or bareExactValueIntent
        or (not explicitAuraBulkScope and ContainsAny(text, FollowupData.MIN_MAX_TERMS))
        or (not explicitAuraBulkScope and not relativeNumberIntent
            and exactValueReference and FirstNumber(text) ~= nil)
    local commandIntent = ContainsAny(text, FollowupData.COMMAND_INTENT_TERMS)
    local auraLaneObjectIntent = ContainsAny(text, FollowupData.AURA_LANE_OBJECT_REFERENCE_TERMS) and ContainsAny(text, FollowupData.AURA_LANE_OBJECT_ACTION_TERMS)
    local genericObjectIntent = ContainsAny(text, FollowupData.GENERIC_OBJECT_REFERENCE_TERMS) and ContainsAny(text, FollowupData.GENERIC_OBJECT_ACTION_TERMS)
    local explicitFollowupReference = ContainsAny(text, FollowupData.EXPLICIT_FOLLOWUP_REFERENCE_TERMS)
    local wordCount = 0
    for _ in tostring(text or ""):gmatch("%S+") do wordCount = wordCount + 1 end
    local bareDirectionalFollowup = ContainsAny(text, FollowupData.BARE_DIRECTIONAL_FOLLOWUP_TERMS) and wordCount <= 3 and not ContainsAny(text, FollowupData.BARE_DIRECTIONAL_GUARD_TERMS)
    local hasIntent = positiveIntent or negativeIntent or neutralIntent or oppositeIntent or reverseCorrectionIntent
        or tooPositiveIntent or tooNegativeIntent or notEnoughIntent or exactValueIntent or relativeNumberIntent
        or leftIntent or rightIntent or targetReplayIntent
        or auraLaneObjectIntent
        or genericObjectIntent
        or ContainsAny(text, FollowupData.HIDE_REFERENCE_TERMS)
    if not hasIntent then return nil end
    local units = DetectUnits(text)
    local groups = DetectGroups(text)

    local function FollowupSiblingKey(key, direction)
        key = tostring(key or "")
        if direction == "left" or direction == "right" then
            if key:find("Y$") then return (key:gsub("Y$", "X")) end
            if key:find("X$") then return key end
        elseif direction == "up" or direction == "down" then
            if key:find("X$") then return (key:gsub("X$", "Y")) end
            if key:find("Y$") then return key end
        end
        return nil
    end

    local function FollowupExactValue(setting)
        if not (setting and setting.type == "number") then return nil end
        if ContainsAny(text, FollowupData.EXACT_MAX_TERMS) and setting.max ~= nil then return setting.max end
        if ContainsAny(text, FollowupData.EXACT_MIN_TERMS) and setting.min ~= nil then return setting.min end
        local value = A._ExplicitNumberValue(text)
        if value == nil then value = FirstNumber(text) end
        if value == nil then return nil end
        if setting.percent == true and value > 1 then value = value / 100 end
        return value
    end

    local function FollowupAmount(setting, prevDelta, explicitAmount)
        local amount = explicitAmount
        local step = (setting and tonumber(setting.step)) or 1
        if amount == nil and prevDelta ~= nil and prevDelta ~= 0 then amount = math.abs(prevDelta) end
        if amount == nil or amount == 0 then amount = step end
        if explicitAmount == nil and ContainsAny(text, FollowupData.SMALL_AMOUNT_TERMS) then
            amount = amount / 2
            if amount < step then amount = step end
        elseif explicitAmount == nil and ContainsAny(text, FollowupData.HALF_AMOUNT_TERMS) then
            amount = amount / 2
            if amount < step then amount = step end
        elseif explicitAmount == nil and not reverseCorrectionIntent and ContainsAny(text, FollowupData.LARGE_AMOUNT_TERMS) then
            amount = amount * 2
        end
        if setting and setting.percent == true and amount > 1 then amount = amount / 100 end
        return amount
    end

    local function AddUniqueValue(out, seen, value)
        value = tostring(value or "")
        if value == "" or seen[value] then return end
        seen[value] = true
        out[#out + 1] = value
    end

    local function HasGenericObjectFollowupReference(textValue)
        return ContainsAny(textValue, FollowupData.GENERIC_REFERENCE_TERMS)
    end

    local function GenericFollowupTargetAttr(textValue, direction)
        if ContainsAny(textValue, FollowupData.GENERIC_ENABLE_TERMS) then return "enabled" end
        if ContainsAny(textValue, FollowupData.GROWTH_TERMS) then return "growth" end
        if ContainsAny(textValue, FollowupData.ANCHOR_TERMS) then return "anchor" end
        if direction and ContainsAny(textValue, FollowupData.MOVEMENT_TERMS) then
            if direction == "left" or direction == "right" then return "offsetX" end
            if direction == "up" or direction == "down" then return "offsetY" end
        end
        if ContainsAny(textValue, FollowupData.X_OFFSET_TERMS) then return "offsetX" end
        if ContainsAny(textValue, FollowupData.Y_OFFSET_TERMS) then return "offsetY" end
        if ContainsAny(textValue, FollowupData.WIDTH_TERMS) then return "width" end
        if ContainsAny(textValue, FollowupData.HEIGHT_TERMS) then return "height" end
        if ContainsAny(textValue, FollowupData.LAYER_TERMS) then return "layer" end
        if ContainsAny(textValue, FollowupData.GENERIC_SIZE_TERMS) then return "size" end
        return nil
    end

    local function RelatedPrefixAliases(prefix)
        local out, seen = {}, {}
        AddUniqueValue(out, seen, prefix)
        if prefix == "hp" then
            AddUniqueValue(out, seen, "healthText")
        elseif prefix == "healthText" then
            AddUniqueValue(out, seen, "hp")
        elseif prefix == "power" then
            AddUniqueValue(out, seen, "powerText")
        elseif prefix == "powerText" then
            AddUniqueValue(out, seen, "power")
        elseif prefix == "name" then
            AddUniqueValue(out, seen, "nameText")
        elseif prefix == "nameText" then
            AddUniqueValue(out, seen, "name")
        elseif prefix == "spellName" then
            AddUniqueValue(out, seen, "text")
        elseif prefix == "text" then
            AddUniqueValue(out, seen, "spellName")
        end
        return out
    end

    local relatedPrefixSuffixes = {
        "OffsetX", "OffsetY", "MaxWidth", "FontSize", "TextLayer", "TextAnchor",
        "Width", "Height", "Size", "Layer", "Anchor", "Enabled", "X", "Y",
    }
    local relatedDirectAttributes = {
        "offsetX", "offsetY", "width", "height", "size", "layer", "anchor", "enabled",
    }

    local function RelatedPrefixFromAttribute(attribute)
        local attr = tostring(attribute or "")
        if attr == "" then return "" end
        for i = 1, #relatedPrefixSuffixes do
            local suffix = relatedPrefixSuffixes[i]
            if attr:sub(-#suffix) == suffix then return attr:sub(1, #attr - #suffix) end
        end
        for i = 1, #relatedDirectAttributes do
            local suffix = relatedDirectAttributes[i]
            if attr == suffix then return "" end
        end
        return attr
    end

    local function GenericRelatedAttributeCandidates(previousAttr, targetAttr)
        local out, seen = {}, {}
        local prefix = RelatedPrefixFromAttribute(previousAttr)
        local prefixes = RelatedPrefixAliases(prefix)
        local function addForPrefix(suffix)
            for i = 1, #prefixes do
                local p = prefixes[i]
                if p == "" then
                    AddUniqueValue(out, seen, suffix)
                else
                    AddUniqueValue(out, seen, p .. suffix)
                end
            end
        end

        if targetAttr == "offsetX" then
            addForPrefix("OffsetX")
            addForPrefix("X")
            AddUniqueValue(out, seen, "offsetX")
        elseif targetAttr == "offsetY" then
            addForPrefix("OffsetY")
            addForPrefix("Y")
            AddUniqueValue(out, seen, "offsetY")
        elseif targetAttr == "size" then
            addForPrefix("Size")
            addForPrefix("FontSize")
            AddUniqueValue(out, seen, "size")
        elseif targetAttr == "layer" then
            addForPrefix("Layer")
            addForPrefix("TextLayer")
            AddUniqueValue(out, seen, "layer")
        elseif targetAttr == "anchor" then
            addForPrefix("Anchor")
            addForPrefix("TextAnchor")
            AddUniqueValue(out, seen, "anchor")
        elseif targetAttr == "enabled" then
            addForPrefix("Enabled")
            AddUniqueValue(out, seen, "enabled")
        else
            AddUniqueValue(out, seen, targetAttr)
        end
        return out
    end

    local function PickGenericRelatedCandidate(candidates, previousSetting)
        if type(candidates) ~= "table" or #candidates == 0 then return nil end
        if #candidates == 1 then return candidates[1] end
        local previousCategory = tostring(previousSetting and previousSetting.category or "")
        local categoryMatch
        for i = 1, #candidates do
            local candidate = candidates[i]
            if previousCategory ~= "" and tostring(candidate and candidate.category or "") == previousCategory then
                if categoryMatch then return nil end
                categoryMatch = candidate
            end
        end
        return categoryMatch
    end

    local function FindGenericRelatedSetting(prev, targetAttr)
        if not (Registry and type(Registry.FindSettings) == "function") then return nil end
        local previousSetting = prev and prev.key and Registry:GetSetting(prev.key) or nil
        if targetAttr == "enabled" and previousSetting and previousSetting.type == "boolean"
            and ContainsAny(text, FollowupData.BOOLEAN_CORRECTION_TERMS)
        then
            -- A pronoun correction such as "actually, turn it back on" owns
            -- the exact boolean that was just changed. Searching siblings for
            -- a generic Enabled attribute can otherwise redirect the command
            -- from Target Name to the whole Target Frame.
            return previousSetting
        end
        local unit = (prev and prev.unit) or (previousSetting and previousSetting.unit)
        local frameType = (prev and prev.frameType) or (previousSetting and previousSetting.frameType)
        local attribute = (prev and prev.attribute) or (previousSetting and previousSetting.attribute)
        if type(frameType) ~= "string" or frameType == "" then return nil end
        local attrCandidates = GenericRelatedAttributeCandidates(attribute, targetAttr)
        for i = 1, #attrCandidates do
            local filter = { frameType = frameType, attribute = attrCandidates[i] }
            if type(unit) == "string" and unit ~= "" then filter.unit = unit end
            local setting = PickGenericRelatedCandidate(Registry:FindSettings(filter), previousSetting)
            if setting then return setting end
        end
        return nil
    end

    local function GenericEnumFollowupValue(setting, targetAttr, direction)
        if not (setting and setting.type == "enum") then return nil end
        local compactText = Compact and Compact(text) or Normalize(text):gsub("%s+", "")
        local aliases = setting.valueAliases
        local bestValue, bestLen
        if type(aliases) == "table" then
            for alias, value in pairs(aliases) do
                local compactAlias = Compact and Compact(alias) or Normalize(alias):gsub("%s+", "")
                if compactAlias ~= "" and compactText:find(compactAlias, 1, true) and (not bestLen or #compactAlias > bestLen) then
                    bestValue, bestLen = value, #compactAlias
                end
            end
        end
        if bestValue ~= nil then return bestValue end
        if targetAttr == "growth" and direction then
            local dir = tostring(direction):upper()
            if setting.values then
                for i = 1, #setting.values do
                    if setting.values[i] == dir then return dir end
                end
            end
            if dir == "LEFT" then return "LEFTDOWN" end
            if dir == "UP" then return "RIGHTUP" end
            if dir == "RIGHT" or dir == "DOWN" then return "RIGHTDOWN" end
        end
        return nil
    end

    local function IsMovementSettingShape(setting, key, attr)
        attr = tostring(attr or (setting and setting.attribute) or "")
        key = tostring(key or (setting and setting.key) or "")
        if attr == "offsetX" or attr == "offsetY" or attr == "x" or attr == "y" then return true end
        if attr == "positionX" or attr == "positionY" then return true end
        if attr:find("OffsetX$") or attr:find("OffsetY$") then return true end
        if attr:find("PositionX$") or attr:find("PositionY$") then return true end
        if key:find("OffsetX$") or key:find("OffsetY$") then return true end
        if key:find("%.x$") or key:find("%.y$") or key:find("%.offsetX$") or key:find("%.offsetY$") then return true end
        return false
    end

    local function PreviousMovementDelta(prev)
        if not prev then return nil end
        local previousSetting = prev.key and Registry and Registry:GetSetting(prev.key) or nil
        if not IsMovementSettingShape(previousSetting, prev.key, prev.attribute) then return nil end
        local delta = tonumber(prev.relativeDelta)
        if delta ~= nil and delta ~= 0 then return delta end
        return nil
    end

    local function PreviousValueDelta(prev)
        if not prev then return nil end
        local oldValue = tonumber(prev.oldValue)
        local newValue = tonumber(prev.value)
        if oldValue == nil or newValue == nil or oldValue == newValue then return nil end
        return newValue - oldValue
    end

    local function GenericNumberFollowupValue(setting, targetAttr, direction, prev)
        if not (setting and setting.type == "number") then return nil, nil end
        local attr = tostring(setting.attribute or "")
        local movementTarget = targetAttr == "offsetX" or targetAttr == "offsetY"
            or attr:find("OffsetX$") or attr:find("OffsetY$") or attr:find("X$") or attr:find("Y$")
        if movementTarget and direction then
            local relative = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, 10) or nil
            if relative ~= nil then return nil, relative end
            local prevDelta = PreviousMovementDelta(prev)
            local amount = A._RelativeNumberAmountForText(text)
                or (prevDelta ~= nil and prevDelta ~= 0 and math.abs(prevDelta))
                or tonumber(setting.moveStep)
                or tonumber(setting.moveAmount)
                or 10
            if amount == nil or amount == 0 then amount = tonumber(setting.step) or 10 end
            if direction == "left" or direction == "down" then amount = -amount end
            return nil, amount
        end

        local relative = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text) or nil
        if relative ~= nil then return nil, relative end
        local value = A._ExplicitNumberValue and A._ExplicitNumberValue(text) or nil
        if value == nil then value = FirstNumber(text) end
        if value ~= nil then return value, nil end
        return nil, nil
    end

    local function GenericRelatedFollowupValue(setting, targetAttr, direction, prev)
        if not setting then return nil, nil end
        if setting.type == "boolean" then
            return DetectBoolean(text), nil
        elseif setting.type == "enum" then
            return GenericEnumFollowupValue(setting, targetAttr, direction), nil
        elseif setting.type == "number" then
            return GenericNumberFollowupValue(setting, targetAttr, direction, prev)
        end
        return nil, nil
    end

    local function TextAreaTargetPrefixes(textValue)
        local prefixes = {}
        if ContainsAny(textValue, FollowupData.POWER_TEXT_TERMS) then
            prefixes[#prefixes + 1] = "power"
            prefixes[#prefixes + 1] = "powerText"
        elseif ContainsAny(textValue, FollowupData.HP_TEXT_TERMS) then
            prefixes[#prefixes + 1] = "hp"
            prefixes[#prefixes + 1] = "healthText"
            prefixes[#prefixes + 1] = "text"
        elseif ContainsAny(textValue, FollowupData.NAME_TEXT_TERMS) then
            prefixes[#prefixes + 1] = "name"
            prefixes[#prefixes + 1] = "nameText"
        end
        return prefixes
    end

    local function TextAreaSuffixFromAttribute(attribute)
        local attr = tostring(attribute or "")
        if attr == "" then return nil end
        for i = 1, #relatedPrefixSuffixes do
            local suffix = relatedPrefixSuffixes[i]
            if attr:sub(-#suffix) == suffix then return suffix end
        end
        return nil
    end

    local function FindTextAreaFollowupSetting(prev, targetPrefixes)
        if not (prev and type(targetPrefixes) == "table" and #targetPrefixes > 0) then return nil end
        if not (Registry and type(Registry.FindSettings) == "function") then return nil end
        local previousSetting = prev.key and Registry:GetSetting(prev.key) or nil
        local unit = prev.unit or (previousSetting and previousSetting.unit)
        local frameType = prev.frameType or (previousSetting and previousSetting.frameType)
        local suffix = TextAreaSuffixFromAttribute(prev.attribute or (previousSetting and previousSetting.attribute))
        if type(unit) ~= "string" or unit == "" or type(frameType) ~= "string" or frameType == "" or not suffix then return nil end

        for i = 1, #targetPrefixes do
            local targetAttr = tostring(targetPrefixes[i]) .. suffix
            local filter = { unit = unit, frameType = frameType, attribute = targetAttr }
            local setting = PickGenericRelatedCandidate(Registry:FindSettings(filter), previousSetting)
            if setting then return setting end
        end
        return nil
    end

    local textAreaTargetPrefixes = TextAreaTargetPrefixes(text)
    if #units == 0 and #groups == 0 and targetReplayIntent and #textAreaTargetPrefixes > 0 then
        local textAreaChanges = {}
        local seenTextAreaKeys = {}
        for i = 1, #ctx.lastChangeBundle do
            local prev = ctx.lastChangeBundle[i]
            local setting = FindTextAreaFollowupSetting(prev, textAreaTargetPrefixes)
            if setting and not seenTextAreaKeys[setting.key] then
                local relativeDelta = tonumber(prev and prev.relativeDelta)
                if relativeDelta ~= nil and setting.type == "number" then
                    seenTextAreaKeys[setting.key] = true
                    textAreaChanges[#textAreaChanges + 1] = { setting = setting, relativeDelta = relativeDelta, direction = prev.direction }
                elseif prev and prev.value ~= nil then
                    seenTextAreaKeys[setting.key] = true
                    textAreaChanges[#textAreaChanges + 1] = { setting = setting, value = prev.value }
                end
            end
        end
        if #textAreaChanges > 0 then
            return {
                kind = "changes",
                changes = textAreaChanges,
                label = "Apply previous text adjustment",
                summary = "Continues the last text change on another text area.",
            }
        end
    end

    local function IsTextSlotPreviousKey(key)
        key = tostring(key or "")
        for _, slot in ipairs({ "Left", "Center", "Right" }) do
            if key:match("^gf_[^%.]+%.text" .. slot .. "$") then return true end
            if key:match("^gf_[^%.]+%.powerText" .. slot .. "$") then return true end
            if key:match("^[^%.]+%.text" .. slot .. "$") then return true end
            if key:match("^[^%.]+%.powerText" .. slot .. "$") then return true end
            if key:match("^gf_[^%.]+%.hpText" .. slot .. "Offset[XY]$") then return true end
            if key:match("^gf_[^%.]+%.powerText" .. slot .. "Offset[XY]$") then return true end
            if key:match("^[^%.]+%.hpText" .. slot .. "Offset[XY]$") then return true end
            if key:match("^[^%.]+%.powerText" .. slot .. "Offset[XY]$") then return true end
        end
        return false
    end

    local function BundleHasTextSlotPrevious()
        for i = 1, #ctx.lastChangeBundle do
            if IsTextSlotPreviousKey(ctx.lastChangeBundle[i] and ctx.lastChangeBundle[i].key) then return true end
        end
        return false
    end

    local textSlotFollowupShouldHandle = #units == 0 and #groups == 0 and BundleHasTextSlotPrevious()
        and (
            ContainsAny(text, FollowupData.HIDE_REFERENCE_TERMS)
            or (followDirection and ContainsAny(text, FollowupData.TEXT_SLOT_MOVE_TERMS))
            or ContainsAny(text, FollowupData.TEXT_SLOT_RESIZE_TERMS)
        )

    local genericObjectFollowupReference = HasGenericObjectFollowupReference(text) or bareDirectionalFollowup
    if #units == 0 and #groups == 0 and genericObjectFollowupReference and not textSlotFollowupShouldHandle then
        local targetAttr = GenericFollowupTargetAttr(text, followDirection)
        if targetAttr then
            local genericChanges = {}
            local seenGenericKeys = {}
            for i = 1, #ctx.lastChangeBundle do
                local prev = ctx.lastChangeBundle[i]
                local setting = FindGenericRelatedSetting(prev, targetAttr)
                if setting and not seenGenericKeys[setting.key] then
                    local value, relativeDelta = GenericRelatedFollowupValue(setting, targetAttr, followDirection, prev)
                    if value ~= nil or relativeDelta ~= nil then
                        seenGenericKeys[setting.key] = true
                        genericChanges[#genericChanges + 1] = {
                            setting = setting,
                            value = value,
                            relativeDelta = relativeDelta,
                            direction = followDirection,
                        }
                    end
                end
            end
            if #genericChanges > 0 then
                return {
                    kind = "changes",
                    changes = genericChanges,
                    label = "Adjust previous MSUF area",
                    summary = "Continues from the last Assistant change.",
                }
            end
        end
    end

    local function AuraLaneInfoFromPrevious(prev)
        local key = tostring((prev and prev.key) or "")
        local unit, lane, attr = key:match("^auras3%.([^%.]+)%.([^%.]+)%.([^%.]+)$")
        if unit and (lane == "buff" or lane == "debuff") then
            return {
                key = key,
                kind = "unit",
                scope = unit,
                lane = lane,
                attr = attr,
            }
        end

        local group, groupLane, groupAttr = key:match("^gf_([^%.]+)%.auras%.([^%.]+)%.([^%.]+)$")
        if group and (groupLane == "buff" or groupLane == "debuff") then
            return {
                key = key,
                kind = "group",
                scope = group,
                lane = groupLane,
                attr = groupAttr,
            }
        end
        return nil
    end

    local function HasAuraObjectFollowupReference(textValue)
        return ContainsAny(textValue, FollowupData.AURA_REFERENCE_TERMS)
    end

    local function AuraLaneFollowupTargetAttr(textValue, direction)
        if ContainsAny(textValue, FollowupData.GROWTH_TERMS) then return "growth" end
        if ContainsAny(textValue, FollowupData.ANCHOR_TERMS) then return "anchor" end
        if direction and ContainsAny(textValue, FollowupData.MOVEMENT_TERMS) then
            if direction == "left" or direction == "right" then return "offsetX" end
            if direction == "up" or direction == "down" then return "offsetY" end
        end
        if ContainsAny(textValue, FollowupData.X_OFFSET_TERMS) then return "offsetX" end
        if ContainsAny(textValue, FollowupData.Y_OFFSET_TERMS) then return "offsetY" end
        if ContainsAny(textValue, FollowupData.AURA_PER_ROW_TERMS) then return "perRow" end
        if ContainsAny(textValue, FollowupData.AURA_SPACING_TERMS) then return "spacing" end
        if ContainsAny(textValue, FollowupData.LAYER_TERMS) then return "layer" end
        if ContainsAny(textValue, FollowupData.AURA_MAX_TERMS) then return "max" end
        if ContainsAny(textValue, FollowupData.AURA_SIZE_TERMS) then return "size" end
        return nil
    end

    local function AuraLaneFollowupSettingKey(info, targetAttr)
        if not (info and targetAttr) then return nil end
        if info.kind == "group" then
            local groupAttr = targetAttr == "offsetX" and "x" or targetAttr == "offsetY" and "y" or targetAttr
            return "gf_" .. tostring(info.scope) .. ".auras." .. tostring(info.lane) .. "." .. tostring(groupAttr)
        end
        return "auras3." .. tostring(info.scope) .. "." .. tostring(info.lane) .. "." .. tostring(targetAttr)
    end

    local function RequestedAuraMirrorLane(textValue)
        local wantsBuff = ContainsAny(textValue, FollowupData.BUFF_TERMS)
        local wantsDebuff = ContainsAny(textValue, FollowupData.DEBUFF_TERMS)
        if wantsBuff == wantsDebuff then return nil end
        return wantsBuff and "buff" or "debuff"
    end

    local function AddAuraLaneMirrorChange(changes, seen, prev, targetLane)
        local info = AuraLaneInfoFromPrevious(prev)
        if not (info and targetLane and info.lane ~= targetLane) then return end
        info = {
            kind = info.kind,
            scope = info.scope,
            lane = targetLane,
            attr = info.attr,
        }
        local setting = Registry:GetSetting(AuraLaneFollowupSettingKey(info, info.attr))
        if not setting or seen[setting.key] then return end
        seen[setting.key] = true
        local relativeDelta = tonumber(prev and prev.relativeDelta)
        if relativeDelta ~= nil and setting.type == "number" then
            changes[#changes + 1] = {
                setting = setting,
                relativeDelta = relativeDelta,
                direction = prev.direction,
            }
        elseif prev and prev.value ~= nil then
            changes[#changes + 1] = {
                setting = setting,
                value = prev.value,
                valueLabel = prev.valueLabel,
            }
        end
    end

    local function AuraLaneEnumFollowupValue(setting, targetAttr, direction)
        if not (setting and setting.type == "enum") then return nil end
        local compactText = Compact and Compact(text) or Normalize(text):gsub("%s+", "")
        local aliases = setting.valueAliases
        local bestValue, bestLen
        if type(aliases) == "table" then
            for alias, value in pairs(aliases) do
                local compactAlias = Compact and Compact(alias) or Normalize(alias):gsub("%s+", "")
                if compactAlias ~= "" and compactText:find(compactAlias, 1, true) and (not bestLen or #compactAlias > bestLen) then
                    bestValue, bestLen = value, #compactAlias
                end
            end
        end
        if bestValue ~= nil then return bestValue end
        if targetAttr == "growth" and direction then
            local dir = tostring(direction):upper()
            if setting.values then
                for i = 1, #setting.values do
                    if setting.values[i] == dir then return dir end
                end
            end
            if dir == "LEFT" then return "LEFTDOWN" end
            if dir == "UP" then return "RIGHTUP" end
            if dir == "RIGHT" or dir == "DOWN" then return "RIGHTDOWN" end
        end
        return nil
    end

    local function AuraLaneNumberFollowupValue(setting, targetAttr, direction)
        if not (setting and setting.type == "number") then return nil, nil end
        if targetAttr == "offsetX" or targetAttr == "offsetY" then
            local relative = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, 10) or nil
            if relative ~= nil then return nil, relative end
            if direction then
                local amount = A._RelativeNumberAmountForText(text)
                    or tonumber(setting.moveStep)
                    or tonumber(setting.moveAmount)
                    or tonumber(setting.step)
                    or 10
                if direction == "left" or direction == "down" then amount = -amount end
                return nil, amount
            end
            return nil, nil
        end

        local relative = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text) or nil
        if relative ~= nil then return nil, relative end
        local value = A._ExplicitNumberValue and A._ExplicitNumberValue(text) or nil
        if value == nil then value = FirstNumber(text) end
        if value ~= nil then return value, nil end
        return nil, nil
    end

    local auraObjectFollowupReference = HasAuraObjectFollowupReference(text) or bareDirectionalFollowup
    local auraReplayReference = targetReplayIntent or explicitFollowupReference or bareDirectionalFollowup
    if #units == 0 and #groups == 0 and not explicitAuraBulkScope and targetReplayIntent and auraObjectFollowupReference then
        local targetLane = RequestedAuraMirrorLane(text)
        if targetLane then
            local mirrorChanges = {}
            local seenMirrorKeys = {}
            for i = 1, #ctx.lastChangeBundle do
                AddAuraLaneMirrorChange(mirrorChanges, seenMirrorKeys, ctx.lastChangeBundle[i], targetLane)
            end
            if #mirrorChanges > 0 then
                return {
                    kind = "changes",
                    changes = mirrorChanges,
                    label = "Apply previous aura lane change",
                    summary = "Continues the last aura lane change on the sibling buff/debuff lane.",
                }
            end
        end
    end
    if #units == 0 and #groups == 0 and not explicitAuraBulkScope and auraReplayReference and auraObjectFollowupReference then
        local targetAttr = AuraLaneFollowupTargetAttr(text, followDirection)
        if targetAttr then
            local auraChanges = {}
            local seenAuraKeys = {}
            for i = 1, #ctx.lastChangeBundle do
                local info = AuraLaneInfoFromPrevious(ctx.lastChangeBundle[i])
                local key = AuraLaneFollowupSettingKey(info, targetAttr)
                local setting = key and Registry:GetSetting(key) or nil
                if setting and not seenAuraKeys[setting.key] then
                    local value, relativeDelta
                    if setting.type == "enum" then
                        value = AuraLaneEnumFollowupValue(setting, targetAttr, followDirection)
                    else
                        value, relativeDelta = AuraLaneNumberFollowupValue(setting, targetAttr, followDirection)
                    end
                    if value ~= nil or relativeDelta ~= nil then
                        seenAuraKeys[setting.key] = true
                        auraChanges[#auraChanges + 1] = {
                            setting = setting,
                            value = value,
                            relativeDelta = relativeDelta,
                            direction = followDirection,
                        }
                    end
                end
            end
            if #auraChanges > 0 then
                return {
                    kind = "changes",
                    changes = auraChanges,
                    label = "Adjust previous aura lane",
                    summary = "Continues from the last aura lane change.",
                }
            end
        end
    end

    local function TextSlotInfoFromPrevious(prev)
        local key = tostring((prev and prev.key) or "")
        local frameType, unit, area, slot
        unit, slot = key:match("^gf_([^%.]+)%.text(Left)$")
        if unit then frameType, area = "group", "hp" end
        if not unit then
            unit, slot = key:match("^gf_([^%.]+)%.text(Center)$")
            if unit then frameType, area = "group", "hp" end
        end
        if not unit then
            unit, slot = key:match("^gf_([^%.]+)%.text(Right)$")
            if unit then frameType, area = "group", "hp" end
        end
        if not unit then
            unit, slot = key:match("^gf_([^%.]+)%.powerText(Left)$")
            if unit then frameType, area = "group", "power" end
        end
        if not unit then
            unit, slot = key:match("^gf_([^%.]+)%.powerText(Center)$")
            if unit then frameType, area = "group", "power" end
        end
        if not unit then
            unit, slot = key:match("^gf_([^%.]+)%.powerText(Right)$")
            if unit then frameType, area = "group", "power" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.text(Left)$")
            if unit then frameType, area = "unitframe", "hp" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.text(Center)$")
            if unit then frameType, area = "unitframe", "hp" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.text(Right)$")
            if unit then frameType, area = "unitframe", "hp" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.powerText(Left)$")
            if unit then frameType, area = "unitframe", "power" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.powerText(Center)$")
            if unit then frameType, area = "unitframe", "power" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.powerText(Right)$")
            if unit then frameType, area = "unitframe", "power" end
        end
        if not unit then
            unit, slot = key:match("^gf_([^%.]+)%.hpText(Left)Offset[XY]$")
            if unit then frameType, area = "group", "hp" end
        end
        if not unit then
            unit, slot = key:match("^gf_([^%.]+)%.hpText(Center)Offset[XY]$")
            if unit then frameType, area = "group", "hp" end
        end
        if not unit then
            unit, slot = key:match("^gf_([^%.]+)%.hpText(Right)Offset[XY]$")
            if unit then frameType, area = "group", "hp" end
        end
        if not unit then
            unit, slot = key:match("^gf_([^%.]+)%.powerText(Left)Offset[XY]$")
            if unit then frameType, area = "group", "power" end
        end
        if not unit then
            unit, slot = key:match("^gf_([^%.]+)%.powerText(Center)Offset[XY]$")
            if unit then frameType, area = "group", "power" end
        end
        if not unit then
            unit, slot = key:match("^gf_([^%.]+)%.powerText(Right)Offset[XY]$")
            if unit then frameType, area = "group", "power" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.hpText(Left)Offset[XY]$")
            if unit then frameType, area = "unitframe", "hp" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.hpText(Center)Offset[XY]$")
            if unit then frameType, area = "unitframe", "hp" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.hpText(Right)Offset[XY]$")
            if unit then frameType, area = "unitframe", "hp" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.powerText(Left)Offset[XY]$")
            if unit then frameType, area = "unitframe", "power" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.powerText(Center)Offset[XY]$")
            if unit then frameType, area = "unitframe", "power" end
        end
        if not unit then
            unit, slot = key:match("^([^%.]+)%.powerText(Right)Offset[XY]$")
            if unit then frameType, area = "unitframe", "power" end
        end
        if not (frameType and unit and area and slot) then return nil end
        return {
            frameType = frameType,
            unit = unit,
            area = area,
            slot = slot,
            slotLower = slot:lower(),
            key = key,
        }
    end

    local function TextSlotSettingKey(info)
        if not info then return nil end
        if info.frameType == "group" then
            return "gf_" .. tostring(info.unit) .. "." .. (info.area == "hp" and "text" or "powerText") .. tostring(info.slot)
        end
        return tostring(info.unit) .. "." .. (info.area == "hp" and "text" or "powerText") .. tostring(info.slot)
    end

    local function TextSlotOffsetKey(info, direction)
        if not (info and direction) then return nil end
        local axis = (direction == "left" or direction == "right") and "OffsetX" or "OffsetY"
        local prefix = info.area == "hp" and "hpText" or "powerText"
        if info.frameType == "group" then
            return "gf_" .. tostring(info.unit) .. "." .. prefix .. tostring(info.slot) .. axis
        end
        return tostring(info.unit) .. "." .. prefix .. tostring(info.slot) .. axis
    end

    local function TextSlotFontKey(info)
        if not info then return nil end
        local attr = info.area == "hp" and "hpFontSize" or "powerFontSize"
        if info.frameType == "group" then return "gf_" .. tostring(info.unit) .. "." .. attr end
        return tostring(info.unit) .. "." .. attr
    end

    if #units == 0 and #groups == 0 then
        local hideTextSlot = ContainsAny(text, FollowupData.HIDE_REFERENCE_TERMS)
        local moveTextSlot = followDirection and ContainsAny(text, FollowupData.TEXT_SLOT_MOVE_TERMS)
        local resizeTextSlot = ContainsAny(text, FollowupData.TEXT_SLOT_RESIZE_TERMS)
        local textSlotFollowupReference = explicitFollowupReference or bareDirectionalFollowup or hideTextSlot
        if textSlotFollowupReference and (hideTextSlot or moveTextSlot or resizeTextSlot) then
            local textSlotChanges = {}
            for i = 1, #ctx.lastChangeBundle do
                local info = TextSlotInfoFromPrevious(ctx.lastChangeBundle[i])
                if info then
                    if hideTextSlot then
                        local setting = Registry:GetSetting(TextSlotSettingKey(info))
                        if setting then textSlotChanges[#textSlotChanges + 1] = { setting = setting, value = "NONE", textArea = info.area, textSlot = info.slotLower } end
                    elseif moveTextSlot then
                        local setting = Registry:GetSetting(TextSlotOffsetKey(info, followDirection))
                        if setting then
                            local amount = A._RelativeNumberAmountForText(text) or FirstNumber(text) or 10
                            if followDirection == "left" or followDirection == "down" then amount = -amount end
                            textSlotChanges[#textSlotChanges + 1] = { setting = setting, relativeDelta = amount, direction = followDirection }
                        end
                    elseif resizeTextSlot then
                        local setting = Registry:GetSetting(TextSlotFontKey(info))
                        if setting then
                            local sign = negativeIntent and -1 or 1
                            local amount = A._RelativeNumberAmountForText(text) or FirstNumber(text) or 1
                            textSlotChanges[#textSlotChanges + 1] = { setting = setting, relativeDelta = amount * sign }
                        end
                    end
                end
            end
            if #textSlotChanges > 0 then
                return {
                    kind = "changes",
                    changes = textSlotChanges,
                    label = "Adjust previous text slot",
                    summary = "Continues from the last HP/Power text-slot change.",
                }
            end
        end
    end

    if #units == 0 and #groups == 0 and exactValueIntent then
        local exactChanges = {}
        for i = 1, #ctx.lastChangeBundle do
            local prev = ctx.lastChangeBundle[i]
            local setting = prev and prev.key and Registry:GetSetting(prev.key)
            local value = FollowupExactValue(setting)
            if value ~= nil then
                exactChanges[#exactChanges + 1] = { setting = setting, value = value }
            end
        end
        if #exactChanges > 0 then
            if #exactChanges > 1 and not pluralExactValueReference then
                return {
                    kind = "ambiguous",
                    choices = exactChanges,
                    label = "Multiple previous numeric options",
                    summary = "Asks which previous numeric option should receive the follow-up value.",
                }
            end
            return {
                kind = "changes",
                changes = exactChanges,
                label = "Set previous numeric value",
                summary = "Continues from the previous numeric option.",
            }
        end
    end

    if #units == 0 and #groups == 0
        and (positiveIntent or negativeIntent or neutralIntent or oppositeIntent or reverseCorrectionIntent
            or tooPositiveIntent or tooNegativeIntent or notEnoughIntent or leftIntent or rightIntent
            or relativeNumberIntent)
        and (not commandIntent or explicitFollowupReference or bareDirectionalFollowup)
    then
        local repeatChanges = {}
        for i = 1, #ctx.lastChangeBundle do
            local prev = ctx.lastChangeBundle[i]
            local setting = prev and prev.key and Registry:GetSetting(prev.key)
            if setting and setting.type == "number" then
                local direction = followDirection or prev.direction
                local siblingKey = followDirection and FollowupSiblingKey(prev.key, followDirection) or nil
                local sibling = siblingKey and Registry:GetSetting(siblingKey) or nil
                if sibling and sibling.type == "number" then setting = sibling end
                local prevDelta = tonumber(prev.relativeDelta)
                local directionDelta = prevDelta
                if directionDelta == nil then directionDelta = PreviousValueDelta(prev) end
                local explicitAmount = A._RelativeNumberAmountForText(text)
                local movementRepeatDelta = PreviousMovementDelta(prev)
                local relativeDelta
                if relativeNumberIntent and P.RelativeNumberDeltaForText then
                    -- A bare "more" after a positional nudge should repeat that
                    -- nudge's magnitude.  Feeding it through the generic number
                    -- parser first would replace a previous +/-10 movement with
                    -- the registry setting's ordinary step (usually 1).  An
                    -- explicit amount still wins, and non-movement settings keep
                    -- their normal step-based interpretation.
                    if movementRepeatDelta == nil or explicitAmount ~= nil then
                        relativeDelta = P.RelativeNumberDeltaForText(setting, text)
                    end
                end
                local amount = FollowupAmount(setting, prevDelta, explicitAmount)
                local previousNegative = (prev.direction == "left" or prev.direction == "down") or (directionDelta ~= nil and directionDelta < 0)
                local sign = nil
                if (oppositeIntent or reverseCorrectionIntent) and directionDelta ~= nil and directionDelta ~= 0 then
                    sign = previousNegative and 1 or -1
                elseif reverseCorrectionIntent or tooPositiveIntent then
                    sign = -1
                elseif tooNegativeIntent then
                    sign = 1
                elseif notEnoughIntent and directionDelta ~= nil and directionDelta ~= 0 then
                    sign = previousNegative and -1 or 1
                elseif notEnoughIntent then
                    sign = 1
                elseif followDirection == "left" or followDirection == "down" then
                    sign = -1
                elseif followDirection == "right" or followDirection == "up" then
                    sign = 1
                elseif negativeIntent then
                    sign = -1
                elseif positiveIntent then
                    sign = 1
                elseif neutralIntent and (directionDelta ~= nil or neutralIncreaseIntent) then
                    sign = previousNegative and -1 or 1
                end
                if relativeDelta == nil and sign ~= nil then
                    relativeDelta = amount * sign
                end
                if relativeDelta ~= nil then
                    repeatChanges[#repeatChanges + 1] = { setting = setting, relativeDelta = relativeDelta, direction = direction }
                end
            end
        end
        if #repeatChanges > 0 then
            return {
                kind = "changes",
                changes = repeatChanges,
                label = "Repeat previous adjustment",
                summary = "Continues from the previous numeric adjustment.",
            }
        end
    end
    if #units == 0 and #groups == 0 and (targetReplayIntent or pureNumberIntent) then
        local colorFollowup = A._BuildColorTokenFollowup(text, ctx)
        if colorFollowup then return colorFollowup end
    end
    if #units == 0 and #groups == 0 then return nil end
    if not targetReplayIntent then return nil end

    local function GlobalScopeForGroup(scope)
        if scope == "party" then return "gf_party" end
        if scope == "raid" or scope == "mythicraid" then return "gf_raid" end
        return scope
    end

    local UNIT_TO_GROUP_REPLAY_ATTR = {
        nameTextAnchor = "nameAnchor",
        hpTextLeft = "healthTextLeft",
        hpTextCenter = "healthTextCenter",
        hpTextRight = "healthTextRight",
        hpTextSeparator = "healthTextDelimiter",
        hpTextReverse = "healthTextReverse",
        hpOffsetX = "healthTextOffsetX",
        hpOffsetY = "healthTextOffsetY",
        hpTextLayer = "healthTextLayer",
        powerOffsetX = "powerTextOffsetX",
        powerOffsetY = "powerTextOffsetY",
    }

    local GROUP_TO_UNIT_REPLAY_ATTR = {
        nameAnchor = "nameTextAnchor",
        healthTextLeft = "hpTextLeft",
        healthTextCenter = "hpTextCenter",
        healthTextRight = "hpTextRight",
        healthTextDelimiter = "hpTextSeparator",
        healthTextReverse = "hpTextReverse",
        healthTextOffsetX = "hpOffsetX",
        healthTextOffsetY = "hpOffsetY",
        healthTextLayer = "hpTextLayer",
        powerTextOffsetX = "powerOffsetX",
        powerTextOffsetY = "powerOffsetY",
    }

    local function ReplayAttributeForTarget(sourceFrameType, targetFrameType, attribute)
        attribute = tostring(attribute or "")
        if sourceFrameType == "unitframe" and targetFrameType == "group" then
            return UNIT_TO_GROUP_REPLAY_ATTR[attribute] or attribute
        end
        if sourceFrameType == "group" and targetFrameType == "unitframe" then
            return GROUP_TO_UNIT_REPLAY_ATTR[attribute] or attribute
        end
        return attribute
    end

    local function AddReplayTarget(out, settingUnit, frameType, attribute, value, sourceFrameType)
        if not (settingUnit and frameType and attribute) then return end
        attribute = ReplayAttributeForTarget(sourceFrameType, frameType, attribute)
        local found = Registry:FindSettings({ unit = settingUnit, frameType = frameType, attribute = attribute })
        local setting = found[1]
        if setting then
            for i = 1, #out do
                if out[i] and out[i].setting and out[i].setting.key == setting.key then return end
            end
            out[#out + 1] = { setting = setting, value = value }
        end
    end

    local ANCHOR_FRAME_VALUES = {
        EssentialCooldownViewer = true,
        UtilityCooldownViewer = true,
        BuffIconCooldownViewer = true,
    }

    local function AddAnchorReplayTargets(out, prev)
        if not (prev and prev.attribute and prev.value ~= nil) then return end
        local attr = tostring(prev.attribute)
        local frameType = tostring(prev.frameType or "")
        local value = prev.value
        if frameType == "unitframe" and attr == "anchorFrameName" then
            for j = 1, #groups do AddReplayTarget(out, groups[j], "group", "customAnchorFrame", value) end
        elseif frameType == "group" and attr == "customAnchorFrame" then
            for j = 1, #units do AddReplayTarget(out, units[j], "unitframe", "anchorFrameName", value) end
        elseif frameType == "unitframe" and attr == "anchorToUnitframe" then
            if ANCHOR_FRAME_VALUES[tostring(value)] then
                for j = 1, #groups do AddReplayTarget(out, groups[j], "group", "customAnchorFrame", value) end
            elseif value == "GLOBAL" then
                for j = 1, #groups do AddReplayTarget(out, groups[j], "group", "anchorToFrame", "FREE") end
            else
                for j = 1, #groups do AddReplayTarget(out, groups[j], "group", "anchorToFrame", value) end
            end
        elseif frameType == "group" and attr == "anchorToFrame" then
            if value == "FREE" then
                for j = 1, #units do AddReplayTarget(out, units[j], "unitframe", "anchorToUnitframe", "GLOBAL") end
            else
                for j = 1, #units do AddReplayTarget(out, units[j], "unitframe", "anchorToUnitframe", value) end
            end
        end
    end

    local changes = {}
    for i = 1, #ctx.lastChangeBundle do
        local prev = ctx.lastChangeBundle[i]
        if prev and prev.attribute ~= nil and prev.value ~= nil then
            for j = 1, #units do
                local targetFrameType = prev.frameType == "group" and "unitframe" or prev.frameType
                AddReplayTarget(changes, units[j], targetFrameType, prev.attribute, prev.value, prev.frameType)
            end
            for j = 1, #groups do
                local scope = groups[j]
                local targetFrameType = prev.frameType == "unitframe" and "group" or prev.frameType
                local settingUnit = scope
                if targetFrameType == "globalBars" or targetFrameType == "fonts" then
                    settingUnit = GlobalScopeForGroup(scope)
                end
                AddReplayTarget(changes, settingUnit, targetFrameType, prev.attribute, prev.value, prev.frameType)
            end
            AddAnchorReplayTargets(changes, prev)
        end
    end
    if #changes == 0 then
        for i = 1, #ctx.lastChangeBundle do
            local prev = ctx.lastChangeBundle[i]
            if prev and prev.attribute ~= nil and prev.value ~= nil and (prev.frameType == "unitframe" or prev.frameType == "group") then
                for j = 1, #units do
                    AddReplayTarget(changes, units[j], "unitframe", prev.attribute, prev.value, prev.frameType)
                end
                for j = 1, #groups do
                    AddReplayTarget(changes, groups[j], "group", prev.attribute, prev.value, prev.frameType)
                end
                AddAnchorReplayTargets(changes, prev)
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Apply previous change to another frame",
        summary = "Continues from the last Assistant change.",
    }
end

local function BuildBooleanCorrection(text, ctx)
    if IsPageExplanationQuestion(text) then return nil end
    if not (ctx and type(ctx.lastSetting) == "string") then return nil end
    if not ContextSubjectRecent(ctx, 3) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    if not ContainsAny(text, FollowupData.BOOLEAN_CORRECTION_TERMS) then return nil end
    local setting = Registry:GetSetting(ctx.lastSetting)
    if not setting or setting.type ~= "boolean" then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Correct previous option",
        summary = "Continues from the last Assistant option.",
    }
end

P.NON_AURA_DEBUFF_CONTROL_TERMS = P.NON_AURA_DEBUFF_CONTROL_TERMS or {
    "debuff stripe", "debuff stripes",
    "dispel overlay", "dispel overlays", "unitframe dispel", "unit frame dispel",
    "unitframe dispel overlay", "unit frame dispel overlay",
    "debuff overlay", "debuff overlays",
    "health bar dispel overlay", "healthbar dispel overlay",
}

local function ParseSetting(text, ctx)
    if ContainsAny(text, FollowupData.AURA_KIND_TERMS)
        and not ContainsAny(text, P.NON_AURA_DEBUFF_CONTROL_TERMS) then
        return nil
    end
    local frameType = DetectFrameType(text, ctx)
    local direction = DetectDirection(text, ctx)
    local movementIntent = direction and ContainsAny(text, FollowupData.PARSE_MOVEMENT_TERMS) and not ContainsAny(text, FollowupData.PARSE_ANCHOR_TERMS)
    local attr = movementIntent and ((direction == "left" or direction == "right") and "offsetX" or "offsetY") or DetectAttribute(text, frameType)
    if not attr then return nil end
    if attr == "enabled" and ContainsAny(text, FollowupData.ENABLED_GUARD_TERMS) then
        return nil
    end
    if (attr == "width" or attr == "height") and ContainsAny(text, FollowupData.DIMENSION_GUARD_TERMS) then
        return nil
    end
    local useLastUnit = ShouldUseLastUnitContext(text) and ContextSubjectRecent(ctx, 3)
    if useLastUnit and frameType == "unitframe" and ctx and IsGroupContextUnit(ctx.lastUnit) then
        frameType = "group"
    end

    local units = {}
    if frameType == "group" then
        units = DetectGroups(text)
    else
        units = DetectUnits(text)
    end
    if #units == 0 and useLastUnit then
        if frameType == "group" then
            units = ContextGroups(ctx)
        else
            units = ContextUnits(ctx)
        end
    end

    local value
    local relativeDelta
    if attr == "offsetX" or attr == "offsetY" then
        local amount = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then amount = -amount end
        value = nil
        relativeDelta = amount
    elseif attr == "width" or attr == "height" then
        relativeDelta = RelativeNumberDeltaForText(nil, text, 10)
        if relativeDelta == nil then value = FirstNumber(text) end
    else
        value = DetectBoolean(text)
    end

    if value == nil and relativeDelta == nil and (attr == "width" or attr == "height") then
        local candidates
        if #units > 0 then
            candidates = Registry:FindSettings({ units = units, frameType = frameType, attribute = attr })
        else
            candidates = Registry:FindSettings({ frameType = frameType, attribute = attr })
        end
        if #candidates == 1 then
            local setting = candidates[1]
            local parts = {}
            if setting.min ~= nil then parts[#parts + 1] = "min " .. tostring(setting.min) end
            if setting.max ~= nil then parts[#parts + 1] = "max " .. tostring(setting.max) end
            if setting.step ~= nil then parts[#parts + 1] = "step " .. tostring(setting.step) end
            local hint = #parts > 0 and ("Use a number (" .. table.concat(parts, ", ") .. ").") or "Use a number."
            return {
                kind = "answer",
                status = "ambiguous",
                text = "What value do you want me to use for " .. tostring(setting.label or "this option") .. "? " .. hint,
                summary = "Value clarification for an MSUF option.",
            }
        end
    end

    if value == nil and relativeDelta == nil and attr ~= "enabled" then return nil end
    if value == nil and relativeDelta == nil and attr == "enabled" then value = DetectBoolean(text) end
    if value == nil and relativeDelta == nil then return nil end

    local candidates
    if #units > 0 then
        candidates = Registry:FindSettings({ units = units, frameType = frameType, attribute = attr })
    else
        candidates = Registry:FindSettings({ frameType = frameType, attribute = attr })
    end
    if #candidates == 0 then
        if attr == "raidMarker" then return nil end
        return {
            kind = "unknown",
            text = "I found that option. I can show where it is without changing it.",
            status = "failed",
        }
    end
    if #units == 0 and #candidates > 1 then
        if ContainsAny(text, FollowupData.ALL_SCOPE_TERMS) then
            return {
                kind = "changes",
                changes = BuildChanges(candidates, value, relativeDelta, direction),
                label = "Assistant option change",
                bulkSafe = true,
                summary = "MSUF options change.",
            }
        end
        return {
            kind = "ambiguous",
            choices = BuildChanges(candidates, value, relativeDelta, direction),
            label = "Multiple matching options",
        }
    end
    return {
        kind = "changes",
        changes = BuildChanges(candidates, value, relativeDelta, direction),
        label = "Assistant option change",
        summary = "MSUF options change.",
    }
end

P.ContextUnits = ContextUnits
P.GROUP_CONTEXT_UNITS = GROUP_CONTEXT_UNITS
P.IsGroupContextUnit = IsGroupContextUnit
P.ContextGroups = ContextGroups
P.ShouldUseLastUnitContext = ShouldUseLastUnitContext
P.ContextSubjectRecent = ContextSubjectRecent
P.BuildFollowup = BuildFollowup
P.BuildContinuationFollowup = BuildContinuationFollowup
P.BuildBooleanCorrection = BuildBooleanCorrection
P.ParseSetting = ParseSetting
