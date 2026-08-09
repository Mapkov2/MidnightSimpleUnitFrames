--- Public registration bridge for frames owned by other addons.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local EM2 = _G.MSUF_EM2
if not (EM2 and EM2.Registry) then return end
local Util = EM2.Util or {}

local API, External = { VERSION = 1 }, {}
local records, owners, listeners = {}, {}, {}
local sessionActive, sessionSnapshot = false, nil
EM2.ExternalElements = External

local function Export(name, value)
    if type(MSUF.ExportPublic) == "function" then return MSUF.ExportPublic(name, value) end
    _G[name] = value
    return value
end

local function ValidName(value)
    return type(value) == "string" and value ~= "" and #value <= 80
        and value:match("^[%w_.%-]+$") ~= nil
end

local function Key(owner, id)
    return "external:" .. owner:lower() .. ":" .. id:lower()
end

local function Finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function Round(value)
    value = tonumber(value)
    if not value then return nil end
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

local function Copy(value, seen, depth)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string" then return value end
    if kind == "number" then
        if Finite(value) then return value end
        return nil, "invalid_number"
    end
    if kind ~= "table" then return nil, "unsupported_" .. kind end
    if depth >= 12 or seen[value] then return nil, "invalid_table" end
    seen[value] = true
    local result, count = {}, 0
    for key, child in pairs(value) do
        count = count + 1
        if count > 512 then seen[value] = nil; return nil, "too_many_items" end
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" and keyType ~= "boolean" then
            seen[value] = nil
            return nil, "invalid_key"
        end
        local copied, reason = Copy(child, seen, depth + 1)
        if reason then seen[value] = nil; return nil, reason end
        result[key] = copied
    end
    seen[value] = nil
    return result
end

local function SafeCopy(value)
    return Copy(value, {}, 0)
end

local function Report(record, name, err)
    local message = ("MSUF Edit Mode API (%s/%s): %s failed: %s"):format(
        record and record.owner or "?", record and record.id or "?", name, tostring(err))
    local handler = type(_G.geterrorhandler) == "function" and _G.geterrorhandler()
    if type(handler) == "function" then handler(message)
    elseif type(_G.print) == "function" then _G.print(message) end
end

local function Invoke(record, name, ...)
    local callback = record and record[name]
    if type(callback) ~= "function" then return false, "callback_missing" end
    local ok, result, detail = pcall(callback, ...)
    if not ok then Report(record, name, result); return false, "callback_error" end
    if result == false then return false, detail or "callback_rejected" end
    return true, result, detail
end

local function Capture(record)
    local name = type(record and record.captureState) == "function" and "captureState" or "getPosition"
    local ok, state = Invoke(record, name)
    if not ok or state == nil then return nil end
    local copy, reason = SafeCopy(state)
    if reason then Report(record, name, reason); return nil end
    return copy
end

local function Restore(record, state, reason)
    local copy = SafeCopy(state)
    if copy == nil then return false end
    local name = type(record and record.restoreState) == "function" and "restoreState" or "setPosition"
    return Invoke(record, name, copy, reason)
end

local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

local function IsActive()
    local state = EM2.State
    return sessionActive and state and state.IsActive and state.IsActive()
        and (not state.GetProvider or state.GetProvider() == "msuf")
end

local function Refresh(kind)
    if EM2.Ticker and EM2.Ticker.RequestIdleSync then
        EM2.Ticker.RequestIdleSync(kind)
    else
        if kind ~= "hud" and EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        if kind ~= "mover" and EM2.HUD and EM2.HUD.RefreshControls then EM2.HUD.RefreshControls() end
    end
end

local function SyncHistory()
    local menu = MSUF.MSUF2 or _G.MSUF2
    if menu and type(menu.SyncExternalHistoryState) == "function" then menu.SyncExternalHistoryState() end
end

local CALLBACKS = {
    "isEnabled", "getPosition", "setPosition", "captureState", "restoreState", "movePosition",
    "resetPosition", "getInspectorValues", "onSelect", "openSettings", "onSessionChanged",
}

