local addonName, MSUF = ...
MSUF = MSUF or {}
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace.lua")
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Auras page: compact Custom Aura workspace.
-- Owns M.BuildAuras3CompactCustomWorkspace, the one-tool-at-a-time editor for
-- Custom 1-3, Defensive Buffs and Dots on target for every supported client.
-- It binds AuraSettings/AuraControls directly and is called lazily from the
-- unit Auras section.
local W = M.Widgets
local T = M.Theme
local A3 = MSUF.MSUF_Auras3
local Model = A3 and A3.MenuModel
local VTP, AurasPage = M.ValueTextPairs, M.AurasPage
assert(W and T and Model and M.AuraSettings and M.AuraControls,
    "Custom aura workspace requires widgets, theme, model and shared aura controls")
local CreateFrame = CreateFrame
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local tonumber, tostring, type, pairs = tonumber, tostring, type, pairs
-- Ordinary controls are schema rows (MSUF_Menu2_Auras.lua owns the row policy).
local BindSwitch, BindSlider = AurasPage.Switch, AurasPage.Slider
local BindDropdown, BindTextInput = AurasPage.Dropdown, AurasPage.TextInput
local AURA_COOLDOWN_COLOR_REFERENCES = M.AuraSettings.AURA_COOLDOWN_COLOR_REFERENCES
local AURA_SORT_DIRECTION_VALUES, ActionButton = M.AuraSettings.AURA_SORT_DIRECTION_VALUES, M.AuraControls.ActionButton
local AddAuraTooltipHelp, AddTooltip, AnchorLabel = M.AuraControls.AddAuraTooltipHelp, M.AuraControls.AddTooltip, M.AuraSettings.AnchorLabel
local ApplyUnit, AuraCatalogToken, AuraControlMeta = M.AuraControls.ApplyUnit, M.AuraControls.AuraCatalogToken, M.AuraControls.AuraControlMeta
local AuraControlMetaAtVisiblePath, AuraSortMethodValues = M.AuraControls.AuraControlMetaAtVisiblePath, M.AuraSettings.AuraSortMethodValues
-- Custom container entries always carry their spell ID.
local FilterSpellEntries = M.AuraControls.FilterSpellEntries
local COOLDOWN_SWIPE_DIRECTION_VALUES, CUSTOM_FRAME_EFFECTS = M.AuraSettings.COOLDOWN_SWIPE_DIRECTION_VALUES, M.AuraSettings.CUSTOM_FRAME_EFFECTS
local ChoiceLabel, ConfigureAuraSpellPriorityDrag = M.AuraSettings.ChoiceLabel, M.AuraControls.ConfigureAuraSpellPriorityDrag
local ConfigureMaxDurationSlider, DEBUFF_TYPE_BORDER_MODE_VALUES = M.AuraControls.ConfigureMaxDurationSlider, M.AuraSettings.DEBUFF_TYPE_BORDER_MODE_VALUES
local DURATION_BAR_DIRECTION_VALUES, DURATION_BAR_DISPLAY_VALUES = M.AuraSettings.DURATION_BAR_DIRECTION_VALUES, M.AuraSettings.DURATION_BAR_DISPLAY_VALUES
local DURATION_BAR_POSITION_VALUES, MatchSuffix = M.AuraSettings.DURATION_BAR_POSITION_VALUES, M.AuraSettings.MatchSuffix
local NATIVE_EXACT_AURA_FILTERS_TEXT, NormalizeAuraSortMethodForLane =
    M.AuraSettings.NATIVE_EXACT_AURA_FILTERS_TEXT, M.AuraSettings.NormalizeAuraSortMethodForLane
local QueueAurasPageRefresh, Rebuild = M.AuraControls.QueueAurasPageRefresh, M.AuraControls.Rebuild
-- A list edit repaints the page in place; Rebuild is kept for the edits that
-- change which controls the tools build (aura type, a container reset).
local Repaint, RegisterAuraControl = M.AuraControls.Repaint, AurasPage.Bound(M.AuraControls.RegisterAuraControl)
local RegisterAuraTextAction, Round, Tr = AurasPage.Bound(M.AuraControls.RegisterAuraTextAction), M.AuraSettings.Round, M.AuraSettings.Tr
local function CustomStyleSectionId(index, suffix)
    return "aura_style_custom_" .. tostring(index or 1) .. "_" .. tostring(suffix or "section")
