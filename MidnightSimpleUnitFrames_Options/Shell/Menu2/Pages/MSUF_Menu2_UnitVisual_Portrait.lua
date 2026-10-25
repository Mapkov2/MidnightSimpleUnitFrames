-- Portrait state owner; dependencies bind once when the page module loads.
local _, MSUF = ...
local M = MSUF.MSUF2
M.UnitVisualFactories = M.UnitVisualFactories or {}

M.UnitVisualFactories.Portrait = function(
    MSUF, M, W, Schema, ControlRow, SectionCard, PixelLayoutRegion, UP, max, min, VT, PORTRAIT_RENDER, PORTRAIT_SHAPES,
    PORTRAIT_BORDERS, GetConf, ReadBool, ReadNumber, SetNumber, NormalizePortrait, SetPortraitValue, ControlMeta, ReviewedMeta,
    CASTBAR_UNITS, UnitSectionShared, SetSectionHeaderStatus, NormalizeTabKey, CurrentTab, SetSectionBodyHeight,
    BuildSectionTabs, PrepareTabTarget
)

-- Portrait placement value lists. Kept in one table instead of one file local
-- per list; the shared ones come from the section helpers the Group page also uses.
local PORTRAIT_PLACEMENT = M.UnitSectionsShared.PortraitPlacementValues()
PORTRAIT_PLACEMENT.dragonLayer = VT("BACKGROUND", "Background", "BORDER", "Border", "ARTWORK", "Artwork", "OVERLAY", "Overlay")
PORTRAIT_PLACEMENT.classificationPreview = VT("OFF", "Off", "elite", "Elite (gold)", "rare", "Rare (silver)",
    "rareelite", "Rare elite (silver)", "worldboss", "Boss (winged gold)")
local PORTRAIT_SIZE_MODES = VT("UNIFORM", "Uniform", "SEPARATE", "Width & height")
local function PortraitClassStyleValues()
    local PM = MSUF and MSUF.PortraitMedia
    local opts = (PM and PM.GetPackOptions and PM.GetPackOptions()) or {
        { value = "BLIZZARD", text = "Blizzard Class Icon" },
    }
    local values = {}
    for i = 1, #opts do
        local item = opts[i]
        values[#values + 1] = {
            value = item.value or item.key,
            text = item.text or item.label or item.value or item.key,
        }
    end
    return values
end
local NormalizePortraitClassStyle = M.NormalizePortraitClassStyle
-- Card heights. BuildPortrait and PortraitLayoutForWidth must agree on these, so
-- both read them from here instead of repeating literals.
local PORTRAIT_CARD_H = { main = 224, geometry = 440, placement = 382, border = 704, style = 330, dragon = 540 }
local PORTRAIT_TAB_HEIGHTS = {
    general = PORTRAIT_CARD_H.main + 116,
    geometry = PORTRAIT_CARD_H.geometry + 116,
    placement = PORTRAIT_CARD_H.placement + 116,
    border = PORTRAIT_CARD_H.border + 116,
    advanced = PORTRAIT_CARD_H.style + 116,
    dragon = PORTRAIT_CARD_H.dragon + 116,
}
local function CurrentPortraitTab(unit)
    return CurrentTab("unitPortraitTabSelection", PORTRAIT_TAB_HEIGHTS, unit)
end
local function PortraitTabHeight(tab)
    return PORTRAIT_TAB_HEIGHTS[NormalizeTabKey(PORTRAIT_TAB_HEIGHTS, tab)]
end
local function PortraitTabValues(sectionWidth)
    if (tonumber(sectionWidth) or 720) < 700 then
        return VT("general", "General", "placement", "Place", "geometry", "Size", "border", "Border", "dragon", "Dragon", "advanced", "More")
    end
    return VT(
        "general", "General",
        "placement", "Placement",
        "geometry", "Size & Zoom",
        "border", "Shape & Border",
        "dragon", "Dragon",
        "advanced", "More Options")
end
local function PortraitLayoutForWidth(sectionWidth, tab)
    sectionWidth = tonumber(sectionWidth) or 720
    return {
        height = PortraitTabHeight(tab),
        cardX = 16,
        cardW = max(260, min(620, sectionWidth - 32)),
        tabW = max(260, min(780, sectionWidth - 40)),
    }
