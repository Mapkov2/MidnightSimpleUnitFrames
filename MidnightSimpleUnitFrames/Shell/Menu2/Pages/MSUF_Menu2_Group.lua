local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Group page foundation.
-- Owns party/raid/mythicraid option binding, preview sync, and page-local batching. Secure
-- header creation/rebuilds remain in the GroupFrames runtime and are only requested here.
local W = M.Widgets
local T = M.Theme
local ControlGates = M.ControlGates or {}
local Shared = M.UnitSectionsShared or {}
local VT = M.ValueTextList
local WL = M.WordList
local floor = math.floor
local max = math.max
local min = math.min
local Specs = M.GroupSpecs or {}
local SCOPE_VALUES, GROWTH_VALUES, BLIZZARD_FALLBACK_VALUES, HEALTH_MODES, TEXT_MODES, DELIMITER_VALUES, ANCHORS, AURA_ANCHORS, SORT_MODES, GF_BAR_MODES, GF_ANCHOR_TO, GF_ANCHOR_POINTS, STATUS_ICON_ANCHORS, GF_STATUS_ICON_SPECS, GF_STATUS_ICON_VALUES, PLACED_INDICATOR_TYPES, FRAME_EFFECT_TYPES, SPELL_GROWTH_VALUES, CI_SLOT_VALUES, CI_SLOT_DEFAULTS, DISPEL_OVERLAY_STYLES, DEBUFF_STRIPE_EDGES = M.PickDefaults(Specs, M.GROUP_SPEC_TABLE_KEYS)
local SIMPLE_TEXTURES = Specs.SimpleTextures or function() return {} end
local pendingGF = {}
local gfFlushQueued = false
local GF_APPLY_DELAY = 0.04
local SCOPE_LABELS = { party = "Party", raid = "Raid", mythicraid = "Mythic Raid" }
local SCOPE_SHORT_LABELS = { mythicraid = "Mythic" }
local GROUP_SECTION_HEADER_BG = { 0.060, 0.070, 0.130, 0.48 }
local GF_INDICATOR_COPY_FIELDS = M.CopyFieldsFromSpecs(GF_STATUS_ICON_SPECS, "pvpIcon statusText statusGhostText statusAFKText",
    [[showGroupNumber groupNumberSize groupNumberAnchor groupNumberX groupNumberY groupBorderEnabled groupBorderSize groupBorderPadding groupBorderR groupBorderG groupBorderB groupBorderA iconStyle useMidnightIcons roleIconStyle leaderIconStyle assistIconStyle raidMarkerStyle readyCheckIconStyle summonIconStyle resurrectIconStyle pvpIconStyle phaseIconStyle roleIconCustomIcon leaderIconCustomIcon assistIconCustomIcon raidMarkerCustomIcon readyCheckIconCustomIcon summonIconCustomIcon resurrectIconCustomIcon pvpIconCustomIcon phaseIconCustomIcon]], "enabled iconStyle customIcon size anchor x y layer")
local function GF()
    return MSUF and MSUF.GF
end
local function GroupProfileStart()
    return M.PerfProfile and M.PerfProfile.enabled == true and M.ProfileStart and M.ProfileStart() or nil
end
local function GroupProfileStop(key, started, extraCount)
    if M.PerfProfile and M.PerfProfile.enabled == true and M.ProfileStop then
        M.ProfileStop("groupPage", key, started, extraCount)
    end
end
local function RequestGFPagePreview()
    if type(M.RequestGFPagePreviewForKey) == "function" then
        return M.RequestGFPagePreviewForKey(M.activeKey)
    end
    if type(M.SyncGFPagePreviewForKey) == "function" then
        return M.SyncGFPagePreviewForKey(M.activeKey)
    end
end
local function RefreshGFPreview(kind)
    -- Preview and live group frames have separate render paths. Refresh both when controls
    -- change so the page does not hide a stale runtime configuration.
    local gf = GF()
    if gf and type(gf.RefreshPreviewLayout) == "function" then
        local started = GroupProfileStart()
        gf.RefreshPreviewLayout(kind)
        GroupProfileStop("GF.RefreshPreviewLayout", started)
    end
    if type(M.RefreshGFNativePreviews) == "function" then
        local started = GroupProfileStart()
        M.RefreshGFNativePreviews("GF_PAGE_REFRESH")
        GroupProfileStop("M.RefreshGFNativePreviews", started)
    end
    if type(M.RequestGFPagePreviewForKey) == "function" or type(M.SyncGFPagePreviewForKey) == "function" then
        local started = GroupProfileStart()
        RequestGFPagePreview()
        GroupProfileStop("M.RequestGFPagePreviewForKey", started)
    end
end
local function Conf(kind)
    local gf = GF()
    if gf and type(gf.GetConf) == "function" then return gf.GetConf(kind) end
    local db = M.EnsureDB()
    local key = kind == "raid" and "gf_raid" or (kind == "mythicraid" and "gf_mythicraid" or "gf_party")
    db[key] = db[key] or {}
    return db[key]
end
local function Val(kind, key, default)
    local gf = GF()
    if gf and type(gf.Val) == "function" then
        local value = gf.Val(kind, key)
        if value ~= nil then return value end
    end
    local conf = Conf(kind)
    if conf[key] ~= nil then return conf[key] end
    return default
end
local function FlushGF()
    gfFlushQueued = false
    local started = GroupProfileStart()
    local gf = GF()
    if not gf then
        GroupProfileStop("FlushGF", started)
        return
    end
    local rebuild = pendingGF.rebuild
    local geometry = pendingGF.geometry
    local visual = pendingGF.visual
    local font = pendingGF.font
    local auras = pendingGF.auras
    local kind = pendingGF.kind
    pendingGF.rebuild = nil
    pendingGF.geometry = nil
    pendingGF.visual = nil
    pendingGF.font = nil
    pendingGF.auras = nil
    pendingGF.kind = nil
    if kind == false then kind = nil end
    if InCombatLockdown and InCombatLockdown() then
        if rebuild and type(gf.RebuildAll) == "function" then gf.RebuildAll() end
        if geometry then gf._pendingRefreshGeometry = true end
        if auras and type(gf.DeferGroupRuntime) == "function" then gf.DeferGroupRuntime("refresh", kind, gf.DIRTY_AURAS) end
        if font or visual or auras then gf._pendingRefreshVisuals = true end
        RefreshGFPreview(kind)
        GroupProfileStop("FlushGF", started)
        return
    end
    if rebuild and type(gf.RebuildAll) == "function" then
        gf.RebuildAll()
        RefreshGFPreview()
        GroupProfileStop("FlushGF", started)
        return
    end
    if geometry then
        if type(gf.RefreshGeometry) == "function" then gf.RefreshGeometry() end
    end
    if font and type(gf.RefreshFonts) == "function" then gf.RefreshFonts(kind) end
    if auras and type(gf.RefreshVisuals) == "function" then gf.RefreshVisuals(kind, gf.DIRTY_AURAS) end
    if visual then
        if type(gf.RefreshVisuals) == "function" then gf.RefreshVisuals(kind) end
    end
    RefreshGFPreview(kind)
    GroupProfileStop("FlushGF", started)
