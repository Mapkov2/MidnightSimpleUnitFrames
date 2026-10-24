local _, MSUF = ...
local M = MSUF.MSUF2
local H = M.PreviewHelpers
local FILE = "Shell/Menu2/MSUF_Menu2_Preview_Dock.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local Fallbacks, floor, min = M.Fallbacks, math.floor, math.min
local shared = H._Shared
local ThemedFont, FlatBackdrop = shared.ThemedFont, shared.FlatBackdrop
local SetShownText, PREVIEW_CHROME_FALLBACK = shared.SetShownText, shared.PREVIEW_CHROME_FALLBACK

local LAYER_BUTTON_FALLBACK_COLOR = { 1, 1, 1 }
local LAYER_BUTTON_SELECTED_BG = { 0.08, 0.34, 0.72, 0.88 }
local function LayerButtonAvailable(owner, key)
    return not (owner and owner.layerAvailable and owner.layerAvailable[key] == false)
end
local function LayerButtonOn(owner, key)
    return LayerButtonAvailable(owner, key) and not (owner and owner.layerVisibility and owner.layerVisibility[key] == false)
end
local function LayerButtonAvailableFor(owner, key, opts)
    if opts and opts.IsAvailable then return opts.IsAvailable(owner, key) end
    return LayerButtonAvailable(owner, key)
end
local function LayerButtonOnFor(owner, key, opts)
    if opts and opts.IsOn then return opts.IsOn(owner, key) end
    return LayerButtonOn(owner, key)
end
local LAYER_CHIP_SELECTED_TEXT = { 0.96, 0.98, 1.00 }
local LAYER_CHIP_DIM_FILL = { 0.010, 0.018, 0.030 }
local layerChipOnFill = { 0, 0, 0 }
-- The tinted fill of an "on" chip: its layer color at 12 percent, in a scratch triple.
local function LayerChipOnFill(c)
    layerChipOnFill[1], layerChipOnFill[2], layerChipOnFill[3] = c[1] * 0.12, c[2] * 0.12, c[3] * 0.12
    return layerChipOnFill
end
-- Paints one chip state: the fill, the layer color bar, the label and (when given) the OFF tag.
local function PaintLayerChip(widgets, btn, c, fill, fillAlpha, barAlpha, text, textAlpha, off, offAlpha)
    widgets.SetLayerColor(btn, btn.bg, fill[1], fill[2], fill[3], fillAlpha)
    widgets.SetLayerColor(btn, btn.bar, c[1], c[2], c[3], barAlpha)
    btn.fs:SetTextColor(text[1], text[2], text[3], textAlpha)
    if btn.off and off then btn.off:SetTextColor(off[1], off[2], off[3], offAlpha) end