end
UP.PortraitLayoutForWidth = PortraitLayoutForWidth
local function PreparePortraitSwitch(ctx, sec, unit)
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then Schema.Section(sec, unit) end
    if entry and entry.featureSwitch then return entry.featureSwitch end
    M._msuf2LastPortraitSide = M._msuf2LastPortraitSide or {}
    local portraitEnable
    portraitEnable = ControlRow(ctx, sec, { "sectionSwitch", "portraitEnable", false, { "Portrait" },
        get = function() return NormalizePortrait(unit) ~= "OFF" end,
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(v)
            if v then
                SetPortraitValue(unit, "portraitMode", M._msuf2LastPortraitSide[unit] or "LEFT", "MSUF2_PORTRAIT_MODE")
            else
                local mode = NormalizePortrait(unit)
                if mode == "LEFT" or mode == "RIGHT" then M._msuf2LastPortraitSide[unit] = mode end
                SetPortraitValue(unit, "portraitMode", "OFF", "MSUF2_PORTRAIT_MODE")
            end
            if portraitEnable.refreshDetails then portraitEnable.refreshDetails() end
        end,
        scope = unit, setting = unit .. ".portraitMode", meta = ReviewedMeta(ctx, "portrait.enabled", "setting", "compound",
            "Portrait is a boolean shortcut over the OFF/LEFT/RIGHT portraitMode enum and restores the remembered side when enabled."),
    })
    portraitEnable:SetChecked(NormalizePortrait(unit) ~= "OFF")
    return portraitEnable
end
local function BuildPortraitDirection(ctx, card, unit, width, metadata)
    local values = VT("TOPLEFT", "Top left", "TOPRIGHT", "Top right", "BOTTOMLEFT", "Bottom left", "BOTTOMRIGHT", "Bottom right", "AUTO", "Auto")
    local pad = W.Segment(card, "Blizzard frame direction", values, 340, { multiSelect = true })
    W.MoveWidget(pad, card, 16, -202, 104)
    pad._msuf2Title:SetWidth(width - 32)
    pad._msuf2SearchText = "Blizzard portrait ring frame direction mirror corner top bottom left right automatic"
    local theme = M.Theme
    local surface = theme.Panel(card, nil, theme.colors.panel2 or { 0.014, 0.038, 0.072, 0.55 }, theme.colors.borderSoft)
    surface:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -226)
    surface:SetSize(104, 78)
    pad:SetParent(surface)
    pad:ClearAllPoints()
    pad:SetPoint("TOPLEFT", surface, "TOPLEFT", 0, 0)
    pad:SetSize(104, 78)
    local center = PixelLayoutRegion(surface:CreateTexture(nil, "ARTWORK"))
    center:SetPoint("CENTER", surface, "CENTER", 0, 0)
    center:SetSize(10, 10)
    local color = theme.colors.coreRim or { 0.043, 0.096, 0.150 }
    center:SetColorTexture(color[1], color[2], color[3], 0.95)
    local positions = {
        { 41, -7, "^", "Up" }, { 18, -30, "<", "Left" },
        { 64, -30, ">", "Right" }, { 41, -53, "v", "Down" }, { 118, 0, values[5].text, "Auto" },
    }
    for i, button in ipairs(pad.buttons) do
        local position = positions[i]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", pad, "TOPLEFT", position[1], position[2])
        button:SetSize(i == 5 and 80 or 22, i == 5 and 22 or 18)
        button:SetText(position[3])
        theme.CenterButtonLabel(button)
        if M.AddTooltip then
            M.AddTooltip(button, position[4], "Move the Blizzard frame corner toward this arrow. Auto follows portrait mirroring.", { hook = true })
        end
    end
    local selection = {}
    function pad:SetValue(value)
        self.value = value
        selection.blizzardDirection, selection.flip = value, GetConf(unit).portraitFlip == true
        local _, coords = MSUF.PortraitDetails.GetBlizzardDirection(selection)
        local top, left = coords.y == 1, coords.x == -1
        self.buttons[1]._msuf2Value = left and "TOPLEFT" or "TOPRIGHT"
        self.buttons[2]._msuf2Value = top and "TOPLEFT" or "BOTTOMLEFT"
        self.buttons[3]._msuf2Value = top and "TOPRIGHT" or "BOTTOMRIGHT"
        self.buttons[4]._msuf2Value = left and "BOTTOMLEFT" or "BOTTOMRIGHT"
        self.buttons[1]:SetActive(top)
        self.buttons[2]:SetActive(left)
        self.buttons[3]:SetActive(not left)
        self.buttons[4]:SetActive(not top)
        self.buttons[5]:SetActive(value == "AUTO")
    end
    pad:SetValue(MSUF.PortraitDetails.NormalizeBlizzardDirection(GetConf(unit).portraitBlizzardDirection))
    local note = MSUF.Client.IsVanilla and "Classic Era uses a round Blizzard portrait frame." or "Auto follows portrait mirroring."
    ControlRow(ctx, card, { "text", "menu2.uf_" .. unit .. ".portrait.blizzardDirection.description", nil,
        { note, 134, -260, width - 150 }, scope = unit, domain = "description" })
    if MSUF.Client.IsVanilla then
        W.SetControlGateEnabled(pad, "classic-round", false)
        W.SetControlDisabledReason(pad, note)
    end
    Schema.Bind(ctx, pad, {
        id = metadata.controlId, kind = "segment", labelKey = "Blizzard frame direction", settingPath = metadata.settingKey,
        meta = metadata, scope = unit, applyDomain = "portrait",
        get = function() return MSUF.PortraitDetails.NormalizeBlizzardDirection(GetConf(unit).portraitBlizzardDirection) end,
        write = { call = SetPortraitValue, args = { "MSUF2_PORTRAIT_BLIZZARD_DIRECTION" } }, --[[schema setter: UnitFrameVisuals.3]]
    })
    return pad
