local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local A3 = MSUF.MSUF_Auras3 or _G.MSUF_Auras3
local Model = A3 and A3.MenuModel

if type(W) ~= "table" or type(T) ~= "table" or type(Model) ~= "table" then return end

local CreateFrame = _G.CreateFrame
local GameTooltip = _G.GameTooltip
local MSUF_SetIconTexture = _G.MSUF_SetIconTexture
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local tonumber, tostring, type, ipairs, pairs = tonumber, tostring, type, ipairs, pairs

local UNIT_ROWS = {
    { unit = "player", label = "Player" },
    { unit = "target", label = "Target" },
    { unit = "focus", label = "Focus" },
    { unit = "boss", label = "Boss" },
}

local GROUP_ROWS = {
    { scope = "party", label = "Party" },
    { scope = "raid", label = "Raid / Mythic" },
}

local AURA_SCOPE_VALUES = {
    { value = "shared", text = "Shared" },
    { value = "player", text = "Player" },
    { value = "target", text = "Target" },
    { value = "focus", text = "Focus" },
    { value = "boss", text = "Boss" },
    { value = "party", text = "Party" },
    { value = "raid", text = "Raid / Mythic" },
}

local LANE_VALUES = {
    { value = "buff", text = "Buffs" },
    { value = "debuff", text = "Debuffs" },
}

local BUFF_EXCLUSIVE = {
    { value = "none", text = "None" },
    { value = "important", text = "Important" },
}

