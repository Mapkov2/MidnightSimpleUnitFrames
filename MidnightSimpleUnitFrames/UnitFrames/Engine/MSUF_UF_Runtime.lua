local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

MSUF.UF = MSUF.UF or {}

local UF = MSUF.UF
local Metadata = UF.Metadata or {}
local type = type
local tostring = tostring
local tonumber = tonumber
local select = select
local CreateFrame = CreateFrame
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local math_floor = math.floor
local debugprofilestop = debugprofilestop

local EMPTY_METADATA_SET = {}
local BOSS_UNITS = {
    boss1 = true,
    boss2 = true,
    boss3 = true,
    boss4 = true,
    boss5 = true,
}

local ApplyElementToFrame = UF.ApplyElementToFrame
local DEFERRED_REFRESH_ALL = "*"

local function QueueDeferredElementRefresh(unit, names, updateReason)
    local pending = UF.pendingElementRefreshes
    local key = unit or DEFERRED_REFRESH_ALL
    if key == DEFERRED_REFRESH_ALL then
        for existing in pairs(pending) do
            pending[existing] = nil
        end
    elseif pending[DEFERRED_REFRESH_ALL] then
        key = DEFERRED_REFRESH_ALL
    end
    local entry = pending[key]
    if not entry then
        entry = { names = {} }
        pending[key] = entry
    end
    local set = entry.names
    for i = 1, #names do
        set[names[i]] = true
    end
    entry.reason = updateReason or entry.reason or "MSUF_DEFERRED_REFRESH"
    local factory = UF.Factory
    if factory and factory.EnsureDeferredDriver then
        factory.EnsureDeferredDriver()
    end
    return false
end

local function BuildDeferredRefreshList(entry)
    local list = entry.list
    if not list then
        list = {}
        entry.list = list
    end
    local n = 0
    local set = entry.names
    for i = 1, #UF.elementOrder do
        local name = UF.elementOrder[i]
        if set[name] == true then
            n = n + 1
            list[n] = name
        end
    end
    for i = n + 1, #list do
        list[i] = nil
    end
    return list
end

local dirtyQueueMethods = {}
local dirtyQueueMeta = { __index = dirtyQueueMethods }
local dirtyQueues = UF.dirtyQueues
local bit_bor = (bit and bit.bor) or function(a, b)
    if type(a) ~= "number" then return b end
    if type(b) ~= "number" then return a end
    local res, bitValue = 0, 1
    while a > 0 or b > 0 do
        local aa = a % 2
        local bb = b % 2
        if aa == 1 or bb == 1 then
            res = res + bitValue
        end
        a = (a - aa) / 2
        b = (b - bb) / 2
        bitValue = bitValue * 2
    end
    return res
end

local function DirtyQueueValue(value, queue, fallback)
    if type(value) == "function" then
        value = value(queue)
    end
    value = tonumber(value) or fallback
    return value
end

function dirtyQueueMethods:Schedule()
    if self.flushQueued then
        return
    end
    self.flushQueued = true
    local sched = _G.MSUF_ScheduleOnce
    if type(sched) == "function" then
        sched(self.scheduleKey, self.flushCallback)
        return
    end
    local timer = _G.C_Timer
    if timer and type(timer.After) == "function" then
        timer.After(0, self.flushCallback)
        return
    end
    self.flushCallback()
end

function dirtyQueueMethods:Mark(frame, bits, deferSchedule)
    if not frame then
        return false
    end
    local runtimeEnabled = self.runtimeEnabled
    if runtimeEnabled and runtimeEnabled(frame) == false then
        return false
    end
    bits = bits or self.defaultBits
    local prev = self.bits[frame]
    if prev ~= nil then
        if type(prev) == "number" and type(bits) == "number" then
            self.bits[frame] = bit_bor(prev, bits)
        else
            self.bits[frame] = bits
        end
    else
        self.bits[frame] = bits
    end
    if not self.queued[frame] then
        local tail = self.tail + 1
        self.tail = tail
        self.queue[tail] = frame
        self.queued[frame] = true
    end
    if not deferSchedule then
        self:Schedule()
    end
    return true
end

function dirtyQueueMethods:Retire(frame)
    if not frame then
        return
    end
    self.bits[frame] = nil
    self.queued[frame] = nil
end