end
function H.RefreshLayerButton(btn, owner, opts)
    if not btn then return end
    opts = opts or {}
    local available = LayerButtonAvailableFor(owner, btn.key, opts)
    local on = LayerButtonOnFor(owner, btn.key, opts)
    local selected = opts.IsSelected and opts.IsSelected(owner, btn.key) == true
    MSUF.MenuSkin.TrackPaint(btn, H.RefreshLayerButton, owner, opts)
    local widgets = M.Widgets
    local hover = btn._msuf2LayerHovered == true
    local state = (on and 1 or 0) + (selected and 2 or 0) + (available and 4 or 0) + (hover and 8 or 0)
    local motion = widgets.BeginLayerMotion(btn, state, available)
    local c = btn.color or LAYER_BUTTON_FALLBACK_COLOR
    local textOn = opts.textOn or { 0.82, 0.88, 1.00, 0.98 }
    local textOff = opts.textOff or { 0.54, 0.61, 0.72, 0.78 }
    local textDisabled = opts.textDisabled or { 0.42, 0.48, 0.58, 0.62 }
    if btn.off then
        btn.off:SetText(opts.offText or "OFF")
        btn.off:SetShown((opts.showOffText == true) and ((not available) or not on))
    end
    local quiet = opts.quiet == true
    local quietBase = opts.quietBase or PREVIEW_CHROME_FALLBACK.rowBase
    local colors = (opts.T or M.Theme).colors
    local selectedBg = opts.selectedBg or colors.pillActive or LAYER_BUTTON_SELECTED_BG
    if MSUF.MenuSkin.IsActive() then
        quietBase = colors.coreSurface or colors.panel
        textOn, textOff, textDisabled = colors.text, colors.muted, colors.dim
        selectedBg = colors.pillActive
    end
    -- PaintLayerChip(fill, fill alpha, bar alpha, label color, label alpha, OFF tag color, OFF alpha)
    if hover and available and not on and not selected then
        local hoverColor = colors.coreRaised or opts.quietHover or PREVIEW_CHROME_FALLBACK.rowHover
        PaintLayerChip(widgets, btn, c, hoverColor, quiet and 0.42 or 0.58, quiet and 0.90 or 1, textOn, textOn[4] or 1)
    elseif not available and quiet then
        PaintLayerChip(widgets, btn, c, quietBase, 0.10, 0.20, textDisabled, textDisabled[4] or 0.62, textDisabled, 0.62)
    elseif selected and quiet then
        PaintLayerChip(widgets, btn, c, selectedBg, selectedBg[4] or 0.88, on and 1.00 or 0.38, LAYER_CHIP_SELECTED_TEXT, 1.00,
            textOff, on and 0 or 0.78)
    elseif on and quiet then
        PaintLayerChip(widgets, btn, c, LayerChipOnFill(c), 0.54, 0.94, textOn, textOn[4] or 0.96, textOff, 0.0)
    elseif quiet then
        PaintLayerChip(widgets, btn, c, quietBase, 0.08, 0.26, textOff, textOff[4] or 0.74, textOff, 0.72)
    elseif not available then
        PaintLayerChip(widgets, btn, c, LAYER_CHIP_DIM_FILL, 0.32, 0.30, textDisabled, textDisabled[4] or 0.62, textDisabled, 0.72)
    elseif selected then
        PaintLayerChip(widgets, btn, c, selectedBg, selectedBg[4] or 0.88, on and 1.00 or 0.42, LAYER_CHIP_SELECTED_TEXT, 1.00,
            textOff, on and 0 or 0.78)
    elseif on then
        PaintLayerChip(widgets, btn, c, LayerChipOnFill(c), 0.54, 0.94, textOn, textOn[4] or 0.98, textOff, 0.0)
    else
        PaintLayerChip(widgets, btn, c, LAYER_CHIP_DIM_FILL, 0.26, 0.42, textOff, textOff[4] or 0.78, textOff, 0.78)
    end
    widgets.FinishControlMotion(motion)
    btn._msuf2LayerPaintingMotion = nil
end
function H.RefreshSelectedLayerButtons(owner, selectedHandle, buttonsField)
    if not owner then return end
    local selectedKey = selectedHandle and selectedHandle._previewLayerKey or nil
    if owner._msuf2SelectedPreviewLayerKey == selectedKey then return end
    owner._msuf2SelectedPreviewLayerKey = selectedKey
    local buttons = owner[buttonsField or "layerButtons"] or {}
    for i = 1, #buttons do
        local button = buttons[i]
        if button and button.Refresh then button:Refresh()
        elseif button and button.refresh then button:refresh() end
    end
end
--- Chip rows measure themselves so a caller can flow them horizontally; the
--- docked row layout keeps its fixed column width.
local function LayoutLayerChip(btn, h)
    btn.bar:SetSize(7, 7)
    btn.bar:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.fs:ClearAllPoints()
    btn.fs:SetPoint("LEFT", btn.bar, "RIGHT", 6, 0)
    btn.fs:SetJustifyH("LEFT")
    local textWidth = btn.fs.GetStringWidth and btn.fs:GetStringWidth() or 0
    if not textWidth or textWidth <= 0 then textWidth = #tostring(btn.fs:GetText() or btn.key or "") * 6 end
    btn:SetSize(floor(textWidth + 0.5) + 30, h)
