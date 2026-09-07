--- Auras3/EditMode_Drag: drag capture, throttled layout writes and reversible native mouse forwarding.
--- Registered at load time; the original entrypoint owns initialization order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
A3.EditModeModules = A3.EditModeModules or {}
A3.EditModeModules.Drag = function(config, layout, IsEditModeActive, IsConfigBlocked, RequestUnitFrameMenuPreview)
local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local math_max, math_abs = math.max, math.abs
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GetCursorPosition = _G.GetCursorPosition
local IsMouseButtonDown = _G.IsMouseButtonDown
local C_Timer = _G.C_Timer
local issecretvalue = _G.issecretvalue
local EM = A3.EditMode
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
-- SetOnUpdateMode takes an Enum.OnUpdateMode value, not a name; a string argument leaves the
-- driver disabled and silently kills the drag OnUpdate.
local Enum = _G.Enum
local ONUPDATE_MODE_DISABLED = (Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.Disabled) or 0
local ONUPDATE_MODE_RUN_WHEN_VISIBLE = (Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.RunWhenVisible) or 1
local AURA_DRAG_RUNTIME_INTERVAL = 0.05
local AURA_PENDING_DRAG_THRESHOLD = 3
local Round = config.Round
local NormalizeKind = config.NormalizeKind
local CustomItem = config.CustomItem
local EnsureDB = config.EnsureDB
local GetLayout = config.GetLayout
local ReadGroupConfig = config.ReadGroupConfig
local BOSS_UNITS = config.BOSS_UNITS
local ARENA_UNITS = config.ARENA_UNITS
local GROUPS = config.GROUPS
local GetFrame = layout.GetFrame
local ApplyGroupScaleForFrame = layout.ApplyGroupScaleForFrame
local PositionPreviewGroup = layout.PositionPreviewGroup
local FallbackMetrics = layout.FallbackMetrics
local function WriteOffset(auras, unit, kind, x, y)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    if spec and spec.customIndex then
        local item = CustomItem(unit, spec.customIndex, true)
        if not item then return end
        item.placed = type(item.placed) == "table" and item.placed or {}
        item.placed.x = Round(x)
        item.placed.y = Round(y)
        return
    end
    local layout = GetLayout(auras, unit, true)
    if not layout then return end
    layout[spec.xKey] = Round(x)
    layout[spec.yKey] = Round(y)
end

--- Older profiles may store only group-lane offsets/sizes. When a user drags a
--- lane in edit mode, promote the effective runtime position back into the
--- per-unit layout so future edits are stable and visible in the menu model.
local function PromoteRuntimeLayout(unit, kind)
    -- Kept as a call-site compatibility no-op. Unit lanes already persist the
    -- exact lane keys; promoting them into generic unit-wide aliases would
    -- recreate the retired Shared-era ownership path.
end

local function ApplyDragUnit(auras, unit, moverKind, x, y)
    WriteOffset(auras, unit, moverKind, x, y)
    local other = EM.groups and EM.groups[unit] and EM.groups[unit][moverKind]
    local frame = other and GetFrame(unit)
    if other and frame then
        local cfg = ReadGroupConfig(unit, moverKind)
        local metrics = type(A3.BuildAuraLaneMetrics) == "function" and A3.BuildAuraLaneMetrics(unit, moverKind) or nil
        metrics = metrics or FallbackMetrics(cfg)
        local laneW = metrics.width or cfg.size
        local laneH = metrics.height or cfg.size
        ApplyGroupScaleForFrame(other, frame)
        PositionPreviewGroup(other, frame, metrics.anchor or cfg.anchor, x, y, laneW, laneH)
    end
end

local function RefreshAffectedRuntimeUnits(unit, shared)
    if BOSS_UNITS[unit] and shared and shared.bossEditTogether ~= false then
        for i = 1, 5 do
            A3.RefreshUnit("boss" .. i)
        end
    elseif ARENA_UNITS[unit] and shared and shared.arenaEditTogether ~= false then
        for i = 1, 3 do
            A3.RefreshUnit("arena" .. i)
        end
    elseif unit then
        A3.RefreshUnit(unit)
    end