function dirtyQueueMethods:Clear()
    local queue = self.queue
    for i = self.head, self.tail do
        queue[i] = nil
    end
    self.bits = {}
    self.queued = {}
    self.head = 1
    self.tail = 0
    self.flushQueued = false
end

function dirtyQueueMethods:Flush()
    self.flushQueued = false

    local process = self.process
    if type(process) ~= "function" then
        return false
    end

    local maxPerFlush = DirtyQueueValue(self.maxPerFlush, self, 8)
    if maxPerFlush < 1 then
        maxPerFlush = 1
    end
    local budgetMs = DirtyQueueValue(self.budgetMs, self, 0.35)
    local endAt
    if debugprofilestop and budgetMs and budgetMs > 0 then
        endAt = debugprofilestop() + budgetMs
    end

    local bitsMap = self.bits
    local queued = self.queued
    local queue = self.queue
    local runtimeEnabled = self.runtimeEnabled
    local anyFlushed = false
    local processed = 0

    while self.head <= self.tail do
        local head = self.head
        local frame = queue[head]
        queue[head] = nil
        self.head = head + 1

        if frame then
            local bits = bitsMap[frame]
            bitsMap[frame] = nil
            queued[frame] = nil
            if bits ~= nil and (not runtimeEnabled or runtimeEnabled(frame) ~= false) then
                if process(frame, bits, self) ~= false then
                    anyFlushed = true
                end
            end
        end

        processed = processed + 1
        if processed >= maxPerFlush then
            self:Schedule()
            return anyFlushed
        end
        if endAt and processed % 4 == 0 and debugprofilestop() > endAt then
            self:Schedule()
            return anyFlushed
        end
    end

    self.head = 1
    self.tail = 0
    if anyFlushed and type(self.onAnyFlushed) == "function" then
        self.onAnyFlushed(self)
    end
    return anyFlushed
end

function UF.CreateDirtyQueue(name, opts)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    opts = opts or {}
    local queue = dirtyQueues[name]
    if not queue then
        queue = setmetatable({
            name = name,
            bits = {},
            queued = {},
            queue = {},
            head = 1,
            tail = 0,
            defaultBits = true,
        }, dirtyQueueMeta)
        queue.flushCallback = function()
            queue:Flush()
        end
        dirtyQueues[name] = queue
    end
    queue.scheduleKey = opts.scheduleKey or queue.scheduleKey or ("MSUF_UF_DIRTY_" .. name)
    queue.process = opts.process or queue.process
    queue.runtimeEnabled = opts.runtimeEnabled
    queue.onAnyFlushed = opts.onAnyFlushed
    queue.maxPerFlush = opts.maxPerFlush or queue.maxPerFlush or 8
    queue.budgetMs = opts.budgetMs or queue.budgetMs or 0.35
    queue.defaultBits = opts.defaultBits or queue.defaultBits or true
    return queue
end

function UF.RefreshElements(unit, names, updateReason)
    if type(names) ~= "table" then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        return QueueDeferredElementRefresh(unit, names, updateReason)
    end
    local refreshedAll = false
    if not unit and UF.Config and UF.Config.Refresh then
        UF.Config.Refresh()
        refreshedAll = true
    end
    local function refreshFrame(frame)
        if not frame then
            return
        end
        local spec
        if refreshedAll and UF.Config and UF.Config.GetSpec then
            spec = UF.Config.GetSpec(frame.unit)
        elseif UF.Config and UF.Config.RefreshUnit then
            spec = UF.Config.RefreshUnit(frame.unit)
        elseif UF.Config and UF.Config.GetSpec then
            spec = UF.Config.GetSpec(frame.unit)
        else
            spec = frame.MSUFSpec
        end
        for i = 1, #names do
            ApplyElementToFrame(frame, names[i], spec, updateReason or "MSUF_ELEMENT_REFRESH")
        end
    end
    if unit then
        local units = UF.UnitsForConfigKey(unit)
        if not units then
            return false
        end
        for i = 1, #units do
            refreshFrame(UF.frames[units[i]])
        end
        return true
    end
    UF.ForEachFrame(refreshFrame)
    return true
end

function UF.FlushDeferredRefreshes()
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    local pending = UF.pendingElementRefreshes
    local any = false
    for key, entry in pairs(pending) do
        pending[key] = nil
        local unit = key ~= DEFERRED_REFRESH_ALL and key or nil
        local names = BuildDeferredRefreshList(entry)
        if #names > 0 then
            UF.RefreshElements(unit, names, entry.reason or "MSUF_DEFERRED_REFRESH")
            any = true
        end
    end
    return any