end
function H.CreateLayerButton(parent, owner, def, index, sideW, opts)
    if not (parent and def) then return nil end
    opts = opts or {}
    local tr = opts.Tr or Fallbacks.Identity
    local theme = opts.T or (M.Theme)
    local chip = opts.layout == "chip"
    local btn = PixelLayoutRegion(CreateFrame("Button", nil, parent))
    local h = opts.height or 20
    if not chip then
        btn:SetSize((sideW or 80) - 12, h)
        btn:SetPoint("TOP", parent, "TOP", 0, -((opts.topOffset or 20) + ((index or 1) - 1) * (opts.rowHeight or h)))
    end
    btn:EnableMouse(true)
    btn.key, btn.color, btn.tooltip = def.key, def.color, def.tooltip
    btn.bg = PixelLayoutRegion(btn:CreateTexture(nil, "BACKGROUND"))
    btn.bg:SetAllPoints()
    btn.bar = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK"))
    btn.fs = PixelLayoutRegion(btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    if not chip then
        btn.bar:SetSize(3, h - 5)
        btn.bar:SetPoint("LEFT", btn, "LEFT", 3, 0)
        btn.fs:SetPoint("LEFT", btn.bar, "RIGHT", 8, 0)
        btn.fs:SetPoint("RIGHT", btn, "RIGHT", opts.showOffText == true and -24 or -8, 0)
        btn.fs:SetJustifyH("LEFT")
    end
    btn.fs:SetText(tr(def.label))
    if theme and theme.ApplyMenuFont then theme.ApplyMenuFont(btn.fs, 0) end
    if chip then LayoutLayerChip(btn, h) end
    btn.off = PixelLayoutRegion(btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    btn.off:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    btn.off:SetText(opts.offText or "OFF")
    btn.off:SetJustifyH("RIGHT")
    if theme and theme.ApplyMenuFont then theme.ApplyMenuFont(btn.off, 0) end
    function btn:Refresh() H.RefreshLayerButton(self, owner, opts) end
    btn.refresh = btn.Refresh
    btn:SetScript("OnClick", function(self)
        if opts.OnClick then
            opts.OnClick(self, owner)
            return
        end
        if not LayerButtonAvailable(owner, self.key) then return end
        owner.layerVisibility[self.key] = owner.layerVisibility[self.key] == false
        self:Refresh()
    end)
    -- Layer pills are toggles, not fire-and-forget buttons.  Expose the exact
    -- state transition to RuntimeControlCatalog so Search requests such as
    -- "show Guides" and "hide Guides" are idempotent and disabled layers can
    -- fail closed instead of silently inverting another state.
    btn._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = function()
            return LayerButtonAvailableFor(owner, btn.key, opts)
                and LayerButtonOnFor(owner, btn.key, opts) or false
        end,
        set = function(value)
            if not LayerButtonAvailableFor(owner, btn.key, opts) then return false end
            local desired = value == true
            local current = LayerButtonOnFor(owner, btn.key, opts) and true or false
            if current == desired then return true end
            if opts.OnClick then
                opts.OnClick(btn, owner)
            else
                owner.layerVisibility[btn.key] = desired
                btn:Refresh()
            end
            return (LayerButtonOnFor(owner, btn.key, opts) and true or false) == desired
        end,
    }
    btn:SetScript("OnEnter", function(self)
        local available = LayerButtonAvailableFor(owner, self.key, opts)
        local on = LayerButtonOnFor(owner, self.key, opts)
        self._msuf2LayerHovered = true
        self:Refresh()
        if opts.OnEnter then
            opts.OnEnter(self, owner, available, on, tr)
        elseif GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tr(self.fs:GetText() or self.key), 1, 1, 1)
            if self.tooltip then GameTooltip:AddLine(tr(self.tooltip), 0.82, 0.82, 0.82, true) end
            if not available and opts.disabledLine then GameTooltip:AddLine(tr(opts.disabledLine), 0.55, 0.68, 0.86, true) end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if GameTooltip then GameTooltip:Hide() end
        self._msuf2LayerHovered = nil
        self:Refresh()
        if opts.OnLeave then opts.OnLeave(self, owner) end
    end)
    btn:Refresh()
    return btn
end
--- The gate both preview live-state drivers run first: entering combat drops
--- every listener but the re-arm signal, a hidden box drops all of them.
--- Returns true when the event ends here.
function H.LiveStateDriverGate(driver, event, box)
    if event == "PLAYER_REGEN_DISABLED" then
        driver:UnregisterAllEvents()
        driver._msufLiveArmed = false
        driver:RegisterEvent("PLAYER_REGEN_ENABLED")
        return true
    end
    if not (box.IsShown and box:IsShown()) then
        driver:UnregisterAllEvents()
        driver._msufLiveArmed = false
        return true
    end
    return false
