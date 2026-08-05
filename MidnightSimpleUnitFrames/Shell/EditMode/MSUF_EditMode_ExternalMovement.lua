local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local EM2 = _G.MSUF_EM2
local External = EM2 and EM2.ExternalProviders
local Controller = External and External.Controller
local Shared = External and External.Shared
if not (Controller and Shared) then return end

--- Session-scoped movement bridge. It reuses MSUF's native drag engine while
--- the external shell owns cursor tracking; no event, ticker, or idle frame loop.
local CASTBAR_FIELDS = Shared.CASTBAR_FIELDS
local InCombat = Shared.InCombat
local FrameRectToUI = Shared.FrameRectToUI
local FrameCenterUI = Shared.FrameCenterUI
local ExpandBounds = Shared.ExpandBounds

function Controller:ElementBounds(cfg, source)
    local bounds
    local movers = EM2.Movers
    if type(cfg and cfg.getMoverBounds) == "function" then
        local ok, left, right, top, bottom = pcall(cfg.getMoverBounds)
        if ok then bounds = ExpandBounds(bounds, left, right, top, bottom) end
    elseif self:IsUnitConfig(cfg) and movers and type(movers.GetUnitVisualBounds) == "function" then
        local ok, left, right, top, bottom = pcall(movers.GetUnitVisualBounds, source)
        if ok then bounds = ExpandBounds(bounds, left, right, top, bottom) end
    end
    if not bounds then bounds = ExpandBounds(bounds, FrameRectToUI(source)) end
    return bounds
end

function Controller:EnsureProxy(externalKey)
    local proxy = self.proxyFrames[externalKey]
    if proxy then return proxy end
    if not (_G.CreateFrame and _G.UIParent) then return nil end
    proxy = _G.CreateFrame("Frame", nil, _G.UIParent)
    proxy[self:Field("ExternalKey")] = externalKey
    proxy._msufExternalController = self
    proxy:SetSize(1, 1)
    proxy:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
    if proxy.SetScale then proxy:SetScale(1) end
    if proxy.SetAlpha then proxy:SetAlpha(0) end
    if proxy.EnableMouse then proxy:EnableMouse(false) end
    proxy:Show()
    self.proxyFrames[externalKey] = proxy
    if type(_G.hooksecurefunc) == "function" then
        _G.hooksecurefunc(proxy, "SetPoint", function(...)
            self:OnProxySetPoint(proxy, ...)
        end)
    end
    return proxy
end

function Controller:HistoryIdentity(binding)
    local unit = binding and self:CastbarUnit(binding.cfg, binding.key)
    if unit then return "castbar", unit end
    if binding and self:IsGroupConfig(binding.cfg) then
        return "gf", tostring(binding.key):gsub("^gf_", "")
    end
    return "unit", binding and binding.key
end

function Controller:BridgeUndoCall(func, ...)
    if type(func) ~= "function" then return false end
    self.bridgeUndoDepth = self.bridgeUndoDepth + 1
    local ok, result = pcall(func, ...)
    self.bridgeUndoDepth = self.bridgeUndoDepth - 1
    return ok and result ~= false
end

function Controller:CaptureMoveStart(binding)
    local frame = binding and self.resolvedFrames[binding.externalKey]
    local conf = binding and binding.cfg and binding.cfg.getConf and binding.cfg.getConf() or nil
    local centerX, centerY = FrameCenterUI(frame)
    if not frame or type(conf) ~= "table" or centerX == nil or centerY == nil then return nil end
    local start = {
        centerX = centerX, centerY = centerY,
        offsetX = tonumber(conf.offsetX) or 0,
        offsetY = tonumber(conf.offsetY) or 0,
        bar = self.sourceFrames[binding.externalKey],
    }
    local unit = self:CastbarUnit(binding.cfg, binding.key)
    if unit then
        local fields = CASTBAR_FIELDS[unit]
        start.castbarX = tonumber(conf[fields.x])
        start.castbarY = tonumber(conf[fields.y])
    end
    return start
