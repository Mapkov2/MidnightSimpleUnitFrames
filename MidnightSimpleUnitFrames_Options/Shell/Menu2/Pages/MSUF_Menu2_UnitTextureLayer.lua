local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local T = M.Theme or {}
local UP = M.UnitPage or {}
local VTP = M.ValueTextPairs
local floor = math.floor
local max = math.max

-- Decorative texture layer section (bottom of every unit page).
-- Three independent layer slots per frame, edited through one shared control
-- set: the slot bar picks the layer, the category bar picks the sub-page
-- (General / Placement / Style / Visibility), and every binding resolves its
-- DB key against the selected slot at read/write time. The runtime lives in
-- UnitFrames/Effects/MSUF_UF_TextureLayer.lua and re-stamps cold path only.
local SLOT_PREFIXES = { "texLayer", "texLayer2", "texLayer3" }
local TEXLAYER_ANCHORS = VTP "TOPLEFT=Top Left|TOP=Top|TOPRIGHT=Top Right|LEFT=Left|CENTER=Center|RIGHT=Right|BOTTOMLEFT=Bottom Left|BOTTOM=Bottom|BOTTOMRIGHT=Bottom Right"
local TEXLAYER_STRATA = VTP "AUTO=Frame default|BACKGROUND=Background|LOW=Low|MEDIUM=Medium|HIGH=High|DIALOG=Dialog|TOOLTIP=Tooltip"
local TEXLAYER_ANCHOR_TARGETS = VTP "FRAME=Whole frame|HEALTH=Health bar|POWER=Power bar|PORTRAIT=Portrait"
local TEXLAYER_VISIBILITY = VTP "ALWAYS=Always|COMBAT=In combat only|OOC=Out of combat only|TARGET=Current target only"
local TEXLAYER_CROP_MODES = VTP "FULL=Full texture|TOP_HALF=Top half|BOTTOM_HALF=Bottom half"
local PAD_DIRECTION_SUFFIXES = { UP = "GradientDirUp", LEFT = "GradientDirLeft", RIGHT = "GradientDirRight", DOWN = "GradientDirDown" }
local TEXLAYER_TABS = M.WordList "general placement style visibility"
local TEXLAYER_TAB_TEXTS = { general = "General", placement = "Placement", style = "Style", visibility = "Visibility" }
local TEXLAYER_SECTION_H = 512
local TEXLAYER_CARD_Y = -108
local TEXLAYER_CARD_H = 370
local HIGHLIGHT_TEXTURE_PRESET = {
    Texture = "",
    CustomTexturePath = "Interface\\PETBATTLES\\PetBattle-SelectedPetGlow",
    FollowFrameAlpha = true,
    Strata = "AUTO",
    Level = 1,
    AnchorTarget = "FRAME",
    Anchor = "CENTER",
    OffsetX = 0,
    OffsetY = 0,
    Width = 0,
    Height = 0,
    GradientEnabled = false,
    GradientDirRight = true,
    GradientDirLeft = false,
    GradientDirUp = false,
    GradientDirDown = false,
    BlendMode = "ADD",
    MirrorH = false,
    MirrorV = false,
    CropMode = "BOTTOM_HALF",
    EdgeSoftness = 0,
    RoundedClip = false,
}

local function HighlightTextureConfigured(conf, prefix)
    if type(conf) ~= "table" or type(prefix) ~= "string" then return false end
    for suffix, value in pairs(HIGHLIGHT_TEXTURE_PRESET) do
        if conf[prefix .. suffix] ~= value then return false end
    end
    return true
end

