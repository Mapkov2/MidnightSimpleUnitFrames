-- MSUF_GF_Core.lua — Group Frames core: factory, layout, preview, hiding
-- Phase 1: Party + Raid frame creation with EQoL-pattern hierarchy
-- Midnight 12.0 secret-safe, zero combat overhead
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF or {}
ns.GF = GF

local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown
local UnitExists = _G.UnitExists
local IsInRaid = _G.IsInRaid
local GetNumGroupMembers = _G.GetNumGroupMembers
local GetNumSubgroupMembers = _G.GetNumSubgroupMembers
local UnitIsConnected = _G.UnitIsConnected
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsAFK = _G.UnitIsAFK
local UnitIsDND = _G.UnitIsDND
local UnitClass = _G.UnitClass
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitPowerType = _G.UnitPowerType
local UnitName = _G.UnitName
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local UnitIsGroupLeader = _G.UnitIsGroupLeader
local UnitIsGroupAssistant = _G.UnitIsGroupAssistant
local GetRaidTargetIndex = _G.GetRaidTargetIndex
local GetRaidRosterInfo = _G.GetRaidRosterInfo
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local hooksecurefunc = _G.hooksecurefunc
local C_Timer = _G.C_Timer
local GetInstanceInfo = _G.GetInstanceInfo
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local PowerBarColor = _G.PowerBarColor
local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local math_floor = math.floor
local pairs = pairs
local type = type
local tonumber = tonumber
local tostring = tostring
local select = select
local GetTime = _G.GetTime
local GF_UNIT_BUTTON_TEMPLATE = "SecureUnitButtonTemplate,PingableUnitFrameTemplate"

local function ResolvePowerBarColor(powerToken)
    local resolver = _G.MSUF_GetResolvedPowerColor
    if type(resolver) == "function" then
        local r, g, b = resolver(nil, powerToken)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end

    if powerToken and PowerBarColor and PowerBarColor[powerToken] then
        local c = PowerBarColor[powerToken]
        local r = c.r or c[1] or 0.5
        local g = c.g or c[2] or 0.5
        local b = c.b or c[3] or 0.8
        return r, g, b
    end

    return 0.5, 0.5, 0.8
end

------------------------------------------------------------------------
-- Hidden parent for Blizzard frame hiding
------------------------------------------------------------------------
local _hiddenParent
local RegisterTrackedFrame, UnregisterTrackedFrame
local function GetHiddenParent()
    if not _hiddenParent then
        _hiddenParent = CreateFrame("Frame", nil, UIParent)
        _hiddenParent:SetAllPoints(UIParent)
        _hiddenParent:Hide()
    end
    return _hiddenParent
end

------------------------------------------------------------------------
-- RetireHeader: aggressively clean up an old header + children.
-- Reparents everything to hidden parent → zero render/CPU cost.
-- WoW never GCs frames, but this removes them from the render pipeline.
------------------------------------------------------------------------
local function RetireHeader(header)
    if not header then return end
    header:Hide()
    local hp = GetHiddenParent()
    local kids = { header:GetChildren() }
    for i = 1, #kids do
        local ch = kids[i]
        if ch then
            local retireFn = _G.MSUF_GF_OnFrameRetire
            if type(retireFn) == "function" then
                retireFn(ch)
            else
                if GF.HideFrameAuras then GF.HideFrameAuras(ch) end
                if GF.ClearPrivateAuras then GF.ClearPrivateAuras(ch) end
                if GF.UnregisterUnitEvents then GF.UnregisterUnitEvents(ch) end
            end
            -- Deregister from GF tracking
            UnregisterTrackedFrame(ch)
            if ch.unit and _G.MSUF_UnitFrames then
                _G.MSUF_UnitFrames[ch.unit] = nil
            end
            -- Strip event handlers (zero combat overhead)
            ch:UnregisterAllEvents()
            if ch.SetScript then
                ch:SetScript("OnEvent", nil)
                ch:SetScript("OnUpdate", nil)
            end
            -- Hide all sub-frames
            if ch.barGroup then ch.barGroup:Hide() end
            if ch.health then ch.health:Hide() end
            if ch.power then ch.power:Hide() end
            if ch._msufGFBorderFrame then ch._msufGFBorderFrame:Hide() end
            if ch._msufGFHighlightBorders then
                for _, border in pairs(ch._msufGFHighlightBorders) do
                    if border then border:Hide() end
                end
            elseif ch._msufGFHighlightBorder then ch._msufGFHighlightBorder:Hide() end
            if ch._msufGFNameText then ch._msufGFNameText:Hide() end
            if ch._msufGFStatusText then ch._msufGFStatusText:Hide() end
            -- Minimize + hide + reparent to hidden frame
            ch:Hide()
            ch:ClearAllPoints()
            ch:SetSize(0.001, 0.001)
            ch:SetParent(hp)
            -- Clear references to allow Lua-side GC of tables
            ch._c = nil
            ch._msufGFBuilt = nil
            ch._msufGFRegisteredUnit = nil
            ch._msufGFKind = nil
        end
    end
    -- Reparent header itself to hidden frame
    header:ClearAllPoints()
    header:SetSize(0.001, 0.001)
    header:SetParent(hp)
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
GF.headers     = GF.headers or {}     -- party/raid SecureGroupHeaders
GF.anchors     = GF.anchors or {}     -- anchor frames
GF.frames      = GF.frames or {}      -- all built unit buttons
GF.frameList   = GF.frameList or {}   -- compact live-frame iteration order

-- Cross-system frame registry (A2, EM2, etc. resolve unit→frame via this table)
if type(_G.MSUF_UnitFrames) ~= "table" then _G.MSUF_UnitFrames = {} end
local GFUnitFrames = _G.MSUF_UnitFrames
GF._eventFrame = GF._eventFrame or nil
GF._previewActive = GF._previewActive or {}

local _headerScanInputSerial = 0
local _rebuildAllActive = false
local function MarkHeaderScanInputsChanged()
    _headerScanInputSerial = _headerScanInputSerial + 1
end

local function MarkPostCombatHeaderRecovery()
    GF._pendingRebuild = true
    GF._pendingVisibilityUpdate = true
end

------------------------------------------------------------------------
-- Click-cast compatibility
------------------------------------------------------------------------
if type(_G.ClickCastFrames) ~= "table" then _G.ClickCastFrames = {} end
local _GF_ClickCastFrames = _G.ClickCastFrames
GF.ClickCastEnabled = true

local function _GF_CallCliqueMethod(clique, methodName, ...)
    local method = clique and clique[methodName]
    if type(method) ~= "function" then return false end
    local ok = pcall(method, clique, ...)
    return ok == true
end

local function _GF_RegisterClickCastFrame(f, refreshEnterLeave)
    if not (f and f.RegisterForClicks) then return end
    if f._msufGFIsPreviewFrame or f._msufGFPreviewActive then return end

    _GF_ClickCastFrames[f] = true

    local clique = _G.Clique
    if type(clique) ~= "table" or type(clique.ccframes) ~= "table" then return end

    _GF_CallCliqueMethod(clique, "RegisterUnitFrame", f)

    -- Clique key bindings depend on secure OnEnter/OnLeave wrappers. Group
    -- frame effects install those scripts after the base button is built, so
    -- refresh the wrappers once scripts are in their final position.
    if not refreshEnterLeave or (InCombatLockdown and InCombatLockdown()) then return end
    if clique.ccframes and clique.ccframes[f] then
        if type(clique.UnwrapOnEnterOnLeave) == "function" and type(clique.WrapOnEnterOnLeave) == "function" then
            _GF_CallCliqueMethod(clique, "UnwrapOnEnterOnLeave", f)
            _GF_CallCliqueMethod(clique, "WrapOnEnterOnLeave", f)
        elseif type(clique.ApplyAttributes) == "function" then
            _GF_CallCliqueMethod(clique, "ApplyAttributes")
        end
    end
end

GF.RegisterClickCastFrame = _GF_RegisterClickCastFrame

------------------------------------------------------------------------
-- Auto-register child frames with _G.MSUF_UnitFrames whenever the
-- SecureGroupHeader assigns/changes their `unit` attribute.
--
-- Why this exists: ScanHeaderChildren can run BEFORE the secure system
-- has populated `unit` attributes on freshly-created children (notably
-- on raid-header activation, where C_Timer.After(0) fires the same
-- frame as Show() but the secure environment assigns unit tokens on
-- the NEXT secure tick). The result was raid frames not appearing
-- in _G.MSUF_UnitFrames even though the header was visible — broke
-- external integrations (mini-cc/OmniCD/etc.) that walk this table.
--
-- The OnAttributeChanged hook fires reliably whenever the secure code
-- mutates `unit`, so registration becomes timing-independent. Idempotent
-- via _msufGFAttrHooked flag. Combat-safe (only Lua table writes and
-- RegisterUnitEvent calls, both legal in lockdown).
--
-- Handles three transitions:
--   nil → "raid7"  : register frame as raid7
--   "raid7" → "raid3" : clear raid7 entry, register raid3
--   "raid7" → nil  : clear raid7 entry (member left group)
------------------------------------------------------------------------
local function _GFResetUnitSlotState(self)
    self._msufGFHasAnyDebuff       = false
    self._msufGFDispelType         = nil
    self._msufGFDispelAuraID       = nil
    self._msufGFPrevDispelAuraID   = nil
    self._msufGFMergedDispel       = nil
    self._msufGFDispelColorObj     = nil
    self._msufGFDispelColorRev     = nil
    self._msufGFColorStyleRevision = nil

    local stopGlow = _G.MSUF_GF_StopDispelGlow
    if type(stopGlow) == "function" then
        stopGlow(self)
    else
        self._msufGFDispelGlowActive = nil
        self._msufGFDispelGlowAnchor = nil
        self._msufGFDispelGlowStyle = nil
    end

    local hlBorder = self._msufGFHighlightBorder
    if hlBorder then
        hlBorder._msufHLActivePrio = nil
    end
    local hlBorders = self._msufGFHighlightBorders
    if hlBorders then
        for _, border in pairs(hlBorders) do
            if border then
                border._msufHLActivePrio = nil
                if border:IsShown() then border:Hide() end
            end
        end
    elseif hlBorder and hlBorder:IsShown() then
        hlBorder:Hide()
    end

    self._msufGFLastFullAura       = nil
    self._msufGFAggroLevel         = nil
    self._msufGFLastName           = nil
    self._msufGFNameCacheKey       = nil
    self._msufGFNameStyleKey       = nil
    self._msufGFNameText           = nil
    self._msufGFNameClass          = nil
    self._msufGFNameColorKey       = nil
    self._msufGFNameHiddenForStatus = nil
    self._msufGFStatusState        = nil
    self._msufGFStatusDirty        = nil

    if GF.ResetStatusIconCaches then GF.ResetStatusIconCaches(self) end
    if GF.ResetOfflineHiddenFrame then GF.ResetOfflineHiddenFrame(self) end

    local stripe = self._msufGFDebuffStripe
    if stripe and stripe:IsShown() then stripe:Hide() end

    local statusText = self._msufGFStatusText or self.statusIndicatorText
    if statusText then
        statusText:SetText("")
        statusText:Hide()
    end

    local disp = self._msufDisplayedAuraIDs
    if disp then
        for k in pairs(disp) do disp[k] = nil end
    end
end

local function _GFOnUnitAttributeChanged(self, name, value)
    if name ~= "unit" then return end

    local prev = self._msufGFRegisteredUnit
    if prev == value and self.unit == value then
        if value == nil or value == "" then return end
        local uf = GFUnitFrames
        if uf and uf[value] == self then return end
    end

    local uf = GFUnitFrames or _G.MSUF_UnitFrames
    if not uf then return end
    GFUnitFrames = uf

    local unitChanged = (prev and prev ~= value)
    if unitChanged then
        if uf[prev] == self then uf[prev] = nil end
        self._msufGFRegisteredUnit = nil
    end

    if unitChanged or (prev and not value) then
        _GFResetUnitSlotState(self)
    end

    if type(value) == "string" and value ~= "" then
        self.unit = value
        local p5 = value:sub(1, 5)
        if p5 == "party" or value:sub(1, 4) == "raid" then
            uf[value] = self
        end

        if not self._msufGFBuilt then
            if InCombatLockdown and InCombatLockdown() then
                MarkPostCombatHeaderRecovery()
            end
            return
        end

        if self._msufGFRegisteredUnit ~= value then
            if GF.IsFrameRuntimeEnabled and not GF.IsFrameRuntimeEnabled(self, self._msufGFKind) then
                if GF.UnregisterUnitEvents then GF.UnregisterUnitEvents(self) end
                self._msufGFRegisteredUnit = nil
                return
            end
            self._msufGFRegisteredUnit = value
            if not (InCombatLockdown and InCombatLockdown()) and GF.ApplyVisuals then
                GF.ApplyVisuals(self, GF.DIRTY_ALL or 0x3F)
            end
            if GF.UpdateButton then GF.UpdateButton(self, value) end
            if GF.RegisterUnitEvents then GF.RegisterUnitEvents(self, value) end
        end
    end
end

local function _GFInstallAttrHook(child)
    if not child or child._msufGFAttrHooked then return end
    if not child.HookScript then return end
    child._msufGFAttrHooked = true
    child:HookScript("OnAttributeChanged", _GFOnUnitAttributeChanged)
end
GF._InstallAttrHook = _GFInstallAttrHook

RegisterTrackedFrame = function(f, kind)
    if not f then return end
    GF.frames[f] = kind
    GF._disabledRuntimeCleanSig = nil
    if f._msufGFFrameListIndex then return end
    local list = GF.frameList
    local idx = #list + 1
    list[idx] = f
    f._msufGFFrameListIndex = idx
end

UnregisterTrackedFrame = function(f)
    if not f then return end
    GF.frames[f] = nil
    GF._disabledRuntimeCleanSig = nil

    local idx = f._msufGFFrameListIndex
    if not idx then return end

    local list = GF.frameList
    local lastIndex = #list
    local last = list[lastIndex]

    list[lastIndex] = nil
    if idx < lastIndex and last then
        list[idx] = last
        last._msufGFFrameListIndex = idx
    end

    f._msufGFFrameListIndex = nil
end

function GF.IsKindEnabled(kind)
    kind = kind or "party"
    local conf = GF.GetConf and GF.GetConf(kind)
    return conf and conf.enabled == true
end

function GF.IsFrameRuntimeEnabled(f, frameKind)
    if f and f._msufGFPreviewActive then return true end
    if f and f.unit and UnitExists and UnitExists(f.unit) and f.IsVisible and f:IsVisible() then
        return true
    end
    return GF.IsKindEnabled(frameKind or (f and f._msufGFKind) or "party")
end

function GF.ForEachFrame(fn, includeDisabled)
    if type(fn) ~= "function" then return end
    local list = GF.frameList
    if list then
        for i = 1, #list do
            local f = list[i]
            if f then
                local frameKind = f._msufGFKind or GF.frames[f]
                if includeDisabled or GF.IsFrameRuntimeEnabled(f, frameKind) then
                    fn(f, frameKind)
                end
            end
        end
    elseif GF.frames then
        for f, frameKind in pairs(GF.frames) do
            if f and (includeDisabled or GF.IsFrameRuntimeEnabled(f, frameKind)) then
                fn(f, frameKind)
            end
        end
    end
end

------------------------------------------------------------------------
-- Group block border
------------------------------------------------------------------------
GF.groupBorders = GF.groupBorders or {}
GF.previewGroupBorders = GF.previewGroupBorders or {}

local function EnsureGroupBorder(kind)
    local borders = GF.groupBorders
    local border = borders[kind]
    if border then return border end

    border = CreateFrame("Frame", "MSUF_GFGroupBorder_" .. tostring(kind), UIParent, "BackdropTemplate")
    border:EnableMouse(false)
    border:SetFrameStrata("MEDIUM")
    border:SetFrameLevel(1)
    border:Hide()
    borders[kind] = border
    return border
end

local function EnsurePreviewGroupBorder(kind, parent)
    local borders = GF.previewGroupBorders
    local border = borders[kind]
    if not border then
        border = CreateFrame("Frame", "MSUF_GFPreviewGroupBorder_" .. tostring(kind), parent or UIParent, "BackdropTemplate")
        border:EnableMouse(false)
        border:SetFrameStrata("MEDIUM")
        border:Hide()
        borders[kind] = border
    elseif parent and border:GetParent() ~= parent then
        border:SetParent(parent)
    end
    return border
end

local function ApplyGroupBorderStyle(border, conf, size)
    if border._msufGBSize ~= size then
        border._msufGBSize = size
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = size })
        border:SetBackdropColor(0, 0, 0, 0)
    end
    border:SetBackdropBorderColor(
        tonumber(conf.groupBorderR) or 0.38,
        tonumber(conf.groupBorderG) or 0.68,
        tonumber(conf.groupBorderB) or 1.00,
        tonumber(conf.groupBorderA) or 0.95
    )
end

function GF.RefreshGroupBorder(kind)
    kind = kind or "party"
    local conf = GF.GetConf and GF.GetConf(kind)
    local border = EnsureGroupBorder(kind)
    if not conf or conf.groupBorderEnabled ~= true then
        border:Hide()
        return
    end

    local left, right, top, bottom
    local uiScale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if uiScale == 0 then uiScale = 1 end

    GF.ForEachFrame(function(f, frameKind)
        local unit = f and f.unit
        if frameKind == kind and type(unit) == "string" and unit ~= ""
            and UnitExists and UnitExists(unit)
            and f.IsVisible and f:IsVisible()
            and not f._msufGFPreviewActive then
            local box = f.barGroup or f
            if box and box.GetLeft then
                local l, r, t, b = box:GetLeft(), box:GetRight(), box:GetTop(), box:GetBottom()
                if l and r and t and b then
                    local boxScale = (box.GetEffectiveScale and box:GetEffectiveScale()) or uiScale
                    local ratio = boxScale / uiScale
                    l, r, t, b = l * ratio, r * ratio, t * ratio, b * ratio
                    left = left and math_min(left, l) or l
                    right = right and math_max(right, r) or r
                    top = top and math_max(top, t) or t
                    bottom = bottom and math_min(bottom, b) or b
                end
            end
        end
    end)

    if not left or not right or not top or not bottom or right <= left or top <= bottom then
        border:Hide()
        return
    end

    local size = math_floor((tonumber(conf.groupBorderSize) or 1) + 0.5)
    if size < 1 then size = 1 elseif size > 12 then size = 12 end
    local pad = math_floor((tonumber(conf.groupBorderPadding) or 2) + 0.5)
    if pad < 0 then pad = 0 elseif pad > 40 then pad = 40 end

    ApplyGroupBorderStyle(border, conf, size)
    border:ClearAllPoints()
    border:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left - pad, bottom - pad)
    border:SetSize((right - left) + pad * 2, (top - bottom) + pad * 2)
    border:Show()
end

function GF.RefreshPreviewGroupBorder(kind)
    kind = kind or "party"
    if _G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()) then return end
    local container = GF._previewContainer and GF._previewContainer[kind]
    local conf = GF.GetConf and GF.GetConf(kind)
    if not conf or conf.groupBorderEnabled ~= true
        or not (GF._previewActive and GF._previewActive[kind])
        or not container or not container.IsShown or not container:IsShown() then
        local border = GF.previewGroupBorders and GF.previewGroupBorders[kind]
        if border then border:Hide() end
        return
    end

    local border = EnsurePreviewGroupBorder(kind, container)

    local cL, cB = container:GetLeft(), container:GetBottom()
    if not cL or not cB then
        border:Hide()
        return
    end
    local containerScale = (container.GetEffectiveScale and container:GetEffectiveScale()) or 1
    if containerScale == 0 then containerScale = 1 end

    local left, right, top, bottom
    local frames = GF._previewFrames and GF._previewFrames[kind]
    if frames then
        for i = 1, #frames do
            local f = frames[i]
            if f and f._msufGFIsPreviewFrame and f.IsShown and f:IsShown() then
                local box = f.barGroup or f
                local l, r, t, b = box:GetLeft(), box:GetRight(), box:GetTop(), box:GetBottom()
                if l and r and t and b then
                    local boxScale = (box.GetEffectiveScale and box:GetEffectiveScale()) or containerScale
                    l = ((l * boxScale) - (cL * containerScale)) / containerScale
                    r = ((r * boxScale) - (cL * containerScale)) / containerScale
                    t = ((t * boxScale) - (cB * containerScale)) / containerScale
                    b = ((b * boxScale) - (cB * containerScale)) / containerScale
                    left = left and math_min(left, l) or l
                    right = right and math_max(right, r) or r
                    top = top and math_max(top, t) or t
                    bottom = bottom and math_min(bottom, b) or b
                end
            end
        end
    end

    if not left or not right or not top or not bottom or right <= left or top <= bottom then
        border:Hide()
        return
    end

    local size = math_floor((tonumber(conf.groupBorderSize) or 1) + 0.5)
    if size < 1 then size = 1 elseif size > 12 then size = 12 end
    local pad = math_floor((tonumber(conf.groupBorderPadding) or 2) + 0.5)
    if pad < 0 then pad = 0 elseif pad > 40 then pad = 40 end

    ApplyGroupBorderStyle(border, conf, size)
    border:SetFrameLevel((container.GetFrameLevel and container:GetFrameLevel() or 0) + 40)
    border:ClearAllPoints()
    border:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", left - pad, bottom - pad)
    border:SetSize((right - left) + pad * 2, (top - bottom) + pad * 2)
    border:Show()
end

function GF.RefreshGroupBorders(kind)
    local previewActive = not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
        and GF._previewActive
    if kind then
        GF.RefreshGroupBorder(kind)
        if previewActive and previewActive[kind] then GF.RefreshPreviewGroupBorder(kind) end
        return
    end
    GF.RefreshGroupBorder("party")
    GF.RefreshGroupBorder("raid")
    GF.RefreshGroupBorder("mythicraid")
    if previewActive then
        if previewActive.party then GF.RefreshPreviewGroupBorder("party") end
        if previewActive.raid then GF.RefreshPreviewGroupBorder("raid") end
        if previewActive.mythicraid then GF.RefreshPreviewGroupBorder("mythicraid") end
    end
