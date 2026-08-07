--- Dominos adapter for MSUF Edit Mode. Dominos keeps ownership of all bars/positions.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local API = _G.MSUF_EditModeAPI
if not (API and API.RegisterElement) then return end

local OWNER, SETTING = "MSUF.Dominos", "dominosEditModeIntegration"
local registered = {}
local active, listening, syncQueued = false, false, false

local function Export(name, value)
    if type(MSUF.ExportPublic) == "function" then return MSUF.ExportPublic(name, value) end
    _G[name] = value
    return value
end

local function General()
    local db = _G.MSUF_DB
    return type(db) == "table" and type(db.general) == "table" and db.general or nil
end

local function Enabled()
    local general = General()
    return not general or general[SETTING] ~= false
end

local function Dominos()
    local dominos = _G.Dominos
    if type(dominos) ~= "table" or type(dominos.RegisterCallback) ~= "function"
        or type(dominos.UnregisterCallback) ~= "function" then return nil end
    local frames = dominos.Frame
    if type(frames) ~= "table" or type(frames.Get) ~= "function"
        or type(frames.GetAll) ~= "function" then return nil end
    return dominos
end

local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

local function Bar(id)
    local dominos = Dominos()
    local bar = dominos and dominos.Frame:Get(id)
    if type(bar) ~= "table" or type(bar.sets) ~= "table"
        or type(bar.GetSavedPosition) ~= "function" or type(bar.SavePosition) ~= "function"
        or type(bar.RestorePosition) ~= "function" then return nil end
    return bar
end

--- Docked bars are SetPoint-anchored to their host bar and follow it natively,
--- and their saved anchor outranks the saved position on every Dominos load,
--- so they must never get their own mover or position writes.
local function Movable(id)
    local bar = Bar(id)
    if not bar or (type(bar.IsAnchored) == "function" and bar:IsAnchored() == true) then return nil end
    return bar
end

local function Capture(id)
    local bar = Movable(id)
    if not bar then return nil end
    local point, relPoint, x, y = bar:GetSavedPosition()
    x, y = tonumber(x), tonumber(y)
    if type(point) ~= "string" or not x or not y then return nil end
    local shown, clickThrough, padW, padH
    if type(bar.FrameIsShown) == "function" then shown = bar:FrameIsShown() == true end
    if type(bar.GetClickThrough) == "function" then clickThrough = bar:GetClickThrough() == true end
    if type(bar.GetPadding) == "function" then
        padW, padH = bar:GetPadding()
        padW, padH = tonumber(padW), tonumber(padH)
    end
    return {
        point = point, relPoint = type(relPoint) == "string" and relPoint or point, x = x, y = y,
        width = bar.GetWidth and bar:GetWidth(), height = bar.GetHeight and bar:GetHeight(),
        scale = type(bar.GetFrameScale) == "function" and tonumber(bar:GetFrameScale()) or nil,
        alpha = type(bar.GetFrameAlpha) == "function" and tonumber(bar:GetFrameAlpha()) or nil,
        fadeAlpha = type(bar.GetFadeMultiplier) == "function" and tonumber(bar:GetFadeMultiplier()) or nil,
        spacing = type(bar.GetSpacing) == "function" and tonumber(bar:GetSpacing()) or nil,
        columns = type(bar.NumColumns) == "function" and tonumber(bar:NumColumns()) or nil,
        buttons = tonumber(id) ~= nil and type(bar.NumButtons) == "function"
            and tonumber(bar:NumButtons()) or nil,
        padW = padW, padH = padH,
        shown = shown, clickThrough = clickThrough,
    }
end

