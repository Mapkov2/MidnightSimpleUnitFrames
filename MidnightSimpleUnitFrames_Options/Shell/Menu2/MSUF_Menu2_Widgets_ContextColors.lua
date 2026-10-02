local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Shell/Menu2/MSUF_Menu2_Widgets_ContextColors.lua
--- Card-local color shortcuts: the three-dot entry point on a card or an
--- accordion header that opens the colors used in that area, and the binding of
--- a color control to its card's shortcut.
---
--- Split from MSUF_Menu2_Widgets.lua; loads after the buttons.

local addonName, MSUF = ...
MSUF = MSUF or {}
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local M = MSUF.MSUF2
local T = M.Theme
local W = M.Widgets
local Shared = W._Shared
local max = math.max

-- A deliberately quiet, card-local entry point for related colors. Target
-- resolution and virtual picker owners are both click-only: constructing or
-- idling Menu2 adds no refresh loop, event, timer, or gameplay work.
local CONTEXT_COLOR_SHORTCUT_TEXT = "|cffff625f•|r|cff61d683•|r|cff5aa7ff•|r"
local THREE_DOT_SHORTCUT_TEXTURE = (T.media and T.media.switchKnob)
    or ("Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\msuf_switch_knob.tga")
local COLOR_SHORTCUT_DOTS = {
    { 1.000, 0.384, 0.373 },
    { 0.380, 0.839, 0.514 },
    { 0.353, 0.655, 1.000 },
}
local LAYER_SHORTCUT_DOTS = {
    { 1, 1, 1 },
    { 1, 1, 1 },
    { 1, 1, 1 },
}

local function AddThreeDotShortcutTextures(shortcut, colors)
    if not (shortcut and shortcut.CreateTexture and type(colors) == "table") then return end
    if shortcut._msuf2Label and shortcut._msuf2Label.Hide then
        shortcut._msuf2Label:Hide()
        -- The dots are textures from here on; the button's own bullet label is
        -- decoration that must never come back. SetControlShown re-shows
        -- _msuf2Label for ordinary controls, which would paint the coloured
        -- bullets on top of - and offset from - the textures.
        shortcut._msuf2Label._msuf2AlwaysHidden = true
    end
    local dots = {}
    for i = 1, 3 do
        local color = colors[i] or LAYER_SHORTCUT_DOTS[i]
        local dot = PixelLayoutRegion(shortcut:CreateTexture(nil, "ARTWORK", nil, 4))
        dot:SetTexture(THREE_DOT_SHORTCUT_TEXTURE)
        dot:SetSize(5, 5)
        dot:SetPoint("CENTER", shortcut, "CENTER", (i - 2) * 7, 0)
        dot:SetVertexColor(color[1], color[2], color[3], 1)
        dots[i] = dot
    end
    shortcut._msuf2ThreeDotTextures = dots
end

W.StyleSectionActionButton = function(button) AddThreeDotShortcutTextures(button, LAYER_SHORTCUT_DOTS) end

local function ResolveContextColorOption(value, fallback)
    if type(value) == "function" then value = value() end
    if value == nil or value == "" then return fallback end
    return value
end

local function ContextColorShortcutContext(card)
    local parent = card
    for _ = 1, 12 do
        if not parent then break end
        local entry = parent._msuf2CollapsibleEntry
        if entry and entry.builder and entry.builder.ctx then return entry.builder.ctx end
        parent = parent.GetParent and parent:GetParent()
    end
    return nil
end

local function TrackContextColorShortcutVisibility(card, shortcut)
    if not (card and shortcut) or shortcut._msuf2ContextColorVisibilityTracked == true then return end
    local refresh = function()
        if shortcut and shortcut._msuf2RefreshContextColorVisibility then shortcut:_msuf2RefreshContextColorVisibility() end
    end
    local ctx = ContextColorShortcutContext(card)
    if ctx and type(M.TrackRefresh) == "function" then
        shortcut._msuf2ContextColorVisibilityTracked = true
        local deferred = ctx._msuf2Building == true
            or (ctx.entry and ctx.entry._msuf2Building == true)
            or ctx.hiddenBuild == true
            or (ctx.entry and ctx.entry.hiddenBuild == true)
        M.TrackRefresh(ctx, refresh)
        if deferred then refresh() end
    else
        refresh()
    end
end