--- Optional owner-defined quick controls rendered inside the MSUF external
--- popup. Each spec is { id, label, kind = "number"|"toggle", get, set } with
--- min/max required for numbers. Values flow through get/set only; MSUF never
--- touches the owner's storage.
local function PrepareControls(list)
    if list == nil then return nil end
    if type(list) ~= "table" then return nil, "invalid_extraControls" end
    local prepared = {}
    for i = 1, #list do
        local spec = list[i]
        if type(spec) ~= "table" then return nil, "invalid_extraControls" end
        if not ValidName(spec.id) then return nil, "invalid_control_id" end
        if type(spec.label) ~= "string" or spec.label == "" or #spec.label > 40 then
            return nil, "invalid_control_label"
        end
        if spec.kind ~= "number" and spec.kind ~= "toggle" then return nil, "invalid_control_kind" end
        if type(spec.get) ~= "function" or type(spec.set) ~= "function" then
            return nil, "invalid_control_callbacks"
        end
        local minValue, maxValue
        if spec.kind == "number" then
            minValue, maxValue = tonumber(spec.min), tonumber(spec.max)
            if not (Finite(minValue) and Finite(maxValue)) or minValue >= maxValue then
                return nil, "invalid_control_range"
            end
        end
        if #prepared >= 12 then return nil, "too_many_controls" end
        local stepValue = tonumber(spec.step)
        prepared[#prepared + 1] = {
            id = spec.id, label = spec.label, kind = spec.kind,
            get = spec.get, set = spec.set, min = minValue, max = maxValue,
            step = (spec.kind == "number" and Finite(stepValue) and stepValue > 0) and stepValue or nil,
            transient = spec.transient == true,
        }
    end
    if #prepared == 0 then return nil end
    return prepared
end