--- Dominos persists through the live frame.sets references, so every phase
--- (preview, commit, discard, history) is the same native SavePosition +
--- RestorePosition pair. Scale, opacity and visibility ride along in the
--- snapshot so undo and discard also revert the popup quick controls; the
--- scale write must land first because SetFrameScale re-saves the position
--- from live geometry.
local function Restore(id, state)
    local bar = Movable(id)
    if InCombat() or not bar or type(state) ~= "table" then return false end
    local x, y = tonumber(state.x), tonumber(state.y)
    if type(state.point) ~= "string" or not x or not y then return false end
    local scale = tonumber(state.scale)
    if scale and scale > 0 and type(bar.SetFrameScale) == "function"
        and (type(bar.GetFrameScale) ~= "function" or bar:GetFrameScale() ~= scale) then
        bar:SetFrameScale(scale)
    end
    local alpha = tonumber(state.alpha)
    if alpha and type(bar.SetFrameAlpha) == "function" then
        bar:SetFrameAlpha(alpha < 0 and 0 or alpha > 1 and 1 or alpha)
    end
    local fadeAlpha = tonumber(state.fadeAlpha)
    if fadeAlpha and type(bar.SetFadeMultiplier) == "function" then
        bar:SetFadeMultiplier(fadeAlpha < 0 and 0 or fadeAlpha > 1 and 1 or fadeAlpha)
    end
    if type(state.buttons) == "number" and type(bar.SetNumButtons) == "function"
        and type(bar.NumButtons) == "function" and bar:NumButtons() ~= state.buttons then
        bar:SetNumButtons(state.buttons)
    end
    if type(state.columns) == "number" and type(bar.SetColumns) == "function" then
        bar:SetColumns(state.columns)
    end
    if type(state.spacing) == "number" and type(bar.SetSpacing) == "function" then
        bar:SetSpacing(state.spacing)
    end
    if type(state.padW) == "number" and type(bar.SetPadding) == "function" then
        bar:SetPadding(state.padW, tonumber(state.padH))
    end
    if state.clickThrough ~= nil and type(bar.SetClickThrough) == "function" then
        bar:SetClickThrough(state.clickThrough == true)
    end
    if state.shown == true and type(bar.ShowFrame) == "function" then bar:ShowFrame()
    elseif state.shown == false and type(bar.HideFrame) == "function" then bar:HideFrame() end
    bar:SavePosition(state.point, state.relPoint, x, y)
    return bar:RestorePosition() == true
end

local function Move(id, request)
    local state, bar = request and request.state, Movable(id)
    if type(state) ~= "table" or not bar then return false end
    local uiScale = _G.UIParent and _G.UIParent.GetEffectiveScale and _G.UIParent:GetEffectiveScale() or 1
    local barScale = bar.GetEffectiveScale and bar:GetEffectiveScale() or uiScale
    if uiScale <= 0 then uiScale = 1 end
    if not barScale or barScale <= 0 then barScale = uiScale end
    return Restore(id, {
        point = state.point, relPoint = state.relPoint,
        x = (tonumber(state.x) or 0) + (tonumber(request.deltaX) or 0) * uiScale / barScale,
        y = (tonumber(state.y) or 0) + (tonumber(request.deltaY) or 0) * uiScale / barScale,
    })
end

local function Label(bar, id)
    local name = type(bar.GetDisplayName) == "function" and bar:GetDisplayName() or nil
    if type(name) ~= "string" or name == "" or #name > 100 then
        name = ("Bar %s"):format(tostring(id))
    end
    return ("Dominos %s"):format(name)
end

--- The popup settings button opens Dominos' own per-bar settings window. The
--- bar menu needs the LoadOnDemand Dominos_Config addon; the global options
--- frame is the fallback.
local function OpenSettings(id)
    local bar = Bar(id)
    if bar and type(bar.ShowMenu) == "function" then
        bar:ShowMenu()
        if type(bar.menu) == "table" then return true end
    end
    local dominos = Dominos()
    if dominos and type(dominos.ShowOptionsFrame) == "function" then
        return dominos:ShowOptionsFrame() == true
    end
    return false
end