end

local function ShouldFlushDragRuntime(self, elapsed)
    self._dragRuntimeElapsed = (tonumber(self._dragRuntimeElapsed) or AURA_DRAG_RUNTIME_INTERVAL) + (tonumber(elapsed) or 0)
    if self._dragRuntimeElapsed < AURA_DRAG_RUNTIME_INTERVAL then
        self._dragRuntimePending = true
        return false
    end
    self._dragRuntimeElapsed = 0
    self._dragRuntimePending = nil
    return true
end

local function FlushDragRuntime(self, baseUnit, shared, reason, force)
    if not force and not ShouldFlushDragRuntime(self, self and self._lastDragElapsed) then return end
    RefreshAffectedRuntimeUnits(baseUnit, shared)
    RequestUnitFrameMenuPreview(reason or "AURAS3_EDITMODE_DRAG")
    local sync = _G.MSUF_SyncAuras3PositionPopup
    if type(sync) == "function" then sync(baseUnit) end
end

--- Drag writes are throttled by value equality and blocked in combat. Boss aura
--- lanes can be edited together, but the persisted value is still written to
--- each boss unit so the runtime path stays simple.
local function ApplyDragDelta(self, dx, dy, elapsed)
    if IsConfigBlocked() then return end
    local auras = self._dragAuras
    local shared = self._dragShared
    if not (auras and shared) then
        auras, shared = EnsureDB()
        self._dragAuras = auras
        self._dragShared = shared
    end
    if not auras or not shared then return end
    local startX = self._dragStartOffsetX or 0
    local startY = self._dragStartOffsetY or 0
    local x = Round(startX + dx)
    local y = Round(startY + dy)
    if self._lastDragX == x and self._lastDragY == y then return end
    self._lastDragX = x
    self._lastDragY = y
    self._lastDragElapsed = tonumber(elapsed) or 0
    local baseUnit = self._msufA3Unit
    local moverKind = self._msufA3MoverKind

    if BOSS_UNITS[baseUnit] and shared.bossEditTogether ~= false then
        for i = 1, 5 do
            ApplyDragUnit(auras, "boss" .. i, moverKind, x, y)
        end
    elseif ARENA_UNITS[baseUnit] and shared.arenaEditTogether ~= false then
        for i = 1, 3 do
            ApplyDragUnit(auras, "arena" .. i, moverKind, x, y)
        end
    elseif baseUnit then
        ApplyDragUnit(auras, baseUnit, moverKind, x, y)
    end
    FlushDragRuntime(self, baseUnit, shared, "AURAS3_EDITMODE_DRAG", false)
end

local function AuraGroupDragOnUpdate(me, elapsed)
    if not me._dragging then
        me:SetScript("OnUpdate", nil)
        if me.SetOnUpdateMode then me:SetOnUpdateMode(ONUPDATE_MODE_DISABLED) end
        return
    end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        local handler = me:GetScript("OnMouseUp")
        if handler then handler(me, "LeftButton") end
        return
    end
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local mx, my = GetCursorPosition()
    if not (mx and my) then return end
    mx, my = mx / uiScale, my / uiScale
    local dx = mx - (me._dragStartCursorX or mx)
    local dy = my - (me._dragStartCursorY or my)
    if not me._dragMoved then
        if (dx * dx + dy * dy) < 9 then return end
        me._dragMoved = true
    end

    local Snap = _G.MSUF_EM2 and _G.MSUF_EM2.Snap
    if Snap and Snap.IsEnabled and Snap.IsEnabled() and Snap.Apply then
        if Snap.HideGuides then Snap.HideGuides() end
        local sx, sy = Snap.Apply((me._snapStartCX or 0) + dx, (me._snapStartCY or 0) + dy, me._snapHW or 0, me._snapHH or 0, me._msufA3SnapName)
        dx = sx - (me._snapStartCX or 0)
        dy = sy - (me._snapStartCY or 0)
    end
    local frameScale = tonumber(me._dragFrameScale) or tonumber(me._msufA3FrameScale) or 1
    if frameScale <= 0 then frameScale = 1 end
    ApplyDragDelta(me, dx / frameScale, dy / frameScale, elapsed)
