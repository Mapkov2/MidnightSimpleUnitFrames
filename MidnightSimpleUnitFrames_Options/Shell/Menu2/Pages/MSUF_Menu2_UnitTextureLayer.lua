local addonName, MSUF = ...
MSUF = MSUF or {}
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_UnitTextureLayer.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets or {}
local T = M.Theme or {}
local Schema = M.ControlSchema
local ROW_OPTIONS = Schema.UnitOptions()
local UP = M.UnitPage or {}
local VTP = M.ValueTextPairs
local Tr = M.TranslateText or M.Tr
local floor = math.floor
local max = math.max

-- Decorative texture layer section (bottom of every unit page).
-- Three independent texture slots per frame are edited through one shared
-- control set. This file only reorganizes the existing profile keys; runtime
-- interpretation remains owned by UnitFrames/Effects/MSUF_UF_TextureLayer.lua.
local SLOT_PREFIXES = { "texLayer", "texLayer2", "texLayer3" }
local TEXLAYER_ANCHORS = VTP("TOPLEFT=Top Left|TOP=Top|TOPRIGHT=Top Right|LEFT=Left|CENTER=Center|RIGHT=Right|BOTTOMLEFT=Bottom Left|BOTTOM=Bottom|" ..
    "BOTTOMRIGHT=Bottom Right")
local TEXLAYER_ANCHOR_TARGETS = VTP "FRAME=Whole frame|HEALTH=Health bar|POWER=Power bar|PORTRAIT=Portrait"
local TEXLAYER_COLOR_MODES = VTP "CUSTOM=Single color|CLASS=Class color|HEALTH=HP gradient"
local TEXLAYER_ABOVE_THRESHOLD_MODES = VTP "HEALTH=Continue HP gradient|CLASS=Class color|CUSTOM=Single color (monochrome)"
local TEXLAYER_VISIBILITY = VTP "ALWAYS=Any combat state|COMBAT=In combat|OOC=Out of combat"
local TEXLAYER_HEALTH_CONDITIONS = VTP "ANY=Any health|BELOW=Below threshold"
local TEXLAYER_CROP_MODES = VTP "FULL=Full texture|TOP_HALF=Top half|BOTTOM_HALF=Bottom half"
local TEXLAYER_COLOR_TREATMENTS = VTP "ORIGINAL=Original|MONOCHROME=Monochrome"
local PAD_DIRECTION_SUFFIXES = { UP = "GradientDirUp", LEFT = "GradientDirLeft", RIGHT = "GradientDirRight", DOWN = "GradientDirDown" }
local TEXLAYER_TABS = M.WordList "setup rules advanced"
local TEXLAYER_TAB_TEXTS = { setup = "Setup", rules = "HP & Visibility", advanced = "Advanced" }
local TEXLAYER_TAB_ALIASES = {
    general = "setup",
    placement = "setup",
    style = "advanced",
    visibility = "rules",
}
local TEXLAYER_SECTION_H = 596
local TEXLAYER_CARD_Y = -108
-- Source color is the lowest dropdown on Setup; keep its 22px button and
-- soft edge inside the card instead of letting them meet the next accordion.
local TEXLAYER_CARD_H = 454
-- What every quick setup resets: the drawing, the placement and the visibility
-- rules. The recipes below only state what makes each of them different.
local TEXLAYER_DRAW_RESET = {
    FollowFrameAlpha = true,
    Strata = "AUTO",
    Level = 1,
    GradientEnabled = false,
    MirrorH = false,
    MirrorV = false,
    EdgeSoftness = 0,
    RoundedClip = false,
}
local TEXLAYER_PLACEMENT_RESET = {
    Anchor = "CENTER",
    OffsetX = 0,
    OffsetY = 0,
    SizeMode = "MANUAL",
    ResponsiveSize = false,
    EdgeAttach = "FREE",
    Width = 0,
    Height = 0,
    GradientDirRight = true,
    GradientDirLeft = false,
    GradientDirUp = false,
    GradientDirDown = false,
}
local TEXLAYER_RULES_RESET = {
    Visibility = "ALWAYS",
    TargetOnly = false,
    HealthCondition = "ANY",
    HealthLowAlphaEnabled = false,
}
-- One new table holding the pairs of every given table; later tables win.
local function TextureLook(...)
    local look = {}
    for i = 1, select("#", ...) do
        for key, value in pairs((select(i, ...))) do look[key] = value end
    end
    return look
end
local TEXT_BACKGROUND_PRESET = TextureLook(TEXLAYER_DRAW_RESET, TEXLAYER_PLACEMENT_RESET, TEXLAYER_RULES_RESET, {
    Enabled = true,
    SourceMode = "SHAREDMEDIA",
    Texture = "",
    CustomTexturePath = "",
    AnchorTarget = "HEALTH",
    ColorMode = "CUSTOM",
    ColorTreatment = "MONOCHROME",
    Alpha = 0.65,
    BlendMode = "BLEND",
    CropMode = "FULL",
})
local HIGHLIGHT_TEXTURE_PRESET = TextureLook(TEXLAYER_DRAW_RESET, TEXLAYER_PLACEMENT_RESET, {
    Texture = "",
    CustomTexturePath = "Interface\\PETBATTLES\\PetBattle-SelectedPetGlow",
    AnchorTarget = "FRAME",
    BlendMode = "ADD",
    CropMode = "BOTTOM_HALF",
})

-- What a slot saved before source and sizing modes existed reads as.
local TEXLAYER_LEGACY_VALUES = { SizeMode = "MANUAL", ResponsiveSize = false, EdgeAttach = "FREE" }

-- Writes each suffix = value pair into the slot's keys and reports whether anything changed.
local function WriteSlotValues(conf, prefix, values)
    local changed = false
    for suffix, value in pairs(values) do
        local key = prefix .. suffix
        if conf[key] ~= value then
            conf[key] = value
            changed = true
        end
    end
    return changed
end