end

function UF.MarkDirty(unit)
    if unit then
        local units = UF.UnitsForConfigKey(unit)
        if not units then
            return
        end
        for i = 1, #units do
            UF.pendingApply[units[i]] = true
        end
        return
    end
    for i = 1, #UF.unitOrder do
        UF.pendingApply[UF.unitOrder[i]] = true
    end
end

function UF.ApplyDirty()
    local factory = UF.Factory
    if not (factory and factory.Apply) then
        return false
    end
    for unit in pairs(UF.pendingApply) do
        UF.pendingApply[unit] = nil
        factory.Apply(unit)
    end
    return true
end

function UF.RequestReanchorAfterCombat()
    if InCombatLockdown and InCombatLockdown() then
        UF.MarkDirty(nil)
        local factory = UF.Factory
        if factory and factory.EnsureDeferredDriver then
            factory.EnsureDeferredDriver()
        end
        return false
    end
    return UF.Apply(nil)
end

function _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
    local k = tostring(key or "")
    local u = tostring(unit or "")
    if k == "" then return u ~= "" and u or nil end
    if k == "boss" and u ~= "" then return k .. ":" .. u end
    return k
end

function _G.MSUF_GetUnitFrameScreenCacheBucket()
    local fn = _G.MSUF_GetProfileScopedCache
    if type(fn) ~= "function" then return nil end
    return fn("unitFrameScreenCache")
end

local function GetFramePoint(frame, point)
    if not frame then return nil, nil, nil end
    point = point or "CENTER"
    if point == "CENTER" and frame.GetCenter then
        local x, y = frame:GetCenter()
        return x, y, "CENTER"
    end
    if not frame.GetLeft or not frame.GetRight or not frame.GetTop or not frame.GetBottom then
        if frame.GetCenter then
            local x, y = frame:GetCenter()
            return x, y, "CENTER"
        end
        return nil, nil, nil
    end

    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not l or not r or not t or not b then
        if frame.GetCenter then
            local x, y = frame:GetCenter()
            return x, y, "CENTER"
        end
        return nil, nil, nil
    end

    local cx = (l + r) * 0.5
    local cy = (t + b) * 0.5
    if point == "TOPLEFT" then return l, t, point end
    if point == "TOP" then return cx, t, point end
    if point == "TOPRIGHT" then return r, t, point end
    if point == "LEFT" then return l, cy, point end
    if point == "RIGHT" then return r, cy, point end
    if point == "BOTTOMLEFT" then return l, b, point end
    if point == "BOTTOM" then return cx, b, point end
    if point == "BOTTOMRIGHT" then return r, b, point end
    return cx, cy, "CENTER"
end

function _G.MSUF_CacheUnitFrameScreenPosition(frame, key, unit, point, allowLocked)
    local uiParent = _G.UIParent
    if not frame or not key or not uiParent or not uiParent.GetCenter then return false end
    if allowLocked ~= true and InCombatLockdown and InCombatLockdown() then return false end

    point = point or frame._msufHardLockPoint or "CENTER"
    local fx, fy, usedPoint = GetFramePoint(frame, point)
    local ux, uy = uiParent:GetCenter()
    if not fx or not fy or not ux or not uy then return false end

    local fs = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    local us = (uiParent.GetEffectiveScale and uiParent:GetEffectiveScale()) or 1
    if fs == 0 then fs = 1 end
    if us == 0 then us = 1 end

    local id = _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
    local bucket = _G.MSUF_GetUnitFrameScreenCacheBucket()
    if not id or not bucket then return false end

    local w = frame.GetWidth and frame:GetWidth() or nil
    local h = frame.GetHeight and frame:GetHeight() or nil
    bucket[id] = {
        v = 3,
        x = math_floor(((fx * fs - ux * us) / us) + 0.5),
        y = math_floor(((fy * fs - uy * us) / us) + 0.5),
        w = w,
        h = h,
        scale = frame.GetScale and frame:GetScale() or nil,
        point = usedPoint or point or "CENTER",
    }
    return true
end

