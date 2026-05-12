local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme

local floor = math.floor

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
    tbl[key] = value
    if type(apply) == "function" then apply() end
end

local function DeepCopyTable(src)
    if type(src) ~= "table" then return src end
    if type(CopyTable) == "function" then return CopyTable(src) end
    local dst = {}
    for k, v in pairs(src) do dst[k] = DeepCopyTable(v) end
    return dst
end

local function BindTableToggle(ctx, section, label, getTable, key, default, apply)
    local toggle = W.Toggle(section, label)
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
    for _, key in ipairs({ "iconSize", "spacing", "offsetX", "offsetY", "cooldownTextSize", "stackTextSize", "reminderGrowth" }) do
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
    u.overrideFilters = true
    if type(u.filters) ~= "table" or u.filters == shared.filters then
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

local function ToggleEditMode()
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    local active = (_G.MSUF_IsMSUFEditModeActive and _G.MSUF_IsMSUFEditModeActive()) or _G.MSUF_UnitEditModeActive
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        pcall(_G.MSUF_SetMSUFEditModeDirect, not active)
    end
    if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
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
    if widget and widget.ClearAllPoints then
        local kind = widget._msuf2ControlKind
        if parent and parent._msuf2Width and (kind == "slider" or kind == "dropdown" or kind == "textinput") then
            local available = floor((parent._msuf2Width or 0) - (x or 0) - 18)
            local currentW = widget.GetWidth and widget:GetWidth()
            if available > 0 and currentW and currentW > available then
                widget:SetWidth(math.max(72, available))
                if widget._msuf2Title and widget._msuf2Title.SetWidth then
                    widget._msuf2Title:SetWidth(math.max(72, available))
                end
                if kind == "slider" and widget._msuf2UpdateFill then
                    widget._msuf2UpdateFill()
                end
            end
        end
        if widget._msuf2Title then
            widget._msuf2Title:ClearAllPoints()
            widget._msuf2Title:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
        end
        widget:ClearAllPoints()
        if widget._msuf2ControlKind == "slider" or widget._msuf2ControlKind == "dropdown" or widget._msuf2ControlKind == "textinput" then
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, (y or 0) - 22)
        elseif widget._msuf2ControlKind == "color" then
            if widget._msuf2Title then widget._msuf2Title:SetWidth(100) end
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT", (x or 0) + 108, (y or 0) + 2)
        else
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
        end
    end
    return widget
end

local function LabelAt(parent, text, x, y, width, template, color)
    local fs = T.Font(parent, template or "GameFontNormalSmall", text or "", color or T.colors.text)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    fs:SetWidth(width or 180)
    fs:SetJustifyH("LEFT")
    return fs
end

local function DividerAt(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, y)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    return line
end

local function BindValueToggle(ctx, section, label, getValue, setValue)
    local toggle = W.Toggle(section, label)
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

local function ValueToggleAt(ctx, section, label, x, y, getValue, setValue)
    return MoveWidget(BindValueToggle(ctx, section, label, getValue, setValue), section, x, y)
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