end

local activeAuraDragGroup
local pendingAuraDragFrame
local pendingAuraDragGroup
local pendingAuraDragStartX
local pendingAuraDragStartY
local auraDragCaptureFrame
local BeginAuraGroupDrag

local function OpenAuraGroupPopup(group)
    if not (group and IsEditModeActive() and not IsConfigBlocked()) then return false end
    if type(_G.MSUF_OpenAuras3PositionPopup) ~= "function" then return false end
    ExportPublic("MSUF_EM2_ActiveAuraGroup", group._msufA3MoverKind)
    ExportPublic("MSUF_EM2_ActiveAuraUnit", group._msufA3Unit)
    _G.MSUF_OpenAuras3PositionPopup(group._msufA3Unit, group)
    return true
end

local function StopAuraPendingDrag(group)
    if group and pendingAuraDragGroup and pendingAuraDragGroup ~= group then return end
    pendingAuraDragGroup = nil
    pendingAuraDragStartX = nil
    pendingAuraDragStartY = nil
    if pendingAuraDragFrame then
        pendingAuraDragFrame:SetScript("OnUpdate", nil)
        pendingAuraDragFrame:Hide()
    end
end

local function EnsureAuraPendingDragFrame()
    if pendingAuraDragFrame then return pendingAuraDragFrame end
    pendingAuraDragFrame = CreateFrame("Frame", nil, UIParent)
    pendingAuraDragFrame:Hide()
    return pendingAuraDragFrame
end

local function StopAuraDragCapture(group)
    if group and activeAuraDragGroup and activeAuraDragGroup ~= group then return end
    activeAuraDragGroup = nil
    if auraDragCaptureFrame then
        auraDragCaptureFrame:SetScript("OnUpdate", nil)
        auraDragCaptureFrame:Hide()
    end
end

local function EnsureAuraDragCaptureFrame()
    if auraDragCaptureFrame then return auraDragCaptureFrame end
    auraDragCaptureFrame = CreateFrame("Button", nil, UIParent)
    auraDragCaptureFrame:SetAllPoints(UIParent)
    auraDragCaptureFrame:SetFrameStrata("TOOLTIP")
    auraDragCaptureFrame:SetFrameLevel(1500)
    auraDragCaptureFrame:EnableMouse(true)
    if auraDragCaptureFrame.RegisterForClicks then
        auraDragCaptureFrame:RegisterForClicks("LeftButtonUp")
    end
    auraDragCaptureFrame:SetScript("OnMouseUp", function(_, button)
        local target = activeAuraDragGroup
        local handler = target and target:GetScript("OnMouseUp")
        if handler then handler(target, button) end
    end)
    auraDragCaptureFrame:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    auraDragCaptureFrame:Hide()
    return auraDragCaptureFrame
end

local function StartAuraDragCapture(group)
    if not group then return end
    activeAuraDragGroup = group
    local capture = EnsureAuraDragCaptureFrame()
    if capture.SetFrameLevel then
        capture:SetFrameLevel(math_max(1500, (group.GetFrameLevel and (group:GetFrameLevel() or 0) or 0) + 200))
    end
    capture:SetScript("OnUpdate", function(_, elapsed)
        local target = activeAuraDragGroup
        if target and target._dragging then
            AuraGroupDragOnUpdate(target, elapsed)
        else
            StopAuraDragCapture(target)
        end
    end)
    capture:Show()
end

