-- Resource selection, scoped actions and exact navigation. Gameplay remains in ClassPower.
local _, MSUF = ...
local M = MSUF.MSUF2
local W, AP = M.Widgets, M.AdvancedPage
local Workspace = {}
M.ClassPowerWorkspace = Workspace
local LABELS = { class = "Class Resource", power = "Player Power", hp = "Extra Health Bar",
    mana = "Alternative Mana", extras = "Additional resources" }
local ORDER = { "class", "power", "hp", "mana", "extras" }
local SECTIONS = { classpower_detached_power = "power", classpower_detached_power_textures = "power",
    classpower_detached_power_text = "power", classpower_player_hp = "hp", classpower_player_hp_textures = "hp",
    classpower_player_hp_text = "hp", classpower_alt_mana = "mana", classpower_alt_mana_behavior = "mana",
    classpower_resource_extras = "extras", classpower_resource_marks = "extras",
    classpower_resource_pain = "extras", classpower_resource_arcane = "extras", classpower_resource_layout = "extras" }
local COPY = {
    { key = "size", label = "Size", fields = { "width", "height", "orb" } },
    { key = "appearance", label = "Appearance", fields = { "texture", "background", "alpha", "outline" } },
    { key = "text", label = "Text size", fields = { "fontSize" } },
    { key = "behavior", label = "Smooth fill", fields = { "smooth" } },
}
local FIELDS = {
    class = { width = "bars.classPowerWidth", height = "bars.classPowerHeight", texture = "bars.classPowerTexture",
        background = "bars.classPowerBgTexture", alpha = "bars.classPowerBgAlpha", outline = "bars.classPowerOutline",
        fontSize = "bars.classPowerFontSize", smooth = "bars.classPowerSmoothFill" },
    power = { width = "player.detachedPowerBarWidth", height = "player.detachedPowerBarHeight", orb = "player.detachedPowerOrbSize",
        outline = "bars.detachedPowerBarOutline", fontSize = "player.powerFontSize", smooth = "player.powerSmoothFill" },
    hp = { width = "bars.playerHPBarWidth", height = "bars.playerHPBarHeight", orb = "bars.playerHPBarOrbSize",
        texture = "bars.playerHPBarTexture", background = "bars.playerHPBarBgTexture", alpha = "bars.playerHPBarBgAlpha",
        outline = "bars.playerHPBarOutline", fontSize = "bars.playerHPBarTextSize", smooth = "bars.playerHPBarSmoothFill" },
    mana = { width = "bars.altManaWidth", height = "bars.altManaHeight", smooth = "bars.altManaSmoothFill" },
}
local PREVIEW_FIELDS = { class = "classPower", power = "detachedPower", hp = "playerHP", mana = "altMana" }
local LIMITS = {
    class = { width = { 30, 800 }, height = { 1, 40 }, fontSize = { 6, 32 }, outline = { 0, 8 }, alpha = { 0, 1 } },
    power = { width = { 20, 800 }, height = { 2, 80 }, fontSize = { 6, 48 }, orb = { 20, 160 }, outline = { 0, 8 } },
    hp = { width = { 20, 1200 }, height = { 2, 80 }, fontSize = { 6, 48 }, orb = { 20, 160 }, outline = { 0, 8 }, alpha = { 0, 1 } },
    mana = { width = { 20, 1200 }, height = { 2, 30 } },
}
local function Read(db, path)
    local scope, key = path:match("^(%w+)%.(.+)$")
    return db[scope] and db[scope][key]
end
local function Write(db, path, value)
    local scope, key = path:match("^(%w+)%.(.+)$")
    db[scope] = db[scope] or {}
    db[scope][key] = AP.DeepCopyTable(value)
end
function Workspace.KindForPath(path)
    if path:find("^detached_power%.") or path == "layout.independent_powerbar_shape" then return "power" end
    if path:find("^player_hp%.") then return "hp" end
    if path:find("^alternative_mana%.") then return "mana" end
    if path:find("^resource_extras%.") then return "extras" end
    return "class"
