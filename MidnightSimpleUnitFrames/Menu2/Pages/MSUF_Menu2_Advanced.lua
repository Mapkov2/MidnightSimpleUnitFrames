local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme

local floor = math.floor
local abs = math.abs
local max = math.max
local min = math.min

local function CallGlobal(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then return pcall(fn, ...) end
    return false
end

local function DB()
    return M.EnsureDB()
end

local function G()
    local db = DB()
    db.general = db.general or {}
    return db.general
end

local function Bars()
    local db = DB()
    db.bars = db.bars or {}
    return db.bars
end

local function Gameplay()
    local db = DB()
    db.gameplay = db.gameplay or {}
    return db.gameplay
end

local function BoolValue(tbl, key, default)
    local value = tbl and tbl[key]
    if value == nil then return default and true or false end
    return value and true or false
end

local function NumValue(tbl, key, default)
    return tonumber(tbl and tbl[key]) or default or 0
end

local function SetValue(tbl, key, value, apply)
    if not tbl or tbl[key] == value then return end
    local function Write()
        if tbl[key] == value then return false end
        tbl[key] = value
        if type(apply) == "function" then apply() end
        return true
    end
    if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
        return M.CaptureHistory(tostring(key), "advanced:" .. tostring(key), Write)
    end
    return Write()
end

local function DeepCopyTable(src)
    if type(src) ~= "table" then return src end
    if type(CopyTable) == "function" then return CopyTable(src) end
    local dst = {}
    for k, v in pairs(src) do dst[k] = DeepCopyTable(v) end
    return dst
end

local function IsEmptyAuraFilterTable(filters)
    if type(filters) ~= "table" then return true end
    for key, value in pairs(filters) do
        if key == "buffs" or key == "debuffs" then
            if type(value) == "table" then
                for _ in pairs(value) do return false end
            elseif value ~= nil then
                return false
            end
        elseif value ~= nil then
            return false
        end
    end
    return true
end

local function BindTableToggle(ctx, section, label, getTable, key, default, apply)
    local toggle = W.Toggle(section, label)
    M.BindToggle(ctx, toggle,
        function() return BoolValue(getTable(), key, default) end,
        function(v) SetValue(getTable(), key, v and true or false, apply) end)
    return toggle
end

local function BindTableSwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, apply)
    local toggle = W.SwitchAt(section, label, x, y, labelWidth)
    M.BindToggle(ctx, toggle,
        function() return BoolValue(getTable(), key, default) end,
        function(v) SetValue(getTable(), key, v and true or false, apply) end)
    return toggle
end

local function BindTableSlider(ctx, section, label, minVal, maxVal, step, width, getTable, key, default, apply)
    local slider = W.Slider(section, label, minVal, maxVal, step, width or 300)
    M.BindSlider(ctx, slider,
        function() return NumValue(getTable(), key, default) end,
        function(v)
            v = tonumber(v) or default or 0
            if (step or 1) >= 1 then v = floor(v + 0.5) end
            SetValue(getTable(), key, v, apply)
        end)
    return slider
end

local function BindTableDropdown(ctx, section, label, values, width, getTable, key, default, apply)
    local dropdown = W.Dropdown(section, label, values, width or 220)
    M.BindDropdown(ctx, dropdown,
        function()
            local tbl = getTable()
            if tbl and tbl[key] ~= nil then return tbl[key] end
            return default
        end,
        function(v) SetValue(getTable(), key, v or default, apply) end)
    return dropdown
end

local function BindValueDropdown(ctx, section, label, values, width, getValue, setValue)
    local dropdown = W.Dropdown(section, label, values, width or 220)
    M.BindDropdown(ctx, dropdown,
        function() return getValue() end,
        function(v) setValue(v) end)
    return dropdown
end

local function ReadRGB(tbl, key, r, g, b)
    local c = tbl and tbl[key]
    if type(c) == "table" then
        return tonumber(c[1] or c["1"] or c.r) or r,
            tonumber(c[2] or c["2"] or c.g) or g,
            tonumber(c[3] or c["3"] or c.b) or b
    end
    return r, g, b
end

local function WriteRGB(tbl, key, r, g, b)
    if not tbl then return end
    tbl[key] = { r, g, b }
end

local function BindTableColor(ctx, section, label, getTable, key, defaultR, defaultG, defaultB, apply)
    local color = W.Color(section, label)
    M.BindColor(ctx, color,
        function() return ReadRGB(getTable(), key, defaultR, defaultG, defaultB) end,
        function(r, g, b)
            WriteRGB(getTable(), key, r, g, b)
            if type(apply) == "function" then apply() end
        end)
    return color
end

local function BindSeparateRGB(ctx, section, label, getTable, prefix, defaultR, defaultG, defaultB, apply)
    local color = W.Color(section, label)
    M.BindColor(ctx, color,
        function()
            local tbl = getTable()
            if not tbl then return defaultR, defaultG, defaultB end
            return tonumber(tbl[prefix .. "R"]) or defaultR,
                tonumber(tbl[prefix .. "G"]) or defaultG,
                tonumber(tbl[prefix .. "B"]) or defaultB
        end,
        function(r, g, b)
            local tbl = getTable()
            if not tbl then return end
            tbl[prefix .. "R"], tbl[prefix .. "G"], tbl[prefix .. "B"] = r, g, b
            if type(apply) == "function" then apply() end
        end)
    return color
end

local A2_APPLY_QUEUED = false
local function ApplyAuras()
    if A2_APPLY_QUEUED then return end
    A2_APPLY_QUEUED = true
    local function Run()
        A2_APPLY_QUEUED = false
        local api = ns and ns.MSUF_Auras2
        if api and api.DB and type(api.DB.InvalidateCache) == "function" then pcall(api.DB.InvalidateCache) end
        if api and api.Colors and type(api.Colors.InvalidateCache) == "function" then pcall(api.Colors.InvalidateCache) end
        if api and type(api.RequestApply) == "function" then
            pcall(api.RequestApply)
        elseif type(_G.MSUF_Auras2_RefreshAll) == "function" then
            pcall(_G.MSUF_Auras2_RefreshAll)
        end
        if type(_G.MSUF_A2_InvalidateCooldownTextCurve) == "function" then pcall(_G.MSUF_A2_InvalidateCooldownTextCurve) end
        if type(_G.MSUF_A2_ForceCooldownTextRecolor) == "function" then pcall(_G.MSUF_A2_ForceCooldownTextRecolor) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, Run) else Run() end
end

local function AurasDB()
    local db = DB()
    db.auras2 = db.auras2 or {}
    local a2 = db.auras2
    a2.shared = a2.shared or {}
    a2.perUnit = a2.perUnit or {}
    return a2, a2.shared
end

local function AurasUnit(key)
    local a2 = AurasDB()
    a2.perUnit[key] = a2.perUnit[key] or {}
    local u = a2.perUnit[key]
    u.layout = u.layout or {}
    u.layoutShared = u.layoutShared or {}
    u.filters = u.filters or {}
    u.filters.buffs = u.filters.buffs or {}
    u.filters.debuffs = u.filters.debuffs or {}
    return u
end

local AURA_SCOPES = {
    { value = "shared", text = "Shared" },
    { value = "player", text = "Player" },
    { value = "target", text = "Target" },
    { value = "focus", text = "Focus" },
    { value = "boss1", text = "Boss 1" },
    { value = "boss2", text = "Boss 2" },
    { value = "boss3", text = "Boss 3" },
    { value = "boss4", text = "Boss 4" },
    { value = "boss5", text = "Boss 5" },
}

local function AuraScope()
    return M.auraScope or "shared"
end

local function AuraShared()
    local _, shared = AurasDB()
    return shared
end

local function AuraLayout()
    local scope = AuraScope()
    if scope == "shared" then return AuraShared() end
    local u = AurasUnit(scope)
    if u.overrideLayout == true then return u.layout end
    return AuraShared()
end

local function AuraCaps()
    local scope = AuraScope()
    if scope == "shared" then return AuraShared() end
    local u = AurasUnit(scope)
    if u.overrideSharedLayout == true then return u.layoutShared end
    return AuraShared()
end

local function AuraFilters()
    local scope = AuraScope()
    local shared = AuraShared()
    shared.filters = shared.filters or {}
    shared.filters.buffs = shared.filters.buffs or {}
    shared.filters.debuffs = shared.filters.debuffs or {}
    if scope == "shared" then return shared.filters end
    local u = AurasUnit(scope)
    if u.overrideFilters == true then return u.filters end
    return shared.filters
end

local function AuraBuffFilters()
    local f = AuraFilters()
    f.buffs = f.buffs or {}
    return f.buffs
end

local function AuraDebuffFilters()
    local f = AuraFilters()
    f.debuffs = f.debuffs or {}
    return f.debuffs
end

local function BossHealAuras()
    local a2 = AurasDB()
    a2.bossHealAuras = a2.bossHealAuras or {}
    return a2.bossHealAuras
end

local function AuraIgnoreCats()
    local scope = AuraScope()
    local shared = AuraShared()
    shared.ignoreCats = shared.ignoreCats or {}
    if scope == "shared" then return shared.ignoreCats end
    local u = AurasUnit(scope)
    if u.overrideIgnore == true then
        u.ignoreCats = u.ignoreCats or {}
        return u.ignoreCats
    end
    return shared.ignoreCats
end

local function AuraReminders()
    local shared = AuraShared()
    shared.reminders = shared.reminders or {}
    return shared.reminders
end

local function ForceAuraLayoutOverride()
    local scope = AuraScope()
    if scope == "shared" then return end
    local shared = AuraShared()
    local u = AurasUnit(scope)
    u.overrideLayout = true
    if type(u.layout) ~= "table" then u.layout = {} end
    local layout = u.layout
    for _, key in ipairs({ "iconSize", "spacing", "cooldownTextSize", "stackTextSize", "reminderGrowth" }) do
        if layout[key] == nil then layout[key] = shared[key] end
    end
end

local function ForceAuraCapsOverride()
    local scope = AuraScope()
    if scope == "shared" then return end
    local shared = AuraShared()
    local u = AurasUnit(scope)
    u.overrideSharedLayout = true
    if type(u.layoutShared) ~= "table" then u.layoutShared = {} end
    local layout = u.layoutShared
    for _, key in ipairs({
        "maxBuffs", "maxDebuffs", "maxIcons", "perRow", "layoutMode", "growth",
        "buffGrowth", "debuffGrowth", "privateGrowth", "rowWrap", "buffRowWrap",
        "debuffRowWrap", "buffDebuffAnchor", "splitSpacing", "stackCountAnchor",
        "sortOrder",
    }) do
        if layout[key] == nil then layout[key] = shared[key] end
    end
end

local function ForceAuraFilterOverride()
    local scope = AuraScope()
    if scope == "shared" then return end
    local shared = AuraShared()
    local u = AurasUnit(scope)
    local hadOverride = (u.overrideFilters == true)
    u.overrideFilters = true
    if type(u.filters) ~= "table" or u.filters == shared.filters or (not hadOverride and IsEmptyAuraFilterTable(u.filters)) then
        u.filters = DeepCopyTable(shared.filters or {})
    end
    u.filters.buffs = u.filters.buffs or {}
    u.filters.debuffs = u.filters.debuffs or {}
end

local function ForceAuraIgnoreOverride()
    local scope = AuraScope()
    if scope == "shared" then return end
    local shared = AuraShared()
    local u = AurasUnit(scope)
    if u.overrideIgnore == true then return end
    u.overrideIgnore = true
    u.ignoreCats = {}
    if type(shared.ignoreCats) == "table" then
        for k, v in pairs(shared.ignoreCats) do u.ignoreCats[k] = v end
    end
end

local function MarkReminderDirty()
    local api = ns and ns.MSUF_Auras2
    local reminder = api and api.Reminder
    if reminder and type(reminder.MarkDirty) == "function" then pcall(reminder.MarkDirty) end
end

local AURA_GROWTH = {
    { value = "RIGHT", text = "Grow Right" },
    { value = "LEFT", text = "Grow Left" },
    { value = "UP", text = "Vertical Up" },
    { value = "DOWN", text = "Vertical Down" },
}

local AURA_ROW_WRAP = {
    { value = "DOWN", text = "2nd row down" },
    { value = "UP", text = "2nd row up" },
}

