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
    W.SetControlEnabled(panel.apply, panel.current.targets ~= nil or panel.widthChanged or panel.colorChanged or false)
end

local function SelectRow(panel, id)
    local row = panel.rows[id]
    panel.current = row
    panel.widthChanged, panel.colorChanged = false, false
    panel.refreshing = true
    panel.select:SetValue(id)
    panel.slider:SetMinMaxValues(row.min, row.max)
    panel.slider:SetValue(row.getWidth and row.getWidth() or math.max(row.min, 1))
    panel.initialWidth = panel.slider:GetValue()
    W.SetControlEnabled(panel.slider, not row.widthEnabled or row.widthEnabled())
    W.SetControlEnabled(panel.color, not row.colorEnabled or row.colorEnabled())
    panel.refreshing = false
    panel.color:SetShown(row.getColor ~= nil)
    panel.color._msuf2Title:SetShown(row.getColor ~= nil)
    if row.getColor then panel.color:SetRGB(row.getColor()) end
    local hint = row.targets and not row.pixels and "The same value may render at different widths."
        or row.pixels and "Screen pixels" or "Scaled UI units"
    T.SetTranslatedText(panel.units, M.Tr(hint))
    RefreshApply(panel)
end

local function Apply(panel)
    if M.BlockCombatAction() then return end
    local row, width = panel.current, panel.slider:GetValue()
    local ok = M.RunWithHistory(M.Tr("Outline settings"), "menu:outline:" .. panel.select:GetValue(), function()
        if row.targets then
            local applied = true
            for _, target in ipairs(row.targets) do
                if target.batch() and target.setWidth(width) == false then applied = false end
            end
            return applied
        end
        if panel.widthChanged and ((row.widthEnabled and not row.widthEnabled()) or row.setWidth(width) == false) then
            return false
        end
        if panel.colorChanged and ((row.colorEnabled and not row.colorEnabled()) or row.setColor(panel.color:GetRGB()) == false) then
            return false
        end
        return true
    end)
    SelectRow(panel, panel.select:GetValue())
    if ok == false and M.ShowStatusFeedback then M.ShowStatusFeedback(M.Tr("Action failed"), "danger", 1.5) end
    if M.RefreshVisibleSliders then M.RefreshVisibleSliders("outline") end
end

local function BuildPopup()
    local panel = M.CreateMenuPopupPanel(UIParent)
    panel:SetSize(392, 226)
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
        panel.widthChanged = panel.slider:GetValue() ~= panel.initialWidth
        RefreshApply(panel)
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
    if #choices == 0 then return end
    popup = popup or BuildPopup()
    popup.anchor, popup.rows = anchor, byID
    popup.select:SetValues(choices)
    local id = focus and focus()
    SelectRow(popup, byID[id] and id or choices[1].value)
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
