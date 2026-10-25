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
local function PlayerManaSourceActive(player, class)
    return (player.playerPowerSource == "MANA" or player._msufResourceExtraMana == true)
        and MSUF.CPBuilders.SampleHasMana(class)
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
local HAS_EXTRA_AURAS = MSUF.Client.IsRetail == true and MSUF.Client.IsForever ~= true
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
-- Core-addon providers (all load before the options addon), resolved once. Only the class power
-- constants table is an optional collaborator.
local Core = {
    SetFontChecked = MSUF.Require("MSUF_SetFontChecked", "Menu2/ClassPowerPreview"),
    GetFontPath = MSUF.Require("MSUF_GetFontPath", "Menu2/ClassPowerPreview"),
    GetFontFlags = MSUF.Require("MSUF_GetFontFlags", "Menu2/ClassPowerPreview"),
    ResolveSafeFontPath = MSUF.Require("MSUF_ResolveSafeFontPath", "Menu2/ClassPowerPreview"),
    GetGlobalFontSettings = MSUF.Require("MSUF_GetGlobalFontSettings", "Menu2/ClassPowerPreview"),
    ResolveFontShadowMetrics = MSUF.Require("MSUF_ResolveFontShadowMetrics", "Menu2/ClassPowerPreview"),
    GetEffectiveCooldownFrame = MSUF.Require("MSUF_GetEffectiveCooldownFrame", "Menu2/ClassPowerPreview"),
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
    local prefix = spec and tostring(spec.key or ""):match("^([^_]+)")
    token = prefix and PREVIEW_CLASS_BY_PREFIX[prefix]
    if token then return token end
    return M.GetClassPowerPreviewClassToken()
end

CPPreview.ClassForSpec = PreviewClassToken
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
local function HideBarOutline(frame)
    if not frame then return end
    local health = frame._msufRuntimeHealthState
    local host = health and health.borderHost or frame.MSUFPowerBorderHost
    if host then host:Hide() end
    if health and health.shapeEdge then health.shapeEdge:Hide() end
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
    local scene = CPPreview._widthScene
    if not scene then
        local parent = PixelLayoutRegion(CreateFrame("Frame"))
        parent:Hide()
        scene = { opts = { sample = {} }, root = { parent = parent } }
        scene.frame = MSUF.UF.PreviewSurfaces.ClassPower.Create(scene)
        CPPreview._widthScene = scene
    end
    scene.config.bars = bars
    scene.frame:SetSize(frameW, 40)
    return scene.layout.MeasureWidth(scene.frame, segCount, height, nativeBar and "WHIRLWIND" or nil)
end

--- Distance of the container's left edge from the player frame (ClassPower
--- Layout.Position); the Offset X setting comes on top.
function CPPreview.ContainerInsetX(bars)
    local _, insetX = MSUF.UF.Shared.ClassPowerFrameInsets(bars and bars.classPowerWidthMode or "player")
    return insetX
end


--- True while the Player Power bar renders Ebon Might instead of Mana. Ordinary
--- Power visibility still decides whether that bar exists at all, exactly as it
--- does at runtime.

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
        preview.cpSceneRoot, preview.cpSample, preview.cpTick, preview.cpCooldowns = root, { bars = {} }, {}, {}
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
local function PlayerPowerTextShown(player)
    player = player or {}
    if player.showPowerText ~= nil then return player.showPowerText ~= false end
    return player.showPower ~= false
end
-- Left, center and right text of the detached power bar at a preview fraction.
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

