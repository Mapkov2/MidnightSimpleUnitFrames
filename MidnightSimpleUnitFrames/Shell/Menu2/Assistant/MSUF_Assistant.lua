local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry

local function Trim(text)
    if A.Trim then return A.Trim(text) end
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function PerfNowMs()
    if type(_G.debugprofilestop) == "function" then return _G.debugprofilestop() end
    local timer = type(_G.GetTimePreciseSec) == "function" and _G.GetTimePreciseSec or _G.GetTime
    if type(timer) == "function" then return (tonumber(timer()) or 0) * 1000 end
    return nil
end

function A.RecordPerfSample(label, startedMs, detail)
    if not startedMs then return nil end
    local now = PerfNowMs()
    if not now then return nil end
    local elapsed = now - startedMs
    if elapsed < 0 then elapsed = 0 end
    local sample = {
        label = tostring(label or "assistant"),
        detail = tostring(detail or ""),
        ms = elapsed,
    }
    A.lastAssistantPerf = sample
    if elapsed >= 250 then A.lastSlowAssistantPerf = sample end
    return sample
end

function A.GetLastPerfSample()
    return A.lastAssistantPerf
end

function A.GetLastSlowPerfSample()
    return A.lastSlowAssistantPerf
end

local function InCombat()
    return _G.InCombatLockdown and _G.InCombatLockdown()
end

local function SettingValueLabel(setting, value)
    if value == nil then return "not set" end
    if setting and setting.type == "boolean" then return value and "enabled" or "disabled" end
    if setting and setting.type == "color" and type(value) == "table" then
        if type(value.label) == "string" and value.label ~= "" then return value.label end
        local r = math.floor(((tonumber(value.r or value[1]) or 0) * 255) + 0.5)
        local g = math.floor(((tonumber(value.g or value[2]) or 0) * 255) + 0.5)
        local b = math.floor(((tonumber(value.b or value[3]) or 0) * 255) + 0.5)
        if r < 0 then r = 0 elseif r > 255 then r = 255 end
        if g < 0 then g = 0 elseif g > 255 then g = 255 end
        if b < 0 then b = 0 elseif b > 255 then b = 255 end
        return string.format("#%02X%02X%02X", r, g, b)
    end
    return tostring(value)
end

local function ValuesEqual(setting, oldValue, newValue)
    if setting and type(setting.sameValue) == "function" then
        return setting.sameValue(oldValue, newValue) == true
    end
    return oldValue == newValue
end