--- Popup quick controls mirror Dominos' own Layout panel — same ranges, same
--- public setters its sliders call. Only controls whose methods exist on the
--- bar are offered, and Buttons stays limited to the numbered action bars
--- exactly like in Dominos' settings. Undo/discard coverage comes from
--- Capture/Restore above.
local function NumberSpec(id, controlId, label, minValue, maxValue, getter, setter)
    return {
        id = controlId, kind = "number", label = label, min = minValue, max = maxValue,
        get = function()
            local bar = Movable(id)
            local value = bar and tonumber(getter(bar))
            if not value then return nil end
            return math.floor(value + 0.5)
        end,
        set = function(value)
            local bar = Movable(id)
            if InCombat() or not bar then return false end
            return setter(bar, tonumber(value)) == true
        end,
    }
end

local function ToggleSpec(id, controlId, label, getter, setter)
    return {
        id = controlId, kind = "toggle", label = label,
        get = function()
            local bar = Movable(id)
            return bar ~= nil and getter(bar) == true
        end,
        set = function(value)
            local bar = Movable(id)
            if InCombat() or not bar then return false end
            return setter(bar, value == true) == true
        end,
    }
end

local function Controls(id)
    local bar = Bar(id)
    local controls = {}
    if bar and tonumber(id) and type(bar.SetNumButtons) == "function"
        and type(bar.NumButtons) == "function" then
        controls[#controls + 1] = NumberSpec(id, "buttons", "Buttons", 1, 12,
            function(b) return b:NumButtons() end,
            function(b, value)
                if type(b.SetNumButtons) ~= "function" then return false end
                b:SetNumButtons(value or 1)
                return true
            end)
    end
    if bar and type(bar.SetColumns) == "function" and type(bar.NumColumns) == "function" then
        controls[#controls + 1] = NumberSpec(id, "columns", "Columns", 1, 12,
            function(b) return b:NumColumns() end,
            function(b, value)
                if type(b.SetColumns) ~= "function" then return false end
                value = value or 1
                local count = type(b.NumButtons) == "function" and tonumber(b:NumButtons()) or nil
                if count and count > 0 and value > count then value = count end
                b:SetColumns(value)
                return true
            end)
    end
    if bar and type(bar.SetSpacing) == "function" and type(bar.GetSpacing) == "function" then
        controls[#controls + 1] = NumberSpec(id, "spacing", "Spacing", -16, 32,
            function(b) return b:GetSpacing() end,
            function(b, value)
                if type(b.SetSpacing) ~= "function" then return false end
                b:SetSpacing(value or 0)
                return true
            end)
    end
    if bar and type(bar.SetPadding) == "function" and type(bar.GetPadding) == "function" then
        controls[#controls + 1] = NumberSpec(id, "padding", "Padding", -16, 32,
            function(b) return (b:GetPadding()) end,
            function(b, value)
                if type(b.SetPadding) ~= "function" then return false end
                b:SetPadding(value or 0)
                return true
            end)
    end
    controls[#controls + 1] = NumberSpec(id, "scale", "Scale", 50, 200,
        function(b)
            local scale = type(b.GetFrameScale) == "function" and tonumber(b:GetFrameScale())
            return scale and scale * 100
        end,
        function(b, value)
            if type(b.SetFrameScale) ~= "function" then return false end
            b:SetFrameScale((value or 100) / 100)
            return true
        end)
    controls[#controls + 1] = NumberSpec(id, "opacity", "Opacity", 0, 100,
        function(b)
            local alpha = type(b.GetFrameAlpha) == "function" and tonumber(b:GetFrameAlpha())
            return alpha and alpha * 100
        end,
        function(b, value)
            if type(b.SetFrameAlpha) ~= "function" then return false end
            b:SetFrameAlpha((value or 100) / 100)
            return true
        end)
    controls[#controls + 1] = NumberSpec(id, "fade", "Faded opacity", 0, 100,
        function(b)
            local alpha = type(b.GetFadeMultiplier) == "function" and tonumber(b:GetFadeMultiplier())
            return alpha and alpha * 100
        end,
        function(b, value)
            if type(b.SetFadeMultiplier) ~= "function" then return false end
            b:SetFadeMultiplier((value or 100) / 100)
            return true
        end)
    controls[#controls + 1] = ToggleSpec(id, "shown", "Show bar",
        function(b) return type(b.FrameIsShown) == "function" and b:FrameIsShown() end,
        function(b, value)
            if value then
                if type(b.ShowFrame) ~= "function" then return false end
                b:ShowFrame()
            else
                if type(b.HideFrame) ~= "function" then return false end
                b:HideFrame()
            end
            return true
        end)
    controls[#controls + 1] = ToggleSpec(id, "clickthrough", "Click through",
        function(b) return type(b.GetClickThrough) == "function" and b:GetClickThrough() end,
        function(b, value)
            if type(b.SetClickThrough) ~= "function" then return false end
            b:SetClickThrough(value)
            return true
        end)
    return controls
