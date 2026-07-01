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

-- Follow-up parser for multi-step assistant flows.
-- These handlers interpret short replies like "yes", "party only", or a copied profile name
-- in the context of the pending assistant state. They should be conservative because the
-- original command may have been parsed in a previous frame or after a yield.
local Normalize = P.Normalize
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
    return ContainsAny(text, {
        "it", "that", "this", "das", "same", "again", "wieder", "back", "more", "mehr",
        "frame", "unitframe", "name", "text", "health", "hp", "power", "width", "height",
        "size", "alpha", "opacity", "position", "offset", "anchor",
    })
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
        if ContainsAny(text, {
            "why is that", "why is this", "why are those", "why are these",
            "why is it", "why are they",
        }) then
            return false
        end
        return ContainsAny(text, {
            "hidden", "missing", "not showing", "not visible", "invisible",
            "disabled", "gone", "broken", "doesnt work", "does not work",
            "frame", "frames", "cast bar", "castbar", "buff", "buffs",
            "debuff", "debuffs", "aura", "auras", "text", "icon", "icons",
        })
    end

    if text:match("^why%s+cant%s+") or text:match("^why%s+cannot%s+")
        or text:match("^why%s+can%s+not%s+") or text:match("^why%s+doesnt%s+")
        or text:match("^why%s+does%s+not%s+") or text:match("^why%s+dont%s+")
        or text:match("^why%s+do%s+not%s+") then
        return ContainsAny(text, {
            "edit mode", "exit", "close", "cancel", "leave", "start", "open",
            "cast bar", "castbar", "frame", "frames", "aura", "auras",
            "buff", "buffs", "debuff", "debuffs", "profile", "import", "export",
            "anchor picker", "custom anchor", "copy", "paste",
        })
    end

    return false
end

local function IsPageExplanationQuestion(text)
    text = Normalize(text)
    if text == "" then return false end
    if ContainsAny(text, {
        "explain this page", "explain current page", "explain the page",
        "explain page", "what is this page", "what can i do on this page",
        "what can i do on current page", "what can i change on this page",
        "what can i change on current page", "what can be changed on this page",
        "how can i configure this page", "show me commands for this page",
        "commands for this page", "current page help", "this page help",
        "help on this page", "help for this page", "page help",
    }) then
        return true
    end
    return false
end

function A._ParseFollowupAnswer(text, ctx)
    if IsTroubleshootingWhyQuestion(text) or IsPageExplanationQuestion(text) then return nil end
    local asksWhatChanged = ContainsAny(text, {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you just change", "what exactly did you change", "what did you set",
        "last change", "last assistant change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
        "show me last change", "show me the last change", "what now", "what happened",
        "what did that do", "what did this do", "what does that mean",
        "what does this mean", "explain that", "explain this",
        "explain the last change", "explain last change", "what is the result",
        "what was the result",
        "what did you copy", "what did you just copy", "what was copied", "last copy",
        "show last copy", "show me last copy",
    })
    local asksWhy = ContainsAny(text, {
        "why did you change", "why did you do that", "why did you do this",
        "why did you set", "why did you pick", "why that change",
        "why this change", "why did that happen", "why did this happen",
        "why", "why that", "why this", "why did you", "why did you choose",
        "why did you choose that", "why did you choose this",
        "why did you choose that option", "why did you choose this option",
        "why that option", "why this option", "why did you pick that option",
        "why did you pick this option", "why did you use that",
        "why did you use this", "explain why",
    })
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