local function ContextColorVirtualOwner(spec, opts)
    if type(spec) ~= "table" then return nil end
    if type(spec.GetRGB) == "function" and type(spec.SetRGB) == "function" then return spec end
    local getRGB = spec.getRGB or spec.get
    local setRGB = spec.setRGB or spec.set
    if type(getRGB) ~= "function" or type(setRGB) ~= "function" then return nil end

    local owner = {
        _msuf2ColorLabel = spec.label or "Color",
        _msuf2ColorHasOpacity = spec.hasOpacity == true,
        _msuf2GetColorByClass = spec.getColorByClass,
        _msuf2SetColorByClass = spec.setColorByClass,
    }
    function owner:GetRGB()
        local r, g, b = getRGB()
        return tonumber(r) or tonumber(spec.defaultR) or 1,
            tonumber(g) or tonumber(spec.defaultG) or 1,
            tonumber(b) or tonumber(spec.defaultB) or 1
    end
    function owner:SetRGB(r, g, b)
        self._msuf2R, self._msuf2G, self._msuf2B = tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1
    end
    function owner:IsEnabled()
        return type(spec.isEnabled) ~= "function" or spec.isEnabled() ~= false
    end
    owner._msuf2OnColorChanged = function(r, g, b, alpha)
        if M.BlockCombatAction and M.BlockCombatAction() then return end
        setRGB(r, g, b, alpha)
    end
    if spec.hasOpacity == true and type(spec.getOpacity) == "function" then
        owner._msuf2GetColorOpacity = function() return spec.getOpacity() end
    end
    if type(spec.captureState) == "function" and type(spec.restoreState) == "function" then
        owner._msuf2CaptureColorState = function() return spec.captureState() end
        owner._msuf2RestoreColorState = function(_, state) spec.restoreState(state) end
    end
    function owner:_msuf2BeginColorInteraction()
        if type(M.BeginHistoryTransaction) ~= "function" then return end
        local label = spec.historyLabel or opts.historyLabel or ((spec.label or "Color") .. " color")
        local source = opts.historySource or "menu:context-color-shortcut"
        self._msuf2ContextColorHistoryActive = M.BeginHistoryTransaction(label, source) == true
    end
    function owner:_msuf2CommitColorInteraction()
        if not self._msuf2ContextColorHistoryActive then return end
        self._msuf2ContextColorHistoryActive = nil
        if type(M.CommitHistoryTransaction) == "function" then M.CommitHistoryTransaction() end
    end
    return owner
end