end

function Controller:DragAdapter()
    local ticker = EM2.Ticker
    if ticker and type(ticker.BeginExternalDrag) == "function"
        and type(ticker.ApplyExternalDrag) == "function"
        and type(ticker.EndExternalDrag) == "function" then
        return ticker
    end
end

function Controller:BeginMove(binding)
    if not binding or not self:IsSessionReady() then return false end
    if binding.externalDrag then return true end
    local ticker = self:DragAdapter()
    local frame = self.resolvedFrames[binding.externalKey]
    if not (ticker and frame) then return false end
    binding.externalDrag = ticker.BeginExternalDrag(frame, binding.key, binding.cfg,
        binding.moveStart or self:CaptureMoveStart(binding))
    if not binding.externalDrag then return false end
    binding.externalApplied = false
    local category, historyKey = self:HistoryIdentity(binding)
    binding.historyChange = self:BridgeUndoCall(_G.MSUF_EM_UndoBeginChange,
        category, historyKey, "Move")
    return true
end

function Controller:ApplyMove(binding)
    local ticker = self:DragAdapter()
    if not ticker or not self:BeginMove(binding) then return false end
    local applied = ticker.ApplyExternalDrag(binding.externalDrag) == true
    binding.externalApplied = binding.externalApplied or applied
    return applied
end

function Controller:MoveChanged(binding)
    local drag = binding and binding.externalDrag
    if not drag then return false end
    local centerX, centerY = FrameCenterUI(drag.mover)
    if centerX == nil or centerY == nil then return false end
    local uiScale = _G.UIParent and _G.UIParent.GetEffectiveScale and _G.UIParent:GetEffectiveScale() or 1
    return math.abs(centerX - (drag.startCX or centerX)) * uiScale > 0.5
        or math.abs(centerY - (drag.startCY or centerY)) * uiScale > 0.5
end

function Controller:FinishMove(binding, applyFinal)
    if not binding or not binding.externalDrag then return false end
    local ticker = self:DragAdapter()
    local moved = self:MoveChanged(binding)
    local applied = binding.externalApplied == true
    if ticker then
        applied = ticker.EndExternalDrag(binding.externalDrag, applyFinal ~= false) == true or applied
    end
    local changed = moved and applied
    binding.externalDrag = nil
    binding.externalApplied = nil
    if changed then
        self.sessionDirty = true
        self:ApplyKey(binding.key)
        if binding.historyChange then self:BridgeUndoCall(_G.MSUF_EM_UndoCommitChange) end
    elseif binding.historyChange and EM2.Undo and EM2.Undo.CancelChange then
        EM2.Undo.CancelChange()
    end
    binding.historyChange = nil
    self:SyncProxy(binding.externalKey, binding.cfg, true)
    binding.moveStart = self:CaptureMoveStart(binding)
    return changed
end

function Controller:ClearBindingMoveState(binding)
    if not binding then return end
    local changed = binding.externalDrag and binding.externalApplied == true and self:MoveChanged(binding)
    local mover = self.externalMovers[binding.externalKey]
    local downXField, downYField = self:Field("DownX"), self:Field("DownY")
    local wasDragField = self:Field("WasDrag")
    local mouseHeld = mover and mover[downXField] ~= nil
    local nativeDragging = mover and self.spec.IsMoverDragging and self.spec.IsMoverDragging(mover)
    if mover then
        if self.spec.AbortMover then self.spec.AbortMover(mover, nativeDragging or mouseHeld) end
        mover[downXField], mover[downYField], mover[wasDragField] = nil, nil, nil
    end
    local ticker = self:DragAdapter()
    if ticker and binding.externalDrag then ticker.EndExternalDrag(binding.externalDrag, false) end
    if binding.historyChange and EM2.Undo and EM2.Undo.CancelChange then EM2.Undo.CancelChange() end
    binding.externalDrag = nil
    binding.externalApplied = nil
    binding.historyChange = nil
    binding.moveStart = nil
    if changed then self.sessionDirty = true end