local function ScopedToggleAt(ctx, section, label, x, y, getTable, key, default, beforeSet, afterSet)
    return ValueToggleAt(ctx, section, label, x, y,
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
    btn:SetScript("OnClick", function(self)
        local tbl = getTable()
        local current = BoolValue(tbl, key, default)
        SetValue(tbl, key, not current, apply)
        self:SetActive(not current)
    end)
    M.AddRefresher(ctx, function()
        btn:SetActive(BoolValue(getTable(), key, default))
    end)
    return btn
end

local function SetControlEnabled(widget, enabled)
    if not widget then return end
    enabled = enabled and true or false
    if widget.Enable and widget.Disable then
        if enabled then widget:Enable() else widget:Disable() end
    elseif widget.SetEnabled then
        widget:SetEnabled(enabled)
    end
    if widget.SetAlpha then widget:SetAlpha(enabled and 1 or 0.38) end
    if widget._msuf2Label and widget._msuf2Label.SetTextColor then
        local c = enabled and T.colors.text or T.colors.dim
        widget._msuf2Label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
    if widget._msuf2Title and widget._msuf2Title.SetTextColor then
        local c = enabled and T.colors.text or T.colors.dim
        widget._msuf2Title:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
    if widget._msuf2LabelHit and widget._msuf2LabelHit.EnableMouse then
        widget._msuf2LabelHit:EnableMouse(enabled)
    end
    local edit = widget.editBox or widget.__MSUF_valueBox
    if edit and edit.Enable and edit.Disable then
        if enabled then edit:Enable() else edit:Disable() end
        if edit.SetAlpha then edit:SetAlpha(enabled and 1 or 0.45) end
    end
    if widget._msuf2StepButtons then
        for i = 1, #widget._msuf2StepButtons do
            local btn = widget._msuf2StepButtons[i]
            if btn.SetEnabled then btn:SetEnabled(enabled) end
            if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
        end
    end
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
    if value ~= "OFF" then M.lastPandemicMode = value end
    shared.pandemicMode = value
    shared.showPandemic = nil
    ApplyAuras()
end

local function AuraHasOverride(key)
    if key == "shared" then return false end
    local a2 = AurasDB()
    local u = a2.perUnit and a2.perUnit[key]
    return u and (u.overrideSharedLayout == true or u.overrideFilters == true) or false
end

local function RefreshAurasPage(ctx)
    for i = 1, #ctx.refreshers do
        local fn = ctx.refreshers[i]
        if type(fn) == "function" then pcall(fn) end
    end
end

local function BuildAuras(ctx)
    local b = W.PageBuilder(ctx)
    local head = b:Header("Unit Auras", "Auras 2.0 display, filters, layout, timer text and reminders.", 72)
    local edit = T.Button(head, "MSUF Edit Mode", 150, 24)
    edit:SetPoint("TOPRIGHT", head, "TOPRIGHT", -14, -14)
    edit:SetScript("OnClick", ToggleEditMode)

    local top = b:Section("Unit Auras", 148)
    ToggleAt(ctx, top, "Enable Unit Auras", 12, -34, function() return AurasDB() end, "enabled", true, function()
        local a2 = AurasDB()
        if a2.enabled == false and type(_G.MSUF_A2_HardDisableAll) == "function" then pcall(_G.MSUF_A2_HardDisableAll) end
        ApplyAuras()
    end)
    ScopedToggleAt(ctx, top, "Enable filters", 200, -34, AuraFilters, "enabled", true, ForceAuraFilterOverride, ApplyAuras)
    ToggleAt(ctx, top, "Preview in Edit Mode", 12, -58, AuraShared, "showInEditMode", true, ApplyAuras)
    ToggleAt(ctx, top, "Enable Masque skinning", 200, -58, AuraShared, "masqueEnabled", false, ApplyAuras)
    ToggleAt(ctx, top, "Hide Masque borders", 200, -82, AuraShared, "masqueHideBorder", false, ApplyAuras)
    LabelAt(top, "Units", 12, -94, 180, "GameFontNormalSmall", T.colors.muted)
    TogglePillAt(ctx, top, "Player", 12, -120, 90, function() return AurasDB() end, "showPlayer", false, ApplyAuras)
    TogglePillAt(ctx, top, "Target", 108, -120, 90, function() return AurasDB() end, "showTarget", true, ApplyAuras)
    TogglePillAt(ctx, top, "Focus", 204, -120, 90, function() return AurasDB() end, "showFocus", true, ApplyAuras)
    TogglePillAt(ctx, top, "Boss 1-5", 300, -120, 96, function() return AurasDB() end, "showBoss", true, ApplyAuras)

    local scope = b:Section("", 104)
    if scope.title then scope.title:Hide() end
    local scopeSeg = W.ScopeOverrideBar(ctx, scope, {
        values = AURA_SCOPES,
        centerY = -20,
        labelX = 10,
        labelWidth = 64,
        gap = 6,
        getValue = AuraScope,
        setValue = function(value)
            M.auraScope = value or "shared"
            RefreshAurasPage(ctx)
        end,
        hasOverride = AuraHasOverride,
    })
    local function RefreshScopeButtons()
        if scopeSeg and scopeSeg.Refresh then scopeSeg:Refresh() end
    end
    M.AddRefresher(ctx, RefreshScopeButtons)

    local overrideFilters = ValueToggleAt(ctx, scope, "Override filters", 10, -48,
        function()
            local s = AuraScope()
            return s ~= "shared" and AurasUnit(s).overrideFilters == true
        end,
        function(v)
            local s = AuraScope()
            if s == "shared" then return end
            AurasUnit(s).overrideFilters = v and true or false
            ApplyAuras()
            RefreshScopeButtons()
        end)
    local overrideCaps = ValueToggleAt(ctx, scope, "Override caps", 190, -48,
        function()
            local s = AuraScope()
            return s ~= "shared" and AurasUnit(s).overrideSharedLayout == true
        end,
        function(v)
            local s = AuraScope()
            if s == "shared" then return end
            AurasUnit(s).overrideSharedLayout = v and true or false
            ApplyAuras()
            RefreshScopeButtons()
        end)
    local reset = T.Button(scope, "Reset", 76, 22)
    reset:SetPoint("TOPRIGHT", scope, "TOPRIGHT", -10, -46)
    reset:SetScript("OnClick", function()
        local a2 = AurasDB()
        for i = 2, #AURA_SCOPES do
            local key = AURA_SCOPES[i].value
            local u = a2.perUnit and a2.perUnit[key]
            if type(u) == "table" then
                u.overrideSharedLayout = false
                u.layoutShared = nil
                u.overrideFilters = false
                u.filters = nil
            end
        end
        ApplyAuras()
        RefreshAurasPage(ctx)
    end)
    local summary = LabelAt(scope, "", 10, -84, 560, "GameFontDisableSmall", T.colors.dim)
    M.AddRefresher(ctx, function()
        local active = {}
        for i = 2, #AURA_SCOPES do
            local spec = AURA_SCOPES[i]
            if AuraHasOverride(spec.value) then active[#active + 1] = spec.text end
        end
        if #active == 0 then
            summary:SetText("|cff9aa0a6No unit overrides active.|r")
        else
            summary:SetText("|cffffffffOverrides active:|r " .. table.concat(active, ", "))
        end
        local isShared = AuraScope() == "shared"
        SetControlEnabled(overrideFilters, not isShared)
        SetControlEnabled(overrideCaps, not isShared)
        RefreshScopeButtons()
    end)

    local master = b:CollapsibleSection("a2_display", "Display", 244, true)
    LabelAt(master, "|cff6EB5FFBuffs|r", 14, -12, 140)
    LabelAt(master, "|cff6EB5FFDebuffs|r", 200, -12, 140)
    LabelAt(master, "|cff6EB5FFBoss Heal Auras|r", 390, -12, 180)
    ToggleAt(ctx, master, "Show Buffs", 12, -28, AuraShared, "showBuffs", true, ApplyAuras)
    ScopedToggleAt(ctx, master, "Only my buffs", 12, -50, AuraBuffFilters, "onlyMine", false, ForceAuraFilterOverride, ApplyAuras)
    ToggleAt(ctx, master, "Highlight own buffs", 12, -74, AuraShared, "highlightOwnBuffs", false, ApplyAuras)
    ScopedToggleAt(ctx, master, "Hide permanent buffs", 12, -96, AuraFilters, "hidePermanent", false, ForceAuraFilterOverride, ApplyAuras)
    ToggleAt(ctx, master, "Show Debuffs", 200, -28, AuraShared, "showDebuffs", true, ApplyAuras)
    ScopedToggleAt(ctx, master, "Only my debuffs", 200, -50, AuraDebuffFilters, "onlyMine", false, ForceAuraFilterOverride, ApplyAuras)
    ToggleAt(ctx, master, "Highlight own debuffs", 200, -74, AuraShared, "highlightOwnDebuffs", false, ApplyAuras)
    ToggleAt(ctx, master, "Highlight own healer buffs", 390, -28, BossHealAuras, "highlightOwn", false, ApplyAuras)
    ToggleAt(ctx, master, "Hide other healer buffs", 390, -50, BossHealAuras, "hideOthers", false, ApplyAuras)
    DividerAt(master, -120)
    LabelAt(master, "|cff6EB5FFIcons|r", 14, -128, 140)
    LabelAt(master, "|cff6EB5FFCooldown|r", 200, -128, 140)
    LabelAt(master, "|cff6EB5FFBorders|r", 390, -128, 140)
    ToggleAt(ctx, master, "Show tooltip", 12, -144, AuraShared, "showTooltip", true, ApplyAuras)
    ToggleAt(ctx, master, "Show stack count", 12, -166, AuraShared, "showStackCount", true, ApplyAuras)
    ToggleAt(ctx, master, "Click-through auras", 12, -188, AuraShared, "clickThroughAuras", false, ApplyAuras)
    ToggleAt(ctx, master, "Show cooldown swipe", 200, -144, AuraShared, "showCooldownSwipe", true, ApplyAuras)
    ToggleAt(ctx, master, "Swipe darkens on loss", 200, -166, AuraShared, "cooldownSwipeDarkenOnLoss", false, ApplyAuras)
    ToggleAt(ctx, master, "Show cooldown text", 200, -188, AuraShared, "showCooldownText", true, ApplyAuras)
    ToggleAt(ctx, master, "Dispel-type borders", 390, -144, AuraShared, "useDebuffTypeBorders", false, ApplyAuras)

    local layout = b:CollapsibleSection("a2_layout", "Layout & Caps", 484, true)
    ScopedSliderAt(ctx, layout, "Max Buffs", 12, -24, 0, 40, 1, 118, function() return AuraCaps() end, "maxBuffs", 8, ForceAuraCapsOverride, ApplyAuras)
    ScopedSliderAt(ctx, layout, "Max Debuffs", 192, -24, 0, 40, 1, 118, function() return AuraCaps() end, "maxDebuffs", 15, ForceAuraCapsOverride, ApplyAuras)
    ScopedSliderAt(ctx, layout, "Icons per row", 372, -24, 1, 20, 1, 118, function() return AuraCaps() end, "perRow", 11, ForceAuraCapsOverride, ApplyAuras)
    ScopedSliderAt(ctx, layout, "Block spacing", 552, -24, 0, 40, 1, 118, function() return AuraCaps() end, "splitSpacing", 0, ForceAuraCapsOverride, ApplyAuras)
    DividerAt(layout, -98)
    ScopedSliderAt(ctx, layout, "Icon size", 12, -118, 12, 64, 1, 118, function() return AuraLayout() end, "iconSize", 26, ForceAuraLayoutOverride, ApplyAuras)
    ScopedSliderAt(ctx, layout, "Spacing", 192, -118, 0, 12, 1, 118, function() return AuraLayout() end, "spacing", 2, ForceAuraLayoutOverride, ApplyAuras)
    ScopedSliderAt(ctx, layout, "Offset X", 372, -118, -300, 300, 1, 118, function() return AuraLayout() end, "offsetX", 0, ForceAuraLayoutOverride, ApplyAuras)
    ScopedSliderAt(ctx, layout, "Offset Y", 552, -118, -300, 300, 1, 118, function() return AuraLayout() end, "offsetY", 6, ForceAuraLayoutOverride, ApplyAuras)
    DividerAt(layout, -192)
    SliderAt(ctx, layout, "Buff Offset Y", 12, -214, -300, 300, 1, 160, AuraShared, "buffOffsetY", 30, ApplyAuras)
    ScopedDropdownAt(ctx, layout, "Layout", 248, -214, {
        { value = "SEPARATE", text = "Separate rows" },
        { value = "SINGLE", text = "Single row (Mixed)" },
    }, 210, function() return AuraCaps() end, "layoutMode", "SEPARATE", ForceAuraCapsOverride, ApplyAuras)
    ScopedDropdownAt(ctx, layout, "Stack Anchor", 484, -214, AURA_STACK_ANCHORS, 210, function() return AuraCaps() end, "stackCountAnchor", "TOPRIGHT", ForceAuraCapsOverride, ApplyAuras)
    ValueDropdownAt(ctx, layout, "Buff Growth", 12, -304, AURA_GROWTH, 210,
        function() local c = AuraCaps(); return c.buffGrowth or c.growth or "RIGHT" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().buffGrowth = v or "RIGHT"; ApplyAuras() end)
    ValueDropdownAt(ctx, layout, "Debuff Growth", 248, -304, AURA_GROWTH, 210,
        function() local c = AuraCaps(); return c.debuffGrowth or c.growth or "RIGHT" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().debuffGrowth = v or "RIGHT"; ApplyAuras() end)
    ValueDropdownAt(ctx, layout, "Private Growth", 484, -304, AURA_GROWTH, 210,
        function() local c = AuraCaps(); return c.privateGrowth or c.growth or "RIGHT" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().privateGrowth = v or "RIGHT"; ApplyAuras() end)
    ValueDropdownAt(ctx, layout, "Buff wrap rows", 12, -368, AURA_ROW_WRAP, 210,
        function() local c = AuraCaps(); return c.buffRowWrap or c.rowWrap or "DOWN" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().buffRowWrap = v or "DOWN"; ApplyAuras() end)
    ValueDropdownAt(ctx, layout, "Debuff wrap rows", 248, -368, AURA_ROW_WRAP, 210,
        function() local c = AuraCaps(); return c.debuffRowWrap or c.rowWrap or "DOWN" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().debuffRowWrap = v or "DOWN"; ApplyAuras() end)
    ValueDropdownAt(ctx, layout, "Sort order", 484, -368, AURA_SORT_ORDER, 250,
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
        end)

    local visual = b:CollapsibleSection("a2_text_coloring", "Text Coloring", 520, false)
    LabelAt(visual, "Cooldown Timer Text", 12, -10, 240, "GameFontNormal", T.colors.text)
    W.Text(visual, "Blizzard native timer text keeps aura countdowns cheap; MSUF only applies the configured colors.", 12, -34, 650, T.colors.muted)
    ToggleAt(ctx, visual, "Use Blizzard timer text (max performance)", 12, -66, AuraShared, "useBlizzardTimerText", true, ApplyAuras)
    ToggleAt(ctx, visual, "Color aura timers by remaining time", 12, -92, G, "aurasCooldownTextUseBuckets", true, ApplyAuras)

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

    ColorAt(ctx, visual, "Safe", 12, -226, G, "aurasCooldownTextSafeColor", 1, 1, 1, ApplyAuras)
    ColorAt(ctx, visual, "Warning", 174, -226, G, "aurasCooldownTextWarningColor", 1, 0.85, 0.2, ApplyAuras)
    ColorAt(ctx, visual, "Urgent", 336, -226, G, "aurasCooldownTextUrgentColor", 1, 0.55, 0.1, ApplyAuras)
    ColorAt(ctx, visual, "Stack count", 498, -226, G, "aurasStackCountColor", 1, 1, 1, ApplyAuras)
    SliderAt(ctx, visual, "Safe (seconds)", 12, -270, 0, 600, 1, 190, G, "aurasCooldownTextSafeSeconds", 60, ApplyAuras)
    SliderAt(ctx, visual, "Warning (<=)", 272, -270, 0, 30, 1, 190, G, "aurasCooldownTextWarningSeconds", 15, ApplyAuras)
    SliderAt(ctx, visual, "Urgent (<=)", 532, -270, 0, 15, 1, 150, G, "aurasCooldownTextUrgentSeconds", 5, ApplyAuras)
    SliderAt(ctx, visual, "Cooldown text size", 12, -330, 6, 32, 1, 190, AuraShared, "cooldownTextSize", 14, ApplyAuras)
    SliderAt(ctx, visual, "Stack text size", 272, -330, 6, 32, 1, 190, AuraShared, "stackTextSize", 14, ApplyAuras)
    DividerAt(visual, -392)
    LabelAt(visual, "Pandemic Window", 16, -408, 240, "GameFontNormal", T.colors.text)
    ValueToggleAt(ctx, visual, "Enable Pandemic Window", 12, -436,
        function() return GetPandemicMode() ~= "OFF" end,
        function(v)
            if v then
                SetPandemicMode(M.lastPandemicMode or "PULSE")
            else
                local mode = GetPandemicMode()
                if mode ~= "OFF" then M.lastPandemicMode = mode end
                SetPandemicMode("OFF")
            end
        end)
    local pandemicDD = ValueDropdownAt(ctx, visual, "Mode", 284, -420, PANDEMIC_MODES, 150,
        function()
            local mode = GetPandemicMode()
            return mode ~= "OFF" and mode or (M.lastPandemicMode or "PULSE")
        end,
        function(v) SetPandemicMode(v or "PULSE") end)
    W.Text(visual, "Best-effort: fixed 30% remaining-duration threshold for all auras. Color is configured in Global Style > Colors.", 12, -468, 650, T.colors.muted)
    M.AddRefresher(ctx, function()
        SetControlEnabled(pandemicDD, GetPandemicMode() ~= "OFF")
    end)

    local private = b:CollapsibleSection("a2_private", "Private Auras", 168, false)
    TogglePillAt(ctx, private, "Enabled", 12, -10, 90, AuraShared, "privateAurasEnabled", true, ApplyAuras)
    local privateShow = ToggleAt(ctx, private, "Show (Player)", 12, -40, AuraShared, "showPrivateAurasPlayer", true, ApplyAuras)
    local privateMax = SliderAt(ctx, private, "Max", 340, -34, 0, 12, 1, 150, AuraShared, "privateAuraMaxPlayer", 4, ApplyAuras)
    local privateBorder = SliderAt(ctx, private, "Border thickness", 520, -34, 0, 10, 0.5, 150, AuraShared, "privateAuraBorderScale", 3, ApplyAuras)
    local privateGrow = DropdownAt(ctx, private, "Grow Direction", 12, -92, AURA_GROWTH, 220, AuraShared, "privateGrowth", "RIGHT", ApplyAuras)
    M.AddRefresher(ctx, function()
        local shared = AuraShared()
        local enabled = shared.privateAurasEnabled ~= false
        local player = enabled and shared.showPrivateAurasPlayer == true
        SetControlEnabled(privateShow, enabled)
        SetControlEnabled(privateMax, player)
        SetControlEnabled(privateBorder, player)
        SetControlEnabled(privateGrow, enabled)
    end)

    local filters = b:CollapsibleSection("a2_filters", "Aura Filters & Sorting", 300, false)
    LabelAt(filters, "Include", 12, -10, 140, "GameFontNormal", T.colors.text)
    ScopedToggleAt(ctx, filters, "Include boss buffs", 12, -34, AuraBuffFilters, "includeBoss", false, ForceAuraFilterOverride, ApplyAuras)
    ScopedToggleAt(ctx, filters, "Include boss debuffs", 12, -62, AuraDebuffFilters, "includeBoss", false, ForceAuraFilterOverride, ApplyAuras)
    ToggleAt(ctx, filters, "Show Sated/Exhaustion", 12, -90, AuraShared, "showSated", true, ApplyAuras)
    ScopedToggleAt(ctx, filters, "Include stealable buffs", 12, -118, AuraBuffFilters, "includeStealable", false, ForceAuraFilterOverride, ApplyAuras)
    ScopedToggleAt(ctx, filters, "Include dispellable debuffs", 12, -146, AuraDebuffFilters, "includeDispellable", false, ForceAuraFilterOverride, ApplyAuras)
    LabelAt(filters, "Hard filters", 380, -10, 160, "GameFontNormal", T.colors.text)
    ScopedToggleAt(ctx, filters, "Only show boss auras", 380, -34, AuraFilters, "onlyBossAuras", false, ForceAuraFilterOverride, ApplyAuras)
    ScopedToggleAt(ctx, filters, "Only show IMPORTANT buffs", 380, -62, AuraBuffFilters, "onlyImportant", false, ForceAuraFilterOverride, ApplyAuras)
    ScopedToggleAt(ctx, filters, "Only show IMPORTANT debuffs", 380, -90, AuraDebuffFilters, "onlyImportant", false, ForceAuraFilterOverride, ApplyAuras)
    ScopedToggleAt(ctx, filters, "Dispel: Magic", 380, -118, AuraDebuffFilters, "dispelMagic", false, ForceAuraFilterOverride, ApplyAuras)
    ScopedToggleAt(ctx, filters, "Dispel: Curse", 380, -146, AuraDebuffFilters, "dispelCurse", false, ForceAuraFilterOverride, ApplyAuras)
    ScopedToggleAt(ctx, filters, "Dispel: Poison", 540, -118, AuraDebuffFilters, "dispelPoison", false, ForceAuraFilterOverride, ApplyAuras)
    ScopedToggleAt(ctx, filters, "Dispel: Disease", 540, -146, AuraDebuffFilters, "dispelDisease", false, ForceAuraFilterOverride, ApplyAuras)
    DividerAt(filters, -178)
    SliderAt(ctx, filters, "Sated threshold", 30, -202, 0, 600, 5, 200, AuraShared, "satedShowAtSeconds", 0, ApplyAuras)
    ValueDropdownAt(ctx, filters, "Sort order", 380, -202, AURA_SORT_ORDER, 270,
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
        end)

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
            ignoreLabel:SetText("|cff888888Not available for Boss frames|r")
        elseif isShared then
            ignoreLabel:SetText("Editing: |cffffd200Shared (all units)|r")
        else
            ignoreLabel:SetText("Editing: |cffffd200" .. tostring(key:gsub("^%l", string.upper)) .. "|r")
        end
        SetControlEnabled(ignoreOverride, not isShared and not isBoss)
        local canEdit = (not isBoss) and (isShared or AurasUnit(key).overrideIgnore == true)
        for i = 1, #ignoreControls do SetControlEnabled(ignoreControls[i], canEdit) end
    end)

    local reminders = b:CollapsibleSection("a2_reminders", "Buff Reminders", 310, false)
    W.Text(reminders, "Ghost icons appear at the player frame when a buff is missing or about to expire. Position via Edit Mode mover.", 12, -6, 620, T.colors.muted)
    local remMaster = ToggleAt(ctx, reminders, "Enable Buff Reminders", 12, -28, AuraShared, "showReminders", true, function() MarkReminderDirty(); ApplyAuras() end)
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
        local enabled = AuraShared().showReminders ~= false
        SetControlEnabled(remMaster, true)
        for i = 1, #reminderControls do SetControlEnabled(reminderControls[i], enabled) end
        SetControlEnabled(expiry, enabled)
        SetControlEnabled(grow, enabled)
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function ApplyColors()
    local api = ns and ns._colorsAPI
    if api and type(api.PushVisualUpdates) == "function" then
        pcall(api.PushVisualUpdates)
    end
    M.RequestGeneralApply("MSUF2_COLORS", { preview = true, applyAll = false })
    CallGlobal("MSUF_RefreshAllFrames")
    CallGlobal("MSUF_RefreshAllIdentityColors")
    CallGlobal("MSUF_RefreshAllPowerTextColors")
    CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
    if ns and type(ns.MSUF_ApplyGameplayVisuals) == "function" then pcall(ns.MSUF_ApplyGameplayVisuals) end
    local gf = ns and ns.GF
    if gf and type(gf.RefreshVisuals) == "function" then pcall(gf.RefreshVisuals) end
end

local function ApplyCastbarColors()
    ApplyColors()
    if ns and type(ns.MSUF_UpdateCastbarVisuals) == "function" then pcall(ns.MSUF_UpdateCastbarVisuals) end
    if ns and type(ns.MSUF_UpdateCastbarTextures_Immediate) == "function" then pcall(ns.MSUF_UpdateCastbarTextures_Immediate) end
end

local function ApplyGameplayColors()
    ApplyColors()
    if ns and type(ns.MSUF_RequestGameplayApply) == "function" then
        pcall(ns.MSUF_RequestGameplayApply)
    elseif ns and type(ns.MSUF_ApplyGameplayVisuals) == "function" then
        pcall(ns.MSUF_ApplyGameplayVisuals)
    end
end

local function ApplyAuraColors()
    ApplyAuras()
    ApplyColors()
    CallGlobal("MSUF_A2_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_A2_ForceCooldownTextRecolor")
    CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
    CallGlobal("MSUF_Auras2_RefreshAll")
    CallGlobal("MSUF_GF_ForceAuraTextColorRefresh")
end

local function ApplyClassPowerColors()
    ApplyColors()
    CallGlobal("MSUF_ClassPower_InvalidateColors")
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
end

local function ApplyPortraitColors(reason)
    CallGlobal("MSUF_PortraitDecoration_RefreshAll")
    CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "PORTRAIT_COLORS")
    ApplyColors()
end

local COLOR_CLASS_TOKENS = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local COLOR_CLASS_LABELS = {
    WARRIOR = "Warrior",
    PALADIN = "Paladin",
    HUNTER = "Hunter",
    ROGUE = "Rogue",
    PRIEST = "Priest",
    DEATHKNIGHT = "Death Knight",
    SHAMAN = "Shaman",
    MAGE = "Mage",
    WARLOCK = "Warlock",
    MONK = "Monk",
    DRUID = "Druid",
    DEMONHUNTER = "Demon Hunter",
    EVOKER = "Evoker",
}

local COLOR_NPC_ROWS = {
    { key = "friendly", label = "Friendly NPC Color", dr = 0, dg = 1, db = 0 },
    { key = "neutral", label = "Neutral NPC Color", dr = 1, dg = 1, db = 0 },
    { key = "enemy", label = "Enemy NPC Color", dr = 0.85, dg = 0.10, db = 0.10 },
    { key = "dead", label = "Dead NPC Color", dr = 0.40, dg = 0.40, db = 0.40 },
}

