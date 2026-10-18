local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
-- Core functions this page calls by their global names: required here at
-- load, called through _G so a hook installed on one later still applies.
M.RequireGlobals("Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", {
    "MSUF_SuppressBlizzardPlayerCastbars",
    "MSUF_ShowReloadRecommendedPopup",
})

-- Menu2 Unit visual sections.
-- Builds controls for portrait, castbar detail, detached power, border/shape, and related
-- frame visuals. It writes through UnitPage helpers and delegates live refresh to runtimes.
local W = M.Widgets or {}
local Schema = M.ControlSchema
-- Unit rows retain the existing typed binding owners, including their refusal,
-- history and normalization policies. Accessors resolve the live profile on input.
local ROW_OPTIONS = Schema.UnitOptions()
local function ControlRow(ctx, parent, row)
    return Schema.Build(ctx, parent, { row }, ROW_OPTIONS)[row[2]]
end
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua")
local UP = M.UnitPage or {}
local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList
local POWER_UNITS, CASTBAR_FIELDS, PORTRAIT_RENDER = UP.POWER_UNITS or {}, UP.CASTBAR_FIELDS or {}, UP.PORTRAIT_RENDER or {}
local PORTRAIT_SHAPES, PORTRAIT_BORDERS = UP.PORTRAIT_SHAPES or {}, UP.PORTRAIT_BORDERS or {}
local GetConf, GetGeneral, GetBars, UnitTopLabel, ReadBool = UP.GetConf, UP.GetGeneral, UP.GetBars, UP.UnitTopLabel, UP.ReadBool
local SetBool, ReadNumber, SetNumber, ReadGeneralBool, SetGeneralBool = UP.SetBool, UP.ReadNumber, UP.SetNumber, UP.ReadGeneralBool, UP.SetGeneralBool
local NormalizePortrait, SetPortraitValue = UP.NormalizePortrait, UP.SetPortraitValue
local IsPlayerPowerManagedByClassResources, ControlMeta, SettingMeta = UP.IsPlayerPowerManagedByClassResources, UP.ControlMeta, UP.SettingMeta
local ReviewedMeta, RegisterControl = UP.ReviewedMeta, UP.RegisterControl
local CASTBAR_BACKEND_VALUES = VT("MSUF", "MSUF castbar", "BLIZZARD", "Blizzard castbar")
local CASTBAR_PREFIX = { player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus", boss = "bossCast", arena = "arenaCast" }
local CASTBAR_UNITS = M.KeySetFromWords "player target focus boss arena"
-- Castbar width and height an unset key reads as: the values the defaults
-- pass seeds (State/Defaults/MSUF_Defaults_Bars.lua). One table for the
-- sliders, their reset values and the spell text width.
local CASTBAR_DEFAULT_SIZE = {
    player = { width = 271, height = 18 }, target = { width = 272, height = 18 },
    focus = { width = 175, height = 18 }, boss = { width = 176, height = 12 }, arena = { width = 176, height = 12 },
}
local CASTBAR_ICON_POSITIONS = VT("LEFT", "Left", "RIGHT", "Right", "INSIDE_LEFT", "Inside Left", "INSIDE_RIGHT", "Inside Right")
local CASTBAR_TEXT_POSITIONS = VT("LEFT", "Left", "CENTER", "Center", "RIGHT", "Right", "ABOVE", "Above", "BELOW", "Below")
local CASTBAR_TIME_FORMATS = VT("CURRENT", "Remaining", "ELAPSED", "Elapsed", "ELAPSED_MAX", "Elapsed / Total", "CURRENT_MAX", "Remaining / Total")
local CASTBAR_TAB_VALUES = VT("general", "General", "icon", "Icon", "spell", "Spell Text", "time", "Time Text", "advanced", "Advanced")
--- The thickness slider owns on/off (0 hides the border); this picks how the
--- visible border is painted. "Castbar border color" is the only value the
--- Castbar Icon Border Color shortcut applies to.
local CASTBAR_ICON_BORDER_STYLES = VT("NONE", "None", "DARK", "Dark", "CASTBAR", "Castbar border color")
-- general grew by 32px when "Show interrupter name" pushed the Size card down.
local CASTBAR_TAB_HEIGHTS = { general = 424, icon = 540, spell = 386, time = 386, advanced = 480 }
local CASTBAR_WIDTH_SOURCE_VALUES = VT("manual", "Manual width", "unitframe", "Auto: Unit Frame", "essential", "Auto: Essential Cooldowns", "utility",
    "Auto: Utility Cooldowns")
local CASTBAR_TEXT_ALIGN = VT("LEFT", "Left", "CENTER", "Center", "RIGHT", "Right")
local CASTBAR_TRUNCATE_VALUES = VT("AUTO", "Auto fit", "CLIP", "Manual width", "NONE", "No width limit")
local DETACHED_POWER_SHAPE_VALUES = VT("BAR", "Bar", "ROUND", "Round", "CRYSTAL", "Crystal", "ORB", "Orb")
local PLAYER_POWER_SOURCE_VALUES = M.PlayerPowerSourceValues
local NormalizePlayerPowerSource = M.NormalizePlayerPowerSource
-- Portrait placement value lists. Kept in one table instead of one file local
-- per list.
local PORTRAIT_PLACEMENT = {
    dragonLayer = VT("BACKGROUND", "Background", "BORDER", "Border", "ARTWORK", "Artwork", "OVERLAY", "Overlay"),
    classificationPreview = VT("OFF", "Off", "elite", "Elite (gold)", "rare", "Rare (silver)",
        "rareelite", "Rare elite (silver)", "worldboss", "Boss (winged gold)"),
    modes = VT("ATTACHED", "Attached to bar", "DETACHED", "Detached", "OVERLAY", "Overlay on bar"),
    points = VT(
        "TOPLEFT", "Top left", "TOP", "Top", "TOPRIGHT", "Top right",
        "LEFT", "Left", "CENTER", "Center", "RIGHT", "Right",
        "BOTTOMLEFT", "Bottom left", "BOTTOM", "Bottom", "BOTTOMRIGHT", "Bottom right"),
    overlay = VT("LEFT", "Left", "CENTER", "Center", "RIGHT", "Right", "FULL", "Fill bar"),
    borderArt = VT("FLAT", "Flat", "RELIEF", "Relief"),
    borderDirection = VT("UP", "Up", "RIGHT", "Right", "DOWN", "Down", "LEFT", "Left"),
}
local PORTRAIT_SIZE_MODES = VT("UNIFORM", "Uniform", "SEPARATE", "Width & height")
local UnitSectionShared = M.UnitSectionsShared or {}
local SetSectionHeaderStatus = UnitSectionShared.SetSectionHeaderStatus
local CreateSectionNotice = UnitSectionShared.CreateSectionNotice
-- Power Bar section card geometry. Player gets one extra resource-source row;
-- BuildPower and PowerSectionHeight share these helpers so the detached card
-- always follows the first row without overlap.
local function PowerMainCardHeight(unit) return unit == "player" and 284 or 220 end
local function PowerDetachedCardTop(unit) return -38 - PowerMainCardHeight(unit) - 26 end
local function PowerSectionHeight(unit)
    local isPlayer = unit == "player"
    return math.abs(PowerDetachedCardTop(unit)) + (isPlayer and 340 or 238) + 52
end
local function NormalizeCastbarTabKey(key)
    if key ~= "general" and key ~= "icon" and key ~= "spell" and key ~= "time" and key ~= "advanced" then key = "general" end
    return key
end
local function CastbarTabHeight(unit, tab)
    tab = NormalizeCastbarTabKey(tab)
    return CASTBAR_TAB_HEIGHTS[tab] or CASTBAR_TAB_HEIGHTS.general
end
local function CurrentCastbarTab(unit)
    if unit == nil then return "general" end
    M.unitCastbarTabSelection = M.unitCastbarTabSelection or {}
    local key = NormalizeCastbarTabKey(M.unitCastbarTabSelection[unit])
    M.unitCastbarTabSelection[unit] = key
    return key
end
local function RefreshClassPowerDetachedState()
    -- Detached player power is influenced by both unitframe and class-resource controls, so
    -- ask the ClassPower page/runtime to recompute enabled state after relevant edits.
    if type(M.RefreshClassPowerDetachedState) == "function" then M.RefreshClassPowerDetachedState() end
end
local NormalizeDetachedPowerShape = _G.MSUF_UF_NormalizeDetachedPowerShape
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
local function NormalizePortraitTabKey(key)
    if key ~= "general" and key ~= "geometry" and key ~= "placement" and key ~= "border" and key ~= "advanced" and key ~= "dragon" then
        key = "general"
    end
    return key
end
local function CurrentPortraitTab(unit)
    if unit == nil then return "general" end
    M.unitPortraitTabSelection = M.unitPortraitTabSelection or {}
    local key = NormalizePortraitTabKey(M.unitPortraitTabSelection[unit])
    M.unitPortraitTabSelection[unit] = key
    return key
end
local function PortraitTabHeight(tab)
    return PORTRAIT_TAB_HEIGHTS[NormalizePortraitTabKey(tab)] or PORTRAIT_TAB_HEIGHTS.general
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
        set = function(v)
            if v then
                SetPortraitValue(unit, "portraitMode", M._msuf2LastPortraitSide[unit] or "LEFT", "MSUF2_PORTRAIT_MODE")
            else
                local mode = NormalizePortrait(unit)
                if mode == "LEFT" or mode == "RIGHT" then M._msuf2LastPortraitSide[unit] = mode end
                SetPortraitValue(unit, "portraitMode", "OFF", "MSUF2_PORTRAIT_MODE")
            end
            if portraitEnable.refreshDetails then portraitEnable.refreshDetails() end
        end,
        scope = unit, meta = ReviewedMeta(ctx, "portrait.enabled", "setting", "compound",
            "Portrait is a boolean shortcut over the OFF/LEFT/RIGHT portraitMode enum and restores the remembered side when enabled."),
    })
    portraitEnable:SetChecked(NormalizePortrait(unit) ~= "OFF")
    return portraitEnable
end
local function PreparePortraitTabTarget(sec, widget, tab, settingKey)
    if not widget then return end
    widget._msuf2ExactTargetKinds = { unitPortraitTab = true }
    widget._msuf2ExactTargetContracts = {
        unitPortraitTab = { [tab] = tostring(settingKey or "") },
    }
    widget._msuf2PrepareExactSearchTarget = function(_, exactTarget)
        if type(exactTarget) ~= "table" or exactTarget.prepareKind ~= "unitPortraitTab"
            or tostring(exactTarget.prepareValue or "") ~= tab
        then
            return false
        end
        return sec._msuf2GuidedSelectTab and sec._msuf2GuidedSelectTab(tab) == true
    end
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
    M.BindSegment(ctx, pad,
        function() return MSUF.PortraitDetails.NormalizeBlizzardDirection(GetConf(unit).portraitBlizzardDirection) end,
        function(value) SetPortraitValue(unit, "portraitBlizzardDirection", value, "MSUF2_PORTRAIT_BLIZZARD_DIRECTION") end,
        metadata)
    Schema.Owned(pad, unit, "portrait")
    return pad
end