end

function Controller:ClearMoveState()
    for _, binding in pairs(self.externalBindings) do self:ClearBindingMoveState(binding) end
end

function Controller:SyncProxy(externalKey, cfg, resolveSource)
    local proxy = self:EnsureProxy(externalKey)
    if not proxy then return nil end
    proxy:Show()
    local source = self.sourceFrames[externalKey]
    local freshSourceMissing = false
    if resolveSource and cfg and type(cfg.getFrame) == "function" then
        local ok, current = pcall(cfg.getFrame)
        if ok then
            freshSourceMissing = current == nil
            if current then source = current end
        end
    end
    self.sourceFrames[externalKey] = source

    local bounds = source and self:ElementBounds(cfg, source) or nil
    local key = tostring(externalKey):gsub("^" .. (self.spec.externalPrefix or "MSUF_"), "")
    local syncingField = self:Field("ProxySyncing")
    proxy[syncingField] = true
    if proxy.SetScale then proxy:SetScale(1) end
    if bounds then
        local width = math.max(2, bounds[2] - bounds[1])
        local height = math.max(2, bounds[3] - bounds[4])
        local centerX, centerY = (bounds[1] + bounds[2]) * 0.5, (bounds[3] + bounds[4]) * 0.5
        local sourceX, sourceY = FrameCenterUI(source)
        proxy:SetSize(width, height)
        proxy:ClearAllPoints()
        if sourceX and sourceY then
            local offsetX, offsetY = centerX - sourceX, centerY - sourceY
            proxy:SetPoint("CENTER", source, "CENTER", offsetX, offsetY)
            proxy[self:Field("Owner")] = source
            proxy[self:Field("OwnerOffsetX")] = offsetX
            proxy[self:Field("OwnerOffsetY")] = offsetY
            proxy[self:Field("OwnerAnchored")] = true
        else
            proxy:SetPoint("CENTER", _G.UIParent, "BOTTOMLEFT", centerX, centerY)
            proxy[self:Field("Owner")] = nil
            proxy[self:Field("OwnerAnchored")] = false
        end
    else
        local width, height = self:ConfigSize(cfg, key)
        local x, y = self:StoredFallback(cfg, key)
        proxy:SetSize(math.max(2, width), math.max(2, height))
        proxy:ClearAllPoints()
        proxy:SetPoint("CENTER", _G.UIParent, "CENTER", x, y)
        proxy[self:Field("Owner")] = nil
        proxy[self:Field("OwnerAnchored")] = false
    end
    proxy[syncingField] = nil
    self.resolvedFrames[externalKey] = proxy
    local binding = self.externalBindings[externalKey]
    if binding and not binding.externalDrag then binding.moveStart = self:CaptureMoveStart(binding) end
    return proxy, source, freshSourceMissing
end

function Controller:DetachProxy(externalKey)
    local proxy = self.proxyFrames[externalKey]
    if not proxy then return end
    proxy[self:Field("ProxySyncing")] = true
    proxy:ClearAllPoints()
    proxy[self:Field("Owner")] = nil
    proxy[self:Field("OwnerOffsetX")] = nil
    proxy[self:Field("OwnerOffsetY")] = nil
    proxy[self:Field("OwnerAnchored")] = false
    proxy[self:Field("ProxySyncing")] = nil
    proxy:Hide()
    self.sourceFrames[externalKey] = nil
    local regions = self.supplementalFrames[externalKey]
    if regions then for i = 1, #regions do regions[i]:Hide() end end
end

function Controller:DetachAllProxies()
    for externalKey in pairs(self.proxyFrames) do self:DetachProxy(externalKey) end
end