end
function Workspace.Decorate(exact, path)
    local kind = Workspace.KindForPath(path)
    exact.searchPrepareKind, exact.searchPrepareValue = "classPowerWorkspace", kind
    exact.prepareExactSearchTarget = function()
        if kind == "extras" then M.ResourceExtrasPreview.FocusPath(path) end
        return Workspace.Select(kind)
    end
    local persisted = exact.settingKey and (exact.settingKey:find("^bars%.") or exact.settingKey:find("^player%."))
    if Workspace.current and persisted then Workspace.current.keys[kind][exact.settingKey] = true end
    return exact
end
function Workspace.Select(kind)
    if not LABELS[kind] then return false end
    M.classPowerWorkspaceKey = kind
    local ui = Workspace.current
    if ui then return ui:Select(kind) end
    return true
end
local UI = {}
UI.__index = UI
function UI:Track(section, id)
    local entry = section._msuf2CollapsibleEntry
    if not entry then return end
    local kind = SECTIONS[id] or "class"
    self.entries[kind][#self.entries[kind] + 1] = entry
    entry._msuf2EnsureVisible = function() self:Select(kind, true) end
end
function UI:Select(kind, fromFocus, building)
    if not LABELS[kind] or self.selecting then return false end
    self.selecting = true
    if self.selected ~= kind and self.hideCopy then self.hideCopy() end
    self.selected, M.classPowerWorkspaceKey = kind, kind
    local visible = {}
    for _, key in ipairs(ORDER) do
        for _, entry in ipairs(self.entries[key]) do
            entry.outer:SetShown(key == kind)
            if key == kind then visible[#visible + 1] = entry end
        end
    end
    self.page.b.layoutEntries = visible
    self.page.b:RequestRelayoutCollapsibles()
    if self.selector then self.selector:Refresh() end
    M.ResourceExtrasPreview.UpdateHeader(self.page.ctx, kind)
    if self.copyButton then self.copyButton:SetShown(kind ~= "extras") end
    if not fromFocus and visible[1] and not visible[1].open then
        W.FocusCollapsibleSection(visible[1].body, { scroll = false, flash = false })
    end
    self.selecting = nil
    local preview = self.page.ctx.entry.classPowerPreview
    if preview then preview._selectedWorkspaceKey = kind
        if not building then preview:Refresh() end
    end
    if not building then self.page.refresh() end
    return true
end
function UI:ResolvedWidth(db, kind)
    local box = self.page.ctx.entry.classPowerPreview
    local frame = box and box[PREVIEW_FIELDS[kind]]
    if frame and frame:IsShown() then return frame:GetWidth() end
    local configured = tonumber(Read(db, FIELDS[kind].width))
    if configured and configured >= 20 then return configured end
    return tonumber(db.player.width) or 250
end
function UI:Copy(target, scopes)
    if M.BlockCombatAction() or not FIELDS[target] or target == self.selected then return false end
    local source, destination = FIELDS[self.selected], FIELDS[target]
    local selected, changed = false, false
    for _, category in ipairs(COPY) do if scopes[category.key] then selected = true end end
    if not selected then M.ShowStatusFeedback("No copy categories selected.", "warning", 2) return false end
    M.RunWithHistory("Copy resource bar settings", "classpower:copy:" .. self.selected, function()
        local db = M.EnsureDB()
        for _, category in ipairs(COPY) do
            if scopes[category.key] then
                for _, field in ipairs(category.fields) do
                    if source[field] and destination[field] then
                        local value = field == "width" and self:ResolvedWidth(db, self.selected) or Read(db, source[field])
                        if value ~= nil then
                            local limits = LIMITS[target][field]
                            if limits then value = math.max(limits[1], math.min(limits[2], value)) end
                            Write(db, destination[field], value)
                            if field == "width" then
                                local modes = { class = "bars.classPowerWidthMode", power = "bars.detachedPowerBarWidthMode",
                                    hp = "bars.playerHPBarWidthMode", mana = "bars.altManaWidthMode" }
                                Write(db, modes[target], target == "power" and "manual" or "custom")
                                if target == "power" then db.player.detachedPowerBarSyncClassPower = false end
                            end
                            changed = true
                        end
                    end
                end
            end
        end
        if changed then self.page.applyWorkspace() end
    end)
    if not changed then M.ShowStatusFeedback("No compatible settings to copy.", "warning", 2) end
    return changed
end
function UI:Reset()
    if M.BlockCombatAction() then return false end
    local kind = self.selected
    M.ShowPrompt("MSUF2_RESOURCE_BAR_RESET", {
        text = M.Format("Reset %s to defaults?", M.Tr(LABELS[kind])), accept = M.Tr("Reset"), cancel = CANCEL,
        onAccept = function()
            if M.BlockCombatAction() then return end
            local defaults = MSUF.MSUF_CreateFactoryDefaultProfile()
            M.RunWithHistory("Reset resource bar settings", "classpower:reset:" .. kind, function()
                local db = M.EnsureDB()
                for path in pairs(self.keys[kind]) do Write(db, path, Read(defaults, path)) end
                self.page.applyWorkspace()
            end)
        end,
    })
    return true
end
function UI:BuildActions(head, selectorH)
    local button = M.Theme.Button(head, "Copy To", 92, 24, { history = false })
    button:SetPoint("TOPRIGHT", head, "TOPRIGHT", -16, -selectorH - 46)
    local target, scopes = "power", { size = true, appearance = true, text = true, behavior = false }
    local popup = M.UnitSectionsShared.MakeScopeCopyPopup(button, {
        controlDomain = "classpower", controlPageKey = "classpower", controlPath = "copy",
        width = 460, height = 260, categories = COPY, scopes = scopes, categoryRowsPerColumn = 2,
        targets = { "class", "power", "hp", "mana" }, targetWidths = { class = 108, power = 90, hp = 104, mana = 104 },
        sourceKey = function() return self.selected end,
        sourceLabel = function(key) return M.Tr(LABELS[key]) end,
        targetLabelText = function(key) return LABELS[key] end,
        selectedTarget = function()
            if target == self.selected then target = self.selected == "power" and "class" or "power" end
            return target
        end,
        isTargetVisible = function(key, source) return key ~= source end,
        onTargetClick = function(key) target = key end,
        runLabel = "Copy Selected", runWidth = 128,
        onRun = function(_, frame) if self:Copy(target, scopes) then frame:Hide() return true end return false end,
    })
    button:SetScript("OnClick", function() popup.Show(button) end)
    head:HookScript("OnHide", popup.Hide)
    self.copyButton, self.copyPopup, self.copyScopes, self.hideCopy = button, popup, scopes, popup.Hide
    M.AddTooltip(button, "Copy To",
        "Copies compatible settings. Keeps positions, anchors and activation. Player Power uses Player power text size and smoothing.")
    local reset = M.Theme.Button(head, "Reset selected", 110, 24, { history = false })
    reset:SetPoint("RIGHT", button, "LEFT", -8, 0)
    reset:SetScript("OnClick", function() self:Reset() end)
    self.resetButton = reset
end
function Workspace.Attach(page, settingKeys)
    local ui = setmetatable({ page = page, entries = {}, keys = {}, selected = M.classPowerWorkspaceKey or "class" }, UI)
    for _, kind in ipairs(ORDER) do ui.entries[kind], ui.keys[kind] = {}, {} end
    for path, key in pairs(settingKeys) do ui.keys[Workspace.KindForPath(path)][key] = true end
    ui.keys.power["player.detachedPowerBarShape"] = true
    for _, slot in ipairs({ "Left", "Center", "Right" }) do
        ui.keys.power["player.powerText" .. slot .. "OffsetX"] = true
        ui.keys.power["player.powerText" .. slot .. "OffsetY"] = true
    end
    for key in pairs(M.ResourceExtrasPage.SettingKeys()) do ui.keys.extras[key] = true end
    local create = page.b.CollapsibleSection
    page.b.CollapsibleSection = function(builder, id, ...)
        local section = create(builder, id, ...)
        ui:Track(section, id)
        return section
    end
    page.ctx._msuf2ClassPowerWorkspace, Workspace.current = ui, ui
    return ui
end
function Workspace.BuildSelector(ui, head, width)
    local values = {}
    local measure = M.Theme.Font(head, "GameFontHighlightSmall", "")
    local available = math.max(86, width - 32)
    for _, kind in ipairs(ORDER) do
        measure:SetText(LABELS[kind])
        values[#values + 1] = { value = kind, text = LABELS[kind],
            width = math.min(available, math.max(86, math.ceil(measure:GetStringWidth()) + 26)) }
    end
    measure:Hide()
    local opts = { values = values, width = width, maxRight = width - 16,
        label = "", labelWidth = 0, startX = 16,
        getValue = function() return ui.selected end, setValue = function(value) ui:Select(value) end }
    local metrics = W.MeasureScopeOverrideBar(values, opts)
    local selector = W.ScopeOverrideBar(ui.page.ctx, head, opts)
    local meta = M.ControlMeta("classpower", "advanced", "workspace", "ephemeral")
    M.BindSegment(ui.page.ctx, selector, opts.getValue, opts.setValue, meta)
    AP.RegisterControl(selector, meta, "Editing", "segment", values)
    ui.selector = selector
    selector:Refresh()
    local selectorH = math.max(54, math.abs(metrics.bottomY) + 14)
    ui:BuildActions(head, selectorH)
    return selectorH
end

-- Shared binding adapters retain exact-search preparation only when explicitly
-- registered. Keep this correction local to the resource workspace.
local BINDERS = { toggle = M.BindBoolWidget, dropdown = M.BindDropdownWidget, color = M.BindColor }
function Workspace.Bind(kind, ctx, widget, get, set, fallback, meta)
    if kind == "dropdown" then
        widget._msuf2StableSearchLabel = widget._msuf2StableSearchLabel
            or (widget._msuf2Title and widget._msuf2Title._msuf2SearchText)
    end
    if kind == "slider" then M.BindNumberWidget(ctx, widget, get, set, fallback, meta)
    else BINDERS[kind](ctx, widget, get, set, meta) end
    AP.RegisterControl(widget, meta, nil, kind)
    return widget
end
function Workspace.BindBoolWidget(ctx, widget, get, set, meta)
    return Workspace.Bind("toggle", ctx, widget, get, set, nil, meta)
end
function Workspace.BindDropdownWidget(ctx, widget, get, set, meta)
    return Workspace.Bind("dropdown", ctx, widget, get, set, nil, meta)
end
function Workspace.BindNumberWidget(ctx, widget, get, set, fallback, meta)
    return Workspace.Bind("slider", ctx, widget, get, set, fallback, meta)
end
function Workspace.BindColor(ctx, widget, get, set, meta)
    return Workspace.Bind("color", ctx, widget, get, set, nil, meta)
end
function Workspace.RegisterSpec(control, spec)
    local kinds = { alpha = "slider", playerPowerOutline = "slider", detachedPowerWidth = "slider",
        comboColorMode = "dropdown", nilDefaultDropdown = "dropdown", detachedTextOnBar = "toggle", detachedTextPreset = "dropdown" }
    local kind = kinds[spec[2]] or spec[2]
    if kind == "dropdown" then control._msuf2StableSearchLabel = control._msuf2StableSearchLabel or spec[3] end
    AP.RegisterControl(control, spec.meta, spec[3], kind, kind == "dropdown" and spec[4] or nil)
end
