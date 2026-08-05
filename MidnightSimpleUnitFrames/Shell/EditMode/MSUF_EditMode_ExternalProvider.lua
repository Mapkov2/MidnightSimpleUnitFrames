local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local External = EM2.ExternalProviders or {}
EM2.ExternalProviders = External

--- Provider-neutral lifecycle and registry ownership for optional Edit Mode shells.
--- Movement/proxy behavior is attached by MSUF_EditMode_ExternalMovement.lua.

local providers = External.providers or {}
External.providers = providers

local CASTBAR_FIELDS = {
    player = { x = "castbarPlayerOffsetX", y = "castbarPlayerOffsetY", w = "castbarPlayerBarWidth", h = "castbarPlayerBarHeight" },
    target = { x = "castbarTargetOffsetX", y = "castbarTargetOffsetY", w = "castbarTargetBarWidth", h = "castbarTargetBarHeight" },
    focus  = { x = "castbarFocusOffsetX",  y = "castbarFocusOffsetY",  w = "castbarFocusBarWidth",  h = "castbarFocusBarHeight" },
    boss   = { x = "bossCastbarOffsetX",   y = "bossCastbarOffsetY",   w = "bossCastbarWidth",       h = "bossCastbarHeight" },
}
local CASTBAR_ENABLE_FIELDS = {
    player = "enablePlayerCastbar", target = "enableTargetCastbar",
    focus = "enableFocusCastbar", boss = "enableBossCastbar",
}

local function General()
    local db = _G.MSUF_DB
    return type(db) == "table" and type(db.general) == "table" and db.general or nil
end

local function InCombat()
    return _G.MSUF_InCombat == true
        or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown()) == true
end

