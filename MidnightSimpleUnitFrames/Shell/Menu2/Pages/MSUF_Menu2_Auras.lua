local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Auras page.
-- Builds controls for Auras3 unit/group scopes, lanes, filters, and visual options. The page
-- talks to the Auras3 menu model; live tracking/filtering is handled by native 12.1 aura containers.
local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local A3 = MSUF.MSUF_Auras3
local Model = A3 and A3.MenuModel
local VTP = M.ValueTextPairs
local PreviewHelpers = M.PreviewHelpers or {}
if type(W) ~= "table" or type(T) ~= "table" or type(Model) ~= "table" then return end
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local MSUF_SetIconTexture = _G.MSUF_SetIconTexture
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local AURA_PREVIEW_EDGE_OPTS = { linesKey = "edge", maxEdgeSize = 1, texture = TEX_W8, color = function() return 1, 1, 1, 0.95 end }
local AURA_MENU_APPLY_DELAY = 0.04
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local tonumber, tostring, type, ipairs, pairs = tonumber, tostring, type, ipairs, pairs
local AURA_SCOPE_VALUES = VTP "shared=Shared|player=Player|target=Target|focus=Focus|boss=Boss|party=Party|raid=Raid / Mythic"
local AURA_SCOPE_LABELS = { shared = "Shared", player = "Player", target = "Target", focus = "Focus", boss = "Boss", party = "Party", raid = "Raid / Mythic" }
local AURA_SCOPE_VALID = M.KeySetFromWords "shared player target focus boss party raid"
local AURA_GROUP_SCOPES = M.KeySetFromWords "party raid mythicraid"
local LANE_VALUES = VTP "buff=Buffs|debuff=Debuffs"
local DEBUFF_TYPE_BORDER_MODE_VALUES = VTP "OFF=Off|BORDER=Border|SYMBOL=Border + Symbol"
local DEBUFF_TYPE_BORDER_PREVIEW_ATLAS = {
    BORDER = "ui-debuff-border-magic-noicon",
    SYMBOL = "ui-debuff-border-magic-icon",
}
local BUFF_EXCLUSIVE = VTP "none=None"
local DEBUFF_EXCLUSIVE = VTP "none=None|raid=Raid"
local NATIVE_EXACT_AURA_FILTERS_ENABLED = false
local NATIVE_EXACT_AURA_FILTERS_DISABLED_TEXT = "Temporarily disabled for 12.1 native AuraContainers. Blizzard currently exposes filter strings only, not SpellID whitelist/blacklist predicates."
local GROUP_NATIVE_FILTER_LABELS = {
    ALL = "All",
    PLAYER = "Player",
    RAID = "Raid",
    RAID_IN_COMBAT = "Raid In Combat",
    RAID_PLAYER_DISPELLABLE = "Dispellable",
    EXTERNAL_DEFENSIVE = "External Defensive",
    BIG_DEFENSIVE = "Big Defensive",
    CROWD_CONTROL = "Crowd Control",
}
local GROUP_NATIVE_FILTER_ALLOWED = {
    buff = M.KeySetFromWords "ALL PLAYER RAID RAID_IN_COMBAT EXTERNAL_DEFENSIVE BIG_DEFENSIVE",
    debuff = M.KeySetFromWords "ALL PLAYER RAID RAID_IN_COMBAT RAID_PLAYER_DISPELLABLE CROWD_CONTROL",
}
local function Tr(text)
    if type(M.Tr) == "function" then return M.Tr(text) end
    return text
end
local function Round(value)
    value = tonumber(value) or 0
    if value < 0 then return -floor((-value) + 0.5) end
    return floor(value + 0.5)
end
local function NormalizeDebuffTypeBorderMode(value, fallback)
    if value == true then return "SYMBOL" end
    if value == false then return "OFF" end
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
    if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
        or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
        return "SYMBOL"
    end
    if value == "OFF" or value == "NONE" or value == "DISABLED" then return "OFF" end
    return fallback or "OFF"
end
local function AddTooltip(widget, title, body)
    return M.AddTooltip(widget, title, body, { hook = true, titleAsLine = true })