end
-- The Portrait section builds in three stages that share one table `p`: the shell (tab frames, cards
-- and tab bar), the controls (every control by name in p.c) and the gate group that enables them.
local PortraitSection = {}
function PortraitSection.Shell(p)
    local ctx, unit, sec, layout = p.ctx, p.unit, p.sec, p.layout
    local tabFrames = {}
    local generalTab, geometryTab, placementTab, borderTab, advancedTab, dragonTab =
        UnitSectionShared.MakeTabFrames(sec, -64, p.sectionW, tabFrames, "general", "geometry", "placement", "border", "advanced", "dragon")
    local cards = {}
    for _, card in ipairs({
        { "main", generalTab, "Visibility & Mode" }, { "geometry", geometryTab, "Geometry" }, { "placement", placementTab, "Placement" },
        { "border", borderTab, "Shape & Border" }, { "style", advancedTab, "Class & Background" }, { "dragon", dragonTab, "Dragon decoration" },
    }) do
        cards[card[1]] = SectionCard(ctx, unit, card[2], "portrait", card[1] .. "Card",
            { card[3], nil, layout.cardX, -4, layout.cardW, PORTRAIT_CARD_H[card[1]], "group" })
    end
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(cards.border, { "portrait.border" }, {
            title = "Portrait Border Color",
            note = "Configure the color used by the Solid and Custom portrait border styles.",
            historySource = "menu:unit-portrait-border-color",
        })
        W.AttachContextColorReferences(cards.style, { "portrait.background" }, {
            title = "Portrait Background Color",
            note = "Configure the optional portrait background color.",
            historySource = "menu:unit-portrait-background-color",
        })
    end
    BuildSectionTabs(ctx, sec, unit, { stateKey = "unitPortraitTabSelection", heights = PORTRAIT_TAB_HEIGHTS,
        values = PortraitTabValues(p.sectionW), width = layout.tabW, frames = tabFrames,
        controlId = "portrait.workspace_tab", label = "Portrait area",
        afterRefresh = function(tab) SetSectionBodyHeight(sec, PortraitTabHeight(tab), PORTRAIT_TAB_HEIGHTS.general) end })
    p.cards = cards
end
-- Row factories of the portrait controls, stored on `p`. Each returns the built control; `extra` carries
-- the row's own fields (afterSet, normalize, search, tab) and becomes the row. `search` adds search
-- text and `tab` makes the control the exact search target of that tab.
function PortraitSection.Factories(p)
    local ctx, unit, sec = p.ctx, p.unit, p.sec
    local w = p.layout.cardW
    function p.Meta(path, settingKey)
        local meta = ControlMeta(ctx, path)
        meta.settingKey = settingKey
        return meta
    end
    function p.TabTarget(widget, tab, settingKey)
        PrepareTabTarget(sec, "unitPortraitTab", widget, tab, settingKey)
    end
    -- One stored portrait setting with the default get/set of its kind.
    local function PortraitRow(parent, row)
        local kind, key, fallback = row[1], row[2], row[3]
        row.get = function()
            if kind == "toggle" then return ReadBool(unit, key, fallback) end
            if kind == "slider" then return ReadNumber(unit, key, fallback) end
            local value = GetConf(unit)[key]
            value = value == nil and fallback or value
            return row.normalize and row.normalize(value) or value
        end
        if row.normalize and kind ~= "slider" and kind ~= "toggle" then
            row.customSetReason = "Canonicalizes the portrait shape or size mode before applying the portrait."
            row.write = {
                call = kind == "slider" and SetNumber or SetPortraitValue,
                args = kind == "slider" and { row.reason, { preview = true } } or { row.reason },
                convert = function(value)
                    if kind == "slider" then return value end
                    if kind == "toggle" then return value and true or false end
                    return row.normalize and row.normalize(value or fallback) or (value or fallback)
                end, after = row.afterSet
            } --[[schema setter: H4.UnitFrameVisuals.3]]
        else
            row.write = { call = kind == "slider" and SetNumber or SetPortraitValue,
                boolean = kind == "toggle", args = { row.reason, kind == "slider" and { preview = true } or nil },
                after = row.afterSet and function() row.afterSet() end } --[[schema setter: UnitFrameVisuals.PortraitRows]]
            if kind ~= "slider" and kind ~= "toggle" then row.write.fallback = fallback end
        end
        row.meta = p.Meta("portrait." .. tostring(key), tostring(unit) .. "." .. tostring(key))
        row.scope, row.roundStep = unit, kind == "slider"
        local widget = ControlRow(ctx, parent, row)
        if row.search then widget._msuf2SearchText = row.search end
        if row.tab then p.TabTarget(widget, row.tab, tostring(unit) .. "." .. key) end
        return widget
    end
    local function Row(kind, key, fallback, args, placement, reason, extra)
        extra = extra or {}
        extra[1], extra[2], extra[3], extra[4], extra[5], extra.reason = kind, key, fallback, args, placement, reason
        return extra
    end
    function p.Drop(card, key, fallback, label, values, y, reason, extra)
        return PortraitRow(card, Row("dropdown", key, fallback, { label, values, 220 }, { 16, y, min(220, w - 32) }, reason, extra))
    end
    function p.Slide(card, key, fallback, label, lo, hi, step, y, reason, extra)
        return PortraitRow(card, Row("slider", key, fallback, { label, lo, hi, step, 280 }, { 16, y, w - 58, "CENTER" }, reason, extra))
    end
    function p.Toggle(card, key, fallback, label, y, reason, extra)
        return PortraitRow(card, Row("toggle", key, fallback, { label, 16, y, w - 32 }, nil, reason, extra))
    end