end

--- A region list kept on owner (owner[cacheField][field]) and refilled with
--- a, b, c, d: the text focus rings and the text handles refit around it on
--- every repaint and animation tick without allocating a table.
function H.CachedRegionList(owner, cacheField, field, a, b, c, d)
    local lists = owner[cacheField]
    if not lists then
        lists = {}
        owner[cacheField] = lists
    end
    local list = lists[field]
    if not list then
        list = {}
        lists[field] = list
    end
    list[1], list[2], list[3], list[4] = a, b, c, d
    return list
end

--- Moves a preview's "Layers" button into the compact header, beside the
--- expand button, or back to the box's top-left corner.
function H.LayoutCompactLayersButton(box, compact, Tr)
    if not box then return end
    local header = box._msuf2CompactHeader
    local expandBtn = box._msuf2CompactExpandButton
    local layersBtn = box._msuf2LayersButton
    if compact and header then
        if layersBtn then
            if layersBtn.SetText then layersBtn:SetText(Tr("Preview Layers") .. " v", true) end
            local layerLabel = layersBtn._msuf2Label
            if layerLabel then layersBtn:SetWidth(math.max(108, layerLabel:GetStringWidth() + 24)) end
            layersBtn:SetParent(header)
            layersBtn:ClearAllPoints()
            if expandBtn then layersBtn:SetPoint("RIGHT", expandBtn, "LEFT", -8, 0)
            else layersBtn:SetPoint("RIGHT", header, "RIGHT", -108, 0) end
            if layersBtn.SetFrameLevel and header.GetFrameLevel then
                layersBtn:SetFrameLevel((header:GetFrameLevel() or 1) + 3)
            end
        end
        return
    end
    if layersBtn then
        if layersBtn.SetText then layersBtn:SetText("Preview Layers") end
        layersBtn:SetParent(box)
        layersBtn:ClearAllPoints()
        layersBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -5)
    end
end

--- Paints an "Animate" / "Stop" preview pill: label, text colour, pill state
--- and, on a button without a pill fill, the backdrop (idleFill / idleBorder
--- while stopped).
function H.PaintAnimateButton(btn, active, Tr, idleFill, idleBorder)
    if btn.fs then
        -- The button plays an animation loop; it does not switch the preview
        -- into a combat state. Label it after what it does.
        btn.fs:SetText(active and Tr("Stop") or Tr("Animate"))
        btn.fs:SetTextColor(active and 0.06 or 0.78, active and 0.95 or 0.84, active and 1.00 or 0.96, 1)
    end
    if btn.MSUF2RefreshPreviewPill then btn:MSUF2RefreshPreviewPill(active) end
    if btn.SetBackdropColor and not btn._msuf2PreviewPillFill then
        if active then
            btn:SetBackdropColor(0.020, 0.125, 0.155, 0.96)
            btn:SetBackdropBorderColor(0.10, 0.82, 0.95, 1)
        else
            btn:SetBackdropColor(idleFill[1], idleFill[2], idleFill[3], idleFill[4])
            btn:SetBackdropBorderColor(idleBorder[1], idleBorder[2], idleBorder[3], idleBorder[4])
        end
    end
end

--- The chip-style layer button options both preview rails share (theme text
--- colours, quiet row fills, the selected-layer check). The caller's table
--- carries availability, on state and the pointer handlers and is returned.
local function LayerChipSelected(owner, key) return owner and owner._msuf2SelectedPreviewLayerKey == key end
function H.LayerChipButtonOpts(Tr, colors, chrome, opts)
    local active = colors.pillTextActive or colors.text or { 0.92, 0.96, 1.00, 1.00 }
    local muted = colors.muted or { 0.62, 0.70, 0.82, 0.90 }
    local disabled = colors.dim or { 0.36, 0.46, 0.60, 0.82 }
    opts.Tr, opts.layout, opts.height, opts.rowHeight, opts.topOffset = Tr, "chip", 20, 20, 23
    opts.showOffText, opts.quiet, opts.quietBase, opts.quietHover = false, true, chrome.rowBase, chrome.rowHover
    opts.textOn = { active[1], active[2], active[3], 1.00 }
    opts.textOff = { muted[1], muted[2], muted[3], 0.72 }
    opts.textDisabled = { disabled[1], disabled[2], disabled[3], 0.64 }
    opts.IsSelected = LayerChipSelected
    return opts