local function ApplyHighlightTextureConfig(conf, prefix, enabled)
    if type(conf) ~= "table" or type(prefix) ~= "string" then return false end
    local changed = false
    if enabled then
        local alpha = tonumber(conf[prefix .. "Alpha"])
        local colorMode = conf[prefix .. "ColorMode"]
        local initializeAppearance = (conf[prefix .. "Texture"] == nil or conf[prefix .. "Texture"] == "")
            and (conf[prefix .. "CustomTexturePath"] == nil or conf[prefix .. "CustomTexturePath"] == "")
            and (alpha == nil or alpha == 1)
            and (colorMode == nil or colorMode == "CUSTOM")
            and (tonumber(conf[prefix .. "ColorR"]) == nil or tonumber(conf[prefix .. "ColorR"]) == 1)
            and (tonumber(conf[prefix .. "ColorG"]) == nil or tonumber(conf[prefix .. "ColorG"]) == 1)
            and (tonumber(conf[prefix .. "ColorB"]) == nil or tonumber(conf[prefix .. "ColorB"]) == 1)
        for suffix, value in pairs(HIGHLIGHT_TEXTURE_PRESET) do
            local key = prefix .. suffix
            if conf[key] ~= value then
                conf[key] = value
                changed = true
            end
        end
        if initializeAppearance then
            local defaults = { Alpha = 0.05, ColorMode = "CUSTOM", ColorR = 1, ColorG = 0.82, ColorB = 0 }
            for suffix, value in pairs(defaults) do
                local key = prefix .. suffix
                if conf[key] ~= value then
                    conf[key] = value
                    changed = true
                end
            end
        end
    elseif HighlightTextureConfigured(conf, prefix) then
        -- Remove only the highlight recipe. Master enable, opacity,
        -- visibility and color remain independent.
        local replacements = {
            CustomTexturePath = "",
            CropMode = "FULL",
            BlendMode = "BLEND",
        }
        for suffix, value in pairs(replacements) do
            local key = prefix .. suffix
            if conf[key] ~= value then
                conf[key] = value
                changed = true
            end
        end
    end
    return changed
end
M.ApplyTextureLayerHighlightConfig = ApplyHighlightTextureConfig

