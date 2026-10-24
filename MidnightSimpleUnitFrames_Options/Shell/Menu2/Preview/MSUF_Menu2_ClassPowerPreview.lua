--- Class Resources preview module.
--- Menu-only composition for ClassPower, detached Player Power, and the
--- optional Class Resources Player HP bar. Edit Mode owns movement; this
--- surface only displays the configured layout and opens element settings.
local MSUF = select(2, ...)
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic
local PublicGlobals = MSUF.PublicGlobals
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Menu2/ClassPowerPreview")
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local Preview = M.ClassPowerStackPreview or {}
M.ClassPowerStackPreview = Preview
local ActivateClassPowerSurface = Preview.ActivateSurface
local RequestClassPowerPreviewRefresh = Preview.RequestRefresh
local W = M.Widgets
local T = M.Theme
local CPPreview = M.ClassPowerPreview or {}
local PreviewCore = MSUF.UFPreviewCore or {}
local Helpers = M.PreviewHelpers or {}
local function PlayerManaSourceActive(player)
    return player and player._msufResourceExtraMana == true or Helpers.PlayerManaSourceActive(player)
end
-- SetOnUpdateMode takes an Enum.OnUpdateMode value, not a name; a string argument leaves the
-- animation driver's OnUpdate disabled.
local ONUPDATE_MODE_DISABLED = (Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.Disabled) or 0
local ONUPDATE_MODE_RUN_WHEN_VISIBLE = (Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.RunWhenVisible) or 1
local NormalizeControlPath = M.NormalizeControlPath
local function PreviewControlMeta(ctx, semanticPath, classification, exact)
    local pageKey = NormalizeControlPath((ctx and ctx.key) or M.activeKey or "classpower")
    if pageKey == "" then pageKey = "classpower" end
    local path = NormalizeControlPath(semanticPath)
    local identity = pageKey .. ".class-power-preview." .. path
    local meta = {
        controlId = "menu2." .. identity,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        pageKey = pageKey,
        classification = classification or "ephemeral",
    }
    if meta.classification == "ephemeral" then meta.ephemeral = true end
    if type(exact) == "table" then
        for key, value in pairs(exact) do meta[key] = value end
    end
    return meta
end
local function RegisterPreviewControl(ctx, widget, semanticPath, label, kind, classification, exact)
    if not (widget and M.RegisterSearchWidget) then return widget end
    local payload = PreviewControlMeta(ctx, semanticPath, classification, exact)
    payload.label = label
    payload.kind = kind
    M.RegisterSearchWidget(widget, payload)
    return widget
end
local floor = math.floor
local max = math.max
local min = math.min
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local PREVIEW_BORDER_COLOR = { 1.00, 0.02, 0.02, 1.00 }
local CP_PREVIEW_ANIMATION_INTERVAL = 0.05
local CP_SHAPES, POWER_SHAPES = CPPreview.CLASS_SHAPES, CPPreview.POWER_SHAPES
local NormalizeClassShape, ResolvePowerShape = CPPreview.NormalizeClassShape, CPPreview.ResolvePowerShape
local CP_OUTLINE_OPTS = {
    linesKey = "_msufCPPreviewEdges",
    maxEdgeSize = 8,
    texture = WHITE8,
    color = function() return PREVIEW_BORDER_COLOR[1], PREVIEW_BORDER_COLOR[2], PREVIEW_BORDER_COLOR[3], PREVIEW_BORDER_COLOR[4] end,
}
local HP_TEXT_REVERSE = { CURMAX = "MAXCUR", MAXCUR = "CURMAX", CURPERCENT = "PERCENTCUR", PERCENTCUR = "CURPERCENT", MAXPERCENT = "PERCENTMAX",
    PERCENTMAX = "MAXPERCENT", CURMAXPERCENT = "PERCENTCURMAX", PERCENTCURMAX = "CURMAXPERCENT", PERCENTMAXCUR = "CURMAXPERCENT" }
local DELIMITERS = { [""] = " ", ["-"] = " - ", ["/"] = " / ", ["\\"] = " \\ ", ["|"] = " | ", ["<"] = " < ", [">"] = " > ", ["~"] = " ~ ", [":"] = " : " }
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
-- Core-addon providers (all load before the options addon), resolved once. Only the class power
-- constants table is an optional collaborator.
local Core = {
    ShapeOutlineAlpha = MSUF.Require("MSUF_UF_ShapeOutlineAlpha", "Menu2/ClassPowerPreview"),
    SetFontChecked = MSUF.Require("MSUF_SetFontChecked", "Menu2/ClassPowerPreview"),
    GetFontPath = MSUF.Require("MSUF_GetFontPath", "Menu2/ClassPowerPreview"),
    GetFontFlags = MSUF.Require("MSUF_GetFontFlags", "Menu2/ClassPowerPreview"),
    ResolveSafeFontPath = MSUF.Require("MSUF_ResolveSafeFontPath", "Menu2/ClassPowerPreview"),
    GetGlobalFontSettings = MSUF.Require("MSUF_GetGlobalFontSettings", "Menu2/ClassPowerPreview"),
    ResolveFontShadowMetrics = MSUF.Require("MSUF_ResolveFontShadowMetrics", "Menu2/ClassPowerPreview"),
    GetSettingsCache = MSUF.Require("MSUF_UFCore_GetSettingsCache", "Menu2/ClassPowerPreview"),
    GetEffectiveCooldownFrame = MSUF.Require("MSUF_GetEffectiveCooldownFrame", "Menu2/ClassPowerPreview"),
    GetBarBackgroundTexture = MSUF.Require("MSUF_GetBarBackgroundTexture", "Menu2/ClassPowerPreview"),
    CDMScaledWidth = MSUF.Require("MSUF_CDM_GetScaledWidth", "Menu2/ClassPowerPreview"),
    CPConst = MSUF.Optional("MSUF_CP_CONST"),
}
local function TR(text)
    return (M.Tr and M.Tr(text)) or text
