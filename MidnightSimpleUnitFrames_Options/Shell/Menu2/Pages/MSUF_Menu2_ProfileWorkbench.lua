local _, MSUF = ...
local M = MSUF.MSUF2
local W, AP, T = MSUF.ProfileWorkbench, M.AdvancedPage, M.Theme
local state = { change = 1, point = 0, preset = "deuteranopia", variant = "" }
local PAGE = "profiles"
local importReviewShown = false
local function Refresh()
    local page = M.activeKey or PAGE
    if page == "profiles" and importReviewShown ~= (state.reviewPage == "profiles" and state.review ~= nil) then
        M.InvalidatePage(page)
        M.RebuildPageKeepingScroll(page)
        return
    end
    M.ProfileVariantPage.Dirty()
    M.RequestRefresh(nil, "profile-workbench")
end
local function Result(ok, why)
    if not ok then M.ShowStatusFeedback(M.Tr(tostring(why or "Action unavailable")), "danger", 6)
    else Refresh() end
    return ok
end
local function Meta(id, classification)
    if PAGE == "opt_colors" and id:sub(1, 7) == "review." then id = "accessibility." .. id end
    return M.ControlMeta("profile_tools", "profiles", id, classification or "ephemeral", { pageKey = PAGE })
end
local function Text(section, label, y, width)
    return M.ProfileVariantPage.Row(nil, section, { "text", "workbench.text." .. tostring(y), nil,
        { label, 20, y, width - 40, T.colors.muted } })
end
local function Button(section, label, id, x, y, action, width)
    local meta = Meta(id, "action")
    local widget = M.ProfileVariantPage.Row(nil, section, { "button", meta.controlId, nil, { label, width or 180, 28 }, meta = meta })
    widget:SetPoint("TOPLEFT", section, "TOPLEFT", x, y)
    widget:SetText(M.Tr(label))
    widget:SetScript("OnClick", action)
    AP.RegisterControl(widget, meta, label, "button")
    return widget
end
local function Input(section, label, id, x, y, width, initial, set)
    local meta = Meta(id)
    local widget = M.ProfileVariantPage.Row(nil, section, { "textinput", meta.controlId, nil, { label, width }, bind = AP.NativeInput, preserveInput = true })
    M.Widgets.MoveWidget(widget, section, x, y, width)
    local text = initial or ""
    if widget:GetText() ~= text then widget:SetText(text) end
    widget._msufWorkbenchInputChanged = set
    if widget._msufWorkbenchInputHooked ~= true then
        widget._msufWorkbenchInputHooked = true
        widget:HookScript("OnTextChanged", function(self, user)
            if user then self._msufWorkbenchInputChanged(self:GetText()) end
        end)
    end
    AP.RegisterControl(widget, meta, label, "editbox")
    return widget
end
local function Drop(ctx, section, label, id, values, get, set, x, y, width)
    local meta = Meta(id)
    local widget = M.ProfileVariantPage.Row(ctx, section, { "dropdown", meta.controlId, nil, { label, values, width }, bind = function(drop)
        M.Widgets.MoveWidget(drop, section, x, y, width)
        M.BindDropdownWidget(ctx, drop, get, set, meta)
        AP.RegisterControl(drop, meta, label, "dropdown", values)
    end })
    return widget
end
local function Editor(ctx, builder, width, draw, section)
    local owner = PAGE
    local editor = M.ProfileVariantPage
    editor.Editor({ ctx = ctx, b = builder, section = section }, function(current)
        PAGE = owner
        local proxy = setmetatable({}, { __index = builder })
        function proxy:CollapsibleSection(id, title, height, open)
            return editor.Section(current, id, title, height, open)
        end
        draw(current.ctx, proxy, width)
    end)
