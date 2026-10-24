-- Guided tour page surfaces, control discovery and emphasis.
local _, MSUF = ...
local Parts = MSUF.GuidedTourParts
local ControlIsAction = Parts.ControlIsAction
local CreateFrame = Parts.CreateFrame
local CurrentStage = Parts.CurrentStage
local EffectiveStageControlLimit = Parts.EffectiveStageControlLimit
local Invoke = Parts.Invoke
local M = Parts.M
local PixelLayoutRegion = Parts.PixelLayoutRegion
local RefreshEditModePlacementCue = Parts.RefreshEditModePlacementCue
local Runtime = Parts.Runtime
local StageIncludesSection = Parts.StageIncludesSection
local Tour = Parts.Tour
local TourIsActive = Parts.TourIsActive
local Tr = Parts.Tr
local max = Parts.max
local sort = Parts.sort
-- Texture helpers shared by the cues, the emphasis markers and the chrome.
local Gfx = {}

--- A right-pointing arrow texture: the NPE atlas where the client has it,
--- otherwise the theme's collapse arrow.
function Gfx.Arrow(T, parent, subLevel, size)
    local texture = PixelLayoutRegion(parent:CreateTexture(nil, "OVERLAY", nil, subLevel))
    if texture.SetAtlas then
        texture:SetAtlas("NPE_ArrowRight", false)
    elseif T.media then
        texture:SetTexture(T.media.collapseArrow)
    end
    texture:SetSize(size, size)
    return texture
end

--- Paints a navigation-atlas icon (or the logo when the atlas is missing) in the icon's own color.
function Gfx.NavIcon(icon, T, iconKey)
    M.Widgets.PaintNavigationTexture(icon, T, iconKey)
    local color = T.navIconColors and T.navIconColors[iconKey] or T.colors.accent
    if color then icon:SetVertexColor(color[1], color[2], color[3], 1) end
end

function Gfx.StopAndHide(marker)
    if not marker then return end
    if M.Theme and type(M.Theme.StopMotion) == "function" then M.Theme.StopMotion(marker) end
    marker:Hide()
end