local function FrameRectToUI(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return nil end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return nil end
    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local uiScale = _G.UIParent and _G.UIParent.GetEffectiveScale and _G.UIParent:GetEffectiveScale() or 1
    if not frameScale or frameScale == 0 then frameScale = 1 end
    if not uiScale or uiScale == 0 then uiScale = 1 end
    local ratio = frameScale / uiScale
    return left * ratio, right * ratio, top * ratio, bottom * ratio
end

local function FrameCenterUI(frame)
    local left, right, top, bottom = FrameRectToUI(frame)
    if not left then return nil end
    return (left + right) * 0.5, (bottom + top) * 0.5
end

local function CenterOffset(frame)
    local left, right, top, bottom = FrameRectToUI(frame)
    if not left then return nil end
    local uiLeft, uiRight, uiTop, uiBottom = FrameRectToUI(_G.UIParent)
    local uiCenterX, uiCenterY
    if uiLeft then
        uiCenterX, uiCenterY = (uiLeft + uiRight) * 0.5, (uiBottom + uiTop) * 0.5
    else
        uiCenterX = ((_G.UIParent and _G.UIParent.GetWidth and _G.UIParent:GetWidth()) or 0) * 0.5
        uiCenterY = ((_G.UIParent and _G.UIParent.GetHeight and _G.UIParent:GetHeight()) or 0) * 0.5
    end
    return ((left + right) * 0.5) - uiCenterX, ((bottom + top) * 0.5) - uiCenterY
end

local function ExpandBounds(bounds, left, right, top, bottom)
    if not (left and right and top and bottom) then return bounds end
    if not bounds then return { left, right, top, bottom } end
    bounds[1] = math.min(bounds[1], left)
    bounds[2] = math.max(bounds[2], right)
    bounds[3] = math.max(bounds[3], top)
    bounds[4] = math.min(bounds[4], bottom)
    return bounds
end

local Controller = External.Controller or {}
External.Controller = Controller
Controller.__index = Controller

local Shared = External.Shared or {}
External.Shared = Shared
Shared.CASTBAR_FIELDS = CASTBAR_FIELDS
Shared.InCombat = InCombat
Shared.FrameRectToUI = FrameRectToUI
Shared.FrameCenterUI = FrameCenterUI
Shared.ExpandBounds = ExpandBounds

function Controller:Field(suffix)
    return (self.spec.fieldPrefix or "_msufExternal") .. suffix
end

function Controller:GetAPI()
    return self.spec.GetAPI and self.spec.GetAPI() or nil
end

function Controller:IsEnabled()
    return not self.spec.IsEnabled or self.spec.IsEnabled() ~= false
end

function Controller:ExternalKey(key)
    return (self.spec.externalPrefix or "MSUF_") .. key
end

function Controller:CastbarUnit(cfg, key)
    local unit = cfg and cfg.castbarUnit
    if not unit and tostring(key):sub(1, 8) == "castbar_" then unit = tostring(key):sub(9) end
    return CASTBAR_FIELDS[unit] and unit or nil
end

function Controller:IsGroupConfig(cfg)
    return tostring(cfg and cfg.popupType or ""):sub(1, 3) == "gf_"
end

function Controller:IsUnitConfig(cfg)
    return cfg and cfg.popupType == "unit"
end

function Controller:IsCastbarConfigEnabled(unit)
    local fields = CASTBAR_FIELDS[unit]
    local general = General()
    if not fields or type(general) ~= "table" or general.castbarPlayerPreviewEnabled == false then return false end
    local shouldUse = _G.MSUF_ShouldUseMSUFCastbar
    if type(shouldUse) == "function" then return shouldUse(unit, general) == true end
    return general[CASTBAR_ENABLE_FIELDS[unit]] ~= false
end

function Controller:IsSessionReady()
    if not self.sessionActive or InCombat() then return false end
    local state = EM2.State
    return state and state.IsActive and state.IsActive()
        and state.GetProvider and state.GetProvider() == self.id
        and not (state.IsExternalPreviewSuspended and state.IsExternalPreviewSuspended())
end

function Controller:ApplyKey(key)
    local util = EM2.Util
    if util and type(util.ApplySettingsForKeySafe) == "function" then
        util.ApplySettingsForKeySafe(key)
    elseif type(_G.MSUF_ApplyAllSettings) == "function" then
        _G.MSUF_ApplyAllSettings()
    end
end

function Controller:StoredFallback(cfg, key)
    local conf = cfg and cfg.getConf and cfg.getConf() or nil
    if type(conf) ~= "table" then return 0, 0 end
    local unit = self:CastbarUnit(cfg, key)
    if unit then
        local fields = CASTBAR_FIELDS[unit]
        return tonumber(conf[fields.x]) or 0, tonumber(conf[fields.y]) or 0
    end
    return tonumber(conf.offsetX) or 0, tonumber(conf.offsetY) or 0
end

function Controller:LoadPosition(cfg, key, frame)
    if not frame and not self:IsGroupConfig(cfg) then
        frame = cfg and cfg.getFrame and cfg.getFrame() or nil
    end
    local x, y = CenterOffset(frame)
    if x == nil then x, y = self:StoredFallback(cfg, key) end
    return { point = "CENTER", relPoint = "CENTER", x = x, y = y }
end

function Controller:ConfigSize(cfg, key)
    local conf = cfg and cfg.getConf and cfg.getConf() or nil
    if type(conf) ~= "table" then return 1, 1 end
    local unit = self:CastbarUnit(cfg, key)
    if unit then
        local fields = CASTBAR_FIELDS[unit]
        return tonumber(conf[fields.w]) or 1, tonumber(conf[fields.h]) or 1
    end
    return tonumber(conf.width) or 1, tonumber(conf.height) or 1
end

function Controller:GetSize(cfg, key, frame)
    if frame and frame.GetWidth and frame.GetHeight then
        local width, height = frame:GetWidth(), frame:GetHeight()
        if width and height then return width, height end
    end
    return self:ConfigSize(cfg, key)
end

function Controller:IsElementHidden(key, cfg)
    if not self:IsEnabled() then return true end
    local castbarUnit = self:CastbarUnit(cfg, key)
    if castbarUnit then return not self:IsCastbarConfigEnabled(castbarUnit) end
    if type(cfg.isEnabled) == "function" and not cfg.isEnabled() then return true end
    if self:IsGroupConfig(cfg) then
        local state = EM2.State
        local selected = state and state.GetUnitKey and state.GetUnitKey() or nil
        if type(selected) == "string" and selected:sub(1, 3) == "gf_" and selected ~= key then return true end
    end
    return false
end

function Controller:ResolveElementFrame(externalKey, cfg)
    return self.resolvedFrames[externalKey] or self:SyncProxy(externalKey, cfg, false)
end

function Controller:BuildElement(api, key, cfg)
    local externalKey = self:ExternalKey(key)
    local opts = {
        key = externalKey,
        label = (self.spec.elementLabelPrefix or "MSUF ") .. tostring(cfg.label or key),
        group = self.spec.elementGroup or "Midnight Simple Unit Frames",
        order = (self.spec.orderBase or 5000) + (tonumber(cfg.order) or 1000),
        getFrame = function() return self:ResolveElementFrame(externalKey, cfg) end,
        getSize = function() return self:GetSize(cfg, key, self.resolvedFrames[externalKey]) end,
        savePos = function()
            local binding = self.externalBindings[externalKey]
            if binding and binding.externalDrag then self:FinishMove(binding, true) end
        end,
        loadPos = function()
            if self.spec.IsEntering(api) and not self.sessionActive then
                self:SyncProxy(externalKey, cfg, true)
                local binding = self.externalBindings[externalKey]
                if binding then binding.entryPrepared = true end
            end
            return self:LoadPosition(cfg, key, self.resolvedFrames[externalKey])
        end,
        clearPos = function() self:ClearPosition(externalKey, cfg, key) end,
        applyPos = function()
            self:ApplyKey(key)
            if self:IsSessionReady() then self:SyncProxy(externalKey, cfg, true) end
        end,
        isHidden = function() return not self.advertiseProxyMovers and self:IsElementHidden(key, cfg) end,
        onLiveMove = function() self:ApplyMove(self.externalBindings[externalKey]) end,
    }
    return self.spec.MakeElement(api, opts)
end

function Controller:RegisterWithShell(api, elements, forceMovers)
    if #elements == 0 then return true end
    self.advertiseProxyMovers = forceMovers == true
    local ok = self.spec.RegisterElements(api, elements, self.spec.folder or "MidnightSimpleUnitFrames")
    self.advertiseProxyMovers = false
    return ok ~= false
end

function Controller:RegisterOneElement(api, key, cfg, batch)
    if not (api and key and cfg and type(cfg.getFrame) == "function" and type(cfg.getConf) == "function") then return false end
    local externalKey = self:ExternalKey(key)
    local previous = self.registeredByRegistryKey[key]
    if previous and previous.cfg == cfg then return true end
    if previous then
        self:ClearBindingMoveState(previous)
        local oldMover = self.externalMovers[previous.externalKey]
        if oldMover then oldMover:Hide() end
        self:DetachProxy(previous.externalKey)
        self.externalBindings[previous.externalKey] = nil
        self.registeredElements[previous.externalKey] = nil
        self.resolvedFrames[previous.externalKey] = nil
        self.spec.UnregisterElement(api, previous.externalKey)
    end
    local record = { key = key, externalKey = externalKey, cfg = cfg }
    self.externalBindings[externalKey] = record
    local element = self:BuildElement(api, key, cfg)
    if not element then self.externalBindings[externalKey] = nil return false end
    record.element = element
    self.registeredByRegistryKey[key] = record
    self.registeredElements[externalKey] = element
    local unlockActive = self.spec.IsModeActive(api)
    self:SyncProxy(externalKey, cfg, unlockActive)
    if not unlockActive then self:DetachProxy(externalKey) end
    if batch then batch[#batch + 1] = element else
        self:RegisterWithShell(api, { element }, unlockActive)
        if unlockActive then self:ScheduleMoverHooks() end
    end
    return true
end

function Controller:UnregisterOneElement(api, key)
    local record = self.registeredByRegistryKey[key]
    if not record then return end
    self:ClearBindingMoveState(record)
    local mover = self.externalMovers[record.externalKey]
    if mover then mover:Hide() end
    self:DetachProxy(record.externalKey)
    self.externalBindings[record.externalKey] = nil
    self.registeredElements[record.externalKey] = nil
    self.resolvedFrames[record.externalKey] = nil
    self.externalMovers[record.externalKey] = nil
    self.registeredByRegistryKey[key] = nil
    self.spec.UnregisterElement(api, record.externalKey)
end

function Controller:SubscribeRegistryChanges()
    local registry = EM2.Registry
    if not (registry and type(registry.RegisterChangeListener) == "function") then return false end
    return registry.RegisterChangeListener(self.listenerOwner .. ":External", function(action, key, cfg)
        if not self:IsEnabled() then return end
        local api = self:GetAPI()
        if not api then return end
        if action == "register" then self:RegisterOneElement(api, key, cfg)
        elseif action == "unregister" then self:UnregisterOneElement(api, key) end
    end) == true
end

function Controller:UnsubscribeRegistryChanges()
    local registry = EM2.Registry
    if registry and type(registry.UnregisterChangeListener) == "function" then
        registry.UnregisterChangeListener(self.listenerOwner .. ":External")
    end
end

function Controller:RegisterElements(api)
    local registry = EM2.Registry
    if not (registry and type(registry.ForEach) == "function") then return false end
    local found, batch = false, {}
    registry.ForEach(function(key, cfg)
        if self:RegisterOneElement(api, key, cfg, batch) then found = true end
    end)
    if #batch > 0 then
        local unlockActive = self.spec.IsModeActive(api)
        self:RegisterWithShell(api, batch, unlockActive)
        if unlockActive then self:ScheduleMoverHooks() end
    end
    return found
end

function Controller:EnsureSessionMovers(api)
    for externalKey, binding in pairs(self.externalBindings) do
        if binding.entryPrepared then binding.entryPrepared = nil
        else self:SyncProxy(externalKey, binding.cfg, true) end
    end

    --- The shell usually built its movers while opening. Discover those first
    --- so the initial session does not re-register every MSUF element.
    self:HookMovers(true)
    local missing = {}
    for externalKey, binding in pairs(self.externalBindings) do
        if self.externalMovers[externalKey] == nil then missing[#missing + 1] = binding.element end
    end
    if #missing > 0 then
        self:RegisterWithShell(api, missing, true)
        self:HookMovers(true)
    end
end

function Controller:MarkShellDirty()
    if self.shellDirtyMarked or not self:IsSessionReady() then return self.shellDirtyMarked end
    local api, mover = self:GetAPI()
    for externalKey in pairs(self.externalBindings) do
        local candidate = self.externalMovers[externalKey]
        if candidate and candidate:IsShown() then mover = candidate break end
        mover = mover or candidate
    end
    if not mover then self:HookMovers() end
    if not mover then local _, first = next(self.externalMovers); mover = first end
    if not mover then return false end
    local binding = self.externalBindings[self.spec.GetMoverKey(mover)]
    local proxy = binding and self.resolvedFrames[binding.externalKey]
    if proxy then proxy[self:Field("ProxySyncing")] = true end
    self.shellDirtyMarked = true
    local ok = self.spec.MarkDirty(api, mover)
    if proxy then
        proxy[self:Field("ProxySyncing")] = nil
        self:SyncProxy(binding.externalKey, binding.cfg, true)
    end
    if not ok then self.shellDirtyMarked = false end
    return ok
end

function Controller:OnMSUFEditChange(category, key)
    if self.bridgeUndoDepth > 0 or not self:IsSessionReady() then return end
    self.sessionDirty = true
    self:MarkShellDirty()
    if category == "castbar" then self.editReconcileCastbars[key] = true end
    if self.editReconcilePending then return end
    self.editReconcilePending = true
    local generation = self.sessionGeneration
    local function reconcile()
        if generation ~= self.sessionGeneration then return end
        self.editReconcilePending = false
        if not self:IsSessionReady() then return end
        for unit in pairs(self.editReconcileCastbars) do
            self.editReconcileCastbars[unit] = nil
            self:ScheduleCastbarMoverSync(unit)
        end
        self:HookMovers()
    end
    local timer = _G.C_Timer
    if timer and type(timer.After) == "function" then timer.After(0, reconcile) else reconcile() end
end

function Controller:InstallDirtyHooks()
    if self.dirtyHooked or type(_G.hooksecurefunc) ~= "function" then return self.dirtyHooked end
    if type(_G.MSUF_EM_UndoBeforeChange) ~= "function" then return false end
    _G.hooksecurefunc("MSUF_EM_UndoBeforeChange", function(category, key)
        self:OnMSUFEditChange(category, key)
    end)
    self.dirtyHooked = true
    return true
end

function Controller:InvalidateDeferredWork()
    self.sessionGeneration = self.sessionGeneration + 1
    self.moverHookScheduled = false
    self.editReconcilePending = false
    for unit in pairs(self.editReconcileCastbars) do self.editReconcileCastbars[unit] = nil end
    for unit in pairs(self.pendingCastbarMoverSync) do self.pendingCastbarMoverSync[unit] = nil end
end

function Controller:ScheduleMenuPreviewReconcile()
    self.menuPreviewReconcileSerial = self.menuPreviewReconcileSerial + 1
    local serial = self.menuPreviewReconcileSerial
    local function reconcile()
        if serial ~= self.menuPreviewReconcileSerial then return end
        local api = self:GetAPI()
        if api and self.spec.IsModeActive(api) then return end
        local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
        local activeKey = menu and menu.activeKey
        if menu and type(menu.RequestOrRefresh) == "function" then
            pcall(menu.RequestOrRefresh, nil, self.spec.menuRefreshReason or "external-edit-close")
        end
        if menu and type(menu.RequestBossPagePreviewForKey) == "function" then
            pcall(menu.RequestBossPagePreviewForKey, activeKey, true)
        end
        if menu and type(menu.RequestGFPagePreviewForKey) == "function" then
            pcall(menu.RequestGFPagePreviewForKey, activeKey, true)
        end
        if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
            pcall(_G.MSUF_UFPreview_RequestRefresh, self.spec.previewRefreshReason or "MSUF_EXTERNAL_EDIT_CLOSE")
        end
        if menu and type(menu.RefreshGFNativePreviews) == "function" then
            pcall(menu.RefreshGFNativePreviews, self.spec.previewRefreshReason or "MSUF_EXTERNAL_EDIT_CLOSE")
        end
    end
    local timer = _G.C_Timer
    if timer and type(timer.After) == "function" then timer.After(0, reconcile) else reconcile() end
end

function Controller:Suspend()
    self:InvalidateDeferredWork()
    self.sessionActive = false
    self:ClearMoveState()
    return true
end

function Controller:Resume()
    local api = self:GetAPI()
    if not (api and self:IsEnabled() and self.spec.IsModeActive(api)) then return false end
    self:InvalidateDeferredWork()
    self.sessionActive = true
    self:EnsureSessionMovers(api)
    self:ScheduleMoverHooks()
    if self.sessionDirty then self:MarkShellDirty() end
    return true
end

function Controller:OnModeChanged(active, closeAction)
    local state = EM2.State
    if not state then return end
    if active == true and self:IsEnabled() then
        if state.IsActive() and state.GetProvider and state.GetProvider() ~= self.id then
            state.Exit(self.id .. "-handoff")
        end
        local alreadyExternal = state.IsActive() and state.GetProvider and state.GetProvider() == self.id
        local suspended = state.IsExternalPreviewSuspended and state.IsExternalPreviewSuspended()
        if alreadyExternal and (self.sessionActive or suspended or InCombat()) then
            self.pendingUnitKey = nil
            return
        end
        if not alreadyExternal and state.Enter(self.pendingUnitKey, { provider = self.id }) ~= true then return end
        self.pendingUnitKey = nil
        self:InvalidateDeferredWork()
        self.shellDirtyMarked = false
        self.sessionDirty = false
        self.sessionActive = true
        local api = self:GetAPI()
        if api then
            self:EnsureSessionMovers(api)
            self:ScheduleMoverHooks()
        end
    elseif active ~= true then
        self:InvalidateDeferredWork()
        self.sessionActive = false
        self:ClearMoveState()
        self:DetachAllProxies()
        if state.IsActive() and state.GetProvider and state.GetProvider() == self.id then
            local discard = closeAction == "discard"
                or (closeAction == "exit" and (self.shellDirtyMarked or self.sessionDirty))
            if discard then state.CancelAll()
            else state.Exit(closeAction == "save" and (self.id .. "-save") or (self.id .. "-exit")) end
        end
        self.shellDirtyMarked = false
        self.sessionDirty = false
        self:ScheduleMenuPreviewReconcile()
    end
end

function Controller:UnregisterElements(api)
    self.sessionActive = false
    self:InvalidateDeferredWork()
    self:ClearMoveState()
    if not InCombat() then self:DetachAllProxies() end
    if next(self.registeredByRegistryKey) == nil then return end
    local keys = {}
    for externalKey in pairs(self.registeredElements) do keys[#keys + 1] = externalKey end
    for _, mover in pairs(self.externalMovers) do mover:Hide() end
    for _, regions in pairs(self.supplementalFrames) do
        for i = 1, #regions do regions[i]:Hide() end
    end
    self.externalBindings, self.resolvedFrames, self.sourceFrames, self.externalMovers = {}, {}, {}, {}
    for i = 1, #keys do self.spec.UnregisterElement(api, keys[i]) end
    self.registeredElements, self.registeredByRegistryKey = {}, {}
end

function Controller:Initialize()
    local api = self:GetAPI()
    if not api then return false end
    if self.initialized then return true end
    self.initialized = true
    if self:IsEnabled() then
        self:InstallDirtyHooks()
        self.spec.RegisterModeListener(api, self.listenerOwner, self.modeListener)
        self.listenerRegistered = true
        self:SubscribeRegistryChanges()
        self:RegisterElements(api)
    end
    return true
end

function Controller:SetEnabled(enabled)
    if self.spec.SetEnabledValue then self.spec.SetEnabledValue(enabled ~= false) end
    local api = self:GetAPI()
    if not api then return false end
    self.initialized = true
    if enabled ~= false then
        self:InstallDirtyHooks()
        if not self.listenerRegistered then
            self.spec.RegisterModeListener(api, self.listenerOwner, self.modeListener)
            self.listenerRegistered = true
        end
        self:SubscribeRegistryChanges()
        self:RegisterElements(api)
    else
        if self.listenerRegistered then
            self.spec.UnregisterModeListener(api, self.listenerOwner)
            self.listenerRegistered = false
        end
        self:UnsubscribeRegistryChanges()
        self:UnregisterElements(api)
        local state = EM2.State
        if state and state.IsActive() and state.GetProvider and state.GetProvider() == self.id then
            state.Exit(self.id .. "-disabled")
            self:ScheduleMenuPreviewReconcile()
        end
    end
    return true
end

function Controller:Open(unitKey)
    if not self:IsEnabled() or not self:Initialize() then return false end
    local api, state = self:GetAPI(), EM2.State
    if not (api and state and self.spec.PrepareOpen(api)) then return false end
    self.pendingUnitKey = unitKey
    if state.IsActive() and state.GetProvider and state.GetProvider() ~= self.id then
        state.Exit(self.id .. "-handoff")
    end
    if not state.IsActive() then
        if state.Enter(unitKey, { provider = self.id }) ~= true then return false end
    elseif unitKey then
        state.SetUnitKey(unitKey)
    end
    if not self.spec.IsModeActive(api) then
        local ok = self.spec.OpenMode(api)
        if not ok or not self.spec.IsModeActive(api) then
            self.pendingUnitKey = nil
            state.Exit(self.id .. "-open-failed")
            return false
        end
    end
    self.pendingUnitKey = nil
    self:ScheduleMoverHooks()
    return true
end

function Controller:Close()
    local state = EM2.State
    if not (state and state.IsActive() and state.GetProvider and state.GetProvider() == self.id) then return false end
    local api = self:GetAPI()
    if api and self.spec.IsModeActive(api) and self.spec.CloseMode(api) then return true end
    self.sessionActive = false
    self:InvalidateDeferredWork()
    self:ClearMoveState()
    if not InCombat() then self:DetachAllProxies() end
    state.Exit(self.id .. "-direct")
    self:ScheduleMenuPreviewReconcile()
    return true
end

function External.Register(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then return nil end
    local controller = providers[spec.id]
    if controller then return controller end
    controller = setmetatable({
        id = spec.id,
        spec = spec,
        listenerOwner = spec.listenerOwner or spec.id,
        registeredElements = {}, registeredByRegistryKey = {}, externalBindings = {},
        resolvedFrames = {}, sourceFrames = {}, externalMovers = {}, proxyFrames = {}, supplementalFrames = {},
        initialized = false, listenerRegistered = false, sessionActive = false,
        sessionGeneration = 0, dirtyHooked = false, shellDirtyMarked = false, sessionDirty = false,
        bridgeUndoDepth = 0, advertiseProxyMovers = false, moverHookScheduled = false,
        pendingCastbarMoverSync = {}, editReconcileCastbars = {}, editReconcilePending = false,
        menuPreviewReconcileSerial = 0,
    }, Controller)
    controller.modeListener = function(active, action) controller:OnModeChanged(active, action) end
    providers[spec.id] = controller
    return controller
end

function External.Get(id) return providers[id] end
function External.IsAvailable(id)
    local controller = providers[id]
    return controller and controller:GetAPI() ~= nil or false
end
function External.Initialize(id)
    local controller = providers[id]
    return controller and controller:Initialize() or false
end
function External.SetEnabled(id, enabled)
    local controller = providers[id]
    return controller and controller:SetEnabled(enabled) or false
end
function External.Open(id, key)
    local controller = providers[id]
    return controller and controller:Open(key) or false
end
function External.Close(id)
    local controller = providers[id]
    return controller and controller:Close() or false
end
function External.Suspend(id)
    local controller = providers[id]
    return controller and controller:Suspend() or false
end
function External.Resume(id)
    local controller = providers[id]
    return controller and controller:Resume() or false
end
function External.ClearMoveState(id)
    local controller = providers[id]
    if not controller then return false end
    controller:ClearMoveState()
    return true
end