end
local function Value(value)
    if value == nil then return M.Tr("Default / not set") end
    if type(value) == "table" then
        local keys, parts = {}, {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for i = 1, math.min(6, #keys) do
            local item = value[keys[i]]
            parts[#parts + 1] = tostring(keys[i]) .. " = " .. (type(item) == "table" and "{…}" or tostring(item))
        end
        return table.concat(parts, ", "):sub(1, 240)
    end
    return tostring(value):sub(1, 240)
end
local function Label(change)
    return M.ProfileVariantPage.FieldLabel(change.path)
end
local function Timeline(ctx, builder, width)
    local section = builder:CollapsibleSection("workbench_versions", "Restore points", 220, true)
    Text(section, "Save a named version of your current settings. The newest 12 versions share an 8 MiB limit.", -16, width)
    Input(section, "Restore point name", "version.name", 20, -60, width - 40, state.name,
        function(value) state.name = value end)
    Button(section, "Save restore point", "version.save", 20, -116,
        function() Result(W.Checkpoint(state.name or M.Tr("Restore point"))) end)
    local values = { { value = 0, text = "Choose a restore point" } }
    for _, point in ipairs(W.Points()) do
        local label = point.automatic and M.Tr(point.label) or point.label
        local stamp = point.time and date("%Y-%m-%d %H:%M", point.time) or tostring(point.id)
        values[#values + 1] = { value = point.id, text = stamp .. " · " .. label, translate = false }
    end
    Drop(ctx, section, "Saved versions", "version.select", values, function() return state.point end,
        function(value) state.point = value end, 220, -92, math.max(160, width - 240))
    Button(section, "Restore selected version", "version.restore", 20, -166, function() Result(W.Restore(state.point)) end, 220)
    Button(section, "Delete restore point", "version.delete", 254, -166, function() Result(W.DeletePoint(state.point)) end)
end
local function ImportReviewValid()
    return state.reviewPage == "profiles" and state.review ~= nil and M.profileImportCreateNew ~= true
        and state.reviewSource == M.profileImportString and state.reviewProfile == M.EnsureDB()
end
local function ReviewRows(ctx, section, width)
    local review = state.reviewPage == PAGE and state.review
    if not review then return end
    local values = {}
    local query = (state.changeQuery or ""):lower()
    for i, change in ipairs(review.changes) do
        local label = Label(change)
        if query == "" or label:lower():find(query, 1, true) then
            values[#values + 1] = { value = i, text = (change.selected and "[+] " or "[–] ") .. label, translate = false }
            if #values >= 100 then break end
        end
    end
    Input(section, "Find a changed setting", "review.find", 20, -146, width - 40, state.changeQuery,
        function(value) state.changeQuery = value end)
    Button(section, "Filter changes", "review.filter", 20, -201, Refresh)
    Drop(ctx, section, "Changes to review", "review.change", values, function() return state.change end,
        function(value) state.change = value Refresh() end, 20, -249, width - 40)
    local change = review.changes[state.change]
    if change then
        Text(section, M.Format("Before: %s", Value(change.before)), -309, width)
        Text(section, M.Format("After: %s", Value(change.value)), -339, width)
        Button(section, change.selected and "Keep current value" or "Accept this change", "review.toggle", 20, -379,
            function() change.selected = not change.selected Refresh() end, 220)
    end
    Button(section, "Keep positions", "review.positions", 20, -421,
        function() W.Preserve(review, "positions", true) Refresh() end)
    Button(section, "Keep fonts", "review.fonts", 220, -421,
        function() W.Preserve(review, "fonts", true) Refresh() end)
    Button(section, "Select all changes", "review.all", 20, -461, function()
        for _, item in ipairs(review.changes) do item.selected = true end
        Refresh()
    end)
    Button(section, "Clear selection", "review.none", 220, -461, function()
        for _, item in ipairs(review.changes) do item.selected = false end
        Refresh()
    end)
    Button(section, "Apply selected changes", "review.apply", 20, -505, function()
        if state.review ~= review or (state.reviewPage == "profiles" and not ImportReviewValid()) then return end
        local ok, why = W.CommitReview(review)
        if ok then state.review = nil end
        Result(ok, why)
    end, 220)
    Text(section, M.Format("Changes available: %s", tostring(#review.changes)), -549, width)
end
local function Import(ctx, builder, width)
    if not ImportReviewValid() then return end
    local section = builder:CollapsibleSection("workbench_review", "Review imported settings", 590, true)
    state.reviewSection = section
    ReviewRows(ctx, section, width)
end
local function Inspector(ctx, builder, width)
    builder:LazyCollapsibleSection("workbench_inspector", "Changed settings and sources", 245, false, function(section)
        section._msuf2ProfileRows = {}
        Editor(ctx, builder, width, function(editorCtx)
            ctx = editorCtx
            PAGE = "profiles"
    local changes, why = W.Changes()
    local values = {}
    for i, change in ipairs(changes or {}) do values[#values + 1] = { value = i, text = Label(change), translate = false } end
    Drop(ctx, section, "Changed from factory defaults", "inspector.select", values,
        function() return state.inspected or 1 end, function(value) state.inspected = value Refresh() end, 20, -30, width - 40)
    local change = changes and changes[state.inspected or 1]
    if change then
        Text(section, M.Format("Effective value: %s", Value(change.effective)), -92, width)
        Text(section, M.Format("Factory value: %s", Value(change.default)), -122, width)
        Text(section, M.Format("Source: %s", M.Tr(change.source)), -152, width)
        Button(section, "Revert this setting", "inspector.revert", 20, -190, function() Result(W.Revert(change)) end)
    elseif why then Text(section, why, -92, width) end
        end, section)
    end)
end
local function Accessibility(ctx, builder, width)
    local reviewing = state.reviewPage == "opt_colors" and state.review ~= nil
    local section = builder:CollapsibleSection("workbench_accessibility", "Color vision accessibility", reviewing and 590 or 155, true)
    Drop(ctx, section, "Color preset", "accessibility.preset", {
        { value = "deuteranopia", text = "Deuteranopia" }, { value = "protanopia", text = "Protanopia" },
        { value = "tritanopia", text = "Tritanopia" } }, function() return state.preset end,
        function(value) state.preset = value end, 20, -30, width - 40)
    Button(section, "Review accessibility changes", "accessibility.review", 20, -92, function()
        local review, why = W.Accessibility(state.preset)
        state.review, state.change, state.reviewPage = review, 1, "opt_colors"
        Result(review ~= nil, why)
    end, 250)
    Button(section, "Open live color preview", "accessibility.preview", 284, -92,
        function() M.SetMenuStateValue("colorsPainterCategory", "unit") M.RebuildPageKeepingScroll("opt_colors") end, 230)
    ReviewRows(ctx, section, width)
end
local function Display(ctx, builder, width)
    local section = builder:CollapsibleSection("workbench_display", "Layouts for your display", 440, false)
    local values = {}
    for _, entry in ipairs((M.EnsureDB().profileVariants or {}).entries or {}) do
        values[#values + 1] = { value = entry.name, text = entry.name, translate = false }
    end
    Drop(ctx, section, "Existing layout variant", "display.variant", values, function() return state.variant end,
        function(value) state.variant = value end, 20, -30, width - 40)
    Input(section, "Minimum display width (pixels)", "display.width", 20, -100, (width - 60) / 2, state.width or "0",
        function(value) state.width = value end)
    Input(section, "Minimum aspect ratio (width / height)", "display.aspect", (width + 20) / 2, -100,
        (width - 60) / 2, state.aspect or "0", function(value) state.aspect = value end)
    Input(section, "Maximum display width (pixels)", "display.maxwidth", 20, -164, (width - 60) / 2, state.maxWidth or "32000",
        function(value) state.maxWidth = value end)
    Input(section, "Maximum aspect ratio (width / height)", "display.maxaspect", (width + 20) / 2, -164,
        (width - 60) / 2, state.maxAspect or "8", function(value) state.maxAspect = value end)
    Button(section, "Save display condition", "display.save", 20, -228, function()
        local w, a = tonumber(state.width or "0"), tonumber(state.aspect or "0")
        local mw, ma = tonumber(state.maxWidth or "32000"), tonumber(state.maxAspect or "8")
        if not w or not a or not mw or not ma then return Result(false, "Enter a valid number.") end
        Result(W.DisplayRule(state.variant, w, a, mw, ma))
    end, 230)
    Text(section, "Record frame positions and relative scale in the selected variant. Display changes apply only when its match changes.", -268, width)
    Input(section, "New display layout name", "display.name", 20, -323, width - 40, state.displayName,
        function(value) state.displayName = value end)
    Button(section, "Record a layout for this display", "display.record", 20, -383, function()
        local ok, why = W.BeginDisplayLayout(state.displayName)
        if ok then
            M.ProfileVariantPage.EditorBar(ctx)
            local EM = MSUF.Require("MSUF_EM2", "Shell/Menu2/Pages/MSUF_Menu2_ProfileWorkbench.lua")
            if not EM.State.IsActive() then M.ToggleMSUFEditMode() end
        end
        Result(ok, why)
    end, 280)
end
local UI = { Button = Button, Text = Text, Drop = Drop, Input = Input, Result = Result, Value = Value,
    Editor = Editor, Refresh = Refresh }
M.ProfileWorkbenchUI = UI
function UI.Owner(page) PAGE = page end
function UI.Profiles(ctx, builder, width, part)
    PAGE = "profiles"
    if part == "versions" then Editor(ctx, builder, width, Timeline)
    elseif part == "display" then Editor(ctx, builder, width, Display)
    elseif part == "review" then
        importReviewShown = ImportReviewValid()
        if importReviewShown then Editor(ctx, builder, width, Import) end
    elseif part == "inspector" then Inspector(ctx, builder, width) end
end
function UI.HasReview() return ImportReviewValid() end
function UI.ImportChanged(text)
    if state.reviewPage ~= "profiles" or not state.review then return end
    if text == state.reviewSource and ImportReviewValid() then return end
    state.review = nil
    if state.reviewSection then state.reviewSection:Hide() end
end
function UI.ReviewImport(text)
    if M.profileImportCreateNew == true then return false end
    text = text or ""
    local review, why = W.ReviewImport(text)
    M.profileImportString = text
    state.reviewSource, state.reviewProfile = text, M.EnsureDB()
    state.review, state.change, state.reviewPage = review, 1, "profiles"
    return Result(review ~= nil, why)
end
function UI.Colors(ctx, builder)
    PAGE = "opt_colors"
    Editor(ctx, builder, math.max(520, builder.width or ctx.width or 640), Accessibility)
end
function UI.Aura(ctx, builder, unit, lane)
    PAGE = "uf_" .. unit
    for _, row in ipairs(W.Visibility(unit, lane)) do
        if row.unit == unit and row.lane == lane then
            local section = builder:CollapsibleSection("workbench_visibility", "Why is this hidden?", 100, false)
            Text(section, "Known configuration only. Protected combat information is not inspected.", -18, builder.width)
            Text(section, M.Tr(row.reason), -50, builder.width)
            if row.detail then Text(section, row.detail, -76, builder.width) end
            break
        end
    end
end
local function BuildSelection(ctx)
    PAGE = "edit_selection"
    local builder = M.Widgets.PageBuilder(ctx)
    builder:Header("Move and align multiple elements",
        "Choose elements here or Ctrl-click their movers. Alignment uses the first selected element in the list.", 76)
    M.BuildMultiSelectionTools(ctx, builder, math.max(520, builder.width or ctx.width or 640))
    ctx:SetContentHeight(math.abs(builder.y) + 42)
end
M.RegisterPage("edit_selection", { title = "Move and align multiple elements", build = BuildSelection, version = 1 })
-- Direct old page links remain useful.
M.ALIASES.profile_tools = "profiles"