function _G.MSUF_ApplyCachedUnitFrameScreenPosition(frame, key, unit)
    local uiParent = _G.UIParent
    if not frame or not key or not uiParent then return false end
    local bucket = _G.MSUF_GetUnitFrameScreenCacheBucket()
    local id = _G.MSUF_GetUnitFrameScreenCacheKey(key, unit)
    local cached = bucket and id and bucket[id]
    if type(cached) ~= "table" or (cached.v ~= 2 and cached.v ~= 3) then return false end
    local x, y = tonumber(cached.x), tonumber(cached.y)
    if not x or not y then return false end

    if cached.v == 3 and frame.SetScale and tonumber(cached.scale) then
        frame:SetScale(tonumber(cached.scale))
    end

    local point = cached.point
    if type(point) ~= "string" or point == "" then point = "CENTER" end
    frame:ClearAllPoints()
    frame:SetPoint(point, uiParent, "CENTER", math_floor(x + 0.5), math_floor(y + 0.5))
    frame._msufPositionInitialized = true
    frame._msufHardLockedToUIParent = true
    frame._msufHardLockPoint = point
    frame._msufLoadedFromScreenCache = true
    return true
end

local function ForceUnits(reason, ...)
    for i = 1, select("#", ...) do
        local unit = select(i, ...)
        if unit then
            UF.UpdateRuntime(unit, reason or "MSUF_FORCE_UPDATE")
        end
    end
end