local COLOR_NPC_TYPE_ROWS = {
    { key = "npcBoss", label = "Boss", dr = 0.74, dg = 0.11, db = 0 },
    { key = "npcMiniboss", label = "Miniboss / Lieutenant", dr = 0.56, dg = 0, db = 0.74 },
    { key = "npcCaster", label = "Caster", dr = 0, dg = 0.45, db = 0.74 },
    { key = "npcMelee", label = "Melee", dr = 0.99, dg = 0.99, db = 0.99 },
    { key = "npcRegular", label = "Regular", dr = 0.70, dg = 0.56, db = 0.33 },
}

local COLOR_DISPEL_TYPES = {
    { key = "Magic", label = "Magic", dr = 0.20, dg = 0.60, db = 1.00 },
    { key = "Curse", label = "Curse", dr = 0.60, dg = 0.00, db = 1.00 },
    { key = "Disease", label = "Disease", dr = 0.60, dg = 0.40, db = 0.00 },
    { key = "Poison", label = "Poison", dr = 0.00, dg = 0.60, db = 0.00 },
    { key = "Bleed", label = "Bleed", dr = 0.80, dg = 0.10, db = 0.10 },
}

local COLOR_POWER_TOKENS = {
    { value = "MANA", text = "Mana" },
    { value = "RAGE", text = "Rage" },
    { value = "ENERGY", text = "Energy" },
    { value = "FOCUS", text = "Focus" },
    { value = "RUNIC_POWER", text = "Runic Power" },
    { value = "INSANITY", text = "Insanity" },
    { value = "FURY", text = "Fury" },
    { value = "PAIN", text = "Pain" },
    { value = "ESSENCE", text = "Essence" },
    { value = "LUNAR_POWER", text = "Astral Power" },
    { value = "MAELSTROM", text = "Maelstrom" },
}

local COLOR_CP_TOKENS = {
    { value = "COMBO_POINTS", text = "Combo Points" },
    { value = "HOLY_POWER", text = "Holy Power" },
    { value = "SOUL_SHARDS", text = "Soul Shards" },
    { value = "CHI", text = "Chi" },
    { value = "ARCANE_CHARGES", text = "Arcane Charges" },
    { value = "RUNES", text = "Runes" },
    { value = "ESSENCE", text = "Essence" },
    { value = "CHARGED", text = "Empowered / Charged" },
    { value = "SOUL_FRAGMENTS", text = "Soul Fragments" },
    { value = "SOUL_FRAGMENTS_META", text = "Soul Fragments (Void Meta)" },
    { value = "MAELSTROM", text = "Maelstrom Weapon" },
    { value = "MAELSTROM_ABOVE_5", text = "Maelstrom Weapon 5+" },
    { value = "ASTRAL_POWER", text = "Astral Power" },
    { value = "AP_PREDICTION", text = "Astral Prediction" },
    { value = "ECLIPSE_SOLAR", text = "Eclipse Solar" },
    { value = "ECLIPSE_LUNAR", text = "Eclipse Lunar" },
    { value = "ECLIPSE_CA", text = "Celestial Alignment" },
    { value = "STAGGER_GREEN", text = "Stagger Light" },
    { value = "STAGGER_YELLOW", text = "Stagger Moderate" },
    { value = "STAGGER_RED", text = "Stagger Heavy" },
    { value = "SOUL_FRAGMENTS_VENG", text = "Soul Fragments (Vengeance)" },
    { value = "INSANITY", text = "Insanity" },
    { value = "MAELSTROM_POWER", text = "Maelstrom Power" },
    { value = "WHIRLWIND", text = "Whirlwind" },
    { value = "TIP_OF_THE_SPEAR", text = "Tip of the Spear" },
    { value = "ICICLES", text = "Icicles" },
    { value = "EBON_MIGHT", text = "Ebon Might" },
    { value = "RESOURCE_TEXT", text = "Resource Text" },
}

local COLOR_CP_SLOT_TOKENS = {
    "COMBO_POINTS_1", "COMBO_POINTS_2", "COMBO_POINTS_3", "COMBO_POINTS_4",
    "COMBO_POINTS_5", "COMBO_POINTS_6", "COMBO_POINTS_7",
}

local COLOR_CP_SLOT_DEFAULTS = {
    COMBO_POINTS_1 = { 0.00, 0.95, 1.00 },
    COMBO_POINTS_2 = { 0.00, 0.95, 1.00 },
    COMBO_POINTS_3 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_4 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_5 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_6 = { 1.00, 0.05, 0.05 },
    COMBO_POINTS_7 = { 1.00, 0.05, 0.05 },
}

local COLOR_CP_SLOT_MODES = {
    { value = "default", text = "Resource color" },
    { value = "ramp", text = "Combo ramp" },
    { value = "custom", text = "Custom slots" },
}

local COLOR_DATA = {
    CLASS_LABELS = COLOR_CLASS_LABELS,
    NPC_ROWS = COLOR_NPC_ROWS,
    NPC_TYPE_ROWS = COLOR_NPC_TYPE_ROWS,
    DISPEL_TYPES = COLOR_DISPEL_TYPES,
    POWER_TOKENS = COLOR_POWER_TOKENS,
    CP_TOKENS = COLOR_CP_TOKENS,
    CP_SLOT_TOKENS = COLOR_CP_SLOT_TOKENS,
    CP_SLOT_MODES = COLOR_CP_SLOT_MODES,
}

local function ColorAPI()
    return (ns and ns._colorsAPI) or {}
end

local function ApiRGB(name, dr, dg, db)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        local ok, r, g, b = pcall(fn)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return dr, dg, db
end

local function ApiSetRGB(name, r, g, b)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        pcall(fn, r, g, b)
    else
        ApplyColors()
    end
end

local function GeneralRGB(prefix, dr, dg, db)
    local g = G()
    return tonumber(g[prefix .. "R"]) or dr, tonumber(g[prefix .. "G"]) or dg, tonumber(g[prefix .. "B"]) or db
end

local function SetGeneralRGB(prefix, r, gCol, b)
    local g = G()
    g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = r, gCol, b
    ApplyColors()
end

local function TableRGB(tbl, key, dr, dg, db)
    local t = tbl and tbl[key]
    if type(t) == "table" then
        local r = tonumber(t[1] or t.r or t["1"])
        local g = tonumber(t[2] or t.g or t["2"])
        local b = tonumber(t[3] or t.b or t["3"])
        if r and g and b then return r, g, b end
    end
    return dr, dg, db
end

local function SetTableRGB(tbl, key, r, g, b)
    if not tbl then return end
    tbl[key] = { r, g, b }
end

local function FontPaletteRGB(key, dr, dg, db)
    local colors = _G.MSUF_FONT_COLORS
    if type(colors) == "table" and type(key) == "string" and colors[key:lower()] then
        local c = colors[key:lower()]
        return c[1] or dr, c[2] or dg, c[3] or db
    end
    return dr, dg, db
end

local function HighlightRGB()
    local g = G()
    if type(g.highlightColor) == "table" then return TableRGB(g, "highlightColor", 1, 1, 1) end
    return FontPaletteRGB(g.highlightColor or "white", 1, 1, 1)
end

local function SetHighlightRGB(r, g, b)
    G().highlightColor = { r, g, b }
    ApplyColors()
    CallGlobal("MSUF_UpdateBossTargetHighlight", true)
    if ns and type(ns.MSUF_FixMouseoverHighlightBindings) == "function" then
        pcall(ns.MSUF_FixMouseoverHighlightBindings)
    end
end

local function ColorValueAt(ctx, section, label, x, y, getRGB, setRGB)
    local color = W.Color(section, label)
    M.BindColor(ctx, color, getRGB, setRGB)
    if color._msuf2Title then
        local sx, sy = x or 0, y or 0
        local sectionW = section._msuf2Width or 720
        local labelWidth = math.min(230, math.max(86, sectionW - sx - 76))
        color._msuf2Title:ClearAllPoints()
        color._msuf2Title:SetPoint("TOPLEFT", section, "TOPLEFT", sx, sy)
        color._msuf2Title:SetWidth(labelWidth)
        color:ClearAllPoints()
        color:SetPoint("TOPLEFT", section, "TOPLEFT", sx + labelWidth + 18, sy + 2)
        return color
    end
    return MoveWidget(color, section, x, y)
end