end
local CUSTOM_AURA_TYPES = VTP "BUFF=Buff|DEBUFF=Debuff"
-- Reminder is the container's operating mode, not a styling detail: it turns
-- a compacting list into one fixed slot per whitelisted entry. It belongs
-- next to Aura type, where the other structural decision already lives.
local REMINDERS_AVAILABLE = not MSUF.Client.IsClassic
local CLASSIC_REMINDER_NOTICE = "Fixed slots and missing-aura reminders are unavailable on Classic. Saved settings are kept; active auras still work."
local CUSTOM_DISPLAY_MODES = VTP "active=Only active auras|reminder=Fixed slots (reminder)"
-- Section titles compose the translated container name into one translated
-- format string, so they are shown as they are.
local TRANSLATED_TITLE = { translated = true }
local function ContainerTitle(C)
    if C.isPlayerDefensives or C.isTargetDots then return Tr(C.containerLabel) end
    return M.Format("Custom %d", C.index)
end
--- A list Search input. Its text is ephemeral menu state that the list
--- painters read from the returned record; typing repaints at once and a
--- commit stores the same text.
local function BindListSearch(ctx, section, y, width, path, onChange)
    local search = { value = "" }
    local searchInput = BindTextInput(ctx, section, "Search", 24, y, width,
        function() return search.value end,
        function(value)
            search.value = tostring(value or "")
            onChange()
        end,
        true, AuraControlMeta(ctx, path, "ephemeral"))
    if searchInput and searchInput.HookScript then
        searchInput:HookScript("OnTextChanged", function(self)
            search.value = self.GetText and tostring(self:GetText() or "") or ""
            onChange()
        end)
    end
    return search
end
--- An ephemeral text input and the button that submits it. A successful
--- submit (spec.submit) clears the input, applies spec.reason with a refresh
--- and repaints; the button is the input's registered search text action.
local function BindInputAction(C, section, spec)
    local ctx, Apply = C.ctx, C.Apply
    local inputValue = ""
    local input = BindTextInput(ctx, section, spec.label, 24, spec.y, spec.width,
        function() return inputValue end,
        function(value) inputValue = value or "" end,
        false, AuraControlMeta(ctx, spec.path, "ephemeral"))
    local button = ActionButton(section, spec.button, spec.buttonWidth, spec.role)
    button:SetPoint(spec.point, section, spec.point, spec.x, spec.buttonY)
    button:SetScript("OnClick", function()
        local value = input and input.GetText and input:GetText() or inputValue
        local changed = spec.submit(value)
        if changed then
            if input and input.SetText then input:SetText("") end
            inputValue = ""
            Apply(spec.reason, true)
            Repaint(ctx)
        end
        return changed and true or false
    end)
    RegisterAuraTextAction(ctx, button, input, spec.button, spec.actionPath, spec.route)
    return input, button
end
--- The search action contract of every input that adds a tracked spell.
local function AddSpellRoute(C)
    return {
        actionKey = "aura_custom_whitelist_add_spell",
        actionFixedArgs = { scope = C.unit, index = C.index },
        actionInputArg = "value",
    }
end
--- A nested list scroll frame at (24, y) and its child, styled like the other
--- nested aura lists.
local function ListScroll(section, y, inner, height, childHeight, step)
    local listScroll = PixelLayoutRegion(CreateFrame("ScrollFrame", nil, section))
    listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, y)
    listScroll:SetSize(inner - 20, height)
    local listChild = PixelLayoutRegion(CreateFrame("Frame", nil, listScroll))
    listChild:SetSize(inner - 44, childHeight)
    listScroll:SetScrollChild(listChild)
    M._StyleNestedAuraScrollFrame(listScroll, section, step)
    return listScroll, listChild
end
--- A row button that runs op(spellID) on its row's spell; when that changed
--- the container it applies reason with a refresh and repaints.
local function RowAction(C, row, button, reason, op)
    local ctx, Apply = C.ctx, C.Apply
    button:SetScript("OnClick", function()
        if row._spellID and op(row._spellID) then
            Apply(reason, true)
            Repaint(ctx)
        end
    end)
