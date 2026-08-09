--- Grid2 adapter for MSUF Edit Mode. Grid2 keeps ownership of all frames/data.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local API = _G.MSUF_EditModeAPI
if not (API and API.RegisterElement) then return end

local OWNER, SETTING = "MSUF.Grid2", "grid2EditModeIntegration"
local registered = {}
local active, hookedLayout, previewOwned = false, nil, false
local scaleHooked, scaleQueued, scalePending = false, false, false
local eventFrame

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

local function Layout()
    local layout = _G.Grid2Layout
    if type(layout) ~= "table" or type(layout.SavePosition) ~= "function"
        or type(layout.RestorePosition) ~= "function" or type(layout.RestorePositions) ~= "function"
        or type(layout.RestoreHeaderPosition) ~= "function" or type(layout.GetFramePosition) ~= "function"
        or type(layout.IterateHeaders) ~= "function" then return nil end
    return layout
end

local function Profile(layout)
    local profile = layout and layout.db and layout.db.profile
    if type(profile) ~= "table" then return nil end
    profile.Positions = type(profile.Positions) == "table" and profile.Positions or {}
    return profile
end

local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

local function FindHeader(positionKey)
    local layout = Layout()
    if not layout then return nil end
    for _, header in layout:IterateHeaders(true) do
        if header and header.headerPosKey == positionKey then return header end
    end
end

local function Restore(layout, frame, state, reason)
    local profile = Profile(layout)
    if InCombat() or not (profile and frame and type(state) == "table") then return false end
    local anchor, x, y = state.anchor, tonumber(state.x), tonumber(state.y)
    if type(anchor) ~= "string" or not x or not y then return false end
    local layoutScale = tonumber(state.layoutScale)
    if layoutScale and layoutScale > 0 and layoutScale ~= tonumber(profile.ScaleSize) then
        profile.ScaleSize = layoutScale
        layout:RestorePosition()
    end
    if state.positionKey then profile.Positions[state.positionKey] = { anchor, x, y }
    else profile.anchor, profile.PosX, profile.PosY = anchor, x, y end
    if frame == layout.frame then layout:RestorePosition()
    else layout:RestoreHeaderPosition(frame) end
    if reason == "commit" then layout:SavePosition(frame) end
    return true
end

local function Capture(layout, frame)
    local profile = Profile(layout)
    if not (profile and frame) then return nil end
    layout:SavePosition(frame)
    local key, position = frame.headerPosKey
    position = key and profile.Positions[key]
    local anchor, x, y
    if type(position) == "table" then anchor, x, y = position[1], position[2], position[3]
    else anchor, x, y, key = profile.anchor, profile.PosX, profile.PosY, nil end
    x, y = tonumber(x), tonumber(y)
    if type(anchor) ~= "string" or not x or not y then return nil end
    local visual = frame.frameBack or frame
    return {
        anchor = anchor, x = x, y = y, positionKey = key,
        layoutScale = tonumber(profile.ScaleSize),
        width = visual.GetWidth and visual:GetWidth(),
        height = visual.GetHeight and visual:GetHeight(),
    }
end