end
-- Controls of the General, Border and Size tabs, in creation order.
function PortraitSection.Controls(p)
    local ctx, unit, sec, cards, c, Refresh = p.ctx, p.unit, p.sec, p.cards, p.c, p.Refresh
    local Meta, TabTarget, Drop, Slide, Toggle = p.Meta, p.TabTarget, p.Drop, p.Slide, p.Toggle
    local w = p.layout.cardW
    c.portraitEnable = PreparePortraitSwitch(ctx, sec, unit)
    c.portraitEnable.refreshDetails = function() p.Refresh() end
    c.portrait = ControlRow(ctx, cards.main, { "segment", "portrait", "LEFT", { "Position", VT("LEFT", "Left", "RIGHT", "Right"), min(220,
        w) }, { 16, -62, min(220, w - 32) },
        get = function()
            local mode = NormalizePortrait(unit)
            return mode == "RIGHT" and "RIGHT" or "LEFT"
        end,
        write = { call = SetPortraitValue, fallback = "LEFT", args = { "MSUF2_PORTRAIT_MODE" },
            before = function(value) M._msuf2LastPortraitSide[unit] = value == "RIGHT" and "RIGHT" or "LEFT" end,
            after = p.Refresh
        } --[[schema setter: J5.UnitPortrait.Position]],
        scope = unit, meta = Meta("portrait.position", tostring(unit) .. ".portraitMode"),
    })
    c.render = Drop(cards.main, "portraitRender", "2D", "Render", PORTRAIT_RENDER, -116, "MSUF2_PORTRAIT_RENDER", { afterSet = Refresh })
    c.clickable = Toggle(cards.main, "portraitClickable", false, "Clickable portrait", -174, "MSUF2_PORTRAIT_CLICKABLE",
        { tab = "general", search = "Clickable portrait unit frame target right click menu click casting mouseover" })
    c.shape = Drop(cards.border, "portraitShape", "SQUARE", "Shape", PORTRAIT_SHAPES, -58, "MSUF2_PORTRAIT_SHAPE", { afterSet = Refresh })
    c.eliteDragon = Toggle(cards.border, "portraitBlizzardElite", false, "Elite and rare dragon", -112, "MSUF2_PORTRAIT_BLIZZARD_ELITE", {
        afterSet = Refresh, tab = "border", search = "Blizzard portrait ring elite rare rareelite boss gold silver dragon classification" })
    c.blizzardCorner = Toggle(cards.border, "portraitBlizzardCorner", false, "Gold corner connector", -148, "MSUF2_PORTRAIT_BLIZZARD_CORNER", {
        afterSet = Refresh, tab = "border", search = "Blizzard portrait frame gold corner triangle connector embellishment Forever" })
    c.blizzardDirection = BuildPortraitDirection(ctx, cards.border, unit, w,
        Meta("portrait.portraitBlizzardDirection", tostring(unit) .. ".portraitBlizzardDirection"))
    TabTarget(c.blizzardDirection, "border", tostring(unit) .. ".portraitBlizzardDirection")
    local portraitElement = MSUF.UF and MSUF.UF.elements and MSUF.UF.elements.Portrait
    function p.DragonPreview(card, id, y, meta, refreshReason)
        return ControlRow(ctx, card, { "dropdown", id, "OFF", { "Runtime Preview", PORTRAIT_PLACEMENT.classificationPreview, 220 },
            { 16, y, min(280, w - 32) },
            get = function() return portraitElement and portraitElement.GetClassificationPreview(unit) or "OFF" end,
            customSetReason = "Changes preview or editor selection state through its existing owner.", set = function(value)
                if portraitElement then portraitElement.SetClassificationPreview(unit, value) end
                if refreshReason then M.RequestRefresh(ctx, refreshReason) end
            end,
            scope = unit, meta = meta })
    end
    c.dragonPreview = p.DragonPreview(cards.border, "dragonPreview", -322, ReviewedMeta(ctx, "portrait.classification_preview", "ephemeral", "excluded",
        "Temporary classification art on the live portrait; no saved setting."))
    TabTarget(c.dragonPreview, "border")
    c.dragonPreview._msuf2SearchText = "Runtime live portrait preview elite rare rareelite boss dragon gold silver"
    local function StopDragonPreview()
        if portraitElement and portraitElement.GetClassificationPreview(unit) then
            portraitElement.SetClassificationPreview(nil)
        end
    end
    sec:HookScript("OnHide", StopDragonPreview)
    if M.AddTooltip then
        M.AddTooltip(c.dragonPreview, "Runtime Preview",
            "Shows the selected dragon on this unit's visible portrait. Off restores the real classification. Ends when this area closes or combat starts.",
            { hook = true })
    end
    c.sizeMode = ControlRow(ctx, cards.geometry, { "segment", "sizeMode", "UNIFORM", { "Size mode", PORTRAIT_SIZE_MODES, min(360, w - 32) },
        { 16, -62, min(360, w - 32) },
        get = function()
            local conf = GetConf(unit)
            local mode = conf.portraitSizeMode
            if mode == "UNIFORM" or mode == "SEPARATE" then return mode end
            if (tonumber(conf.portraitSizeOverride) or 0) > 0 then return "UNIFORM" end
            return ((tonumber(conf.portraitWidth) or 0) > 0 or (tonumber(conf.portraitHeight) or 0) > 0)
                and "SEPARATE" or "UNIFORM"
        end,
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", write = {
                call = SetPortraitValue, args = { "MSUF2_PORTRAIT_SIZE_MODE" },
                convert = function(value) return value == "SEPARATE" and "SEPARATE" or "UNIFORM" end,
                after = p.Refresh
            } --[[schema setter: H4.UnitFrameVisuals.6]],
        scope = unit, meta = Meta("portrait.portraitSizeMode", tostring(unit) .. ".portraitSizeMode"),
    })
    TabTarget(c.sizeMode, "geometry", tostring(unit) .. ".portraitSizeMode")
    c.size = Slide(cards.geometry, "portraitSizeOverride", 0, "Size override", 0, 128, 1, -116, "MSUF2_PORTRAIT_SIZE")
    c.widthOverride = Slide(cards.geometry, "portraitWidth", 0, "Width override", 0, 256, 1, -170, "MSUF2_PORTRAIT_WIDTH")
    c.heightOverride = Slide(cards.geometry, "portraitHeight", 0, "Height override", 0, 256, 1, -224, "MSUF2_PORTRAIT_HEIGHT")
    c.zoom = Slide(cards.geometry, "portraitZoom", 100, "Portrait zoom", 100, 300, 1, -278, "MSUF2_PORTRAIT_ZOOM")
    c.panX = Slide(cards.geometry, "portraitPanX", 0, "Zoom center X", -100, 100, 1, -332, "MSUF2_PORTRAIT_PAN_X")
    c.panY = Slide(cards.geometry, "portraitPanY", 0, "Zoom center Y", -100, 100, 1, -386, "MSUF2_PORTRAIT_PAN_Y")
    p.StopDragonPreview = StopDragonPreview