end

-- PERF (Stage 1): Pre-built per-kind callbacks — created once on first call, reused thereafter.
-- MSUF_ScheduleOnce deduplicates by key, replacing the old _groupBorderRefreshQueued table.
-- Saves one closure allocation + one table write per GROUP_ROSTER_UPDATE burst call.
local _GF_BorderFlushFn  = {}  -- [normalizedKind] = function (built once)
local _GF_BorderSchedKey = {}  -- [normalizedKind] = schedKey string (built once)

function GF.QueueGroupBorderRefresh(kind)
    local k = kind or "_all"
    local fn = _GF_BorderFlushFn[k]
    if not fn then
        fn = function() if GF.RefreshGroupBorders then GF.RefreshGroupBorders(kind) end end
        _GF_BorderFlushFn[k]  = fn
        _GF_BorderSchedKey[k] = "GF_BORDER_REFRESH_" .. k
    end
    local schedOnce = _G.MSUF_ScheduleOnce
    if schedOnce then
        schedOnce(_GF_BorderSchedKey[k], fn)
        return
    end
    -- Fallback when MSUF_Scheduler is not yet available (early-init only).
    GF._groupBorderRefreshQueued = GF._groupBorderRefreshQueued or {}
    if GF._groupBorderRefreshQueued[k] then return end
    GF._groupBorderRefreshQueued[k] = true
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            GF._groupBorderRefreshQueued[k] = nil
            if GF.RefreshGroupBorders then GF.RefreshGroupBorders(kind) end
        end)
    else
        GF._groupBorderRefreshQueued[k] = nil
        if GF.RefreshGroupBorders then GF.RefreshGroupBorders(kind) end
    end
end

------------------------------------------------------------------------
-- Forward declarations (Phase 2+ stubs)
------------------------------------------------------------------------
local function noop() end
GF.RegisterUnitEvents = GF.RegisterUnitEvents or noop
GF.UnregisterUnitEvents = GF.UnregisterUnitEvents or noop

------------------------------------------------------------------------
-- Visual slot anchoring
--
-- SecureGroupHeader can occasionally leave one protected child (usually the
-- first/player slot) with a stale physical width/height after roster or zone
-- relayouts. If the visual root uses SetAllPoints(child), that stale protected
-- size leaks into the bars and makes exactly one group frame look different.
-- Keep the secure button sized when possible, but make the visual root use the
-- configured slot metrics and anchor it to the same primary point as the header
-- layout. This keeps every visible bar identical even if the protected click
-- frame is briefly out of sync, and the late scans below still repair the real
-- child size out of combat.
------------------------------------------------------------------------
local function AnchorVisualRootToSlot(f, kind, w, h, force)
    if not f or not f.barGroup then return end
    local conf = GF.GetConf(kind)
    local growth = (conf and conf.growth) or "DOWN"
    local bg = f.barGroup

    if not force and bg._msufGFSlotW == w and bg._msufGFSlotH == h and bg._msufGFSlotGrowth == growth then
        return
    end
    bg._msufGFSlotW = w
    bg._msufGFSlotH = h
    bg._msufGFSlotGrowth = growth

    bg:ClearAllPoints()
    bg:SetSize(w, h)

    if growth == "UP" then
        bg:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    elseif growth == "RIGHT" then
        bg:SetPoint("LEFT", f, "LEFT", 0, 0)
    elseif growth == "LEFT" then
        bg:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    else
        bg:SetPoint("TOP", f, "TOP", 0, 0)
    end
end

function GF.GetFrameLayerLevel(f, layer, fallback)
    local lvl = tonumber(layer) or fallback or 1
    if lvl < 0 then lvl = 0 elseif lvl > 30 then lvl = 30 end

    local base = f and (f.health or f.barGroup or f)
    local baseLvl = base and base.GetFrameLevel and base:GetFrameLevel() or 0
    return baseLvl + lvl, lvl
end

GF.STRATA_EFFECT = GF.STRATA_EFFECT or _G.MSUF_EFFECT_FRAME_STRATA or "HIGH"
GF.STRATA_RANK = GF.STRATA_RANK or _G.MSUF_FRAME_STRATA_RANK
GF.ClampFrameLevel = _G.MSUF_ClampFrameLevel
GF.MaxFrameStrata = _G.MSUF_MaxFrameStrata

function GF.SyncFrameLayerAbove(child, parent, offset, strata)
    return _G.MSUF_SyncFrameLayerAbove(child, parent, offset, strata or GF.STRATA_EFFECT)
end

function GF.SetFrameLayerLevel(frame, owner, layer, fallback)
    if not (frame and frame.SetFrameLevel) then return end
    frame:SetFrameLevel(GF.GetFrameLayerLevel(owner, layer, fallback))
end

GF.LAYER_DISPEL_OVERLAY = GF.LAYER_DISPEL_OVERLAY or 6
GF.LAYER_DEBUFF_STRIPE = GF.LAYER_DEBUFF_STRIPE or 7
GF.LAYER_HIGHLIGHT_BORDER = GF.LAYER_HIGHLIGHT_BORDER or 10
local GF_DISPEL_TYPE_LAYER_KEYS = { "magic", "curse", "disease", "poison", "bleed" }

local function GetFrameOutlineInset(kind, conf)
    -- Unit frames draw the bar outline outside the bars. Keep group-frame
    -- health/power geometry unshrunk so the same thickness behaves identically.
    return 0
end

------------------------------------------------------------------------
-- Frame hierarchy builder (EQoL pattern)
------------------------------------------------------------------------
local function BuildFrameHierarchy(f, kind)
    if f._msufGFBuilt then return end
    f._msufGFBuilt = true

    -- Clear any inherited backdrop from SecureUnitButtonTemplate
    if f.SetBackdrop then f:SetBackdrop(nil) end
    if f.SetClipsChildren then f:SetClipsChildren(false) end

    local conf = GF.GetConf(kind)
    local w, h = conf.width or 120, conf.height or 40
    if GF.GetScaledFrameMetrics then
        w, h = GF.GetScaledFrameMetrics(kind)
    end
    local powerH = (GF.GetEffectivePowerHeight and GF.GetEffectivePowerHeight(kind, f.unit, f._msufGFPreviewRole, conf))
        or ((GF.GetScaledPowerHeight and GF.GetScaledPowerHeight(kind)) or (conf.powerHeight or 6))
    local inset = GetFrameOutlineInset(kind, conf)

    -- barGroup — visual container (bgFile-only, EQoL pattern)
    -- Edge tiling on SetAllPoints frames causes TexCoord crash during
    -- SecureGroupHeader reposition (0-dimension transient). Border on separate frame.
    local barGroup = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.barGroup = barGroup
    AnchorVisualRootToSlot(f, kind, w, h)
    barGroup:EnableMouse(false)
    if barGroup.SetClipsChildren then barGroup:SetClipsChildren(false) end

    barGroup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    barGroup:SetBackdropColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)

    -- Separate border frame (2-point anchored, never SetAllPoints)
    local borderFrame = CreateFrame("Frame", nil, barGroup, "BackdropTemplate")
    borderFrame:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, 0)
    borderFrame:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", 0, 0)
    borderFrame:SetFrameLevel(barGroup:GetFrameLevel() + 1)
    borderFrame:EnableMouse(false)
    f._msufGFBorderFrame = borderFrame
    if borderFrame.SetBackdrop then borderFrame:SetBackdrop(nil) end
    borderFrame:Hide()

    -- Health StatusBar
    local health = CreateFrame("StatusBar", nil, barGroup)
    health:SetStatusBarTexture(GF.ResolveBarTexture(kind))
    health:SetMinMaxValues(0, 1)
    health:SetValue(1)
    health:SetPoint("TOPLEFT", barGroup, "TOPLEFT", inset, -inset)
    health:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", -inset, powerH > 0 and (powerH + inset) or inset)
    f.health = health

    -- Health bar background
    local healthBg = health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints(health)
    healthBg:SetTexture(GF.ResolveBarBgTexture(kind))
    healthBg:SetVertexColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    f.healthBg = healthBg

    -- Health prediction overlays (children of health, below text layer)
    local hLvl = health:GetFrameLevel()

    local incomingHealBar = CreateFrame("StatusBar", nil, health)
    incomingHealBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    incomingHealBar:SetMinMaxValues(0, 1)
    incomingHealBar:SetValue(0)
    incomingHealBar:SetAllPoints(health)
    incomingHealBar:SetFrameLevel(hLvl + 1)
    incomingHealBar:Hide()
    f.incomingHealBar = incomingHealBar

    local absorbBar = CreateFrame("StatusBar", nil, health)
    absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)
    absorbBar:SetAllPoints(health)
    absorbBar:SetFrameLevel(hLvl + 2)
    absorbBar:Hide()
    f.absorbBar = absorbBar

    local healAbsorbBar = CreateFrame("StatusBar", nil, health)
    healAbsorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    healAbsorbBar:SetMinMaxValues(0, 1)
    healAbsorbBar:SetValue(0)
    healAbsorbBar:SetAllPoints(health)
    healAbsorbBar:SetFrameLevel(hLvl + 3)
    healAbsorbBar:Hide()
    f.healAbsorbBar = healAbsorbBar

    -- Dispel overlay (color wash on health bar — above absorb, below text)
    local dispelOv = CreateFrame("StatusBar", nil, barGroup)
    dispelOv:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    dispelOv:SetMinMaxValues(0, 1)
    dispelOv:SetValue(1)
    dispelOv:SetAllPoints(health)
    GF.SyncFrameLayerAbove(dispelOv, health, GF.LAYER_DISPEL_OVERLAY)
    dispelOv:SetStatusBarColor(0, 0, 0, 0)
    dispelOv:Hide()
    f._msufGFDispelOverlay = dispelOv
    f._msufGFDispelOverlays = { default = dispelOv }
    dispelOv._msufGFDOKey = "default"

    local function CreateDispelOverlayLayer(key)
        local overlay = CreateFrame("StatusBar", nil, barGroup)
        overlay:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        overlay:SetMinMaxValues(0, 1)
        overlay:SetValue(1)
        overlay:SetAllPoints(health)
        GF.SyncFrameLayerAbove(overlay, health, GF.LAYER_DISPEL_OVERLAY)
        overlay:SetStatusBarColor(0, 0, 0, 0)
        overlay._msufGFDOKey = key
        overlay:Hide()
        f._msufGFDispelOverlays[key] = overlay
        return overlay
    end
    for i = 1, #GF_DISPEL_TYPE_LAYER_KEYS do
        CreateDispelOverlayLayer("dispel:" .. GF_DISPEL_TYPE_LAYER_KEYS[i])
    end

    -- Debuff stripe (thin edge indicator for any debuff — above dispel overlay, below text)
    local debuffStripe = CreateFrame("StatusBar", nil, barGroup)
    debuffStripe:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    debuffStripe:SetMinMaxValues(0, 1)
    debuffStripe:SetValue(1)
    debuffStripe:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    debuffStripe:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    debuffStripe:SetHeight(3)
    GF.SyncFrameLayerAbove(debuffStripe, health, GF.LAYER_DEBUFF_STRIPE)
    debuffStripe:SetStatusBarColor(0.8, 0.2, 0.2, 0.6)
    debuffStripe:Hide()
    f._msufGFDebuffStripe = debuffStripe

    -- Name text layer
    local nameTextLayer = CreateFrame("Frame", nil, health)
    nameTextLayer:SetAllPoints(health)
    GF.SetFrameLayerLevel(nameTextLayer, f, conf.nameTextLayer, 5)
    f.nameTextLayer = nameTextLayer

    -- Health text layer (above all overlays)
    local healthTextLayer = CreateFrame("Frame", nil, health)
    healthTextLayer:SetAllPoints(health)
    GF.SetFrameLayerLevel(healthTextLayer, f, conf.textLayer, 5)
    f.healthTextLayer = healthTextLayer

    -- Name text
    local nameText = nameTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetJustifyH("LEFT")
    f.nameText = nameText
    f.name = nameText

    -- 3-slot health text: left / center / right
    local textLeftFS = healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textLeftFS:SetJustifyH("LEFT")
    textLeftFS:SetText("")
    f.textLeftFS = textLeftFS

    local textCenterFS = healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textCenterFS:SetJustifyH("CENTER")
    textCenterFS:SetText("")
    f.textCenterFS = textCenterFS

    local textRightFS = healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textRightFS:SetJustifyH("RIGHT")
    textRightFS:SetText("")
    f.textRightFS = textRightFS
    f.hpText = textRightFS  -- backward compat alias

    -- Status text (OFFLINE / DEAD / GHOST — white; AFK / DND — red via GF pipeline)
    local statusText = healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetJustifyH("CENTER")
    statusText:SetTextColor(1, 1, 1, 1)
    statusText:SetText("")
    statusText:Hide()
    f.statusIndicatorText = statusText -- bridge to main MSUF status pipeline
    f._msufGFStatusText = statusText   -- GF-owned reference

    -- Group number text (raid subgroup)
    local groupNumText = healthTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupNumText:SetJustifyH("RIGHT")
    groupNumText:SetText("")
    groupNumText:Hide()
    f.groupNumberText = groupNumText

    -- Power StatusBar
    local power = CreateFrame("StatusBar", nil, barGroup)
    power:SetStatusBarTexture(GF.ResolveBarTexture(kind))
    power:SetMinMaxValues(0, 1)
    power:SetValue(1)
    if powerH > 0 then
        power:SetPoint("BOTTOMLEFT", barGroup, "BOTTOMLEFT", inset, inset)
        power:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", -inset, inset)
        power:SetHeight(powerH)
        power:Show()
    else
        power:SetPoint("BOTTOMLEFT", barGroup, "BOTTOMLEFT", inset, inset)
        power:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", -inset, inset)
        power:SetHeight(0.001)
        power:Hide()
    end
    f.power = power

    -- Power bar background
    local powerBg = power:CreateTexture(nil, "BACKGROUND")
    powerBg:SetAllPoints(power)
    powerBg:SetTexture(GF.ResolveBarBgTexture(kind))
    powerBg:SetVertexColor(conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, conf.bgA or 0.85)
    f.powerBg = powerBg

    -- Power text layer
    -- Parent to barGroup instead of the power StatusBar so power text can stay
    -- visible when the power bar itself is hidden by role/settings.
    local powerTextLayer = CreateFrame("Frame", nil, barGroup)
    powerTextLayer:SetAllPoints(barGroup)
    GF.SetFrameLayerLevel(powerTextLayer, f, conf.powerTextLayer, 2)
    f.powerTextLayer = powerTextLayer

    -- 3-slot power text: left / center / right
    local powerTextLeftFS = powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerTextLeftFS:SetJustifyH("LEFT")
    powerTextLeftFS:SetText("")
    f.powerTextLeftFS = powerTextLeftFS

    local powerTextCenterFS = powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerTextCenterFS:SetJustifyH("CENTER")
    powerTextCenterFS:SetText("")
    f.powerTextCenterFS = powerTextCenterFS

    local powerTextRightFS = powerTextLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerTextRightFS:SetJustifyH("RIGHT")
    powerTextRightFS:SetText("")
    f.powerTextRightFS = powerTextRightFS
    f.powerText = powerTextCenterFS  -- backward compat alias

    -- Status icon anchor layer. Actual status icons/text get their own child
    -- frames so their configured layer can order them against name/HP text.
    local statusIconLayer = CreateFrame("Frame", nil, barGroup)
    statusIconLayer:SetAllPoints(barGroup)
    statusIconLayer:SetFrameLevel(barGroup:GetFrameLevel() + 5)
    statusIconLayer:EnableMouse(false)
    if statusIconLayer.SetClipsChildren then statusIconLayer:SetClipsChildren(false) end
    f.statusIconLayer = statusIconLayer

    local statusTextLayer = CreateFrame("Frame", nil, barGroup)
    statusTextLayer:SetAllPoints(barGroup)
    GF.SetFrameLayerLevel(statusTextLayer, f, conf.statusTextLayer, 7)
    statusTextLayer:EnableMouse(false)
    if statusTextLayer.SetClipsChildren then statusTextLayer:SetClipsChildren(false) end
    f.statusTextLayer = statusTextLayer
    if statusText.SetParent then statusText:SetParent(statusTextLayer) end

    local function CreateLayeredStatusTexture(size, texture)
        local layerFrame = CreateFrame("Frame", nil, barGroup)
        layerFrame:SetSize(size, size)
        layerFrame:SetFrameLevel(hLvl + 1)
        layerFrame:EnableMouse(false)
        if layerFrame.SetClipsChildren then layerFrame:SetClipsChildren(false) end

        local tex = layerFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetAllPoints(layerFrame)
        if texture then tex:SetTexture(texture) end
        tex:Hide()
        tex._msufGFLayerFrame = layerFrame
        return tex
    end

    -- Role icon
    local roleIcon = CreateLayeredStatusTexture(conf.roleIconSize or 12)
    f.roleIcon = roleIcon

    -- Raid target icon
    local raidIcon = CreateLayeredStatusTexture(conf.raidMarkerSize or 14, "Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.raidIcon = raidIcon

    -- Leader icon
    local leaderIcon = CreateLayeredStatusTexture(conf.leaderIconSize or 12)
    f.leaderIcon = leaderIcon

    -- Assist icon
    local assistIcon = CreateLayeredStatusTexture(conf.assistIconSize or 12)
    f.assistIcon = assistIcon

    -- Ready check icon
    local readyCheckIcon = CreateLayeredStatusTexture(conf.readyCheckSize or 16, "Interface\\RaidFrame\\ReadyCheck-Waiting")
    f.readyCheckIcon = readyCheckIcon

    -- Summon icon
    local summonIcon = CreateLayeredStatusTexture(conf.summonIconSize or 16)
    f.summonIcon = summonIcon

    -- Resurrect icon
    local resurrectIcon = CreateLayeredStatusTexture(conf.resurrectIconSize or 16, "Interface\\RaidFrame\\Raid-Icon-Rez")
    f.resurrectIcon = resurrectIcon

    -- Phase icon
    local phaseIcon = CreateLayeredStatusTexture(conf.phaseIconSize or 14, "Interface\\TargetingFrame\\UI-PhasingIcon")
    f.phaseIcon = phaseIcon

    -- Unified highlight border (aggro/dispel/target — priority pipeline like main UF)
    local hlBorder = CreateFrame("Frame", nil, barGroup, "BackdropTemplate")
    hlBorder:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, 0)
    hlBorder:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", 0, 0)
    GF.SyncFrameLayerAbove(hlBorder, health, GF.LAYER_HIGHLIGHT_BORDER)
    hlBorder:EnableMouse(false)
    hlBorder:Hide()
    f._msufGFHighlightBorder = hlBorder
    f._msufGFHighlightBorders = { dispel = hlBorder }
    hlBorder._msufGFHLKey = "dispel"

    local function CreateHighlightBorderLayer(key)
        local border = CreateFrame("Frame", nil, barGroup, "BackdropTemplate")
        border:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, 0)
        border:SetPoint("BOTTOMRIGHT", barGroup, "BOTTOMRIGHT", 0, 0)
        GF.SyncFrameLayerAbove(border, health, GF.LAYER_HIGHLIGHT_BORDER)
        border:EnableMouse(false)
        border._msufGFHLKey = key
        border:Hide()
        f._msufGFHighlightBorders[key] = border
        return border
    end
    f._msufGFDispelHighlightBorder = hlBorder
    for i = 1, #GF_DISPEL_TYPE_LAYER_KEYS do
        CreateHighlightBorderLayer("dispel:" .. GF_DISPEL_TYPE_LAYER_KEYS[i])
    end
    CreateHighlightBorderLayer("aggro")
    CreateHighlightBorderLayer("target")
    CreateHighlightBorderLayer("focus")

    -- ClickCast integration; effects refresh this after OnEnter/OnLeave are set.
    if not f._msufGFIsPreviewFrame then GF.RegisterClickCastFrame(f, false) end

    -- Unit menu
    f.menu = function(btn)
        if btn.unit and UnitExists(btn.unit) then
            local which = "PARTY"
            if _G.IsInRaid and _G.IsInRaid() then which = "RAID_PLAYER" end
            if UnitPopup_ShowMenu then
                UnitPopup_ShowMenu(btn, which, btn.unit, UnitName(btn.unit))
            end
        end
    end
end