end
local function SetPreviewSummary(box, classFrame, powerFrame, hpFrame)
    if not (box and box.summary and box.summary.SetText) then return end
    local parts = {}
    if classFrame then parts[#parts + 1] = TR("Class Resource") end
    if powerFrame then parts[#parts + 1] = TR("Player Power") end
    if hpFrame then parts[#parts + 1] = TR("Extra Health Bar") end
    if box.altMana and box.altMana:IsShown() then parts[#parts + 1] = TR("Alternative Mana") end
    if #parts == 0 then
        T.SetTranslatedText(box.summary, TR("Enable a resource bar to preview it."))
    else
        T.SetTranslatedText(box.summary, TR("Shown here: ") .. table.concat(parts, " + "))
    end
end
local CP_PREVIEW_LAYERS = {
    { key = "guides", label = "Guides", color = { 0.42, 0.72, 1.00 }, tooltip = "Click to open settings. Move resources in Edit Mode." },
    { key = "border", label = "Border", color = PREVIEW_BORDER_COLOR, tooltip = "Actual HP, Power and Class Resource outlines." },
    { key = "class", label = "Resource", color = { 0.30, 0.78, 0.55 }, tooltip = "Class resource bar or pips." },
    { key = "classText", label = "Res Text", color = { 0.30, 0.78, 0.55 }, tooltip = "Class resource numeric text." },
    { key = "power", label = "Power Bar", color = { 0.95, 0.72, 0.18 }, tooltip = "Detached player power bar bound to Class Resources." },
    { key = "powerText", label = "Power Txt", color = { 0.95, 0.72, 0.18 }, tooltip = "Detached player power text." },
    { key = "hp", label = "HP Bar", color = { 0.25, 0.90, 0.42 }, tooltip = "Extra player HP bar in Class Resources." },
    { key = "mana", label = "Alternative Mana", color = { 0.45, 0.70, 1.00 }, tooltip = "Additional mana bar for dual-resource specializations." },
    { key = "hpText", label = "HP Text", color = { 0.25, 0.90, 0.42 }, tooltip = "Extra player HP text." },
    { key = "bounds", label = "Bounds", color = { 1.00, 0.22, 0.12 }, tooltip = "Preview-only bounds around visible elements." },
}
-- Layer colours by key, shared by the handles and the bounds (Ebon Might has no layer of its own).
local LAYER_COLORS = { ebon = { 0.40, 0.80, 0.60 } }
for i = 1, #CP_PREVIEW_LAYERS do LAYER_COLORS[CP_PREVIEW_LAYERS[i].key] = CP_PREVIEW_LAYERS[i].color end
local Interaction = M.ClassPowerPreviewInteraction
local Round = Interaction.Round
local ReadHandle = Interaction.Read
local OpenClassPowerHandleSettings = Interaction.OpenSettings
local function Clamp(value, fallback, minValue, maxValue)
    value = tonumber(value) or fallback
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end
local function Alpha(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value == nil then value = 1 end
    if value > 1 then value = value / 100 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
local function EnsureDB()
    return M.EnsureDB()
end
--- A saved-variables section of the active profile, created on first use.
local function Section(name)
    local db = EnsureDB()
    db[name] = db[name] or {}
    return db[name]
end
local function SetShownSafe(region, shown)
    if not region then return end
    if region.SetShown then
        region:SetShown(shown == true)
    elseif shown then
        region:Show()
    else
        region:Hide()
    end
end
local function HideMeterText(frame)
    if not frame then return end
    SetShownSafe(frame.left, false)
    SetShownSafe(frame.center, false)
    SetShownSafe(frame.right, false)
end
local function PreviewParent(preview)
    return preview and (preview.stage or preview.canvas)
end
local function PreviewGuidesEnabled()
    local value = Section("general").classPowerPreviewGuidesEnabled
    return value ~= nil and value ~= false
end
local function SetPreviewGuidesEnabled(enabled)
    Section("general").classPowerPreviewGuidesEnabled = enabled ~= false
end
local function LayerAvailable(preview, key)
    local available = preview and preview.layerAvailable
    return not (available and available[key] == false)
end
--- False once the user switched the layer off in the rail.
local function Wanted(preview, key)
    local visible = preview.layerVisibility
    return not (visible and visible[key] == false)
end
-- Both checks inline: the 20 Hz class timer and every handle hover ask this.
local function LayerOn(preview, key)
    if not preview then return false end
    local available = preview.layerAvailable
    if available and available[key] == false then return false end
    local visible = preview.layerVisibility
    if visible and visible[key] == false then return false end
    return true
end
local function GuidesOn(preview)
    return LayerOn(preview, "guides")
end
local function RefreshLayerButtons(preview)
    local buttons = preview and preview.layerButtons
    if not buttons then return end
    for i = 1, #buttons do
        if buttons[i].Refresh then buttons[i]:Refresh() end
    end
end

local function ResolveHPShape(bars, player)
    local value = tostring(bars and bars.playerHPBarShape or "BAR"):upper()
    if value ~= "FOLLOW_POWER" then return ResolvePowerShape(value, bars and bars.classPowerShape) end
    if not (player and player.powerBarDetached == true) then return "BAR" end
    return ResolvePowerShape(player.detachedPowerBarShape or "BAR", bars and bars.classPowerShape)
end
local function AnimationEnabled(preview)
    return preview and preview._animationEnabled == true
end
local function PreviewAnimationInCombat()
    return ((InCombatLockdown and InCombatLockdown()) or PublicGlobals.MSUF_InCombat == true) and true or false
end
local function PreviewElapsed(preview)
    return tonumber(preview and preview._animationElapsed) or 0
end
local function AnimatedMeterFraction(preview, fallback, speed, low, high)
    if not AnimationEnabled(preview) then return fallback end
    local phase = (PreviewElapsed(preview) * speed) % 2
    local wave = phase <= 1 and phase or (2 - phase)
    return low + (wave * (high - low))
end
local function PreviewOutline(preview, value, fallback)
    if not LayerOn(preview, "border") then return 0 end
    return Clamp(value, fallback or 0, 0, 8)
end
local ResolveTexture = CPPreview.ResolveTexture
local PREVIEW_CLASS_BY_PREFIX = { deathknight = "DEATHKNIGHT", demonhunter = "DEMONHUNTER", druid = "DRUID", evoker = "EVOKER", hunter = "HUNTER",
    mage = "MAGE", monk = "MONK", paladin = "PALADIN", priest = "PRIEST", rogue = "ROGUE", shaman = "SHAMAN", warlock = "WARLOCK", warrior = "WARRIOR" }
-- The spec's own class token, upper-cased, when it names one.
local function SpecToken(spec)
    local token = spec and (spec.classToken or spec.class)
    return token and tostring(token):upper() or nil
end
local function PreviewClassToken(spec)
    local token = SpecToken(spec)
    if token then return token end
    if M.GetClassPowerPreviewClassToken then
        local class = M.GetClassPowerPreviewClassToken()
        if class then return tostring(class):upper() end
    end
    local key = tostring((spec and spec.key) or "")
    local prefix = key:match("^([^_]+)")
    return prefix and PREVIEW_CLASS_BY_PREFIX[prefix] or nil
end
local function ClassColor(spec)
    local class = PreviewClassToken(spec)
    if not class and UnitClass then class = select(2, UnitClass("player")) end
    return MSUF.UF.Config.ClassColor(class)
end
local function PowerColor(player)
    local explicitMana = PlayerManaSourceActive(player)
    local sample = player and player._msufResourceExtraPower
    local c = PowerBarColor and ((sample and PowerBarColor[sample]) or (explicitMana and PowerBarColor.MANA) or PowerBarColor.ENERGY or PowerBarColor.MANA)
    if c then return c.r or c[1] or 1, c.g or c[2] or 0.82, c.b or c[3] or 0.10 end
    return 1.00, 0.86, 0.12
end
local function CPTextAlpha()
    local g = EnsureDB().general
    local alpha = tonumber(g and g.fontTextAlpha) or 1
    if alpha < 0.7 then alpha = 0.7 elseif alpha > 1 then alpha = 1 end
    return alpha
end
local function HPColor(bars, spec)
    local mode = tostring(bars and bars.playerHPBarColorMode or "GLOBAL"):upper()
    if mode == "DARK" then
        return Helpers.DarkBarColor(Core.GetSettingsCache())
    end
    if mode == "GRADIENT" then
        local pct = 0.74
        local r = pct > 0.5 and (1 - (pct - 0.5) * 2) or 1
        local g = pct > 0.5 and 1 or (pct * 2)
        return r, g, 0
    end
    return ClassColor(spec)
end
local function ShortValue(value)
    value = tonumber(value) or 0
    local abbrev = AbbreviateShortNumber or AbbreviateLargeNumbers
    if abbrev then
        local NumberFormat = MSUF.NumberFormat
        local text = abbrev(value, NumberFormat and NumberFormat.GetOptions and NumberFormat.GetOptions() or nil)
        if text ~= nil then return text end
    end
    local absValue = value < 0 and -value or value
    local sign = value < 0 and "-" or ""
    if absValue >= 1000000 then
        local n = floor((absValue / 100000) + 0.5) / 10
        return sign .. (n >= 10 and tostring(floor(n + 0.5)) or string.format("%.1f", n)) .. "M"
    elseif absValue >= 1000 then
        local n = floor((absValue / 100) + 0.5) / 10
        return sign .. (n >= 10 and tostring(floor(n + 0.5)) or string.format("%.1f", n)) .. "K"
    end
    return tostring(floor(value + 0.5))
end
local function ModeText(mode, current, maxValue, delimiter, hidePercentSymbol)
    mode = tostring(mode or "NONE"):upper()
    if mode == "NONE" then return "" end
    current = tonumber(current) or 0
    maxValue = tonumber(maxValue) or 1
    if maxValue < 1 then maxValue = 1 end
    delimiter = DELIMITERS[delimiter] or delimiter or " "
    local pct = floor((current / maxValue) * 100 + 0.5)
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    local curText, maxText, pctText = ShortValue(current), ShortValue(maxValue), tostring(pct)
    if hidePercentSymbol ~= true then pctText = pctText .. "%" end
    if mode == "CURRENT" then return curText end
    if mode == "MAX" then return maxText end
    if mode == "DEFICIT" then
        local missing = maxValue - current
        return missing > 0 and ("-" .. ShortValue(missing)) or ""
    end
    if mode == "PERCENT" then return pctText end
    if mode == "CURMAX" then return curText .. delimiter .. maxText end
    if mode == "MAXCUR" then return maxText .. delimiter .. curText end
    if mode == "CURPERCENT" then return curText .. delimiter .. pctText end
    if mode == "PERCENTCUR" then return pctText .. delimiter .. curText end
    if mode == "MAXPERCENT" then return maxText .. delimiter .. pctText end
    if mode == "PERCENTMAX" then return pctText .. delimiter .. maxText end
    if mode == "CURMAXPERCENT" then return curText .. delimiter .. maxText .. delimiter .. pctText end
    if mode == "PERCENTCURMAX" then return pctText .. delimiter .. curText .. delimiter .. maxText end
    if mode == "PERCENTMAXCUR" then return pctText .. delimiter .. maxText .. delimiter .. curText end
    return curText
end
local function HidePercentValue(source, key)
    if source and source[key] ~= nil then return source[key] == true end
    local g = M.EnsureDB().general
    return g and g.hidePercentSymbol == true
end
local function ApplyFont(region, size)
    if not (region and region.SetFont) then return end
    size = Clamp(size, 12, 6, 48)
    local g = EnsureDB().general
    local fontPath = Core.GetFontPath() or STANDARD_TEXT_FONT
    local fontFlags = Core.GetFontFlags() or "OUTLINE"
    if not fontPath or fontPath == "" then fontPath = FALLBACK_FONT end
    if not fontFlags or fontFlags == "" then fontFlags = "OUTLINE" end
    fontPath = Core.ResolveSafeFontPath(fontPath, size, fontFlags, g and g.fontKey)
    if not Core.SetFontChecked(region, fontPath, size, fontFlags) then
        Core.SetFontChecked(region, FALLBACK_FONT, size, fontFlags)
    end
    local useShadow = select(7, Core.GetGlobalFontSettings())
    if useShadow == nil then useShadow = not (g and g.textBackdrop == false) end
    if useShadow then
        local shadowAlpha, shadowX, shadowY = Core.ResolveFontShadowMetrics(
            g and g.fontShadowOpacity, g and g.fontShadowDistance, g and g.fontShadowStrength)
        if region.SetShadowColor then region:SetShadowColor(0, 0, 0, shadowAlpha) end
        if region.SetShadowOffset then region:SetShadowOffset(shadowX, shadowY) end
    elseif region.SetShadowOffset then
        region:SetShadowOffset(0, 0)
    end
end
local function EnsureOutlineHost(frame)
    local parent = frame and frame:GetParent()
    if not parent then return nil end
    local host = frame._msufCPPreviewOutlineHost
    if not host then
        host = PixelLayoutRegion(CreateFrame("Frame", nil, parent))
        host:EnableMouse(false)
        frame._msufCPPreviewOutlineHost = host
    end
    if host:GetParent() ~= parent then host:SetParent(parent) end
    return host
end
local function ApplyBarOutline(frame, outline)
    local host = EnsureOutlineHost(frame)
    if not host then return end
    outline = floor((tonumber(outline) or 0) + 0.5)
    if outline <= 0 then
        Helpers.SetEdgeLinesShown(host, false, CP_OUTLINE_OPTS)
        host:Hide()
        return
    end
    if outline > 8 then outline = 8 end
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", frame, "TOPLEFT", -outline, outline)
    host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", outline, -outline)
    local parent = host:GetParent()
    host:SetFrameLevel(((parent and parent.GetFrameLevel and parent:GetFrameLevel()) or 0) + 74)
    host:Show()
    Helpers.LayoutEdgeLines(host, outline, CP_OUTLINE_OPTS)
end
local function HideBarOutline(frame)
    local host = frame and frame._msufCPPreviewOutlineHost
    if not host then return end
    Helpers.SetEdgeLinesShown(host, false, CP_OUTLINE_OPTS)
    host:Hide()
end
local CP_POWER_ROUNDED_OPTS = {
    bgKey = "_msufCPRoundedBg",
    edgeKey = "_msufCPRoundedEdge",
    stackKey = "_msufCPRoundedEdgeStack",
    countKey = "_msufCPRoundedEdgeCount",
    whiteTexture = WHITE8,
    edgeLayer = "OVERLAY",
    edgeSubLevel = 6,
    snapOff = Helpers.SnapOff,
    baseEdgeColor = function()
        local spec = MSUF.UFPreviewRuntime.SpecForPreviewKey("player")
        local power = spec and spec.power
        if power then return power.borderR, power.borderG, power.borderB, power.borderA end
        local player = EnsureDB().player or {}
        local r, g, b, a = Helpers.BaseEdgeColor()
        return tonumber(player.powerBarBorderColorR) or tonumber(player.barOutlineColorR) or r,
            tonumber(player.powerBarBorderColorG) or tonumber(player.barOutlineColorG) or g,
            tonumber(player.powerBarBorderColorB) or tonumber(player.barOutlineColorB) or b,
            tonumber(player.powerBarBorderColorA) or a
    end,
}
local function RoundedPowerPreviewEnabled()
    local bars = EnsureDB().bars
    return bars and bars.roundedFramesEnabled == true
        and bars.roundedUnitFrames ~= false
        and bars.roundedPowerBars ~= false
end
local function SetRoundedPowerPreview(frame, enabled, outline)
    if not frame then return false end
    if not enabled or not RoundedPowerPreviewEnabled() then
        Helpers.ClearMasks(frame, "_msufCPRoundedMasked")
        Helpers.SetRoundedEdgeStackShown(frame, false, CP_POWER_ROUNDED_OPTS)
        if frame._msufCPRoundedBg then frame._msufCPRoundedBg:Hide() end
        return false
    end
    local maskPath, edgePath, strength = Helpers.ResolveRoundedMedia()
    CP_POWER_ROUNDED_OPTS.edgeTexture = edgePath
    CP_POWER_ROUNDED_OPTS.mediaStrength = strength
    local bgMask = Helpers.EnsureRoundedMask(frame, "background", frame, frame.bg,
        "_msufCPRoundedMasks", maskPath, Helpers.SnapOff)
    local fillMask = Helpers.EnsureRoundedMask(frame, "fill", frame, frame.fill,
        "_msufCPRoundedMasks", maskPath, Helpers.SnapOff)
    if not (bgMask and fillMask and Helpers.EnsureRoundedVisuals(frame, CP_POWER_ROUNDED_OPTS)) then return false end
    Helpers.SetMask(frame, frame.bg, bgMask, "_msufCPRoundedMasked")
    Helpers.SetMask(frame, frame.fill, fillMask, "_msufCPRoundedMasked")
    HideBarOutline(frame)
    outline = floor((tonumber(outline) or 0) + 0.5)
    if outline > 8 then outline = 8 end
    if outline > 0 then
        Helpers.ApplyRoundedEdgeStack(frame, outline, CP_POWER_ROUNDED_OPTS)
    else
        Helpers.SetRoundedEdgeStackShown(frame, false, CP_POWER_ROUNDED_OPTS)
    end
    if frame._msufCPRoundedBg then frame._msufCPRoundedBg:Hide() end
    return true
end
local function EnsureHandleGear(handle, shown)
    return Helpers.EnsurePreviewHandleGear(handle, {
        T = T,
        Tr = TR,
        shown = shown,
        openSettings = OpenClassPowerHandleSettings,
    })
end
local function RefreshHandleVisuals(preview)
    if not (preview and preview.handles) then return end
    Helpers.RefreshSelectedLayerButtons(preview, preview.selectedHandle)
    local guidesOn = GuidesOn(preview)
    for i = 1, #preview.handles do
        local h = preview.handles[i]
        if h and h._msufPlaced ~= true then
            h:Hide()
        elseif h then
            SetShownSafe(h, LayerOn(preview, h._layerKey or h._key))
        end
        local active = h == preview.selectedHandle or h._hovering == true
        local c = h._color or { 1, 1, 1 }
        if h.SetBackdropColor then h:SetBackdropColor(c[1], c[2], c[3], active and 0.16 or (guidesOn and 0.035 or 0)) end
        if h.SetBackdropBorderColor then h:SetBackdropBorderColor(c[1], c[2], c[3], active and 0.95 or (guidesOn and 0.44 or 0)) end
        if h._msuf2SettingsGear then h._msuf2SettingsGear:SetShown(guidesOn and h == preview.selectedHandle and h._msufPlaced == true) end
    end
    local selected = preview.selectedHandle
    -- Inline EnsureHandleGear: handle hovers repaint through here.
    if selected and selected._msufPlaced == true and guidesOn and Helpers.EnsurePreviewHandleGear then
        Helpers.EnsurePreviewHandleGear(selected, {
            T = T,
            Tr = TR,
            shown = true,
            openSettings = OpenClassPowerHandleSettings,
        })
    end
    if preview.hint then
        if selected and selected._msufPlaced == true then
            local x, y = ReadHandle(selected)
            T.SetTranslatedText(preview.hint, string.format(TR("%s   x: %d   y: %d"),
                TR(selected._label or selected._key or "Element"), Round(x or 0), Round(y or 0)))
        else
            T.SetTranslatedText(preview.hint, TR("Click to open settings. Move resources in Edit Mode."))
        end
    end
end
local function SelectHandle(handle)
    local preview = handle and handle._preview
    if not preview then return end
    preview.selectedHandle = handle
    RefreshHandleVisuals(preview)
end

-- Keep published commands fail-closed for callers holding the old preview API.
-- Moving resources belongs to the Edit Mode movers, including while this page is open.
function Preview.NudgeHandle()
    return false, "edit-mode-required"
end
function Preview.Pan()
    return false, "preview-auto-fit"
end
ExportPublic("MSUF_ClassPowerPreview_NudgeHandle", Preview.NudgeHandle)
ExportPublic("MSUF_ClassPowerPreview_Pan", Preview.Pan)

local function HandleOnEnter(self)
    self._hovering = true
    RefreshHandleVisuals(self._preview)
    if GameTooltip and Helpers.ShouldShowPreviewHandleTooltip(self._preview) then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TR(self._label), 1, 1, 1)
        GameTooltip:AddLine(TR("Click to open settings. Move resources in Edit Mode."), 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine(TR("Right-click opens quick actions."), 0.50, 0.78, 0.92, true)
        GameTooltip:Show()
    end
end
local function HandleOnLeave(self)
    self._hovering = nil
    RefreshHandleVisuals(self._preview)
    if GameTooltip then GameTooltip:Hide() end
end
local function HandleOnClick(self, button)
    SelectHandle(self)
    if button == "RightButton" then
        Helpers.ShowPreviewHandleContext(self, {
            M = M,
            T = T,
            Tr = TR,
            title = self._label or self._key,
            openSettings = OpenClassPowerHandleSettings,
        })
        return
    end
    OpenClassPowerHandleSettings(self)
end
-- Selection handles: field on the box, key, saved-offset store and keys with their defaults, label,
-- layer key (also the apply kind and the colour source) and the interaction priority.
local HANDLE_DEFS = {
    { field = "handleClass", key = "classPower", store = "bars", xKey = "classPowerOffsetX", yKey = "classPowerOffsetY",
        label = "Class resource bar", layer = "class" },
    { field = "handleClassText", key = "classPowerText", store = "bars", xKey = "classPowerTextOffsetX", yKey = "classPowerTextOffsetY",
        label = "Class resource text", layer = "classText", priority = 2 },
    { field = "handlePower", key = "detachedPower", store = "player", xKey = "detachedPowerBarOffsetX", yKey = "detachedPowerBarOffsetY",
        defaultY = -4, label = "Player power bar", layer = "power" },
    { field = "handlePowerText", key = "detachedPowerText", store = "player", xKey = "powerOffsetX", yKey = "powerOffsetY",
        defaultX = -4, defaultY = 4, label = "Player power text", layer = "powerText", priority = 2 },
    { field = "handleHP", key = "playerHP", store = "bars", xKey = "playerHPBarOffsetX", yKey = "playerHPBarOffsetY",
        label = "Second player HP bar", layer = "hp" },
    { field = "handleHPText", key = "playerHPText", store = "bars", xKey = "playerHPBarTextOffsetX", yKey = "playerHPBarTextOffsetY",
        label = "Second player HP text", layer = "hpText", priority = 2 },
    mana = { field = "handleMana", key = "alternativeMana", store = "bars", xKey = "altManaOffsetX", yKey = "altManaOffsetY",
        defaultY = -2, label = "Alternative Mana", layer = "mana" },
}
--- Selection handles open settings without changing saved resource positions.
local function MakeHandle(preview, def)
    local key, label, layerKey = def.key, def.label, def.layer
    local h = PixelLayoutRegion(CreateFrame("Button", nil, PreviewParent(preview), "BackdropTemplate"))
    h:SetSize(24, 20)
    PixelLayoutRegion(h, "SetBackdrop", { bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    -- Class Resource text can live on any absolute element layer. Keep every
    -- mouse catcher above that visual stack, and keep the smaller text handles
    -- deterministically above their broad bar handles.
    local interactionPriority = def.priority or 0
    h:SetFrameLevel((PreviewCore.InteractionFrameLevel
        and PreviewCore.InteractionFrameLevel(PreviewParent(preview), interactionPriority))
        or ((preview.canvas:GetFrameLevel() or 0) + 140 + interactionPriority))
    h:EnableMouse(true)
    if h.RegisterForClicks then h:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    h._preview, h._key, h._store = preview, key, def.store
    h._xKey, h._yKey = def.xKey, def.yKey
    h._defaultX, h._defaultY = def.defaultX or 0, def.defaultY or 0
    h._label, h._color, h._applyKind = label, LAYER_COLORS[layerKey], layerKey
    h._layerKey = layerKey
    h._previewLayerKey = layerKey
    h:SetScript("OnEnter", HandleOnEnter)
    h:SetScript("OnLeave", HandleOnLeave)
    h:SetScript("OnClick", HandleOnClick)
    h._msuf2CommandAction = {
        kind = "button",
        historyMode = "none",
        interaction = "preview.handle.select",
        previewSurface = "class-power",
        previewHandleKey = key,
        set = function()
            if h._msufPlaced ~= true then return false end
            if h.IsShown and not h:IsShown() then return false end
            SelectHandle(h)
            return OpenClassPowerHandleSettings(h)
        end,
    }
    RegisterPreviewControl(preview._catalogCtx, h, "handle." .. tostring(key), label or key, "button", "ephemeral", {
        help = "Selects this Class Resources preview element and opens its settings. Movement is handled in Edit Mode.",
    })
    local gear = EnsureHandleGear(h, false)
    gear._msuf2ClassPowerOpenCommand = gear._msuf2ClassPowerOpenCommand or {
        kind = "button",
        historyMode = "none",
        canExecute = function() return h ~= nil end,
        set = function() return OpenClassPowerHandleSettings(h) end,
    }
    RegisterPreviewControl(preview._catalogCtx, gear, "handle." .. tostring(key) .. ".open_settings",
        M.Format("Open %s settings", M.Tr(label or key)), "button", "action", {
            historyMode = "none",
            help = "Opens the settings section for this preview element.",
            command = gear._msuf2ClassPowerOpenCommand,
        })
    preview.handles[#preview.handles + 1] = h
    h:Hide()
    return h
end
--- Stretches a handle or bound around `region` by `pad`, or hides it while the region is not shown.
local function PlaceAround(frame, region, pad)
    if not (region and region.IsShown and region:IsShown()) then
        frame._msufPlaced = false
        frame:Hide()
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", region, "TOPLEFT", -pad, pad)
    frame:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", pad, -pad)
    frame._msufPlaced = true
    frame:Show()
    return true
end
local function PlaceHandle(handle, region, pad)
    return handle and PlaceAround(handle, region, tonumber(pad) or 4) or false
end
local FIT_TEXT_OPTS = { fitText = true }
local function PlaceTextHandle(handle, parent, regions)
    if Helpers.PlaceHandleAroundRegions(handle, parent, regions, 4, FIT_TEXT_OPTS) then
        handle._msufPlaced = true
        return true
    end
    for i = 1, #(regions or {}) do
        local region = regions[i]
        if region and region.IsShown and region:IsShown() then
            handle:ClearAllPoints()
            handle:SetSize(max(24, (region.GetStringWidth and region:GetStringWidth() or 20) + 10),
                max(18, (region.GetStringHeight and region:GetStringHeight() or 12) + 6))
            handle:SetPoint("CENTER", region, "CENTER", 0, 0)
            handle._msufPlaced = true
            handle:Show()
            return true
        end
    end
    handle._msufPlaced = false
    handle:Hide()
    return false
end
local function MakeText(parent, layer, justify, subLevel)
    local fs = PixelLayoutRegion(parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlightSmall", subLevel))
    fs:SetJustifyH(justify or "CENTER")
    if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    return fs
end
local function MakeTexture(parent, layer, subLevel, allPoints, hidden)
    local tex = PixelLayoutRegion(parent:CreateTexture(nil, layer, nil, subLevel))
    tex:SetTexture(WHITE8)
    if allPoints then tex:SetAllPoints() end
    if hidden then tex:Hide() end
    return tex
end
local function EnsureMeter(preview, name, separateTextOwner)
    if preview[name] then return preview[name] end
    local frame = PixelLayoutRegion(CreateFrame("Frame", nil, PreviewParent(preview), "BackdropTemplate"))
    PixelLayoutRegion(frame, "SetBackdrop", { bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    frame.bg = MakeTexture(frame, "BACKGROUND", nil, true)
    frame.fill = MakeTexture(frame, "ARTWORK")
    frame.edge = MakeTexture(frame, "OVERLAY", 7, true, true)
    local textOwner = frame
    if separateTextOwner then
        textOwner = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
        textOwner:SetAllPoints(frame)
        if textOwner.EnableMouse then textOwner:EnableMouse(false) end
        frame.textOwner = textOwner
    end
    frame.left = MakeText(textOwner, "OVERLAY", "LEFT")
    frame.center = MakeText(textOwner, "OVERLAY", "CENTER")
    frame.right = MakeText(textOwner, "OVERLAY", "RIGHT")
    preview[name] = frame
    return frame
end
-- Fill length along one axis: at least one pixel, a rounded share of `size` while the fraction is positive.
local function FillSpan(size, frac)
    return frac > 0 and max(1, floor(size * frac + 0.5)) or 1
end
-- Crops and sizes the fill texture to a fraction of the meter.
local function SetFillExtent(frame, w, h, frac)
    local fill = frame.fill
    if frame._msufCPPreviewShapeAxis == "VERTICAL" then
        fill:SetTexCoord(0, 1, frac > 0 and (1 - frac) or 1, 1)
        fill:SetSize(w, FillSpan(h, frac))
    else
        fill:SetTexCoord(0, frame._msufCPPreviewHasShape and frac or 1, 0, 1)
        fill:SetSize(FillSpan(w, frac), h)
    end
    if frac > 0 then fill:Show() else fill:Hide() end
end
local function RenderMeter(frame, shapeInfo, opts)
    opts = opts or {}
    local w = max(1, floor(tonumber(opts.width) or 1))
    local h = max(1, floor(tonumber(opts.height) or 1))
    local frac = Clamp(opts.fraction, 1, 0, 1)
    frame._msufCPPreviewW = w
    frame._msufCPPreviewH = h
    frame._msufCPPreviewShapeAxis = shapeInfo and shapeInfo.axis or nil
    frame._msufCPPreviewHasShape = shapeInfo ~= nil
    frame:SetSize(w, h)
    frame.bg:ClearAllPoints()
    frame.bg:SetAllPoints(frame)
    frame.fill:ClearAllPoints()
    if shapeInfo then
        HideBarOutline(frame)
        frame.bg:SetTexture(shapeInfo.bg)
        frame.bg:SetVertexColor(opts.bgR or opts.r or 1, opts.bgG or opts.g or 1, opts.bgB or opts.b or 1, opts.bgA or 0.28)
        frame.fill:SetTexture(shapeInfo.fill)
        frame.fill:SetVertexColor(opts.r or 1, opts.g or 1, opts.b or 1, frac > 0 and 1 or 0)
        SetFillExtent(frame, w, h, frac)
        if shapeInfo.axis == "VERTICAL" then
            frame.fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            frame.fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        else
            frame.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        end
        if frame.edge then
            local outline = floor((tonumber(opts.outline) or 0) + 0.5)
            if outline > 0 then
                frame.edge:SetTexture(shapeInfo.edge)
                frame.edge:SetVertexColor(PREVIEW_BORDER_COLOR[1], PREVIEW_BORDER_COLOR[2], PREVIEW_BORDER_COLOR[3], Core.ShapeOutlineAlpha(outline))
                frame.edge:SetAllPoints(frame)
                frame.edge:Show()
            else
                frame.edge:Hide()
            end
        end
    else
        if frame.edge then frame.edge:Hide() end
        ApplyBarOutline(frame, opts.outline or 0)
        frame.bg:SetTexture(opts.bgTexture or WHITE8)
        frame.bg:SetVertexColor(opts.bgR or 0, opts.bgG or 0, opts.bgB or 0, opts.bgA or 0.35)
        frame.fill:SetTexture(opts.texture or WHITE8)
        frame.fill:SetVertexColor(opts.r or 1, opts.g or 1, opts.b or 1, 1)
        SetFillExtent(frame, w, h, frac)
        frame.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    end
end
-- Per-tick fill update: the same crop and length as SetFillExtent, inline so a tick adds no Lua call.
local function UpdateMeterFill(frame, fraction)
    if not (frame and frame.fill) then return false end
    local w = max(1, floor(tonumber(frame._msufCPPreviewW) or (frame.GetWidth and frame:GetWidth()) or 1))
    local h = max(1, floor(tonumber(frame._msufCPPreviewH) or (frame.GetHeight and frame:GetHeight()) or 1))
    local frac = tonumber(fraction) or 0
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local fill = frame.fill
    if frame._msufCPPreviewShapeAxis == "VERTICAL" then
        fill:SetTexCoord(0, 1, frac > 0 and (1 - frac) or 1, 1)
        fill:SetHeight(frac > 0 and max(1, floor(h * frac + 0.5)) or 1)
    else
        fill:SetTexCoord(0, frame._msufCPPreviewHasShape and frac or 1, 0, 1)
        fill:SetWidth(frac > 0 and max(1, floor(w * frac + 0.5)) or 1)
    end
    if frac > 0 then fill:Show() else fill:Hide() end
    return true
end
--- A Cooldown Manager viewer by frame name: the effective (relocated) frame first, then the global.
local function CooldownFrame(frameName)
    return Core.GetEffectiveCooldownFrame(frameName) or _G[frameName]
end
--- Plain rectangles of the shown Cooldown Manager viewers, placed relative to the live player frame when
--- there is one (the scene sizes and anchors the container from these like the live layout does).
local CDM_VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
function CPPreview.ProjectCooldowns(out)
    local player = MSUF.UF.GetFrame and MSUF.UF.GetFrame("player")
    local pe = player and player.GetEffectiveScale and tonumber(player:GetEffectiveScale())
    local px, py
    if pe and pe > 0 and player.GetCenter then px, py = player:GetCenter() end
    local any
    for i = 1, #CDM_VIEWERS do
        local name = CDM_VIEWERS[i]
        local frame = CooldownFrame(name)
        if frame and frame.IsShown and frame:IsShown() and (tonumber(frame:GetWidth()) or 0) > 0 then
            local entry = out[name]
            if not entry then
                entry = {}
                out[name] = entry
            end
            any = true
            local ve = tonumber(frame:GetEffectiveScale()) or 1
            entry.width, entry.height = frame:GetWidth(), frame:GetHeight()
            entry.scale = px and ve / pe or tonumber(frame:GetScale()) or 1
            local vx, vy = frame:GetCenter()
            if px and vx and vy and ve > 0 then
                entry.x, entry.y = (vx * ve - px * pe) / ve, (vy * ve - py * pe) / ve
            else
                entry.x, entry.y = nil, nil
            end
        else
            out[name] = nil
        end
    end
    return any and out or nil
end
--- Width of the class resource container on a player frame `frameW` wide, by the
--- live rule (ClassPower Layout.ResolveWidth): the pip auto-fit, a Cooldown
--- Manager viewer's scaled width, the custom width, else the frame width less
--- the engine's inset. Unclamped like the live container; the unit preview and
--- this page each clamp for their own canvas. `nativeBar` is a Warrior-style
--- bar that never takes a pip shape.
function CPPreview.ContainerWidth(bars, frameW, height, segCount, nativeBar)
    bars = bars or {}
    local UFShared = MSUF.UF.Shared
    local widthMode = bars.classPowerWidthMode or "player"
    frameW = tonumber(frameW) or 275
    local shape = not nativeBar and CP_SHAPES[NormalizeClassShape(bars.classPowerShape)] or nil
    if shape and widthMode == "auto_pips" then
        return UFShared.ClassPowerAutoFitWidth(segCount, height, bars.classPowerGap)
    end
    local cdmFrames = Core.CPConst and Core.CPConst.CDM_FRAMES
    local frameName = cdmFrames and cdmFrames[widthMode]
    if frameName then
        local source = CooldownFrame(frameName)
        local width
        if source and source.IsShown and source:IsShown() then
            -- ClassPower builds its container lazily and keeps it; cached once it exists.
            local container = Core.ClassPowerContainer
            if not container then
                container = MSUF.Optional("MSUF_ClassPowerContainer")
                Core.ClassPowerContainer = container
            end
            width = Core.CDMScaledWidth(source, container)
        end
        if tonumber(width) and width >= 30 then return width end
    elseif widthMode == "custom" then
        local width = tonumber(bars.classPowerWidth) or 0
        if width >= 30 then return width end
    end
    return frameW - UFShared.ClassPowerFrameInsets(widthMode)
end
--- Distance of the container's left edge from the player frame (ClassPower
--- Layout.Position); the Offset X setting comes on top.
function CPPreview.ContainerInsetX(bars)
    local _, insetX = MSUF.UF.Shared.ClassPowerFrameInsets(bars and bars.classPowerWidthMode or "player")
    return insetX
end

local function IsAugCompositePreviewSpec(spec)
    return spec and spec.key == "evoker_augmentation_ebon"
        and type(spec.secondaryTimer) == "table"
end

--- True while the Player Power bar renders Ebon Might instead of Mana. Ordinary
--- Power visibility still decides whether that bar exists at all, exactly as it
--- does at runtime.
local function PowerShowsEbonMight(bars, player, spec)
    return IsAugCompositePreviewSpec(spec)
        and not PlayerManaSourceActive(player)
        and bars.showEbonMight ~= false
end

local function ClassPowerPreviewState(bars, spec)
    if bars and bars.showClassPower == false then return false, "settings" end
    if not spec or spec.enabled == false or spec.mode == "none" then return false, "resource" end
    return true
end

local function PlaceClassTextHandle(preview, scene)
    local text = scene.CP.text
    if text and text:IsShown() then
        PlaceTextHandle(preview.handleClassText, PreviewParent(preview), { text })
    else
        preview.handleClassText:Hide()
    end
end
-- The spec's own class, else the page's current preview class (every page version provides it).
local function SpecClass(spec)
    return SpecToken(spec) or M.GetClassPowerPreviewClassToken()
end

--- The class resource row: the engine's ClassPower scene inside a player-frame stand-in over the reference frame.
--- The scene is made when the row is first painted and kept for the box. It reads every look setting the way the
--- live resource does; this feeds the previewed resource, the layer overlays and the Cooldown Manager rectangles.
local function RenderClassPower(preview, bars, player, spec)
    local scene = preview.cpScene
    local enabled, disabledReason = ClassPowerPreviewState(bars, spec)
    if not enabled or (scene and not Wanted(preview, "class")) then
        if scene then scene:Hide() end
        if preview.classPower then preview.classPower:Hide() end
        preview.handleClass:Hide()
        preview.handleClassText:Hide()
        if not enabled then return nil, disabledReason end
        return preview.classPower
    end
    local root = preview.cpSceneRoot
    if not root then
        root = MSUF.GF.NewPreviewScene(PreviewParent(preview))
        preview.cpSceneRoot, preview.cpSample, preview.cpTick, preview.cpCooldowns = root, {}, {}, {}
        preview.cpOpts = { sample = preview.cpSample, point = "CENTER", x = 0, y = -34 }
    end
    root:Activate()
    local sample, elapsed, animated = preview.cpSample, PreviewElapsed(preview), AnimationEnabled(preview)
    CPPreview.SceneStatic(sample, spec, SpecClass(spec))
    local overlay = sample.bars
    -- The Border and Res Text layers switch the live outline and text off for this preview only.
    if Wanted(preview, "border") then overlay.classPowerOutline = nil else overlay.classPowerOutline = 0 end
    if Wanted(preview, "classText") then overlay.classPowerShowText = nil else overlay.classPowerShowText = false end
    CPPreview.SceneValues(sample, spec, animated and CPPreview.AnimatedValue(spec, elapsed) or nil, elapsed, animated)
    local opts = preview.cpOpts
    opts.playerWidth, opts.playerHeight = preview.playerW, preview.playerH
    opts.cooldowns = CPPreview.ProjectCooldowns(preview.cpCooldowns)
    scene = root:ClassPower(opts)
    preview.cpScene, preview.cpSpec = scene, spec
    local frame, container = scene:Frame(), scene.CP.container
    if not (frame and frame:IsShown() and container:IsShown()) then
        preview.handleClass:Hide()
        preview.handleClassText:Hide()
        return nil, "resource"
    end
    preview.classPower = container
    PlaceHandle(preview.handleClass, container, 5)
    PlaceClassTextHandle(preview, scene)
    return container
end

--- Ebon Might is rendered by the Player Power bar itself, so this dedicated row
--- no longer exists. The stub stays because the surrounding preview plumbing
--- (bounds, zoom fit, HP anchoring) still threads an optional second class row.
local function RenderSecondaryClassTimer(preview)
    local frame = preview and preview.ebonTimer
    if not frame then return nil end
    frame._msufCPPreviewActive = false
    frame._msufCPPreviewTimerAnim = nil
    frame:Hide()
    HideBarOutline(frame)
    frame.left:Hide()
    frame.center:Hide()
    frame.right:Hide()
    return nil
end

local function DetachedPowerShown(player)
    return player.powerBarDetached == true and player.detachedPowerBarAnchorToClassPower == true
end
local function DetachedPowerWidth(preview, bars, player, classFrame)
    local shape = ResolvePowerShape(player.detachedPowerBarShape or "BAR", bars.classPowerShape)
    return CPPreview.ResolveDetachedPowerWidth({
        shape = shape,
        orbSize = player.detachedPowerOrbSize,
        syncClass = player.detachedPowerBarSyncClassPower ~= false,
        classWidth = classFrame and classFrame.GetWidth and classFrame:GetWidth() or nil,
        classFallbackWidth = (tonumber(preview.playerW) or 275) - 4,
        widthMode = bars.detachedPowerBarWidthMode,
        manualWidth = player.detachedPowerBarWidth,
        frameWidth = preview.playerW,
    }), shape
end
-- Anchor, width share and layout keys of the three meter text slots.
local METER_TEXT_SLOTS = {
    { key = "left", point = "LEFT", inset = 4, share = 0.34, layoutX = "leftX", layoutY = "leftY" },
    { key = "center", point = "CENTER", inset = 0, share = 1, layoutX = "centerX", layoutY = "centerY" },
    { key = "right", point = "RIGHT", inset = -4, share = 0.34, layoutX = "rightX", layoutY = "rightY" },
}
local function ApplyMeterText(frame, size, x, y, layout, leftText, centerText, rightText)
    x, y = x or 0, y or 0
    local width = frame:GetWidth() or 100
    local textH = max(14, (frame:GetHeight() or 8) + 8)
    for i = 1, #METER_TEXT_SLOTS do
        local slot = METER_TEXT_SLOTS[i]
        local region = frame[slot.key]
        local text = select(i, leftText, centerText, rightText) or ""
        ApplyFont(region, size)
        region:SetText(text)
        region:SetTextColor(1, 1, 1, 1)
        region:ClearAllPoints()
        region:SetPoint(slot.point, frame, slot.point, slot.inset + (layout and layout[slot.layoutX] or x),
            layout and layout[slot.layoutY] or y)
        region:SetSize(max(20, width * slot.share), textH)
        if text ~= "" then region:Show() else region:Hide() end
    end
end

local function PowerTextSide(player, general, side, axis)
    local key, legacy = "powerText" .. side .. "Offset" .. axis, "power" .. side .. "Offset" .. axis
    return tonumber(player[key] or player[legacy] or general[key] or general[legacy]) or 0
end
local function ResolvePlayerPowerTextLayout(player)
    player = player or {}
    local general = Section("general")
    local baseX = tonumber(player.powerOffsetX or player.powerTextOffsetX or general.powerOffsetX or general.powerTextOffsetX) or -4
    local baseY = tonumber(player.powerOffsetY or player.powerTextOffsetY or general.powerOffsetY or general.powerTextOffsetY) or 4
    local baseline = tonumber((player.fontOverride == true and player.fontBaselineOffset) or general.fontBaselineOffset) or 0
    if baseline < -4 then baseline = -4 elseif baseline > 4 then baseline = 4 end
    baseY = baseY + baseline
    return {
        leftX = baseX + PowerTextSide(player, general, "Left", "X"), leftY = baseY + PowerTextSide(player, general, "Left", "Y"),
        centerX = baseX + PowerTextSide(player, general, "Center", "X"), centerY = baseY + PowerTextSide(player, general, "Center", "Y"),
        rightX = baseX + PowerTextSide(player, general, "Right", "X"), rightY = baseY + PowerTextSide(player, general, "Right", "Y"),
    }
end

local function PlayerPowerTextShown(player)
    player = player or {}
    if player.showPowerText ~= nil then return player.showPowerText ~= false end
    return player.showPower ~= false
end
-- Left, center and right text of the detached power bar at a preview fraction.
local function DetachedPowerTexts(player, fraction)
    local current = floor((fraction * 100) + 0.5)
    local delimiter = player.powerTextSeparator or player.hpTextSeparator or ""
    return ModeText(player.powerTextLeft, current, 100, delimiter, HidePercentValue(player, "powerTextLeftHidePercentSymbol")),
        ModeText(player.powerTextCenter, current, 100, delimiter, HidePercentValue(player, "powerTextCenterHidePercentSymbol")),
        ModeText(player.powerTextRight or player.powerTextMode or "CURPERCENT", current, 100, delimiter,
            HidePercentValue(player, "powerTextRightHidePercentSymbol"))
end
-- The player's own value, else the shared bars value, for a texture key.
local function PlayerThenBars(player, bars, key)
    local value = player[key]
    if type(value) ~= "string" or value == "" then value = bars[key] end
    return value
end
local function TimerText(spec, value)
    return CPPreview.TextForValue(spec, value) or tostring(spec.previewText or "12.0")
end
-- Anchors the detached power bar under the class resource when it shows, else under the player stand-in.
local function AnchorDetachedPower(preview, frame, player, classFrame, x, y)
    frame:ClearAllPoints()
    if classFrame and classFrame.IsShown and classFrame:IsShown() then
        frame:SetPoint("TOP", classFrame, "BOTTOM", x, y)
    elseif tostring(player.detachedPowerBarAnchorMode or ""):upper() == "LEGACY_TOPLEFT" then
        frame:SetPoint("TOPLEFT", preview.playerRef, "BOTTOMLEFT", x, y)
    else
        frame:SetPoint("TOP", preview.playerRef, "BOTTOM", x, y)
    end
end
-- The native duration binding always writes this text, independently of the
-- ordinary power-text slots, which are dropped for this bar.
local function PaintEbonPowerText(preview, frame, player, ebonSpec, ebonAnimated)
    frame.left:Hide()
    frame.right:Hide()
    local showText = ebonSpec.nativeDurationText == true or PlayerPowerTextShown(player)
    if showText then
        local textR, textG, textB = CPPreview.ResolveTextColor(1, 1, 1)
        ApplyFont(frame.center, Clamp(player.powerFontSize, 14, 6, 48))
        frame.center:SetText(TimerText(ebonSpec, ebonAnimated))
        frame.center:SetTextColor(textR, textG, textB, CPTextAlpha())
        frame.center:ClearAllPoints()
        frame.center:SetPoint("CENTER", frame, "CENTER",
            tonumber(player.powerOffsetX) or 0,
            tonumber(player.powerOffsetY) or 0)
        frame.center:Show()
        PlaceTextHandle(preview.handlePowerText, PreviewParent(preview), { frame.center })
    else
        frame.center:Hide()
        preview.handlePowerText:Hide()
    end
    frame._msufCPPreviewTimerAnim = { spec = ebonSpec, showText = showText }
end

--- Detached power preview follows the same anchoring relationship as runtime:
--- it can attach to ClassPower, but no live player power events are involved.
local function RenderDetachedPower(preview, bars, player, classFrame, spec)
    local frame = EnsureMeter(preview, "detachedPower")
    if not DetachedPowerShown(player) then
        SetRoundedPowerPreview(frame, false)
        frame:Hide()
        HideBarOutline(frame)
        preview.handlePower:Hide()
        preview.handlePowerText:Hide()
        return nil
    end
    -- Augmentation: this bar renders Ebon Might's remaining duration instead of
    -- Mana. Geometry, media and outline stay the ordinary Player Power settings.
    local ebonSpec = PowerShowsEbonMight(bars, player, spec) and spec.secondaryTimer or nil
    if type(ebonSpec) ~= "table" then ebonSpec = nil end
    local width, shape = DetachedPowerWidth(preview, bars, player, classFrame)
    local shapeInfo = POWER_SHAPES[shape]
    local height = shape == "ORB" and width or Clamp(player.detachedPowerBarHeight, 6, 2, 80)
    local x, y = tonumber(player.detachedPowerBarOffsetX) or 0, tonumber(player.detachedPowerBarOffsetY) or -4
    local pr, pg, pb = PowerColor(player)
    -- The detached bar follows the normal power-texture precedence (per-unit
    -- Player value -> shared bars value -> global bar texture); there is no
    -- separate Class Resources texture anymore (see UF config).
    local fgTex = ResolveTexture(PlayerThenBars(player, bars, "powerBarTexture"))
    -- An unset background follows the global bar background, not the
    -- foreground, so detaching alone never repaints the bar.
    local bgTex = ResolveTexture(PlayerThenBars(player, bars, "powerBarBgTexture"),
        Core.GetBarBackgroundTexture() or fgTex)
    -- Class Resources owns the detached Player outline for every shape,
    -- including the rectangular bar.
    local outline = PreviewOutline(preview, bars.detachedPowerBarOutline, 1)
    local fraction = AnimatedMeterFraction(preview, 0.72, 0.46, 0.08, 0.96)
    local ebonAnimated
    if ebonSpec then
        pr, pg, pb = CPPreview.ResolveBaseColor(ebonSpec, bars, 0.40, 0.80, 0.60)
        ebonAnimated = AnimationEnabled(preview) and CPPreview.AnimatedValue(ebonSpec, PreviewElapsed(preview)) or nil
        fraction = Clamp(tonumber(ebonAnimated) or ebonSpec.value, 0.6, 0, 1)
    end
    AnchorDetachedPower(preview, frame, player, classFrame, x, y)
    RenderMeter(frame, shapeInfo, {
        width = width, height = height, fraction = fraction,
        r = pr, g = pg, b = pb, bgR = pr, bgG = pg, bgB = pb, bgA = 0.28,
        texture = fgTex, bgTexture = bgTex, outline = outline,
    })
    SetRoundedPowerPreview(frame, shapeInfo == nil, outline)
    frame:Show()
    if ebonSpec then
        PaintEbonPowerText(preview, frame, player, ebonSpec, ebonAnimated)
        PlaceHandle(preview.handlePower, frame, 5)
        return frame
    end
    frame._msufCPPreviewTimerAnim = nil
    if PlayerPowerTextShown(player) and player.detachedPowerBarTextOnBar == true then
        ApplyMeterText(frame, Clamp(player.powerFontSize, 14, 6, 48), nil, nil, ResolvePlayerPowerTextLayout(player),
            DetachedPowerTexts(player, fraction))
        PlaceTextHandle(preview.handlePowerText, PreviewParent(preview), { frame.left, frame.center, frame.right })
    else
        HideMeterText(frame)
        preview.handlePowerText:Hide()
    end
    PlaceHandle(preview.handlePower, frame, 5)
    return frame
end
local function HPWidth(preview, bars, classFrame, powerFrame)
    local mode = tostring(bars.playerHPBarWidthMode or "class"):lower()
    local width
    if mode == "custom" then
        width = tonumber(bars.playerHPBarWidth)
        if not width or width < 20 then width = preview.playerW end
    elseif mode == "power" then
        width = powerFrame and powerFrame.GetWidth and powerFrame:GetWidth()
    elseif mode == "player" then
        width = preview.playerW
    else
        width = classFrame and classFrame.GetWidth and classFrame:GetWidth()
    end
    width = tonumber(width) or preview.playerW
    if width < 20 then width = 20 elseif width > 1200 then width = 1200 end
    return floor(width + 0.5)
end
local function PlaceHP(frame, preview, bars, classFrame, powerFrame, classBottomFrame)
    local mode = tostring(bars.playerHPBarAnchor or "CLASS_TOP"):upper()
    local anchor = (mode == "POWER_TOP" or mode == "POWER_BOTTOM") and powerFrame or classFrame
    if mode == "CLASS_BOTTOM" and classBottomFrame then anchor = classBottomFrame end
    if not (anchor and anchor.IsShown and anchor:IsShown()) then
        anchor = ((mode == "CLASS_BOTTOM" or mode == "POWER_BOTTOM") and classBottomFrame)
            or classFrame or preview.playerRef
    end
    local x = tonumber(bars.playerHPBarOffsetX) or 0
    local y = tonumber(bars.playerHPBarOffsetY) or 0
    local gap = Clamp(bars.playerHPBarGap, 2, 0, 60)
    frame:ClearAllPoints()
    if mode == "CLASS_BOTTOM" or mode == "POWER_BOTTOM" then
        frame:SetPoint("TOP", anchor, "BOTTOM", x, y - gap)
    else
        frame:SetPoint("BOTTOM", anchor, "TOP", x, y + gap)
    end
end
local function HPTextConfig(bars, player)
    local left, center, right, delimiter, reverse, hideLeft, hideCenter, hideRight
    if bars.playerHPBarUsePlayerText ~= false then
        left = tostring(player.textLeft or "NONE"):upper()
        center = tostring(player.textCenter or "NONE"):upper()
        right = tostring(player.textRight or player.hpTextMode or "CURPERCENT"):upper()
        delimiter = player.hpTextSeparator or ""
        reverse = player.hpTextReverse == true
        hideLeft = HidePercentValue(player, "hpTextLeftHidePercentSymbol")
        hideCenter = HidePercentValue(player, "hpTextCenterHidePercentSymbol")
        hideRight = HidePercentValue(player, "hpTextRightHidePercentSymbol")
    else
        left = tostring(bars.playerHPBarTextLeft or "NONE"):upper()
        center = tostring(bars.playerHPBarTextCenter or "NONE"):upper()
        right = tostring(bars.playerHPBarTextRight or "CURPERCENT"):upper()
        delimiter = bars.playerHPBarTextSeparator or ""
        reverse = bars.playerHPBarTextReverse == true
        hideLeft = HidePercentValue(bars, "playerHPBarTextLeftHidePercentSymbol")
        hideCenter = HidePercentValue(bars, "playerHPBarTextCenterHidePercentSymbol")
        hideRight = HidePercentValue(bars, "playerHPBarTextRightHidePercentSymbol")
    end
    if reverse then
        left, right = HP_TEXT_REVERSE[right] or right, HP_TEXT_REVERSE[left] or left
        center = HP_TEXT_REVERSE[center] or center
        hideLeft, hideRight = hideRight, hideLeft
    end
    return left, center, right, delimiter, hideLeft, hideCenter, hideRight
end
-- Left, center and right text of the extra HP bar at a preview fraction.
local function HPTexts(bars, player, fraction)
    local leftMode, centerMode, rightMode, delimiter, hideLeft, hideCenter, hideRight = HPTextConfig(bars, player)
    local maxValue = 1000000
    local current = floor((maxValue * fraction) + 0.5)
    return ModeText(leftMode, current, maxValue, delimiter, hideLeft),
        ModeText(centerMode, current, maxValue, delimiter, hideCenter),
        ModeText(rightMode, current, maxValue, delimiter, hideRight)
end

--- Optional ClassPower-owned player HP preview. It mirrors runtime layout/text
--- rules without reading real UnitHealth.
local function RenderPlayerHP(preview, bars, player, classFrame, powerFrame, spec, classBottomFrame)
    local frame = EnsureMeter(preview, "playerHP")
    if bars.playerHPBarEnabled ~= true then
        frame:Hide()
        HideBarOutline(frame)
        preview.handleHP:Hide()
        preview.handleHPText:Hide()
        return nil
    end
    local shape = ResolveHPShape(bars, player)
    local shapeInfo = POWER_SHAPES[shape]
    local followPower = tostring(bars.playerHPBarShape or "BAR"):upper() == "FOLLOW_POWER"
    local orbSize = followPower and Clamp(player.detachedPowerOrbSize, 54, 20, 160) or Clamp(bars.playerHPBarOrbSize, 54, 20, 160)
    local width = shape == "ORB" and orbSize or HPWidth(preview, bars, classFrame, powerFrame)
    local height = shape == "ORB" and width or Clamp(bars.playerHPBarHeight, 6, 2, 80)
    local hr, hg, hb = HPColor(bars, spec)
    local fgTex = ResolveTexture(bars.playerHPBarTexture)
    local bgTex = ResolveTexture(bars.playerHPBarBgTexture, fgTex)
    local fraction = AnimatedMeterFraction(preview, 0.74, 0.34, 0.18, 1.00)
    PlaceHP(frame, preview, bars, classFrame, powerFrame, classBottomFrame)
    RenderMeter(frame, shapeInfo, {
        width = width, height = height, fraction = fraction,
        r = hr, g = hg, b = hb, bgR = 0, bgG = 0, bgB = 0, bgA = Alpha(bars.playerHPBarBgAlpha, 0.35),
        texture = fgTex, bgTexture = bgTex, outline = PreviewOutline(preview, bars.playerHPBarOutline, 1),
    })
    frame:Show()
    if bars.playerHPBarTextEnabled ~= false then
        ApplyMeterText(frame, Clamp(bars.playerHPBarUsePlayerText ~= false and player.hpFontSize or bars.playerHPBarTextSize, 14, 6, 48),
            tonumber(bars.playerHPBarTextOffsetX) or 0, tonumber(bars.playerHPBarTextOffsetY) or 0, nil,
            HPTexts(bars, player, fraction))
        PlaceTextHandle(preview.handleHPText, PreviewParent(preview), { frame.left, frame.center, frame.right })
    else
        HideMeterText(frame)
        preview.handleHPText:Hide()
    end
    PlaceHandle(preview.handleHP, frame, 5)
    return frame
end
-- Per-tick repaint, kept as plain file-level functions with the text math inline (no extra Lua call per tick).
local function UpdateClassPowerAnimation(preview)
    local scene, spec = preview.cpScene, preview.cpSpec
    if not (scene and spec) then return false end
    local frame = scene:Frame()
    if not (frame and frame:IsShown()) then return true end
    local elapsed = PreviewElapsed(preview)
    CPPreview.SceneValues(preview.cpTick, spec, CPPreview.AnimatedValue(spec, elapsed), elapsed, true)
    scene:Tick(preview.cpTick)
    PlaceClassTextHandle(preview, scene)
    return true
end
--- Drives a native duration meter. Ebon Might now runs on the Player Power bar,
--- so its text follows the Power text layer rather than the Class Resource one.
local function UpdateSecondaryClassTimerAnimation(preview, frame, textLayerKey)
    local state = frame and frame._msufCPPreviewTimerAnim
    local spec = state and state.spec
    if not (preview and frame and spec) then return false end
    if frame.IsShown and not frame:IsShown() then return true end
    local value = CPPreview.AnimatedValue(spec, PreviewElapsed(preview)) or tonumber(spec.value) or 0.6
    UpdateMeterFill(frame, value)
    if state.showText and frame.center then
        frame.center:SetText(CPPreview.TextForValue(spec, value) or tostring(spec.previewText or "12.0"))
        if LayerOn(preview, textLayerKey or "classText") then frame.center:Show() end
    end
    return true
end
local function UpdateDetachedPowerAnimation(preview, frame, bars, player)
    if not (preview and frame and bars and player) then return false end
    if frame.IsShown and not frame:IsShown() then return true end
    -- Augmentation drives this bar from the Ebon Might duration instead of a
    -- power fraction, and its native duration text replaces the power slots.
    local ebonState = frame._msufCPPreviewTimerAnim
    if ebonState and ebonState.spec then
        return UpdateSecondaryClassTimerAnimation(preview, frame, "powerText")
    end
    local fraction = AnimatedMeterFraction(preview, 0.72, 0.46, 0.08, 0.96)
    UpdateMeterFill(frame, fraction)
    if PlayerPowerTextShown(player) and player.detachedPowerBarTextOnBar == true then
        local leftMode = tostring(player.powerTextLeft or "NONE"):upper()
        local centerMode = tostring(player.powerTextCenter or "NONE"):upper()
        local rightMode = tostring(player.powerTextRight or player.powerTextMode or "CURPERCENT"):upper()
        local delimiter = player.powerTextSeparator or player.hpTextSeparator or ""
        local current = floor((fraction * 100) + 0.5)
        if frame.left then frame.left:SetText(ModeText(leftMode, current, 100, delimiter, HidePercentValue(player, "powerTextLeftHidePercentSymbol"))) end
        if frame.center then frame.center:SetText(ModeText(centerMode, current, 100, delimiter,
            HidePercentValue(player, "powerTextCenterHidePercentSymbol"))) end
        if frame.right then frame.right:SetText(ModeText(rightMode, current, 100, delimiter, HidePercentValue(player, "powerTextRightHidePercentSymbol"))) end
    end
    return true
end
local function UpdatePlayerHPAnimation(preview, frame, bars, player)
    if not (preview and frame and bars and player) then return false end
    if frame.IsShown and not frame:IsShown() then return true end
    local fraction = AnimatedMeterFraction(preview, 0.74, 0.34, 0.18, 1.00)
    UpdateMeterFill(frame, fraction)
    if bars.playerHPBarTextEnabled ~= false then
        local leftMode, centerMode, rightMode, delimiter, hideLeft, hideCenter, hideRight = HPTextConfig(bars, player)
        local maxValue = 1000000
        local current = floor((maxValue * fraction) + 0.5)
        if frame.left then frame.left:SetText(ModeText(leftMode, current, maxValue, delimiter, hideLeft)) end
        if frame.center then frame.center:SetText(ModeText(centerMode, current, maxValue, delimiter, hideCenter)) end
        if frame.right then frame.right:SetText(ModeText(rightMode, current, maxValue, delimiter, hideRight)) end
    end
    return true
end
local function RefreshClassPowerAnimation(preview)
    local state = preview and preview._msufCPPreviewAnim
    if not state then return false end
    if state.classFrame and not UpdateClassPowerAnimation(preview) then return false end
    if state.ebonFrame and state.ebonFrame._msufCPPreviewTimerAnim
        and state.ebonFrame._msufCPPreviewTimerAnim.spec
        and not UpdateSecondaryClassTimerAnimation(preview, state.ebonFrame) then return false end
    if state.powerFrame and not UpdateDetachedPowerAnimation(preview, state.powerFrame, state.bars, state.player) then return false end
    if state.hpFrame and not UpdatePlayerHPAnimation(preview, state.hpFrame, state.bars, state.player) then return false end
    if preview.altMana and preview.altMana:IsShown() then
        UpdateMeterFill(preview.altMana, AnimatedMeterFraction(preview, .68, .36, .15, .96))
    end
    Preview.UpdateSampleThresholds(preview)
    return true
end
local function PaintPlayerReference(preview)
    local player = preview.playerRef
    player:SetSize(preview.playerW, preview.playerH)
    player:ClearAllPoints()
    player:SetPoint("CENTER", PreviewParent(preview), "CENTER", 0, -34)
end
local function CreatePlayerReference(preview)
    preview.playerRef = PixelLayoutRegion(CreateFrame("Frame", nil, PreviewParent(preview)))
    preview.playerRef:EnableMouse(false)
end
function Preview.RenderAlternativeMana(preview, bars)
    if bars.showAltMana ~= true then
        SetShownSafe(preview.altMana, false)
        return
    end
    local frame = EnsureMeter(preview, "altMana")
    local width = bars.altManaWidthMode == "custom" and tonumber(bars.altManaWidth) or nil
    if not width or width < 20 then width = preview.playerW - 4 end
    local r, g, blue = CPPreview.ResolveColor("MANA", bars.altManaColorR or 0, bars.altManaColorG or 0, bars.altManaColorB or .8)
    RenderMeter(frame, nil, { width = min(1200, width), height = Clamp(bars.altManaHeight, 4, 2, 30),
        fraction = AnimatedMeterFraction(preview, .68, .36, .15, .96), texture = ResolveTexture(nil),
        r = r, g = g, b = blue, bgR = 0, bgG = 0, bgB = 0, bgA = .4, outline = PreviewOutline(preview, 1, 1) })
    frame:ClearAllPoints()
    frame:SetPoint("TOP", preview.playerRef, "BOTTOM", Clamp(bars.altManaOffsetX, 0, -1000, 1000), tonumber(bars.altManaOffsetY) or -2)
    HideMeterText(frame)
    frame:Show()
    if not preview.handleMana then preview.handleMana = MakeHandle(preview, HANDLE_DEFS.mana) end
    PlaceHandle(preview.handleMana, frame, 5)
end
local function EnsureBound(preview, key, label, color)
    preview.bounds = preview.bounds or {}
    local frame = preview.bounds[key]
    if frame then return frame end
    local parent = PreviewParent(preview)
    frame = PixelLayoutRegion(CreateFrame("Frame", nil, parent, "BackdropTemplate"))
    PixelLayoutRegion(frame, "SetBackdrop", { bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(color[1], color[2], color[3], 0.90)
    frame:EnableMouse(false)
    frame:SetFrameLevel(((parent and parent.GetFrameLevel and parent:GetFrameLevel()) or 0) + 70)
    frame.label = MakeText(frame, "OVERLAY", "LEFT")
    ApplyFont(frame.label, 9)
    frame.label:SetText(TR(label))
    frame.label:SetTextColor(color[1], color[2], color[3], 0.95)
    frame.label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 1, 1)
    frame._msufPlaced = false
    frame._layerKey = key
    frame:Hide()
    preview.bounds[key] = frame
    return frame
end
local function PlaceBound(preview, key, region, label, color, pad, layerKey)
    local bound = EnsureBound(preview, key, label, color)
    bound._layerKey = layerKey or key
    PlaceAround(bound, region, tonumber(pad) or 1)
end
-- These are deterministic menu samples, never attached to real resource frames.
-- Reuse the menu meter painter and retain objects across configuration refreshes.
-- Context samples follow the live class/spec gates. The Additional resources
-- workspace selects a client-supported example independently of the character.
-- Both paths reuse these painters with the configured bar and text colours.
local SAMPLE = {
    LIVE_EXTRAS = MSUF.Client ~= nil and MSUF.Client.IsRetail == true and MSUF.Client.IsForever ~= true,
    BLUE = { .45, .7, 1 }, WHITE = { 1, 1, 1 },
    FIVE = { 1, .65, .2 }, TICK = { .3, 1, .7 }, COST = { .7, .7, 1 },
    ARCANE = { .66, .42, 1 }, ARCANE_WARN = { 1, .78, .25 },
    SOUL = { .92, .4, .86 },
    NO_MARKS = {}, METER_OPTS = {},
}
function SAMPLE.Color(bars, colorKey, fallback)
    local color = bars[colorKey]
    return type(color) == "table" and color or fallback
end
function SAMPLE.MeterOpts(width, height, fraction, texture, color)
    local opts = SAMPLE.METER_OPTS
    opts.width, opts.height, opts.fraction, opts.texture = width, height, fraction, texture
    opts.r, opts.g, opts.b = color[1], color[2], color[3]
    opts.bgR, opts.bgG, opts.bgB, opts.bgA, opts.bgTexture, opts.outline = nil, nil, nil, nil, nil, nil
    return opts
end
-- Explicit workspace examples already passed the client's choice gates.
-- Context samples still match the live class, specialization and activation.
function SAMPLE.Eligible(preview, bars, class, spec)
    if preview._resourceExtraExample then return M.ResourceExtrasPreview.Eligibility(preview) end
    if not SAMPLE.LIVE_EXTRAS then return false, false end
    local pain = class == "WARRIOR" and bars.showIgnorePain == true
    local arcane = spec ~= nil and spec.key == "mage_arcane" and bars.showArcaneWindow == true
    if not (pain or arcane) then return false, false end
    local liveClass = select(2, UnitClass("player"))
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local liveSpec = getSpec and getSpec() or nil
    return pain and liveClass == "WARRIOR" and liveSpec == 3, arcane and liveClass == "MAGE" and liveSpec == 1
end
--- The retained sample meter of a key, anchored under the player stand-in or the power bar by the caller.
function SAMPLE.Frame(preview, samples, key)
    local frame = samples[key] or EnsureMeter(preview, "resourceSample" .. key)
    samples[key] = frame
    frame:ClearAllPoints()
    return frame
end
function SAMPLE.Activate(frame, layer)
    frame._sampleLayer = layer
    frame._sampleActive = true
    frame:Show()
    return frame
end
function SAMPLE.Meter(preview, samples, bars, key, row, colorKey, fallback, fraction, text, textColor)
    local frame = SAMPLE.Frame(preview, samples, key)
    frame:SetPoint("TOP", preview.playerRef, "BOTTOM", tonumber(bars.resourceExtraOffsetX) or 0,
        (tonumber(bars.resourceExtraOffsetY) or -18) - row * ((tonumber(bars.resourceExtraHeight) or 8) + 6))
    RenderMeter(frame, nil, SAMPLE.MeterOpts(tonumber(bars.resourceExtraWidth) or 220,
        tonumber(bars.resourceExtraHeight) or 8, fraction, ResolveTexture(bars.classPowerTexture),
        SAMPLE.Color(bars, colorKey, fallback)))
    frame.center:SetFont(Core.GetFontPath() or STANDARD_TEXT_FONT,
        tonumber(bars.classPowerFontSize) or 14, "OUTLINE")
    frame.center:SetTextColor(textColor[1], textColor[2], textColor[3], 1)
    frame.center:SetText(text)
    frame.center:SetPoint("CENTER", frame, "CENTER")
    frame.center:SetAlpha(1)
    frame.center:Show()
    return SAMPLE.Activate(frame, preview._resourceExtraExample and "extras" or "class")
end
function SAMPLE.Strip(preview, samples, bars, powerFrame, key, height, anchor, offset, colorKey, fallback, fraction)
    local frame = SAMPLE.Frame(preview, samples, key)
    frame:SetPoint(anchor, powerFrame, anchor == "BOTTOMLEFT" and "TOPLEFT" or "BOTTOMLEFT", 0, offset)
    RenderMeter(frame, nil, SAMPLE.MeterOpts(powerFrame:GetWidth(), height, fraction, WHITE8,
        SAMPLE.Color(bars, colorKey, fallback)))
    return SAMPLE.Activate(frame, "power")
end
-- The live power bar the marks sit on: the Mana display source, else the
-- player's real power type (MSUF_CP_ResourceMarks Target), and its maximum for
-- ABSOLUTE marks. Secret or missing values leave the maximum unknown.
function SAMPLE.PowerTarget(mana)
    local power, token
    if mana then
        power, token = 0, "MANA"
    elseif UnitPowerType then
        power, token = UnitPowerType("player")
    end
    if type(power) ~= "number" or (issecretvalue and issecretvalue(power)) then return token, nil end
    local maximum = UnitPowerMax and UnitPowerMax("player", power) or nil
    if type(maximum) ~= "number" or (issecretvalue and issecretvalue(maximum)) then maximum = nil end
    return token, maximum
end
function SAMPLE.PaintArcane(preview, samples, bars)
    -- Reuse the duration bar sample painter for both phases of the live window.
    local warn = tonumber(bars.arcaneWindowWarnSeconds)
    if not warn or warn ~= warn then warn = 3 end
    warn = max(0, min(10, warn))
    if bars.arcaneWindowWarnLastGCD == true then warn = 1.5 end
    local seconds, soul = M.ResourceExtrasPreview.ArcaneSample(preview, warn)
    local mode, from = bars.arcaneWindowText, tonumber(bars.arcaneWindowTextFrom) or 0
    local casts = math.ceil(seconds / 1.5)
    local secondsFormat = seconds >= 10 and "%d" or "%.1f"
    local text = mode == "gcds" and string.format("x%d", casts)
        or mode == "both" and string.format(secondsFormat .. " (x%d)", seconds, casts) or string.format(secondsFormat, seconds)
    if from > 0 and seconds >= from then text = "" end
    local fraction = preview._resourceExtraExample and seconds / (soul and 10 or 15) or .25
    local colorKey = soul and "arcaneWindowSoulColor" or "arcaneWindowColor"
    SAMPLE.Meter(preview, samples, bars, "ARCANE", 0, colorKey, soul and SAMPLE.SOUL or SAMPLE.ARCANE, fraction, text,
        (warn > 0 and seconds < warn) and SAMPLE.Color(bars, "arcaneWindowWarnColor", SAMPLE.ARCANE_WARN) or SAMPLE.WHITE)
end
function SAMPLE.PaintPain(preview, samples, bars)
    local frame = SAMPLE.Meter(preview, samples, bars, "PAIN", 0, "ignorePainColor", SAMPLE.BLUE, .65, "7.8 s", SAMPLE.WHITE)
    local marker = frame.marker or MakeTexture(frame, "OVERLAY")
    frame.marker = marker
    marker:SetColorTexture(1, 1, 1, 1)
    marker:SetWidth(2)
    marker:ClearAllPoints()
    marker:SetPoint("TOP", frame.fill, "TOPRIGHT")
    marker:SetPoint("BOTTOM", frame.fill, "BOTTOMRIGHT")
    marker:SetShown(bars.ignorePainTimeMarker ~= false)
end
--- The upcoming-cost strip: a share of the power bar's end, masked to the bar's shape.
function SAMPLE.PaintCost(preview, samples, bars, powerFrame)
    local frame = SAMPLE.Strip(preview, samples, bars, powerFrame, "COST", powerFrame:GetHeight(), "TOPLEFT", 0,
        "manaCostColor", SAMPLE.COST, .18)
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", powerFrame.fill, "TOPRIGHT")
    frame:SetWidth(max(1, powerFrame:GetWidth() * .18))
    frame.fill:SetWidth(frame:GetWidth())
    if powerFrame._msufCPPreviewShapeAxis == "VERTICAL" then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", powerFrame.fill, "TOPLEFT", 0, -powerFrame:GetHeight() * .18)
        frame:SetSize(powerFrame:GetWidth(), max(1, powerFrame:GetHeight() * .18))
        frame.fill:SetSize(frame:GetWidth(), frame:GetHeight())
    end
    frame.bg:Hide()
    if powerFrame._msufCPPreviewHasShape then
        local mask = frame.costMask
        if not mask then
            mask = PixelLayoutRegion(powerFrame:CreateMaskTexture(nil, "OVERLAY"))
            frame.costMask = mask
        end
        if not frame.costMasked then
            frame.fill:AddMaskTexture(mask)
            frame.costMasked = true
        end
        mask:SetTexture(powerFrame.fill:GetTexture(), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:ClearAllPoints()
        mask:SetAllPoints(powerFrame)
        mask:Show()
    elseif frame.costMasked then
        frame.fill:RemoveMaskTexture(frame.costMask)
        frame.costMasked = false
        frame.costMask:Hide()
    end
end
function SAMPLE.PaintManaStrips(preview, samples, bars, powerFrame)
    local regenTimers = MSUF.CPBuilders and MSUF.CPBuilders.ManaRegenTimersSupported
    regenTimers = regenTimers and regenTimers() or false
    if regenTimers and bars.manaRegenPause == true then
        SAMPLE.Strip(preview, samples, bars, powerFrame, "FIVE", 3, "BOTTOMLEFT", 1, "manaRegenPauseColor", SAMPLE.FIVE, .6)
    end
    if regenTimers and bars.manaGainPulse == true then
        SAMPLE.Strip(preview, samples, bars, powerFrame, "TICK", 2, "TOPLEFT", -1, "manaGainPulseColor", SAMPLE.TICK, .5)
    end
    if bars.manaUpcomingCost == true then SAMPLE.PaintCost(preview, samples, bars, powerFrame) end
end
--- The configured resource marks: one retained texture per mark on its host bar, and the
--- threshold rules the tint pass reads.
function SAMPLE.PaintMarks(preview, bars, spec, classFrame, powerFrame, mana)
    preview.resourceSampleMarks = preview.resourceSampleMarks or {}
    for _, texture in ipairs(preview.resourceSampleMarks) do texture:Hide() end
    local thresholds = preview.resourceSampleThresholds or {}
    preview.resourceSampleThresholds = thresholds
    local thresholdCount = 0
    local count = 0
    local marks = bars.resourceMarks or SAMPLE.NO_MARKS
    -- The power bar's type and maximum are read only once a mark sits on it.
    local powerToken, powerMaximum, powerResolved
    for i = 1, min(#marks, 256) do
        local rule = marks[i]
        local host, token, maximum
        if rule.target == "CLASS" and classFrame and spec and spec.mode ~= "aura_segmented" then
            host, token, maximum = classFrame, spec.token, tonumber(spec.segments)
        elseif rule.target ~= "CLASS" and rule.target ~= "ALTMANA" and powerFrame then
            if not powerResolved then
                powerToken, powerMaximum = SAMPLE.PowerTarget(mana)
                powerResolved = true
            end
            host, token, maximum = powerFrame, powerToken, powerMaximum
        end
        local value = tonumber(rule.value)
        local fraction = value and (rule.mode == "ABSOLUTE" and maximum and maximum > 0 and value / maximum
            or rule.mode ~= "ABSOLUTE" and value / 100)
        if host and rule.enabled ~= false and (not rule.resource or rule.resource == "ALL" or rule.resource == token)
            and fraction and fraction >= 0 and fraction <= 1 then
            count = count + 1
            -- Live marks draw on OVERLAY sublevel 7, above the fill and its edge.
            local texture = preview.resourceSampleMarks[count] or MakeTexture(host, "OVERLAY", 7)
            preview.resourceSampleMarks[count] = texture
            texture:SetParent(host)
            texture:ClearAllPoints()
            local color = rule.color or SAMPLE.WHITE
            texture:SetColorTexture(color[1], color[2], color[3], 1)
            texture:SetWidth(max(1, min(20, tonumber(rule.width) or 2)))
            texture:SetPoint("TOP", host, "TOPLEFT", host:GetWidth() * fraction, 0)
            texture:SetPoint("BOTTOM", host, "BOTTOMLEFT", host:GetWidth() * fraction, 0)
            texture:SetShown(rule.mark ~= false)
            if rule.threshold == true then
                thresholdCount = thresholdCount + 1
                local entry = thresholds[thresholdCount]
                if not entry then
                    entry = {}
                    thresholds[thresholdCount] = entry
                end
                entry.host, entry.spec, entry.fraction = host, host == classFrame and spec or nil, fraction
                entry.direction, entry.color, entry.maximum = rule.direction, color, maximum
            end
        end
    end
    preview.resourceSampleThresholdCount = thresholdCount
end
--- Remembers the power bar's own fill colour: the threshold tint is undone from it on every paint.
function SAMPLE.CapturePowerBase(preview, powerFrame)
    local base = preview.resourceSamplePowerBaseState
    preview.resourceSamplePowerBase = nil
    if not powerFrame then return end
    if not base then
        base = {}
        preview.resourceSamplePowerBaseState = base
    end
    local r, g, b, a = powerFrame.fill:GetVertexColor()
    base.host, base.r, base.g, base.b, base.a = powerFrame, r or 1, g or 1, b or 1, a or 1
    preview.resourceSamplePowerBase = base
end
local function RenderExtraSamples(preview, bars, player, spec, classFrame, powerFrame)
    local samples = preview.resourceSamples or {}
    preview.resourceSamples = samples
    for _, frame in pairs(samples) do
        frame:Hide()
        frame._sampleActive = false
    end
    SAMPLE.CapturePowerBase(preview, powerFrame)
    local pain, arcane = SAMPLE.Eligible(preview, bars, PreviewClassToken(spec), spec)
    if pain then SAMPLE.PaintPain(preview, samples, bars) end
    if arcane then SAMPLE.PaintArcane(preview, samples, bars) end
    -- The existing detached mock uses Energy unless its configured source is Mana.
    -- Alternate-mana has no mock host here and is therefore not misrepresented.
    local mana = powerFrame and PlayerManaSourceActive(player) and not PowerShowsEbonMight(bars, player, spec)
    if mana then SAMPLE.PaintManaStrips(preview, samples, bars, powerFrame) end
    SAMPLE.PaintMarks(preview, bars, spec, classFrame, powerFrame, mana)
    Preview.UpdateSampleThresholds(preview)
end
function Preview.UpdateSampleThresholds(preview)
    local base = preview.resourceSamplePowerBase
    if base then base.host.fill:SetVertexColor(base.r, base.g, base.b, base.a) end
    local thresholds = preview.resourceSampleThresholds
    for i = 1, tonumber(preview.resourceSampleThresholdCount) or 0 do
        local rule = thresholds[i]
        local host, spec = rule.host, rule.spec
        local value
        if spec then
            value = AnimationEnabled(preview) and CPPreview.AnimatedValue(spec, PreviewElapsed(preview)) or spec.value
            value = (tonumber(value) or 0) / (rule.maximum or 1)
        else
            value = host._msufCPPreviewShapeAxis == "VERTICAL" and host.fill:GetHeight() / max(1, host:GetHeight())
                or host.fill:GetWidth() / max(1, host:GetWidth())
        end
        if (rule.direction == "BELOW" and value < rule.fraction) or (rule.direction ~= "BELOW" and value >= rule.fraction) then
            local color = rule.color
            if spec then
                -- The class resource is the engine scene: tint its bars like the live threshold step does and
                -- record the tint in the painters' colour stamp, so the next paint writes the base colour back.
                local CP = preview.cpScene.CP
                for s = 1, CP.currentMax do
                    local bar = CP.bars[s]
                    local _, _, _, alpha = bar:GetStatusBarColor()
                    alpha = alpha or 1
                    bar:SetStatusBarColor(color[1], color[2], color[3], alpha)
                    bar._msufCPR, bar._msufCPG, bar._msufCPB, bar._msufCPA = color[1], color[2], color[3], alpha
                end
            else
                host.fill:SetVertexColor(color[1], color[2], color[3], base and base.a or 1)
            end
        end
    end
end

local function RefreshBounds(preview, classFrame, ebonFrame, powerFrame, hpFrame)
    PlaceBound(preview, "class", classFrame, "Class", LAYER_COLORS.class, 1)
    PlaceBound(preview, "ebon", ebonFrame, "Ebon Might", LAYER_COLORS.ebon, 1, "class")
    PlaceBound(preview, "power", powerFrame, "Power", LAYER_COLORS.power, 1)
    PlaceBound(preview, "hp", hpFrame, "HP", LAYER_COLORS.hp, 1)
    PlaceBound(preview, "mana", preview.altMana, "Alternative Mana", LAYER_COLORS.mana, 1)
    local samples = preview.resourceSamples or SAMPLE.NO_MARKS
    local pain, arcane = samples.PAIN, samples.ARCANE
    PlaceBound(preview, "pain", pain and pain._sampleActive and pain, "Ignore Pain", SAMPLE.BLUE, 1,
        pain and pain._sampleLayer)
    PlaceBound(preview, "arcane", arcane and arcane._sampleActive and arcane, "Arcane Window", SAMPLE.ARCANE, 1,
        arcane and arcane._sampleLayer)
end
local function AddPreviewRegionBounds(preview, region, bounds)
    if not (preview and preview.stage and region and region.IsShown and region:IsShown()) then return end
    local stageX, stageY = preview.stage:GetCenter()
    local regionX, regionY = region:GetCenter()
    if not (stageX and stageY and regionX and regionY) then return end
    local halfW = max(0, (tonumber(region:GetWidth()) or 0) * 0.5)
    local halfH = max(0, (tonumber(region:GetHeight()) or 0) * 0.5)
    -- GetCenter values for regions in the same scaled hierarchy are already in
    -- their shared local coordinate space (see Blizzard_SharedXML/RegionUtil).
    local centerX = regionX - stageX
    local centerY = regionY - stageY
    bounds.minX = min(bounds.minX, centerX - halfW)
    bounds.maxX = max(bounds.maxX, centerX + halfW)
    bounds.minY = min(bounds.minY, centerY - halfH)
    bounds.maxY = max(bounds.maxY, centerY + halfH)
    bounds.found = true
end

-- Text handles fit with the layer of the element they label.
local TEXT_HANDLE_PARENT = { classText = "class", powerText = "power", hpText = "hp" }
local function ResolvePreviewFit(preview, classFrame, ebonFrame, powerFrame, hpFrame)
    local bounds = { minX = math.huge, maxX = -math.huge, minY = math.huge, maxY = -math.huge }
    -- layerAvailable still describes the preceding refresh at this point.  Fit
    -- the frames produced by this refresh and apply availability afterwards.
    if Wanted(preview, "class") then
        AddPreviewRegionBounds(preview, classFrame, bounds)
        AddPreviewRegionBounds(preview, ebonFrame, bounds)
    end
    if Wanted(preview, "power") then AddPreviewRegionBounds(preview, powerFrame, bounds) end
    if Wanted(preview, "hp") then AddPreviewRegionBounds(preview, hpFrame, bounds) end
    if Wanted(preview, "mana") then AddPreviewRegionBounds(preview, preview.altMana, bounds) end
    for _, frame in pairs(preview.resourceSamples or {}) do
        if Wanted(preview, frame._sampleLayer) then AddPreviewRegionBounds(preview, frame, bounds) end
    end
    for i = 1, #(preview.handles or {}) do
        local handle = preview.handles[i]
        local key = handle._layerKey or handle._key
        local parentKey = TEXT_HANDLE_PARENT[key]
        if parentKey and handle._msufPlaced == true and Wanted(preview, parentKey) and Wanted(preview, key) then
            AddPreviewRegionBounds(preview, handle, bounds)
        end
    end
    if not bounds.found then return 1, 0, 0 end

    local pad = 20
    local contentW = max(1, (bounds.maxX - bounds.minX) + pad * 2)
    local contentH = max(1, (bounds.maxY - bounds.minY) + pad * 2)
    local canvasW = max(1, tonumber(preview.canvasW) or tonumber(preview.canvas:GetWidth()) or 1)
    local canvasH = max(1, tonumber(preview.canvasH) or tonumber(preview.canvas:GetHeight()) or 1)
    local autoScale = min(1, max(1, canvasW - 24) / contentW, max(1, canvasH - 24) / contentH)
    local centerX = (bounds.minX + bounds.maxX) * 0.5
    local centerY = (bounds.minY + bounds.maxY) * 0.5
    return autoScale, -centerX, -centerY
end

local function ApplyPreviewZoom(preview, classFrame, ebonFrame, powerFrame, hpFrame)
    if not (preview and preview.stage) then return end
    local scale, centerX, centerY = ResolvePreviewFit(preview, classFrame, ebonFrame, powerFrame, hpFrame)
    preview._mockAutoScale = scale
    preview._mockScale = scale
    preview._mockEffectiveScale = scale
    preview._mockBaseOffsetX = centerX * scale
    preview._mockBaseOffsetY = centerY * scale
    if preview.stage.SetScale then preview.stage:SetScale(scale) end
    preview.stage:ClearAllPoints()
    preview.stage:SetPoint("CENTER", preview.canvas, "CENTER",
        preview._mockBaseOffsetX, preview._mockBaseOffsetY)
end
local function ApplyPreviewBorder(preview)
    if not (preview and preview.canvas and preview.canvas.SetBackdropBorderColor) then return end
    local c = preview._canvasBorderColor or { 0.10, 0.13, 0.18, 0.65 }
    preview.canvas:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
end
local function ApplyLayerVisibility(preview)
    if not preview then return end
    local classOn = LayerOn(preview, "class")
    local classTextOn = classOn and LayerOn(preview, "classText")
    local powerOn = LayerOn(preview, "power")
    local powerTextOn = powerOn and LayerOn(preview, "powerText")
    local hpOn = LayerOn(preview, "hp")
    local hpTextOn = hpOn and LayerOn(preview, "hpText")
    local boundsOn = LayerOn(preview, "bounds")
    for _, frame in pairs(preview.resourceSamples or {}) do
        SetShownSafe(frame, frame._sampleActive == true and LayerOn(preview, frame._sampleLayer))
    end
    SetShownSafe(preview.altMana, LayerOn(preview, "mana") and Section("bars").showAltMana == true)
    local ebonTimer = preview.ebonTimer
    local ebonActive = ebonTimer and ebonTimer._msufCPPreviewActive == true
    SetShownSafe(ebonTimer, classOn and ebonActive)
    if ebonTimer then
        SetShownSafe(ebonTimer.left, false)
        SetShownSafe(ebonTimer.center, classTextOn and ebonActive
            and ebonTimer._msufCPPreviewTimerAnim
            and ebonTimer._msufCPPreviewTimerAnim.showText == true)
        SetShownSafe(ebonTimer.right, false)
    end
    SetShownSafe(preview.detachedPower, powerOn)
    if not powerOn then HideBarOutline(preview.detachedPower) end
    if not powerTextOn then HideMeterText(preview.detachedPower) end
    SetShownSafe(preview.playerHP, hpOn)
    if not hpOn then HideBarOutline(preview.playerHP) end
    if not hpTextOn then HideMeterText(preview.playerHP) end
    if preview.bounds then
        for _, bound in pairs(preview.bounds) do
            SetShownSafe(bound, boundsOn and bound._msufPlaced == true and LayerOn(preview, bound._layerKey))
        end
    end
    for i = 1, #(preview.handles or {}) do
        local handle = preview.handles[i]
        SetShownSafe(handle, handle._msufPlaced == true and LayerOn(preview, handle._layerKey or handle._key))
    end
    if preview.selectedHandle and not preview.selectedHandle:IsShown() then
        preview.selectedHandle = nil
    end
    ApplyPreviewBorder(preview)
end
local CP_LAYER_BUTTON_OPTS = Helpers.LayerChipButtonOpts(TR, T.colors, Helpers.PreviewChromePalette(T), {
    Tr = TR,
    IsAvailable = LayerAvailable,
    IsOn = LayerOn,
    disabledLine = "This element is disabled in the current settings.",
    OnClick = function(self, preview)
        if not LayerAvailable(preview, self.key) then return end
        preview.layerVisibility[self.key] = preview.layerVisibility[self.key] == false
        if self.key == "guides" then SetPreviewGuidesEnabled(preview.layerVisibility[self.key] ~= false) end
        if preview and preview.Refresh then
            RequestClassPowerPreviewRefresh(preview, "CLASSPOWER_PREVIEW_LAYER")
        else
            ApplyLayerVisibility(preview)
            RefreshHandleVisuals(preview)
            RefreshLayerButtons(preview)
        end
    end,
})
local function CreateLayerSidebar(box, sideW)
    local sidebar = T.Panel(box, nil, { 0.025, 0.028, 0.04, 0.82 }, T.colors.borderSoft)
    Helpers.ApplyPreviewChrome(sidebar, "sidebar", T)
    sidebar:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 12)
    sidebar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    if sidebar.SetClipsChildren then sidebar:SetClipsChildren(true) end
    box.sidebar = sidebar
    local chrome = Helpers.PreviewChromePalette(T)
    local hdr = T.Font(sidebar, "GameFontDisableSmall", "Preview Layers", chrome.layerHeader or T.colors.muted)
    hdr:SetPoint("LEFT", sidebar, "LEFT", 10, 0)
    box._msuf2LayerRailHeader = hdr
    box.LayoutLayerRail = function(self, width)
        return Helpers.LayoutLayerRail(self, self.sidebar, self.layerButtons, width)
    end
    box.layerVisibility = {}
    box.layerButtons = {}
    for i = 1, #CP_PREVIEW_LAYERS do
        local def = CP_PREVIEW_LAYERS[i]
        box.layerVisibility[def.key] = def.key ~= "guides" or PreviewGuidesEnabled()
        local btn = Helpers.CreateLayerButton(sidebar, box, def, i, sideW, CP_LAYER_BUTTON_OPTS)
        local isGuides = def.key == "guides"
        RegisterPreviewControl(box._catalogCtx, btn, "layer." .. tostring(def.key),
            tostring(def.label or def.key) .. " preview layer", isGuides and "toggle" or "button", isGuides and "setting" or "ephemeral",
            isGuides and { settingKey = "general.classPowerPreviewGuidesEnabled", help = def.tooltip } or { help = def.tooltip })
        box.layerButtons[#box.layerButtons + 1] = btn
    end
end
-- Preview animation: the toggle button and the OnUpdate driver (the per-tick repaint is above).
local Anim = { IDLE_FILL = { 0.025, 0.030, 0.045, 0.88 }, IDLE_BORDER = { 0.12, 0.16, 0.24, 0.92 } }
function Anim.RefreshButton(preview)
    local btn = preview and preview.animateButton
    if not btn then return end
    Helpers.PaintAnimateButton(btn, AnimationEnabled(preview), TR, Anim.IDLE_FILL, Anim.IDLE_BORDER)
end
function Anim.Stop(preview)
    local driver = preview and preview.animationDriver
    if not driver then return end
    driver:SetScript("OnUpdate", nil)
    if driver.SetOnUpdateMode then driver:SetOnUpdateMode(ONUPDATE_MODE_DISABLED) end
    driver:Hide()
end
-- Combat ends the animation: the choice is saved as off and the driver stops.
function Anim.Cancel(preview)
    preview._animationEnabled = false
    Section("general").classPowerPreviewAnimate = false
    Anim.Stop(preview)
    Anim.RefreshButton(preview)
end
function Anim.OnUpdate(driver, elapsed)
    local preview = driver and driver._preview
    if not (preview and preview._animationEnabled == true and preview.IsShown and preview:IsShown()) then
        Anim.Stop(preview)
        return
    end
    if PreviewAnimationInCombat() then
        Anim.Cancel(preview)
        return
    end
    elapsed = tonumber(elapsed) or 0
    preview._animationElapsed = (tonumber(preview._animationElapsed) or 0) + elapsed
    preview._animationAccum = (tonumber(preview._animationAccum) or 0) + elapsed
    if preview._animationAccum < CP_PREVIEW_ANIMATION_INTERVAL then return end
    preview._animationAccum = 0
    if preview.Refresh then
        local light = preview.RefreshAnimation and preview:RefreshAnimation("CLASSPOWER_PREVIEW_ANIMATE")
        if not light then preview:Refresh("CLASSPOWER_PREVIEW_ANIMATE") end
    end
end
function Anim.Start(preview)
    if not (preview and preview._animationEnabled == true) then return end
    if PreviewAnimationInCombat() then return end
    local driver = preview.animationDriver
    if not driver then
        driver = PixelLayoutRegion(CreateFrame("Frame", nil, preview.canvas or preview))
        preview.animationDriver = driver
    end
    driver._preview = preview
    if driver.SetOnUpdateMode then driver:SetOnUpdateMode(ONUPDATE_MODE_RUN_WHEN_VISIBLE) end
    driver:SetScript("OnUpdate", Anim.OnUpdate)
    driver:Show()
end
function Anim.SetEnabled(preview, enabled)
    if not preview then return end
    enabled = enabled == true
    if enabled and PreviewAnimationInCombat() then
        Anim.Cancel(preview)
        return false
    end
    if enabled and preview._animationEnabled ~= true then
        preview._animationElapsed = 0
        preview._animationAccum = 0
    end
    preview._animationEnabled = enabled
    Section("general").classPowerPreviewAnimate = enabled
    Anim.RefreshButton(preview)
    if enabled then
        Anim.Start(preview)
    else
        Anim.Stop(preview)
    end
    if preview.Refresh then preview:Refresh("CLASSPOWER_PREVIEW_ANIMATE_TOGGLE") end
    return AnimationEnabled(preview) == enabled
end
function Anim.CreateButton(preview)
    local btn = PixelLayoutRegion(CreateFrame("Button", nil, preview.canvas, "BackdropTemplate"))
    btn:SetSize(72, 22)
    PixelLayoutRegion(btn, "SetBackdrop", { bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    if preview.zoomBar then
        btn:SetPoint("RIGHT", preview.zoomBar, "LEFT", -6, 0)
    else
        btn:SetPoint("TOPRIGHT", preview.canvas, "TOPRIGHT", -174, -6)
    end
    btn.fs = PixelLayoutRegion(btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    btn.fs:SetPoint("CENTER")
    if T and T.StyleFontString then T.StyleFontString(btn.fs, T.colors and T.colors.text or { 1, 1, 1, 1 }, 0) end
    Helpers.StylePreviewPillButton(btn, T, { fontField = "fs" })
    btn:SetScript("OnClick", function(self)
        Anim.SetEnabled(self._preview, not AnimationEnabled(self._preview))
    end)
    btn._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = function() return AnimationEnabled(preview) end,
        set = function(enabled) return Anim.SetEnabled(preview, enabled == true) end,
    }
    M.AddTooltip(btn, "Animate Preview", "Animates Class Resource, Player Power, and HP fill values in this preview only.", { hook = true })
    btn._preview = preview
    preview.animateButton = btn
    RegisterPreviewControl(preview._catalogCtx, btn, "animation.toggle", "Animate Preview", "button", "ephemeral", {
        help = "Starts or stops preview-only Class Resource, Player Power, and HP fill animation.",
    })
    Anim.RefreshButton(preview)
    return btn
end
local function EnsureClassPowerLayersButton(box)
    if box._msuf2LayersButton then return box._msuf2LayersButton end
    local btn = T.Button(box, "", 132, 20)
    btn:SetText(TR("Preview Layers") .. " v", true)
    if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
    btn:SetScript("OnClick", function()
        if box.sidebar then box.sidebar:SetShown(not box.sidebar:IsShown()) end
    end)
    M.AddTooltip(btn, "Preview Layers", "Toggle the preview layer list.", { hook = true })
    RegisterPreviewControl(box._catalogCtx, btn, "layer.popover", "Class Resources Preview Layers", "button", "ephemeral")
    box._msuf2LayersButton = btn
    return btn
end
local function ApplyClassPowerCompactPresentation(box, compact, sideW)
    if not box then return end
    compact = compact == true
    box._msuf2CompactPreview = compact
    if box._msuf2PinnedFloating == true then compact = false end
    local boxWidth = max(1, tonumber(box.GetWidth and box:GetWidth()) or 1)
    local canvas, sidebar = box.canvas, box.sidebar
    if compact then
        if box.title then box.title:Hide() end
        if box.hint then box.hint:Hide() end
        Helpers.SetCanvasToolsShown(box, false, box.animateButton)
        if canvas then
            box.canvasW = max(1, (box.GetWidth and box:GetWidth() or 1) - 16)
            box.canvasH = max(1, (box.GetHeight and box:GetHeight() or 1) - 16)
            canvas:ClearAllPoints()
            canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
            canvas:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)
            if box.stage then box.stage:SetSize(box.canvasW, box.canvasH) end
        end
        local layersBtn = EnsureClassPowerLayersButton(box)
        if sidebar and canvas then
            sidebar:ClearAllPoints()
            if box._msuf2CompactHeader then sidebar:SetPoint("TOPRIGHT", layersBtn, "BOTTOMRIGHT", 0, -6)
            else sidebar:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -28) end
            box._msuf2LayerPopoverWidth = min(268, max(160, boxWidth - 24))
            if box._msuf2LayerRailHeader then box._msuf2LayerRailHeader:Hide() end
            box:LayoutLayerRail(box._msuf2LayerPopoverWidth)
            if sidebar.SetFrameLevel and canvas.GetFrameLevel then sidebar:SetFrameLevel((canvas:GetFrameLevel() or 1) + 90) end
            sidebar:Hide()
        end
        layersBtn:Show()
        Helpers.LayoutCompactLayersButton(box, true, TR)
        return
    end
    if box.title then box.title:Show() end
    if box.hint then box.hint:Show() end
    Helpers.SetCanvasToolsShown(box, true, box.animateButton)
    Helpers.LayoutCompactLayersButton(box, false, TR)
    box._msuf2LayerPopoverWidth = nil
    if box._msuf2LayerRailHeader then box._msuf2LayerRailHeader:Show() end
    if canvas then
        canvas:ClearAllPoints()
        canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
        Helpers.ApplyDockedPreviewLayout(box, sidebar, canvas, 12, true)
        canvas:ClearAllPoints()
        canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
        canvas:SetPoint("BOTTOMRIGHT", sidebar, "TOPRIGHT", 0, 6)
        box.canvasW = max(1, boxWidth - 24)
        box.canvasH = max(1, (tonumber(box.GetHeight and box:GetHeight()) or 330) - 48 - sidebar:GetHeight())
        box._msuf2ExpandedCanvasW, box._msuf2ExpandedCanvasH = box.canvasW, box.canvasH
        box.playerW = min(275, max(190, box.canvasW - 160))
        if box.stage then box.stage:SetSize(box.canvasW, box.canvasH) end
    end
    if box._msuf2LayersButton then box._msuf2LayersButton:Hide() end
end

-- The box shell, its refresh and lifecycle hooks; the heights and top offset of the fixed section.
local Box = { FIXED_HEIGHT = 180, COMPACT_HEIGHT = 132, EXPANDED_HEIGHT = 330, Y = -40 }
--- The box shell: panel, title and hint, canvas with stage, animate button, layer rail, player stand-in
--- and the six selection handles. Frames are created in this order.
function Box.CreateShell(ctx, parent, innerW, sideW)
    local box = T.Panel(parent, nil, { 0.018, 0.022, 0.044, 0.88 }, T.colors.borderSoft)
    box._msuf2PreviewSurfaceFamily = "classpower"
    local chrome = Helpers.ApplyPreviewChrome(box, "outer", T)
        or { title = T.colors.title or T.colors.text, canvasBorder = T.colors.borderSoft }
    box._catalogCtx = ctx
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, Box.Y)
    box:SetSize(innerW, Box.COMPACT_HEIGHT)
    box.canvasW, box.canvasH = max(1, innerW - sideW - 32), 288
    box._msuf2ExpandedCanvasW, box._msuf2ExpandedCanvasH = box.canvasW, box.canvasH
    box.playerW, box.playerH = min(275, max(190, box.canvasW - 160)), 38
    box.handles = {}
    local title = T.Font(box, "GameFontNormal", "Class Resources Preview", chrome.title or T.colors.accent)
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    box.title = title
    local hint = T.Font(box, "GameFontDisableSmall", "Click to open settings. Move resources in Edit Mode.", T.colors.muted)
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    hint:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    box.hint = hint
    box.canvas = T.Panel(box, nil, { 0, 0, 0, 1 }, T.colors.borderSoft)
    box.canvas._msuf2PreviewCanvasUnderlay = box
    Helpers.ApplyPreviewChrome(box.canvas, "canvas", T)
    box.canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
    box.canvas:SetSize(box.canvasW, box.canvasH)
    box._canvasBorderColor = chrome.canvasBorder or T.colors.borderSoft
    if box.canvas.SetClipsChildren then box.canvas:SetClipsChildren(true) end
    box.canvas:EnableMouse(true)
    box.stage = PixelLayoutRegion(CreateFrame("Frame", nil, box.canvas))
    box.stage:SetSize(box.canvasW, box.canvasH)
    box.stage:SetPoint("CENTER", box.canvas, "CENTER", 0, 0)
    box.mock = box.stage
    box._animationEnabled = Section("general").classPowerPreviewAnimate == true
    Anim.CreateButton(box)
    box.canvas:SetScript("OnMouseDown", function()
        box.selectedHandle = nil
        RefreshHandleVisuals(box)
    end)
    RegisterPreviewControl(ctx, box.canvas, "canvas", "Class Resources preview canvas", "canvas", "ephemeral", {
        help = "Shows the resource layout fitted to the preview. Movement is handled in Edit Mode.",
    })
    CreateLayerSidebar(box, sideW)
    box.noResource = T.Font(box.canvas, "GameFontDisableSmall", "Class resource is disabled for this preview resource.", T.colors.muted)
    box.noResource:SetPoint("CENTER", box.canvas, "CENTER", 0, 28)
    box.noResource:Hide()
    CreatePlayerReference(box)
    for i = 1, #HANDLE_DEFS do
        box[HANDLE_DEFS[i].field] = MakeHandle(box, HANDLE_DEFS[i])
    end
    return box
end
--- Paints every element of the preview from the current settings.
function Box.Refresh(box)
    -- Like the unit preview, never render in combat: the refresh waits for
    -- PLAYER_REGEN_ENABLED (the menu closes at combat start; this covers a
    -- surface that is still shown).
    if PreviewAnimationInCombat() then
        if box.RegisterEvent then box:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    --- Keep the persisted Guides choice authoritative across factory reset,
    --- profile switch and Search mutation even when this preview frame
    --- was already constructed under the previous profile table.
    if type(box.layerVisibility) == "table" then
        box.layerVisibility.guides = PreviewGuidesEnabled()
    end
    local bars = Section("bars")
    local player = Section("player")
    local spec = M.GetClassPowerPreviewSpec and M.GetClassPowerPreviewSpec() or nil
    local profileBars = bars
    bars, player, spec = M.ResourceExtrasPreview.Config(box, bars, player, spec)
    PaintPlayerReference(box)
    Preview.RenderAlternativeMana(box, bars)
    local classFrame, classDisabledReason = RenderClassPower(box, bars, player, spec)
    local ebonFrame = RenderSecondaryClassTimer(box)
    if classFrame and classFrame.IsShown and classFrame:IsShown() then
        box.noResource:Hide()
    else
        box.noResource:SetText(classDisabledReason == "settings"
            and "Class resource is disabled in Class Resource settings."
            or "The selected preview resource has no class resource.")
        box.noResource:Show()
    end
    local powerFrame = RenderDetachedPower(box, bars, player, classFrame, spec)
    local hpFrame = RenderPlayerHP(box, bars, player, classFrame, powerFrame, spec, ebonFrame)
    RenderExtraSamples(box, bars, player, spec, classFrame, powerFrame)
    box._msufCPPreviewAnim = {
        bars = bars,
        player = player,
        spec = spec,
        classFrame = classFrame,
        ebonFrame = ebonFrame,
        powerFrame = powerFrame,
        hpFrame = hpFrame,
    }
    if box._selectedWorkspaceKey and box._selectedWorkspaceKey ~= "class" then box.noResource:Hide() end
    SetPreviewSummary(box, classFrame, powerFrame, hpFrame)
    box.layerAvailable = {
        guides = true,
        border = true,
        mana = bars.showAltMana == true,
        class = classFrame ~= nil,
        classText = classFrame ~= nil and (bars.classPowerShowText == true
            or (spec and spec.secondaryTimer and spec.secondaryTimer.nativeDurationText == true)),
        power = powerFrame ~= nil,
        powerText = powerFrame ~= nil and PlayerPowerTextShown(player) and player.detachedPowerBarTextOnBar == true,
        hp = hpFrame ~= nil,
        hpText = hpFrame ~= nil and bars.playerHPBarTextEnabled ~= false,
        bounds = true,
    }
    RefreshBounds(box, classFrame, ebonFrame, powerFrame, hpFrame)
    ApplyPreviewZoom(box, classFrame, ebonFrame, powerFrame, hpFrame)
    ApplyLayerVisibility(box)
    RefreshLayerButtons(box)
    RefreshHandleVisuals(box)
    M.ResourceExtrasPreview.PaintLabels(box, profileBars)
    Anim.RefreshButton(box)
    if box._animationEnabled == true then Anim.Start(box) end
end
function Box.OnEvent(self, event)
    if event ~= "PLAYER_REGEN_ENABLED" then return end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if self:IsShown() and self:_msufCPPreviewHostShown() then self:Refresh() end
end
function Box.HostShown(self)
    if tostring(M.activeKey or "") ~= tostring(self._msufCPPreviewPageKey or "classpower") then return false end
    if M.frame and M.frame.IsShown and not M.frame:IsShown() then return false end
    local wrapper = self._msufCPPreviewWrapper
    if wrapper and wrapper.IsShown and not wrapper:IsShown() then return false end
    local ownerShown = self._msufCPPreviewOwnerShown
    return not ownerShown or ownerShown() == true
end
function Box.Release(self)
    self.selectedHandle = nil
    RefreshHandleVisuals(self)
end
function Box.OnShow(box)
    if box.IsShown and box:IsShown() and box:_msufCPPreviewHostShown() then ActivateClassPowerSurface(box) end
    RequestClassPowerPreviewRefresh(box, "CLASSPOWER_PREVIEW_SHOW")
    if box._animationEnabled == true then Anim.Start(box) end
end
function Box.OnHide(box)
    box._msufCPRefreshSerial = (tonumber(box._msufCPRefreshSerial) or 0) + 1
    box._msufCPRefreshQueued = nil
    box._msufCPRefreshReason = nil
    Anim.Stop(box)
    if box.cpSceneRoot then box.cpSceneRoot:Deactivate() end
    box:ReleasePreviewInteraction()
    if Preview.active == box then Preview.active = nil end
    ActivateClassPowerSurface(nil)
end
function Box.Create(ctx, parent, toolbar, innerW, sideW)
    local box = Box.CreateShell(ctx, parent, innerW, sideW)
    box.Refresh = Box.Refresh
    -- The tick calls this directly (no wrapper): RefreshClassPowerAnimation only reads its first argument, the box.
    box.RefreshAnimation = RefreshClassPowerAnimation
    box:SetScript("OnEvent", Box.OnEvent)
    box._msufCPPreviewHostShown = Box.HostShown
    box.ReleasePreviewInteraction = Box.Release
    box:HookScript("OnShow", Box.OnShow)
    box:HookScript("OnHide", Box.OnHide)
    box._msuf2PreferredRestoreHeight = Box.COMPACT_HEIGHT
    box._msuf2PreferredRestoreYOffset = Box.Y
    box._msuf2CompactHeader = toolbar
    box.ApplyPinnedPreviewPresentation = function(self)
        ApplyClassPowerCompactPresentation(self, self._msuf2CompactPreview == true, sideW)
    end
    box.ApplyCompactPreviewPresentation = function(self, compact)
        ApplyClassPowerCompactPresentation(self, compact, sideW)
    end
    return box
end

--- Build the fixed ClassPower preview section and install its refresh function.
--- The same surface switches between compact and expanded geometry in place.
function Preview.Create(ctx, builder)
    if not (W and W.FixedPreviewSection and T and builder) then return nil end
    local section, toolbar, fixedRecord = W.FixedPreviewSection(ctx, builder, {
        title = TR("Preview") .. " - " .. TR("Class Resources"),
        height = Box.FIXED_HEIGHT,
        gap = 8,
    })
    if not section then return nil end
    -- The preview is fixed page chrome and uses the full page width instead of
    -- the narrower settings-form content width.
    local pageW = ctx.width or builder.width or section._msuf2Width or 720
    local innerW = max(1, pageW - 28)
    local sideW = min(104, max(72, innerW - 252))
    local box = Box.Create(ctx, section, toolbar, innerW, sideW)
    box._msufCPPreviewPageKey = ctx.key
    box._msufCPPreviewWrapper = ctx.wrapper
    box._msufCPPreviewOwnerShown = function()
        return not section.IsShown or section:IsShown()
    end
    M._msuf2ClassPowerInlinePreview = section
    if W.AttachPinnedPreview then
        W.AttachPinnedPreview(section, box, {
            stateKey = "classPowerPreview",
            title = box.title,
            hint = box.hint,
            pageKey = ctx.key,
            wrapper = ctx.wrapper,
        })
    end
    local expander
    if W.AttachFixedPreviewExpander then
        expander = W.AttachFixedPreviewExpander(section, toolbar, box, {
            pageKey = ctx.key,
            wrapper = ctx.wrapper,
            compactHeight = Box.COMPACT_HEIGHT,
            compactTop = Box.Y,
            expandedHeight = Box.EXPANDED_HEIGHT,
            refreshPreview = function(target, reason)
                RequestClassPowerPreviewRefresh(target, reason or "CLASSPOWER_PREVIEW_SIZE")
            end,
            onStateChanged = function(expanded, target)
                if target.ReleasePreviewInteraction then target:ReleasePreviewInteraction() end
                Anim.Stop(target)
                target._animationEnabled = Section("general").classPowerPreviewAnimate == true
                ActivateClassPowerSurface(target)
                if target._animationEnabled == true
                    and target.IsShown and target:IsShown()
                    and target._msufCPPreviewHostShown and target:_msufCPPreviewHostShown()
                then
                    Anim.Start(target)
                end
            end,
        })
    end
    box._msuf2CompactExpandButton = expander and expander.button or nil
    box._msuf2FixedPreviewExpanderRecord = expander
    if expander and expander.button then
        RegisterPreviewControl(ctx, expander.button, "height.toggle",
            "Expand Class Resources Preview", "button", "ephemeral")
    end
    box:ApplyCompactPreviewPresentation(true)
    ActivateClassPowerSurface(box)
    local function RefreshVisibleSurfaces(reason)
        RequestClassPowerPreviewRefresh(box, reason or (expander and expander.expanded
            and "CLASSPOWER_PREVIEW_EXPANDED" or "CLASSPOWER_PREVIEW_COMPACT"))
    end
    function section:Refresh(reason)
        RefreshVisibleSurfaces(reason or "CLASSPOWER_PREVIEW_SECTION_REFRESH")
    end
    ctx.entry.classPowerPreview = box
    M.TrackRefresh(ctx, function() RefreshVisibleSurfaces("CLASSPOWER_PREVIEW_PAGE_REFRESH") end)
    if fixedRecord then
        fixedRecord.onActivate = function()
            if expander and expander.expanded then expander:Relayout("CLASSPOWER_FIXED_HEADER")
            else box:ApplyCompactPreviewPresentation(true) end
            M.ResumeClassPowerPreview("CLASSPOWER_FIXED_HEADER", ctx.key)
            if box._animationEnabled == true then
                Anim.Start(box)
            end
        end
    end
    return section
end