local function BuildPortrait(ctx, builder, unit)
    local layout = PortraitLayoutForWidth((ctx and ctx.width) or 720, CurrentPortraitTab(unit))
    local sec = builder:CollapsibleSection("portrait", "Portrait", layout.height, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    layout = PortraitLayoutForWidth(sectionW, CurrentPortraitTab(unit))
    local leftX, rightX = layout.cardX, layout.cardX
    local leftW, rightW = layout.cardW, layout.cardW
    local RefreshPortraitControls = M.RefreshProxy()
    local function PortraitControlMeta(path, settingKey)
        local meta = ControlMeta(ctx, path)
        meta.settingKey = settingKey
        return meta
    end
    local function PortraitRow(parent, row)
        local kind, key, fallback = row[1], row[2], row[3]
        row.get = function()
            if kind == "toggle" then return ReadBool(unit, key, fallback) end
            if kind == "slider" then return ReadNumber(unit, key, fallback) end
            local value = GetConf(unit)[key]
            value = value == nil and fallback or value
            return row.normalize and row.normalize(value) or value
        end
        row.set = function(value)
            if kind == "slider" then SetNumber(unit, key, value, row.reason, { preview = true })
            else
                if kind == "toggle" then value = value and true or false
                else value = row.normalize and row.normalize(value or fallback) or (value or fallback) end
                SetPortraitValue(unit, key, value, row.reason)
            end
            if row.afterSet then row.afterSet() end
        end
        row.meta = PortraitControlMeta("portrait." .. tostring(key), tostring(unit) .. "." .. tostring(key))
        row.scope, row.roundStep = unit, kind == "slider"
        return ControlRow(ctx, parent, row)
    end
    M._msuf2LastPortraitSide = M._msuf2LastPortraitSide or {}
    local function SetPortraitSectionHeight(height)
        height = max(120, floor((tonumber(height) or PORTRAIT_TAB_HEIGHTS.general) + 0.5))
        local entry = sec and sec._msuf2CollapsibleEntry
        if sec and sec.SetHeight then sec:SetHeight(height) end
        if entry then
            local changed = entry.contentHeight ~= height
            entry.contentHeight = height
            if entry.body and entry.body.SetHeight then entry.body:SetHeight(height) end
            if entry.outer and entry.outer.SetHeight then entry.outer:SetHeight((entry.headerHeight or 28) + (entry.open and height or 0)) end
            if changed and entry.builder and entry.builder.RelayoutCollapsibles then entry.builder:RelayoutCollapsibles() end
        end
    end
    local tabFrames = {}
    local generalTab, geometryTab, placementTab, borderTab, advancedTab, dragonTab =
        UnitSectionShared.MakeTabFrames(sec, -64, sectionW, tabFrames, "general", "geometry", "placement", "border", "advanced", "dragon")
    local mainCard = ControlRow(ctx, generalTab, { "card", "menu2.uf_" .. unit .. ".portrait.mainCard", nil,
        { "Visibility & Mode", nil, leftX, -4, leftW, PORTRAIT_CARD_H.main, "group" }, scope = unit, domain = "layout" })
    local geometryCard = ControlRow(ctx, geometryTab, { "card", "menu2.uf_" .. unit .. ".portrait.geometryCard", nil,
        { "Geometry", nil, rightX, -4, rightW, PORTRAIT_CARD_H.geometry, "group" }, scope = unit, domain = "layout" })
    local placementCard = ControlRow(ctx, placementTab, { "card", "menu2.uf_" .. unit .. ".portrait.placementCard", nil,
        { "Placement", nil, leftX, -4, leftW, PORTRAIT_CARD_H.placement, "group" }, scope = unit, domain = "layout" })
    local borderCard = ControlRow(ctx, borderTab, { "card", "menu2.uf_" .. unit .. ".portrait.borderCard", nil,
        { "Shape & Border", nil, leftX, -4, leftW, PORTRAIT_CARD_H.border, "group" }, scope = unit, domain = "layout" })
    local styleCard = ControlRow(ctx, advancedTab, { "card", "menu2.uf_" .. unit .. ".portrait.styleCard", nil,
        { "Class & Background", nil, rightX, -4, rightW, PORTRAIT_CARD_H.style, "group" }, scope = unit, domain = "layout" })
    local dragonCard = ControlRow(ctx, dragonTab, { "card", "menu2.uf_" .. unit .. ".portrait.dragonCard", nil,
        { "Dragon decoration", nil, leftX, -4, leftW, PORTRAIT_CARD_H.dragon, "group" }, scope = unit, domain = "layout" })
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(borderCard, { "portrait.border" }, {
            title = "Portrait Border Color",
            note = "Configure the color used by the Solid and Custom portrait border styles.",
            historySource = "menu:unit-portrait-border-color",
        })
        W.AttachContextColorReferences(styleCard, { "portrait.background" }, {
            title = "Portrait Background Color",
            note = "Configure the optional portrait background color.",
            historySource = "menu:unit-portrait-background-color",
        })
    end
    local portraitTabs, RefreshPortraitTabs, ReadPortraitTab, SetGuidedPortraitTab = W.SegmentTabs(ctx, sec, {
        label = "",
        values = PortraitTabValues(sectionW),
        width = layout.tabW,
        frames = tabFrames,
        defaultTab = "general",
        get = function() return CurrentPortraitTab(unit) end,
        set = function(v)
            M.unitPortraitTabSelection = M.unitPortraitTabSelection or {}
            M.unitPortraitTabSelection[unit] = NormalizePortraitTabKey(v)
        end,
        afterRefresh = function(tab) SetPortraitSectionHeight(PortraitTabHeight(tab)) end,
        x = 20,
        y = -12,
    })
    if portraitTabs._msuf2Title then portraitTabs._msuf2Title:Hide() end
    RegisterControl(portraitTabs, ctx, "portrait.workspace_tab", "Portrait area", "segment", "ephemeral")
    Schema.Owned(portraitTabs, unit, "sectionNavigation")
    sec._msuf2GuidedSelectTab = function(tab)
        tab = NormalizePortraitTabKey(tab)
        if type(ReadPortraitTab) == "function" and ReadPortraitTab() == tab then return true end
        if type(SetGuidedPortraitTab) == "function" then
            SetGuidedPortraitTab(tab)
        else
            M.unitPortraitTabSelection = M.unitPortraitTabSelection or {}
            M.unitPortraitTabSelection[unit] = tab
            if type(RefreshPortraitTabs) == "function" then RefreshPortraitTabs() end
        end
        return type(ReadPortraitTab) ~= "function" or ReadPortraitTab() == tab
    end
    local function BindExactPortraitTabTarget(widget, tab, settingKey)
        PreparePortraitTabTarget(sec, widget, tab, settingKey)
    end
    local portraitEnable = PreparePortraitSwitch(ctx, sec, unit)
    portraitEnable.refreshDetails = function() RefreshPortraitControls() end
    local portrait = ControlRow(ctx, mainCard, { "segment", "portrait", "LEFT", { "Position", VT("LEFT", "Left", "RIGHT", "Right"), min(220,
        rightW) }, { 16, -62, min(220, leftW - 32) },
        get = function()
            local mode = NormalizePortrait(unit)
            return mode == "RIGHT" and "RIGHT" or "LEFT"
        end,
        set = function(v)
            M._msuf2LastPortraitSide[unit] = v == "RIGHT" and "RIGHT" or "LEFT"
            SetPortraitValue(unit, "portraitMode", v or "LEFT", "MSUF2_PORTRAIT_MODE")
            RefreshPortraitControls()
        end,
        scope = unit, meta = PortraitControlMeta("portrait.position", tostring(unit) .. ".portraitMode"),
    })
    local render = PortraitRow(mainCard, { "dropdown", "portraitRender", "2D", { "Render", PORTRAIT_RENDER, 220 }, { 16, -116, min(220,
        leftW - 32) }, reason = "MSUF2_PORTRAIT_RENDER", afterSet = RefreshPortraitControls })
    local clickable = PortraitRow(mainCard, { "toggle", "portraitClickable", false, { "Clickable portrait", 16, -174, leftW - 32 },
        reason = "MSUF2_PORTRAIT_CLICKABLE" })
    clickable._msuf2SearchText = "Clickable portrait unit frame target right click menu click casting mouseover"
    BindExactPortraitTabTarget(clickable, "general", tostring(unit) .. ".portraitClickable")
    local shape = PortraitRow(borderCard, { "dropdown", "portraitShape", "SQUARE", { "Shape", PORTRAIT_SHAPES, 220 }, { 16, -58, min(220,
        leftW - 32) }, reason = "MSUF2_PORTRAIT_SHAPE", afterSet = RefreshPortraitControls })
    local eliteDragon = PortraitRow(borderCard, { "toggle", "portraitBlizzardElite", false, { "Elite and rare dragon", 16, -112, leftW - 32 },
        reason = "MSUF2_PORTRAIT_BLIZZARD_ELITE", afterSet = RefreshPortraitControls })
    eliteDragon._msuf2SearchText = "Blizzard portrait ring elite rare rareelite boss gold silver dragon classification"
    BindExactPortraitTabTarget(eliteDragon, "border", tostring(unit) .. ".portraitBlizzardElite")
    local blizzardCorner = PortraitRow(borderCard, { "toggle", "portraitBlizzardCorner", false, { "Gold corner connector", 16, -148, leftW - 32 },
        reason = "MSUF2_PORTRAIT_BLIZZARD_CORNER", afterSet = RefreshPortraitControls })
    blizzardCorner._msuf2SearchText = "Blizzard portrait frame gold corner triangle connector embellishment Forever"
    BindExactPortraitTabTarget(blizzardCorner, "border", tostring(unit) .. ".portraitBlizzardCorner")
    local blizzardDirection = BuildPortraitDirection(ctx, borderCard, unit, leftW,
        PortraitControlMeta("portrait.portraitBlizzardDirection", tostring(unit) .. ".portraitBlizzardDirection"))
    BindExactPortraitTabTarget(blizzardDirection, "border", tostring(unit) .. ".portraitBlizzardDirection")
    local portraitElement = MSUF.UF and MSUF.UF.elements and MSUF.UF.elements.Portrait
    local dragonPreview = ControlRow(ctx, borderCard, { "dropdown", "dragonPreview", "OFF", { "Runtime Preview",
        PORTRAIT_PLACEMENT.classificationPreview, 220 }, { 16, -322, min(280, leftW - 32) },
        get = function() return portraitElement and portraitElement.GetClassificationPreview(unit) or "OFF" end,
        set = function(value)
            if portraitElement then portraitElement.SetClassificationPreview(unit, value) end
        end,
        scope = unit, meta = ReviewedMeta(ctx, "portrait.classification_preview", "ephemeral", "excluded",
            "Temporary classification art on the live portrait; no saved setting."),
    })
    BindExactPortraitTabTarget(dragonPreview, "border")
    dragonPreview._msuf2SearchText = "Runtime live portrait preview elite rare rareelite boss dragon gold silver"
    local function StopDragonPreview()
        if portraitElement and portraitElement.GetClassificationPreview(unit) then
            portraitElement.SetClassificationPreview(nil)
        end
    end
    sec:HookScript("OnHide", StopDragonPreview)
    if M.AddTooltip then
        M.AddTooltip(dragonPreview, "Runtime Preview",
            "Shows the selected dragon on this unit's visible portrait. Off restores the real classification. Ends when this area closes or combat starts.",
            { hook = true })
    end
    local sizeMode = ControlRow(ctx, geometryCard, { "segment", "sizeMode", "UNIFORM", { "Size mode", PORTRAIT_SIZE_MODES, min(360,
        rightW - 32) }, { 16, -62, min(360, rightW - 32) },
        get = function()
            local conf = GetConf(unit)
            local mode = conf.portraitSizeMode
            if mode == "UNIFORM" or mode == "SEPARATE" then return mode end
            if (tonumber(conf.portraitSizeOverride) or 0) > 0 then return "UNIFORM" end
            return ((tonumber(conf.portraitWidth) or 0) > 0 or (tonumber(conf.portraitHeight) or 0) > 0)
                and "SEPARATE" or "UNIFORM"
        end,
        set = function(value)
            value = value == "SEPARATE" and "SEPARATE" or "UNIFORM"
            SetPortraitValue(unit, "portraitSizeMode", value, "MSUF2_PORTRAIT_SIZE_MODE")
            RefreshPortraitControls()
        end,
        scope = unit, meta = PortraitControlMeta("portrait.portraitSizeMode", tostring(unit) .. ".portraitSizeMode"),
    })
    BindExactPortraitTabTarget(sizeMode, "geometry", tostring(unit) .. ".portraitSizeMode")
    local size = PortraitRow(geometryCard, { "slider", "portraitSizeOverride", 0, { "Size override", 0, 128, 1, 280 }, { 16, -116, rightW - 58,
        "CENTER" }, reason = "MSUF2_PORTRAIT_SIZE" })
    local widthOverride = PortraitRow(geometryCard, { "slider", "portraitWidth", 0, { "Width override", 0, 256, 1, 280 }, { 16, -170, rightW - 58,
        "CENTER" }, reason = "MSUF2_PORTRAIT_WIDTH" })
    local heightOverride = PortraitRow(geometryCard, { "slider", "portraitHeight", 0, { "Height override", 0, 256, 1, 280 }, { 16, -224,
        rightW - 58, "CENTER" }, reason = "MSUF2_PORTRAIT_HEIGHT" })
    local zoom = PortraitRow(geometryCard, { "slider", "portraitZoom", 100, { "Portrait zoom", 100, 300, 1, 280 }, { 16, -278, rightW - 58,
        "CENTER" }, reason = "MSUF2_PORTRAIT_ZOOM" })
    local panX = PortraitRow(geometryCard, { "slider", "portraitPanX", 0, { "Zoom center X", -100, 100, 1, 280 }, { 16, -332, rightW - 58,
        "CENTER" }, reason = "MSUF2_PORTRAIT_PAN_X" })
    local panY = PortraitRow(geometryCard, { "slider", "portraitPanY", 0, { "Zoom center Y", -100, 100, 1, 280 }, { 16, -386, rightW - 58,
        "CENTER" }, reason = "MSUF2_PORTRAIT_PAN_Y" })
    local placement = PortraitRow(placementCard, { "dropdown", "portraitPlacement", "ATTACHED", { "Placement", PORTRAIT_PLACEMENT.modes, 220 },
        { 16, -58, min(220, leftW - 32) }, reason = "MSUF2_PORTRAIT_PLACEMENT", afterSet = RefreshPortraitControls })
    placement._msuf2SearchText = "Portrait placement attached detached overlay free position anchor"
    local detachedPoint = PortraitRow(placementCard, { "dropdown", "portraitDetachedPoint", "RIGHT", { "Portrait anchor point",
        PORTRAIT_PLACEMENT.points, 220 }, { 16, -112, min(220, leftW - 32) }, reason = "MSUF2_PORTRAIT_DETACHED_POINT" })
    local detachedTo = PortraitRow(placementCard, { "dropdown", "portraitDetachedTo", "LEFT", { "Attach to frame point", PORTRAIT_PLACEMENT.points,
        220 }, { 16, -166, min(220, leftW - 32) }, reason = "MSUF2_PORTRAIT_DETACHED_TO" })
    local overlayAlign = PortraitRow(placementCard, { "dropdown", "portraitOverlayAlign", "LEFT", { "Overlay alignment", PORTRAIT_PLACEMENT.overlay,
        220 }, { 16, -220, min(220, leftW - 32) }, reason = "MSUF2_PORTRAIT_OVERLAY_ALIGN" })
    local levelOffset = PortraitRow(placementCard, { "slider", "portraitLevelOffset", 7, { "Layer offset", 0, 30, 1, 280 }, { 16, -274, leftW - 58,
        "CENTER" }, reason = "MSUF2_PORTRAIT_LEVEL" })
    levelOffset._msuf2SearchText = "Portrait layer offset frame level behind in front of bars"
    local portraitAlpha = PortraitRow(placementCard, { "slider", "portraitAlpha", 100, { "Portrait opacity", 0, 100, 1, 280 }, { 16, -328,
        leftW - 58, "CENTER" }, reason = "MSUF2_PORTRAIT_ALPHA" })
    local classStyle = PortraitRow(styleCard, { "dropdown", "portraitClassStyle", "BLIZZARD", { "Class portrait style", PortraitClassStyleValues,
        220 }, { 16, -58, min(220, rightW - 32) }, reason = "MSUF2_PORTRAIT_CLASS_STYLE", normalize = NormalizePortraitClassStyle })
    classStyle._msuf2SearchText = "Class portrait style Blizzard Rondo Colored Rondo WoW"
    local border = PortraitRow(borderCard, { "dropdown", "portraitBorderStyle", "NONE", { "Border", PORTRAIT_BORDERS, 220 }, { 16, -376, min(220,
        leftW - 32) }, reason = "MSUF2_PORTRAIT_BORDER", afterSet = RefreshPortraitControls })
    local edgeSoftness = PortraitRow(borderCard, { "slider", "portraitEdgeSoftness", 0, { "Portrait edge softness", 0, 30, 2, 280 }, { 16, -430,
        leftW - 58, "CENTER" }, reason = "MSUF2_PORTRAIT_EDGE_SOFTNESS" })
    BindExactPortraitTabTarget(edgeSoftness, "border", tostring(unit) .. ".portraitEdgeSoftness")
    edgeSoftness._msuf2SearchText = "Portrait edge softness feather fade borderless percent"
    local borderArt = PortraitRow(borderCard, { "dropdown", "portraitBorderArt", "FLAT", { "Border art", PORTRAIT_PLACEMENT.borderArt, 220 }, { 16,
        -484, min(220, leftW - 32) }, reason = "MSUF2_PORTRAIT_BORDER_ART", afterSet = RefreshPortraitControls })
    borderArt._msuf2SearchText = "Portrait border art flat relief beveled ring blizzard style"
    local borderDirection = PortraitRow(borderCard, { "dropdown", "portraitBorderDirection", "UP", { "Border direction",
        PORTRAIT_PLACEMENT.borderDirection, 220 }, { 16, -538, min(220, leftW - 32) }, reason = "MSUF2_PORTRAIT_BORDER_DIRECTION" })
    borderDirection._msuf2SearchText = "Portrait border direction rotate light up right down left"
    local borderSize = PortraitRow(borderCard, { "slider", "portraitBorderThickness", 2, { "Border thickness", 1, 12, 1, 280 }, { 16, -592,
        leftW - 58, "CENTER" }, reason = "MSUF2_PORTRAIT_BORDER_SIZE" })
    local fillBorder = PortraitRow(borderCard, { "toggle", "portraitFillBorder", false, { "Fill border into frame gap", 16, -660, leftW - 32 },
        reason = "MSUF2_PORTRAIT_FILL_BORDER" })
    local portraitBg = PortraitRow(styleCard, { "toggle", "portraitBgEnabled", false, { "Portrait background", 16, -112, rightW - 32 },
        reason = "MSUF2_PORTRAIT_BG" })
    -- The Castbar section's Icon tab hosts a second toggle for this same key on
    -- every unit that has a castbar. Re-run the page refreshers so the twin
    -- surface picks up the new state instead of showing a stale checkbox.
    local castSpellIcon = PortraitRow(styleCard, { "toggle", "portraitCastSpellIcon", false, { "Show cast spell icon in portrait", 16, -166,
        rightW - 32 }, reason = "MSUF2_PORTRAIT_CAST_ICON", afterSet = CASTBAR_UNITS[unit] and function() M.RequestRefresh(ctx,
        "portrait-cast-icon-mirror") end or nil })
    castSpellIcon._msuf2SearchText = "Portrait cast spell icon casting channel empower"
    local flip = PortraitRow(styleCard, { "toggle", "portraitFlip", false, { "Flip portrait left to right", 16, -220, rightW - 32 },
        reason = "MSUF2_PORTRAIT_FLIP" })
    local shadow = PortraitRow(styleCard, { "slider", "portraitInnerShadow", 0, { "Inset shadow strength", 0, 100, 1, 280 }, { 16, -274,
        rightW - 58, "CENTER" }, reason = "MSUF2_PORTRAIT_SHADOW" })
    local dragonPreviewExtra = ControlRow(ctx, dragonCard, { "dropdown", "dragonPreviewExtra", "OFF", { "Runtime Preview",
        PORTRAIT_PLACEMENT.classificationPreview, 220 }, { 16, -58, min(280, leftW - 32) },
        get = function() return portraitElement and portraitElement.GetClassificationPreview(unit) or "OFF" end,
        set = function(value)
            if portraitElement then portraitElement.SetClassificationPreview(unit, value) end
            M.RequestRefresh(ctx, "portrait-dragon-preview")
        end,
        scope = unit, meta = ReviewedMeta(ctx, "portrait.classification_preview_dragon", "ephemeral", "excluded",
            "Temporary dragon preview while adjusting decoration geometry; no saved setting."),
    })
    BindExactPortraitTabTarget(dragonPreviewExtra, "dragon")
    dragonPreview:HookScript("OnHide", StopDragonPreview)
    dragonPreviewExtra:HookScript("OnHide", StopDragonPreview)
    local dragonArtwork = PortraitRow(dragonCard, { "toggle", "portraitDragonArtwork", false, { "Always show dragon artwork", 16, -428,
        leftW - 32 }, reason = "MSUF2_DRAGON_ARTWORK", afterSet = RefreshPortraitControls })
    BindExactPortraitTabTarget(dragonArtwork, "dragon", tostring(unit) .. ".portraitDragonArtwork")
    local dragonControls = {
        PortraitRow(dragonCard, { "slider", "portraitDragonScale", 100, { "Dragon size", 25, 300, 1, 280 }, { 16, -112, leftW - 58, "CENTER" },
            reason = "MSUF2_DRAGON_SCALE" }),
        PortraitRow(dragonCard, { "slider", "portraitDragonX", 0, { "Dragon horizontal shift", -200, 200, 1, 280 }, { 16, -166, leftW - 58,
            "CENTER" }, reason = "MSUF2_DRAGON_X" }),
        PortraitRow(dragonCard, { "slider", "portraitDragonY", 0, { "Dragon vertical shift", -200, 200, 1, 280 }, { 16, -220, leftW - 58,
            "CENTER" }, reason = "MSUF2_DRAGON_Y" }),
        PortraitRow(dragonCard, { "dropdown", "portraitDragonLayer", "OVERLAY", { "Dragon draw order", PORTRAIT_PLACEMENT.dragonLayer, 220 }, { 16,
            -274, min(220, leftW - 32) }, reason = "MSUF2_DRAGON_LAYER" }),
        PortraitRow(dragonCard, { "slider", "portraitDragonLevel", 1, { "Dragon level above portrait", 0, 30, 1, 280 }, { 16, -328, leftW - 58,
            "CENTER" }, reason = "MSUF2_DRAGON_LEVEL" }),
        PortraitRow(dragonCard, { "toggle", "portraitDragonFlip", false, { "Flip dragon left to right", 16, -382, leftW - 32 }, reason = "MSUF2_DRAGON_FLIP" }),
        PortraitRow(dragonCard, { "toggle", "portraitDragonInInstances", true, { "Keep enemy dragons in instances", 16, -474, leftW - 32 },
            reason = "MSUF2_DRAGON_INSTANCES" }),
    }
    local dragonKeys = { "portraitDragonScale", "portraitDragonX", "portraitDragonY", "portraitDragonLayer", "portraitDragonLevel",
        "portraitDragonFlip", "portraitDragonInInstances" }
    for i, control in ipairs(dragonControls) do
        BindExactPortraitTabTarget(control, "dragon", tostring(unit) .. "." .. dragonKeys[i])
    end
    BindExactPortraitTabTarget(flip, "advanced", tostring(unit) .. ".portraitFlip")
    BindExactPortraitTabTarget(shadow, "advanced", tostring(unit) .. ".portraitInnerShadow")
    if M.AddTooltip then
        M.AddTooltip(shadow, "Inset shadow strength", "Darkens the inner edges of square portraits.", { hook = true })
        M.AddTooltip(dragonArtwork, "Always show dragon artwork",
            "Always displays the gold dragon as decoration, independent of the unit's classification.", { hook = true })
        M.AddTooltip(dragonControls[4], "Dragon draw order", "Places the dragon in front of or behind the art on the frame it shares: the portrait image at level 0, the gold ring at level 1. From level 2 on the dragon has a frame of its own above the ring.", { hook = true })
    end
    local portraitActiveControls = {
        render, clickable, shape, sizeMode, size, widthOverride, heightOverride, edgeSoftness, portraitBg, castSpellIcon,
        placement, levelOffset, portraitAlpha,
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
    RefreshPortraitControls = RefreshPortraitControls(M.BindGateGroup(ctx, function() return GetConf(unit) end, {
        { enable = { portraitEnable } },
        { controls = portraitActiveControls, on = PortraitActive, reason = W.TurnOnReason and W.TurnOnReason("Portrait") },
        -- The Left/Right segment only steers the attached layout; detached and
        -- overlay portraits take their position from the Placement card instead.
        { controls = portrait, on = function(conf) return PortraitPlacementIs(conf, "ATTACHED") end },
        { controls = { detachedPoint, detachedTo }, on = function(conf) return PortraitPlacementIs(conf, "DETACHED") end },
        { controls = overlayAlign, on = function(conf) return PortraitPlacementIs(conf, "OVERLAY") end },
        -- Fill-bar geometry comes from the two bar anchors. Every other
        -- placement exposes one explicit mode: a uniform size or two axes.
        { controls = sizeMode, on = function(conf) return PortraitActive() and not PortraitFillsBar(conf) end },
        { controls = size, on = function(conf)
            return PortraitActive() and not PortraitFillsBar(conf) and not PortraitUsesSeparateSize(conf)
        end },
        { controls = { widthOverride, heightOverride }, on = function(conf)
            return PortraitActive()
                and not PortraitFillsBar(conf)
                and PortraitUsesSeparateSize(conf)
        end },
        { controls = { panX, panY }, on = PortraitIs2D },
        { controls = zoom, on = function(conf) return PortraitActive() and conf.portraitRender ~= "CLASS" end },
        { controls = flip, on = PortraitActive },
        { controls = shadow, on = function(conf) return PortraitActive() and (conf.portraitShape or "SQUARE") == "SQUARE" end },
        { controls = dragonArtwork, on = PortraitActive },
        { controls = dragonControls, on = function(conf)
            return PortraitActive() and (conf.portraitDragonArtwork == true
                or (PortraitShapeIsBlizzard(conf) and conf.portraitBlizzardElite == true))
        end },
        { controls = dragonControls[7], on = function(conf)
            return PortraitActive() and PortraitShapeIsBlizzard(conf)
                and conf.portraitBlizzardElite == true and conf.portraitDragonArtwork ~= true
        end },
        { controls = { eliteDragon, blizzardCorner, blizzardDirection }, on = function(conf) return PortraitActive() and PortraitShapeIsBlizzard(conf) end },
        { controls = { dragonPreview, dragonPreviewExtra }, on = function(conf)
            local enabled = PortraitActive() and PortraitShapeIsBlizzard(conf)
                and conf.portraitBlizzardElite == true and conf.portraitDragonArtwork ~= true
            if not enabled then StopDragonPreview() end
            return enabled
        end },
        { controls = border, on = function(conf) return PortraitActive() and not PortraitShapeIsBlizzard(conf) end },
        { controls = edgeSoftness, on = function(conf)
            return PortraitActive()
                and not PortraitShapeIsBlizzard(conf)
                and ((conf.portraitBorderStyle or "NONE") == "NONE")
        end },
        { controls = { borderSize, borderArt }, on = function(conf)
            return PortraitActive()
                and ((conf.portraitBorderStyle or "NONE") ~= "NONE")
                and not PortraitShapeIsBlizzard(conf)
        end },
        -- Direction rotates the relief art's light; the flat renderers have no
        -- orientation to speak of.
        { controls = borderDirection, on = function(conf)
            return PortraitActive()
                and ((conf.portraitBorderStyle or "NONE") ~= "NONE")
                and ((conf.portraitBorderArt or "FLAT") == "RELIEF")
                and not PortraitShapeIsBlizzard(conf)
        end },
        -- Fill-into-the-gap squares off the four straight edges; shaped portraits
        -- render a ring that follows the silhouette and relief art replaces both.
        { controls = fillBorder, on = function(conf)
            return PortraitActive()
                and ((conf.portraitBorderStyle or "NONE") ~= "NONE")
                and ((conf.portraitShape or "SQUARE") == "SQUARE")
                and ((conf.portraitBorderArt or "FLAT") ~= "RELIEF")
        end },
        { controls = classStyle, on = function(conf) return PortraitActive() and ((conf.portraitRender or "2D") == "CLASS") end },
    }, {
        also = function() SetSectionHeaderStatus(sec, nil) end,
        track = function(c, r) return M.TrackCollapsibleRefresh(c, sec, r) end,
    }))
end
local function PreparePowerSwitch(ctx, sec, unit)
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then Schema.Section(sec, unit) end
    if entry and entry.featureSwitch then return entry.featureSwitch end
    local show
    show = ControlRow(ctx, sec, { "sectionSwitch", "show", true, { "Show power bar" },
        get = function() return ReadBool(unit, "showPowerBar", true) end,
        set = function(v)
            SetBool(unit, "showPowerBar", v, "MSUF2_POWER_SHOW", { power = true, preview = true })
            _G.MSUF_EnsureCooldownWidthObservers()
            if show.refreshDetails then show.refreshDetails() end
        end,
        scope = unit, meta = SettingMeta(ctx, "power.show", unit, "showPowerBar"),
        beforeBind = function(widget)
            W.AttachUnitEditFocus(widget, unit, "powerbar")
        end,
    })
    M.TrackRefresh(ctx, function()
        W.SetControlEnabled(show, not (unit == "player" and IsPlayerPowerManagedByClassResources and IsPlayerPowerManagedByClassResources(unit)))
    end)
    return show
end

local function SetPowerFillMode(ctx, unit, key, peerKey, value, reason, historyLabel, opts)
    value = value == true
    local function Write()
        local conf = GetConf(unit)
        local changed = conf[key] ~= value
        conf[key] = value
        if value and conf[peerKey] ~= false then
            conf[peerKey] = false
            changed = true
        end
        if not changed then return false end
        M.RequestUnitDomains(unit, reason, opts)
        if M.RequestRefresh then M.RequestRefresh(ctx, "unit-power-fill-mode") end
        return true
    end
    if type(M.RunWithHistory) == "function" then
        return M.RunWithHistory(historyLabel, "unit:" .. tostring(unit) .. ":powerFillMode", Write)
    end
    return Write()
end
local function BuildPower(ctx, builder, unit)
    if not POWER_UNITS[unit] then return end
    local isPlayer = unit == "player"
    local mainCardHeight = PowerMainCardHeight(unit)
    local detachedCardY = PowerDetachedCardTop(unit)
    local detachedCardHeight = isPlayer and 340 or 238
    local powerSectionHeight = PowerSectionHeight(unit)
    local powerNoticeY = detachedCardY - detachedCardHeight - 12
    local sec = builder:CollapsibleSection("power_bar", "Power Bar", powerSectionHeight, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 16
    local cardGap = 28
    local availableW = max(340, sectionW - (leftX * 2))
    local cardW = max(260, min(460, floor((availableW - cardGap) * 0.5)))
    local rightX = leftX + cardW + cardGap
    local rightW = max(240, min(460, sectionW - rightX - leftX))
    local fullW = max(300, min(sectionW - (leftX * 2), cardW + cardGap + rightW))
    local detachedGap = 28
    local detachedLeftW = max(190, min(320, floor((fullW - 32 - detachedGap) * 0.5)))
    local detachedRightX = 16 + detachedLeftW + detachedGap
    local detachedRightW = max(180, min(320, fullW - detachedRightX - 16))
    local detachedSliderW = max(170, min(300, min(detachedLeftW, detachedRightW) - 42))
    local RefreshPowerEnabled = M.RefreshProxy()
    local powerControls = {}
    local detachedControls = {}
    local detachedShape
    local detachedSync
    local detachedWidth
    local detachedHeight
    local orbSize
    local detachedTextToggle
    local function AddPowerControl(control) M.AppendValues(powerControls, control); W.AttachUnitEditFocus(control, unit, "powerbar"); return control end
    local function AddDetachedControl(control) M.AppendValues(detachedControls, control); return AddPowerControl(control) end
    local function ResolveDefault(value)
        if type(value) == "function" then return value() end
        return value
    end
    local POWER_OPTS = { power = true, preview = true }
    local DETACHED_POWER_OPTS = { power = true, detachedPowerBar = true, preview = true }
    local POWER_TEXT_OPTS = M.KeySetFromWords "power text preview"
    local function ReadSyncedPlayerPowerOutline()
        if not isPlayer or GetConf(unit).powerBarDetached ~= true then return nil end
        local outline = tonumber(GetBars().detachedPowerBarOutline)
        if outline == nil then return nil end
        return max(0, min(8, floor(outline + 0.5)))
    end
    local function ReadPowerBorderEnabled()
        local outline = ReadSyncedPlayerPowerOutline()
        if outline ~= nil then return outline > 0 end
        local conf = GetConf(unit)
        if conf.powerBarBorderEnabled ~= nil then return conf.powerBarBorderEnabled == true end
        return GetBars().powerBarBorderEnabled == true
    end
    local function ReadPowerBorderThickness()
        local outline = ReadSyncedPlayerPowerOutline()
        if outline ~= nil then return outline end
        local conf = GetConf(unit)
        return tonumber(conf.powerBarBorderThickness) or tonumber(GetBars().powerBarBorderThickness or GetBars().powerBarBorderSize) or 1
    end
    local function SetSyncedPlayerPowerOutline(outline, reason)
        outline = max(0, min(8, floor((tonumber(outline) or 0) + 0.5)))
        local function Write()
            local conf, bars = GetConf(unit), GetBars()
            local enabled, changed = outline > 0, false
            if conf.powerBarBorderEnabled ~= enabled then conf.powerBarBorderEnabled, changed = enabled, true end
            if enabled and conf.powerBarBorderThickness ~= outline then conf.powerBarBorderThickness, changed = outline, true end
            if bars.detachedPowerBarOutline ~= outline then bars.detachedPowerBarOutline, changed = outline, true end
            if not changed then return false end
            M.RequestUnitDomains(unit, reason, POWER_OPTS)
            RefreshClassPowerDetachedState()
            return true
        end
        if type(M.RunWithHistory) == "function" then
            return M.RunWithHistory("Power bar border", "unit:player:powerBarBorder", Write)
        end
        return Write()
    end
    local function SetManualDetachedPowerWidth(value, reason)
        local conf, bars = GetConf(unit), GetBars()
        local sharedSourceChanged = bars.detachedPowerBarWidthMode ~= nil
        bars.detachedPowerBarWidthMode = nil
        if isPlayer then conf.detachedPowerBarSyncClassPower = false end
        SetNumber(unit, "detachedPowerBarWidth", value, reason, DETACHED_POWER_OPTS)
        if detachedSync and detachedSync.SetChecked then detachedSync:SetChecked(false) end
        _G.MSUF_EnsureCooldownWidthObservers()
        if sharedSourceChanged then
            M.RequestGeneralDomains(reason, DETACHED_POWER_OPTS)
        end
        RefreshClassPowerDetachedState()
    end
    local function BuildPowerControls(parent, addFn, rows)
        return Schema.Build(ctx, parent, rows, {
            beforeBind = addFn,
            bind = function(c, widget, row, kind)
                local key, fallback = row.key or row[2], row[3]
                row.get = function()
                    if row.read then return row.read() end
                    if kind == "toggle" then return ReadBool(unit, key, fallback) end
                    return ReadNumber(unit, key, ResolveDefault(fallback))
                end
                row.set = function(value)
                    if kind == "toggle" then
                        SetBool(unit, key, value, row.reason, row.opts or POWER_OPTS)
                        if row.afterSet then row.afterSet() end
                    elseif key == "detachedPowerBarWidth" then
                        return SetManualDetachedPowerWidth(value, row.reason)
                    else return SetNumber(unit, key, value, row.reason, row.opts or POWER_OPTS) end
                end
                row.meta = SettingMeta(ctx, "power." .. tostring(key), unit, key)
                row.scope, row.roundStep = unit, kind == "slider"
                row[3] = ResolveDefault(fallback)
                Schema.UnitBinding(c, widget, row, kind)
            end,
        })
    end
    local powerNotice, _, powerNoticeButton = CreateSectionNotice(sec, powerNoticeY, "Show Power", 126)
    if powerNoticeButton then
        local powerShortcutMeta
        if not isPlayer then
            powerShortcutMeta = {
                settingKey = unit .. ".showPowerBar",
                command = {
                    kind = "toggle", valueKind = "boolean",
                    get = function() return ReadBool(unit, "showPowerBar", true) end,
                    set = function(value) SetBool(unit, "showPowerBar", value == true, "MSUF2_POWER_SHOW", { power = true, preview = true }) end,
                },
            }
        else
            powerShortcutMeta = {
                actionKey = "show_player_power_or_open_class_resources",
            }
        end
        RegisterControl(powerNoticeButton, ctx, "power.enable_now", "Show Power", "button",
            not isPlayer and "setting" or "action", powerShortcutMeta)
        powerNoticeButton:SetScript("OnClick", function()
            if isPlayer and IsPlayerPowerManagedByClassResources and IsPlayerPowerManagedByClassResources(unit) then
                if type(M.SelectPage) == "function" then M.SelectPage("classpower") end
                return
            end
            SetBool(unit, "showPowerBar", true, "MSUF2_POWER_SHOW", { power = true, preview = true })
            _G.MSUF_EnsureCooldownWidthObservers()
            RefreshPowerEnabled()
        end)
        Schema.Owned(powerNoticeButton, unit, "power")
    end
    local mainCard = ControlRow(ctx, sec, { "card", "menu2.uf_" .. unit .. ".power.mainCard", nil,
        { "Visibility & Size", nil, leftX, -38, cardW, mainCardHeight }, scope = unit, domain = "layout" })
    local borderCard = ControlRow(ctx, sec, { "card", "menu2.uf_" .. unit .. ".power.borderCard", nil,
        { "Border & fill", "Outline and fill behavior.", rightX, -38, rightW, mainCardHeight }, scope = unit, domain = "layout" })
    local detachedCard = ControlRow(ctx, sec, { "card", "menu2.uf_" .. unit .. ".power.detachedCard", nil,
        { "Detached placement", "Used only when the power bar is detached from the unit frame.",
            leftX, detachedCardY, fullW, detachedCardHeight }, scope = unit, domain = "layout" })
    -- Power bar art is configured once on the Bars page. The per-unit keys stay
    -- scope-aware in the UF compiler (conf -> bars -> unit bar texture); they
    -- simply have no control on this page anymore.
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(borderCard, function()
            local refs = { "power.current" }
            if not (GetGeneral().powerBarBgMatchBarColor == true or GetBars().powerBarBgMatchBarColor == true) then
                refs[#refs + 1] = "bar.power_background"
            end
            refs[#refs + 1] = "bar.power_loss"
            if ReadPowerBorderEnabled() then refs[#refs + 1] = "power.border" end
            return refs
        end, {
            title = "Power Bar Colors",
            note = "Color by class applies to all unit power bars. Resource colors apply when it is off. A matched background follows Health.",
            historySource = "menu:unit-power-colors",
            context = function() return { unit = unit } end,
        })
    end
    local show = PreparePowerSwitch(ctx, sec, unit)
    show.refreshDetails = function() RefreshPowerEnabled() end
    if isPlayer then
        local sourceMeta = SettingMeta(ctx, "power.resource_source", unit, "playerPowerSource")
        sourceMeta.label = M.PlayerPowerSourceSearchLabel
        sourceMeta.historySource = "classpower:playerPowerSource"
        local playerPowerSource = ControlRow(ctx, mainCard, { "dropdown", "playerPowerSource", nil, { "Displayed resource",
            PLAYER_POWER_SOURCE_VALUES, cardW - 72 }, { 16, -132, cardW - 72 },
            get = function() return NormalizePlayerPowerSource(GetConf(unit).playerPowerSource) end,
            set = function(value)
                GetConf(unit).playerPowerSource = NormalizePlayerPowerSource(value)
                M.ApplyPlayerPowerSource("MSUF2_PLAYER_POWER_SOURCE")
            end,
            scope = unit, meta = sourceMeta,
            beforeBind = function(widget)
                widget._msuf2StableSearchLabel = M.PlayerPowerSourceSearchLabel
            end,
        })
        RegisterControl(playerPowerSource, ctx, "power.resource_source",
            M.PlayerPowerSourceSearchLabel, "dropdown", "setting", {
                settingKey = "player.playerPowerSource",
                values = PLAYER_POWER_SOURCE_VALUES,
            })
        if M.AddTooltip then
            M.AddTooltip(playerPowerSource, "Displayed resource",
                M.PlayerPowerSourceTooltip,
                { hook = true, owner = "ANCHOR_RIGHT" })
        end
    end
    local powerBorder = ControlRow(ctx, borderCard, { "toggle", "powerBorder", false, { "Power bar border", 16, -62, rightW - 32 },
        get = ReadPowerBorderEnabled,
        set = function(value)
        if isPlayer then
            local thickness = ReadPowerBorderThickness()
            if value and thickness <= 0 then
                thickness = tonumber(GetConf(unit).powerBarBorderThickness) or 1
                if thickness <= 0 then thickness = 1 end
            end
            SetSyncedPlayerPowerOutline(value and thickness or 0, "MSUF2_POWER_BORDER")
        else
            SetBool(unit, "powerBarBorderEnabled", value, "MSUF2_POWER_BORDER", POWER_OPTS)
        end
        RefreshPowerEnabled()
    end,
        scope = unit, meta = SettingMeta(ctx, "power.powerBarBorderEnabled", unit, "powerBarBorderEnabled"),
        beforeBind = AddPowerControl,
    })
    local smoothFill = ControlRow(ctx, borderCard, { "toggle", "smoothFill", false, { "Smooth fill", 16, -158, rightW - 32 },
        get = function() return ReadBool(unit, "powerSmoothFill", false) end,
        set = function(v) SetPowerFillMode(ctx, unit, "powerSmoothFill", "powerChunkedFill", v, "MSUF2_POWER_SMOOTH", "Smooth power fill", POWER_OPTS) end,
        scope = unit, meta = SettingMeta(ctx, "power.powerSmoothFill", unit, "powerSmoothFill"),
        beforeBind = AddPowerControl,
    })
    local chunkedFill = ControlRow(ctx, borderCard, { "toggle", "chunkedFill", false, { "Chunked power loss", 16, -188, rightW - 32 },
        get = function() return ReadBool(unit, "powerChunkedFill", false) end,
        set = function(v) SetPowerFillMode(ctx, unit, "powerChunkedFill", "powerSmoothFill", v, "MSUF2_POWER_CHUNKED", "Chunked power loss", POWER_OPTS) end,
        scope = unit, meta = SettingMeta(ctx, "power.powerChunkedFill", unit, "powerChunkedFill"),
        beforeBind = AddPowerControl,
    })
    local attachedPowerFields = BuildPowerControls(mainCard, AddPowerControl, {
        { "slider", "powerBarHeight", 3, { "Power bar height", 1, 20, 1, 300 }, { 16, -76, cardW - 72, "CENTER" },
            reason = "MSUF2_POWER_HEIGHT", read = function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarHeight) or tonumber(GetBars().powerBarHeight) or 3
        end },
        { "toggle", "embedPowerBarIntoHealth", false, { "Embed into health", 16, isPlayer and -202 or -138, cardW - 32 },
            reason = "MSUF2_POWER_EMBED", read = function()
            local conf = GetConf(unit)
            if conf.embedPowerBarIntoHealth ~= nil then return conf.embedPowerBarIntoHealth == true end
            return GetBars().embedPowerBarIntoHealth == true
        end },
    })
    local attachedPowerHeight = attachedPowerFields.powerBarHeight
    local embedPower = attachedPowerFields.embedPowerBarIntoHealth
    local borderSize = ControlRow(ctx, borderCard, { "slider", "borderSize", 1, { "Border thickness", 0, isPlayer and 8 or 6, 1, 300 }, { 16, -108,
        rightW - 72, "CENTER" },
        get = ReadPowerBorderThickness,
        set = function(value)
        if isPlayer then
            SetSyncedPlayerPowerOutline(value, "MSUF2_POWER_BORDER_SIZE")
        else
            SetNumber(unit, "powerBarBorderThickness", value, "MSUF2_POWER_BORDER_SIZE", POWER_OPTS)
        end
        RefreshPowerEnabled()
    end,
        scope = unit, meta = SettingMeta(ctx, "power.powerBarBorderThickness", unit, "powerBarBorderThickness"), roundStep = true,
        beforeBind = AddPowerControl,
    })
    local detached = ControlRow(ctx, mainCard, { "toggle", "detached", false, { "Detach from frame", 16, isPlayer and -230 or -166, cardW - 32 },
        get = function() return ReadBool(unit, "powerBarDetached", false) end,
        set = function(v)
            local conf = GetConf(unit)
            conf.powerBarDetached = v and true or false
            if conf.powerBarDetached then
                conf.detachedPowerBarOffsetX = tonumber(conf.detachedPowerBarOffsetX) or 0
                conf.detachedPowerBarOffsetY = tonumber(conf.detachedPowerBarOffsetY) or -4
                conf.detachedPowerBarWidth = tonumber(conf.detachedPowerBarWidth) or tonumber(conf.width) or (unit == "focus" and 180 or 275)
                conf.detachedPowerBarHeight = tonumber(conf.detachedPowerBarHeight) or 6
                conf.detachedPowerBarFrameLevelOffset = tonumber(conf.detachedPowerBarFrameLevelOffset) or 6
                if isPlayer and conf.detachedPowerBarSyncClassPower == nil then conf.detachedPowerBarSyncClassPower = true end
                if isPlayer and conf.detachedPowerBarShape == nil then conf.detachedPowerBarShape = "BAR" end
                if isPlayer and conf.detachedPowerOrbSize == nil then conf.detachedPowerOrbSize = 54 end
            end
            _G.MSUF_EnsureCooldownWidthObservers()
            M.RequestUnitDomains(unit, "MSUF2_POWER_DETACHED", DETACHED_POWER_OPTS)
            RefreshPowerEnabled()
            RefreshClassPowerDetachedState()
        end,
        scope = unit, meta = ReviewedMeta(ctx, "power.detached", "setting", "compound",
            "Enabling detached power seeds its required geometry and Player synchronization defaults."),
        beforeBind = AddPowerControl,
    })
    local detachedTextFields = BuildPowerControls(detachedCard, AddDetachedControl, {
        { "toggle", "detachedPowerBarTextOnBar", false, { "Text on detached bar", 16, -62, detachedLeftW },
            reason = "MSUF2_POWER_DETACHED_TEXT", opts = POWER_TEXT_OPTS },
    })
    detachedTextToggle = detachedTextFields and detachedTextFields.detachedPowerBarTextOnBar
    local sliderTop = -116
    if isPlayer then
        sliderTop = -148
        local playerDetached = BuildPowerControls(detachedCard, AddDetachedControl, {
            { "toggle", "sync", true, { "Sync width to Class Resource", 16, -94, detachedLeftW }, key = "detachedPowerBarSyncClassPower",
                reason = "MSUF2_POWER_DETACHED_SYNC", read = function() return GetConf(unit).detachedPowerBarSyncClassPower ~= false end,
                afterSet = function() _G.MSUF_EnsureCooldownWidthObservers() end, opts = DETACHED_POWER_OPTS },
            { "toggle", "detachedPowerBarAnchorToClassPower", false, { "Anchor to Class Resource", detachedRightX, -94, detachedRightW },
                reason = "MSUF2_POWER_DETACHED_ANCHOR", opts = DETACHED_POWER_OPTS },
        })
        detachedSync = playerDetached.sync
    end
    local detachedFields = BuildPowerControls(detachedCard, AddDetachedControl, {
        { "slider", "width", function() return ReadNumber(unit, "width", 250) end, { "Detached width", 20, 800, 1, 300 }, { 16, sliderTop,
            detachedSliderW, "CENTER" }, key = "detachedPowerBarWidth", reason = "MSUF2_POWER_DETACHED_W", opts = DETACHED_POWER_OPTS },
        { "slider", "height", 6, { "Detached height", 2, 80, 1, 300 }, { detachedRightX, sliderTop, detachedSliderW, "CENTER" },
            key = "detachedPowerBarHeight", reason = "MSUF2_POWER_DETACHED_H", opts = DETACHED_POWER_OPTS },
        { "slider", "detachedPowerBarFrameLevelOffset", 6, { "Detached layer", 0, 30, 1, 300 }, { 16, sliderTop - 66, detachedSliderW, "CENTER" },
            reason = "MSUF2_POWER_DETACHED_LAYER", opts = DETACHED_POWER_OPTS },
    })
    detachedWidth, detachedHeight = detachedFields.width, detachedFields.height
    if detachedWidth and M.AddTooltip then
        M.AddTooltip(detachedWidth, "Detached width",
            "Changing this value selects Manual width. For Player, it also turns off Sync width to Class Resource so the new width takes effect immediately.",
            { hook = true, owner = "ANCHOR_RIGHT" })
    end
    if isPlayer then
        detachedShape = ControlRow(ctx, detachedCard, { "dropdown", "detachedShape", "BAR", { "Detached shape", DETACHED_POWER_SHAPE_VALUES,
            detachedSliderW }, { detachedRightX, sliderTop - 66, detachedSliderW },
            get = function()
                return NormalizeDetachedPowerShape(GetConf(unit).detachedPowerBarShape)
            end,
            set = function(v)
                v = NormalizeDetachedPowerShape(v)
                local conf = GetConf(unit)
                conf.detachedPowerBarShape = v
                if v == "ORB" and conf.detachedPowerOrbSize == nil then conf.detachedPowerOrbSize = 54 end
                _G.MSUF_EnsureCooldownWidthObservers()
                M.RequestUnitDomains(unit, "MSUF2_POWER_DETACHED_SHAPE", DETACHED_POWER_OPTS)
                RefreshPowerEnabled()
                RefreshClassPowerDetachedState()
            end,
            scope = unit, meta = SettingMeta(ctx, "power.detached_shape", unit, "detachedPowerBarShape"),
            beforeBind = AddDetachedControl,
        })
        if M.AddTooltip then M.AddTooltip(detachedShape, "Independent Powerbar Shape",
            "Changes only Player power. Class Resources keep their own shape setting. Round and Crystal fill horizontally; Orb fills bottom-to-top.", { hook = true, owner = "ANCHOR_RIGHT" }) end
        orbSize = BuildPowerControls(detachedCard, AddDetachedControl, { { "slider", "detachedPowerOrbSize", 54, { "Orb size", 20, 160, 1, 300 },
            { 16, sliderTop - 132, detachedSliderW, "CENTER" }, reason = "MSUF2_POWER_DETACHED_ORB_SIZE",
            opts = DETACHED_POWER_OPTS } })["detachedPowerOrbSize"]
    end
    local function PowerOn() return ReadBool(unit, "showPowerBar", true) end
    local function DetachedOn() return PowerOn() and ReadBool(unit, "powerBarDetached", false) end
    local function OrbSelected() return isPlayer and NormalizeDetachedPowerShape(GetConf(unit).detachedPowerBarShape) == "ORB" end
    local function ClassManaged() return isPlayer and IsPlayerPowerManagedByClassResources and IsPlayerPowerManagedByClassResources(unit) and true or false end
    -- While Class Resources owns the Player power bar the section notice
    -- explains the lock, so these hover reasons stay silent then.
    local turnOn = W.TurnOnReason or function() return nil end
    RefreshPowerEnabled = RefreshPowerEnabled(M.BindGateGroup(ctx, nil, {
        { enable = { show }, controls = powerControls, on = PowerOn,
            reason = turnOn("Show power bar", function() return PowerOn() or ClassManaged() end) },
        { controls = detachedControls, on = DetachedOn,
            reason = turnOn("Detach from frame", function() return DetachedOn() or ClassManaged() end) },
        { controls = { attachedPowerHeight, embedPower }, on = function() return PowerOn() and not DetachedOn() end },
        { controls = borderSize, on = function() return PowerOn() and ReadPowerBorderEnabled() end },
        -- Detached width/height/sync exist only when a detached card was built; the `when`
        -- guard keeps the optional Player-only detached controls safe.
        { controls = detachedSync, when = function() return detachedSync ~= nil end, on = function() return DetachedOn() and not OrbSelected() end },
        { controls = detachedWidth, when = function() return detachedWidth ~= nil end, on = function() return DetachedOn() and not OrbSelected() end },
        { controls = detachedHeight, when = function() return detachedHeight ~= nil end, on = function() return DetachedOn() and not OrbSelected() end },
        { controls = detachedShape, when = function() return detachedShape ~= nil end, on = DetachedOn },
        { controls = orbSize, when = function() return orbSize ~= nil end, on = function() return DetachedOn() and OrbSelected() end },
    }, {
        -- Player power managed by Class Resources force-disables the whole group, overriding
        -- the rows above. Then update the section notice and header status.
        override = function(_, setEnabled)
            if ClassManaged() then
                setEnabled(powerControls, false)
                setEnabled(detachedControls, false)
                if detachedTextToggle then setEnabled(detachedTextToggle, DetachedOn()) end
                setEnabled({ show }, false)
                setEnabled(borderSize, false)
            end
        end,
        also = function()
            if ClassManaged() then
                if powerNoticeButton and powerNoticeButton.SetText then powerNoticeButton:SetText(M.Tr and M.Tr("Class Resources") or "Class Resources") end
                powerNotice:SetMessage(M.Tr("Player power bar is connected to Class Resources. Manage detached power and power text in Class Resources > Detached Power Bar."), "warning")
                powerNotice:Show()
            elseif not PowerOn() then
                if powerNoticeButton and powerNoticeButton.SetText then powerNoticeButton:SetText(M.Tr and M.Tr("Show Power") or "Show Power") end
                powerNotice:SetMessage(M.Format("%s power bar is hidden. Turn it on to configure size, embed, or detached settings.",
                    UnitTopLabel(unit)), "warning")
                powerNotice:Show()
            else
                if powerNoticeButton and powerNoticeButton.SetText then powerNoticeButton:SetText(M.Tr and M.Tr("Show Power") or "Show Power") end
                powerNotice:Hide()
            end
            SetSectionHeaderStatus(sec, nil)
        end,
        track = function(c, r) return M.TrackCollapsibleRefresh(c, sec, r) end,
    }))
end
local function PrepareCastbarSwitch(ctx, sec, unit)
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then Schema.Section(sec, unit) end
    if entry and entry.featureSwitch then return entry.featureSwitch end
    local fields = CASTBAR_FIELDS[unit]
    local providerMemoryKey = fields.providerMemory or (fields.backend and (fields.backend .. "BeforeHide") or nil)
    local canUseBlizzardProvider = unit == "player"
    local state = {}
    local function NormalizeBackend(value)
        local fnUnit = _G.MSUF_NormalizeCastbarBackendForUnit
        if type(fnUnit) == "function" then return fnUnit(unit, value) or "MSUF" end
        local fn = _G.MSUF_NormalizeCastbarBackend
        if type(fn) == "function" then
            local backend = fn(value) or "MSUF"
            if backend == "BLIZZARD" and not canUseBlizzardProvider then return "HIDE" end
            return backend
        end
        if value == "BLIZZARD" and not canUseBlizzardProvider then return "HIDE" end
        if value == "BLIZZARD" or value == "HIDE" or value == "MSUF" then return value end
        return "MSUF"
    end
    local function ReadCastbarBackend()
        local fn = _G.MSUF_GetCastbarBackend
        if type(fn) == "function" then return NormalizeBackend(fn(unit, GetGeneral())) end
        local g = GetGeneral()
        local value = fields.backend and g[fields.backend]
        if value == nil then return ReadGeneralBool(fields.enable, true) and "MSUF" or (canUseBlizzardProvider and "BLIZZARD" or "HIDE") end
        return NormalizeBackend(value)
    end
    local function SetCastbarBackend(value)
        local backend = NormalizeBackend(value)
        local g = GetGeneral()
        if providerMemoryKey and backend ~= "HIDE" then g[providerMemoryKey] = backend end
        local fn = _G.MSUF_SetCastbarBackend
        if type(fn) == "function" then
            fn(unit, backend, g)
        else
            if fields.backend then g[fields.backend] = backend end
            g[fields.enable] = (backend == "MSUF")
        end
        M.RequestUnitDomains(unit, "MSUF2_CASTBAR_BACKEND", { castbar = true, preview = true })
        _G.MSUF_Castbars_OnSettingsChanged("menu2_backend")
        if unit == "player" then _G.MSUF_SuppressBlizzardPlayerCastbars() end
        if state.refresh then state.refresh() end
    end
    local function ReadCastbarProvider()
        if not canUseBlizzardProvider then return "MSUF" end
        local backend = ReadCastbarBackend()
        if backend == "BLIZZARD" then return "BLIZZARD" end
        if backend == "MSUF" then return "MSUF" end
        local remembered = providerMemoryKey and NormalizeBackend(GetGeneral()[providerMemoryKey]) or nil
        if remembered == "BLIZZARD" then return "BLIZZARD" end
        return "MSUF"
    end
    local function SetCastbarProvider(value)
        if not canUseBlizzardProvider then return end
        local backend = NormalizeBackend(value)
        if backend == "HIDE" then backend = "MSUF" end
        local previousBackend = ReadCastbarBackend()
        SetCastbarBackend(backend)
        if backend == "BLIZZARD" and previousBackend ~= "BLIZZARD" then
            _G.MSUF_ShowReloadRecommendedPopup("Player Blizzard castbar")
        end
    end
    local function SetCastbarEnabled(enabled)
        if enabled then
            SetCastbarBackend(canUseBlizzardProvider and ReadCastbarProvider() or "MSUF")
        else
            local backend = ReadCastbarBackend()
            if providerMemoryKey and backend ~= "HIDE" then GetGeneral()[providerMemoryKey] = backend end
            SetCastbarBackend("HIDE")
        end
    end
    state.read, state.set = ReadCastbarBackend, SetCastbarBackend
    state.readProvider, state.setProvider = ReadCastbarProvider, SetCastbarProvider
    state.setEnabled = SetCastbarEnabled
    local enabled = ControlRow(ctx, sec, { "sectionSwitch", "enabled", true, { "Enable Castbar" },
        get = function() return ReadCastbarBackend() ~= "HIDE" end,
        set = SetCastbarEnabled,
        scope = unit, meta = ReviewedMeta(ctx, "castbar.enabled", "setting", "compound",
            "Castbar visibility coordinates backend, enable state, and remembered provider."),
        beforeBind = function(widget)
            widget._msuf2CastbarState = state
            W.AttachUnitEditFocus(widget, unit, "castbar")
        end,
    })
    return enabled
end
-- The unit Castbar section builds in order through these functions; s carries
-- the section frame, its layout, the control lists and every binder, card
-- and control a later part or the closing gate group reads.
local CastbarSection = {}
function CastbarSection.Binders(s)
    local ctx, unit, prefix, allCastbarControls = s.ctx, s.unit, s.prefix, s.allCastbarControls
    local function AddControl(list, control)
        if control then
            allCastbarControls[#allCastbarControls + 1] = control
            if list then list[#list + 1] = control end
        end
        return control
    end
    local function DetailKey(suffix)
        return prefix and (prefix .. suffix) or suffix
    end
    local function CastbarWidthKey()
        if unit == "boss" then return "bossCastbarWidth" end
        if unit == "arena" then return "arenaCastbarWidth" end
        return prefix and (prefix .. "BarWidth") or nil
    end
    local function CastbarHeightKey()
        if unit == "boss" then return "bossCastbarHeight" end
        if unit == "arena" then return "arenaCastbarHeight" end
        return prefix and (prefix .. "BarHeight") or nil
    end
    local function CastbarWidthSourceKey()
        local fn = _G.MSUF_GetCastbarWidthSourceKey
        if type(fn) == "function" then
            local key = fn(unit)
            if key then return key end
        end
        if unit == "player" then return "castbarPlayerMatchWidth" end
        if unit == "target" then return "castbarTargetMatchWidth" end
        if unit == "focus" then return "castbarFocusMatchWidth" end
        if unit == "boss" then return "bossCastbarMatchWidth" end
        if unit == "arena" then return "arenaCastbarMatchWidth" end
    end
    local function NormalizeWidthSource(value)
        local fn = _G.MSUF_NormalizeCastbarWidthSource or _G.MSUF_NormalizePlayerCastbarWidthSource
        if type(fn) == "function" then return fn(value) end
        if value == true then return "unitframe" end
        if value == "unitframe" or value == "essential" or value == "utility" then return value end
        return nil
    end
    local function ReadWidthSource()
        local key = CastbarWidthSourceKey()
        return NormalizeWidthSource(key and GetGeneral()[key]) or "manual"
    end
    local function ReadGeneralValue(key, defaultValue)
        local value = GetGeneral()[key]
        if value == nil or value == "" then return defaultValue end
        return value
    end
    local function ReadGeneralNumber(key, defaultValue)
        local value = tonumber(GetGeneral()[key])
        if value == nil then value = defaultValue or 0 end
        return value
    end
    local function SetGeneralValue(key, value, reason)
        M.SetGeneralValue(key, value, reason, { castbar = true, preview = true, applyAll = false })
    end
    local function SetGeneralNumber(key, value, reason)
        value = tonumber(value)
        if value == nil then return end
        if math.abs(value - floor(value + 0.5)) < 0.001 then value = floor(value + 0.5) end
        SetGeneralValue(key, value, reason)
    end
    local function PrepareControl(widget, row)
        if row.castbarControl then AddControl(nil, widget) end
        W.AttachUnitEditFocus(widget, unit, "castbar")
    end
    -- No castbar detail color binder lives here on purpose: every castbar text
    -- reaches its color through the card's three-dot shortcut and the Colors page,
    -- so this page never grows a second swatch for a key it already edits.
    local function BuildDetailControls(parent, list, rows)
        return Schema.Build(ctx, parent, rows, {
            beforeBind = function(widget)
                AddControl(list, widget)
                W.AttachUnitEditFocus(widget, unit, "castbar")
            end,
            bind = function(c, widget, row, kind)
                local key, fallback = row[2], row[3]
                row.get = function()
                    if kind == "slider" then return ReadGeneralNumber(key, fallback) end
                    return ReadGeneralValue(key, fallback)
                end
                row.set = function(value)
                    if kind == "slider" then
                        if row.beforeSet then row.beforeSet(value) end
                        SetGeneralNumber(key, value, row.reason)
                    else
                        SetGeneralValue(key, value or fallback, row.reason)
                        if row.afterSet then row.afterSet() end
                    end
                end
                row.meta = SettingMeta(ctx, "castbar.detail." .. tostring(row.reason), "general", key)
                row.scope, row.roundStep = unit, kind == "slider"
                Schema.UnitBinding(c, widget, row, kind)
            end,
        })
    end
    s.AddControl, s.DetailKey, s.CastbarWidthKey = AddControl, DetailKey, CastbarWidthKey
    s.CastbarHeightKey, s.CastbarWidthSourceKey = CastbarHeightKey, CastbarWidthSourceKey
    s.NormalizeWidthSource, s.ReadWidthSource = NormalizeWidthSource, ReadWidthSource
    s.ReadGeneralValue, s.ReadGeneralNumber, s.SetGeneralValue = ReadGeneralValue, ReadGeneralNumber, SetGeneralValue
    s.SetGeneralNumber, s.BuildDetailControls, s.PrepareControl = SetGeneralNumber, BuildDetailControls, PrepareControl
end
function CastbarSection.Cards(s)
    local ctx, unit, fields, sec, sectionW, leftX, leftW = s.ctx, s.unit, s.fields, s.sec, s.sectionW, s.leftX, s.leftW
    local rightX, rightW, RefreshCastbarEnabled, DetailKey = s.rightX, s.rightW, s.RefreshCastbarEnabled, s.DetailKey
    local ReadGeneralValue = s.ReadGeneralValue
    local castbarState = PrepareCastbarSwitch(ctx, sec, unit)._msuf2CastbarState
    castbarState.refresh = function() RefreshCastbarEnabled() end
    local ReadCastbarBackend, SetCastbarBackend = castbarState.read, castbarState.set
    local ReadCastbarProvider, SetCastbarProvider = castbarState.readProvider, castbarState.setProvider
    local SetCastbarEnabled = castbarState.setEnabled
    local controlWLeft = max(220, leftW - 58)
    local controlWRight = max(220, rightW - 58)
    local function SetCastbarSectionHeight(height)
        height = max(120, floor((tonumber(height) or CASTBAR_TAB_HEIGHTS.general) + 0.5))
        local entry = sec and sec._msuf2CollapsibleEntry
        if sec and sec.SetHeight then sec:SetHeight(height) end
        if entry then
            local changed = (entry.contentHeight ~= height)
            entry.contentHeight = height
            if entry.body and entry.body.SetHeight then entry.body:SetHeight(height) end
            if entry.outer and entry.outer.SetHeight then entry.outer:SetHeight((entry.headerHeight or 28) + (entry.open and height or 0)) end
            if changed and entry.builder and entry.builder.RelayoutCollapsibles then entry.builder:RelayoutCollapsibles() end
        end
    end
    local tabFrames = {}
    local generalTab, iconTab, spellTab, timeTab, advancedTab =
        UnitSectionShared.MakeTabFrames(sec, -64, sectionW, tabFrames, "general", "icon", "spell", "time", "advanced")
    local generalCard = ControlRow(ctx, generalTab, { "card", "menu2.uf_" .. unit .. ".castbar.generalCard", nil,
        { nil, nil, leftX, -4, leftW, 164 }, scope = unit, domain = "layout" })
    local providerCard = ControlRow(ctx, generalTab, { "card", "menu2.uf_" .. unit .. ".castbar.providerCard", nil,
        { "Provider & Surface", nil, rightX, -4, rightW, 164, "group" }, scope = unit, domain = "layout" })
    local sizeCard = ControlRow(ctx, generalTab, { "card", "menu2.uf_" .. unit .. ".castbar.sizeCard", nil,
        { "Size", "Width can use manual bounds or follow another frame.", leftX, -186, sectionW - 32, 166, "group" }, scope = unit, domain = "layout" })
    local iconCard = ControlRow(ctx, iconTab, { "card", "menu2.uf_" .. unit .. ".castbar.iconCard", nil,
        { nil, nil, leftX, -4, leftW, 424 }, scope = unit, domain = "layout" })
    local portraitIconCard = ControlRow(ctx, iconTab, { "card", "menu2.uf_" .. unit .. ".castbar.portraitIconCard", nil,
        { "Portrait Cast Icon", nil, rightX, -4, rightW, 156, "group" }, scope = unit, domain = "layout" })
    local spellCard = ControlRow(ctx, spellTab, { "card", "menu2.uf_" .. unit .. ".castbar.spellCard", nil,
        { nil, nil, leftX, -4, leftW, 270 }, scope = unit, domain = "layout" })
    local targetNameCard = fields.targetName and ControlRow(ctx, spellTab, { "card", "menu2.uf_" .. unit .. ".castbar.targetNameCard", nil,
        { "Cast Target Text", nil, rightX, -4, rightW, 270, "group" }, scope = unit, domain = "layout" }) or nil
    local timeCard = ControlRow(ctx, timeTab, { "card", "menu2.uf_" .. unit .. ".castbar.timeCard", nil,
        { nil, nil, leftX, -4, leftW, 270 }, scope = unit, domain = "layout" })
    local textAdvancedCard = ControlRow(ctx, advancedTab, { "card", "menu2.uf_" .. unit .. ".castbar.textAdvancedCard", nil,
        { "Spell Text Behavior", nil, leftX, -4, leftW, 190, "group" }, scope = unit, domain = "layout" })
    local iconAdvancedCard = ControlRow(ctx, advancedTab, { "card", "menu2.uf_" .. unit .. ".castbar.iconAdvancedCard", nil,
        { "Icon Style", nil, rightX, -4, rightW, 212, "group" }, scope = unit, domain = "layout" })
    local layerAdvancedCard = ControlRow(ctx, advancedTab, { "card", "menu2.uf_" .. unit .. ".castbar.layerAdvancedCard", nil,
        { "Whole Castbar Layer", nil, rightX, -230, rightW, 164, "group" }, scope = unit, domain = "layout" })
    if W.AttachContextColorReferences then
        local function GeneralCastbarColorRefs()
            local refs = {}
            local general = GetGeneral()
            if unit == "player" and general.playerCastbarOverrideEnabled == true then
                local mode = tostring(general.playerCastbarOverrideMode or "CLASS"):upper()
                refs[1] = mode == "CUSTOM" and "cast.player_override" or "unit.class.current"
            else
                refs[1], refs[2] = "cast.interruptible", "cast.non_interruptible"
            end
            refs[#refs + 1] = "cast.interrupt_feedback"
            return refs
        end
        local function IconBorderColorRefs()
            local style = tostring(ReadGeneralValue(DetailKey("IconBorderStyle"), "DARK")):upper()
            return style == "CASTBAR" and { "cast.border" } or {}
        end
        local castContext = function() return { unit = unit } end
        W.AttachContextColorReferences(generalCard, GeneralCastbarColorRefs, {
            title = M.Format("%s Castbar Colors", UnitTopLabel(unit)),
            note = "Player colors follow the active override mode.",
            historySource = "menu:unit-castbar-general-colors",
            context = castContext,
        })
        W.AttachContextColorReferences(providerCard, { "cast.background", "cast.border" }, {
            title = "Castbar Surface Colors",
            note = "Shared castbar background and outline colors.",
            historySource = "menu:unit-castbar-surface-colors",
        })
        W.AttachContextColorReferences(iconCard, IconBorderColorRefs, {
            title = "Castbar Icon Border Color",
            note = "Used by the Castbar icon-border style.",
            historySource = "menu:unit-castbar-icon-border-color",
        })
        local function AttachCastTextSettings(card, colorId, title, source)
            if not (card and W.AttachContextColorShortcut) then return end
            W.AttachContextColorShortcut(card, {
                title = title,
                historyLabel = title,
                historySource = source,
                textSettings = {
                    scope = "shared",
                    unit = unit,
                    kind = colorId == "cast.target_text.current" and "cast_target" or "cast",
                    colorReferences = { colorId },
                    colorContext = castContext,
                    colorTitle = title,
                    subtitle = "Castbar text follows the shared Fonts settings until this text gets its own color.",
                    capabilities = { baseline = false },
                },
            })
        end
        -- Each text gets its own detail reference. They resolve to the shared
        -- castbar text color while no per-castbar override exists, so the three
        -- cards no longer all edit one value behind three different labels.
        AttachCastTextSettings(spellCard, "cast.spell_text.current", "Cast Spell Text Color", "menu:unit-castbar-spell-text-color")
        if targetNameCard then
            AttachCastTextSettings(targetNameCard, "cast.target_text.current", "Cast Target Text Color", "menu:unit-castbar-target-text-color")
        end
        AttachCastTextSettings(timeCard, "cast.time_text.current", "Cast Time Text Color", "menu:unit-castbar-time-text-color")
        AttachCastTextSettings(textAdvancedCard, "cast.spell_text.current", "Cast Spell Text Color", "menu:unit-castbar-advanced-text-color")
        W.AttachContextColorReferences(iconAdvancedCard, IconBorderColorRefs, {
            title = "Castbar Icon Border Color",
            note = "Used by the Castbar icon-border style.",
            historySource = "menu:unit-castbar-advanced-icon-border-color",
        })
    end
    s.ReadCastbarBackend, s.SetCastbarBackend = ReadCastbarBackend, SetCastbarBackend
    s.ReadCastbarProvider, s.SetCastbarProvider = ReadCastbarProvider, SetCastbarProvider
    s.SetCastbarEnabled, s.controlWLeft, s.controlWRight = SetCastbarEnabled, controlWLeft, controlWRight
    s.SetCastbarSectionHeight, s.tabFrames, s.generalTab = SetCastbarSectionHeight, tabFrames, generalTab
    s.generalCard, s.providerCard, s.sizeCard, s.iconCard = generalCard, providerCard, sizeCard, iconCard
    s.portraitIconCard, s.spellCard, s.targetNameCard = portraitIconCard, spellCard, targetNameCard
    s.timeCard, s.textAdvancedCard, s.iconAdvancedCard = timeCard, textAdvancedCard, iconAdvancedCard
    s.layerAdvancedCard = layerAdvancedCard
end
function CastbarSection.Tabs(s)
    local ctx, unit, sec, sectionW = s.ctx, s.unit, s.sec, s.sectionW
    local SetCastbarSectionHeight, tabFrames = s.SetCastbarSectionHeight, s.tabFrames
    local castbarTabs, RefreshCastbarTabs, ReadCastbarTab, SetGuidedCastbarTab = W.SegmentTabs(ctx, sec, {
        label = "", values = CASTBAR_TAB_VALUES, width = min(620, sectionW - 48),
        frames = tabFrames, defaultTab = "general",
        get = function() return CurrentCastbarTab(unit) end,
        set = function(v)
            M.unitCastbarTabSelection = M.unitCastbarTabSelection or {}
            M.unitCastbarTabSelection[unit] = NormalizeCastbarTabKey(v)
        end,
        afterRefresh = function(tab) SetCastbarSectionHeight(CastbarTabHeight(unit, tab)) end,
        x = 20, y = -12,
    })
    if castbarTabs._msuf2Title then castbarTabs._msuf2Title:Hide() end
    RegisterControl(castbarTabs, ctx, "castbar.workspace_tab", "Castbar area", "segment", "ephemeral")
    Schema.Owned(castbarTabs, unit, "sectionNavigation")
    sec._msuf2GuidedSelectTab = function(tab)
        tab = NormalizeCastbarTabKey(tab)
        if type(ReadCastbarTab) == "function" and ReadCastbarTab() == tab then return true end
        if type(SetGuidedCastbarTab) == "function" then
            SetGuidedCastbarTab(tab)
        else
            M.unitCastbarTabSelection = M.unitCastbarTabSelection or {}
            M.unitCastbarTabSelection[unit] = tab
            if type(RefreshCastbarTabs) == "function" then RefreshCastbarTabs() end
        end
        return type(ReadCastbarTab) ~= "function" or ReadCastbarTab() == tab
    end
    local function BindExactCastbarTabTarget(widget, tab, settingKey)
        if not widget then return end
        widget._msuf2ExactTargetKinds = { unitCastbarTab = true }
        widget._msuf2ExactTargetContracts = {
            unitCastbarTab = { [tab] = tostring(settingKey or "") },
        }
        widget._msuf2PrepareExactSearchTarget = function(_, exactTarget)
            if type(exactTarget) ~= "table" or exactTarget.prepareKind ~= "unitCastbarTab"
                or tostring(exactTarget.prepareValue or "") ~= tab
            then
                return false
            end
            return sec._msuf2GuidedSelectTab and sec._msuf2GuidedSelectTab(tab) == true
        end
    end
    s.BindExactCastbarTabTarget = BindExactCastbarTabTarget
end
function CastbarSection.General(s)
    local ctx, unit, fields, sec, sectionW, rightW = s.ctx, s.unit, s.fields, s.sec, s.sectionW, s.rightW
    local RefreshCastbarEnabled, canUseBlizzardProvider = s.RefreshCastbarEnabled, s.canUseBlizzardProvider
    local CastbarWidthKey, CastbarHeightKey = s.CastbarWidthKey, s.CastbarHeightKey
    local CastbarWidthSourceKey, NormalizeWidthSource = s.CastbarWidthSourceKey, s.NormalizeWidthSource
    local ReadWidthSource, ReadGeneralNumber = s.ReadWidthSource, s.ReadGeneralNumber
    local SetGeneralValue, SetGeneralNumber = s.SetGeneralValue, s.SetGeneralNumber
    local ReadCastbarBackend, SetCastbarBackend = s.ReadCastbarBackend, s.SetCastbarBackend
    local ReadCastbarProvider, SetCastbarProvider = s.ReadCastbarProvider, s.SetCastbarProvider
    local SetCastbarEnabled, controlWRight, generalTab = s.SetCastbarEnabled, s.controlWRight, s.generalTab
    local generalCard, providerCard, sizeCard = s.generalCard, s.providerCard, s.sizeCard
    local BindExactCastbarTabTarget = s.BindExactCastbarTabTarget
    local castbarNotice, _, castbarNoticeButton = CreateSectionNotice(generalTab, -334, "Use MSUF", 96)
    if castbarNoticeButton then
        RegisterControl(castbarNoticeButton, ctx, "castbar.use_msuf", "Use MSUF", "button", "setting", {
            settingKey = "general." .. tostring(fields.enable),
            command = {
                kind = "toggle", valueKind = "boolean",
                get = function() return ReadCastbarBackend() ~= "HIDE" end,
                set = function(value) SetCastbarEnabled(value == true) end,
            },
        })
        castbarNoticeButton:SetScript("OnClick", function()
            SetCastbarBackend("MSUF")
        end)
        Schema.Owned(castbarNoticeButton, unit, "castbar")
    end
    local enabled = PrepareCastbarSwitch(ctx, sec, unit)
    local provider
    if canUseBlizzardProvider then
        provider = ControlRow(ctx, providerCard, { "dropdown", "provider", "MSUF", { "Castbar provider", CASTBAR_BACKEND_VALUES, min(260,
            controlWRight) }, { 16, -52, min(260, controlWRight) },
            get = ReadCastbarProvider,
            set = SetCastbarProvider,
            scope = unit, meta = SettingMeta(ctx, "castbar.provider", "general", fields.backend),
            beforeBind = function(widget)
                -- Player castbar ownership is independent from Player UnitFrame
                -- ownership, so the page-level frame-disabled gate must not lock this
                -- provider selector while the MSUF Player frame is off.
                widget._msuf2UnitFrameGateAlwaysEnabled = true
                W.AttachUnitEditFocus(widget, unit, "castbar")
            end,
        })
    else
        ControlRow(ctx, providerCard, { "text", "menu2.uf_" .. unit .. ".unit.visuals.providerCard.description", nil,
            { "MSUF castbar", 16, -58, rightW - 32 }, scope = unit, domain = "description" })
    end
    local interrupt = ControlRow(ctx, generalCard, { "toggle", "interrupt", true, { "Show interrupt", 16, -84, 240 },
        get = function() return ReadBool(unit, "showInterrupt", true) end,
        set = function(v) SetBool(unit, "showInterrupt", v, "MSUF2_CASTBAR_INTERRUPT", { castbar = true, preview = true }) end,
        scope = unit, meta = SettingMeta(ctx, "castbar.show_interrupt", unit, "showInterrupt"),
        beforeBind = s.PrepareControl,
    })
    -- Appends the interrupter's class-colored name to the Interrupted feedback
    -- (Blizzard's SPELL_INTERRUPTED_BY format); resolution is secret-safe and
    -- falls back to the plain label against restricted identities.
    local interruptSource = ControlRow(ctx, generalCard, { "toggle", "interruptSource", false, { "Show interrupter name", 16, -116, 240 },
        get = function() return ReadBool(unit, "showInterruptSource", false) end,
        set = function(v) SetBool(unit, "showInterruptSource", v, "MSUF2_CASTBAR_INTERRUPT_SOURCE", { castbar = true, preview = true }) end,
        scope = unit, meta = SettingMeta(ctx, "castbar.show_interrupt_source", unit, "showInterruptSource"),
        beforeBind = s.PrepareControl,
    })
    BindExactCastbarTabTarget(interruptSource, "general", tostring(unit) .. ".showInterruptSource")
    local sizeCardW = sizeCard._msuf2Width or (sectionW - 32)
    local sizeRightX = max(350, floor(sizeCardW * 0.52))
    local sizeControlWLeft = min(300, max(220, sizeRightX - 42))
    local sizeControlWRight = min(320, max(220, sizeCardW - sizeRightX - 24))
    local widthMode = ControlRow(ctx, sizeCard, { "dropdown", "widthMode", "manual", { "Width mode", CASTBAR_WIDTH_SOURCE_VALUES,
        sizeControlWLeft }, { 16, -52, sizeControlWLeft },
        get = ReadWidthSource,
        set = function(v)
            local key = CastbarWidthSourceKey()
            if not key then return end
            local nextValue = NormalizeWidthSource(v)
            SetGeneralValue(key, nextValue, "MSUF2_CASTBAR_WIDTH_MODE")
            RefreshCastbarEnabled()
        end,
        scope = unit, meta = SettingMeta(ctx, "castbar.width_mode", "general", CastbarWidthSourceKey()),
        beforeBind = s.PrepareControl, castbarControl = true,
    })
    local widthKey = CastbarWidthKey()
    local heightKey = CastbarHeightKey()
    local defaultSize = CASTBAR_DEFAULT_SIZE[unit] or CASTBAR_DEFAULT_SIZE.target
    local manualWidth = ControlRow(ctx, sizeCard, { "slider", "manualWidth", defaultSize.width, { "Manual width", 40, 900, 1, sizeControlWRight },
        { sizeRightX, -52, sizeControlWRight },
        get = function() return ReadGeneralNumber(widthKey, defaultSize.width) end,
        set = function(v)
            if not widthKey then return end
            SetGeneralNumber(widthKey, v, "MSUF2_CASTBAR_WIDTH")
        end,
        scope = unit, meta = SettingMeta(ctx, "castbar.manual_width", "general", widthKey), roundStep = true,
        beforeBind = s.PrepareControl, castbarControl = true,
    })
    local height = ControlRow(ctx, sizeCard, { "slider", "height", defaultSize.height, { "Height", 6, 80, 1, sizeControlWRight }, { sizeRightX,
        -106, sizeControlWRight },
        get = function() return ReadGeneralNumber(heightKey, defaultSize.height) end,
        set = function(v)
            if not heightKey then return end
            SetGeneralNumber(heightKey, v, "MSUF2_CASTBAR_HEIGHT")
        end,
        scope = unit, meta = SettingMeta(ctx, "castbar.height", "general", heightKey), roundStep = true,
        beforeBind = s.PrepareControl, castbarControl = true,
    })
    s.castbarNotice, s.enabled, s.provider, s.interrupt = castbarNotice, enabled, provider, interrupt
    s.manualWidth, s.defaultSize = manualWidth, defaultSize
end
function CastbarSection.IconAndText(s)
    local ctx, unit, fields, rightW, RefreshCastbarEnabled = s.ctx, s.unit, s.fields, s.rightW, s.RefreshCastbarEnabled
    local iconControls, spellControls, targetNameControls = s.iconControls, s.spellControls, s.targetNameControls
    local DetailKey, ReadGeneralValue = s.DetailKey, s.ReadGeneralValue
    local BuildDetailControls, controlWLeft, controlWRight = s.BuildDetailControls, s.controlWLeft, s.controlWRight
    local iconCard, portraitIconCard, spellCard = s.iconCard, s.portraitIconCard, s.spellCard
    local targetNameCard = s.targetNameCard
    local function BindCastbarFeatureToggle(parent, field, reason)
        local control = ControlRow(ctx, parent, { "switch", field, true, { "Enable", 16, -52, 160 },
            get = function() return ReadGeneralBool(field, true) end,
            set = function(v)
                SetGeneralBool(field, v, reason, { castbar = true, preview = true })
                RefreshCastbarEnabled()
            end,
            scope = unit, meta = SettingMeta(ctx, "castbar.feature." .. tostring(reason), "general", field),
            beforeBind = s.PrepareControl,
        })
        return control
    end
    local icon = BindCastbarFeatureToggle(iconCard, fields.icon, "MSUF2_CASTBAR_ICON")
    BuildDetailControls(iconCard, iconControls, {
        { "dropdown", DetailKey("IconPosition"), "LEFT", { "Position", CASTBAR_ICON_POSITIONS, min(260, controlWLeft) }, { 16, -88, min(260,
            controlWLeft) }, reason = "MSUF2_CASTBAR_ICON_POSITION" },
        { "slider", DetailKey("IconSize"), 0, { "Size", 0, 128, 1, controlWLeft }, { 16, -142, controlWLeft }, reason = "MSUF2_CASTBAR_ICON_SIZE" },
        { "slider", DetailKey("IconZoom"), 100, { "Icon Zoom (%)", 100, 200, 1, controlWLeft }, { 16, -196, controlWLeft },
            reason = "MSUF2_CASTBAR_ICON_ZOOM" },
        { "slider", DetailKey("IconSpacing"), 1, { "Spacing", 0, 40, 1, controlWLeft }, { 16, -250, controlWLeft }, reason = "MSUF2_CASTBAR_ICON_SPACING" },
        { "slider", DetailKey("IconBorderThickness"), 0, { "Border thickness", 0, 8, 1, controlWLeft }, { 16, -304, controlWLeft },
            reason = "MSUF2_CASTBAR_ICON_BORDER_THICKNESS", beforeSet = function(v)
            if tonumber(v) and tonumber(v) > 0 and tostring(ReadGeneralValue(DetailKey("IconBorderStyle"), "DARK")):upper() == "NONE" then
                GetGeneral()[DetailKey("IconBorderStyle")] = "DARK"
                -- The Border style dropdown below must show what this just
                -- wrote. Only the one-shot upgrade refreshes, never every tick
                -- of the drag.
                M.RequestRefresh(ctx, "castbar-icon-border-style-upgrade")
            end
        end },
        { "dropdown", DetailKey("IconBorderStyle"), "DARK", { "Border Style", CASTBAR_ICON_BORDER_STYLES, min(260, controlWLeft) }, { 16, -358,
            min(260, controlWLeft) }, reason = "MSUF2_CASTBAR_ICON_BORDER_STYLE", afterSet = function()
                -- The Castbar Icon Border Color shortcut is relevant only for
                -- the Castbar style, so its ::: dot re-evaluates on every
                -- change here.
                M.RequestRefresh(ctx, "castbar-icon-border-style")
            end },
    })
    -- Second surface for the Portrait section's cast-icon toggle: players look for
    -- it next to the castbar icon options. Both toggles write the same per-unit key
    -- and request a page refresh, so whichever one is clicked updates the other.
    -- It stays out of allCastbarControls/iconControls on purpose - the portrait
    -- cast icon is a portrait feature and works with any castbar backend.
    local portraitCastIcon = ControlRow(ctx, portraitIconCard, { "toggle", "portraitCastIcon", false, { "Show cast spell icon in portrait", 16, -52,
        rightW - 32 },
        get = function() return ReadBool(unit, "portraitCastSpellIcon", false) end,
        set = function(v)
            SetPortraitValue(unit, "portraitCastSpellIcon", v and true or false, "MSUF2_PORTRAIT_CAST_ICON")
            M.RequestRefresh(ctx, "portrait-cast-icon-mirror")
        end,
        scope = unit, meta = ReviewedMeta(ctx, "castbar.portrait_cast_icon", "setting", "duplicate",
            "Second surface for the Portrait section cast-icon toggle; that control owns the Search target for portraitCastSpellIcon."),
        beforeBind = function(widget)
            W.AttachUnitEditFocus(widget, unit, "portrait")
        end,
    })
    portraitCastIcon._msuf2SearchText = "Portrait cast spell icon casting channel empower castbar icon"
    local portraitCastIconNote = ControlRow(ctx, portraitIconCard, { "text", "menu2.uf_" .. unit .. ".unit.visuals.portraitIconCard.description", nil,
        { "The same setting as Portrait > More Options. It swaps the portrait for the spell icon while the unit casts, "
            .. "so the portrait has to be enabled.", 16, -86, rightW - 32 }, scope = unit, domain = "description" })
    if portraitCastIconNote.SetWordWrap then portraitCastIconNote:SetWordWrap(true) end
    local text = BindCastbarFeatureToggle(spellCard, fields.text, "MSUF2_CASTBAR_TEXT")
    BuildDetailControls(spellCard, spellControls, {
        { "dropdown", DetailKey("SpellNamePosition"), "LEFT", { "Position preset", CASTBAR_TEXT_POSITIONS, min(260, controlWLeft) }, { 16, -88,
            min(260, controlWLeft) }, reason = "MSUF2_CASTBAR_SPELL_POSITION" },
        { "slider", DetailKey("SpellNameFontSize"), 0, { "Size", 0, 48, 1, controlWLeft }, { 16, -142, controlWLeft }, reason = "MSUF2_CASTBAR_SPELL_SIZE" },
        -- Position owns the visible justification, matching Time Text.
        -- Spell text color deliberately lives on the Colors page (castbar
        -- detail colors) and in the per-control color shortcuts only; a second
        -- inline swatch here double-writes the same key.
    })
    local targetNameToggle
    if fields.targetName and targetNameCard then
        targetNameToggle = ControlRow(ctx, targetNameCard, { "switch", "targetNameToggle", false, { "Enable", 16, -52, 160 },
            get = function() return ReadGeneralBool(fields.targetName, false) end,
            set = function(v)
                SetGeneralBool(fields.targetName, v, "MSUF2_CASTBAR_TARGET_NAME", { castbar = true, preview = true })
                RefreshCastbarEnabled()
            end,
            scope = unit, meta = SettingMeta(ctx, "castbar.show_target_name", "general", fields.targetName),
            beforeBind = s.PrepareControl, castbarControl = true,
        })
        BuildDetailControls(targetNameCard, targetNameControls, {
            { "dropdown", DetailKey("TargetNamePosition"), "BELOW", { "Position preset", CASTBAR_TEXT_POSITIONS, min(260, controlWRight) }, { 16, -88,
                min(260, controlWRight) }, reason = "MSUF2_CASTBAR_TARGET_NAME_POSITION" },
            { "slider", DetailKey("TargetNameFontSize"), 10, { "Size", 6, 48, 1, controlWRight }, { 16, -142, controlWRight },
                reason = "MSUF2_CASTBAR_TARGET_NAME_SIZE" },
            { "dropdown", DetailKey("TargetNameAlign"), "RIGHT", { "Alignment", CASTBAR_TEXT_ALIGN, min(260, controlWRight) }, { 16, -196, min(260,
                controlWRight) }, reason = "MSUF2_CASTBAR_TARGET_NAME_ALIGN" },
            -- Target text color deliberately lives on the Colors page (castbar
            -- detail colors) and in the per-control color shortcuts only; a second
            -- inline swatch here double-writes the same key.
        })
    end
    s.BindCastbarFeatureToggle, s.icon, s.portraitCastIcon = BindCastbarFeatureToggle, icon, portraitCastIcon
    s.text, s.targetNameToggle = text, targetNameToggle
end
function CastbarSection.Advanced(s)
    local ctx, unit, fields, rightW, RefreshCastbarEnabled = s.ctx, s.unit, s.fields, s.rightW, s.RefreshCastbarEnabled
    local iconControls, spellControls, timeControls = s.iconControls, s.spellControls, s.timeControls
    local AddControl, DetailKey, CastbarWidthKey = s.AddControl, s.DetailKey, s.CastbarWidthKey
    local ReadGeneralValue, ReadGeneralNumber = s.ReadGeneralValue, s.ReadGeneralNumber
    local SetGeneralValue, SetGeneralNumber = s.SetGeneralValue, s.SetGeneralNumber
    local BuildDetailControls, controlWLeft, controlWRight = s.BuildDetailControls, s.controlWLeft, s.controlWRight
    local timeCard, textAdvancedCard, iconAdvancedCard = s.timeCard, s.textAdvancedCard, s.iconAdvancedCard
    local layerAdvancedCard, defaultSize = s.layerAdvancedCard, s.defaultSize
    local BindCastbarFeatureToggle = s.BindCastbarFeatureToggle
    local function ReadSpellTextWidthMode()
        local value = tostring(ReadGeneralValue(DetailKey("SpellNameTruncate"), "AUTO") or "AUTO"):upper()
        if value == "CLIP" or value == "NONE" then return value end
        return "AUTO"
    end
    local function IsManualSpellTextWidth()
        return ReadSpellTextWidthMode() == "CLIP"
    end
    local function DefaultSpellTextManualWidth()
        local value = ReadGeneralNumber(CastbarWidthKey(), defaultSize.width) - 64
        return max(40, min(260, floor(value + 0.5)))
    end
    local spellTextWidthMode = ControlRow(ctx, textAdvancedCard, { "dropdown", "spellTextWidthMode", "AUTO", { "Width behavior",
        CASTBAR_TRUNCATE_VALUES, min(260, controlWLeft) }, { 16, -52, min(260, controlWLeft) },
        get = ReadSpellTextWidthMode,
        set = function(v)
            local nextValue = tostring(v or "AUTO"):upper()
            if nextValue ~= "CLIP" and nextValue ~= "NONE" then nextValue = "AUTO" end
            SetGeneralValue(DetailKey("SpellNameTruncate"), nextValue, "MSUF2_CASTBAR_SPELL_TRUNCATE")
            if nextValue == "CLIP" and ReadGeneralNumber(DetailKey("SpellNameMaxWidth"), 0) <= 0 then
                SetGeneralNumber(DetailKey("SpellNameMaxWidth"), DefaultSpellTextManualWidth(), "MSUF2_CASTBAR_SPELL_MAX_WIDTH")
            end
            RefreshCastbarEnabled()
        end,
        scope = unit, meta = ReviewedMeta(ctx, "castbar.spell_text_width_mode", "setting", "compound",
            "Selecting manual width can initialize the paired maximum-width value."),
        beforeBind = function(widget)
            AddControl(spellControls, widget)
            W.AttachUnitEditFocus(widget, unit, "castbar")
        end,
    })
    local spellTextManualWidth = ControlRow(ctx, textAdvancedCard, { "slider", "spellTextManualWidth", 0, { "Manual text width", 20, 500, 1,
        controlWLeft }, { 16, -106, controlWLeft },
        get = function() return ReadGeneralNumber(DetailKey("SpellNameMaxWidth"), 0) end,
        set = function(v) SetGeneralNumber(DetailKey("SpellNameMaxWidth"), v, "MSUF2_CASTBAR_SPELL_MAX_WIDTH") end,
        scope = unit, meta = SettingMeta(ctx, "castbar.spell_text_manual_width", "general", DetailKey("SpellNameMaxWidth")), roundStep = true,
        beforeBind = s.PrepareControl, castbarControl = true,
    })
    BuildDetailControls(iconAdvancedCard, iconControls, {
        { "slider", DetailKey("IconFrameLevelOffset"), 0, { "Layer (0-30)", 0, 30, 1, controlWRight }, { 16, -52, controlWRight },
            reason = "MSUF2_CASTBAR_ICON_LAYER" },
    })
    local iconLayerDescription = ControlRow(ctx, iconAdvancedCard, { "text", "menu2.uf_" .. unit .. ".unit.visuals.iconAdvancedCard.description", nil,
        { "0 keeps the icon just above the bar and moves it together with the whole-castbar layer. "
            .. "1-30 pins the icon to that frame level on the shared layer scale, so it can be ordered in front of or behind the bar, texts, "
            .. "and other frame elements.", 16, -106, rightW - 32 }, scope = unit, domain = "description" })
    if iconLayerDescription.SetWordWrap then iconLayerDescription:SetWordWrap(true) end
    local castbarLayer = ControlRow(ctx, layerAdvancedCard, { "slider", "castbarLayer", 6, { "Layer (0-30)", 0, 30, 1, controlWRight }, { 16, -52,
        controlWRight },
        get = function() return ReadGeneralNumber(DetailKey("FrameLevelOffset"), 6) end,
        set = function(v) SetGeneralNumber(DetailKey("FrameLevelOffset"), v, "MSUF2_CASTBAR_LAYER") end,
        scope = unit, meta = SettingMeta(ctx, "castbar.frame_layer", "general", DetailKey("FrameLevelOffset")), roundStep = true,
        beforeBind = s.PrepareControl, castbarControl = true,
    })
    local castbarLayerDescription = ControlRow(ctx, layerAdvancedCard, { "text", "menu2.uf_" .. unit .. ".unit.visuals.layerAdvancedCard.description", nil,
        { "Applies to the entire castbar: bar, icon, all text, effects, and border. "
            .. "All MSUF elements share this 0-30 order; every part of layer 30 draws above every part of layer 29.",
            16, -108, rightW - 32 }, scope = unit, domain = "description" })
    if castbarLayerDescription.SetWordWrap then castbarLayerDescription:SetWordWrap(true) end
    local time = BindCastbarFeatureToggle(timeCard, fields.time, "MSUF2_CASTBAR_TIME")
    BuildDetailControls(timeCard, timeControls, {
        { "dropdown", fields.timeFormat, "CURRENT", { "Format", CASTBAR_TIME_FORMATS, min(260, controlWLeft) }, { 16, -88, min(260, controlWLeft) },
            reason = "MSUF2_CASTBAR_TIME_FORMAT" },
        { "dropdown", DetailKey("TimePosition"), "RIGHT", { "Position preset", CASTBAR_TEXT_POSITIONS, min(260, controlWLeft) }, { 16, -142,
            min(260, controlWLeft) }, reason = "MSUF2_CASTBAR_TIME_POSITION" },
        { "slider", DetailKey("TimeFontSize"), 0, { "Size", 0, 48, 1, controlWLeft }, { 16, -196, controlWLeft }, reason = "MSUF2_CASTBAR_TIME_SIZE" },
        -- Cast time color deliberately lives on the Colors page (castbar
        -- detail colors) and in the per-control color shortcuts only; a second
        -- inline swatch here double-writes the same key.
    })
    s.IsManualSpellTextWidth, s.spellTextManualWidth, s.time = IsManualSpellTextWidth, spellTextManualWidth, time
end
local function BuildCastbar(ctx, builder, unit)
    local fields = CASTBAR_FIELDS[unit]
    if not fields then return end
    local sec = builder:CollapsibleSection("castbar", "Castbar", CastbarTabHeight(unit, CurrentCastbarTab(unit)), false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 16
    local cardGap = 28
    local leftW = floor((sectionW - 48 - cardGap) * 0.5)
    leftW = max(310, min(430, leftW))
    local rightX = leftX + leftW + cardGap
    local rightW = max(310, min(430, sectionW - rightX - 16))
    local prefix = CASTBAR_PREFIX[unit]
    local RefreshCastbarEnabled = M.RefreshProxy()
    local canUseBlizzardProvider = (unit == "player")
    local allCastbarControls, iconControls, spellControls, targetNameControls, timeControls = {}, {}, {}, {}, {}
    local s = {
        ctx = ctx, builder = builder, unit = unit, fields = fields, sec = sec, sectionW = sectionW, leftX = leftX,
        cardGap = cardGap, leftW = leftW, rightX = rightX, rightW = rightW, prefix = prefix,
        RefreshCastbarEnabled = RefreshCastbarEnabled, canUseBlizzardProvider = canUseBlizzardProvider,
        allCastbarControls = allCastbarControls, iconControls = iconControls, spellControls = spellControls,
        targetNameControls = targetNameControls, timeControls = timeControls,
    }
    CastbarSection.Binders(s)
    CastbarSection.Cards(s)
    CastbarSection.Tabs(s)
    CastbarSection.General(s)
    CastbarSection.IconAndText(s)
    CastbarSection.Advanced(s)
    local ReadWidthSource, ReadCastbarBackend, castbarNotice = s.ReadWidthSource, s.ReadCastbarBackend, s.castbarNotice
    local enabled, provider, interrupt, manualWidth, icon = s.enabled, s.provider, s.interrupt, s.manualWidth, s.icon
    local portraitCastIcon, text, targetNameToggle = s.portraitCastIcon, s.text, s.targetNameToggle
    local IsManualSpellTextWidth, spellTextManualWidth, time = s.IsManualSpellTextWidth, s.spellTextManualWidth, s.time
    local castbarFeatureToggles = { time, interrupt, icon, text, targetNameToggle }
    local function MsufOn() return ReadCastbarBackend() == "MSUF" end
    -- Hover reason for the locked castbar controls: the section notice wording.
    local function BackendReason()
        local backend = ReadCastbarBackend()
        if backend == "MSUF" then return nil end
        if backend == "HIDE" then return M.Format("%s castbar is off. Turn it on to use the MSUF castbar.", UnitTopLabel(unit)) end
        return M.Format("%s castbar uses Blizzard. Select MSUF to adjust castbar layout and text behavior.", UnitTopLabel(unit))
    end
    RefreshCastbarEnabled = RefreshCastbarEnabled(M.BindGateGroup(ctx, nil, {
        { enable = { enabled }, controls = castbarFeatureToggles, on = MsufOn, reason = BackendReason },
        { controls = provider, when = function() return provider ~= nil end, on = function() return ReadCastbarBackend() ~= "HIDE" end,
            reason = BackendReason },
        { controls = allCastbarControls, on = MsufOn, reason = BackendReason },
        { controls = manualWidth, on = function() return MsufOn() and ReadWidthSource() == "manual" end },
        { controls = iconControls, on = function() return MsufOn() and ReadGeneralBool(fields.icon, true) end },
        { controls = spellControls, on = function() return MsufOn() and ReadGeneralBool(fields.text, true) end },
        { controls = targetNameControls, on = function() return MsufOn() and fields.targetName and ReadGeneralBool(fields.targetName, false) end },
        { controls = spellTextManualWidth, on = function() return MsufOn() and ReadGeneralBool(fields.text, true) and IsManualSpellTextWidth() end },
        { controls = timeControls, on = function() return MsufOn() and ReadGeneralBool(fields.time, true) end },
        -- Mirrored portrait setting: gated by the portrait, never by the castbar.
        { controls = portraitCastIcon, on = function() return NormalizePortrait(unit) ~= "OFF" end },
    }, {
        also = function()
            local backend = ReadCastbarBackend()
            if backend ~= "MSUF" then
                if backend == "HIDE" then
                    castbarNotice:SetMessage(M.Format("%s castbar is off. Turn it on to use the MSUF castbar.", UnitTopLabel(unit)), "warning")
                else
                    castbarNotice:SetMessage(M.Format("%s castbar uses Blizzard. Select MSUF to adjust castbar layout and text behavior.",
                        UnitTopLabel(unit)), "warning")
                end
                castbarNotice:Show()
            else
                castbarNotice:Hide()
            end
            SetSectionHeaderStatus(sec, nil)
        end,
        track = function(c, r) return M.TrackCollapsibleRefresh(c, sec, r) end,
    }))
end
if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({ id = "portrait", title = "Portrait", height = function(ctx, _, unit) return PortraitLayoutForWidth(ctx and ctx.width,
        CurrentPortraitTab(unit)).height end, placement = "after_inline_text", order = 10, build = BuildPortrait,
        prepareShell = function(ctx, sec, unit) PreparePortraitSwitch(ctx, sec, unit) end })
    UP.RegisterSection({ id = "power", sectionId = "power_bar", title = "Power Bar", height = function(_, _, unit) return PowerSectionHeight(unit) end,
        placement = "after_inline_text", order = 20, units = POWER_UNITS, build = BuildPower, prepareShell = PreparePowerSwitch })
    UP.RegisterSection({ id = "castbar", title = "Castbar", height = function(_, _, unit) return CastbarTabHeight(unit, CurrentCastbarTab(unit)) end,
        placement = "after_inline_text", order = 30, units = CASTBAR_UNITS, build = BuildCastbar, prepareShell = PrepareCastbarSwitch })
end