end
local function QueueGF(kind, mode)
    if kind ~= nil then
        if pendingGF.kind == nil then
            pendingGF.kind = kind
        elseif pendingGF.kind ~= kind then
            pendingGF.kind = false
        end
    end
    if mode == "rebuild" then pendingGF.rebuild = true end
    if mode == "geometry" then pendingGF.geometry = true end
    if mode == "visual" then pendingGF.visual = true end
    if mode == "font" then pendingGF.font = true end
    if mode == "auras" then pendingGF.auras = true end
    if gfFlushQueued then return end
    gfFlushQueued = true
    if type(_G.MSUF_ScheduleDelayOnce) == "function" then
        _G.MSUF_ScheduleDelayOnce("MSUF2_GF_APPLY", GF_APPLY_DELAY, FlushGF)
    elseif type(_G.MSUF_ScheduleOnce) == "function" then
        _G.MSUF_ScheduleOnce("MSUF2_GF_APPLY", FlushGF)
    elseif _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(GF_APPLY_DELAY, FlushGF)
    else
        FlushGF()
    end
end
local function Set(kind, key, value, mode)
    local function Write()
        local conf = Conf(kind)
        local textureKey = key == "barTexture" or key == "barBackgroundTexture" or key == "barBgTexture"
        local activatesTextureOverride = textureKey and type(value) == "string" and value ~= "" and conf.hlOverride ~= true
        if conf[key] == value and not activatesTextureOverride then return false end
        conf[key] = value
        if activatesTextureOverride then
            conf.hlOverride = true
        end
        QueueGF(kind, mode or "visual")
        return true
    end
    return M.RunWithHistory("Group " .. tostring(key), "group:" .. tostring(kind) .. ":" .. tostring(key), Write)
end
local function Bool(kind, key, default)
    local value = Val(kind, key, default and true or false)
    return value and true or false
end
local function Num(kind, key, default)
    return tonumber(Val(kind, key, default)) or default or 0
end
local function CurrentScope()
    return M.gfScope or "party"
end
local function ScopeLabel(kind)
    return M.Tr(SCOPE_LABELS[kind] or "Party")
end
local function ScopeShortLabel(kind)
    return M.Tr(SCOPE_SHORT_LABELS[kind] or SCOPE_LABELS[kind] or "Party")
end
local GF_COPY_EXCLUDE = M.KeySetFromWords "offsetX offsetY point positionMode _hlMigrated"
local GF_COPY_CATEGORIES = {
    { key = "general", label = "Basics", keys = WL [[enabled blizzardFallbackMode showPlayer showSolo clickCastEnabled width height spacing growth groupFilter sortMode sortByRole roleOrder playerFirstInRole unitsPerColumn maxColumns preserveRaidGroups reverseFill smoothFill hideInClientScene hideInHousing hideOfflineEnabled hideOfflineInCombat hideOfflineDelay frameScaleMode frameScaleManual scaleAt10 scaleAt20 scaleAt25 scaleOver25]] },
    { key = "health", label = "Health & Bars", keys = WL [[gfBarMode healthColorMode healthCustomR healthCustomG healthCustomB gfDarkR gfDarkG gfDarkB gfUnifiedR gfUnifiedG gfUnifiedB barTexture barBgTexture powerBarEnabled powerHeight showPower showPowerText powerTextLeft powerTextCenter powerTextRight powerTextLeftHidePercentSymbol powerTextCenterHidePercentSymbol powerTextRightHidePercentSymbol powerTextDelimiter powerFontSize powerOffsetX powerOffsetY powerTextLayer powerSmoothFill powerShowTank powerShowHealer powerShowDamager dispelOverlayEnabled dispelOverlayStyle dispelOverlayOnHealth dispelOverlayAlpha dispelOverlayTrigger deadBgEnabled deadBgOffline deadBgR deadBgG deadBgB deadBgA]] },
    { key = "text", label = "Text & Name", keys = WL [[showName hideNameOnDeadOffline nameFontSize nameAnchor nameOffsetX nameOffsetY nameTextLayer nameColorMode nameColorR nameColorG nameColorB nameShortenEnabled nameClipSide nameMaxChars nameNoEllipsis showHPText hpFontSize textLeft textCenter textRight hpTextLeftHidePercentSymbol hpTextCenterHidePercentSymbol hpTextRightHidePercentSymbol textDelimiter hpTextReverse healthTextDecimals hpOffsetX hpOffsetY textLayer]] },
    { key = "font", label = "Font Override", keys = WL [[fontOverride fontOutline useGlobalFontColor fontR fontG fontB]] },
    { key = "border", label = "Background & Opacity", keys = WL [[bgR bgG bgB hpBarAlpha hpBgAlpha alphaExcludeTextPortrait]] },
    { key = "range", label = "Range Fade", keys = WL [[rangeFadeEnabled rangeFadeAlpha rangeFadeLayerMode offlineAlpha]] },
    { key = "indicators", label = "Status & Indicators", keys = GF_INDICATOR_COPY_FIELDS, prefix = WL [[si_ statusIcon indicator]] },
    { key = "auras", label = "Auras", tables = WL [[auras]] },
    { key = "highlight", label = "Highlight & Aggro", keys = WL [[targetIndicator targetR targetG targetB aggroMode]], prefix = WL [[hl dispel]] },
    { key = "dstripe", label = "Debuff Stripe", prefix = WL [[debuffStripe]] },
    { key = "features", label = "Corner/Spell", keys = WL [[ciEnabled ciAlpha]], tables = WL [[spellIndicators]], prefix = WL [[ci]] },
}
local function DeepCopy(value)
    local gf = GF()
    if gf and type(gf._DeepCopyTable) == "function" then return gf._DeepCopyTable(value) end
    if type(_G.MSUF_DeepCopy) == "function" then return _G.MSUF_DeepCopy(value) end
    return M.DeepCopy(value)
end
local function NewGFCopyScopes()
    local scopes = {}
    for i = 1, #GF_COPY_CATEGORIES do
        scopes[GF_COPY_CATEGORIES[i].key] = true
    end
    return scopes