end

local function Element(id, elementId, label, order)
    return {
        id = elementId, label = label, group = "Dominos", order = order,
        getFrame = function() return Bar(id) end,
        isEnabled = function() return active and Enabled() and Movable(id) ~= nil end,
        captureState = function() return Capture(id) end,
        restoreState = function(state) return Restore(id, state) end,
        movePosition = function(request) return Move(id, request) end,
        openSettings = function() return OpenSettings(id) end,
        extraControls = Controls(id),
    }
end

local function Sync()
    local dominos = active and Enabled() and Dominos()
    if not dominos then return end
    for id, bar in dominos.Frame:GetAll() do
        local stem = tostring(id):lower():gsub("[^%w_.%-]+", "_")
        local elementId = ("bar_%s"):format(stem ~= "" and stem or "bar")
        if not registered[elementId] then
            local order = tonumber(id) and 700 + tonumber(id) or 760
            if API.RegisterElement(OWNER, Element(id, elementId, Label(bar, id), order)) then
                registered[elementId] = true
            end
        end
    end
    if next(registered) and API.RefreshOwner then API.RefreshOwner(OWNER) end
end

--- Dominos rebuilds its bars inside the same callbacks we subscribe to, and
--- CallbackHandler order between listeners is undefined, so enumerate one
--- frame later instead of racing the bar constructors.
local function QueueSync()
    if syncQueued or not active then return end
    syncQueued = true
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, function()
            syncQueued = false
            Sync()
        end)
    else
        syncQueued = false
        Sync()
    end
end

local listener = { __name = "MSUF Dominos Edit Mode" }
local events = { "LAYOUT_LOADED", "LAYOUT_UNLOADED", "ACTIONBAR_COUNT_UPDATED" }

local function Listen(dominos, enable)
    if enable == listening then return end
    listening = enable
    for i = 1, #events do
        if enable then dominos.RegisterCallback(listener, events[i], QueueSync)
        else dominos.UnregisterCallback(listener, events[i]) end
    end
end

local function Activate()
    if active or not Enabled() then return false end
    local dominos = Dominos()
    if not dominos then return false end
    active = true
    Listen(dominos, true)
    Sync()
    return true
end

local function Deactivate()
    if not active then return false end
    local dominos = Dominos()
    active = false
    if dominos then Listen(dominos, false) end
    if next(registered) then API.UnregisterOwner(OWNER) end
    registered = {}
    return true
end

local function SetEnabled(enabled)
    enabled = enabled ~= false
    local general = General()
    if general then general[SETTING] = enabled end
    return enabled and Activate() or Deactivate()
end

Export("MSUF_DominosEditMode_IsAvailable", function() return Dominos() ~= nil end)
Export("MSUF_DominosEditMode_SetEnabled", SetEnabled)

local eventFrame = _G.CreateFrame and _G.CreateFrame("Frame")
if eventFrame then
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:SetScript("OnEvent", function(_, _, addon)
        if addon == "Dominos" and Enabled() then Activate() end
    end)
end

if Enabled() then Activate() end