--- One layout-wide scale (profile.ScaleSize, Grid2's own setting): applied
--- through Grid2's RestorePosition, which SetScales the layout frame and
--- repositions it against the new scale.
local function ScaleControl()
    return {
        id = "scale", kind = "number", label = "Scale", min = 50, max = 200, step = 5,
        get = function()
            local layout = Layout()
            local profile = layout and Profile(layout)
            if not profile then return nil end
            return math.floor(((tonumber(profile.ScaleSize) or 1) * 100) + 0.5)
        end,
        set = function(value)
            local layout = Layout()
            local profile = layout and Profile(layout)
            value = tonumber(value)
            if InCombat() or not (profile and value) then return false end
            profile.ScaleSize = value / 100
            layout:RestorePosition()
            return true
        end,
    }
end

local function Move(layout, resolve, request)
    local frame, state = resolve(), request and request.state
    if not (frame and type(state) == "table" and frame.ClearAllPoints and frame.SetPoint)
        or not Restore(layout, frame, state, "preview") then return false end
    local anchor, x, y = layout:GetFramePosition(frame)
    x, y = tonumber(x), tonumber(y)
    if type(anchor) ~= "string" or not x or not y then return false end
    local uiScale = _G.UIParent and _G.UIParent.GetEffectiveScale and _G.UIParent:GetEffectiveScale() or 1
    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or uiScale
    if uiScale <= 0 then uiScale = 1 end
    if not frameScale or frameScale <= 0 then frameScale = uiScale end
    frame:ClearAllPoints()
    frame:SetPoint(anchor, _G.UIParent, anchor,
        x + (tonumber(request.deltaX) or 0) * uiScale / frameScale,
        y + (tonumber(request.deltaY) or 0) * uiScale / frameScale)
    layout:SavePosition(frame)
    if frame == layout.frame then layout:RestorePosition()
    else layout:RestoreHeaderPosition(frame) end
    return true
end

local function Element(layout, id, label, order, resolve, reset, controls)
    local function State() return Capture(layout, resolve()) end
    return {
        id = id, label = label, group = "Grid2", order = order,
        extraControls = controls,
        getFrame = function()
            local frame = resolve()
            return frame and (frame.frameBack or frame)
        end,
        isEnabled = function() return active and Enabled() and resolve() ~= nil end,
        captureState = State,
        restoreState = function(state, reason) return Restore(layout, resolve(), state, reason) end,
        movePosition = function(request) return Move(layout, resolve, request) end,
        resetPosition = reset,
        openSettings = function()
            local grid = _G.Grid2
            if type(grid) == "table" and type(grid.OpenGrid2Options) == "function" then
                grid:OpenGrid2Options()
                return true
            end
            return false
        end,
        getInspectorValues = function()
            local state = State()
            return state and { x = state.x, y = state.y, width = state.width, height = state.height }
        end,
    }
end

local function StableId(key)
    local text, hash = tostring(key or "detached"), 5381
    for i = 1, #text do hash = (hash * 33 + text:byte(i)) % 2147483647 end
    local stem = text:lower():gsub("[^%w_.%-]+", "_"):sub(1, 42)
    return ("detached_%s_%d"):format(stem ~= "" and stem or "detached", hash)
end

local function Add(element)
    if registered[element.id] then return true end
    local ok = API.RegisterElement(OWNER, element)
    if ok then registered[element.id] = true end
    return ok == true
end

local function SyncHeaders()
    local layout = active and Enabled() and Layout()
    if not layout then return end
    local index = 0
    for _, header in layout:IterateHeaders(true) do
        local key = header and header.headerPosKey
        if type(key) == "string" then
            index = index + 1
            local function Resolve() return Layout() == layout and FindHeader(key) end
            Add(Element(layout, StableId(key), ("Grid2 Detached Group %d"):format(index), 810 + index,
                Resolve, function()
                    if InCombat() then return false end
                    local profile = Profile(layout)
                    if not profile then return false end
                    profile.Positions[key] = nil
                    layout:ReloadLayout(true)
                    return true
                end))
        end
    end
    if API.RefreshOwner then API.RefreshOwner(OWNER) end
end

local function SessionChanged(enabled)
    local layout = Layout()
    if enabled then
        if layout and layout.SetTestMode and layout.testLayoutName == nil and type(layout.layoutName) == "string" then
            previewOwned = true
            layout:SetTestMode(true, nil, layout.layoutName)
        end
        SyncHeaders()
    elseif previewOwned then
        previewOwned = false
        if layout and layout.SetTestMode then layout:SetTestMode(false) end
    end
end

local function RestoreAfterScale()
    scaleQueued = false
    if not scalePending or not active or not Enabled() then scalePending = false; return end
    if InCombat() then
        if eventFrame then eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    scalePending = false
    if eventFrame then eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    local layout = Layout()
    if layout then
        layout:RestorePositions()
        if API.RefreshOwner then API.RefreshOwner(OWNER) end
    end
end

local function QueueScaleRestore()
    if not active or not Enabled() then return end
    scalePending = true
    if scaleQueued then return end
    scaleQueued = true
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, RestoreAfterScale)
    else RestoreAfterScale() end
end

local function Activate()
    if active or not Enabled() then return false end
    local layout = Layout()
    if not layout then return false end
    active = true
    if hookedLayout ~= layout and type(_G.hooksecurefunc) == "function" then
        hookedLayout = layout
        _G.hooksecurefunc(layout, "ReloadLayout", SyncHeaders)
    end
    if not scaleHooked and type(_G.hooksecurefunc) == "function" and _G.UIParent and _G.UIParent.SetScale then
        scaleHooked = true
        _G.hooksecurefunc(_G.UIParent, "SetScale", QueueScaleRestore)
    end
    local function Main() return Layout() == layout and layout.frame end
    if not Add(Element(layout, "layout", "Grid2", 800, Main, function()
        if InCombat() or not layout.ResetPosition then return false end
        layout:ResetPosition()
        return true
    end, { ScaleControl() })) then active = false; return false end
    API.RegisterSessionListener(OWNER, SessionChanged)
    SyncHeaders()
    return true
end

local function Deactivate()
    if not active then return false end
    SessionChanged(false)
    active, scalePending = false, false
    if eventFrame then eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    API.UnregisterOwner(OWNER)
    registered = {}
    return true
end

local function SetEnabled(enabled)
    enabled = enabled ~= false
    local general = General()
    if general then general[SETTING] = enabled end
    return enabled and Activate() or Deactivate()
end

Export("MSUF_Grid2EditMode_IsAvailable", function() return Layout() ~= nil end)
Export("MSUF_Grid2EditMode_SetEnabled", SetEnabled)

eventFrame = _G.CreateFrame and _G.CreateFrame("Frame")
if eventFrame then
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" and addon == "Grid2" and Enabled() then Activate()
        elseif event == "PLAYER_REGEN_ENABLED" then RestoreAfterScale() end
    end)
end

if Enabled() then Activate() end