local function ButtonAt(parent, label, x, y, width, onClick)
    local btn = T.Button(parent, label, width or 150, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    if type(onClick) == "function" then btn:SetScript("OnClick", onClick) end
    return btn
end

local function GetClassTokens()
    local tokens = ColorAPI().CLASS_TOKENS
    if type(tokens) == "table" and #tokens > 0 then return tokens end
    return COLOR_CLASS_TOKENS
end

local function GetNPCTypeUnits()
    local units = ColorAPI().NPC_TYPE_UNITS
    if type(units) == "table" and #units > 0 then return units end
    return {
        { key = "npcTypeTarget", label = "Target" },
        { key = "npcTypeFocus", label = "Focus" },
        { key = "npcTypeBoss", label = "Boss" },
        { key = "npcTypeToT", label = "Target of Target" },
    }
end

local function PowerDefaultRGB(token)
    local col = _G.PowerBarColor and token and _G.PowerBarColor[token]
    if type(col) == "table" then
        local r = tonumber(col.r or col[1])
        local g = tonumber(col.g or col[2])
        local b = tonumber(col.b or col[3])
        if r and g and b then return r, g, b end
    end
    return 0.8, 0.8, 0.8
end

local function EnsurePowerOverrides()
    local g = G()
    if type(g.powerColorOverrides) ~= "table" then g.powerColorOverrides = {} end
    return g.powerColorOverrides
end

local function GetPowerOverrideRGB(token)
    local overrides = G().powerColorOverrides
    local r, g, b = PowerDefaultRGB(token)
    if type(overrides) == "table" then return TableRGB(overrides, token, r, g, b) end
    return r, g, b
end

local function SetPowerOverrideRGB(token, r, g, b)
    EnsurePowerOverrides()[token] = { r, g, b }
    ApplyColors()
end

local function ResetPowerOverride(token)
    local overrides = EnsurePowerOverrides()
    overrides[token] = nil
    ApplyColors()
end

local function ClassPowerDefaultRGB(token)
    local slot = COLOR_CP_SLOT_DEFAULTS[token]
    if slot then return slot[1], slot[2], slot[3] end
    if token == "CHARGED" then return 0.60, 0.20, 0.80 end
    if token == "RESOURCE_TEXT" then return ApiRGB("GetGlobalFontColor", 1, 1, 1) end
    if token == "SOUL_FRAGMENTS" then return 0.00, 0.80, 0.00 end
    if token == "SOUL_FRAGMENTS_META" then return 0.60, 0.20, 0.93 end
    if token == "MAELSTROM" or token == "MAELSTROM_POWER" then return PowerDefaultRGB("MAELSTROM") end
    if token == "MAELSTROM_ABOVE_5" then return 1.00, 0.50, 0.00 end
    if token == "ASTRAL_POWER" or token == "AP_PREDICTION" then return PowerDefaultRGB("LUNAR_POWER") end
    if token == "ECLIPSE_SOLAR" then return 0.82, 0.56, 0.25 end
    if token == "ECLIPSE_LUNAR" then return 0.41, 0.49, 0.82 end
    if token == "ECLIPSE_CA" then return 0.30, 1.00, 0.43 end
    if token == "STAGGER_GREEN" then return 0.52, 1.00, 0.52 end
    if token == "STAGGER_YELLOW" then return 1.00, 0.98, 0.72 end
    if token == "STAGGER_RED" then return 1.00, 0.42, 0.42 end
    if token == "SOUL_FRAGMENTS_VENG" then return 0.34, 0.06, 0.46 end
    if token == "INSANITY" then return PowerDefaultRGB("INSANITY") end
    if token == "WHIRLWIND" then return 0.20, 0.80, 0.20 end
    if token == "TIP_OF_THE_SPEAR" then return 0.60, 0.80, 0.20 end
    if token == "ICICLES" then return 0.50, 0.80, 1.00 end
    if token == "EBON_MIGHT" then return 0.40, 0.80, 0.60 end
    return PowerDefaultRGB(token)
end

local function EnsureClassPowerOverrides()
    local g = G()
    if type(g.classPowerColorOverrides) ~= "table" then g.classPowerColorOverrides = {} end
    if type(g.classPowerBgColorOverrides) ~= "table" then g.classPowerBgColorOverrides = {} end
    return g
end

local function GetClassPowerRGB(token)
    local dr, dg, db = ClassPowerDefaultRGB(token)
    local g = G()
    return TableRGB(g.classPowerColorOverrides, token, dr, dg, db)
end

local function SetClassPowerRGB(token, r, g, b)
    EnsureClassPowerOverrides().classPowerColorOverrides[token] = { r, g, b }
    ApplyClassPowerColors()
end

local function GetClassPowerBgRGB(token)
    return TableRGB(G().classPowerBgColorOverrides, token, 0, 0, 0)
end

local function SetClassPowerBgRGB(token, r, g, b)
    EnsureClassPowerOverrides().classPowerBgColorOverrides[token] = { r, g, b }
    ApplyClassPowerColors()
end

local function ResetClassPowerRGB(token, bg)
    local g = EnsureClassPowerOverrides()
    if bg then g.classPowerBgColorOverrides[token] = nil else g.classPowerColorOverrides[token] = nil end
    ApplyClassPowerColors()
end

local function GetPandemicRGB()
    local db = DB()
    db.auras2 = db.auras2 or {}
    db.auras2.shared = db.auras2.shared or {}
    local sh = db.auras2.shared
    return tonumber(sh.pandemicR) or 0.0, tonumber(sh.pandemicG) or 0.4, tonumber(sh.pandemicB) or 1.0
end

local function SetPandemicRGB(r, g, b)
    local db = DB()
    db.auras2 = db.auras2 or {}
    db.auras2.shared = db.auras2.shared or {}
    db.auras2.shared.pandemicR, db.auras2.shared.pandemicG, db.auras2.shared.pandemicB = r, g, b
    ApplyAuraColors()
end

local function SetAllPortraitRGB(prefix, r, g, b)
    local db = DB()
    db.general = db.general or {}
    db.general[prefix .. "R"], db.general[prefix .. "G"], db.general[prefix .. "B"] = r, g, b
    for _, key in ipairs({ "player", "target", "focus", "targettarget", "pet", "boss" }) do
        db[key] = db[key] or {}
        db[key][prefix .. "R"], db[key][prefix .. "G"], db[key][prefix .. "B"] = r, g, b
    end
    ApplyPortraitColors(prefix)
end

local function BuildColors(ctx)
    local b = W.PageBuilder(ctx)
    b:Header("Colors", "Native color controls matching the original MSUF color groups.", 64)

    local font = b:CollapsibleSection("colors_font", "Global Font Color", 100, false)
    ColorValueAt(ctx, font, "Global font color", 12, -10,
        function() return ApiRGB("GetGlobalFontColor", 1, 1, 1) end,
        function(r, g, c) ApiSetRGB("SetGlobalFontColor", r, g, c) end)
    ButtonAt(font, "Use font palette", 12, -50, 150, function()
        local fn = ColorAPI().ResetGlobalFontToPalette
        if type(fn) == "function" then pcall(fn) else G().useCustomFontColor = false; G().fontColorCustomR, G().fontColorCustomG, G().fontColorCustomB = nil, nil, nil end
        ApplyColors()
    end)

    local classColors = b:CollapsibleSection("colors_classes", "Class Bar Colors", 190, false)
    LabelAt(classColors, "Choose an override bar color per class.", 12, -8, 540, "GameFontHighlightSmall", T.colors.muted)
    local tokens = GetClassTokens()
    for i = 1, #tokens do
        local token = tokens[i]
        local col = (i - 1) % 4
        local row = floor((i - 1) / 4)
        ColorValueAt(ctx, classColors, COLOR_DATA.CLASS_LABELS[token] or token, 12 + col * 166, -34 - row * 36,
            function()
                local api = ColorAPI()
                if type(api.GetClassColor) == "function" then
                    local ok, r, g, c = pcall(api.GetClassColor, token)
                    if ok then return r, g, c end
                end
                local rc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
                if rc then return rc.r, rc.g, rc.b end
                return 1, 1, 1
            end,
            function(r, g, c)
                local api = ColorAPI()
                if type(api.SetClassColor) == "function" then pcall(api.SetClassColor, token, r, g, c) else ApplyColors() end
            end)
    end
    ButtonAt(classColors, "Reset all class colors", 12, -154, 190, function()
        local fn = ColorAPI().ResetAllClassColors
        if type(fn) == "function" then pcall(fn) else DB().classColors = nil end
        ApplyColors()
    end)

    local background = b:CollapsibleSection("colors_background", "Bar Background Tint", 170, false)
    ColorValueAt(ctx, background, "Bar background tint", 12, -10,
        function() return ApiRGB("GetClassBarBgColor", 0, 0, 0) end,
        function(r, g, c)
            local api = ColorAPI()
            if type(api.SetClassBarBgColor) == "function" then pcall(api.SetClassBarBgColor, r, g, c) else SetGeneralRGB("classBarBg", r, g, c) end
        end)
    ValueToggleAt(ctx, background, "Background follows HP color", 12, -50,
        function()
            local fn = ColorAPI().GetBarBgMatchHP
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().barBgMatchHPColor == true
        end,
        function(v)
            local fn = ColorAPI().SetBarBgMatchHP
            if type(fn) == "function" then pcall(fn, v) else G().barBgMatchHPColor = v and true or false end
            ApplyColors()
        end)
    ValueToggleAt(ctx, background, "Custom color in Dark Mode", 12, -78,
        function() return G().darkBgCustomColor == true end,
        function(v) G().darkBgCustomColor = v and true or false; ApplyColors() end)
    ButtonAt(background, "Reset to black", 12, -126, 140, function()
        local fn = ColorAPI().ResetClassBarBgColor
        if type(fn) == "function" then pcall(fn) else G().classBarBgR, G().classBarBgG, G().classBarBgB = nil, nil, nil end
        ApplyColors()
    end)

    local appearance = b:CollapsibleSection("colors_appearance", "Unitframe Global Coloring", 290, true)
    ValueDropdownAt(ctx, appearance, "Bar mode", 12, -10, {
        { value = "dark", text = "Dark Mode (dark black bars)" },
        { value = "class", text = "Class Color Mode (color HP bars)" },
        { value = "unified", text = "Unified Color Mode (one color for all frames)" },
        { value = "gradient", text = "Color Gradient" },
    }, 320,
        function()
            local g = G()
            local mode = g.barMode
            if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then
                mode = (g.useClassColors and "class") or "dark"
            end
            return mode
        end,
        function(mode)
            local g = G()
            g.barMode = mode
            g.darkMode = (mode == "dark")
            g.useClassColors = (mode == "class")
            ApplyColors()
        end)
    ColorValueAt(ctx, appearance, "Unified bar color", 12, -70,
        function() return GeneralRGB("unifiedBar", 0.10, 0.60, 0.90) end,
        function(r, g, c) SetGeneralRGB("unifiedBar", r, g, c) end)
    ValueSliderAt(ctx, appearance, "Dark mode bar color", 12, -112, 0, 100, 1, 300,
        function()
            local v = tonumber(G().darkBarGray)
            if not v then return 7 end
            if v <= 1 then return floor(v * 100 + 0.5) end
            return floor(v + 0.5)
        end,
        function(v)
            G().darkBarGray = (tonumber(v) or 0) / 100
            G().darkBarTone = nil
            ApplyColors()
        end)
    SliderAt(ctx, appearance, "Gradient strength", 360, -70, 0, 1, 0.05, 250, G, "gradientStrength", 0.45, ApplyColors)
    local gradientToggle = BindTableToggle(ctx, appearance, "Enable health gradient", G, "enableGradient", true, ApplyColors)
    MoveWidget(gradientToggle, appearance, 360, -158)

    local unit = b:CollapsibleSection("colors_unit", "Unitframe Colors", 230, false)
    for i = 1, #COLOR_DATA.NPC_ROWS do
        local row = COLOR_DATA.NPC_ROWS[i]
        ColorValueAt(ctx, unit, row.label, 12, -10 - (i - 1) * 36,
            function()
                local api = ColorAPI()
                if type(api.GetNPCColor) == "function" then
                    local ok, r, g, c = pcall(api.GetNPCColor, row.key)
                    if ok then return r, g, c end
                end
                return row.dr, row.dg, row.db
            end,
            function(r, g, c)
                local api = ColorAPI()
                if type(api.SetNPCColor) == "function" then pcall(api.SetNPCColor, row.key, r, g, c) else ApplyColors() end
            end)
    end
    ColorValueAt(ctx, unit, "Pet Frame Color", 360, -10,
        function() return ApiRGB("GetPetFrameColor", 0, 0.8, 0) end,
        function(r, g, c) ApiSetRGB("SetPetFrameColor", r, g, c) end)
    ButtonAt(unit, "Reset Unitframe Colors", 12, -190, 190, function()
        local fn = ColorAPI().ResetAllNPCColors
        if type(fn) == "function" then pcall(fn) else DB().npcColors = nil end
        ApplyColors()
    end)

    local npcType = b:CollapsibleSection("colors_npc_type", "NPC Type Colors", 330, false)
    local npcControls = {}
    npcControls[#npcControls + 1] = ValueToggleAt(ctx, npcType, "Color HP bar (Class Color mode only)", 32, -38,
        function()
            local fn = ColorAPI().GetNPCTypeColorBar
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().npcTypeColorBar ~= false
        end,
        function(v)
            local fn = ColorAPI().SetNPCTypeColorBar
            if type(fn) == "function" then pcall(fn, v) else G().npcTypeColorBar = v and true or false end
            ApplyColors()
        end)
    npcControls[#npcControls + 1] = ValueToggleAt(ctx, npcType, "Color name text", 32, -62,
        function()
            local fn = ColorAPI().GetNPCTypeColorText
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().npcTypeColorText ~= false
        end,
        function(v)
            local fn = ColorAPI().SetNPCTypeColorText
            if type(fn) == "function" then pcall(fn, v) else G().npcTypeColorText = v and true or false end
            ApplyColors()
        end)
    local npcMaster = ValueToggleAt(ctx, npcType, "Enable NPC Type Colors (Boss / Caster / Melee ...)", 12, -10,
        function()
            local fn = ColorAPI().GetNPCColorMode
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v == "type" end end
            return G().npcColorMode == "type"
        end,
        function(v)
            local fn = ColorAPI().SetNPCColorMode
            if type(fn) == "function" then pcall(fn, v and "type" or "reaction") else G().npcColorMode = v and "type" or "reaction" end
            ApplyColors()
        end)
    local units = GetNPCTypeUnits()
    LabelAt(npcType, "Apply to:", 12, -94, 120, "GameFontNormalSmall", T.colors.muted)
    for i = 1, #units do
        local info = units[i]
        local col = (i - 1) % 2
        local row = floor((i - 1) / 2)
        npcControls[#npcControls + 1] = ValueToggleAt(ctx, npcType, info.label or info.key, 32 + col * 180, -114 - row * 24,
            function()
                local fn = ColorAPI().GetNPCTypePerUnit
                if type(fn) == "function" then local ok, v = pcall(fn, info.key); if ok then return v end end
                return G()[info.key] ~= false
            end,
            function(v)
                local fn = ColorAPI().SetNPCTypePerUnit
                if type(fn) == "function" then pcall(fn, info.key, v) else G()[info.key] = v and true or false end
                ApplyColors()
            end)
    end
    for i = 1, #COLOR_DATA.NPC_TYPE_ROWS do
        local row = COLOR_DATA.NPC_TYPE_ROWS[i]
        local col = (i - 1) % 2
        local line = floor((i - 1) / 2)
        local sw = ColorValueAt(ctx, npcType, row.label, 12 + col * 330, -174 - line * 38,
            function()
                local api = ColorAPI()
                if type(api.GetNPCColor) == "function" then
                    local ok, r, g, c = pcall(api.GetNPCColor, row.key)
                    if ok then return r, g, c end
                end
                return row.dr, row.dg, row.db
            end,
            function(r, g, c)
                local api = ColorAPI()
                if type(api.SetNPCColor) == "function" then pcall(api.SetNPCColor, row.key, r, g, c) else ApplyColors() end
            end)
        npcControls[#npcControls + 1] = sw
    end
    ButtonAt(npcType, "Reset NPC Type Colors", 12, -292, 190, function()
        local fn = ColorAPI().ResetNPCTypeColors
        if type(fn) == "function" then pcall(fn) else DB().npcColors = nil end
        ApplyColors()
    end)
    M.AddRefresher(ctx, function()
        local enabled = npcMaster:GetChecked() and true or false
        for i = 1, #npcControls do SetControlEnabled(npcControls[i], enabled) end
    end)

    local barColors = b:CollapsibleSection("colors_bar_colors", "Bar Colors", 270, false)
    ColorValueAt(ctx, barColors, "Absorb Bar Color", 12, -10,
        function() return ApiRGB("GetAbsorbOverlayColor", 1, 1, 1) end,
        function(r, g, c) ApiSetRGB("SetAbsorbOverlayColor", r, g, c) end)
    ColorValueAt(ctx, barColors, "Heal-Absorb Bar Color", 12, -46,
        function() return ApiRGB("GetHealAbsorbOverlayColor", 0.7, 0, 0) end,
        function(r, g, c) ApiSetRGB("SetHealAbsorbOverlayColor", r, g, c) end)
    local powerBg = ColorValueAt(ctx, barColors, "Power Bar Background Color", 12, -82,
        function() return ApiRGB("GetPowerBarBackgroundColor", 0, 0, 0) end,
        function(r, g, c) ApiSetRGB("SetPowerBarBackgroundColor", r, g, c) end)
    local powerBgMatch = ValueToggleAt(ctx, barColors, "Match HP", 360, -82,
        function()
            local fn = ColorAPI().GetPowerBarBackgroundMatchHP
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().powerBarBgMatchBarColor == true
        end,
        function(v)
            local fn = ColorAPI().SetPowerBarBackgroundMatchHP
            if type(fn) == "function" then pcall(fn, v) else G().powerBarBgMatchBarColor = v and true or false end
            ApplyColors()
        end)
    ColorValueAt(ctx, barColors, "Aggro Border Color", 12, -118,
        function() return ApiRGB("GetAggroBorderColor", 1, 0.5, 0) end,
        function(r, g, c) ApiSetRGB("SetAggroBorderColor", r, g, c) end)
    ColorValueAt(ctx, barColors, "Purge Border Color", 12, -154,
        function() return GeneralRGB("purgeBorderColor", 1.00, 0.85, 0.00) end,
        function(r, g, c) SetGeneralRGB("purgeBorderColor", r, g, c) end)
    ButtonAt(barColors, "Reset Bar Colors", 12, -224, 160, function()
        local g = G()
        for _, prefix in ipairs({ "absorbBarColor", "healAbsorbBarColor", "powerBarBgColor", "aggroBorder", "purgeBorderColor" }) do
            g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"], g[prefix .. "A"] = nil, nil, nil, nil
        end
        g.powerBarBgMatchBarColor = nil
        ApplyColors()
    end)
    M.AddRefresher(ctx, function()
        SetControlEnabled(powerBg, not (powerBgMatch:GetChecked() and true or false))
    end)

    local dispel = b:CollapsibleSection("colors_dispel", "Dispel", 310, false)
    LabelAt(dispel, "Dispel color shared by Highlight Border and Group Frame Dispel Overlay.", 12, -8, 620, "GameFontHighlightSmall", T.colors.muted)
    ValueDropdownAt(ctx, dispel, "Color mode", 12, -42, {
        { value = "SINGLE", text = "Single color" },
        { value = "TYPE", text = "Per debuff type" },
    }, 220,
        function() return G().hlDispelColorMode or "SINGLE" end,
        function(v)
            G().hlDispelColorMode = v or "SINGLE"
            ApplyColors()
            CallGlobal("MSUF_PrioRows_Reinit")
        end)
    local singleDispel = ColorValueAt(ctx, dispel, "Dispel Color (all types)", 12, -102,
        function() return GeneralRGB("dispelBorderColor", 0.25, 0.75, 1.00) end,
        function(r, g, c) SetGeneralRGB("dispelBorderColor", r, g, c) end)
    local typeControls = {}
    for i = 1, #COLOR_DATA.DISPEL_TYPES do
        local def = COLOR_DATA.DISPEL_TYPES[i]
        local col = (i - 1) % 2
        local row = floor((i - 1) / 2)
        typeControls[#typeControls + 1] = ColorValueAt(ctx, dispel, def.label, 12 + col * 330, -146 - row * 36,
            function() return GeneralRGB("dispelType" .. def.key, def.dr, def.dg, def.db) end,
            function(r, g, c) SetGeneralRGB("dispelType" .. def.key, r, g, c) end)
    end
    ButtonAt(dispel, "Reset Dispel Colors", 12, -274, 180, function()
        local g = G()
        g.dispelBorderColorR, g.dispelBorderColorG, g.dispelBorderColorB = nil, nil, nil
        g.hlDispelColorMode = nil
        for i = 1, #COLOR_DATA.DISPEL_TYPES do
            local prefix = "dispelType" .. COLOR_DATA.DISPEL_TYPES[i].key
            g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = nil, nil, nil
        end
        ApplyColors()
        CallGlobal("MSUF_PrioRows_Reinit")
    end)
    M.AddRefresher(ctx, function()
        local single = (G().hlDispelColorMode or "SINGLE") ~= "TYPE"
        SetControlEnabled(singleDispel, single)
        for i = 1, #typeControls do SetControlEnabled(typeControls[i], not single) end
    end)

    local castbar = b:CollapsibleSection("colors_castbar", "Castbar Colors", 520, false)
    ColorValueAt(ctx, castbar, "Interruptible cast color", 12, -10,
        function() return ApiRGB("GetInterruptibleCastColor", 0, 0.9, 0.8) end,
        function(r, g, c) ApiSetRGB("SetInterruptibleCastColor", r, g, c); ApplyCastbarColors() end)
    ColorValueAt(ctx, castbar, "Non-interruptible cast color", 12, -46,
        function() return ApiRGB("GetNonInterruptibleCastColor", 0.4, 0.01, 0.01) end,
        function(r, g, c) ApiSetRGB("SetNonInterruptibleCastColor", r, g, c); ApplyCastbarColors() end)
    ColorValueAt(ctx, castbar, "Interrupt color (all castbars)", 12, -82,
        function() return ApiRGB("GetInterruptFeedbackCastColor", 1.0, 0.82, 0.0) end,
        function(r, g, c) ApiSetRGB("SetInterruptFeedbackCastColor", r, g, c); ApplyCastbarColors() end)
    ColorValueAt(ctx, castbar, "Castbar text color", 360, -10,
        function() return ApiRGB("GetCastbarTextColor", 1, 1, 1) end,
        function(r, g, c) ApiSetRGB("SetCastbarTextColor", r, g, c); ApplyCastbarColors() end)
    ColorValueAt(ctx, castbar, "Castbar border color", 360, -46,
        function() return ApiRGB("GetCastbarBorderColor", 0, 0, 0) end,
        function(r, g, c)
            local fn = ColorAPI().SetCastbarBorderColor
            if type(fn) == "function" then pcall(fn, r, g, c, 1) else SetGeneralRGB("castbarBorder", r, g, c) end
            ApplyCastbarColors()
        end)
    ColorValueAt(ctx, castbar, "Castbar background color", 360, -82,
        function() return ApiRGB("GetCastbarBackgroundColor", 0.10, 0.10, 0.10) end,
        function(r, g, c)
            local fn = ColorAPI().SetCastbarBackgroundColor
            if type(fn) == "function" then pcall(fn, r, g, c, 0.85) else SetGeneralRGB("castbarBg", r, g, c) end
            ApplyCastbarColors()
        end)
    LabelAt(castbar, "Player castbar override", 12, -134, 260, "GameFontNormal", T.colors.text)
    local overrideColor = ColorValueAt(ctx, castbar, "Custom color", 360, -190,
        function() return ApiRGB("GetPlayerCastbarOverrideColor", 0, 0.6, 1) end,
        function(r, g, c) ApiSetRGB("SetPlayerCastbarOverrideColor", r, g, c); ApplyCastbarColors() end)
    local overrideMode = ValueDropdownAt(ctx, castbar, "Mode", 190, -154, {
        { value = "CLASS", text = "Class color" },
        { value = "CUSTOM", text = "Custom color" },
    }, 160,
        function()
            local fn = ColorAPI().GetPlayerCastbarOverrideMode
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().playerCastbarOverrideMode or "CLASS"
        end,
        function(v)
            local fn = ColorAPI().SetPlayerCastbarOverrideMode
            if type(fn) == "function" then pcall(fn, v) else G().playerCastbarOverrideMode = v end
            ApplyCastbarColors()
        end)
    local overrideEnable = ValueToggleAt(ctx, castbar, "Enable Player override", 12, -154,
        function()
            local fn = ColorAPI().GetPlayerCastbarOverrideEnabled
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().playerCastbarOverrideEnabled == true
        end,
        function(v)
            local fn = ColorAPI().SetPlayerCastbarOverrideEnabled
            if type(fn) == "function" then pcall(fn, v) else G().playerCastbarOverrideEnabled = v and true or false end
            ApplyCastbarColors()
        end)
    LabelAt(castbar, "Interrupt Ready Indicator", 12, -244, 260, "GameFontNormal", T.colors.text)
    ColorValueAt(ctx, castbar, "Ready color (kick available)", 12, -274,
        function() return TableRGB(G(), "kickReadyColor", 0, 1, 0) end,
        function(r, g, c) SetTableRGB(G(), "kickReadyColor", r, g, c); ApplyCastbarColors() end)
    ColorValueAt(ctx, castbar, "Not ready color (kick on cooldown)", 12, -310,
        function() return TableRGB(G(), "kickNotReadyColor", 1, 0, 0) end,
        function(r, g, c) SetTableRGB(G(), "kickNotReadyColor", r, g, c); ApplyCastbarColors() end)
    ButtonAt(castbar, "Reset castbar colors", 12, -470, 170, function()
        local api = ColorAPI()
        if type(api.ResetCastbarTextColorToGlobal) == "function" then pcall(api.ResetCastbarTextColorToGlobal) end
        if type(api.ResetCastbarBorderColor) == "function" then pcall(api.ResetCastbarBorderColor) end
        if type(api.ResetCastbarBackgroundColor) == "function" then pcall(api.ResetCastbarBackgroundColor) end
        local g = G()
        g.castbarInterruptibleR, g.castbarInterruptibleG, g.castbarInterruptibleB = nil, nil, nil
        g.castbarNonInterruptibleR, g.castbarNonInterruptibleG, g.castbarNonInterruptibleB = nil, nil, nil
        g.castbarInterruptFeedbackR, g.castbarInterruptFeedbackG, g.castbarInterruptFeedbackB = nil, nil, nil
        g.playerCastbarOverrideEnabled = false
        g.playerCastbarOverrideMode = "CLASS"
        g.playerCastbarOverrideR, g.playerCastbarOverrideG, g.playerCastbarOverrideB = nil, nil, nil
        g.kickReadyColor, g.kickNotReadyColor = nil, nil
        ApplyCastbarColors()
    end)
    M.AddRefresher(ctx, function()
        local enabled = overrideEnable:GetChecked() and true or false
        SetControlEnabled(overrideMode, enabled)
        SetControlEnabled(overrideColor, enabled and ((overrideMode.GetValue and overrideMode:GetValue()) == "CUSTOM"))
    end)

    local highlight = b:CollapsibleSection("colors_highlight", "Mouseover Highlight", 210, false)
    local highlightColor = ColorValueAt(ctx, highlight, "Mouseover highlight color", 12, -48, HighlightRGB, SetHighlightRGB)
    local highlightEnabled = BindTableToggle(ctx, highlight, "Enable mouseover highlight", G, "highlightEnabled", true, function()
        SetHighlightRGB(HighlightRGB())
    end)
    MoveWidget(highlightEnabled, highlight, 12, -10)
    ColorValueAt(ctx, highlight, "Boss target highlight color", 12, -104,
        function() return TableRGB(G(), "bossTargetHighlightColor", 1, 0.82, 0) end,
        function(r, g, c)
            SetTableRGB(G(), "bossTargetHighlightColor", r, g, c)
            ApplyColors()
            CallGlobal("MSUF_UpdateBossTargetHighlight", true)
        end)
    M.AddRefresher(ctx, function()
        SetControlEnabled(highlightColor, G().highlightEnabled ~= false)
    end)

    local gameplay = b:CollapsibleSection("colors_gameplay", "Gameplay", 310, false)
    ColorValueAt(ctx, gameplay, "Combat timer text color", 12, -10,
        function() return TableRGB(Gameplay(), "combatTimerColor", 1, 1, 1) end,
        function(r, g, c) SetTableRGB(Gameplay(), "combatTimerColor", r, g, c); ApplyGameplayColors() end)
    ColorValueAt(ctx, gameplay, "Combat Enter text color", 12, -46,
        function() return TableRGB(Gameplay(), "combatStateEnterColor", 1, 1, 1) end,
        function(r, g, c)
            local gp = Gameplay()
            SetTableRGB(gp, "combatStateEnterColor", r, g, c)
            if gp.combatStateColorSync then SetTableRGB(gp, "combatStateLeaveColor", r, g, c) end
            ApplyGameplayColors()
        end)
    local leaveColor = ColorValueAt(ctx, gameplay, "Combat Leave text color", 12, -82,
        function() return TableRGB(Gameplay(), "combatStateLeaveColor", 0.7, 0.7, 0.7) end,
        function(r, g, c) SetTableRGB(Gameplay(), "combatStateLeaveColor", r, g, c); ApplyGameplayColors() end)
    local sync = BindTableToggle(ctx, gameplay, "Sync", Gameplay, "combatStateColorSync", false, function()
        local gp = Gameplay()
        if gp.combatStateColorSync then
            local r, g, c = TableRGB(gp, "combatStateEnterColor", 1, 1, 1)
            SetTableRGB(gp, "combatStateLeaveColor", r, g, c)
        end
        ApplyGameplayColors()
    end)
    MoveWidget(sync, gameplay, 360, -82)
    ColorValueAt(ctx, gameplay, "Crosshair in-range color", 12, -142,
        function() return TableRGB(Gameplay(), "crosshairInRangeColor", 0, 1, 0) end,
        function(r, g, c) SetTableRGB(Gameplay(), "crosshairInRangeColor", r, g, c); ApplyGameplayColors() end)
    ColorValueAt(ctx, gameplay, "Crosshair out-of-range color", 12, -178,
        function() return TableRGB(Gameplay(), "crosshairOutRangeColor", 1, 0, 0) end,
        function(r, g, c) SetTableRGB(Gameplay(), "crosshairOutRangeColor", r, g, c); ApplyGameplayColors() end)
    ButtonAt(gameplay, "Reset gameplay colors", 12, -254, 170, function()
        local gp = Gameplay()
        gp.combatTimerColor = { 1, 1, 1 }
        gp.combatStateEnterColor = { 1, 1, 1 }
        gp.combatStateLeaveColor = gp.combatStateColorSync and { 1, 1, 1 } or { 0.7, 0.7, 0.7 }
        gp.crosshairInRangeColor = { 0, 1, 0 }
        gp.crosshairOutRangeColor = { 1, 0, 0 }
        ApplyGameplayColors()
    end)
    M.AddRefresher(ctx, function()
        SetControlEnabled(leaveColor, not (Gameplay().combatStateColorSync == true))
    end)

    local power = b:CollapsibleSection("colors_power", "Power Bar Colors", 150, false)
    M.colorsPowerToken = M.colorsPowerToken or "MANA"
    local powerColor
    ValueDropdownAt(ctx, power, "Power type", 12, -10, COLOR_DATA.POWER_TOKENS, 260,
        function() return M.colorsPowerToken or "MANA" end,
        function(v)
            M.colorsPowerToken = v or "MANA"
            if powerColor then powerColor:SetRGB(GetPowerOverrideRGB(M.colorsPowerToken)) end
        end)
    powerColor = ColorValueAt(ctx, power, "Color", 360, -10,
        function() return GetPowerOverrideRGB(M.colorsPowerToken or "MANA") end,
        function(r, g, c) SetPowerOverrideRGB(M.colorsPowerToken or "MANA", r, g, c) end)
    ButtonAt(power, "Reset", 360, -54, 90, function()
        ResetPowerOverride(M.colorsPowerToken or "MANA")
        if powerColor then powerColor:SetRGB(GetPowerOverrideRGB(M.colorsPowerToken or "MANA")) end
    end)

    local classPower = b:CollapsibleSection("colors_class_power", "Class Power Colors", 430, false)
    M.colorsCPToken = M.colorsCPToken or "COMBO_POINTS"
    local cpColor, cpBg
    ValueDropdownAt(ctx, classPower, "Resource type", 12, -10, COLOR_DATA.CP_TOKENS, 310,
        function() return M.colorsCPToken or "COMBO_POINTS" end,
        function(v)
            M.colorsCPToken = v or "COMBO_POINTS"
            if cpColor then cpColor:SetRGB(GetClassPowerRGB(M.colorsCPToken)) end
            if cpBg then cpBg:SetRGB(GetClassPowerBgRGB(M.colorsCPToken)) end
        end)
    cpColor = ColorValueAt(ctx, classPower, "Color", 360, -10,
        function() return GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, c) SetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", r, g, c) end)
    cpBg = ColorValueAt(ctx, classPower, "Background", 360, -46,
        function() return GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, c) SetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS", r, g, c) end)
    ButtonAt(classPower, "Reset color", 360, -86, 110, function()
        ResetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", false)
        if cpColor then cpColor:SetRGB(GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS")) end
    end)
    ButtonAt(classPower, "Reset bg", 480, -86, 110, function()
        ResetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", true)
        if cpBg then cpBg:SetRGB(GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS")) end
    end)
    ValueDropdownAt(ctx, classPower, "Combo point slot mode", 12, -92, COLOR_DATA.CP_SLOT_MODES, 230,
        function()
            local mode = Bars().classPowerComboPointColorMode or "default"
            if mode ~= "ramp" and mode ~= "custom" then mode = "default" end
            return mode
        end,
        function(v)
            Bars().classPowerComboPointColorMode = v or "default"
            ApplyClassPowerColors()
        end)
    for i = 1, #COLOR_DATA.CP_SLOT_TOKENS do
        local token = COLOR_DATA.CP_SLOT_TOKENS[i]
        ColorValueAt(ctx, classPower, tostring(i), 12 + ((i - 1) % 4) * 160, -154 - floor((i - 1) / 4) * 38,
            function() return GetClassPowerRGB(token) end,
            function(r, g, c)
                Bars().classPowerComboPointColorMode = "custom"
                SetClassPowerRGB(token, r, g, c)
            end)
    end
    ButtonAt(classPower, "Reset slots", 12, -246, 120, function()
        local g = EnsureClassPowerOverrides()
        for i = 1, #COLOR_DATA.CP_SLOT_TOKENS do g.classPowerColorOverrides[COLOR_DATA.CP_SLOT_TOKENS[i]] = nil end
        ApplyClassPowerColors()
    end)

    local auras = b:CollapsibleSection("colors_auras", "Auras", 310, false)
    ColorValueAt(ctx, auras, "Own buff highlight color", 12, -10,
        function() return TableRGB(G(), "aurasOwnBuffHighlightColor", 1.0, 0.85, 0.2) end,
        function(r, g, c) SetTableRGB(G(), "aurasOwnBuffHighlightColor", r, g, c); ApplyAuraColors() end)
    ColorValueAt(ctx, auras, "Own debuff highlight color", 12, -46,
        function() return TableRGB(G(), "aurasOwnDebuffHighlightColor", 1.0, 0.85, 0.2) end,
        function(r, g, c) SetTableRGB(G(), "aurasOwnDebuffHighlightColor", r, g, c); ApplyAuraColors() end)
    ColorValueAt(ctx, auras, "Stack count text color", 12, -82,
        function() return TableRGB(G(), "aurasStackCountColor", 1, 1, 1) end,
        function(r, g, c) SetTableRGB(G(), "aurasStackCountColor", r, g, c); ApplyAuraColors() end)
    ColorValueAt(ctx, auras, "Pandemic window color", 12, -118, GetPandemicRGB, SetPandemicRGB)
    local bucketToggle = BindTableToggle(ctx, auras, "Color aura timers by remaining time", G, "aurasCooldownTextUseBuckets", true, ApplyAuraColors)
    MoveWidget(bucketToggle, auras, 12, -154)
    ColorValueAt(ctx, auras, "Cooldown text: Safe", 360, -10,
        function()
            local t = G().aurasCooldownTextSafeColor
            if type(t) == "table" then return TableRGB(G(), "aurasCooldownTextSafeColor", 1, 1, 1) end
            return ApiRGB("GetGlobalFontColor", 1, 1, 1)
        end,
        function(r, g, c) SetTableRGB(G(), "aurasCooldownTextSafeColor", r, g, c); ApplyAuraColors() end)
    ColorValueAt(ctx, auras, "Cooldown text: Warning", 360, -46,
        function() return TableRGB(G(), "aurasCooldownTextWarningColor", 1, 0.85, 0.2) end,
        function(r, g, c) SetTableRGB(G(), "aurasCooldownTextWarningColor", r, g, c); ApplyAuraColors() end)
    ColorValueAt(ctx, auras, "Cooldown text: Urgent", 360, -82,
        function() return TableRGB(G(), "aurasCooldownTextUrgentColor", 1, 0.55, 0.1) end,
        function(r, g, c) SetTableRGB(G(), "aurasCooldownTextUrgentColor", r, g, c); ApplyAuraColors() end)
    ButtonAt(auras, "Reset aura colors", 12, -264, 150, function()
        local g = G()
        g.aurasOwnBuffHighlightColor = { 1.0, 0.85, 0.2 }
        g.aurasOwnDebuffHighlightColor = { 1.0, 0.85, 0.2 }
        g.aurasStackCountColor = { 1, 1, 1 }
        g.aurasCooldownTextSafeColor = nil
        g.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
        g.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
        SetPandemicRGB(0.0, 0.4, 1.0)
        ApplyAuraColors()
    end)

    local portrait = b:CollapsibleSection("colors_portrait", "Portrait Colors", 180, false)
    ColorValueAt(ctx, portrait, "Border custom color", 12, -10,
        function() return GeneralRGB("portraitBorderColor", 1, 1, 1) end,
        function(r, g, c) SetAllPortraitRGB("portraitBorderColor", r, g, c) end)
    ColorValueAt(ctx, portrait, "Background color", 12, -46,
        function() return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05) end,
        function(r, g, c) SetAllPortraitRGB("portraitBgColor", r, g, c) end)
    ButtonAt(portrait, "Reset portrait colors", 12, -118, 170, function()
        SetAllPortraitRGB("portraitBorderColor", 1, 1, 1)
        SetAllPortraitRGB("portraitBgColor", 0.05, 0.05, 0.05)
        G().portraitBorderColorA = 1
        G().portraitBgColorA = 0.85
        ApplyPortraitColors("PORTRAIT_COLOR_RESET")
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function ApplyGameplay()
    if ns and type(ns.MSUF_RequestGameplayApply) == "function" then
        pcall(ns.MSUF_RequestGameplayApply)
    elseif ns and type(ns.MSUF_ApplyGameplayVisuals) == "function" then
        pcall(ns.MSUF_ApplyGameplayVisuals)
    end
end

local function BuildGameplay(ctx)
    local b = W.PageBuilder(ctx)
    b:Header("Midnight Simple Unit Frames - Gameplay", "Here are several gameplay enhancement options you can toggle on or off.", 74)

    local disabledRefresh
    local previewRefresh
    local function ApplyGameplayUI()
        ApplyGameplay()
        if disabledRefresh then disabledRefresh() end
        if previewRefresh then previewRefresh() end
    end

    local anchorValues = {
        { value = "none", text = "None" },
        { value = "player", text = "Player" },
        { value = "target", text = "Target" },
        { value = "focus", text = "Focus" },
    }
    local frameAnchors = {
        { value = "TOPLEFT", text = "TOPLEFT" },
        { value = "TOP", text = "TOP" },
        { value = "TOPRIGHT", text = "TOPRIGHT" },
        { value = "LEFT", text = "LEFT" },
        { value = "CENTER", text = "CENTER" },
        { value = "RIGHT", text = "RIGHT" },
        { value = "BOTTOMLEFT", text = "BOTTOMLEFT" },
        { value = "BOTTOM", text = "BOTTOM" },
        { value = "BOTTOMRIGHT", text = "BOTTOMRIGHT" },
    }

    local function PlayerSpecID()
        if ns and type(ns.MSUF_GetPlayerSpecID) == "function" then
            local ok, value = pcall(ns.MSUF_GetPlayerSpecID)
            if ok then return value end
        end
        if GetSpecialization and GetSpecializationInfo then
            local spec = GetSpecialization()
            if spec then
                local id = GetSpecializationInfo(spec)
                return id
            end
        end
        return nil
    end

    local function CurrentMeleeSpellID()
        local g = Gameplay()
        local id = 0
        if g.meleeSpellPerSpec and type(g.nameplateMeleeSpellIDBySpec) == "table" then
            local specID = PlayerSpecID()
            if specID then id = tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0 end
        end
        if id <= 0 and g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
            local _, class = UnitClass("player")
            if class then id = tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0 end
        end
        if id <= 0 then id = tonumber(g.nameplateMeleeSpellID) or 0 end
        return id
    end

    local function SpellName(id)
        id = tonumber(id) or 0
        if id <= 0 then return nil end
        if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
            local info = C_Spell.GetSpellInfo(id)
            if type(info) == "table" and info.name then return info.name end
        end
        if GetSpellInfo then
            local name = GetSpellInfo(id)
            return name
        end
        return nil
    end

    local function SpellIDFromInput(value)
        local text = tostring(value or ""):match("^%s*(.-)%s*$")
        local asNumber = tonumber(text)
        if asNumber then return floor(asNumber + 0.5) end
        if text ~= "" and C_Spell and type(C_Spell.GetSpellInfo) == "function" then
            local ok, info = pcall(C_Spell.GetSpellInfo, text)
            if not ok then info = nil end
            if type(info) == "table" and info.spellID then return tonumber(info.spellID) or 0 end
        end
        if text ~= "" and GetSpellInfo then
            local _, _, _, _, _, _, spellID = GetSpellInfo(text)
            return tonumber(spellID) or 0
        end
        return 0
    end

    local function SeedMeleeClass()
        local g = Gameplay()
        if type(g.nameplateMeleeSpellIDByClass) ~= "table" then g.nameplateMeleeSpellIDByClass = {} end
        if UnitClass then
            local _, class = UnitClass("player")
            if class and (tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0) <= 0 then
                g.nameplateMeleeSpellIDByClass[class] = CurrentMeleeSpellID()
            end
        end
    end

    local function SeedMeleeSpec()
        local g = Gameplay()
        if type(g.nameplateMeleeSpellIDBySpec) ~= "table" then g.nameplateMeleeSpellIDBySpec = {} end
        local specID = PlayerSpecID()
        if specID and (tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0) <= 0 then
            g.nameplateMeleeSpellIDBySpec[specID] = CurrentMeleeSpellID()
        end
    end

    local function SetMeleeSpellID(value)
        local spellID = SpellIDFromInput(value)
        local g = Gameplay()
        if g.meleeSpellPerSpec then
            if type(g.nameplateMeleeSpellIDBySpec) ~= "table" then g.nameplateMeleeSpellIDBySpec = {} end
            local specID = PlayerSpecID()
            if specID then g.nameplateMeleeSpellIDBySpec[specID] = spellID end
        elseif g.meleeSpellPerClass and UnitClass then
            if type(g.nameplateMeleeSpellIDByClass) ~= "table" then g.nameplateMeleeSpellIDByClass = {} end
            local _, class = UnitClass("player")
            if class then g.nameplateMeleeSpellIDByClass[class] = spellID end
        end
        g.nameplateMeleeSpellID = spellID
    end

    local timerControls = {}
    local stateControls = {}
    local totemControls = {}
    local firstDanceControls = {}
    local crossControls = {}
    local meleeControls = {}
    local selectedSpellText
    local noSpellWarn

    local function Add(list, widget)
        list[#list + 1] = widget
        return widget
    end

    -- Old order: Combat Timer, Combat Enter/Leave, Class-specific toggles, Combat Crosshair.
    local timer = b:CollapsibleSection("gameplay_timer", "Combat Timer", 430, true)
    local timerEnable = ToggleAt(ctx, timer, "Enable in-combat timer", 14, -40, Gameplay, "enableCombatTimer", false, ApplyGameplayUI)
    local timerAnchor = DropdownAt(ctx, timer, "Anchor", 320, -40, anchorValues, 160, Gameplay, "combatTimerAnchor", "none", ApplyGameplayUI)
    Add(timerControls, timerAnchor)
    Add(timerControls, SliderAt(ctx, timer, "Timer size", 14, -94, 10, 64, 1, 270, Gameplay, "combatFontSize", 24, ApplyGameplayUI))
    Add(timerControls, ToggleAt(ctx, timer, "Lock position", 360, -100, Gameplay, "lockCombatTimer", false, ApplyGameplayUI))
    Add(timerControls, ToggleAt(ctx, timer, "Click-through (ALT to drag when unlocked)", 360, -132, Gameplay, "combatTimerClickThrough", false, ApplyGameplayUI))
    LabelAt(timer, "Timer position (offset)", 14, -186, 260, "GameFontHighlightSmall", T.colors.muted)
    Add(timerControls, SliderAt(ctx, timer, "X offset", 14, -216, -800, 800, 1, 300, Gameplay, "combatOffsetX", 0, ApplyGameplayUI))
    Add(timerControls, SliderAt(ctx, timer, "Y offset", 360, -216, -800, 800, 1, 300, Gameplay, "combatOffsetY", -200, ApplyGameplayUI))
    LabelAt(timer, "Colors are configured in Colors > Gameplay.", 14, -312, 520, "GameFontDisableSmall", T.colors.muted)

    local state = b:CollapsibleSection("gameplay_state", "Combat Enter/Leave", 340, false)
    local stateEnable = ToggleAt(ctx, state, "Show combat enter/leave text", 14, -40, Gameplay, "enableCombatStateText", false, ApplyGameplayUI)
    Add(stateControls, ToggleAt(ctx, state, "Lock position", 360, -40, Gameplay, "lockCombatState", false, ApplyGameplayUI))
    local enterInput = MoveWidget(W.TextInput(state, "Enter text", 220), state, 14, -86)
    M.BindTextInput(ctx, enterInput,
        function() return Gameplay().combatStateEnterText or "+Combat" end,
        function(v)
            Gameplay().combatStateEnterText = tostring(v or "")
            ApplyGameplayUI()
        end, true)
    Add(stateControls, enterInput)
    local leaveInput = MoveWidget(W.TextInput(state, "Leave text", 220), state, 300, -86)
    M.BindTextInput(ctx, leaveInput,
        function() return Gameplay().combatStateLeaveText or "-Combat" end,
        function(v)
            Gameplay().combatStateLeaveText = tostring(v or "")
            ApplyGameplayUI()
        end, true)
    Add(stateControls, leaveInput)
    Add(stateControls, SliderAt(ctx, state, "Text size", 14, -152, 10, 64, 1, 250, Gameplay, "combatStateFontSize", 24, ApplyGameplayUI))
    Add(stateControls, SliderAt(ctx, state, "Duration (s)", 320, -152, 0.5, 5.0, 0.5, 250, Gameplay, "combatStateDuration", 1.5, ApplyGameplayUI))
    Add(stateControls, SliderAt(ctx, state, "X offset", 14, -238, -800, 800, 1, 250, Gameplay, "combatStateOffsetX", 0, ApplyGameplayUI))
    Add(stateControls, SliderAt(ctx, state, "Y offset", 320, -238, -800, 800, 1, 250, Gameplay, "combatStateOffsetY", 80, ApplyGameplayUI))

    local classSec = b:CollapsibleSection("gameplay_class_specific", "Class-specific toggles", 704, false)
    local classToken
    if UnitClass then
        local _, token = UnitClass("player")
        classToken = token
    end
    local hasTotemFrame = classToken == "SHAMAN" or classToken == "MONK"
    local isRogue = classToken == "ROGUE"
    LabelAt(classSec, hasTotemFrame and "Totem / Statue frame" or "(Totem/Statue frame is Shaman/Monk-only)", 14, -38, 360, "GameFontNormalSmall", T.colors.text)
    LabelAt(classSec, "Uses Blizzard TotemFrame; MSUF only re-anchors it out of combat.", 14, -60, 520, "GameFontDisableSmall", T.colors.muted)
    local totemEnable = ToggleAt(ctx, classSec, "Re-anchor Blizzard TotemFrame", 14, -92, Gameplay, "enablePlayerTotems", false, ApplyGameplayUI)
    local previewBtn = T.Button(classSec, "Preview", 120, 22)
    previewBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", 14, -128)
    previewBtn:SetScript("OnClick", function()
        if ns and type(ns.MSUF_PlayerTotems_TogglePreview) == "function" then
            pcall(ns.MSUF_PlayerTotems_TogglePreview)
        end
    end)
    local resetTotemBtn = T.Button(classSec, "Reset TotemFrame layout", 190, 22)
    resetTotemBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", 146, -128)
    resetTotemBtn:SetScript("OnClick", function()
        local g = Gameplay()
        g.playerTotemsIconSize = 24
        g.playerTotemsOffsetX = 0
        g.playerTotemsOffsetY = -6
        g.playerTotemsAnchorFrom = "TOPLEFT"
        g.playerTotemsAnchorTo = "BOTTOMLEFT"
        ApplyGameplayUI()
        if M.Refresh then M.Refresh(ctx) end
    end)
    LabelAt(classSec, "Tip: Move the preview via mousedrag or arrow keys.", 14, -158, 520, "GameFontDisableSmall", T.colors.muted)
    Add(totemControls, totemEnable)
    Add(totemControls, previewBtn)
    Add(totemControls, resetTotemBtn)
    Add(totemControls, SliderAt(ctx, classSec, "Icon size", 390, -84, 8, 64, 1, 250, Gameplay, "playerTotemsIconSize", 24, ApplyGameplayUI))
    Add(totemControls, SliderAt(ctx, classSec, "X offset", 390, -168, -200, 200, 1, 250, Gameplay, "playerTotemsOffsetX", 0, ApplyGameplayUI))
    Add(totemControls, SliderAt(ctx, classSec, "Y offset", 390, -252, -200, 200, 1, 250, Gameplay, "playerTotemsOffsetY", -6, ApplyGameplayUI))
    Add(totemControls, DropdownAt(ctx, classSec, "From", 14, -202, frameAnchors, 180, Gameplay, "playerTotemsAnchorFrom", "TOPLEFT", ApplyGameplayUI))
    Add(totemControls, DropdownAt(ctx, classSec, "To", 210, -202, frameAnchors, 180, Gameplay, "playerTotemsAnchorTo", "BOTTOMLEFT", ApplyGameplayUI))

    DividerAt(classSec, -330)
    LabelAt(classSec, "Rogue: First Dance tracker", 14, -354, 360, "GameFontNormalSmall", T.colors.text)
    LabelAt(classSec, "Optional helper. Shows a 6s timer after leaving combat.", 14, -376, 520, "GameFontDisableSmall", T.colors.muted)
    local firstDanceEnable = ToggleAt(ctx, classSec, "Track 'The First Dance' (6s after leaving combat)", 14, -410, Gameplay, "enableFirstDanceTimer", false, ApplyGameplayUI)
    Add(firstDanceControls, ToggleAt(ctx, classSec, "Lock position", 390, -410, Gameplay, "lockFirstDance", false, ApplyGameplayUI))
    Add(firstDanceControls, ToggleAt(ctx, classSec, "Click-through (ALT to drag when unlocked)", 14, -444, Gameplay, "firstDanceClickThrough", false, ApplyGameplayUI))
    Add(firstDanceControls, ToggleAt(ctx, classSec, "Show as icon with cooldown swipe", 14, -478, Gameplay, "firstDanceShowIcon", true, ApplyGameplayUI))
    Add(firstDanceControls, ToggleAt(ctx, classSec, "Keep visible when ready (hide on combat enter)", 390, -444, Gameplay, "firstDanceShowReady", false, ApplyGameplayUI))
    Add(firstDanceControls, SliderAt(ctx, classSec, "Icon size", 14, -524, 16, 96, 1, 250, Gameplay, "firstDanceIconSize", 40, ApplyGameplayUI))
    Add(firstDanceControls, SliderAt(ctx, classSec, "X offset", 300, -524, -800, 800, 1, 250, Gameplay, "firstDanceOffsetX", 0, ApplyGameplayUI))
    Add(firstDanceControls, SliderAt(ctx, classSec, "Y offset", 14, -608, -800, 800, 1, 250, Gameplay, "firstDanceOffsetY", 80, ApplyGameplayUI))

    local cross = b:CollapsibleSection("gameplay_crosshair", "Combat Crosshair", 560, false)
    local crossEnable = ToggleAt(ctx, cross, "Show green combat crosshair under player (in combat)", 14, -40, Gameplay, "enableCombatCrosshair", false, ApplyGameplayUI)
    local rangeToggle = ToggleAt(ctx, cross, "Crosshair: color by melee range to target (green=in range, red=out)", 14, -74, Gameplay, "enableCombatCrosshairMeleeRangeColor", false, ApplyGameplayUI)
    LabelAt(cross, "Uses the spell selected below.", 38, -104, 420, "GameFontDisableSmall", T.colors.muted)
    noSpellWarn = LabelAt(cross, "No melee range spell selected - Crosshair will not work.", 38, -126, 520, "GameFontNormalSmall", { 1, 0.55, 0.1, 1 })
    local spellInput = MoveWidget(W.TextInput(cross, "Choose spell (type spell ID or name)", 220), cross, 14, -170)
    M.BindTextInput(ctx, spellInput,
        function()
            local id = CurrentMeleeSpellID()
            return id > 0 and tostring(id) or ""
        end,
        function(v)
            SetMeleeSpellID(v)
            ApplyGameplayUI()
        end, true)
    selectedSpellText = LabelAt(cross, "", 260, -192, 360, "GameFontDisableSmall", T.colors.muted)
    LabelAt(cross, "Used by: Crosshair melee-range color.", 260, -214, 360, "GameFontDisableSmall", T.colors.muted)
    local classSpellToggle = ToggleAt(ctx, cross, "Store per class", 260, -244, Gameplay, "meleeSpellPerClass", false, function()
        if Gameplay().meleeSpellPerClass then SeedMeleeClass() end
        ApplyGameplayUI()
    end)
    local specSpellToggle = ToggleAt(ctx, cross, "Store per spec", 430, -244, Gameplay, "meleeSpellPerSpec", false, function()
        if Gameplay().meleeSpellPerSpec then SeedMeleeSpec() end
        ApplyGameplayUI()
    end)
    Add(crossControls, rangeToggle)
    Add(crossControls, spellInput)
    Add(crossControls, classSpellToggle)
    Add(crossControls, specSpellToggle)
    Add(meleeControls, spellInput)
    Add(meleeControls, classSpellToggle)
    Add(meleeControls, specSpellToggle)

    local preview = T.Panel(cross, nil, { 0, 0, 0, 0.92 }, T.colors.borderSoft)
    preview:SetPoint("TOPLEFT", cross, "TOPLEFT", 14, -292)
    preview:SetSize(260, 120)
    local bars = {}
    for i = 1, 4 do
        bars[i] = preview:CreateTexture(nil, "ARTWORK")
        bars[i]:SetColorTexture(1, 0, 0, 1)
    end
    Add(crossControls, SliderAt(ctx, cross, "Crosshair thickness", 300, -314, 1, 12, 1, 260, Gameplay, "crosshairThickness", 3, ApplyGameplayUI))
    Add(crossControls, SliderAt(ctx, cross, "Crosshair size", 300, -398, 20, 120, 2, 260, Gameplay, "crosshairSize", 40, ApplyGameplayUI))
    LabelAt(cross, "Colors are configured in Colors > Gameplay.", 300, -494, 360, "GameFontDisableSmall", T.colors.muted)

    previewRefresh = function()
        local g = Gameplay()
        local id = CurrentMeleeSpellID()
        local name = SpellName(id)
        if selectedSpellText then
            selectedSpellText:SetText((id > 0 and ("Selected: " .. (name or "Spell") .. " (" .. id .. ")")) or "Selected: none")
        end
        if noSpellWarn then noSpellWarn:SetShown((g.enableCombatCrosshairMeleeRangeColor == true) and id <= 0) end
        local size = math.max(20, tonumber(g.crosshairSize) or 40)
        local thick = math.max(1, tonumber(g.crosshairThickness) or 3)
        local centerX, centerY = 130, -60
        local gap = math.max(6, floor(size * 0.20))
        local r, gr, b = 0, 1, 0
        if g.enableCombatCrosshairMeleeRangeColor then
            local c = g.crosshairOutRangeColor
            r, gr, b = (c and c[1]) or 1, (c and c[2]) or 0, (c and c[3]) or 0
        end
        for i = 1, 4 do bars[i]:ClearAllPoints() end
        bars[1]:SetPoint("CENTER", preview, "TOPLEFT", centerX - gap - size * 0.28, centerY)
        bars[1]:SetSize(size * 0.42, thick)
        bars[2]:SetPoint("CENTER", preview, "TOPLEFT", centerX + gap + size * 0.28, centerY)
        bars[2]:SetSize(size * 0.42, thick)
        bars[3]:SetPoint("CENTER", preview, "TOPLEFT", centerX, centerY + gap + size * 0.28)
        bars[3]:SetSize(thick, size * 0.42)
        bars[4]:SetPoint("CENTER", preview, "TOPLEFT", centerX, centerY - gap - size * 0.28)
        bars[4]:SetSize(thick, size * 0.42)
        for i = 1, 4 do bars[i]:SetVertexColor(r or 1, gr or 0, b or 0, g.enableCombatCrosshair and 1 or 0.35) end
    end

    disabledRefresh = function()
        local g = Gameplay()
        local timerOn = g.enableCombatTimer == true
        for i = 1, #timerControls do SetControlEnabled(timerControls[i], timerOn) end
        SetControlEnabled(timerEnable, true)

        local stateOn = g.enableCombatStateText == true
        for i = 1, #stateControls do SetControlEnabled(stateControls[i], stateOn) end
        SetControlEnabled(stateEnable, true)

        local totemsOn = hasTotemFrame and g.enablePlayerTotems == true
        SetControlEnabled(totemEnable, hasTotemFrame)
        for i = 1, #totemControls do
            local control = totemControls[i]
            if control ~= totemEnable then SetControlEnabled(control, hasTotemFrame and (totemsOn or control == previewBtn or control == resetTotemBtn)) end
        end

        local firstOn = isRogue and g.enableFirstDanceTimer == true
        SetControlEnabled(firstDanceEnable, isRogue)
        for i = 1, #firstDanceControls do SetControlEnabled(firstDanceControls[i], firstOn) end

        local crossOn = g.enableCombatCrosshair == true
        SetControlEnabled(crossEnable, true)
        for i = 1, #crossControls do SetControlEnabled(crossControls[i], crossOn) end
        local meleeOn = crossOn and g.enableCombatCrosshairMeleeRangeColor == true
        for i = 1, #meleeControls do SetControlEnabled(meleeControls[i], meleeOn) end
    end

    M.AddRefresher(ctx, function()
        disabledRefresh()
        previewRefresh()
    end)
    disabledRefresh()
    previewRefresh()
    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function ApplyClassPower()
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
    CallGlobal("MSUF_ClassPower_RefreshCDMWidthBindings", true)
    M.RequestGeneralApply("MSUF2_CLASSPOWER", { preview = true, applyAll = false })
end

local function ShowClassPowerReloadPrompt()
    if _G.StaticPopupDialogs and not _G.StaticPopupDialogs["MSUF_CLASSPOWER_ENABLE_RELOAD"] then
        _G.StaticPopupDialogs["MSUF_CLASSPOWER_ENABLE_RELOAD"] = {
            text = "Class Resources were enabled or disabled.\n\nA UI reload is required to fully apply this change.\n\nReload now?",
            button1 = RELOADUI,
            button2 = CANCEL,
            OnAccept = function() if ReloadUI then ReloadUI() end end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    if StaticPopup_Show then StaticPopup_Show("MSUF_CLASSPOWER_ENABLE_RELOAD") end
end

local function TextureValues(followText)
    local ui = ns and ns.UI
    if ui and type(ui.StatusBarTextureItems) == "function" then
        return ui.StatusBarTextureItems(followText)
    end
    local out = {}
    if followText then out[#out + 1] = { value = "", text = followText } end
    for _, name in ipairs({ "Blizzard", "Flat", "RaidHP", "RaidPower", "Skills", "Outline" }) do
        out[#out + 1] = { value = name, text = name }
    end
    return out
end

local function BindBarsAlphaPercent(ctx, section, label, key, default, apply, step)
    local slider = W.Slider(section, label, 0, 100, step or 5, 300)
    M.BindSlider(ctx, slider,
        function()
            local value = NumValue(Bars(), key, default or 0)
            if value <= 1 then value = value * 100 end
            if value < 0 then value = 0 elseif value > 100 then value = 100 end
            return floor(value + 0.5)
        end,
        function(v)
            v = tonumber(v) or ((default or 0) * 100)
            if v < 0 then v = 0 elseif v > 100 then v = 100 end
            SetValue(Bars(), key, v / 100, apply)
        end)
    return slider
end

local function ApplyDetachedPowerBar()
    CallGlobal("MSUF_DetachedPowerBar_RefreshTextures")
    CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
    M.RequestGeneralApply("MSUF2_DETACHED_POWER_BAR", { preview = true, power = true, applyAll = false })
end

local function ApplyDetachedPowerBarOutline()
    CallGlobal("MSUF_ApplyBarOutlineThickness_All")
    ApplyDetachedPowerBar()
end

local function BuildClassPower(ctx)
    local b = W.PageBuilder(ctx)
    b:Header("Class Resources", "Native class-resource layout, visibility and text controls.", 64)

    local display = b:CollapsibleSection("classpower_display", "Layout", 420, true)
    local cpControls = {}
    local textControls = {}
    local dpbControls = {}
    local altManaControls = {}

    local cpEnable = BindTableToggle(ctx, display, "Enable", Bars, "showClassPower", true, function()
        ApplyClassPower()
        ShowClassPowerReloadPrompt()
    end)
    local cpHeight = BindTableSlider(ctx, display, "Height", 1, 40, 1, 300, Bars, "classPowerHeight", 4, ApplyClassPower)
    local cpWidthMode = BindTableDropdown(ctx, display, "Width mode", {
        { value = "player", text = "Player frame" },
        { value = "cooldown", text = "Essential Cooldowns" },
        { value = "utility", text = "Utility Cooldowns" },
        { value = "tracked_buffs", text = "Tracked Buffs" },
        { value = "custom", text = "Custom" },
    }, 260, Bars, "classPowerWidthMode", "player", ApplyClassPower)
    local cpWidth = BindTableSlider(ctx, display, "Width", 30, 800, 1, 300, Bars, "classPowerWidth", 0, ApplyClassPower)
    local cpX = BindTableSlider(ctx, display, "Offset X", -800, 800, 1, 300, Bars, "classPowerOffsetX", 0, ApplyClassPower)
    local cpY = BindTableSlider(ctx, display, "Offset Y", -800, 800, 1, 300, Bars, "classPowerOffsetY", 0, ApplyClassPower)
    local cpLevel = BindTableSlider(ctx, display, "Frame level", 0, 30, 1, 300, Bars, "classPowerFrameLevelOffset", 5, ApplyClassPower)
    cpControls[#cpControls + 1] = cpHeight
    cpControls[#cpControls + 1] = cpWidthMode
    cpControls[#cpControls + 1] = cpX
    cpControls[#cpControls + 1] = cpY
    cpControls[#cpControls + 1] = cpLevel

    local behavior = b:CollapsibleSection("classpower_behavior", "Behavior", 328, false)
    local cpAnchor = BindTableToggle(ctx, behavior, "Anchor to Essential Cooldown", Bars, "classPowerAnchorToCooldown", false, ApplyClassPower)
    local cpCharged = BindTableToggle(ctx, behavior, "Show empowered combo points", Bars, "showChargedComboPoints", true, ApplyClassPower)
    local cpText = BindTableToggle(ctx, behavior, "Show resource text", Bars, "classPowerShowText", false, ApplyClassPower)
    local cpRune = BindTableToggle(ctx, behavior, "Show rune time (per rune)", Bars, "runeShowTime", true, ApplyClassPower)
    local cpReverse = BindTableToggle(ctx, behavior, "Fill right-to-left", Bars, "classPowerFillReverse", false, ApplyClassPower)
    local cpEle = BindTableToggle(ctx, behavior, "Show Maelstrom bar (Ele)", Bars, "showEleMaelstrom", false, ApplyClassPower)
    local cpEbon = BindTableToggle(ctx, behavior, "Show Ebon Might timer (Aug)", Bars, "showEbonMight", true, ApplyClassPower)
    local cpShadow = BindTableToggle(ctx, behavior, "Show Insanity bar (Shadow)", Bars, "showShadowMana", false, ApplyClassPower)
    local cpPrediction = BindTableToggle(ctx, behavior, "Show resource prediction", Bars, "classPowerShowPrediction", true, ApplyClassPower)
    for _, control in ipairs({ cpAnchor, cpCharged, cpText, cpRune, cpReverse, cpEle, cpEbon, cpShadow, cpPrediction }) do
        cpControls[#cpControls + 1] = control
    end

    local visual = b:CollapsibleSection("classpower_visuals", "Style", 780, false)
    local cpColor = BindTableToggle(ctx, visual, "Color by resource type", Bars, "classPowerColorByType", true, ApplyClassPower)
    local cpComboColor = BindTableDropdown(ctx, visual, "Combo point colors", {
        { value = "default", text = "Resource color" },
        { value = "ramp", text = "Combo ramp" },
        { value = "custom", text = "Custom slots" },
    }, 260, Bars, "classPowerComboPointColorMode", "default", ApplyClassPower)
    local cpFont = BindTableSlider(ctx, visual, "Font size", 6, 32, 1, 300, Bars, "classPowerFontSize", 16, ApplyClassPower)
    local cpTextX = BindTableSlider(ctx, visual, "Text X", -200, 200, 1, 300, Bars, "classPowerTextOffsetX", 0, ApplyClassPower)
    local cpTextY = BindTableSlider(ctx, visual, "Text Y", -200, 200, 1, 300, Bars, "classPowerTextOffsetY", 0, ApplyClassPower)
    local cpBg = BindBarsAlphaPercent(ctx, visual, "BG opacity", "classPowerBgAlpha", 0.3, ApplyClassPower, 1)
    local cpSeparator = BindTableSlider(ctx, visual, "Separator", 0, 4, 1, 300, Bars, "classPowerTickWidth", 1, ApplyClassPower)
    local cpOutline = BindTableSlider(ctx, visual, "Outline", 0, 4, 1, 300, Bars, "classPowerOutline", 1, ApplyClassPower)
    local cpFilled = BindBarsAlphaPercent(ctx, visual, "Filled %", "classPowerFilledAlpha", 1.0, ApplyClassPower, 5)
    local cpEmpty = BindBarsAlphaPercent(ctx, visual, "Empty %", "classPowerEmptyAlpha", 0.3, ApplyClassPower, 5)
    local cpGap = BindTableSlider(ctx, visual, "Pip gap", 0, 8, 1, 300, Bars, "classPowerGap", 0, ApplyClassPower)
    local cpFgTex = BindTableDropdown(ctx, visual, "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, Bars, "classPowerTexture", "", ApplyClassPower)
    local cpBgTex = BindTableDropdown(ctx, visual, "Background texture", function() return TextureValues("Use foreground texture") end, 300, Bars, "classPowerBgTexture", "", ApplyClassPower)
    for _, control in ipairs({ cpColor, cpComboColor, cpBg, cpSeparator, cpOutline, cpFilled, cpEmpty, cpGap, cpFgTex, cpBgTex }) do
        cpControls[#cpControls + 1] = control
    end
    textControls[#textControls + 1] = cpFont
    textControls[#textControls + 1] = cpTextX
    textControls[#textControls + 1] = cpTextY

    local visibility = b:CollapsibleSection("classpower_visibility", "Auto-Hide", 170, false)
    local hideOOC = BindTableToggle(ctx, visibility, "Hide out of combat", Bars, "classPowerHideOOC", false, ApplyClassPower)
    local hideFull = BindTableToggle(ctx, visibility, "Hide when full", Bars, "classPowerHideWhenFull", false, ApplyClassPower)
    local hideEmpty = BindTableToggle(ctx, visibility, "Hide when empty", Bars, "classPowerHideWhenEmpty", false, ApplyClassPower)
    for _, control in ipairs({ hideOOC, hideFull, hideEmpty }) do cpControls[#cpControls + 1] = control end

    local dpb = b:CollapsibleSection("classpower_detached_power", "Detached Power Bar", 352, false)
    W.Text(dpb, "Only applies when power bar is detached.", 14, -38, ctx.width - 28, T.colors.muted)
    dpb._msuf2CursorY = -72
    local dpbMode = W.Dropdown(dpb, "Width mode", {
        { value = "manual", text = "Manual" },
        { value = "cooldown", text = "Essential Cooldowns" },
        { value = "utility", text = "Utility Cooldowns" },
        { value = "tracked_buffs", text = "Tracked Buffs" },
    }, 260)
    M.BindDropdown(ctx, dpbMode,
        function() return Bars().detachedPowerBarWidthMode or "manual" end,
        function(v)
            Bars().detachedPowerBarWidthMode = (v ~= "manual") and v or nil
            ApplyDetachedPowerBar()
        end)
    local dpbFg = BindTableDropdown(ctx, dpb, "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, Bars, "detachedPowerBarTexture", "", ApplyDetachedPowerBar)
    local dpbBg = BindTableDropdown(ctx, dpb, "Background texture", function() return TextureValues("Use foreground texture") end, 300, Bars, "detachedPowerBarBgTexture", "", ApplyDetachedPowerBar)
    local dpbOutline = BindTableSlider(ctx, dpb, "Power bar outline", 0, 6, 1, 300, Bars, "detachedPowerBarOutline", 1, ApplyDetachedPowerBarOutline)
    for _, control in ipairs({ dpbMode, dpbFg, dpbBg, dpbOutline }) do dpbControls[#dpbControls + 1] = control end

    local altMana = b:CollapsibleSection("classpower_alt_mana", "Alternative Mana Bar", 238, false)
    W.Text(altMana, "Shadow, Ret, Ele, Enh, Balance, Feral, WW", 14, -38, ctx.width - 28, T.colors.muted)
    altMana._msuf2CursorY = -72
    local altManaToggle = BindTableToggle(ctx, altMana, "Show mana bar (dual resource)", Bars, "showAltMana", false, ApplyClassPower)
    local altManaHeight = BindTableSlider(ctx, altMana, "Height", 2, 30, 1, 300, Bars, "altManaHeight", 4, ApplyClassPower)
    local altManaY = BindTableSlider(ctx, altMana, "Y offset", -50, 50, 1, 300, Bars, "altManaOffsetY", -2, ApplyClassPower)
    altManaControls[#altManaControls + 1] = altManaHeight
    altManaControls[#altManaControls + 1] = altManaY

    M.AddRefresher(ctx, function()
        local bars = Bars()
        local cpOn = BoolValue(bars, "showClassPower", true)
        local textOn = cpOn and BoolValue(bars, "classPowerShowText", false)
        local customWidth = cpOn and ((bars.classPowerWidthMode or "player") == "custom")
        local anyDetached = false
        local db = M.EnsureDB()
        for _, key in ipairs({ "player", "target", "focus" }) do
            if db[key] and db[key].powerBarDetached then anyDetached = true; break end
        end
        for i = 1, #cpControls do SetControlEnabled(cpControls[i], cpOn) end
        SetControlEnabled(cpWidth, customWidth)
        for i = 1, #textControls do SetControlEnabled(textControls[i], textOn) end
        for i = 1, #dpbControls do SetControlEnabled(dpbControls[i], anyDetached) end
        local altOn = BoolValue(bars, "showAltMana", false)
        for i = 1, #altManaControls do SetControlEnabled(altManaControls[i], altOn) end
        SetControlEnabled(altManaToggle, true)
        SetControlEnabled(cpEnable, true)
    end)

    local actions = b:Section("Quick Actions", 82)
    local edit = T.Button(actions, "Edit Mode", 156, 24)
    edit:SetPoint("TOPLEFT", actions, "TOPLEFT", 14, -38)
    if T.SkinPrimaryButton then T.SkinPrimaryButton(edit) end
    edit:SetScript("OnClick", function()
        local st = _G.MSUF_EditState
        local active = st and st.active
        local fn = _G.MSUF_SetMSUFEditModeDirect or _G.MSUF_SetEditMode
        if type(fn) == "function" then pcall(fn, not active) end
    end)
    local colors = T.Button(actions, "Class color", 156, 24)
    colors:SetPoint("LEFT", edit, "RIGHT", 12, 0)
    colors:SetScript("OnClick", function() M.SelectPage("opt_colors") end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function BuildProfiles(ctx)
    local b = W.PageBuilder(ctx)
    b:Header("Profiles", "Create, switch, copy, delete, export and import profiles.", 64)

    local current = b:CollapsibleSection("profiles_management", "Profile Management", 278, true)
    local profileDrop = W.Dropdown(current, "Active profile", {}, 260)
    local function RefreshProfileValues()
        local values = {}
        local list = type(_G.MSUF_GetAllProfiles) == "function" and _G.MSUF_GetAllProfiles() or { "Default" }
        for i = 1, #list do values[#values + 1] = { value = list[i], text = list[i] } end
        profileDrop.values = values
    end
    profileDrop:SetOnValueChanged(function(value)
        if type(_G.MSUF_SwitchProfile) == "function" then pcall(_G.MSUF_SwitchProfile, value) end
        M.RequestGeneralApply("MSUF2_PROFILE_SWITCH", { preview = true })
        if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    end)
    M.AddRefresher(ctx, function()
        RefreshProfileValues()
        profileDrop:SetValue(_G.MSUF_ActiveProfile or "Default")
    end)
    local nameInput = W.TextInput(current, "New / target profile name", 260)
    local create = W.Button(current, "Create profile", 150)
    create:SetScript("OnClick", function()
        local name = nameInput:GetText()
        if name and name ~= "" and type(_G.MSUF_CreateProfile) == "function" then
            pcall(_G.MSUF_CreateProfile, name)
            pcall(_G.MSUF_SwitchProfile, name)
        end
        M.InvalidatePage("profiles")
        M.SelectPage("profiles")
    end)
    local copy = T.Button(current, "Copy current to name", 170, 24)
    copy:SetPoint("LEFT", create, "RIGHT", 8, 0)
    copy:SetScript("OnClick", function()
        local name = nameInput:GetText()
        if name and name ~= "" and type(_G.MSUF_CopyProfile) == "function" then
            pcall(_G.MSUF_CopyProfile, _G.MSUF_ActiveProfile or "Default", name)
            M.InvalidatePage("profiles")
            M.SelectPage("profiles")
        end
    end)
    local reset = W.Button(current, "Reset current profile", 170)
    reset:SetScript("OnClick", function()
        if type(_G.MSUF_ResetProfile) == "function" then pcall(_G.MSUF_ResetProfile, _G.MSUF_ActiveProfile or "Default") end
        M.RequestGeneralApply("MSUF2_PROFILE_RESET", { preview = true })
    end)
    local delete = T.Button(current, "Delete current profile", 170, 24)
    delete:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    T.SkinDangerButton(delete)
    delete:SetScript("OnClick", function()
        if type(_G.MSUF_DeleteProfile) == "function" then pcall(_G.MSUF_DeleteProfile, _G.MSUF_ActiveProfile or "Default") end
        M.InvalidatePage("profiles")
        M.SelectPage("profiles")
    end)

    local io = b:CollapsibleSection("profiles_io", "Export / Import", 232, false)
    local exportKind = W.Dropdown(io, "Export kind", {
        { value = "all", text = "Full profile" },
        { value = "unitframe", text = "Unitframes" },
        { value = "colors", text = "Colors" },
        { value = "gameplay", text = "Gameplay" },
        { value = "groupframe", text = "Group Frames" },
    }, 240)
    M.BindDropdown(ctx, exportKind,
        function() return M.profileExportKind or "all" end,
        function(v) M.profileExportKind = v or "all" end)
    local blob = W.TextInput(io, "Profile string", 640)
    blob._msuf2CommitOnBlur = false
    local export = W.Button(io, "Export", 120)
    export:SetScript("OnClick", function()
        local fn = _G.MSUF_ExportSelectionToString
        if type(fn) == "function" then
            local ok, value = pcall(fn, M.profileExportKind or "all")
            if ok and type(value) == "string" then blob:SetText(value); blob:HighlightText() end
        end
    end)
    local import = T.Button(io, "Import into current", 160, 24)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)
    import:SetScript("OnClick", function()
        local text = blob:GetText()
        if text and text ~= "" and type(_G.MSUF_ImportFromString) == "function" then
            pcall(_G.MSUF_ImportFromString, text)
            M.RequestGeneralApply("MSUF2_PROFILE_IMPORT", { preview = true })
        end
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function BuildModules(ctx)
    local b = W.PageBuilder(ctx)
    b:Header("Modules", "Optional MSUF style and visual modules.", 64)
    local style = b:CollapsibleSection("modules_style", "Style", 230, true)
    local enable = W.Toggle(style, "Enable MSUF Style")
    M.BindToggle(ctx, enable,
        function()
            if type(_G.MSUF_StyleIsEnabled) == "function" then
                local ok, v = pcall(_G.MSUF_StyleIsEnabled)
                if ok then return v and true or false end
            end
            return G().styleEnabled ~= false
        end,
        function(v)
            if type(_G.MSUF_SetStyleEnabled) == "function" then pcall(_G.MSUF_SetStyleEnabled, v and true or false) end
            G().styleEnabled = v and true or false
            CallGlobal("MSUF_ApplyModules")
        end)
    local dropdownMode = W.Dropdown(style, "Dropdown style", {
        { text = "MSUF superellipse", value = "msuf" },
        { text = "Blizzard legacy", value = "old" },
    }, 230)
    M.BindDropdown(ctx, dropdownMode,
        function()
            if type(_G.MSUF_GetDropdownStyleMode) == "function" then
                local ok, value = pcall(_G.MSUF_GetDropdownStyleMode)
                if ok then return value or "msuf" end
            end
            local mode = G().dropdownStyleMode
            return (mode == "old" or mode == "blizzard" or mode == "legacy") and "old" or "msuf"
        end,
        function(v)
            v = (v == "old") and "old" or "msuf"
            if type(_G.MSUF_ApplyDropdownStyleModeImmediate) == "function" then
                pcall(_G.MSUF_ApplyDropdownStyleModeImmediate, v)
            elseif type(_G.MSUF_SetDropdownStyleMode) == "function" then
                pcall(_G.MSUF_SetDropdownStyleMode, v)
                G().dropdownStyleMode = v
            else
                G().dropdownStyleMode = v
            end
        end)
    BindTableToggle(ctx, style, "Rounded unitframes", G, "roundedUnitframes", false, function() CallGlobal("MSUF_ApplyModules") end)
    BindTableToggle(ctx, style, "Portrait decoration", G, "portraitDecorationEnabled", false, function() CallGlobal("MSUF_ApplyModules") end)
    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("auras2", { title = "MSUF Unit Auras", build = BuildAuras, version = 3 })
M.RegisterPage("opt_colors", { title = "MSUF Colors", build = BuildColors, version = 2 })
M.RegisterPage("gameplay", { title = "MSUF Gameplay", build = BuildGameplay, version = 2 })
M.RegisterPage("classpower", { title = "MSUF Class Resources", build = BuildClassPower, version = 2 })
M.RegisterPage("profiles", { title = "MSUF Profiles", build = BuildProfiles })
M.RegisterPage("modules", { title = "MSUF Modules", build = BuildModules })
