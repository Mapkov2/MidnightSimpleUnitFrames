--- Auras3/EditMode_Preview: fake aura groups and their refresh signatures; live aura payloads remain native.
--- Registered at load time; the original entrypoint owns initialization order.
local addonName, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Auras3/MSUF_Auras3_EditMode_Preview.lua")
local A3 = MSUF.MSUF_Auras3
local AuraPainter = assert(MSUF.Require("MSUF_Auras3", "Auras3/EditMode_Preview").MockAuraPainter, "MSUF: missing core mock aura painter")
local GetGlobalFontSettings = MSUF.Require("MSUF_GetGlobalFontSettings", "Auras3/MSUF_Auras3_EditMode_Preview.lua")
local SetFontChecked = MSUF.Require("MSUF_SetFontChecked", "Auras3/MSUF_Auras3_EditMode_Preview.lua")
local MAX_ARENA_FRAMES = tonumber(MSUF.Client.MaxArenaOpponents) or 3

A3.EditModeModules.Preview = function(config, layout, drag, IsBossScope, ForEachBossUnit, EditPreviewActive, UnitPreviewActive, SyncPreviewGroupStrata)
local PaintSwipe, AuraState, PlaceText = AuraPainter.Swipe, AuraPainter.AuraState, AuraPainter.PlaceText
local DispelBorder, LayoutDurationBar = AuraPainter.DispelBorder, AuraPainter.LayoutDurationBar
local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local math_floor, math_min, math_max = math.floor, math.min, math.max
local CreateFrame, UIParent = CreateFrame, UIParent
local EM = A3.EditMode
local function IsArenaScope(unit)
    return tostring(unit or ""):lower() == "arena"
end

local function ForEachArenaUnit(fn)
    if type(fn) ~= "function" then return end
    for i = 1, MAX_ARENA_FRAMES do fn("arena" .. i) end
end

local FrameLayers = MSUF.UF and MSUF.UF.Layers or {}
local Clamp = config.Clamp
local Round = config.Round
local NormalizeKind = config.NormalizeKind
local CustomItem = config.CustomItem
local CustomPreviewEntries = config.CustomPreviewEntries
local CustomPreviewEntriesSignature = config.CustomPreviewEntriesSignature
local GroupTitle = config.GroupTitle
local EnsureDB = config.EnsureDB
local UnitEnabled = config.UnitEnabled
local UnitHasCustomPreview = config.UnitHasCustomPreview
local ReadTextConfig = config.ReadTextConfig
local ReadGroupConfig = config.ReadGroupConfig
local AURA_UNITS = config.AURA_UNITS
local GROUPS = config.GROUPS
local GetFrame = layout.GetFrame
local FrameScaleRelativeToUIParent = layout.FrameScaleRelativeToUIParent
local ApplyGroupScaleForFrame = layout.ApplyGroupScaleForFrame
local IconGridCoord = layout.IconGridCoord
local PaddingInset = layout.PaddingInset
local LaneIconStyle = layout.LaneIconStyle
local PositionPreviewGroup = layout.PositionPreviewGroup
local FallbackMetrics = layout.FallbackMetrics
local OpenAuraGroupPopup = drag.OpenAuraGroupPopup
local StopAuraPendingDrag = drag.StopAuraPendingDrag
local QueueAuraPendingDrag = drag.QueueAuraPendingDrag
local EndAuraGroupDrag = drag.EndAuraGroupDrag
local SetRuntimeAuraHidden = drag.SetRuntimeAuraHidden
local BeginAuraGroupDrag = drag.BeginAuraGroupDrag
local W8 = "Interface\\Buttons\\WHITE8X8"
local HEADER_H = 18
local PREVIEW_ICONS = 4
local function ApplyGlobalFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow = GetGlobalFontSettings()
    fontPath = fontPath or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fontFlags = fontFlags or "OUTLINE"
    if fs.SetFont then
        size = tonumber(size) or 14
        if size <= 0 then size = 14 end
        if size < 6 then size = 6 elseif size > 40 then size = 40 end
        SetFontChecked(fs, fontPath, size, fontFlags)
    end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then
        if useShadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
    end
end

local function StyleLabel(fs)
    ApplyGlobalFont(fs, 11)
    if fs and fs.SetTextColor then fs:SetTextColor(0.92, 0.96, 1, 0.95) end
end