------------------------------------------------------------------------
-- Apply fonts to a GF frame
------------------------------------------------------------------------
local function ApplyFonts(f, kind)
    local conf = GF.GetConf(kind)
    local fontPath  = GF.ResolveFontPath(kind)
    local fontFlags = GF.ResolveFontFlags(kind)
    local fr, fg, fb = GF.ResolveFontColor(kind)
    local db = _G.MSUF_DB
    local fontKey = db and db.general and db.general.fontKey
    local fScale = conf._resolvedFrameScale or 1
    local nameSize  = conf.nameFontSize or 12
    local hpSize    = conf.hpFontSize or 10
    local powSize   = conf.powerFontSize or 9
    if fScale ~= 1 then
        nameSize = math_max(6, math_floor(nameSize * fScale + 0.5))
        hpSize   = math_max(6, math_floor(hpSize * fScale + 0.5))
        powSize  = math_max(6, math_floor(powSize * fScale + 0.5))
    end

    local safeSetFont = _G.MSUF_SetFontSafe
    local function SetFont(fs, size)
        if not fs then return end
        if type(safeSetFont) == "function" then
            safeSetFont(fs, fontPath, size, fontFlags, fontKey)
        else
            fs:SetFont(fontPath, size, fontFlags)
        end
    end

    if f.nameText then
        SetFont(f.nameText, nameSize)
        -- Name color applied dynamically per-unit in dispatchName/UpdateButton
        f.nameText:SetTextColor(fr, fg, fb, 1)
    end
    if f.textLeftFS then
        SetFont(f.textLeftFS, hpSize)
        f.textLeftFS:SetTextColor(fr, fg, fb, 0.9)
    end
    if f.textCenterFS then
        SetFont(f.textCenterFS, hpSize)
        f.textCenterFS:SetTextColor(fr, fg, fb, 0.9)
    end
    if f.textRightFS then
        SetFont(f.textRightFS, hpSize)
        f.textRightFS:SetTextColor(fr, fg, fb, 0.9)
    end
    if f.statusIndicatorText then
        local statusSize = tonumber(conf.statusTextSize)
        if statusSize then
            if fScale ~= 1 then statusSize = math_max(6, math_floor(statusSize * fScale + 0.5)) end
        else
            statusSize = nameSize + 2
        end
        SetFont(f.statusIndicatorText, statusSize)
    end
    if f.powerTextLeftFS then
        SetFont(f.powerTextLeftFS, powSize)
        f.powerTextLeftFS:SetTextColor(fr, fg, fb, 0.9)
    end
    if f.powerTextCenterFS then
        SetFont(f.powerTextCenterFS, powSize)
        f.powerTextCenterFS:SetTextColor(fr, fg, fb, 0.9)
    end
    if f.powerTextRightFS then
        SetFont(f.powerTextRightFS, powSize)
        f.powerTextRightFS:SetTextColor(fr, fg, fb, 0.9)
    end
end

------------------------------------------------------------------------
-- Layout text elements within a GF frame
------------------------------------------------------------------------
local function LayoutText(f, kind)
    local conf = GF.GetConf(kind)
    local fScale = conf._resolvedFrameScale or 1
    local pad3 = 3
    local nox = conf.nameOffsetX or 0
    local noy = conf.nameOffsetY or 0
    if fScale ~= 1 and GF.ScaleValue then
        pad3 = GF.ScaleValue(pad3, fScale, 1)
        nox = GF.ScaleValue(nox, fScale)
        noy = GF.ScaleValue(noy, fScale)
    end

    if f.nameText then
        if f.nameTextLayer and f.nameText.SetParent and f.nameText.GetParent and f.nameText:GetParent() ~= f.nameTextLayer then
            f.nameText:SetParent(f.nameTextLayer)
        end
        f.nameText:ClearAllPoints()
        local anchor = conf.nameAnchor or "LEFT"
        if anchor == "CENTER" then
            f.nameText:SetPoint("LEFT", f.health, "LEFT", pad3 + nox, noy)
            f.nameText:SetPoint("RIGHT", f.health, "RIGHT", -pad3 + nox, noy)
            f.nameText:SetJustifyH("CENTER")
        elseif anchor == "RIGHT" then
            f.nameText:SetPoint("LEFT", f.health, "LEFT", pad3 + nox, noy)
            f.nameText:SetPoint("RIGHT", f.health, "RIGHT", -pad3 + nox, noy)
            f.nameText:SetJustifyH("RIGHT")
        else
            f.nameText:SetPoint("LEFT", f.health, "LEFT", pad3 + nox, noy)
            f.nameText:SetPoint("RIGHT", f.health, "RIGHT", -pad3, noy)
            f.nameText:SetJustifyH("LEFT")
        end
        f.nameText:SetWordWrap(false)
        if GF.ShouldShowNameText and GF.ShouldShowNameText(f, conf) then f.nameText:Show() else f.nameText:Hide() end
    end
    -- 3-slot health text
    local hpTextOn = conf.showHPText ~= false
    local tl, tc, tr
    if GF.ResolveHealthTextSlots then
        tl, tc, tr = GF.ResolveHealthTextSlots(conf)
    else
        tl = hpTextOn and (conf.textLeft or "NONE") or "NONE"
        tc = hpTextOn and (conf.textCenter or "NONE") or "NONE"
        tr = hpTextOn and (conf.textRight or "NONE") or "NONE"
    end
    if f.textLeftFS then
        f.textLeftFS:ClearAllPoints()
        f.textLeftFS:SetPoint("LEFT", f.health, "LEFT", 3, 0)
        if tl ~= "NONE" then f.textLeftFS:Show() else f.textLeftFS:SetText(""); f.textLeftFS:Hide() end
    end
    if f.textCenterFS then
        f.textCenterFS:ClearAllPoints()
        f.textCenterFS:SetPoint("LEFT", f.health, "LEFT", 3, 0)
        f.textCenterFS:SetPoint("RIGHT", f.health, "RIGHT", -3, 0)
        f.textCenterFS:SetJustifyH("CENTER")
        if tc ~= "NONE" then f.textCenterFS:Show() else f.textCenterFS:SetText(""); f.textCenterFS:Hide() end
    end
    if f.textRightFS then
        f.textRightFS:ClearAllPoints()
        f.textRightFS:SetPoint("RIGHT", f.health, "RIGHT", -3, 0)
        if tr ~= "NONE" then f.textRightFS:Show() else f.textRightFS:SetText(""); f.textRightFS:Hide() end
    end
    if f.statusIndicatorText then
        local stLayer = f.statusTextLayer or f.statusIconLayer
        if stLayer and f.statusIndicatorText.SetParent and f.statusIndicatorText.GetParent
            and f.statusIndicatorText:GetParent() ~= stLayer
        then
            f.statusIndicatorText:SetParent(stLayer)
        end
        if stLayer and stLayer.SetFrameLevel and f.health and f.health.GetFrameLevel then
            GF.SetFrameLayerLevel(stLayer, f, conf.statusTextLayer, 7)
        end
        f.statusIndicatorText:ClearAllPoints()
        local anchor = conf.statusTextAnchor or "CENTER"
        local sox = conf.statusOffsetX or 0
        local soy = conf.statusOffsetY or 0
        if fScale ~= 1 and GF.ScaleValue then
            sox = GF.ScaleValue(sox, fScale)
            soy = GF.ScaleValue(soy, fScale)
        end
        f.statusIndicatorText:SetPoint(anchor, f.health, anchor, sox, soy)
        if f.statusIndicatorText.SetJustifyH then
            local j = "CENTER"
            if anchor == "TOPLEFT" or anchor == "BOTTOMLEFT" or anchor == "LEFT" then
                j = "LEFT"
            elseif anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT" or anchor == "RIGHT" then
                j = "RIGHT"
            end
            f.statusIndicatorText:SetJustifyH(j)
        end
        if f.statusIndicatorText.SetDrawLayer then
            local sub = tonumber(conf.statusTextLayer) or 7
            if sub < 0 then sub = 0 elseif sub > 7 then sub = 7 end
            f.statusIndicatorText:SetDrawLayer("OVERLAY", sub)
        end
        if f._msufGFStatusState and f._msufGFStatusState ~= 0 and GF.ApplyStatusTextStateLayout then
            GF.ApplyStatusTextStateLayout(f, conf, f._msufGFStatusState)
        end
    end
    if f.powerTextLeftFS then
        f.powerTextLeftFS:ClearAllPoints()
        f.powerTextLeftFS:SetPoint("LEFT", f.power, "LEFT", 2, 0)
    end
    if f.powerTextCenterFS then
        f.powerTextCenterFS:ClearAllPoints()
        f.powerTextCenterFS:SetPoint("CENTER", f.power, "CENTER", 0, 0)
    end
    if f.powerTextRightFS then
        f.powerTextRightFS:ClearAllPoints()
        f.powerTextRightFS:SetPoint("RIGHT", f.power, "RIGHT", -2, 0)
    end
    do
        local effectivePowerH = (GF.GetEffectivePowerHeight and GF.GetEffectivePowerHeight(kind, f.unit, f._msufGFPreviewRole, conf))
            or ((GF.GetScaledPowerHeight and GF.GetScaledPowerHeight(kind)) or (conf.powerHeight or 6))
        local showPowerText = (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(kind, conf)) or false
        local ptl = showPowerText and (conf.powerTextLeft   or "NONE") or "NONE"
        local ptc = showPowerText and (conf.powerTextCenter  or "NONE") or "NONE"
        local ptr = showPowerText and (conf.powerTextRight   or "NONE") or "NONE"
        local anchor = (effectivePowerH > 0 and f.power) or f.health or f.barGroup or f
        if f.powerTextLeftFS then
            f.powerTextLeftFS:ClearAllPoints()
            f.powerTextLeftFS:SetPoint("LEFT", anchor, "LEFT", 2, 0)
            if ptl ~= "NONE" then f.powerTextLeftFS:Show() else f.powerTextLeftFS:Hide() end
        end
        if f.powerTextCenterFS then
            f.powerTextCenterFS:ClearAllPoints()
            f.powerTextCenterFS:SetPoint("CENTER", anchor, "CENTER", 0, 0)
            if ptc ~= "NONE" then f.powerTextCenterFS:Show() else f.powerTextCenterFS:Hide() end
        end
        if f.powerTextRightFS then
            f.powerTextRightFS:ClearAllPoints()
            f.powerTextRightFS:SetPoint("RIGHT", anchor, "RIGHT", -2, 0)
            if ptr ~= "NONE" then f.powerTextRightFS:Show() else f.powerTextRightFS:Hide() end
        end
    end
    if f.nameTextLayer and f.health then
        f.nameTextLayer:ClearAllPoints()
        f.nameTextLayer:SetAllPoints(f.health)
        GF.SetFrameLayerLevel(f.nameTextLayer, f, conf.nameTextLayer, 5)
    end
    if f.healthTextLayer and f.health then
        GF.SetFrameLayerLevel(f.healthTextLayer, f, conf.textLayer, 5)
    end
    if f.powerTextLayer then
        GF.SetFrameLayerLevel(f.powerTextLayer, f, conf.powerTextLayer, 2)
    end
end