end
local function CopyGroupSettings(srcKind, dstKind, scopes)
    local srcConf = Conf(srcKind)
    local dstConf = Conf(dstKind)
    if not (srcConf and dstConf and srcKind and dstKind) or srcKind == dstKind then return false end
    scopes = (type(scopes) == "table") and scopes or NewGFCopyScopes()
    local allowKeys, allowPrefixes, allowTables = {}, {}, {}
    for i = 1, #GF_COPY_CATEGORIES do
        local cat = GF_COPY_CATEGORIES[i]
        if scopes[cat.key] then
            if cat.keys then
                for j = 1, #cat.keys do allowKeys[cat.keys[j]] = true end
            end
            if cat.prefix then
                for j = 1, #cat.prefix do allowPrefixes[#allowPrefixes + 1] = cat.prefix[j] end
            end
            if cat.tables then
                for j = 1, #cat.tables do allowTables[cat.tables[j]] = true end
            end
        end
    end
    for key, value in pairs(srcConf) do
        if not GF_COPY_EXCLUDE[key] then
            local copy = allowKeys[key] or allowTables[key]
            if (not copy) and type(key) == "string" then
                for i = 1, #allowPrefixes do
                    local prefix = allowPrefixes[i]
                    if key:sub(1, #prefix) == prefix then
                        copy = true
                        break
                    end
                end
            end
            if copy then dstConf[key] = DeepCopy(value) end
        end
    end
    QueueGF(dstKind, "rebuild")
    RefreshGFPreview()
    return true
end
local function RefreshContext(ctx)
    if M.RequestRefresh then return M.RequestRefresh(ctx, "gf-context") end
    if not (ctx and ctx.refreshers) then return end
    for i = 1, #ctx.refreshers do
        local fn = ctx.refreshers[i]
        if type(fn) == "function" then fn() end
    end
end
local function SetSectionHeaderStatus(sec, opts)
    if not Shared.SetSectionHeaderStatus then return end
    if not (opts and opts.bg) then opts = M.Assign({ bg = GROUP_SECTION_HEADER_BG }, opts) end
    Shared.SetSectionHeaderStatus(sec, opts)
end
local function SetSectionBadges(sec, specs)
    if W and W.SetCollapsibleBadges then
        if sec then sec._msuf2CollapsibleBadgesOnlyWhenOpen = true end
        W.SetCollapsibleBadges(sec, specs or {})
    end
end
local function SetSectionBadgesAndStatus(sec, specs, status)
    SetSectionBadges(sec, specs)
    SetSectionHeaderStatus(sec, status)
end
local TrackSectionRefresh = M.TrackCollapsibleRefresh
local ApplyScopeEnabledGate
local function FinalizeScopePage(ctx, builder)
    if type(ApplyScopeEnabledGate) == "function" then M.TrackRefresh(ctx, function() ApplyScopeEnabledGate(ctx) end) end
    if ctx and ctx.SetContentHeight and builder then ctx:SetContentHeight(math.abs(builder.y) + 42) end
end
local OnOffBadge, BadgeNumber, OptionText = M.OnOffBadge, M.BadgeNumber, M.OptionText
local function CreateSectionNotice(sec, topY, buttonLabel, buttonWidth)
    return Shared.CreateSectionNotice(sec, topY, buttonLabel, buttonWidth, "_msuf2GroupFrameGateAlwaysEnabled")
end
local function ScopeSection(ctx, builder)
    local compactTop = (tonumber(builder.width) or 0) < 600
    local h = compactTop and 78 or 48
    local sec = T.Panel(builder.parent, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    T.ApplySurface(sec, "status")
    sec:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    sec:SetSize(builder.width, h)
    sec._msuf2Width = builder.width
    builder.y = builder.y - h - 8
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(builder.y) + 28) end
    local function MakeTopButton(parent, text, width, opts)
        return W.TopButton(parent, text, width, 24, opts or {})
    end
    local function AddScopeTooltip(frame, title, text)
        return M.AddTooltip and M.AddTooltip(frame, title, text, {
            hook = true,
            titleAsLine = true,
            bodyColor = { 0.85, 0.85, 0.85 },
        }) or frame
    end
    local function SelectScope(kind)
        local previousScope = M.gfScope
        M.SetMenuStateValue("gfScope", kind or "party")
        if previousScope ~= M.gfScope and M.ShowStatusFeedback then M.ShowStatusFeedback(ScopeShortLabel(M.gfScope) .. " scope", "info", 1.1) end
        local gf = GF()
        if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(M.gfScope) end
        RequestGFPagePreview()
        if gf and type(gf.PreviewScopeChanged) == "function" then
            gf.PreviewScopeChanged()
        else
            RefreshGFPreview()
        end
        RefreshContext(ctx)
    end
    local scopeBtns = {}
    local previous
    local rowY = compactTop and -14 or -12
    for i = 1, #SCOPE_VALUES do
        local info = SCOPE_VALUES[i]
        local width = (info.value == "mythicraid") and 68 or 56
        local btn = MakeTopButton(sec, ScopeShortLabel(info.value), width, {
            bg = { 0.026, 0.040, 0.084, 0.95 },
            border = { 0.095, 0.165, 0.330, 0.62 },
            activeBg = { 0.050, 0.110, 0.255, 0.98 },
            activeBorder = { 0.200, 0.430, 0.850, 0.92 },
        })
        if previous then
            btn:SetPoint("TOPLEFT", previous, "TOPRIGHT", 6, 0)
        else
            btn:SetPoint("TOPLEFT", sec, "TOPLEFT", 8, rowY)
        end
        btn:SetScript("OnClick", function() SelectScope(info.value) end)
        scopeBtns[info.value] = btn
        previous = btn
    end
    local actionY = compactTop and -46 or rowY
    local copy = (W.RoleButton and W.RoleButton(sec, M.Tr("Copy To"), "normal", compactTop and 82 or 86, 24)) or MakeTopButton(sec, M.Tr("Copy To"), compactTop and 82 or 86)
    copy:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -8, actionY)
    local edit = (W.RoleButton and W.RoleButton(sec, M.Tr("MSUF Edit Mode"), "primary", compactTop and 118 or 128, 24)) or MakeTopButton(sec, M.Tr("MSUF Edit Mode"), compactTop and 118 or 128)
    edit:SetPoint("RIGHT", copy, "LEFT", -8, 0)
    local reset = MakeTopButton(sec, M.Tr("Reset Scopes"), compactTop and 94 or 104, {
        bg = { 0.070, 0.026, 0.034, 0.94 },
        border = { 0.340, 0.090, 0.110, 0.82 },
        textColor = { 1.00, 0.82, 0.82, 1 },
        hoverBg = { 0.090, 0.035, 0.045, 0.96 },
        hoverBorder = { 0.420, 0.120, 0.140, 0.90 },
        activeBg = { 0.070, 0.026, 0.034, 0.94 },
        activeBorder = { 0.340, 0.090, 0.110, 0.82 },
        activeTextColor = { 1.00, 0.82, 0.82, 1 },
    })
    reset:SetPoint("RIGHT", edit, "LEFT", -8, 0)
    AddScopeTooltip(reset, "Reset Scopes", "Resets Party, Raid, and Mythic Raid Group Frame settings for the active profile.")
    AddScopeTooltip(edit, "MSUF Edit Mode", "Drag frames to move them. Group aura handles can be selected in previews; Blizzard-controlled aura blocks cannot be dragged.")
    local function RefreshTop()
        local current = CurrentScope()
        for i = 1, #SCOPE_VALUES do
            local info = SCOPE_VALUES[i]
            if scopeBtns[info.value] and scopeBtns[info.value].SetActive then scopeBtns[info.value]:SetActive(current == info.value) end
        end
        if edit.SetText then edit:SetText(M.IsMSUFEditModeActive() and M.Tr("Exit Edit Mode") or M.Tr("MSUF Edit Mode")) end
    end
    local gfResetPopup = M.InstallStaticPopup("MSUF2_GF_RESET_ALL_CONFIRM", {
        text = M.Tr("Reset all Group Frame settings to defaults?\n\nThis resets Party, Raid, and Mythic Raid Group Frames for the active profile. Defaults are read from the current MSUF factory profile, so future default changes are used automatically."),
        button1 = YES or M.Tr("Yes"),
        button2 = NO or M.Tr("No"),
    })
    gfResetPopup.OnAccept = function()
        local function ResetAllGroupFrames()
            local gf = GF()
            if gf and type(gf.ResetAllToDefaults) == "function" and gf.ResetAllToDefaults() then
                RefreshGFPreview()
                RefreshContext(ctx)
                if M.ShowStatusFeedback then
                    M.ShowStatusFeedback("Group frames reset", "ok", 1.4)
                elseif print then
                    print(M.Tr("|cffffd700MSUF:|r Group Frames reset to defaults."))
                end
            end
        end
        M.RunWithHistory("Reset Group Frames", "group:resetAll", ResetAllGroupFrames)
    end
    reset:SetScript("OnClick", function()
        if StaticPopup_Show then StaticPopup_Show("MSUF2_GF_RESET_ALL_CONFIRM") end
    end)
    M.WireEditModeButton(ctx, edit, {
        blockConfig = true,
        defer = true,
        source = "msuf2_group",
        unit = function() return "gf_" .. CurrentScope() end,
        afterClick = function(enabled)
            if M.ShowStatusFeedback then M.ShowStatusFeedback(enabled and "Edit mode on" or "Edit mode off", "info", 1.1) end
            local function RefreshAfterToggle()
                RefreshTop()
                RequestGFPagePreview()
            end
            C_Timer.After(0, RefreshAfterToggle)
        end,
    })
    M.gfCopyScopes = (type(M.gfCopyScopes) == "table") and M.gfCopyScopes or NewGFCopyScopes()
    local copyPopup = Shared.MakeScopeCopyPopup and Shared.MakeScopeCopyPopup(copy, {
        width = 430,
        height = 334,
        categories = GF_COPY_CATEGORIES,
        scopes = M.gfCopyScopes,
        targets = SCOPE_VALUES,
        targetWidths = { party = 58, raid = 58, mythicraid = 70 },
        sourceKey = CurrentScope,
        sourceLabel = ScopeLabel,
        targetLabelText = ScopeShortLabel,
        isTargetVisible = function(kind, source) return kind ~= source end,
        categoryRowsPerColumn = 6,
        categoryColumnWidth = 205,
        categoryWidth = 150,
        onTargetClick = function(kind, api, popup)
            local function RunCopy()
                if CopyGroupSettings(CurrentScope(), kind, M.gfCopyScopes) then
                    RefreshContext(ctx)
                    if M.ShowStatusFeedback then M.ShowStatusFeedback("Copied to " .. ScopeShortLabel(kind), "ok", 1.3) end
                end
            end
            M.RunWithHistory("Copy Group Settings", "group:copy:" .. tostring(CurrentScope()) .. ":" .. tostring(kind), RunCopy)
            popup:Hide()
        end,
    })
    copy:SetScript("OnClick", function(self) if copyPopup then copyPopup.Show(self) end end)
    sec:SetScript("OnHide", function() if copyPopup then copyPopup.Hide() end end)
    M.TrackRefresh(ctx, RefreshTop)
