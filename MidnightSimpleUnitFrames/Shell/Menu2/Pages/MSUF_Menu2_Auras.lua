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
local table_concat = table.concat
local AURA_SCOPE_VALUES = VTP "shared=Shared|player=Player|target=Target|focus=Focus|boss=Boss|party=Party|raid=Raid / Mythic"
local AURA_SCOPE_LABELS = { shared = "Shared", player = "Player", target = "Target", focus = "Focus", boss = "Boss", party = "Party", raid = "Raid / Mythic" }
local AURA_SCOPE_VALID = M.KeySetFromWords "shared player target focus boss party raid"
local AURA_GROUP_SCOPES = M.KeySetFromWords "party raid mythicraid"
local SHARED_PREVIEW_SCOPES = {
    { scope = "player", label = "Player" },
    { scope = "target", label = "Target" },
    { scope = "focus", label = "Focus" },
    { scope = "boss", label = "Boss" },
    { scope = "party", label = "Party" },
    { scope = "raid", label = "Raid" },
}
local LANE_VALUES = VTP "buff=Buffs|debuff=Debuffs"
local DEBUFF_TYPE_BORDER_MODE_VALUES = VTP "OFF=Off|BORDER=Border|SYMBOL=Border + Symbol"
local COOLDOWN_SWIPE_DIRECTION_VALUES = VTP "NORMAL=Normal|REVERSE=Reverse"
local DURATION_BAR_DISPLAY_VALUES = VTP "BAR_ONLY=Bar Only|OVERLAY=Icon + Bar"
local DURATION_BAR_POSITION_VALUES = VTP "BOTTOM=Bottom|TOP=Top"
local DURATION_BAR_DIRECTION_VALUES = VTP "REMAINING=Remaining|ELAPSED=Elapsed"
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
    INCLUDE_NAME_PLATE_ONLY = "Include Nameplate-only",
    CANCELABLE = "Cancelable",
    NOT_CANCELABLE = "Not Cancelable",
    RAID_PLAYER_DISPELLABLE = "Dispellable",
    EXTERNAL_DEFENSIVE = "External Defensive",
    BIG_DEFENSIVE = "Big Defensive",
    CROWD_CONTROL = "Crowd Control",
}
local GROUP_NATIVE_FILTER_ALLOWED = {
    buff = M.KeySetFromWords "ALL PLAYER RAID RAID_IN_COMBAT INCLUDE_NAME_PLATE_ONLY CANCELABLE NOT_CANCELABLE EXTERNAL_DEFENSIVE BIG_DEFENSIVE",
    debuff = M.KeySetFromWords "ALL PLAYER RAID RAID_IN_COMBAT INCLUDE_NAME_PLATE_ONLY RAID_PLAYER_DISPELLABLE CROWD_CONTROL",
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
local function OpenAuraColors()
    _G.MSUF_EM2_MenuFocusRequest = {
        pageKey = "opt_colors",
        sectionId = "colors_auras",
        explicit = true,
        consumed = false,
    }
    if M.SelectPage and M.SelectPage("opt_colors") == false then
        _G.MSUF_EM2_MenuFocusRequest = nil
    end
end
local pendingAuraUnits = {}
local pendingAuraReasons = {}
local pendingAuraGlobal
local pendingAuraGlobalReason
local pendingAuraRefreshCtx
local pendingAuraRefreshReason
local auraApplyQueued = false
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
local BindDropdown, BindTextInput = M.BindDropdownAt, M.BindTextInputAt
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
local AURA_STYLE_UNIT_SCOPES = {
    { value = "player", text = "Player" },
    { value = "target", text = "Target" },
    { value = "focus", text = "Focus" },
    { value = "boss", text = "Boss" },
}
local function AuraStyleUnitOverrideLabels()
    local out = {}
    for i = 1, #AURA_STYLE_UNIT_SCOPES do
        local item = AURA_STYLE_UNIT_SCOPES[i]
        if not Model.UseSharedVisuals(item.value) then out[#out + 1] = item.text end
    end
    return out
end
local function AuraStyleVisibleOverrideLabels(unitLabels)
    local out = {}
    unitLabels = unitLabels or AuraStyleUnitOverrideLabels()
    for i = 1, #unitLabels do out[#out + 1] = unitLabels[i] end
    out[#out + 1] = "Party"
    out[#out + 1] = "Raid / Mythic"
    return out
end
local function AuraStyleScopeHasOverride(scope)
    if scope == "shared" then return false end
    if IsGroupScope(scope) then return true end
    return not Model.UseSharedVisuals(scope)
end
local function BuildAuraStyleScopeOverrideSection(ctx, b)
    local values = AURA_SCOPE_VALUES
    local scopeOpts = {
        values = values,
        width = ctx.width,
        getValue = CurrentScope,
        setValue = function(value)
            SetCurrentScope(value)
            Rebuild(ctx)
        end,
        hasOverride = AuraStyleScopeHasOverride,
    }
    local metrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(values, scopeOpts)
    local overrideY = min(-58, ((metrics and metrics.bottomY) or -40) - 18)
    local hintY = overrideY - 34
    local section = b:Section("", max(128, abs(hintY) + 42))
    if section.title then section.title:Hide() end
    local segment = W.ScopeOverrideBar(ctx, section, scopeOpts)
    local override = W.ToggleAt(section, "Use custom aura style for this scope", 14, overrideY, 300)
    AddTooltip(override, "Aura style override", "On: this scope keeps local aura style settings. Off: this scope follows Shared aura style.")
    M.BindBoolWidget(ctx, override,
        function()
            local current = CurrentScope()
            return current ~= "shared" and not IsGroupScope(current) and not Model.UseSharedVisuals(current)
        end,
        function(enabled)
            local current = CurrentScope()
            if current == "shared" or IsGroupScope(current) then return end
            Model.SetUseSharedVisuals(current, not enabled)
            ApplyUnit(ctx, current, "AURAS3_STYLE_OVERRIDE", true)
            Rebuild(ctx)
        end)
    local overrideInfo = W.Text(section, "", 14, overrideY, ctx.width - 130, T.colors.text)
    local reset = T.Button(section, "Reset", 76, 22)
    reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, overrideY + 8)
    T.CenterButtonLabel(reset)
    reset:SetScript("OnClick", function()
        for i = 1, #AURA_STYLE_UNIT_SCOPES do
            Model.SetUseSharedVisuals(AURA_STYLE_UNIT_SCOPES[i].value, true)
            ApplyUnit(ctx, AURA_STYLE_UNIT_SCOPES[i].value, "AURAS3_STYLE_RESET", false)
        end
        Rebuild(ctx)
    end)
    local hint = W.Text(section, "", 14, hintY, ctx.width - 28, T.colors.muted)
    M.TrackRefresh(ctx, function()
        local current = CurrentScope()
        local shared = current == "shared"
        local group = IsGroupScope(current)
        local active = AuraStyleUnitOverrideLabels()
        local visibleActive = AuraStyleVisibleOverrideLabels(active)
        W.SetControlShown(override, not shared and not group)
        overrideInfo:SetShown(shared or group)
        reset:SetShown(shared and #active > 0)
        if shared then
            overrideInfo:SetText("|cffffffff" .. Tr("Overrides:") .. "|r " .. (#visibleActive > 0 and table_concat(visibleActive, ", ") or Tr("None")))
            hint:SetText("Shared aura style is the baseline for unit-frame aura text, swipe, border, and timer settings. Party and Raid are group-frame style scopes with their own settings.")
        elseif group then
            overrideInfo:SetText("|cffffffff" .. Tr("Group style scope:") .. "|r " .. ScopeLabel(current))
            hint:SetText(ScopeLabel(current) .. " uses group-frame aura style settings. These controls are scoped here and do not change unit-frame Shared style.")
        elseif not Model.UseSharedVisuals(current) then
            hint:SetText("Override active: this scope keeps its own aura style. Shared style changes will not replace it until the override is reset.")
        else
            hint:SetText("Inherited: this scope follows Shared aura style. Enable custom aura style only when this scope needs different text, swipe, border, or timer settings.")
        end
        if segment and segment.Refresh then segment:Refresh() end
        hint:SetWidth(ctx.width - 28)
    end)
    return CurrentScope()
end
local AURA_FILTER_UNIT_SCOPES = AURA_STYLE_UNIT_SCOPES
local function AuraFilterUnitOverrideLabels()
    local out = {}
    for i = 1, #AURA_FILTER_UNIT_SCOPES do
        local item = AURA_FILTER_UNIT_SCOPES[i]
        if not Model.UseSharedRules(item.value) then out[#out + 1] = item.text end
    end
    return out
end
local function AuraFilterVisibleOverrideLabels(unitLabels)
    local out = {}
    unitLabels = unitLabels or AuraFilterUnitOverrideLabels()
    for i = 1, #unitLabels do out[#out + 1] = unitLabels[i] end
    out[#out + 1] = "Party"
    out[#out + 1] = "Raid / Mythic"
    return out
end
local function AuraFilterScopeHasOverride(scope)
    if scope == "shared" then return false end
    if IsGroupScope(scope) then return true end
    return not Model.UseSharedRules(scope)
end
local function BuildAuraFilterScopeOverrideSection(ctx, b)
    local values = AURA_SCOPE_VALUES
    local scopeOpts = {
        values = values,
        width = ctx.width,
        getValue = CurrentScope,
        setValue = function(value)
            SetCurrentScope(value)
            Rebuild(ctx)
        end,
        hasOverride = AuraFilterScopeHasOverride,
    }
    local metrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(values, scopeOpts)
    local overrideY = min(-58, ((metrics and metrics.bottomY) or -40) - 18)
    local hintY = overrideY - 34
    local section = b:Section("", max(128, abs(hintY) + 42))
    if section.title then section.title:Hide() end
    local segment = W.ScopeOverrideBar(ctx, section, scopeOpts)
    local override = W.ToggleAt(section, "Use custom aura filters for this scope", 14, overrideY, 310)
    AddTooltip(override, "Aura filter override", "On: this scope keeps local aura filter rules. Off: this scope follows Shared aura filters.")
    M.BindBoolWidget(ctx, override,
        function()
            local current = CurrentScope()
            return current ~= "shared" and not IsGroupScope(current) and not Model.UseSharedRules(current)
        end,
        function(enabled)
            local current = CurrentScope()
            if current == "shared" or IsGroupScope(current) then return end
            Model.SetUseSharedRules(current, not enabled)
            ApplyUnit(ctx, current, "AURAS3_FILTER_OVERRIDE", true)
            Rebuild(ctx)
        end)
    local overrideInfo = W.Text(section, "", 14, overrideY, ctx.width - 130, T.colors.text)
    local reset = T.Button(section, "Reset", 76, 22)
    reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, overrideY + 8)
    T.CenterButtonLabel(reset)
    reset:SetScript("OnClick", function()
        for i = 1, #AURA_FILTER_UNIT_SCOPES do
            Model.SetUseSharedRules(AURA_FILTER_UNIT_SCOPES[i].value, true)
            ApplyUnit(ctx, AURA_FILTER_UNIT_SCOPES[i].value, "AURAS3_FILTER_RESET", false)
        end
        Rebuild(ctx)
    end)
    local hint = W.Text(section, "", 14, hintY, ctx.width - 28, T.colors.muted)
    M.TrackRefresh(ctx, function()
        local current = CurrentScope()
        local shared = current == "shared"
        local group = IsGroupScope(current)
        local active = AuraFilterUnitOverrideLabels()
        local visibleActive = AuraFilterVisibleOverrideLabels(active)
        W.SetControlShown(override, not shared and not group)
        overrideInfo:SetShown(shared or group)
        reset:SetShown(shared and #active > 0)
        if shared then
            overrideInfo:SetText("|cffffffff" .. Tr("Overrides:") .. "|r " .. (#visibleActive > 0 and table_concat(visibleActive, ", ") or Tr("None")))
            hint:SetText("Shared aura filters are the baseline for unit-frame buff and debuff rules. Party and Raid are group-frame filter scopes with their own settings.")
        elseif group then
            overrideInfo:SetText("|cffffffff" .. Tr("Group filter scope:") .. "|r " .. ScopeLabel(current))
            hint:SetText(ScopeLabel(current) .. " uses group-frame aura filter settings. These controls are scoped here and do not change unit-frame Shared filters.")
        elseif not Model.UseSharedRules(current) then
            hint:SetText("Override active: this scope keeps its own aura filter rules. Shared filter changes will not replace it until the override is reset.")
        else
            hint:SetText("Inherited: this scope follows Shared aura filters. Enable custom aura filters only when this scope needs different buff or debuff rules.")
        end
        if segment and segment.Refresh then segment:Refresh() end
        hint:SetWidth(ctx.width - 28)
    end)
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
        return VT("ALL", "All Buffs", "PLAYER", "My Buffs Only", "RAID", "Raid Buffs", "RAID_IN_COMBAT", "Raid In Combat", "INCLUDE_NAME_PLATE_ONLY", "Include Nameplate-only", "CANCELABLE", "Cancelable", "NOT_CANCELABLE", "Not Cancelable", "EXTERNAL_DEFENSIVE", "External Defensive", "BIG_DEFENSIVE", "Big Defensive")
    end
    return VT("ALL", "All Debuffs", "PLAYER", "My Debuffs Only", "RAID", "Raid Debuffs", "RAID_IN_COMBAT", "Raid In Combat", "INCLUDE_NAME_PLATE_ONLY", "Include Nameplate-only", "RAID_PLAYER_DISPELLABLE", "Dispellable", "CROWD_CONTROL", "Crowd Control")
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
    f.durationBar = f:CreateTexture(nil, "OVERLAY")
    f.durationBar:SetTexture(TEX_W8)
    f.durationBar:SetVertexColor(0.08, 0.78, 1.00, 0.92)
    f.durationBar:Hide()
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
    if fs.SetFont then
        local px = max(7, tonumber(size) or 10)
        local flags = fontFlags or "OUTLINE"
        local path = fontPath or FONT
        local resolveSafe = _G.MSUF_ResolveSafeFontPath
        if type(resolveSafe) == "function" then
            local gdb = _G.MSUF_DB and _G.MSUF_DB.general
            path = resolveSafe(path, px, flags, gdb and gdb.fontKey)
        end
        local ok = pcall(fs.SetFont, fs, path, px, flags)
        if not ok then
            pcall(fs.SetFont, fs, FONT, px, flags)
        end
    end
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
        cooldownSwipeReverse = false,
        stackSize = 10,
        stackAnchor = "TOPRIGHT",
        stackX = -1,
        stackY = -1,
        cooldownSize = 9,
        cooldownAnchor = "CENTER",
        cooldownX = 0,
        cooldownY = 0,
        debuffBorderMode = "OFF",
        showDurationBar = false,
        durationBarHeight = 2,
        durationBarDisplay = "BAR_ONLY",
        durationBarPosition = "BOTTOM",
        durationBarDirection = "REMAINING",
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
        cfg.cooldownSwipeReverse = group.cooldownSwipeReverse == true
        cfg.stackSize = tonumber(group.stackSize) or 10
        cfg.stackAnchor = group.stackAnchor or "BOTTOMRIGHT"
        cfg.stackX = tonumber(group.stackX) or 0
        cfg.stackY = tonumber(group.stackY) or 0
        cfg.cooldownSize = tonumber(group.cooldownSize) or 8
        cfg.cooldownAnchor = group.cooldownAnchor or "CENTER"
        cfg.cooldownX = tonumber(group.cooldownX) or 0
        cfg.cooldownY = tonumber(group.cooldownY) or 0
        cfg.cooldownDecimalSeconds = tonumber(group.cooldownDecimalSeconds) or 3
        cfg.showDurationBar = group.showDurationBar == true
        cfg.durationBarHeight = tonumber(group.durationBarHeight) or 2
        cfg.durationBarDisplay = group.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
        cfg.durationBarPosition = group.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
        cfg.durationBarDirection = group.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING"
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
            cfg.cooldownSwipeReverse = Model.ReadLaneStyleBool(readScope, lane, "cooldownSwipeReverse", false)
            cfg.showDurationBar = Model.ReadLaneStyleBool(readScope, lane, "showDurationBar", false)
        else
            cfg.showStacks = Model.ReadBool(readScope, "showStackCount", true)
            cfg.showTimers = Model.ReadBool(readScope, "showCooldownText", true)
            cfg.showSwipe = Model.ReadBool(readScope, "showCooldownSwipe", true)
            cfg.cooldownSwipeReverse = Model.ReadBool(readScope, "cooldownSwipeReverse", false)
            cfg.showDurationBar = Model.ReadBool(readScope, "showDurationBar", false)
        end
        cfg.stackSize = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextSize", 14, 6, 40) or Model.ReadNumber(readScope, "stackTextSize", 14, 6, 40)
        cfg.stackAnchor = lane and type(Model.ReadLaneStackAnchor) == "function" and Model.ReadLaneStackAnchor(readScope, lane) or Model.ReadStackAnchor(readScope)
        cfg.stackX = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextOffsetX", -1, -2000, 2000) or Model.ReadNumber(readScope, "stackTextOffsetX", -1, -2000, 2000)
        cfg.stackY = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextOffsetY", 1, -2000, 2000) or Model.ReadNumber(readScope, "stackTextOffsetY", 1, -2000, 2000)
        cfg.cooldownSize = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextSize", 14, 6, 40) or Model.ReadNumber(readScope, "cooldownTextSize", 14, 6, 40)
        if lane and type(Model.ReadLaneCooldownAnchor) == "function" then
            cfg.cooldownAnchor = Model.ReadLaneCooldownAnchor(readScope, lane)
        elseif type(Model.ReadCooldownAnchor) == "function" then
            cfg.cooldownAnchor = Model.ReadCooldownAnchor(readScope)
        elseif runtimePreview and runtimePreview.cooldownAnchor then
            cfg.cooldownAnchor = runtimePreview.cooldownAnchor
        end
        cfg.cooldownX = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextOffsetX", 0, -2000, 2000) or Model.ReadNumber(readScope, "cooldownTextOffsetX", 0, -2000, 2000)
        cfg.cooldownY = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextOffsetY", 0, -2000, 2000) or Model.ReadNumber(readScope, "cooldownTextOffsetY", 0, -2000, 2000)
        cfg.cooldownDecimalSeconds = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownDecimalSeconds", 3, 0, 30) or Model.ReadNumber(readScope, "cooldownDecimalSeconds", 3, 0, 30)
        cfg.durationBarHeight = lane and Model.ReadLaneStyleNumber(readScope, lane, "durationBarHeight", 2, 1, 16) or Model.ReadNumber(readScope, "durationBarHeight", 2, 1, 16)
        if lane and type(Model.ReadLaneDurationBarDisplay) == "function" then
            cfg.durationBarDisplay = Model.ReadLaneDurationBarDisplay(readScope, lane)
        else
            cfg.durationBarDisplay = Model.ReadValue(readScope, "durationBarDisplay", "BAR_ONLY")
        end
        if lane and type(Model.ReadLaneDurationBarPosition) == "function" then
            cfg.durationBarPosition = Model.ReadLaneDurationBarPosition(readScope, lane)
        else
            cfg.durationBarPosition = Model.ReadValue(readScope, "durationBarPosition", "BOTTOM")
        end
        if lane and type(Model.ReadLaneDurationBarDirection) == "function" then
            cfg.durationBarDirection = Model.ReadLaneDurationBarDirection(readScope, lane)
        else
            cfg.durationBarDirection = Model.ReadValue(readScope, "durationBarDirection", "REMAINING")
        end
        if lane == "debuff" then
            if type(Model.ReadDebuffTypeBorderMode) == "function" then
                cfg.debuffBorderMode = Model.ReadDebuffTypeBorderMode(readScope)
            elseif type(Model.ReadLaneStyleBool) == "function" then
                cfg.debuffBorderMode = Model.ReadLaneStyleBool(readScope, "debuff", "useDebuffTypeBorders", false) and "SYMBOL" or "OFF"
            end
        end
    end
    local maxSize = max(12, min(128, floor((height or 104) - 38), floor((width or 300) - 20)))
    cfg.actualSize = max(10, tonumber(cfg.size) or 24)
    cfg.size = min(maxSize, cfg.actualSize)
    cfg.spacing = min(10, max(0, tonumber(cfg.spacing) or 2))
    cfg.perRow = max(1, Round(cfg.perRow))
    cfg.maxIcons = max(0, Round(cfg.maxIcons))
    local maxCols = max(1, floor(((width or 300) - 20 + cfg.spacing) / max(1, cfg.size + cfg.spacing)))
    cfg.columns = min(cfg.perRow, maxCols)
    cfg.maxRows = max(1, floor(((height or 104) - 38 + cfg.spacing) / max(1, cfg.size + cfg.spacing)))
    cfg.count = min(14, cfg.maxIcons, cfg.columns * cfg.maxRows)
    cfg.stackSize = max(7, tonumber(cfg.stackSize) or 10)
    cfg.cooldownSize = max(7, tonumber(cfg.cooldownSize) or 9)
    cfg.cooldownDecimalSeconds = min(30, max(0, tonumber(cfg.cooldownDecimalSeconds) or 3))
    cfg.durationBarHeight = min(max(1, tonumber(cfg.durationBarHeight) or 2), max(1, floor((cfg.size or 24) / 2)))
    cfg.durationBarDisplay = cfg.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    cfg.durationBarPosition = cfg.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
    cfg.durationBarDirection = cfg.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING"
    return cfg
end
local function FormatAuraPreviewTimer(seconds, cfg)
    seconds = tonumber(seconds) or 0
    local decimalSec = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3
    if decimalSec > 0 and seconds < decimalSec then return string.format("%.1f", seconds) end
    if seconds >= 60 then return tostring(max(1, floor(seconds / 60))) end
    return tostring(Round(seconds))
end
local function SharedAuraPreviewLabel(cfg)
    local labels = cfg and cfg._labels
    local count = labels and #labels or 0
    local name = cfg and cfg._label or "Frame"
    if count == #SHARED_PREVIEW_SCOPES then
        name = "All Frames"
    elseif count == 2 then
        name = labels[1] .. " / " .. labels[2]
    elseif count > 2 then
        name = labels[1] .. " +" .. tostring(count - 1)
    end
    local size = cfg and (cfg.actualSize or cfg.size) or 0
    local direction = cfg and cfg.cooldownSwipeReverse == true and "Reverse" or "Normal"
    return name .. "\n" .. tostring(Round(size)) .. "px " .. direction
end
local function BuildSharedAuraPreviewSamples(lane, width, height)
    local samples, bySize = {}, {}
    for i = 1, #SHARED_PREVIEW_SCOPES do
        local spec = SHARED_PREVIEW_SCOPES[i]
        local cfg = ReadMiniAuraPreviewConfig(spec.scope, lane, width, height)
        local size = Round(cfg.actualSize or cfg.size or 0)
        if size > 0 then
            local sampleKey = tostring(size) .. (cfg.cooldownSwipeReverse == true and ":R" or ":N")
            local existing = bySize[sampleKey]
            if existing then
                existing._labels[#existing._labels + 1] = spec.label
                existing.previewLabel = SharedAuraPreviewLabel(existing)
            else
                cfg.actualSize = size
                cfg._label = spec.label
                cfg._labels = { spec.label }
                cfg.previewLabel = SharedAuraPreviewLabel(cfg)
                samples[#samples + 1] = cfg
                bySize[sampleKey] = cfg
            end
        end
    end
    return samples
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
    local labels = {}
    for i = 1, 14 do
        local label = T.Font(box, "GameFontDisableSmall", "", T.colors.muted)
        label:SetJustifyH("CENTER")
        if label.SetJustifyV then label:SetJustifyV("TOP") end
        label:Hide()
        labels[i] = label
    end
    local buffTex = { 135987, 136116, 135932, 136085, 132333, 135981, 136048 }
    local debuffTex = { 136118, 136139, 136197, 135817, 132851, 136188, 136170 }
    local function HidePreviewIcon(icon)
        icon:Hide()
        icon.swipe:Hide()
        icon.durationBar:Hide()
        icon.dispelBorder:Hide()
    end
    local function RenderPreviewIcon(icon, index, cfg, isBuffIcon, forceText)
        icon:SetSize(cfg.size, cfg.size)
        local barOnly = cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
        local tex = isBuffIcon and buffTex or debuffTex
        icon.icon:SetTexture(tex[((index - 1) % #tex) + 1])
        icon.bg:SetShown(not barOnly)
        icon.icon:SetShown(not barOnly)
        local r, g, b = isBuffIcon and 0.20 or 0.78, isBuffIcon and 0.72 or 0.20, isBuffIcon and 0.42 or 0.24
        local borderAtlas = (not barOnly and not isBuffIcon) and DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[cfg.debuffBorderMode] or nil
        local showPreviewEdges = isBuffIcon == true and not barOnly
        for _, edge in pairs(icon.edge) do edge:SetShown(showPreviewEdges); edge:SetVertexColor(r, g, b, 0.95) end
        icon.swipe:SetShown(cfg.showSwipe ~= false and not barOnly)
        icon.swipe:ClearAllPoints()
        if cfg.cooldownSwipeReverse == true then
            icon.swipe:SetPoint("TOPRIGHT", icon, "TOP", 0, -1)
            icon.swipe:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 1, 1)
        else
            icon.swipe:SetPoint("TOPLEFT", icon, "TOP", 0, -1)
            icon.swipe:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
        end
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
        if cfg.showDurationBar == true then
            local inset = max(1, floor((cfg.size / 32) + 0.5))
            icon.durationBar:ClearAllPoints()
            icon.durationBar:SetHeight(cfg.durationBarHeight or 2)
            if cfg.durationBarPosition == "TOP" then
                icon.durationBar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
                icon.durationBar:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, -inset)
            else
                icon.durationBar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
                icon.durationBar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
            end
            if cfg.durationBarDirection == "ELAPSED" then
                icon.durationBar:SetVertexColor(0.22, 0.88, 0.50, 0.92)
            else
                icon.durationBar:SetVertexColor(0.08, 0.78, 1.00, 0.92)
            end
            icon.durationBar:Show()
        else
            icon.durationBar:Hide()
        end
        ApplyAuraPreviewFont(icon.stack, cfg.stackSize)
        ApplyAuraPreviewFont(icon.timer, cfg.cooldownSize)
        PlaceAuraPreviewText(icon.stack, icon, cfg.stackAnchor, cfg.stackX, cfg.stackY)
        PlaceAuraPreviewText(icon.timer, icon, cfg.cooldownAnchor, cfg.cooldownX, cfg.cooldownY)
        icon.stack:SetText(cfg.showStacks and ((forceText or index % 3 == 1) and "2" or "") or "")
        local sampleSeconds = forceText and 2.7 or (index % 2 == 0 and 12 or nil)
        icon.timer:SetText(cfg.showTimers and sampleSeconds and FormatAuraPreviewTimer(sampleSeconds, cfg) or "")
        icon:Show()
    end
    local function RefreshPreview()
        if AurasMenuCombatLocked() then return end
        if scope == "shared" then
            local samples = BuildSharedAuraPreviewSamples(lane, width, height)
            local count = min(#samples, #icons)
            local boxW, boxH = width or 300, height or 104
            local contentW = max(1, boxW - 20)
            local columns = min(count, max(1, floor(contentW / 86)))
            local rows = max(1, ceil(count / max(1, columns)))
            local cellW = max(56, floor(contentW / max(1, columns)))
            local cellH = max(44, floor((boxH - 42) / rows))
            local maxIconSize = max(12, min(80, cellW - 8, cellH - 24))
            for i = 1, #icons do
                local icon, label = icons[i], labels[i]
                if i <= count then
                    local cfg = samples[i]
                    local col = (i - 1) % columns
                    local row = floor((i - 1) / columns)
                    cfg.size = min(maxIconSize, max(10, tonumber(cfg.actualSize) or tonumber(cfg.size) or 24))
                    icon:ClearAllPoints()
                    icon:SetPoint("TOPLEFT", box, "TOPLEFT",
                        10 + col * cellW + floor((cellW - cfg.size) / 2),
                        -34 - row * cellH)
                    RenderPreviewIcon(icon, i, cfg, lane ~= "debuff", true)
                    label:ClearAllPoints()
                    label:SetWidth(cellW)
                    label:SetHeight(28)
                    label:SetPoint("TOP", icon, "BOTTOM", 0, -4)
                    label:SetText(cfg.previewLabel or SharedAuraPreviewLabel(cfg))
                    label:Show()
                else
                    HidePreviewIcon(icon)
                    label:Hide()
                end
            end
            return
        end
        local cfg = ReadMiniAuraPreviewConfig(scope, lane, width, height)
        for i = 1, #icons do
            local icon = icons[i]
            labels[i]:Hide()
            if i <= cfg.count then
                local col = (i - 1) % cfg.columns
                local row = floor((i - 1) / cfg.columns)
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", box, "TOPLEFT", 10 + col * (cfg.size + cfg.spacing), -34 - row * (cfg.size + cfg.spacing))
                local isBuffIcon = lane and lane == "buff" or (not lane and i <= 7)
                RenderPreviewIcon(icon, i, cfg, isBuffIcon, false)
            else
                HidePreviewIcon(icon)
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
    local styleControls = {}
    local refreshMiniPreview
    local function RefreshStylePreview()
        RefreshMiniAuraPreviewNow(refreshMiniPreview)
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
    local function ReadScopeCooldownAnchor()
        if type(Model.ReadLaneCooldownAnchor) == "function" then return Model.ReadLaneCooldownAnchor(unit, lane) end
        if type(Model.ReadCooldownAnchor) == "function" then return Model.ReadCooldownAnchor(unit) end
        return "CENTER"
    end
    local function WriteScopeCooldownAnchor(value)
        if type(Model.WriteLaneCooldownAnchor) == "function" then
            Model.WriteLaneCooldownAnchor(unit, lane, value)
        elseif type(Model.WriteCooldownAnchor) == "function" then
            Model.WriteCooldownAnchor(unit, value)
        end
    end
    local function ReadScopeSwipeDirection()
        return ReadScopeBool("cooldownSwipeReverse", false) and "REVERSE" or "NORMAL"
    end
    local function WriteScopeSwipeDirection(value)
        WriteScopeBool("cooldownSwipeReverse", value == "REVERSE")
    end
    local function ReadScopeDurationBarDisplay()
        if type(Model.ReadLaneDurationBarDisplay) == "function" then return Model.ReadLaneDurationBarDisplay(unit, lane) end
        local value = Model.ReadValue and Model.ReadValue(unit, "durationBarDisplay", "BAR_ONLY") or "BAR_ONLY"
        return value == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    end
    local function WriteScopeDurationBarDisplay(value)
        value = value == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
        if type(Model.WriteLaneDurationBarDisplay) == "function" then
            Model.WriteLaneDurationBarDisplay(unit, lane, value)
        elseif type(Model.WriteValue) == "function" then
            Model.WriteValue(unit, "durationBarDisplay", value)
        end
    end
    local function ReadScopeDurationBarPosition()
        if type(Model.ReadLaneDurationBarPosition) == "function" then return Model.ReadLaneDurationBarPosition(unit, lane) end
        local value = Model.ReadValue and Model.ReadValue(unit, "durationBarPosition", "BOTTOM") or "BOTTOM"
        return value == "TOP" and "TOP" or "BOTTOM"
    end
    local function WriteScopeDurationBarPosition(value)
        value = value == "TOP" and "TOP" or "BOTTOM"
        if type(Model.WriteLaneDurationBarPosition) == "function" then
            Model.WriteLaneDurationBarPosition(unit, lane, value)
        elseif type(Model.WriteValue) == "function" then
            Model.WriteValue(unit, "durationBarPosition", value)
        end
    end
    local function ReadScopeDurationBarDirection()
        if type(Model.ReadLaneDurationBarDirection) == "function" then return Model.ReadLaneDurationBarDirection(unit, lane) end
        local value = Model.ReadValue and Model.ReadValue(unit, "durationBarDirection", "REMAINING") or "REMAINING"
        return value == "ELAPSED" and "ELAPSED" or "REMAINING"
    end
    local function WriteScopeDurationBarDirection(value)
        value = value == "ELAPSED" and "ELAPSED" or "REMAINING"
        if type(Model.WriteLaneDurationBarDirection) == "function" then
            Model.WriteLaneDurationBarDirection(unit, lane, value)
        elseif type(Model.WriteValue) == "function" then
            Model.WriteValue(unit, "durationBarDirection", value)
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
    local function BodyWidth(body)
        return body and (body._msuf2Width or body.GetWidth and body:GetWidth()) or b.width or 720
    end
    local scopeLabel = ScopeLabel(scope)
    local baseId = "aura_style_" .. tostring(scope or "shared") .. "_" .. lane

    local previewH = unit == "shared" and 244 or 204
    local previewBoxH = unit == "shared" and 158 or 118
    local previewHintY = unit == "shared" and -210 or -170
    local preview = b:Section(LaneTitle(lane) .. " Preview", previewH)
    local pw = BodyWidth(preview)
    refreshMiniPreview = select(2, BuildMiniAuraPreview(ctx, preview, unit, 24, -34, pw - 48, previewBoxH, lane))
    local hint = W.Text(preview, "", 24, previewHintY, pw - 48, T.colors.muted)

    local featuresH = 154 + extraDebuffControls
    local features = b:CollapsibleSection(baseId .. "_features", LaneTitle(lane) .. " Basics", featuresH, true)
    local fw = BodyWidth(features)
    local featuresY = -44
    local colorsButton = ActionButton(features, "Open Aura Colors", 150, "normal")
    colorsButton:SetPoint("TOPLEFT", features, "TOPLEFT", 24, featuresY)
    colorsButton:SetScript("OnClick", OpenAuraColors)
    AddTooltip(colorsButton, "Aura colors", "Opens Colors > Auras for timer, stack, highlight, and pandemic colors.")
    BindStyleSwitch(features, "Show Cooldown Text", 24, featuresY - 44, fw - 48, "showCooldownText", true, "AURAS3_SHOW_COOLDOWN_TEXT")
    BindStyleSwitch(features, "Show Cooldown Swipe", 24, featuresY - 76, fw - 48, "showCooldownSwipe", true, "AURAS3_SHOW_COOLDOWN_SWIPE")
    if lane == "debuff" then
        BindStyleDropdown(features, "Dispel-type Border", 24, featuresY - 126,
            type(Model.DebuffTypeBorderModeValues) == "function" and Model.DebuffTypeBorderModeValues() or DEBUFF_TYPE_BORDER_MODE_VALUES,
            fw - 48, ReadScopeDebuffBorderMode, WriteScopeDebuffBorderMode, "AURAS3_DEBUFF_TYPE_BORDER_MODE")
    end

    local stack = b:CollapsibleSection(baseId .. "_stack", LaneTitle(lane) .. " Stack Count", 296, false)
    local sw = BodyWidth(stack)
    BindStyleSwitch(stack, "Show Stack Count", 24, -54, sw - 48, "showStackCount", true, "AURAS3_SHOW_STACKS")
    AddStyleControl(BindDropdown(ctx, stack, "Anchor", 24, -94, Model.StackAnchorValues(), sw - 48,
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
    BindStyleSlider(stack, "Text Size", 24, -152, 6, 40, 1, sw - 48, "stackTextSize", 14, 6, 40, nil, nil, "AURAS3_STACK_SIZE")
    local stackSmallW = max(120, floor((sw - 72) / 2))
    BindStyleSlider(stack, "X", 24, -212, -40, 40, 1, stackSmallW, "stackTextOffsetX", -1, -2000, 2000, nil, nil, "AURAS3_STACK_X")
    BindStyleSlider(stack, "Y", 32 + stackSmallW, -212, -40, 40, 1, stackSmallW, "stackTextOffsetY", 1, -2000, 2000, nil, nil, "AURAS3_STACK_Y")

    local cooldown = b:CollapsibleSection(baseId .. "_cooldown", LaneTitle(lane) .. " Cooldown Text", 474, true)
    local cw = BodyWidth(cooldown)
    W.Text(cooldown, "Timer font size, anchor, offset, and tooltip behavior for " .. scopeLabel .. " " .. laneName .. ".", 24, -42, cw - 48, T.colors.muted)
    BindStyleSlider(cooldown, "Text Size", 24, -82, 6, 40, 1, cw - 48, "cooldownTextSize", 14, 6, 40, nil, nil, "AURAS3_COOLDOWN_SIZE")
    BindStyleDropdown(cooldown, "Anchor", 24, -140, type(Model.AuraAnchorValues) == "function" and Model.AuraAnchorValues() or GFAnchorValues(), cw - 48, ReadScopeCooldownAnchor, WriteScopeCooldownAnchor, "AURAS3_COOLDOWN_ANCHOR")
    BindStyleSlider(cooldown, "X", 24, -198, -40, 40, 1, cw - 48, "cooldownTextOffsetX", 0, -2000, 2000, nil, nil, "AURAS3_COOLDOWN_X")
    BindStyleSlider(cooldown, "Y", 24, -258, -40, 40, 1, cw - 48, "cooldownTextOffsetY", 0, -2000, 2000, nil, nil, "AURAS3_COOLDOWN_Y")
    BindStyleSwitch(cooldown, "Show Tooltip", 24, -306, cw - 48, "showTooltip", true, "AURAS3_TOOLTIP")
    local swipeDirection = BindStyleDropdown(cooldown, "Swipe Direction", 24, -354, COOLDOWN_SWIPE_DIRECTION_VALUES, cw - 48, ReadScopeSwipeDirection, WriteScopeSwipeDirection, "AURAS3_COOLDOWN_SWIPE_DIRECTION")
    AddTooltip(swipeDirection, "Cooldown swipe direction", "Selects the Blizzard cooldown swipe direction with Cooldown:SetReverse. This only affects the swipe overlay, not icon size or position.")
    local decimal = BindStyleSlider(cooldown, "Decimals below sec", 24, -412, 0, 30, 1, cw - 48, "cooldownDecimalSeconds", 3, 0, 30, nil, nil, "AURAS3_COOLDOWN_FORMAT")
    AddTooltip(decimal, "Cooldown text format", "Remaining time below this value uses one decimal place. Timers show unitless seconds below 1 minute and unitless minutes above it. Set 0 for whole seconds only.")
    W.Text(cooldown, "Uses Blizzard DurationTextBinding; no Lua timer or OnUpdate work is added. Durations are unitless seconds below 1 minute, then unitless minutes.", 24, -456, cw - 48, T.colors.muted)

    local durationBar = b:CollapsibleSection(baseId .. "_duration_bar", LaneTitle(lane) .. " Duration Bar", 358, false)
    local dbw = BodyWidth(durationBar)
    W.Text(durationBar, "Optional native StatusBar timer for " .. scopeLabel .. " " .. laneName .. ". Driven by Blizzard's DurationBar binding.", 24, -42, dbw - 48, T.colors.muted)
    BindStyleSwitch(durationBar, "Show Duration Bar", 24, -82, dbw - 48, "showDurationBar", false, "AURAS3_DURATION_BAR")
    BindStyleSlider(durationBar, "Height", 24, -140, 1, 16, 1, dbw - 48, "durationBarHeight", 2, 1, 16, nil, nil, "AURAS3_DURATION_BAR_HEIGHT")
    BindStyleDropdown(durationBar, "Display", 24, -198,
        type(Model.DurationBarDisplayValues) == "function" and Model.DurationBarDisplayValues() or DURATION_BAR_DISPLAY_VALUES,
        dbw - 48, ReadScopeDurationBarDisplay, WriteScopeDurationBarDisplay, "AURAS3_DURATION_BAR_DISPLAY")
    BindStyleDropdown(durationBar, "Position", 24, -256,
        type(Model.DurationBarPositionValues) == "function" and Model.DurationBarPositionValues() or DURATION_BAR_POSITION_VALUES,
        dbw - 48, ReadScopeDurationBarPosition, WriteScopeDurationBarPosition, "AURAS3_DURATION_BAR_POSITION")
    BindStyleDropdown(durationBar, "Fill Mode", 24, -314,
        type(Model.DurationBarDirectionValues) == "function" and Model.DurationBarDirectionValues() or DURATION_BAR_DIRECTION_VALUES,
        dbw - 48, ReadScopeDurationBarDirection, WriteScopeDurationBarDirection, "AURAS3_DURATION_BAR_DIRECTION")

    M.TrackRefresh(ctx, function()
        local editable = unit == "shared" or not Model.UseSharedVisuals(unit)
        W.SetControlsEnabled(styleControls, editable)
        if W.SetCollapsibleBadges then
            if unit == "shared" then
                W.SetCollapsibleBadges(features, {
                    { text = "Shared baseline", kind = "info", showWhenClosed = true },
                })
            else
                W.SetCollapsibleBadges(features, {
                    { text = editable and "Override active" or "Inherited", kind = editable and "accent" or "muted", showWhenClosed = true },
                })
            end
        end
        if unit == "shared" then
            hint:SetText("Shared preview groups frames by identical icon size and swipe direction; labels show the actual frame icon size. Font family follows Global Style > Fonts.")
        else
            hint:SetText(editable and "Font family follows Global Style > Fonts. Legacy blacklists are read-only on Filters." or "This scope inherits the Shared aura style.")
        end
    end)
end
local function BuildGroupStyle(ctx, b, scope)
    local lane = CurrentLane("auraStyleGFLane", "debuff")
    local extraDebuffControls = lane == "debuff" and 64 or 0
    local laneName = LanePlural(lane)
    local refreshMiniPreview
    local function RefreshStylePreview()
        RefreshMiniAuraPreviewNow(refreshMiniPreview)
    end
    local function BodyWidth(body)
        return body and (body._msuf2Width or body.GetWidth and body:GetWidth()) or b.width or 720
    end
    local scopeLabel = ScopeLabel(scope)
    local baseId = "aura_style_group_" .. tostring(scope or "group") .. "_" .. lane

    local preview = b:Section("Group " .. LaneTitle(lane) .. " Preview", 160)
    local pw = BodyWidth(preview)
    refreshMiniPreview = select(2, BuildMiniAuraPreview(ctx, preview, scope, 24, -34, pw - 48, 118, lane))

    local features = b:CollapsibleSection(baseId .. "_features", "Group " .. LaneTitle(lane) .. " Basics", 154 + extraDebuffControls, true)
    local fw = BodyWidth(features)
    local colorsButton = ActionButton(features, "Open Aura Colors", 150, "normal")
    colorsButton:SetPoint("TOPLEFT", features, "TOPLEFT", 24, -42)
    colorsButton:SetScript("OnClick", OpenAuraColors)
    AddTooltip(colorsButton, "Aura colors", "Opens Colors > Auras for timer, stack, highlight, and pandemic colors.")
    BindGroupSwitch(ctx, features, "Show Cooldown Text", 24, -82, fw - 48, scope, lane, "showCooldown", true, "visual", RefreshStylePreview)
    BindGroupSwitch(ctx, features, "Show Cooldown Swipe", 24, -114, fw - 48, scope, lane, "showCooldownSwipe", true, "visual", RefreshStylePreview)
    if lane == "debuff" then
        BindDropdown(ctx, features, "Dispel-type Border", 24, -166,
            type(Model.DebuffTypeBorderModeValues) == "function" and Model.DebuffTypeBorderModeValues() or DEBUFF_TYPE_BORDER_MODE_VALUES,
            fw - 48,
            function() return ReadGroupDebuffTypeBorderMode(scope, lane) end,
            function(v)
                WriteGroupDebuffTypeBorderMode(scope, lane, v)
                RefreshStylePreview()
            end)
    end

    local cooldown = b:CollapsibleSection(baseId .. "_cooldown", "Group " .. LaneTitle(lane) .. " Cooldown Text", 382, true)
    local cw = BodyWidth(cooldown)
    BindGroupSlider(ctx, cooldown, "Cooldown Font", 24, -54, 6, 24, 1, cw - 48, scope, lane, "cooldownSize", 8, "font", RefreshStylePreview)
    BindGroupDropdown(ctx, cooldown, "Cooldown Anchor", 24, -112, GFAnchorValues(), cw - 48, scope, lane, "cooldownAnchor", "CENTER", "geometry", RefreshStylePreview)
    local cooldownSmallW = max(120, floor((cw - 72) / 2))
    BindGroupSlider(ctx, cooldown, "Cooldown X", 24, -170, -40, 40, 1, cooldownSmallW, scope, lane, "cooldownX", 0, "geometry", RefreshStylePreview)
    BindGroupSlider(ctx, cooldown, "Cooldown Y", 32 + cooldownSmallW, -170, -40, 40, 1, cooldownSmallW, scope, lane, "cooldownY", 0, "geometry", RefreshStylePreview)
    local groupSwipeDirection = BindDropdown(ctx, cooldown, "Swipe Direction", 24, -230, COOLDOWN_SWIPE_DIRECTION_VALUES, cw - 48,
        function()
            local group = GFReadGroup(scope, lane)
            return group.cooldownSwipeReverse == true and "REVERSE" or "NORMAL"
        end,
        function(v)
            GFWriteGroupValue(scope, lane, "cooldownSwipeReverse", v == "REVERSE", "visual")
            RefreshStylePreview()
        end)
    AddTooltip(groupSwipeDirection, "Cooldown swipe direction", "Selects the Blizzard cooldown swipe direction with Cooldown:SetReverse. This only affects the swipe overlay, not icon size or position.")
    local groupDecimal = BindGroupSlider(ctx, cooldown, "Decimals below sec", 24, -288, 0, 30, 1, cw - 48, scope, lane, "cooldownDecimalSeconds", 3, "visual", RefreshStylePreview)
    AddTooltip(groupDecimal, "Cooldown text format", "Remaining time below this value uses one decimal place. Timers show unitless seconds below 1 minute and unitless minutes above it. Set 0 for whole seconds only.")
    W.Text(cooldown, "Uses Blizzard DurationTextBinding; no Lua timer or OnUpdate work is added. Durations are unitless seconds below 1 minute, then unitless minutes.", 24, -340, cw - 48, T.colors.muted)

    local durationBar = b:CollapsibleSection(baseId .. "_duration_bar", "Group " .. LaneTitle(lane) .. " Duration Bar", 358, false)
    local dbw = BodyWidth(durationBar)
    W.Text(durationBar, "Optional native StatusBar timer for " .. scopeLabel .. " " .. laneName .. ".", 24, -42, dbw - 48, T.colors.muted)
    BindGroupSwitch(ctx, durationBar, "Show Duration Bar", 24, -82, dbw - 48, scope, lane, "showDurationBar", false, "visual", RefreshStylePreview)
    BindGroupSlider(ctx, durationBar, "Height", 24, -140, 1, 16, 1, dbw - 48, scope, lane, "durationBarHeight", 2, "visual", RefreshStylePreview)
    BindGroupDropdown(ctx, durationBar, "Display", 24, -198, DURATION_BAR_DISPLAY_VALUES, dbw - 48, scope, lane, "durationBarDisplay", "BAR_ONLY", "visual", RefreshStylePreview)
    BindGroupDropdown(ctx, durationBar, "Position", 24, -256, DURATION_BAR_POSITION_VALUES, dbw - 48, scope, lane, "durationBarPosition", "BOTTOM", "visual", RefreshStylePreview)
    BindGroupDropdown(ctx, durationBar, "Fill Mode", 24, -314, DURATION_BAR_DIRECTION_VALUES, dbw - 48, scope, lane, "durationBarDirection", "REMAINING", "visual", RefreshStylePreview)

    local stack = b:CollapsibleSection(baseId .. "_stack", "Group " .. LaneTitle(lane) .. " Stack Count", 270, false)
    local sw = BodyWidth(stack)
    BindGroupSwitch(ctx, stack, "Show Stack Count", 24, -54, sw - 48, scope, lane, "showStacks", true, "visual", RefreshStylePreview)
    BindGroupSlider(ctx, stack, "Stack Font", 24, -94, 6, 24, 1, sw - 48, scope, lane, "stackSize", 10, "font", RefreshStylePreview)
    BindGroupDropdown(ctx, stack, "Stack Anchor", 24, -152, GFAnchorValues(), sw - 48, scope, lane, "stackAnchor", "BOTTOMRIGHT", "geometry", RefreshStylePreview)
    local stackSmallW = max(120, floor((sw - 72) / 2))
    BindGroupSlider(ctx, stack, "Stack X", 24, -210, -40, 40, 1, stackSmallW, scope, lane, "stackX", 0, "geometry", RefreshStylePreview)
    BindGroupSlider(ctx, stack, "Stack Y", 32 + stackSmallW, -210, -40, 40, 1, stackSmallW, scope, lane, "stackY", 0, "geometry", RefreshStylePreview)

    local behavior = b:CollapsibleSection(baseId .. "_behavior", "Group " .. LaneTitle(lane) .. " Behavior", 252, false)
    local bw = BodyWidth(behavior)
    W.Text(behavior, "Shared group-frame aura behavior for " .. scopeLabel .. ".", 24, -42, bw - 48, T.colors.muted)
    BindGroupRootSwitch(ctx, behavior, "Show Tooltip", 24, -82, bw - 48, scope, "showTooltip", true, "visual")
    BindGroupRootSwitch(ctx, behavior, "Sort by Duration", 24, -114, bw - 48, scope, "sortByDuration", false, "visual")
    BindGroupRootSwitch(ctx, behavior, "Prefer Player Auras", 24, -146, bw - 48, scope, "preferPlayer", false, "visual")
    BindGroupRootSwitch(ctx, behavior, "Dynamic Icon Scale", 24, -178, bw - 48, scope, "dynamicScale", false, "geometry", RefreshStylePreview)
    BindGroupConfSwitch(ctx, behavior, "Cooldown darkens on loss", 24, -220, bw - 48, scope, "cooldownSwipeDarkenOnLoss", false, "visual", RefreshStylePreview)
end
local function BuildAuraStylePage(ctx)
    local b = W.PageBuilder(ctx)
    Model.EnsureDB()
    b:GlobalStyleHeader("Aura Style", "Text, cooldown, stack and marker styling.", 72)
    local scope = BuildAuraStyleScopeOverrideSection(ctx, b)
    BuildAuraStyleNav(ctx, b)
    if IsGroupScope(scope) then
        BuildGroupStyle(ctx, b, scope)
    else
        BuildUnitStyle(ctx, b, scope)
    end
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
    local enableFilters = BindSwitch(ctx, section, "Enable Filters", 24, -48, 180,
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
    local function FilterToggle(label, key, x, y, tip, conflicts)
        local widget = BindSwitch(ctx, card, label, x, y, colW - 32,
            function() return Model.ReadFilter(scope, lane, key, false) == true end,
            function(v)
                local didConflict = false
                if v == true and type(conflicts) == "table" then
                    for i = 1, #conflicts do
                        Model.WriteFilter(scope, lane, conflicts[i], false)
                        didConflict = true
                    end
                end
                Model.WriteFilter(scope, lane, key, v)
                ApplyUnit(ctx, scope, "AURAS3_FILTER_" .. lane .. "_" .. key, true)
                if didConflict then QueueAurasPageRefresh(ctx, "auras-filter-conflict") end
            end)
        AddTooltip(widget, label, tip or "")
        filterControls[#filterControls + 1] = widget
        return widget
    end
    W.LabelAt(card, "Native Filter Tokens", 16, -70, colW, "GameFontNormalSmall", T.colors.accent)
    local filterSpecs = lane == "buff" and {
        { "Player", "onlyMine", 1, 1, "Auras applied by the player." },
        { "Raid", "raid", 1, 2, "Raid-useful public Buffs." },
        { "Raid In Combat", "raidInCombat", 1, 3, "Buffs Blizzard flags for raid frames while in combat." },
        { "Include Nameplate-only", "includeNameplateOnly", 1, 4, "Also include Buffs Blizzard marks as nameplate-only." },
        { "External Defensive", "externalDefensive", 2, 1, "External defensive Buffs from Blizzard's native filter." },
        { "Big Defensive", "bigDefensive", 2, 2, "Major defensive Buffs from Blizzard's native filter." },
        { "Cancelable", "cancelable", 2, 3, "Buffs that can be cancelled.", { "notCancelable" } },
        { "Not Cancelable", "notCancelable", 2, 4, "Buffs that cannot be cancelled.", { "cancelable" } },
    } or {
        { "Player", "onlyMine", 1, 1, "Debuffs applied by the player." },
        { "Raid", "raid", 1, 2, "Raid and encounter Debuffs." },
        { "Raid In Combat", "raidInCombat", 1, 3, "Debuffs Blizzard flags for raid frames while in combat." },
        { "Include Nameplate-only", "includeNameplateOnly", 1, 4, "Also include Debuffs Blizzard marks as nameplate-only." },
        { "Dispellable", "includeDispellable", 2, 1, "Debuffs Blizzard marks as dispellable by the player." },
        { "Crowd Control", "crowdControl", 2, 2, "Crowd-control Debuffs from Blizzard's native filter." },
    }
    M.BuildControlSpecs(filterSpecs, {
        ["*"] = function(s) return FilterToggle(s[1], s[2], s[3] == 2 and rightX or 16, -100 - ((s[4] - 1) * 34), s[5], s[6]) end,
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
    local filter = Card(section, "Native " .. laneText .. " Filter", "Filter token for " .. ScopeLabel(scope) .. " group-frame " .. laneText .. "s.", 24, -42, filterW, 234)
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
    Model.EnsureDB()
    b:GlobalStyleHeader("Aura Filters", "Native 12.1 Buff and Debuff filters; legacy whitelist/blacklist data is read-only.", 72)
    local scope = BuildAuraFilterScopeOverrideSection(ctx, b)
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
M.RegisterPage("auras3_buffs", { title = "MSUF Aura Buffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "buff") end, version = 10 })
M.RegisterPage("auras3_debuffs", { title = "MSUF Aura Debuffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "debuff") end, version = 10 })
M.RegisterPage("auras3_styling", { title = "MSUF Aura Style", build = BuildAuraStylePage, version = 31 })
M.RegisterPage("auras3_filters", { title = "MSUF Aura Filters", build = BuildAuraFiltersPage, version = 22 })
