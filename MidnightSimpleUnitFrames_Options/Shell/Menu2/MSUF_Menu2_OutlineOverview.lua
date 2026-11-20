local _, MSUF = ...
local M = MSUF.MSUF2
local W, T = M.Widgets, M.Theme
local providers = {}
local popup

-- Providers describe settings only when this menu opens. The regular settings
-- pages continue to own profile values, history and repaint requests.
function M.RegisterOutlineOverviewProvider(id, collect)
    providers[id] = collect
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

local function Collect()
    local rows = {}
    for _, collect in pairs(providers) do collect(rows) end
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
    panel.slider:SetMinMaxValues(row.min, row.max)
    panel.slider:SetValue(retainedWidth or (row.getWidth and row.getWidth()) or math.max(row.min, 1))
    panel.initialWidth = panel.slider:GetValue()
    panel.refreshing = false
    panel.color:SetShown(row.getColor ~= nil)
    panel.color._msuf2Title:SetShown(row.getColor ~= nil)
    if row.getColor then panel.color:SetRGB(row.getColor()) end
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
    M.frame:HookScript("OnHide", function() panel:Hide() end)
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
    panel.matchHost = CreateFrame("Frame", nil, panel)
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
    return panel
end

local function Show(anchor, focus)
    if M.BlockCombatAction() then return end
    if popup and popup:IsShown() and popup.anchor == anchor then popup:Hide() return end
    local rows, choices, byID = Collect(), {}, {}
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
    local id = focus and focus()
    SelectRow(popup, byID[id] and id or rows[1].id)
    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -5)
    M.ApplyPopupFramePriority(popup)
    popup:Show()
end

function M.AttachOutlineOverview(slider, focus)
    local parent, title = slider:GetParent(), slider._msuf2Title
    if not title then return end
    local gear = T.Button(parent, "", 20, 18, { noSearch = true })
    gear._msuf2SkipHistoryCheckpoint = true
    gear:SetPoint("TOPRIGHT", title, "TOPRIGHT", 0, 2)
    gear:SetFrameLevel(slider:GetFrameLevel() + 4)
    local icon = gear:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetScript("OnClick", function(self) Show(self, focus) end)
    gear:SetScript("OnHide", function(self)
        if popup and popup.anchor == self then popup:Hide() end
    end)
    M.AddTooltip(gear, "Outline settings", nil, { hook = true, owner = "ANCHOR_RIGHT" })
end
