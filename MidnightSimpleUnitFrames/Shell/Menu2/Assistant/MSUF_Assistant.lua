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
        local label = choice and (choice.label or choice.valueLabel) or nil
        if not label or label == "" then
            label = tostring(setting and setting.label or "Option")
        end
        label = tostring(label):gsub("%s*%[%s*%]", "")
        lines[#lines + 1] = tostring(i) .. ". " .. tostring(label)
    end
    lines[#lines + 1] = "0. None - do nothing."
    lines[#lines + 1] = (#choices == 1) and "Type 1 to apply it, or 0/None to cancel." or "Please choose one, or 0/None to cancel."
    return table.concat(lines, "\n")
end
A._ChoiceTextForTest = ChoiceText

local function SerializeChoices(choices)
    local out = {}
    for i = 1, #(choices or {}) do
        local choice = choices[i]
        local setting = choice and choice.setting
        out[#out + 1] = {
            key = setting and setting.key,
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
    return "This will apply: " .. label .. ". Type 'yes' to apply or 'cancel'."
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
            local label = NormalizeReply(choice and (choice.label or choice.valueLabel) or "")
            local valueLabel = NormalizeReply(choice and choice.valueLabel or "")
            local settingLabel = NormalizeReply(setting and setting.label or "")
            if label ~= "" and (label == normalized or label:find(normalized, 1, true)) then return choice end
            if valueLabel ~= "" and (valueLabel == normalized or valueLabel:find(normalized, 1, true)) then return choice end
            if settingLabel ~= "" and settingLabel == normalized then return choice end
        end
    end
    return nil
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
    if action.captureSnapshot and A.CaptureSnapshot then before = A.CaptureSnapshot() end
    if action.captureProfileSnapshot and A.CaptureProfileSnapshot then beforeProfile = A.CaptureProfileSnapshot() end
    local ok, message = action.run(plan.args or {})
    if not ok then
        return { text = message or "Action failed.", status = "failed", summary = plan.summary }
    end
    if before or beforeProfile then
        local after = A.CaptureSnapshot and A.CaptureSnapshot()
        local afterProfile = action.captureProfileSnapshot and A.CaptureProfileSnapshot and A.CaptureProfileSnapshot() or nil
        A.PushUndo({
            label = plan.label or action.label or "Assistant action",
            action = action.key,
            beforeSnapshot = before,
            afterSnapshot = after,
            beforeProfileSnapshot = beforeProfile,
            afterProfileSnapshot = afterProfile,
        })
    end
    A.RememberAppliedBundle({
        action = action.key,
        serializable = {},
    })
    return { text = ActionResponse(action, plan, message), status = "applied", summary = plan.summary }
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
        if IsCancel(text) then
            A.pendingConfirmation = nil
            local ctx = A.GetContext and A.GetContext()
            if ctx then ctx.pendingConfirmation = nil end
            return { text = "Cancelled.", status = "failed" }
        end
        if IsYes(text) then
            local plan = A.pendingConfirmation
            A.pendingConfirmation = nil
            local ctx = A.GetContext and A.GetContext()
            if ctx then ctx.pendingConfirmation = nil end
            return A.ExecutePlan(plan, { confirmed = true })
        end
        return { text = "Type 'yes' to apply or 'cancel'.", status = "confirmation_needed" }
    end
    local choices = CurrentPendingChoices()
    if choices then
        if IsChoiceAbort(text) then
            ClearPendingChoices()
            return { text = "Cancelled. No MSUF setting changed.", status = "info" }
        end
        local choice = FindChoice(text, choices)
        if choice then
            ClearPendingChoices()
            return A.ExecutePlan({ kind = "changes", changes = { choice }, label = "Assistant selected setting" })
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

local function SubmitNow(text, opts)
    opts = opts or {}
    text = Trim(text)
    if text == "" then return nil end
    if opts.skipUserHistory ~= true then
        A.AddHistory("user", text, "submitted")
    end
    local result = A.HandleInput(text)
    if result and result.text then
        A.AddHistory("assistant", result.text, result.status, result.summary)
        if result.status == "applied" and type(A.RecordSuccessfulAssistantAction) == "function" and type(A.MaybePowerUserSupportHint) == "function" then
            A.RecordSuccessfulAssistantAction()
            local hint = A.MaybePowerUserSupportHint()
            if hint then A.AddHistory("assistant", hint, "info", "Assistant power-user dashboard links hint") end
        end
    end
    if type(A.RefreshUI) == "function" then A.RefreshUI() end
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