end

--- Sample-effect layers paint a stand-in effect (a dispel wash, dispel symbols) that the frame does not carry right
--- now. They start hidden in every preview, so the rail never tints a preview with an effect nobody asked for. They
--- show on a chip click, or while the settings section that owns them is open, and a hint under the preview names
--- whatever is painted and hides it again with one click.
H.SAMPLE_EFFECT_LAYERS = { dispelOverlay = true, dispelSymbol = true }
function H.IsSampleEffectLayer(key) return H.SAMPLE_EFFECT_LAYERS[key] == true end
--- The chip tooltip line every sample-effect chip adds below its own description.
function H.AddSampleEffectTooltipLine(key, tr)
    if H.SAMPLE_EFFECT_LAYERS[key] ~= true or not GameTooltip then return end
    GameTooltip:AddLine(tr("Shows a sample effect your frame does not currently have."), 0.95, 0.80, 0.40, true)
end
--- One edge of "the matching settings section opened/closed". Opening switches an off layer on and remembers that the
--- section did it; closing switches that layer off again. A chip click clears the memory (state.auto[key] = nil), so a
--- layer the user picked stays as picked. Returns true when the layer changed.
function H.SyncSampleLayerSection(state, visibility, key, open)
    if (state.open[key] == true) == open then return false end
    state.open[key] = open
    if open then
        if visibility[key] ~= false then return false end
        visibility[key], state.auto[key] = true, true
        return true
    end
    if state.auto[key] ~= true then return false end
    state.auto[key] = nil
    visibility[key] = false
    return true
end
--- Reads the open settings sections of one page (accordion = the persisted accordion states) for every sample layer in
--- `sections` (layerKey -> sectionId) and applies the edges. `holder` keeps the per-surface state and the composed
--- state keys, so a warm repaint allocates nothing. With activePage given, the sections count as open only while that
--- page is the one shown (previews shared by several pages). Returns true when a layer changed.
function H.SyncSampleLayerSections(holder, visibility, pageKey, sections, accordion, activePage)
    if not (pageKey and type(accordion) == "table" and type(visibility) == "table") then return false end
    local state = holder._msuf2SampleLayers
    if not state then
        state = { auto = {}, open = {}, keys = {} }
        holder._msuf2SampleLayers = state
    end
    if state.page ~= pageKey then
        state.page = pageKey
        for layerKey, sectionId in pairs(sections) do state.keys[layerKey] = pageKey .. ":" .. sectionId end
    end
    local changed, onPage = false, activePage == nil or activePage == pageKey
    for layerKey, stateKey in pairs(state.keys) do
        if H.SyncSampleLayerSection(state, visibility, layerKey, onPage and accordion[stateKey] == true) then changed = true end
    end
    return changed
end
--- Registers the hint under a preview surface; the button itself is built the first time a sample effect paints, so a
--- preview that never shows one carries no extra frame. opts: Tr, T, buttons (field on the box holding the layer
--- chips), IsOn(box, key) (the chip's painting state), Hide(box) (what a click does: the same as clicking each
--- painted chip).
function H.SetupSampleEffectHint(box, surface, opts)
    if not (box and surface) then return end
    opts.surface = surface
    box._msuf2SampleEffectOpts = opts
end
local function BuildSampleEffectHint(box, opts)
    local surface = opts.surface
    local T, tr = opts.T or M.Theme, opts.Tr or Fallbacks.Identity
    local hint = PixelLayoutRegion(CreateFrame("Button", nil, surface, T and T.Template and T.Template() or "BackdropTemplate"))
    hint:SetHeight(20)
    hint:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -8, 8)
    if hint.SetFrameLevel and surface.GetFrameLevel then hint:SetFrameLevel((surface:GetFrameLevel() or 0) + 120) end
    if hint.SetBackdrop then
        FlatBackdrop(hint, { 0.012, 0.020, 0.040, 0.92 }, { 0.80, 0.62, 0.20, 0.90 })
    end
    local text = ThemedFont(hint, T, "GameFontDisableSmall", nil, { 0.96, 0.86, 0.58, 1 })
    text:SetPoint("LEFT", hint, "LEFT", 8, 0)
    text:SetPoint("RIGHT", hint, "RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    hint._text = text
    hint:SetScript("OnClick", function() opts.Hide(box) end)
    hint:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText(text:GetText() or "", 1, 1, 1, 1, true)
        GameTooltip:AddLine(tr("Click to hide these sample effects."), 0.55, 0.68, 0.86, true)
        GameTooltip:Show()
    end)
    hint:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    hint:Hide()
    box._msuf2SampleEffectHint = hint
    return hint