local function Prepare(owner, element)
    if type(element) ~= "table" then return nil, "element_not_table" end
    if not ValidName(element.id) then return nil, "invalid_element_id" end
    if type(element.label) ~= "string" or element.label == "" or #element.label > 120 then
        return nil, "invalid_label"
    end
    if element.settingsLabel ~= nil and (type(element.settingsLabel) ~= "string"
        or element.settingsLabel == "" or #element.settingsLabel > 120) then
        return nil, "invalid_settings_label"
    end
    if type(element.getFrame) ~= "function" then return nil, "getFrame_required" end
    for i = 1, #CALLBACKS do
        local name = CALLBACKS[i]
        if element[name] ~= nil and type(element[name]) ~= "function" then return nil, "invalid_" .. name end
    end
    local statePair = type(element.captureState) == "function" and type(element.restoreState) == "function"
    local positionPair = type(element.getPosition) == "function" and type(element.setPosition) == "function"
    if not statePair and not positionPair then return nil, "capture_restore_or_get_set_required" end
    if type(element.movePosition) ~= "function" and not positionPair then
        return nil, "movePosition_or_get_set_required"
    end
    local controls, controlsReason = PrepareControls(element.extraControls)
    if controlsReason then return nil, controlsReason end
    local key = Key(owner, element.id)
    if records[key] or (EM2.Registry.Get and EM2.Registry.Get(key)) then return nil, "element_already_registered" end
    local record = { owner = owner, key = key }
    for field, value in pairs(element) do record[field] = value end
    record.extraControls = controls
    record.order = Finite(tonumber(record.order)) and tonumber(record.order) or 1000
    record.group = type(record.group) == "string" and record.group or owner
    return record
end

local function Enabled(record)
    if type(record.isEnabled) ~= "function" then return true end
    local ok, enabled = Invoke(record, "isEnabled")
    return ok and enabled ~= false
end

local function Frame(record)
    if not Enabled(record) then return nil end
    local ok, frame = Invoke(record, "getFrame")
    return ok and frame or nil
end

local function Add(record)
    records[record.key] = record
    owners[record.owner] = owners[record.owner] or {}
    owners[record.owner][record.id] = record
    EM2.Registry.Register({
        key = record.key, label = record.label, group = record.group, order = record.order,
        popupType = "external", canResize = false, canNudge = true,
        externalPublicElement = true, externalRecord = record,
        canReset = type(record.resetPosition) == "function",
        canOpenSettings = type(record.openSettings) == "function",
        getFrame = function() return Frame(record) end,
        isEnabled = function() return Enabled(record) end,
        getInspectorValues = record.getInspectorValues,
    })
    if sessionActive then
        local state = Capture(record)
        if state then sessionSnapshot[record.key] = state end
        if record.onSessionChanged then Invoke(record, "onSessionChanged", true, "join") end
    end
end

local function Remove(record)
    if EM2.ExternalPopup and EM2.ExternalPopup.GetKey
        and EM2.ExternalPopup.GetKey() == record.key and EM2.ExternalPopup.Close then
        EM2.ExternalPopup.Close()
    end
    if EM2.Movers and EM2.Movers.Remove then EM2.Movers.Remove(record.key) end
    EM2.Registry.Unregister(record.key)
    records[record.key] = nil
    local owned = owners[record.owner]
    if owned then
        owned[record.id] = nil
        if not next(owned) then owners[record.owner] = nil end
    end
    if sessionSnapshot then sessionSnapshot[record.key] = nil end
end

function API.GetVersion() return API.VERSION end
function API.GetCapabilities()
    return { registration = true, drag = true, gridSnap = true, nudge = true,
        undoRedo = true, saveDiscard = true, reset = true, inspector = true,
        settingsLink = true, popup = true, sessionCallbacks = true,
        resize = false, polling = false }
end

local function Record(owner, id)
    return ValidName(owner) and ValidName(id) and records[Key(owner, id)] or nil
end

function API.GetElementCapabilities(owner, id)
    local record = Record(owner, id)
    if not record then return nil, "not_registered" end
    return {
        available = Frame(record) ~= nil,
        reset = type(record.resetPosition) == "function",
        settings = type(record.openSettings) == "function",
        inspector = true,
        drag = true,
        nudge = true,
        undoRedo = true,
        saveDiscard = true,
        resize = false,
    }
end

function API.RegisterElements(owner, elements)
    if not ValidName(owner) then return false, "invalid_owner" end
    if type(elements) ~= "table" then return false, "elements_not_table" end
    local prepared, seen = {}, {}
    for _, element in pairs(elements) do
        local record, reason = Prepare(owner, element)
        if not record then return false, reason end
        if seen[record.key] then return false, "duplicate_element_id" end
        seen[record.key], prepared[#prepared + 1] = true, record
    end
    if #prepared == 0 then return false, "no_elements" end
    for i = 1, #prepared do Add(prepared[i]) end
    SyncHistory(); Refresh()
    return true
end

function API.RegisterElement(owner, element) return API.RegisterElements(owner, { element }) end

function API.UnregisterElement(owner, id)
    local record = ValidName(owner) and ValidName(id) and records[Key(owner, id)]
    if not record or record.owner ~= owner then return false, "not_registered" end
    Remove(record); SyncHistory(); Refresh()
    return true
end

function API.UnregisterOwner(owner)
    local owned = ValidName(owner) and owners[owner]
    if not owned then return false, "not_registered" end
    local remove = {}
    for _, record in pairs(owned) do remove[#remove + 1] = record end
    for i = 1, #remove do Remove(remove[i]) end
    listeners[owner] = nil
    SyncHistory(); Refresh()
    return true
end

function API.RegisterSessionListener(owner, callback)
    if not ValidName(owner) or type(callback) ~= "function" then return false end
    listeners[owner] = callback
    return true
end

function API.UnregisterSessionListener(owner)
    if not ValidName(owner) then return false end
    listeners[owner] = nil
    return true
end

function API.IsActive() return IsActive() end
function API.RefreshElement(owner, id)
    if not (ValidName(owner) and ValidName(id) and records[Key(owner, id)]) then return false, "not_registered" end
    Refresh(); return true
end
function API.RefreshOwner(owner)
    if not owners[owner] then return false, "not_registered" end
    Refresh(); return true
end

function API.Open(owner, id)
    local record = Record(owner, id)
    if not record then return false, "not_registered" end
    if not IsActive() or InCombat() then return false, "edit_mode_inactive" end
    if not Frame(record) then return false, "frame_unavailable" end
    if EM2.State and EM2.State.SetUnitKey then EM2.State.SetUnitKey(record.key) end
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(record.key, nil, nil, { source = "public-api", menu = false })
    end
    if record.onSelect and not Invoke(record, "onSelect", { source = "public-api", key = record.id }) then
        return false, "callback_error"
    end
    Refresh("hud")
    return true
end

API.SelectElement = API.Open

function API.EnterEditMode(owner, id)
    local record = Record(owner, id)
    if not record then return false, "not_registered" end
    if InCombat() then return false, "combat_lockdown" end
    if not Frame(record) then return false, "frame_unavailable" end
    local state = EM2.State
    if not (state and type(state.Enter) == "function") then return false, "edit_mode_unavailable" end
    if state.Enter(record.key, { provider = "msuf" }) ~= true then return false, "edit_mode_unavailable" end
    return API.Open(owner, id)
end

function API.OpenPopup(owner, id)
    local record = Record(owner, id)
    if not record then return false, "not_registered" end
    if not API.Open(owner, id) then return false, "edit_mode_inactive" end
    local popups = EM2.Popups
    if not (popups and type(popups.Open) == "function") then return false, "popup_unavailable" end
    if popups.Open(record.key) ~= true then return false, "popup_unavailable" end
    return true
end

function API.OpenSettings(owner, id)
    local record = Record(owner, id)
    if not record then return false, "not_registered" end
    if InCombat() then return false, "combat_lockdown" end
    if not IsActive() then return false, "edit_mode_inactive" end
    if type(record.openSettings) ~= "function" then return false, "settings_unavailable" end
    return Invoke(record, "openSettings", record.id, {
        owner = record.owner, id = record.id, key = record.key, source = "public-api",
    })
end

function API.ResetElement(owner, id)
    local record = Record(owner, id)
    if not record then return false, "not_registered" end
    if not IsActive() then return false, "edit_mode_inactive" end
    if type(record.resetPosition) ~= "function" then return false, "reset_unavailable" end
    return External.Reset(record.key)
end

function External.GetRecord(key) return records[key] end
function External.CaptureState(key) return Capture(records[key]) end

function External.ApplyMove(key, startState, dx, dy, centerX, centerY, phase)
    local record = records[key]
    dx, dy = tonumber(dx), tonumber(dy)
    if not record or not IsActive() or InCombat() or not Finite(dx) or not Finite(dy) then return false end
    phase = phase == "commit" and "commit" or "preview"
    local state = SafeCopy(startState)
    if type(state) ~= "table" then return false end
    if record.movePosition then
        return Invoke(record, "movePosition", {
            state = state, deltaX = dx, deltaY = dy,
            centerX = tonumber(centerX), centerY = tonumber(centerY), phase = phase,
        })
    end
    local xKey = Finite(state.x) and Finite(state.y) and "x"
        or (Finite(state.offsetX) and Finite(state.offsetY) and "offsetX")
    if not xKey then return false end
    local yKey = xKey == "x" and "y" or "offsetY"
    state[xKey], state[yKey] = state[xKey] + dx, state[yKey] + dy
    return Restore(record, state, phase)
end

function External.Nudge(key, dx, dy)
    local state, undo = External.CaptureState(key), EM2.Undo
    if InCombat() or not state or not (undo and undo.BeginChange and undo.CommitChange and undo.CancelChange)
        or undo.BeginChange("external", key, "Nudge") ~= true then return false end
    if not External.ApplyMove(key, state, dx, dy, nil, nil, "commit") then
        undo.CancelChange(); Restore(records[key], state, "rollback"); return false
    end
    undo.CommitChange(); Refresh()
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
    return true
end

local function ControlSpec(record, id)
    local list = record and record.extraControls
    for i = 1, #(list or {}) do
        if list[i].id == id then return list[i] end
    end
end

local function InvokeControl(record, spec, name, ...)
    local callback = spec and spec[name]
    if type(callback) ~= "function" then return false, "callback_missing" end
    local ok, result = pcall(callback, ...)
    if not ok then
        Report(record, ("control %s %s"):format(tostring(spec.id), name), result)
        return false, "callback_error"
    end
    if result == false then return false, "callback_rejected" end
    return true, result
end

function External.GetControls(key)
    local record = records[key]
    return record and record.extraControls or nil
end

function External.GetControlValue(key, id)
    local record = records[key]
    local spec = ControlSpec(record, id)
    if not spec then return nil end
    local ok, value = InvokeControl(record, spec, "get")
    if not ok then return nil end
    return value
end

--- One undo transaction per committed control change; the element's own
--- captureState/restoreState carry the before-state, so undo/redo and discard
--- revert control values exactly like positions.
function External.ApplyControl(key, id, value)
    local record, undo = records[key], EM2.Undo
    local spec = ControlSpec(record, id)
    if not spec or not IsActive() or InCombat()
        or not (undo and undo.BeginChange and undo.CommitChange and undo.CancelChange) then return false end
    if spec.kind == "number" then
        value = tonumber(value)
        if not Finite(value) then return false end
        if spec.min and value < spec.min then value = spec.min end
        if spec.max and value > spec.max then value = spec.max end
    else
        value = value == true
    end
    --- Transient controls are session view state (previews, visibility aids):
    --- no undo entry, no capture/rollback — the owner's set either applies or
    --- reports failure and the popup re-syncs to the real state.
    if spec.transient then
        if not InvokeControl(record, spec, "set", value) then return false end
        Refresh()
        return true
    end
    local before = Capture(record)
    if not before or undo.BeginChange("external", key, spec.label) ~= true then return false end
    if not InvokeControl(record, spec, "set", value) then
        undo.CancelChange()
        Restore(record, before, "rollback")
        return false
    end
    undo.CommitChange()
    Refresh()
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
    return true
end

function External.Reset(key)
    local record, undo = records[key], EM2.Undo
    if not record or not record.resetPosition or not IsActive() or InCombat()
        or not (undo and undo.BeginChange and undo.CommitChange and undo.CancelChange)
        or undo.BeginChange("external", key, "Reset") ~= true then return false end
    if not Invoke(record, "resetPosition", "commit") then undo.CancelChange(); return false end
    undo.CommitChange(); Refresh()
    return true
end

function External.Select(key, source, anchorFrame)
    local record = records[key]
    if not record or not record.onSelect then return record ~= nil end
    return Invoke(record, "onSelect", {
        source = source or "mover", owner = record.owner, id = record.id,
        key = record.key, anchorFrame = anchorFrame,
    })
end

function External.CanOpenSettings(key)
    return type(records[key] and records[key].openSettings) == "function"
end

function External.CanReset(key)
    return type(records[key] and records[key].resetPosition) == "function"
end

function External.GetDisplayInfo(key)
    local record = records[key]
    if not record then return nil end
    return record.label, record.group, record.settingsLabel,
        type(record.openSettings) == "function", type(record.resetPosition) == "function"
end

function External.OpenSettings(key, source)
    local record = records[key]
    if not record or not IsActive() or InCombat() or type(record.openSettings) ~= "function" then return false end
    local ok = Invoke(record, "openSettings", record.id, {
        owner = record.owner, id = record.id, key = record.key,
        source = type(source) == "string" and source or "msuf-edit-mode",
    })
    if ok and EM2.ExternalPopup and EM2.ExternalPopup.GetKey
        and EM2.ExternalPopup.GetKey() == key and EM2.ExternalPopup.Close then
        EM2.ExternalPopup.Close()
    end
    return ok
end

function External.GetInspectorValues(key)
    local record = records[key]
    if not record then return nil end
    local frame = Frame(record)
    if type(Util.FramePositionValues) == "function" then
        local x, y, width, height = Util.FramePositionValues(frame)
        if x ~= nil then return record.label, x, y, width, height end
    end
    if frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom then
        local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
        if left and right and top and bottom then
            local uiScale = _G.UIParent and _G.UIParent.GetEffectiveScale and _G.UIParent:GetEffectiveScale() or 1
            local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or uiScale
            local ratio = uiScale ~= 0 and frameScale / uiScale or 1
            --- Fallback when Core's shared geometry helper is unavailable:
            --- use the same center-facing horizontal edge as native elements.
            local screenW = _G.UIParent and _G.UIParent.GetWidth and _G.UIParent:GetWidth() or 0
            local screenH = _G.UIParent and _G.UIParent.GetHeight and _G.UIParent:GetHeight() or 0
            local uiLeft, uiRight = left * ratio, right * ratio
            local centerX = screenW * 0.5
            local x
            if uiRight <= centerX then
                x = uiRight - centerX
            elseif uiLeft >= centerX then
                x = uiLeft - centerX
            else
                x = 0
            end
            return record.label,
                Round(x),
                Round(top * ratio - screenH * 0.5),
                Round(uiRight - uiLeft), Round((top - bottom) * ratio)
        end
    end
    if record.getInspectorValues then
        local ok, values = Invoke(record, "getInspectorValues")
        if ok and type(values) == "table" then
            return record.label, values.x, values.y, values.width, values.height
        end
    end
    local state = Capture(record)
    return record.label, state and tonumber(state.x or state.offsetX), state and tonumber(state.y or state.offsetY),
        state and tonumber(state.width), state and tonumber(state.height)
end

local function NotifySession(enabled, reason)
    for _, record in pairs(records) do
        if record.onSessionChanged then Invoke(record, "onSessionChanged", enabled, reason) end
    end
    for owner, callback in pairs(listeners) do
        local ok, err = pcall(callback, enabled, reason)
        if not ok then Report({ owner = owner, id = "session" }, "listener", err) end
    end
end

function External.BeginSession()
    if sessionActive then return true end
    sessionActive, sessionSnapshot = true, {}
    for key, record in pairs(records) do sessionSnapshot[key] = Capture(record) end
    NotifySession(true, "enter")
    return true
end

function External.EndSession(outcome)
    if not sessionActive then return false end
    outcome = outcome == "discard" and "discard" or "save"
    if outcome == "discard" then
        for key, state in pairs(sessionSnapshot) do
            if records[key] and state then Restore(records[key], state, "discard") end
        end
    end
    sessionActive, sessionSnapshot = false, nil
    NotifySession(false, outcome)
    return true
end

function External.CaptureHistorySnapshot()
    if not sessionActive then return nil end
    local snapshot = { _msufEditModeExternalHistory = true, elements = {} }
    for key, record in pairs(records) do snapshot.elements[key] = Capture(record) end
    return snapshot
end

function External.RestoreHistorySnapshot(snapshot, reason)
    if type(snapshot) ~= "table" or snapshot._msufEditModeExternalHistory ~= true
        or type(snapshot.elements) ~= "table" then return false end
    for key, state in pairs(snapshot.elements) do
        if records[key] and state then Restore(records[key], state, reason or "history") end
    end
    Refresh()
    return true
end

function External.CaptureHistoryState(key)
    local state = External.CaptureState(key)
    return state and { category = "external", key = key, data = state } or nil
end

function External.RestoreHistoryState(snapshot)
    local record = snapshot and records[snapshot.key]
    if not record then return false end
    local ok = Restore(record, snapshot.data, "history")
    if ok then Refresh() end
    return ok
end

API._BeginSession = External.BeginSession
API._EndSession = External.EndSession
API._CaptureHistorySnapshot = External.CaptureHistorySnapshot
API._RestoreHistorySnapshot = External.RestoreHistorySnapshot
MSUF.EditModeAPI = API
Export("MSUF_EditModeAPI", API)