local function DriverOnEvent(self, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        UF.UpdateRuntime("target", "MSUF_UNIT_IDENTITY")
        UF.UpdateRuntime("targettarget", "MSUF_UNIT_IDENTITY_SOFT")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        UF.UpdateRuntime("focus", "MSUF_UNIT_IDENTITY")
        UF.UpdateRuntime("focustarget", "MSUF_UNIT_IDENTITY_SOFT")
    elseif event == "UNIT_TARGET" then
        if unit == "target" then
            UF.UpdateRuntime("targettarget", "MSUF_UNIT_IDENTITY")
        elseif unit == "focus" then
            UF.UpdateRuntime("focustarget", "MSUF_UNIT_IDENTITY")
        elseif unit and BOSS_UNITS[unit] then
            UF.UpdateRuntime(unit, "MSUF_UNIT_IDENTITY")
        end
    elseif event == "UNIT_PET" then
        if unit == "player" then
            UF.UpdateRuntime("pet", "MSUF_UNIT_IDENTITY")
        end
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        ForceUnits("MSUF_UNIT_IDENTITY", "boss1", "boss2", "boss3", "boss4", "boss5")
    else
        UF.UpdateRuntime(nil, "MSUF_FORCE_UPDATE")
    end
end

if CreateFrame and not UF.driver then
    UF.driver = CreateFrame("Frame")
    UF.driver:SetScript("OnEvent", DriverOnEvent)
    UF.driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    UF.driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    UF.driver:RegisterEvent("PLAYER_FOCUS_CHANGED")
    UF.driver:RegisterEvent("UNIT_PET")
    UF.driver:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    if UF.driver.RegisterUnitEvent then
        UF.driver:RegisterUnitEvent("UNIT_TARGET", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5")
    else
        UF.driver:RegisterEvent("UNIT_TARGET")
    end
end

local REFRESH_ELEMENT_GROUPS = Metadata.refreshElementGroups or EMPTY_METADATA_SET

local HEALTH_TEXT_BORDER_ELEMENTS = REFRESH_ELEMENT_GROUPS.healthTextBorder or EMPTY_METADATA_SET
local VISUAL_ELEMENTS = REFRESH_ELEMENT_GROUPS.visuals or EMPTY_METADATA_SET
local POWER_TEXT_ELEMENTS = REFRESH_ELEMENT_GROUPS.powerText or EMPTY_METADATA_SET
local TEXT_ELEMENTS = REFRESH_ELEMENT_GROUPS.text or EMPTY_METADATA_SET
local BORDER_ELEMENTS = REFRESH_ELEMENT_GROUPS.borders or EMPTY_METADATA_SET
local REVERSE_FILL_ELEMENTS = REFRESH_ELEMENT_GROUPS.reverseFill or EMPTY_METADATA_SET
local ALPHA_ELEMENTS = REFRESH_ELEMENT_GROUPS.alpha or EMPTY_METADATA_SET

function UF.NotifyConfigChanged(unit, applyNow, forceUpdate)
    if InCombatLockdown and InCombatLockdown() then
        UF.MarkDirty(unit)
        if UF.Config then
            UF.Config.dirty = true
        end
        local factory = UF.Factory
        if factory and factory.EnsureDeferredDriver then
            factory.EnsureDeferredDriver()
        end
        return false
    end
    if applyNow ~= false then
        UF.Apply(unit)
    elseif forceUpdate ~= false then
        if UF.Config then
            if unit and UF.Config.RefreshUnit then
                local units = UF.UnitsForConfigKey(unit)
                if units then
                    for i = 1, #units do
                        UF.Config.RefreshUnit(units[i])
                    end
                end
            elseif UF.Config.Refresh then
                UF.Config.Refresh()
            end
        end
        UF.ForceUpdate(unit)
    end
    return true
end

function UF.RegisterVisualRefreshCallback(key, fn)
    if type(fn) ~= "function" then
        return false
    end
    UF.visualRefreshCallbacks[key or fn] = fn
    return true
end

local function RunVisualRefreshCallbacks(unit)
    for _, fn in pairs(UF.visualRefreshCallbacks) do
        fn(unit)
    end
end

function UF.RefreshVisuals(unit)
    local ok = UF.RefreshElements(unit, VISUAL_ELEMENTS, "MSUF_VISUALS")
    RunVisualRefreshCallbacks(unit)
    return ok
end

function UF.RefreshIdentityColors()
    return UF.RefreshElements(nil, HEALTH_TEXT_BORDER_ELEMENTS, "MSUF_IDENTITY_COLORS")
end

function UF.RefreshPowerTextColors()
    return UF.RefreshElements(nil, POWER_TEXT_ELEMENTS, "MSUF_POWER_TEXT_COLORS")
end

function UF.RefreshAlphas()
    return UF.RefreshElements(nil, ALPHA_ELEMENTS, "MSUF_ALPHA")
end

function UF.RefreshBorders()
    return UF.RefreshElements(nil, BORDER_ELEMENTS, "MSUF_BORDER_LAYOUT")
end

function UF.RefreshHealthLayout()
    return UF.RefreshElements(nil, REVERSE_FILL_ELEMENTS, "MSUF_REVERSE_FILL")
end

function UF.RefreshPowerLayout(unit)
    return UF.RefreshElements(unit, POWER_TEXT_ELEMENTS, "MSUF_POWER_LAYOUT")
end

function UF.RefreshPowerLayoutForFrame(frame)
    if frame and frame.unit then
        return UF.RefreshPowerLayout(frame.unit)
    end
    return UF.RefreshPowerLayout(nil)
end

function UF.RefreshTextLayout(unit)
    return UF.RefreshElements(unit, TEXT_ELEMENTS, "MSUF_TEXT_LAYOUT")
end

UF.ApplyUnitFrameKey = UF.Apply

_G.MSUF_UnitFrames = UF.frames
_G.MSUF_UnitFramesList = UF.frameList
_G.MSUF_ForEachUnitFrame = UF.ForEachFrame
_G.MSUF_UFCore_NotifyConfigChanged = UF.NotifyConfigChanged
_G.MSUF_RefreshAllFrames = UF.RefreshVisuals
MSUF.MSUF_RefreshAllFrames = UF.RefreshVisuals
_G.MSUF_RefreshAllIdentityColors = UF.RefreshIdentityColors
_G.MSUF_RefreshAllPowerTextColors = UF.RefreshPowerTextColors
_G.MSUF_ForceTextLayoutForUnitKey = UF.RefreshTextLayout
_G.MSUF_RefreshAllUnitAlphas = UF.RefreshAlphas
_G.MSUF_ApplyBarOutlineThickness_All = UF.RefreshBorders
_G.MSUF_ApplyPowerBarBorder_All = UF.RefreshBorders
_G.MSUF_ApplyReverseFillBars = UF.RefreshHealthLayout
_G.MSUF_ApplyAllAlpha = UF.RefreshAlphas
_G.MSUF_ApplyPowerBarEmbedLayout_All = UF.RefreshPowerLayout
_G.MSUF_ApplyPowerBarEmbedLayout = UF.RefreshPowerLayoutForFrame
_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = UF.RefreshPowerLayout
_G.MSUF_ApplyUnitFrameKey_Immediate = UF.ApplyUnitFrameKey
_G.MSUF_RequestUnitFrameReanchorAfterCombat = UF.RequestReanchorAfterCombat