local AURA_STACK_ANCHORS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}

local AURA_IGNORE_CATEGORIES = {
    { key = "RAID_BUFFS", label = "Raid Buffs" },
    { key = "BLESSING_BRONZE", label = "Blessing of the Bronze" },
    { key = "HEALER_HOTS", label = "Healer HoTs" },
    { key = "ROGUE_POISONS", label = "Rogue Poisons" },
    { key = "SHAMAN_IMBUE", label = "Shaman Imbuements" },
    { key = "DESERTER", label = "Deserter" },
    { key = "SKYRIDING", label = "Skyriding" },
    { key = "SELF_BUFFS", label = "Long-term Self Buffs" },
    { key = "RESOURCE_AURAS", label = "Resource-like Auras" },
    { key = "COOLDOWNS", label = "Cooldowns" },
}

local AURA_REMINDERS = {
    { key = "FORTITUDE", label = "Power Word: Fortitude" },
    { key = "ARCANE_INTELLECT", label = "Arcane Intellect" },
    { key = "MARK_OF_WILD", label = "Mark of the Wild" },
    { key = "BATTLE_SHOUT", label = "Battle Shout" },
    { key = "SKYFURY", label = "Skyfury" },
    { key = "SOURCE_OF_MAGIC", label = "Source of Magic" },
    { key = "BLESSING_BRONZE", label = "Blessing of the Bronze" },
    { key = "ROGUE_LETHAL", label = "Lethal Poison (Rogue)" },
    { key = "ROGUE_NONLETHAL", label = "Non-Lethal Poison (Rogue)" },
}

local AURA_SORT_ORDER = {
    { value = 0, text = "Unsorted (default)" },
    { value = 1, text = "Default (player > canApply > ID)" },
    { value = 2, text = "Big Defensive (longest first)" },
    { value = 3, text = "Expiration (soonest first)" },
    { value = 4, text = "Expiration only" },
    { value = 5, text = "Name (alphabetical)" },
    { value = 6, text = "Name only" },
}

local PANDEMIC_MODES = {
    { value = "BORDER", text = "Border" },
    { value = "PULSE", text = "Pulse" },
    { value = "GLOW", text = "Glow" },
}

local function MoveWidget(widget, parent, x, y)
    return W.MoveWidget(widget, parent, x, y)
end

local function LabelAt(parent, text, x, y, width, template, color)
    return W.LabelAt(parent, text, x, y, width, template, color)
end

local function DividerAt(parent, y, leftPad, rightPad)
    return W.DividerAt(parent, y, leftPad, rightPad)
end

local function BindValueToggle(ctx, section, label, getValue, setValue)
    local toggle = W.Toggle(section, label)
    M.BindToggle(ctx, toggle,
        function() return getValue() and true or false end,
        function(v) setValue(v and true or false) end)
    return toggle
end

local function BindValueSwitchAt(ctx, section, label, x, y, labelWidth, getValue, setValue)
    local toggle = W.SwitchAt(section, label, x, y, labelWidth)
    M.BindToggle(ctx, toggle,
        function() return getValue() and true or false end,
        function(v) setValue(v and true or false) end)
    return toggle
end

local function BindValueSlider(ctx, section, label, minVal, maxVal, step, width, getValue, setValue)
    local slider = W.Slider(section, label, minVal, maxVal, step, width or 160)
    M.BindSlider(ctx, slider,
        function() return tonumber(getValue()) or minVal or 0 end,
        function(v)
            v = tonumber(v) or minVal or 0
            if (step or 1) >= 1 then v = floor(v + 0.5) end
            setValue(v)
        end)
    return slider
end

local function ToggleAt(ctx, section, label, x, y, getTable, key, default, apply)
    return MoveWidget(BindTableToggle(ctx, section, label, getTable, key, default, apply), section, x, y)
end

local function SwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, apply)
    return BindTableSwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, apply)
end

local function ValueToggleAt(ctx, section, label, x, y, getValue, setValue)
    return MoveWidget(BindValueToggle(ctx, section, label, getValue, setValue), section, x, y)
end

local function ValueSwitchAt(ctx, section, label, x, y, labelWidth, getValue, setValue)
    return BindValueSwitchAt(ctx, section, label, x, y, labelWidth, getValue, setValue)
end

local function SliderAt(ctx, section, label, x, y, minVal, maxVal, step, width, getTable, key, default, apply)
    return MoveWidget(BindTableSlider(ctx, section, label, minVal, maxVal, step, width, getTable, key, default, apply), section, x, y)
end

local function ValueSliderAt(ctx, section, label, x, y, minVal, maxVal, step, width, getValue, setValue)
    return MoveWidget(BindValueSlider(ctx, section, label, minVal, maxVal, step, width, getValue, setValue), section, x, y)
end

local function DropdownAt(ctx, section, label, x, y, values, width, getTable, key, default, apply)
    return MoveWidget(BindTableDropdown(ctx, section, label, values, width, getTable, key, default, apply), section, x, y)
end

local function ValueDropdownAt(ctx, section, label, x, y, values, width, getValue, setValue)
    return MoveWidget(BindValueDropdown(ctx, section, label, values, width, getValue, setValue), section, x, y)
end

local function ColorAt(ctx, section, label, x, y, getTable, key, defaultR, defaultG, defaultB, apply)
    return MoveWidget(BindTableColor(ctx, section, label, getTable, key, defaultR, defaultG, defaultB, apply), section, x, y)
end

local function AddTooltip(widget, title, body)
    if not widget then return widget end
    local function ShowTooltip(self)
        if not _G.GameTooltip then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title and title ~= "" then _G.GameTooltip:AddLine(M.Tr and M.Tr(title) or title, 1, 1, 1) end
        if body and body ~= "" then _G.GameTooltip:AddLine(M.Tr and M.Tr(body) or body, 0.72, 0.76, 0.86, true) end
        _G.GameTooltip:Show()
    end
    local function HideTooltip()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end
    if widget.HookScript then
        widget:HookScript("OnEnter", ShowTooltip)
        widget:HookScript("OnLeave", HideTooltip)
    end
    if widget._msuf2LabelHit and widget._msuf2LabelHit.HookScript then
        widget._msuf2LabelHit:HookScript("OnEnter", ShowTooltip)
        widget._msuf2LabelHit:HookScript("OnLeave", HideTooltip)
    end
    return widget
end

local function ScopedToggleAt(ctx, section, label, x, y, getTable, key, default, beforeSet, afterSet)
    return ValueToggleAt(ctx, section, label, x, y,
        function() return BoolValue(getTable(), key, default) end,
        function(v)
            if type(beforeSet) == "function" then beforeSet() end
            SetValue(getTable(), key, v and true or false, afterSet)
        end)
end

local function ScopedSwitchAt(ctx, section, label, x, y, labelWidth, getTable, key, default, beforeSet, afterSet)
    return ValueSwitchAt(ctx, section, label, x, y, labelWidth,
        function() return BoolValue(getTable(), key, default) end,
        function(v)
            if type(beforeSet) == "function" then beforeSet() end
            SetValue(getTable(), key, v and true or false, afterSet)
        end)
end

local function ScopedSliderAt(ctx, section, label, x, y, minVal, maxVal, step, width, getTable, key, default, beforeSet, afterSet)
    return ValueSliderAt(ctx, section, label, x, y, minVal, maxVal, step, width,
        function() return NumValue(getTable(), key, default) end,
        function(v)
            if type(beforeSet) == "function" then beforeSet() end
            v = tonumber(v) or default or 0
            if (step or 1) >= 1 then v = floor(v + 0.5) end
            SetValue(getTable(), key, v, afterSet)
        end)
end

local function ScopedDropdownAt(ctx, section, label, x, y, values, width, getTable, key, default, beforeSet, afterSet)
    return ValueDropdownAt(ctx, section, label, x, y, values, width,
        function()
            local tbl = getTable()
            if tbl and tbl[key] ~= nil then return tbl[key] end
            return default
        end,
        function(v)
            if type(beforeSet) == "function" then beforeSet() end
            SetValue(getTable(), key, v or default, afterSet)
        end)
end