------------------------------------------------------------------------
-- Layout status icons
------------------------------------------------------------------------
local ROLE_TEXTURES = {
    TANK    = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    HEALER  = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    DAMAGER = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
}
local ROLE_COORDS = {
    TANK    = { 0,    19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64,  20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}

local function LayoutIcons(f, kind)
    local conf = GF.GetConf(kind)
    local anchor = f.statusIconLayer or f.barGroup or f
    local base = f.health or anchor
    local baseLvl = base.GetFrameLevel and base:GetFrameLevel() or anchor:GetFrameLevel()
    local fScale = conf._resolvedFrameScale or 1

    local function lay(icon, sizeKey, defSz, anchorKey, defPt, xKey, yKey, layerKey, defLayer)
        if not icon then return end
        local region = icon._msufGFLayerFrame or icon
        region:ClearAllPoints()
        local sz = conf[sizeKey] or defSz
        if fScale ~= 1 then sz = math_max(4, math_floor(sz * fScale + 0.5)) end
        region:SetSize(sz, sz)
        local pt = conf[anchorKey] or defPt
        local ox = conf[xKey] or 0
        local oy = conf[yKey] or 0
        if fScale ~= 1 and GF.ScaleValue then
            ox = GF.ScaleValue(ox, fScale)
            oy = GF.ScaleValue(oy, fScale)
        end
        region:SetPoint(pt, anchor, pt, ox, oy)
        local layer = tonumber(conf[layerKey]) or defLayer or 1
        if layer < 0 then layer = 0 elseif layer > 30 then layer = 30 end
        if region.SetFrameLevel then
            region:SetFrameLevel((GF.GetFrameLayerLevel and GF.GetFrameLayerLevel(f, layer, defLayer)) or (baseLvl + layer))
        end
        if region ~= icon then
            icon:ClearAllPoints()
            icon:SetAllPoints(region)
        end
        if icon.SetDrawLayer then icon:SetDrawLayer("OVERLAY", 7) end
    end

    lay(f.roleIcon,       "roleIconSize",      12, "roleIconAnchor",   "TOPLEFT",  "roleIconX",   "roleIconY",   "roleIconLayer",   1)
    lay(f.leaderIcon,     "leaderIconSize",     12, "leaderIconAnchor", "TOPRIGHT", "leaderIconX", "leaderIconY", "leaderIconLayer", 2)
    lay(f.assistIcon,     "assistIconSize",     12, "assistIconAnchor", "TOPRIGHT", "assistIconX", "assistIconY", "assistIconLayer", 2)
    lay(f.raidIcon,       "raidMarkerSize",     14, "raidMarkerAnchor", "CENTER",   "raidMarkerX", "raidMarkerY", "raidMarkerLayer", 3)
    lay(f.readyCheckIcon, "readyCheckSize",     16, "readyCheckAnchor", "CENTER",   "readyCheckX", "readyCheckY", "readyCheckLayer", 4)
    lay(f.summonIcon,     "summonIconSize",     16, "summonAnchor",     "CENTER",   "summonX",     "summonY",     "summonLayer", 4)
    lay(f.resurrectIcon,  "resurrectIconSize",  16, "resurrectAnchor",  "CENTER",   "resurrectX",  "resurrectY",  "resurrectLayer", 4)
    lay(f.phaseIcon,      "phaseIconSize",      14, "phaseAnchor",      "TOPLEFT",  "phaseX",      "phaseY",      "phaseLayer", 3)
end

------------------------------------------------------------------------
-- Init a single unit button (post-creation, NOT in initialConfigFunction)
------------------------------------------------------------------------
local function GF_InitButton(f, kind)
    f._msufIsGroupFrame = true
    f._msufGFKind = kind
    f.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ((kind == "raid") and "gf_raid" or "gf_party")

    -- RegisterForClicks MUST happen here, NOT in initialConfigFunction
    if f.RegisterForClicks then
        f:RegisterForClicks("AnyUp")
    end

    BuildFrameHierarchy(f, kind)
    ApplyFonts(f, kind)
    LayoutText(f, kind)
    LayoutIcons(f, kind)
    if GF.LayoutCornerIndicators then GF.LayoutCornerIndicators(f, kind) end

    -- Size hook
    if not f._msufGFSizeHooked then
        f._msufGFSizeHooked = true
        f:HookScript("OnSizeChanged", function(btn)
            LayoutText(btn, btn._msufGFKind or "party")
            LayoutIcons(btn, btn._msufGFKind or "party")
            if GF.LayoutCornerIndicators then GF.LayoutCornerIndicators(btn, btn._msufGFKind or "party") end
        end)
    end

    f:SetClampedToScreen(true)

    -- Track in the live-frame registry used by refresh/effect sweeps.
    RegisterTrackedFrame(f, kind)
end

------------------------------------------------------------------------
-- Update health color for a GF frame
------------------------------------------------------------------------
local function ApplyHealthColor(f, kind, unit)
    if not f.health then return end
    -- Delegate to Render pipeline if available (respects global barMode)
    if GF.ApplyVisuals then
        GF.ApplyVisuals(f, 0x08) -- DIRTY_COLOR
        return
    end
    -- Fallback: basic class color
    local conf = GF.GetConf(kind)
    if unit then
        local _, cls = UnitClass(unit)
        local cc = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        if cc then
            f.health:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
            return
        end
    end
    f.health:SetStatusBarColor(
        conf.healthCustomR or 0.2,
        conf.healthCustomG or 0.8,
        conf.healthCustomB or 0.2, 1)
end

------------------------------------------------------------------------
-- Update power color
------------------------------------------------------------------------
local function ApplyPowerColor(f, unit)
    if not (f.power and unit) then return end
    if not UnitExists(unit) then return end
    local _, pToken = UnitPowerType(unit)
    -- Secret-safe: pToken may be secret in 12.0.
    if issecretvalue and pToken and issecretvalue(pToken) then
        f.power:SetStatusBarColor(0.5, 0.5, 0.8, 1)
        return
    end
    local r, g, b = ResolvePowerBarColor(pToken)
    f.power:SetStatusBarColor(r, g, b, 1)
end

local function _GF_CoreIconShow(icon)
    if icon and icon.IsShown and not icon:IsShown() then icon:Show() end
end

local function _GF_CoreIconHide(icon)
    if icon and icon.IsShown and icon:IsShown() then icon:Hide() end
end

local function _GF_CoreIconSetTexture(icon, texture)
    if not icon or icon._msufGFCachedTexture == texture then return end
    icon._msufGFCachedTexture = texture
    icon:SetTexture(texture)
end

local function _GF_CoreIconSetTexCoord(icon, l, r, t, b)
    if not icon then return end
    if icon._msufGFTexL == l and icon._msufGFTexR == r
        and icon._msufGFTexT == t and icon._msufGFTexB == b
    then
        return
    end
    icon._msufGFTexL = l
    icon._msufGFTexR = r
    icon._msufGFTexT = t
    icon._msufGFTexB = b
    icon:SetTexCoord(l, r, t, b)
end

local function _GF_CoreIconSetTextureAndCoords(icon, texture, l, r, t, b)
    _GF_CoreIconSetTexture(icon, texture)
    if l ~= nil then _GF_CoreIconSetTexCoord(icon, l, r, t, b) end
end

------------------------------------------------------------------------
-- Update all visuals for a unit (called on roster change + events)
------------------------------------------------------------------------
function GF.UpdateButton(f, unit)
    if not f or not unit then return end
    local kind = f._msufGFKind or "party"
    if GF.IsKindEnabled and not f._msufGFPreviewActive and not GF.IsKindEnabled(kind) then return end
    local conf = GF.GetConf(kind)
    if f._msufGFOfflineActive and (_G.MSUF_InCombat ~= true or f._msufGFOfflineCombatAllowed)
        and GF.UpdateOfflineHiddenFrame and GF.UpdateOfflineHiddenFrame(f, unit)
    then
        return
    end

    if not UnitExists(unit) then
        if f.nameText then f.nameText:SetText("") end
        if f.textLeftFS then f.textLeftFS:SetText("") end
        if f.textCenterFS then f.textCenterFS:SetText("") end
        if f.textRightFS then f.textRightFS:SetText("") end
        if f.health then f.health:SetValue(0) end
        if GF.SyncPreserveMissingHP then GF.SyncPreserveMissingHP(f, kind, 1, 1) end
        if f.power then f.power:SetValue(0) end
        if f.powerTextLeftFS then f.powerTextLeftFS:SetText("") end
        if f.powerTextCenterFS then f.powerTextCenterFS:SetText("") end
        if f.powerTextRightFS then f.powerTextRightFS:SetText("") end
        if f.roleIcon then f.roleIcon:Hide() end
        if f.raidIcon then f.raidIcon:Hide() end
        if f.leaderIcon then f.leaderIcon:Hide() end
        if f.assistIcon then f.assistIcon:Hide() end
        if f.readyCheckIcon then f.readyCheckIcon:Hide() end
        if f.summonIcon then f.summonIcon:Hide() end
        if f.resurrectIcon then f.resurrectIcon:Hide() end
        if f.phaseIcon then f.phaseIcon:Hide() end
        if f.statusIndicatorText then f.statusIndicatorText:SetText(""); f.statusIndicatorText:Hide() end
        f._msufGFStatusState = 0
        f._msufGFStatusDirty = nil
        return
    end

    -- Name (with color mode + truncation)
    if f.nameText and GF.ShouldShowNameText and GF.ShouldShowNameText(f, conf) then
        local name = UnitName(unit) or ""
        local maxC, noEllipsis, clipSide = GF.ResolveNameTruncation(kind)
        if maxC > 0 then
            name = GF.TruncateName(name, maxC, noEllipsis, clipSide)
        end
        f.nameText:SetText(name)
        f.nameText:Show()
        -- Apply name color
        local _, classToken = UnitClass(unit)
        local nr, ng, nb = GF.ResolveNameColor(kind, classToken)
        f.nameText:SetTextColor(nr, ng, nb, 1)
    end

    -- Health (secret-safe: pass raw values to C-side SetValue/SetMinMaxValues)
    if f.health then
        local hp    = UnitHealth(unit)
        local hpMax = UnitHealthMax(unit)
        f.health:SetMinMaxValues(0, hpMax)
        f.health:SetValue(hp)
        f._msufGFCachedHpMax = hpMax
        if GF.SyncPreserveMissingHP then
            GF.SyncPreserveMissingHP(f, kind, hp, hpMax)
        end
    end

    ApplyHealthColor(f, kind, unit)

    -- 3-slot health text (secret-safe: unit passed for UnitHealthPercent)
    do
        local hp    = UnitHealth(unit)
        local hpMax = UnitHealthMax(unit)
        local delim = conf.textDelimiter or " / "
        local hpTextOn = conf.showHPText ~= false
        local tl, tc, tr
        if GF.ResolveHealthTextSlots then
            tl, tc, tr = GF.ResolveHealthTextSlots(conf)
        else
            tl = hpTextOn and (conf.textLeft or "NONE") or "NONE"
            tc = hpTextOn and (conf.textCenter or "NONE") or "NONE"
            tr = hpTextOn and (conf.textRight or "NONE") or "NONE"
        end
        if f.textLeftFS then
            local txt = GF.FormatHealthText(tl, hp, hpMax, delim, false, unit)
            f.textLeftFS:SetText(txt)
            if tl ~= "NONE" then f.textLeftFS:Show() else f.textLeftFS:Hide() end
        end
        if f.textCenterFS then
            local txt = GF.FormatHealthText(tc, hp, hpMax, delim, false, unit)
            f.textCenterFS:SetText(txt)
            if tc ~= "NONE" then f.textCenterFS:Show() else f.textCenterFS:Hide() end
        end
        if f.textRightFS then
            local txt = GF.FormatHealthText(tr, hp, hpMax, delim, false, unit)
            f.textRightFS:SetText(txt)
            if tr ~= "NONE" then f.textRightFS:Show() else f.textRightFS:Hide() end
        end
    end

    -- Power (secret-safe: raw values to C-side) + independent power text
    if f.power then
        local role = (GF.GetUnitGroupRole and GF.GetUnitGroupRole(unit))
            or ((UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) or "DAMAGER")
        local powerH = (GF.GetEffectivePowerHeight and GF.GetEffectivePowerHeight(kind, unit, role, conf)) or (conf.powerHeight or 6)
        local showPow = powerH > 0
        local roleHidden = not showPow
        local prevRoleHidden = f._msufGFPowRoleHidden
        if prevRoleHidden ~= nil and prevRoleHidden ~= roleHidden and not (InCombatLockdown and InCombatLockdown()) and GF.MarkDirty then
            GF.MarkDirty(f, (GF.DIRTY_GEOMETRY or 0x01) + (GF.DIRTY_LAYOUT or 0x20))
        end
        f._msufGFPowRoleHidden = roleHidden

        local powerTextOn = (GF.HasActivePowerTextSlot and GF.HasActivePowerTextSlot(kind, conf)) or false
        if showPow or powerTextOn then
            local pw    = UnitPower(unit)
            local pwMax = UnitPowerMax(unit)
            f._msufGFCachedPwMax = pwMax

            if showPow then
                f.power:SetMinMaxValues(0, pwMax)
                if conf.powerSmoothFill then
                    local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
                    if interp then f.power:SetValue(pw, interp) else f.power:SetValue(pw) end
                else
                    f.power:SetValue(pw)
                end
                f.power:Show()
                ApplyPowerColor(f, unit)
            else
                f.power:Hide()
            end

            if powerTextOn then
                local pDelim = conf.powerTextDelimiter or " / "
                local ptl = conf.powerTextLeft   or "NONE"
                local ptc = conf.powerTextCenter  or "NONE"
                local ptr = conf.powerTextRight   or "NONE"
                if f.powerTextLeftFS then
                    f.powerTextLeftFS:SetText(GF.FormatPowerText(ptl, pw, pwMax, pDelim, unit))
                    if ptl ~= "NONE" then f.powerTextLeftFS:Show() else f.powerTextLeftFS:Hide() end
                end
                if f.powerTextCenterFS then
                    f.powerTextCenterFS:SetText(GF.FormatPowerText(ptc, pw, pwMax, pDelim, unit))
                    if ptc ~= "NONE" then f.powerTextCenterFS:Show() else f.powerTextCenterFS:Hide() end
                end
                if f.powerTextRightFS then
                    f.powerTextRightFS:SetText(GF.FormatPowerText(ptr, pw, pwMax, pDelim, unit))
                    if ptr ~= "NONE" then f.powerTextRightFS:Show() else f.powerTextRightFS:Hide() end
                end
            else
                if f.powerTextLeftFS then f.powerTextLeftFS:SetText(""); f.powerTextLeftFS:Hide() end
                if f.powerTextCenterFS then f.powerTextCenterFS:SetText(""); f.powerTextCenterFS:Hide() end
                if f.powerTextRightFS then f.powerTextRightFS:SetText(""); f.powerTextRightFS:Hide() end
            end
        else
            f.power:Hide()
            if f.powerTextLeftFS then f.powerTextLeftFS:SetText(""); f.powerTextLeftFS:Hide() end
            if f.powerTextCenterFS then f.powerTextCenterFS:SetText(""); f.powerTextCenterFS:Hide() end
            if f.powerTextRightFS then f.powerTextRightFS:SetText(""); f.powerTextRightFS:Hide() end
        end
    end

    -- Role icon
    if f.roleIcon then
        if conf.roleIcon ~= false then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            if role and role ~= "NONE" then
                local tex, l, r, t, b = GF.GetRoleTexture(kind, role)
                if tex then
                    _GF_CoreIconSetTextureAndCoords(f.roleIcon, tex, l, r, t, b)
                    _GF_CoreIconShow(f.roleIcon)
                else
                    _GF_CoreIconHide(f.roleIcon)
                end
            else
                _GF_CoreIconHide(f.roleIcon)
            end
        else
            _GF_CoreIconHide(f.roleIcon)
        end
    end

    -- Raid target marker
    if f.raidIcon then
        if conf.raidMarker ~= false then
            local idx = GetRaidTargetIndex(unit)
            if idx then
                -- Midnight/Beta can return a secret number here. Do not cache
                -- or compare it in Lua; hand it directly to the C-side helper.
                f.raidIcon._msufGFRaidMarkerIndex = nil
                f.raidIcon._msufGFCachedTexture = nil
                SetRaidTargetIconTexture(f.raidIcon, idx)
                _GF_CoreIconShow(f.raidIcon)
            else
                _GF_CoreIconHide(f.raidIcon)
                f.raidIcon._msufGFRaidMarkerIndex = nil
            end
        else
            _GF_CoreIconHide(f.raidIcon)
            f.raidIcon._msufGFRaidMarkerIndex = nil
        end
    end

    -- Leader icon (crown only, no assist)
    if f.leaderIcon then
        if conf.leaderIcon ~= false then
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
            if isLeader then
                local tex, l, r, t, b = GF.GetLeaderTexture(kind)
                _GF_CoreIconSetTextureAndCoords(f.leaderIcon, tex, l, r, t, b)
                _GF_CoreIconShow(f.leaderIcon)
            else
                _GF_CoreIconHide(f.leaderIcon)
            end
        else
            _GF_CoreIconHide(f.leaderIcon)
        end
    end

    -- Assist icon (separate, shield only)
    if f.assistIcon then
        if conf.assistIcon ~= false then
            local isAssist = UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
            if isAssist and not isLeader then
                local tex, l, r, t, b = GF.GetAssistTexture(kind)
                _GF_CoreIconSetTextureAndCoords(f.assistIcon, tex, l, r, t, b)
                _GF_CoreIconShow(f.assistIcon)
            else
                _GF_CoreIconHide(f.assistIcon)
            end
        else
            _GF_CoreIconHide(f.assistIcon)
        end
    end
end

------------------------------------------------------------------------
-- Scan header children and init them
------------------------------------------------------------------------
local function _SetFrameSizeIfChanged(frame, w, h)
    if not frame then return end
    local cw = frame.GetWidth and frame:GetWidth()
    local ch = frame.GetHeight and frame:GetHeight()
    if cw ~= w then frame:SetWidth(w) end
    if ch ~= h then frame:SetHeight(h) end
end

local function _SetShownIfChanged(frame, shown)
    if not frame then return end
    shown = shown and true or false
    if frame.IsShown and frame:IsShown() == shown then return end
    if shown then frame:Show() else frame:Hide() end
end

local function _AnchorTwoPointIfChanged(frame, owner, key, tlx, tly, brx, bry, force)
    if not frame or not owner then return end
    if not force
        and frame._msufGFScanAnchorOwner == owner
        and frame._msufGFScanAnchorKey == key
        and frame._msufGFScanTLX == tlx
        and frame._msufGFScanTLY == tly
        and frame._msufGFScanBRX == brx
        and frame._msufGFScanBRY == bry
    then
        return
    end
    frame._msufGFScanAnchorOwner = owner
    frame._msufGFScanAnchorKey = key
    frame._msufGFScanTLX = tlx
    frame._msufGFScanTLY = tly
    frame._msufGFScanBRX = brx
    frame._msufGFScanBRY = bry
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", owner, "TOPLEFT", tlx, tly)
    frame:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", brx, bry)
end

local function _ScanHeaderChildrenVarargs(header, kind, force, ...)
    if not header then return end
    if GF.IsKindEnabled and not GF.IsKindEnabled(kind) then
        if GF.DeactivateKindRuntime then GF.DeactivateKindRuntime(kind, false) end
        return
    end
    -- Throttle normal GROUP_ROSTER_UPDATE bursts. Forced scans are still
    -- allowed for the post-layout repair pass, but identical forced scans
    -- inside the same short burst are skipped.
    local now = (GetTime and GetTime()) or 0
    if force then
        local scanKey = tostring(kind) .. ":" .. tostring(_headerScanInputSerial)
        if header._msufGFLastForceScanKey == scanKey
            and header._msufGFLastForceScanAt
            and (now - header._msufGFLastForceScanAt) < 0.04
        then
            return
        end
        header._msufGFLastForceScanKey = scanKey
        header._msufGFLastForceScanAt = now
    else
        if header._msufGFLastScan and (now - header._msufGFLastScan) < 0.05 then return end
        header._msufGFLastScan = now
    end

    -- Protected frames: cannot call SetSize/SetPoint in combat
    local inCombat = InCombatLockdown()
    local conf = GF.GetConf(kind)
    local w, h = conf.width or (IsRaidLikeKind(kind) and 80 or 120), conf.height or (IsRaidLikeKind(kind) and 32 or 40)
    if GF.GetScaledFrameMetrics then
        w, h = GF.GetScaledFrameMetrics(kind)
    end

    local firstMeasured = false
    local childCount = select("#", ...)
    for ci = 1, childCount do
        local child = select(ci, ...)
        -- Install OnAttributeChanged hook on every child BEFORE filtering by
        -- unit attribute. Children whose unit isn't set yet (secure code
        -- hasn't ticked) will get registered the moment the secure system
        -- assigns one — bypasses the timing race between header:Show() and
        -- the secure unit-token assignment pass.
        _GFInstallAttrHook(child)
        -- Skip non-button children (anchor frames, etc.)
        if child and child.GetAttribute and child:GetAttribute("unit") ~= nil then
            if not child._msufGFBuilt then
                if inCombat then
                    MarkPostCombatHeaderRecovery()
                    break
                end
                _G.MSUF_GF_InitButton(child, kind)
            end
            child._msufGFKind = kind
            child.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ("gf_" .. tostring(kind))
            local unit = child:GetAttribute("unit") or child.unit
            -- Keep child slot size aligned with configured metrics.
            -- Use SetWidth + SetHeight separately (SetSize can be ignored when
            -- SecureGroupHeader has set conflicting anchor points on children).
            if not inCombat then
                _SetFrameSizeIfChanged(child, w, h)

                -- Clear any backdrop on child frame itself
                -- (SecureUnitButtonTemplate may inherit BackdropTemplate in WoW 12.0)
                if child.SetBackdrop and not child._msufGFChildBackdropCleared then
                    child:SetBackdrop(nil)
                    child._msufGFChildBackdropCleared = true
                end

                -- Re-anchor the visual root to configured slot metrics.
                -- Do not SetAllPoints(child): the protected child can be the
                -- stale part; the visual bars must remain normalized.
                AnchorVisualRootToSlot(child, kind, w, h, force)

                -- borderFrame
                if child._msufGFBorderFrame then
                    _AnchorTwoPointIfChanged(child._msufGFBorderFrame, child.barGroup or child, "border", 0, 0, 0, 0, force)
                end

                -- highlightBorder
                if child._msufGFHighlightBorders then
                    for _, border in pairs(child._msufGFHighlightBorders) do
                        if border then
                            local hofs = border._msufHLOfs or 0
                            _AnchorTwoPointIfChanged(border, child.barGroup or child, "highlight", -hofs, hofs, hofs, -hofs, force)
                            GF.SyncFrameLayerAbove(border, child.health or child.barGroup or child, border._msufHLLayerOffset or GF.LAYER_HIGHLIGHT_BORDER)
                        end
                    end
                elseif child._msufGFHighlightBorder then
                    local hofs = child._msufGFHighlightBorder._msufHLOfs or 0
                    _AnchorTwoPointIfChanged(child._msufGFHighlightBorder, child.barGroup or child, "highlight", -hofs, hofs, hofs, -hofs, force)
                    GF.SyncFrameLayerAbove(child._msufGFHighlightBorder, child.health or child.barGroup or child, child._msufGFHighlightBorder._msufHLLayerOffset or GF.LAYER_HIGHLIGHT_BORDER)
                end
                if child._msufGFDispelOverlays then
                    for _, overlay in pairs(child._msufGFDispelOverlays) do
                        if overlay then
                            GF.SyncFrameLayerAbove(overlay, child.health or child.barGroup or child, overlay._msufDOLayerOffset or GF.LAYER_DISPEL_OVERLAY)
                        end
                    end
                elseif child._msufGFDispelOverlay then
                    GF.SyncFrameLayerAbove(child._msufGFDispelOverlay, child.health or child.barGroup or child, child._msufGFDispelOverlay._msufDOLayerOffset or GF.LAYER_DISPEL_OVERLAY)
                end
                if child._msufGFDebuffStripe then
                    GF.SyncFrameLayerAbove(child._msufGFDebuffStripe, child.health or child.barGroup or child, GF.LAYER_DEBUFF_STRIPE)
                end

                -- health bar
                local inset = GetFrameOutlineInset(kind, conf)
                local powerH = (GF.GetEffectivePowerHeight and GF.GetEffectivePowerHeight(kind, unit, nil, conf))
                    or ((GF.GetScaledPowerHeight and GF.GetScaledPowerHeight(kind)) or (conf.powerHeight or 6))
                if child.health then
                    _AnchorTwoPointIfChanged(child.health, child.barGroup or child, "health", inset, -inset, -inset, powerH > 0 and (powerH + inset) or inset, force)
                end

                -- power bar
                if child.power then
                    local owner = child.barGroup or child
                    if force
                        or child.power._msufGFScanAnchorOwner ~= owner
                        or child.power._msufGFScanAnchorKey ~= "power"
                        or child.power._msufGFScanTLX ~= inset
                        or child.power._msufGFScanTLY ~= inset
                        or child.power._msufGFScanBRX ~= -inset
                        or child.power._msufGFScanBRY ~= inset
                    then
                        child.power._msufGFScanAnchorOwner = owner
                        child.power._msufGFScanAnchorKey = "power"
                        child.power._msufGFScanTLX = inset
                        child.power._msufGFScanTLY = inset
                        child.power._msufGFScanBRX = -inset
                        child.power._msufGFScanBRY = inset
                        child.power:ClearAllPoints()
                        child.power:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", inset, inset)
                        child.power:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -inset, inset)
                    end
                    if powerH > 0 then
                        if child.power.GetHeight and child.power:GetHeight() ~= powerH then child.power:SetHeight(powerH) end
                        _SetShownIfChanged(child.power, true)
                    else
                        if child.power.GetHeight and child.power:GetHeight() ~= 0.001 then child.power:SetHeight(0.001) end
                        _SetShownIfChanged(child.power, false)
                    end
                end
            end

            if not firstMeasured and header.GetCenter and child.GetCenter then
                firstMeasured = true
                local hx, hy = header:GetCenter()
                local cx, cy = child:GetCenter()
                if hx and hy and cx and cy then
                    local hs = (header.GetEffectiveScale and header:GetEffectiveScale()) or 1
                    local cs = (child.GetEffectiveScale and child:GetEffectiveScale()) or 1
                    if hs == 0 then hs = 1 end
                    if cs == 0 then cs = 1 end
                    GF._measuredFirstCenterDelta = GF._measuredFirstCenterDelta or {}
                    GF._measuredFirstCenterDelta[kind] = {
                        x = (cx * cs - hx * hs) / hs,
                        y = (cy * cs - hy * hs) / hs,
                    }
                end
            end

            if unit then
                child.unit = unit
                local p = unit:sub(1, 5)
                if p == "party" or unit:sub(1, 4) == "raid" then
                    _G.MSUF_UnitFrames[unit] = child
                end
                if child._msufGFRegisteredUnit ~= unit then
                    child._msufGFRegisteredUnit = unit
                    if not inCombat and GF.ApplyVisuals then
                        GF.ApplyVisuals(child, GF.DIRTY_ALL or 0x3F)
                    end
                    GF.UpdateButton(child, unit)
                    GF.RegisterUnitEvents(child, unit)
                end
            end
        end
    end

    -- After measuring delta, reposition header
    if not inCombat and GF.SyncHeaderPosition then
        GF.SyncHeaderPosition(kind, nil, header)
    end
    if GF.QueueGroupBorderRefresh then GF.QueueGroupBorderRefresh(kind) end
end

local function ScanHeaderChildren(header, kind, force)
    if not header then return end
    -- GetChildren() is more reliable than GetAttribute("child"..i) for
    -- SecureGroupHeader. Forwarding varargs avoids allocating a temporary
    -- child table on every roster/header scan.
    return _ScanHeaderChildrenVarargs(header, kind, force, header:GetChildren())
end

------------------------------------------------------------------------
-- Grid-center positioning helpers
------------------------------------------------------------------------
GF._previewAnchorFrame = GF._previewAnchorFrame or {}

local GetDefaultCenter
local RaidGroupAllowed

local function IsRaidLikeKind(kind)
    return kind == "raid" or kind == "mythicraid"
end

local function GetLiveRaidKind()
    return (GF.GetLiveRaidKind and GF.GetLiveRaidKind()) or "raid"
end

GF.raidGroupHeaders = GF.raidGroupHeaders or {}

local function PreserveRaidGroups(kind, conf)
    conf = conf or GF.GetConf(kind)
    return IsRaidLikeKind(kind) and conf and conf.preserveRaidGroups == true
end

local function GetPreservedRaidGroupCount(conf)
    local groups = math_floor((tonumber(conf and conf.maxColumns) or 8) + 0.5)
    if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
    if IsInRaid and IsInRaid() and GetNumGroupMembers and GetRaidRosterInfo then
        local liveGroups = 0
        local n = GetNumGroupMembers() or 0
        for i = 1, n do
            local subgroup = select(3, GetRaidRosterInfo(i))
            subgroup = tonumber(subgroup) or 0
            if subgroup > liveGroups then liveGroups = subgroup end
        end
        if liveGroups > groups then groups = liveGroups end
        if groups > 8 then groups = 8 end
    end
    return groups
end
GF.GetPreservedRaidGroupCount = GetPreservedRaidGroupCount

local function GetPreservedRaidPrimary(conf)
    local upc = math_floor((tonumber(conf and conf.unitsPerColumn) or 5) + 0.5)
    if upc < 1 then upc = 1 elseif upc > 40 then upc = 40 end
    local primary = math_min(upc, 5)
    local columns = math_ceil(5 / primary)
    if columns < 1 then columns = 1 end
    return upc, primary, columns
end

local function GetPreservedRaidMetrics(kind, conf)
    conf = conf or GF.GetConf(kind)
    local _, _, totalW, totalH, w, h, spacing, growth, _, _, _, _, primary, groups, blockColumns, blockW, blockH
    if GF.GetPreservedRaidGridMetrics then
        _, _, totalW, totalH, w, h, spacing, growth, _, _, _, _, primary, groups, blockColumns, blockW, blockH =
            GF.GetPreservedRaidGridMetrics(kind, 5 * GetPreservedRaidGroupCount(conf))
    end
    if totalW then
        return totalW, totalH, w, h, spacing, growth, primary, groups, blockColumns, blockW, blockH
    end

    w, h, spacing = GF.GetScaledFrameMetrics(kind)
    growth = conf.growth or "DOWN"
    local _, primaryFallback, columnsFallback = GetPreservedRaidPrimary(conf)
    local groupsFallback = GetPreservedRaidGroupCount(conf)
    if growth == "DOWN" or growth == "UP" then
        blockW = columnsFallback * w + math_max(0, columnsFallback - 1) * spacing
        blockH = primaryFallback * h + math_max(0, primaryFallback - 1) * spacing
        totalW = groupsFallback * blockW + math_max(0, groupsFallback - 1) * spacing
        totalH = blockH
    else
        blockW = primaryFallback * w + math_max(0, primaryFallback - 1) * spacing
        blockH = columnsFallback * h + math_max(0, columnsFallback - 1) * spacing
        totalW = blockW
        totalH = groupsFallback * blockH + math_max(0, groupsFallback - 1) * spacing
    end
    return totalW, totalH, w, h, spacing, growth, primaryFallback, groupsFallback, columnsFallback, blockW, blockH
end

local function ForEachRaidHeader(fn)
    if type(fn) ~= "function" then return end
    local list = GF.raidGroupHeaders
    if list then
        for i = 1, #list do
            local header = list[i]
            if header then fn(header, i) end
        end
    end
    local single = GF.headers and GF.headers.raid
    if single and not single._msufRaidGroupIndex then
        fn(single, nil)
    end
end

local function AnyRaidHeader()
    if GF.headers and GF.headers.raid then return true end
    local list = GF.raidGroupHeaders
    if list then
        for i = 1, #list do
            if list[i] then return true end
        end
    end
    return false
end

local function HideRaidHeaders(preserveRuntime)
    local container = GF.raidGroupContainer
    if container then container:Hide() end
    ForEachRaidHeader(function(header) header:Hide() end)
    -- Preview hides the secure headers only; real visibility changes still clear child runtime.
    if not preserveRuntime and GF.DeactivateKindRuntime then
        local visual = not (InCombatLockdown and InCombatLockdown())
        GF.DeactivateKindRuntime("raid", visual)
        GF.DeactivateKindRuntime("mythicraid", visual)
    end
end
GF.HideRaidHeaders = HideRaidHeaders

local function ShowRaidHeaders(kind)
    local showKind = kind or GetLiveRaidKind()
    local conf = GF.GetConf(showKind)
    if not (conf and conf.enabled == true) then
        HideRaidHeaders()
        return
    end
    local preserve = PreserveRaidGroups(showKind, conf)
    local container = GF.raidGroupContainer
    if container then
        if preserve then container:Show() else container:Hide() end
    end
    ForEachRaidHeader(function(header)
        local groupIndex = header._msufRaidGroupIndex
        if preserve and groupIndex and RaidGroupAllowed and not RaidGroupAllowed(conf, groupIndex) then
            header:Hide()
        else
            header:Show()
        end
    end)
end
GF.ShowRaidHeaders = ShowRaidHeaders

local function RetirePreservedRaidHeaders()
    local list = GF.raidGroupHeaders
    if list then
        for i = 1, #list do
            if list[i] then RetireHeader(list[i]) end
            list[i] = nil
        end
    end
    local container = GF.raidGroupContainer
    if container then
        container:Hide()
        container:ClearAllPoints()
        container:SetSize(0.001, 0.001)
        container:SetParent(GetHiddenParent())
    end
    GF.raidGroupContainer = nil
    if GF.headers and GF.headers.raid and GF.headers.raid._msufRaidGroupIndex then
        GF.headers.raid = nil
    end
