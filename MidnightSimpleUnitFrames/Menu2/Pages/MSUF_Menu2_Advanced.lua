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
    return W.MoveWidget(widget, parent, x, y)
end

local function LabelAt(parent, text, x, y, width, template, color)
    return W.LabelAt(parent, text, x, y, width, template, color)
end

local function DividerAt(parent, y)
    return W.DividerAt(parent, y)
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
    W.SetControlEnabled(widget, enabled)
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

    local layout = b:CollapsibleSection("a2_layout", "Caps & Icons", 414, true)
    ScopedSliderAt(ctx, layout, "Max Buffs", 12, -24, 0, 40, 1, 118, function() return AuraCaps() end, "maxBuffs", 8, ForceAuraCapsOverride, ApplyAuras)
    ScopedSliderAt(ctx, layout, "Max Debuffs", 192, -24, 0, 40, 1, 118, function() return AuraCaps() end, "maxDebuffs", 15, ForceAuraCapsOverride, ApplyAuras)
    ScopedSliderAt(ctx, layout, "Icons per row", 372, -24, 1, 20, 1, 118, function() return AuraCaps() end, "perRow", 11, ForceAuraCapsOverride, ApplyAuras)
    ScopedSliderAt(ctx, layout, "Block spacing", 552, -24, 0, 40, 1, 118, function() return AuraCaps() end, "splitSpacing", 0, ForceAuraCapsOverride, ApplyAuras)
    DividerAt(layout, -98)
    ScopedSliderAt(ctx, layout, "Icon size", 12, -118, 12, 64, 1, 118, function() return AuraLayout() end, "iconSize", 26, ForceAuraLayoutOverride, ApplyAuras)
    ScopedSliderAt(ctx, layout, "Spacing", 192, -118, 0, 12, 1, 118, function() return AuraLayout() end, "spacing", 2, ForceAuraLayoutOverride, ApplyAuras)
    ScopedDropdownAt(ctx, layout, "Row layout", 372, -118, {
        { value = "SEPARATE", text = "Separate rows" },
        { value = "SINGLE", text = "Single row (Mixed)" },
    }, 210, function() return AuraCaps() end, "layoutMode", "SEPARATE", ForceAuraCapsOverride, ApplyAuras)
    ScopedDropdownAt(ctx, layout, "Stack Anchor", 12, -204, AURA_STACK_ANCHORS, 210, function() return AuraCaps() end, "stackCountAnchor", "TOPRIGHT", ForceAuraCapsOverride, ApplyAuras)
    ValueDropdownAt(ctx, layout, "Buff Growth", 248, -204, AURA_GROWTH, 210,
        function() local c = AuraCaps(); return c.buffGrowth or c.growth or "RIGHT" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().buffGrowth = v or "RIGHT"; ApplyAuras() end)
    ValueDropdownAt(ctx, layout, "Debuff Growth", 484, -204, AURA_GROWTH, 210,
        function() local c = AuraCaps(); return c.debuffGrowth or c.growth or "RIGHT" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().debuffGrowth = v or "RIGHT"; ApplyAuras() end)
    ValueDropdownAt(ctx, layout, "Private Growth", 12, -288, AURA_GROWTH, 210,
        function() local c = AuraCaps(); return c.privateGrowth or c.growth or "RIGHT" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().privateGrowth = v or "RIGHT"; ApplyAuras() end)
    ValueDropdownAt(ctx, layout, "Buff wrap rows", 248, -288, AURA_ROW_WRAP, 210,
        function() local c = AuraCaps(); return c.buffRowWrap or c.rowWrap or "DOWN" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().buffRowWrap = v or "DOWN"; ApplyAuras() end)
    ValueDropdownAt(ctx, layout, "Debuff wrap rows", 484, -288, AURA_ROW_WRAP, 210,
        function() local c = AuraCaps(); return c.debuffRowWrap or c.rowWrap or "DOWN" end,
        function(v) ForceAuraCapsOverride(); AuraCaps().debuffRowWrap = v or "DOWN"; ApplyAuras() end)
    ValueDropdownAt(ctx, layout, "Sort order", 12, -352, AURA_SORT_ORDER, 250,
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
AdvancedPage.BindValueSlider = BindValueSlider
AdvancedPage.ToggleAt = ToggleAt
AdvancedPage.ValueToggleAt = ValueToggleAt
AdvancedPage.SliderAt = SliderAt
AdvancedPage.ValueSliderAt = ValueSliderAt
AdvancedPage.DropdownAt = DropdownAt
AdvancedPage.ValueDropdownAt = ValueDropdownAt
AdvancedPage.ColorAt = ColorAt
AdvancedPage.ScopedToggleAt = ScopedToggleAt
AdvancedPage.ScopedSliderAt = ScopedSliderAt
AdvancedPage.ScopedDropdownAt = ScopedDropdownAt
AdvancedPage.TogglePillAt = TogglePillAt
AdvancedPage.SetControlEnabled = SetControlEnabled

M.RegisterPage("auras2", { title = "MSUF Unit Auras", build = BuildAuras, version = 4 })