local function TogglePillAt(ctx, parent, label, x, y, width, getTable, key, default, apply)
    local btn = T.Button(parent, label, width or 90, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    local marker = btn:CreateTexture(nil, "OVERLAY")
    marker:SetTexture("Interface\\Buttons\\WHITE8X8")
    marker:SetSize(7, 7)
    marker:SetPoint("LEFT", btn, "LEFT", 8, 0)
    if btn._msuf2Label then
        btn._msuf2Label:ClearAllPoints()
        btn._msuf2Label:SetPoint("LEFT", btn, "LEFT", 22, 0)
        btn._msuf2Label:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        btn._msuf2Label:SetJustifyH("LEFT")
    end
    local function PaintMarker(active)
        if active then
            marker:SetVertexColor(0.24, 0.88, 0.46, 1)
        else
            marker:SetVertexColor(0.92, 0.20, 0.26, 1)
        end
    end
    btn:SetScript("OnClick", function(self)
        local tbl = getTable()
        local current = BoolValue(tbl, key, default)
        SetValue(tbl, key, not current, apply)
        self:SetActive(not current)
        PaintMarker(not current)
    end)
    M.AddRefresher(ctx, function()
        local active = BoolValue(getTable(), key, default)
        btn:SetActive(active)
        PaintMarker(active)
    end)
    return btn
end

local function SetControlEnabled(widget, enabled)
    W.SetControlEnabled(widget, enabled)
end

local function FlowTopLeft(widths, startX, startY, maxRight, gap, rowStep, itemH)
    local positions = {}
    local x, y = startX or 0, startY or 0
    maxRight = maxRight or 720
    gap = gap or 8
    rowStep = rowStep or 28
    itemH = itemH or 24
    local bottomY = y - itemH

    for i = 1, #widths do
        local width = widths[i] or 0
        if x > startX and x + width > maxRight then
            x = startX
            y = y - rowStep
        end
        positions[i] = { x = x, y = y, width = width }
        bottomY = y - itemH
        x = x + width + gap
    end

    return positions, bottomY
end

local function FitInlineToggle(toggle, width)
    if not (toggle and toggle._msuf2Label and toggle._msuf2Label.SetWidth) then return toggle end
    toggle._msuf2Label:SetWidth(max(80, (tonumber(width) or 140) - 32))
    return toggle
end

local function NormalizePandemicMode(value)
    if value == true then return "PULSE" end
    if value == "BORDER" or value == "PULSE" or value == "GLOW" then return value end
    return "OFF"
end

local function GetPandemicMode()
    local shared = AuraShared()
    return NormalizePandemicMode(shared.pandemicMode ~= nil and shared.pandemicMode or shared.showPandemic)
end

local function SetPandemicMode(value)
    local shared = AuraShared()
    value = NormalizePandemicMode(value)
    if value ~= "OFF" then
        if type(M.PersistMenuStateValue) == "function" then
            M.PersistMenuStateValue("lastPandemicMode", value)
        else
            M.lastPandemicMode = value
        end
    end
    shared.pandemicMode = value
    shared.showPandemic = nil
    ApplyAuras()
end

local function AuraHasOverride(key)
    if key == "shared" then return false end
    local a2 = AurasDB()
    local u = a2.perUnit and a2.perUnit[key]
    return u and (
        u.overrideSharedLayout == true
        or u.overrideLayout == true
        or u.overrideFilters == true
        or u.overrideIgnore == true
    ) or false
end

local function RefreshAurasPage(ctx)
    for i = 1, #ctx.refreshers do
        local fn = ctx.refreshers[i]
        if type(fn) == "function" then pcall(fn) end
    end
end

local AURAS_BUILD_DEPS = {
    M = M, W = W, T = T, ns = ns,
    floor = floor, abs = abs, max = max, min = min,
    BoolValue = BoolValue, SetValue = SetValue, G = G,
    ApplyAuras = ApplyAuras, AurasDB = AurasDB, AurasUnit = AurasUnit,
    AuraScope = AuraScope, AuraShared = AuraShared, AuraLayout = AuraLayout,
    AuraCaps = AuraCaps, AuraFilters = AuraFilters, AuraBuffFilters = AuraBuffFilters,
    AuraDebuffFilters = AuraDebuffFilters, BossHealAuras = BossHealAuras,
    AuraIgnoreCats = AuraIgnoreCats, AuraReminders = AuraReminders,
    ForceAuraLayoutOverride = ForceAuraLayoutOverride, ForceAuraCapsOverride = ForceAuraCapsOverride,
    ForceAuraFilterOverride = ForceAuraFilterOverride, ForceAuraIgnoreOverride = ForceAuraIgnoreOverride,
    MarkReminderDirty = MarkReminderDirty, SetControlEnabled = SetControlEnabled,
    FlowTopLeft = FlowTopLeft, FitInlineToggle = FitInlineToggle,
    GetPandemicMode = GetPandemicMode, SetPandemicMode = SetPandemicMode,
    AuraHasOverride = AuraHasOverride, RefreshAurasPage = RefreshAurasPage,
    AURA_SCOPES = AURA_SCOPES, AURA_GROWTH = AURA_GROWTH, AURA_ROW_WRAP = AURA_ROW_WRAP,
    AURA_STACK_ANCHORS = AURA_STACK_ANCHORS, AURA_IGNORE_CATEGORIES = AURA_IGNORE_CATEGORIES,
    AURA_REMINDERS = AURA_REMINDERS, AURA_SORT_ORDER = AURA_SORT_ORDER,
    PANDEMIC_MODES = PANDEMIC_MODES,
}

local function BuildAuras(ctx)
    local deps = AURAS_BUILD_DEPS
    local M, W, T, ns = deps.M, deps.W, deps.T, deps.ns
    local floor, abs, max, min = deps.floor, deps.abs, deps.max, deps.min
    local BoolValue, SetValue, G = deps.BoolValue, deps.SetValue, deps.G
    local ApplyAuras, AurasDB, AurasUnit = deps.ApplyAuras, deps.AurasDB, deps.AurasUnit
    local AuraScope, AuraShared, AuraLayout, AuraCaps = deps.AuraScope, deps.AuraShared, deps.AuraLayout, deps.AuraCaps
    local AuraFilters, AuraBuffFilters, AuraDebuffFilters = deps.AuraFilters, deps.AuraBuffFilters, deps.AuraDebuffFilters
    local BossHealAuras, AuraIgnoreCats, AuraReminders = deps.BossHealAuras, deps.AuraIgnoreCats, deps.AuraReminders
    local ForceAuraLayoutOverride, ForceAuraCapsOverride = deps.ForceAuraLayoutOverride, deps.ForceAuraCapsOverride
    local ForceAuraFilterOverride, ForceAuraIgnoreOverride = deps.ForceAuraFilterOverride, deps.ForceAuraIgnoreOverride
    local MarkReminderDirty, SetControlEnabled = deps.MarkReminderDirty, deps.SetControlEnabled
    local FlowTopLeft, FitInlineToggle = deps.FlowTopLeft, deps.FitInlineToggle
    local GetPandemicMode, SetPandemicMode = deps.GetPandemicMode, deps.SetPandemicMode
    local AuraHasOverride, RefreshAurasPage = deps.AuraHasOverride, deps.RefreshAurasPage
    local AURA_SCOPES, AURA_GROWTH, AURA_ROW_WRAP = deps.AURA_SCOPES, deps.AURA_GROWTH, deps.AURA_ROW_WRAP
    local AURA_STACK_ANCHORS, AURA_IGNORE_CATEGORIES = deps.AURA_STACK_ANCHORS, deps.AURA_IGNORE_CATEGORIES
    local AURA_REMINDERS, AURA_SORT_ORDER, PANDEMIC_MODES = deps.AURA_REMINDERS, deps.AURA_SORT_ORDER, deps.PANDEMIC_MODES

    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Unit Auras", "Set where auras appear, choose the edited scope, then tune caps, filters, layout and reminders.", 72)
    local contentW = max(320, tonumber(ctx and ctx.width) or 720)

    local sharedOnlyControls = {}
    local filterOverrideControls = {}
    local capsOverrideControls = {}
    local layoutOverrideControls = {}

    local function Track(list, control)
        if list and control then list[#list + 1] = control end
        return control
    end

    local function IsSharedScope()
        return AuraScope() == "shared"
    end

    local function UnitOverrideEnabled(flag)
        local scopeKey = AuraScope()
        if scopeKey == "shared" then return true end
        local u = AurasUnit(scopeKey)
        return u and u[flag] == true
    end

    local function AuraScopeLabel()
        local scopeKey = AuraScope()
        for i = 1, #AURA_SCOPES do
            local spec = AURA_SCOPES[i]
            if spec.value == scopeKey then
                local text = spec.text or scopeKey
                return (M.Tr and M.Tr(text)) or text
            end
        end
        return tostring(scopeKey or "")
    end

    local function ApplyUnitAuraEnabled()
        local a2 = AurasDB()
        if a2.enabled == false and type(_G.MSUF_A2_HardDisableAll) == "function" then pcall(_G.MSUF_A2_HardDisableAll) end
        ApplyAuras()
    end

    local function ActiveAuraUnitCount()
        local a2 = AurasDB()
        local count = 0
        if BoolValue(a2, "showPlayer", false) then count = count + 1 end
        if BoolValue(a2, "showTarget", true) then count = count + 1 end
        if BoolValue(a2, "showFocus", true) then count = count + 1 end
        if BoolValue(a2, "showBoss", true) then count = count + 1 end
        return count
    end

    local QUICK_PRESETS = {
        clean = {
            label = "Clean",
            maxBuffs = 6, maxDebuffs = 12, perRow = 10, splitSpacing = 4, iconSize = 24, spacing = 2, sortOrder = 0,
            layoutMode = "SEPARATE", buffGrowth = "RIGHT", debuffGrowth = "RIGHT", privateGrowth = "RIGHT", buffRowWrap = "DOWN", debuffRowWrap = "DOWN",
            hidePermanent = true, buffIncludeBoss = false, debuffIncludeBoss = true, includeStealable = true,
            includeDispellable = true, onlyMineBuffs = false, onlyMineDebuffs = false,
            highlightOwnBuffs = true, highlightOwnDebuffs = true, showCooldownSwipe = true, showCooldownText = true, showStackCount = true, useBlizzardTimerText = true,
        },
        focused = {
            label = "Focused",
            maxBuffs = 10, maxDebuffs = 16, perRow = 10, splitSpacing = 6, iconSize = 26, spacing = 2, sortOrder = 3,
            layoutMode = "SEPARATE", buffGrowth = "RIGHT", debuffGrowth = "RIGHT", privateGrowth = "RIGHT", buffRowWrap = "DOWN", debuffRowWrap = "DOWN",
            hidePermanent = false, buffIncludeBoss = true, debuffIncludeBoss = true, includeStealable = true,
            includeDispellable = true, onlyMineBuffs = true, onlyMineDebuffs = true,
            highlightOwnBuffs = true, highlightOwnDebuffs = true, showCooldownSwipe = true, showCooldownText = true, showStackCount = true, useBlizzardTimerText = true,
        },
        performance = {
            label = "Fast",
            maxBuffs = 4, maxDebuffs = 8, perRow = 8, splitSpacing = 2, iconSize = 22, spacing = 1, sortOrder = 0,
            layoutMode = "SEPARATE", buffGrowth = "RIGHT", debuffGrowth = "RIGHT", privateGrowth = "RIGHT", buffRowWrap = "DOWN", debuffRowWrap = "DOWN",
            hidePermanent = true, buffIncludeBoss = false, debuffIncludeBoss = true, includeStealable = false,
            includeDispellable = false, onlyMineBuffs = false, onlyMineDebuffs = false,
            highlightOwnBuffs = false, highlightOwnDebuffs = false, showCooldownSwipe = false, showCooldownText = true, showStackCount = false, useBlizzardTimerText = true,
        },
    }
    local previewPreset

    local function EffectiveCapsValues()
        local p = previewPreset and QUICK_PRESETS[previewPreset]
        local caps = AuraCaps()
        local shared = AuraShared()
        return {
            maxBuffs = p and p.maxBuffs or NumValue(caps, "maxBuffs", 8),
            maxDebuffs = p and p.maxDebuffs or NumValue(caps, "maxDebuffs", 15),
            perRow = p and p.perRow or NumValue(caps, "perRow", 11),
            iconSize = p and p.iconSize or NumValue(AuraLayout(), "iconSize", 26),
            spacing = p and p.spacing or NumValue(AuraLayout(), "spacing", 2),
            privateMax = NumValue(shared, "privateAuraMaxPlayer", 4),
            sortOrder = p and p.sortOrder or NumValue(caps, "sortOrder", 0),
        }
    end

    local function BudgetInfo()
        local v = EffectiveCapsValues()
        local shared = AuraShared()
        local total = (BoolValue(shared, "showBuffs", true) and v.maxBuffs or 0)
            + (BoolValue(shared, "showDebuffs", true) and v.maxDebuffs or 0)
            + ((BoolValue(shared, "privateAurasEnabled", true) and BoolValue(shared, "showPrivateAurasPlayer", true)) and v.privateMax or 0)
        if total <= 18 then return "Light", total, T.colors.ok end
        if total <= 30 then return "Medium", total, T.colors.accent2 end
        return "Heavy", total, T.colors.danger end

    local function SortLabel(value)
        for i = 1, #AURA_SORT_ORDER do
            if tostring(AURA_SORT_ORDER[i].value) == tostring(value) then return AURA_SORT_ORDER[i].text or tostring(value) end
        end
        return tostring(value or 0)
    end

    local function ApplyQuickPreset(name)
        local p = QUICK_PRESETS[name]
        if not p then return end
        local sharedScope = AuraScope() == "shared"
        if not sharedScope then
            ForceAuraFilterOverride()
            ForceAuraCapsOverride()
            ForceAuraLayoutOverride()
        end
        local caps = AuraCaps()
        local layout = AuraLayout()
        local filters = AuraFilters()
        local buffs = AuraBuffFilters()
        local debuffs = AuraDebuffFilters()
        caps.maxBuffs, caps.maxDebuffs, caps.perRow = p.maxBuffs, p.maxDebuffs, p.perRow
        caps.splitSpacing, caps.sortOrder = p.splitSpacing, p.sortOrder
        caps.layoutMode = p.layoutMode or caps.layoutMode or "SEPARATE"
        caps.buffGrowth, caps.debuffGrowth, caps.privateGrowth = p.buffGrowth, p.debuffGrowth, p.privateGrowth
        caps.buffRowWrap, caps.debuffRowWrap = p.buffRowWrap, p.debuffRowWrap
        layout.iconSize, layout.spacing = p.iconSize, p.spacing
        filters.hidePermanent = p.hidePermanent
        buffs.includeBoss, debuffs.includeBoss = p.buffIncludeBoss, p.debuffIncludeBoss
        buffs.includeStealable, debuffs.includeDispellable = p.includeStealable, p.includeDispellable
        buffs.onlyMine, debuffs.onlyMine = p.onlyMineBuffs, p.onlyMineDebuffs
        if sharedScope then
            local shared = AuraShared()
            shared.highlightOwnBuffs = p.highlightOwnBuffs
            shared.highlightOwnDebuffs = p.highlightOwnDebuffs
            shared.showCooldownSwipe = p.showCooldownSwipe
            shared.showCooldownText = p.showCooldownText
            shared.showStackCount = p.showStackCount
            shared.useBlizzardTimerText = p.useBlizzardTimerText
        end
        ApplyAuras()
        RefreshAurasPage(ctx)
    end

    local function ResetSelectedScope()
        local s = AuraScope()
        if s == "shared" then return end
        local a2 = AurasDB()
        if a2.perUnit then a2.perUnit[s] = nil end
        ApplyAuras()
        RefreshAurasPage(ctx)
    end

    local function ResetAllAuraOverrides()
        local a2 = AurasDB()
        for i = 2, #AURA_SCOPES do
            local key = AURA_SCOPES[i].value
            local u = a2.perUnit and a2.perUnit[key]
            if type(u) == "table" then
                u.overrideSharedLayout = false
                u.layoutShared = nil
                u.overrideLayout = false
                u.layout = nil
                u.overrideFilters = false
                u.filters = nil
                u.overrideIgnore = false
                u.ignoreCats = nil
            end
        end
        ApplyAuras()
        RefreshAurasPage(ctx)
    end

    local function AuraAccordionState()
        if type(M.GetPersistentMenuStateTable) == "function" then
            M.accordionState = M.GetPersistentMenuStateTable("accordionState")
        else
            M.accordionState = M.accordionState or {}
        end
        return M.accordionState
    end

    local function SetAurasUXMode(mode)
        local state = AuraAccordionState()
        local prefix = tostring(ctx.key or "page") .. ":"
        local advanced = mode == "advanced"
        local desired = {
            a2_display = true,
            a2_layout = true,
            a2_text_coloring = advanced,
            a2_private = advanced,
            a2_filters = advanced,
            a2_ignore = advanced,
            a2_reminders = advanced,
        }
        for id, open in pairs(desired) do
            local stateKey = prefix .. id
            state[stateKey] = open and true or false
            if b and b.collapsibles then
                for i = 1, #b.collapsibles do
                    local entry = b.collapsibles[i]
                    if entry and entry.stateKey == stateKey then
                        entry.open = open and true or false
                    end
                end
            end
        end
        if type(M.PersistMenuStateValue) == "function" then M.PersistMenuStateValue("auraUXMode", advanced and "advanced" or "basic") end
        local rebuilt = false
        local key = (ctx and ctx.key) or M.activeKey or "auras2"
        if M.InvalidatePage and M.SelectPage and M.frame and M.frame.IsShown and M.frame:IsShown() then
            M.InvalidatePage(key)
            M.activeKey = nil
            rebuilt = M.SelectPage(key) and true or false
        end
        if not rebuilt then
            if b and b.RelayoutCollapsibles then b:RelayoutCollapsibles() end
            if M.Refresh then M.Refresh(ctx) end
        end
    end

    local function IsAdvancedUXMode()
        local state = AuraAccordionState()
        local prefix = tostring(ctx.key or "page") .. ":"
        return state[prefix .. "a2_filters"] == true
            or state[prefix .. "a2_text_coloring"] == true
            or state[prefix .. "a2_private"] == true
            or state[prefix .. "a2_ignore"] == true
            or state[prefix .. "a2_reminders"] == true
    end

    local hasSidePreview = contentW >= 860
    local previewW = hasSidePreview and min(420, max(360, floor(contentW * 0.34))) or max(320, contentW - 28)
    local leftW = hasSidePreview and max(380, contentW - previewW - 42) or max(320, contentW - 28)
    local compactSetup = leftW < 660
    local setupGap = 12
    local essentialsH = compactSetup and 150 or 128
    local scopeH = compactSetup and 226 or 142
    local presetH = compactSetup and 214 or 128
    local cardsBottomOffset = 38 + essentialsH + setupGap + scopeH + setupGap + presetH
    local previewH = hasSidePreview and max(348, min(388, cardsBottomOffset - 44)) or 350
    local controlH = hasSidePreview and (cardsBottomOffset + 44) or (cardsBottomOffset + previewH + 72)
    local control = b:Section("Aura Setup", controlH)

    local essentialsY = -38
    local scopeY = essentialsY - essentialsH - setupGap
    local presetY = scopeY - scopeH - setupGap
    local essentials = W.ControlCard(control, "1. Essentials", nil, 14, essentialsY, leftW, essentialsH)
    local scopeCard = W.ControlCard(control, "2. Scope", nil, 14, scopeY, leftW, scopeH)
    local presetCard = W.ControlCard(control, "3. Preset & View", nil, 14, presetY, leftW, presetH)

    local switchCols = compactSetup and 2 or 4
    local switchColW = floor((leftW - 32) / switchCols)
    local switchLabelW = max(80, min(154, switchColW - 48))
    local function SwitchX(index)
        return 16 + ((index - 1) % switchCols) * switchColW
    end
    local function SwitchY(index)
        return -50 - floor((index - 1) / switchCols) * 28
    end
    local function EssentialSwitch(index, label, getValue, setValue, trackList)
        local sw = W.SwitchAt(essentials, label, SwitchX(index), SwitchY(index), switchLabelW)
        M.BindToggle(ctx, sw,
            function() return getValue() and true or false end,
            function(v) setValue(v and true or false) end)
        if trackList then Track(trackList, sw) end
        return sw
    end

    EssentialSwitch(1, "Unit Auras",
        function() return BoolValue(AurasDB(), "enabled", true) end,
        function(v) SetValue(AurasDB(), "enabled", v, ApplyUnitAuraEnabled) end,
        sharedOnlyControls)
    EssentialSwitch(2, "Filters",
        function() return BoolValue(AuraFilters(), "enabled", true) end,
        function(v)
            if AuraScope() ~= "shared" then ForceAuraFilterOverride() end
            SetValue(AuraFilters(), "enabled", v, ApplyAuras)
        end,
        filterOverrideControls)
    EssentialSwitch(3, "Edit Preview",
        function() return BoolValue(AuraShared(), "showInEditMode", true) end,
        function(v) SetValue(AuraShared(), "showInEditMode", v, ApplyAuras) end,
        sharedOnlyControls)
    EssentialSwitch(4, "Masque",
        function() return BoolValue(AuraShared(), "masqueEnabled", false) end,
        function(v) SetValue(AuraShared(), "masqueEnabled", v, ApplyAuras) end,
        sharedOnlyControls)

    local unitY = compactSetup and -106 or -88
    LabelAt(essentials, "Visible units", 16, unitY + 4, 88, "GameFontNormalSmall", T.colors.muted)
    local unitPillPos = FlowTopLeft({ 90, 90, 90, 96 }, 112, unitY + 8, leftW - 16, 6, 28, 22)
    Track(sharedOnlyControls, TogglePillAt(ctx, essentials, "Player", unitPillPos[1].x, unitPillPos[1].y, unitPillPos[1].width, function() return AurasDB() end, "showPlayer", false, ApplyAuras))
    Track(sharedOnlyControls, TogglePillAt(ctx, essentials, "Target", unitPillPos[2].x, unitPillPos[2].y, unitPillPos[2].width, function() return AurasDB() end, "showTarget", true, ApplyAuras))
    Track(sharedOnlyControls, TogglePillAt(ctx, essentials, "Focus", unitPillPos[3].x, unitPillPos[3].y, unitPillPos[3].width, function() return AurasDB() end, "showFocus", true, ApplyAuras))
    Track(sharedOnlyControls, TogglePillAt(ctx, essentials, "Boss 1-5", unitPillPos[4].x, unitPillPos[4].y, unitPillPos[4].width, function() return AurasDB() end, "showBoss", true, ApplyAuras))

    local scopeDropdownW = compactSetup and max(190, min(260, leftW - 32)) or max(210, min(260, floor(leftW * 0.28)))
    local scopeDrop = ValueDropdownAt(ctx, scopeCard, "Editing scope", 16, -50, AURA_SCOPES, scopeDropdownW,
        AuraScope,
        function(value)
            if type(M.PersistMenuStateValue) == "function" then
                M.PersistMenuStateValue("auraScope", value or "shared")
            else
                M.auraScope = value or "shared"
            end
            RefreshAurasPage(ctx)
        end)
    local scopeSummaryX = compactSetup and 16 or (scopeDropdownW + 42)
    local scopeSummaryY = compactSetup and -96 or -52
    local scopeSummaryW = compactSetup and (leftW - 32) or max(120, leftW - scopeSummaryX - 16)
    local scopeSummary = LabelAt(scopeCard, "", scopeSummaryX, scopeSummaryY, scopeSummaryW, "GameFontDisableSmall", T.colors.muted)
    if scopeSummary.SetWordWrap then scopeSummary:SetWordWrap(true) end
    if scopeSummary.SetHeight then scopeSummary:SetHeight(compactSetup and 34 or 34) end

    local function RefreshScopeButtons()
        if scopeDrop and scopeDrop.SetValue then scopeDrop:SetValue(AuraScope()) end
    end
    M.AddRefresher(ctx, RefreshScopeButtons)

    local overrideY = compactSetup and -142 or -108
    LabelAt(scopeCard, "Overrides", 16, overrideY + 4, 76, "GameFontNormalSmall", T.colors.muted)
    local overrideStartX = compactSetup and 16 or 106
    local overridePos = FlowTopLeft({ 128, 112, 120, 118, 92, 82 }, overrideStartX, overrideY + 8, leftW - 16, 8, 28, 22)
    local overrideFilters = FitInlineToggle(ValueToggleAt(ctx, scopeCard, "Custom filters", overridePos[1].x, overridePos[1].y,
        function()
            local s = AuraScope()
            return s ~= "shared" and AurasUnit(s).overrideFilters == true
        end,
        function(v)
            local s = AuraScope()
            if s == "shared" then return end
            if v then ForceAuraFilterOverride() else AurasUnit(s).overrideFilters = false end
            ApplyAuras()
            RefreshScopeButtons()
            RefreshAurasPage(ctx)
        end), overridePos[1].width)
    local overrideCaps = FitInlineToggle(ValueToggleAt(ctx, scopeCard, "Custom caps", overridePos[2].x, overridePos[2].y,
        function()
            local s = AuraScope()
            return s ~= "shared" and AurasUnit(s).overrideSharedLayout == true
        end,
        function(v)
            local s = AuraScope()
            if s == "shared" then return end
            if v then ForceAuraCapsOverride() else AurasUnit(s).overrideSharedLayout = false end
            ApplyAuras()
            RefreshScopeButtons()
            RefreshAurasPage(ctx)
        end), overridePos[2].width)
    local overrideLayout = FitInlineToggle(ValueToggleAt(ctx, scopeCard, "Custom layout", overridePos[3].x, overridePos[3].y,
        function()
            local s = AuraScope()
            return s ~= "shared" and AurasUnit(s).overrideLayout == true
        end,
        function(v)
            local s = AuraScope()
            if s == "shared" then return end
            if v then ForceAuraLayoutOverride() else AurasUnit(s).overrideLayout = false end
            ApplyAuras()
            RefreshScopeButtons()
            RefreshAurasPage(ctx)
        end), overridePos[3].width)
    local overrideIgnoreTop = FitInlineToggle(ValueToggleAt(ctx, scopeCard, "Custom ignore", overridePos[4].x, overridePos[4].y,
        function()
            local s = AuraScope()
            return s ~= "shared" and AurasUnit(s).overrideIgnore == true
        end,
        function(v)
            local s = AuraScope()
            if s == "shared" then return end
            if v then ForceAuraIgnoreOverride() else AurasUnit(s).overrideIgnore = false end
            ApplyAuras()
            RefreshScopeButtons()
            RefreshAurasPage(ctx)
        end), overridePos[4].width)
    local resetScope = T.Button(scopeCard, "Reset scope", overridePos[5].width, 22)
    resetScope:SetPoint("TOPLEFT", scopeCard, "TOPLEFT", overridePos[5].x, overridePos[5].y + 1)
    resetScope:SetScript("OnClick", function()
        M.CaptureHistory("Reset aura scope", "auras2:scope:reset", ResetSelectedScope)
    end)
    local resetAll = T.Button(scopeCard, "Reset all", overridePos[6].width, 22)
    resetAll:SetPoint("TOPLEFT", scopeCard, "TOPLEFT", overridePos[6].x, overridePos[6].y + 1)
    resetAll:SetScript("OnClick", function()
        M.CaptureHistory("Reset all aura overrides", "auras2:overrides:reset", ResetAllAuraOverrides)
    end)

    LabelAt(presetCard, "Quick setup", 16, -50, 92, "GameFontNormalSmall", T.colors.muted)
    local quickY = compactSetup and -70 or -66
    local quickPos, quickBottomY = FlowTopLeft({ 108, 132, 104 }, compactSetup and 16 or 112, quickY, leftW - 16, 8, 28, 24)
    local presetHintX = compactSetup and 16 or 472
    local presetHintY = compactSetup and (quickBottomY - 14) or -52
    local presetHintW = compactSetup and (leftW - 32) or max(120, leftW - presetHintX - 16)
    local presetHint = LabelAt(presetCard, "", presetHintX, presetHintY, presetHintW, "GameFontDisableSmall", T.colors.muted)
    if presetHint.SetWordWrap then presetHint:SetWordWrap(true) end
    if presetHint.SetHeight then presetHint:SetHeight(44) end
    local quickIndex = 0
    local function QuickButton(name, label)
        quickIndex = quickIndex + 1
        local p = QUICK_PRESETS[name]
        local pos = quickPos[quickIndex]
        local btn = T.Button(presetCard, label or p.label, pos.width or 102, 24)
        btn:SetPoint("TOPLEFT", presetCard, "TOPLEFT", pos.x, pos.y)
        btn:SetScript("OnClick", function()
            previewPreset = nil
            M.CaptureHistory("Apply aura preset " .. p.label, "auras2:preset:" .. name, function() ApplyQuickPreset(name) end)
        end)
        btn:HookScript("OnEnter", function()
            previewPreset = name
            if M.Refresh then M.Refresh(ctx) end
        end)
        btn:HookScript("OnLeave", function()
            if previewPreset == name then
                previewPreset = nil
                if M.Refresh then M.Refresh(ctx) end
            end
        end)
        return btn
    end
    QuickButton("clean", "Clean 6/12")
    QuickButton("focused", "Focused 10/16")
    QuickButton("performance", "Fast 4/8")

    local modeY = compactSetup and (presetHintY - 54) or -108
    LabelAt(presetCard, "Show", 16, modeY + 4, 76, "GameFontNormalSmall", T.colors.muted)
    local basicMode = T.Button(presetCard, "Basic", 104, 24)
    basicMode:SetPoint("TOPLEFT", presetCard, "TOPLEFT", compactSetup and 86 or 112, modeY + 8)
    basicMode:SetScript("OnClick", function() SetAurasUXMode("basic") end)
    local advancedMode = T.Button(presetCard, "All settings", 124, 24)
    advancedMode:SetPoint("TOPLEFT", presetCard, "TOPLEFT", compactSetup and 198 or 224, modeY + 8)
    advancedMode:SetScript("OnClick", function() SetAurasUXMode("advanced") end)

    local previewX = hasSidePreview and (leftW + 28) or 14
    local previewY = hasSidePreview and -38 or (-cardsBottomOffset - 24)
    local preview = T.Panel(control, nil, { 0.018, 0.026, 0.052, 0.88 }, T.colors.cardBorder or T.colors.borderSoft)
    preview:SetPoint("TOPLEFT", control, "TOPLEFT", previewX, previewY)
    preview:SetSize(previewW, previewH)
    LabelAt(preview, "Aura Preview", 14, -14, previewW - 28, "GameFontNormal", T.colors.text)
    local previewChips = {
        LabelAt(preview, "", 14, -40, 90, "GameFontDisableSmall", T.colors.muted),
        LabelAt(preview, "", 112, -40, 90, "GameFontDisableSmall", T.colors.muted),
        LabelAt(preview, "", 210, -40, previewW - 224, "GameFontDisableSmall", T.colors.accent2),
    }
    local stage = T.Panel(preview, nil, { 0.010, 0.014, 0.030, 0.70 }, T.colors.borderSoft)
    stage:SetPoint("TOPLEFT", preview, "TOPLEFT", 14, -64)
    stage:SetSize(previewW - 28, previewH - 136)
    local groupLabels = {
        buffs = LabelAt(stage, "", 10, -10, previewW - 48, "GameFontNormalSmall", T.colors.text),
        debuffs = LabelAt(stage, "", 10, -78, previewW - 48, "GameFontNormalSmall", T.colors.text),
        private = LabelAt(stage, "", 10, -146, previewW - 48, "GameFontNormalSmall", T.colors.text),
    }
    local previewMeta = LabelAt(preview, "", 14, -previewH + 60, previewW - 28, "GameFontDisableSmall", T.colors.muted)
    if previewMeta.SetWordWrap then previewMeta:SetWordWrap(true) end
    local iconPools = { buffs = {}, debuffs = {}, private = {} }
    local function PreviewIconSet(globalName, fallback)
        local icons = _G and _G[globalName]
        if type(icons) == "table" and #icons > 0 then return icons end
        return fallback
    end
    local PREVIEW_AURA_ICONS = {
        buff = PreviewIconSet("MSUF_A2_PREVIEW_BUFF_TEXTURES", { 136116, 135932, 135987, 136085, 135915, 132333, 136075, 135981, 136076, 135964, 136048, 132316 }),
        debuff = PreviewIconSet("MSUF_A2_PREVIEW_DEBUFF_TEXTURES", { 136118, 136139, 136197, 135817, 132851, 135813, 136188, 136186, 135975, 132337, 136093, 136170 }),
        private = { 136177, 134400, 135894, 136116, 135987, 136085, 132333, 135932, 136075, 135981, 136048, 132316 },
    }
    local DEBUFF_BORDER_COLORS = {
        { 0.32, 0.58, 1.00, 0.96 },
        { 0.72, 0.38, 1.00, 0.96 },
        { 0.28, 0.82, 0.44, 0.96 },
        { 0.72, 0.48, 0.22, 0.96 },
    }
    local function SetPreviewIconTexture(icon, texture)
        if type(_G.MSUF_SetIconTexture) == "function" then
            _G.MSUF_SetIconTexture(icon.icon, texture, "")
        else
            icon.icon:SetTexture(texture)
        end
        if icon.icon.SetTexCoord then icon.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end
    local function PaintPreviewBorder(icon, r, g, b, a)
        for i = 1, #icon.border do
            icon.border[i]:SetVertexColor(r, g, b, a or 1)
        end
    end
    local function CreatePreviewIcon(kind)
        local f = CreateFrame("Frame", nil, stage)
        f.shadow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
        f.shadow:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
        f.shadow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
        f.shadow:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.shadow:SetVertexColor(0, 0, 0, 0.85)
        f.icon = f:CreateTexture(nil, "BACKGROUND")
        f.icon:SetAllPoints(f)
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.cooldownShade = f:CreateTexture(nil, "ARTWORK")
        f.cooldownShade:SetAllPoints(f)
        f.cooldownShade:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.border = {}
        f.border[1] = f:CreateTexture(nil, "BORDER")
        f.border[1]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f.border[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        f.border[1]:SetHeight(2)
        f.border[2] = f:CreateTexture(nil, "BORDER")
        f.border[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        f.border[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        f.border[2]:SetHeight(2)
        f.border[3] = f:CreateTexture(nil, "BORDER")
        f.border[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f.border[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        f.border[3]:SetWidth(2)
        f.border[4] = f:CreateTexture(nil, "BORDER")
        f.border[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        f.border[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        f.border[4]:SetWidth(2)
        for i = 1, #f.border do f.border[i]:SetTexture("Interface\\Buttons\\WHITE8X8") end
        f.timer = T.Font(f, nil, "", T.colors.text)
        f.timer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 1)
        if f.timer.SetShadowColor then f.timer:SetShadowColor(0, 0, 0, 1) end
        if f.timer.SetShadowOffset then f.timer:SetShadowOffset(1, -1) end
        f.stack = T.Font(f, nil, "", T.colors.text)
        f.stack:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -1)
        if f.stack.SetShadowColor then f.stack:SetShadowColor(0, 0, 0, 1) end
        if f.stack.SetShadowOffset then f.stack:SetShadowOffset(1, -1) end
        f.privateLock = f:CreateTexture(nil, "OVERLAY")
        f.privateLock:SetTexture(134400)
        f.privateLock:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        f.privateLock:Hide()
        f._kind = kind
        return f
    end
    for i = 1, 40 do
        iconPools.buffs[i] = CreatePreviewIcon("buff")
        iconPools.debuffs[i] = CreatePreviewIcon("debuff")
    end
    for i = 1, 12 do iconPools.private[i] = CreatePreviewIcon("private") end

    local function DrawIconPool(pool, count, startX, startY, iconSize, spacing, perRow, kind)
        perRow = max(1, perRow)
        local icons = PREVIEW_AURA_ICONS[kind] or PREVIEW_AURA_ICONS.buff
        for i = 1, #pool do
            local icon = pool[i]
            if i <= count then
                local row = floor((i - 1) / perRow)
                local col = (i - 1) % perRow
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", stage, "TOPLEFT", startX + col * (iconSize + spacing), startY - row * (iconSize + spacing))
                icon:SetSize(iconSize, iconSize)
                SetPreviewIconTexture(icon, icons[((i - 1) % #icons) + 1])
                if icon.cooldownShade then
                    local shade = BoolValue(AuraShared(), "showCooldownSwipe", true) and (i % 3 == 0 and 0.34 or 0.16) or 0
                    icon.cooldownShade:SetVertexColor(0, 0, 0, shade)
                end
                if icon.privateLock then
                    if kind == "private" then
                        local lockSize = max(9, floor(iconSize * 0.38))
                        icon.privateLock:SetSize(lockSize, lockSize)
                        icon.privateLock:Show()
                    else
                        icon.privateLock:Hide()
                    end
                end
                if kind == "debuff" and BoolValue(AuraShared(), "useDebuffTypeBorders", false) then
                    local d = DEBUFF_BORDER_COLORS[((i - 1) % #DEBUFF_BORDER_COLORS) + 1]
                    PaintPreviewBorder(icon, d[1], d[2], d[3], d[4])
                elseif (icon._kind == "buff" and BoolValue(AuraShared(), "highlightOwnBuffs", false) and i % 4 == 1)
                    or (icon._kind == "debuff" and BoolValue(AuraShared(), "highlightOwnDebuffs", false) and i % 5 == 1)
                    or icon._kind == "private" then
                    PaintPreviewBorder(icon, 0.96, 0.76, 0.22, 0.96)
                elseif kind == "buff" then
                    PaintPreviewBorder(icon, 0.18, 0.66, 0.36, 0.82)
                elseif kind == "debuff" then
                    PaintPreviewBorder(icon, 0.74, 0.18, 0.24, 0.86)
                else
                    PaintPreviewBorder(icon, 0.58, 0.38, 0.96, 0.92)
                end
                icon.timer:SetText(BoolValue(AuraShared(), "showCooldownText", true) and (icon._kind == "buff" and (i % 3 == 0 and "2m" or "42") or icon._kind == "private" and "P" or tostring(({ 8, 14, 22, 4 })[((i - 1) % 4) + 1])) or "")
                icon.stack:SetText(BoolValue(AuraShared(), "showStackCount", true) and (i % 3 == 1 and "2" or "") or "")
                icon:Show()
            else
                icon:Hide()
            end
        end
    end

    local function RefreshPreview()
        local caps = EffectiveCapsValues()
        local shared = AuraShared()
        local stageW = tonumber(stage.GetWidth and stage:GetWidth()) or (previewW - 28)
        if stageW < 80 then stageW = previewW - 28 end
        local iconSize = max(18, min(34, caps.iconSize))
        local spacing = max(1, min(6, caps.spacing))
        local perRow = max(1, min(caps.perRow, floor((stageW - 22) / (iconSize + spacing))))
        local buffCount = BoolValue(shared, "showBuffs", true) and max(0, min(40, caps.maxBuffs)) or 0
        local debuffCount = BoolValue(shared, "showDebuffs", true) and max(0, min(40, caps.maxDebuffs)) or 0
        local privateCount = (BoolValue(shared, "privateAurasEnabled", true) and BoolValue(shared, "showPrivateAurasPlayer", true)) and max(0, min(12, caps.privateMax)) or 0
        local budget, total, budgetColor = BudgetInfo()
        previewChips[1]:SetText("Auras only")
        previewChips[2]:SetText("Scope: " .. AuraScopeLabel())
        previewChips[3]:SetText((previewPreset and (QUICK_PRESETS[previewPreset].label .. " preview") or ("Budget: " .. budget)))
        if previewChips[3].SetTextColor and budgetColor then previewChips[3]:SetTextColor(budgetColor[1], budgetColor[2], budgetColor[3], 1) end
        groupLabels.buffs:SetText("Buffs  " .. buffCount .. "/" .. caps.maxBuffs .. " shown")
        groupLabels.debuffs:SetText("Debuffs  " .. debuffCount .. "/" .. caps.maxDebuffs .. " shown")
        groupLabels.private:SetText("Private  " .. privateCount .. "/" .. caps.privateMax .. " shown")
        local function RowsFor(count)
            return max(1, floor((max(0, count) + perRow - 1) / perRow))
        end
        local function MoveGroupLabel(label, y)
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", stage, "TOPLEFT", 10, y)
        end
        local buffRows = RowsFor(buffCount)
        local debuffRows = RowsFor(debuffCount)
        local buffY = -10
        local buffIconsY = buffY - 20
        local debuffY = buffIconsY - buffRows * (iconSize + spacing) - 14
        local debuffIconsY = debuffY - 20
        local privateY = debuffIconsY - debuffRows * (iconSize + spacing) - 14
        local privateIconsY = privateY - 20
        MoveGroupLabel(groupLabels.buffs, buffY)
        MoveGroupLabel(groupLabels.debuffs, debuffY)
        MoveGroupLabel(groupLabels.private, privateY)
        DrawIconPool(iconPools.buffs, buffCount, 10, buffIconsY, iconSize, spacing, perRow, "buff")
        DrawIconPool(iconPools.debuffs, debuffCount, 10, debuffIconsY, iconSize, spacing, perRow, "debuff")
        DrawIconPool(iconPools.private, privateCount, 10, privateIconsY, iconSize, spacing, perRow, "private")
        previewMeta:SetText("Icon " .. caps.iconSize .. "px   Per row " .. caps.perRow .. "   Total " .. total .. "   Sort " .. SortLabel(caps.sortOrder))
    end
    M.AddRefresher(ctx, RefreshPreview)

    M.AddRefresher(ctx, function()
        local budget, total = BudgetInfo()
        local active = {}
        for i = 2, #AURA_SCOPES do
            local spec = AURA_SCOPES[i]
            if AuraHasOverride(spec.value) then active[#active + 1] = M.Tr(spec.text or "") end
        end
        local isShared = AuraScope() == "shared"
        if isShared and #active == 0 then
            scopeSummary:SetText("|cffffffff" .. M.Tr("Shared baseline") .. "|r\n|cff9aa0a6" .. M.Tr("No unit overrides are active.") .. "|r")
        elseif isShared then
            scopeSummary:SetText("|cffffffff" .. M.Tr("Shared baseline") .. "|r\n|cff9aa0a6" .. tostring(#active) .. M.Tr(" unit scopes override it: ") .. table.concat(active, ", ") .. "|r")
        else
            local selected = AuraScope()
            if AuraHasOverride(selected) then
                scopeSummary:SetText("|cffffffff" .. AuraScopeLabel() .. M.Tr(" uses custom aura settings.") .. "|r\n|cff9aa0a6" .. M.Tr("Shared still controls every unchecked group.") .. "|r")
            else
                scopeSummary:SetText("|cffffffff" .. AuraScopeLabel() .. "|r\n|cff9aa0a6" .. M.Tr("Inherits Shared until a custom checkbox is enabled.") .. "|r")
            end
        end
        if presetHint then
            if previewPreset and QUICK_PRESETS[previewPreset] then
                local p = QUICK_PRESETS[previewPreset]
                presetHint:SetText(M.Tr(p.label) .. ": " .. tostring(p.maxBuffs) .. M.Tr(" buffs, ") .. tostring(p.maxDebuffs) .. M.Tr(" debuffs, ") .. tostring(p.iconSize) .. "px")
            else
                presetHint:SetText(tostring(ActiveAuraUnitCount()) .. M.Tr(" visible groups, ") .. budget .. M.Tr(" budget, ") .. tostring(total) .. M.Tr(" max icons"))
            end
        end
        SetControlEnabled(overrideFilters, not isShared)
        SetControlEnabled(overrideCaps, not isShared)
        SetControlEnabled(overrideLayout, not isShared)
        SetControlEnabled(overrideIgnoreTop, not isShared)
        SetControlEnabled(resetScope, not isShared and AuraHasOverride(AuraScope()))
        SetControlEnabled(resetAll, #active > 0)
        local advancedModeActive = IsAdvancedUXMode()
        if basicMode.SetActive then basicMode:SetActive(not advancedModeActive) end
        if advancedMode.SetActive then advancedMode:SetActive(advancedModeActive) end
        RefreshScopeButtons()
        RefreshPreview()
    end)

    local compactDisplay = contentW < 560
    local displayCol1 = 14
    local displayCol2 = compactDisplay and max(188, min(210, floor(contentW * 0.52))) or 200
    local displayCol3 = compactDisplay and displayCol1 or 390
    local displayCol1W = max(130, displayCol2 - displayCol1 - 14)
    local displayCol2W = compactDisplay and max(130, contentW - displayCol2 - 14) or 170
    local displayCol3W = compactDisplay and displayCol1W or max(130, contentW - displayCol3 - 14)
    local bossLabelY = compactDisplay and -120 or -12
    local bossToggleY = bossLabelY - 16
    local dividerY = compactDisplay and -188 or -120
    local lowerLabelY = dividerY - 8
    local lowerToggleY = lowerLabelY - 16
    local borderLabelY = compactDisplay and (lowerLabelY - 88) or lowerLabelY
    local borderToggleY = borderLabelY - 16
    local displayHintY = borderToggleY - 70
    local displayBaseH = compactDisplay and max(244, abs(borderToggleY - 24) + 18) or 244
    local masterH = max(displayBaseH, abs(displayHintY) + 58)

    local master = b:CollapsibleSection("a2_display", "Display", masterH, true)
    LabelAt(master, "|cff6EB5FFBuffs|r", displayCol1, -12, displayCol1W)
    LabelAt(master, "|cff6EB5FFDebuffs|r", displayCol2, -12, displayCol2W)
    LabelAt(master, "|cff6EB5FFBoss Heal Auras|r", displayCol3, bossLabelY, displayCol3W)
    local hidePermanentTooltip = "Hides buffs with no duration. Debuffs are never hidden by this option.\n\nThis filter is applied out of combat only. Target/Focus APIs may still show permanent buffs during combat due to API limitations."
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Show Buffs", displayCol1 - 2, -28, AuraShared, "showBuffs", true, ApplyAuras), displayCol1W))
    Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, master, "Only my buffs", displayCol1 - 2, -50, AuraBuffFilters, "onlyMine", false, ForceAuraFilterOverride, ApplyAuras), displayCol1W))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Highlight own buffs", displayCol1 - 2, -74, AuraShared, "highlightOwnBuffs", false, ApplyAuras), displayCol1W))
    Track(filterOverrideControls, AddTooltip(FitInlineToggle(ScopedToggleAt(ctx, master, "Hide permanent buffs", displayCol1 - 2, -96, AuraFilters, "hidePermanent", false, ForceAuraFilterOverride, ApplyAuras), displayCol1W), "Hide permanent buffs", hidePermanentTooltip))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Show Debuffs", displayCol2 - 2, -28, AuraShared, "showDebuffs", true, ApplyAuras), displayCol2W))
    Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, master, "Only my debuffs", displayCol2 - 2, -50, AuraDebuffFilters, "onlyMine", false, ForceAuraFilterOverride, ApplyAuras), displayCol2W))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Highlight own debuffs", displayCol2 - 2, -74, AuraShared, "highlightOwnDebuffs", false, ApplyAuras), displayCol2W))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Highlight own healer buffs", displayCol3 - 2, bossToggleY, BossHealAuras, "highlightOwn", false, ApplyAuras), displayCol3W))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Hide other healer buffs", displayCol3 - 2, bossToggleY - 22, BossHealAuras, "hideOthers", false, ApplyAuras), displayCol3W))
    DividerAt(master, dividerY)
    LabelAt(master, "|cff6EB5FFIcons|r", displayCol1, lowerLabelY, displayCol1W)
    LabelAt(master, "|cff6EB5FFCooldown|r", displayCol2, lowerLabelY, displayCol2W)
    LabelAt(master, "|cff6EB5FFBorders|r", displayCol3, borderLabelY, displayCol3W)
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Show tooltip", displayCol1 - 2, lowerToggleY, AuraShared, "showTooltip", true, ApplyAuras), displayCol1W))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Show stack count", displayCol1 - 2, lowerToggleY - 22, AuraShared, "showStackCount", true, ApplyAuras), displayCol1W))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Click-through auras", displayCol1 - 2, lowerToggleY - 44, AuraShared, "clickThroughAuras", false, ApplyAuras), displayCol1W))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Show cooldown swipe", displayCol2 - 2, lowerToggleY, AuraShared, "showCooldownSwipe", true, ApplyAuras), displayCol2W))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Swipe darkens on loss", displayCol2 - 2, lowerToggleY - 22, AuraShared, "cooldownSwipeDarkenOnLoss", false, ApplyAuras), displayCol2W))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Show cooldown text", displayCol2 - 2, lowerToggleY - 44, AuraShared, "showCooldownText", true, ApplyAuras), displayCol2W))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Dispel-type borders", displayCol3 - 2, borderToggleY, AuraShared, "useDebuffTypeBorders", false, ApplyAuras), displayCol3W))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, master, "Hide Masque borders", displayCol3 - 2, borderToggleY - 22, AuraShared, "masqueHideBorder", false, ApplyAuras), displayCol3W))
    local displayScopeHint = W.Text(master, "Player-only buff hiding uses Custom caps and Max Buffs 0 because Show Buffs is shared.", 14, displayHintY, contentW - 28, T.colors.muted)
    if displayScopeHint.SetWordWrap then displayScopeHint:SetWordWrap(true) end
    if displayScopeHint.SetHeight then displayScopeHint:SetHeight(52) end
    M.AddRefresher(ctx, function()
        local scopeKey = AuraScope()
        local scopeName = AuraScopeLabel()
        if scopeKey == "shared" then
            displayScopeHint:SetText(M.Tr("Need to hide buffs only for one unit? Select that unit above, enable Custom caps, then set Caps & Icons > Max Buffs to 0."))
        elseif UnitOverrideEnabled("overrideSharedLayout") then
            displayScopeHint:SetText(M.Format("Editing %s caps. Use Caps & Icons > Max Buffs = 0 to hide buffs only for this unit; Max Debuffs = 0 hides debuffs.", scopeName))
        else
            displayScopeHint:SetText(M.Format("Show Buffs is shared and stays locked while editing %s. Enable Custom caps, then set Caps & Icons > Max Buffs to 0 to hide buffs only for this unit.", scopeName))
        end
    end)

    local layout = b:CollapsibleSection("a2_layout", "Caps & Icons", 466, true)
    local layoutW = layout._msuf2Width or ctx.width or 900
    local layoutPad, layoutGap = 32, 26
    local layoutColW = floor((layoutW - layoutPad * 2 - layoutGap * 3) / 4)
    if layoutColW < 180 then layoutColW = 180 end
    local layoutCol1 = layoutPad
    local layoutCol2 = layoutCol1 + layoutColW + layoutGap
    local layoutCol3 = layoutCol2 + layoutColW + layoutGap
    local layoutCol4 = layoutCol3 + layoutColW + layoutGap
    local layoutSliderW = max(196, min(250, layoutColW))
    local layoutDropdownW = max(190, min(260, layoutColW))

    LabelAt(layout, "Limits", layoutCol1, -38, layoutColW, "GameFontNormalSmall", T.colors.accent)
    LabelAt(layout, "Density", layoutCol3, -38, layoutColW, "GameFontNormalSmall", T.colors.accent)
    Track(capsOverrideControls, ScopedSliderAt(ctx, layout, "Max Buffs", layoutCol1, -64, 0, 40, 1, layoutSliderW, function() return AuraCaps() end, "maxBuffs", 8, ForceAuraCapsOverride, ApplyAuras))
    Track(capsOverrideControls, ScopedSliderAt(ctx, layout, "Max Debuffs", layoutCol2, -64, 0, 40, 1, layoutSliderW, function() return AuraCaps() end, "maxDebuffs", 15, ForceAuraCapsOverride, ApplyAuras))
    Track(capsOverrideControls, ScopedSliderAt(ctx, layout, "Icons per row", layoutCol3, -64, 1, 20, 1, layoutSliderW, function() return AuraCaps() end, "perRow", 11, ForceAuraCapsOverride, ApplyAuras))
    Track(capsOverrideControls, ScopedSliderAt(ctx, layout, "Block spacing", layoutCol4, -64, 0, 40, 1, layoutSliderW, function() return AuraCaps() end, "splitSpacing", 0, ForceAuraCapsOverride, ApplyAuras))

    DividerAt(layout, -138, layoutPad, 32)
    LabelAt(layout, "Icon Layout", layoutCol1, -160, layoutColW, "GameFontNormalSmall", T.colors.accent)
    LabelAt(layout, "Rows", layoutCol3, -160, layoutColW, "GameFontNormalSmall", T.colors.accent)
    Track(layoutOverrideControls, ScopedSliderAt(ctx, layout, "Icon size", layoutCol1, -186, 12, 64, 1, layoutSliderW, function() return AuraLayout() end, "iconSize", 26, ForceAuraLayoutOverride, ApplyAuras))
    Track(layoutOverrideControls, ScopedSliderAt(ctx, layout, "Spacing", layoutCol2, -186, 0, 12, 1, layoutSliderW, function() return AuraLayout() end, "spacing", 2, ForceAuraLayoutOverride, ApplyAuras))
    Track(capsOverrideControls, ScopedDropdownAt(ctx, layout, "Row layout", layoutCol3, -186, {
        { value = "SEPARATE", text = "Separate rows" },
        { value = "SINGLE", text = "Single row (Mixed)" },
    }, layoutDropdownW, function() return AuraCaps() end, "layoutMode", "SEPARATE", ForceAuraCapsOverride, ApplyAuras))
    Track(capsOverrideControls, ScopedDropdownAt(ctx, layout, "Stack Anchor", layoutCol4, -186, AURA_STACK_ANCHORS, layoutDropdownW, function() return AuraCaps() end, "stackCountAnchor", "TOPRIGHT", ForceAuraCapsOverride, ApplyAuras))

    DividerAt(layout, -260, layoutPad, 32)
    LabelAt(layout, "Growth", layoutCol1, -282, layoutColW, "GameFontNormalSmall", T.colors.accent)
    LabelAt(layout, "Wrapping & Sorting", layoutCol3, -282, layoutColW * 2 + layoutGap, "GameFontNormalSmall", T.colors.accent)
    Track(capsOverrideControls, ValueDropdownAt(ctx, layout, "Buff Growth", layoutCol1, -308, AURA_GROWTH, layoutDropdownW,
        function() local c = AuraCaps(); return c.buffGrowth or c.growth or "RIGHT" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().buffGrowth = v or "RIGHT"; ApplyAuras() end))
    Track(capsOverrideControls, ValueDropdownAt(ctx, layout, "Debuff Growth", layoutCol2, -308, AURA_GROWTH, layoutDropdownW,
        function() local c = AuraCaps(); return c.debuffGrowth or c.growth or "RIGHT" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().debuffGrowth = v or "RIGHT"; ApplyAuras() end))
    Track(capsOverrideControls, ValueDropdownAt(ctx, layout, "Private Growth", layoutCol1, -392, AURA_GROWTH, layoutDropdownW,
        function() local c = AuraCaps(); return c.privateGrowth or c.growth or "RIGHT" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().privateGrowth = v or "RIGHT"; ApplyAuras() end))
    Track(capsOverrideControls, ValueDropdownAt(ctx, layout, "Buff wrap rows", layoutCol3, -308, AURA_ROW_WRAP, layoutDropdownW,
        function() local c = AuraCaps(); return c.buffRowWrap or c.rowWrap or "DOWN" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().buffRowWrap = v or "DOWN"; ApplyAuras() end))
    Track(capsOverrideControls, ValueDropdownAt(ctx, layout, "Debuff wrap rows", layoutCol4, -308, AURA_ROW_WRAP, layoutDropdownW,
        function() local c = AuraCaps(); return c.debuffRowWrap or c.rowWrap or "DOWN" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().debuffRowWrap = v or "DOWN"; ApplyAuras() end))
    Track(capsOverrideControls, ValueDropdownAt(ctx, layout, "Sort order", layoutCol3, -392, AURA_SORT_ORDER, layoutDropdownW * 2 + layoutGap,
        function()
            local c = AuraCaps()
            if type(c.sortOrder) == "number" then return c.sortOrder end
            local f = AuraFilters()
            return (f and type(f.sortOrder) == "number") and f.sortOrder or 0
        end,
        function(v)
            ForceAuraCapsOverride()
            AuraCaps().sortOrder = tonumber(v) or 0
            ApplyAuras()
        end))

    M.AddRefresher(ctx, function()
        local sharedScope = IsSharedScope()
        W.SetControlsEnabled(sharedOnlyControls, sharedScope)
        W.SetControlsEnabled(filterOverrideControls, sharedScope or UnitOverrideEnabled("overrideFilters"))
        W.SetControlsEnabled(capsOverrideControls, sharedScope or UnitOverrideEnabled("overrideSharedLayout"))
        W.SetControlsEnabled(layoutOverrideControls, sharedScope or UnitOverrideEnabled("overrideLayout"))
    end)

    if IsAdvancedUXMode() then
    local visual = b:CollapsibleSection("a2_text_coloring", "Text Coloring", 520, false)
    LabelAt(visual, "Cooldown Timer Text", 12, -10, 240, "GameFontNormal", T.colors.text)
    W.Text(visual, "Blizzard native timer text keeps aura countdowns cheap; MSUF only applies the configured colors.", 12, -34, 650, T.colors.muted)
    Track(sharedOnlyControls, ToggleAt(ctx, visual, "Use Blizzard timer text (max performance)", 12, -66, AuraShared, "useBlizzardTimerText", true, ApplyAuras))
    Track(sharedOnlyControls, ToggleAt(ctx, visual, "Color aura timers by remaining time", 12, -92, G, "aurasCooldownTextUseBuckets", true, ApplyAuras))

    local preview = T.Panel(visual, nil, { 0.030, 0.040, 0.070, 0.62 }, T.colors.borderSoft)
    preview:SetPoint("TOPLEFT", visual, "TOPLEFT", 12, -124)
    preview:SetSize(676, 82)
    LabelAt(preview, "Preview", 10, -31, 100, "GameFontNormalSmall", T.colors.muted)
    local samples = {
        { key = "safe", label = "Safe", text = "60" },
        { key = "warn", label = "Warning", text = "15" },
        { key = "urg", label = "Urgent", text = "5" },
    }
    for i = 1, #samples do
        local box = T.Panel(preview, nil, { 0.020, 0.020, 0.030, 0.85 }, T.colors.borderSoft)
        box:SetPoint("LEFT", preview, "LEFT", 178 + (i - 1) * 126, 0)
        box:SetSize(116, 54)
        local fs = T.Font(box, nil, samples[i].text, T.colors.text)
        fs:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
        fs:SetPoint("CENTER", box, "CENTER", 0, 7)
        box.value = fs
        local lbl = T.Font(box, "GameFontDisableSmall", samples[i].label, T.colors.muted)
        lbl:SetPoint("BOTTOM", box, "BOTTOM", 0, 5)
        samples[i].box = box
    end
    M.AddRefresher(ctx, function()
        local g = G()
        local safeR, safeG, safeB = ReadRGB(g, "aurasCooldownTextSafeColor", 1, 1, 1)
        local warnR, warnG, warnB = ReadRGB(g, "aurasCooldownTextWarningColor", 1, 0.85, 0.20)
        local urgR, urgG, urgB = ReadRGB(g, "aurasCooldownTextUrgentColor", 1, 0.55, 0.10)
        local buckets = g.aurasCooldownTextUseBuckets ~= false
        if samples[1].box.value then samples[1].box.value:SetTextColor(safeR, safeG, safeB, 1) end
        if samples[2].box.value then samples[2].box.value:SetTextColor(buckets and warnR or safeR, buckets and warnG or safeG, buckets and warnB or safeB, 1) end
        if samples[3].box.value then samples[3].box.value:SetTextColor(buckets and urgR or safeR, buckets and urgG or safeG, buckets and urgB or safeB, 1) end
    end)

    Track(sharedOnlyControls, ColorAt(ctx, visual, "Safe", 12, -226, G, "aurasCooldownTextSafeColor", 1, 1, 1, ApplyAuras))
    Track(sharedOnlyControls, ColorAt(ctx, visual, "Warning", 174, -226, G, "aurasCooldownTextWarningColor", 1, 0.85, 0.2, ApplyAuras))
    Track(sharedOnlyControls, ColorAt(ctx, visual, "Urgent", 336, -226, G, "aurasCooldownTextUrgentColor", 1, 0.55, 0.1, ApplyAuras))
    Track(sharedOnlyControls, ColorAt(ctx, visual, "Stack count", 498, -226, G, "aurasStackCountColor", 1, 1, 1, ApplyAuras))
    Track(sharedOnlyControls, SliderAt(ctx, visual, "Safe (seconds)", 12, -270, 0, 600, 1, 190, G, "aurasCooldownTextSafeSeconds", 60, ApplyAuras))
    Track(sharedOnlyControls, SliderAt(ctx, visual, "Warning (<=)", 272, -270, 0, 30, 1, 190, G, "aurasCooldownTextWarningSeconds", 15, ApplyAuras))
    Track(sharedOnlyControls, SliderAt(ctx, visual, "Urgent (<=)", 532, -270, 0, 15, 1, 150, G, "aurasCooldownTextUrgentSeconds", 5, ApplyAuras))
    Track(layoutOverrideControls, ScopedSliderAt(ctx, visual, "Cooldown text size", 12, -330, 6, 32, 1, 190, function() return AuraLayout() end, "cooldownTextSize", 14, ForceAuraLayoutOverride, ApplyAuras))
    Track(layoutOverrideControls, ScopedSliderAt(ctx, visual, "Stack text size", 272, -330, 6, 32, 1, 190, function() return AuraLayout() end, "stackTextSize", 14, ForceAuraLayoutOverride, ApplyAuras))
    DividerAt(visual, -392)
    LabelAt(visual, "Pandemic Window", 16, -408, 240, "GameFontNormal", T.colors.text)
    Track(sharedOnlyControls, ValueSwitchAt(ctx, visual, "Enable Pandemic Window", 12, -436, 240,
        function() return GetPandemicMode() ~= "OFF" end,
        function(v)
            if v then
                SetPandemicMode(M.lastPandemicMode or "PULSE")
            else
                local mode = GetPandemicMode()
                if mode ~= "OFF" then
                    if type(M.PersistMenuStateValue) == "function" then
                        M.PersistMenuStateValue("lastPandemicMode", mode)
                    else
                        M.lastPandemicMode = mode
                    end
                end
                SetPandemicMode("OFF")
            end
        end))
    local pandemicDD = ValueDropdownAt(ctx, visual, "Mode", 284, -420, PANDEMIC_MODES, 150,
        function()
            local mode = GetPandemicMode()
            return mode ~= "OFF" and mode or (M.lastPandemicMode or "PULSE")
        end,
        function(v) SetPandemicMode(v or "PULSE") end)
    W.Text(visual, "Best-effort: fixed 30% remaining-duration threshold for all auras. Color is configured in Global Style > Colors.", 12, -468, 650, T.colors.muted)

    local private = b:CollapsibleSection("a2_private", "Private Auras", 168, false)
    Track(sharedOnlyControls, SwitchAt(ctx, private, "Enable Private Auras", 12, -10, 220, AuraShared, "privateAurasEnabled", true, ApplyAuras))
    local privateShow = ToggleAt(ctx, private, "Show (Player)", 12, -40, AuraShared, "showPrivateAurasPlayer", true, ApplyAuras)
    local privateMax = SliderAt(ctx, private, "Max", 340, -34, 0, 12, 1, 150, AuraShared, "privateAuraMaxPlayer", 4, ApplyAuras)
    local privateBorder = SliderAt(ctx, private, "Border thickness", 520, -34, 0, 10, 0.5, 150, AuraShared, "privateAuraBorderScale", 3, ApplyAuras)
    local privateGrow = DropdownAt(ctx, private, "Grow Direction", 12, -92, AURA_GROWTH, 220, AuraShared, "privateGrowth", "RIGHT", ApplyAuras)

    local filters = b:CollapsibleSection("a2_filters", "Aura Filters & Sorting", 320, false)
    LabelAt(filters, "Extra includes", 12, -10, 160, "GameFontNormal", T.colors.accent)
    filters._msuf2IncludeBossBuffs = Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, filters, "Also show boss buffs", 12, -34, AuraBuffFilters, "includeBoss", false, ForceAuraFilterOverride, ApplyAuras), 330))
    filters._msuf2IncludeBossDebuffs = Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, filters, "Also show boss debuffs", 12, -62, AuraDebuffFilters, "includeBoss", false, ForceAuraFilterOverride, ApplyAuras), 330))
    Track(sharedOnlyControls, FitInlineToggle(ToggleAt(ctx, filters, "Show Sated/Exhaustion", 12, -90, AuraShared, "showSated", true, ApplyAuras), 330))
    filters._msuf2IncludeStealable = Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, filters, "Also show stealable buffs", 12, -118, AuraBuffFilters, "includeStealable", false, ForceAuraFilterOverride, ApplyAuras), 330))
    filters._msuf2IncludeDispellable = Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, filters, "Also show dispellable debuffs", 12, -146, AuraDebuffFilters, "includeDispellable", false, ForceAuraFilterOverride, ApplyAuras), 330))
    LabelAt(filters, "Narrow filters", 380, -10, 160, "GameFontNormal", T.colors.accent)
    Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, filters, "Only boss auras", 380, -34, AuraFilters, "onlyBossAuras", false, ForceAuraFilterOverride, ApplyAuras), 220))
    Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, filters, "Only important buffs", 380, -62, AuraBuffFilters, "onlyImportant", false, ForceAuraFilterOverride, ApplyAuras), 220))
    Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, filters, "Only important debuffs", 380, -90, AuraDebuffFilters, "onlyImportant", false, ForceAuraFilterOverride, ApplyAuras), 220))
    LabelAt(filters, "Dispel exception types", 380, -118, 190, "GameFontNormalSmall", T.colors.muted)
    filters._msuf2DispelMagic = Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, filters, "Magic", 380, -142, AuraDebuffFilters, "dispelMagic", false, ForceAuraFilterOverride, ApplyAuras), 136))
    filters._msuf2DispelPoison = Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, filters, "Poison", 540, -142, AuraDebuffFilters, "dispelPoison", false, ForceAuraFilterOverride, ApplyAuras), 136))
    filters._msuf2DispelCurse = Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, filters, "Curse", 380, -166, AuraDebuffFilters, "dispelCurse", false, ForceAuraFilterOverride, ApplyAuras), 136))
    filters._msuf2DispelDisease = Track(filterOverrideControls, FitInlineToggle(ScopedToggleAt(ctx, filters, "Disease", 540, -166, AuraDebuffFilters, "dispelDisease", false, ForceAuraFilterOverride, ApplyAuras), 136))
    DividerAt(filters, -198)
    Track(sharedOnlyControls, SliderAt(ctx, filters, "Sated threshold", 30, -222, 0, 600, 5, 200, AuraShared, "satedShowAtSeconds", 0, ApplyAuras))
    Track(capsOverrideControls, ValueDropdownAt(ctx, filters, "Sort order", 380, -222, AURA_SORT_ORDER, 270,
        function()
            local c = AuraCaps()
            if type(c.sortOrder) == "number" then return c.sortOrder end
            local f = AuraFilters()
            return (f and type(f.sortOrder) == "number") and f.sortOrder or 0
        end,
        function(v)
            ForceAuraCapsOverride()
            AuraCaps().sortOrder = tonumber(v) or 0
            ApplyAuras()
        end))

    local ignore = b:CollapsibleSection("a2_ignore", "Global Ignore List", 228, false)
    local ignoreLabel = LabelAt(ignore, "", 170, -10, 260, "GameFontHighlightSmall", T.colors.muted)
    local ignoreOverride = ValueToggleAt(ctx, ignore, "Override for this unit", 380, -10,
        function()
            local s = AuraScope()
            return s ~= "shared" and AurasUnit(s).overrideIgnore == true
        end,
        function(v)
            local s = AuraScope()
            if s == "shared" then return end
            if v then
                ForceAuraIgnoreOverride()
            else
                AurasUnit(s).overrideIgnore = false
            end
            ApplyAuras()
            RefreshScopeButtons()
            RefreshAurasPage(ctx)
        end)
    local ignoreControls = {}
    for i = 1, #AURA_IGNORE_CATEGORIES do
        local spec = AURA_IGNORE_CATEGORIES[i]
        local col = (i <= 5) and 12 or 380
        local row = (i <= 5) and i or (i - 5)
        ignoreControls[#ignoreControls + 1] = ScopedToggleAt(ctx, ignore, spec.label, col, -34 - (row - 1) * 28, AuraIgnoreCats, spec.key, false, ForceAuraIgnoreOverride, function()
            local api = ns and ns.MSUF_Auras2
            local cache = api and api.Cache
            if cache and type(cache.InvalidateIgnoreHash) == "function" then pcall(cache.InvalidateIgnoreHash) end
            ApplyAuras()
        end)
    end
    M.AddRefresher(ctx, function()
        local key = AuraScope()
        local isShared = key == "shared"
        local isBoss = key == "boss1" or key == "boss2" or key == "boss3" or key == "boss4" or key == "boss5"
        if isBoss then
            ignoreLabel:SetText(M.Tr("Editing:") .. " |cff38c7f0" .. M.Tr("Shared (boss frames)") .. "|r")
        elseif isShared then
            ignoreLabel:SetText(M.Tr("Editing:") .. " |cff38c7f0" .. M.Tr("Shared (all units)") .. "|r")
        else
            ignoreLabel:SetText(M.Tr("Editing:") .. " |cff38c7f0" .. M.Tr(tostring(key:gsub("^%l", string.upper))) .. "|r")
        end
        SetControlEnabled(ignoreOverride, not isShared and not isBoss)
        local canEdit = isShared or isBoss or AurasUnit(key).overrideIgnore == true
        for i = 1, #ignoreControls do SetControlEnabled(ignoreControls[i], canEdit) end
    end)

    local reminders = b:CollapsibleSection("a2_reminders", "Buff Reminders", 310, false)
    W.Text(reminders, "Ghost icons appear at the player frame when a buff is missing or about to expire. Position via Edit Mode mover.", 12, -6, 620, T.colors.muted)
    local remMaster = SwitchAt(ctx, reminders, "Enable Buff Reminders", 12, -28, 220, AuraShared, "showReminders", true, function() MarkReminderDirty(); ApplyAuras() end)
    local reminderControls = {}
    for i = 1, #AURA_REMINDERS do
        local spec = AURA_REMINDERS[i]
        local col = (i <= 5) and 12 or 380
        local row = (i <= 5) and i or (i - 5)
        reminderControls[#reminderControls + 1] = ToggleAt(ctx, reminders, spec.label, col, -52 - (row - 1) * 24, AuraReminders, spec.key, true, function() MarkReminderDirty(); ApplyAuras() end)
    end
    local expiry = SliderAt(ctx, reminders, "Expiry Warning", 12, -220, 0, 600, 5, 340, AuraShared, "reminderThreshold", 0, function() MarkReminderDirty(); ApplyAuras() end)
    local grow = DropdownAt(ctx, reminders, "Grow Direction", 500, -200, AURA_GROWTH, 190, AuraShared, "reminderGrowth", "RIGHT", function() MarkReminderDirty(); ApplyAuras() end)

    M.AddRefresher(ctx, function()
        local sharedScope = IsSharedScope()
        W.SetControlsEnabled(sharedOnlyControls, sharedScope)
        W.SetControlsEnabled(filterOverrideControls, sharedScope or UnitOverrideEnabled("overrideFilters"))
        W.SetControlsEnabled(capsOverrideControls, sharedScope or UnitOverrideEnabled("overrideSharedLayout"))
        W.SetControlsEnabled(layoutOverrideControls, sharedScope or UnitOverrideEnabled("overrideLayout"))

        local filtersEditable = sharedScope or UnitOverrideEnabled("overrideFilters")
        local bf = AuraBuffFilters()
        local df = AuraDebuffFilters()
        local buffOnlyMine = BoolValue(bf, "onlyMine", false)
        local debuffOnlyMine = BoolValue(df, "onlyMine", false)
        local buffNarrow = buffOnlyMine or BoolValue(bf, "onlyImportant", false)
        local debuffNarrow = debuffOnlyMine or BoolValue(df, "onlyImportant", false)
        local dispelTypesEnabled = filtersEditable and debuffNarrow and BoolValue(df, "includeDispellable", false)
        SetControlEnabled(filters._msuf2IncludeBossBuffs, filtersEditable and buffOnlyMine)
        SetControlEnabled(filters._msuf2IncludeBossDebuffs, filtersEditable and debuffOnlyMine)
        SetControlEnabled(filters._msuf2IncludeStealable, filtersEditable and buffNarrow)
        SetControlEnabled(filters._msuf2IncludeDispellable, filtersEditable and debuffNarrow)
        SetControlEnabled(filters._msuf2DispelMagic, dispelTypesEnabled)
        SetControlEnabled(filters._msuf2DispelPoison, dispelTypesEnabled)
        SetControlEnabled(filters._msuf2DispelCurse, dispelTypesEnabled)
        SetControlEnabled(filters._msuf2DispelDisease, dispelTypesEnabled)

        SetControlEnabled(pandemicDD, sharedScope and GetPandemicMode() ~= "OFF")

        local shared = AuraShared()
        local privateEnabled = sharedScope and shared.privateAurasEnabled ~= false
        local privatePlayer = privateEnabled and shared.showPrivateAurasPlayer == true
        SetControlEnabled(privateShow, privateEnabled)
        SetControlEnabled(privateMax, privatePlayer)
        SetControlEnabled(privateBorder, privatePlayer)
        SetControlEnabled(privateGrow, privateEnabled)

        local remindersEnabled = sharedScope and shared.showReminders ~= false
        SetControlEnabled(remMaster, sharedScope)
        for i = 1, #reminderControls do SetControlEnabled(reminderControls[i], remindersEnabled) end
        SetControlEnabled(expiry, remindersEnabled)
        SetControlEnabled(grow, remindersEnabled)
    end)
    end

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local AdvancedPage = M.AdvancedPage or {}
M.AdvancedPage = AdvancedPage
AdvancedPage.CallGlobal = CallGlobal
AdvancedPage.DB = DB
AdvancedPage.G = G
AdvancedPage.Bars = Bars
AdvancedPage.Gameplay = Gameplay
AdvancedPage.BoolValue = BoolValue
AdvancedPage.NumValue = NumValue
AdvancedPage.SetValue = SetValue
AdvancedPage.DeepCopyTable = DeepCopyTable
AdvancedPage.BindTableToggle = BindTableToggle
AdvancedPage.BindTableSwitchAt = BindTableSwitchAt
AdvancedPage.BindTableSlider = BindTableSlider
AdvancedPage.BindTableDropdown = BindTableDropdown
AdvancedPage.BindValueDropdown = BindValueDropdown
AdvancedPage.ReadRGB = ReadRGB
AdvancedPage.WriteRGB = WriteRGB
AdvancedPage.BindTableColor = BindTableColor
AdvancedPage.BindSeparateRGB = BindSeparateRGB
AdvancedPage.ApplyAuras = ApplyAuras
AdvancedPage.MoveWidget = MoveWidget
AdvancedPage.LabelAt = LabelAt
AdvancedPage.DividerAt = DividerAt
AdvancedPage.BindValueToggle = BindValueToggle
AdvancedPage.BindValueSwitchAt = BindValueSwitchAt
AdvancedPage.BindValueSlider = BindValueSlider
AdvancedPage.ToggleAt = ToggleAt
AdvancedPage.SwitchAt = SwitchAt
AdvancedPage.ValueToggleAt = ValueToggleAt
AdvancedPage.ValueSwitchAt = ValueSwitchAt
AdvancedPage.SliderAt = SliderAt
AdvancedPage.ValueSliderAt = ValueSliderAt
AdvancedPage.DropdownAt = DropdownAt
AdvancedPage.ValueDropdownAt = ValueDropdownAt
AdvancedPage.ColorAt = ColorAt
AdvancedPage.ScopedToggleAt = ScopedToggleAt
AdvancedPage.ScopedSwitchAt = ScopedSwitchAt
AdvancedPage.ScopedSliderAt = ScopedSliderAt
AdvancedPage.ScopedDropdownAt = ScopedDropdownAt
AdvancedPage.TogglePillAt = TogglePillAt
AdvancedPage.SetControlEnabled = SetControlEnabled

M.RegisterPage("auras2", { title = "MSUF Unit Auras", build = BuildAuras, version = 8 })
