--- Details! adapter for MSUF Edit Mode. Snapped windows move as one native group.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local API = _G.MSUF_EditModeAPI
if not (API and API.RegisterElement) then return end

local OWNER, SETTING = "MSUF.Details", "detailsEditModeIntegration"
local registered, active, listening = {}, false, false

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

local function Details()
    local details = _G.Details
    return type(details) == "table" and type(details.GetInstance) == "function"
        and type(details.GetNumInstances) == "function" and details or nil
end

local function Id(instance)
    if type(instance) ~= "table" then return nil end
    if type(instance.GetId) == "function" then
        local ok, id = pcall(instance.GetId, instance)
        if ok and tonumber(id) then return tonumber(id) end
    end
    return tonumber(instance.meu_id)
end

local function Instance(id)
    local details = Details()
    local instance = details and details:GetInstance(tonumber(id))
    if type(instance) ~= "table" or not instance.baseframe then return nil end
    if type(instance.IsEnabled) == "function" then
        local ok, enabled = pcall(instance.IsEnabled, instance)
        if not ok or enabled ~= true then return nil end
    elseif instance.ativa ~= true then return nil end
    return instance
end

local function Group(instance)
    if not instance then return {} end
    local group
    if type(instance.GetInstanceGroup) == "function" then
        local ok, result = pcall(instance.GetInstanceGroup, instance)
        if ok and type(result) == "table" then group = result end
    end
    local result, seen = {}, {}
    for _, member in ipairs(group or { instance }) do
        local id = Id(member)
        if id and not seen[id] and Instance(id) == member then
            seen[id], result[#result + 1] = true, member
        end
    end
    if #result == 0 then result[1] = instance end
    table.sort(result, function(a, b) return (Id(a) or 0) < (Id(b) or 0) end)
    return result
end

local function Root(id)
    local instance = Instance(id)
    local group = instance and Group(instance)
    return group and Id(group[1]) == tonumber(id) and instance or nil
end

local function Save(group)
    for i = 1, #group do
        local instance = group[i]
        if type(instance.SaveMainWindowPosition) == "function" then
            pcall(instance.SaveMainWindowPosition, instance)
        end
    end
end

local function MemberScale(member)
    if type(member) ~= "table" or type(member.CreatePositionTable) ~= "function" then return nil end
    local ok, position = pcall(member.CreatePositionTable, member)
    return ok and type(position) == "table" and tonumber(position.scale) or nil
end

local function Capture(id)
    local root = Root(id)
    if not root then return nil end
    local group = Group(root)
    Save(group)
    local state = { rootId = Id(root), members = {} }
    for i = 1, #group do
        local member, mode = group[i], group[i].mostrando or "normal"
        local position = type(member.posicao) == "table" and member.posicao[mode]
        local memberId = Id(member)
        if memberId and type(position) == "table" and tonumber(position.x) and tonumber(position.y) then
            local entry = { id = memberId, mode = mode, x = tonumber(position.x), y = tonumber(position.y),
                w = tonumber(position.w), h = tonumber(position.h), scale = MemberScale(member) }
            state.members[#state.members + 1] = entry
            if memberId == state.rootId then
                state.x, state.y = entry.x, entry.y
                state.width = root.baseframe.GetWidth and root.baseframe:GetWidth() or entry.w
                state.height = root.baseframe.GetHeight and root.baseframe:GetHeight() or entry.h
            end
        end
    end
    return state.x and state.y and state or nil
end

local function Restore(id, state, reason)
    local root = type(state) == "table" and (Instance(state.rootId) or Root(id))
    if not (root and type(state.members) == "table") then return false end
    for i = 1, #state.members do
        local entry, member = state.members[i], Instance(state.members[i].id)
        local position = member and type(member.posicao) == "table" and member.posicao[entry.mode]
        local x, y = tonumber(entry.x), tonumber(entry.y)
        if type(position) == "table" and x and y then
            position.x, position.y = x, y
            if tonumber(entry.w) then position.w = tonumber(entry.w) end
            if tonumber(entry.h) then position.h = tonumber(entry.h) end
        end
        local scale = tonumber(entry.scale)
        if member and scale and scale ~= MemberScale(member)
            and type(member.SetWindowScale) == "function" then
            pcall(member.SetWindowScale, member, scale, false)
        end
    end
    if type(root.BaseFrameSnap) == "function" then root:BaseFrameSnap()
    elseif type(root.RestoreMainWindowPositionNoResize) == "function" then root:RestoreMainWindowPositionNoResize()
    else return false end
    if reason ~= "preview" then Save(Group(root)) end
    return true
end

local function Move(id, request)
    local state, root = request and request.state, Root(id)
    if type(state) ~= "table" or not root then return false end
    local x = (tonumber(state.x) or 0) + (tonumber(request.deltaX) or 0)
    local y = (tonumber(state.y) or 0) + (tonumber(request.deltaY) or 0)
    state.x, state.y = x, y
    for i = 1, #(state.members or {}) do
        if tonumber(state.members[i].id) == Id(root) then
            state.members[i].x, state.members[i].y = x, y
            break
        end
    end
    return Restore(id, state, request.phase)
end

--- Window scale via the documented Details! API (SetWindowScale 0.65–1.5,
--- refresh_group true keeps snapped windows aligned), shown as percent.
local function ScaleControl(id)
    return {
        id = "scale", kind = "number", label = "Scale", min = 65, max = 150, step = 5,
        get = function()
            local root = Root(id)
            local scale = root and MemberScale(root)
            return scale and math.floor(scale * 100 + 0.5) or nil
        end,
        set = function(value)
            local root = Root(id)
            value = tonumber(value)
            if not (root and value and type(root.SetWindowScale) == "function") then return false end
            local ok = pcall(root.SetWindowScale, root, value / 100, true)
            if ok then Save(Group(root)) end
            return ok == true
        end,
    }
end

local function Element(id)
    return {
        id = "window_" .. id, label = ("Details! Window %d"):format(id), group = "Details!", order = 900 + id,
        extraControls = { ScaleControl(id) },
        getFrame = function() local root = Root(id); return root and root.baseframe end,
        isEnabled = function() return active and Enabled() and Root(id) ~= nil end,
        captureState = function() return Capture(id) end,
        restoreState = function(state, reason) return Restore(id, state, reason) end,
        movePosition = function(request) return Move(id, request) end,
        openSettings = function()
            local details, root = Details(), Root(id)
            if details and root and type(details.OpenOptionsWindow) == "function" then
                details:OpenOptionsWindow(root)
                return true
            end
            return false
        end,
    }
end

local function Sync()
    local details = active and Enabled() and Details()
    if not details then return end
    for id = 1, tonumber(details:GetNumInstances()) or 0 do
        if not registered[id] and API.RegisterElement(OWNER, Element(id)) then registered[id] = true end
    end
    if next(registered) and API.RefreshOwner then API.RefreshOwner(OWNER) end
end

local listener = { Enabled = true, __enabled = true, __name = "MSUF Details Edit Mode" }
local events = { "DETAILS_INSTANCE_OPEN", "DETAILS_INSTANCE_CLOSE", "DETAILS_OPTIONS_MODIFIED", "DETAILS_PROFILE_APPLYED" }

local function Listen(details, enable)
    if enable == listening then return end
    listening = enable
    local method = enable and details.RegisterEvent or details.UnregisterEvent
    if type(method) ~= "function" then return end
    for i = 1, #events do method(details, listener, events[i], enable and Sync or nil) end
end

local function Activate()
    if active or not Enabled() then return false end
    local details = Details()
    if not details then return false end
    active = true
    Listen(details, true)
    Sync()
    return true
end

local function Deactivate()
    if not active then return false end
    local details = Details()
    active = false
    if details then Listen(details, false) end
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

Export("MSUF_DetailsEditMode_IsAvailable", function() return Details() ~= nil end)
Export("MSUF_DetailsEditMode_SetEnabled", SetEnabled)

local eventFrame = _G.CreateFrame and _G.CreateFrame("Frame")
if eventFrame then
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:SetScript("OnEvent", function(_, _, addon)
        if addon == "Details" and Enabled() then Activate() end
    end)
end

if Enabled() then Activate() end