end
local GroupPage = M.GroupPage or {}
M.GroupPage = GroupPage
M.Assign(GroupPage, {
    Conf = Conf, Val = Val, Set = Set, Bool = Bool, Num = Num, CurrentScope = CurrentScope,
    GF_COPY_CATEGORIES = GF_COPY_CATEGORIES, NewGFCopyScopes = NewGFCopyScopes, CopyGroupSettings = CopyGroupSettings,
})
local function BindScopeToggle(ctx, widget, key, default, mode)
    M.BindBoolWidget(ctx, widget,
        function() return Bool(CurrentScope(), key, default) end,
        function(v)
            Set(CurrentScope(), key, v and true or false, mode or "visual")
            RefreshContext(ctx)
        end)
    return widget
end
local function BindScopeSlider(ctx, widget, key, default, mode)
    M.BindNumberWidget(ctx, widget,
        function() return Num(CurrentScope(), key, default) end,
        function(v) Set(CurrentScope(), key, floor((tonumber(v) or default or 0) + 0.5), mode or "visual") end,
        default, { step = 1, roundStep = true })
    return widget
end
local function BindScopeDropdown(ctx, widget, key, default, mode)
    M.BindDropdownWidget(ctx, widget,
        function() return Val(CurrentScope(), key, default) end,
        function(v) Set(CurrentScope(), key, v or default, mode or "visual") end)
    return widget
end
local function ScopeDropdown(ctx, parent, label, values, width, key, default, mode, x, y, placeWidth, justify)
    local control = BindScopeDropdown(ctx, W.Dropdown(parent, label, values, width), key, default, mode)
    if x then W.MoveWidget(control, parent, x, y, placeWidth or width, justify or "LEFT") end
    return control
end
local function ScopeSlider(ctx, parent, label, minValue, maxValue, step, width, key, default, mode, x, y, placeWidth, justify)
    local control = BindScopeSlider(ctx, W.Slider(parent, label, minValue, maxValue, step, width), key, default, mode)
    if x then W.MoveWidget(control, parent, x, y, placeWidth or width, justify or "CENTER") end
    return control
end
local function ScopeColor(ctx, parent, label, width, rKey, gKey, bKey, defaults, mode, x, y, placeWidth, justify)
    local control = W.Color(parent, label)
    defaults = defaults or {}
    M.BindColor(ctx, control,
        function()
            return Num(CurrentScope(), rKey, defaults[1] or 1),
                Num(CurrentScope(), gKey, defaults[2] or 1),
                Num(CurrentScope(), bKey, defaults[3] or 1)
        end,
        function(r, g, b)
            local conf = Conf(CurrentScope())
            conf[rKey], conf[gKey], conf[bKey] = r, g, b
            QueueGF(CurrentScope(), mode or "visual")
        end)
    if x then W.MoveWidget(control, parent, x, y, placeWidth or width or 220, justify or "LEFT") end
    return control