local function EnsureIcon(group, index)
    local icons = group._icons
    if not icons then
        icons = {}
        group._icons = icons
    end
    local icon = icons[index]
    if icon then return icon end

    icon = PixelLayoutRegion(CreateFrame("Frame", nil, group.Body or group, "BackdropTemplate"))
    PixelLayoutRegion(icon, "SetBackdrop", { bgFile = W8, edgeFile = W8, edgeSize = 1 })
    icon:SetBackdropColor(0, 0, 0, 0)
    icon:SetBackdropBorderColor(0, 0, 0, 0)

    local tex = PixelLayoutRegion(icon:CreateTexture(nil, "BORDER"))
    tex:SetAllPoints(icon)
    tex:SetTexCoord(0, 1, 0, 1)
    icon.Icon = tex

    local shade = PixelLayoutRegion(icon:CreateTexture(nil, "ARTWORK"))
    shade:SetAllPoints(icon)
    shade:SetColorTexture(0, 0, 0, 0)
    icon.Shade = shade

    -- Preview-only deterministic swipe. The shared preview animation advances
    -- its width; no native Cooldown state survives an Off -> On transition.
    icon.Swipe = AuraPainter.NewSwipe(icon)
    icon.DurationBar = AuraPainter.NewDurationBar(icon)

    local dispelBorder = PixelLayoutRegion(icon:CreateTexture(nil, "OVERLAY", nil, 2))
    dispelBorder:Hide()
    icon.DispelBorder = dispelBorder

    local cd = PixelLayoutRegion(icon:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    if cd.SetDrawLayer then
        cd:SetDrawLayer("OVERLAY", FrameLayers.AURA_COOLDOWN_TEXT_DRAW_SUBLEVEL or 7)
    end
    cd:SetPoint("CENTER", icon, "CENTER", 0, 0)
    ApplyGlobalFont(cd, 14)
    cd:SetText("1m")
    icon.CooldownText = cd

    local count = PixelLayoutRegion(icon:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    if count.SetDrawLayer then
        count:SetDrawLayer("OVERLAY", FrameLayers.AURA_STACK_DRAW_SUBLEVEL or 6)
    end
    ApplyGlobalFont(count, 14)
    count:SetText(index == 1 and "3" or "")
    icon.Count = count

    icons[index] = icon
    return icon
end

local function LayoutPreviewSwipe(icon, cfg, remainingFrac)
    local swipe = icon.Swipe
    if not (swipe and cfg.showCooldownSwipe ~= false and not (cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY")) then
        if swipe then swipe:Hide() end
        return
    end
    local size = math_max(1, (icon.GetWidth and icon:GetWidth()) or 1)
    PaintSwipe(swipe, icon, size, size, remainingFrac, cfg.cooldownSwipeReverse == true)
    swipe:Show()
end

local ApplyIconZoom = AuraPainter.IconZoom

local function ApplyPreviewIconText(icon, unit, cfg, index)
    cfg = cfg or ReadTextConfig(unit)
    local barOnly = cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
    if icon.Icon then icon.Icon:SetShown(not barOnly) end
    if icon.Shade then icon.Shade:SetShown(not barOnly) end
    if icon.Count then
        ApplyGlobalFont(icon.Count, cfg.stackSize)
        local anchor = cfg.stackAnchor
        if anchor ~= "TOPLEFT" and anchor ~= "BOTTOMLEFT" and anchor ~= "BOTTOMRIGHT" then anchor = "TOPRIGHT" end
        PlaceText(icon.Count, icon, anchor, cfg.stackX, cfg.stackY)
        icon.Count:SetShown(cfg.showStackCount ~= false)
    end
    if icon.CooldownText then
        ApplyGlobalFont(icon.CooldownText, cfg.cooldownSize)
        PlaceText(icon.CooldownText, icon, cfg.cooldownAnchor, cfg.cooldownX or 0, cfg.cooldownY or 0)
        icon.CooldownText:SetShown(cfg.showCooldownText ~= false)
    end
    LayoutPreviewSwipe(icon, cfg)
    DispelBorder(icon.DispelBorder, icon, math_max(1, (icon.GetWidth and icon:GetWidth()) or 24),
        not barOnly and cfg.debuffBorderMode or "OFF", cfg.iconShape, index)
    if icon.DurationBar then
        if cfg.showDurationBar == true then
            LayoutDurationBar(icon.DurationBar, icon, cfg.durationBarPosition,
                Clamp(cfg.durationBarHeight, 2, 1, 16), 1)
        else
            icon.DurationBar:Hide()
        end
    end
end

local function ApplyPreviewDurationBarProgress(icon, cfg, auraState)
    local bar = icon.DurationBar
    if not bar then return end
    local size = math_max(1, (icon.GetWidth and icon:GetWidth()) or 1)
    local height = Clamp(cfg.durationBarHeight, 2, 1, math_max(1, size))
    local inset = math_max(1, math_floor(size / 32 + 0.5))
    local frac
    if cfg.durationBarDirection == "ELAPSED" then
        frac = auraState and auraState.elapsedFrac or 1
    else
        frac = auraState and auraState.remainingFrac or 1
    end
    frac = math_max(0.02, math_min(1, tonumber(frac) or 1))
    LayoutDurationBar(bar, icon, cfg.durationBarPosition, height, inset, size, auraState and frac or nil)
end

local function ApplyPreviewAuraAnimation(group, kind, shownIcons, textCfg, elapsed)
    local icons = group and group._icons
    if not icons then return end
    group._msufA3PreviewAnimated = elapsed ~= nil or MSUF.PreviewAnimation.enabled == true
    for i = 1, shownIcons do
        local icon = icons[i]
        if icon then
            local auraState = AuraState(icon, kind, i, textCfg, elapsed)
            if icon.Count then icon.Count:SetText(textCfg.showStackCount ~= false and (auraState and auraState.stacks or (i == 1 and "3" or "")) or "") end
            if icon.CooldownText then
                icon.CooldownText:SetText(textCfg.showCooldownText ~= false
                    and (auraState and auraState.text or (i == 1 and "1m" or "32")) or "")
            end
            LayoutPreviewSwipe(icon, textCfg, auraState and auraState.remainingFrac)
            -- The lane's bar was hidden by the layout that recorded this config.
            if textCfg.showDurationBar == true then ApplyPreviewDurationBarProgress(icon, textCfg, auraState) end
        end
    end
end

local function CreateGroup(unit, kind)
    kind = NormalizeKind(kind)
    EM.groups = EM.groups or {}
    local byUnit = EM.groups[unit]
    if not byUnit then
        byUnit = {}
        EM.groups[unit] = byUnit
    end
    if byUnit[kind] then return byUnit[kind] end

    local spec = GROUPS[kind]
    local snapName = "AuraPreview:" .. tostring(unit) .. ":" .. tostring(kind)
    local group = PixelLayoutRegion(CreateFrame("Button", nil, UIParent, "BackdropTemplate"), true)
    SyncPreviewGroupStrata(group)
    group:SetFrameLevel(900)
    group:SetClampedToScreen(false)
    group:SetMovable(true)
    group:EnableMouse(true)
    if group.SetMouseClickEnabled then group:SetMouseClickEnabled(true) end
    if group.SetMouseMotionEnabled then group:SetMouseMotionEnabled(true) end
    if group.RegisterForClicks then group:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if group.RegisterForDrag then group:RegisterForDrag("LeftButton") end
    PixelLayoutRegion(group, "SetBackdrop", {
        bgFile = W8, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    group:SetBackdropColor(0.02, 0.03, 0.08, 0.28)
    group:SetBackdropBorderColor(spec.color[1], spec.color[2], spec.color[3], 0.72)

    local header = PixelLayoutRegion(CreateFrame("Frame", nil, group, "BackdropTemplate"))
    header:SetPoint("TOPLEFT", group, "TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", group, "TOPRIGHT", -2, -2)
    header:SetHeight(HEADER_H)
    PixelLayoutRegion(header, "SetBackdrop", { bgFile = W8 })
    header:SetBackdropColor(spec.color[1], spec.color[2], spec.color[3], spec.color[4])
    group.Header = header

    local label = PixelLayoutRegion(header:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    label:SetPoint("LEFT", header, "LEFT", 6, 0)
    label:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    StyleLabel(label)
    label:SetText(GroupTitle(unit, kind, spec))
    group.Label = label

    local body = PixelLayoutRegion(CreateFrame("Frame", nil, group))
    body:SetPoint("BOTTOMLEFT", group, "BOTTOMLEFT", 0, 0)
    body:SetSize(1, 1)
    group.Body = body

    group._msufA3Unit = unit
    group._msufA3MoverKind = kind
    group._msufA3SnapName = snapName
    group:Hide()

    group:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            StopAuraPendingDrag(self)
            OpenAuraGroupPopup(self)
            return
        end
        QueueAuraPendingDrag(self, button)
    end)

    group:SetScript("OnMouseUp", function(self, button)
        EndAuraGroupDrag(self, button)
    end)
    group:SetScript("OnDragStart", function(self)
        BeginAuraGroupDrag(self, true)
    end)
    group:SetScript("OnDragStop", function(self)
        EndAuraGroupDrag(self, "LeftButton")
    end)
    group:SetScript("OnHide", function(self)
        EndAuraGroupDrag(self, "LeftButton", true)
    end)

    local hitbox = PixelLayoutRegion(CreateFrame("Button", nil, group), true)
    hitbox:SetAllPoints(group)
    hitbox:EnableMouse(true)
    if hitbox.SetMouseClickEnabled then hitbox:SetMouseClickEnabled(true) end
    if hitbox.SetMouseMotionEnabled then hitbox:SetMouseMotionEnabled(true) end
    if hitbox.RegisterForClicks then hitbox:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if hitbox.RegisterForDrag then hitbox:RegisterForDrag("LeftButton") end
    hitbox._msufA3HitboxOwner = group
    hitbox:SetScript("OnMouseDown", function(self, button)
        local owner = self._msufA3HitboxOwner or self:GetParent()
        if button == "RightButton" then
            StopAuraPendingDrag(owner)
            OpenAuraGroupPopup(owner)
        else
            QueueAuraPendingDrag(owner, button)
        end
    end)
    hitbox:SetScript("OnMouseUp", function(self, button)
        local owner = self._msufA3HitboxOwner or self:GetParent()
        EndAuraGroupDrag(owner, button)
    end)
    hitbox:SetScript("OnDragStart", function(self)
        local owner = self._msufA3HitboxOwner or self:GetParent()
        BeginAuraGroupDrag(owner, true)
    end)
    hitbox:SetScript("OnDragStop", function(self)
        local owner = self._msufA3HitboxOwner or self:GetParent()
        EndAuraGroupDrag(owner, "LeftButton")
    end)
    group.Hitbox = hitbox

    byUnit[kind] = group
    return group
end

--- Share the live renderer for matching Glow, Pulse, alpha and effect layers.
--- The dragged preview uses the same Layers.AuraEffectLevel as live frames.
local function ApplyEditModeCustomEffect(group, frame, item)
    local runtime = A3.SpellIndicators
    local owner = group and group._msufA3CustomEffectPreview
    local normalize = runtime and runtime.NormalizeFrameEffect
    local effect = type(normalize) == "function" and normalize(item and item.frame) or nil
    if not (group and frame and effect
        and runtime and type(runtime.ApplyPreviewFrameEffect) == "function") then
        if owner then
            if runtime and type(runtime.HidePreviewFrameEffect) == "function" then
                runtime.HidePreviewFrameEffect(owner)
            else
                owner:Hide()
            end
        end
        return
    end
    if not owner then
        owner = PixelLayoutRegion(CreateFrame("Frame", nil, group))
        owner:EnableMouse(false)
        group._msufA3CustomEffectPreview = owner
    end
    owner:ClearAllPoints()
    owner:SetAllPoints(group)
    runtime.ApplyPreviewFrameEffect(owner, effect, frame)
end

local function FrameRefreshSignature(frame)
    if not frame then return "noframe" end
    local l = frame.GetLeft and frame:GetLeft() or 0
    local t = frame.GetTop and frame:GetTop() or 0
    local w = frame.GetWidth and frame:GetWidth() or 0
    local h = frame.GetHeight and frame:GetHeight() or 0
    return tostring(Round(l or 0)) .. "\031" .. tostring(Round(t or 0))
        .. "\031" .. tostring(Round(w or 0)) .. "\031" .. tostring(Round(h or 0))
        .. "\031" .. tostring(Round(FrameScaleRelativeToUIParent(frame) * 1000))
end

local function EditModeThemeRevision()
    local menu = MSUF.MSUF2
    return tostring((menu and (menu._msuf2MenuDataRevision or menu._msuf2LayoutVersion)) or 0)
end

local function RefreshSignature(unit, kind, cfg, metrics, textCfg, lane, frameSig)
    return tostring(unit) .. "\030" .. tostring(kind) .. "\030" .. tostring(frameSig)
        .. "\030" .. EditModeThemeRevision()
        .. "\030" .. tostring(cfg and cfg.show) .. "\030" .. tostring(metrics and metrics.num or cfg and cfg.max)
        .. "\030" .. tostring(metrics and metrics.layer or cfg and cfg.layer)
        .. "\030" .. tostring(metrics and metrics.spacing or cfg and cfg.spacing)
        .. "\030" .. tostring(metrics and metrics.alpha or cfg and cfg.alpha)
        .. "\030" .. tostring(lane.shownIcons) .. "\030" .. tostring(lane.size)
        .. "\030" .. tostring(lane.step) .. "\030" .. tostring(lane.perRow)
        .. "\030" .. tostring(lane.laneW) .. "\030" .. tostring(lane.laneH)
        .. "\030" .. tostring(lane.growthX) .. "\030" .. tostring(lane.growthY)
        .. "\030" .. tostring(lane.vertical) .. "\030" .. tostring(lane.initialAnchor)
        .. "\030" .. tostring(lane.x) .. "\030" .. tostring(lane.y) .. "\030" .. tostring(lane.anchor)
        .. "\030" .. tostring(metrics and metrics.enabled)
        .. "\030" .. tostring(metrics and metrics.iconZoom or cfg and cfg.iconZoom)
        .. "\030" .. tostring(metrics and metrics.iconShape or cfg and cfg.iconShape)
        .. "\030" .. tostring(textCfg and textCfg.stackSize) .. "\030" .. tostring(textCfg and textCfg.stackX)
        .. "\030" .. tostring(textCfg and textCfg.stackY) .. "\030" .. tostring(textCfg and textCfg.cooldownSize)
        .. "\030" .. tostring(textCfg and textCfg.cooldownX) .. "\030" .. tostring(textCfg and textCfg.cooldownY)
        .. "\030" .. tostring(textCfg and textCfg.cooldownDecimalSeconds)
        .. "\030" .. tostring(textCfg and textCfg.stackAnchor) .. "\030" .. tostring(textCfg and textCfg.cooldownAnchor)
        .. "\030" .. tostring(textCfg and textCfg.showDurationBar) .. "\030" .. tostring(textCfg and textCfg.durationBarHeight)
        .. "\030" .. tostring(textCfg and textCfg.durationBarDisplay) .. "\030" .. tostring(textCfg and textCfg.durationBarPosition)
        .. "\030" .. tostring(textCfg and textCfg.durationBarDirection)
        .. "\030" .. tostring(textCfg and textCfg.showStackCount) .. "\030" .. tostring(textCfg and textCfg.showCooldownText)
        .. "\030" .. tostring(textCfg and textCfg.showCooldownSwipe) .. "\030" .. tostring(textCfg and textCfg.cooldownSwipeReverse)
        .. "\030" .. tostring(textCfg and textCfg.debuffBorderMode)
end

--- Edit mode shows draggable chrome (header, tinted backdrop, mouse). The boss
--- page preview renders the same lanes chromeless and click-through so they
--- read as pure aura previews on top of the previewed frames.
local function ApplyGroupChrome(group, spec, chrome)
    if not group or group._msufA3ChromeMode == chrome then return end
    group._msufA3ChromeMode = chrome
    if group.Header then group.Header:SetShown(chrome) end
    if group.SetBackdropColor then group:SetBackdropColor(0.02, 0.03, 0.08, chrome and 0.28 or 0) end
    if group.SetBackdropBorderColor then
        local color = (spec and spec.color) or {}
        group:SetBackdropBorderColor(color[1] or 1, color[2] or 1, color[3] or 1, chrome and 0.72 or 0)
    end
    local interactive = chrome == true
    group:EnableMouse(interactive)
    if group.SetMouseClickEnabled then group:SetMouseClickEnabled(interactive) end
    if group.SetMouseMotionEnabled then group:SetMouseMotionEnabled(interactive) end
    local hitbox = group.Hitbox
    if hitbox then
        hitbox:EnableMouse(interactive)
        if hitbox.SetMouseClickEnabled then hitbox:SetMouseClickEnabled(interactive) end
        if hitbox.SetMouseMotionEnabled then hitbox:SetMouseMotionEnabled(interactive) end
    end
end

function EM.HideUnit(unit)
    if IsBossScope(unit) then
        ForEachBossUnit(EM.HideUnit)
        return
    end
    if IsArenaScope(unit) then
        ForEachArenaUnit(EM.HideUnit)
        return
    end
    local byUnit = EM.groups and EM.groups[unit]
    SetRuntimeAuraHidden(unit, false)
    if not byUnit then return end
    for _, group in pairs(byUnit) do
        if group then
            group._msufA3RefreshSignature = nil
            group:Hide()
        end
    end
end

--- Resolves the frame a unit's preview lanes sit on. Hides the unit's lanes and
--- returns nil when the unit has nothing to preview.
local function PreviewFrameFor(unit)
    local auras, shared = EnsureDB()
    -- showInEditMode is an edit-mode-only toggle; the boss page preview keeps
    -- rendering lanes regardless because it is the page's whole purpose.
    if not shared or (EditPreviewActive() and shared.showInEditMode == false)
        or (not UnitEnabled(auras, unit) and not UnitHasCustomPreview(unit)) then
        EM.HideUnit(unit)
        return nil
    end

    local frame = GetFrame(unit)
    if not frame then
        EM.HideUnit(unit)
        return nil
    end
    -- Outside edit mode (boss page preview) lanes only make sense on frames the
    -- preview actually shows; edit mode forces its frames visible itself.
    if not EditPreviewActive() and frame.IsShown and not frame:IsShown() then
        EM.HideUnit(unit)
        return nil
    end
    return frame
end

-- One lane's resolved layout, rewritten completely by every ResolveLaneState
-- call and consumed before the next lane resolves.
local PREVIEW_LANE = {}

--- Resolves one lane's layout numbers: the compiled Runtime metrics win and the
--- preview-only fallbacks fill the gaps. Returns the shared PREVIEW_LANE table.
local function ResolveLaneState(unit, kind, spec, cfg, metrics, textCfg, entries, frame)
    local shownIcons
    if entries then
        -- Custom lanes preview the tracked spells 1:1: one icon per
        -- configured spell, capped by the lane's own max.
        shownIcons = math_min((metrics and metrics.num) or cfg.max, #entries)
    else
        shownIcons = math_min(PREVIEW_ICONS, (metrics and metrics.num) or cfg.max)
    end
    if shownIcons < 1 then shownIcons = 1 end
    local size = (metrics and metrics.size) or cfg.size
    local iconH = (metrics and metrics.buttonHeight) or size
    local step = (metrics and (metrics.stepX or metrics.step)) or (cfg.size + cfg.spacing)
    local stepY = (metrics and metrics.stepY) or (iconH + cfg.spacing)
    local perRow = (metrics and metrics.perRow) or cfg.perRow
    local fallback
    if not metrics then fallback = FallbackMetrics(cfg) end
    local laneW = (metrics and metrics.width) or (fallback and fallback.width) or cfg.size
    local laneH = (metrics and metrics.height) or (fallback and fallback.height) or cfg.size
    local growthX = (metrics and metrics.growthX) or (fallback and fallback.growthX) or 1
    local growthY = (metrics and metrics.growthY) or (fallback and fallback.growthY) or -1
    local vertical = metrics and metrics.verticalGrowth == true or (fallback and fallback.verticalGrowth == true)
    local initialAnchor = (metrics and metrics.initialAnchor) or (fallback and fallback.initialAnchor) or "TOPLEFT"
    -- Shared icon style + lane padding, 1:1 with the runtime lane. A
    -- bar-only lane renders no icon chrome, so the style stays off.
    local barOnly = textCfg.showDurationBar == true and textCfg.durationBarDisplay == "BAR_ONLY"
    local appearanceKind = spec.preset and unit == "player" and "playerDefensives"
        or spec.preset and "targetDots"
        or ((kind == "debuff" or cfg.auraType == "DEBUFF") and "debuff" or "buff")
    local iconStyle = (not barOnly) and LaneIconStyle(metrics, unit, appearanceKind) or nil
    local requestedIconShape = (metrics and metrics.requestedIconShape) or cfg.iconShape
    local iconShape = (metrics and metrics.iconShape) or cfg.iconShape or "RECTANGLE"
    if type(A3.ResolveAuraIconShape) == "function" then
        iconShape = A3.ResolveAuraIconShape(requestedIconShape,
            frame and frame.MSUFSpec and frame.MSUFSpec.portrait and frame.MSUFSpec.portrait.shape)
    end
    textCfg.iconShape = iconShape

    local lane = PREVIEW_LANE
    lane.shownIcons = shownIcons
    lane.size = size
    lane.iconH = iconH
    lane.step = step
    lane.stepY = stepY
    lane.perRow = perRow
    lane.laneW = laneW
    lane.laneH = laneH
    lane.growthX = growthX
    lane.growthY = growthY
    lane.vertical = vertical
    lane.initialAnchor = initialAnchor
    lane.x = (metrics and metrics.x) or cfg.x
    lane.y = (metrics and metrics.y) or cfg.y
    lane.anchor = (metrics and metrics.anchor) or cfg.anchor
    lane.padding = Clamp(metrics and metrics.padding, 0, 0, 16)
    lane.iconStyle = iconStyle
    lane.iconShape = iconShape
    return lane
end

--- Sizes, anchors and styles the lane's icons and hides the unused ones.
local function LayoutPreviewIcons(group, unit, spec, cfg, metrics, textCfg, entries, lane)
    local size, iconH, perRow, vertical = lane.size, lane.iconH, lane.perRow, lane.vertical
    local initialAnchor, step, stepY = lane.initialAnchor, lane.step, lane.stepY
    local growthX, growthY = lane.growthX, lane.growthY
    local iconStyle, iconShape, shownIcons = lane.iconStyle, lane.iconShape, lane.shownIcons
    local padX, padY = PaddingInset(initialAnchor, lane.padding)
    for i = 1, shownIcons do
        local icon = EnsureIcon(group, i)
        icon:SetSize(size, iconH)
        icon:ClearAllPoints()
        local col, row = IconGridCoord(i, perRow, vertical)
        local body = group.Body or group
        icon:SetPoint(initialAnchor, body, initialAnchor, col * step * growthX + padX, row * stepY * growthY + padY)
        if icon.Icon then
            local entry = entries and entries[i]
            icon.Icon:SetTexture((entry and entry.icon) or cfg.texture or spec.texture)
            ApplyIconZoom(icon.Icon, metrics and metrics.iconZoom or cfg.iconZoom, size, iconH)
        end
        if type(A3.ApplyAuraIconShape) == "function" then
            A3.ApplyAuraIconShape(icon, iconShape, nil, icon.Icon, icon.Shade, icon.Swipe)
        end
        if icon.Count then icon.Count:SetText(i == 1 and "3" or "") end
        if icon.CooldownText then icon.CooldownText:SetText(i == 1 and "1m" or "32") end
        ApplyPreviewIconText(icon, unit, textCfg, i)
        local skinned = A3.ApplyIconStyleSkinned(icon, iconStyle, size, iconShape, iconH)
        A3.MockAuraPainter.SkinLayers(icon.Swipe, skinned)
        icon:Show()
    end

    local icons = group._icons
    if icons then
        for i = shownIcons + 1, #icons do
            if icons[i] then icons[i]:Hide() end
        end
    end
end

--- Repositions the lane's group and rebuilds its icons; runs only when the
--- lane's refresh signature changed.
local function ApplyLaneLayout(group, frame, unit, kind, spec, cfg, metrics, textCfg, entries, lane, chrome)
    if group.SetClampedToScreen then group:SetClampedToScreen(false) end
    ApplyGroupScaleForFrame(group, frame)
    PositionPreviewGroup(group, frame, lane.anchor, lane.x, lane.y, lane.laneW, lane.laneH)
    group:SetSize(lane.laneW, lane.laneH + HEADER_H)
    if group.Body then group.Body:SetSize(lane.laneW, lane.laneH) end
    if group.Body then group.Body:SetAlpha(Clamp(metrics and metrics.alpha or cfg.alpha, 1, 0, 1)) end
    local layers = MSUF.UF and MSUF.UF.Layers
    local layer = (metrics and metrics.layer) or cfg.layer
    group:SetFrameLevel(layers and layers.ElementLevel and layers.ElementLevel(layer, 5, 0)
        or (900 + Clamp(layer, 5, 0, 30)))
    if group.Hitbox and group.Hitbox.SetFrameLevel then
        group.Hitbox:SetFrameLevel((group:GetFrameLevel() or 0) + 20)
    end
    if group.Label then
        group.Label:SetText(GroupTitle(unit, kind, spec))
        StyleLabel(group.Label)
    end
    ApplyGroupChrome(group, spec, chrome)
    LayoutPreviewIcons(group, unit, spec, cfg, metrics, textCfg, entries, lane)
end

--- Refreshes one aura lane of a unit's preview: hides it when it has nothing to
--- show, otherwise resolves its layout, repaints on a changed signature and
--- advances the animation state.
local function RefreshLane(unit, kind, spec, frame, frameSig, chrome, runtimeConfig)
    local cfg = ReadGroupConfig(unit, kind)
    local entries = spec.customIndex and CustomPreviewEntries(unit, kind) or nil
    -- Target DoTs retain their configuration preview while disabled.
    -- Player Defensives obey their master switch in Edit Mode as well.
    local laneShown = cfg.show
        or (unit ~= "player" and spec.preset and entries ~= nil)
    -- Outside edit mode custom lanes stay strictly 1:1 with the runtime:
    -- nothing tracked means nothing to preview. Placeholder-only custom
    -- lanes exist purely as edit-mode drag surfaces.
    if laneShown and spec.customIndex and not entries and not chrome then laneShown = false end
    local byUnit = EM.groups and EM.groups[unit]
    local group = byUnit and byUnit[kind]
    if not laneShown or cfg.max <= 0 then
        if group then
            group._msufA3RefreshSignature = nil
            group:Hide()
        end
        return
    end
    group = group or CreateGroup(unit, kind)
    SyncPreviewGroupStrata(group)
    local metrics = group._msufA3PreviewMetrics
    if not runtimeConfig or group._msufA3PreviewConfig ~= runtimeConfig then
        metrics = A3.BuildAuraLaneMetrics(runtimeConfig or unit, kind)
        group._msufA3PreviewConfig, group._msufA3PreviewMetrics = runtimeConfig, metrics
    end
    if metrics and metrics.enabled == false then
        group._msufA3RefreshSignature = nil
        group:Hide()
        return
    end

    -- Existing lanes use the compiler-finalized Runtime contract.
    -- ReadTextConfig remains only for edit-only placeholders that do
    -- not have a compiled lane yet.
    local textCfg = (metrics and metrics.textConfig) or ReadTextConfig(unit, kind)
    local lane = ResolveLaneState(unit, kind, spec, cfg, metrics, textCfg, entries, frame)
    local iconStyle = lane.iconStyle
    local signature = RefreshSignature(unit, kind, cfg, metrics, textCfg, lane, frameSig)
        .. "\030" .. CustomPreviewEntriesSignature(entries) .. "\030" .. tostring(chrome)
        .. "\030" .. tostring(lane.padding) .. "\030" .. tostring(lane.iconH)
        .. "\030" .. tostring(iconStyle and iconStyle.signature)

    if group._msufA3RefreshSignature ~= signature or not (group.IsShown and group:IsShown()) then
        group._msufA3RefreshSignature = signature
        ApplyLaneLayout(group, frame, unit, kind, spec, cfg, metrics, textCfg, entries, lane, chrome)
    elseif not spec.customIndex and not group._msufA3PreviewAnimated and MSUF.PreviewAnimation.enabled ~= true then
        -- Animation has its own tick; a refresh of unchanged standard lanes
        -- keeps those pixels and their pooled icons instead of restarting them.
        group:Show()
        if group.Raise then group:Raise() end
        return
    end

    -- Cache the already-resolved lane state so Menu2's existing
    -- animation tick can advance only these visible regions.  It must
    -- not rerun DB reads, metrics, anchoring, or a full RefreshUnit at
    -- 20 Hz merely to keep Edit Mode in phase with the menu preview.
    local shownIcons = lane.shownIcons
    group._msufA3AnimationKind = kind
    group._msufA3AnimationShownIcons = shownIcons
    group._msufA3AnimationTextConfig = textCfg
    ApplyPreviewAuraAnimation(group, kind, shownIcons, textCfg)
    if spec.customIndex then ApplyEditModeCustomEffect(group, frame, CustomItem(unit, spec.customIndex, false)) end
    group:Show()
    if group.Raise then group:Raise() end
end

function EM.RefreshUnit(unit)
    if not unit then return end
    if IsBossScope(unit) then
        ForEachBossUnit(EM.RefreshUnit)
        return
    end
    if IsArenaScope(unit) then
        ForEachArenaUnit(EM.RefreshUnit)
        return
    end
    if not UnitPreviewActive(unit) then
        EM.HideUnit(unit)
        return
    end

    local frame = PreviewFrameFor(unit)
    if not frame then return end

    SetRuntimeAuraHidden(unit, true)
    local frameSig = FrameRefreshSignature(frame)

    local chrome = EditPreviewActive()
    local runtimeConfig = A3.ResolveUnitFrameConfig(unit)
    for kind, spec in pairs(GROUPS) do
        RefreshLane(unit, kind, spec, frame, frameSig, chrome, runtimeConfig)
    end
end

function EM.RefreshAll()
    for i = 1, #AURA_UNITS do
        EM.RefreshUnit(AURA_UNITS[i])
    end
end

function EM.HideAll()
    if not EM.groups then return end
    for unit in pairs(EM.groups) do
        EM.HideUnit(unit)
    end
end


return {
    ApplyPreviewAuraAnimation = ApplyPreviewAuraAnimation,
}
end