function Controller:OnProxySetPoint(proxy, arg1, arg2, arg3, arg4, arg5, arg6)
    if proxy[self:Field("ProxySyncing")] or not self.sessionActive or InCombat() then return end
    local point, relativeTo, relativePoint, x, y
    if arg1 == proxy then
        point, relativeTo, relativePoint, x, y = arg2, arg3, arg4, arg5, arg6
    else
        point, relativeTo, relativePoint, x, y = arg1, arg2, arg3, arg4, arg5
    end
    local externalKey = proxy[self:Field("ExternalKey")]
    local binding = self.externalBindings[externalKey]
    if not binding then return end
    local mover = self.externalMovers[externalKey]
    local gestureActive = mover and ((self.spec.IsMoverDragging and self.spec.IsMoverDragging(mover))
        or mover[self:Field("WasDrag")])
    if gestureActive then
        if relativeTo == _G.UIParent then proxy[self:Field("OwnerAnchored")] = false end
        return
    end
    if not self:IsSessionReady() then return end

    if proxy[self:Field("OwnerAnchored")] and point == "CENTER"
        and relativeTo == _G.UIParent and relativePoint == "CENTER" then
        local owner = proxy[self:Field("Owner")]
        local ownerOffsetX = tonumber(proxy[self:Field("OwnerOffsetX")]) or 0
        local ownerOffsetY = tonumber(proxy[self:Field("OwnerOffsetY")]) or 0
        local ownerX, ownerY = FrameCenterUI(owner)
        if ownerX and ownerY then
            local start = self:CaptureMoveStart(binding)
            if start then
                start.centerX, start.centerY = ownerX + ownerOffsetX, ownerY + ownerOffsetY
                binding.moveStart = start
            end
            proxy[self:Field("ProxySyncing")] = true
            proxy:ClearAllPoints()
            proxy:SetPoint("CENTER", _G.UIParent, "BOTTOMLEFT",
                ownerX + (tonumber(x) or ownerOffsetX), ownerY + (tonumber(y) or ownerOffsetY))
            proxy[self:Field("ProxySyncing")] = nil
            proxy[self:Field("OwnerAnchored")] = false
        end
    elseif relativeTo == _G.UIParent then
        proxy[self:Field("OwnerAnchored")] = false
    end

    self:ApplyMove(binding)
    self:FinishMove(binding, false)
end

