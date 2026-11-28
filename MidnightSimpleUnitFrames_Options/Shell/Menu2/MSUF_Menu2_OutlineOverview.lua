local _, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Menu2/OutlineOverview")
local M = MSUF.MSUF2
local W, T = M.Widgets, M.Theme
local providers = {}
local settingResolvers = {}
local popup

-- Providers describe settings only when this menu opens. The regular settings
-- pages continue to own profile values, history and repaint requests.
function M.RegisterOutlineOverviewProvider(id, collect)
    providers[id] = collect
end

function M.RegisterOutlineSettingResolver(namespace, resolve)
    settingResolvers[namespace] = resolve
end

local function CollectCastbarOutline(rows)
    local GP = M.GlobalPage
    local colors = MSUF._colorsAPI
    rows[#rows + 1] = {
        id = "core.castbar.outline", group = "Castbars", label = "Border", min = 0, max = 6,
        batch = function() return true end,
        getWidth = function() return GP.ReadG("castbarOutlineThickness", 1) end,
        setWidth = function(value)
            if GP.ReadG("castbarOutlineThickness", 1) == value then return true end
            GP.SetG("castbarOutlineThickness", value, "MSUF2_CASTBAR_OUTLINE", { preview = true, castbar = true })
            return true
        end,
        getColor = colors.GetCastbarBorderColor,
        setColor = function(r, g, b)
            local _, _, _, a = colors.GetCastbarBorderColor()
            colors.SetCastbarBorderColor(r, g, b, a)
            return true
        end,
    }
end
M.RegisterOutlineOverviewProvider("core.castbars", CollectCastbarOutline)