local DEBUFF_EXCLUSIVE = {
    { value = "none", text = "None" },
    { value = "important", text = "Important" },
    { value = "raid", text = "Raid" },
    { value = "all", text = "All" },
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

local function BadgeNumber(value)
    value = Round(value)
    return tostring(value)
end

local function AddTooltip(widget, title, body)
    if type(M.AddTooltip) == "function" then
        return M.AddTooltip(widget, title, body, { hook = true, titleAsLine = true })
    end
    if not (widget and widget.SetScript) then return widget end
    widget:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Tr(title or ""), 1, 1, 1)
        if body and body ~= "" then GameTooltip:AddLine(Tr(body), 0.75, 0.78, 0.86, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return widget
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
    if card and T.ApplyBackdrop then
        T.ApplyBackdrop(card, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
    end
    return card
end

local function Rebuild(ctx)
    local key = (ctx and ctx.key) or M.activeKey or "auras3"
    if M.InvalidatePage and M.SelectPage and M.frame and M.frame.IsShown and M.frame:IsShown() then
        M.InvalidatePage(key)
        M.activeKey = nil
        M.SelectPage(key)
    elseif M.Refresh then
        M.Refresh(ctx)
    end
end

local function SelectPage(pageKey, scope)
    if scope then
        if type(M.PersistMenuStateValue) == "function" then
            M.PersistMenuStateValue("auraScope", scope)
            if scope == "party" or scope == "raid" then M.PersistMenuStateValue("auraStyleGFScope", scope) end
        else
            M.auraScope = scope
            if scope == "party" or scope == "raid" then M.auraStyleGFScope = scope end
        end
    end
    if M.SelectPage then M.SelectPage(pageKey or "auras3") end
end

local function ApplyUnit(ctx, unit, reason, refresh)
    Model.Apply(unit, reason or "AURAS3_MENU2")
    if refresh and M.Refresh then M.Refresh(ctx) end
end

local function BindSwitch(ctx, parent, label, x, y, width, getValue, setValue)
    local widget = W.SwitchAt(parent, label, x, y, width or 180)
    M.BindToggle(ctx, widget,
        function() return getValue() and true or false end,
        function(v) setValue(v and true or false) end)
    return widget
end

local function BindToggle(ctx, parent, label, x, y, width, getValue, setValue)
    local widget = W.ToggleAt(parent, label, x, y, width or 180)
    M.BindToggle(ctx, widget,
        function() return getValue() and true or false end,
        function(v) setValue(v and true or false) end)
    return widget
end

local function BindSlider(ctx, parent, label, x, y, minVal, maxVal, step, width, getValue, setValue)
    local widget = W.Slider(parent, label, minVal, maxVal, step, width)
    W.MoveWidget(widget, parent, x, y, width)
    M.BindSlider(ctx, widget,
        function() return tonumber(getValue()) or 0 end,
        function(v) setValue(v) end)
    return widget
end

local function BindDropdown(ctx, parent, label, x, y, values, width, getValue, setValue)
    local widget = W.Dropdown(parent, label, values, width)
    W.MoveWidget(widget, parent, x, y, width)
    M.BindDropdown(ctx, widget,
        function() return getValue() end,
        function(v) setValue(v) end)
    return widget
end

local function BindTextInput(ctx, parent, label, x, y, width, getValue, setValue)
    local widget = W.TextInput(parent, label, width)
    W.MoveWidget(widget, parent, x, y, width)
    M.BindTextInput(ctx, widget,
        function() return getValue() or "" end,
        function(v) setValue(v or "") end)
    return widget
end

local function BindColor(ctx, parent, label, x, y, getRGB, setRGB)
    local widget = W.Color(parent, label)
    W.MoveWidget(widget, parent, x, y)
    M.BindColor(ctx, widget, getRGB, setRGB)
    return widget
end

local function CurrentScope()
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    local scope = M.auraScope or "shared"
    if scope == "mythicraid" then scope = "raid" end
    if scope ~= "shared" and scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" and scope ~= "party" and scope ~= "raid" then
        scope = "shared"
    end
    return scope
end

local function SetCurrentScope(scope)
    scope = scope or "shared"
    if scope == "mythicraid" then scope = "raid" end
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("auraScope", scope)
        if scope == "party" or scope == "raid" then M.PersistMenuStateValue("auraStyleGFScope", scope) end
    else
        M.auraScope = scope
        if scope == "party" or scope == "raid" then M.auraStyleGFScope = scope end
    end
end

local function IsGroupScope(scope)
    scope = scope or CurrentScope()
    return scope == "party" or scope == "raid" or scope == "mythicraid"
end

local function ScopeLabel(scope)
    if scope == "shared" then return "Shared" end
    if scope == "player" then return "Player" end
    if scope == "target" then return "Target" end
    if scope == "focus" then return "Focus" end
    if scope == "boss" then return "Boss" end
    if scope == "party" then return "Party" end
    return "Raid / Mythic"
end

local function BuildScopeTabs(ctx, section, x, y, width)
    local gap = 6
    local count = #AURA_SCOPE_VALUES
    local bw = max(54, floor(((width or 720) - gap * (count - 1)) / count))
    local buttons = {}
    for i = 1, count do
        local item = AURA_SCOPE_VALUES[i]
        local btn = ActionButton(section, item.text, bw)
        btn:SetPoint("TOPLEFT", section, "TOPLEFT", x + (i - 1) * (bw + gap), y)
        btn:SetScript("OnClick", function()
            SetCurrentScope(item.value)
            Rebuild(ctx)
        end)
        buttons[i] = btn
    end
    M.AddRefresher(ctx, function()
        local current = CurrentScope()
        for i = 1, count do
            if buttons[i].SetActive then buttons[i]:SetActive(AURA_SCOPE_VALUES[i].value == current) end
        end
    end)
    return CurrentScope()
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
    if type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue(stateKey, lane)
        if stateKey ~= "auraStyleGFLane" then M.PersistMenuStateValue("auraStyleGFLane", lane) end
    else
        M[stateKey] = lane
        if stateKey ~= "auraStyleGFLane" then M.auraStyleGFLane = lane end
    end
end

local function BuildLaneTabs(ctx, parent, stateKey, x, y, width)
    local gap = 6
    local bw = floor(((width or 260) - gap) / 2)
    local buttons = {}
    for i = 1, #LANE_VALUES do
        local item = LANE_VALUES[i]
        local btn = ActionButton(parent, item.text, bw)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (bw + gap), y)
        btn:SetScript("OnClick", function()
            SetCurrentLane(stateKey, item.value)
            Rebuild(ctx)
        end)
        buttons[i] = btn
    end
    M.AddRefresher(ctx, function()
        local lane = CurrentLane(stateKey, "debuff")
        for i = 1, #LANE_VALUES do
            if buttons[i].SetActive then buttons[i]:SetActive(LANE_VALUES[i].value == lane) end
        end
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
    if T.ApplyMaterial then T.ApplyMaterial(section, "card") elseif T.ApplyGlass then T.ApplyGlass(section, "card") end
    section:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    section:SetSize(b.width, h)
    section._msuf2Width = b.width

    b.y = b.y - h - 12
    if ctx and ctx.SetContentHeight then ctx:SetContentHeight(abs(b.y) + 28) end

    local w = section._msuf2Width or b.width or 720
    local navW = min(460, w - 32)
    local gap = 8
    local bw = floor((navW - gap) / 2)
    local buttons = {}

    local function NavButton(kind, x)
        local btn = T.Button(section, LanePlural(kind), bw, 24)
        if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
        btn:SetPoint("TOPLEFT", section, "TOPLEFT", x, -15)
        btn:SetScript("OnClick", function()
            SetCurrentLane("auraStyleGFLane", kind)
            local key = (ctx and ctx.key) or M.activeKey
            if key == "auras3_buffs" or key == "auras3_debuffs" then
                SelectPage("auras3_styling", CurrentScope())
            else
                Rebuild(ctx)
            end
        end)
        buttons[kind] = btn
        return btn
    end

    NavButton("buff", 16)
    NavButton("debuff", 16 + bw + gap)

    M.AddRefresher(ctx, function()
        local lane = CurrentLane("auraStyleGFLane", "debuff")
        if buttons.buff and buttons.buff.SetActive then buttons.buff:SetActive(lane == "buff") end
        if buttons.debuff and buttons.debuff.SetActive then buttons.debuff:SetActive(lane == "debuff") end
    end)
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
        if not Model.GroupShown(unit, OtherLane(kind)) then
            Model.SetUnitEnabled(unit, false)
        end
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
    if type(GP.QueueGF) == "function" then
        GP.QueueGF(a, mode or "visual")
        if b then GP.QueueGF(b, mode or "visual") end
    end
    RefreshGFPreview()
end

local function GFAurasRoot(kind)
    local conf = GroupConf(kind)
    conf.auras = conf.auras or {}
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

local function GFNativeKeyForGroup(groupKey)
    return groupKey == "buff" and "buffs" or "debuffs"
end

local function GFReadBlizzardType(scope, nativeKey, defaultValue)
    local gf = GF()
    if gf and type(gf.IsBlizzardAuraTypeEnabled) == "function" then
        local kind = GroupScopeKinds(scope)
        return gf.IsBlizzardAuraTypeEnabled(GroupConf(kind), nativeKey) == true
    end
    local root = GFReadRoot(scope)
    if (root.renderer or "BLIZZARD") == "CUSTOM" then return false end
    local types = root.blizzardTypes
    if type(types) ~= "table" or types[nativeKey] == nil then return defaultValue and true or false end
    return types[nativeKey] == true
end

local function GFWriteBlizzardType(scope, nativeKey, value)
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local root = GFAurasRoot(kind)
        root.blizzardTypes = root.blizzardTypes or {}
        local nextValue = value and true or false
        if root.blizzardTypes[nativeKey] == nextValue then return end
        root.blizzardTypes[nativeKey] = nextValue
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then QueueGroupScope(scope, "rebuild") end
end

local function GFWriteGroupValue(scope, groupKey, key, value, mode)
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local group = GFAuraGroup(kind, groupKey)
        if group[key] == value then return end
        group[key] = value
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then QueueGroupScope(scope, mode or "visual") end
end

local function GFWriteRootValue(scope, key, value, mode)
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local root = GFAurasRoot(kind)
        if root[key] == value then return end
        root[key] = value
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then QueueGroupScope(scope, mode or "visual") end
end

local function GFWriteConfValue(scope, key, value, mode)
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local conf = GroupConf(kind)
        if conf[key] == value then return end
        conf[key] = value
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then QueueGroupScope(scope, mode or "visual") end
end

local function GroupLaneShown(scope, groupKey)
    if GFReadBlizzardType(scope, GFNativeKeyForGroup(groupKey), true) then return true end
    local root = GFReadRoot(scope)
    local group = GFReadGroup(scope, groupKey)
    return root.enabled ~= false and group.enabled ~= false
end

local function SetGroupLaneShown(scope, groupKey, shown)
    shown = shown and true or false
    if shown then GFWriteRootValue(scope, "enabled", true, "visual") end
    GFWriteGroupValue(scope, groupKey, "enabled", shown, "visual")
    GFWriteBlizzardType(scope, GFNativeKeyForGroup(groupKey), shown)
end

local function AuraFilter()
    local gf = GF()
    return (gf and gf.AuraFilter) or _G.MSUF_GF_AuraFilter
end

local function GroupFilterValues(groupKey)
    local af = AuraFilter()
    local source = groupKey == "debuff" and af and af.DEBUFF_FILTER_ITEMS or af and af.BUFF_FILTER_ITEMS
    local out = {}
    if type(source) == "table" then
        for i = 1, #source do
            local item = source[i]
            if item then
                out[#out + 1] = {
                    value = item.value or item.key,
                    text = item.text or item.label or tostring(item.value or item.key or ""),
                }
            end
        end
    end
    if #out > 0 then return out end
    if groupKey == "buff" then
        return {
            { value = "ALL", text = "All Buffs" },
            { value = "PLAYER", text = "My Buffs Only" },
            { value = "RAID", text = "Raid Buffs" },
            { value = "IMPORTANT", text = "Important" },
        }
    end
    return {
        { value = "ALL", text = "All Debuffs" },
        { value = "PLAYER", text = "My Debuffs Only" },
        { value = "RAID", text = "Boss / Raid" },
        { value = "DISPELLABLE", text = "Dispellable" },
        { value = "IMPORTANT", text = "Important" },
    }
end

local function GFAnchorValues()
    local values = GP.STATUS_ICON_ANCHORS or GP.AURA_ANCHORS
    if type(values) == "table" and #values > 0 then return values end
    return {
        { value = "CENTER", text = "Center" },
        { value = "TOPLEFT", text = "Top Left" },
        { value = "TOPRIGHT", text = "Top Right" },
        { value = "BOTTOMLEFT", text = "Bottom Left" },
        { value = "BOTTOMRIGHT", text = "Bottom Right" },
    }
end

local function BindGroupSwitch(ctx, parent, label, x, y, width, scope, groupKey, key, defaultValue, mode)
    return BindSwitch(ctx, parent, label, x, y, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            local value = group[key]
            if value == nil then value = defaultValue end
            return value and true or false
        end,
        function(v) GFWriteGroupValue(scope, groupKey, key, v and true or false, mode or "visual") end)
end

local function BindGroupRootSwitch(ctx, parent, label, x, y, width, scope, key, defaultValue, mode)
    return BindSwitch(ctx, parent, label, x, y, width,
        function()
            local root = GFReadRoot(scope)
            local value = root[key]
            if value == nil then value = defaultValue end
            return value and true or false
        end,
        function(v) GFWriteRootValue(scope, key, v and true or false, mode or "visual") end)
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

local function BindGroupSlider(ctx, parent, label, x, y, minVal, maxVal, step, width, scope, groupKey, key, defaultValue, mode)
    return BindSlider(ctx, parent, label, x, y, minVal, maxVal, step, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            return tonumber(group[key]) or defaultValue or 0
        end,
        function(v)
            v = Round(v)
            GFWriteGroupValue(scope, groupKey, key, v, mode or "visual")
        end)
end

local function BindGroupDropdown(ctx, parent, label, x, y, values, width, scope, groupKey, key, defaultValue, mode)
    return BindDropdown(ctx, parent, label, x, y, values, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            return group[key] or defaultValue
        end,
        function(v) GFWriteGroupValue(scope, groupKey, key, v or defaultValue, mode or "visual") end)
end

local function RequestAuraTextRefresh()
    if type(_G.MSUF_A3_InvalidateCooldownTextCurve) == "function" then _G.MSUF_A3_InvalidateCooldownTextCurve() end
    if type(_G.MSUF_A3_ForceCooldownTextRecolor) == "function" then _G.MSUF_A3_ForceCooldownTextRecolor() end
    if type(_G.MSUF_GF_InvalidateCooldownTextCurve) == "function" then _G.MSUF_GF_InvalidateCooldownTextCurve() end
    if type(_G.MSUF_GF_ForceCooldownTextRecolor) == "function" then _G.MSUF_GF_ForceCooldownTextRecolor() end
    QueueGroupScope("party", "visual")
    QueueGroupScope("raid", "visual")
    Model.Apply("shared", "AURAS3_TEXT_REFRESH")
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
    f.edge = {}
    for i = 1, 4 do
        f.edge[i] = f:CreateTexture(nil, "OVERLAY")
        f.edge[i]:SetTexture(TEX_W8)
    end
    f.edge[1]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); f.edge[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); f.edge[1]:SetHeight(1)
    f.edge[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); f.edge[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); f.edge[2]:SetHeight(1)
    f.edge[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); f.edge[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); f.edge[3]:SetWidth(1)
    f.edge[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); f.edge[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); f.edge[4]:SetWidth(1)
    f.stack = f:CreateFontString(nil, "OVERLAY")
    f.stack:SetFont(FONT, 9, "OUTLINE")
    f.stack:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    f.timer = f:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont(FONT, 8, "OUTLINE")
    f.timer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 1)
    return f
