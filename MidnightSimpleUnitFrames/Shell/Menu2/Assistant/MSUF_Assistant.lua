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
    local lines = { "I found multiple matches:" }
    for i = 1, #choices do
        local choice = choices[i]
        local setting = choice and choice.setting
        local label = choice and (choice.label or choice.valueLabel) or nil
        if not label or label == "" then
            label = tostring(setting and setting.label or "Option")
        end
        lines[#lines + 1] = tostring(i) .. ". " .. tostring(label)
    end
    lines[#lines + 1] = "Please choose one."
    return table.concat(lines, "\n")
end

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
    if type(plan.changes) == "table" and #plan.changes >= 6 then return true end
    return false
end

local function ConfirmationText(plan)
    local label = tostring(plan and plan.label or "this action")
    return "This will apply: " .. label .. ". Type 'yes' to apply or 'cancel'."
end

local function NormalizeReply(text)
    return A.Normalize and A.Normalize(text) or Trim(text):lower()
end

local function IsYes(text)
    text = NormalizeReply(text)
    return text == "yes" or text == "y" or text == "ja" or text == "confirm" or text == "apply"
end

local function IsCancel(text)
    text = NormalizeReply(text)
    return text == "cancel" or text == "no" or text == "nein" or text == "abort" or text == "stop"
end

local function FindChoice(text, choices)
    local normalized = NormalizeReply(text)
    local n = tonumber(normalized)
    if n and choices[n] then return choices[n] end
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
        }
    end
    return out
end

local function ExecuteChanges(plan)
    local changes = plan.changes or {}
    local undoChanges = {}
    local changedSettings = {}
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
            end
        end
    end

    if #undoChanges == 0 then
        return { text = "Already set.", status = "applied", summary = plan.summary }
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

    local first = changedSettings[1]
    local text
    if #undoChanges == 1 and first then
        text = "Done. " .. tostring(first.label) .. " " .. tostring(undoChanges[1].valueLabel or SettingValueLabel(first, undoChanges[1].newValue)) .. "."
    else
        text = "Done. Applied " .. tostring(#undoChanges) .. " changes."
    end
    if requiresReload then text = text .. " Reload UI is required for the change to fully take effect." end
    return { text = text, status = "applied", summary = plan.summary }
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
    return { text = message or "Done.", status = "applied", summary = plan.summary }
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
        local choice = FindChoice(text, choices)
        if choice then
            A.pendingChoices = nil
            local ctx = A.GetContext and A.GetContext()
            if ctx then ctx.pendingChoices = nil end
            return A.ExecutePlan({ kind = "changes", changes = { choice }, label = "Assistant selected setting" })
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
    return A.ExecutePlan(parsed)
end

function A.HandleInput(text)
    if type(A.RouteInput) == "function" then
        return A.RouteInput(text, A.HandleCommandInput)
    end
    return A.HandleCommandInput(text)
end

function A.Submit(text)
    text = Trim(text)
    if text == "" then return nil end
    A.AddHistory("user", text, "submitted")
    local result = A.HandleInput(text)
    if result and result.text then
        A.AddHistory("assistant", result.text, result.status, result.summary)
    end
    if type(A.RefreshUI) == "function" then A.RefreshUI() end
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