function W.OpenContextColors(card, opts, resolvedTargets, onFinish)
    opts = opts or {}
    local targets = resolvedTargets or ResolveContextColorOption(opts.getTargets or opts.targets, {})
    if type(targets) ~= "table" then return false end
    local owners, maxTargets = {}, math.max(1, tonumber(opts.maxTargets) or 4)
    -- Never hide a setting silently. Curated contextual mappings stay at four
    -- unless the card's subject genuinely is a list -- group resource colors
    -- are one per power type -- in which case it states its own bound. An
    -- oversized mapping that never asked for the room must be fixed at its
    -- source instead of opening an incomplete picker.
    if #targets > maxTargets then return false end
    for i = 1, #targets do
        local owner = ContextColorVirtualOwner(targets[i], opts)
        if owner and (owner._msuf2ContextColorAllowDisabled == true
            or not owner.IsEnabled or owner:IsEnabled())
        then
            owners[#owners + 1] = owner
        end
    end
    if #owners == 0 or type(W.OpenColorContextPicker) ~= "function" then return false end
    local fallbackTitle = card and card._msuf2ControlCardTitle or "Colors"
    local title = ResolveContextColorOption(opts.title, fallbackTitle)
    local note = ResolveContextColorOption(opts.note, nil)
    local scopeTag = ResolveContextColorOption(opts.scopeTag, nil)
    W.OpenColorContextPicker(title, owners, note, owners[1], onFinish, scopeTag)
    return true
end

local function ContextColorShortcutsSuppressed(card)
    local frame = card
    for _ = 1, 16 do
        if not frame then break end
        if frame._msuf2SuppressContextColorShortcuts == true then return true end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
end

function W.AttachContextColorShortcut(card, opts)
    if not card then return nil end
    -- The canonical Colors page already exposes the color controls directly.
    -- Its contextual shortcut would only reopen the same picker and add noise.
    if ContextColorShortcutsSuppressed(card) then return nil end
    opts = opts or {}
    if card._msuf2ContextColorShortcut then
        local existing = card._msuf2ContextColorShortcut
        existing._msuf2ContextColorOptions = opts
        if opts.isRelevant ~= nil then TrackContextColorShortcutVisibility(card, existing) end
        if existing._msuf2RefreshContextColorVisibility then existing:_msuf2RefreshContextColorVisibility() end
        return existing
    end

    local shortcut = T.Button(card, CONTEXT_COLOR_SHORTCUT_TEXT, 34, 20, { noSearch = true })
    shortcut._msuf2SkipHistoryCheckpoint = true
    shortcut._msuf2ContextColorOptions = opts
    shortcut:ClearAllPoints()
    shortcut:SetPoint("TOPRIGHT", card, "TOPRIGHT", tonumber(opts.offsetX) or -12, tonumber(opts.offsetY) or -10)
    shortcut:SetFrameLevel((card.GetFrameLevel and card:GetFrameLevel() or 1) + 3)
    shortcut:SetAlpha(0.58)
    AddThreeDotShortcutTextures(shortcut, COLOR_SHORTCUT_DOTS)
    shortcut:HookScript("OnEnter", function(self) self:SetAlpha(0.96) end)
    shortcut:HookScript("OnLeave", function(self) self:SetAlpha(0.58) end)
    function shortcut:_msuf2RefreshContextColorVisibility()
        local options = self._msuf2ContextColorOptions or {}
        local relevant = ResolveContextColorOption(options.isRelevant, true) ~= false
        if self.SetShown then self:SetShown(relevant)
        elseif relevant and self.Show then self:Show()
        elseif not relevant and self.Hide then self:Hide() end
        return relevant
    end
    shortcut:SetScript("OnClick", function(self)
        if M.BlockCombatAction and M.BlockCombatAction() then return end
        if self._msuf2RefreshContextColorVisibility and not self:_msuf2RefreshContextColorVisibility() then return end
        local options = self._msuf2ContextColorOptions or {}
        if options.textSettings and type(W.OpenTextQuickSettings) == "function" then
            W.OpenTextQuickSettings(self, options)
            return
        end
        W.OpenContextColors(card, options)
    end)
    if M.AddTooltip then
        local tooltipTitle = opts.tooltipTitle or (opts.textSettings and "Text quick settings" or "Colors")
        local tooltipText = opts.tooltipText
            or (opts.textSettings and "Open the fonts and colors used in this area." or "Open the colors used in this area.")
        M.AddTooltip(shortcut, tooltipTitle, tooltipText, { hook = true })
    end
    if card.title and card.title.SetWidth then
        card.title:SetWidth(max(24, (tonumber(card._msuf2Width) or 360) - 70))
    end
    card._msuf2ContextColorShortcut = shortcut
    if opts.isRelevant ~= nil then TrackContextColorShortcutVisibility(card, shortcut) end
    return shortcut
end

-- Cross-page color references stay declarative at their feature card.  The
-- canonical resolver lives with Advanced Colors and is deliberately invoked
-- only by the shortcut click, so unopened popups and normal gameplay never
-- pay for target construction or color reads.
function W.AttachContextColorReferences(card, references, opts)
    if not card then return nil end
    opts = opts or {}
    local options = {}
    for key, value in pairs(opts) do options[key] = value end
    if options.isRelevant == nil then
        options.isRelevant = function()
            local resolvedReferences = ResolveContextColorOption(options.references or references, {})
            local count = type(resolvedReferences) == "table" and #resolvedReferences or 0
            local maxTargets = math.max(1, tonumber(options.maxTargets) or 4)
            return count > 0 and count <= maxTargets
        end
    end
    options.getTargets = function()
        local resolver = M.ResolveContextColorReferences
        if type(resolver) ~= "function" then return {} end
        local resolvedReferences = ResolveContextColorOption(options.references or references, {})
        local resolvedContext = ResolveContextColorOption(options.context, {})
        return resolver(resolvedReferences, resolvedContext)
    end
    options.references = nil
    local shortcut = W.AttachContextColorShortcut(card, options)
    -- An explicit semantic mapping owns this card. A later generic BindColor
    -- must not replace its curated 1-4 target set merely because controls are
    -- laid out after the card shortcut was attached.
    if shortcut then shortcut._msuf2BoundColorShortcut = nil end
    return shortcut
end

local function PositionedContextColorCard(parent, x, y)
    local cards = parent and parent._msuf2ControlCards
    x, y = tonumber(x), tonumber(y)
    if type(cards) ~= "table" or x == nil or y == nil then return nil end
    local best, bestArea
    for i = 1, #cards do
        local card = cards[i]
        local left = tonumber(card and card._msuf2ContextColorLeft)
        local top = tonumber(card and card._msuf2ContextColorTop)
        local width = tonumber(card and card._msuf2ContextColorWidth)
        local height = tonumber(card and card._msuf2ContextColorHeight)
        if left and top and width and height
            and x >= left and x <= left + width
            and y <= top and y >= top - height
        then
            local area = width * height
            if not bestArea or area < bestArea then best, bestArea = card, area end
        end
    end
    return best
end

local function AttachBoundColorToContextCard(colorControl)
    local card = colorControl and colorControl._msuf2ContextColorCardOverride
    local parent = colorControl and colorControl.GetParent and colorControl:GetParent()
    local nearestHost
    if not card then
        for _ = 1, 12 do
            if not parent then break end
            if parent._msuf2ControlCard then card = parent; break end
            if not nearestHost and parent._msuf2ContextColorHost then nearestHost = parent end
            parent = parent.GetParent and parent:GetParent()
        end
    end
    if not card then
        local layoutParent = colorControl and colorControl._msuf2ContextLayoutParent
        card = PositionedContextColorCard(layoutParent,
            colorControl and colorControl._msuf2ContextLayoutX,
            colorControl and colorControl._msuf2ContextLayoutY)
    end
    -- Cards with sibling controls are resolved after W.MoveWidget records the
    -- final position. Until then, do not attach the color to the outer body.
    if not card and nearestHost and type(nearestHost._msuf2ControlCards) == "table"
        and #nearestHost._msuf2ControlCards > 0
        and not (colorControl and colorControl._msuf2ContextLayoutParent)
    then
        return false
    end
    card = card or nearestHost
    if not card then return false end
    local existingShortcut = card._msuf2ContextColorShortcut
    if existingShortcut and existingShortcut._msuf2BoundColorShortcut ~= true then return false end
    card._msuf2ContextColorOwners = card._msuf2ContextColorOwners or {}
    card._msuf2ContextColorOwnerKeys = card._msuf2ContextColorOwnerKeys or {}
    local command = colorControl._msuf2CommandAction
    local settingKey = command and tostring(command.settingKey or "") or ""
    local identity = settingKey ~= "" and ("setting:" .. settingKey) or colorControl
    if not card._msuf2ContextColorOwnerKeys[identity] then
        card._msuf2ContextColorOwnerKeys[identity] = true
        card._msuf2ContextColorOwners[#card._msuf2ContextColorOwners + 1] = colorControl
    end
    if #card._msuf2ContextColorOwners > 4 then
        card._msuf2ContextColorOverflow = true
        if existingShortcut and existingShortcut.Hide then existingShortcut:Hide() end
        return true
    end
    local shortcut = W.AttachContextColorShortcut(card, {
        title = function()
            return card._msuf2ControlCardTitle or card._msuf2ContextColorHostTitle or "Colors"
        end,
        getTargets = function() return card._msuf2ContextColorOwners end,
        isRelevant = function()
            local owners = card._msuf2ContextColorOwners or {}
            if card._msuf2ContextColorOverflow == true or #owners == 0 or #owners > 4 then return false end
            for i = 1, #owners do
                local owner = owners[i]
                if owner and (owner._msuf2ContextColorAllowDisabled == true
                    or not owner.IsEnabled or owner:IsEnabled())
                then
                    return true
                end
            end
            return false
        end,
        historySource = "menu:card-colors",
        maxTargets = 4,
    })
    if shortcut then
        shortcut._msuf2BoundColorShortcut = true
        if colorControl.HookScript and not colorControl._msuf2ContextShortcutEnableHooks then
            colorControl._msuf2ContextShortcutEnableHooks = true
            colorControl:HookScript("OnEnable", function()
                if shortcut._msuf2RefreshContextColorVisibility then shortcut:_msuf2RefreshContextColorVisibility() end
            end)
            colorControl:HookScript("OnDisable", function()
                if shortcut._msuf2RefreshContextColorVisibility then shortcut:_msuf2RefreshContextColorVisibility() end
            end)
        end
    end
    return true
end


--- Register every bound color for its nearest visible content surface and for
--- picker grouping. Accordion headers intentionally stay clean: the only
--- automatic entry point is the quiet RGB shortcut inside the opened card.
--- This is cold Menu2 construction only; it adds no gameplay/combat work.
function W.AttachBoundColorToCollapsible(ctx, colorControl)
    if not colorControl then return false end
    colorControl._msuf2ContextColorBound = true
    local contextAttached = AttachBoundColorToContextCard(colorControl)
    if colorControl._msuf2CollapsibleColorContextAttached then return contextAttached end
    local parent = colorControl.GetParent and colorControl:GetParent()
    local section, entry
    for _ = 1, 12 do
        if not parent then break end
        entry = parent._msuf2CollapsibleEntry
        if entry then section = entry.body or parent; break end
        parent = parent.GetParent and parent:GetParent()
    end
    if not (section and entry) then return contextAttached end
    colorControl._msuf2CollapsibleColorContextAttached = true
    local contextEntry = entry
    while contextEntry.ancestorEntry do contextEntry = contextEntry.ancestorEntry end
    contextEntry._msuf2ColorContextOwners = contextEntry._msuf2ColorContextOwners or {}
    contextEntry._msuf2ColorContextOwners[#contextEntry._msuf2ColorContextOwners + 1] = colorControl
    colorControl._msuf2ColorContextOwners = contextEntry._msuf2ColorContextOwners
    AttachBoundColorToContextCard(colorControl)
    return true
end
W.ResolveContextColorOption = ResolveContextColorOption
Shared.LAYER_SHORTCUT_DOTS = LAYER_SHORTCUT_DOTS
Shared.AddThreeDotShortcutTextures = AddThreeDotShortcutTextures
Shared.AttachBoundColorToContextCard = AttachBoundColorToContextCard