-- Corner pair and sized axis of the four outline edges: top, right, bottom, left.
Gfx.OUTLINE_EDGES = {
    { "TOPLEFT", "TOPRIGHT", "SetHeight" },
    { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
    { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
    { "TOPLEFT", "BOTTOMLEFT", "SetWidth" },
}

local function RefreshEditModeOpenCue(show)
    local T = M.Theme
    local button = M.dashboardToolbarEditModeButton
    local cue = Runtime.editModeOpenCue
    show = show == true and button ~= nil and T ~= nil
    if not show then
        if cue then cue:Hide() end
        Runtime.editModeOpenCueVisible = nil
        return
    end
    if not cue or cue:GetParent() ~= button then
        if cue then cue:Hide() end
        cue = PixelLayoutRegion(CreateFrame("Frame", nil, button))
        cue:SetAllPoints(button)
        cue:EnableMouse(false)
        cue:SetFrameLevel((button:GetFrameLevel() or 1) + 12)
        local color = T.colors.ok or { 0.24, 0.82, 0.46, 1 }
        local function Arrow(point, rotation)
            local texture = Gfx.Arrow(T, cue, 7, 20)
            texture:SetPoint(point, cue, point, point == "LEFT" and 3 or -3, 0)
            if rotation and texture.SetRotation then texture:SetRotation(rotation) end
            texture:SetVertexColor(color[1], color[2], color[3], 1)
            return texture
        end
        cue._leftArrow = Arrow("LEFT")
        cue._rightArrow = Arrow("RIGHT", math.pi)
        Runtime.editModeOpenCue = cue
    end
    cue:Show()
    if not Runtime.editModeOpenCueVisible then
        Runtime.editModeOpenCueVisible = true
        if type(T.PlayMotion) == "function" then
            T.PlayMotion(cue, "controlFocusIn", { fromAlpha = 0.30, toAlpha = 1, duration = 0.18 })
        end
        if type(T.PlayNeonFlash) == "function" then
            T.PlayNeonFlash(button, "success", { alpha = 0.28, duration = 0.80 })
        end
    end
end

-- Records an Edit Mode milestone with the tour, then repaints the cue, the page and the chrome.
local function NotifyEditModeMilestone(method, moverKey, refreshReason, chromeReason)
    local ok, marked = Invoke(Tour(), method, moverKey)
    if not ok or marked ~= true then return false end
    RefreshEditModePlacementCue()
    if M.activeKey == "guided_setup" then
        M.RequestRefresh(nil, refreshReason)
    end
    if type(M.RefreshGuidedTourChrome) == "function" then
        M.RefreshGuidedTourChrome(chromeReason)
    end
    return true
end

function M.NotifyGuidedEditModeMoved(moverKey)
    return NotifyEditModeMilestone("MarkEditModePlacementComplete", moverKey, "GUIDED_EDIT_MODE_MOVED", "EDIT_MODE_MOVED")
end

function M.NotifyGuidedEditModePopupOpened(moverKey)
    return NotifyEditModeMilestone("MarkEditModePopupOpened", moverKey, "GUIDED_EDIT_MODE_POPUP_OPENED", "EDIT_MODE_POPUP_OPENED")
end

local function LiveEditModePopupKey()
    local editMode = MSUF.EditModeController
    local popups = editMode and editMode.Popups
    if not (popups and type(popups.IsAnyOpen) == "function" and popups.IsAnyOpen()) then return nil end
    local focus = editMode.Focus
    local key = focus and type(focus.GetSelection) == "function" and focus.GetSelection() or nil
    if not key then
        local state = editMode.State
        key = state and type(state.GetUnitKey) == "function" and state.GetUnitKey() or nil
    end
    return tostring(key or "")
end

local function ReconcileGuidedEditModePopup(stage)
    if not TourIsActive() then return false end
    stage = stage or CurrentStage()
    local key = LiveEditModePopupKey()
    if key == "" then return false end
    if stage.id == "group_edit_mode" then
        if key ~= "gf_party" and key ~= "party" then return false end
    elseif stage.id == "edit_mode" then
        if key ~= "player" then return false end
    else
        return false
    end
    local ok, accepted, changed = Invoke(Tour(), "MarkEditModePopupOpened", key)
    return ok and accepted == true and changed == true
end
M.ReconcileGuidedEditModePopup = ReconcileGuidedEditModePopup

local function OpenGuidedEditModePopup(key, stage)
    local editMode = MSUF.EditModeController
    local popups = editMode and editMode.Popups
    if not (popups and type(popups.Open) == "function") then return false end
    local mover = editMode.Movers and type(editMode.Movers.Get) == "function" and editMode.Movers.Get(key) or nil
    local opened = popups.Open(key, mover)
    if opened ~= true and type(popups.IsAnyOpen) == "function" then opened = popups.IsAnyOpen() == true end
    if not opened then return false end
    ReconcileGuidedEditModePopup(stage)
    return true
end

local function ExpectedPage(stage)
    stage = stage or CurrentStage()
    return stage.special and "guided_setup" or stage.pageKey
end

local function SafeText(fontString)
    if type(fontString) == "string" then return fontString end
    if not (fontString and type(fontString.GetText) == "function") then return "" end
    local value = tostring(fontString:GetText() or "")
    return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

-- A frame's GetTop or GetLeft as a number, or nil while it has no rect yet.
local function FrameEdge(frame, getter)
    if not (frame and type(frame[getter]) == "function") then return nil end
    return tonumber(frame[getter](frame)) or nil
end

local IsWidgetInside

local function RefreshCachedSectionDescriptors(cached)
    local sections = cached and cached.sections
    if type(sections) ~= "table" then return false end
    for i = 1, #sections do
        local section = sections[i]
        local entry = section.entry
        if type(entry) ~= "table" or tonumber(entry.guidedOrder) ~= section.guidedOrder then return false end
        if section.region then
            local body = entry.body or entry.outer
            local outer = entry.outer or body
            if body ~= section.body or outer ~= section.outer then return false end
            local label = SafeText(entry.label)
            if label == "" then label = SafeText(body and body.title) end
            section.label = label ~= "" and label or "Scope and overrides"
        else
            if entry.body ~= section.body or entry.outer ~= section.outer then return false end
            local label = SafeText(entry.label)
            section.label = label ~= "" and label or tostring(section.id or "Section")
        end
    end
    return true
end

-- Appends a section record and reports whether its guidedOrder is set and unique.
local function AppendSection(sections, orders, section)
    sections[#sections + 1] = section
    local order = section.guidedOrder
    if order == nil or orders[order] then return false end
    orders[order] = true
    return true
end

local function SortedSections(pageKey)
    local entry = M.cache and M.cache[pageKey]
    local source = entry and entry.sections
    local regions = entry and entry.guidedRegions
    local cached = entry and entry._msuf2GuidedSortedSections
    if cached and cached.source == source and cached.regions == regions
        and RefreshCachedSectionDescriptors(cached)
    then
        return cached.sections
    end
    if entry then entry._msuf2GuidedSortedSections = nil end
    local sections = {}
    local orders = {}
    local stableOrder = true
    if type(source) == "table" then
        for sectionId, body in pairs(source) do
            local collapsible = body and body._msuf2CollapsibleEntry
            if collapsible then
                local label = SafeText(collapsible.label)
                if label == "" then label = tostring(sectionId or "Section") end
                stableOrder = AppendSection(sections, orders, {
                    id = tostring(sectionId or ""),
                    body = body,
                    outer = collapsible.outer,
                    entry = collapsible,
                    label = label,
                    guidedOrder = tonumber(collapsible.guidedOrder),
                    collapsible = true,
                }) and stableOrder
            end
        end
    end
    if type(regions) == "table" then
        for regionId, region in pairs(regions) do
            local body = type(region) == "table" and (region.body or region.outer) or nil
            local outer = type(region) == "table" and (region.outer or body) or nil
            if body and outer then
                local label = SafeText(region.label)
                if label == "" then label = SafeText(body.title) end
                if label == "" then label = "Scope and overrides" end
                stableOrder = AppendSection(sections, orders, {
                    id = "region:" .. tostring(region.id or regionId or ""),
                    body = body,
                    outer = outer,
                    entry = region,
                    label = label,
                    guidedOrder = tonumber(region.guidedOrder),
                    region = true,
                }) and stableOrder
            end
        end
    end
    if not stableOrder then
        for i = 1, #sections do sections[i].top = FrameEdge(sections[i].outer, "GetTop") end
    end
    sort(sections, function(a, b)
        if a.guidedOrder ~= b.guidedOrder then
            if a.guidedOrder == nil then return false end
            if b.guidedOrder == nil then return true end
            return a.guidedOrder < b.guidedOrder
        end
        if a.top ~= b.top then
            if a.top == nil then return false end
            if b.top == nil then return true end
            return a.top > b.top
        end
        return a.id < b.id
    end)
    if entry and stableOrder then
        entry._msuf2GuidedSortedSections = { source = source, regions = regions, sections = sections }
    end
    return sections
end

function M.RegisterGuidedCopyPopup(kind, pageKey, ensureVisible)
    kind, pageKey = tostring(kind or ""), tostring(pageKey or "")
    if kind == "" or pageKey == "" or type(ensureVisible) ~= "function" then return false end
    Runtime.copyPopupOpeners = Runtime.copyPopupOpeners or {}
    Runtime.copyPopupOpeners[kind] = Runtime.copyPopupOpeners[kind] or {}
    Runtime.copyPopupOpeners[kind][pageKey] = ensureVisible
    return true
end

-- The cached page section a stage prepares (tab and slot selection live on it).
local function PreparedSection(stage)
    local pageEntry = M.cache and M.cache[stage.pageKey]
    return pageEntry and pageEntry.sections and pageEntry.sections[stage.prepareSection]
end

local function EnsureStageSurface(stage)
    if type(stage) == "table" and stage.area == "groupframes" and stage.special ~= true and M.gfScope ~= "party" then
        local pageEntry = M.cache and M.cache[stage.pageKey]
        local scopeRegion = pageEntry and pageEntry.guidedRegions and pageEntry.guidedRegions.group_scope
        local selectScope = scopeRegion and scopeRegion.body and scopeRegion.body._msuf2GuidedSelectScope
        if not (type(selectScope) == "function" and selectScope("party") ~= false) then
            if type(M.SetMenuStateValue) == "function" then M.SetMenuStateValue("gfScope", "party") else M.gfScope = "party" end
        end
    end
    if type(stage) == "table" and stage.prepareSection and stage.prepareTab and stage.prepareState then
        local section = PreparedSection(stage)
        local selectTab = section and section._msuf2GuidedSelectTab
        if not (type(selectTab) == "function" and selectTab(stage.prepareTab) ~= false) then
            local state = M[stage.prepareState]
            if type(state) ~= "table" then
                state = {}
                M[stage.prepareState] = state
            end
            state[stage.prepareStateIndex or "player"] = stage.prepareTab
        end
    end
    if type(stage) == "table" and stage.prepareSection and stage.prepareTab and stage.prepareSlot and stage.prepareSlotState then
        local section = PreparedSection(stage)
        local selectSlot = section and section._msuf2GuidedSelectSlot
        if not (type(selectSlot) == "function" and selectSlot(stage.prepareTab, stage.prepareSlot) ~= false) then
            local state = M[stage.prepareSlotState]
            if type(state) ~= "table" then
                state = {}
                M[stage.prepareSlotState] = state
            end
            local index = stage.prepareStateIndex or "player"
            if type(state[index]) ~= "table" then state[index] = {} end
            state[index][stage.prepareTab] = stage.prepareSlot
        end
    end
    local kind = stage and stage.ensureCopyPopup
    if not kind then return true end
    if tostring(Runtime.touchedSignature or ""):match("^" .. tostring(stage.id or "") .. "\031") then return true end
    local byKind = Runtime.copyPopupOpeners and Runtime.copyPopupOpeners[kind]
    local ensureVisible = byKind and byKind[stage.pageKey]
    if type(ensureVisible) ~= "function" then return false end
    local visible = ensureVisible()
    return visible ~= false
end

local function StageSections(stage)
    EnsureStageSurface(stage)
    local sections = SortedSections(stage and stage.pageKey)
    if type(stage) ~= "table" then return sections end
    local function Filter(source)
        local filtered = {}
        for i = 1, #source do
            local section = source[i]
            if StageIncludesSection(stage, section.id) then filtered[#filtered + 1] = section end
        end
        return filtered
    end
    local filtered = Filter(sections)
    local W = M.Widgets
    local materialized
    if W and type(W.FocusCollapsibleSection) == "function" then
        for i = 1, #filtered do
            local section = filtered[i]
            if section.collapsible and section.entry and section.entry.open ~= true then
                W.FocusCollapsibleSection(section.body, { persist = false, flash = false, scroll = false })
                materialized = true
            end
        end
    end
    if materialized then filtered = Filter(SortedSections(stage.pageKey)) end
    return filtered
end

local function ClearControlEmphasis()
    Runtime.controlEmphasisSignature = nil
    Runtime.controlEmphasisWidget = nil
    local emphasized = Runtime.controlEmphasis
    if type(emphasized) ~= "table" then return end
    for i = 1, #emphasized do
        local item = emphasized[i]
        local widget = item and item.widget
        if widget and type(widget.SetAlpha) == "function" and item.originalAlpha ~= nil then
            local current = type(widget.GetAlpha) == "function" and widget:GetAlpha() or item.appliedAlpha
            if current == nil or item.appliedAlpha == nil or math.abs(current - item.appliedAlpha) < 0.001 then
                widget:SetAlpha(item.originalAlpha)
            end
        end
        local marker = item and item.marker
        if marker then
            if M.Theme and type(M.Theme.StopMotion) == "function" then M.Theme.StopMotion(marker) end
            if type(marker.Hide) == "function" then marker:Hide() end
        end
    end
    Runtime.controlEmphasis = nil
end

local function ClearSectionEmphasis(pageKey)
    Runtime.emphasisSignature = nil
    ClearControlEmphasis()
    local cache = M.cache
    if type(cache) ~= "table" then return end
    for key in pairs(cache) do
        if pageKey == nil or key == pageKey then
            local sections = SortedSections(key)
            for i = 1, #sections do
                local section = sections[i]
                local outer = section.outer
                if outer and outer.SetAlpha and outer._msuf2GuidedOriginalAlpha ~= nil then
                    outer:SetAlpha(outer._msuf2GuidedOriginalAlpha)
                    outer._msuf2GuidedOriginalAlpha = nil
                end
                local flash = outer and outer._msuf2NeonFlash
                if flash then
                    if flash._msuf2FlashGroup and flash._msuf2FlashGroup.Stop then flash._msuf2FlashGroup:Stop() end
                    if flash.SetAlpha then flash:SetAlpha(0) end
                    if flash.Hide then flash:Hide() end
                end
                Gfx.StopAndHide(section.entry and section.entry._msuf2GuidedArrow)
                Gfx.StopAndHide(section.entry and section.entry._msuf2GuidedControlArrow)
            end
        end
    end
end

local function EmphasizeSection(pageKey, current, currentControl)
    local T = M.Theme
    local sections = SortedSections(pageKey)
    local signature = tostring(pageKey or "") .. "\031" .. tostring(current and current.id or "")
    local animate = Runtime.emphasisSignature ~= signature
    Runtime.emphasisSignature = signature
    for i = 1, #sections do
        local section = sections[i]
        local entry = section.entry
        local selected = current and section.id == current.id
        local outer = section.outer
        if outer and outer.SetAlpha and outer._msuf2GuidedOriginalAlpha ~= nil then
            -- Older tour builds dimmed every non-current section. Restore that
            -- state once and keep the whole page readable and interactive.
            outer:SetAlpha(outer._msuf2GuidedOriginalAlpha)
            outer._msuf2GuidedOriginalAlpha = nil
        end
        local marker = entry._msuf2GuidedArrow
        if selected and not marker and outer and outer.CreateTexture and T and T.media then
            marker = Gfx.Arrow(T, outer, 7, 20)
            marker:SetPoint("RIGHT", outer, "LEFT", -4, 0)
            local color = T.colors.accent
            marker:SetVertexColor(color[1], color[2], color[3], 1)
            entry._msuf2GuidedArrow = marker
        end
        if marker then
            local showMarker = selected and not currentControl
            marker:SetShown(showMarker and true or false)
            if showMarker and animate and T and type(T.PlayMotion) == "function" then
                T.PlayMotion(marker, "controlFocusIn", { fromAlpha = 0.28, toAlpha = 1, duration = 0.16 })
            end
        end
    end
end

IsWidgetInside = function(widget, ancestor)
    local current = widget
    for _ = 1, 48 do
        if not current then return false end
        if current == ancestor then return true end
        if type(current.GetParent) ~= "function" then return false end
        local parent = current:GetParent()
        if parent == current then return false end
        current = parent
    end
    return false
end

local function RuntimeControlRecords()
    local catalog = M.RuntimeControlCatalog
    if not (catalog and type(catalog.GetRecords) == "function") then return {} end
    local records = catalog.GetRecords()
    return type(records) == "table" and records or {}
end

local function GuidedWidgetIsActionable(widget)
    if not widget or widget._msuf2AppliedEnabled == false or widget._msuf2DesiredEnabled == false then return false end
    local function ObjectEnabled(object)
        if not object or type(object.IsEnabled) ~= "function" then return true end
        local enabled = object:IsEnabled()
        return enabled ~= false and enabled ~= 0
    end
    if not ObjectEnabled(widget) then return false end
    if type(widget.buttons) == "table" and #widget.buttons > 0 then
        for i = 1, #widget.buttons do
            local button = widget.buttons[i]
            if button
                and button._msuf2AppliedEnabled ~= false
                and button._msuf2DesiredEnabled ~= false
                and ObjectEnabled(button)
            then
                return true
            end
        end
        return false
    end
    return true
end

local function GuidedDisplayLabel(value)
    value = tostring(value or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil end
    -- Semantic identities are excellent stable keys, but terrible UI copy.
    if value:find("/", 1, true) or value:match("^[%w_%-]+%.[%w_.%-]+$") then return nil end
    return value
end

local function HumanizeGuidedIdentity(record)
    local semantic = tostring(record and (record.controlPath or record.identityKey or record.settingKey or record.identityLabel) or "")
    local leaf = semantic:match("([^/%.]+)$") or semantic
    leaf = leaf:gsub("_", " "):gsub("%-", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local lower = leaf:lower()
    if lower == "enabled" then return Tr("Enable") end
    if lower == "x" then return Tr("X position") end
    if lower == "y" then return Tr("Y position") end
    if lower == "selected aura" then return Tr("Spell") end
    if leaf == "" then return Tr("Setting") end
    return Tr(leaf:sub(1, 1):upper() .. leaf:sub(2))
end

local function GuidedControlLabel(record, widget)
    local label = GuidedDisplayLabel(widget and SafeText(widget._msuf2Title))
    if label then return label end
    label = GuidedDisplayLabel(widget and SafeText(widget._msuf2Label))
    if label then return label end
    label = GuidedDisplayLabel(record and record.label)
    if label then return label end
    label = GuidedDisplayLabel(widget and widget._msuf2SearchText)
    if label then return label end
    label = GuidedDisplayLabel(record and record.identityLabel)
    if label then return label end
    return HumanizeGuidedIdentity(record)
end

local function SectionControls(pageKey, section, sections, records, includeEphemeral, includeLocked, controlLimit, controlPaths)
    local catalog = M.RuntimeControlCatalog
    if not (catalog and section and section.body) then return {} end
    records = type(records) == "table" and records or RuntimeControlRecords()
    sections = type(sections) == "table" and sections or SortedSections(pageKey)
    local controls, seen = {}, {}
    for i = 1, #records do
        local record = records[i]
        if type(record) == "table"
            and record.pageKey == pageKey
            and (record.classification == "setting" or record.classification == "action"
                or (includeEphemeral == true and record.classification == "ephemeral"))
            and type(record.controlId) == "string"
            and not seen[record.controlId]
        then
            local internal = type(catalog.Get) == "function" and catalog.Get(record.controlId) or nil
            local widget = internal and internal.widget
            local shown = true
            if widget and type(widget.IsVisible) == "function" then
                shown = widget:IsVisible() == true
            elseif widget and type(widget.IsShown) == "function" then
                shown = widget:IsShown() == true
            end
            local actionable = GuidedWidgetIsActionable(widget)
            local owner = widget and shown and (actionable or includeLocked == true) and IsWidgetInside(widget, section.body) and section or nil
            if owner then
                for j = 1, #sections do
                    local candidate = sections[j]
                    if candidate ~= owner
                        and candidate.body ~= owner.body
                        and IsWidgetInside(widget, candidate.body)
                        and IsWidgetInside(candidate.body, owner.body)
                    then
                        owner = candidate
                    end
                end
            end
            if owner == section then
                seen[record.controlId] = true
                controls[#controls + 1] = {
                    id = record.controlId,
                    label = GuidedControlLabel(record, widget),
                    help = tostring(record.help or ""),
                    kind = tostring(record.kind or ""),
                    classification = tostring(record.classification or ""),
                    controlPath = tostring(record.controlPath or ""),
                    settingKey = tostring(record.settingKey or ""),
                    widget = widget,
                    actionable = actionable,
                    top = FrameEdge(widget, "GetTop"),
                    left = FrameEdge(widget, "GetLeft"),
                }
            end
        end
    end
    sort(controls, function(a, b)
        if a.top ~= b.top then
            if a.top == nil then return false end
            if b.top == nil then return true end
            if math.abs(a.top - b.top) > 2 then return a.top > b.top end
        end
        if a.left ~= b.left then
            if a.left == nil then return false end
            if b.left == nil then return true end
            if math.abs(a.left - b.left) > 2 then return a.left < b.left end
        end
        local al, bl = a.label:lower(), b.label:lower()
        return al == bl and a.id < b.id or al < bl
    end)
    if type(controlPaths) == "table" and #controlPaths > 0 then
        local byPath, selected, selectedIds = {}, {}, {}
        for i = 1, #controls do
            local path = controls[i].controlPath
            if path ~= "" and byPath[path] == nil then byPath[path] = controls[i] end
        end
        for i = 1, #controlPaths do
            local control = byPath[controlPaths[i]]
            if control and not selectedIds[control.id] then
                selectedIds[control.id] = true
                selected[#selected + 1] = control
            end
        end
        -- Keep the tour resilient if a curated control is unavailable in a
        -- future build: fill the remaining slots with the next visible setting.
        for i = 1, #controls do
            local control = controls[i]
            if not selectedIds[control.id] then
                selectedIds[control.id] = true
                selected[#selected + 1] = control
            end
        end
        controls = selected
    end
    controlLimit = max(0, tonumber(controlLimit) or 0)
    if controlLimit > 0 then
        for i = #controls, controlLimit + 1, -1 do controls[i] = nil end
    end
    return controls
end

-- SectionControls with the control filters the stage declares.
local function StageSectionControls(stage, section, sections, records)
    return SectionControls(stage.pageKey, section, sections, records, stage.includeEphemeralControls, stage.includeLockedControls,
        EffectiveStageControlLimit(stage), stage.controlPaths)
end

local function AllStageControls(stage)
    local sections = StageSections(stage)
    local records = RuntimeControlRecords()
    local controls, seen = {}, {}
    for i = 1, #sections do
        local list = StageSectionControls(stage, sections[i], sections, records)
        for j = 1, #list do
            local control = list[j]
            if not seen[control.id] then
                seen[control.id] = true
                controls[#controls + 1] = control
            end
        end
    end
    return controls
end

local function EmphasizeControl(stage, section, controls, current)
    if not (stage and section and current and current.widget) then
        ClearControlEmphasis()
        return
    end
    local signature = table.concat({ stage.id or "", section.id or "", current.id or "" }, "\031")
    if Runtime.controlEmphasisSignature == signature
        and Runtime.controlEmphasisWidget == current.widget
        and type(Runtime.controlEmphasis) == "table"
    then
        return
    end
    ClearControlEmphasis()
    Runtime.controlEmphasisSignature = signature
    Runtime.controlEmphasisWidget = current.widget
    Runtime.controlEmphasis = {}

    local selectedWidget = current.widget
    local T = M.Theme
    if type(CreateFrame) == "function" and T then
        local marker = Runtime.controlMarker
        if marker and marker._msuf2DualPointer ~= true then
            marker:Hide()
            marker = nil
        end
        if not marker then
            marker = PixelLayoutRegion(CreateFrame("Frame", nil, selectedWidget))
            marker._msuf2DualPointer = true
            if type(marker.EnableMouse) == "function" then marker:EnableMouse(false) end
            local function Arrow(rotation)
                local texture = Gfx.Arrow(T, marker, 7, 20)
                if rotation and type(texture.SetRotation) == "function" then texture:SetRotation(rotation) end
                return texture
            end
            marker._msuf2LeftArrow = Arrow()
            marker._msuf2RightArrow = Arrow(math.pi)
            marker._msuf2Edges = {}
            for i = 1, 4 do marker._msuf2Edges[i] = PixelLayoutRegion(marker:CreateTexture(nil, "OVERLAY", nil, 6)) end
            Runtime.controlMarker = marker
        else
            marker:SetParent(selectedWidget)
        end
        marker:ClearAllPoints()
        marker:SetPoint("TOPLEFT", selectedWidget, "TOPLEFT", -5, 5)
        marker:SetPoint("BOTTOMRIGHT", selectedWidget, "BOTTOMRIGHT", 5, -5)
        if type(marker.SetFrameLevel) == "function" and type(selectedWidget.GetFrameLevel) == "function" then
            marker:SetFrameLevel(selectedWidget:GetFrameLevel() + 8)
        end
        local color = (T.colors and T.colors.ok) or { 0.24, 0.88, 0.40, 1 }
        local leftArrow, rightArrow = marker._msuf2LeftArrow, marker._msuf2RightArrow
        leftArrow:ClearAllPoints()
        leftArrow:SetPoint("RIGHT", marker, "LEFT", -4, 0)
        rightArrow:ClearAllPoints()
        rightArrow:SetPoint("LEFT", marker, "RIGHT", 4, 0)
        leftArrow:SetVertexColor(color[1], color[2], color[3], 1)
        rightArrow:SetVertexColor(color[1], color[2], color[3], 1)
        for i = 1, 4 do
            local edge, spec = marker._msuf2Edges[i], Gfx.OUTLINE_EDGES[i]
            edge:ClearAllPoints()
            edge:SetPoint(spec[1])
            edge:SetPoint(spec[2])
            edge[spec[3]](edge, 2)
            edge:SetColorTexture(color[1], color[2], color[3], 0.92)
        end
        marker:Show()
        Runtime.controlEmphasis[#Runtime.controlEmphasis + 1] = { marker = marker }
        if type(T.PlayMotion) == "function" then
            T.PlayMotion(marker, "controlFocusIn", { fromAlpha = 0.28, toAlpha = 1, duration = 0.16 })
        end
    end
    if T and type(T.PlayNeonFlash) == "function" and type(selectedWidget.CreateTexture) == "function" then
        T.PlayNeonFlash(selectedWidget, "success", { alpha = 0.24, duration = 0.72 })
    end
    if ControlIsAction(current) then
        local function HookActionTarget(target)
            if not (target and type(target.HookScript) == "function") then return end
            target._msuf2GuidedActionHooks = target._msuf2GuidedActionHooks or {}
            if target._msuf2GuidedActionHooks[current.id] then return end
            target._msuf2GuidedActionHooks[current.id] = true
            target:HookScript("OnClick", function()
                if type(M.NotifyGuidedTourControlInteraction) == "function" then
                    M.NotifyGuidedTourControlInteraction(selectedWidget)
                end
            end)
        end
        HookActionTarget(selectedWidget)
        for i = 1, type(selectedWidget.buttons) == "table" and #selectedWidget.buttons or 0 do
            HookActionTarget(selectedWidget.buttons[i])
        end
    end
end


Parts.AllStageControls = AllStageControls
Parts.ClearSectionEmphasis = ClearSectionEmphasis
Parts.EmphasizeControl = EmphasizeControl
Parts.EmphasizeSection = EmphasizeSection
Parts.ExpectedPage = ExpectedPage
Parts.Gfx = Gfx
Parts.IsWidgetInside = IsWidgetInside
Parts.OpenGuidedEditModePopup = OpenGuidedEditModePopup
Parts.ReconcileGuidedEditModePopup = ReconcileGuidedEditModePopup
Parts.RefreshEditModeOpenCue = RefreshEditModeOpenCue
Parts.RuntimeControlRecords = RuntimeControlRecords
Parts.StageSectionControls = StageSectionControls
Parts.StageSections = StageSections