end
--- Shows the hint while at least one sample-effect chip paints, naming the painted layers. The label list is rebuilt
--- only when the painted set changes.
function H.RefreshSampleEffectHint(box)
    local opts = box._msuf2SampleEffectOpts
    if not opts then return end
    local hint = box._msuf2SampleEffectHint
    local buttons, mask, count = box[opts.buttons] or {}, 0, 0
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn.key and H.SAMPLE_EFFECT_LAYERS[btn.key] == true and opts.IsOn(box, btn.key) and (not btn.IsShown or btn:IsShown()) then
            mask, count = mask + 2 ^ (i - 1), count + 1
        end
    end
    if count == 0 then
        if hint and hint._mask ~= 0 then
            hint._mask = 0
            hint:Hide()
        end
        return
    end
    hint = hint or BuildSampleEffectHint(box, opts)
    if hint._mask ~= mask then
        hint._mask = mask
        local names = {}
        for i = 1, #buttons do
            if floor(mask / 2 ^ (i - 1)) % 2 == 1 then names[#names + 1] = buttons[i].fs:GetText() or buttons[i].key end
        end
        local tr = opts.Tr or Fallbacks.Identity
        SetShownText(hint._text, string.format(tr("Sample effects shown: %s - not your live state"), table.concat(names, ", ")))
        local width = (hint._text.GetStringWidth and hint._text:GetStringWidth() or 0) + 18
        local surface = hint:GetParent()
        local surfaceWidth = surface and surface.GetWidth and surface:GetWidth() or 0
        if surfaceWidth > 40 and width > surfaceWidth - 16 then width = surfaceWidth - 16 end
        hint:SetWidth(width)
        hint:Show()
    end
end

--- Lays out a preview box's layer chips: as the compact popover while the
--- rail hangs under the "Layers" button (it owns its width then), otherwise
--- flowed across the rail beside the optional rail header.
function H.LayoutLayerRail(box, rail, buttons, railWidth)
    local popover = box._msuf2LayerPopoverWidth
    if popover then
        local boxW = (box.GetWidth and box:GetWidth()) or 0
        local boxH = (box.GetHeight and box:GetHeight()) or 0
        return H.FlowLayerPopover(rail, buttons, {
            width = popover,
            maxWidth = boxW > 0 and (boxW - 24) or nil,
            maxHeight = boxH > 0 and (boxH - 44) or nil,
            rowHeight = 20,
        })
    end
    railWidth = tonumber(railWidth) or (rail and rail.GetWidth and rail:GetWidth()) or 0
    local headerWidth = 0
    local header = box._msuf2LayerRailHeader
    if header and header:IsShown() then
        headerWidth = ((header.GetStringWidth and header:GetStringWidth()) or 44) + 18
    end
    return H.FlowLayerChips(rail, buttons, {
        width = railWidth,
        padX = 10 + headerWidth,
        padXRight = 10,
        rowHeight = 20,
    })
end

--- One layout path for a docked or floating preview box: the layer rail on
--- the bottom edge, the selection bar above it, the surface takes the rest.
--- raiseRail lifts the rail over the surface and shows its header first.
function H.ApplyDockedPreviewLayout(box, rail, surface, bottomInset, raiseRail)
    bottomInset = tonumber(bottomInset) or 12
    local selection = box._msuf2SelectionBar
    if not surface then return end
    if rail then
        rail:ClearAllPoints()
        rail:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, bottomInset)
        rail:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, bottomInset)
        if raiseRail then
            if rail.SetFrameLevel and surface.GetFrameLevel then
                rail:SetFrameLevel((surface:GetFrameLevel() or 1) + 1)
            end
            if box._msuf2LayerRailHeader then box._msuf2LayerRailHeader:Show() end
        end
        rail:Show()
        if box.LayoutLayerRail then
            box:LayoutLayerRail((box.GetWidth and box:GetWidth() or 0) - 24)
        end
    end
    surface:ClearAllPoints()
    surface:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
    if selection and rail then
        selection:ClearAllPoints()
        selection:SetPoint("BOTTOMLEFT", rail, "TOPLEFT", 0, 6)
        selection:SetPoint("BOTTOMRIGHT", rail, "TOPRIGHT", 0, 6)
        selection:Show()
        surface:SetPoint("BOTTOMRIGHT", selection, "TOPRIGHT", 0, 6)
    else
        surface:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, bottomInset)
    end
    if box._msuf2ElementPicker then box._msuf2ElementPicker:Show() end