end
-- Controls of the Placement, Class & Background, Border (rest) and Dragon tabs, in creation order.
function PortraitSection.MoreControls(p)
    local ctx, cards, c, Refresh = p.ctx, p.cards, p.c, p.Refresh
    local TabTarget, Drop, Slide, Toggle = p.TabTarget, p.Drop, p.Slide, p.Toggle
    c.placement = Drop(cards.placement, "portraitPlacement", "ATTACHED", "Placement", PORTRAIT_PLACEMENT.modes, -58, "MSUF2_PORTRAIT_PLACEMENT",
        { afterSet = Refresh, search = "Portrait placement attached detached overlay free position anchor" })
    c.detachedPoint = Drop(cards.placement, "portraitDetachedPoint", "RIGHT", "Portrait anchor point", PORTRAIT_PLACEMENT.points, -112,
        "MSUF2_PORTRAIT_DETACHED_POINT")
    c.detachedTo = Drop(cards.placement, "portraitDetachedTo", "LEFT", "Attach to frame point", PORTRAIT_PLACEMENT.points, -166,
        "MSUF2_PORTRAIT_DETACHED_TO")
    c.overlayAlign = Drop(cards.placement, "portraitOverlayAlign", "LEFT", "Overlay alignment", PORTRAIT_PLACEMENT.overlay, -220,
        "MSUF2_PORTRAIT_OVERLAY_ALIGN")
    c.levelOffset = Slide(cards.placement, "portraitLevelOffset", 7, "Layer offset", 0, 30, 1, -274, "MSUF2_PORTRAIT_LEVEL",
        { search = "Portrait layer offset frame level behind in front of bars" })
    c.portraitAlpha = Slide(cards.placement, "portraitAlpha", 100, "Portrait opacity", 0, 100, 1, -328, "MSUF2_PORTRAIT_ALPHA")
    c.classStyle = Drop(cards.style, "portraitClassStyle", "BLIZZARD", "Class portrait style", PortraitClassStyleValues, -58,
        "MSUF2_PORTRAIT_CLASS_STYLE", { normalize = NormalizePortraitClassStyle, search = "Class portrait style Blizzard Rondo Colored Rondo WoW" })
    c.border = Drop(cards.border, "portraitBorderStyle", "NONE", "Border", PORTRAIT_BORDERS, -376, "MSUF2_PORTRAIT_BORDER", { afterSet = Refresh })
    c.edgeSoftness = Slide(cards.border, "portraitEdgeSoftness", 0, "Portrait edge softness", 0, 30, 2, -430, "MSUF2_PORTRAIT_EDGE_SOFTNESS",
        { tab = "border", search = "Portrait edge softness feather fade borderless percent" })
    c.borderArt = Drop(cards.border, "portraitBorderArt", "FLAT", "Border art", PORTRAIT_PLACEMENT.borderArt, -484, "MSUF2_PORTRAIT_BORDER_ART",
        { afterSet = Refresh, search = "Portrait border art flat relief beveled ring blizzard style" })
    c.borderDirection = Drop(cards.border, "portraitBorderDirection", "UP", "Border direction", PORTRAIT_PLACEMENT.borderDirection, -538,
        "MSUF2_PORTRAIT_BORDER_DIRECTION", { search = "Portrait border direction rotate light up right down left" })
    c.borderSize = Slide(cards.border, "portraitBorderThickness", 2, "Border thickness", 1, 12, 1, -592, "MSUF2_PORTRAIT_BORDER_SIZE")
    c.fillBorder = Toggle(cards.border, "portraitFillBorder", false, "Fill border into frame gap", -660, "MSUF2_PORTRAIT_FILL_BORDER")
    c.portraitBg = Toggle(cards.style, "portraitBgEnabled", false, "Portrait background", -112, "MSUF2_PORTRAIT_BG")
    -- The Castbar section's Icon tab hosts a second toggle for this same key on
    -- every unit that has a castbar. Re-run the page refreshers so the twin
    -- surface picks up the new state instead of showing a stale checkbox.
    c.castSpellIcon = Toggle(cards.style, "portraitCastSpellIcon", false, "Show cast spell icon in portrait", -166, "MSUF2_PORTRAIT_CAST_ICON", {
        afterSet = CASTBAR_UNITS[p.unit] and function() M.RequestRefresh(ctx, "portrait-cast-icon-mirror") end or nil,
        search = "Portrait cast spell icon casting channel empower" })
    c.flip = Toggle(cards.style, "portraitFlip", false, "Flip portrait left to right", -220, "MSUF2_PORTRAIT_FLIP", { tab = "advanced" })
    c.shadow = Slide(cards.style, "portraitInnerShadow", 0, "Inset shadow strength", 0, 100, 1, -274, "MSUF2_PORTRAIT_SHADOW", { tab = "advanced" })
    c.dragonPreviewExtra = p.DragonPreview(cards.dragon, "dragonPreviewExtra", -58, ReviewedMeta(ctx, "portrait.classification_preview_dragon",
        "ephemeral", "excluded", "Temporary dragon preview while adjusting decoration geometry; no saved setting."),
        "portrait-dragon-preview")
    TabTarget(c.dragonPreviewExtra, "dragon")
    c.dragonPreview:HookScript("OnHide", p.StopDragonPreview)
    c.dragonPreviewExtra:HookScript("OnHide", p.StopDragonPreview)
    c.dragonArtwork = Toggle(cards.dragon, "portraitDragonArtwork", false, "Always show dragon artwork", -428, "MSUF2_DRAGON_ARTWORK",
        { afterSet = Refresh, tab = "dragon" })
    c.dragonControls = {
        Slide(cards.dragon, "portraitDragonScale", 100, "Dragon size", 25, 300, 1, -112, "MSUF2_DRAGON_SCALE", { tab = "dragon" }),
        Slide(cards.dragon, "portraitDragonX", 0, "Dragon horizontal shift", -200, 200, 1, -166, "MSUF2_DRAGON_X", { tab = "dragon" }),
        Slide(cards.dragon, "portraitDragonY", 0, "Dragon vertical shift", -200, 200, 1, -220, "MSUF2_DRAGON_Y", { tab = "dragon" }),
        Drop(cards.dragon, "portraitDragonLayer", "OVERLAY", "Dragon draw order", PORTRAIT_PLACEMENT.dragonLayer, -274, "MSUF2_DRAGON_LAYER",
            { tab = "dragon" }),
        Slide(cards.dragon, "portraitDragonLevel", 1, "Dragon level above portrait", 0, 30, 1, -328, "MSUF2_DRAGON_LEVEL", { tab = "dragon" }),
        Toggle(cards.dragon, "portraitDragonFlip", false, "Flip dragon left to right", -382, "MSUF2_DRAGON_FLIP", { tab = "dragon" }),
        Toggle(cards.dragon, "portraitDragonInInstances", true, "Keep enemy dragons in instances", -474, "MSUF2_DRAGON_INSTANCES", { tab = "dragon" }),
    }
    if M.AddTooltip then
        M.AddTooltip(c.shadow, "Inset shadow strength", "Darkens the inner edges of square portraits.", { hook = true })
        M.AddTooltip(c.dragonArtwork, "Always show dragon artwork",
            "Always displays the gold dragon as decoration, independent of the unit's classification.", { hook = true })
        M.AddTooltip(c.dragonControls[4], "Dragon draw order",
            "Places the dragon in front of or behind the art on the frame it shares: the portrait image at level 0, "
            .. "the gold ring at level 1. From level 2 on the dragon has a frame of its own above the ring.", { hook = true })
    end