local function BuildTextureLayer(ctx, builder, unit)
    local ReadBool = UP.ReadBool
    local SetBool = UP.SetBool
    local ReadNumber = UP.ReadNumber
    local SetNumber = UP.SetNumber
    local SetString = UP.SetString
    local SetControlEnabled = UP.SetControlEnabled
    local GetConf = UP.GetConf
    local Call = UP.Call
    local ReviewedMeta = UP.ReviewedMeta
    if not (ReadBool and SetBool and ReadNumber and SetNumber and SetString and SetControlEnabled and GetConf and Call and ReviewedMeta) then return end

    M.unitTexLayerSlot = M.unitTexLayerSlot or {}
    M.unitTexLayerTab = M.unitTexLayerTab or {}
    local function CurrentSlot()
        local slot = tonumber(M.unitTexLayerSlot[unit]) or 1
        if slot < 1 or slot > #SLOT_PREFIXES then slot = 1 end
        return slot
    end
    local function Key(base)
        return SLOT_PREFIXES[CurrentSlot()] .. base
    end
    local function RefreshLayer()
        Call("MSUF_RefreshUnitTextureLayers", unit)
    end
    local function SetHighlightTextureEnabled(enabled)
        if M.BlockCombatAction and M.BlockCombatAction() then return false end
        local conf = GetConf(unit)
        local prefix = SLOT_PREFIXES[CurrentSlot()]
        local changed = ApplyHighlightTextureConfig(conf, prefix, enabled)
        if not changed then return false end
        if M.RequestUnitApply then
            M.RequestUnitApply(unit, "MSUF2_TEXLAYER_HIGHLIGHT_TEXTURE", { preview = true, history = false })
        end
        RefreshLayer()
        if M.RequestRefresh then M.RequestRefresh(ctx, "texture-layer-highlight-texture") end
        return true
    end

    local sec = builder:CollapsibleSection("texture_layer", "Texture Layer", TEXLAYER_SECTION_H, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 20
    local innerW = max(320, sectionW - 40)
    local colGap = 16
    local colW = floor((innerW - 32 - colGap) / 2)
    local colX = 16 + colW + colGap

    local generalCard = W.ControlCard(sec, "General", nil, leftX, TEXLAYER_CARD_Y, innerW, TEXLAYER_CARD_H)
    local placementCard = W.ControlCard(sec, "Placement", nil, leftX, TEXLAYER_CARD_Y, innerW, TEXLAYER_CARD_H)
    local styleCard = W.ControlCard(sec, "Style", nil, leftX, TEXLAYER_CARD_Y, innerW, TEXLAYER_CARD_H)
    local visibilityCard = W.ControlCard(sec, "Visibility", nil, leftX, TEXLAYER_CARD_Y, innerW, TEXLAYER_CARD_H)
    local cardsByTab = { general = generalCard, placement = placementCard, style = styleCard, visibility = visibilityCard }

    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(styleCard, function()
            local slotIds = { "texture_layer", "texture_layer2", "texture_layer3" }
            local slotId = slotIds[CurrentSlot()] or "texture_layer"
            local refs = { slotId .. ".color" }
            if GetConf(unit)[Key("GradientEnabled")] == true then
                refs[#refs + 1] = slotId .. ".gradient"
            end
            return refs
        end, {
            title = "Texture Layer Colors",
            note = "These colors are shared from the Colors page.",
            historySource = "menu:unit-texture-layer-colors",
            context = function() return { unit = unit } end,
        })
    end

    local dependentControls = {}
    local function Track(control)
        dependentControls[#dependentControls + 1] = control
        return control
    end
    local function LayerMeta(base, path, step)
        local meta = ReviewedMeta(ctx, "texture_layer." .. (path or base), "setting", "dynamic",
            "This control edits the texture-layer slot selected in the accordion's slot bar.")
        local keys = {}
        for i = 1, #SLOT_PREFIXES do keys[i] = tostring(unit) .. "." .. SLOT_PREFIXES[i] .. base end
        meta.assistantSettingKeys = keys
        if step and meta then meta.step, meta.roundStep = step, true end
        return meta
    end
    local function BindLayerToggle(parent, label, x, y, width, base, default, after)
        local control = W.ToggleAt(parent, label, x, y, width)
        M.BindBoolWidget(ctx, control,
            function() return ReadBool(unit, Key(base), default) end,
            function(v)
                SetBool(unit, Key(base), v, "MSUF2_TEXLAYER", { preview = true })
                RefreshLayer()
                if after then after() end
            end,
            LayerMeta(base))
        return control
    end
    local function BindLayerSlider(parent, label, x, y, width, minV, maxV, step, base, default, percent)
        local control = W.Slider(parent, label, minV, maxV, step, width - 58)
        if percent then
            M.UsePercentInput(control)
        elseif control.SetValueFormatter then
            control:SetValueFormatter(function(v) return tostring(floor((tonumber(v) or 0) + 0.5)) end)
        end
        M.BindNumberWidget(ctx, control,
            function() return ReadNumber(unit, Key(base), default) end,
            function(v)
                SetNumber(unit, Key(base), v, "MSUF2_TEXLAYER", { preview = true })
                RefreshLayer()
            end,
            default,
            LayerMeta(base, nil, percent and nil or step))
        W.MoveWidget(control, parent, x, y, width - 58, "LEFT")
        return control
    end
    local function BindLayerDropdown(parent, label, x, y, width, values, base, default)
        local control = W.Dropdown(parent, label, values, width)
        M.BindDropdownWidget(ctx, control,
            function()
                local value = GetConf(unit)[Key(base)]
                if value == nil or value == "" then value = default end
                return value
            end,
            function(v)
                SetString(unit, Key(base), v or default, "MSUF2_TEXLAYER", { preview = true })
                RefreshLayer()
            end,
            LayerMeta(base))
        W.MoveWidget(control, parent, x, y, width, "LEFT")
        return control
    end

    -- General: enable, art sources, layering.
    BindLayerToggle(generalCard, "Enable Texture Layer", 16, -54, colW - 16, "Enabled", false, function()
        M.RequestRefresh(ctx, "MSUF2_TEXLAYER_ENABLE")
    end)
    Track(BindLayerDropdown(generalCard, "Texture (SharedMedia)", 16, -114, colW - 16,
        function() return M.StatusBarTextureItems("Use bar texture") end, "Texture", ""))
    Track(BindLayerDropdown(generalCard, "Frame strata", 16, -190, colW - 16, TEXLAYER_STRATA, "Strata", "AUTO"))
    Track(BindLayerSlider(generalCard, "Layer (0-30)", colX, -62, colW, 0, 30, 1, "Level", 1))
    local customPath = W.TextInput(generalCard, "Custom texture path", colW - 16)
    M.BindTextInput(ctx, customPath,
        function() return tostring(GetConf(unit)[Key("CustomTexturePath")] or "") end,
        function(v)
            SetString(unit, Key("CustomTexturePath"), v or "", "MSUF2_TEXLAYER", { preview = true })
            RefreshLayer()
        end,
        true,
        LayerMeta("CustomTexturePath"))
    W.MoveWidget(customPath, generalCard, colX, -140, colW - 16, "LEFT")
    Track(customPath)
    local highlightTexture = W.ToggleAt(generalCard, "Highlight texture", 16, -264, colW - 16)
    M.BindBoolWidget(ctx, highlightTexture,
        function()
            local prefix = SLOT_PREFIXES[CurrentSlot()]
            return HighlightTextureConfigured(GetConf(unit), prefix)
        end,
        SetHighlightTextureEnabled,
        ReviewedMeta(ctx, "texture_layer.highlight_texture", "ephemeral", "ephemeral",
            "Applies or removes the built-in highlight appearance without changing whether the texture layer is enabled."))
    local classColor = W.ToggleAt(generalCard, "Class color", colX, -264, colW - 16)
    M.BindBoolWidget(ctx, classColor,
        function() return GetConf(unit)[Key("ColorMode")] == "CLASS" end,
        function(enabled)
            SetString(unit, Key("ColorMode"), enabled and "CLASS" or "CUSTOM",
                "MSUF2_TEXLAYER", { preview = true })
            RefreshLayer()
        end,
        LayerMeta("ColorMode", "class_color"))
    Track(classColor)
    local currentTargetOnly = W.ToggleAt(generalCard, "Current target only", 16, -310, colW - 16)
    M.BindBoolWidget(ctx, currentTargetOnly,
        function() return GetConf(unit)[Key("Visibility")] == "TARGET" end,
        function(enabled)
            SetString(unit, Key("Visibility"), enabled and "TARGET" or "ALWAYS",
                "MSUF2_TEXLAYER", { preview = true })
            RefreshLayer()
        end,
        LayerMeta("Visibility", "current_target_only"))
    Track(currentTargetOnly)

    -- Placement: Preview owns position; this card keeps anchor target and size.
    Track(BindLayerDropdown(placementCard, "Anchor to", 16, -54, colW - 16, TEXLAYER_ANCHOR_TARGETS, "AnchorTarget", "FRAME"))
    Track(BindLayerDropdown(placementCard, "Anchor", 16, -130, colW - 16, TEXLAYER_ANCHORS, "Anchor", "TOP"))
    Track(BindLayerSlider(placementCard, "Width", 16, -214, colW, 0, 600, 1, "Width", 0))
    Track(BindLayerSlider(placementCard, "Height (0 = auto)", colX, -62, colW, 0, 120, 1, "Height", 16))
    W.LabelAt(placementCard, "Use the colored Texture handle in Preview for exact placement.", colX, -130,
        colW - 16, "GameFontNormalSmall", T.colors and T.colors.muted)
    Track(BindLayerDropdown(placementCard, "Texture region", colX, -214, colW - 16,
        TEXLAYER_CROP_MODES, "CropMode", "FULL"))

    -- Style: gradient with a Bars-style direction D-pad, blend, mirroring,
    -- opacity and a four-edge feather mask. Color selection lives in the
    -- compact General toggle and on the Colors page/context shortcut.
    local padButtons = {}
    local pad
    local function DirectionActive(value)
        return ReadBool(unit, Key(PAD_DIRECTION_SUFFIXES[value]), value == "RIGHT")
    end
    local function AnyDirectionActive()
        return DirectionActive("UP") or DirectionActive("LEFT") or DirectionActive("RIGHT") or DirectionActive("DOWN")
    end
    local function RefreshGradientControls()
        local on = ReadBool(unit, Key("Enabled"), false) and ReadBool(unit, Key("GradientEnabled"), false)
        if pad and pad.SetAlpha then pad:SetAlpha(on and 1 or 0.45) end
        for value, btn in pairs(padButtons) do
            if btn.SetActive then btn:SetActive(DirectionActive(value)) end
            SetControlEnabled(btn, on)
        end
    end
    Track(BindLayerToggle(styleCard, "Gradient", 16, -54, colW - 16, "GradientEnabled", false, RefreshGradientControls))
    W.LabelAt(styleCard, "Direction", 16, -88, colW - 16, "GameFontNormalSmall", T.colors and T.colors.accent)
    local padW, padH = 104, 78
    local padButtonW, padButtonH = 22, 18
    pad = T.Panel(styleCard, nil, (T.colors and T.colors.panel2) or { 0.014, 0.038, 0.072, 0.55 }, T.colors and T.colors.borderSoft)
    pad:SetPoint("TOPLEFT", styleCard, "TOPLEFT", 16, -110)
    pad:SetSize(padW, padH)
    local padCenter = pad:CreateTexture(nil, "ARTWORK")
    padCenter:SetPoint("CENTER", pad, "CENTER", 0, 0)
    padCenter:SetSize(10, 10)
    local padCenterColor = (T.colors and T.colors.coreRim) or { 0.043, 0.096, 0.150 }
    padCenter:SetColorTexture(padCenterColor[1], padCenterColor[2], padCenterColor[3], 0.95)
    local function PadButton(text, value, x, buttonY)
        local btn = T.Button(pad, text, padButtonW, padButtonH)
        btn:SetPoint("TOPLEFT", pad, "TOPLEFT", x, buttonY)
        if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
        btn:SetScript("OnClick", function()
            local base = PAD_DIRECTION_SUFFIXES[value]
            SetBool(unit, Key(base), not DirectionActive(value), "MSUF2_TEXLAYER", { preview = true })
            -- Never leave the gradient without an edge: re-enable the clicked
            -- direction when it was the last active one (Bars pad behavior).
            if not AnyDirectionActive() then
                SetBool(unit, Key(base), true, "MSUF2_TEXLAYER", { preview = true })
            end
            RefreshLayer()
            RefreshGradientControls()
        end)
        if UP.RegisterControl then
            UP.RegisterControl(btn, ctx, "texture_layer.gradient_direction." .. value, "Gradient direction", "button", "ephemeral")
        end
        padButtons[value] = btn
        return btn
    end
    local padCenterX = (padW - padButtonW) * 0.5
    local padCenterY = (padH - padButtonH) * 0.5
    local padSideOffset = 23
    PadButton("^", "UP", padCenterX, -(padCenterY - padSideOffset))
    PadButton("<", "LEFT", padCenterX - padSideOffset, -padCenterY)
    PadButton(">", "RIGHT", padCenterX + padSideOffset, -padCenterY)
    PadButton("v", "DOWN", padCenterX, -(padCenterY + padSideOffset))
    Track(BindLayerSlider(styleCard, "Opacity", colX, -62, colW, 0, 1, 0.05, "Alpha", 1, true))
    local blend = W.ToggleAt(styleCard, "Additive glow", colX, -122, colW - 16)
    M.BindBoolWidget(ctx, blend,
        function() return GetConf(unit)[Key("BlendMode")] == "ADD" end,
        function(v)
            SetString(unit, Key("BlendMode"), v and "ADD" or "BLEND", "MSUF2_TEXLAYER", { preview = true })
            RefreshLayer()
        end,
        LayerMeta("BlendMode"))
    Track(blend)
    Track(BindLayerToggle(styleCard, "Mirror horizontally", colX, -168, colW - 16, "MirrorH", false))
    Track(BindLayerToggle(styleCard, "Mirror vertically", colX, -214, colW - 16, "MirrorV", false))
    Track(BindLayerSlider(styleCard, "Edge softness", colX, -272, colW, 0, 0.30, 0.02, "EdgeSoftness", 0, true))
    W.LabelAt(styleCard, "Fades all four outer edges; 0% keeps the original texture.", colX, -322,
        colW - 16, "GameFontNormalSmall", T.colors and T.colors.muted)

    -- Visibility: alpha inheritance, combat gating, rounded clipping.
    Track(BindLayerToggle(visibilityCard, "Follow frame transparency", 16, -54, colW - 16, "FollowFrameAlpha", true))
    Track(BindLayerDropdown(visibilityCard, "Show", 16, -114, colW - 16, TEXLAYER_VISIBILITY, "Visibility", "ALWAYS"))
    Track(BindLayerToggle(visibilityCard, "Clip to rounded frame", colX, -62, colW - 16, "RoundedClip", false))

    -- Slot + category bars. Both are menu-session state, never persisted.
    local function ApplyTab()
        local tab = M.unitTexLayerTab[unit]
        if not cardsByTab[tab] then tab = "general" end
        for key, card in pairs(cardsByTab) do
            W.SetControlShown(card, key == tab)
        end
    end
    local slotValues = {
        { value = 1, text = "Layer 1" },
        { value = 2, text = "Layer 2" },
        { value = 3, text = "Layer 3" },
    }
    local slotBar = W.ScopeOverrideBar(ctx, sec, {
        values = slotValues,
        width = sectionW,
        label = "Editing:",
        labelX = leftX,
        labelWidth = 64,
        centerY = -52,
        getValue = function() return CurrentSlot() end,
        setValue = function(value)
            M.unitTexLayerSlot[unit] = tonumber(value) or 1
            RefreshGradientControls()
            M.RequestRefresh(ctx, "MSUF2_TEXLAYER_SLOT")
        end,
    })
    if UP.RegisterControl then
        UP.RegisterControl(slotBar, ctx, "texture_layer.slot_selector", "Editing", "segment", "ephemeral")
    end
    local tabValues = {}
    for i = 1, #TEXLAYER_TABS do
        tabValues[i] = { value = TEXLAYER_TABS[i], text = TEXLAYER_TAB_TEXTS[TEXLAYER_TABS[i]] }
    end
    local tabBar = W.ScopeOverrideBar(ctx, sec, {
        values = tabValues,
        width = sectionW,
        label = "Category:",
        labelX = leftX,
        labelWidth = 64,
        centerY = -84,
        getValue = function() return cardsByTab[M.unitTexLayerTab[unit]] and M.unitTexLayerTab[unit] or "general" end,
        setValue = function(value)
            M.unitTexLayerTab[unit] = cardsByTab[value] and value or "general"
            ApplyTab()
        end,
    })
    if UP.RegisterControl then
        UP.RegisterControl(tabBar, ctx, "texture_layer.category_selector", "Category", "segment", "ephemeral")
    end
    ApplyTab()

    local function RefreshLayerControls()
        local on = ReadBool(unit, Key("Enabled"), false)
        for i = 1, #dependentControls do SetControlEnabled(dependentControls[i], on) end
        RefreshGradientControls()
    end
    RefreshLayerControls()
    M.TrackRefresh(ctx, RefreshLayerControls)
end
if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "texture_layer",
        title = "Texture Layer",
        height = TEXLAYER_SECTION_H,
        placement = "after_load_conditions",
        order = 30,
        build = BuildTextureLayer,
    })
end