end
local function ActionButton(parent, label, width, role)
    if W.RoleButton then return W.RoleButton(parent, label, role or "normal", width or 90, 24) end
    if W.TopButton then return W.TopButton(parent, label, width or 90, 24) end
    local btn = T.Button(parent, label, width or 90, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(btn) end
    return btn
end
local function Card(parent, title, subtitle, x, y, width, height)
    local card = W.ControlCard(parent, title, subtitle, x, y, width, height)
    if card and T.ApplyBackdrop then T.ApplyBackdrop(card, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
    return card
end
local function Rebuild(ctx)
    local key = (ctx and ctx.key) or M.activeKey or "auras3"
    if M.InvalidatePage and M.SelectPage and M.frame and M.frame.IsShown and M.frame:IsShown() then
        M.InvalidatePage(key)
        M.activeKey = nil
        M.SelectPage(key)
    elseif M.RequestRefresh then
        M.RequestRefresh(ctx, "auras-rebuild-fallback")
    elseif M.Refresh then
        M.Refresh(ctx)
    end
end
local function SelectPage(pageKey, scope)
    if scope then
        M.SetMenuStateValue("auraScope", scope)
        if scope == "party" or scope == "raid" then M.SetMenuStateValue("auraStyleGFScope", scope) end
    end
    if M.SelectPage then M.SelectPage(pageKey or "auras3") end
end
local pendingAuraUnits = {}
local pendingAuraReasons = {}
local pendingAuraGlobal
local pendingAuraGlobalReason
local pendingAuraRefreshCtx
local pendingAuraRefreshReason
local auraApplyQueued = false
local auraTextRefreshQueued = false
local function AurasProfileStart()
    return M.PerfProfile and M.PerfProfile.enabled == true and M.ProfileStart and M.ProfileStart() or nil
end
local function AurasProfileStop(key, started, extraCount)
    if M.PerfProfile and M.PerfProfile.enabled == true and M.ProfileStop then
        M.ProfileStop("aurasPage", key, started, extraCount)
    end
end
local function ScheduleAuraMenuWork(key, delay, fn)
    if type(_G.MSUF_ScheduleDelayOnce) == "function" then
        _G.MSUF_ScheduleDelayOnce(key, delay or AURA_MENU_APPLY_DELAY, fn)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(delay or AURA_MENU_APPLY_DELAY, fn)
    else
        fn()
    end
end
local function AurasMenuCombatLocked()
    if type(M.IsConfigCombatLocked) == "function" then return M.IsConfigCombatLocked() and true or false end
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then return _G.MSUF_IsConfigCombatLocked() and true or false end
    return (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false
end
local function QueueAurasPageRefresh(ctx, reason)
    if AurasMenuCombatLocked() then return false end
    if M.RequestRefresh then
        M.RequestRefresh(ctx, reason or "auras-refresh")
    elseif M.Refresh then
        M.Refresh(ctx)
    end
end
local function FlushAuraApply()
    auraApplyQueued = false
    local units, reasons = pendingAuraUnits, pendingAuraReasons
    local global, globalReason = pendingAuraGlobal, pendingAuraGlobalReason
    local refreshCtx, refreshReason = pendingAuraRefreshCtx, pendingAuraRefreshReason
    pendingAuraUnits, pendingAuraReasons = {}, {}
    pendingAuraGlobal, pendingAuraGlobalReason = nil, nil
    pendingAuraRefreshCtx, pendingAuraRefreshReason = nil, nil

    local started = AurasProfileStart()
    local count = 0
    if global then
        Model.Apply("shared", globalReason or "AURAS3_MENU2_BATCH")
        count = 1
    else
        for unit in pairs(units) do
            Model.Apply(unit, reasons[unit] or "AURAS3_MENU2_BATCH")
            count = count + 1
        end
    end
    AurasProfileStop("FlushAuraApply", started, count)

    if (refreshCtx or refreshReason) and not AurasMenuCombatLocked() then
        QueueAurasPageRefresh(refreshCtx, refreshReason or "auras-apply")
    end
end
local function QueueAuraApply(ctx, unit, reason, refresh)
    reason = reason or "AURAS3_MENU2"
    unit = unit or "shared"
    if unit == "shared" then
        pendingAuraGlobal = true
        pendingAuraGlobalReason = reason
        pendingAuraUnits, pendingAuraReasons = {}, {}
    elseif not pendingAuraGlobal then
        pendingAuraUnits[unit] = true
        pendingAuraReasons[unit] = reason
    end
    if refresh then
        pendingAuraRefreshCtx = ctx or pendingAuraRefreshCtx
        pendingAuraRefreshReason = reason
    end
    if auraApplyQueued then return end
    auraApplyQueued = true
    ScheduleAuraMenuWork("MSUF2_AURAS_PAGE_APPLY", AURA_MENU_APPLY_DELAY, FlushAuraApply)
end
local function ApplyUnit(ctx, unit, reason, refresh)
    QueueAuraApply(ctx, unit, reason or "AURAS3_MENU2", refresh == true)
end
local BindSwitch, BindToggle, BindSlider = M.BindSwitchAt, M.BindToggleAt, M.BindSliderAt
local BindDropdown, BindTextInput, BindColor = M.BindDropdownAt, M.BindTextInputAt, M.BindColorAt
local function BuildActionTabs(ctx, parent, values, x, y, width, getValue, setValue, gap, buttonFactory)
    gap = gap or 6
    local count = #values
    local bw = max(54, floor(((width or 720) - gap * (count - 1)) / count))
    local buttons = {}
    for i = 1, count do
        local item = values[i]
        local btn = (buttonFactory and buttonFactory(parent, item, bw)) or ActionButton(parent, item.text, bw)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (bw + gap), y)
        btn:SetScript("OnClick", function() setValue(item.value) end)
        buttons[i] = btn
        if item.value ~= nil then buttons[item.value] = btn end
    end
    local function RefreshButtons()
        local current = getValue()
        for i = 1, count do
            if buttons[i].SetActive then buttons[i]:SetActive(values[i].value == current) end
        end
    end
    M.TrackRefresh(ctx, RefreshButtons)
    return getValue(), buttons, RefreshButtons
end
local function CurrentScope()
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    local scope = M.auraScope or "shared"
    if scope == "mythicraid" then scope = "raid" end
    return AURA_SCOPE_VALID[scope] and scope or "shared"
end
local function SetCurrentScope(scope)
    scope = scope or "shared"
    if scope == "mythicraid" then scope = "raid" end
    M.SetMenuStateValue("auraScope", scope)
    if scope == "party" or scope == "raid" then M.SetMenuStateValue("auraStyleGFScope", scope) end
end
local function IsGroupScope(scope)
    scope = scope or CurrentScope()
    return AURA_GROUP_SCOPES[scope] == true
end
local function ScopeLabel(scope)
    return AURA_SCOPE_LABELS[scope] or "Raid / Mythic"
end
local function BuildScopeTabs(ctx, section, x, y, width)
    return BuildActionTabs(ctx, section, AURA_SCOPE_VALUES, x, y, width, CurrentScope, function(value)
        SetCurrentScope(value)
        Rebuild(ctx)
    end)
end
local function BuildAuraChrome(ctx, b, title, subtitle)
    Model.EnsureDB()
    b:GlobalStyleHeader(title, subtitle, 72)
    local scope = b:Section("Scope", 78)
    local w = scope._msuf2Width or b.width or 720
    BuildScopeTabs(ctx, scope, 16, -34, w - 32)
    return CurrentScope()
end
local function FinishPage(ctx, b)
    if ctx and ctx.SetContentHeight then ctx:SetContentHeight(abs(b.y) + 42) end
end
local SetCurrentLane
local function CurrentLane(stateKey, defaultValue)
    local lane = M[stateKey] or defaultValue or "debuff"
    if lane ~= "buff" and lane ~= "debuff" then lane = defaultValue or "debuff" end
    return lane
end
function SetCurrentLane(stateKey, lane)
    lane = lane == "buff" and "buff" or "debuff"
    M.SetMenuStateValue(stateKey, lane)
    if stateKey ~= "auraStyleGFLane" then M.SetMenuStateValue("auraStyleGFLane", lane) end
end
local function BuildLaneTabs(ctx, parent, stateKey, x, y, width)
    BuildActionTabs(ctx, parent, LANE_VALUES, x, y, width, function() return CurrentLane(stateKey, "debuff") end, function(value)
        SetCurrentLane(stateKey, value)
        Rebuild(ctx)
    end)
end
local function LaneTitle(kind)
    return kind == "buff" and "Buff" or "Debuff"
end
local function LanePlural(kind)
    return kind == "buff" and "Buffs" or "Debuffs"
end
local function BuildAuraStyleNav(ctx, b)
    local h = 54
    local section = T.Panel(b.parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
    T.ApplySurface(section, "card")
    section:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    section:SetSize(b.width, h)
    section._msuf2Width = b.width
    b.y = b.y - h - 12
    if ctx and ctx.SetContentHeight then ctx:SetContentHeight(abs(b.y) + 28) end
    local w = section._msuf2Width or b.width or 720
    local navW = min(460, w - 32)
    local gap = 8
    local function NavButton(parent, item, width)
        local btn = T.Button(parent, item.text or LanePlural(item.value), width, 24)
        if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
        return btn
    end
    BuildActionTabs(ctx, section, LANE_VALUES, 16, -15, navW, function()
        return CurrentLane("auraStyleGFLane", "debuff")
    end, function(kind)
        SetCurrentLane("auraStyleGFLane", kind)
        local key = (ctx and ctx.key) or M.activeKey
        if key == "auras3_buffs" or key == "auras3_debuffs" then
            SelectPage("auras3_styling", CurrentScope())
        else
            Rebuild(ctx)
        end
    end, gap, NavButton)
end
local function OtherLane(kind)
    return kind == "buff" and "debuff" or "buff"
end
local function LaneMaxKey(kind)
    return kind == "buff" and "maxBuffs" or "maxDebuffs"
end
local function LaneSizeKey(kind)
    return kind == "buff" and "buffGroupIconSize" or "debuffGroupIconSize"
end
local function LaneXKey(kind)
    return kind == "buff" and "buffGroupOffsetX" or "debuffGroupOffsetX"
end
local function LaneYKey(kind)
    return kind == "buff" and "buffGroupOffsetY" or "debuffGroupOffsetY"
end
local function LaneDefaultMax(kind)
    return kind == "buff" and 8 or 12
end
local function LaneDefaultY(kind)
    return kind == "buff" and 36 or 6
end
local function UnitLaneShown(unit, kind)
    return Model.UnitEnabled(unit) and Model.GroupShown(unit, kind)
end
local function SetUnitLaneShown(ctx, unit, kind, shown, reason)
    if shown then
        Model.SetUnitEnabled(unit, true)
        Model.WriteSharedBool(kind == "buff" and "showBuffs" or "showDebuffs", true)
        Model.SetGroupShown(unit, kind, true)
    else
        Model.SetGroupShown(unit, kind, false)
        if not Model.GroupShown(unit, OtherLane(kind)) then Model.SetUnitEnabled(unit, false) end
    end
    ApplyUnit(ctx, unit, reason or "AURAS3_VISIBILITY", true)
end
local function GF()
    if type(GP.GF) == "function" then return GP.GF() end
    return MSUF and MSUF.GF
end
local function RefreshGFPreview()
    if type(GP.RefreshGFPreview) == "function" then GP.RefreshGFPreview() end
end
local function GroupScopeKinds(scope)
    if scope == "party" then return "party" end
    return "raid", "mythicraid"
end
local function GroupConf(kind)
    if type(GP.Conf) == "function" then return GP.Conf(kind) end
    local db = M.EnsureDB()
    local key = kind == "raid" and "gf_raid" or (kind == "mythicraid" and "gf_mythicraid" or "gf_party")
    db[key] = db[key] or {}
    return db[key]
end
local function QueueGroupScope(scope, mode)
    local a, b = GroupScopeKinds(scope)
    local queued = false
    if type(GP.QueueGF) == "function" then
        GP.QueueGF(a, mode or "visual")
        if b then GP.QueueGF(b, mode or "visual") end
        queued = true
    end
    if not queued then
        RefreshGFPreview()
    end
end
local function GFAurasRoot(kind)
    local conf = GroupConf(kind)
    conf.auras = conf.auras or {}
    if conf.auras.renderer ~= "CUSTOM" then conf.auras.renderer = "CUSTOM" end
    conf.auras.blizzardTypes = conf.auras.blizzardTypes or {}
    conf.auras.buff = conf.auras.buff or {}
    conf.auras.debuff = conf.auras.debuff or {}
    return conf.auras
end
local function GFAuraGroup(kind, groupKey)
    local root = GFAurasRoot(kind)
    root[groupKey] = root[groupKey] or {}
    return root[groupKey]
end
local function GFReadRoot(scope)
    local kind = GroupScopeKinds(scope)
    return GFAurasRoot(kind)
end
local function GFReadGroup(scope, groupKey)
    local kind = GroupScopeKinds(scope)
    return GFAuraGroup(kind, groupKey)
end
local function GFReadConf(scope)
    local kind = GroupScopeKinds(scope)
    return GroupConf(kind)
end
local function GFWriteScopeValue(scope, mode, getTarget, key, value)
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local target = getTarget(kind)
        if target[key] == value then return end
        target[key] = value
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then QueueGroupScope(scope, mode or "visual") end
end
local function GFWriteGroupValue(scope, groupKey, key, value, mode)
    GFWriteScopeValue(scope, mode, function(kind) return GFAuraGroup(kind, groupKey) end, key, value)
end
local function GFWriteGroupValues(scope, groupKey, values, mode)
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local target = GFAuraGroup(kind, groupKey)
        for key, value in pairs(values) do
            if target[key] ~= value then
                target[key] = value
                changed = true
            end
        end
    end
    write(a)
    if b then write(b) end
    if changed then QueueGroupScope(scope, mode or "visual") end
end
local function GFWriteRootValue(scope, key, value, mode)
    GFWriteScopeValue(scope, mode, GFAurasRoot, key, value)
end
local function GFWriteConfValue(scope, key, value, mode)
    GFWriteScopeValue(scope, mode, GroupConf, key, value)
end
local function AuraFilter()
    local gf = GF()
    return (gf and gf.AuraFilter) or _G.MSUF_GF_AuraFilter
end
local function GroupFilterValues(groupKey)
    local af = AuraFilter()
    local source = groupKey == "debuff" and af and af.DEBUFF_FILTER_ITEMS or af and af.BUFF_FILTER_ITEMS
    local allowed = GROUP_NATIVE_FILTER_ALLOWED[groupKey == "debuff" and "debuff" or "buff"]
    local out = {}
    if type(source) == "table" then
        for i = 1, #source do
            local item = source[i]
            local value = item and tostring(item.value or item.key or ""):upper()
            if value == "DISPELLABLE" then value = "RAID_PLAYER_DISPELLABLE" end
            if allowed[value] then
                out[#out + 1] = {
                    value = value,
                    text = GROUP_NATIVE_FILTER_LABELS[value] or item.text or item.label or value,
                }
            end
        end
    end
    if #out > 0 then return out end
    if groupKey == "buff" then
        return VT("ALL", "All Buffs", "PLAYER", "My Buffs Only", "RAID", "Raid Buffs", "RAID_IN_COMBAT", "Raid In Combat", "EXTERNAL_DEFENSIVE", "External Defensive", "BIG_DEFENSIVE", "Big Defensive")
    end
    return VT("ALL", "All Debuffs", "PLAYER", "My Debuffs Only", "RAID", "Raid Debuffs", "RAID_IN_COMBAT", "Raid In Combat", "RAID_PLAYER_DISPELLABLE", "Dispellable", "CROWD_CONTROL", "Crowd Control")
end
local function GFAnchorValues()
    local values = GP.STATUS_ICON_ANCHORS or GP.AURA_ANCHORS
    if type(values) == "table" and #values > 0 then return values end
    return VT("CENTER", "Center", "TOPLEFT", "Top Left", "TOPRIGHT", "Top Right", "BOTTOMLEFT", "Bottom Left", "BOTTOMRIGHT", "Bottom Right")
end
local function BindGroupSwitch(ctx, parent, label, x, y, width, scope, groupKey, key, defaultValue, mode, afterSet)
    return BindSwitch(ctx, parent, label, x, y, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            local value = group[key]
            if value == nil then value = defaultValue end
            return value and true or false
        end,
        function(v)
            GFWriteGroupValue(scope, groupKey, key, v and true or false, mode or "visual")
            if afterSet then afterSet(v and true or false) end
        end)
end
local function BindGroupRootSwitch(ctx, parent, label, x, y, width, scope, key, defaultValue, mode, afterSet)
    return BindSwitch(ctx, parent, label, x, y, width,
        function()
            local root = GFReadRoot(scope)
            local value = root[key]
            if value == nil then value = defaultValue end
            return value and true or false
        end,
        function(v)
            GFWriteRootValue(scope, key, v and true or false, mode or "visual")
            if afterSet then afterSet(v and true or false) end
        end)
end
local function BindGroupConfSwitch(ctx, parent, label, x, y, width, scope, key, defaultValue, mode, afterSet)
    return BindSwitch(ctx, parent, label, x, y, width,
        function()
            local conf = GFReadConf(scope)
            local value = conf[key]
            if value == nil then value = defaultValue end
            return value and true or false
        end,
        function(v)
            GFWriteConfValue(scope, key, v and true or false, mode or "visual")
            if afterSet then afterSet(v and true or false) end
        end)
end
local function BindGroupSlider(ctx, parent, label, x, y, minVal, maxVal, step, width, scope, groupKey, key, defaultValue, mode, afterSet)
    return BindSlider(ctx, parent, label, x, y, minVal, maxVal, step, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            return tonumber(group[key]) or defaultValue or 0
        end,
        function(v)
            v = Round(v)
            GFWriteGroupValue(scope, groupKey, key, v, mode or "visual")
            if afterSet then afterSet(v) end
        end)
end
local function BindGroupDropdown(ctx, parent, label, x, y, values, width, scope, groupKey, key, defaultValue, mode, afterSet)
    return BindDropdown(ctx, parent, label, x, y, values, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            return group[key] or defaultValue
        end,
        function(v)
            GFWriteGroupValue(scope, groupKey, key, v or defaultValue, mode or "visual")
            if afterSet then afterSet(v or defaultValue) end
        end)
end
local function ReadGroupDebuffTypeBorderMode(scope, groupKey)
    local group = GFReadGroup(scope, groupKey or "debuff")
    if group.dispelBorderMode ~= nil then
        local mode = NormalizeDebuffTypeBorderMode(group.dispelBorderMode, "OFF")
        return (mode == "OFF" and group.showDispelBorder == true) and "SYMBOL" or mode
    end
    return group.showDispelBorder == true and "SYMBOL" or "OFF"
end
local function WriteGroupDebuffTypeBorderMode(scope, groupKey, value)
    value = NormalizeDebuffTypeBorderMode(value, "OFF")
    GFWriteGroupValues(scope, groupKey or "debuff", {
        dispelBorderMode = value,
        showDispelBorder = value ~= "OFF",
        showDispelSymbol = value == "SYMBOL",
    }, "visual")
end
local function RequestAuraTextRefresh()
    if auraTextRefreshQueued then return end
    auraTextRefreshQueued = true
    ScheduleAuraMenuWork("MSUF2_AURAS_TEXT_REFRESH", AURA_MENU_APPLY_DELAY, function()
        auraTextRefreshQueued = false
        local started = AurasProfileStart()
        if A3 and type(A3.ApplyFontsFromGlobal) == "function" then
            A3.ApplyFontsFromGlobal()
        elseif A3 and type(A3.RefreshAll) == "function" then
            A3.RefreshAll()
        else
            QueueAuraApply(nil, "shared", "AURAS3_TEXT_REFRESH", false)
        end
        if type(M.RefreshGFNativePreviews) == "function" then
            M.RefreshGFNativePreviews("AURAS3_TEXT_REFRESH")
        end
        if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
            _G.MSUF_UFPreview_RequestRefresh("AURAS3_TEXT_REFRESH")
        end
        AurasProfileStop("RequestAuraTextRefresh", started, 1)
    end)
end
local function CreateAuraPreviewIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(24, 24)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.85)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    if f.icon.SetTexCoord then f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    f.swipe = f:CreateTexture(nil, "ARTWORK")
    f.swipe:SetPoint("TOPLEFT", f, "TOP", 0, -1)
    f.swipe:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.swipe:SetTexture(TEX_W8)
    f.swipe:SetVertexColor(0, 0, 0, 0.28)
    f.swipe:Hide()
    f.dispelBorder = f:CreateTexture(nil, "OVERLAY")
    f.dispelBorder:Hide()
    f.edge = {}
    if PreviewHelpers.LayoutEdgeLines then PreviewHelpers.LayoutEdgeLines(f, 1, AURA_PREVIEW_EDGE_OPTS) end
    f.stack = f:CreateFontString(nil, "OVERLAY")
    f.stack:SetFont(FONT, 9, "OUTLINE")
    f.stack:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    f.timer = f:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont(FONT, 8, "OUTLINE")
    f.timer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 1)
    return f
end
local function ApplyAuraPreviewFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow
    if type(_G.MSUF_GetGlobalFontSettings) == "function" then fontPath, fontFlags, r, g, b, _, useShadow = _G.MSUF_GetGlobalFontSettings() end
    if fs.SetFont then fs:SetFont(fontPath or FONT, max(7, tonumber(size) or 10), fontFlags or "OUTLINE") end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then fs:SetShadowOffset(useShadow and 1 or 0, useShadow and -1 or 0) end
end
local function PlaceAuraPreviewText(fs, icon, anchor, x, y)
    if not (fs and icon) then return end
    anchor = tostring(anchor or "CENTER"):upper()
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    fs:ClearAllPoints()
    fs:SetPoint(anchor, icon, anchor, x, y)
    if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
        fs:SetJustifyH("LEFT")
    elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyH("RIGHT")
    else
        fs:SetJustifyH("CENTER")
    end
    if fs.SetJustifyV then
        if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
            fs:SetJustifyV("TOP")
        elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
            fs:SetJustifyV("BOTTOM")
        else
            fs:SetJustifyV("MIDDLE")
        end
    end
end
local function RefreshMiniAuraPreviewNow(refreshPreview)
    if AurasMenuCombatLocked() then return end
    if type(refreshPreview) == "function" then refreshPreview() end
end
local function GroupAuraPreviewDefaultSize(scope, lane)
    if scope == "raid" or scope == "mythicraid" then return 16 end
    return lane == "buff" and 22 or 20
end
local function ReadMiniAuraPreviewConfig(scope, lane, width, height)
    local isGroup = IsGroupScope(scope)
    local cfg = {
        size = 24,
        spacing = 2,
        perRow = 7,
        maxIcons = 14,
        showStacks = true,
        showTimers = true,
        showSwipe = true,
        stackSize = 10,
        stackAnchor = "TOPRIGHT",
        stackX = -1,
        stackY = -1,
        cooldownSize = 9,
        cooldownAnchor = "CENTER",
        cooldownX = 0,
        cooldownY = 0,
        debuffBorderMode = "OFF",
    }
    if isGroup then
        local group = GFReadGroup(scope, lane or "debuff")
        cfg.size = tonumber(group.size) or GroupAuraPreviewDefaultSize(scope, lane)
        cfg.spacing = tonumber(group.spacing) or 1
        cfg.perRow = tonumber(group.perRow) or (lane == "buff" and 4 or 3)
        cfg.maxIcons = tonumber(group.max) or cfg.perRow * 2
        cfg.showStacks = group.showStacks ~= false
        cfg.showTimers = group.showCooldown ~= false
        cfg.showSwipe = group.showCooldownSwipe ~= false
        cfg.stackSize = tonumber(group.stackSize) or 10
        cfg.stackAnchor = group.stackAnchor or "BOTTOMRIGHT"
        cfg.stackX = tonumber(group.stackX) or 0
        cfg.stackY = tonumber(group.stackY) or 0
        cfg.cooldownSize = tonumber(group.cooldownSize) or 8
        cfg.cooldownAnchor = group.cooldownAnchor or "CENTER"
        cfg.cooldownX = tonumber(group.cooldownX) or 0
        cfg.cooldownY = tonumber(group.cooldownY) or 0
        if lane == "debuff" then cfg.debuffBorderMode = ReadGroupDebuffTypeBorderMode(scope, "debuff") end
    else
        local readScope = scope or "shared"
        local runtimePreview = (readScope ~= "shared" and type(Model.ReadPreviewConfig) == "function") and Model.ReadPreviewConfig(readScope) or nil
        if lane == "buff" then
            cfg.size = tonumber(runtimePreview and runtimePreview.buffSize) or Model.ReadNumber(readScope, LaneSizeKey(lane), 26, 10, 128)
            cfg.perRow = tonumber(runtimePreview and runtimePreview.buffPerRow) or Model.ReadLanePerRow(readScope, lane)
            cfg.maxIcons = tonumber(runtimePreview and runtimePreview.maxBuffs) or Model.ReadNumber(readScope, LaneMaxKey(lane), LaneDefaultMax(lane), 0, 80)
        elseif lane == "debuff" then
            cfg.size = tonumber(runtimePreview and runtimePreview.debuffSize) or Model.ReadNumber(readScope, LaneSizeKey(lane), 26, 10, 128)
            cfg.perRow = tonumber(runtimePreview and runtimePreview.debuffPerRow) or Model.ReadLanePerRow(readScope, lane)
            cfg.maxIcons = tonumber(runtimePreview and runtimePreview.maxDebuffs) or Model.ReadNumber(readScope, LaneMaxKey(lane), LaneDefaultMax(lane), 0, 80)
        else
            cfg.size = Model.ReadNumber(readScope, "iconSize", 26, 10, 128)
            cfg.perRow = tonumber(runtimePreview and runtimePreview.perRow) or Model.ReadNumber(readScope, "perRow", 12, 1, 40)
            cfg.maxIcons = cfg.perRow * 2
        end
        cfg.spacing = tonumber(runtimePreview and runtimePreview.spacing) or Model.ReadNumber(readScope, "spacing", 2, 0, 12)
        if type(Model.ReadLaneStyleBool) == "function" and lane then
            cfg.showStacks = Model.ReadLaneStyleBool(readScope, lane, "showStackCount", true)
            cfg.showTimers = Model.ReadLaneStyleBool(readScope, lane, "showCooldownText", true)
            cfg.showSwipe = Model.ReadLaneStyleBool(readScope, lane, "showCooldownSwipe", true)
        else
            cfg.showStacks = Model.ReadBool(readScope, "showStackCount", true)
            cfg.showTimers = Model.ReadBool(readScope, "showCooldownText", true)
            cfg.showSwipe = Model.ReadBool(readScope, "showCooldownSwipe", true)
        end
        cfg.stackSize = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextSize", 14, 6, 40) or Model.ReadNumber(readScope, "stackTextSize", 14, 6, 40)
        cfg.stackAnchor = lane and type(Model.ReadLaneStackAnchor) == "function" and Model.ReadLaneStackAnchor(readScope, lane) or Model.ReadStackAnchor(readScope)
        cfg.stackX = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextOffsetX", -1, -2000, 2000) or Model.ReadNumber(readScope, "stackTextOffsetX", -1, -2000, 2000)
        cfg.stackY = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextOffsetY", 1, -2000, 2000) or Model.ReadNumber(readScope, "stackTextOffsetY", 1, -2000, 2000)
        cfg.cooldownSize = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextSize", 14, 6, 40) or Model.ReadNumber(readScope, "cooldownTextSize", 14, 6, 40)
        cfg.cooldownAnchor = "CENTER"
        cfg.cooldownX = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextOffsetX", 0, -2000, 2000) or Model.ReadNumber(readScope, "cooldownTextOffsetX", 0, -2000, 2000)
        cfg.cooldownY = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextOffsetY", 0, -2000, 2000) or Model.ReadNumber(readScope, "cooldownTextOffsetY", 0, -2000, 2000)
        if lane == "debuff" then
            if type(Model.ReadDebuffTypeBorderMode) == "function" then
                cfg.debuffBorderMode = Model.ReadDebuffTypeBorderMode(readScope)
            elseif type(Model.ReadLaneStyleBool) == "function" then
                cfg.debuffBorderMode = Model.ReadLaneStyleBool(readScope, "debuff", "useDebuffTypeBorders", false) and "SYMBOL" or "OFF"
            end
        end
    end
    local maxSize = max(12, min(128, floor((height or 104) - 38), floor((width or 300) - 20)))
    cfg.size = min(maxSize, max(10, tonumber(cfg.size) or 24))
    cfg.spacing = min(10, max(0, tonumber(cfg.spacing) or 2))
    cfg.perRow = max(1, Round(cfg.perRow))
    cfg.maxIcons = max(0, Round(cfg.maxIcons))
    local maxCols = max(1, floor(((width or 300) - 20 + cfg.spacing) / max(1, cfg.size + cfg.spacing)))
    cfg.columns = min(cfg.perRow, maxCols)
    cfg.maxRows = max(1, floor(((height or 104) - 38 + cfg.spacing) / max(1, cfg.size + cfg.spacing)))
    cfg.count = min(14, cfg.maxIcons, cfg.columns * cfg.maxRows)
    cfg.stackSize = max(7, tonumber(cfg.stackSize) or 10)
    cfg.cooldownSize = max(7, tonumber(cfg.cooldownSize) or 9)
    return cfg
end
local function BuildMiniAuraPreview(ctx, parent, scope, x, y, width, height, lane)
    if ctx and ctx.hiddenBuild then return nil end
    lane = lane == "buff" and "buff" or (lane == "debuff" and "debuff" or nil)
    local box = T.Panel(parent, nil, { 0.010, 0.016, 0.034, 0.88 }, T.colors.borderSoft)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width or 300, height or 104)
    W.LabelAt(box, "Preview", 10, -10, 100, "GameFontNormalSmall", T.colors.text)
    local icons = {}
    for i = 1, 14 do icons[i] = CreateAuraPreviewIcon(box) end
    local buffTex = { 135987, 136116, 135932, 136085, 132333, 135981, 136048 }
    local debuffTex = { 136118, 136139, 136197, 135817, 132851, 136188, 136170 }
    local function RefreshPreview()
        if AurasMenuCombatLocked() then return end
        local cfg = ReadMiniAuraPreviewConfig(scope, lane, width, height)
        for i = 1, #icons do
            local icon = icons[i]
            if i <= cfg.count then
                local col = (i - 1) % cfg.columns
                local row = floor((i - 1) / cfg.columns)
                icon:SetSize(cfg.size, cfg.size)
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", box, "TOPLEFT", 10 + col * (cfg.size + cfg.spacing), -34 - row * (cfg.size + cfg.spacing))
                local isBuffIcon = lane and lane == "buff" or (not lane and i <= 7)
                local tex = isBuffIcon and buffTex or debuffTex
                icon.icon:SetTexture(tex[((i - 1) % #tex) + 1])
                local r, g, b = isBuffIcon and 0.20 or 0.78, isBuffIcon and 0.72 or 0.20, isBuffIcon and 0.42 or 0.24
                local borderAtlas = (not isBuffIcon) and DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[cfg.debuffBorderMode] or nil
                local showPreviewEdges = isBuffIcon == true
                for _, edge in pairs(icon.edge) do edge:SetShown(showPreviewEdges); edge:SetVertexColor(r, g, b, 0.95) end
                icon.swipe:SetShown(cfg.showSwipe ~= false)
                if borderAtlas and icon.dispelBorder.SetAtlas then
                    local pad = max(1, floor((cfg.size / 24) + 0.5))
                    icon.dispelBorder:ClearAllPoints()
                    icon.dispelBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
                    icon.dispelBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
                    icon.dispelBorder:SetAtlas(borderAtlas, TextureKitConstants and TextureKitConstants.IgnoreAtlasSize)
                    icon.dispelBorder:Show()
                else
                    icon.dispelBorder:Hide()
                end
                ApplyAuraPreviewFont(icon.stack, cfg.stackSize)
                ApplyAuraPreviewFont(icon.timer, cfg.cooldownSize)
                PlaceAuraPreviewText(icon.stack, icon, cfg.stackAnchor, cfg.stackX, cfg.stackY)
                PlaceAuraPreviewText(icon.timer, icon, cfg.cooldownAnchor, cfg.cooldownX, cfg.cooldownY)
                icon.stack:SetText(cfg.showStacks and (i % 3 == 1 and "2" or "") or "")
                icon.timer:SetText(cfg.showTimers and (i % 2 == 0 and "12" or "") or "")
                icon:Show()
            else
                icon:Hide()
                icon.swipe:Hide()
                icon.dispelBorder:Hide()
            end
        end
    end
    M.TrackRefresh(ctx, RefreshPreview)
    return box, RefreshPreview
end
local function BuildUnitStyle(ctx, b, scope)
    local unit = scope == "shared" and "shared" or scope
    local lane = CurrentLane("auraStyleGFLane", "debuff")
    local laneName = LanePlural(lane)
    local extraDebuffControls = lane == "debuff" and 64 or 0
    local section = b:Section("Unit Aura " .. LaneTitle(lane) .. " Style", 590 + extraDebuffControls + (unit == "shared" and 0 or 42))
    local w = section._msuf2Width or b.width or 720
    local colW = max(300, floor((w - 66) / 2))
    local rightX = 32 + colW + 18
    local rightW = max(260, w - rightX - 24)
    local styleControls = {}
    local refreshMiniPreview
    local function RefreshStylePreview()
        RefreshMiniAuraPreviewNow(refreshMiniPreview)
    end
    local topY = -42
    local useShared
    if unit ~= "shared" then
        useShared = BindSwitch(ctx, section, "Use Shared Style", 24, -40, 220,
            function() return Model.UseSharedVisuals(unit) end,
            function(v)
                Model.SetUseSharedVisuals(unit, v)
                ApplyUnit(ctx, unit, "AURAS3_STYLE_INHERIT", true)
                RefreshStylePreview()
            end)
        topY = -84
    end
    local function ReadScopeBool(key, defaultValue)
        if type(Model.ReadLaneStyleBool) == "function" then return Model.ReadLaneStyleBool(unit, lane, key, defaultValue) end
        if type(Model.ReadBool) == "function" then return Model.ReadBool(unit, key, defaultValue) end
        return Model.ReadSharedBool(key, defaultValue)
    end
    local function WriteScopeBool(key, value)
        if type(Model.WriteLaneStyleBool) == "function" then
            Model.WriteLaneStyleBool(unit, lane, key, value)
        elseif type(Model.WriteBool) == "function" then
            Model.WriteBool(unit, key, value)
        else
            Model.WriteSharedBool(key, value)
        end
    end
    local function ReadScopeDebuffBorderMode()
        if type(Model.ReadDebuffTypeBorderMode) == "function" then return Model.ReadDebuffTypeBorderMode(unit) end
        return ReadScopeBool("useDebuffTypeBorders", false) and "SYMBOL" or "OFF"
    end
    local function WriteScopeDebuffBorderMode(value)
        value = NormalizeDebuffTypeBorderMode(value, "OFF")
        if type(Model.WriteDebuffTypeBorderMode) == "function" then
            Model.WriteDebuffTypeBorderMode(unit, value)
        else
            WriteScopeBool("useDebuffTypeBorders", value ~= "OFF")
        end
    end
    local function ReadScopeNumber(key, defaultValue, minValue, maxValue)
        if type(Model.ReadLaneStyleNumber) == "function" then return Model.ReadLaneStyleNumber(unit, lane, key, defaultValue, minValue, maxValue) end
        return Model.ReadNumber(unit, key, defaultValue, minValue, maxValue)
    end
    local function WriteScopeNumber(key, value, minValue, maxValue)
        if type(Model.WriteLaneStyleNumber) == "function" then
            Model.WriteLaneStyleNumber(unit, lane, key, value, minValue, maxValue)
        else
            Model.WriteNumber(unit, key, value, minValue, maxValue)
        end
    end
    local function AddStyleControl(control) M.AppendValues(styleControls, control); return control end
    local function BindStyleSwitch(parent, label, x, y, width, key, defaultValue, reason)
        return AddStyleControl(BindSwitch(ctx, parent, label, x, y, width,
            function() return ReadScopeBool(key, defaultValue) end,
            function(v)
                WriteScopeBool(key, v)
                ApplyUnit(ctx, unit, reason)
                RefreshStylePreview()
            end))
    end
    local function BindStyleDropdown(parent, label, x, y, values, width, getValue, setValue, reason)
        return AddStyleControl(BindDropdown(ctx, parent, label, x, y, values, width,
            getValue,
            function(v)
                setValue(v)
                ApplyUnit(ctx, unit, reason)
                RefreshStylePreview()
            end))
    end
    local function BindStyleSlider(parent, label, x, y, minVal, maxVal, step, width, key, defaultValue, readMin, readMax, writeMin, writeMax, reason)
        readMin, readMax = readMin or minVal, readMax or maxVal
        writeMin, writeMax = writeMin or readMin, writeMax or readMax
        return AddStyleControl(BindSlider(ctx, parent, label, x, y, minVal, maxVal, step, width,
            function() return ReadScopeNumber(key, defaultValue, readMin, readMax) end,
            function(v)
                WriteScopeNumber(key, v, writeMin, writeMax)
                ApplyUnit(ctx, unit, reason)
                RefreshStylePreview()
            end))
    end
    local text = Card(section, laneName .. " Text Features", "Stack-count and cooldown text for " .. ScopeLabel(scope) .. " " .. laneName .. ".", 24, topY, colW, 388 + extraDebuffControls)
    BindStyleSwitch(text, "Show Stack Count", 16, -66, colW - 32, "showStackCount", true, "AURAS3_SHOW_STACKS")
    BindStyleSwitch(text, "Show Cooldown Text", 16, -98, colW - 32, "showCooldownText", true, "AURAS3_SHOW_COOLDOWN_TEXT")
    BindStyleSwitch(text, "Show Cooldown Swipe", 16, -130, colW - 32, "showCooldownSwipe", true, "AURAS3_SHOW_COOLDOWN_SWIPE")
    if lane == "debuff" then
        BindStyleDropdown(text, "Dispel-type Border", 16, -162,
            type(Model.DebuffTypeBorderModeValues) == "function" and Model.DebuffTypeBorderModeValues() or DEBUFF_TYPE_BORDER_MODE_VALUES,
            colW - 32, ReadScopeDebuffBorderMode, WriteScopeDebuffBorderMode, "AURAS3_DEBUFF_TYPE_BORDER_MODE")
    end
    W.LabelAt(text, "Stack Count", 16, -178 - extraDebuffControls, colW - 32, "GameFontNormalSmall", T.colors.accent)
    AddStyleControl(BindDropdown(ctx, text, "Anchor", 16, -214 - extraDebuffControls, Model.StackAnchorValues(), colW - 32,
        function()
            if type(Model.ReadLaneStackAnchor) == "function" then return Model.ReadLaneStackAnchor(unit, lane) end
            return Model.ReadStackAnchor(unit)
        end,
        function(v)
            if type(Model.WriteLaneStackAnchor) == "function" then
                Model.WriteLaneStackAnchor(unit, lane, v)
            else
                Model.WriteStackAnchor(unit, v)
            end
            ApplyUnit(ctx, unit, "AURAS3_STACK_ANCHOR")
            RefreshStylePreview()
        end))
    BindStyleSlider(text, "Text Size", 16, -272 - extraDebuffControls, 6, 40, 1, colW - 32, "stackTextSize", 14, 6, 40, nil, nil, "AURAS3_STACK_SIZE")
    local smallW = max(120, floor((colW - 44) / 2))
    BindStyleSlider(text, "X", 16, -332 - extraDebuffControls, -40, 40, 1, smallW, "stackTextOffsetX", -1, -2000, 2000, nil, nil, "AURAS3_STACK_X")
    BindStyleSlider(text, "Y", 24 + smallW, -332 - extraDebuffControls, -40, 40, 1, smallW, "stackTextOffsetY", 1, -2000, 2000, nil, nil, "AURAS3_STACK_Y")
    local cooldown = Card(section, laneName .. " Cooldown Text", "Timer font size, center offset, and tooltip behavior for " .. ScopeLabel(scope) .. " " .. laneName .. ".", rightX, topY, rightW, 316)
    BindStyleSlider(cooldown, "Text Size", 16, -62, 6, 40, 1, rightW - 32, "cooldownTextSize", 14, 6, 40, nil, nil, "AURAS3_COOLDOWN_SIZE")
    BindStyleSlider(cooldown, "X", 16, -122, -40, 40, 1, rightW - 32, "cooldownTextOffsetX", 0, -2000, 2000, nil, nil, "AURAS3_COOLDOWN_X")
    BindStyleSlider(cooldown, "Y", 16, -182, -40, 40, 1, rightW - 32, "cooldownTextOffsetY", 0, -2000, 2000, nil, nil, "AURAS3_COOLDOWN_Y")
    BindStyleSwitch(cooldown, "Show Tooltip", 16, -242, rightW - 32, "showTooltip", true, "AURAS3_TOOLTIP")
    refreshMiniPreview = select(2, BuildMiniAuraPreview(ctx, section, unit, rightX, topY - 340, rightW, 118, lane))
    local hint = W.Text(section, "", 24, topY - 472, w - 48, T.colors.muted)
    M.TrackRefresh(ctx, function()
        local editable = unit == "shared" or not Model.UseSharedVisuals(unit)
        W.SetControlsEnabled(styleControls, editable)
        if useShared then W.SetControlEnabled(useShared, true) end
        hint:SetText(editable and "Font family follows Global Style > Fonts. Legacy blacklists are read-only on Filters." or "This scope inherits the Shared aura style.")
    end)
end
local function BuildGroupStyle(ctx, b, scope)
    local lane = CurrentLane("auraStyleGFLane", "debuff")
    local extraDebuffControls = lane == "debuff" and 64 or 0
    local section = b:Section("Group Aura Style", 668 + extraDebuffControls)
    local w = section._msuf2Width or b.width or 720
    local laneName = LanePlural(lane)
    local colW = max(300, floor((w - 66) / 2))
    local rightX = 32 + colW + 18
    local rightW = max(260, w - rightX - 24)
    local refreshMiniPreview
    local function RefreshStylePreview()
        RefreshMiniAuraPreviewNow(refreshMiniPreview)
    end
    local text = Card(section, "Group Aura " .. LaneTitle(lane) .. " Text", "Cooldown and stack text for " .. ScopeLabel(scope) .. " " .. laneName .. ".", 24, -42, colW, 548 + extraDebuffControls)
    BindGroupSwitch(ctx, text, "Show Cooldown Swipe", 16, -78, colW - 32, scope, lane, "showCooldownSwipe", true, "visual", RefreshStylePreview)
    BindGroupSwitch(ctx, text, "Show Cooldown Text", 16, -110, colW - 32, scope, lane, "showCooldown", true, "visual", RefreshStylePreview)
    BindGroupSwitch(ctx, text, "Show Stack Count", 16, -142, colW - 32, scope, lane, "showStacks", true, "visual", RefreshStylePreview)
    if lane == "debuff" then
        BindDropdown(ctx, text, "Dispel-type Border", 16, -174,
            type(Model.DebuffTypeBorderModeValues) == "function" and Model.DebuffTypeBorderModeValues() or DEBUFF_TYPE_BORDER_MODE_VALUES,
            colW - 32,
            function() return ReadGroupDebuffTypeBorderMode(scope, lane) end,
            function(v)
                WriteGroupDebuffTypeBorderMode(scope, lane, v)
                RefreshStylePreview()
            end)
    end
    BindGroupSlider(ctx, text, "Cooldown Font", 16, -198 - extraDebuffControls, 6, 24, 1, colW - 32, scope, lane, "cooldownSize", 8, "font", RefreshStylePreview)
    BindGroupDropdown(ctx, text, "Cooldown Anchor", 16, -256 - extraDebuffControls, GFAnchorValues(), colW - 32, scope, lane, "cooldownAnchor", "CENTER", "geometry", RefreshStylePreview)
    local textSmallW = max(120, floor((colW - 44) / 2))
    BindGroupSlider(ctx, text, "Cooldown X", 16, -314 - extraDebuffControls, -40, 40, 1, textSmallW, scope, lane, "cooldownX", 0, "geometry", RefreshStylePreview)
    BindGroupSlider(ctx, text, "Cooldown Y", 24 + textSmallW, -314 - extraDebuffControls, -40, 40, 1, textSmallW, scope, lane, "cooldownY", 0, "geometry", RefreshStylePreview)
    BindGroupSlider(ctx, text, "Stack Font", 16, -374 - extraDebuffControls, 6, 24, 1, colW - 32, scope, lane, "stackSize", 10, "font", RefreshStylePreview)
    BindGroupDropdown(ctx, text, "Stack Anchor", 16, -432 - extraDebuffControls, GFAnchorValues(), colW - 32, scope, lane, "stackAnchor", "BOTTOMRIGHT", "geometry", RefreshStylePreview)
    BindGroupSlider(ctx, text, "Stack X", 16, -490 - extraDebuffControls, -40, 40, 1, textSmallW, scope, lane, "stackX", 0, "geometry", RefreshStylePreview)
    BindGroupSlider(ctx, text, "Stack Y", 24 + textSmallW, -490 - extraDebuffControls, -40, 40, 1, textSmallW, scope, lane, "stackY", 0, "geometry", RefreshStylePreview)
    local behavior = Card(section, "Behavior", "Shared group-frame aura behavior for " .. ScopeLabel(scope) .. ".", rightX, -42, rightW, 306)
    BindGroupRootSwitch(ctx, behavior, "Show Tooltip", 16, -64, rightW - 32, scope, "showTooltip", true, "visual")
    BindGroupRootSwitch(ctx, behavior, "Sort by Duration", 16, -96, rightW - 32, scope, "sortByDuration", false, "visual")
    BindGroupRootSwitch(ctx, behavior, "Prefer Player Auras", 16, -128, rightW - 32, scope, "preferPlayer", false, "visual")
    BindGroupRootSwitch(ctx, behavior, "Dynamic Icon Scale", 16, -160, rightW - 32, scope, "dynamicScale", false, "geometry", RefreshStylePreview)
    BindGroupConfSwitch(ctx, behavior, "Cooldown darkens on loss", 16, -202, rightW - 32, scope, "cooldownSwipeDarkenOnLoss", false, "visual", RefreshStylePreview)
    refreshMiniPreview = select(2, BuildMiniAuraPreview(ctx, section, scope, rightX, -404, rightW, 118, lane))
end
local function BuildSharedColors(ctx, b)
    local section = b:Section("Shared Aura Colors", 480)
    local w = section._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 58) / 2))
    local rightX = 24 + colW + 18
    local cooldown = Card(section, "Cooldown Timer Colors", nil, 24, -42, colW, 380)
    local markers = Card(section, "Stack & Highlights", nil, rightX, -42, colW, 380)
    local preview = T.Panel(cooldown, nil, { 0.014, 0.020, 0.040, 0.82 }, T.colors.borderSoft)
    preview:SetPoint("TOPLEFT", cooldown, "TOPLEFT", 16, -60)
    preview:SetSize(colW - 32, 88)
    W.LabelAt(preview, "Preview", 12, -12, 120, "GameFontNormalSmall", T.colors.muted)
    local samples = {}
    for i = 1, 3 do
        local box = T.Panel(preview, nil, { 0.020, 0.024, 0.046, 0.92 }, T.colors.borderSoft)
        box:SetPoint("LEFT", preview, "LEFT", 88 + (i - 1) * 78, -6)
        box:SetSize(64, 54)
        local fs = T.Font(box, nil, i == 1 and "60" or (i == 2 and "15" or "5"), T.colors.text)
        fs:SetFont(FONT, 18, "OUTLINE")
        fs:SetPoint("CENTER", box, "CENTER", 0, 6)
        local label = T.Font(box, "GameFontDisableSmall", i == 1 and "Safe" or (i == 2 and "Warn" or "Urgent"), T.colors.muted)
        label:SetPoint("BOTTOM", box, "BOTTOM", 0, 5)
        samples[i] = fs
    end
    local function RefreshColorSamples()
        local sr, sg, sb = Model.ReadGeneralColor("aurasCooldownTextSafeColor", 1, 1, 1)
        local wr, wg, wb = Model.ReadGeneralColor("aurasCooldownTextWarningColor", 1, 0.85, 0.20)
        local ur, ug, ub = Model.ReadGeneralColor("aurasCooldownTextUrgentColor", 1, 0.55, 0.10)
        local buckets = Model.ReadGeneralBool("aurasCooldownTextUseBuckets", false)
        samples[1]:SetTextColor(sr, sg, sb, 1)
        samples[2]:SetTextColor(buckets and wr or sr, buckets and wg or sg, buckets and wb or sb, 1)
        samples[3]:SetTextColor(buckets and ur or sr, buckets and ug or sg, buckets and ub or sb, 1)
    end
    BindSwitch(ctx, cooldown, "Color by time", 16, -166, colW - 32,
        function() return Model.ReadGeneralBool("aurasCooldownTextUseBuckets", false) end,
        function(v)
            Model.WriteGeneralBool("aurasCooldownTextUseBuckets", v)
            RefreshColorSamples()
            RequestAuraTextRefresh()
        end)
    local function BindGeneralColor(parent, label, y, key, r, g, bcol, after)
        BindColor(ctx, parent, label, 16, y,
            function() return Model.ReadGeneralColor(key, r, g, bcol) end,
            function(nr, ng, nb)
                Model.WriteGeneralColor(key, nr, ng, nb)
                if after then after() end
            end)
    end
    local function RefreshTextColors()
        RefreshColorSamples()
        RequestAuraTextRefresh()
    end
    BindGeneralColor(cooldown, "Safe", -210, "aurasCooldownTextSafeColor", 1, 1, 1, RefreshTextColors)
    BindGeneralColor(cooldown, "Warning", -248, "aurasCooldownTextWarningColor", 1, 0.85, 0.20, RefreshTextColors)
    BindGeneralColor(cooldown, "Urgent", -286, "aurasCooldownTextUrgentColor", 1, 0.55, 0.10, RefreshTextColors)
    BindGeneralColor(markers, "Stack Count", -62, "aurasStackCountColor", 1, 1, 1, RequestAuraTextRefresh)
    BindGeneralColor(markers, "Own Buff", -102, "aurasOwnBuffHighlightColor", 1, 0.85, 0.20)
    BindGeneralColor(markers, "Own Debuff", -142, "aurasOwnDebuffHighlightColor", 1, 0.30, 0.30)
    BindSlider(ctx, markers, "Safe seconds", 16, -196, 0, 600, 1, colW - 32,
        function() return Model.ReadGeneralNumber("aurasCooldownTextSafeSeconds", 60, 0, 600) end,
        function(v) Model.WriteGeneralNumber("aurasCooldownTextSafeSeconds", v, 0, 600); RequestAuraTextRefresh() end)
    BindSlider(ctx, markers, "Warning <= sec", 16, -256, 0, 60, 1, colW - 32,
        function() return Model.ReadGeneralNumber("aurasCooldownTextWarningSeconds", 15, 0, 60) end,
        function(v) Model.WriteGeneralNumber("aurasCooldownTextWarningSeconds", v, 0, 60); RequestAuraTextRefresh() end)
    BindSlider(ctx, markers, "Urgent <= sec", 16, -316, 0, 30, 1, colW - 32,
        function() return Model.ReadGeneralNumber("aurasCooldownTextUrgentSeconds", 5, 0, 30) end,
        function(v) Model.WriteGeneralNumber("aurasCooldownTextUrgentSeconds", v, 0, 30); RequestAuraTextRefresh() end)
    W.Text(section, "Timer and marker colors are shared by unit and group aura previews.", 24, -440, w - 48, T.colors.muted)
    M.TrackRefresh(ctx, RefreshColorSamples)
