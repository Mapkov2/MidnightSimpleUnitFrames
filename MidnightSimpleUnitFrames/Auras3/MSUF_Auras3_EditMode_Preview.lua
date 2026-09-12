--- Auras3/EditMode_Preview: fake aura groups and their refresh signatures; live aura payloads remain native.
--- Registered at load time; the original entrypoint owns initialization order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
A3.EditModeModules = A3.EditModeModules or {}
A3.EditModeModules.Preview = function(config, layout, drag, IsBossScope, ForEachBossUnit, EditPreviewActive, UnitPreviewActive, SyncPreviewGroupStrata)
local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local math_floor, math_min, math_max = math.floor, math.min, math.max
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local TextureKitConstants = _G.TextureKitConstants
local EM = A3.EditMode
local function IsArenaScope(unit)
    return tostring(unit or ""):lower() == "arena"
end

local function ForEachArenaUnit(fn)
    if type(fn) ~= "function" then return end
    for i = 1, 3 do fn("arena" .. i) end
end


local FrameLayers = MSUF.UF and MSUF.UF.Layers or {}
local function AuraDurationBarColor()
    local resolver = A3.GetDurationBarColor
    if type(resolver) == "function" then return resolver() end
    return 1, 1, 1
end
local Clamp = config.Clamp
local Round = config.Round
local NormalizeKind = config.NormalizeKind
local CustomItem = config.CustomItem
local CustomPreviewEntries = config.CustomPreviewEntries
local CustomPreviewEntriesSignature = config.CustomPreviewEntriesSignature
local UnitLabel = config.UnitLabel
local GroupLabel = config.GroupLabel
local EnsureDB = config.EnsureDB
local UnitEnabled = config.UnitEnabled
local UnitHasCustomPreview = config.UnitHasCustomPreview
local ReadTextConfig = config.ReadTextConfig
local ReadGroupConfig = config.ReadGroupConfig
local AURA_UNITS = config.AURA_UNITS
local GROUPS = config.GROUPS
local AURA_TEXT_ANCHOR_OK = config.AURA_TEXT_ANCHOR_OK
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
local DEBUFF_TYPE_BORDER_PREVIEW_ATLAS = {
    BORDER = "ui-debuff-border-magic-noicon",
    SYMBOL = "ui-debuff-border-magic-icon",
}
local HEADER_H = 18
local PREVIEW_ICONS = 4
local function ApplyGlobalFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        fontPath, fontFlags, r, g, b, _, useShadow = gfs()
    end
    fontPath = fontPath or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fontFlags = fontFlags or "OUTLINE"
    if fs.SetFont then
        size = tonumber(size) or 14
        if size <= 0 then size = 14 end
        if size < 6 then size = 6 elseif size > 40 then size = 40 end
        _G.MSUF_SetFontChecked(fs, fontPath, size, fontFlags)
    end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then
        if useShadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
    end
end