end

local function PositionPreservedRaidHeaders(kind, headerOverride)
    if InCombatLockdown() then return end
    local conf = GF.GetConf(kind)
    local totalW, totalH, _, _, spacing, growth, _, groups, _, blockW, blockH = GetPreservedRaidMetrics(kind, conf)
    local container = GF.raidGroupContainer
    if not container then return end

    local cx, cy = conf.offsetX, conf.offsetY
    if cx == nil or cy == nil then
        cx, cy = GetDefaultCenter(kind)
    end
    local anchorFrame = GF.ResolveAnchorFrame(kind)
    local pt = conf.anchorPoint or conf.point or "CENTER"
    container:ClearAllPoints()
    container:SetSize(math_max(totalW, 1), math_max(totalH, 1))
    container:SetPoint("CENTER", anchorFrame, pt, cx, cy)

    local function PositionOne(header, groupIndex)
        if not header then return end
        groupIndex = groupIndex or header._msufRaidGroupIndex or 1
        if groupIndex < 1 or groupIndex > groups then
            header:Hide()
            return
        end

        header:ClearAllPoints()
        if growth == "DOWN" then
            header:SetPoint("TOPLEFT", container, "TOPLEFT", (groupIndex - 1) * (blockW + spacing), 0)
        elseif growth == "UP" then
            header:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", (groupIndex - 1) * (blockW + spacing), 0)
        elseif growth == "RIGHT" then
            header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(groupIndex - 1) * (blockH + spacing))
        elseif growth == "LEFT" then
            header:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -(groupIndex - 1) * (blockH + spacing))
        else
            header:SetPoint("TOPLEFT", container, "TOPLEFT", (groupIndex - 1) * (blockW + spacing), 0)
        end
    end

    if headerOverride then
        PositionOne(headerOverride)
    else
        local list = GF.raidGroupHeaders
        for i = 1, groups do
            PositionOne(list and list[i], i)
        end
    end
end

local function ScanRaidHeaders(kind, force)
    local list = GF.raidGroupHeaders
    if list and #list > 0 then
        for i = 1, #list do
            local header = list[i]
            if header then
                ScanHeaderChildren(header, kind, force)
            end
        end
        return
    end
    local header = GF.headers and GF.headers.raid
    if header then ScanHeaderChildren(header, kind, force) end
end

local _scheduledHeaderScans = {}
local function ScheduleHeaderChildScan(scope, delay, kind)
    scope = (scope == "party") and "party" or "raid"
    delay = delay or 0
    local key = scope .. ":" .. tostring(delay)
    if _scheduledHeaderScans[key] then return end
    _scheduledHeaderScans[key] = true

    local function run()
        _scheduledHeaderScans[key] = nil
        if InCombatLockdown() then
            MarkPostCombatHeaderRecovery()
            return
        end

        local scanKind = kind
        if scope == "raid" then
            scanKind = scanKind or GetLiveRaidKind()
            if GF.IsKindEnabled and not GF.IsKindEnabled(scanKind) then
                if GF.DeactivateKindRuntime then GF.DeactivateKindRuntime(scanKind, false) end
                return
            end
            ScanRaidHeaders(scanKind, true)
            return
        else
            scanKind = "party"
        end
        if GF.IsKindEnabled and not GF.IsKindEnabled(scanKind) then
            if GF.DeactivateKindRuntime then GF.DeactivateKindRuntime(scanKind, false) end
            return
        end
        local header = GF.headers and GF.headers[scope]
        if not header then return end
        ScanHeaderChildren(header, scanKind, true)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(delay, run)
    else
        run()
    end
end

function GF.UpdateAnyEnabledFlag()
    local partyConf = GF.GetConf("party")
    local raidConf = GF.GetConf(GetLiveRaidKind())
    GF._anyEnabled = ((partyConf and partyConf.enabled == true) or (raidConf and raidConf.enabled == true)) and true or false
    return GF._anyEnabled
end

local function ClearKindFrameRuntime(f, visual)
    if not f then return end
    if GF.UnregisterUnitEvents then GF.UnregisterUnitEvents(f) end
    if GF._RetireFromDirty then GF._RetireFromDirty(f) end
    f._msufGFFullPending = nil
    f._msufGFRegUnit = nil
    f._msufGFRegBits = nil
    f._msufGFRosterGUID = nil
    f._msufGFRosterUnit = nil
    f._msufGFRosterRole = nil
    f._msufGFRosterLeaderState = nil
    f._msufGFIsTarget = nil
    f._msufGFIsFocus = nil

    if visual then
        if GF.HideFrameAuras then GF.HideFrameAuras(f) end
        if GF.HideSpellIndicators then GF.HideSpellIndicators(f) end
        if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
        local hideHB = _G.MSUF_GF_HB_HideFrame
        if type(hideHB) == "function" then hideHB(f) end
        local gn = f._msufGroupNumberFS or f.groupNumberText
        if gn then gn:SetText(""); gn:Hide() end
        if f.statusIndicatorText then f.statusIndicatorText:SetText(""); f.statusIndicatorText:Hide() end
        if f.roleIcon then f.roleIcon:Hide() end
        if f.raidIcon then f.raidIcon:Hide() end
        if f.leaderIcon then f.leaderIcon:Hide() end
        if f.assistIcon then f.assistIcon:Hide() end
        if f.readyCheckIcon then f.readyCheckIcon:Hide() end
        if f.summonIcon then f.summonIcon:Hide() end
        if f.resurrectIcon then f.resurrectIcon:Hide() end
        if f.phaseIcon then f.phaseIcon:Hide() end
        if f._msufGFHighlightBorders then
            for _, border in pairs(f._msufGFHighlightBorders) do
                if border then border:Hide() end
            end
        elseif f._msufGFHighlightBorder then f._msufGFHighlightBorder:Hide() end
        if f._msufGFTargetBorder then f._msufGFTargetBorder:Hide() end
        if f._msufGFDebuffStripe then f._msufGFDebuffStripe:Hide() end
        if f.barGroup then f.barGroup:Hide() end
        if f.Hide then f:Hide() end
    end
end

function GF.DeactivateKindRuntime(kind, visual)
    if not kind then return end
    GF._disabledRuntimeCleanSig = nil
    GF.ForEachFrame(function(f, frameKind)
        if frameKind == kind then
            ClearKindFrameRuntime(f, visual ~= false)
        end
    end, true)
end

function GF.DeactivateDisabledKinds(visual)
    local visualOn = visual ~= false
    local listCount = GF.frameList and #GF.frameList or 0
    local sig = tostring(GF.IsKindEnabled("party")) .. "|"
        .. tostring(GF.IsKindEnabled("raid")) .. "|"
        .. tostring(GF.IsKindEnabled("mythicraid")) .. "|"
        .. tostring(visualOn) .. "|"
        .. tostring(listCount)
    if GF._disabledRuntimeCleanSig == sig then return end

    local seen = {}
    GF.ForEachFrame(function(_, frameKind)
        if frameKind and not seen[frameKind] and not GF.IsKindEnabled(frameKind) then
            seen[frameKind] = true
            GF.DeactivateKindRuntime(frameKind, visualOn)
        end
    end, true)
    GF._disabledRuntimeCleanSig = sig
end

GetDefaultCenter = function(kind)
    return IsRaidLikeKind(kind) and -500 or -400, 0
end

local function GetDefaultPreviewCount(kind)
    if kind == "mythicraid" then return 20 end
    if kind == "raid" then return 30 end
    return 5
end

local function GetLiveCount(kind)
    local conf = GF.GetConf(kind)
    if IsRaidLikeKind(kind) then
        local n = (type(GetNumGroupMembers) == "function") and (GetNumGroupMembers() or 0) or 0
        if (type(IsInRaid) == "function" and IsInRaid()) and n > 0 then
            return n
        end
        return 10
    end

    local n = (type(GetNumSubgroupMembers) == "function") and (GetNumSubgroupMembers() or 0) or 0
    if n > 0 then
        if conf.showPlayer ~= false then n = n + 1 end
        return n
    end
    if conf.showSolo and conf.showPlayer ~= false then
        return 1
    end
    return 5
end

local function GetPreviewShownCount(kind)
    local frames = GF._previewFrames and GF._previewFrames[kind]
    if not frames then return 0 end
    local n = 0
    for i = 1, #frames do
        local f = frames[i]
        if f and f:IsShown() then n = n + 1 end
    end
    return n
end

function GF.GetPreviewAuraCount(kind)
    local n = GF._previewShownCounts and GF._previewShownCounts[kind]
    if n and n > 0 then return n end
    return GetPreviewShownCount(kind)
end

--- Fixed reference count for positioning: deterministic regardless of live party size.
function GF.GetPositionCount(kind)
    local conf = GF.GetConf(kind)
    local upc = conf.unitsPerColumn or 5
    if IsRaidLikeKind(kind) then
        if conf.preserveRaidGroups == true then
            return 5 * (conf.maxColumns or 8)
        end
        return upc * (conf.maxColumns or 8)
    end
    return upc
end

------------------------------------------------------------------------
-- Anchor frame resolution (same pattern as UF MSUF_ResolveConfiguredAnchorFrame)
------------------------------------------------------------------------
function GF.ResolveAnchorFrame(kind)
    local conf = GF.GetConf(kind)
    local atv = conf.anchorToFrame
    if type(atv) == "string" and atv ~= "" and atv ~= "FREE" then
        -- Unit frame anchoring
        local uf = _G.MSUF_UnitFrames or _G.UnitFrames
        local rel = uf and uf[atv]
        if not rel then rel = _G["MSUF_" .. atv] end
        if rel and rel ~= UIParent and rel ~= WorldFrame and (not rel.IsForbidden or not rel:IsForbidden()) then
            return rel
        end
        -- Custom frame name
        local custom = _G[atv]
        if custom and custom ~= UIParent and custom ~= WorldFrame and (not custom.IsForbidden or not custom:IsForbidden()) then
            return custom
        end
    end
    return UIParent
end

local function PositionHeaderFromGridCenter(kind, header, countOverride)
    if not header then return end
    local conf = GF.GetConf(kind)
    local count = countOverride or GF.GetPositionCount(kind)
    local dx, dy = GF.GetGridMetrics(kind, count)
    local cx, cy = conf.offsetX, conf.offsetY
    if cx == nil or cy == nil then
        cx, cy = GetDefaultCenter(kind)
    end
    local anchorFrame = GF.ResolveAnchorFrame(kind)
    local pt = conf.anchorPoint or conf.point or "CENTER"
    header:ClearAllPoints()
    header:SetPoint(pt, anchorFrame, pt, cx - dx, cy - dy)
end

function GF.SyncHeaderPosition(kind, countOverride, headerOverride)
    if InCombatLockdown() then return end
    if PreserveRaidGroups(kind) then
        PositionPreservedRaidHeaders(kind, headerOverride)
        if GF.QueueGroupBorderRefresh then GF.QueueGroupBorderRefresh(kind) end
        return
    end
    local header = headerOverride or (GF.headers and GF.headers[kind])
    if not header then return end
    PositionHeaderFromGridCenter(kind, header, countOverride)
    if GF.QueueGroupBorderRefresh then GF.QueueGroupBorderRefresh(kind) end
end

------------------------------------------------------------------------
-- SetAttribute diff-cache: skip SetAttribute when value unchanged.
-- SecureGroupHeader re-creates internal child layout on SetAttribute;
-- skipping identical values avoids expensive reflows.
------------------------------------------------------------------------
local _NIL_TOKEN = {} -- sentinel for nil values in cache
local function _GF_SetAttrIfChanged(header, key, value)
    local cache = header._msufAttrCache
    if not cache then cache = {}; header._msufAttrCache = cache end
    local norm = (value == nil) and _NIL_TOKEN or value
    if cache[key] == norm then return false end
    header:SetAttribute(key, value)
    cache[key] = norm
    return true
end

-- Invalidate cache: forces ALL attributes to be re-applied on next setup.
-- Called after zone change when SecureGroupHeader may have lost internal state.
local function _GF_InvalidateAttrCache(header)
    if header then header._msufAttrCache = nil end
end

local _nativeRoleOrderParts = {}
local _nativeRoleOrderSeen = {}

local function AppendNativeRole(tok)
    if tok == "MELEE" or tok == "RANGED" then tok = "DAMAGER" end
    if tok ~= "TANK" and tok ~= "HEALER" and tok ~= "DAMAGER" then return end
    if _nativeRoleOrderSeen[tok] then return end
    _nativeRoleOrderSeen[tok] = true
    _nativeRoleOrderParts[#_nativeRoleOrderParts + 1] = tok
end

local function BuildNativeRoleOrder(conf)
    for i = #_nativeRoleOrderParts, 1, -1 do _nativeRoleOrderParts[i] = nil end
    for k in pairs(_nativeRoleOrderSeen) do _nativeRoleOrderSeen[k] = nil end

    local roleStr = conf.roleOrder or "TANK,HEALER,DAMAGER"
    for tok in roleStr:gmatch("[^,]+") do
        AppendNativeRole(tok)
    end
    AppendNativeRole("TANK")
    AppendNativeRole("HEALER")
    AppendNativeRole("DAMAGER")

    return table.concat(_nativeRoleOrderParts, ",")
end

local function ApplyNativeRoleSort(header, conf)
    _GF_SetAttrIfChanged(header, "sortMethod", "INDEX")
    _GF_SetAttrIfChanged(header, "groupBy", "ASSIGNEDROLE")
    _GF_SetAttrIfChanged(header, "groupingOrder", BuildNativeRoleOrder(conf))
end

local function ApplyIndexSort(header)
    _GF_SetAttrIfChanged(header, "sortMethod", "INDEX")
    _GF_SetAttrIfChanged(header, "groupBy", nil)
    _GF_SetAttrIfChanged(header, "groupingOrder", nil)
end

------------------------------------------------------------------------
-- Party header setup
------------------------------------------------------------------------
local _initCfgNonce = 0
local function SetupPartyHeader()
    if InCombatLockdown() then
        GF._pendingPartyRefresh = true
        return
    end
    if not _rebuildAllActive then MarkHeaderScanInputsChanged() end

    local conf = GF.GetConf("party")
    if not conf.enabled then return end

    local parent = _G.PetBattleFrameHider or UIParent
    local header = GF.headers.party

    -- Fresh header on zone-change (fixes C-side layout bug).
    -- Normal rebuilds (settings, roster, /reload) reuse existing header.
    if header and GF._forceRecreateHeaders then
        RetireHeader(header)
        header = nil
        GF.headers.party = nil
    end

    if not header then
        GF._partyHeaderSerial = (GF._partyHeaderSerial or 0) + 1
        local headerName = "MSUF_GFPartyHeader" .. GF._partyHeaderSerial
        header = CreateFrame("Frame", headerName, parent, "SecureGroupHeaderTemplate")
        header._msufGFKind = "party"
        header:SetClampedToScreen(true)
        if header.SetClipsChildren then header:SetClipsChildren(false) end
        header:Hide()
        header:HookScript("OnShow", function(self)
            if not InCombatLockdown() then
                local n = (self:GetAttribute("_msufLayoutNonce") or 0) + 1
                self:SetAttribute("_msufLayoutNonce", n)
            end
        end)
        GF.headers.party = header
    end

    -- CRITICAL: Hide header BEFORE setting attributes.
    -- Each SetAttribute triggers SecureGroupHeader's internal re-layout.
    -- If the header is visible, intermediate layouts render with wrong
    -- child sizes/positions that can persist visually (zone-change bug).
    -- Setting all attributes while hidden ensures ONE clean layout on Show().
    header:Hide()

    -- Attributes (combat-lockdown safe: we checked above)
    local w, h, spacing = conf.width or 120, conf.height or 40, conf.spacing or 1
    local growth = conf.growth or "DOWN"

    -- Frame scaling (geometry first; fonts/icons use the cached scale in render)
    if GF.GetScaledFrameMetrics then
        w, h, spacing = GF.GetScaledFrameMetrics("party")
    elseif GF.ApplyFrameScale then
        GF.ApplyFrameScale("party")
    end

    _GF_SetAttrIfChanged(header, "showParty", true)
    _GF_SetAttrIfChanged(header, "showRaid", false)
    _GF_SetAttrIfChanged(header, "showPlayer", conf.showPlayer and true or false)
    _GF_SetAttrIfChanged(header, "showSolo", conf.showSolo and true or false)
    _GF_SetAttrIfChanged(header, "maxColumns", conf.maxColumns or 1)
    _GF_SetAttrIfChanged(header, "unitsPerColumn", conf.unitsPerColumn or 5)
    _GF_SetAttrIfChanged(header, "template", GF_UNIT_BUTTON_TEMPLATE)
    _GF_SetAttrIfChanged(header, "initial-width", w)
    _GF_SetAttrIfChanged(header, "initial-height", h)
    _GF_SetAttrIfChanged(header, "sortDir", "ASC")

    -- Role sort
    if conf.sortByRole then
        ApplyNativeRoleSort(header, conf)
    else
        ApplyIndexSort(header)
    end

    -- Growth direction → point/xOffset/yOffset
    -- SecureGroupHeader already accounts for child width/height; offsets are spacing only.
    if growth == "DOWN" then
        _GF_SetAttrIfChanged(header, "point", "TOP")
        _GF_SetAttrIfChanged(header, "xOffset", 0)
        _GF_SetAttrIfChanged(header, "yOffset", -spacing)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "LEFT")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "UP" then
        _GF_SetAttrIfChanged(header, "point", "BOTTOM")
        _GF_SetAttrIfChanged(header, "xOffset", 0)
        _GF_SetAttrIfChanged(header, "yOffset", spacing)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "LEFT")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "RIGHT" then
        _GF_SetAttrIfChanged(header, "point", "LEFT")
        _GF_SetAttrIfChanged(header, "xOffset", spacing)
        _GF_SetAttrIfChanged(header, "yOffset", 0)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "TOP")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "LEFT" then
        _GF_SetAttrIfChanged(header, "point", "RIGHT")
        _GF_SetAttrIfChanged(header, "xOffset", -spacing)
        _GF_SetAttrIfChanged(header, "yOffset", 0)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "TOP")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    end

    -- initialConfigFunction: bake size VALUES into string (EQoL pattern).
    -- When size changes, the string changes → SecureGroupHeader re-runs on all children.
    -- Nonce forces SecureGroupHeader to re-run initialConfigFunction on ALL
    -- existing children (not just new ones). Fixes zone-change size bug.
    _initCfgNonce = _initCfgNonce + 1
    local initCfg = string.format([[
        self:ClearAllPoints()
        self:SetWidth(%.3f)
        self:SetHeight(%.3f)
        self:SetAttribute('*type1', 'target')
        self:SetAttribute('*type2', 'togglemenu')
        RegisterUnitWatch(self)
        -- nonce %d
    ]], w, h, _initCfgNonce)
    header:SetAttribute("initialConfigFunction", initCfg)

    -- Position (stored offset = grid center)
    PositionHeaderFromGridCenter("party", header)

    header:Show()

    -- EQoL pattern: nudge SecureGroupHeader's internal layout engine
    -- by setting a dummy attribute. Forces complete child re-positioning
    -- even when real attributes haven't changed (zone-change fix).
    local nonce = (header:GetAttribute("_msufLayoutNonce") or 0) + 1
    header:SetAttribute("_msufLayoutNonce", nonce)

    -- Try the first build immediately; delayed scans still catch secure
    -- children whose unit token is assigned on the next tick.
    ScanHeaderChildren(header, "party", true)

    -- Deferred child scan (children created async after Show)
    ScheduleHeaderChildScan("party", 0, "party")
    ScheduleHeaderChildScan("party", 0.05, "party")
end

------------------------------------------------------------------------
-- Raid header setup
------------------------------------------------------------------------
RaidGroupAllowed = function(conf, groupIndex)
    local gf = conf and conf.groupFilter
    if type(gf) == "table" then
        return gf[groupIndex] ~= false
    end
    if type(gf) == "string" and gf ~= "" then
        local needle = tostring(groupIndex)
        for token in gf:gmatch("[^,]+") do
            token = token:match("^%s*(.-)%s*$")
            if token == needle then return true end
        end
        return false
    end
    return true
end

local function ApplyPreservedRaidSort(header, conf)
    local sortMode = conf.sortMode
    if not sortMode then
        sortMode = conf.sortByRole and "ROLE" or "INDEX"
    end

    if sortMode == "ROLE" or sortMode == "GROUP_ROLE" then
        ApplyNativeRoleSort(header, conf)
    elseif sortMode == "NAME" then
        _GF_SetAttrIfChanged(header, "sortMethod", "NAME")
        _GF_SetAttrIfChanged(header, "groupBy", nil)
        _GF_SetAttrIfChanged(header, "groupingOrder", nil)
    else
        ApplyIndexSort(header)
    end
end

local function ApplyRaidGrowthAttributes(header, growth, spacing)
    if growth == "DOWN" then
        _GF_SetAttrIfChanged(header, "point", "TOP")
        _GF_SetAttrIfChanged(header, "xOffset", 0)
        _GF_SetAttrIfChanged(header, "yOffset", -spacing)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "LEFT")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "UP" then
        _GF_SetAttrIfChanged(header, "point", "BOTTOM")
        _GF_SetAttrIfChanged(header, "xOffset", 0)
        _GF_SetAttrIfChanged(header, "yOffset", spacing)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "LEFT")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "RIGHT" then
        _GF_SetAttrIfChanged(header, "point", "LEFT")
        _GF_SetAttrIfChanged(header, "xOffset", spacing)
        _GF_SetAttrIfChanged(header, "yOffset", 0)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "TOP")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "LEFT" then
        _GF_SetAttrIfChanged(header, "point", "RIGHT")
        _GF_SetAttrIfChanged(header, "xOffset", -spacing)
        _GF_SetAttrIfChanged(header, "yOffset", 0)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "TOP")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    end