end
function PortraitSection.Gates(p)
    local ctx, unit, sec, c, StopDragonPreview = p.ctx, p.unit, p.sec, p.c, p.StopDragonPreview
    local portraitActiveControls = {
        c.render, c.clickable, c.shape, c.sizeMode, c.size, c.widthOverride, c.heightOverride, c.edgeSoftness, c.portraitBg, c.castSpellIcon,
        c.placement, c.levelOffset, c.portraitAlpha,
    }
    local function PortraitActive() return NormalizePortrait(unit) ~= "OFF" end
    local function PortraitPlacementIs(conf, mode)
        return PortraitActive() and ((conf.portraitPlacement or "ATTACHED") == mode)
    end
    local function PortraitIs2D(conf)
        return PortraitActive() and ((conf.portraitRender or "2D") == "2D")
    end
    -- The Blizzard ring shape brings the stock gold ring with it, so every MSUF
    -- border control is inert while it is selected.
    local function PortraitShapeIsBlizzard(conf)
        return (conf.portraitShape or "SQUARE") == "BLIZZARD"
    end
    local function PortraitFillsBar(conf)
        return (conf.portraitPlacement or "ATTACHED") == "OVERLAY"
            and (conf.portraitOverlayAlign or "LEFT") == "FULL"
    end
    local function PortraitUsesSeparateSize(conf)
        local mode = conf.portraitSizeMode
        if mode == "SEPARATE" then return true end
        if mode == "UNIFORM" then return false end
        if (tonumber(conf.portraitSizeOverride) or 0) > 0 then return false end
        return (tonumber(conf.portraitWidth) or 0) > 0 or (tonumber(conf.portraitHeight) or 0) > 0
    end
    p.Refresh = p.Refresh(M.BindGateGroup(ctx, function() return GetConf(unit) end, {
        { enable = { c.portraitEnable } },
        { controls = portraitActiveControls, on = PortraitActive, reason = W.TurnOnReason and W.TurnOnReason("Portrait") },
        -- The Left/Right segment only steers the attached layout; detached and
        -- overlay portraits take their position from the Placement card instead.
        { controls = c.portrait, on = function(conf) return PortraitPlacementIs(conf, "ATTACHED") end },
        { controls = { c.detachedPoint, c.detachedTo }, on = function(conf) return PortraitPlacementIs(conf, "DETACHED") end },
        { controls = c.overlayAlign, on = function(conf) return PortraitPlacementIs(conf, "OVERLAY") end },
        -- Fill-bar geometry comes from the two bar anchors. Every other
        -- placement exposes one explicit mode: a uniform size or two axes.
        { controls = c.sizeMode, on = function(conf) return PortraitActive() and not PortraitFillsBar(conf) end },
        { controls = c.size, on = function(conf)
            return PortraitActive() and not PortraitFillsBar(conf) and not PortraitUsesSeparateSize(conf)
        end },
        { controls = { c.widthOverride, c.heightOverride }, on = function(conf)
            return PortraitActive()
                and not PortraitFillsBar(conf)
                and PortraitUsesSeparateSize(conf)
        end },
        { controls = { c.panX, c.panY }, on = PortraitIs2D },
        { controls = c.zoom, on = function(conf) return PortraitActive() and conf.portraitRender ~= "CLASS" end },
        { controls = c.flip, on = PortraitActive },
        { controls = c.shadow, on = function(conf) return PortraitActive() and (conf.portraitShape or "SQUARE") == "SQUARE" end },
        { controls = c.dragonArtwork, on = PortraitActive },
        { controls = c.dragonControls, on = function(conf)
            return PortraitActive() and (conf.portraitDragonArtwork == true
                or (PortraitShapeIsBlizzard(conf) and conf.portraitBlizzardElite == true))
        end },
        { controls = c.dragonControls[7], on = function(conf)
            return PortraitActive() and PortraitShapeIsBlizzard(conf)
                and conf.portraitBlizzardElite == true and conf.portraitDragonArtwork ~= true
        end },
        { controls = { c.eliteDragon, c.blizzardCorner, c.blizzardDirection },
            on = function(conf) return PortraitActive() and PortraitShapeIsBlizzard(conf) end },
        { controls = { c.dragonPreview, c.dragonPreviewExtra }, on = function(conf)
            local enabled = PortraitActive() and PortraitShapeIsBlizzard(conf)
                and conf.portraitBlizzardElite == true and conf.portraitDragonArtwork ~= true
            if not enabled then StopDragonPreview() end
            return enabled
        end },
        { controls = c.border, on = function(conf) return PortraitActive() and not PortraitShapeIsBlizzard(conf) end },
        { controls = c.edgeSoftness, on = function(conf)
            return PortraitActive()
                and not PortraitShapeIsBlizzard(conf)
                and ((conf.portraitBorderStyle or "NONE") == "NONE")
        end },
        { controls = { c.borderSize, c.borderArt }, on = function(conf)
            return PortraitActive()
                and ((conf.portraitBorderStyle or "NONE") ~= "NONE")
                and not PortraitShapeIsBlizzard(conf)
        end },
        -- Direction rotates the relief art's light; the flat renderers have no
        -- orientation to speak of.
        { controls = c.borderDirection, on = function(conf)
            return PortraitActive()
                and ((conf.portraitBorderStyle or "NONE") ~= "NONE")
                and ((conf.portraitBorderArt or "FLAT") == "RELIEF")
                and not PortraitShapeIsBlizzard(conf)
        end },
        -- Fill-into-the-gap squares off the four straight edges; shaped portraits
        -- render a ring that follows the silhouette and relief art replaces both.
        { controls = c.fillBorder, on = function(conf)
            return PortraitActive()
                and ((conf.portraitBorderStyle or "NONE") ~= "NONE")
                and ((conf.portraitShape or "SQUARE") == "SQUARE")
                and ((conf.portraitBorderArt or "FLAT") ~= "RELIEF")
        end },
        { controls = c.classStyle, on = function(conf) return PortraitActive() and ((conf.portraitRender or "2D") == "CLASS") end },
    }, {
        also = function() SetSectionHeaderStatus(sec, nil) end,
        track = function(gateCtx, r) return M.TrackCollapsibleRefresh(gateCtx, sec, r) end,
    }))
end
local function BuildPortrait(ctx, builder, unit)
    local layout = PortraitLayoutForWidth((ctx and ctx.width) or 720, CurrentPortraitTab(unit))
    local sec = builder:CollapsibleSection("portrait", "Portrait", layout.height, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local p = { ctx = ctx, unit = unit, sec = sec, sectionW = sectionW, c = {}, Refresh = M.RefreshProxy(),
        layout = PortraitLayoutForWidth(sectionW, CurrentPortraitTab(unit)) }
    M._msuf2LastPortraitSide = M._msuf2LastPortraitSide or {}
    PortraitSection.Shell(p)
    PortraitSection.Factories(p)
    PortraitSection.Controls(p)
    PortraitSection.MoreControls(p)
    PortraitSection.Gates(p)
end

return BuildPortrait, PreparePortraitSwitch, PortraitLayoutForWidth, CurrentPortraitTab
end