--- Detached power preview follows the same anchoring relationship as runtime:
--- it can attach to ClassPower, but no live player power events are involved.
local function EnsurePlayerRuntime(preview, bars, player, spec)
    local surface = preview.playerRuntime
    if not surface then
        surface = Helpers.NewRuntimeUnitSurface(preview.playerRef, "player", {})
        surface.fit = false
        surface.layerVisible = { health = false, border = false, nameText = false, hpText = false, portrait = false,
            status = false, auras = false, dispelOverlay = false, dispelSymbol = false, texLayer = false }
        surface.layout = function(frame)
            local player = preview._runtimePlayer
            if frame.targetPowerBar and DetachedPowerShown(player) then
                AnchorDetachedPower(preview, frame.targetPowerBar, player, preview.cpScene and preview.cpScene.CP.container,
                    tonumber(player.detachedPowerBarOffsetX) or 0, tonumber(player.detachedPowerBarOffsetY) or -4)
            end
        end
        preview.playerRuntime = surface
        surface.configure = function(config)
            config.width, config.height = preview.playerW, preview.playerH
            local power = config.power
            local bars, player = preview._runtimeBars, preview._runtimePlayer
            local class = preview.cpScene and preview.cpScene.CP.container
            power.detachedWidthExplicit = CPPreview.ResolveDetachedPowerWidth({
                frameWidth = preview.playerW, syncClass = player.detachedPowerBarSyncClassPower ~= false,
                classWidth = class and class:GetWidth(), classFallbackWidth = power.detachedClassWidth,
                widthFrameName = power.detachedWidthFrameName, widthMode = bars.detachedPowerBarWidthMode,
                manualWidth = player.detachedPowerBarWidth, explicitWidth = power.detachedWidthExplicit,
            })
            power.detachedAnchorClass, power.detachedSyncClass = false, false
            if not Wanted(preview, "border") then power.detachedOutline, power.borderThickness = 0, 0 end
        end
    end
    preview._runtimeBars, preview._runtimePlayer = bars, player
    local sample = surface.sample
    sample.class = preview._resourceExtraExample == "pain" and "WARRIOR"
        or preview._resourceExtraExample == "arcane" and "MAGE" or PreviewClassToken(spec)
    sample.hp, sample.power, sample.powerType, sample.powerToken = .74, .72, CPPreview.PrimaryPower(spec, sample.class), nil
    local cp = preview.cpScene and preview.cpScene.CP
    if PlayerManaSourceActive(player, sample.class) or (cp and cp.visible and spec and spec.mode == "continuous"
        and (spec.token == "INSANITY" or spec.token == "MAELSTROM")) then sample.powerType = 0 end
    sample.powerToken = player._msufResourceExtraPower
    if not sample.powerToken then sample.powerToken = Core.CPConst.POWER_TYPE_TOKENS[sample.powerType] end
    for key, token in pairs(Core.CPConst.POWER_TYPE_TOKENS) do if token == sample.powerToken then sample.powerType = key break end end
    surface.layerVisible.power = DetachedPowerShown(player)
    local frame = surface:Refresh(sample)
    if not frame then return nil end
    if not preview.auxiliary then preview.auxiliary = MSUF.CPBuilders.NewAuxiliarySurface(frame) end
    local cp = preview.cpScene and preview.cpScene.CP
    local count = preview.cpSample and preview.cpSample.count or 0
    local maximum = preview.cpSample and preview.cpSample.maximum or 1
    preview.auxiliary:Configure(frame, cp, bars, player, sample.class, spec and spec.specIndex or 1,
        count, maximum, sample.powerType, sample.powerToken, Wanted(preview, "border"))
    return frame
end
local function RenderDetachedPower(preview, bars, player, classFrame, spec)
    local owner = EnsurePlayerRuntime(preview, bars, player, spec)
    local frame = owner and owner.targetPowerBar
    if not frame or not DetachedPowerShown(player) then
        preview._sampleEbonEnabled = false
        if preview.auxiliary then preview.auxiliary:PaintEbon(false) end
        if frame then frame:Hide() end
        preview.handlePower:Hide()
        preview.handlePowerText:Hide()
        return nil
    end
    preview.detachedPower = frame
    frame.fill = frame:GetStatusBarTexture()
    frame.left, frame.center, frame.right = owner.powerTextLeft, owner.powerTextCenter, owner.powerText
    local ebon = bars.showClassPower ~= false and spec and spec.key == "evoker_augmentation_ebon" and bars.showEbonMight ~= false
        and not preview.auxiliary.ownership.playerManaOverride
    local timer = spec and spec.secondaryTimer
    local value = timer and (AnimationEnabled(preview) and CPPreview.AnimatedValue(timer, PreviewElapsed(preview)) or timer.value) or .6
    preview._sampleEbonEnabled = ebon and true or false
    local text = preview.auxiliary:PaintEbon(ebon, value * 20, 20)
    if text then frame.center = text end
    AnchorDetachedPower(preview, frame, player, classFrame, tonumber(player.detachedPowerBarOffsetX) or 0,
        tonumber(player.detachedPowerBarOffsetY) or -4)
    PlaceHandle(preview.handlePower, frame, 5)
    PlaceTextHandle(preview.handlePowerText, PreviewParent(preview), { frame.left, frame.center, frame.right })
    return frame