local function QueueAuraPendingDrag(group, button)
    if button ~= "LeftButton" or not group or group._dragging then return false end
    if not IsEditModeActive() or IsConfigBlocked() then return false end
    local cx, cy = GetCursorPosition()
    if not (cx and cy) then return false end
    ExportPublic("MSUF_EM2_ActiveAuraGroup", group._msufA3MoverKind)
    ExportPublic("MSUF_EM2_ActiveAuraUnit", group._msufA3Unit)
    group._suppressNextAuraClick = nil
    pendingAuraDragGroup = group
    pendingAuraDragStartX = cx
    pendingAuraDragStartY = cy

    local frame = EnsureAuraPendingDragFrame()
    frame:SetScript("OnUpdate", function()
        local target = pendingAuraDragGroup
        if not target then
            StopAuraPendingDrag()
            return
        end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            StopAuraPendingDrag(target)
            return
        end
        if not IsEditModeActive() or IsConfigBlocked() or (target.IsShown and not target:IsShown()) then
            StopAuraPendingDrag(target)
            return
        end
        local mx, my = GetCursorPosition()
        if not (mx and my) then return end
        if math_max(math_abs(mx - (pendingAuraDragStartX or mx)), math_abs(my - (pendingAuraDragStartY or my))) < AURA_PENDING_DRAG_THRESHOLD then
            return
        end
        StopAuraPendingDrag(target)
        if type(BeginAuraGroupDrag) == "function" then BeginAuraGroupDrag(target, true) end
    end)
    frame:Show()
    return true
end

BeginAuraGroupDrag = function(self, fromMotion)
    if not self or self._dragging then return true end
    StopAuraPendingDrag(self)
    if not IsEditModeActive() or IsConfigBlocked() then return false end
    if self.Raise then self:Raise() end

    ExportPublic("MSUF_EM2_ActiveAuraGroup", self._msufA3MoverKind)
    ExportPublic("MSUF_EM2_ActiveAuraUnit", self._msufA3Unit)

    local cfg = ReadGroupConfig(self._msufA3Unit, self._msufA3MoverKind)
    self._dragStartOffsetX = cfg.x
    self._dragStartOffsetY = cfg.y
    self._dragFrameScale = ApplyGroupScaleForFrame(self, GetFrame(self._msufA3Unit))

    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not scale or scale == 0 then scale = 1 end
    local cx, cy = GetCursorPosition()
    if not (cx and cy) then return false end
    if type(_G.MSUF_EM_UndoBeginChange) == "function" and not _G.MSUF__UndoRestoring then
        self._msufA3HistoryDrag = _G.MSUF_EM_UndoBeginChange("aura", self._msufA3Unit, "Move") == true
    else
        local before = _G.MSUF_EM_UndoBeforeChange
        if type(before) == "function" and not _G.MSUF__UndoRestoring then before("aura", self._msufA3Unit) end
    end
    self._dragStartCursorX = cx / scale
    self._dragStartCursorY = cy / scale
    self._dragMoved = false
    self._dragStartedByMotion = fromMotion == true
    self._dragging = true
    self._lastDragX = nil
    self._lastDragY = nil
    self._dragRuntimeElapsed = AURA_DRAG_RUNTIME_INTERVAL
    self._dragRuntimePending = nil
    self._lastDragElapsed = 0

    local l, r, t, b = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
    if not (l and r and t and b) then
        local centerX, centerY = self:GetCenter()
        local w = self:GetWidth() or 0
        local h = self:GetHeight() or 0
        centerX, centerY = centerX or 0, centerY or 0
        l, r = centerX - w * 0.5, centerX + w * 0.5
        b, t = centerY - h * 0.5, centerY + h * 0.5
    end
    self._snapStartCX = (l + r) * 0.5
    self._snapStartCY = (t + b) * 0.5
    self._snapHW = (r - l) * 0.5
    self._snapHH = (t - b) * 0.5

    if self.SetOnUpdateMode then self:SetOnUpdateMode(ONUPDATE_MODE_RUN_WHEN_VISIBLE) end
    self:SetScript("OnUpdate", AuraGroupDragOnUpdate)
    StartAuraDragCapture(self)
    return true
end