end
local GROWTH_TILE_VALUES = {
    { value = "DOWN", text = "Down", dx = 0, dy = -1, arrow = "v" },
    { value = "UP", text = "Up", dx = 0, dy = 1, arrow = "^" },
    { value = "RIGHT", text = "Right", dx = 1, dy = 0, arrow = ">" },
    { value = "LEFT", text = "Left", dx = -1, dy = 0, arrow = "<" },
}
local function BuildGrowthDirectionTiles(ctx, section, opts)
    if not section then return nil end
    opts = opts or {}
    local x = opts.x or section._msuf2ContentX or 14
    local y = opts.y or section._msuf2CursorY or -38
    local tileW, tileH, gap = opts.tileWidth or 64, opts.tileHeight or 64, opts.gap or 6
    if opts.advanceCursor ~= false then section._msuf2CursorY = y - tileH - 40 end
    local label = T.Font(section, "GameFontNormalSmall", M.Tr("Growth Direction"), T.colors.accent)
    label:SetPoint("TOPLEFT", section, "TOPLEFT", x, y)
    local holder = CreateFrame("Frame", nil, section)
    holder:SetPoint("TOPLEFT", section, "TOPLEFT", x, y - 20)
    holder:SetSize((tileW * 4) + (gap * 3), tileH)
    holder._msuf2Label = label
    local buttons = {}
    local function SetTileVisual(btn, active, hover)
        if not btn then return end
        if btn.SetBackdropColor then
            if active then
                btn:SetBackdropColor(0.100, 0.180, 0.300, hover and 0.98 or 0.92)
                btn:SetBackdropBorderColor(0.260, 0.620, 1.000, 1.00)
            elseif hover then
                btn:SetBackdropColor(0.115, 0.135, 0.185, 0.95)
                btn:SetBackdropBorderColor(0.380, 0.450, 0.620, 0.95)
            else
                btn:SetBackdropColor(0.045, 0.052, 0.076, 0.92)
                btn:SetBackdropBorderColor(0.190, 0.220, 0.310, 0.85)
            end
        end
        if btn._label then
            if active then
                btn._label:SetTextColor(0.95, 1.00, 1.00, 1)
            else
                btn._label:SetTextColor(0.74, 0.80, 0.90, 0.95)
            end
        end
    end
    local function DrawMiniPreview(btn, info, raidLike)
        if not btn or not info then return end
        btn._cells = btn._cells or {}
        local cols, rows
        if raidLike then
            if info.dy ~= 0 then
                cols, rows = 4, 5
            else
                cols, rows = 5, 4
            end
        elseif info.dy ~= 0 then
            cols, rows = 1, 5
        else
            cols, rows = 5, 1
        end
        local pad = 5
        local labelH = 13
        local innerW = tileW - (pad * 2)
        local innerH = tileH - pad - labelH
        local cellGap = 1
        local cellW = max(3, floor((innerW - ((cols - 1) * cellGap)) / cols))
        local cellH = max(3, floor((innerH - ((rows - 1) * cellGap)) / rows))
        local gridW = (cols * cellW) + ((cols - 1) * cellGap)
        local gridH = (rows * cellH) + ((rows - 1) * cellGap)
        local originX = pad + floor((innerW - gridW) * 0.5 + 0.5)
        local originY = -pad - floor((innerH - gridH) * 0.5 + 0.5)
        local positions = {}
        if info.dy ~= 0 then
            local rowStart, rowEnd, rowStep = 0, rows - 1, 1
            if info.dy == 1 then rowStart, rowEnd, rowStep = rows - 1, 0, -1 end
            for col = 0, cols - 1 do
                for row = rowStart, rowEnd, rowStep do
                    positions[#positions + 1] = { col = col, row = row }
                end
            end
        else
            local colStart, colEnd, colStep = 0, cols - 1, 1
            if info.dx == -1 then colStart, colEnd, colStep = cols - 1, 0, -1 end
            for row = 0, rows - 1 do
                for col = colStart, colEnd, colStep do
                    positions[#positions + 1] = { col = col, row = row }
                end
            end
        end
        for i = 1, #positions do
            local cell = btn._cells[i]
            if not cell then
                cell = btn:CreateTexture(nil, "ARTWORK")
                btn._cells[i] = cell
            end
            local pos = positions[i]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", btn, "TOPLEFT", originX + (pos.col * (cellW + cellGap)), originY - (pos.row * (cellH + cellGap)))
            cell:SetSize(cellW, cellH)
            if i == 1 then
                cell:SetColorTexture(0.120, 0.950, 0.620, 0.98)
            elseif i <= 4 then
                cell:SetColorTexture(0.220, 0.580, 0.940, 0.78)
            else
                cell:SetColorTexture(0.160, 0.360, 0.640, 0.42)
            end
            cell:Show()
        end
        for i = #positions + 1, #btn._cells do
            btn._cells[i]:Hide()
        end
        if not btn._firstText then
            btn._firstText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if btn._firstText.SetFont then btn._firstText:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE") end
            btn._firstText:SetText("1")
            btn._firstText:SetTextColor(0, 0, 0, 1)
        end
        local first = positions[1]
        if first then
            btn._firstText:ClearAllPoints()
            btn._firstText:SetPoint("CENTER", btn, "TOPLEFT",
                originX + (first.col * (cellW + cellGap)) + (cellW * 0.5),
                originY - (first.row * (cellH + cellGap)) - (cellH * 0.5))
            btn._firstText:Show()
        end
        if not btn._arrow then
            btn._arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if btn._arrow.SetFont then btn._arrow:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE") end
            btn._arrow:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.95)
        end
        btn._arrow:SetText(info.arrow)
        btn._arrow:ClearAllPoints()
        if info.dy == -1 then
            btn._arrow:SetPoint("BOTTOM", btn, "BOTTOM", 0, labelH + 1)
        elseif info.dy == 1 then
            btn._arrow:SetPoint("TOP", btn, "TOP", 0, -4)
        elseif info.dx == 1 then
            btn._arrow:SetPoint("RIGHT", btn, "RIGHT", -4, labelH * 0.5)
        else
            btn._arrow:SetPoint("LEFT", btn, "LEFT", 4, labelH * 0.5)
        end
        btn._arrow:Show()
    end
    local function RefreshGrowthTiles()
        local current = Val(CurrentScope(), "growth", "DOWN")
        local raidLike = CurrentScope() ~= "party"
        for i = 1, #GROWTH_TILE_VALUES do
            local info = GROWTH_TILE_VALUES[i]
            local btn = buttons[info.value]
            if btn then
                DrawMiniPreview(btn, info, raidLike)
                SetTileVisual(btn, current == info.value, btn.IsMouseOver and btn:IsMouseOver())
            end
        end
    end
    for i = 1, #GROWTH_TILE_VALUES do
        local info = GROWTH_TILE_VALUES[i]
        local btn = CreateFrame("Button", nil, holder, T.Template and T.Template() or nil)
        btn:SetSize(tileW, tileH)
        btn:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (tileW + gap), 0)
        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
        end
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if text.SetFont then text:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE") end
        text:SetPoint("BOTTOM", btn, "BOTTOM", 0, 3)
        text:SetText(info.text)
        btn._label = text
        btn:SetScript("OnEnter", function(self)
            SetTileVisual(self, Val(CurrentScope(), "growth", "DOWN") == info.value, true)
        end)
        btn:SetScript("OnLeave", function(self)
            SetTileVisual(self, Val(CurrentScope(), "growth", "DOWN") == info.value, false)
        end)
        M.AddTooltip(btn, function() return M.Format(M.Tr("Growth: %s"), M.Tr(info.text or "")) end, "Click to set group frame growth direction.", { hook = true, titleAsLine = true, bodyColor = { 0.72, 0.76, 0.86 } })
        btn:SetScript("OnClick", function()
            Set(CurrentScope(), "growth", info.value, "rebuild")
            RefreshGrowthTiles()
        end)
        buttons[info.value] = btn
    end
    M.TrackRefresh(ctx, RefreshGrowthTiles)
    return holder