local function PlaceStackText(fs, owner, cfg)
    if not fs or not owner or not cfg then return end
    fs:ClearAllPoints()
    if cfg.stackAnchor == "TOPLEFT" then
        fs:SetPoint("TOPLEFT", owner, "TOPLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
    elseif cfg.stackAnchor == "BOTTOMLEFT" then
        fs:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("BOTTOM")
    elseif cfg.stackAnchor == "BOTTOMRIGHT" then
        fs:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetPoint("TOPRIGHT", owner, "TOPRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("TOP")
    end
end

local function PlaceCooldownText(fs, owner, cfg)
    if not fs or not owner or not cfg then return end
    fs:ClearAllPoints()
    local anchor = AURA_TEXT_ANCHOR_OK[cfg.cooldownAnchor] and cfg.cooldownAnchor or "CENTER"
    fs:SetPoint(anchor, owner, anchor, cfg.cooldownX or 0, cfg.cooldownY or 0)
    if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
        fs:SetJustifyH("LEFT")
    elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyH("RIGHT")
    else
        fs:SetJustifyH("CENTER")
    end
    if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
        fs:SetJustifyV("TOP")
    elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetJustifyV("MIDDLE")
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

    icon = CreateFrame("Frame", nil, group.Body or group, "BackdropTemplate")
    icon:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    icon:SetBackdropColor(0, 0, 0, 0)
    icon:SetBackdropBorderColor(0, 0, 0, 0)

    local tex = icon:CreateTexture(nil, "BORDER")
    tex:SetAllPoints(icon)
    tex:SetTexCoord(0, 1, 0, 1)
    icon.Icon = tex

    local shade = icon:CreateTexture(nil, "ARTWORK")
    shade:SetAllPoints(icon)
    shade:SetColorTexture(0, 0, 0, 0)
    icon.Shade = shade

    -- Preview-only deterministic swipe. The shared preview animation advances
    -- its width; no native Cooldown state survives an Off -> On transition.
    local swipe = icon:CreateTexture(nil, "ARTWORK", nil, 1)
    swipe:SetTexture(W8)
    swipe:SetVertexColor(0, 0, 0, 0.58)
    swipe:Hide()
    icon.Swipe = swipe

    local durationBar = icon:CreateTexture(nil, "OVERLAY")
    durationBar:SetTexture(W8)
    local durationR, durationG, durationB = AuraDurationBarColor()
    durationBar:SetVertexColor(durationR, durationG, durationB, 0.92)
    durationBar:Hide()
    icon.DurationBar = durationBar

    local dispelBorder = icon:CreateTexture(nil, "OVERLAY", nil, 2)
    dispelBorder:Hide()
    icon.DispelBorder = dispelBorder

    local cd = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if cd.SetDrawLayer then
        cd:SetDrawLayer("OVERLAY", FrameLayers.AURA_COOLDOWN_TEXT_DRAW_SUBLEVEL or 7)
    end
    cd:SetPoint("CENTER", icon, "CENTER", 0, 0)
    ApplyGlobalFont(cd, 14)
    cd:SetText("1m")
    icon.CooldownText = cd

    local count = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    local swipe = icon and icon.Swipe
    local barOnly = cfg and cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
    if not (swipe and cfg and cfg.showCooldownSwipe ~= false and not barOnly) then
        if swipe then swipe:Hide() end
        return
    end
    local size = math_max(1, (icon.GetWidth and icon:GetWidth()) or 1)
    -- Keep the preview legible at both ends of its loop while preserving the
    -- configured direction and the existing event-driven animation cadence.
    local frac = math_max(0.08, math_min(0.92, tonumber(remainingFrac) or 0.48))
    swipe:ClearAllPoints()
    swipe:SetWidth(math_max(1, math_floor(size * frac + 0.5)))
    swipe:SetHeight(size)
    if cfg.cooldownSwipeReverse == true then
        swipe:SetPoint("TOPLEFT", icon, "TOPLEFT")
        swipe:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT")
    else
        swipe:SetPoint("TOPRIGHT", icon, "TOPRIGHT")
        swipe:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT")
    end
    swipe:Show()
end

local function LayoutPreviewDispelBorder(icon, cfg, index)
    local border = icon and icon.DispelBorder
    local atlas = cfg and DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[cfg.debuffBorderMode]
    local barOnly = cfg and cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
    local size = math_max(1, (icon and icon.GetWidth and icon:GetWidth()) or 24)
    if not barOnly and type(A3.ApplyAuraDispelPreview) == "function"
        and A3.ApplyAuraDispelPreview(border, icon, size, cfg and cfg.debuffBorderMode,
            cfg and cfg.iconShape, A3.PreviewDispelTypeForIndex(index)) then
        return
    end
    if not (border and atlas and border.SetAtlas and not barOnly) then
        if border then border:Hide() end
        return
    end
    local pad = type(A3.NativeAuraDispelBorderPadding) == "function"
        and A3.NativeAuraDispelBorderPadding(size)
        or math_max(1, math_floor(size / 6 + 0.5))
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    border:SetAtlas(atlas, TextureKitConstants and TextureKitConstants.IgnoreAtlasSize)
    border:Show()
end

local function ApplyIconZoom(texture, zoom)
    if not (texture and texture.SetTexCoord) then return end
    zoom = Clamp(zoom, 100, 100, 200)
    local visible = 100 / zoom
    local inset = (1 - visible) * 0.5
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end

local function ApplyPreviewIconText(icon, unit, cfg, index)
    cfg = cfg or ReadTextConfig(unit)
    local barOnly = cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
    if icon.Icon then icon.Icon:SetShown(not barOnly) end
    if icon.Shade then icon.Shade:SetShown(not barOnly) end
    if icon.Count then
        ApplyGlobalFont(icon.Count, cfg.stackSize)
        PlaceStackText(icon.Count, icon, cfg)
        icon.Count:SetShown(cfg.showStackCount ~= false)
    end
    if icon.CooldownText then
        ApplyGlobalFont(icon.CooldownText, cfg.cooldownSize)
        PlaceCooldownText(icon.CooldownText, icon, cfg)
        icon.CooldownText:SetShown(cfg.showCooldownText ~= false)
    end
    LayoutPreviewSwipe(icon, cfg)
    LayoutPreviewDispelBorder(icon, cfg, index)
    if icon.DurationBar then
        if cfg.showDurationBar == true then
            local height = Clamp(cfg.durationBarHeight, 2, 1, 16)
            local inset = 1
            icon.DurationBar:ClearAllPoints()
            icon.DurationBar:SetHeight(height)
            if cfg.durationBarPosition == "TOP" then
                icon.DurationBar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
                icon.DurationBar:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, -inset)
            else
                icon.DurationBar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
                icon.DurationBar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
            end
            local r, g, b = AuraDurationBarColor()
            icon.DurationBar:SetVertexColor(r, g, b, 0.92)
            icon.DurationBar:Show()
        else
            icon.DurationBar:Hide()
        end
    end
end

local function PreviewAuraState(kind, index, icon, cfg, elapsed)
    local previewAnimation = MSUF and MSUF.PreviewAnimation
    local fn = elapsed ~= nil and (previewAnimation and previewAnimation.BuildAuraState
        or _G.MSUF_BuildPreviewAnimationAuraState)
        or _G.MSUF_GetPreviewAnimationAuraState
    if type(fn) ~= "function" then return nil end
    icon._msufA3PreviewAuraScratch = icon._msufA3PreviewAuraScratch or {}
    local options = icon._msufA3PreviewAuraOptions
    if not options then
        options = {}
        icon._msufA3PreviewAuraOptions = options
    end
    options.decimalThreshold = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3
    if elapsed ~= nil then
        return fn(kind, index, icon._msufA3PreviewAuraScratch, options, elapsed)
    end
    return fn(kind, index, icon._msufA3PreviewAuraScratch, options)
end

local function ApplyPreviewDurationBarProgress(icon, cfg, auraState)
    local bar = icon and icon.DurationBar
    if not (bar and cfg and cfg.showDurationBar == true) then
        if bar then bar:Hide() end
        return
    end
    local size = math_max(1, (icon.GetWidth and icon:GetWidth()) or 1)
    local height = Clamp(cfg.durationBarHeight, 2, 1, math_max(1, size))
    local inset = math_max(1, math_floor(size / 32 + 0.5))
    local frac
    if cfg.durationBarDirection == "ELAPSED" then
        frac = auraState and auraState.elapsedFrac or 1
    else
        frac = auraState and auraState.remainingFrac or 1
    end
    local r, g, b = AuraDurationBarColor()
    bar:SetVertexColor(r, g, b, 0.92)
    frac = math_max(0.02, math_min(1, tonumber(frac) or 1))
    bar:ClearAllPoints()
    bar:SetHeight(height)
    if auraState then
        bar:SetWidth(math_max(1, math_floor(math_max(1, size - inset * 2) * frac + 0.5)))
        if cfg.durationBarPosition == "TOP" then
            bar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
        else
            bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
        end
    elseif cfg.durationBarPosition == "TOP" then
        bar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
        bar:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, -inset)
    else
        bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
        bar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
    end
    bar:Show()