end
local function BuildAuraStylePage(ctx)
    local b = W.PageBuilder(ctx)
    local scope = BuildAuraChrome(ctx, b, "Aura Style", "Text, cooldown, stack and marker styling.")
    BuildAuraStyleNav(ctx, b)
    if IsGroupScope(scope) then
        BuildGroupStyle(ctx, b, scope)
    else
        BuildUnitStyle(ctx, b, scope)
    end
    BuildSharedColors(ctx, b)
    FinishPage(ctx, b)
end
local function BuildAuraStyleLanePage(ctx, lane)
    SetCurrentLane("auraStyleGFLane", lane)
    BuildAuraStylePage(ctx)
end
local function BuildUnitFilterRulesByLane(ctx, b, scope)
    local section = b:Section("Filter Rules", 512)
    local w = section._msuf2Width or b.width or 720
    local lane = CurrentLane("auraFilterLane", "buff")
    local laneTitle = lane == "buff" and "Buff Filters" or "Debuff Filters"
    local filterControls = {}
    local useShared
    if scope ~= "shared" then
        useShared = BindSwitch(ctx, section, "Use Shared Rules", 24, -48, 190,
            function() return Model.UseSharedRules(scope) end,
            function(v)
                Model.SetUseSharedRules(scope, v)
                ApplyUnit(ctx, scope, "AURAS3_FILTER_INHERIT", true)
            end)
    end
    local enableX = scope == "shared" and 24 or 234
    local enableFilters = BindSwitch(ctx, section, "Enable Filters", enableX, -48, 180,
        function() return Model.ScopeFiltersEnabled(scope) end,
        function(v)
            Model.SetScopeFiltersEnabled(scope, v)
            ApplyUnit(ctx, scope, "AURAS3_FILTER_ENABLE", true)
        end)
    W.LabelAt(section, "Filter Type", 24, -108, 90, "GameFontNormalSmall", T.colors.accent)
    BuildLaneTabs(ctx, section, "auraFilterLane", 118, -104, min(280, w - 160))
    local card = Card(section, laneTitle, "Rules for " .. ScopeLabel(scope) .. ".", 24, -152, w - 48, 336)
    local colW = max(280, floor(((w - 48) - 46) / 2))
    local rightX = 24 + colW
    local function FilterToggle(label, key, x, y, tip)
        local widget = BindSwitch(ctx, card, label, x, y, colW - 32,
            function() return Model.ReadFilter(scope, lane, key, false) == true end,
            function(v)
                Model.WriteFilter(scope, lane, key, v)
                ApplyUnit(ctx, scope, "AURAS3_FILTER_" .. lane .. "_" .. key, true)
            end)
        AddTooltip(widget, label, tip or "")
        filterControls[#filterControls + 1] = widget
        return widget
    end
    W.LabelAt(card, "Inclusive Filters", 16, -70, colW, "GameFontNormalSmall", T.colors.accent)
    local filterSpecs = lane == "buff" and {
        { "Player", "onlyMine", 1, 1, "Auras applied by the player." },
        { "Raid", "raid", 1, 2, "Raid-useful public Buffs." },
        { "Raid In Combat", "raidInCombat", 1, 3, "Buffs Blizzard flags for raid frames while in combat." },
        { "External Defensive", "externalDefensive", 1, 4, "External defensive Buffs from Blizzard's native filter." },
        { "Big Defensive", "bigDefensive", 2, 1, "Major defensive Buffs from Blizzard's native filter." },
        { "Cancelable", "cancelable", 2, 2, "Buffs that can be cancelled." },
        { "Not Cancelable", "notCancelable", 2, 3, "Buffs that cannot be cancelled." },
    } or {
        { "Player", "onlyMine", 1, 1, "Debuffs applied by the player." },
        { "Raid", "raid", 1, 2, "Raid and encounter Debuffs." },
        { "Raid In Combat", "raidInCombat", 1, 3, "Debuffs Blizzard flags for raid frames while in combat." },
        { "Dispellable", "includeDispellable", 2, 1, "Debuffs Blizzard marks as dispellable by the player." },
        { "Crowd Control", "crowdControl", 2, 2, "Crowd-control Debuffs from Blizzard's native filter." },
    }
    M.BuildControlSpecs(filterSpecs, {
        ["*"] = function(s) return FilterToggle(s[1], s[2], s[3] == 2 and rightX or 16, -100 - ((s[4] - 1) * 34), s[5]) end,
    })
    local exclusiveValues = lane == "buff" and BUFF_EXCLUSIVE or DEBUFF_EXCLUSIVE
    local exclusiveEvent = lane == "buff" and "AURAS3_FILTER_BUFF_EXCLUSIVE" or "AURAS3_FILTER_DEBUFF_EXCLUSIVE"
    filterControls[#filterControls + 1] = BindDropdown(ctx, card, "Exclusive Filter", rightX, -250, exclusiveValues, min(250, colW - 32),
        function() return Model.ReadFilter(scope, lane, "exclusive", "none") end,
        function(v)
            Model.WriteFilter(scope, lane, "exclusive", v or "none")
            ApplyUnit(ctx, scope, exclusiveEvent, true)
        end)
    W.Text(section, "Native 12.1 AuraContainers currently support Blizzard filter tokens only. Exact SpellID whitelist/blacklist data is shown below as read-only legacy data.", 24, -506, w - 48, T.colors.muted)
    M.TrackRefresh(ctx, function()
        local customRules = scope == "shared" or not Model.UseSharedRules(scope)
        local filtersOn = customRules and Model.ScopeFiltersEnabled(scope)
        W.SetControlEnabled(enableFilters, customRules)
        W.SetControlsEnabled(filterControls, filtersOn)
        if useShared then W.SetControlEnabled(useShared, scope ~= "shared") end
    end)
end
local function BuildUnitBlacklist(ctx, b, scope)
    local section = b:Section("Blacklist", 572)
    local w = section._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 68) / 2))
    local rightX = 36 + colW + 24
    local editEnabled = NATIVE_EXACT_AURA_FILTERS_ENABLED and (scope == "shared" or not Model.UseSharedBlacklist(scope))
    local useShared
    if scope ~= "shared" then
        useShared = BindSwitch(ctx, section, "Use Shared Blacklist", 24, -42, 210,
            function() return Model.UseSharedBlacklist(scope) end,
            function(v)
                Model.SetUseSharedBlacklist(scope, v)
                ApplyUnit(ctx, scope, "AURAS3_BLACKLIST_INHERIT", true)
            end)
    end
    local manual = Card(section, "Blacklist", "Read-only legacy SpellID list for Buff and Debuff filtering.", 24, -72, colW, 222)
    local preset = Card(section, "Blacklist Presets", "Read-only legacy aura ID groups.", rightX, -72, colW, 222)
    local inputValue = ""
    local input = BindTextInput(ctx, manual, "Spell ID, spell link, or resolvable spell name", 16, -82, colW - 32,
        function() return inputValue end,
        function(v) inputValue = v or "" end)
    local add = ActionButton(manual, "Add", 104)
    add:SetPoint("TOPLEFT", manual, "TOPLEFT", 16, -134)
    add:SetScript("OnClick", function()
        local value = input and input.GetText and input:GetText() or inputValue
        Model.AddBlacklistSpell(scope, value)
        if input and input.SetText then input:SetText("") end
        inputValue = ""
        ApplyUnit(ctx, scope, "AURAS3_BLACKLIST_ADD", true)
    end)
    local remove = ActionButton(manual, "Remove", 112)
    remove:SetPoint("TOPLEFT", manual, "TOPLEFT", 134, -134)
    remove:SetScript("OnClick", function()
        local value = input and input.GetText and input:GetText() or inputValue
        Model.RemoveBlacklistSpell(scope, value)
        ApplyUnit(ctx, scope, "AURAS3_BLACKLIST_REMOVE", true)
    end)
    W.Text(manual, NATIVE_EXACT_AURA_FILTERS_DISABLED_TEXT, 16, -176, colW - 32, T.colors.muted)
    local function CurrentPreset()
        local key = M.auraBlacklistPreset or "RAID_BUFFS"
        local values = Model.BlacklistPresetValues()
        for i = 1, #values do
            if values[i].value == key then return key end
        end
        return values[1] and values[1].value or "RAID_BUFFS"
    end
    local presetDrop = W.Dropdown(preset, "Preset", function() return Model.BlacklistPresetValues() end, colW - 32)
    W.MoveWidget(presetDrop, preset, 16, -82, colW - 32)
    M.BindDropdownWidget(ctx, presetDrop,
        function() return CurrentPreset() end,
        function(v)
            M.auraBlacklistPreset = v or "RAID_BUFFS"
            M.auraBlacklistSpell = nil
            QueueAurasPageRefresh(ctx, "auras-blacklist-preset")
        end)
    local spellDrop = W.Dropdown(preset, "Spell", function() return Model.BlacklistSpellValues(CurrentPreset()) end, colW - 32)
    W.MoveWidget(spellDrop, preset, 16, -136, colW - 32)
    M.BindDropdownWidget(ctx, spellDrop,
        function()
            local values = Model.BlacklistSpellValues(CurrentPreset())
            local selected = M.auraBlacklistSpell
            for i = 1, #values do
                if values[i].value == selected then return selected end
            end
            return values[1] and values[1].value or nil
        end,
        function(v) M.auraBlacklistSpell = v end)
    local addPreset = ActionButton(preset, "Add Spell", 112)
    addPreset:SetPoint("TOPLEFT", preset, "TOPLEFT", 16, -184)
    addPreset:SetScript("OnClick", function()
        local values = Model.BlacklistSpellValues(CurrentPreset())
        local spellID = M.auraBlacklistSpell or (values[1] and values[1].value)
        Model.AddBlacklistPresetSpell(scope, spellID)
        ApplyUnit(ctx, scope, "AURAS3_BLACKLIST_PRESET_ADD", true)
    end)
    local addPresetGroup = ActionButton(preset, "Add Group", 112)
    addPresetGroup:SetPoint("TOPLEFT", preset, "TOPLEFT", 138, -184)
    addPresetGroup:SetScript("OnClick", function()
        Model.AddBlacklistPresetGroup(scope, CurrentPreset())
        ApplyUnit(ctx, scope, "AURAS3_BLACKLIST_PRESET_GROUP_ADD", true)
    end)
    local blacklistEditControls = { input, add, remove, presetDrop, spellDrop, addPreset, addPresetGroup }
    local current = Card(section, "Current List", nil, 24, -318, w - 48, 184)
    local prepared = W.Text(current, "", 16, -18, w - 80, T.colors.accent)
    local emptyText = W.Text(current, "No blacklisted spells.", 16, -48, w - 80, T.colors.muted)
    local moreText = W.Text(current, "Read-only while the 12.1 native backend is active.", 16, -164, w - 80, T.colors.muted)
    local listScroll = CreateFrame("ScrollFrame", nil, current, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", current, "TOPLEFT", 16, -42)
    listScroll:SetSize(w - 82, 116)
    if listScroll.EnableMouseWheel then listScroll:EnableMouseWheel(true) end
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(w - 104, 116)
    listScroll:SetScrollChild(listChild)
    listScroll:SetScript("OnMouseWheel", function(self, delta)
        local step = 42
        local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
        local value = (self.GetVerticalScroll and self:GetVerticalScroll() or 0) - ((tonumber(delta) or 0) * step)
        if value < 0 then value = 0 end
        if value > range then value = range end
        if self.SetVerticalScroll then self:SetVerticalScroll(value) end
    end)
    local rows = {}
    local rowW = w - 112
    local rowH = 22
    local function EnsureRow(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Button", nil, listChild)
        row:SetSize(rowW, rowH)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0.020, 0.026, 0.052, 0.78)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.icon:SetSize(18, 18)
        row.text = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.050, 0.065, 0.120, 0.92) end)
        row:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.020, 0.026, 0.052, 0.78) end)
        row:SetScript("OnClick", function(self)
            if not editEnabled then return end
            Model.RemoveBlacklistSpell(scope, self._msufValue)
            ApplyUnit(ctx, scope, "AURAS3_BLACKLIST_REMOVE_ROW", true)
        end)
        row:Hide()
        rows[i] = row
        return row
    end
    M.TrackRefresh(ctx, function()
        editEnabled = NATIVE_EXACT_AURA_FILTERS_ENABLED and (scope == "shared" or not Model.UseSharedBlacklist(scope))
        if useShared then W.SetControlEnabled(useShared, false) end
        W.SetControlsEnabled(blacklistEditControls, editEnabled)
        local count = Model.BlacklistPreparedCount(scope)
        prepared:SetText(count == 1 and "1 prepared blacklist entry" or (tostring(count) .. " prepared blacklist entries"))
        local entries = Model.BlacklistEntries(scope)
        emptyText:SetShown(#entries == 0)
        listScroll:SetShown(#entries > 0)
        listChild:SetHeight(max(116, (#entries * 24) + 2))
        for i = 1, max(#rows, #entries) do
            local row = rows[i]
            local item = entries[i]
            if item then
                row = EnsureRow(i)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 24))
                row._msufValue = item.value
                if item.icon then
                    if type(MSUF_SetIconTexture) == "function" then
                        MSUF_SetIconTexture(row.icon, item.icon, "")
                    else
                        row.icon:SetTexture(item.icon)
                    end
                    row.icon:SetTexCoord(0, 1, 0, 1)
                    row.icon:Show()
                    row.text:ClearAllPoints()
                    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                else
                    row.icon:Hide()
                    row.text:ClearAllPoints()
                    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                end
                row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.text:SetText(item.text or item.value or "")
                row:SetAlpha(editEnabled and 1 or 0.55)
                if row.EnableMouse then row:EnableMouse(editEnabled) end
                row:Show()
            elseif row then
                row._msufValue = nil
                row:Hide()
            end
        end
        moreText:SetShown(#entries > 0)
    end)
end
local function GFReadBlacklistCat(scope, groupKey, catKey)
    if Model and type(Model.ReadGroupBlacklistCategory) == "function" then return Model.ReadGroupBlacklistCategory(scope, groupKey, catKey) end
    local group = GFReadGroup(scope, groupKey)
    return type(group.blacklistCats) == "table" and group.blacklistCats[catKey] == true
end
local function GFInvalidateBlacklist(scope, groupKey)
    local af = AuraFilter()
    if not (af and type(af.InvalidateBlacklistHash) == "function") then return end
    local a, b = GroupScopeKinds(scope)
    af.InvalidateBlacklistHash(GFAuraGroup(a, groupKey))
    if b then af.InvalidateBlacklistHash(GFAuraGroup(b, groupKey)) end
end
local function GFWriteBlacklistCat(scope, groupKey, catKey, value)
    if Model and type(Model.WriteGroupBlacklistCategory) == "function" then
        local changed = Model.WriteGroupBlacklistCategory(scope, groupKey, catKey, value)
        if changed then QueueGroupScope(scope, "visual") end
        return
    end
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local group = GFAuraGroup(kind, groupKey)
        group.blacklistCats = group.blacklistCats or {}
        local nextValue = value and true or nil
        if group.blacklistCats[catKey] == nextValue then return end
        group.blacklistCats[catKey] = nextValue
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then
        GFInvalidateBlacklist(scope, groupKey)
        QueueGroupScope(scope, "visual")
    end
end
local function CategoryLabel(cat)
    if cat and cat.key == "RAID_BUFFS" then return "Raid / Mythic Buffs" end
    return (cat and cat.label) or (cat and cat.key) or ""
end
local function BuildGroupFilters(ctx, b, scope)
    local section = b:Section("Group Frame Filters", 690)
    local w = section._msuf2Width or b.width or 720
    local lane = CurrentLane("auraFilterLane", "buff")
    local laneText = lane == "buff" and "Buff" or "Debuff"
    local filterW = w - 48
    local filter = Card(section, "Inclusive " .. laneText .. " Filter", "Filter token for " .. ScopeLabel(scope) .. " group-frame " .. laneText .. "s.", 24, -42, filterW, 234)
    W.LabelAt(filter, "Filter Type", 16, -72, 90, "GameFontNormalSmall", T.colors.accent)
    BuildLaneTabs(ctx, filter, "auraFilterLane", 112, -68, min(300, w - 180))
    local dropdownW = min(360, max(240, floor((filterW - 48) * 0.55)))
    BindGroupDropdown(ctx, filter, laneText .. " Filter", 16, -142, GroupFilterValues(lane), dropdownW, scope, lane, "filterToken", "ALL", "visual")
    W.Text(filter, "Category blacklist data below is read-only in the native 12.1 backend.", 40 + dropdownW, -142, max(220, filterW - dropdownW - 64), T.colors.muted)
    local blacklist = Card(section, "Category Blacklist", "Read-only legacy category data for " .. ScopeLabel(scope) .. ".", 24, -304, w - 48, 324)
    W.LabelAt(blacklist, "Active", 16, -50, 70, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(blacklist, lane == "buff" and "Buff category blacklist" or "Debuff category blacklist", 86, -50, 260, "GameFontHighlightSmall", T.colors.text)
    W.Text(blacklist, NATIVE_EXACT_AURA_FILTERS_DISABLED_TEXT, 16, -72, w - 96, T.colors.muted)
    local af = AuraFilter()
    local meta = af and af.DECLASSIFIED_META
    if not (type(meta) == "table" and #meta > 0) then
        W.Text(blacklist, "No public aura category data is loaded.", 16, -96, w - 96, T.colors.muted)
        return
    end
    local half = ceil(#meta / 2)
    local catColW = max(230, floor((w - 104) / 2))
    local x2 = 16 + catColW + 24
    local startY = -120
    local categoryControls = {}
    for i = 1, #meta do
        local cat = meta[i]
        local col = i <= half and 0 or 1
        local row = col == 0 and (i - 1) or (i - half - 1)
        local tx = col == 0 and 16 or x2
        local toggle = BindToggle(ctx, blacklist, CategoryLabel(cat), tx, startY - row * 30, catColW,
            function() return GFReadBlacklistCat(scope, lane, cat.key) end,
            function(v) GFWriteBlacklistCat(scope, lane, cat.key, v) end)
        if cat.tooltip then AddTooltip(toggle, CategoryLabel(cat), cat.tooltip) end
        categoryControls[#categoryControls + 1] = toggle
    end
    M.TrackRefresh(ctx, function()
        W.SetControlsEnabled(categoryControls, NATIVE_EXACT_AURA_FILTERS_ENABLED)
    end)
end
local function BuildAuraFiltersPage(ctx)
    local b = W.PageBuilder(ctx)
    local scope = BuildAuraChrome(ctx, b, "Aura Filters", "Native 12.1 Buff and Debuff filters; legacy whitelist/blacklist data is read-only.")
    if IsGroupScope(scope) then
        BuildGroupFilters(ctx, b, scope)
    else
        BuildUnitFilterRulesByLane(ctx, b, scope)
        BuildUnitBlacklist(ctx, b, scope)
    end
    FinishPage(ctx, b)
end
local function BuildUnitAuraPlacementCard(ctx, parent, unit, kind, x, y, width)
    local title = kind == "buff" and "Buffs" or "Debuffs"
    local controls = {}
    local leftX = x + 16
    local rightX = max(x + 430, min(x + 520, x + floor(width * 0.50)))
    local leftW = max(270, min(340, rightX - leftX - 70))
    local rightW = max(280, min(360, width - (rightX - x) - 24))
    local anchorValues = type(Model.AuraAnchorValues) == "function" and Model.AuraAnchorValues() or GFAnchorValues()
    local growthValues = type(Model.LaneGrowthValues) == "function" and Model.LaneGrowthValues() or Model.GrowthValues()
    W.ControlCardBackdrop(parent, x, y, width, 42)
    W.ControlCard(parent, "Placement", nil, leftX - 14, y - 46, leftW + 28, 292)
    W.ControlCard(parent, "Icon Grid", nil, rightX - 14, y - 46, rightW + 28, 342)
    local enable = BindSwitch(ctx, parent, title, leftX, y - 6, 190,
        function() return UnitLaneShown(unit, kind) end,
        function(v) SetUnitLaneShown(ctx, unit, kind, v, "AURAS3_UNIT_PAGE_" .. (kind == "buff" and "BUFFS" or "DEBUFFS")) end)
    enable._msuf2GroupFrameGateAlwaysEnabled = true
    M.AppendValues(controls, BindDropdown(ctx, parent, "Anchor", leftX, y - 80, anchorValues, leftW,
        function()
            if type(Model.ReadLaneAnchor) == "function" then return Model.ReadLaneAnchor(unit, kind) end
            return kind == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
        end,
        function(v)
            if type(Model.WriteLaneAnchor) == "function" then
                Model.WriteLaneAnchor(unit, kind, v)
                ApplyUnit(ctx, unit, "AURAS3_UNIT_ANCHOR")
            end
        end))
    M.AppendValues(controls, BindDropdown(ctx, parent, "Growth", leftX, y - 132, growthValues, leftW,
        function()
            if type(Model.ReadLaneGrowthPair) == "function" then return Model.ReadLaneGrowthPair(unit, kind) end
            return Model.ReadLaneGrowth(unit, kind)
        end,
        function(v)
            if type(Model.WriteLaneGrowthPair) == "function" then
                Model.WriteLaneGrowthPair(unit, kind, v)
            else
                Model.WriteLaneGrowth(unit, kind, v)
            end
            ApplyUnit(ctx, unit, "AURAS3_UNIT_GROWTH")
        end))
    local sliderSpecs = {
        { "Offset X", leftX, y - 190, -300, 300, 1, leftW, function() return Model.ReadNumber(unit, LaneXKey(kind), 0, -4096, 4096) end, function(v) Model.WriteNumber(unit, LaneXKey(kind), v, -4096, 4096); ApplyUnit(ctx, unit, "AURAS3_UNIT_X") end },
        { "Offset Y", leftX, y - 250, -300, 300, 1, leftW, function() return Model.ReadNumber(unit, LaneYKey(kind), LaneDefaultY(kind), -4096, 4096) end, function(v) Model.WriteNumber(unit, LaneYKey(kind), v, -4096, 4096); ApplyUnit(ctx, unit, "AURAS3_UNIT_Y") end },
        { "Max Icons", rightX, y - 80, 0, 80, 1, rightW, function() return Model.ReadNumber(unit, LaneMaxKey(kind), LaneDefaultMax(kind), 0, 80) end, function(v) Model.WriteNumber(unit, LaneMaxKey(kind), v, 0, 80); ApplyUnit(ctx, unit, "AURAS3_UNIT_MAX") end },
        { "Icon Size", rightX, y - 140, 10, 80, 1, rightW, function() return Model.ReadNumber(unit, LaneSizeKey(kind), 26, 1, 128) end, function(v) Model.WriteNumber(unit, LaneSizeKey(kind), v, 1, 128); ApplyUnit(ctx, unit, "AURAS3_UNIT_SIZE") end },
        { "Per Row", rightX, y - 200, 1, 40, 1, rightW, function() return Model.ReadLanePerRow(unit, kind) end, function(v) Model.WriteLanePerRow(unit, kind, v); ApplyUnit(ctx, unit, "AURAS3_UNIT_PER_ROW") end },
        { "Spacing", rightX, y - 260, 0, 12, 1, rightW, function() return Model.ReadNumber(unit, "spacing", 2, 0, 64) end, function(v) Model.WriteNumber(unit, "spacing", v, 0, 64); ApplyUnit(ctx, unit, "AURAS3_UNIT_SPACING") end },
        { "Layer (Z-Order)", rightX, y - 320, 1, 15, 1, rightW, function() return type(Model.ReadLaneLayer) == "function" and Model.ReadLaneLayer(unit, kind) or (kind == "buff" and 5 or 6) end, function(v) if type(Model.WriteLaneLayer) == "function" then Model.WriteLaneLayer(unit, kind, v); ApplyUnit(ctx, unit, "AURAS3_UNIT_LAYER") end end },
    }
    M.BuildControlSpecs(sliderSpecs, {
        ["*"] = function(s) return BindSlider(ctx, parent, s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9]) end,
    }, nil, controls)
    local function RefreshLaneCard()
        local shown = UnitLaneShown(unit, kind)
        W.SetControlEnabled(enable, true)
        W.SetControlsEnabled(controls, shown)
    end
    M.TrackRefresh(ctx, RefreshLaneCard)
    return controls
end
function M.BuildAuras3UnitSection(ctx, builder, unit)
    if not Model.UnitSupported(unit) then return end
    local sec = builder:CollapsibleSection("auras3", "Auras", 622, false)
    local sectionW = sec._msuf2Width or builder.width or 720
    local laneCardW = sectionW - 36
    local top = Card(sec, "Aura Area", "Visibility, placement and icon grid for this unit frame.", 18, -38, sectionW - 36, 112)
    W.LabelAt(top, "Lane", 16, -66, 54, "GameFontNormalSmall", T.colors.accent)
    M.unitAuraTabSelection = M.unitAuraTabSelection or {}
    local function CurrentTab()
        local tab = M.unitAuraTabSelection[unit] or "buff"
        if tab ~= "buff" and tab ~= "debuff" then tab = "buff" end
        return tab
    end
    local _, laneButtons = BuildActionTabs(ctx, top, LANE_VALUES, 74, -62, 200, CurrentTab, function(kind)
        M.unitAuraTabSelection[unit] = kind
        QueueAurasPageRefresh(ctx, "auras-unit-lane-tab")
    end, 8)
    local actionsX = max(360, sectionW - 206)
    local style = ActionButton(top, "Style", 72)
    style:SetPoint("TOPLEFT", top, "TOPLEFT", actionsX, -62)
    style:SetScript("OnClick", function() SelectPage("auras3_styling", unit) end)
    local filters = ActionButton(top, "Filters", 82)
    filters:SetPoint("LEFT", style, "RIGHT", 8, 0)
    filters:SetScript("OnClick", function() SelectPage("auras3_filters", unit) end)
    local tabFrames = {}
    local buffFrame, debuffFrame = M.UnitSectionsShared.MakeTabFrames(sec, -170, sectionW, tabFrames, "buff", "debuff")
    BuildUnitAuraPlacementCard(ctx, buffFrame, unit, "buff", 18, -6, laneCardW)
    BuildUnitAuraPlacementCard(ctx, debuffFrame, unit, "debuff", 18, -6, laneCardW)
    local function RefreshTabs()
        local tab = CurrentTab()
        for key, frame in pairs(tabFrames) do frame:SetShown(key == tab) end
    end
    M.TrackRefresh(ctx, function()
        W.SetControlEnabled(laneButtons.buff, true)
        W.SetControlEnabled(laneButtons.debuff, true)
        RefreshTabs()
        if W.SetCollapsibleBadges then
            W.SetCollapsibleBadges(sec, {
                { text = UnitLaneShown(unit, "buff") and "Buffs on" or "Buffs off", kind = UnitLaneShown(unit, "buff") and "ok" or "muted", onlyWhenOpen = true },
                { text = UnitLaneShown(unit, "debuff") and "Debuffs on" or "Debuffs off", kind = UnitLaneShown(unit, "debuff") and "ok" or "muted", onlyWhenOpen = true },
                { text = CurrentTab() == "debuff" and "Debuffs" or "Buffs", kind = "accent", onlyWhenOpen = true },
            })
        end
    end)
end
M.RegisterPage("auras3_buffs", { title = "MSUF Aura Buffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "buff") end, version = 9 })
M.RegisterPage("auras3_debuffs", { title = "MSUF Aura Debuffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "debuff") end, version = 9 })
M.RegisterPage("auras3_styling", { title = "MSUF Aura Style", build = BuildAuraStylePage, version = 27 })
M.RegisterPage("auras3_filters", { title = "MSUF Aura Filters", build = BuildAuraFiltersPage, version = 20 })