local function Collect(focused)
    local rows = {}
    for _, collect in pairs(providers) do collect(rows) end
    if focused then
        local found
        for _, row in ipairs(rows) do
            if row.id == focused.id then found = true break end
        end
        if not found then rows[#rows + 1] = focused end
    end
    table.sort(rows, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)
    return rows
end

local function Batch(rows, pixelsOnly)
    local targets = {}
    local minimum, maximum = 0, math.huge
    for _, row in ipairs(rows) do
        if row.batch and (not pixelsOnly or row.pixels) and row.batch() then
            minimum, maximum = math.max(minimum, row.min), math.min(maximum, row.max)
            targets[#targets + 1] = row
        end
    end
    if #targets == 0 or minimum > maximum then return end
    return {
        min = minimum, max = maximum, pixels = pixelsOnly, targets = targets,
        label = pixelsOnly and "All pixel borders" or "All outlines",
    }
end

local function RefreshApply(panel)
    local match = panel.current.getMatchTooltip and panel.match:GetChecked()
    local changed = panel.matchChanged or not match and (panel.widthChanged or panel.colorChanged)
    W.SetControlEnabled(panel.apply, changed == true)
end

local function RefreshMode(panel)
    local row = panel.current
    local match = row.getMatchTooltip and panel.match:GetChecked()
    W.SetControlEnabled(panel.slider, not match and (not row.widthEnabled or row.widthEnabled()))
    W.SetControlEnabled(panel.color, not match and (not row.colorEnabled or row.colorEnabled()))
    local hint = row.targets and not row.pixels and "The same value may render at different widths."
        or match and "Tooltip" or row.pixels and "Screen pixels" or "Scaled UI units"
    T.SetTranslatedText(panel.units, M.Tr(hint))
    RefreshApply(panel)
end

local function SelectRow(panel, id, retainedWidth)
    local row = panel.rows[id]
    panel.current = row
    panel.widthChanged, panel.colorChanged, panel.matchChanged = false, false, false
    panel.refreshing = true
    panel.select:SetValue(id)
    local hasWidth = row.getWidth ~= nil or row.targets ~= nil
    if hasWidth then
        panel.slider:SetMinMaxValues(row.min, row.max)
        panel.slider:SetValue(retainedWidth or (row.getWidth and row.getWidth()) or math.max(row.min, 1))
        panel.initialWidth = panel.slider:GetValue()
    end
    panel.refreshing = false
    W.SetControlShown(panel.slider, hasWidth)
    panel.units:SetShown(hasWidth)
    panel.color:SetShown(row.getColor ~= nil)
    panel.color._msuf2Title:SetShown(row.getColor ~= nil)
    if row.getColor then panel.color:SetRGB(row.getColor()) end
    panel.open:SetShown(row.open ~= nil)
    panel.initialMatch = row.getMatchTooltip and row.getMatchTooltip() or false
    panel.match:SetChecked(panel.initialMatch)
    panel.matchHost:SetShown(row.getMatchTooltip ~= nil)
    RefreshMode(panel)
end

-- One validated update per Suite module, even when it owns hundreds of elements.
local function ApplyBatch(targets, width)
    local groups, ordered, direct = {}, {}, {}
    for _, target in ipairs(targets) do
        if target.batch() and target.getWidth() ~= width then
            if target.batchGroup then
                local group = groups[target.batchGroup]
                if not group then
                    group = { values = {}, commit = target.setWidths }
                    groups[target.batchGroup] = group
                    ordered[#ordered + 1] = group
                end
                group.values[target.widthKey] = width + target.widthOffset
            else
                direct[#direct + 1] = target
            end
        end
    end
    local changed, failed = false, false
    for _, row in ipairs(direct) do
        if row.setWidth(width) == false then failed = true else changed = true end
    end
    for _, group in ipairs(ordered) do
        if group.commit(group.values) == false then failed = true else changed = true end
    end
    return changed, failed
end

local function ApplySingle(panel, row, width)
    local match = row.getMatchTooltip and panel.match:GetChecked()
    if not match and ((panel.widthChanged and row.widthEnabled and not row.widthEnabled())
        or (panel.colorChanged and row.colorEnabled and not row.colorEnabled())) then
        return false, true
    end
    local changed = false
    if panel.matchChanged then
        if row.setMatchTooltip(match and true or false) == false then return false, true end
        changed = true
    end
    if match then return changed, false end
    if panel.widthChanged then
        if row.setWidth(width) == false then return changed, true end
        changed = true
    end
    if panel.colorChanged then
        if row.setColor(panel.color:GetRGB()) == false then return changed, true end
        changed = true
    end
    return changed, false
end

local function Apply(panel)
    if M.BlockCombatAction() or not panel.apply:IsEnabled() then return end
    local row, width = panel.current, panel.slider:GetValue()
    local id, failed = panel.select:GetValue(), false
    M.RunWithHistory(M.Tr("Outline settings"), "menu:outline:" .. id, function()
        local changed
        if row.targets then changed, failed = ApplyBatch(row.targets, width)
        else changed, failed = ApplySingle(panel, row, width) end
        return changed
    end)
    SelectRow(panel, id, row.targets and width)
    if failed and M.ShowStatusFeedback then M.ShowStatusFeedback(M.Tr("Action failed"), "danger", 1.5) end
    if M.RefreshVisibleSliders then M.RefreshVisibleSliders("outline") end
end

local function BuildPopup()
    local panel = M.CreateMenuPopupPanel(UIParent)
    panel:SetSize(392, 235)
    panel:SetClampedToScreen(true)
    panel.SmartNavigationCloseHandler = function()
        panel:Hide()
        return true
    end
    if M.frame then M.frame:HookScript("OnHide", function() panel:Hide() end) end
    panel._msuf2ContentX, panel._msuf2CursorY = 16, -45
    local heading = T.Font(panel, "GameFontNormal", "Outline settings", T.colors.accent)
    heading:SetPoint("TOPLEFT", 16, -15)
    local close = M.CreateWindowControlButton(panel, "close")
    close:SetPoint("TOPRIGHT", -8, -7)
    close:SetScript("OnClick", function() panel:Hide() end)

    panel.select = W.Dropdown(panel, "Element", {}, 360)
    W.MoveWidget(panel.select, panel, 16, -44, 360, "LEFT")
    panel.select:SetOnValueChanged(function(id) SelectRow(panel, id) end)
    panel.slider = W.Slider(panel, "Border thickness", 0, 10, 1, 360)
    W.MoveWidget(panel.slider, panel, 16, -101, 360, "LEFT")
    panel.slider:HookScript("OnValueChanged", function()
        if panel.refreshing or not panel.current then return end
        panel.widthChanged = panel.current.targets ~= nil or panel.slider:GetValue() ~= panel.initialWidth
        RefreshApply(panel)
    end)
    panel.slider:HookScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and panel.current and panel.current.targets then
            panel.widthChanged = true
            RefreshApply(panel)
        end
    end)
    panel.units = W.Text(panel, "", 16, -149, 360, T.colors.muted)
    panel.color = W.Color(panel, "Outline color")
    W.MoveWidget(panel.color, panel, 16, -172, 230, "LEFT")
    W.SetControlDisabledReason(panel.slider, "Unavailable with the current settings.")
    W.SetControlDisabledReason(panel.color, "Unavailable with the current settings.")
    panel.color:SetScript("OnClick", function(self)
        if M.BlockCombatAction() then return end
        local row = panel.current
        W.OpenColorContextPicker("Outline color", { self }, nil, self, function()
            if panel.current ~= row then return end
            local r, g, b = row.getColor()
            local chosenR, chosenG, chosenB = self:GetRGB()
            panel.colorChanged = r ~= chosenR or g ~= chosenG or b ~= chosenB
            RefreshApply(panel)
        end)
    end)
    panel.matchHost = PixelLayoutRegion(CreateFrame("Frame", nil, panel))
    panel.matchHost:SetPoint("BOTTOMLEFT", 16, 12)
    panel.matchHost:SetSize(260, 24)
    panel.match = W.SwitchAt(panel.matchHost, "Match tooltip border", 0, -2, 230)
    panel.match._msuf2SkipHistoryCheckpoint = true
    panel.match:SetScript("OnClick", function(self)
        panel.matchChanged = (self:GetChecked() and true or false) ~= panel.initialMatch
        RefreshMode(panel)
    end)
    panel.apply = T.Button(panel, "Apply", 88, 24, { noSearch = true })
    panel.apply:SetPoint("BOTTOMRIGHT", -16, 12)
    panel.apply._msuf2SkipHistoryCheckpoint = true
    panel.apply:SetScript("OnClick", function() Apply(panel) end)
    panel.open = T.Button(panel, "Open settings", 124, 24, { noSearch = true })
    panel.open:SetPoint("BOTTOMLEFT", 16, 12)
    panel.open._msuf2SkipHistoryCheckpoint = true
    panel.open:SetScript("OnClick", function()
        if M.BlockCombatAction() then return end
        local open = panel.current.open
        panel:Hide()
        if open then open() end
    end)
    return panel
end

local function Show(anchor)
    if M.BlockCombatAction() then return end
    if popup and popup:IsShown() and popup.anchor == anchor then popup:Hide() return end
    local id = anchor._msuf2OutlineFocus and anchor._msuf2OutlineFocus()
    local describe = anchor._msuf2OutlineDescribe
    local rows, choices, byID = Collect(id and describe and describe(id)), {}, {}
    local function Add(id, row, label)
        byID[id] = row
        choices[#choices + 1] = { value = id, text = label, translate = false }
    end
    local all, pixels = Batch(rows, false), Batch(rows, true)
    if all then Add("@all", all, M.Tr(all.label)) end
    if pixels then Add("@pixels", pixels, M.Tr(pixels.label)) end
    for _, row in ipairs(rows) do
        Add(row.id, row, M.Format("%s / %s", M.Tr(row.group), row.localizedLabel and row.label or M.Tr(row.label)))
    end
    if #rows == 0 then return end
    popup = popup or BuildPopup()
    popup.anchor, popup.rows = anchor, byID
    popup.select:SetValues(choices)
    SelectRow(popup, byID[id] and id or rows[1].id)
    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -5)
    M.ApplyPopupFramePriority(popup)
    popup:Show()
end

function M.AttachOutlineOverview(control, focus, placement, describe)
    local gear = control._msuf2OutlineGear
    if gear then
        if gear._msuf2OutlinePositioned and not (placement or describe) then return gear end
        gear._msuf2OutlineFocus, gear._msuf2OutlineDescribe = focus, describe
        return gear
    end
    local title = control._msuf2Title or control._msuf2Label
    if not (placement or title) then return end
    local parent = placement and control or control:GetParent()
    gear = T.Button(parent, "", 20, 18, { noSearch = true })
    control._msuf2OutlineGear = gear
    gear._msuf2OutlineFocus, gear._msuf2OutlineDescribe = focus, describe
    gear._msuf2OutlinePositioned = placement ~= nil
    gear._msuf2SkipHistoryCheckpoint = true
    if placement == true then
        gear:SetPoint("LEFT", control, "RIGHT", 4, 0)
    elseif placement then
        gear:SetPoint("RIGHT", placement.anchor or control, "RIGHT", placement.offsetX, 0)
    else
        if title:IsShown() then gear:SetPoint("TOPRIGHT", title, "TOPRIGHT", 0, 2)
        else gear:SetPoint("RIGHT", control, "LEFT", -5, 0) end
        control:HookScript("OnShow", function() gear:Show() end)
        control:HookScript("OnHide", function() gear:Hide() end)
        gear:SetShown(control:IsShown())
    end
    gear:SetFrameLevel(control:GetFrameLevel() + 4)
    local icon = PixelLayoutRegion(gear:CreateTexture(nil, "ARTWORK"))
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetScript("OnClick", Show)
    gear:SetScript("OnHide", function(self)
        if popup and popup.anchor == self then popup:Hide() end
    end)
    M.AddTooltip(gear, "Outline settings", nil, { hook = true, owner = "ANCHOR_RIGHT" })
    return gear
end

function M.CloseOutlineOverview()
    if popup then popup:Hide() end
end

local function IsFrameBorder(key, label)
    if label:find("text outline", 1, true) or label:find("font outline", 1, true) then return false end
    if key:find("nooutline", 1, true) or key:find("fontoutline", 1, true)
        or key:find("textoutline", 1, true) or key:find("text.outline", 1, true) then return false end
    if key:match("castoutline$") or (key:find("font", 1, true) and not key:find("border", 1, true)) then return false end
    return key:find("border", 1, true) or key:find("outerframe", 1, true) or key:match("%.rim$")
        or key:find("outline", 1, true)
end

local function CoreFocus(key)
    if key:match("%.castbarOutlineThickness$") or key == "general.castbarBorder"
        or key == "general.castbarBorderColor" or key == "cast.border" then return "core.castbar.outline" end
    if key == "general.barOutlineColor" then return "core.frame.shared" end
    if key == "bar.outline" then return "core.frame.shared" end
    if key == "group.border" then return function() return "core.group.border." .. M.GroupPage.CurrentScope() end end
    if key == "group.focus" then return function() return "core.group.focus." .. M.GroupPage.CurrentScope() end end
end

function M.ConsiderOutlineColorShortcut(shortcut, setting, label, getTarget, focus)
    if not shortcut then return end
    return M.ConsiderOutlineOverview(shortcut, {
        settingKey = setting, label = label, outlineFocus = focus, describeOutline = function(id)
            local target = getTarget()
            local row = { id = id, group = "Frame Outline", label = target and target.label or label or "Border",
                open = function() shortcut:Click() end }
            local get = target and (target.getRGB or target.get)
            local set = target and (target.setRGB or target.set)
            if get and set then
                row.getColor, row.colorEnabled = get, target.isEnabled
                row.setColor = function(r, g, b)
                    local _, _, _, a = get()
                    return set(r, g, b, a)
                end
            end
            return row
        end,
    }, shortcut, -34)
end

local function IsWidthKey(key)
    return key:find("thickness", 1, true) or key:find("size", 1, true)
        or key:match("borderwidth$") or key:match("outlinewidth$")
        or key:match("outline$") or key:match("border$")
end

-- A bound control carries the gear only when the popup edits its value: a
-- thickness slider or a color. Styles, opacity, distance, edge toggles and
-- section switches keep their own controls without a gear.
local function EditsOutline(control, key)
    local command = control._msuf2CommandAction
    local kind = command and command.kind
    return kind == "color" or (kind == "slider" and IsWidthKey(key) ~= nil)
end

local function DescribeControl(control, id, label, key)
    local command = control._msuf2CommandAction
    local parent = control:GetParent()
    local row = { id = id, group = parent and parent._msuf2ControlCardTitle or "Frame Outline", label = label,
        open = function() T.PlayNeonFlash(control, "success") end }
    if not (command and command.get and command.set) then return row end
    local function Enabled() return control:IsVisible() and (not control.IsEnabled or control:IsEnabled()) end
    if command.kind == "slider" and IsWidthKey(key) then
        local minimum, maximum = control:GetMinMaxValues()
        if minimum % 1 == 0 and maximum % 1 == 0 then
            row.min, row.max = minimum, maximum
            row.getWidth, row.setWidth, row.widthEnabled = command.get, command.set, Enabled
        end
    elseif command.kind == "color" then
        row.getColor, row.colorEnabled = command.get, Enabled
        row.setColor = function(r, g, b)
            local _, _, _, a = command.get()
            return command.set(r, g, b, a)
        end
    end
    return row
end

function M.ConsiderOutlineOverview(control, info, anchor, offsetX)
    if info.outlineFocus == false then return end
    local key = type(info.settingKey) == "string" and info.settingKey or nil
    local resolver = key and settingResolvers[key:match("^([^.]+)%.")]
    local focus = info.outlineFocus or (resolver and resolver(key)) or (key and CoreFocus(key))
    local label = info.label or control._msuf2SearchText or control._msuf2SearchTitle or "Border"
    if type(label) ~= "string" then label = "Border" end
    local identity = key or (type(info.controlId) == "string" and info.controlId)
    if not identity and (label == "Outline thickness" or label == "Border thickness" or label == "Window outline") then
        identity = (M.PageKeyForWidget(control) or "outline") .. "." .. label
    end
    if not focus and (not identity or not IsFrameBorder(identity:lower(), label:lower())) then return end
    local actualKey = (identity or ""):lower()
    -- Color shortcuts describe their own row (ConsiderOutlineColorShortcut).
    if not info.describeOutline and not EditsOutline(control, actualKey) then return end
    if not focus then focus = "outline." .. identity end
    local resolveFocus = focus
    if type(focus) ~= "function" then resolveFocus = function() return focus end end
    local placement = anchor and { anchor = anchor, offsetX = offsetX } or nil
    return M.AttachOutlineOverview(control, resolveFocus, placement, info.describeOutline or function(id)
        return DescribeControl(control, id, label, actualKey)
    end)
end