function Controller:ClearPosition(externalKey, cfg, key)
    local binding = self.externalBindings[externalKey]
    local category, historyKey = self:HistoryIdentity(binding)
    if self:IsGroupConfig(cfg) and type(_G.MSUF_GF_EM2_ResetPosition) == "function" then
        self:BridgeUndoCall(_G.MSUF_GF_EM2_ResetPosition, tostring(key):gsub("^gf_", ""))
        self.sessionDirty = true
        self:SyncProxy(externalKey, cfg, true)
        return
    end
    local create = (MSUF and MSUF.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
    local defaults = type(create) == "function" and create() or nil
    local conf = cfg and cfg.getConf and cfg.getConf() or nil
    if type(defaults) ~= "table" or type(conf) ~= "table" then return end
    self:BridgeUndoCall(_G.MSUF_EM_UndoBeforeChange, category, historyKey)
    local unit = self:CastbarUnit(cfg, key)
    if unit then
        local fields = CASTBAR_FIELDS[unit]
        local defaultGeneral = defaults.general or {}
        conf[fields.x], conf[fields.y] = defaultGeneral[fields.x], defaultGeneral[fields.y]
    else
        local defaultConf = defaults[key] or {}
        conf.offsetX, conf.offsetY = defaultConf.offsetX, defaultConf.offsetY
    end
    self.sessionDirty = true
    self:ApplyKey(key)
    self:SyncProxy(externalKey, cfg, true)
end

function Controller:OpenNativePopup(key, cfg, parent)
    if not (self:CastbarUnit(cfg, key) or self:IsGroupConfig(cfg) or self:IsUnitConfig(cfg)) then return false end
    local state = EM2.State
    if state and state.SetUnitKey then state.SetUnitKey(key) end
    if EM2.Popups and type(EM2.Popups.Open) == "function" then
        EM2.Popups.Open(key, parent)
        return true
    end
    return false
end

local function MoverController(frame)
    return frame and frame._msufExternalController
end

local function MoverMouseDown(mover, button)
    local controller = MoverController(mover)
    if controller then controller:OnMoverMouseDown(mover, button) end
end

local function MoverDragStart(mover)
    local controller = MoverController(mover)
    if controller then controller:OnMoverDragStart(mover) end
end

local function MoverDragStop(mover)
    local controller = MoverController(mover)
    if controller then controller:OnMoverDragStop(mover) end
end

local function MoverMouseUp(mover, button)
    local controller = MoverController(mover)
    if controller then controller:OnMoverMouseUp(mover, button) end
end

local function MoverHide(mover)
    local controller = MoverController(mover)
    if controller then controller:OnMoverHide(mover) end
end

local function ForwardSupplemental(region, scriptName, ...)
    local controller = MoverController(region)
    if controller then controller:ForwardMoverScript(region, scriptName, ...) end
end

local function SupplementalOnEnter(self) ForwardSupplemental(self, "OnEnter") end
local function SupplementalOnLeave(self) ForwardSupplemental(self, "OnLeave") end
local function SupplementalOnMouseDown(self, button) ForwardSupplemental(self, "OnMouseDown", button) end
local function SupplementalOnMouseUp(self, button) ForwardSupplemental(self, "OnMouseUp", button) end
local function SupplementalOnDragStart(self) ForwardSupplemental(self, "OnDragStart", "LeftButton") end
local function SupplementalOnDragStop(self) ForwardSupplemental(self, "OnDragStop", "LeftButton") end
local function SupplementalOnClick(self, button) ForwardSupplemental(self, "OnClick", button) end

function Controller:OnMoverMouseDown(mover, button)
    if button ~= "LeftButton" or not self:IsSessionReady() then return end
    if self.spec.SyncMover then self.spec.SyncMover(mover) end
    local x, y = 0, 0
    if type(_G.GetCursorPosition) == "function" then x, y = _G.GetCursorPosition() end
    mover[self:Field("DownX")], mover[self:Field("DownY")] = x, y
    mover[self:Field("WasDrag")] = false
    local binding = self.externalBindings[self.spec.GetMoverKey(mover)]
    if binding then binding.moveStart = self:CaptureMoveStart(binding) end
end

function Controller:OnMoverDragStart(mover)
    mover[self:Field("WasDrag")] = true
    self:BeginMove(self.externalBindings[self.spec.GetMoverKey(mover)])
end

function Controller:OnMoverDragStop(mover)
    mover[self:Field("WasDrag")] = true
    self:FinishMove(self.externalBindings[self.spec.GetMoverKey(mover)], true)
end

function Controller:OnMoverMouseUp(mover, button)
    local downXField, downYField = self:Field("DownX"), self:Field("DownY")
    if button ~= "LeftButton" or mover[downXField] == nil then return end
    local wasDrag = mover[self:Field("WasDrag")] == true
    if not wasDrag and type(_G.GetCursorPosition) == "function" then
        local x, y = _G.GetCursorPosition()
        wasDrag = math.abs(x - mover[downXField]) > 3 or math.abs(y - mover[downYField]) > 3
    end
    mover[downXField], mover[downYField], mover[self:Field("WasDrag")] = nil, nil, nil
    local binding = self.externalBindings[self.spec.GetMoverKey(mover)]
    if wasDrag then
        if binding and binding.externalDrag then self:FinishMove(binding, true) end
        return
    end
    if binding then
        self:ClearBindingMoveState(binding)
        self:SyncProxy(binding.externalKey, binding.cfg, true)
        self:OpenNativePopup(binding.key, binding.cfg, mover)
    end
end

function Controller:OnMoverHide(mover)
    self:ClearBindingMoveState(self.externalBindings[self.spec.GetMoverKey(mover)])
end

function Controller:ForwardMoverScript(region, scriptName, ...)
    local mover = region._msufExternalPrimaryMover
    local handler = mover and mover.GetScript and mover:GetScript(scriptName)
    if handler then handler(mover, ...) end
    if scriptName == "OnMouseDown" then self:OnMoverMouseDown(mover, ...)
    elseif scriptName == "OnMouseUp" then self:OnMoverMouseUp(mover, ...)
    elseif scriptName == "OnDragStart" then self:OnMoverDragStart(mover)
    elseif scriptName == "OnDragStop" then self:OnMoverDragStop(mover) end
end

function Controller:SyncSupplementalRegions(binding, mover)
    local getBounds = binding and binding.cfg and binding.cfg.getSupplementalMoverBounds
    if type(getBounds) ~= "function" then return end
    local ok, bounds = pcall(getBounds)
    if not ok then bounds = nil end
    local regions = self.supplementalFrames[binding.externalKey] or {}
    self.supplementalFrames[binding.externalKey] = regions
    local proxy = self.resolvedFrames[binding.externalKey]
    local proxyX, proxyY = FrameCenterUI(proxy)
    local count = type(bounds) == "table" and #bounds or 0
    for i = 1, count do
        local region = regions[i]
        if not region then
            region = _G.CreateFrame("Button", nil, self.spec.GetRoot() or _G.UIParent)
            region:RegisterForDrag("LeftButton")
            if region.RegisterForClicks then region:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
            region:EnableMouse(true)
            region:SetScript("OnEnter", SupplementalOnEnter)
            region:SetScript("OnLeave", SupplementalOnLeave)
            region:SetScript("OnMouseDown", SupplementalOnMouseDown)
            region:SetScript("OnMouseUp", SupplementalOnMouseUp)
            region:SetScript("OnDragStart", SupplementalOnDragStart)
            region:SetScript("OnDragStop", SupplementalOnDragStop)
            region:SetScript("OnClick", SupplementalOnClick)
            region._msufExternalController = self
            regions[i] = region
        end
        region._msufExternalPrimaryMover = mover
        region[self:Field("PrimaryMover")] = mover
        if region.SetFrameStrata and mover.GetFrameStrata then region:SetFrameStrata(mover:GetFrameStrata()) end
        if region.SetFrameLevel and mover.GetFrameLevel then region:SetFrameLevel(mover:GetFrameLevel()) end
        local rect = bounds and bounds[i]
        local left, right = rect and (rect.l or rect[1]), rect and (rect.r or rect[2])
        local top, bottom = rect and (rect.t or rect[3]), rect and (rect.b or rect[4])
        if proxyX and proxyY and left and right and top and bottom and not self:IsElementHidden(binding.key, binding.cfg) then
            region:ClearAllPoints()
            region:SetSize(math.max(2, right - left), math.max(2, top - bottom))
            region:SetPoint("CENTER", proxy, "CENTER", (left + right) * 0.5 - proxyX, (top + bottom) * 0.5 - proxyY)
            region:Show()
        else
            region:Hide()
        end
    end
    for i = count + 1, #regions do regions[i]:Hide() end
end

function Controller:HookMovers(skipProxySync)
    local api, root = self:GetAPI(), self.spec.GetRoot()
    if not (api and self:IsEnabled() and self.spec.IsModeActive(api) and root and root.GetChildren) then return end
    if not skipProxySync then
        for externalKey, binding in pairs(self.externalBindings) do
            if not binding.externalDrag then self:SyncProxy(externalKey, binding.cfg, true) end
        end
    end
    local children = { root:GetChildren() }
    for i = 1, #children do
        local mover = children[i]
        local externalKey = self.spec.GetMoverKey(mover)
        local binding = self.externalBindings[externalKey]
        if binding then
            self.externalMovers[externalKey] = mover
            mover._msufExternalController = self
        end
        if binding and not binding.externalDrag then
            if self:IsElementHidden(binding.key, binding.cfg) then
                mover:Hide()
            else
                if self.spec.SyncMover then self.spec.SyncMover(mover) end
                mover:Show()
            end
            self:SyncSupplementalRegions(binding, mover)
        end
        if binding and mover.HookScript and mover._msufExternalBridgeProvider ~= self.id then
            mover._msufExternalBridgeProvider = self.id
            mover:HookScript("OnMouseDown", MoverMouseDown)
            mover:HookScript("OnDragStart", MoverDragStart)
            mover:HookScript("OnDragStop", MoverDragStop)
            mover:HookScript("OnMouseUp", MoverMouseUp)
            mover:HookScript("OnHide", MoverHide)
        end
    end
end

function Controller:SyncCastbarMover(unit)
    if not CASTBAR_FIELDS[unit] or InCombat() then return false end
    local api = self:GetAPI()
    if not (api and self:IsEnabled() and self.spec.IsModeActive(api)) then return false end
    if type(_G.MSUF_PositionCastbarPreviewUnit) == "function" then
        pcall(_G.MSUF_PositionCastbarPreviewUnit, unit)
    end
    local externalKey = self:ExternalKey("castbar_" .. unit)
    local binding = self.externalBindings[externalKey]
    local sourceMissing = false
    if binding then
        local _, _, missing = self:SyncProxy(externalKey, binding.cfg, true)
        sourceMissing = missing
    end
    if sourceMissing then return false end
    local mover = self.externalMovers[externalKey]
    if not mover then
        self:HookMovers()
        mover = self.externalMovers[externalKey]
    end
    if not mover then
        self:ScheduleMoverHooks()
        return false
    end
    if self.spec.SyncMover then self.spec.SyncMover(mover) end
    if self.spec.RefreshMover then self.spec.RefreshMover(mover) end
    return true
end

function Controller:ScheduleCastbarMoverSync(unit)
    unit = tostring(unit or ""):match("^(boss)%d*$") or unit
    if InCombat() or not CASTBAR_FIELDS[unit] or self.pendingCastbarMoverSync[unit] then return end
    local api = self:GetAPI()
    if not (api and self:IsEnabled() and self.spec.IsModeActive(api)) then return end
    self.pendingCastbarMoverSync[unit] = true
    local generation = self.sessionGeneration
    local function run()
        if generation ~= self.sessionGeneration then return end
        if InCombat() then self.pendingCastbarMoverSync[unit] = nil return end
        if self:SyncCastbarMover(unit) == true then
            self.pendingCastbarMoverSync[unit] = nil
            return
        end
        local timer = _G.C_Timer
        if timer and type(timer.After) == "function" then
            timer.After(0.15, function()
                if generation ~= self.sessionGeneration then return end
                self.pendingCastbarMoverSync[unit] = nil
                if not InCombat() then self:SyncCastbarMover(unit) end
            end)
        else
            self.pendingCastbarMoverSync[unit] = nil
        end
    end
    local timer = _G.C_Timer
    if timer and type(timer.After) == "function" then timer.After(0, run) else run() end
end

function Controller:ScheduleMoverHooks()
    local api = self:GetAPI()
    if not (api and self.sessionActive and self.spec.IsModeActive(api)) or self.moverHookScheduled then return end
    self.moverHookScheduled = true
    local generation = self.sessionGeneration
    local function run()
        if generation ~= self.sessionGeneration then return end
        self.moverHookScheduled = false
        self:HookMovers()
    end
    local timer = _G.C_Timer
    if timer and type(timer.After) == "function" then timer.After(0.06, run) else run() end
end