-- The highlight glow is a custom file path. The SharedMedia source ignores
-- custom paths and draws the bar texture instead, so a slot only counts as a
-- highlight while its source is not SharedMedia.
local function HighlightTextureConfigured(conf, prefix)
    if type(conf) ~= "table" or type(prefix) ~= "string" then return false end
    if conf[prefix .. "SourceMode"] == "SHAREDMEDIA" then return false end
    for suffix, value in pairs(HIGHLIGHT_TEXTURE_PRESET) do
        local current = conf[prefix .. suffix]
        if current == nil then current = TEXLAYER_LEGACY_VALUES[suffix] end
        if current ~= value then return false end
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
        changed = WriteSlotValues(conf, prefix, HIGHLIGHT_TEXTURE_PRESET)
        -- The glow replaces the slot's texture, whatever source it used, so
        -- only the highlight is drawn.
        if WriteSlotValues(conf, prefix, { SourceMode = "CUSTOM" }) then changed = true end
        if initializeAppearance
            and WriteSlotValues(conf, prefix, { Alpha = 0.05, ColorMode = "CUSTOM", ColorR = 1, ColorG = 0.82, ColorB = 0 }) then
            changed = true
        end
    elseif HighlightTextureConfigured(conf, prefix) then
        -- Remove only the highlight recipe. Master enable, opacity,
        -- visibility and color remain independent.
        changed = WriteSlotValues(conf, prefix, { SourceMode = "SHAREDMEDIA", CustomTexturePath = "", CropMode = "FULL", BlendMode = "BLEND" })
    end
    return changed
end
M.ApplyTextureLayerHighlightConfig = ApplyHighlightTextureConfig
M.TextureLayerTextBackgroundPreset = TEXT_BACKGROUND_PRESET