end
local function RenderPlayerHP(preview, bars, player, classFrame, powerFrame, spec)
    if not preview.auxiliary then return nil end
    local frame, state = preview.auxiliary:PaintHP(AnimatedMeterFraction(preview, .74, .34, .18, 1))
    preview.playerHP = frame
    if not frame then preview.handleHP:Hide() preview.handleHPText:Hide() return nil end
    frame.left, frame.center, frame.right = state.left, state.center, state.right
    frame.fill = state.bar:GetStatusBarTexture()
    frame._msufRuntimeHealthState = state
    PlaceHandle(preview.handleHP, frame, 5)
    PlaceTextHandle(preview.handleHPText, PreviewParent(preview), { state.left, state.center, state.right })
    return frame
end

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
local ApplyLayerVisibility
local function RefreshClassPowerAnimation(preview)
    local state = preview._msufCPPreviewAnim
    if not state then return false end
    if state.classFrame then UpdateClassPowerAnimation(preview) end
    local surface, auxiliary = preview.playerRuntime, preview.auxiliary
    if surface then
        surface.sample.power = AnimatedMeterFraction(preview, .72, .46, .08, .96)
        surface.sample.hp = AnimatedMeterFraction(preview, .74, .34, .18, 1)
        surface.scene:SetSample(surface.sample, true)
        surface.scene:RefreshData(false)
        surface.scene:Frame().hpBar:Hide()
        surface.scene:Frame().healthBackgroundBar:Hide()
    end
    if auxiliary then
        local spec, timer = state.spec, state.spec and state.spec.secondaryTimer
        if preview._sampleEbonEnabled and timer then
            local value = CPPreview.AnimatedValue(timer, PreviewElapsed(preview)) or timer.value or .6
            auxiliary:PaintEbon(true, value * 20, 20)
        end
        auxiliary:TickHP(AnimatedMeterFraction(preview, .74, .34, .18, 1))
        auxiliary:PaintMana(AnimatedMeterFraction(preview, .68, .36, .15, .96))
        auxiliary.classCount = preview.cpTick and preview.cpTick.count or auxiliary.classCount
        auxiliary.marks.PaintSample()
    end
    ApplyLayerVisibility(preview)
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
    if not preview.auxiliary then return end
    local frame = preview.auxiliary:PaintMana(AnimatedMeterFraction(preview, .68, .36, .15, .96))
    preview.altMana = frame
    if not frame then return end
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
local function RenderExtraSamples(preview, bars, player, spec)
    local auxiliary = preview.auxiliary
    if not auxiliary then return end
    local pain, arcane
    if preview._resourceExtraExample then pain, arcane = M.ResourceExtrasPreview.Eligibility(preview)
    else
        local class = PreviewClassToken(spec)
        pain = class == "WARRIOR" and bars.showIgnorePain == true
        arcane = spec and spec.key == "mage_arcane" and bars.showArcaneWindow == true
    end
    if not HAS_EXTRA_AURAS then pain, arcane = false, false end
    local seconds, soul = M.ResourceExtrasPreview.ArcaneSample(preview, tonumber(bars.arcaneWindowWarnSeconds) or 3)
    preview.resourceSamples = auxiliary:PaintExtras(pain, arcane, seconds, soul)
end
function Preview.UpdateSampleThresholds(preview)
    if preview.auxiliary then preview.auxiliary.marks.PaintSample() end
end

local function RefreshBounds(preview, classFrame, ebonFrame, powerFrame, hpFrame)
    PlaceBound(preview, "class", classFrame, "Class", LAYER_COLORS.class, 1)
    PlaceBound(preview, "ebon", ebonFrame, "Ebon Might", LAYER_COLORS.ebon, 1, "class")
    PlaceBound(preview, "power", powerFrame, "Power", LAYER_COLORS.power, 1)
    PlaceBound(preview, "hp", hpFrame, "HP", LAYER_COLORS.hp, 1)
    PlaceBound(preview, "mana", preview.altMana, "Alternative Mana", LAYER_COLORS.mana, 1)
    local samples = preview.resourceSamples or {}
    local pain, arcane = samples.PAIN, samples.ARCANE
    PlaceBound(preview, "pain", pain and pain._sampleActive and pain, "Ignore Pain", { .45, .7, 1 }, 1,
        pain and pain._sampleLayer)
    PlaceBound(preview, "arcane", arcane and arcane._sampleActive and arcane, "Arcane Window", { .66, .42, 1 }, 1,
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
ApplyLayerVisibility = function(preview)
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
    SetShownSafe(preview.altMana, LayerOn(preview, "mana") and preview.auxiliary and preview.auxiliary.AM.visible == true)
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
    Preview.RenderAlternativeMana(box, bars)
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
    if box.playerRuntime then box.playerRuntime.root:Deactivate() end
    if box.auxiliary then box.auxiliary:Hide() end
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