end

local function SetupPreservedRaidHeaders(kind, conf)
    if InCombatLockdown() then
        GF._pendingRaidRefresh = true
        return
    end

    local parent = _G.PetBattleFrameHider or UIParent
    if GF.headers.raid and not GF.headers.raid._msufRaidGroupIndex then
        RetireHeader(GF.headers.raid)
        GF.headers.raid = nil
    end

    local container = GF.raidGroupContainer
    if not container then
        container = CreateFrame("Frame", "MSUF_GFRaidGroupContainer", parent)
        container._msufGFKind = kind
        container:SetClampedToScreen(true)
        GF.raidGroupContainer = container
    end
    if container:GetParent() ~= parent then container:SetParent(parent) end
    container._msufGFKind = kind
    container:Hide()

    local w, h, spacing = conf.width or 80, conf.height or 32, conf.spacing or 1
    local growth = conf.growth or "DOWN"
    if GF.GetScaledFrameMetrics then
        w, h, spacing = GF.GetScaledFrameMetrics(kind)
    elseif GF.ApplyFrameScale then
        GF.ApplyFrameScale(kind)
    end

    local _, primary, blockColumns = GetPreservedRaidPrimary(conf)
    local groupCount = GetPreservedRaidGroupCount(conf)
    local headers = GF.raidGroupHeaders
    for groupIndex = 1, groupCount do
        local header = headers[groupIndex]
        if header and GF._forceRecreateHeaders then
            RetireHeader(header)
            header = nil
            headers[groupIndex] = nil
        end
        if not header then
            GF._raidHeaderSerial = (GF._raidHeaderSerial or 0) + 1
            local headerName = "MSUF_GFRaidHeader" .. GF._raidHeaderSerial .. "Group" .. groupIndex
            header = CreateFrame("Frame", headerName, container, "SecureGroupHeaderTemplate")
            header._msufRaidGroupIndex = groupIndex
            header:SetClampedToScreen(true)
            if header.SetClipsChildren then header:SetClipsChildren(false) end
            header:Hide()
            header:HookScript("OnShow", function(self)
                if not InCombatLockdown() then
                    local n = (self:GetAttribute("_msufLayoutNonce") or 0) + 1
                    self:SetAttribute("_msufLayoutNonce", n)
                end
            end)
            headers[groupIndex] = header
        end

        header._msufGFKind = kind
        header._msufRaidGroupIndex = groupIndex
        if header:GetParent() ~= container then header:SetParent(container) end
        header:Hide()

        _GF_SetAttrIfChanged(header, "showParty", false)
        _GF_SetAttrIfChanged(header, "showRaid", true)
        _GF_SetAttrIfChanged(header, "showPlayer", true)
        _GF_SetAttrIfChanged(header, "showSolo", false)
        _GF_SetAttrIfChanged(header, "maxColumns", blockColumns)
        _GF_SetAttrIfChanged(header, "unitsPerColumn", primary)
        _GF_SetAttrIfChanged(header, "template", GF_UNIT_BUTTON_TEMPLATE)
        _GF_SetAttrIfChanged(header, "initial-width", w)
        _GF_SetAttrIfChanged(header, "initial-height", h)
        _GF_SetAttrIfChanged(header, "sortDir", "ASC")
        _GF_SetAttrIfChanged(header, "groupFilter", tostring(groupIndex))
        ApplyPreservedRaidSort(header, conf)
        ApplyRaidGrowthAttributes(header, growth, spacing)

        _initCfgNonce = _initCfgNonce + 1
        local initCfg = string.format([[
        self:ClearAllPoints()
        self:SetWidth(%.3f)
        self:SetHeight(%.3f)
        self:SetAttribute('*type1', 'target')
        self:SetAttribute('*type2', 'togglemenu')
        RegisterUnitWatch(self)
        -- nonce %d
    ]], w, h, _initCfgNonce)
        header:SetAttribute("initialConfigFunction", initCfg)
    end

    for groupIndex = groupCount + 1, #headers do
        if headers[groupIndex] then
            RetireHeader(headers[groupIndex])
            headers[groupIndex] = nil
        end
    end

    GF.headers.raid = headers[1]
    PositionPreservedRaidHeaders(kind)
    container:Show()
    for groupIndex = 1, groupCount do
        local header = headers[groupIndex]
        if header then
            if RaidGroupAllowed(conf, groupIndex) then
                header:Show()
                local nonce = (header:GetAttribute("_msufLayoutNonce") or 0) + 1
                header:SetAttribute("_msufLayoutNonce", nonce)
            else
                header:Hide()
            end
        end
    end

    ScanRaidHeaders(kind, true)

    ScheduleHeaderChildScan("raid", 0, kind)
    ScheduleHeaderChildScan("raid", 0.05, kind)
end

local function SetupRaidHeader()
    if InCombatLockdown() then
        GF._pendingRaidRefresh = true
        return
    end
    if not _rebuildAllActive then MarkHeaderScanInputsChanged() end

    local kind = GetLiveRaidKind()
    local conf = GF.GetConf(kind)
    if not conf.enabled then return end

    if PreserveRaidGroups(kind, conf) then
        SetupPreservedRaidHeaders(kind, conf)
        return
    end
    RetirePreservedRaidHeaders()

    local parent = _G.PetBattleFrameHider or UIParent
    local header = GF.headers.raid

    if header and GF._forceRecreateHeaders then
        RetireHeader(header)
        header = nil
        GF.headers.raid = nil
    end

    if not header then
        GF._raidHeaderSerial = (GF._raidHeaderSerial or 0) + 1
        local headerName = "MSUF_GFRaidHeader" .. GF._raidHeaderSerial
        header = CreateFrame("Frame", headerName, parent, "SecureGroupHeaderTemplate")
        header._msufGFKind = kind
        header:SetClampedToScreen(true)
        if header.SetClipsChildren then header:SetClipsChildren(false) end
        header:Hide()
        header:HookScript("OnShow", function(self)
            if not InCombatLockdown() then
                local n = (self:GetAttribute("_msufLayoutNonce") or 0) + 1
                self:SetAttribute("_msufLayoutNonce", n)
            end
        end)
        GF.headers.raid = header
    end
    header._msufGFKind = kind

    local w, h, spacing = conf.width or 80, conf.height or 32, conf.spacing or 1
    local growth = conf.growth or "DOWN"
    local unitsPerColumn = conf.unitsPerColumn or 5
    local maxColumns = conf.maxColumns or 8

    -- Frame scaling (geometry first; fonts/icons use the cached scale in render)
    if GF.GetScaledFrameMetrics then
        w, h, spacing = GF.GetScaledFrameMetrics(kind)
    elseif GF.ApplyFrameScale then
        GF.ApplyFrameScale(kind)
    end

    -- CRITICAL: Hide before attributes (see SetupPartyHeader comment)
    header:Hide()

    _GF_SetAttrIfChanged(header, "showParty", false)
    _GF_SetAttrIfChanged(header, "showRaid", true)
    _GF_SetAttrIfChanged(header, "showPlayer", true)
    _GF_SetAttrIfChanged(header, "showSolo", false)
    _GF_SetAttrIfChanged(header, "maxColumns", maxColumns)
    _GF_SetAttrIfChanged(header, "unitsPerColumn", unitsPerColumn)
    _GF_SetAttrIfChanged(header, "template", GF_UNIT_BUTTON_TEMPLATE)
    _GF_SetAttrIfChanged(header, "initial-width", w)
    _GF_SetAttrIfChanged(header, "initial-height", h)
    _GF_SetAttrIfChanged(header, "sortDir", "ASC")
    -- Group filter: which raid groups to display (1-8)
    local gf = conf.groupFilter
    if type(gf) == "string" and gf ~= "" then
        _GF_SetAttrIfChanged(header, "groupFilter", gf)
    elseif type(gf) == "table" then
        local parts = {}
        for i = 1, 8 do
            if gf[i] ~= false then parts[#parts + 1] = tostring(i) end
        end
        if #parts > 0 and #parts < 8 then
            _GF_SetAttrIfChanged(header, "groupFilter", table.concat(parts, ","))
        else
            _GF_SetAttrIfChanged(header, "groupFilter", nil)
        end
    else
        _GF_SetAttrIfChanged(header, "groupFilter", nil)
    end
    -- Sort mode: INDEX / ROLE / GROUP / GROUP_ROLE / NAME
    -- Migration: sortByRole boolean → sortMode string
    local sortMode = conf.sortMode
    if not sortMode then
        sortMode = conf.sortByRole and "ROLE" or "INDEX"
    end

    if sortMode == "ROLE" then
        ApplyNativeRoleSort(header, conf)
    elseif sortMode == "GROUP" then
        -- Group by raid group number (1-8), index within each
        _GF_SetAttrIfChanged(header, "sortMethod", "INDEX")
        _GF_SetAttrIfChanged(header, "groupBy", "GROUP")
        _GF_SetAttrIfChanged(header, "groupingOrder", "1,2,3,4,5,6,7,8")
    elseif sortMode == "GROUP_ROLE" then
        -- Group by raid group, then by role within each group
        _GF_SetAttrIfChanged(header, "sortMethod", "INDEX")
        _GF_SetAttrIfChanged(header, "groupBy", "GROUP")
        _GF_SetAttrIfChanged(header, "groupingOrder", "1,2,3,4,5,6,7,8")
        -- Note: within-group role sorting requires Blizzard's native prioritization
        -- which sorts TANK > HEALER > DAMAGER within each group automatically
    elseif sortMode == "NAME" then
        _GF_SetAttrIfChanged(header, "sortMethod", "NAME")
        _GF_SetAttrIfChanged(header, "groupBy", nil)
        _GF_SetAttrIfChanged(header, "groupingOrder", nil)
    else
        -- INDEX (default): flat, no grouping
        _GF_SetAttrIfChanged(header, "sortMethod", "INDEX")
        _GF_SetAttrIfChanged(header, "groupBy", nil)
        _GF_SetAttrIfChanged(header, "groupingOrder", nil)
    end

    -- Growth
    local colGrowth = "DOWN"
    if growth == "DOWN" then
        _GF_SetAttrIfChanged(header, "point", "TOP")
        _GF_SetAttrIfChanged(header, "xOffset", 0)
        _GF_SetAttrIfChanged(header, "yOffset", -spacing)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "LEFT")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "UP" then
        _GF_SetAttrIfChanged(header, "point", "BOTTOM")
        _GF_SetAttrIfChanged(header, "xOffset", 0)
        _GF_SetAttrIfChanged(header, "yOffset", spacing)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "LEFT")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "RIGHT" then
        _GF_SetAttrIfChanged(header, "point", "LEFT")
        _GF_SetAttrIfChanged(header, "xOffset", spacing)
        _GF_SetAttrIfChanged(header, "yOffset", 0)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "TOP")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    elseif growth == "LEFT" then
        _GF_SetAttrIfChanged(header, "point", "RIGHT")
        _GF_SetAttrIfChanged(header, "xOffset", -spacing)
        _GF_SetAttrIfChanged(header, "yOffset", 0)
        _GF_SetAttrIfChanged(header, "columnAnchorPoint", "TOP")
        _GF_SetAttrIfChanged(header, "columnSpacing", spacing)
    end

    -- Nonce forces SecureGroupHeader to re-run initialConfigFunction on ALL
    -- existing children (not just new ones). Fixes zone-change size bug.
    _initCfgNonce = _initCfgNonce + 1
    local initCfg = string.format([[
        self:ClearAllPoints()
        self:SetWidth(%.3f)
        self:SetHeight(%.3f)
        self:SetAttribute('*type1', 'target')
        self:SetAttribute('*type2', 'togglemenu')
        RegisterUnitWatch(self)
        -- nonce %d
    ]], w, h, _initCfgNonce)
    header:SetAttribute("initialConfigFunction", initCfg)

    PositionHeaderFromGridCenter(kind, header)

    header:Show()

    -- EQoL pattern: nudge layout (see SetupPartyHeader comment)
    local nonce = (header:GetAttribute("_msufLayoutNonce") or 0) + 1
    header:SetAttribute("_msufLayoutNonce", nonce)

    -- Try the first build immediately; delayed scans still catch secure
    -- children whose unit token is assigned on the next tick.
    ScanHeaderChildren(header, kind, true)

    ScheduleHeaderChildScan("raid", 0, kind)
    ScheduleHeaderChildScan("raid", 0.05, kind)
end

------------------------------------------------------------------------
-- Blizzard frame hiding
------------------------------------------------------------------------
local function HideFrameLocked(frame)
    if not frame then return end
    if frame._msufGFHidden then return end
    frame._msufGFHidden = true
    if frame.GetParent and not frame._msufGFOriginalParent then
        frame._msufGFOriginalParent = frame:GetParent()
    end
    local hp = GetHiddenParent()
    if frame.SetParent then frame:SetParent(hp) end
    if not frame._msufGFHideHooked then
        frame._msufGFHideHooked = true
        if frame.Show then
            hooksecurefunc(frame, "Show", function(f)
                if f._msufGFHidden then
                    if InCombatLockdown() then
                        GF._pendingBlizzardDisable = true
                        return
                    end
                    if f.SetParent then f:SetParent(hp) end
                end
            end)
        end
    end
end

local function RestoreFrameLocked(frame, showAfter)
    if not frame then return end
    local wasHidden = frame._msufGFHidden == true
    if not wasHidden and not showAfter then return end
    frame._msufGFHidden = nil
    local parent = frame._msufGFOriginalParent or UIParent
    if not InCombatLockdown() then
        if wasHidden and frame.SetParent then frame:SetParent(parent) end
        if showAfter and frame.Show then frame:Show() end
    end
end

local function NormalizeBlizzardFallbackMode(mode)
    if type(mode) == "string" then mode = mode:upper() end
    if mode == "SHOW" or mode == "BLIZZARD" or mode == true then return "SHOW" end
    if mode == "NONE" or mode == "HIDE" or mode == false then return "NONE" end
    return "AUTO"
end

local function BlizzardRaidManagerWantsShown()
    local getSetting = _G.CompactRaidFrameManager_GetSetting
    if type(getSetting) ~= "function" then return nil end
    local value = getSetting("IsShown")
    if value == nil then return nil end
    if value == "0" or value == 0 or value == false then return false end
    return value == "1" or value == 1 or value == true
end

local function ApplyDisabledPartyFallback(mode)
    mode = NormalizeBlizzardFallbackMode(mode)
    if mode == "NONE" then
        HideFrameLocked(_G.PartyFrame)
        HideFrameLocked(_G.CompactPartyFrame)
        HideFrameLocked(_G.CompactPartyFrameTitle)
        return
    end
    RestoreFrameLocked(_G.PartyFrame, true)
    RestoreFrameLocked(_G.CompactPartyFrame, true)
    RestoreFrameLocked(_G.CompactPartyFrameTitle, true)
end

local function ApplyDisabledRaidFallback(mode)
    mode = NormalizeBlizzardFallbackMode(mode)
    if mode == "NONE" then
        HideFrameLocked(_G.CompactRaidFrameContainer)
        if _G.CompactRaidFrameManager_SetSetting then
            _G.CompactRaidFrameManager_SetSetting("IsShown", "0")
        end
        return
    end
    if mode == "SHOW" then
        if _G.CompactRaidFrameManager_SetSetting then
            _G.CompactRaidFrameManager_SetSetting("IsShown", "1")
        end
        RestoreFrameLocked(_G.CompactRaidFrameContainer, true)
        return
    end
    local wantsShown = BlizzardRaidManagerWantsShown()
    RestoreFrameLocked(_G.CompactRaidFrameContainer, wantsShown == true)
    if wantsShown == false and _G.CompactRaidFrameContainer and _G.CompactRaidFrameContainer.Hide then
        _G.CompactRaidFrameContainer:Hide()
    end
end

function GF.DisableBlizzardFrames()
    if InCombatLockdown() then
        GF._pendingBlizzardDisable = true
        return
    end
    local partyConf = GF.GetConf("party")
    local raidConf  = GF.GetConf(GetLiveRaidKind())
    if partyConf.enabled == true then
        HideFrameLocked(_G.PartyFrame)
        HideFrameLocked(_G.CompactPartyFrame)
        HideFrameLocked(_G.CompactPartyFrameTitle)
    else
        ApplyDisabledPartyFallback(partyConf.blizzardFallbackMode)
    end
    if raidConf.enabled == true then
        HideFrameLocked(_G.CompactRaidFrameContainer)
    else
        ApplyDisabledRaidFallback(raidConf.blizzardFallbackMode)
    end
end

function GF.RestoreBlizzardFrames()
    -- Undo reparenting
    for _, name in pairs({ "PartyFrame", "CompactPartyFrame", "CompactPartyFrameTitle", "CompactRaidFrameContainer" }) do
        RestoreFrameLocked(_G[name])
    end
end

------------------------------------------------------------------------
-- Preview system (fake data for Edit Mode / Options)
------------------------------------------------------------------------
local PREVIEW_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER",
    "EVOKER" }
local PREVIEW_NAMES = { "Thrall", "Jaina", "Sylvanas", "Anduin", "Tyrande" }
local PREVIEW_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "HEALER" }