end
--- Dragging a tracked-spell row moves its spell and activates Custom Priority.
local function RowPriorityDrag(C, row, listChild, rowHeight, reason)
    local ctx, unit, index, Apply = C.ctx, C.unit, C.index, C.Apply
    AddTooltip(row, "Drag to reorder", "Drag this row to a new position. Reordering activates Custom Priority.")
    ConfigureAuraSpellPriorityDrag(row, row, listChild, rowHeight, function(spellID, target)
        if Model.MoveCustomContainerSpellToIndex(unit, index, spellID, target) then
            Model.EnableCustomContainerSpellPriority(unit, index)
            Apply(reason, true)
            Repaint(ctx)
        end
    end)
end

local function HideInlineSwatch(color)
    color:Hide()
    if color._msuf2Title then
        color._msuf2Title:Hide()
        color._msuf2Title._msuf2AlwaysHidden = true
    end
end
--- The Setup Reset button: restores the container's factory record and
--- rebuilds the tools.
local function ResetButton(C, section, width, y, reason)
    local ctx, unit, index, Apply = C.ctx, C.unit, C.index, C.Apply
    local reset = ActionButton(section, "Reset", width)
    reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, y)
    reset:SetScript("OnClick", function()
        Model.ResetCustomContainer(unit, index)
        Apply(reason, true)
        Rebuild(ctx)
    end)
    RegisterAuraControl(ctx, reset, "Reset", "button", C.customActionPath .. ".setup.reset", "action", {
        actionKey = "reset_aura_custom_container", actionFixedArgs = { scope = unit, index = index },
    })
    return reset
end

-- Lexical collaborators shared by the responsibility modules below this load site.
M.CustomAuraWorkspaceParts = {
    HideInlineSwatch = HideInlineSwatch,
    ResetButton = ResetButton,
    PixelLayoutRegion = PixelLayoutRegion,
    W = W,
    T = T,
    A3 = A3,
    Model = Model,
    AurasPage = AurasPage,
    CreateFrame = CreateFrame,
    floor = floor,
    ceil = ceil,
    max = max,
    min = min,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    BindSwitch = BindSwitch,
    BindSlider = BindSlider,
    BindDropdown = BindDropdown,
    BindTextInput = BindTextInput,
    AURA_COOLDOWN_COLOR_REFERENCES = AURA_COOLDOWN_COLOR_REFERENCES,
    AURA_SORT_DIRECTION_VALUES = AURA_SORT_DIRECTION_VALUES,
    ActionButton = ActionButton,
    AddAuraTooltipHelp = AddAuraTooltipHelp,
    AddTooltip = AddTooltip,
    AnchorLabel = AnchorLabel,
    AuraCatalogToken = AuraCatalogToken,
    AuraControlMeta = AuraControlMeta,
    AuraControlMetaAtVisiblePath = AuraControlMetaAtVisiblePath,
    AuraSortMethodValues = AuraSortMethodValues,
    FilterSpellEntries = FilterSpellEntries,
    COOLDOWN_SWIPE_DIRECTION_VALUES = COOLDOWN_SWIPE_DIRECTION_VALUES,
    CUSTOM_FRAME_EFFECTS = CUSTOM_FRAME_EFFECTS,
    ChoiceLabel = ChoiceLabel,
    ConfigureMaxDurationSlider = ConfigureMaxDurationSlider,
    DEBUFF_TYPE_BORDER_MODE_VALUES = DEBUFF_TYPE_BORDER_MODE_VALUES,
    DURATION_BAR_DIRECTION_VALUES = DURATION_BAR_DIRECTION_VALUES,
    DURATION_BAR_DISPLAY_VALUES = DURATION_BAR_DISPLAY_VALUES,
    DURATION_BAR_POSITION_VALUES = DURATION_BAR_POSITION_VALUES,
    MatchSuffix = MatchSuffix,
    NATIVE_EXACT_AURA_FILTERS_TEXT = NATIVE_EXACT_AURA_FILTERS_TEXT,
    NormalizeAuraSortMethodForLane = NormalizeAuraSortMethodForLane,
    QueueAurasPageRefresh = QueueAurasPageRefresh,
    Rebuild = Rebuild,
    Repaint = Repaint,
    RegisterAuraControl = RegisterAuraControl,
    RegisterAuraTextAction = RegisterAuraTextAction,
    Round = Round,
    Tr = Tr,
    CustomStyleSectionId = CustomStyleSectionId,
    CUSTOM_AURA_TYPES = CUSTOM_AURA_TYPES,
    REMINDERS_AVAILABLE = REMINDERS_AVAILABLE,
    CLASSIC_REMINDER_NOTICE = CLASSIC_REMINDER_NOTICE,
    CUSTOM_DISPLAY_MODES = CUSTOM_DISPLAY_MODES,
    TRANSLATED_TITLE = TRANSLATED_TITLE,
    ContainerTitle = ContainerTitle,
    BindListSearch = BindListSearch,
    BindInputAction = BindInputAction,
    AddSpellRoute = AddSpellRoute,
    ListScroll = ListScroll,
    RowAction = RowAction,
    RowPriorityDrag = RowPriorityDrag,
}