local function EndAuraGroupDrag(self, button, suppressClick)
    if button and button ~= "LeftButton" then return false end
    StopAuraPendingDrag(self)
    if not self then return false end

    if not self._dragging then
        if self._suppressNextAuraClick then
            self._suppressNextAuraClick = nil
            return false
        end
        if not suppressClick and button == "LeftButton" then OpenAuraGroupPopup(self) end
        return false
    end

    local moved = self._dragMoved == true or self._dragStartedByMotion == true
    self._dragging = false
    self:SetScript("OnUpdate", nil)
    StopAuraDragCapture(self)
    if self.SetOnUpdateMode then self:SetOnUpdateMode(ONUPDATE_MODE_DISABLED) end
    self._dragAuras = nil
    self._dragShared = nil
    self._dragRuntimeElapsed = nil
    self._dragRuntimePending = nil
    self._lastDragElapsed = nil
    self._dragStartedByMotion = nil
    if self._msufA3HistoryDrag and type(_G.MSUF_EM_UndoCommitChange) == "function" then
        self._msufA3HistoryDrag = nil
        _G.MSUF_EM_UndoCommitChange()
    end
    local Snap = _G.MSUF_EM2 and _G.MSUF_EM2.Snap
    if Snap and Snap.HideGuides then Snap.HideGuides() end

    if moved then
        local _, shared = EnsureDB()
        RefreshAffectedRuntimeUnits(self._msufA3Unit, shared)
        RequestUnitFrameMenuPreview("AURAS3_EDITMODE_DRAG_END")
        local sync = _G.MSUF_SyncAuras3PositionPopup
        if type(sync) == "function" then sync(self._msufA3Unit) end
        self._lastDragX = nil
        self._lastDragY = nil
        self._dragMoved = false
        self._suppressNextAuraClick = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if self then self._suppressNextAuraClick = nil end
            end)
        end
        return true
    end

    if not suppressClick then OpenAuraGroupPopup(self) end
    self._lastDragX = nil
    self._lastDragY = nil
    return false
end
local function SafeFrameCall(frame, methodName, ...)
    local method = frame and frame[methodName]
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, frame, ...)
    if ok then return value end
    return nil
end

local function IsSecretValue(value)
    -- issecretvalue is the sanctioned never-throwing probe.
    if type(issecretvalue) ~= "function" then return true end
    return issecretvalue(value) == true
end

local function SafeFrameBool(frame, methodName)
    local value = SafeFrameCall(frame, methodName)
    if value == nil then return nil end
    if IsSecretValue(value) then return nil end
    return value == true
end

local function StoreAuraMouseState(frame)
    if not frame or frame._msufA3EditMouseStored == true then return end
    frame._msufA3EditMouseStored = true
    frame._msufA3EditMouseEnabled = SafeFrameBool(frame, "IsMouseEnabled")
    frame._msufA3EditClickEnabled = SafeFrameBool(frame, "IsMouseClickEnabled")
    frame._msufA3EditMotionEnabled = SafeFrameBool(frame, "IsMouseMotionEnabled")
    frame._msufA3EditPropagateClicks = SafeFrameBool(frame, "GetPropagateMouseClicks")
end

local function SuppressAuraMouse(frame, forwardClicks)
    if not frame then return end
    StoreAuraMouseState(frame)
    local hasClick = type(frame.SetMouseClickEnabled) == "function"
    local hasMotion = type(frame.SetMouseMotionEnabled) == "function"
    if type(frame.EnableMouse) == "function" then
        SafeFrameCall(frame, "EnableMouse", forwardClicks ~= false)
    end
    if hasClick then SafeFrameCall(frame, "SetMouseClickEnabled", forwardClicks ~= false) end
    if hasMotion then SafeFrameCall(frame, "SetMouseMotionEnabled", false) end
    if forwardClicks ~= false then
        SafeFrameCall(frame, "SetPropagateMouseClicks", true)
        frame._msufA3EditPropagateChanged = true
    end
end