function GF.ApplyPreviewData(f, index, kind)
    if not f then return end
    f._msufGFPreviewActive = true
    f._msufGFPreviewIndex = index
    f._msufGFPreviewClass = PREVIEW_CLASSES[((index - 1) % #PREVIEW_CLASSES) + 1]
    local conf = GF.GetConf(kind or "party")
    local cls = f._msufGFPreviewClass
    local name = PREVIEW_NAMES[((index - 1) % #PREVIEW_NAMES) + 1]
    local role = PREVIEW_ROLES[((index - 1) % #PREVIEW_ROLES) + 1]
    f._msufGFPreviewRole = role
    f._msufGFNameHiddenForStatus = nil
    local hpPct = 0.3 + (index * 0.15) % 0.7

    -- Name (with color + truncation)
    if f.nameText and GF.ShouldShowNameText and GF.ShouldShowNameText(f, conf) then
        local displayName = name
        local maxC, noEllipsis, clipSide = GF.ResolveNameTruncation(kind or "party")
        if maxC > 0 then
            displayName = GF.TruncateName(displayName, maxC, noEllipsis, clipSide)
        end
        f.nameText:SetText(displayName)
        f.nameText:Show()
        local nr, ng, nb = GF.ResolveNameColor(kind or "party", cls)
        f.nameText:SetTextColor(nr, ng, nb, 1)
    end

    -- Health bar value + color (respects GF-independent barMode)
    if f.health then
        f.health:SetMinMaxValues(0, 100)
        f.health:SetValue(math_floor(hpPct * 100))
        local gfMode = conf.gfBarMode
        local mode
        if gfMode and gfMode ~= "GLOBAL" then
            mode = gfMode
        else
            local getCache = _G.MSUF_UFCore_GetSettingsCache
            local cache = type(getCache) == "function" and getCache() or nil
            local gm = cache and cache.barMode
            if gm == "dark" or gm == "unified" then mode = gm
            else mode = conf.healthColorMode or "CLASS" end
        end
        if mode == "dark" then
            local getCache = _G.MSUF_UFCore_GetSettingsCache
            local cache = type(getCache) == "function" and getCache() or nil
            f.health:SetStatusBarColor(conf.gfDarkR or (cache and cache.darkBarR) or 0, conf.gfDarkG or (cache and cache.darkBarG) or 0, conf.gfDarkB or (cache and cache.darkBarB) or 0, 1)
        elseif mode == "unified" then
            local getCache = _G.MSUF_UFCore_GetSettingsCache
            local cache = type(getCache) == "function" and getCache() or nil
            f.health:SetStatusBarColor(conf.gfUnifiedR or (cache and cache.unifiedBarR) or 0.10, conf.gfUnifiedG or (cache and cache.unifiedBarG) or 0.60, conf.gfUnifiedB or (cache and cache.unifiedBarB) or 0.90, 1)
        elseif mode == "GRADIENT" then
            local r = hpPct > 0.5 and (1 - (hpPct - 0.5) * 2) or 1
            local g = hpPct > 0.5 and 1 or (hpPct * 2)
            f.health:SetStatusBarColor(r, g, 0, 1)
        elseif mode == "CUSTOM" then
            f.health:SetStatusBarColor(conf.healthCustomR or 0.2, conf.healthCustomG or 0.8, conf.healthCustomB or 0.2, 1)
        else
            local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
            if type(fastClass) == "function" then
                local cr, cg, cb = fastClass(cls)
                if cr then f.health:SetStatusBarColor(cr, cg, cb, 1)
                else
                    local cc = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                    if cc then f.health:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
                    else f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1) end
                end
            else
                local cc = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                if cc then f.health:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
                else f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1) end
            end
        end
    end

    -- 3-slot health text (preview with fake values)
    do
        local fakeHP = math_floor(hpPct * 100)
        local fakeMax = 100
        local delim = conf.textDelimiter or " / "
        local hpTextOn = conf.showHPText ~= false
        local tl, tc, tr
        if GF.ResolveHealthTextSlots then
            tl, tc, tr = GF.ResolveHealthTextSlots(conf)
        else
            tl = hpTextOn and (conf.textLeft or "NONE") or "NONE"
            tc = hpTextOn and (conf.textCenter or "NONE") or "NONE"
            tr = hpTextOn and (conf.textRight or "NONE") or "NONE"
        end
        if f.textLeftFS then
            f.textLeftFS:SetText(GF.FormatHealthText(tl, fakeHP, fakeMax, delim, false))
            if tl ~= "NONE" then f.textLeftFS:Show() else f.textLeftFS:Hide() end
        end
        if f.textCenterFS then
            f.textCenterFS:SetText(GF.FormatHealthText(tc, fakeHP, fakeMax, delim, false))
            if tc ~= "NONE" then f.textCenterFS:Show() else f.textCenterFS:Hide() end
        end
        if f.textRightFS then
            f.textRightFS:SetText(GF.FormatHealthText(tr, fakeHP, fakeMax, delim, false))
            if tr ~= "NONE" then f.textRightFS:Show() else f.textRightFS:Hide() end
        end
    end

    -- Health prediction overlays (preview with fake values + global colors)
    local hpVal = math_floor(hpPct * 100)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    -- Per-GF absorb setting resolver (mirrors _GF_GetAbsorbSetting in Effects)
    local gfKind = f._msufGFKind or "party"
    local gfDbKey = GF.GetConfigDBKey and GF.GetConfigDBKey(gfKind) or ((gfKind == "raid") and "gf_raid" or "gf_party")
    local gfDb = _G.MSUF_DB and _G.MSUF_DB[gfDbKey]
    local gfHasOvr = gfDb and gfDb.hlOverride
    local function _pResolve(key)
        if gfHasOvr and gfDb[key] ~= nil then return gfDb[key] end
        return gen and gen[key]
    end
    local function _pSetOverlayAlpha(bar, alpha)
        if type(alpha) ~= "number" then return end
        if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
        local tex = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        if tex and tex.SetAlpha then tex:SetAlpha(alpha) end
    end
    if f.incomingHealBar then
        if GF._ApplyHealPredAnchor then GF._ApplyHealPredAnchor(f) end
        local hpEnabled = (GF.IsHealPredictionEnabled and GF.IsHealPredictionEnabled(f._msufGFKind or "party", conf)) or false
        if hpEnabled ~= false then
            f.incomingHealBar:SetMinMaxValues(0, 100)
            f.incomingHealBar:SetValue(math_min(20, math_max(0, 100 - hpVal)))
            local r, g, b = 0.0, 1.0, 0.4
            if gen then
                if type(gen.healPredColorR) == "number" then r = gen.healPredColorR end
                if type(gen.healPredColorG) == "number" then g = gen.healPredColorG end
                if type(gen.healPredColorB) == "number" then b = gen.healPredColorB end
            end
            f.incomingHealBar:SetStatusBarColor(r, g, b, 0.45)
            f.incomingHealBar:Show()
        else
            f.incomingHealBar:Hide()
        end
    end
    -- Absorb enabled: mirrors _GF_IsAbsorbEnabled — hlOverride-aware
    local absorbBarVisible
    do
        local atm = tonumber(_pResolve("absorbTextMode"))
        if atm then
            absorbBarVisible = (atm == 2 or atm == 3)
        else
            local eab = _pResolve("enableAbsorbBar")
            if eab ~= nil then absorbBarVisible = (eab ~= false) else absorbBarVisible = true end
        end
    end
    -- Absorb anchoring: SetReverseFill from absorbAnchorMode (per-GF → general)
    if GF._ApplyAbsorbAnchor then
        GF._ApplyAbsorbAnchor(f)
    elseif absorbBarVisible or (f.healAbsorbBar and conf.healAbsorbEnabled ~= false) then
        local anchorMode = tonumber(_pResolve("absorbAnchorMode")) or 2
        local absorbReverse, healReverse
        if anchorMode == 1 then
            absorbReverse = false; healReverse = true
        elseif anchorMode == 5 then
            local hpReverse = f.health and f.health.GetReverseFill and f.health:GetReverseFill()
            absorbReverse = not hpReverse; healReverse = hpReverse and true or false
        else
            absorbReverse = true; healReverse = false
        end
        if f.absorbBar and f.absorbBar.SetReverseFill then f.absorbBar:SetReverseFill(absorbReverse and true or false) end
        if f.healAbsorbBar and f.healAbsorbBar.SetReverseFill then f.healAbsorbBar:SetReverseFill(healReverse and true or false) end
    end
    if f.absorbBar and absorbBarVisible then
        f.absorbBar:SetMinMaxValues(0, 100)
        f.absorbBar:SetValue(15 + index * 5)
        local r, g, b = 0.8, 0.9, 1.0
        if gen then
            if type(gen.absorbBarColorR) == "number" then r = gen.absorbBarColorR end
            if type(gen.absorbBarColorG) == "number" then g = gen.absorbBarColorG end
            if type(gen.absorbBarColorB) == "number" then b = gen.absorbBarColorB end
        end
        local a = tonumber(_pResolve("absorbBarOpacity")) or 0.6
        f.absorbBar:SetStatusBarColor(r, g, b, 1)
        _pSetOverlayAlpha(f.absorbBar, a)
        f.absorbBar:Show()
    elseif f.absorbBar then
        f.absorbBar:Hide()
    end
    -- Heal absorb: independent enabled check (NOT gated on absorb bar)
    local healAbsorbVisible = conf.healAbsorbEnabled ~= false
    if f.healAbsorbBar and healAbsorbVisible then
        f.healAbsorbBar:SetMinMaxValues(0, 100)
        f.healAbsorbBar:SetValue(math_min(8, hpVal))
        local r, g, b = 1.0, 0.4, 0.4
        if gen then
            if type(gen.healAbsorbBarColorR) == "number" then r = gen.healAbsorbBarColorR end
            if type(gen.healAbsorbBarColorG) == "number" then g = gen.healAbsorbBarColorG end
            if type(gen.healAbsorbBarColorB) == "number" then b = gen.healAbsorbBarColorB end
        end
        local a = tonumber(_pResolve("healAbsorbBarOpacity")) or 0.7
        f.healAbsorbBar:SetStatusBarColor(r, g, b, 1)
        _pSetOverlayAlpha(f.healAbsorbBar, a)
        f.healAbsorbBar:Show()
    elseif f.healAbsorbBar then
        f.healAbsorbBar:Hide()
    end

    -- Power bar + independent power text preview
    local previewPowerH = (GF.GetEffectivePowerHeight and GF.GetEffectivePowerHeight(kind or "party", nil, role, conf))
        or (conf.powerHeight or 6)
    local powerTextOn = (GF.HasActivePowerTextSlot and GF.HasActivePowerTextSlot(kind, conf)) or false
    local fakePow = 50 + index * 10
    local fakePowMax = 100
    if f.power and previewPowerH > 0 then
        f.power:SetMinMaxValues(0, fakePowMax)
        f.power:SetValue(fakePow)
        f.power:SetStatusBarColor(0.2, 0.2, 0.8, 1)
        f.power:Show()
    elseif f.power then
        f.power:Hide()
    end
    if powerTextOn then
        local pDelim = conf.powerTextDelimiter or " / "
        local ptl = conf.powerTextLeft   or "NONE"
        local ptc = conf.powerTextCenter  or "NONE"
        local ptr = conf.powerTextRight   or "NONE"
        if f.powerTextLeftFS then
            f.powerTextLeftFS:SetText(GF.FormatPowerText(ptl, fakePow, fakePowMax, pDelim))
            if ptl ~= "NONE" then f.powerTextLeftFS:Show() else f.powerTextLeftFS:Hide() end
        end
        if f.powerTextCenterFS then
            f.powerTextCenterFS:SetText(GF.FormatPowerText(ptc, fakePow, fakePowMax, pDelim))
            if ptc ~= "NONE" then f.powerTextCenterFS:Show() else f.powerTextCenterFS:Hide() end
        end
        if f.powerTextRightFS then
            f.powerTextRightFS:SetText(GF.FormatPowerText(ptr, fakePow, fakePowMax, pDelim))
            if ptr ~= "NONE" then f.powerTextRightFS:Show() else f.powerTextRightFS:Hide() end
        end
    else
        if f.powerTextLeftFS then f.powerTextLeftFS:SetText(""); f.powerTextLeftFS:Hide() end
        if f.powerTextCenterFS then f.powerTextCenterFS:SetText(""); f.powerTextCenterFS:Hide() end
        if f.powerTextRightFS then f.powerTextRightFS:SetText(""); f.powerTextRightFS:Hide() end
    end

    -- Role icon
    if f.roleIcon then
        if conf.roleIcon ~= false then
            local tex, l, r, t, b = GF.GetRoleTexture(kind, role)
            if tex then
                f.roleIcon:SetTexture(tex)
                f.roleIcon:SetTexCoord(l, r, t, b)
                f.roleIcon:Show()
            else
                f.roleIcon:Hide()
            end
        else
            f.roleIcon:Hide()
        end
    end

    -- Leader icon (preview: show for index 1)
    if f.leaderIcon and conf.leaderIcon ~= false and index == 1 then
        local tex, l, r, t, b = GF.GetLeaderTexture(kind)
        f.leaderIcon:SetTexture(tex)
        f.leaderIcon:SetTexCoord(l, r, t, b)
        f.leaderIcon:Show()
    elseif f.leaderIcon then
        f.leaderIcon:Hide()
    end

    -- Assist icon (preview: show for index 2)
    if f.assistIcon and conf.assistIcon ~= false and index == 2 then
        local tex, l, r, t, b = GF.GetAssistTexture(kind)
        f.assistIcon:SetTexture(tex)
        f.assistIcon:SetTexCoord(l, r, t, b)
        f.assistIcon:Show()
    elseif f.assistIcon then
        f.assistIcon:Hide()
    end

    -- Raid marker (preview: show for index 1)
    if f.raidIcon and conf.raidMarker ~= false and index == 1 then
        f.raidIcon:SetTexCoord(0, 0.25, 0, 0.25)  -- star
        f.raidIcon:Show()
    elseif f.raidIcon then
        f.raidIcon:Hide()
    end

    -- Event icons in preview (show on specific frames for visual reference)
    if f.readyCheckIcon and conf.readyCheckIcon ~= false then
        if index == 1 or index == 3 then
            f.readyCheckIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            f.readyCheckIcon:Show()
        else
            f.readyCheckIcon:Hide()
        end
    elseif f.readyCheckIcon then f.readyCheckIcon:Hide() end

    if f.summonIcon and conf.summonIcon ~= false then
        if index == 2 then
            f.summonIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-SummonPending")
            f.summonIcon:Show()
        else
            f.summonIcon:Hide()
        end
    elseif f.summonIcon then f.summonIcon:Hide() end

    if f.resurrectIcon and conf.resurrectIcon ~= false then
        if index == 3 then
            f.resurrectIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
            f.resurrectIcon:Show()
        else
            f.resurrectIcon:Hide()
        end
    elseif f.resurrectIcon then f.resurrectIcon:Hide() end

    if f.phaseIcon and conf.phaseIcon ~= false then
        if index == 4 or index == 2 then
            f.phaseIcon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
            f.phaseIcon:Show()
        else
            f.phaseIcon:Hide()
        end
    elseif f.phaseIcon then f.phaseIcon:Hide() end

    -- Private auras: hide real container (no unit), show mock preview
    if f._gfPrivContainer then f._gfPrivContainer:Hide() end
    if GF.PreviewPrivateAuras then
        GF.PreviewPrivateAuras(f, kind)
    end

    -- Spell indicators preview (placed icons + frame effects with mock data)
    if GF.PreviewSpellIndicators then
        GF.PreviewSpellIndicators(f, kind, nil, nil)
    end

    -- Aura group preview (mock buff/debuff/external icons)
    if GF.PreviewFrameAuras then
        GF.PreviewFrameAuras(f, kind, index)
    end

    -- Status text hidden in preview
    if f.statusIndicatorText then
        f.statusIndicatorText:SetText("")
        f.statusIndicatorText:Hide()
    end

    -- Group number (preview: fake subgroup)
    if f.groupNumberText and conf.showGroupNumber then
        f.groupNumberText:SetText(tostring(((index - 1) % 5) + 1))
        f.groupNumberText:Show()
    elseif f.groupNumberText then
        f.groupNumberText:Hide()
    end

    -- Reverse fill
    if f.health and f.health.SetReverseFill then
        f.health:SetReverseFill(conf.reverseFill and true or false)
    end

    -- Show the frame
    f:Show()
end

function GF.ClearPreviewData(f)
    if not f then return end
    f._msufGFPreviewActive = nil
    f._msufGFPreviewIndex = nil
    if f.nameText then f.nameText:SetText("") end
    if f.textLeftFS then f.textLeftFS:SetText("") end
    if f.textCenterFS then f.textCenterFS:SetText("") end
    if f.textRightFS then f.textRightFS:SetText("") end
    if f.health then f.health:SetValue(0) end
    if GF.SyncPreserveMissingHP then GF.SyncPreserveMissingHP(f, f._msufGFKind or "party", 1, 1) end
    if f.incomingHealBar then f.incomingHealBar:SetValue(0); f.incomingHealBar:Hide() end
    if f.absorbBar then f.absorbBar:SetValue(0); f.absorbBar:Hide() end
    if f.healAbsorbBar then f.healAbsorbBar:SetValue(0); f.healAbsorbBar:Hide() end
    if f.power then f.power:SetValue(0) end
    if f.powerTextLeftFS then f.powerTextLeftFS:SetText(""); f.powerTextLeftFS:Hide() end
    if f.powerTextCenterFS then f.powerTextCenterFS:SetText(""); f.powerTextCenterFS:Hide() end
    if f.powerTextRightFS then f.powerTextRightFS:SetText(""); f.powerTextRightFS:Hide() end
    if f.roleIcon then f.roleIcon:Hide() end
    if f.raidIcon then f.raidIcon:Hide() end
    if f.leaderIcon then f.leaderIcon:Hide() end
    if f.assistIcon then f.assistIcon:Hide() end
    if f.readyCheckIcon then f.readyCheckIcon:Hide() end
    if f.summonIcon then f.summonIcon:Hide() end
    if f.resurrectIcon then f.resurrectIcon:Hide() end
    if f.phaseIcon then f.phaseIcon:Hide() end
    if f.groupNumberText then f.groupNumberText:SetText(""); f.groupNumberText:Hide() end
    if f.statusIndicatorText then f.statusIndicatorText:SetText(""); f.statusIndicatorText:Hide() end
    if f._gfPrivContainer then f._gfPrivContainer:Hide() end
    if GF.HidePreviewPrivateAuras then GF.HidePreviewPrivateAuras(f) end
    if GF.HideSpellIndicators then GF.HideSpellIndicators(f) end
    if GF.HideFrameAuras then GF.HideFrameAuras(f) end
end

------------------------------------------------------------------------
-- Preview frames (standalone, not tied to SecureGroupHeader)
------------------------------------------------------------------------
GF._previewFrames = GF._previewFrames or {}
GF._previewShownCounts = GF._previewShownCounts or {}

function GF.SetPreviewAnchor(kind, parent)
    GF._previewAnchorFrame[kind] = parent
end

------------------------------------------------------------------------
-- Grid position helper (used by ShowPreview + RefreshPreviewLayout)
------------------------------------------------------------------------
local function GridPosition(baseX, baseY, i, w, h, spacing, growth, upc)
    upc = upc or 40
    local col = math.floor((i - 1) / upc)
    local row = (i - 1) % upc
    if growth == "DOWN" then
        return baseX + col * (w + spacing), baseY - row * (h + spacing)
    elseif growth == "UP" then
        return baseX + col * (w + spacing), baseY + row * (h + spacing)
    elseif growth == "RIGHT" then
        return baseX + row * (w + spacing), baseY - col * (h + spacing)
    elseif growth == "LEFT" then
        return baseX - row * (w + spacing), baseY - col * (h + spacing)
    end
    return baseX, baseY
end

local function PreviewUsesPreservedRaidGroups(kind, conf)
    return IsRaidLikeKind(kind) and conf and conf.preserveRaidGroups == true
end

local function SetPreservedPreviewPoint(frame, container, i, w, h, spacing, growth, primary, blockW, blockH)
    primary = primary or 5
    blockW = blockW or w
    blockH = blockH or h
    local groupIndex = math_floor((i - 1) / 5)
    local withinGroup = (i - 1) % 5
    local minor = math_floor(withinGroup / primary)
    local major = withinGroup % primary

    if growth == "DOWN" then
        frame:SetPoint("TOPLEFT", container, "TOPLEFT",
            groupIndex * (blockW + spacing) + minor * (w + spacing),
            -major * (h + spacing))
    elseif growth == "UP" then
        frame:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT",
            groupIndex * (blockW + spacing) + minor * (w + spacing),
            major * (h + spacing))
    elseif growth == "RIGHT" then
        frame:SetPoint("TOPLEFT", container, "TOPLEFT",
            major * (w + spacing),
            -(groupIndex * (blockH + spacing) + minor * (h + spacing)))
    elseif growth == "LEFT" then
        frame:SetPoint("TOPRIGHT", container, "TOPRIGHT",
            -major * (w + spacing),
            -(groupIndex * (blockH + spacing) + minor * (h + spacing)))
    end
end

function GF.ShowPreview(kind, count)
    kind = kind or "party"
    count = count or GetDefaultPreviewCount(kind)
    local conf = GF.GetConf(kind)
    local _, _, totalW, totalH, w, h, spacing, growth, upc, _, _, _, primary, _, _, blockW, blockH = GF.GetGridMetrics(kind, count)
    local preservePreviewGroups = PreviewUsesPreservedRaidGroups(kind, conf)
    local key = kind

    GF._previewActive[key] = true
    GF._previewShownCounts[key] = count

    if not GF._previewFrames[key] then GF._previewFrames[key] = {} end
    local frames = GF._previewFrames[key]

    -- Container at same position as real header
    local anchorParent = GF._previewAnchorFrame and GF._previewAnchorFrame[key]
    local parent = anchorParent or UIParent

    if not GF._previewContainer then GF._previewContainer = {} end
    local container = GF._previewContainer[key]
    if not container then
        container = CreateFrame("Frame", "MSUF_GFPreviewContainer_" .. key, parent)
        container:EnableMouse(false)
        GF._previewContainer[key] = container
    end
    if container:GetParent() ~= parent then container:SetParent(parent) end

    -- Position container identically to the live SecureGroupHeader:
    -- always use the configured full grid footprint, not the reduced dummy
    -- preview count. This keeps Edit Mode previews/movers in the same place
    -- as the real group frames.
    local posCount = GF.GetPositionCount(kind)
    local _, _, posTotalW, posTotalH = GF.GetGridMetrics(kind, posCount)
    local cx, cy = conf.offsetX, conf.offsetY
    if cx == nil or cy == nil then cx, cy = GetDefaultCenter(kind) end
    container:SetSize(math_max(posTotalW, 1), math_max(posTotalH, 1))
    container:ClearAllPoints()
    if anchorParent then
        container:SetPoint("CENTER", parent, "CENTER", 0, 0)
    else
        local af = GF.ResolveAnchorFrame(kind)
        local pt = conf.anchorPoint or conf.point or "CENTER"
        -- (cx, cy) is GRID_CENTER_V1 relative to the resolved configured anchor.
        container:SetPoint("CENTER", af, pt, cx, cy)
    end
    container:Show()

    -- Resolve anchor point + offsets (same as SetupPartyHeader / SetupRaidHeader)
    local anchorPt, xOff, yOff, colAnchor
    if growth == "DOWN" then
        anchorPt = "TOP"; xOff = 0; yOff = -spacing; colAnchor = "LEFT"
    elseif growth == "UP" then
        anchorPt = "BOTTOM"; xOff = 0; yOff = spacing; colAnchor = "LEFT"
    elseif growth == "RIGHT" then
        anchorPt = "LEFT"; xOff = spacing; yOff = 0; colAnchor = "TOP"
    elseif growth == "LEFT" then
        anchorPt = "RIGHT"; xOff = -spacing; yOff = 0; colAnchor = "TOP"
    else
        anchorPt = "TOP"; xOff = 0; yOff = -spacing; colAnchor = "LEFT"
    end

    for i = 1, count do
        local f = frames[i]
        if not f then
            f = CreateFrame("Button", "MSUF_GFPreview_" .. key .. "_" .. i, container, "BackdropTemplate")
            f:SetSize(w, h)
            f._msufGFKind = kind
            f._msufIsGroupFrame = true
            f._msufGFIsPreviewFrame = true
            f.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ((kind == "raid") and "gf_raid" or "gf_party")
            BuildFrameHierarchy(f, kind)
            ApplyFonts(f, kind)
            LayoutText(f, kind)
            LayoutIcons(f, kind)
            if GF.LayoutCornerIndicators then GF.LayoutCornerIndicators(f, kind) end
            frames[i] = f
        end
        if f:GetParent() ~= container then f:SetParent(container) end

        f:SetSize(w, h)
        f:ClearAllPoints()

        if preservePreviewGroups then
            SetPreservedPreviewPoint(f, container, i, w, h, spacing, growth, primary, blockW, blockH)
        else
            -- Replicate SecureGroupHeader child layout (corner-anchored)
            local row = (i - 1) % upc
            local col = math_floor((i - 1) / upc)

            if growth == "DOWN" then
                f:SetPoint("TOPLEFT", container, "TOPLEFT", col * (w + spacing), -row * (h + spacing))
            elseif growth == "UP" then
                f:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", col * (w + spacing), row * (h + spacing))
            elseif growth == "RIGHT" then
                f:SetPoint("TOPLEFT", container, "TOPLEFT", row * (w + spacing), -col * (h + spacing))
            elseif growth == "LEFT" then
                f:SetPoint("TOPRIGHT", container, "TOPRIGHT", -row * (w + spacing), -col * (h + spacing))
            end
        end

        GF.ApplyPreviewData(f, i, kind)
    end

    for i = count + 1, #frames do
        if frames[i] then
            GF.ClearPreviewData(frames[i])
            frames[i]:Hide()
        end
    end
    if not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
        and GF.RefreshPreviewGroupBorder
    then
        GF.RefreshPreviewGroupBorder(kind)
    end
end

function GF.HidePreview(kind)
    kind = kind or "party"
    GF._previewActive[kind] = nil
    if GF._previewShownCounts then GF._previewShownCounts[kind] = nil end
    local frames = GF._previewFrames[kind]
    if frames then
        for i = 1, #frames do
            if frames[i] then
                GF.ClearPreviewData(frames[i])
                frames[i]:Hide()
            end
        end
    end
    local container = GF._previewContainer and GF._previewContainer[kind]
    if container then container:Hide() end
    if not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
        and GF.RefreshPreviewGroupBorder
    then
        GF.RefreshPreviewGroupBorder(kind)
    end
end

local function GF_PreviewsAllowed()
    if _G.MSUF_UnitEditModeActive == true then
        return true
    end
    if _G.MSUF2_GFPagePreviewActive == true then
        return true
    end
    local panel = _G.MSUF_GFOptionsPanel
    if panel and panel.IsShown and panel:IsShown() then
        return true
    end
    return false
end

function GF.HideOrphanedPreviews()
    if GF_PreviewsAllowed() then return false end
    local hidden = false
    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
        local active = GF._previewActive and GF._previewActive[kind]
        local container = GF._previewContainer and GF._previewContainer[kind]
        if active or (container and container.IsShown and container:IsShown()) then
            GF.HidePreview(kind)
            hidden = true
        end
    end
    return hidden
end

------------------------------------------------------------------------
-- Refresh preview layout (sizes + positions from current config)
-- Called by Options sliders when width/height/spacing/growth change.
------------------------------------------------------------------------
function GF.RefreshPreviewLayout(kind)
    kind = kind or "party"
    if not GF._previewActive or not GF._previewActive[kind] then return end
    local frames = GF._previewFrames and GF._previewFrames[kind]
    if not frames then return end
    local count = GetPreviewShownCount(kind)
    local conf = GF.GetConf(kind)
    local _, _, totalW, totalH, w, h, spacing, growth, upc, _, _, _, primary, _, _, blockW, blockH = GF.GetGridMetrics(kind, count)
    local preservePreviewGroups = PreviewUsesPreservedRaidGroups(kind, conf)

    -- Update container position (grid center = stored offset)
    local container = GF._previewContainer and GF._previewContainer[kind]
    if container then
        local posCount = GF.GetPositionCount(kind)
        local _, _, posTotalW, posTotalH = GF.GetGridMetrics(kind, posCount)
        local cx, cy = conf.offsetX, conf.offsetY
        if cx == nil or cy == nil then cx, cy = GetDefaultCenter(kind) end
        local anchorParent = GF._previewAnchorFrame and GF._previewAnchorFrame[kind]
        container:SetSize(math_max(posTotalW, 1), math_max(posTotalH, 1))
        container:ClearAllPoints()
        if anchorParent then
            container:SetPoint("CENTER", anchorParent, "CENTER", 0, 0)
        else
            local af = GF.ResolveAnchorFrame(kind)
            local pt = conf.anchorPoint or conf.point or "CENTER"
            container:SetPoint("CENTER", af, pt, cx, cy)
        end
    end

    for i = 1, #frames do
        local f = frames[i]
        if f and f:IsShown() then
            if container and f:GetParent() ~= container then f:SetParent(container) end
            f:SetSize(w, h)
            if f.barGroup then f.barGroup:SetSize(w, h) end
            f:ClearAllPoints()
            local c = container or UIParent
            if preservePreviewGroups then
                SetPreservedPreviewPoint(f, c, i, w, h, spacing, growth, primary, blockW, blockH)
            else
                local row = (i - 1) % upc
                local col = math_floor((i - 1) / upc)
                if growth == "DOWN" then
                    f:SetPoint("TOPLEFT", c, "TOPLEFT", col * (w + spacing), -row * (h + spacing))
                elseif growth == "UP" then
                    f:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", col * (w + spacing), row * (h + spacing))
                elseif growth == "RIGHT" then
                    f:SetPoint("TOPLEFT", c, "TOPLEFT", row * (w + spacing), -col * (h + spacing))
                elseif growth == "LEFT" then
                    f:SetPoint("TOPRIGHT", c, "TOPRIGHT", -row * (w + spacing), -col * (h + spacing))
                end
            end
        end
    end
    if not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
        and GF.RefreshPreviewGroupBorder
    then
        GF.RefreshPreviewGroupBorder(kind)
    end
end

------------------------------------------------------------------------
-- Refresh all GF frames
------------------------------------------------------------------------
function GF.RefreshAll()
    GF.ForEachFrame(function(f)
        local unit = f.unit
        if unit and UnitExists(unit) then
            GF.UpdateButton(f, unit)
        end
    end)
end

function GF.RebuildAll()
    if InCombatLockdown() then
        GF.UpdateAnyEnabledFlag()
        if GF.DeactivateDisabledKinds then GF.DeactivateDisabledKinds(false) end
        if GF.SyncGroupGlobalEvents then GF.SyncGroupGlobalEvents() end
        MarkPostCombatHeaderRecovery()
        return
    end
    MarkHeaderScanInputsChanged()
    GF.HideOrphanedPreviews()
    local partyConf = GF.GetConf("party")
    local raidKind = GetLiveRaidKind()
    local raidConf  = GF.GetConf(raidKind)
    GF.UpdateAnyEnabledFlag()
    if GF.DeactivateDisabledKinds then GF.DeactivateDisabledKinds(true) end

    local inRaid = IsInRaid and IsInRaid() or false

    _rebuildAllActive = true
    -- Party: build once, show only outside raid
    if partyConf.enabled == true then
        SetupPartyHeader()
        if inRaid and GF.headers.party then
            GF.headers.party:Hide()
        end
    elseif GF.headers.party then
        GF.headers.party:Hide()
    end

    -- Raid: build once, show only in raid
    if raidConf.enabled == true then
        SetupRaidHeader()
        if not inRaid then
            HideRaidHeaders()
        end
    else
        HideRaidHeaders()
    end
    _rebuildAllActive = false

    GF.DisableBlizzardFrames()
    GF.RefreshPreviewLayout("party")
    GF.RefreshPreviewLayout("raid")
    GF.RefreshPreviewLayout("mythicraid")
    -- Deferred: after SecureGroupHeader repositions children, re-apply visuals (geometry, bars, text)
    local function ClearBuiltRegisteredUnits(...)
        for ci = 1, select("#", ...) do
            local ch = select(ci, ...)
            if ch and ch._msufGFBuilt then
                ch._msufGFRegisteredUnit = nil
            end
        end
    end
    C_Timer.After(0.05, function()
        if InCombatLockdown() then
            MarkPostCombatHeaderRecovery()
            return
        end
        MarkHeaderScanInputsChanged()
        -- Force event re-registration (picks up aura/dispel toggle changes)
        for _, kind in pairs({"party"}) do
            local hdr = GF.headers[kind]
            if hdr and GF.IsKindEnabled(kind) then
                ClearBuiltRegisteredUnits(hdr:GetChildren())
                ScanHeaderChildren(hdr, kind, true)
            end
        end
        if GF.IsKindEnabled(GetLiveRaidKind()) then
            ForEachRaidHeader(function(hdr)
                ClearBuiltRegisteredUnits(hdr:GetChildren())
            end)
            ScanRaidHeaders(GetLiveRaidKind(), true)
        end
        GF.MarkAllDirty(GF.DIRTY_ALL)
        if GF.RefreshGroupBorders then GF.RefreshGroupBorders() end
        if GF.SyncGroupGlobalEvents then GF.SyncGroupGlobalEvents() end
    end)
end

function GF.RefreshOutlineGeometry()
    if InCombatLockdown() then
        GF._pendingRefreshGeometry = true
        GF._pendingRefreshVisuals = true
        MarkPostCombatHeaderRecovery()
        return
    end
    if GF.InvalidateConfCache then GF.InvalidateConfCache() end
    MarkHeaderScanInputsChanged()

    local partyHeader = GF.headers and GF.headers.party
    if partyHeader and GF.IsKindEnabled("party") then
        ScanHeaderChildren(partyHeader, "party", true)
    end

    local raidKind = GetLiveRaidKind()
    if GF.IsKindEnabled(raidKind) then
        ScanRaidHeaders(raidKind, true)
    end

    if GF.RefreshVisuals then
        GF.RefreshVisuals()
    elseif GF.MarkAllDirty then
        GF.MarkAllDirty((GF.DIRTY_GEOMETRY or 0x01) + (GF.DIRTY_BORDER or 0x10) + (GF.DIRTY_LAYOUT or 0x20))
    end
end

local function GF_DifficultySignature()
    local liveKind = GetLiveRaidKind()
    local _, instanceType, difficultyID = GetInstanceInfo and GetInstanceInfo()
    local situation = (GF.DetectRaidSituation and GF.DetectRaidSituation()) or ""
    local conf = GF.GetConf(liveKind)
    local mode = (conf and conf.raidLayoutMode) or "manual"
    local active = (conf and conf._activeRaidLayout) or ""
    return tostring(liveKind) .. "|" .. tostring(instanceType) .. "|" .. tostring(difficultyID)
        .. "|" .. tostring(mode) .. "|" .. tostring(active) .. "|" .. tostring(situation)
end

local function GF_UpdateDifficultyCache()
    GF._lastDifficultySig = GF_DifficultySignature()
    GF._lastDifficultyLiveKind = GetLiveRaidKind()
end

------------------------------------------------------------------------
-- Toggle headers when group type changes (party ↔ raid)
------------------------------------------------------------------------
function GF.UpdateGroupVisibility()
    if InCombatLockdown() then
        GF._pendingVisibilityUpdate = true
        GF.UpdateAnyEnabledFlag()
        if GF.DeactivateDisabledKinds then GF.DeactivateDisabledKinds(false) end
        return
    end
    MarkHeaderScanInputsChanged()
    local inRaid = IsInRaid and IsInRaid() or false
    local partyConf = GF.GetConf("party")
    local raidKind = GetLiveRaidKind()
    local raidConf  = GF.GetConf(raidKind)
    GF.UpdateAnyEnabledFlag()

    -- Party header
    if GF.headers.party then
        if partyConf.enabled == true and not inRaid then
            GF.SyncHeaderPosition("party")
            GF.headers.party:Show()
            ScheduleHeaderChildScan("party", 0, "party")
            ScheduleHeaderChildScan("party", 0.5, "party")
        else
            GF.headers.party:Hide()
            if GF.DeactivateKindRuntime then GF.DeactivateKindRuntime("party", true) end
        end
    end

    -- Raid header
    if AnyRaidHeader() then
        if raidConf.enabled == true and inRaid then
            GF.SyncHeaderPosition(raidKind)
            ShowRaidHeaders(raidKind)
            ScheduleHeaderChildScan("raid", 0, raidKind)
            ScheduleHeaderChildScan("raid", 0.5, raidKind)
        else
            HideRaidHeaders()
        end
    end
    if GF.DeactivateDisabledKinds then GF.DeactivateDisabledKinds(true) end
    if GF.DisableBlizzardFrames then GF.DisableBlizzardFrames() end
    if GF.SyncGroupGlobalEvents then GF.SyncGroupGlobalEvents() end
end

local _gfVisibilityQueued = false
local function GF_FlushGroupVisibility()
    _gfVisibilityQueued = false
    GF.UpdateGroupVisibility()
end

local function GF_RequestGroupVisibility()
    if InCombatLockdown() then
        GF._pendingVisibilityUpdate = true
        return
    end
    if _gfVisibilityQueued then return end
    _gfVisibilityQueued = true
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("GF_CORE_VISIBILITY", GF_FlushGroupVisibility)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, GF_FlushGroupVisibility)
    else
        GF_FlushGroupVisibility()
    end
end

------------------------------------------------------------------------
-- Event frame
------------------------------------------------------------------------
local function OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        GF.EnsureDB()
        local partyConf = GF.GetConf("party")
        local raidConf  = GF.GetConf(GetLiveRaidKind())
        GF.UpdateAnyEnabledFlag()
        if partyConf.enabled == true or raidConf.enabled == true then
            GF.RebuildAll()
        else
            if GF.DeactivateDisabledKinds then GF.DeactivateDisabledKinds(true) end
            if GF.DisableBlizzardFrames then GF.DisableBlizzardFrames() end
            if GF.SyncGroupGlobalEvents then GF.SyncGroupGlobalEvents() end
        end
        GF_UpdateDifficultyCache()

    elseif event == "GROUP_ROSTER_UPDATE" then
        MarkHeaderScanInputsChanged()
        GF.UpdateAnyEnabledFlag()
        if not GF._anyEnabled then
            if GF.DeactivateDisabledKinds then GF.DeactivateDisabledKinds(not (InCombatLockdown and InCombatLockdown())) end
            if GF.DisableBlizzardFrames then GF.DisableBlizzardFrames() end
            if GF.SyncGroupGlobalEvents then GF.SyncGroupGlobalEvents() end
            return
        end
        -- Switch party/raid visibility + rescan children
        GF_RequestGroupVisibility()

        -- Invalidate group size cache (dynamic aura scale)
        if GF.InvalidateGroupSizeCache then GF.InvalidateGroupSizeCache() end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if GF._pendingPartyRefresh then
            GF._pendingPartyRefresh = nil
            SetupPartyHeader()
        end
        if GF._pendingRaidRefresh then
            GF._pendingRaidRefresh = nil
            SetupRaidHeader()
        end
        if GF._pendingBlizzardDisable then
            GF._pendingBlizzardDisable = nil
            GF.DisableBlizzardFrames()
        end
        GF.UpdateAnyEnabledFlag()
        if not GF._anyEnabled then
            if GF.DeactivateDisabledKinds then GF.DeactivateDisabledKinds(true) end
            if GF.DisableBlizzardFrames then GF.DisableBlizzardFrames() end
            if GF.SyncGroupGlobalEvents then GF.SyncGroupGlobalEvents() end
            GF._pendingRebuild = nil
            GF._pendingVisibilityUpdate = nil
            GF._pendingRefreshGeometry = nil
            GF._pendingRefreshVisuals = nil
            return
        end
        -- Force rebuild if headers don't exist (mid-combat /reload recovery)
        local needRebuild = GF._pendingRebuild
        if not GF.headers.party and not AnyRaidHeader() then needRebuild = true end
        if needRebuild then
            GF._pendingRebuild = nil
            GF.RebuildAll()
            GF_UpdateDifficultyCache()
        end
        if GF._pendingVisibilityUpdate then
            GF._pendingVisibilityUpdate = nil
            GF.UpdateGroupVisibility()
        end
        if GF._pendingRefreshGeometry then
            GF._pendingRefreshGeometry = nil
            if GF.RefreshGeometry then GF.RefreshGeometry() end
        end
        if GF._pendingRefreshVisuals then
            GF._pendingRefreshVisuals = nil
            if GF.RefreshVisuals then GF.RefreshVisuals() end
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        GF.EnsureDB()
        local partyConf = GF.GetConf("party")
        local raidConf  = GF.GetConf(GetLiveRaidKind())
        GF.UpdateAnyEnabledFlag()
        if partyConf.enabled == true or raidConf.enabled == true then
            -- Only recreate headers on actual zone transitions (not /reload).
            -- /reload creates everything fresh anyway, no C-side state bug.
            if not isLogin and not isReload then
                GF._forceRecreateHeaders = true
            end
            if GF._zoneFixTicker then
                GF._zoneFixTicker:Cancel()
                GF._zoneFixTicker = nil
            end
            C_Timer.After(0.3, function()
                if not InCombatLockdown() then
                    -- Auto-switch raid layout per situation (Mythic/Normal/OpenWorld)
                    if GF.AutoSwitchRaidLayout then
                        GF.AutoSwitchRaidLayout()
                    end
                    GF.RebuildAll()
                    GF._forceRecreateHeaders = nil
                    GF_UpdateDifficultyCache()
                else
                    MarkPostCombatHeaderRecovery()
                end
            end)
        else
            if GF.DeactivateDisabledKinds then GF.DeactivateDisabledKinds(not (InCombatLockdown and InCombatLockdown())) end
            if GF.DisableBlizzardFrames then GF.DisableBlizzardFrames() end
            if GF.SyncGroupGlobalEvents then GF.SyncGroupGlobalEvents() end
        end
    elseif event == "PLAYER_DIFFICULTY_CHANGED" then
        local sig = GF_DifficultySignature()
        if GF._lastDifficultySig == sig then
            return
        end
        GF._lastDifficultySig = sig
        GF.UpdateAnyEnabledFlag()
        if not GF._anyEnabled then
            if GF.DeactivateDisabledKinds then GF.DeactivateDisabledKinds(not (InCombatLockdown and InCombatLockdown())) end
            if GF.DisableBlizzardFrames then GF.DisableBlizzardFrames() end
            if GF.SyncGroupGlobalEvents then GF.SyncGroupGlobalEvents() end
            GF_UpdateDifficultyCache()
            return
        end

        if InCombatLockdown() then
            MarkPostCombatHeaderRecovery()
        else
            local oldKind = GF._lastDifficultyLiveKind
            local switched = false
            if GF.AutoSwitchRaidLayout then
                switched = (GF.AutoSwitchRaidLayout() == true)
            end
            local liveKind = GetLiveRaidKind()
            GF._lastDifficultyLiveKind = liveKind
            if not switched and oldKind and oldKind ~= liveKind then
                GF.RebuildAll()
            end
            GF.UpdateGroupVisibility()
            GF_UpdateDifficultyCache()
        end
    end
end

local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("GROUP_ROSTER_UPDATE")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
ef:SetScript("OnEvent", OnEvent)
GF._eventFrame = ef

------------------------------------------------------------------------
-- Global exports
------------------------------------------------------------------------
--- Convenience refresh (called by EM2 popup Apply — syncs text/font/layout)
function GF.Refresh()
    if GF.MarkAllDirty then GF.MarkAllDirty(0x3F) end -- DIRTY_ALL
    if GF.RefreshVisuals then GF.RefreshVisuals() end
end

_G.MSUF_GF_ShowPreview      = GF.ShowPreview
_G.MSUF_GF_HidePreview      = GF.HidePreview
_G.MSUF_GF_RebuildAll        = GF.RebuildAll
_G.MSUF_GF_RefreshAll        = GF.RefreshAll
_G.MSUF_GF_Refresh           = GF.Refresh
_G.MSUF_GF_RefreshOutlineGeometry = GF.RefreshOutlineGeometry
_G.MSUF_GF_RefreshPreviewLayout = GF.RefreshPreviewLayout
_G.MSUF_GF_DisableBlizzard   = GF.DisableBlizzardFrames
_G.MSUF_GF_RestoreBlizzard   = GF.RestoreBlizzardFrames
_G.MSUF_GF_UpdateButton      = GF.UpdateButton
_G.MSUF_GF_InitButton        = GF_InitButton
_G.MSUF_GF_UpdateGroupVisibility = GF.UpdateGroupVisibility

-- Idle-diagnosis exports
_G.MSUF_GF_ScanHeaderChildren = ScanHeaderChildren
_G.MSUF_GF_CoreEventFrame     = ef

------------------------------------------------------------------------
-- Profile-swap re-init: hook MSUF_SwitchProfile → EnsureDB + RebuildAll
------------------------------------------------------------------------
do
    C_Timer.After(0.2, function()
        local origSwitch = _G.MSUF_SwitchProfile
        if type(origSwitch) == "function" then
            _G.MSUF_SwitchProfile = function(...)
                origSwitch(...)
                GF.EnsureDB()
                if GF.InvalidateConfCache then GF.InvalidateConfCache() end
                C_Timer.After(0.1, function()
                    GF.RebuildAll()
                end)
            end
        end
    end)
end

-- Debug: /run MSUF_GF_DebugSizes()
function _G.MSUF_GF_DebugSizes()
    local GF = _G.MSUF_NS and _G.MSUF_NS.GF or {}
    local header = GF.headers and GF.headers["party"]
    if not header then print("No party header"); return end
    local children = { header:GetChildren() }
    for ci = 1, #children do
        local child = children[ci]
        if child and child.GetAttribute and child:GetAttribute("unit") then
            local unit = child:GetAttribute("unit") or "?"
            local cw, ch = child:GetSize()
            -- Enumerate ALL child frames and regions
            local subFrames = { child:GetChildren() }
            local subRegions = { child:GetRegions() }
            print(("[%d] %s sz=%.0fx%.0f children=%d regions=%d"):format(ci, unit, cw, ch, #subFrames, #subRegions))
            for si, sf in ipairs(subFrames) do
                local sw, sh = sf:GetSize()
                local shown = sf:IsShown()
                local np = sf:GetNumPoints()
                local name = sf:GetName() or sf:GetObjectType()
                -- check if it extends beyond parent
                local sl, st, sb, sr = sf:GetLeft(), sf:GetTop(), sf:GetBottom(), sf:GetRight()
                local cl, ct, cb, cr = child:GetLeft(), child:GetTop(), child:GetBottom(), child:GetRight()
                local extends = ""
                if sl and cl and sr and cr and st and ct and sb and cb then
                    if sl < cl - 1 or sr > cr + 1 or st > ct + 1 or sb < cb - 1 then
                        extends = " *** EXTENDS OUTSIDE ***"
                    end
                end
                if shown then
                    print(("  F[%d] %s sz=%.0fx%.0f pts=%d%s"):format(si, name, sw, sh, np, extends))
                end
            end
            for si, sr in ipairs(subRegions) do
                local sw, sh = 0, 0
                if sr.GetSize then sw, sh = sr:GetSize() end
                local shown = sr:IsShown()
                local ot = sr:GetObjectType()
                local sl, st, sb, sright = sr:GetLeft(), sr:GetTop(), sr:GetBottom(), sr:GetRight()
                local cl, ct, cb, cr = child:GetLeft(), child:GetTop(), child:GetBottom(), child:GetRight()
                local extends = ""
                if sl and cl and sright and cr and st and ct and sb and cb then
                    if sl < cl - 1 or sright > cr + 1 or st > ct + 1 or sb < cb - 1 then
                        extends = " *** EXTENDS ***"
                    end
                end
                if shown and extends ~= "" then
                    print(("  R[%d] %s sz=%.0fx%.0f%s"):format(si, ot, sw, sh, extends))
                end
            end
        end
    end
end