end
local ROLE_SORT_DEFS = {
    { key = "TANK", label = "Tank", r = 0.30, g = 0.55, b = 0.85 },
    { key = "HEALER", label = "Healer", r = 0.20, g = 0.72, b = 0.35 },
    { key = "DAMAGER", label = "DPS", r = 0.82, g = 0.30, b = 0.30 },
}
local ROLE_SORT_BY_KEY = {}
for i = 1, #ROLE_SORT_DEFS do
    ROLE_SORT_BY_KEY[ROLE_SORT_DEFS[i].key] = i
end
local function BuildRoleOrderRows(ctx, section, opts)
    if not section then return nil end
    opts = opts or {}
    local rowW, rowH, rowGap = opts.width or 220, 22, 4
    local x = opts.x or section._msuf2ContentX or 14
    local y = opts.y or section._msuf2CursorY or -146
    local listY = y
    if opts.hint or opts.title then
        local title = T.Font(section, "GameFontNormalSmall", opts.title or "Role Priority", T.colors.text)
        title:SetPoint("TOPLEFT", section, "TOPLEFT", x, y)
        title:SetWidth(rowW)
        title:SetJustifyH("LEFT")
        local hint = T.Font(section, "GameFontDisableSmall", opts.hint or "Drag roles to reorder.", T.colors.dim)
        hint:SetPoint("TOPLEFT", section, "TOPLEFT", x, y - 16)
        hint:SetWidth(rowW + 80)
        hint:SetJustifyH("LEFT")
        listY = y - 38
    end
    if opts.advanceCursor ~= false then section._msuf2CursorY = listY - (#ROLE_SORT_DEFS * (rowH + rowGap)) - 10 end
    local function NormalizeRoleToken(token)
        if token == "MELEE" or token == "RANGED" then return "DAMAGER" end
        return token
    end
    local holder, rows
    local function SaveOrder()
        local kind = CurrentScope()
        local function WriteOrder()
            local ordered = {}
            for i = 1, #rows do ordered[#ordered + 1] = rows[i] end
            table.sort(ordered, function(a, b) return (a.slotIndex or 0) < (b.slotIndex or 0) end)
            local parts = {}
            for i = 1, #ordered do parts[#parts + 1] = ordered[i].key end
            local conf = Conf(kind)
            conf.roleOrder = table.concat(parts, ",")
            QueueGF(kind, "rebuild")
        end
        M.RunWithHistory("Role Priority Order", "group:roleOrder:" .. tostring(kind), WriteOrder)
    end
    local function LoadOrder()
        local conf = Conf(CurrentScope())
        local order = type(conf.roleOrder) == "string" and conf.roleOrder or "TANK,HEALER,DAMAGER"
        local slot = 0
        local assigned = {}
        for token in order:gmatch("[^,]+") do
            token = NormalizeRoleToken(token)
            local index = ROLE_SORT_BY_KEY[token]
            if index and not assigned[index] then
                slot = slot + 1
                rows[index].slotIndex = slot
                assigned[index] = true
            end
        end
        for i = 1, #rows do
            if not assigned[i] then
                slot = slot + 1
                rows[i].slotIndex = slot
            end
        end
        holder:SnapRows()
    end
    holder = Shared.MakeDragSortRows(section, ROLE_SORT_DEFS, {
        x = x, y = listY, width = rowW, rowHeight = rowH, gap = rowGap,
        onReorder = SaveOrder,
        tooltip = function(self, row, tip)
            tip:SetOwner(self, "ANCHOR_RIGHT")
            tip:AddLine(M.Tr((row and row.def and row.def.label) or ""), 1, 1, 1)
            tip:AddLine(M.Tr("Drag to change role priority."), 0.72, 0.76, 0.86)
            tip:Show()
        end,
    })
    rows = holder.rows
    holder.Refresh = LoadOrder
    M.TrackRefresh(ctx, LoadOrder)
    holder:SetRowsEnabled(false)
    return holder
end
local function AurasRoot(kind)
    local conf = Conf(kind)
    conf.auras = conf.auras or {}
    if conf.auras.renderer ~= "CUSTOM" then conf.auras.renderer = "CUSTOM" end
    conf.auras.blizzardTypes = conf.auras.blizzardTypes or {}
    conf.auras.buff = conf.auras.buff or {}
    conf.auras.debuff = conf.auras.debuff or {}
    conf.auras.externals = conf.auras.externals or {}
    return conf.auras
end
local function AuraGroup(kind, groupKey)
    local root = AurasRoot(kind)
    root[groupKey] = root[groupKey] or {}
    return root[groupKey]
end
local function SpellIndicators(kind)
    local conf = Conf(kind)
    if type(conf.spellIndicators) ~= "table" then conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9 } end
    conf.spellIndicators.specs = conf.spellIndicators.specs or {}
    return conf.spellIndicators
end
local function IconStyleValues()
    local gf = GF()
    if gf and type(gf.ICON_STYLE_ITEMS) == "table" then return gf.ICON_STYLE_ITEMS end
    return VT(
        "BLIZZARD", "Blizzard (Default)", "CLASSIC", "Classic", "MIDNIGHT", "Midnight",
        "UXPRO", "UX Pro", "GLOSSY_ORBS", "Glossy Orbs", "DARK_EMBOSS", "Dark Emboss", "GLASS_PANELS", "Glass Panels",
        "NEON_OUTLINE", "Neon Outline", "RING_SYMBOLS", "Ring Symbols", "DOTS", "Dots",
        "SHAPES", "Shapes", "DIAMONDS", "Diamonds", "SQUARES", "Squares")