local function RestoreAuraMouse(frame, motionEnabled, fallbackClickEnabled)
    if not frame then return end
    local stored = frame._msufA3EditMouseStored == true
    local mouseEnabled = frame._msufA3EditMouseEnabled
    local clickEnabled = frame._msufA3EditClickEnabled
    local storedMotionEnabled = frame._msufA3EditMotionEnabled
    local propagateClicks = frame._msufA3EditPropagateClicks
    local propagateChanged = frame._msufA3EditPropagateChanged

    frame._msufA3EditMouseStored = nil
    frame._msufA3EditMouseEnabled = nil
    frame._msufA3EditClickEnabled = nil
    frame._msufA3EditMotionEnabled = nil
    frame._msufA3EditPropagateClicks = nil
    frame._msufA3EditPropagateChanged = nil

    local hasClick = type(frame.SetMouseClickEnabled) == "function"
    local hasMotion = type(frame.SetMouseMotionEnabled) == "function"
    if type(frame.EnableMouse) == "function" then
        if mouseEnabled ~= nil then
            SafeFrameCall(frame, "EnableMouse", mouseEnabled)
        elseif not hasClick and not hasMotion then
            if stored ~= true or fallbackClickEnabled == true then
                mouseEnabled = true
            elseif motionEnabled ~= nil then
                mouseEnabled = motionEnabled
            else
                mouseEnabled = false
            end
            SafeFrameCall(frame, "EnableMouse", mouseEnabled)
        end
    end
    if hasClick then
        if clickEnabled == nil then clickEnabled = fallbackClickEnabled == true end
        SafeFrameCall(frame, "SetMouseClickEnabled", clickEnabled)
    end
    if hasMotion then
        if motionEnabled == nil then motionEnabled = storedMotionEnabled end
        if motionEnabled == nil then motionEnabled = false end
        SafeFrameCall(frame, "SetMouseMotionEnabled", motionEnabled)
    end
    if propagateClicks ~= nil then
        SafeFrameCall(frame, "SetPropagateMouseClicks", propagateClicks)
    elseif propagateChanged == true then
        SafeFrameCall(frame, "SetPropagateMouseClicks", false)
    end
end

local function NativeAuraEditGroup(frame)
    if not frame or not IsEditModeActive() then return nil end
    local container = frame._msufA3EditForwardContainer or frame
    local laneKind = frame._msufA3LaneKind or container._msufA3NativeLane
    if laneKind == "buffs" then laneKind = "buff" end
    if laneKind == "debuffs" then laneKind = "debuff" end
    if laneKind ~= "buff" and laneKind ~= "debuff" then return nil end
    local lane = container._msufA3NativeLaneConfig
    local unit = (lane and lane.unit) or container.unit
    return unit and EM.groups and EM.groups[unit] and EM.groups[unit][laneKind] or nil
end

local function ForwardNativeAuraMouse(frame, scriptName, button)
    if button ~= "LeftButton" and button ~= "RightButton" then return end
    local group = NativeAuraEditGroup(frame)
    local handler = group and group:GetScript(scriptName)
    if handler then handler(group, button) end
end

local function WireNativeAuraEditForward(frame, container)
    if not (frame and frame.HookScript) then return false end
    if frame._msufA3EditDragForwardHooked == true then return true end
    frame._msufA3EditForwardContainer = container or frame
    local okDown = pcall(frame.HookScript, frame, "OnMouseDown", function(self, button)
        ForwardNativeAuraMouse(self, "OnMouseDown", button)
    end)
    local okUp = pcall(frame.HookScript, frame, "OnMouseUp", function(self, button)
        ForwardNativeAuraMouse(self, "OnMouseUp", button)
    end)
    frame._msufA3EditDragForwardHooked = (okDown or okUp) and true or nil
    return frame._msufA3EditDragForwardHooked == true
end