-- Bundled MSUF textures behind the third quick setup button. The catalog lives
-- in this load-on-demand page: the runtime only ever sees the chosen file path,
-- so the catalog costs nothing while the options are closed. Frame art leaves
-- an 82% x 30% window for the unit frame (ResolveLayerSize in the runtime fits
-- it around the frame); medallions are square and sit on the left frame edge.
-- Each group lists its textures as VALUE=Name pairs; the file is
-- msuf_texlayer_<value in lower case>.png.
local TEXLAYER_PACK_ROOT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\TextureLayers\\"
local TEXLAYER_PACK_GROUPS = {
    { role = "FRAME", text = "Frames", tooltip = "A complete frame that fits around the unit frame.", textures = [[
        MIDNIGHT_RAIL=Midnight Rail|MIDNIGHT_VECTOR=Midnight Vector|VOIDGLASS_HORIZON=Voidglass Horizon|TITANWEAVE=Titanweave|
        RUNEBLADE=Runeblade|EMBERFORGE=Emberforge|FROSTWARD=Frostward|WILDWOOD_NIGHT=Wildwood Night|DAWNSTEEL=Dawnsteel|
        BLOODSTONE_EDGE=Bloodstone Edge|ASTRAL_CIRCUIT=Astral Circuit|GRIMTHORN=Grimthorn|NIGHTFORGED=Nightforged|
        OBSIDIAN_VANGUARD=Obsidian Vanguard|ASTRAL_RUNE=Astral Rune|DRAGONBONE=Dragonbone|VERDANT_THORN=Verdant Thorn|
        MINIMAL_ECLIPSE=Minimal Eclipse]] },
    { role = "BASE", text = "Minimal frames", tooltip = "A thin frame outline that fits around the unit frame.", textures = [[
        MIN_BASE_HAIRLINE=Hairline|MIN_BASE_DOUBLE_RAIL=Double Rail|MIN_BASE_OPEN_BRACKET=Open Bracket|
        MIN_BASE_CENTER_NOTCH=Center Notch|MIN_BASE_STEPPED_TECH=Stepped Tech|MIN_BASE_ARCANE_CAPSULE=Arcane Capsule|
        MIN_BASE_SPLIT_HORIZON=Split Horizon|MIN_BASE_ASYM_VECTOR=Asym Vector|MIN_BASE_SHARD_CORNERS=Shard Corners|
        MIN_BASE_ECLIPSE_ARC=Eclipse Arc|MOD_SAFE_CORE=Safe Core]] },
    { role = "ACCENT", text = "Accents", tooltip = "A light accent. Put a frame in another texture slot to combine them.", textures = [[
        MIN_OVERLAY_MICRO_DOTS=Micro Dots|MIN_OVERLAY_RUNE_TICKS=Rune Ticks|MIN_OVERLAY_CORNER_GLINT=Corner Glint|
        MIN_OVERLAY_CENTER_SIGIL=Center Sigil|MIN_OVERLAY_ENERGY_SWEEP=Energy Sweep|MOD_CREST_TICKS=Crest Ticks|
        MOD_LOWER_RAIL=Lower Data Rail]] },
    { role = "CLASS", text = "Class accents", tooltip = "A light accent. Put a frame in another texture slot to combine them.", textures = [[
        CLASS_WARRIOR=Warrior|CLASS_PALADIN=Paladin|CLASS_HUNTER=Hunter|CLASS_ROGUE=Rogue|CLASS_PRIEST=Priest|
        CLASS_DEATHKNIGHT=Death Knight|CLASS_SHAMAN=Shaman|CLASS_MAGE=Mage|CLASS_WARLOCK=Warlock|CLASS_MONK=Monk|
        CLASS_DRUID=Druid|CLASS_DEMONHUNTER=Demon Hunter|CLASS_EVOKER=Evoker]] },
    { role = "ORNAMENT", text = "Medallions", tooltip = "A round medallion on the left frame edge.", textures = [[
        MOD_PORTRAIT_RING=Portrait Ring]] },
}
local TEXLAYER_PACK_BY_VALUE = {}
local TEXLAYER_PACK_BY_PATH = {}
local TEXLAYER_PACK_ITEMS = {}
for groupIndex = 1, #TEXLAYER_PACK_GROUPS do
    local group = TEXLAYER_PACK_GROUPS[groupIndex]
    TEXLAYER_PACK_ITEMS[#TEXLAYER_PACK_ITEMS + 1] = { value = "HEADER_" .. group.role, text = group.text, header = true }
    for value, text in group.textures:gmatch("([%u_]+)=([^|\r\n]+)") do
        local texture = { value = value, text = text, role = group.role, path = TEXLAYER_PACK_ROOT .. "msuf_texlayer_" .. value:lower() .. ".png" }
        TEXLAYER_PACK_BY_VALUE[value] = texture
        TEXLAYER_PACK_BY_PATH[texture.path] = texture
        TEXLAYER_PACK_ITEMS[#TEXLAYER_PACK_ITEMS + 1] = {
            value = value,
            text = text,
            previewKind = "statusbar",
            texturePreview = texture.path,
            tooltip = group.tooltip,
        }
    end
end

-- A fresh MSUF texture is a plain static layer: no class/HP color, no combat,
-- target or health rule, so it registers no runtime event at all.
local TEXLAYER_PACK_STATIC_LOOK = TextureLook(TEXLAYER_DRAW_RESET, TEXLAYER_RULES_RESET, {
    Alpha = 1,
    ColorMode = "CUSTOM",
    ColorTreatment = "ORIGINAL",
    ColorR = 1,
    ColorG = 1,
    ColorB = 1,
    BlendMode = "BLEND",
    CropMode = "FULL",
})

-- Writes one bundled texture into a slot and reports whether anything changed.
-- The texture fits itself around the frame (FRAME) or stays a square on the
-- left frame edge (medallion); Width/Height hold the fitted size for when the
-- user sizes it by hand. Swapping between MSUF textures keeps the slot's look
-- and rules, and keeps its placement while the kind (frame art vs. medallion)
-- stays the same. frameW/frameH are the unit's configured size.
local function ApplyTexturePackConfig(conf, prefix, value, frameW, frameH)
    local texture = TEXLAYER_PACK_BY_VALUE[value]
    if type(conf) ~= "table" or type(prefix) ~= "string" or not texture then return false end
    local previous = conf[prefix .. "SourceMode"] ~= "SHAREDMEDIA" and conf[prefix .. "Enabled"] == true
        and TEXLAYER_PACK_BY_PATH[tostring(conf[prefix .. "CustomTexturePath"] or "")] or nil
    local ornament = texture.role == "ORNAMENT"
    local keepPlacement = previous and ((previous.role == "ORNAMENT") == ornament)
    local changed = WriteSlotValues(conf, prefix, { Enabled = true, SourceMode = "PACK", Texture = "", CustomTexturePath = texture.path })
    if not keepPlacement then
        frameW = max(40, tonumber(frameW) or 180)
        frameH = max(10, tonumber(frameH) or 30)
        local height = floor(math.min(220, max(48, (frameH + 10) / 0.30)) + 0.5)
        if WriteSlotValues(conf, prefix, {
            AnchorTarget = "FRAME",
            Anchor = "CENTER",
            OffsetX = 0,
            OffsetY = 0,
            SizeMode = ornament and "HEIGHT" or "FRAME",
            ResponsiveSize = true,
            EdgeAttach = ornament and "LEFT" or "FREE",
            Width = ornament and height or floor(math.min(600, max(72, (frameW + 20) / 0.82)) + 0.5),
            Height = height,
        }) then changed = true end
    end
    if not previous and WriteSlotValues(conf, prefix, TEXLAYER_PACK_STATIC_LOOK) then changed = true end
    return changed
end
M.ApplyTextureLayerPackConfig = ApplyTexturePackConfig
M.TextureLayerPackItems = TEXLAYER_PACK_ITEMS

-- Resolved on the first layer write: every slider step refreshes the layers through it.
local RefreshUnitTextureLayers
-- Whole-number readout shared by the layer size sliders.
local function WholeNumber(control)
    if control.SetValueFormatter then
        control:SetValueFormatter(function(v) return tostring(floor((tonumber(v) or 0) + 0.5)) end)
    end
end

-- Texture Layer section. BuildTextureLayer runs a sequence of stages that share one state table (`s`):
-- slot actions, shell and cards, binders, then the Setup, Advanced and HP & Visibility cards, the
-- conditional refresh, the slot and category bars and the refresh. The stages create their widgets in
-- the order the single builder did, so the layout is unchanged.
local function TextureLayerActions(ctx, unit, s)
    local SetBool, SetString, GetConf = s.SetBool, s.SetString, s.GetConf

    M.unitTexLayerSlot = M.unitTexLayerSlot or {}
    M.unitTexLayerTab = M.unitTexLayerTab or {}
    local function NormalizeSlot(value)
        local slot = tonumber(value) or 1
        if slot < 1 or slot > #SLOT_PREFIXES then slot = 1 end
        return slot
    end
    local function CurrentSlot()
        return NormalizeSlot(M.unitTexLayerSlot[unit])
    end
    -- Every control created by this page build belongs to exactly one texture
    -- slot. Never resolve the prefix from mutable menu state inside a later
    -- slider/text/dropdown callback: after a slot switch that would let an old
    -- control write into the newly selected slot.
    local boundSlot = CurrentSlot()
    local boundPrefix = SLOT_PREFIXES[boundSlot]
    local function Key(base)
        return boundPrefix .. base
    end
    local function RefreshLayer()
        RefreshUnitTextureLayers = RefreshUnitTextureLayers
            or MSUF.Require("MSUF_RefreshUnitTextureLayers", "Shell/Menu2/Pages/MSUF_Menu2_UnitTextureLayer.lua")
        RefreshUnitTextureLayers(unit)
    end
    local function FinishPreset(changed, reason)
        if not changed then return false end
        if M.RequestUnitDomains then
            M.RequestUnitDomains(unit, reason, { preview = true, history = false })
        end
        RefreshLayer()
        if M.RequestRefresh then M.RequestRefresh(ctx, reason) end
        return true
    end
    local function ApplyPreset(values, reason)
        if M.BlockCombatAction and M.BlockCombatAction() then return false end
        return FinishPreset(WriteSlotValues(GetConf(unit), boundPrefix, values), reason)
    end
    local function SetHighlightTextureEnabled(enabled)
        if M.BlockCombatAction and M.BlockCombatAction() then return false end
        local conf = GetConf(unit)
        local changed = ApplyHighlightTextureConfig(conf, boundPrefix, enabled)
        if enabled and WriteSlotValues(conf, boundPrefix, { Enabled = true }) then changed = true end
        return FinishPreset(changed, "MSUF2_TEXLAYER_HIGHLIGHT_TEXTURE")
    end
    local function CurrentPackValue()
        local conf = GetConf(unit)
        if conf[Key("SourceMode")] == "SHAREDMEDIA" then return nil end
        local texture = TEXLAYER_PACK_BY_PATH[tostring(conf[Key("CustomTexturePath")] or "")]
        return texture and texture.value or nil
    end
    local function ApplyPackTexture(value)
        if M.BlockCombatAction and M.BlockCombatAction() then return false end
        local texture = TEXLAYER_PACK_BY_VALUE[value]
        if not texture then return false end
        local conf = GetConf(unit)
        local function Write()
            return ApplyTexturePackConfig(conf, boundPrefix, value, conf.width, conf.height)
        end
        local changed
        if type(M.RunWithHistory) == "function" then
            changed = M.RunWithHistory(M.TranslatedHistoryLabel(M.Format("Texture: %s", M.Tr(texture.text))),
                "unit:texture-layer-texture:" .. tostring(unit) .. ":" .. tostring(boundSlot), Write)
        else
            changed = Write()
        end
        return FinishPreset(changed == true, "MSUF2_TEXLAYER_MSUF_TEXTURE")
    end
    -- MSUF textures fit themselves around the frame. Moving Width or Height
    -- sizes that slot by hand from then on.
    local function KeepManualSize()
        local conf = GetConf(unit)
        if conf[Key("SizeMode")] == "MANUAL"
            or (conf[Key("SizeMode")] == nil and conf[Key("ResponsiveSize")] ~= true) then return end
        SetString(unit, Key("SizeMode"), "MANUAL", "MSUF2_TEXLAYER", { preview = true })
        SetBool(unit, Key("ResponsiveSize"), false, "MSUF2_TEXLAYER", { preview = true })
        RefreshLayer()
    end
    s.NormalizeSlot, s.CurrentSlot, s.boundSlot, s.Key = NormalizeSlot, CurrentSlot, boundSlot, Key
    s.RefreshLayer, s.ApplyPreset, s.SetHighlightTextureEnabled = RefreshLayer, ApplyPreset, SetHighlightTextureEnabled
    s.CurrentPackValue, s.ApplyPackTexture, s.KeepManualSize = CurrentPackValue, ApplyPackTexture, KeepManualSize
end
local function TextureLayerShell(ctx, builder, s)
    local unit, boundSlot, Key, GetConf = s.unit, s.boundSlot, s.Key, s.GetConf
    local sec = Schema.Section(builder:CollapsibleSection("texture_layer", "Texture Layer", TEXLAYER_SECTION_H, false), unit)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 20
    local innerW = max(320, sectionW - 40)
    local colGap = 16
    local colW = floor((innerW - 32 - colGap) / 2)
    local colX = 16 + colW + colGap

    local setupCard = Schema.Build(ctx, sec, {{ "card", "texture_layer.setup", nil, { "Basic setup", nil, leftX, TEXLAYER_CARD_Y, innerW,
        TEXLAYER_CARD_H }, scope = unit, domain = "layout" }})["texture_layer.setup"]
    local rulesCard = Schema.Build(ctx, sec, {{ "card", "texture_layer.rules", nil, { "HP & Visibility", nil, leftX, TEXLAYER_CARD_Y, innerW,
        TEXLAYER_CARD_H }, scope = unit, domain = "layout" }})["texture_layer.rules"]
    local advancedCard = Schema.Build(ctx, sec, {{ "card", "texture_layer.advanced", nil, { "Advanced texture options", nil, leftX,
        TEXLAYER_CARD_Y, innerW, TEXLAYER_CARD_H }, scope = unit, domain = "layout" }})["texture_layer.advanced"]
    local cardsByTab = { setup = setupCard, rules = rulesCard, advanced = advancedCard }

    if W.AttachContextColorReferences then
        local function TextureLayerColorRefs()
            local slotIds = { "texture_layer", "texture_layer2", "texture_layer3" }
            local slotId = slotIds[boundSlot] or "texture_layer"
            local refs = { slotId .. ".color" }
            if GetConf(unit)[Key("GradientEnabled")] == true then
                refs[#refs + 1] = slotId .. ".gradient"
            end
            return refs
        end
        local colorRefOptions = {
            title = "Texture Layer Colors",
            note = "These colors are shared from the Colors page.",
            historySource = "menu:unit-texture-layer-colors",
            context = function() return { unit = unit } end,
        }
        W.AttachContextColorReferences(setupCard, TextureLayerColorRefs, colorRefOptions)
        W.AttachContextColorReferences(advancedCard, TextureLayerColorRefs, colorRefOptions)
    end
    s.sec, s.sectionW, s.leftX, s.innerW, s.colW, s.colX = sec, sectionW, leftX, innerW, colW, colX
    s.setupCard, s.rulesCard, s.advancedCard, s.cardsByTab = setupCard, rulesCard, advancedCard, cardsByTab
end
local function TextureLayerBinders(ctx, s)
    local unit, Key, RefreshLayer, colW = s.unit, s.Key, s.RefreshLayer, s.colW
    local ReadBool, ReadNumber, SetBool, SetNumber, SetString = s.ReadBool, s.ReadNumber, s.SetBool, s.SetNumber, s.SetString
    local GetConf, ReviewedMeta = s.GetConf, s.ReviewedMeta

    local dependentControls = {}
    -- A build is bound to one slot (a slot switch rebuilds the page), so the control names that slot's key;
    -- the other slots' keys stay search aliases.
    local function LayerMeta(base, path, step)
        local meta = ReviewedMeta(ctx, "texture_layer." .. (path or base), "setting", "dynamic",
            "This control edits the texture-layer slot selected in the accordion's slot bar.")
        meta.settingKey = tostring(unit) .. "." .. Key(base)
        local keys = {}
        for i = 1, #SLOT_PREFIXES do keys[i] = tostring(unit) .. "." .. SLOT_PREFIXES[i] .. base end
        meta.searchSettingKeys = keys
        if step and meta then meta.step, meta.roundStep = step, true end
        return meta
    end
    -- Release links: this build's controls edit the bound slot; the hook shows
    -- the control's card (the route selects slot and card before the build).
    local function ExactSlot(control, parent, base)
        local tab = parent == s.setupCard and "setup" or parent == s.advancedCard and "advanced"
            or parent == s.rulesCard and "rules" or nil
        if not tab then return control end
        return M.DeclareExactViewContract(control, "unitTextureLayer",
            { [s.boundSlot .. "_" .. tab] = tostring(unit) .. "." .. SLOT_PREFIXES[s.boundSlot] .. base }, function()
                M.unitTexLayerTab[unit] = tab
                if s.ApplyTab then s.ApplyTab() end
                return true
            end)
    end
    -- Row factories shared by the cards. Each returns one replacing row sized to the card
    -- columns; `extra` carries the row's own fields and becomes the row itself.
    local R = { Meta = LayerMeta }
    local function Row(kind, base, default, args, placement, extra)
        extra = extra or {}
        extra[1], extra[2], extra[3], extra[4], extra[5] = kind, base, default, args, placement
        return extra
    end
    function R.Drop(base, default, label, values, x, y, extra)
        return Row("dropdown", base, default, { label, values, colW - 16 }, { x, y, colW - 16, "LEFT" }, extra)
    end
    function R.Slide(base, default, label, lo, hi, step, x, y, extra)
        return Row("slider", base, default, { label, lo, hi, step, colW - 58 }, { x, y, colW - 58, "LEFT" }, extra)
    end
    -- Whole-number sliders carry their step in the metadata; percent sliders edit 0-1 as 0-100%.
    function R.Whole(base, default, label, lo, hi, x, y, afterSet)
        return R.Slide(base, default, label, lo, hi, 1, x, y, { meta = LayerMeta(base, nil, 1), beforeBind = WholeNumber, afterSet = afterSet })
    end
    function R.Percent(base, default, label, lo, hi, step, x, y, afterSet)
        return R.Slide(base, default, label, lo, hi, step, x, y, { beforeBind = M.UsePercentInput, afterSet = afterSet })
    end
    function R.Toggle(base, default, label, x, y, extra)
        return Row("toggle", base, default, { label, x, y, colW - 16 }, nil, extra)
    end
    -- Static headings and hints: the shared font row, plus the search registration W.LabelAt performs.
    function R.Label(parent, id, text, color, x, y)
        return { "font", id, nil, { "GameFontNormalSmall", text, T.colors and T.colors[color] },
            anchor = { "TOPLEFT", parent, "TOPLEFT", x, y }, scope = unit, beforeBind = function(label)
                W._Shared.SetSearchText(label, text)
                W.RegisterSearchObject(label, text, "text")
                label:SetWidth(colW - 16)
                label:SetJustifyH("LEFT")
            end }
    end
    function R.AfterConditional()
        if s.RefreshConditional then s.RefreshConditional() end
    end
    -- Builds the rows in order on one card. A row without its own accessors reads and writes the
    -- bound slot's key and is a release-link target; every control except an `untracked` one joins
    -- the controls the Enabled switch gates.
    function R.Build(parent, rows)
        for _, row in ipairs(rows) do
            if row[1] ~= "font" then
                local kind, base, default = row[1], row[2], row[3]
                row.scope, row.domain = unit, "textureLayer"
                row.meta = row.meta or LayerMeta(base)
                if not row.get then
                    row.exact = true
                    row.get = function()
                        if kind == "toggle" then return ReadBool(unit, Key(base), default) end
                        if kind == "slider" then return ReadNumber(unit, Key(base), default) end
                        local value = GetConf(unit)[Key(base)]
                        if value == nil or value == "" then value = default end
                        return value
                    end
                    row.set = function(value)
                        if kind == "toggle" then SetBool(unit, Key(base), value, "MSUF2_TEXLAYER", { preview = true })
                        elseif kind == "slider" then SetNumber(unit, Key(base), value, "MSUF2_TEXLAYER", { preview = true })
                        else SetString(unit, Key(base), value or default, "MSUF2_TEXLAYER", { preview = true }) end
                        RefreshLayer()
                        if row.afterSet then row.afterSet() end
                    end
                end
            end
        end
        local controls = Schema.Build(ctx, parent, rows, ROW_OPTIONS)
        for _, row in ipairs(rows) do
            if row.exact then ExactSlot(controls[row[2]], parent, row[2]) end
            if row[1] ~= "font" and not row.untracked then dependentControls[#dependentControls + 1] = controls[row[2]] end
        end
        return controls
    end
    s.dependentControls, s.R = dependentControls, R
end
local function TextureLayerSetupCard(ctx, s)
    local unit, Key, RefreshLayer, colW, colX, setupCard, R = s.unit, s.Key, s.RefreshLayer, s.colW, s.colX, s.setupCard, s.R
    local SetString, GetConf = s.SetString, s.GetConf
    local ApplyPreset, SetHighlightTextureEnabled = s.ApplyPreset, s.SetHighlightTextureEnabled
    local CurrentPackValue, ApplyPackTexture, KeepManualSize = s.CurrentPackValue, s.ApplyPackTexture, s.KeepManualSize

    -- Setup: the common path stays on one page. Presets are explicit actions;
    -- merely opening this section never rewrites an existing profile.
    R.Build(setupCard, {
        R.Toggle("Enabled", false, "Enable Texture Layer", 16, -54, { untracked = true, afterSet = function()
            M.RequestRefresh(ctx, "MSUF2_TEXLAYER_ENABLE")
        end }),
        R.Label(setupCard, "texture_layer.quick_setup_heading", "Quick setup", "accent", 16, -88),
    })
    local presetButtons = {}
    local function PresetButton(id, label, width, x, onClick)
        local button = Schema.Build(ctx, setupCard, {{ "topButton", id, nil, { label, width, 24 }, scope = unit, domain = "textureLayer" }})[id]
        button:SetPoint("TOPLEFT", setupCard, "TOPLEFT", x, -108)
        button._msuf2HistoryLabel = label
        button:SetScript("OnClick", onClick)
        presetButtons[#presetButtons + 1] = { button, id, label }
        return button
    end
    local textBackgroundPreset = PresetButton("texture_layer.preset.text_background", "Text background", 142, 16, function()
        ApplyPreset(TEXT_BACKGROUND_PRESET, "MSUF2_TEXLAYER_TEXT_BACKGROUND_PRESET")
    end)
    local highlightPreset = PresetButton("texture_layer.preset.highlight", "Highlight", 112, 166, function()
        SetHighlightTextureEnabled(true)
    end)
    -- Third quick setup: the bundled MSUF textures, each listed with a preview.
    local texturePackPreset = PresetButton("texture_layer.preset.msuf_texture", "MSUF textures", 132, 286, function(self)
        if type(W.OpenDropdown) ~= "function" then return end
        W.OpenDropdown(self, TEXLAYER_PACK_ITEMS, CurrentPackValue(), function(value)
            ApplyPackTexture(value)
        end)
    end)
    texturePackPreset._msuf2DropdownPreferredWidth = 320
    local packChevron = PixelLayoutRegion(texturePackPreset:CreateTexture(nil, "OVERLAY"))
    packChevron:SetTexture(T.media and T.media.dropdownChevron)
    packChevron:SetSize(12, 12)
    packChevron:SetPoint("RIGHT", texturePackPreset, "RIGHT", -8, 0)
    if texturePackPreset._msuf2Label then
        texturePackPreset._msuf2Label:SetPoint("RIGHT", texturePackPreset, "RIGHT", -22, 0)
    end
    if colW < 402 then
        -- A narrow menu shrinks the three quick setups together so the row
        -- stays inside the left column.
        local quickX = 16
        local quickWidths = { 142, 112, 132 }
        for i, preset in ipairs(presetButtons) do
            local width = floor(quickWidths[i] * (colW - 16) / 386)
            preset[1]:SetWidth(width)
            preset[1]:SetPoint("TOPLEFT", setupCard, "TOPLEFT", quickX, -108)
            quickX = quickX + width + 8
        end
    end
    if UP.RegisterControl then
        for _, preset in ipairs(presetButtons) do UP.RegisterControl(preset[1], ctx, preset[2], preset[3], "button", "ephemeral") end
        for _, preset in ipairs(presetButtons) do Schema.Owned(preset[1], unit, "textureLayer") end
    end
    local controls = R.Build(setupCard, {
        R.Drop("Texture", "", "Texture (SharedMedia)", function() return M.StatusBarTextureItems("Use bar texture") end, 16, -164),
        { "textinput", "CustomTexturePath", "", { "Custom texture path", colW - 16 }, { 16, -240, colW - 16, "LEFT" }, commitOnBlur = true,
            get = function() return tostring(GetConf(unit)[Key("CustomTexturePath")] or "") end,
            set = function(v)
                local path = tostring(v or "")
                -- The typed path is drawn; clearing it returns to the SharedMedia texture.
                SetString(unit, Key("SourceMode"), path == "" and "SHAREDMEDIA" or (TEXLAYER_PACK_BY_PATH[path] and "PACK" or "CUSTOM"),
                    "MSUF2_TEXLAYER", { preview = true })
                SetString(unit, Key("CustomTexturePath"), path, "MSUF2_TEXLAYER", { preview = true })
                RefreshLayer()
            end },
        R.Drop("ColorMode", "CUSTOM", "Color mode", TEXLAYER_COLOR_MODES, 16, -316, { afterSet = R.AfterConditional }),
        R.Drop("ColorTreatment", "ORIGINAL", "Source color", TEXLAYER_COLOR_TREATMENTS, 16, -392),
        R.Drop("AnchorTarget", "FRAME", "Anchor to", TEXLAYER_ANCHOR_TARGETS, colX, -54),
        R.Drop("Anchor", "TOP", "Anchor", TEXLAYER_ANCHORS, colX, -130),
        R.Whole("Width", 0, "Width", 0, 600, colX, -214, KeepManualSize),
        R.Whole("Height", 16, "Height (0 = auto)", 0, 220, colX, -298, KeepManualSize),
        R.Percent("Alpha", 1, "Opacity", 0, 1, 0.05, colX, -382),
        R.Label(setupCard, "texture_layer.placement_hint",
            "Use the colored Texture handle in Preview for exact placement.", "muted", colX, -342),
    })
    if M.AddTooltip then
        M.AddTooltip(textBackgroundPreset, "Text background",
            "Creates a simple monochrome texture on the health bar. You can then choose any bar texture and place HP text above it.", { hook = true })
        M.AddTooltip(highlightPreset, "Highlight", "Applies the built-in additive highlight style to this texture slot.", { hook = true })
        M.AddTooltip(texturePackPreset, "MSUF textures",
            "Choose one of the bundled MSUF textures for this texture slot. Frames fit around the unit frame on their own.", { hook = true })
        M.AddTooltip(controls.ColorMode, "Color mode",
            "Single color uses this layer's configured tint. HP gradient follows the shared low, mid and high HP colors.", { hook = true })
    end
    s.customPath = controls.CustomTexturePath
end
local function TextureLayerAdvancedCard(ctx, s)
    local unit, Key, RefreshLayer, colX, advancedCard, R = s.unit, s.Key, s.RefreshLayer, s.colX, s.advancedCard, s.R
    local ReadBool, SetBool, SetString = s.ReadBool, s.SetBool, s.SetString
    local SetControlEnabled, GetConf = s.SetControlEnabled, s.GetConf

    -- Directional overlay gradient with a Bars-style D-pad, blend, mirroring,
    -- and a four-edge feather mask.
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
    -- Advanced: rendering and source-treatment details that are unnecessary
    -- for the common "texture behind text" path.
    R.Build(advancedCard, {
        R.Label(advancedCard, "texture_layer.strata_hint",
            "Texture layers use the unit frame's strata. Use Layer (0-30) to set their order.", "muted", 16, -54),
        R.Whole("Level", 1, "Layer (0-30)", 0, 30, 16, -138),
        R.Drop("CropMode", "FULL", "Texture region", TEXLAYER_CROP_MODES, 16, -222),
        R.Toggle("FollowFrameAlpha", true, "Follow frame transparency", 16, -298),
        R.Toggle("RoundedClip", false, "Clip to rounded frame", 16, -344),
        R.Toggle("GradientEnabled", false, "Gradient", colX, -54, { afterSet = RefreshGradientControls }),
        R.Label(advancedCard, "texture_layer.direction_heading", "Direction", "accent", colX, -88),
    })
    local padW, padH = 104, 78
    local padButtonW, padButtonH = 22, 18
    pad = T.Panel(advancedCard, nil, (T.colors and T.colors.panel2) or { 0.014, 0.038, 0.072, 0.55 }, T.colors and T.colors.borderSoft)
    pad:SetPoint("TOPLEFT", advancedCard, "TOPLEFT", colX, -110)
    pad:SetSize(padW, padH)
    Schema.Custom(pad, { id = "texture_layer.gradient_pad", kind = "directionPad", scope = unit, applyDomain = "textureLayer", owner = pad })
    local padCenter = PixelLayoutRegion(pad:CreateTexture(nil, "ARTWORK"))
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
            -- It writes the layer's gradient edges, like the Bars page pad: an action,
            -- found once by its first arrow (the others would be identical rows).
            UP.RegisterControl(btn, ctx, "texture_layer.gradient_direction." .. value, "Gradient direction", "button",
                value == "UP" and "action" or "ephemeral")
        end
        Schema.Owned(btn, unit, "textureLayer")
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
    R.Build(advancedCard, {
        R.Toggle("BlendMode", false, "Additive glow", colX, -210, {
            get = function() return GetConf(unit)[Key("BlendMode")] == "ADD" end,
            set = function(v)
                SetString(unit, Key("BlendMode"), v and "ADD" or "BLEND", "MSUF2_TEXLAYER", { preview = true })
                RefreshLayer()
            end }),
        R.Toggle("MirrorH", false, "Mirror horizontally", colX, -256),
        R.Toggle("MirrorV", false, "Mirror vertically", colX, -302),
        R.Percent("EdgeSoftness", 0, "Edge softness", 0, 0.30, 0.02, colX, -360),
        R.Label(advancedCard, "texture_layer.edge_softness_hint",
            "Fades all four outer edges; 0% keeps the original texture.", "muted", colX, -410),
    })
    s.RefreshGradientControls = RefreshGradientControls
end
local function TextureLayerRulesCard(ctx, s)
    local unit, Key, RefreshLayer, colX, rulesCard, R = s.unit, s.Key, s.RefreshLayer, s.colX, s.rulesCard, s.R
    local SetBool, SetString, GetConf = s.SetBool, s.SetString, s.GetConf

    -- HP response and visibility live together because the same threshold can
    -- drive color, opacity, and whether the texture is shown. Existing fields
    -- remain independent and visibility filters continue to combine with AND.
    local controls = R.Build(rulesCard, {
        R.Label(rulesCard, "texture_layer.health_behavior_heading", "Health behavior", "accent", 16, -48),
        R.Drop("HealthCondition", "ANY", "Show by health", TEXLAYER_HEALTH_CONDITIONS, 16, -70, { afterSet = R.AfterConditional }),
        R.Percent("HealthThreshold", 0.35, "HP threshold", 0.01, 1, 0.01, 16, -154, R.AfterConditional),
        R.Drop("HealthAboveMode", "HEALTH", "Color above threshold", TEXLAYER_ABOVE_THRESHOLD_MODES, 16, -238,
            { afterSet = R.AfterConditional }),
        R.Toggle("HealthLowAlphaEnabled", false, "Change opacity below threshold", 16, -314, { afterSet = R.AfterConditional }),
        R.Percent("HealthLowAlpha", 1, "Opacity below threshold", 0, 1, 0.05, 16, -382),
        R.Label(rulesCard, "texture_layer.visibility_heading", "Visibility", "accent", colX, -48),
        R.Drop("Visibility", "ALWAYS", "Combat state", TEXLAYER_VISIBILITY, colX, -70, {
            meta = R.Meta("Visibility", "combat_state"),
            get = function()
                local value = GetConf(unit)[Key("Visibility")]
                if value == "TARGET" then return "ALWAYS" end
                if value ~= "COMBAT" and value ~= "OOC" then return "ALWAYS" end
                return value
            end,
            set = function(value)
                local conf = GetConf(unit)
                if conf[Key("Visibility")] == "TARGET" and conf[Key("TargetOnly")] == nil then
                    SetBool(unit, Key("TargetOnly"), true, "MSUF2_TEXLAYER", { preview = true })
                end
                SetString(unit, Key("Visibility"), value or "ALWAYS", "MSUF2_TEXLAYER", { preview = true })
                RefreshLayer()
                if s.RefreshConditional then s.RefreshConditional() end
            end }),
        R.Toggle("TargetOnly", false, "Current target only", colX, -146, {
            meta = R.Meta("TargetOnly", "current_target_only"),
            get = function()
                local conf = GetConf(unit)
                return conf[Key("TargetOnly")] == true or conf[Key("Visibility")] == "TARGET"
            end,
            set = function(enabled)
                local conf = GetConf(unit)
                if conf[Key("Visibility")] == "TARGET" then
                    SetString(unit, Key("Visibility"), "ALWAYS", "MSUF2_TEXLAYER", { preview = true })
                end
                SetBool(unit, Key("TargetOnly"), enabled, "MSUF2_TEXLAYER", { preview = true })
                RefreshLayer()
                if s.RefreshConditional then s.RefreshConditional() end
            end }),
        R.Label(rulesCard, "texture_layer.condition_summary", "Active: Always", "accent", colX, -204),
        R.Label(rulesCard, "texture_layer.condition_hint", "All selected visibility conditions must match (AND).", "muted", colX, -238),
        R.Label(rulesCard, "texture_layer.health_behavior_summary", "HP color: Off", "muted", colX, -292),
    })
    if M.AddTooltip then
        M.AddTooltip(controls.HealthCondition, "Show by health", "Below threshold hides this texture until the unit reaches the configured HP threshold.",
            { hook = true })
        M.AddTooltip(controls.HealthAboveMode, "Color above threshold",
            "With HP gradient selected, choose what the texture uses after it passes the threshold.", { hook = true })
        M.AddTooltip(controls.HealthLowAlphaEnabled, "Change opacity below threshold",
            "Uses a separate texture opacity below the HP threshold. The normal Opacity from Setup remains active above it.", { hook = true })
    end
    s.healthThreshold, s.aboveThreshold, s.lowAlpha = controls.HealthThreshold, controls.HealthAboveMode, controls.HealthLowAlpha
    s.conditionSummary, s.healthBehaviorSummary = controls["texture_layer.condition_summary"], controls["texture_layer.health_behavior_summary"]
end
local function TextureLayerRefreshConditional(s)
    local unit, Key = s.unit, s.Key
    local ReadBool, ReadNumber, SetControlEnabled, GetConf = s.ReadBool, s.ReadNumber, s.SetControlEnabled, s.GetConf
    local aboveThreshold, healthThreshold, lowAlpha = s.aboveThreshold, s.healthThreshold, s.lowAlpha
    local conditionSummary, healthBehaviorSummary = s.conditionSummary, s.healthBehaviorSummary
    s.RefreshConditional = function()
        local conf = GetConf(unit)
        local layerOn = ReadBool(unit, Key("Enabled"), false)
        local mode = conf[Key("ColorMode")] or "CUSTOM"
        local condition = conf[Key("HealthCondition")] or "ANY"
        local aboveMode = conf[Key("HealthAboveMode")] or "HEALTH"
        local lowAlphaOn = conf[Key("HealthLowAlphaEnabled")] == true
        local showAboveMode = mode == "HEALTH" and condition ~= "BELOW"
        local thresholdUsed = condition == "BELOW" or lowAlphaOn or (showAboveMode and aboveMode ~= "HEALTH")
        W.SetControlShown(aboveThreshold, showAboveMode)
        W.SetControlShown(lowAlpha, lowAlphaOn)
        SetControlEnabled(aboveThreshold, layerOn)
        SetControlEnabled(healthThreshold, layerOn and thresholdUsed)
        SetControlEnabled(lowAlpha, layerOn and lowAlphaOn)
        if mode == "HEALTH" then
            healthBehaviorSummary:SetText("HP color: Gradient")
        elseif lowAlphaOn or condition == "BELOW" then
            healthBehaviorSummary:SetText("HP color: Off; threshold still affects opacity or visibility")
        else
            healthBehaviorSummary:SetText("HP color: Off")
        end
        local parts = {}
        local visibility = conf[Key("Visibility")]
        if visibility == "COMBAT" then
            parts[#parts + 1] = Tr("In combat")
        elseif visibility == "OOC" then
            parts[#parts + 1] = Tr("Out of combat")
        end
        if condition == "BELOW" then
            local threshold = ReadNumber(unit, Key("HealthThreshold"), 0.35)
            parts[#parts + 1] = string.format(Tr("Below %d%% HP"), floor((threshold * 100) + 0.5))
        end
        if conf[Key("TargetOnly")] == true or visibility == "TARGET" then
            parts[#parts + 1] = Tr("Current target")
        end
        if lowAlphaOn then
            local alpha = ReadNumber(unit, Key("HealthLowAlpha"), 1)
            parts[#parts + 1] = string.format(Tr("Low HP opacity: %d%%"), floor((alpha * 100) + 0.5))
        end
        if #parts == 0 then parts[1] = Tr("Always") end
        conditionSummary:SetText(string.format(Tr("Active: %s"), table.concat(parts, " + ")))
    end
end
local function TextureLayerSelectors(ctx, s)
    local unit, sec, sectionW, leftX, cardsByTab = s.unit, s.sec, s.sectionW, s.leftX, s.cardsByTab
    local NormalizeSlot, CurrentSlot, customPath = s.NormalizeSlot, s.CurrentSlot, s.customPath
    -- Slot + category bars. Both are menu-session state, never persisted.
    local function NormalizeTab(tab)
        tab = TEXLAYER_TAB_ALIASES[tab] or tab
        return cardsByTab[tab] and tab or "setup"
    end
    local function ApplyTab()
        local tab = NormalizeTab(M.unitTexLayerTab[unit])
        M.unitTexLayerTab[unit] = tab
        for key, card in pairs(cardsByTab) do
            W.SetControlShown(card, key == tab)
        end
    end
    for tab, card in pairs(cardsByTab) do
        card._msuf2ExactTabView = {
            kind = "unitTextureLayer", value = tostring(s.boundSlot) .. "_" .. tab,
            select = function(value)
                M.unitTexLayerTab[unit] = value:match("^%d_(.+)$")
                ApplyTab()
            end,
        }
    end
    local slotValues = {
        { value = 1, text = "Texture 1" },
        { value = 2, text = "Texture 2" },
        { value = 3, text = "Texture 3" },
    }
    local tabValues = {}
    for i = 1, #TEXLAYER_TABS do
        tabValues[i] = { value = TEXLAYER_TABS[i], text = TEXLAYER_TAB_TEXTS[TEXLAYER_TABS[i]] }
    end
    Schema.Build(ctx, sec, {
        { "scopebar", "texture_layer.slot_bar", nil, { {
            values = slotValues,
            width = sectionW,
            label = "Texture:",
            labelX = leftX,
            labelWidth = 64,
            centerY = -52,
            getValue = function() return CurrentSlot() end,
            setValue = function(value)
                local nextSlot = NormalizeSlot(value)
                local previousSlot = CurrentSlot()
                if nextSlot == previousSlot then return end
                -- Commit an in-progress custom path while the old slot remains
                -- selected. Its callback is slot-bound as an additional safeguard.
                if customPath and customPath.HasFocus and customPath:HasFocus() and customPath.ClearFocus then
                    customPath:ClearFocus()
                end
                M.unitTexLayerSlot[unit] = nextSlot
                local pageKey = M.activeKey or ("uf_" .. tostring(unit))
                if M.RebuildPageKeepingScroll and M.RebuildPageKeepingScroll(pageKey) then return end
                -- A visible control must never change ownership without a rebuild.
                -- Roll the ephemeral selection back if rebuilding is unavailable.
                M.unitTexLayerSlot[unit] = previousSlot
                if M.RequestRefresh then M.RequestRefresh(ctx, "MSUF2_TEXLAYER_SLOT_RESTORE") end
            end,
        } }, scope = unit, beforeBind = function(control)
            UP.RegisterControl(control, ctx, "texture_layer.slot_selector", "Texture", "segment", "ephemeral")
        end },
        { "scopebar", "texture_layer.tab_bar", nil, { {
            values = tabValues,
            width = sectionW,
            label = "Options:",
            labelX = leftX,
            labelWidth = 64,
            centerY = -84,
            getValue = function() return NormalizeTab(M.unitTexLayerTab[unit]) end,
            setValue = function(value)
                M.unitTexLayerTab[unit] = NormalizeTab(value)
                ApplyTab()
            end,
        } }, scope = unit, beforeBind = function(control)
            UP.RegisterControl(control, ctx, "texture_layer.category_selector", "Options", "segment", "ephemeral")
        end },
    })
    s.ApplyTab = ApplyTab
    ApplyTab()
end
local function TextureLayerRefresh(ctx, s)
    local unit, Key = s.unit, s.Key
    local ReadBool, SetControlEnabled = s.ReadBool, s.SetControlEnabled
    local dependentControls, RefreshGradientControls, RefreshConditionalControls = s.dependentControls, s.RefreshGradientControls, s.RefreshConditional
    local function RefreshLayerControls()
        local on = ReadBool(unit, Key("Enabled"), false)
        for i = 1, #dependentControls do SetControlEnabled(dependentControls[i], on) end
        RefreshGradientControls()
        RefreshConditionalControls()
    end
    RefreshLayerControls()
    M.TrackRefresh(ctx, RefreshLayerControls)
end

local function BuildTextureLayer(ctx, builder, unit)
    local ReadBool = UP.ReadBool
    local SetBool = UP.SetBool
    local ReadNumber = UP.ReadNumber
    local SetNumber = UP.SetNumber
    local SetString = UP.SetString
    local SetControlEnabled = UP.SetControlEnabled
    local GetConf = UP.GetConf
    local ReviewedMeta = UP.ReviewedMeta
    assert(ReadBool and SetBool and ReadNumber and SetNumber and SetString and SetControlEnabled and GetConf and ReviewedMeta,
        "Texture Layer requires the UnitPage settings API")
    local s = {
        unit = unit,
        ReadBool = ReadBool, SetBool = SetBool, ReadNumber = ReadNumber, SetNumber = SetNumber, SetString = SetString,
        SetControlEnabled = SetControlEnabled, GetConf = GetConf, ReviewedMeta = ReviewedMeta,
    }
    TextureLayerActions(ctx, unit, s)
    TextureLayerShell(ctx, builder, s)
    TextureLayerBinders(ctx, s)
    TextureLayerSetupCard(ctx, s)
    TextureLayerAdvancedCard(ctx, s)
    TextureLayerRulesCard(ctx, s)
    TextureLayerRefreshConditional(s)
    TextureLayerSelectors(ctx, s)
    TextureLayerRefresh(ctx, s)
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