--- Compact, task-focused Custom Aura editor used inside UnitFrame > Auras.
--- Only one tool is rendered at a time; all values still write to the same
--- native Custom Container record consumed by runtime and previews.
function M.BuildAuras3CompactCustomWorkspace(ctx, b, unit, index, tool)
    index = max(1, min(type(Model.CustomContainerMax) == "function" and Model.CustomContainerMax() or 3, tonumber(index) or 1))
    -- The selected Custom Aura index is part of an action's executable
    -- identity.  Reusing one path for Custom 1/2/3 made the generated schema
    -- collapse three different fixed argument contracts into one action.
    local customActionPath = "custom-container.custom" .. tostring(index)
    local isPlayerDefensives = unit == "player" and index == 4
    local isTargetDots = unit ~= "player" and index == 4
    local containerLabel = isPlayerDefensives and "Defensive Buffs"
        or (isTargetDots and "Dots on target" or ("Custom " .. tostring(index)))
    local item = Model.CustomContainer(unit, index, true)
    if not item then return end
    item.filters = type(item.filters) == "table" and item.filters or {}
    item.placed = type(item.placed) == "table" and item.placed or {}
    item.frame = type(item.frame) == "table" and item.frame or { type = "none", color = { 0.69, 0.50, 0.88, 0.8 }, priority = 5, thickness = 2, layer = 0,
        strata = "AUTO" }
    if type(item.frame.color) ~= "table" then item.frame.color = { 0.69, 0.50, 0.88, 0.8 } end
    local styleItem = item
    local function Apply(reason, rebuild)
        ApplyUnit(ctx, unit, reason or "AURAS3_CUSTOM_CONTAINER", rebuild == true)
        if type(ctx._auraAppearancePreviewRefresh) == "function" then ctx._auraAppearancePreviewRefresh() end
    end
    local function Grid(w, count, gap)
        gap = gap or 10
        return floor(((w - 48) - gap * (count - 1)) / count), gap
    end
    local C = {
        ctx = ctx, b = b, unit = unit, index = index, tool = tool,
        customActionPath = customActionPath, isPlayerDefensives = isPlayerDefensives,
        isTargetDots = isTargetDots, containerLabel = containerLabel,
        item = item, styleItem = styleItem, Apply = Apply, Grid = Grid,
    }

    -- Every UnitFrame-local Custom Aura exposes the same rich styling
    -- accordions, tailored to its aura type. Dots additionally expose Pandemic;
    -- all containers retain their Full-Frame effect controls.
    if tool == "style" then
        M.BuildAuras3CompactCustomWorkspace(ctx, b, unit, index, "appearance")
        M.BuildAuras3CompactCustomWorkspace(ctx, b, unit, index, "effect")
        return
    end

    if M.CustomAuraWorkspaceParts.BuildCustomDefensivesTool(C) then return end
    if M.CustomAuraWorkspaceParts.BuildCustomDotsTool(C) then return end
    if M.CustomAuraWorkspaceParts.BuildCustomWhitelistTool(C) then return end
    if M.CustomAuraWorkspaceParts.BuildCustomFiltersTool(C) then return end
    if M.CustomAuraWorkspaceParts.BuildCustomLayoutTool(C) then return end
    if M.CustomAuraWorkspaceParts.BuildCustomAppearanceTool(C) then return end
    if M.CustomAuraWorkspaceParts.BuildCustomEffectTool(C) then return end
    if M.CustomAuraWorkspaceParts.BuildCustomBehaviorTool(C) then return end
    if M.CustomAuraWorkspaceParts.BuildCustomDefensivesSetup(C) then return end
    if M.CustomAuraWorkspaceParts.BuildCustomDotsSetup(C) then return end
    M.CustomAuraWorkspaceParts.BuildCustomContainerSetup(C)
end