end

--- Flows measured layer chips into `rail`, wrapping when a row is full.
--- Returns the height the rail needs, so callers can let the canvas absorb
--- whatever the chips do not use instead of reserving a fixed strip.
function H.FlowLayerChips(rail, buttons, opts)
    opts = opts or {}
    if not (rail and buttons) then return 0 end
    local padX, padY = opts.padX or 8, opts.padY or 5
    local gapX, gapY = opts.gapX or 5, opts.gapY or 4
    local rowH = opts.rowHeight or 20
    local available = (tonumber(opts.width) or (rail.GetWidth and rail:GetWidth()) or 0) - padX - (tonumber(opts.padXRight) or padX)
    if available <= 0 then available = 480 end
    local x, rows, widest = 0, 1, 0
    for i = 1, #buttons do
        local btn = buttons[i]
        -- Hidden layer buttons (a feature the surface does not expose) must not
        -- leave a gap in the flow.
        if btn and (not btn.IsShown or btn:IsShown()) then
            local w = (btn.GetWidth and btn:GetWidth()) or 60
            if x > 0 and (x + w) > available then
                x = 0
                rows = rows + 1
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", rail, "TOPLEFT", padX + x, -(padY + (rows - 1) * (rowH + gapY)))
            x = x + w + gapX
            if x - gapX > widest then widest = x - gapX end
        end
    end
    local height = padY * 2 + rows * rowH + (rows - 1) * gapY
    if rail.SetHeight then rail:SetHeight(height) end
    rail._msuf2ChipRows = rows
    -- Second return: the width the widest row actually needs, so a popover can
    -- hug its chips instead of leaving dead panel beside a short last row.
    return height, padX + widest + (tonumber(opts.padXRight) or padX)
end
-- A layer rail hanging under a "Layers" button is a dropdown, so it has to stay
-- inside the preview it belongs to in both directions. Flow at the narrow
-- authored column first, widen only as far as needed to keep it off the bottom
-- edge, then hug the chips so a short last row leaves no dead panel.
function H.FlowLayerPopover(rail, buttons, opts)
    opts = opts or {}
    local width = tonumber(opts.width) or 268
    local cap = math.max(width, tonumber(opts.maxWidth) or width)
    local budget = tonumber(opts.maxHeight)
    local function Flow(w)
        return H.FlowLayerChips(rail, buttons, {
            width = w,
            padX = opts.padX or 10,
            padXRight = opts.padXRight or 10,
            rowHeight = opts.rowHeight,
        })
    end
    local height, used = Flow(width)
    while budget and height > budget and width < cap do
        width = min(cap, width + 48)
        height, used = Flow(width)
    end
    if rail and rail.SetWidth then
        rail:SetWidth(min(width, math.max(120, used or width)))
    end
    return height, width
end
local function SetCanvasToolsShown(box, shown, animateButton)
    if not box then return end
    local controlsHint = box._msuf2PreviewControlsHint
    if not shown then
        if box._msuf2CompactToolsHidden ~= true then
            box._msuf2CompactControlsHintWasShown = controlsHint and controlsHint.IsShown and controlsHint:IsShown() or false
        end
        box._msuf2CompactToolsHidden = true
        if box.zoomBar then box.zoomBar:Hide() end
        if animateButton then animateButton:Hide() end
        if controlsHint then controlsHint:Hide() end
        return
    end
    box._msuf2CompactToolsHidden = nil
    if box.zoomBar then box.zoomBar:Show() end
    if animateButton then animateButton:Show() end
    if controlsHint and box._msuf2CompactControlsHintWasShown then controlsHint:Show() end
end
H.SetCanvasToolsShown = SetCanvasToolsShown