end

local function BuildMiniAuraPreview(ctx, parent, scope, x, y, width, height, lane)
    lane = lane == "buff" and "buff" or (lane == "debuff" and "debuff" or nil)
    local box = T.Panel(parent, nil, { 0.010, 0.016, 0.034, 0.88 }, T.colors.borderSoft)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width or 300, height or 104)
    W.LabelAt(box, "Preview", 10, -10, 100, "GameFontNormalSmall", T.colors.text)
    local icons = {}
    for i = 1, 14 do icons[i] = CreateAuraPreviewIcon(box) end
    local buffTex = { 135987, 136116, 135932, 136085, 132333, 135981, 136048 }
    local debuffTex = { 136118, 136139, 136197, 135817, 132851, 136188, 136170 }
    M.AddRefresher(ctx, function()
        local readScope = IsGroupScope(scope) and "shared" or (scope or "shared")
        local size = min(28, max(18, Model.ReadNumber(readScope, "iconSize", 26, 10, 64)))
        local spacing = min(5, max(1, Model.ReadNumber(readScope, "spacing", 2, 0, 12)))
        local count = min(14, max(4, Model.ReadNumber(readScope, "perRow", 12, 1, 40)))
        local showStacks
        local showTimers
        local stackSize
        local cooldownSize
        if type(Model.ReadBool) == "function" then
            if lane and type(Model.ReadLaneStyleBool) == "function" then
                showStacks = Model.ReadLaneStyleBool(readScope, lane, "showStackCount", true)
                showTimers = Model.ReadLaneStyleBool(readScope, lane, "showCooldownText", true)
            else
                showStacks = Model.ReadBool(readScope, "showStackCount", true)
                showTimers = Model.ReadBool(readScope, "showCooldownText", true)
            end
        else
            showStacks = Model.ReadSharedBool("showStackCount", true)
            showTimers = Model.ReadSharedBool("showCooldownText", true)
        end
        if lane and type(Model.ReadLaneStyleNumber) == "function" then
            stackSize = min(14, max(7, Model.ReadLaneStyleNumber(readScope, lane, "stackTextSize", 14, 6, 40)))
            cooldownSize = min(14, max(7, Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextSize", 14, 6, 40)))
        else
            stackSize = min(14, max(7, Model.ReadNumber(readScope, "stackTextSize", 14, 6, 40)))
            cooldownSize = min(14, max(7, Model.ReadNumber(readScope, "cooldownTextSize", 14, 6, 40)))
        end
        for i = 1, #icons do
            local icon = icons[i]
            if i <= count then
                local col = (i - 1) % 7
                local row = floor((i - 1) / 7)
                icon:SetSize(size, size)
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", box, "TOPLEFT", 10 + col * (size + spacing), -34 - row * (size + spacing))
                local isBuffIcon = lane and lane == "buff" or (not lane and i <= 7)
                local tex = isBuffIcon and buffTex or debuffTex
                icon.icon:SetTexture(tex[((i - 1) % #tex) + 1])
                local r, g, b = isBuffIcon and 0.20 or 0.78, isBuffIcon and 0.72 or 0.20, isBuffIcon and 0.42 or 0.24
                for e = 1, 4 do icon.edge[e]:SetVertexColor(r, g, b, 0.95) end
                if icon.stack.SetFont then icon.stack:SetFont(FONT, stackSize, "OUTLINE") end
                if icon.timer.SetFont then icon.timer:SetFont(FONT, cooldownSize, "OUTLINE") end
                icon.stack:SetText(showStacks and (i % 3 == 1 and "2" or "") or "")
                icon.timer:SetText(showTimers and (i % 2 == 0 and "12" or "") or "")
                icon:Show()
            else
                icon:Hide()
            end
        end
    end)
    return box
end

local function BuildUnitStyle(ctx, b, scope)
    local unit = scope == "shared" and "shared" or scope
    local lane = CurrentLane("auraStyleGFLane", "debuff")
    local laneName = LanePlural(lane)
    local section = b:Section("Unit Aura " .. LaneTitle(lane) .. " Style", 510)
    local w = section._msuf2Width or b.width or 720
    local colW = max(300, floor((w - 66) / 2))
    local rightX = 32 + colW + 18
    local rightW = max(260, w - rightX - 24)
    local styleControls = {}
    local topY = -42

    local useShared
    if unit ~= "shared" then
        useShared = BindSwitch(ctx, section, "Use Shared Style", 24, -40, 220,
            function() return Model.UseSharedVisuals(unit) end,
            function(v)
                Model.SetUseSharedVisuals(unit, v)
                ApplyUnit(ctx, unit, "AURAS3_STYLE_INHERIT", true)
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

    local text = Card(section, laneName .. " Text Features", "Stack-count and cooldown text for " .. ScopeLabel(scope) .. " " .. laneName .. ".", 24, topY, colW, 388)
    styleControls[#styleControls + 1] = BindSwitch(ctx, text, "Show Stack Count", 16, -66, colW - 32,
        function() return ReadScopeBool("showStackCount", true) end,
        function(v)
            WriteScopeBool("showStackCount", v)
            ApplyUnit(ctx, unit, "AURAS3_SHOW_STACKS", true)
        end)
    styleControls[#styleControls + 1] = BindSwitch(ctx, text, "Show Cooldown Text", 16, -98, colW - 32,
        function() return ReadScopeBool("showCooldownText", true) end,
        function(v)
            WriteScopeBool("showCooldownText", v)
            ApplyUnit(ctx, unit, "AURAS3_SHOW_COOLDOWN_TEXT", true)
        end)
    styleControls[#styleControls + 1] = BindSwitch(ctx, text, "Show Cooldown Swipe", 16, -130, colW - 32,
        function() return ReadScopeBool("showCooldownSwipe", true) end,
        function(v)
            WriteScopeBool("showCooldownSwipe", v)
            ApplyUnit(ctx, unit, "AURAS3_SHOW_COOLDOWN_SWIPE", true)
        end)

    W.LabelAt(text, "Stack Count", 16, -178, colW - 32, "GameFontNormalSmall", T.colors.accent)
    styleControls[#styleControls + 1] = BindDropdown(ctx, text, "Anchor", 16, -214, Model.StackAnchorValues(), colW - 32,
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
        end)
    styleControls[#styleControls + 1] = BindSlider(ctx, text, "Text Size", 16, -272, 6, 40, 1, colW - 32,
        function() return ReadScopeNumber("stackTextSize", 14, 6, 40) end,
        function(v)
            WriteScopeNumber("stackTextSize", v, 6, 40)
            ApplyUnit(ctx, unit, "AURAS3_STACK_SIZE")
        end)
    local smallW = max(120, floor((colW - 44) / 2))
    styleControls[#styleControls + 1] = BindSlider(ctx, text, "X", 16, -332, -40, 40, 1, smallW,
        function() return ReadScopeNumber("stackTextOffsetX", -1, -2000, 2000) end,
        function(v)
            WriteScopeNumber("stackTextOffsetX", v, -2000, 2000)
            ApplyUnit(ctx, unit, "AURAS3_STACK_X")
        end)
    styleControls[#styleControls + 1] = BindSlider(ctx, text, "Y", 24 + smallW, -332, -40, 40, 1, smallW,
        function() return ReadScopeNumber("stackTextOffsetY", 1, -2000, 2000) end,
        function(v)
            WriteScopeNumber("stackTextOffsetY", v, -2000, 2000)
            ApplyUnit(ctx, unit, "AURAS3_STACK_Y")
        end)

    local cooldown = Card(section, laneName .. " Cooldown Text", "Timer font size and center offset for " .. ScopeLabel(scope) .. " " .. laneName .. ".", rightX, topY, rightW, 268)
    styleControls[#styleControls + 1] = BindSlider(ctx, cooldown, "Text Size", 16, -62, 6, 40, 1, rightW - 32,
        function() return ReadScopeNumber("cooldownTextSize", 14, 6, 40) end,
        function(v)
            WriteScopeNumber("cooldownTextSize", v, 6, 40)
            ApplyUnit(ctx, unit, "AURAS3_COOLDOWN_SIZE")
        end)
    styleControls[#styleControls + 1] = BindSlider(ctx, cooldown, "X", 16, -122, -40, 40, 1, rightW - 32,
        function() return ReadScopeNumber("cooldownTextOffsetX", 0, -2000, 2000) end,
        function(v)
            WriteScopeNumber("cooldownTextOffsetX", v, -2000, 2000)
            ApplyUnit(ctx, unit, "AURAS3_COOLDOWN_X")
        end)
    styleControls[#styleControls + 1] = BindSlider(ctx, cooldown, "Y", 16, -182, -40, 40, 1, rightW - 32,
        function() return ReadScopeNumber("cooldownTextOffsetY", 0, -2000, 2000) end,
        function(v)
            WriteScopeNumber("cooldownTextOffsetY", v, -2000, 2000)
            ApplyUnit(ctx, unit, "AURAS3_COOLDOWN_Y")
        end)

    BuildMiniAuraPreview(ctx, section, unit, rightX, topY - 292, rightW, 118, lane)
    local hint = W.Text(section, "", 24, topY - 424, w - 48, T.colors.muted)
    M.AddRefresher(ctx, function()
        local editable = unit == "shared" or not Model.UseSharedVisuals(unit)
        W.SetControlsEnabled(styleControls, editable)
        if useShared then W.SetControlEnabled(useShared, true) end
        hint:SetText(editable and "Font family follows Global Style > Fonts. Filters and blacklists live on Filters." or "This scope inherits the Shared aura style.")
    end)
end

local function BuildGroupStyle(ctx, b, scope)
    local section = b:Section("Group Aura Style", 548)
    local w = section._msuf2Width or b.width or 720
    local lane = CurrentLane("auraStyleGFLane", "debuff")
    local laneName = LanePlural(lane)
    local colW = max(300, floor((w - 66) / 2))
    local rightX = 32 + colW + 18
    local rightW = max(260, w - rightX - 24)

    local text = Card(section, "Group Aura " .. LaneTitle(lane) .. " Text", "Cooldown and stack text for " .. ScopeLabel(scope) .. " " .. laneName .. ".", 24, -42, colW, 374)

    BindGroupSwitch(ctx, text, "Show Cooldown Swipe", 16, -78, colW - 32, scope, lane, "showCooldownSwipe", true, "visual")
    BindGroupSwitch(ctx, text, "Show Cooldown Text", 16, -110, colW - 32, scope, lane, "showCooldown", true, "visual")
    BindGroupSwitch(ctx, text, "Show Stack Count", 16, -142, colW - 32, scope, lane, "showStacks", true, "visual")
    BindGroupSlider(ctx, text, "Cooldown Font", 16, -198, 6, 24, 1, colW - 32, scope, lane, "cooldownSize", 8, "font")
    BindGroupDropdown(ctx, text, "Cooldown Anchor", 16, -256, GFAnchorValues(), colW - 32, scope, lane, "cooldownAnchor", "CENTER", "geometry")
    BindGroupSlider(ctx, text, "Stack Font", 16, -314, 6, 24, 1, colW - 32, scope, lane, "stackSize", 10, "font")

    local behavior = Card(section, "Behavior", "Shared group-frame aura behavior for " .. ScopeLabel(scope) .. ".", rightX, -42, rightW, 306)
    BindGroupRootSwitch(ctx, behavior, "Show Tooltip", 16, -64, rightW - 32, scope, "showTooltip", true, "visual")
    BindGroupRootSwitch(ctx, behavior, "Sort by Duration", 16, -96, rightW - 32, scope, "sortByDuration", false, "visual")
    BindGroupRootSwitch(ctx, behavior, "Prefer Player Auras", 16, -128, rightW - 32, scope, "preferPlayer", true, "visual")
    BindGroupRootSwitch(ctx, behavior, "Dynamic Icon Scale", 16, -160, rightW - 32, scope, "dynamicScale", false, "geometry")
    BindGroupConfSwitch(ctx, behavior, "Cooldown darkens on loss", 16, -202, rightW - 32, scope, "cooldownSwipeDarkenOnLoss", false, "visual")
    BindGroupConfSwitch(ctx, behavior, "Masque skin", 16, -234, rightW - 32, scope, "masqueEnabled", false, "visual", function()
        local gf = GF()
        if gf and gf.Masque and type(gf.Masque.ReskinAllIcons) == "function" then gf.Masque.ReskinAllIcons() end
    end)

    BuildMiniAuraPreview(ctx, section, scope, rightX, -404, rightW, 92)
end

local function BuildSharedColors(ctx, b)
    local section = b:Section("Shared Aura Colors", 438)
    local w = section._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 58) / 2))
    local rightX = 24 + colW + 18
    local cooldown = Card(section, "Cooldown Timer Colors", nil, 24, -42, colW, 338)
    local markers = Card(section, "Stack & Highlights", nil, rightX, -42, colW, 338)

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
        local buckets = Model.ReadGeneralBool("aurasCooldownTextUseBuckets", true)
        samples[1]:SetTextColor(sr, sg, sb, 1)
        samples[2]:SetTextColor(buckets and wr or sr, buckets and wg or sg, buckets and wb or sb, 1)
        samples[3]:SetTextColor(buckets and ur or sr, buckets and ug or sg, buckets and ub or sb, 1)
    end

    BindSwitch(ctx, cooldown, "Color by time", 16, -166, colW - 32,
        function() return Model.ReadGeneralBool("aurasCooldownTextUseBuckets", true) end,
        function(v)
            Model.WriteGeneralBool("aurasCooldownTextUseBuckets", v)
            RefreshColorSamples()
            RequestAuraTextRefresh()
        end)
    BindColor(ctx, cooldown, "Safe", 16, -210,
        function() return Model.ReadGeneralColor("aurasCooldownTextSafeColor", 1, 1, 1) end,
        function(r, g, bcol)
            Model.WriteGeneralColor("aurasCooldownTextSafeColor", r, g, bcol)
            RefreshColorSamples()
            RequestAuraTextRefresh()
        end)
    BindColor(ctx, cooldown, "Warning", 16, -248,
        function() return Model.ReadGeneralColor("aurasCooldownTextWarningColor", 1, 0.85, 0.20) end,
        function(r, g, bcol)
            Model.WriteGeneralColor("aurasCooldownTextWarningColor", r, g, bcol)
            RefreshColorSamples()
            RequestAuraTextRefresh()
        end)
    BindColor(ctx, cooldown, "Urgent", 16, -286,
        function() return Model.ReadGeneralColor("aurasCooldownTextUrgentColor", 1, 0.55, 0.10) end,
        function(r, g, bcol)
            Model.WriteGeneralColor("aurasCooldownTextUrgentColor", r, g, bcol)
            RefreshColorSamples()
            RequestAuraTextRefresh()
        end)

    BindColor(ctx, markers, "Stack Count", 16, -62,
        function() return Model.ReadGeneralColor("aurasStackCountColor", 1, 1, 1) end,
        function(r, g, bcol)
            Model.WriteGeneralColor("aurasStackCountColor", r, g, bcol)
            RequestAuraTextRefresh()
        end)
    BindColor(ctx, markers, "Own Buff", 16, -102,
        function() return Model.ReadGeneralColor("aurasOwnBuffHighlightColor", 1, 0.85, 0.20) end,
        function(r, g, bcol) Model.WriteGeneralColor("aurasOwnBuffHighlightColor", r, g, bcol) end)
    BindColor(ctx, markers, "Own Debuff", 16, -142,
        function() return Model.ReadGeneralColor("aurasOwnDebuffHighlightColor", 1, 0.30, 0.30) end,
        function(r, g, bcol) Model.WriteGeneralColor("aurasOwnDebuffHighlightColor", r, g, bcol) end)
    BindSlider(ctx, markers, "Safe seconds", 16, -196, 0, 600, 1, colW - 32,
        function() return Model.ReadGeneralNumber("aurasCooldownTextSafeSeconds", 60, 0, 600) end,
        function(v) Model.WriteGeneralNumber("aurasCooldownTextSafeSeconds", v, 0, 600) end)
    BindSlider(ctx, markers, "Warning <= sec", 16, -256, 0, 60, 1, colW - 32,
        function() return Model.ReadGeneralNumber("aurasCooldownTextWarningSeconds", 15, 0, 60) end,
        function(v) Model.WriteGeneralNumber("aurasCooldownTextWarningSeconds", v, 0, 60) end)

    W.Text(section, "Timer and marker colors are shared by unit and group aura previews.", 24, -398, w - 48, T.colors.muted)
    M.AddRefresher(ctx, RefreshColorSamples)
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

local function BuildUnitFilterRules(ctx, b, scope)
    local section = b:Section("Filter Rules", 520)
    local w = section._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 48) / 2))
    local rightX = 24 + colW + 16
    local filterControls = {}
    local useShared
    if scope ~= "shared" then
        useShared = BindSwitch(ctx, section, "Use Shared Rules", 24, -38, 190,
            function() return Model.UseSharedRules(scope) end,
            function(v)
                Model.SetUseSharedRules(scope, v)
                ApplyUnit(ctx, scope, "AURAS3_FILTER_INHERIT", true)
            end)
    end
    local enableFilters = BindSwitch(ctx, section, "Enable Filters", scope == "shared" and 24 or 234, -38, 180,
        function() return Model.ScopeFiltersEnabled(scope) end,
        function(v)
            Model.SetScopeFiltersEnabled(scope, v)
            ApplyUnit(ctx, scope, "AURAS3_FILTER_ENABLE", true)
        end)

    local function FilterToggle(card, label, kind, key, x, y, tip)
        local widget = BindSwitch(ctx, card, label, x, y, colW - 64,
            function() return Model.ReadFilter(scope, kind, key, false) == true end,
            function(v)
                Model.WriteFilter(scope, kind, key, v)
                ApplyUnit(ctx, scope, "AURAS3_FILTER_" .. kind .. "_" .. key, true)
            end)
        AddTooltip(widget, label, tip or "")
        filterControls[#filterControls + 1] = widget
        return widget
    end

    local buff = Card(section, "Buff Filters", "Inclusive rules plus one exclusive filter.", 24, -84, colW, 326)
    local debuff = Card(section, "Debuff Filters", "Inclusive rules plus one exclusive filter.", rightX, -84, colW, 326)

    W.LabelAt(buff, "Inclusive Filters", 16, -50, colW - 32, "GameFontNormalSmall", T.colors.accent)
    FilterToggle(buff, "Player", "buff", "onlyMine", 16, -76, "Auras applied by the player.")
    FilterToggle(buff, "Raid", "buff", "raid", 16, -108, "Raid-useful public Buffs.")
    FilterToggle(buff, "Cancelable", "buff", "cancelable", 16, -140, "Buffs that can be cancelled.")
    FilterToggle(buff, "Not Cancelable", "buff", "notCancelable", 16, -172, "Buffs that cannot be cancelled.")
    FilterToggle(buff, "Stealable", "buff", "includeStealable", 16, -204, "Stealable Buff marker.")
    filterControls[#filterControls + 1] = BindDropdown(ctx, buff, "Exclusive Filter", 16, -258, BUFF_EXCLUSIVE, min(250, colW - 32),
        function() return Model.ReadFilter(scope, "buff", "exclusive", "none") end,
        function(v)
            Model.WriteFilter(scope, "buff", "exclusive", v or "none")
            ApplyUnit(ctx, scope, "AURAS3_FILTER_BUFF_EXCLUSIVE", true)
        end)

    W.LabelAt(debuff, "Inclusive Filters", 16, -50, colW - 32, "GameFontNormalSmall", T.colors.accent)
    FilterToggle(debuff, "Player", "debuff", "onlyMine", 16, -76, "Debuffs applied by the player.")
    FilterToggle(debuff, "Raid", "debuff", "raid", 16, -108, "Raid and encounter Debuffs.")
    FilterToggle(debuff, "Dispellable", "debuff", "includeDispellable", 16, -140, "Dispellable Debuffs.")
    FilterToggle(debuff, "Not Dispellable", "debuff", "notDispellable", 16, -172, "Non-dispellable Debuffs.")
    FilterToggle(debuff, "Boss", "debuff", "boss", 16, -204, "Boss Debuffs.")
    filterControls[#filterControls + 1] = BindDropdown(ctx, debuff, "Exclusive Filter", 16, -258, DEBUFF_EXCLUSIVE, min(250, colW - 32),
        function() return Model.ReadFilter(scope, "debuff", "exclusive", "none") end,
        function(v)
            Model.WriteFilter(scope, "debuff", "exclusive", v or "none")
            ApplyUnit(ctx, scope, "AURAS3_FILTER_DEBUFF_EXCLUSIVE", true)
        end)

    W.Text(section, "On/off and placement are on each Unit Frame page. These filters apply to the selected unit-frame scope.", 24, -436, w - 48, T.colors.muted)
    M.AddRefresher(ctx, function()
        local customRules = scope == "shared" or not Model.UseSharedRules(scope)
        local filtersOn = customRules and Model.ScopeFiltersEnabled(scope)
        W.SetControlEnabled(enableFilters, customRules)
        W.SetControlsEnabled(filterControls, filtersOn)
        if useShared then W.SetControlEnabled(useShared, scope ~= "shared") end
    end)
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

    local card = Card(section, laneTitle, "Rules for " .. ScopeLabel(scope) .. ".", 24, -152, w - 48, 286)
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
    if lane == "buff" then
        FilterToggle("Player", "onlyMine", 16, -100, "Auras applied by the player.")
        FilterToggle("Raid", "raid", 16, -134, "Raid-useful public Buffs.")
        FilterToggle("Cancelable", "cancelable", 16, -168, "Buffs that can be cancelled.")
        FilterToggle("Not Cancelable", "notCancelable", rightX, -100, "Buffs that cannot be cancelled.")
        FilterToggle("Stealable", "includeStealable", rightX, -134, "Stealable Buff marker.")
        filterControls[#filterControls + 1] = BindDropdown(ctx, card, "Exclusive Filter", rightX, -204, BUFF_EXCLUSIVE, min(250, colW - 32),
            function() return Model.ReadFilter(scope, "buff", "exclusive", "none") end,
            function(v)
                Model.WriteFilter(scope, "buff", "exclusive", v or "none")
                ApplyUnit(ctx, scope, "AURAS3_FILTER_BUFF_EXCLUSIVE", true)
            end)
    else
        FilterToggle("Player", "onlyMine", 16, -100, "Debuffs applied by the player.")
        FilterToggle("Raid", "raid", 16, -134, "Raid and encounter Debuffs.")
        FilterToggle("Dispellable", "includeDispellable", 16, -168, "Dispellable Debuffs.")
        FilterToggle("Not Dispellable", "notDispellable", rightX, -100, "Non-dispellable Debuffs.")
        FilterToggle("Boss", "boss", rightX, -134, "Boss Debuffs.")
        filterControls[#filterControls + 1] = BindDropdown(ctx, card, "Exclusive Filter", rightX, -204, DEBUFF_EXCLUSIVE, min(250, colW - 32),
            function() return Model.ReadFilter(scope, "debuff", "exclusive", "none") end,
            function(v)
                Model.WriteFilter(scope, "debuff", "exclusive", v or "none")
                ApplyUnit(ctx, scope, "AURAS3_FILTER_DEBUFF_EXCLUSIVE", true)
            end)
    end

    W.Text(section, "Blacklist entries below apply to both Buff and Debuff preparation for the selected unit-frame scope.", 24, -456, w - 48, T.colors.muted)
    M.AddRefresher(ctx, function()
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
    local editEnabled = scope == "shared" or not Model.UseSharedBlacklist(scope)
    local useShared
    if scope ~= "shared" then
        useShared = BindSwitch(ctx, section, "Use Shared Blacklist", 24, -42, 210,
            function() return Model.UseSharedBlacklist(scope) end,
            function(v)
                Model.SetUseSharedBlacklist(scope, v)
                ApplyUnit(ctx, scope, "AURAS3_BLACKLIST_INHERIT", true)
            end)
    end

    local manual = Card(section, "Blacklist", "Prepared spell-ID list for Buff and Debuff filtering.", 24, -72, colW, 222)
    local preset = Card(section, "Blacklist Presets", "Curated aura ID groups that can be added to the blacklist.", rightX, -72, colW, 222)

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
    W.Text(manual, "Names must resolve to a spell ID before they can be prepared.", 16, -176, colW - 32, T.colors.muted)

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
    M.BindDropdown(ctx, presetDrop,
        function() return CurrentPreset() end,
        function(v)
            M.auraBlacklistPreset = v or "RAID_BUFFS"
            M.auraBlacklistSpell = nil
            if M.Refresh then M.Refresh(ctx) end
        end)
    local spellDrop = W.Dropdown(preset, "Spell", function() return Model.BlacklistSpellValues(CurrentPreset()) end, colW - 32)
    W.MoveWidget(spellDrop, preset, 16, -136, colW - 32)
    M.BindDropdown(ctx, spellDrop,
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

    local current = Card(section, "Current List", nil, 24, -318, w - 48, 184)
    local prepared = W.Text(current, "", 16, -18, w - 80, T.colors.accent)
    local emptyText = W.Text(current, "No blacklisted spells.", 16, -48, w - 80, T.colors.muted)
    local moreText = W.Text(current, "Click an entry to remove it.", 16, -164, w - 80, T.colors.muted)
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

    M.AddRefresher(ctx, function()
        editEnabled = scope == "shared" or not Model.UseSharedBlacklist(scope)
        if useShared then W.SetControlEnabled(useShared, scope ~= "shared") end
        W.SetControlEnabled(input, editEnabled)
        W.SetControlEnabled(add, editEnabled)
        W.SetControlEnabled(remove, editEnabled)
        W.SetControlEnabled(presetDrop, editEnabled)
        W.SetControlEnabled(spellDrop, editEnabled)
        W.SetControlEnabled(addPreset, editEnabled)
        W.SetControlEnabled(addPresetGroup, editEnabled)
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
    if Model and type(Model.ReadGroupBlacklistCategory) == "function" then
        return Model.ReadGroupBlacklistCategory(scope, groupKey, catKey)
    end
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
    BindGroupDropdown(ctx, filter, laneText .. " Filter", 16, -142, GroupFilterValues(lane), dropdownW, scope, lane, "filterToken", lane == "buff" and "RAID" or "ALL", "visual")
    W.Text(filter, "Use category blacklist below to exclude public " .. laneText .. " groups.", 40 + dropdownW, -142, max(220, filterW - dropdownW - 64), T.colors.muted)

    local blacklist = Card(section, "Category Blacklist", "Checked categories are hidden for " .. ScopeLabel(scope) .. ".", 24, -304, w - 48, 324)
    W.LabelAt(blacklist, "Active", 16, -50, 70, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(blacklist, lane == "buff" and "Buff category blacklist" or "Debuff category blacklist", 86, -50, 260, "GameFontHighlightSmall", T.colors.text)

    local af = AuraFilter()
    local meta = af and af.DECLASSIFIED_META
    if not (type(meta) == "table" and #meta > 0) then
        W.Text(blacklist, "No public aura category data is loaded.", 16, -96, w - 96, T.colors.muted)
        return
    end

    local half = ceil(#meta / 2)
    local catColW = max(230, floor((w - 104) / 2))
    local x2 = 16 + catColW + 24
    local startY = -98
    for i = 1, #meta do
        local cat = meta[i]
        local col = i <= half and 0 or 1
        local row = col == 0 and (i - 1) or (i - half - 1)
        local tx = col == 0 and 16 or x2
        local toggle = BindToggle(ctx, blacklist, CategoryLabel(cat), tx, startY - row * 30, catColW,
            function() return GFReadBlacklistCat(scope, lane, cat.key) end,
            function(v) GFWriteBlacklistCat(scope, lane, cat.key, v) end)
        if cat.tooltip then AddTooltip(toggle, CategoryLabel(cat), cat.tooltip) end
    end
end

local function BuildAuraFiltersPage(ctx)
    local b = W.PageBuilder(ctx)
    local scope = BuildAuraChrome(ctx, b, "Aura Filters", "Buff and Debuff filters, blacklists and group-frame category hiding.")
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

    controls[#controls + 1] = BindDropdown(ctx, parent, "Anchor", leftX, y - 80, anchorValues, leftW,
        function()
            if type(Model.ReadLaneAnchor) == "function" then return Model.ReadLaneAnchor(unit, kind) end
            return kind == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
        end,
        function(v)
            if type(Model.WriteLaneAnchor) == "function" then
                Model.WriteLaneAnchor(unit, kind, v)
                ApplyUnit(ctx, unit, "AURAS3_UNIT_ANCHOR")
            end
        end)
    controls[#controls + 1] = BindDropdown(ctx, parent, "Growth", leftX, y - 132, growthValues, leftW,
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
        end)
    controls[#controls + 1] = BindSlider(ctx, parent, "Offset X", leftX, y - 190, -300, 300, 1, leftW,
        function() return Model.ReadNumber(unit, LaneXKey(kind), 0, -4096, 4096) end,
        function(v)
            Model.WriteNumber(unit, LaneXKey(kind), v, -4096, 4096)
            ApplyUnit(ctx, unit, "AURAS3_UNIT_X")
        end)
    controls[#controls + 1] = BindSlider(ctx, parent, "Offset Y", leftX, y - 250, -300, 300, 1, leftW,
        function() return Model.ReadNumber(unit, LaneYKey(kind), LaneDefaultY(kind), -4096, 4096) end,
        function(v)
            Model.WriteNumber(unit, LaneYKey(kind), v, -4096, 4096)
            ApplyUnit(ctx, unit, "AURAS3_UNIT_Y")
        end)

    controls[#controls + 1] = BindSlider(ctx, parent, "Max Icons", rightX, y - 80, 0, 80, 1, rightW,
        function() return Model.ReadNumber(unit, LaneMaxKey(kind), LaneDefaultMax(kind), 0, 80) end,
        function(v)
            Model.WriteNumber(unit, LaneMaxKey(kind), v, 0, 80)
            ApplyUnit(ctx, unit, "AURAS3_UNIT_MAX")
        end)
    controls[#controls + 1] = BindSlider(ctx, parent, "Icon Size", rightX, y - 140, 10, 80, 1, rightW,
        function() return Model.ReadNumber(unit, LaneSizeKey(kind), 26, 1, 128) end,
        function(v)
            Model.WriteNumber(unit, LaneSizeKey(kind), v, 1, 128)
            ApplyUnit(ctx, unit, "AURAS3_UNIT_SIZE")
        end)
    controls[#controls + 1] = BindSlider(ctx, parent, "Per Row", rightX, y - 200, 1, 40, 1, rightW,
        function() return Model.ReadLanePerRow(unit, kind) end,
        function(v)
            Model.WriteLanePerRow(unit, kind, v)
            ApplyUnit(ctx, unit, "AURAS3_UNIT_PER_ROW")
        end)
    controls[#controls + 1] = BindSlider(ctx, parent, "Spacing", rightX, y - 260, 0, 12, 1, rightW,
        function() return Model.ReadNumber(unit, "spacing", 2, 0, 64) end,
        function(v)
            Model.WriteNumber(unit, "spacing", v, 0, 64)
            ApplyUnit(ctx, unit, "AURAS3_UNIT_SPACING")
        end)
    controls[#controls + 1] = BindSlider(ctx, parent, "Layer (Z-Order)", rightX, y - 320, 1, 15, 1, rightW,
        function()
            if type(Model.ReadLaneLayer) == "function" then return Model.ReadLaneLayer(unit, kind) end
            return kind == "buff" and 5 or 6
        end,
        function(v)
            if type(Model.WriteLaneLayer) == "function" then
                Model.WriteLaneLayer(unit, kind, v)
                ApplyUnit(ctx, unit, "AURAS3_UNIT_LAYER")
            end
        end)

    local function RefreshLaneCard()
        local shown = UnitLaneShown(unit, kind)
        W.SetControlEnabled(enable, true)
        W.SetControlsEnabled(controls, shown)
    end
    M.AddRefresher(ctx, RefreshLaneCard)
    RefreshLaneCard()

    return controls
end

function M.BuildAuras3UnitSection(ctx, builder, unit)
    if not Model.UnitSupported(unit) then return end
    local sec = builder:CollapsibleSection("auras3", "Auras", 622, false)
    local sectionW = sec._msuf2Width or builder.width or 720
    local laneCardW = sectionW - 36
    local top = Card(sec, "Aura Area", "Visibility, placement and icon grid for this unit frame.", 18, -38, sectionW - 36, 112)

    W.LabelAt(top, "Lane", 16, -66, 54, "GameFontNormalSmall", T.colors.accent)
    local laneButtons = {}
    local function LaneButton(kind, x)
        local label = kind == "buff" and "Buffs" or "Debuffs"
        local btn = ActionButton(top, label, 96)
        btn:SetPoint("TOPLEFT", top, "TOPLEFT", x, -62)
        btn:SetScript("OnClick", function()
            M.unitAuraTabSelection = M.unitAuraTabSelection or {}
            M.unitAuraTabSelection[unit] = kind
            if M.Refresh then M.Refresh(ctx) end
        end)
        laneButtons[kind] = btn
        return btn
    end
    LaneButton("buff", 74)
    LaneButton("debuff", 178)

    local actionsX = max(360, sectionW - 206)
    local style = ActionButton(top, "Style", 72)
    style:SetPoint("TOPLEFT", top, "TOPLEFT", actionsX, -62)
    style:SetScript("OnClick", function() SelectPage("auras3_styling", unit) end)
    local filters = ActionButton(top, "Filters", 82)
    filters:SetPoint("LEFT", style, "RIGHT", 8, 0)
    filters:SetScript("OnClick", function() SelectPage("auras3_filters", unit) end)

    M.unitAuraTabSelection = M.unitAuraTabSelection or {}
    local function CurrentTab()
        local tab = M.unitAuraTabSelection[unit] or "buff"
        if tab ~= "buff" and tab ~= "debuff" then tab = "buff" end
        return tab
    end

    local tabFrames = {}
    local function MakeTabFrame(key)
        local frame = CreateFrame("Frame", nil, sec)
        frame:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -170)
        frame:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", 0, 12)
        frame._msuf2Width = sectionW
        tabFrames[key] = frame
        return frame
    end

    BuildUnitAuraPlacementCard(ctx, MakeTabFrame("buff"), unit, "buff", 18, -6, laneCardW)
    BuildUnitAuraPlacementCard(ctx, MakeTabFrame("debuff"), unit, "debuff", 18, -6, laneCardW)

    local function RefreshTabs()
        local tab = CurrentTab()
        for key, frame in pairs(tabFrames) do frame:SetShown(key == tab) end
        if laneButtons.buff and laneButtons.buff.SetActive then laneButtons.buff:SetActive(tab == "buff") end
        if laneButtons.debuff and laneButtons.debuff.SetActive then laneButtons.debuff:SetActive(tab == "debuff") end
    end

    M.AddRefresher(ctx, function()
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
    RefreshTabs()
end

M.RegisterPage("auras3", { title = "MSUF Aura Style", build = BuildAuraStylePage, version = 69 })
M.RegisterPage("auras3_buffs", { title = "MSUF Aura Buffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "buff") end, version = 9 })
M.RegisterPage("auras3_debuffs", { title = "MSUF Aura Debuffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "debuff") end, version = 9 })
M.RegisterPage("auras3_rendering", { title = "MSUF Aura Style", build = BuildAuraStylePage, version = 69 })
M.RegisterPage("auras3_styling", { title = "MSUF Aura Style", build = BuildAuraStylePage, version = 26 })
M.RegisterPage("auras3_filters", { title = "MSUF Aura Filters", build = BuildAuraFiltersPage, version = 20 })