end
local function CurrentGFStatusSpec()
    if not M.gfStatusIconSelection then M.SetMenuStateValue("gfStatusIconSelection", "roleIcon") end
    for i = 1, #GF_STATUS_ICON_SPECS do
        local spec = GF_STATUS_ICON_SPECS[i]
        if spec.value == M.gfStatusIconSelection then return spec end
    end
    M.SetMenuStateValue("gfStatusIconSelection", GF_STATUS_ICON_SPECS[1].value)
    return GF_STATUS_ICON_SPECS[1]
end
local function QueueSpellIndicators(kind)
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if si and type(si.InvalidateRuntimeCaches) == "function" then si.InvalidateRuntimeCaches() end
    QueueGF(kind or CurrentScope(), "visual")
end
local function SpellSpecValues()
    local values = VT("auto", "Auto-Detect", "multi", "Multi-Spec")
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if si and type(si.SpecInfo) == "table" then
        for specKey, info in pairs(si.SpecInfo) do
            values[#values + 1] = { value = specKey, text = (info and info.display) or tostring(specKey) }
        end
    end
    return values
end
local function SpellTrackedSpecValues()
    local values = {}
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if si and type(si.SpecInfo) == "table" then
        for specKey, info in pairs(si.SpecInfo) do
            values[#values + 1] = { value = specKey, text = (info and info.display) or tostring(specKey) }
        end
        table.sort(values, function(a, b) return tostring(a.text) < tostring(b.text) end)
    end
    if #values == 0 then values[1] = { value = "", text = "No supported specs" } end
    return values
end
local function CurrentSpellMultiSpec(kind)
    M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
    local selected = M.gfSpellMultiSpecSelection[kind]
    local values = SpellTrackedSpecValues()
    for i = 1, #values do
        if values[i].value == selected then return selected end
    end
    selected = values[1] and values[1].value or ""
    M.gfSpellMultiSpecSelection[kind] = selected
    return selected
end
local function EffectiveSpellSpec(kind)
    local cfg = SpellIndicators(kind)
    local selected = cfg.spec or "auto"
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if selected ~= "auto" and selected ~= "multi" and si and si.SpecInfo and si.SpecInfo[selected] then return selected end
    if selected == "multi" then
        local chosen = CurrentSpellMultiSpec(kind)
        if chosen and si and si.SpecInfo and si.SpecInfo[chosen] then return chosen end
        if type(cfg.multiSpecs) == "table" then
            for specKey, enabled in pairs(cfg.multiSpecs) do
                if enabled and si and si.SpecInfo and si.SpecInfo[specKey] then return specKey end
            end
        end
    end
    if si and type(si.GetPlayerSpec) == "function" then
        local specKey = si.GetPlayerSpec()
        if specKey and si.SpecInfo and si.SpecInfo[specKey] then return specKey end
    end
    if si and type(si.SpecInfo) == "table" then
        for specKey in pairs(si.SpecInfo) do return specKey end
    end
    return nil
end
local function SpellAuraValues(kind)
    local gf = GF()
    local si = gf and gf.SpellIndicators
    local specKey = EffectiveSpellSpec(kind)
    local trackable = specKey and si and si.TrackableAuras and si.TrackableAuras[specKey]
    local values = {}
    if type(trackable) == "table" then
        for i = 1, #trackable do
            local info = trackable[i]
            local key = info and info.name
            if key then values[#values + 1] = { value = key, text = info.display or key } end
        end
    end
    if #values == 0 then values[1] = { value = "", text = "No spells for current spec" } end
    return values
end
local function CurrentSpellAura(kind)
    M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
    local selected = M.gfSpellIndicatorSelection[kind]
    local values = SpellAuraValues(kind)
    for i = 1, #values do
        if values[i].value == selected then return selected end
    end
    selected = values[1] and values[1].value or ""
    M.gfSpellIndicatorSelection[kind] = selected
    return selected
end
local function CurrentSpellConfig(kind, create)
    local specKey = EffectiveSpellSpec(kind)
    local auraName = CurrentSpellAura(kind)
    if not (specKey and auraName and auraName ~= "") then return nil end
    local cfg = SpellIndicators(kind)
    cfg.specs[specKey] = cfg.specs[specKey] or {}
    if create and type(cfg.specs[specKey][auraName]) ~= "table" then cfg.specs[specKey][auraName] = { enabled = true, onlyOwn = true } end
    return cfg.specs[specKey][auraName], specKey, auraName
end
local function PlacedConfig(kind, create)
    local cfg = CurrentSpellConfig(kind, create)
    if not cfg then return nil end
    if create and type(cfg.placed) ~= "table" then cfg.placed = { type = "icon", anchor = "TOPLEFT", x = 0, y = 0, size = 18, showCooldownSwipe = true } end
    return cfg.placed
end
local function FrameEffectConfig(kind, create)
    local cfg = CurrentSpellConfig(kind, create)
    if not cfg then return nil end
    if create and type(cfg.frame) ~= "table" then cfg.frame = { type = "none" } end
    return cfg.frame
end
local function CICategoryValues()
    local gf = GF()
    if gf and type(gf.CI_CATEGORIES) == "table" then return gf.CI_CATEGORIES end
    return VT("none", "None", "dispel", "Dispellable", "aggro", "Aggro/Threat", "custom", "Custom Spell")
end
local function CIFilterValues()
    local gf = GF()
    if gf and type(gf.CI_CUSTOM_FILTERS) == "table" then return gf.CI_CUSTOM_FILTERS end
    return VT(
        "HELPFUL|PLAYER", "Buff (cast by me)", "HELPFUL", "Buff (any caster)",
        "HARMFUL|PLAYER", "Debuff (cast by me)", "HARMFUL", "Debuff (any caster)")
end
local function CIModeValues()
    local gf = GF()
    if gf and type(gf.CI_CUSTOM_MODES) == "table" then return gf.CI_CUSTOM_MODES end
    return VT("present", "Show when present", "missing", "Show when missing")
end
local function CurrentCISlot()
    if not M.gfCornerSlotSelection then M.SetMenuStateValue("gfCornerSlotSelection", "TL") end
    for i = 1, #CI_SLOT_VALUES do
        if CI_SLOT_VALUES[i].value == M.gfCornerSlotSelection then return M.gfCornerSlotSelection end
    end
    M.SetMenuStateValue("gfCornerSlotSelection", "TL")
    return "TL"
end
local function CICustomConfig(kind, slot, create)
    local conf = Conf(kind)
    local key = "ciCustom" .. (slot or CurrentCISlot())
    if create and type(conf[key]) ~= "table" then conf[key] = { spells = "", mode = "present", filter = "HELPFUL|PLAYER", r = 0.40, g = 1.00, b = 0.40 } end
    return type(conf[key]) == "table" and conf[key] or nil
end
local function BindNestedToggle(ctx, widget, getTable, key, default, mode)
    M.BindBoolWidget(ctx, widget,
        function()
            local tbl = getTable()
            local value = tbl[key]
            if value == nil then return default and true or false end
            return value and true or false
        end,
        function(v)
            local tbl = getTable()
            if tbl[key] == (v and true or false) then return end
            tbl[key] = v and true or false
            QueueGF(CurrentScope(), mode or "visual")
            RefreshContext(ctx)
        end)
    return widget
end
local function BindNestedSlider(ctx, widget, getTable, key, default, mode)
    M.BindNumberWidget(ctx, widget,
        function()
            local tbl = getTable()
            return tonumber(tbl[key]) or default or 0
        end,
        function(v)
            local tbl = getTable()
            v = floor((tonumber(v) or default or 0) + 0.5)
            if tbl[key] == v then return end
            tbl[key] = v
            QueueGF(CurrentScope(), mode or "visual")
        end,
        default, { step = 1, roundStep = true })
    return widget
end
local function BindNestedDropdown(ctx, widget, getTable, key, default, mode)
    M.BindDropdownWidget(ctx, widget,
        function()
            local tbl = getTable()
            return tbl[key] or default
        end,
        function(v)
            local tbl = getTable()
            tbl[key] = v or default
            QueueGF(CurrentScope(), mode or "visual")
        end)
    return widget
end
local SetOptionEnabled = W.SetControlEnabled
local SetOptionsEnabled = W.SetControlsEnabled
local function ForEachGroupPageControl(parent, callback)
    if not (parent and parent.GetChildren and type(callback) == "function") then return end
    local children = { parent:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child._msuf2ControlKind and not child._msuf2GroupFrameGateAlwaysEnabled then callback(child) end
        ForEachGroupPageControl(child, callback)
    end
end
ApplyScopeEnabledGate = function(ctx)
    local wrapper = ctx and ctx.wrapper
    if not wrapper then return end
    local scope = CurrentScope()
    local enabled = Bool(scope, "enabled", false)
    local gateKey = "groupFrameEnabled"
    if ControlGates.Apply then
        ControlGates.Apply(wrapper, gateKey, enabled, { alwaysEnabledFlag = "_msuf2GroupFrameGateAlwaysEnabled" })
        return
    end
    if wrapper._msuf2GroupFrameGateKey == gateKey and wrapper._msuf2GroupFrameGateEnabled == enabled then return end
    wrapper._msuf2GroupFrameGateKey = gateKey
    wrapper._msuf2GroupFrameGateEnabled = enabled
    ForEachGroupPageControl(wrapper, function(control)
        W.SetControlGateEnabled(control, gateKey, enabled)
    end)
end
M.Assign(GroupPage, {
    SCOPE_VALUES = SCOPE_VALUES,
    GROWTH_VALUES = GROWTH_VALUES,
    BLIZZARD_FALLBACK_VALUES = BLIZZARD_FALLBACK_VALUES,
    HEALTH_MODES = HEALTH_MODES,
    TEXT_MODES = TEXT_MODES,
    DELIMITER_VALUES = DELIMITER_VALUES,
    ANCHORS = ANCHORS,
    AURA_ANCHORS = AURA_ANCHORS,
    SORT_MODES = SORT_MODES,
    GF_BAR_MODES = GF_BAR_MODES,
    SIMPLE_TEXTURES = SIMPLE_TEXTURES,
    GF_ANCHOR_TO = GF_ANCHOR_TO,
    GF_ANCHOR_POINTS = GF_ANCHOR_POINTS,
    STATUS_ICON_ANCHORS = STATUS_ICON_ANCHORS,
    GF_STATUS_ICON_SPECS = GF_STATUS_ICON_SPECS,
    GF_STATUS_ICON_VALUES = GF_STATUS_ICON_VALUES,
    PLACED_INDICATOR_TYPES = PLACED_INDICATOR_TYPES,
    FRAME_EFFECT_TYPES = FRAME_EFFECT_TYPES,
    SPELL_GROWTH_VALUES = SPELL_GROWTH_VALUES,
    CI_SLOT_VALUES = CI_SLOT_VALUES,
    CI_SLOT_DEFAULTS = CI_SLOT_DEFAULTS,
    DISPEL_OVERLAY_STYLES = DISPEL_OVERLAY_STYLES,
    DEBUFF_STRIPE_EDGES = DEBUFF_STRIPE_EDGES,
    GF = GF,
    RefreshGFPreview = RefreshGFPreview,
    QueueGF = QueueGF,
    RefreshContext = RefreshContext,
    ScopeSection = ScopeSection,
    BindScopeToggle = BindScopeToggle,
    BindScopeSlider = BindScopeSlider,
    BindScopeDropdown = BindScopeDropdown,
    ScopeDropdown = ScopeDropdown,
    ScopeSlider = ScopeSlider,
    ScopeColor = ScopeColor,
    BuildGrowthDirectionTiles = BuildGrowthDirectionTiles,
    BuildRoleOrderRows = BuildRoleOrderRows,
    AuraGroup = AuraGroup,
    AurasRoot = AurasRoot,
    SpellIndicators = SpellIndicators,
    IconStyleValues = IconStyleValues,
    CurrentGFStatusSpec = CurrentGFStatusSpec,
    QueueSpellIndicators = QueueSpellIndicators,
    SpellSpecValues = SpellSpecValues,
    SpellTrackedSpecValues = SpellTrackedSpecValues,
    CurrentSpellMultiSpec = CurrentSpellMultiSpec,
    EffectiveSpellSpec = EffectiveSpellSpec,
    SpellAuraValues = SpellAuraValues,
    CurrentSpellAura = CurrentSpellAura,
    CurrentSpellConfig = CurrentSpellConfig,
    PlacedConfig = PlacedConfig,
    FrameEffectConfig = FrameEffectConfig,
    CICategoryValues = CICategoryValues,
    CIFilterValues = CIFilterValues,
    CIModeValues = CIModeValues,
    CurrentCISlot = CurrentCISlot,
    CICustomConfig = CICustomConfig,
    BindNestedToggle = BindNestedToggle,
    BindNestedSlider = BindNestedSlider,
    BindNestedDropdown = BindNestedDropdown,
    SetOptionEnabled = SetOptionEnabled,
    SetOptionsEnabled = SetOptionsEnabled,
    ApplyScopeEnabledGate = ApplyScopeEnabledGate,
    FinalizeScopePage = FinalizeScopePage,
    SetSectionHeaderStatus = SetSectionHeaderStatus,
    SetSectionBadges = SetSectionBadges,
    SetSectionBadgesAndStatus = SetSectionBadgesAndStatus,
    TrackSectionRefresh = TrackSectionRefresh,
    OnOffBadge = OnOffBadge,
    BadgeNumber = BadgeNumber,
    OptionText = OptionText,
    CreateSectionNotice = CreateSectionNotice,
})