local function BuildFollowup(text, ctx)
    if not ctx then return nil end
    if IsPageExplanationQuestion(text) then return nil end
    local copyActionFollowup = P.BuildCopyActionFollowup and P.BuildCopyActionFollowup(text, ctx)
    if copyActionFollowup then return copyActionFollowup end
    if ContainsAny(text, {
        "what did you copy", "what was copied", "what did you just copy",
        "last copy", "previous copy", "copy history", "show copy",
    }) and ctx.lastAction ~= "copy_unit" and ctx.lastAction ~= "copy_group" then
        return {
            kind = "answer",
            status = "info",
            text = "I don't have an earlier copy task to repeat yet.",
            summary = "Reports that there is no previous copy task yet.",
        }
    end
    if type(ctx.lastChangeBundle) ~= "table" then return nil end
    local positiveTerms = {
        "bigger", "larger", "higher", "thicker", "wider", "taller", "increase", "raise", "up", "grow", "stronger",
        "brighter", "lighter", "more opaque", "more visible",
        "groesser", "hoeher", "dicker", "breiter", "heller", "hoch",
    }
    local negativeTerms = {
        "smaller", "lower", "thinner", "narrower", "shorter", "less", "decrease", "reduce", "down", "shrink", "weaker",
        "darker", "dimmer", "more transparent", "less opaque", "fainter",
        "kleiner", "tiefer", "duenner", "weniger", "dunkler", "runter",
    }
    local neutralTerms = {
        "more", "mehr", "weiter", "further", "farther", "again", "do it again", "same again", "once more", "one more",
        "another", "repeat", "keep going", "continue", "nochmal", "noch mal",
    }
    local oppositeTerms = {
        "opposite", "opposite way", "other way", "reverse", "reverse it", "undo direction", "andersrum", "umgekehrt",
    }
    local reverseCorrectionTerms = {
        "too much", "too far", "not that much", "went too far", "go back a bit", "back a bit", "a bit back",
        "zu viel", "zu weit", "etwas zurueck",
    }
    local tooPositiveTerms = {
        "too high", "too big", "too large", "too thick", "too wide", "too tall", "too bright", "too visible", "too opaque",
        "zu hoch", "zu gross", "zu dick", "zu breit", "zu hell",
    }
    local tooNegativeTerms = {
        "too low", "too small", "too thin", "too narrow", "too short", "too dark", "too transparent", "not visible enough",
        "zu niedrig", "zu klein", "zu duenn", "zu schmal", "zu dunkel",
    }
    local notEnoughTerms = {
        "not enough", "needs more", "need more", "more still", "still more", "not far enough",
        "not big enough", "not high enough", "not wide enough", "not visible enough",
        "nicht genug", "mehr noch",
    }
    local replayTerms = {
        "too", "also", "as well", "same", "same for", "same on", "same to",
        "do the same", "do that", "do it", "apply that", "apply it", "copy that", "copy it",
        "repeat that", "repeat it", "repeat that for", "repeat it for",
        "apply that to", "apply it to", "do that for", "do it for",
        "make same change", "make the same change", "make that same change",
        "auch", "auch fuer", "auch fur", "genauso", "genauso fuer", "genauso fur",
        "das auch", "mach das", "mach das gleiche", "das gleiche fuer", "das gleiche fur",
    }
    local rightIntent = ContainsAny(text, { "right", "rechts" })
    local leftIntent = ContainsAny(text, { "left", "links" })
    local upIntent = ContainsAny(text, { "up", "higher", "hoch", "oben", "hoeher" })
    local downIntent = ContainsAny(text, { "down", "lower", "tiefer", "runter", "unten" })
    local followDirection = rightIntent and "right" or (leftIntent and "left" or (upIntent and "up" or (downIntent and "down" or nil)))
    local forcePositive = ContainsAny(text, { "more opaque", "less transparent", "more visible", "brighter", "lighter", "heller" })
    local forceNegative = ContainsAny(text, { "more transparent", "less opaque", "darker", "dimmer", "fainter", "dunkler" })
    local positiveIntent = forcePositive or (ContainsAny(text, positiveTerms) and not forceNegative)
    local negativeIntent = forceNegative or (ContainsAny(text, negativeTerms) and not forcePositive)
    local neutralIntent = ContainsAny(text, neutralTerms)
    local neutralIncreaseIntent = ContainsAny(text, { "more", "mehr", "weiter", "further", "farther", "once more", "one more", "another", "keep going", "continue" })
    local oppositeIntent = ContainsAny(text, oppositeTerms)
    local reverseCorrectionIntent = ContainsAny(text, reverseCorrectionTerms)
    local tooPositiveIntent = ContainsAny(text, tooPositiveTerms)
    local tooNegativeIntent = ContainsAny(text, tooNegativeTerms)
    local notEnoughIntent = ContainsAny(text, notEnoughTerms)
    local targetReplayIntent = ContainsAny(text, replayTerms)
    local explicitAuraBulkScope = ContainsAny(text, {
        "all aura", "all auras", "all aura icon", "all aura icons",
        "all unit aura", "all unit auras", "all unit aura icon", "all unit aura icons",
        "all group aura", "all group auras", "all group aura icon", "all group aura icons",
        "all buff", "all buffs", "all buff icon", "all buff icons",
        "all debuff", "all debuffs", "all debuff icon", "all debuff icons",
        "every aura", "every aura icon", "every aura icons",
        "every buff", "every buff icon", "every debuff", "every debuff icon",
    })
    local pureNumberIntent = tostring(text or ""):match("^[-+]?%d+%.?%d*$") ~= nil
    local bareExactValueIntent = tostring(text or ""):match("^to%s+[-+]?%d+%.?%d*$") ~= nil
        or tostring(text or ""):match("^move%s+to%s+[-+]?%d+%.?%d*$") ~= nil
        or tostring(text or ""):match("^set%s+to%s+[-+]?%d+%.?%d*$") ~= nil
        or tostring(text or ""):match("^change%s+to%s+[-+]?%d+%.?%d*$") ~= nil
        or tostring(text or ""):match("^auf%s+[-+]?%d+%.?%d*$") ~= nil
        or tostring(text or ""):match("^zu%s+[-+]?%d+%.?%d*$") ~= nil
    local exactValueReference = ContainsAny(text, {
        "it", "that", "this",
        "last setting", "last value", "actually", "instead", "rather",
        "no", "nope", "wait", "oops",
        "set it", "set them", "set those", "set these",
        "make it", "make them", "make those", "make these",
        "change it", "change them", "change those", "change these",
        "move it to", "move them to", "move those to", "move these to",
        "them to", "those to", "these to",
        "use",
    })
    local pluralExactValueReference = ContainsAny(text, {
        "them", "those", "these", "both", "all", "all of them",
        "each", "every", "settings", "options", "values",
    })
    local exactValueIntent = pureNumberIntent
        or bareExactValueIntent
        or (not explicitAuraBulkScope and ContainsAny(text, { "min", "minimum", "max", "maximum" }))
        or (not explicitAuraBulkScope and exactValueReference and FirstNumber(text) ~= nil)
    local commandIntent = ContainsAny(text, {
        "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift",
        "create", "select", "use", "reset", "copy", "open", "import", "export", "rename", "delete", "remove", "switch", "assign",
        "setze", "stelle", "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken", "einblenden", "ausblenden", "verschiebe", "verschieben",
    })
    local auraLaneObjectIntent = ContainsAny(text, {
        "them", "those", "these", "their",
        "the icon", "the icons", "icons", "aura icon", "aura icons",
        "buff icon", "buff icons", "debuff icon", "debuff icons",
        "buffs", "debuffs", "auras",
    }) and ContainsAny(text, {
        "move", "nudge", "shift", "offset", "position", "left", "right", "up", "down",
        "x offset", "y offset", "per row", "icons per row", "spacing", "gap",
        "layer", "z", "z layer", "frame level", "cap", "limit", "max", "maximum", "count",
        "size", "bigger", "larger", "smaller", "shrink", "growth", "grow", "anchor",
    })
    local genericObjectIntent = ContainsAny(text, {
        "it", "its", "that", "this", "them", "those", "these", "their",
        "the frame", "the frames", "the bar", "the bars", "the text", "the icon", "the icons",
        "same object", "same option area",
    }) and ContainsAny(text, {
        "move", "nudge", "shift", "offset", "position", "left", "right", "up", "down",
        "x offset", "y offset", "width", "height", "wider", "narrower", "taller", "shorter",
        "size", "bigger", "larger", "smaller", "shrink",
        "layer", "z", "z layer", "frame level", "anchor", "growth", "grow",
        "show", "hide", "enable", "disable", "turn on", "turn off", "on", "off",
    })
    local explicitFollowupReference = ContainsAny(text, { "it", "that", "this", "them", "those", "these", "same", "do it", "do that", "again", "more", "less", "opposite", "other way" })
    local wordCount = 0
    for _ in tostring(text or ""):gmatch("%S+") do wordCount = wordCount + 1 end
    local bareDirectionalFollowup = ContainsAny(text, {
        "left", "right", "up", "down",
        "move left", "move right", "move up", "move down",
        "nudge left", "nudge right", "nudge up", "nudge down",
        "shift left", "shift right", "shift up", "shift down",
    }) and wordCount <= 3 and not ContainsAny(text, { "anchor", "attach", "point", "bottom left", "bottom right", "top left", "top right" })
    local hasIntent = positiveIntent or negativeIntent or neutralIntent or oppositeIntent or reverseCorrectionIntent
        or tooPositiveIntent or tooNegativeIntent or notEnoughIntent or exactValueIntent
        or leftIntent or rightIntent or targetReplayIntent
        or auraLaneObjectIntent
        or genericObjectIntent
        or ContainsAny(text, { "hide it", "clear it", "remove it", "empty it", "turn it off", "disable it", "hide that", "clear that", "remove that" })
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
        if ContainsAny(text, { "maximum", "max" }) and setting.max ~= nil then return setting.max end
        if ContainsAny(text, { "minimum", "min" }) and setting.min ~= nil then return setting.min end
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
        if explicitAmount == nil and ContainsAny(text, { "a bit", "bit", "a little", "little", "slightly", "tiny", "small step", "etwas" }) then
            amount = amount / 2
            if amount < step then amount = step end
        elseif explicitAmount == nil and ContainsAny(text, { "half", "half as much" }) then
            amount = amount / 2
            if amount < step then amount = step end
        elseif explicitAmount == nil and not reverseCorrectionIntent and ContainsAny(text, { "a lot", "much", "way more", "way less", "far more", "far less", "big step", "large step", "twice", "double" }) then
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
        return ContainsAny(textValue, {
            "it", "its", "that", "this", "them", "those", "these", "their",
            "the frame", "the frames", "the bar", "the bars", "the text", "the icon", "the icons",
            "same", "same object", "same option area",
        })
    end

    local function GenericFollowupTargetAttr(textValue, direction)
        if ContainsAny(textValue, { "show", "hide", "enable", "disable", "turn on", "turn off", "on", "off" }) then return "enabled" end
        if ContainsAny(textValue, { "growth direction", "grow direction", "growth", "grow", "grows" }) then return "growth" end
        if ContainsAny(textValue, { "anchor", "anchor point", "position anchor", "bottom left", "bottom right", "top left", "top right", "bottomleft", "bottomright", "topleft", "topright" }) then return "anchor" end
        if direction and ContainsAny(textValue, { "move", "nudge", "shift", "offset", "position", "left", "right", "up", "down", "links", "rechts", "hoch", "runter", "oben", "unten" }) then
            if direction == "left" or direction == "right" then return "offsetX" end
            if direction == "up" or direction == "down" then return "offsetY" end
        end
        if ContainsAny(textValue, { "x offset", "offset x", "horizontal offset" }) then return "offsetX" end
        if ContainsAny(textValue, { "y offset", "offset y", "vertical offset" }) then return "offsetY" end
        if ContainsAny(textValue, { "width", "wider", "narrower", "wide", "breite", "breiter", "schmaler" }) then return "width" end
        if ContainsAny(textValue, { "height", "taller", "shorter", "tall", "hoehe", "hoeher" }) then return "height" end
        if ContainsAny(textValue, { "layer", "z", "z layer", "z level", "z-level", "z order", "z-order", "z index", "z-index", "draw layer", "frame level", "strata" }) then return "layer" end
        if ContainsAny(textValue, { "icon size", "text size", "font size", "size", "bigger", "larger", "smaller", "shrink", "groesse", "grosse", "groesser", "kleiner" }) then return "size" end
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
        if ContainsAny(textValue, { "power text", "mana text", "power number", "mana number", "power value", "mana value" }) then
            prefixes[#prefixes + 1] = "power"
            prefixes[#prefixes + 1] = "powerText"
        elseif ContainsAny(textValue, { "hp text", "health text", "health number", "hp number", "health value", "hp value" }) then
            prefixes[#prefixes + 1] = "hp"
            prefixes[#prefixes + 1] = "healthText"
            prefixes[#prefixes + 1] = "text"
        elseif ContainsAny(textValue, { "name text", "name" }) then
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
            ContainsAny(text, { "hide it", "clear it", "remove it", "empty it", "turn it off", "disable it", "hide that", "clear that", "remove that" })
            or (followDirection and ContainsAny(text, { "move", "nudge", "shift", "left", "right", "up", "down" }))
            or ContainsAny(text, { "make it bigger", "make it larger", "bigger", "larger", "increase it", "make it smaller", "smaller", "decrease it", "shrink it" })
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
        return ContainsAny(textValue, {
            "it", "that", "this", "them", "those", "these", "their",
            "the icon", "the icons", "icons", "aura icon", "aura icons",
            "buff icon", "buff icons", "debuff icon", "debuff icons",
            "buffs", "debuffs", "auras", "same",
        })
    end

    local function AuraLaneFollowupTargetAttr(textValue, direction)
        if ContainsAny(textValue, { "growth direction", "grow direction", "growth", "grow", "grows" }) then return "growth" end
        if ContainsAny(textValue, { "anchor", "anchor point", "position anchor", "bottom left", "bottom right", "top left", "top right", "bottomleft", "bottomright", "topleft", "topright" }) then return "anchor" end
        if direction and ContainsAny(textValue, { "move", "nudge", "shift", "offset", "position", "left", "right", "up", "down", "links", "rechts", "hoch", "runter", "oben", "unten" }) then
            if direction == "left" or direction == "right" then return "offsetX" end
            if direction == "up" or direction == "down" then return "offsetY" end
        end
        if ContainsAny(textValue, { "x offset", "offset x", "horizontal offset" }) then return "offsetX" end
        if ContainsAny(textValue, { "y offset", "offset y", "vertical offset" }) then return "offsetY" end
        if ContainsAny(textValue, { "per row", "icons per row", "wrap count", "row count" }) then return "perRow" end
        if ContainsAny(textValue, { "spacing", "gap", "icon gap", "space them", "space out" }) then return "spacing" end
        if ContainsAny(textValue, { "layer", "z", "z layer", "z level", "z-level", "z order", "z-order", "z index", "z-index", "draw layer", "frame level", "strata" }) then return "layer" end
        if ContainsAny(textValue, {
            "max", "maximum", "max icons", "maximum icons", "max count", "maximum count",
            "icon count", "aura count", "buff count", "debuff count", "count",
            "cap", "caps", "capped", "aura cap", "buff cap", "debuff cap",
            "limit", "limits", "limited", "icon limit", "aura limit", "buff limit", "debuff limit",
        }) then return "max" end
        if ContainsAny(textValue, { "icon size", "icons size", "size", "bigger", "larger", "smaller", "shrink", "groesse", "grosse", "groesser", "kleiner" }) then return "size" end
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
        local wantsBuff = ContainsAny(textValue, { "buff", "buffs" })
        local wantsDebuff = ContainsAny(textValue, { "debuff", "debuffs" })
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
        local hideTextSlot = ContainsAny(text, { "hide it", "clear it", "remove it", "empty it", "turn it off", "disable it", "hide that", "clear that", "remove that" })
        local moveTextSlot = followDirection and ContainsAny(text, { "move", "nudge", "shift", "left", "right", "up", "down" })
        local resizeTextSlot = ContainsAny(text, { "make it bigger", "make it larger", "bigger", "larger", "increase it", "make it smaller", "smaller", "decrease it", "shrink it" })
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
            or tooPositiveIntent or tooNegativeIntent or notEnoughIntent or leftIntent or rightIntent)
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
                local relativeDelta = nil
                local prevDelta = tonumber(prev.relativeDelta)
                local directionDelta = prevDelta
                if directionDelta == nil then directionDelta = PreviousValueDelta(prev) end
                local explicitAmount = A._RelativeNumberAmountForText(text)
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
                if sign ~= nil then
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
    local value = DetectBoolean(text)
    if value == nil then return nil end
    if not ContainsAny(text, {
        "again", "wieder", "doch", "actually", "ne",
        "it", "that", "this", "back", "back on", "back off",
        "turn it", "turn that", "same setting", "last setting",
    }) then return nil end
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
    if ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" })
        and not ContainsAny(text, P.NON_AURA_DEBUFF_CONTROL_TERMS) then
        return nil
    end
    local frameType = DetectFrameType(text, ctx)
    local direction = DetectDirection(text, ctx)
    local movementIntent = direction and ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "offset", "position", "x", "y" }) and not ContainsAny(text, { "anchor" })
    local attr = movementIntent and ((direction == "left" or direction == "right") and "offsetX" or "offsetY") or DetectAttribute(text, frameType)
    if not attr then return nil end
    if attr == "enabled" and ContainsAny(text, {
        "in group", "when solo", "while solo", "show player", "hide player", "player in group",
        "show while solo", "while in group", "group when solo",
        "out of combat", "outside combat", "in combat", "while mounted", "when mounted", "mounted",
        "in vehicle", "while in vehicle", "when in vehicle", "resting", "stealthed", "load condition",
        "dispel overlay", "unitframe dispel", "debuff overlay",
    }) then
        return nil
    end
    if (attr == "width" or attr == "height") and ContainsAny(text, {
        "width mode", "height mode", "width source", "height source",
        "power bar height", "mana bar height", "energy bar height",
        "portrait height", "portrait width", "castbar height", "castbar width",
        "icon height", "icon width", "text height", "text width",
    }) then
        return nil
    end
    local useLastUnit = ShouldUseLastUnitContext(text)
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
        if ContainsAny(text, { "all", "all of", "every", "each", "alle", "alles", "jede", "jeder", "jedes" }) then
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
P.BuildFollowup = BuildFollowup
P.BuildBooleanCorrection = BuildBooleanCorrection
P.ParseSetting = ParseSetting