local function SetLaneMouseSuppressed(element, container, suppressed)
    if not container then return end
    local laneKind = container._msufA3NativeLane
    local forwardKind = laneKind
    if forwardKind == "buffs" then forwardKind = "buff" end
    if forwardKind == "debuffs" then forwardKind = "debuff" end
    local canForward = forwardKind == "buff" or forwardKind == "debuff"
    local laneCfg = element and element._msufA3Config and element._msufA3Config.lanes and element._msufA3Config.lanes[laneKind]
    local motionEnabled = not laneCfg or laneCfg.showTooltip ~= false
    local nativeLaneCfg = container._msufA3NativeLaneConfig or laneCfg
    local cancelablePlayerBuff = forwardKind == "buff"
        and nativeLaneCfg and nativeLaneCfg.unit == "player"
    if suppressed then
        if canForward then WireNativeAuraEditForward(container, container) end
        SuppressAuraMouse(container, canForward)
    else
        RestoreAuraMouse(container, nil, false)
    end

    -- Flow buttons belong to Blizzard's frame provider, not container[index].
    -- Enumerate its public group API after MSUF's fixed slots; this also covers
    -- mixed Unit owners without retaining a second button registry.
    local groupKey = container._msufA3ManagedGroupKey
    local groupCount = groupKey and SafeFrameCall(container, "GetAuraGroupFrameCount", groupKey)
    local fixedCount = container._msufA3FixedButtonCount or 0
    local count = groupCount and (fixedCount + groupCount)
        or (type(container.GetAuraFrameCount) == "function" and container:GetAuraFrameCount())
        or tonumber(container.createdButtons) or 0
    for i = 1, count do
        local ok, button
        if groupCount and i > fixedCount then
            ok, button = pcall(container.GetAuraGroupFrame, container, groupKey, i - fixedCount)
        elseif type(container.GetAuraFrame) == "function" then
            ok, button = pcall(container.GetAuraFrame, container, i)
        end
        if not button then button = container[i] end
        if container._msufA3GroupSlotsRoot == true and button then
            -- A mixed owner also contains click-through Dispel slots. Restore
            -- input per actual Aura lane, never from the owner's sensor kind.
            laneKind = button._msufA3LaneKind
            canForward = laneKind == "buff" or laneKind == "debuff"
            laneCfg = element._msufA3Config.lanes[laneKind]
            motionEnabled = laneCfg and laneCfg.showTooltip ~= false or false
            cancelablePlayerBuff = laneKind == "buff" and laneCfg and laneCfg.unit == "player"
        end
        if ok ~= false and button then
            if suppressed then
                if canForward then WireNativeAuraEditForward(button, container) end
                SuppressAuraMouse(button, canForward)
            else
                -- Forbidden buttons can hide their stored input state. Restore
                -- the sole runtime exception (Player Buff RightButtonUp cancel)
                -- and keep every other AuraButton click-through.
                RestoreAuraMouse(button, motionEnabled, cancelablePlayerBuff)
            end
        end
    end
end

local RUNTIME_MOUSE_ROOTS = { "Buffs", "Debuffs", "Externals",
    "DispelSensor", "DispelSensorNeutral", "DispelSensorHostile" }
local function SetRuntimeAuraMouse(element, suppressed)
    for i = 1, #RUNTIME_MOUSE_ROOTS do
        local container = element[RUNTIME_MOUSE_ROOTS[i]]
        if i <= 3 or container and container._msufA3GroupSlotsRoot == true then
            SetLaneMouseSuppressed(element, container, suppressed)
        end
    end
end

local function SetRuntimeAuraHidden(unit, hidden)
    local frame = GetFrame(unit)
    local element = frame and frame.Auras
    if not element or not element.SetAlpha then return end
    if hidden then
        if element._msufA3EditModeAlpha == nil and element.GetAlpha then
            element._msufA3EditModeAlpha = element:GetAlpha()
        end
        element:SetAlpha(0)
        SetRuntimeAuraMouse(element, true)
    elseif element._msufA3EditModeAlpha ~= nil then
        element:SetAlpha(element._msufA3EditModeAlpha)
        element._msufA3EditModeAlpha = nil
        SetRuntimeAuraMouse(element, false)
    end
end


return {
    PromoteRuntimeLayout = PromoteRuntimeLayout,
    OpenAuraGroupPopup = OpenAuraGroupPopup,
    StopAuraPendingDrag = StopAuraPendingDrag,
    QueueAuraPendingDrag = QueueAuraPendingDrag,
    EndAuraGroupDrag = EndAuraGroupDrag,
    SetRuntimeAuraHidden = SetRuntimeAuraHidden,
    BeginAuraGroupDrag = BeginAuraGroupDrag,
}
end