end

local function ApplyPreviewAuraAnimation(group, kind, shownIcons, textCfg, elapsed)
    local icons = group and group._icons
    if not icons then return end
    for i = 1, shownIcons do
        local icon = icons[i]
        if icon then
            local auraState = PreviewAuraState(kind, i, icon, textCfg, elapsed)
            if icon.Count then icon.Count:SetText(textCfg.showStackCount ~= false and (auraState and auraState.stacks or (i == 1 and "3" or "")) or "") end
            if icon.CooldownText then icon.CooldownText:SetText(textCfg.showCooldownText ~= false and (auraState and auraState.text or (i == 1 and "1m" or "32")) or "") end
            LayoutPreviewSwipe(icon, textCfg, auraState and auraState.remainingFrac)
            ApplyPreviewDurationBarProgress(icon, textCfg, auraState)
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
    local group = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    SyncPreviewGroupStrata(group)
    group:SetFrameLevel(900)
    group:SetClampedToScreen(false)
    group:SetMovable(true)
    group:EnableMouse(true)
    if group.SetMouseClickEnabled then group:SetMouseClickEnabled(true) end
    if group.SetMouseMotionEnabled then group:SetMouseMotionEnabled(true) end
    if group.RegisterForClicks then group:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if group.RegisterForDrag then group:RegisterForDrag("LeftButton") end
    group:SetBackdrop({ bgFile = W8, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    group:SetBackdropColor(0.02, 0.03, 0.08, 0.28)
    group:SetBackdropBorderColor(spec.color[1], spec.color[2], spec.color[3], 0.72)

    local header = CreateFrame("Frame", nil, group, "BackdropTemplate")
    header:SetPoint("TOPLEFT", group, "TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", group, "TOPRIGHT", -2, -2)
    header:SetHeight(HEADER_H)
    header:SetBackdrop({ bgFile = W8 })
    header:SetBackdropColor(spec.color[1], spec.color[2], spec.color[3], spec.color[4])
    group.Header = header

    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", header, "LEFT", 6, 0)
    label:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    StyleLabel(label)
    label:SetText(UnitLabel(unit) .. " " .. GroupLabel(unit, kind, spec))
    group.Label = label

    local body = CreateFrame("Frame", nil, group)
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

    local hitbox = CreateFrame("Button", nil, group)
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

--- Edit Mode paints Custom Aura Full-Frame effects through the live renderer,
--- the single owner the frames and the Menu previews already use. The former
--- Edit-Mode-only copy drew Glow as four flat edges instead of the runtime's
--- radial halo, never animated Pulse and carried its own alpha, so the surface
--- you drag disagreed with the result you get. Layer and priority now come from
--- the same Layers.AuraEffectLevel call the live effect uses.
local function ApplyEditModeCustomEffect(group, frame, item)
    local runtime = A3 and A3.SpellIndicators
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
        owner = CreateFrame("Frame", nil, group)
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
    local menu = MSUF and MSUF.MSUF2
    return tostring((menu and (menu._msuf2MenuDataRevision or menu._msuf2LayoutVersion)) or 0)
end

local function RefreshSignature(unit, kind, cfg, metrics, textCfg, shownIcons, size, step, perRow, laneW, laneH, growthX, growthY, vertical, initialAnchor, x, y, anchor, frameSig)
    return tostring(unit) .. "\030" .. tostring(kind) .. "\030" .. tostring(frameSig)
        .. "\030" .. EditModeThemeRevision()
        .. "\030" .. tostring(cfg and cfg.show) .. "\030" .. tostring(metrics and metrics.num or cfg and cfg.max)
        .. "\030" .. tostring(metrics and metrics.layer or cfg and cfg.layer)
        .. "\030" .. tostring(metrics and metrics.spacing or cfg and cfg.spacing)
        .. "\030" .. tostring(metrics and metrics.alpha or cfg and cfg.alpha)
        .. "\030" .. tostring(shownIcons) .. "\030" .. tostring(size)
        .. "\030" .. tostring(step) .. "\030" .. tostring(perRow)
        .. "\030" .. tostring(laneW) .. "\030" .. tostring(laneH)
        .. "\030" .. tostring(growthX) .. "\030" .. tostring(growthY)
        .. "\030" .. tostring(vertical) .. "\030" .. tostring(initialAnchor)
        .. "\030" .. tostring(x) .. "\030" .. tostring(y) .. "\030" .. tostring(anchor)
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

    local auras, shared = EnsureDB()
    -- showInEditMode is an edit-mode-only toggle; the boss page preview keeps
    -- rendering lanes regardless because it is the page's whole purpose.
    if not shared or (EditPreviewActive() and shared.showInEditMode == false)
        or (not UnitEnabled(auras, unit) and not UnitHasCustomPreview(unit)) then
        EM.HideUnit(unit)
        return
    end

    local frame = GetFrame(unit)
    if not frame then
        EM.HideUnit(unit)
        return
    end
    -- Outside edit mode (boss page preview) lanes only make sense on frames the
    -- preview actually shows; edit mode forces its frames visible itself.
    if not EditPreviewActive() and frame.IsShown and not frame:IsShown() then
        EM.HideUnit(unit)
        return
    end

    SetRuntimeAuraHidden(unit, true)
    local frameSig = FrameRefreshSignature(frame)

    local chrome = EditPreviewActive()
    for kind, spec in pairs(GROUPS) do
        local cfg = ReadGroupConfig(unit, kind)
        local metrics = type(A3.BuildAuraLaneMetrics) == "function" and A3.BuildAuraLaneMetrics(unit, kind) or nil
        local group = CreateGroup(unit, kind)
        SyncPreviewGroupStrata(group)
        local entries = spec.customIndex and CustomPreviewEntries(unit, kind) or nil
        -- Target DoTs retain their configuration preview while disabled.
        -- Player Defensives obey their master switch in Edit Mode as well.
        local laneShown = cfg.show
            or (unit ~= "player" and spec.customIndex == 4 and entries ~= nil)
        -- Outside edit mode custom lanes stay strictly 1:1 with the runtime:
        -- nothing tracked means nothing to preview. Placeholder-only custom
        -- lanes exist purely as edit-mode drag surfaces.
        if laneShown and spec.customIndex and not entries and not chrome then laneShown = false end
        if not (laneShown and cfg.max > 0 and (not metrics or metrics.enabled ~= false)) then
            group._msufA3RefreshSignature = nil
            group:Hide()
        else
            -- Existing lanes use the compiler-finalized Runtime contract.
            -- ReadTextConfig remains only for edit-only placeholders that do
            -- not have a compiled lane yet.
            local textCfg = (metrics and metrics.textConfig) or ReadTextConfig(unit, kind)
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
            local step = (metrics and metrics.step) or (cfg.size + cfg.spacing)
            local perRow = (metrics and metrics.perRow) or cfg.perRow
            local fallback
            if not metrics then fallback = FallbackMetrics(cfg) end
            local laneW = (metrics and metrics.width) or (fallback and fallback.width) or cfg.size
            local laneH = (metrics and metrics.height) or (fallback and fallback.height) or cfg.size
            local growthX = (metrics and metrics.growthX) or (fallback and fallback.growthX) or 1
            local growthY = (metrics and metrics.growthY) or (fallback and fallback.growthY) or -1
            local vertical = metrics and metrics.verticalGrowth == true or (fallback and fallback.verticalGrowth == true)
            local initialAnchor = (metrics and metrics.initialAnchor) or (fallback and fallback.initialAnchor) or "TOPLEFT"
            local x = (metrics and metrics.x) or cfg.x
            local y = (metrics and metrics.y) or cfg.y
            local anchor = (metrics and metrics.anchor) or cfg.anchor
            -- Shared icon style + lane padding, 1:1 with the runtime lane. A
            -- bar-only lane renders no icon chrome, so the style stays off.
            local padding = Clamp(metrics and metrics.padding, 0, 0, 16)
            local barOnly = textCfg.showDurationBar == true and textCfg.durationBarDisplay == "BAR_ONLY"
            local appearanceKind = spec.customIndex == 4 and unit == "player" and "playerDefensives"
                or spec.customIndex == 4 and "targetDots"
                or ((kind == "debuff" or cfg.auraType == "DEBUFF") and "debuff" or "buff")
            local iconStyle = (not barOnly) and LaneIconStyle(metrics, unit, appearanceKind) or nil
            local requestedIconShape = (metrics and metrics.requestedIconShape) or cfg.iconShape
            local iconShape = (metrics and metrics.iconShape) or cfg.iconShape or "RECTANGLE"
            if type(A3.ResolveAuraIconShape) == "function" then
                iconShape = A3.ResolveAuraIconShape(requestedIconShape,
                    frame and frame.MSUFSpec and frame.MSUFSpec.portrait and frame.MSUFSpec.portrait.shape)
            end
            textCfg.iconShape = iconShape
            local signature = RefreshSignature(unit, kind, cfg, metrics, textCfg, shownIcons, size, step, perRow, laneW, laneH, growthX, growthY, vertical, initialAnchor, x, y, anchor, frameSig)
                .. "\030" .. CustomPreviewEntriesSignature(entries) .. "\030" .. tostring(chrome)
                .. "\030" .. tostring(padding) .. "\030" .. tostring(iconStyle and iconStyle.signature)

            if group._msufA3RefreshSignature ~= signature or not (group.IsShown and group:IsShown()) then
                group._msufA3RefreshSignature = signature
                if group.SetClampedToScreen then group:SetClampedToScreen(false) end
                ApplyGroupScaleForFrame(group, frame)
                PositionPreviewGroup(group, frame, anchor, x, y, laneW, laneH)
                group:SetSize(laneW, laneH + HEADER_H)
                if group.Body then group.Body:SetSize(laneW, laneH) end
                if group.Body then group.Body:SetAlpha(Clamp(metrics and metrics.alpha or cfg.alpha, 1, 0, 1)) end
                local layers = MSUF.UF and MSUF.UF.Layers
                local layer = (metrics and metrics.layer) or cfg.layer
                group:SetFrameLevel(layers and layers.ElementLevel and layers.ElementLevel(layer, 5, 0)
                    or (900 + Clamp(layer, 5, 0, 30)))
                if group.Hitbox and group.Hitbox.SetFrameLevel then
                    group.Hitbox:SetFrameLevel((group:GetFrameLevel() or 0) + 20)
                end
                if group.Label then
                    group.Label:SetText(UnitLabel(unit) .. " " .. GroupLabel(unit, kind, spec))
                    StyleLabel(group.Label)
                end
                ApplyGroupChrome(group, spec, chrome)

                local padX, padY = PaddingInset(initialAnchor, padding)
                for i = 1, shownIcons do
                    local icon = EnsureIcon(group, i)
                    icon:SetSize(size, size)
                    icon:ClearAllPoints()
                    local col, row = IconGridCoord(i, perRow, vertical)
                    local body = group.Body or group
                    icon:SetPoint(initialAnchor, body, initialAnchor, col * step * growthX + padX, row * step * growthY + padY)
                    if icon.Icon then
                        local entry = entries and entries[i]
                        icon.Icon:SetTexture((entry and entry.icon) or cfg.texture or spec.texture)
                        ApplyIconZoom(icon.Icon, metrics and metrics.iconZoom or cfg.iconZoom)
                    end
                    if type(A3.ApplyAuraIconShape) == "function" then
                        A3.ApplyAuraIconShape(icon, iconShape, nil, icon.Icon, icon.Shade, icon.Swipe)
                    end
                    if icon.Count then icon.Count:SetText(i == 1 and "3" or "") end
                    if icon.CooldownText then icon.CooldownText:SetText(i == 1 and "1m" or "32") end
                    ApplyPreviewIconText(icon, unit, textCfg, i)
                    if type(A3.ApplyIconStylePreview) == "function" then
                        A3.ApplyIconStylePreview(icon, iconStyle, size, iconShape)
                    end
                    icon:Show()
                end

                local icons = group._icons
                if icons then
                    for i = shownIcons + 1, #icons do
                        if icons[i] then icons[i]:Hide() end
                    end
                end
            end

            -- Cache the already-resolved lane state so Menu2's existing
            -- animation tick can advance only these visible regions.  It must
            -- not rerun DB reads, metrics, anchoring, or a full RefreshUnit at
            -- 20 Hz merely to keep Edit Mode in phase with the menu preview.
            group._msufA3AnimationKind = kind
            group._msufA3AnimationShownIcons = shownIcons
            group._msufA3AnimationTextConfig = textCfg
            ApplyPreviewAuraAnimation(group, kind, shownIcons, textCfg)
            if spec.customIndex then ApplyEditModeCustomEffect(group, frame, CustomItem(unit, spec.customIndex, false)) end
            group:Show()
            if group.Raise then group:Raise() end
        end
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
