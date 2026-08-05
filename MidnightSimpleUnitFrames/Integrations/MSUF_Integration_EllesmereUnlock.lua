local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local PROVIDER_ID = "ellesmere"
local LISTENER_OWNER = addonName or "MidnightSimpleUnitFrames"

local function EllesmereAPI()
    local api = _G.EllesmereUI
    if type(api) ~= "table"
        or type(api.RegisterUnlockElements) ~= "function"
        or type(api.UnregisterUnlockElement) ~= "function"
        or type(api.RegisterUnlockModeListener) ~= "function"
        or type(api.UnregisterUnlockModeListener) ~= "function"
        or type(api.IsUnlockModeActive) ~= "function" then
        return nil
    end
    return api
end

--- EllesmereUI is an OptionalDep and its lightweight Unlock header is ready
--- before MSUF. The heavy body remains deferred until the user opens Edit Mode.
if not EllesmereAPI() then return end

local EM2 = _G.MSUF_EM2
local External = EM2 and EM2.ExternalProviders
if not (External and type(External.Register) == "function") then return end

local function General()
    local db = _G.MSUF_DB
    return type(db) == "table" and type(db.general) == "table" and db.general or nil
end

local spec = {
    id = PROVIDER_ID,
    listenerOwner = LISTENER_OWNER,
    folder = addonName or "MidnightSimpleUnitFrames",
    externalPrefix = "MSUF_",
    elementGroup = "Midnight Simple Unit Frames",
    elementLabelPrefix = "MSUF ",
    fieldPrefix = "_msufEllesmere",
    menuRefreshReason = "eui-unlock-close",
    previewRefreshReason = "MSUF2_EUI_UNLOCK_CLOSE",

    GetAPI = EllesmereAPI,
    IsEnabled = function()
        local general = General()
        return general == nil or general.ellesmereEditModeIntegration ~= false
    end,
    SetEnabledValue = function(enabled)
        local general = General()
        if general then general.ellesmereEditModeIntegration = enabled ~= false end
    end,
    IsModeActive = function(api)
        return api:IsUnlockModeActive() == true
    end,
    IsEntering = function(api)
        return api:IsUnlockModeActive() == true
            or api._unlockActive == true or api._unlockModeActive == true
    end,

    MakeElement = function(api, opts)
        opts.noResize = true
        opts.noInitHook = true
        opts.noAnchorTarget = true
        opts.noAnchorTo = true
        opts.noSizeMatchTarget = true
        if type(api.MakeUnlockElement) == "function" then return api.MakeUnlockElement(opts) end
        opts.savePosition, opts.loadPosition = opts.savePos, opts.loadPos
        opts.clearPosition, opts.applyPosition = opts.clearPos, opts.applyPos
        return opts
    end,
    RegisterElements = function(api, elements, folder)
        return pcall(api.RegisterUnlockElements, api, elements, folder)
    end,
    UnregisterElement = function(api, key)
        api:UnregisterUnlockElement(key)
    end,
    RegisterModeListener = function(api, owner, listener)
        api:RegisterUnlockModeListener(owner, listener)
    end,
    UnregisterModeListener = function(api, owner)
        api:UnregisterUnlockModeListener(owner)
    end,

    GetRoot = function() return _G.EllesmereUnlockMode end,
    GetMoverKey = function(mover) return mover and mover._barKey end,
    SyncMover = function(mover)
        if mover and type(mover.Sync) == "function" then mover:Sync() end
    end,
    RefreshMover = function(mover)
        if mover and type(mover.RefreshAnchoredText) == "function" then mover:RefreshAnchoredText() end
    end,
    IsMoverDragging = function(mover)
        return mover and mover._dragging == true
    end,
    AbortMover = function(mover, releaseMouse)
        if not mover then return end
        if mover.SetScript then mover:SetScript("OnUpdate", nil) end
        mover._dragging = false
        if releaseMouse and mover.GetScript then
            local mouseUp = mover:GetScript("OnMouseUp")
            if mouseUp then pcall(mouseUp, mover, "LeftButton") end
        end
    end,
    MarkDirty = function(api, mover)
        local nudge = api and api._unlockNudge
        return type(nudge) == "function" and pcall(nudge, 0, 0, mover, true) or false
    end,

    PrepareOpen = function(api)
        if type(api.OpenUnlockMode) ~= "function" and type(api.EnsureLoaded) == "function" then
            pcall(api.EnsureLoaded, api)
        end
        return type(api.OpenUnlockMode or api._openUnlockMode) == "function"
    end,
    OpenMode = function(api)
        local openUnlock = api.OpenUnlockMode or api._openUnlockMode
        return type(openUnlock) == "function" and pcall(openUnlock, api) or false
    end,
    CloseMode = function(api)
        return type(api.ToggleUnlockMode) == "function" and pcall(api.ToggleUnlockMode, api) or false
    end,
}

local controller = External.Register(spec)
if not controller then return end

ExportPublic("MSUF_EllesmereEditMode_IsAvailable", function()
    return External.IsAvailable(PROVIDER_ID)
end)
ExportPublic("MSUF_EllesmereEditMode_SetEnabled", function(enabled)
    return External.SetEnabled(PROVIDER_ID, enabled)
end)
ExportPublic("MSUF_TryOpenExternalEditMode", function(unitKey)
    return External.Open(PROVIDER_ID, unitKey)
end)
ExportPublic("MSUF_TryCloseExternalEditMode", function()
    return External.Close(PROVIDER_ID)
end)
ExportPublic("MSUF_EllesmereEditMode_SuspendPreview", function()
    return External.Suspend(PROVIDER_ID)
end)
ExportPublic("MSUF_EllesmereEditMode_ResumePreview", function()
    return External.Resume(PROVIDER_ID)
end)
ExportPublic("MSUF_EllesmereEditMode_ClearMoveState", function()
    return External.ClearMoveState(PROVIDER_ID)
end)

External.Initialize(PROVIDER_ID)