local function ChoiceText(choices)
    local lines = { (#choices == 1) and "I found a likely match:" or "I found multiple matches:" }
    for i = 1, #choices do
        local choice = choices[i]
        local setting = choice and choice.setting
        local action = choice and choice.action
        local label = choice and (choice.label or choice.valueLabel) or nil
        if not label or label == "" then
            label = tostring((setting and setting.label) or (action and action.label) or "Option")
        end
        label = tostring(label):gsub("%s*%[%s*%]", "")
        lines[#lines + 1] = tostring(i) .. ". " .. tostring(label)
    end
    lines[#lines + 1] = "0. None - do nothing."
    if #choices == 1 then
        local only = choices[1]
        if only and only.diagnosticFix == true then
            lines[#lines + 1] = "Type 1, yes, or 'fix it' to apply the repair; 0/None cancels."
        elseif only and (only.action or only.actionKey) then
            lines[#lines + 1] = "Type 1, yes, or a natural reply like 'open it' to apply; 0/None cancels."
        else
            lines[#lines + 1] = "Type 1, yes, or 'apply it' to apply the setting; 0/None cancels."
        end
    else
        lines[#lines + 1] = "Please choose one by number or label, or 0/None to cancel."
    end
    return table.concat(lines, "\n")
end
A._ChoiceTextForTest = ChoiceText

local function SerializeChoices(choices)
    local out = {}
    for i = 1, #(choices or {}) do
        local choice = choices[i]
        local setting = choice and choice.setting
        local action = choice and choice.action
        out[#out + 1] = {
            key = setting and setting.key,
            actionKey = (action and action.key) or choice and choice.actionKey,
            args = choice and choice.args,
            confirmRequired = choice and choice.confirmRequired,
            diagnosticFix = choice and choice.diagnosticFix,
            value = choice and choice.value,
            relativeDelta = choice and choice.relativeDelta,
            direction = choice and choice.direction,
            label = choice and choice.label,
            valueLabel = choice and choice.valueLabel,
            mediaType = choice and choice.mediaType,
            textArea = choice and choice.textArea,
            textSlot = choice and choice.textSlot,
        }
    end
    return out
end

local function RehydrateChoices(serialized)
    local choices = {}
    if not (Registry and type(serialized) == "table") then return choices end
    for i = 1, #serialized do
        local item = serialized[i]
        local setting = item and Registry:GetSetting(item.key)
        if setting then
            choices[#choices + 1] = {
                setting = setting,
                value = item.value,
                relativeDelta = item.relativeDelta,
                direction = item.direction,
                label = item.label,
                valueLabel = item.valueLabel,
                mediaType = item.mediaType,
                textArea = item.textArea,
                textSlot = item.textSlot,
            }
        elseif item and item.actionKey and type(Registry.GetAction) == "function" then
            local action = Registry:GetAction(item.actionKey)
            if action then
                choices[#choices + 1] = {
                    action = action,
                    actionKey = item.actionKey,
                    args = item.args,
                    confirmRequired = item.confirmRequired,
                    diagnosticFix = item.diagnosticFix,
                    label = item.label,
                    valueLabel = item.valueLabel,
                }
            end
        end
    end
    return choices
end

local function CurrentPendingChoices()
    if type(A.pendingChoices) == "table" and #A.pendingChoices > 0 then return A.pendingChoices end
    local ctx = A.GetContext and A.GetContext()
    if ctx and type(ctx.pendingChoices) == "table" then
        local choices = RehydrateChoices(ctx.pendingChoices)
        if #choices > 0 then
            A.pendingChoices = choices
            return choices
        end
        ctx.pendingChoices = nil
    end
    return nil
end

local function AnyCombatUnsafe(plan)
    if type(plan) ~= "table" then return false end
    if plan.kind == "action" then
        return not (plan.action and plan.action.combatSafe == true)
    end
    if type(plan.changes) == "table" then
        for i = 1, #plan.changes do
            local setting = plan.changes[i].setting
            if not (setting and setting.combatSafe == true) then return true end
        end
    end
    return false
end

local function AnySettingFlag(plan, flag)
    if type(plan) ~= "table" or type(plan.changes) ~= "table" then return false end
    for i = 1, #plan.changes do
        local setting = plan.changes[i].setting
        if setting and setting[flag] == true then return true end
    end
    return false
end

local function PlanNeedsConfirmation(plan)
    if type(plan) ~= "table" then return false end
    if plan.confirmRequired == true then return true end
    if plan.kind == "action" and plan.action and plan.action.confirmRequired == true then return true end
    if AnySettingFlag(plan, "confirmRequired") then return true end
    if type(plan.changes) == "table" and #plan.changes >= 6 and plan.bulkSafe ~= true then return true end
    return false
end

local function ConfirmationText(plan)
    local label = tostring(plan and plan.label or "this action")
    return "This will apply: " .. label .. ". Type 'yes', 'do it', or 'mach das' to apply, or 'cancel'."
end

local function NormalizeReply(text)
    return A.Normalize and A.Normalize(text) or Trim(text):lower()
end

local function ReplyHasPhrase(text, phrase)
    text = " " .. NormalizeReply(text) .. " "
    phrase = NormalizeReply(phrase)
    if phrase == "" then return false end
    return text:find(" " .. phrase .. " ", 1, true) ~= nil
end

local function IsYes(text)
    text = NormalizeReply(text)
    return text == "yes" or text == "y" or text == "ja" or text == "confirm" or text == "apply"
end

local function IsCancel(text)
    text = NormalizeReply(text)
    return text == "cancel" or text == "no" or text == "nein" or text == "abort" or text == "stop"
end

local function IsChoiceAbort(text)
    if IsCancel(text) then return true end
    local normalized = NormalizeReply(text)
    local withoutPrefix = normalized:gsub("^option%s+", ""):gsub("^choice%s+", ""):gsub("^select%s+", ""):gsub("^pick%s+", "")
    if normalized == "0" or withoutPrefix == "0" then return true end
    if normalized == "none" or withoutPrefix == "none" then return true end
    if normalized == "nothing" or withoutPrefix == "nothing" then return true end
    if normalized == "do nothing" or withoutPrefix == "do nothing" then return true end
    local phrases = {
        "nope", "never mind", "nevermind", "forget it", "leave it", "skip it",
        "cancel that", "abort that", "stop that", "stop it", "not now",
        "i dont want", "i do not want", "dont want", "do not want",
        "i dont want to change", "i do not want to change", "dont change", "do not change",
        "not that", "not this", "wrong choice", "wrong list", "none of these", "none of them",
        "abbrechen", "abbruch", "nein danke", "nicht aendern", "nichts aendern",
        "ich will nicht", "will ich nicht", "doch nicht", "vergiss es", "lass es",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) then return true end
    end
    return false
end

local function IsSingleChoiceApply(text)
    local normalized = NormalizeReply(text)
    if normalized == "1" then return true end
    local phrases = {
        "yes", "y", "yeah", "yep", "yup", "ok", "okay", "sure", "sounds good",
        "yes please", "go ahead", "please do",
        "apply", "apply it", "apply that", "do it", "do that", "fix it", "fix that",
        "use it", "use that", "take it", "take that", "yes do it", "yes apply it",
        "ok do it", "okay do it", "sure do it", "open it", "open that", "show it", "show me",
        "ja", "ja bitte", "mach das", "mach es", "anwenden", "uebernehmen", "ja mach das", "ja anwenden",
        "oeffne es", "oeffne das", "zeig es", "zeig mir das",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) or normalized == NormalizeReply(phrases[i]) then return true end
    end
    return false
end

local function IsNaturalFixApply(text)
    local normalized = NormalizeReply(text)
    local phrases = {
        "fix it", "fix that", "repair it", "repair that", "apply fix", "apply the fix",
        "do the fix", "use the fix", "do it", "do that", "mach das", "mach es",
        "reparieren", "beheben", "fix anwenden",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) or normalized == NormalizeReply(phrases[i]) then return true end
    end
    return false
end

local function IsConfirmationApply(text)
    if IsYes(text) then return true end
    local normalized = NormalizeReply(text)
    local phrases = {
        "yes do it", "yes apply it", "yes please", "yep", "yup", "sure",
        "go ahead", "please do", "do it", "do that", "apply it", "apply that",
        "run it", "confirm it", "ok do it", "okay do it", "ok apply it", "okay apply it",
        "ja bitte", "ja mach das", "mach das", "mach es", "mach weiter", "leg los",
        "anwenden", "uebernehmen", "bestaetigen",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) or normalized == NormalizeReply(phrases[i]) then return true end
    end
    return false
end

local function LooksLikeFreshCommand(text)
    local phrases = {
        "change", "set", "turn", "enable", "disable", "show", "hide", "open", "search",
        "help", "diagnose", "move", "copy", "reset", "import", "export", "rename",
        "create", "delete", "profile", "edit mode", "how", "what", "where", "why",
        "make", "increase", "decrease", "switch",
        "aendere", "setze", "schalte", "zeige", "verstecke", "oeffne", "suche",
        "hilfe", "diagnose", "verschiebe", "kopiere", "zuruecksetzen", "profil",
        "wie", "was", "wo", "warum",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) then return true end
    end
    return false
end

local function ClearPendingChoices()
    A.pendingChoices = nil
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingChoices = nil end
end

function A.SetPendingChoices(choices)
    if type(choices) ~= "table" or #choices == 0 then
        ClearPendingChoices()
        return nil
    end
    A.pendingChoices = choices
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingChoices = SerializeChoices(A.pendingChoices) end
    return ChoiceText(A.pendingChoices)
end

local function FindChoice(text, choices)
    local normalized = NormalizeReply(text)
    local n = tonumber(normalized)
    if n and choices[n] then return choices[n] end

    local withPrefix = normalized:gsub("^option%s+", ""):gsub("^choice%s+", ""):gsub("^select%s+", ""):gsub("^pick%s+", "")
    n = tonumber(withPrefix)
    if n and choices[n] then return choices[n] end

    n = tonumber(normalized:match("^(%d+)[a-z]+$"))
    if n and choices[n] then return choices[n] end

    local wordToNumber = {
        ["first"] = 1, ["second"] = 2, ["third"] = 3, ["fourth"] = 4, ["fifth"] = 5,
        ["sixth"] = 6, ["seventh"] = 7, ["eighth"] = 8, ["ninth"] = 9, ["tenth"] = 10,
    }
    local choiceIndex = wordToNumber[normalized] or wordToNumber[withPrefix]
    if choiceIndex and choices[choiceIndex] then return choices[choiceIndex] end

    local units = A.Parse and A.Parse("show " .. normalized .. " name")
    local wantedUnit
    if units and type(units.changes) == "table" and units.changes[1] and units.changes[1].setting then
        wantedUnit = units.changes[1].setting.unit
    end
    if not wantedUnit then
        local aliases = A.UnitAliases or {}
        for unit, list in pairs(aliases) do
            for i = 1, #list do
                if normalized == A.Normalize(list[i]) then wantedUnit = unit; break end
            end
            if wantedUnit then break end
        end
    end
    if wantedUnit then
        for i = 1, #choices do
            local setting = choices[i].setting
            if setting and setting.unit == wantedUnit then return choices[i] end
        end
    end
    if #normalized >= 2 then
        for i = 1, #choices do
            local choice = choices[i]
            local setting = choice and choice.setting
            local action = choice and choice.action
            local label = NormalizeReply(choice and (choice.label or choice.valueLabel) or "")
            local valueLabel = NormalizeReply(choice and choice.valueLabel or "")
            local settingLabel = NormalizeReply(setting and setting.label or "")
            local actionLabel = NormalizeReply(action and action.label or "")
            if label ~= "" and (label == normalized or label:find(normalized, 1, true)) then return choice end
            if valueLabel ~= "" and (valueLabel == normalized or valueLabel:find(normalized, 1, true)) then return choice end
            if settingLabel ~= "" and settingLabel == normalized then return choice end
            if actionLabel ~= "" and actionLabel == normalized then return choice end
        end
    end
    return nil
end

local function SingleNaturalFixChoice(text, choices)
    if not IsNaturalFixApply(text) then return nil end
    local fixes = {}
    for i = 1, #(choices or {}) do
        local choice = choices[i]
        if choice and (choice.diagnosticFix == true or (choice.setting and choice.diagnosticFix ~= false)) then
            fixes[#fixes + 1] = choice
        end
    end
    return #fixes == 1 and fixes[1] or nil
end

local function ExecuteChoice(choice)
    if choice and choice.setting then
        return A.ExecutePlan({ kind = "changes", changes = { choice }, label = "Assistant selected setting" })
    end
    if choice and (choice.action or choice.actionKey) then
        local action = choice.action
        if not action and Registry and type(Registry.GetAction) == "function" then action = Registry:GetAction(choice.actionKey) end
        if not action then return { text = "That Assistant action is not available anymore.", status = "failed" } end
        return A.ExecutePlan({
            kind = "action",
            action = action,
            args = choice.args or {},
            confirmRequired = choice.confirmRequired,
            label = choice.label or action.label or "Assistant selected action",
            summary = choice.summary or "Assistant selected action.",
        })
    end
    return { text = "That option is not available anymore.", status = "failed" }
end

local function RunApplies(changedSettings)
    local applied = {}
    for i = 1, #changedSettings do
        local setting = changedSettings[i]
        if setting and type(setting.apply) == "function" and not applied[setting.key] then
            applied[setting.key] = true
            setting.apply()
        end
    end
end

local function NormalizeTextSlot(slot)
    slot = tostring(slot or ""):lower()
    if slot == "left" then return "left" end
    if slot == "center" or slot == "centre" or slot == "middle" then return "center" end
    if slot == "right" then return "right" end
    return nil
end

local function TextContextFromSetting(setting, item)
    local area = item and item.textArea
    local slot = NormalizeTextSlot(item and item.textSlot)
    local attr = tostring(setting and setting.attribute or "")
    local key = tostring(setting and setting.key or "")
    local hay = attr .. " " .. key
    if not area then
        if hay:find("hpText", 1, true) or hay:find(".text", 1, true) or hay:find("healthText", 1, true) then
            area = "hp"
        elseif hay:find("powerText", 1, true) then
            area = "power"
        end
    end
    if not slot then
        if hay:find("Left", 1, true) or hay:find("textLeft", 1, true) then
            slot = "left"
        elseif hay:find("Center", 1, true) or hay:find("textCenter", 1, true) then
            slot = "center"
        elseif hay:find("Right", 1, true) or hay:find("textRight", 1, true) then
            slot = "right"
        end
    end
    if area ~= "hp" and area ~= "power" then return nil end
    if not slot then return nil end
    return area, slot
end

local function RememberTextChangeContext(setting, item, value)
    local area, slot = TextContextFromSetting(setting, item)
    if not area then return end
    local ctx = A.GetContext and A.GetContext()
    if not ctx then return end
    ctx.lastTextArea = area
    ctx.lastTextSlot = slot
    ctx.lastTextSetting = setting and setting.key
    ctx.lastTextValue = value
    ctx.lastTextFrameType = setting and setting.frameType
    ctx.lastTextUnit = setting and setting.unit
    ctx.selectedTextEditorTarget = {
        frameType = setting and setting.frameType,
        unit = setting and setting.unit,
        tab = area,
        slot = slot,
    }
end

local function BuildSerializable(changes)
    local out = {}
    for i = 1, #changes do
        local setting = changes[i].setting
        out[#out + 1] = {
            key = setting and setting.key,
            unit = setting and setting.unit,
            frameType = setting and setting.frameType,
            attribute = setting and setting.attribute,
            value = changes[i].newValue,
            relativeDelta = changes[i].relativeDelta,
            direction = changes[i].direction,
            textArea = changes[i].textArea,
            textSlot = changes[i].textSlot,
        }
    end
    return out
end

local function SettingLabel(setting)
    return tostring(setting and setting.label or "MSUF setting")
end

local function DescribeChange(setting, undo)
    local oldLabel = SettingValueLabel(setting, undo and undo.oldValue)
    local newLabel = tostring((undo and undo.valueLabel) or SettingValueLabel(setting, undo and undo.newValue))
    return SettingLabel(setting) .. " from " .. tostring(oldLabel) .. " to " .. tostring(newLabel)
end

local UNDO_FOLLOWUP_HINT = "Next: type 'undo' to revert, or describe another follow-up change."

local function AppendUndoFollowupHint(text)
    text = tostring(text or "")
    if text:find(UNDO_FOLLOWUP_HINT, 1, true) then return text end
    return text .. "\n" .. UNDO_FOLLOWUP_HINT
end

local function ChangedResponse(changedSettings, undoChanges)
    local count = #undoChanges
    if count == 1 then
        return "Done. I changed " .. DescribeChange(changedSettings[1], undoChanges[1]) .. "."
    end

    local visible = math.min(count, 5)
    local lines = { "Done. I changed " .. tostring(count) .. " MSUF settings:" }
    for i = 1, visible do
        lines[#lines + 1] = tostring(i) .. ". " .. DescribeChange(changedSettings[i], undoChanges[i]) .. "."
    end
    if count > visible then
        lines[#lines + 1] = "And " .. tostring(count - visible) .. " more."
    end
    return table.concat(lines, "\n")
end

local function AlreadySetResponse(changes)
    if type(changes) == "table" and #changes == 1 then
        local setting = changes[1].setting
        if setting and type(setting.get) == "function" then
            return "Already set. " .. SettingLabel(setting) .. " is already " .. SettingValueLabel(setting, setting.get()) .. "."
        end
    end
    return "Already set. No MSUF setting changed."
end

local function RefreshedAlreadySetResponse(setting)
    if setting and type(setting.get) == "function" then
        return "Already set. " .. SettingLabel(setting) .. " is already " .. SettingValueLabel(setting, setting.get()) .. ". I refreshed it so the visible UI uses the current value."
    end
    return "Already set. I refreshed the related MSUF control so the visible UI uses the current value."
end

local function ExecuteChanges(plan)
    local changes = plan.changes or {}
    local undoChanges = {}
    local changedSettings = {}
    local unchangedApplySettings = {}
    local lastSetting, lastUnit, lastFrameType, lastCategory, lastValue
    local requiresReload

    for i = 1, #changes do
        local item = changes[i]
        local setting = item.setting
        if setting and type(setting.get) == "function" and type(setting.set) == "function" then
            local oldValue = setting.get()
            local newValue = item.value
            if item.relativeDelta ~= nil then
                newValue = (tonumber(oldValue) or 0) + (tonumber(item.relativeDelta) or 0)
            end
            if setting.type == "number" and A.ClampNumber then
                newValue = A.ClampNumber(newValue, setting.min, setting.max, setting.step)
            elseif setting.type == "boolean" then
                newValue = newValue and true or false
            end
            if not ValuesEqual(setting, oldValue, newValue) then
                setting.set(newValue)
                undoChanges[#undoChanges + 1] = {
                    key = setting.key,
                    oldValue = oldValue,
                    newValue = newValue,
                    valueLabel = item.valueLabel,
                }
                item.newValue = newValue
                changedSettings[#changedSettings + 1] = setting
                lastSetting = setting.key
                lastUnit = setting.unit
                lastFrameType = setting.frameType
                lastCategory = setting.category
                lastValue = newValue
                if setting.requiresReload == true then requiresReload = true end
                if item.direction then A.SetContextValue("lastDirection", item.direction) end
                RememberTextChangeContext(setting, item, newValue)
            elseif setting.applyWhenUnchanged == true then
                unchangedApplySettings[#unchangedApplySettings + 1] = setting
            end
        end
    end

    if #undoChanges == 0 then
        if #unchangedApplySettings > 0 then
            RunApplies(unchangedApplySettings)
            local first = unchangedApplySettings[1]
            return { text = RefreshedAlreadySetResponse(first), status = "applied", summary = plan.summary }
        end
        return { text = AlreadySetResponse(changes), status = "applied", summary = plan.summary }
    end

    RunApplies(changedSettings)

    local bundle = {
        label = plan.label or "Assistant change",
        action = "change",
        changes = undoChanges,
        lastSetting = lastSetting,
        lastUnit = lastUnit,
        lastFrameType = lastFrameType,
        lastCategory = lastCategory,
        lastValue = lastValue,
        serializable = BuildSerializable(changes),
    }
    A.PushUndo(bundle)
    A.RememberAppliedBundle(bundle)

    local text = ChangedResponse(changedSettings, undoChanges)
    if requiresReload then text = text .. " Reload UI is required for the change to fully take effect." end
    text = AppendUndoFollowupHint(text)
    return { text = text, status = "applied", summary = plan.summary }
end

local function ActionResponse(action, plan, message)
    message = Trim(message or "")
    if message == "" or message == "Done." then
        return "Done. I ran " .. tostring(plan and plan.label or action and action.label or "that MSUF action") .. "."
    end
    if message:find("^Done%.") or message:find("^Already set%.") then return message end
    return "Done. " .. message
end

local function ExecuteAction(plan)
    local action = plan.action
    if not (action and type(action.run) == "function") then
        return { text = "That action is not available yet.", status = "failed", summary = plan.summary }
    end
    local before
    local beforeProfile
    local captureProfile = action.captureProfileSnapshot and A.CaptureProfileSnapshot
    local captureSnapshot = action.captureSnapshot and not captureProfile and A.CaptureSnapshot
    local snapshotStart = PerfNowMs()
    if captureSnapshot then before = A.CaptureSnapshot() end
    if captureProfile then beforeProfile = A.CaptureProfileSnapshot() end
    A.RecordPerfSample("assistant.snapshot.before", snapshotStart, action.key)
    local ok, message = action.run(plan.args or {})
    if not ok then
        return { text = message or "Action failed.", status = "failed", summary = plan.summary }
    end
    local undoAvailable = false
    if before or beforeProfile then
        snapshotStart = PerfNowMs()
        local after = captureSnapshot and A.CaptureSnapshot() or nil
        local afterProfile = captureProfile and A.CaptureProfileSnapshot() or nil
        A.RecordPerfSample("assistant.snapshot.after", snapshotStart, action.key)
        undoAvailable = A.PushUndo({
            label = plan.label or action.label or "Assistant action",
            action = action.key,
            beforeSnapshot = before,
            afterSnapshot = after,
            beforeProfileSnapshot = beforeProfile,
            afterProfileSnapshot = afterProfile,
        })
    end
    local text = ActionResponse(action, plan, message)
    A.RememberAppliedBundle({
        action = action.key,
        actionLabel = plan.label or action.label,
        actionMessage = text,
        undoAvailable = undoAvailable,
        serializable = {},
    })
    if undoAvailable then text = AppendUndoFollowupHint(text) end
    return { text = text, status = "applied", summary = plan.summary }
end

function A.ShowLargeTextPanel(spec)
    if type(spec) ~= "table" then return false end
    A.largeTextPanel = spec
    if type(A.RefreshUI) == "function" then A.RefreshUI() end
    return true
end

function A.CloseLargeTextPanel()
    A.largeTextPanel = nil
    if type(A.RefreshUI) == "function" then A.RefreshUI() end
end

function A.ExecutePlan(plan, opts)
    opts = opts or {}
    if type(plan) ~= "table" then return { text = "I could not parse that.", status = "failed" } end
    if PlanNeedsConfirmation(plan) and opts.confirmed ~= true then
        A.pendingConfirmation = plan
        local ctx = A.GetContext and A.GetContext()
        if ctx then ctx.pendingConfirmation = plan.label or "Assistant action" end
        return { text = ConfirmationText(plan), status = "confirmation_needed", summary = plan.summary }
    end
    if InCombat() and AnyCombatUnsafe(plan) and opts.fromQueue ~= true then
        A.QueuePlan(plan)
        return { text = "Queued until combat ends: " .. tostring(plan.label or "Assistant change") .. ".", status = "queued", summary = plan.summary }
    end
    if plan.kind == "changes" then return ExecuteChanges(plan) end
    if plan.kind == "action" then return ExecuteAction(plan) end
    return { text = "I do not know that setting yet.", status = "failed", summary = plan.summary }
end

local function HandlePending(text)
    if type(A.HandlePendingFlow) == "function" then
        local flowResult = A.HandlePendingFlow(text)
        if flowResult then return flowResult end
    end
    if A.pendingConfirmation then
        if IsChoiceAbort(text) then
            A.pendingConfirmation = nil
            local ctx = A.GetContext and A.GetContext()
            if ctx then ctx.pendingConfirmation = nil end
            return { text = "Cancelled.", status = "failed" }
        end
        if IsConfirmationApply(text) then
            local plan = A.pendingConfirmation
            A.pendingConfirmation = nil
            local ctx = A.GetContext and A.GetContext()
            if ctx then ctx.pendingConfirmation = nil end
            return A.ExecutePlan(plan, { confirmed = true })
        end
        return { text = "Type 'yes', 'do it', or 'mach das' to apply, or 'cancel'.", status = "confirmation_needed" }
    end
    local choices = CurrentPendingChoices()
    if choices then
        if IsChoiceAbort(text) then
            ClearPendingChoices()
            return { text = "Cancelled. No MSUF change applied.", status = "info" }
        end
        if #choices == 1 and IsSingleChoiceApply(text) then
            local choice = choices[1]
            ClearPendingChoices()
            return ExecuteChoice(choice)
        end
        local naturalFix = SingleNaturalFixChoice(text, choices)
        if naturalFix then
            ClearPendingChoices()
            return ExecuteChoice(naturalFix)
        end
        local choice = FindChoice(text, choices)
        if choice then
            ClearPendingChoices()
            return ExecuteChoice(choice)
        end
        if LooksLikeFreshCommand(text) then
            ClearPendingChoices()
            return nil
        end
        return { text = "Please choose one of the listed options by number or unit name.", status = "ambiguous" }
    end
    return nil
end

function A.HandleCommandInput(text)
    local pending = HandlePending(text)
    if pending then return pending end

    local parsed = A.Parse and A.Parse(text) or nil
    if not parsed then return { text = "I could not parse that.", status = "failed" } end

    if parsed.kind == "empty" then return nil end
    if parsed.kind == "undo" then
        local ok, message = A.UndoLast()
        return { text = message, status = ok and "applied" or "failed" }
    end
    if parsed.kind == "redo" then
        local ok, message = A.RedoLast()
        return { text = message, status = ok and "applied" or "failed" }
    end
    if parsed.kind == "ambiguous" then
        A.pendingChoices = parsed.choices or {}
        local ctx = A.GetContext and A.GetContext()
        if ctx then ctx.pendingChoices = SerializeChoices(A.pendingChoices) end
        return { text = ChoiceText(A.pendingChoices), status = "ambiguous", summary = parsed.summary }
    end
    if parsed.kind == "unknown" then
        return { text = parsed.text or "I do not know that setting yet.", status = parsed.status or "failed", kind = "unknown" }
    end
    if parsed.kind == "answer" then
        return { text = parsed.text or "", status = parsed.status or "info", summary = parsed.summary }
    end
    return A.ExecutePlan(parsed)
end

function A.HandleInput(text)
    if type(A.RouteInput) == "function" then
        return A.RouteInput(text, A.HandleCommandInput)
    end
    return A.HandleCommandInput(text)
end

function A.IsBusy()
    return A._busy == true
end

function A.GetBusyText()
    return tostring(A._busyText or "I am working on that")
end

function A.SetBusy(active, text)
    A._busy = active and true or false
    A._busyText = A._busy and Trim(text or "I am working on that") or nil
    A._busySerial = (tonumber(A._busySerial) or 0) + 1
    if type(A.RefreshUI) == "function" then A.RefreshUI() end
    return A._busy
end

local BATCH_COMMAND_STARTERS = {
    "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift", "reset", "copy",
    "add", "put", "clear", "increase", "decrease", "raise", "lower", "detach", "attach", "embed",
    "remove", "open", "close", "toggle", "diagnose", "start", "stop", "pause", "play", "animate", "preview",
    "select", "use", "apply", "verschiebe", "verschieben", "setze", "stelle", "kopiere", "kopieren", "uebernehmen",
    "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken", "einblenden", "ausblenden",
    "oeffne", "waehle", "nutze",
}

local function NormalizeForBatch(text)
    if A.Normalize then return A.Normalize(text) end
    text = tostring(text or ""):lower():gsub("[,;:!?%(%)]", " "):gsub("%s+", " ")
    return Trim(text)
end

local function StripBatchLead(text)
    text = Trim(text)
    local changed = true
    while changed do
        changed = false
        for _, lead in ipairs({ "also", "then", "please", "pls", "and then", "auch", "dann", "bitte", "und dann" }) do
            local prefix = lead .. " "
            if NormalizeForBatch(text):sub(1, #prefix) == prefix then
                text = Trim(text:sub(#prefix + 1))
                changed = true
                break
            end
        end
    end
    return text
end

local function StartsBatchCommand(text)
    local norm = NormalizeForBatch(StripBatchLead(text))
    if norm == "" then return false end
    for i = 1, #BATCH_COMMAND_STARTERS do
        local starter = BATCH_COMMAND_STARTERS[i]
        if norm == starter or norm:sub(1, #starter + 1) == starter .. " " then return true end
    end
    return false
end

local function BatchBooleanLead(text)
    local norm = NormalizeForBatch(text)
    for _, lead in ipairs({ "turn on", "turn off", "enable", "disable", "show", "hide", "start", "stop", "preview" }) do
        if norm == lead or norm:sub(1, #lead + 1) == lead .. " " then return lead end
    end
    return nil
end

local function InheritableActionTail(text)
    text = NormalizeForBatch(text)
    if text == "" or StartsBatchCommand(text) then return false end
    if text:find("test", 1, true) and (
        text:find("border", 1, true)
        or text:find("bar", 1, true)
        or text:find("bars", 1, true)
    ) then
        return true
    end
    if text:find("preview", 1, true) and (
        text:find("resource", 1, true)
        or text:find("class", 1, true)
        or text:find("animation", 1, true)
    ) then
        return true
    end
    return false
end

local function BatchHasPhrase(text, phrase)
    local norm = NormalizeForBatch(text)
    phrase = NormalizeForBatch(phrase)
    if norm == "" or phrase == "" then return false end
    return (" " .. norm .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

local function BatchContainsAny(text, phrases)
    for i = 1, #(phrases or {}) do
        if BatchHasPhrase(text, phrases[i]) then return true end
    end
    return false
end

local function HasExplicitBatchScope(text)
    local parser = A.Parser or {}
    if type(parser.DetectUnits) == "function" and #(parser.DetectUnits(text) or {}) > 0 then return true end
    if type(parser.DetectGroups) == "function" and #(parser.DetectGroups(text) or {}) > 0 then return true end
    return BatchContainsAny(text, {
        "target of target", "focus target", "mythic raid", "player", "target", "focus", "pet", "boss",
        "party", "raid", "party frames", "raid frames", "group frames",
    })
end

local function HasScopedSettingDetail(text)
    text = NormalizeForBatch(text)
    if text == "" then return false end
    if not HasExplicitBatchScope(text) then return false end
    return BatchContainsAny(text, {
        "frame", "frames", "name", "names", "portrait", "portraits", "power bar", "powerbar", "mana bar",
        "health bar", "hp bar", "castbar", "cast bar", "text", "raid marker", "leader icon", "assist icon",
        "ready check", "status icon", "rested icon", "combat indicator", "dead indicator", "ghost indicator",
        "afk indicator", "dnd indicator", "load condition", "alpha", "opacity", "width", "height",
    })
end

local function InheritableSettingTail(text)
    text = NormalizeForBatch(text)
    if text == "" or StartsBatchCommand(text) then return false end
    return HasScopedSettingDetail(text)
end

local function InheritedBatchCommand(before, after)
    local actionTail = InheritableActionTail(after)
    local settingTail = InheritableSettingTail(after)
    if not actionTail and not settingTail then return nil end
    local lead = BatchBooleanLead(before)
    if not lead then return nil end
    if settingTail and not HasScopedSettingDetail(before) then return nil end
    return Trim(lead .. " " .. after)
end

local function SplitBatchCommands(text)
    if A.pendingConfirmation or CurrentPendingChoices() then return nil end
    local parts = { Trim(text) }
    local connectors = { " and ", " then ", " und ", " dann " }
    local changed = true
    while changed do
        changed = false
        for p = 1, #parts do
            local raw = parts[p]
            local lower = raw:lower()
            for c = 1, #connectors do
                local startAt = 1
                while true do
                    local s, e = lower:find(connectors[c], startAt, true)
                    if not s then break end
                    local before = Trim(raw:sub(1, s - 1))
                    local after = StripBatchLead(raw:sub(e + 1))
                    if before ~= "" and after ~= "" and StartsBatchCommand(after) then
                        parts[p] = before
                        table.insert(parts, p + 1, after)
                        changed = true
                        break
                    end
                    local inherited = before ~= "" and after ~= "" and InheritedBatchCommand(before, after) or nil
                    if inherited then
                        parts[p] = before
                        table.insert(parts, p + 1, inherited)
                        changed = true
                        break
                    end
                    startAt = e + 1
                end
                if changed then break end
            end
            if changed then break end
        end
    end
    return #parts > 1 and parts or nil
end

local function BatchLine(text)
    text = tostring(text or ""):gsub("\r", "")
    text = text:gsub("\nNext:.-$", "")
    local first = text:match("([^\n]+)") or text
    return Trim(first)
end

local function TrySubmitBatch(text)
    local parts = SplitBatchCommands(text)
    if not parts then return nil end
    local lines = {}
    local applied = 0
    for i = 1, #parts do
        local result = A.HandleInput(parts[i])
        if not result then
            return { text = "I could not process command " .. tostring(i) .. ": " .. tostring(parts[i]), status = "failed" }
        end
        if result.status ~= "applied" and result.status ~= "info" then
            return result
        end
        if result.status == "applied" then applied = applied + 1 end
        lines[#lines + 1] = tostring(i) .. ". " .. BatchLine(result.text)
    end
    local textOut = "Done. I handled " .. tostring(#parts) .. " commands:\n" .. table.concat(lines, "\n")
    if applied > 0 then textOut = AppendUndoFollowupHint(textOut) end
    return { text = textOut, status = applied > 0 and "applied" or "info", summary = "Executed multiple Assistant commands." }
end

local function SubmitNow(text, opts)
    opts = opts or {}
    text = Trim(text)
    if text == "" then return nil end
    local startedMs = PerfNowMs()
    if opts.skipUserHistory ~= true then
        A.AddHistory("user", text, "submitted")
    end
    local result = TrySubmitBatch(text) or A.HandleInput(text)
    if result and result.text then
        A.AddHistory("assistant", result.text, result.status, result.summary)
        if result.status == "applied" and type(A.RecordSuccessfulAssistantAction) == "function" and type(A.MaybePowerUserSupportHint) == "function" then
            A.RecordSuccessfulAssistantAction()
            local hint = A.MaybePowerUserSupportHint()
            if hint then A.AddHistory("assistant", hint, "info", "Assistant power-user dashboard links hint") end
        end
    end
    if type(A.RefreshUI) == "function" then A.RefreshUI() end
    A.RecordPerfSample("assistant.submit", startedMs, text)
    return result
end

function A.Submit(text)
    return SubmitNow(text)
end

function A.SubmitDeferred(text, callback)
    text = Trim(text)
    if text == "" then return nil end
    if A.IsBusy() then
        return { text = "I am still working on the previous request.", status = "busy" }
    end

    A.AddHistory("user", text, "submitted")
    A.SetBusy(true, "I am working on that")

    local result
    local function Finish()
        local ok, err = pcall(function()
            result = SubmitNow(text, { skipUserHistory = true })
        end)
        if not ok then
            result = {
                text = "Something went wrong while MSUF processed that request: " .. tostring(err),
                status = "failed",
            }
            A.AddHistory("assistant", result.text, result.status)
        end
        A.SetBusy(false)
        if type(callback) == "function" then pcall(callback, result) end
    end

    local scheduler = (MSUF and MSUF.Scheduler) or _G.MSUF_Scheduler
    if scheduler and type(scheduler.RunNextFrame) == "function" then
        scheduler.RunNextFrame(Finish)
        return { text = A.GetBusyText(), status = "queued" }
    end
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, Finish)
        return { text = A.GetBusyText(), status = "queued" }
    end

    Finish()
    return result
end

function A.RegisteredSettingSummary()
    local settings = Registry and Registry:AllSettings() or {}
    local out = {}
    for i = 1, #settings do out[#out + 1] = settings[i].key end
    return out
end

function A.TodoSummary()
    return Registry and Registry:GetTodos() or {}
end
