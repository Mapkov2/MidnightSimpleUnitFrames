local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- GroupFrames assistant action domain.
-- Depends on MSUF_AssistantRegistry_GroupFrames.lua for status-icon helpers.
local ctx = A.GroupFramesRegistry and A.GroupFramesRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
M = ctx.M or M
MSUF = ctx.MSUF or MSUF
local UNIT_LABELS = ctx.UNIT_LABELS or {}
local ResolveGroupStatusIcon = ctx.ResolveGroupStatusIcon
local ResetGroupStatusIcon = ctx.ResetGroupStatusIcon
local GROUP_STATUS_ICON_SPECS = ctx.GROUP_STATUS_ICON_SPECS or {}

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(ResolveGroupStatusIcon) ~= "function" or type(ResetGroupStatusIcon) ~= "function" then return end

local function GroupLabel(scope)
    if A and type(A.DisplayGroupLabel) == "function" then return A.DisplayGroupLabel(scope) end
    local label = UNIT_LABELS[scope]
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    if scope == "mythicraid" then return "Mythic Raid" end
    if scope == "raid" then return "Raid" end
    return "Party"
end

Registry:RegisterAction({
    key = "reset_group_status_icon",
    label = "Reset Group Status Icon",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope = args and args.scope
        if scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        local spec = ResolveGroupStatusIcon(args and args.icon)
        if not spec then return false, "Which group status icon do you want me to reset?" end
        ResetGroupStatusIcon(scope, spec)
        return true, "Done. Reset " .. GroupLabel(scope) .. " " .. tostring(spec.label) .. " placement and icon style."
    end,
})

Registry:RegisterAction({
    key = "reset_selected_group_status_icon",
    label = "Reset Selected Group Status Icon",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    aliases = {
        "reset selected group status icon", "reset current group status icon",
        "reset selected group status indicator",
    },
    aliasNoArgs = true,
    run = function()
        local gp = M and M.GroupPage
        local scope = gp and type(gp.CurrentScope) == "function" and gp.CurrentScope() or (M and M.gfScope)
        if scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end

        local spec = gp and type(gp.CurrentGFStatusSpec) == "function" and gp.CurrentGFStatusSpec()
            or ResolveGroupStatusIcon(M and M.gfStatusIconSelection)
        if not spec then return false, "Select a group status icon first." end

        local conf = gp and type(gp.Conf) == "function" and gp.Conf(scope)
        local gf = gp and type(gp.GF) == "function" and gp.GF() or (MSUF and MSUF.GF)
        if type(conf) == "table" then
            for _, field in ipairs({ "size", "anchor", "x", "y", "layer", "iconStyle", "customIcon" }) do
                local key = spec[field]
                if key then conf[key] = gf and gf.GetDefault and gf.GetDefault(scope, key) or nil end
            end
            if gp and type(gp.QueueGF) == "function" then
                gp.QueueGF(scope, "visual")
            else
                ResetGroupStatusIcon(scope, spec)
            end
        else
            ResetGroupStatusIcon(scope, spec)
        end

        if M and type(M.RequestRefresh) == "function" then
            M.RequestRefresh(nil, "gf-indicators-status-icon")
        elseif M and type(M.Refresh) == "function" then
            M.Refresh()
        end
        return true, "Done. Reset " .. GroupLabel(scope) .. " " .. tostring(spec.label) .. " placement and icon style."
    end,
})

Registry:RegisterAction({
    key = "reset_group_status_icons",
    label = "Reset Group Status Icons",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local scope = args and args.scope
        if scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        for i = 1, #GROUP_STATUS_ICON_SPECS do ResetGroupStatusIcon(scope, GROUP_STATUS_ICON_SPECS[i]) end
        return true, "Done. Reset " .. GroupLabel(scope) .. " status icon placement and icon styles."
    end,
})

Registry:RegisterAction({
    key = "preview_group_status_icon",
    label = "Preview Group Status Icon",
    type = "preview",
    combatSafe = true,
    aliases = {
        "preview group status icon", "preview group status indicator",
        "preview group indicator", "preview group indicators", "preview group status and indicators",
        "group status icon test mode", "group status indicator test mode",
        "group indicator test mode", "group indicators test mode", "group status and indicators test mode",
        "test group status icons", "test group status indicators", "test group indicators", "test group status and indicators",
        "show all group status icons", "show all group status indicators", "show all group indicators", "show all group status and indicators",
    },
    run = function(args)
        local mode = args and args.mode == "all" and "all" or "current"
        local spec = ResolveGroupStatusIcon(args and (args.icon or args.text))
        local gf = MSUF and MSUF.GF
        if gf and type(gf.SetPreviewFocus) == "function" then gf.SetPreviewFocus("sicons") end
        if gf and type(gf.SetStatusPreviewMode) == "function" then gf.SetStatusPreviewMode(mode) end
        if mode == "current" and spec and gf and type(gf._PreviewSelectStatusIcon) == "function" then gf._PreviewSelectStatusIcon(spec.value) end
        if mode == "all" then return true, "Done. Showing all group status icons in the preview." end
        return true, "Done. Previewing " .. tostring(spec and spec.label or "the current group status icon") .. "."
    end,
})

local GROUP_COPY_SCOPE_LABELS = {
    { key = "general", label = "Basics" },
    { key = "health", label = "Health & Bars" },
    { key = "dispel", label = "Dispel Overlay" },
    { key = "text", label = "Text & Name" },
    { key = "font", label = "Font Override" },
    { key = "range", label = "Range Fade" },
    { key = "indicators", label = "Status & Indicators" },
    { key = "auras", label = "Aura Options" },
    { key = "aurastyle", label = "Aura Style" },
    { key = "highlight", label = "Highlight & Aggro" },
    { key = "dstripe", label = "Debuff Stripe" },
    { key = "features", label = "Corner/Spell" },
}

local function GroupCopyScopeSummary(scopes)
    if type(scopes) ~= "table" then return "" end
    local selected, total = {}, 0
    for i = 1, #GROUP_COPY_SCOPE_LABELS do
        local row = GROUP_COPY_SCOPE_LABELS[i]
        total = total + 1
        if scopes[row.key] == true then selected[#selected + 1] = row.label end
    end
    if #selected == 0 then return " Which group-frame parts do you want me to copy?" end
    if #selected == total then return " Categories: all group-frame parts." end
    return " Categories: " .. table.concat(selected, ", ") .. "."
end


local function WordList(words)
    local out = {}
    for word in tostring(words or ""):gmatch("%S+") do out[#out + 1] = word end
    return out
end

local function WordSet(words)
    local out = {}
    for _, word in ipairs(WordList(words)) do out[word] = true end
    return out
end

local function MaskHas(mask, flag)
    mask = tonumber(mask) or 0
    flag = tonumber(flag) or 0
    if flag <= 0 then return false end
    return mask % (flag * 2) >= flag
end

local function AddDirty(mask, flag)
    if not flag then return mask or 0 end
    mask = tonumber(mask) or 0
    if MaskHas(mask, flag) then return mask end
    return mask + flag
end

local GROUP_COPY_EXCLUDE = WordSet("offsetX offsetY point positionMode _hlMigrated")
local GROUP_SHARED_COLOR_KEYS = WordSet([[
gfBarMode healthColorMode healthCustomR healthCustomG healthCustomB gfDarkR gfDarkG gfDarkB
gfUnifiedR gfUnifiedG gfUnifiedB bgR bgG bgB deadBgEnabled deadBgOffline deadBgR deadBgG deadBgB deadBgA
debuffStripeAlpha debuffStripeColorR debuffStripeColorG debuffStripeColorB targetR targetG targetB
hlFocusColorR hlFocusColorG hlFocusColorB groupBorderR groupBorderG groupBorderB groupBorderA
ciAggroColorR ciAggroColorG ciAggroColorB
]])
local GROUP_COPY_CATEGORIES = {
    { key = "general", keys = WordList("enabled blizzardFallbackMode showPlayer showSolo clickCastEnabled width height spacing growth groupFilter sortMode sortByRole roleOrder playerFirstInRole unitsPerColumn maxColumns maxFrames autoTanks preserveRaidGroups reverseFill smoothFill hideInClientScene hideInHousing hideOfflineEnabled hideOfflineInCombat hideOfflineDelay frameScaleEnabled frameScaleMode frameScaleManual scaleAt10 scaleAt20 scaleAt25 scaleOver25") },
    { key = "health", keys = WordList("gfBarMode healthColorMode healthCustomR healthCustomG healthCustomB gfDarkR gfDarkG gfDarkB gfUnifiedR gfUnifiedG gfUnifiedB barTexture barBackgroundTexture barBgTexture hpBarAlpha hpBgAlpha alphaExcludeTextPortrait powerBarEnabled powerHeight showPower showPowerText powerTextLeft powerTextCenter powerTextRight powerTextLeftHidePercentSymbol powerTextCenterHidePercentSymbol powerTextRightHidePercentSymbol powerTextDelimiter powerFontSize powerOffsetX powerOffsetY powerTextLayer powerSmoothFill powerShowTank powerShowHealer powerShowDamager powerBarDetached powerBarBorderEnabled powerBarBorderThickness embedPowerBarIntoHealth barOutlineTexture oocFadeEnabled oocFadeAlpha healthFadeEnabled healthFadeThreshold healthFadeAlpha deadBgEnabled deadBgOffline deadBgR deadBgG deadBgB deadBgA powerTextLeftFontSize powerTextCenterFontSize powerTextRightFontSize powerTextLeftOffsetX powerTextLeftOffsetY powerTextCenterOffsetX powerTextCenterOffsetY powerTextRightOffsetX powerTextRightOffsetY"), prefix = WordList("detachedPower") },
    { key = "dispel", keys = WordList("dispelOverlayEnabled dispelOverlayStyle dispelOverlayOnHealth dispelOverlayAlpha dispelOverlayTrigger dispelOverlayLayer dispelOverlayStrata"), prefix = WordList("dispelSymbol") },
    { key = "text", keys = WordList("showName hideNameOnDeadOffline nameFontSize nameAnchor nameOffsetX nameOffsetY nameTextLayer nameColorMode nameColorR nameColorG nameColorB nameShortenEnabled nameClipSide nameMaxChars nameNoEllipsis showHPText hpFontSize textLeft textCenter textRight hpTextLeftHidePercentSymbol hpTextCenterHidePercentSymbol hpTextRightHidePercentSymbol hpTextLeftAbsorbIcon hpTextCenterAbsorbIcon hpTextRightAbsorbIcon textDelimiter hpTextReverse healthTextDecimals hpTextDecimals hpFullValueShort hpAbsorbIcon hpOffsetX hpOffsetY textLayer hpTextLeftFontSize hpTextCenterFontSize hpTextRightFontSize hpTextLeftOffsetX hpTextLeftOffsetY hpTextCenterOffsetX hpTextCenterOffsetY hpTextRightOffsetX hpTextRightOffsetY") },
    { key = "font", keys = WordList("fontOverride fontOutline useGlobalFontColor fontR fontG fontB colorHealthTextByHealth colorPowerTextByType powerTextColorByType") },
    { key = "range", keys = WordList("rangeFadeEnabled rangeFadeAlpha rangeFadeLayerMode offlineFadeEnabled offlineAlpha") },
    { key = "indicators", keys = WordList("showGroupNumber groupNumberSize groupNumberAnchor groupNumberX groupNumberY groupNumberLayer groupBorderEnabled groupBorderSize groupBorderPadding groupBorderR groupBorderG groupBorderB groupBorderA iconStyle useMidnightIcons roleIconShowTank roleIconShowHealer roleIconShowDPS roleIconStyle leaderIconStyle assistIconStyle raidMarkerStyle readyCheckIconStyle summonIconStyle resurrectIconStyle pvpIconStyle phaseIconStyle roleIconCustomIcon leaderIconCustomIcon assistIconCustomIcon raidMarkerCustomIcon readyCheckIconCustomIcon summonIconCustomIcon resurrectIconCustomIcon pvpIconCustomIcon phaseIconCustomIcon roleIcon roleIconSize roleIconAnchor roleIconX roleIconY roleIconLayer leaderIcon leaderIconSize leaderIconAnchor leaderIconX leaderIconY leaderIconLayer assistIcon assistIconSize assistIconAnchor assistIconX assistIconY assistIconLayer raidMarker raidMarkerSize raidMarkerAnchor raidMarkerX raidMarkerY raidMarkerLayer readyCheckIcon readyCheckSize readyCheckAnchor readyCheckX readyCheckY readyCheckLayer summonIcon summonIconSize summonAnchor summonX summonY summonLayer resurrectIcon resurrectIconSize resurrectAnchor resurrectX resurrectY resurrectLayer pvpIcon pvpIconSize pvpIconAnchor pvpIconX pvpIconY pvpIconLayer phaseIcon phaseIconSize phaseAnchor phaseX phaseY phaseLayer statusText statusTextSize statusTextAnchor statusOffsetX statusOffsetY statusTextLayer statusGhostText statusGhostTextSize statusGhostTextAnchor statusGhostOffsetX statusGhostOffsetY statusGhostTextLayer statusAFKText statusAFKTextSize statusAFKTextAnchor statusAFKOffsetX statusAFKOffsetY statusAFKTextLayer statusAFKTimerText statusAFKTimerTextSize statusAFKTimerTextAnchor statusAFKTimerOffsetX statusAFKTimerOffsetY statusAFKTimerTextLayer statusDNDText statusDNDTextSize statusDNDTextAnchor statusDNDOffsetX statusDNDOffsetY statusDNDTextLayer"), prefix = WordList("si_ statusIcon indicator") },
    { key = "auras", tables = WordList("auras") },
    { key = "aurastyle", default = true },
    { key = "highlight", keys = WordList("targetIndicator targetR targetG targetB aggroEnabled aggroMode dispelEnabled dispelOutlineMode dispelBorderEnabled dispelBorderMode dispelBorderTrigger dispelTrigger"), prefix = WordList("hl") },
    { key = "dstripe", prefix = WordList("debuffStripe") },
    { key = "features", keys = WordList("ciEnabled ciAlpha"), tables = WordList("spellIndicators"), prefix = WordList("ci") },
}

local function NewGroupCopyScopesFallback()
    local scopes = {}
    for i = 1, #GROUP_COPY_CATEGORIES do
        local category = GROUP_COPY_CATEGORIES[i]
        scopes[category.key] = category.default ~= false
    end
    return scopes
end

local function DeepCopyLocal(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        out[DeepCopyLocal(key, seen)] = DeepCopyLocal(item, seen)
    end
    return out
end

local function DeepCopyGroupValue(value)
    if type(value) ~= "table" then return value end
    if type(_G.MSUF_DeepCopy) == "function" then return _G.MSUF_DeepCopy(value) end
    if M and type(M.DeepCopy) == "function" then return M.DeepCopy(value) end
    return DeepCopyLocal(value)
end

local function GroupConfig(kind)
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    return db["gf_" .. tostring(kind)]
end

local function GroupCopyDirtyMask(gf, scopes)
    if not gf or type(scopes) ~= "table" then return nil end
    if scopes.general then return nil end
    if scopes.health or scopes.dispel or scopes.text or scopes.range or scopes.indicators or scopes.highlight or scopes.dstripe or scopes.features then
        return gf.DIRTY_CONFIG or gf.DIRTY_ALL or gf.DIRTY_VISUAL
    end
    local dirty
    if scopes.font then dirty = AddDirty(dirty, gf.DIRTY_FONT) end
    if scopes.auras or scopes.aurastyle then dirty = AddDirty(dirty, gf.DIRTY_AURAS) end
    return dirty or gf.DIRTY_VISUAL
end

local function RefreshGroupCopyLegacy(dstKind, dirty, structural)
    if not dstKind then return false end
    local did = false
    if structural then
        if type(_G.MSUF_GF_RefreshGeometry) == "function" then _G.MSUF_GF_RefreshGeometry(dstKind); did = true end
        if type(_G.MSUF_GF_RefreshUnitBindings) == "function" then _G.MSUF_GF_RefreshUnitBindings(dstKind); did = true end
    end
    if type(_G.MSUF_GF_RefreshVisuals) == "function" then _G.MSUF_GF_RefreshVisuals(dstKind, dirty); did = true end
    return did
end

local function RequestGroupCopyRuntime(dstKind, dirty, structural)
    if not dstKind then return false end
    local apply = (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
    local GP = M and M.GroupPage
    if not apply then
        if GP and type(GP.QueueGF) == "function" then
            return GP.QueueGF(dstKind, structural and "rebuild" or "visual") ~= false
        end
        return false
    end
    if structural then
        if type(apply.RequestGroup) == "function" then
            return apply.RequestGroup(dstKind, "rebuild", "MSUF_ASSISTANT_GROUP_COPY")
        end
        if GP and type(GP.QueueGF) == "function" then
            return GP.QueueGF(dstKind, "rebuild") ~= false
        end
        return false
    end
    if dirty and type(apply.RequestGroupDirtyMask) == "function" then
        return apply.RequestGroupDirtyMask(dstKind, dirty, "MSUF_ASSISTANT_GROUP_COPY")
    end
    if type(apply.RequestGroup) == "function" then
        return apply.RequestGroup(dstKind, "visual", "MSUF_ASSISTANT_GROUP_COPY")
    end
    if GP and type(GP.QueueGF) == "function" then
        return GP.QueueGF(dstKind, "visual") ~= false
    end
    return false
end

local function RefreshGroupCopyRuntime(dstKind, scopes)
    local gf = MSUF and (MSUF.GF or MSUF.GroupFrames)
    local dirty = GroupCopyDirtyMask(gf, scopes)
    local structural = not (type(scopes) == "table" and scopes.general ~= true)
    if RequestGroupCopyRuntime(dstKind, dirty, structural) then
        return
    end
    if not gf then
        RefreshGroupCopyLegacy(dstKind, dirty, structural)
        return
    end
    if type(scopes) == "table" and scopes.general ~= true and type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals(dstKind, dirty)
        if type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout(dstKind) end
        return
    end
    if dstKind and type(gf.Rebuild) == "function" then
        gf.Rebuild(dstKind)
        if type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout(dstKind) end
        return
    end
    if dstKind and type(gf.RefreshGeometry) == "function" then
        gf.RefreshGeometry(dstKind)
        if type(gf.RefreshUnitBindings) == "function" then gf.RefreshUnitBindings(dstKind) end
        if type(gf.RefreshVisuals) == "function" then gf.RefreshVisuals(dstKind, gf.DIRTY_ALL) end
        if type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout(dstKind) end
        return
    end
    if RefreshGroupCopyLegacy(dstKind, dirty or (gf and gf.DIRTY_ALL), structural) then
        if type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout(dstKind) end
        return
    end
    if type(gf.RefreshAll) == "function" then gf.RefreshAll(); return end
    if type(gf.RebuildAll) == "function" then gf.RebuildAll(); return end
    if type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout(dstKind) end
end

local GROUP_AURA_STYLE_ROOT_KEYS = { "dynamicScale", "showTooltip", "iconZoom" }
local GROUP_AURA_STYLE_LANE_KEYS = {
    "iconZoom", "showCooldown", "showCooldownSwipe", "showTooltip",
    "dispelBorderMode", "showDispelBorder", "showDispelSymbol",
    "cooldownSize", "cooldownAnchor", "cooldownX", "cooldownY", "cooldownSwipeReverse", "cooldownDecimalSeconds",
    "showDurationBar", "durationBarHeight", "durationBarDisplay", "durationBarPosition", "durationBarDirection",
    "showStacks", "stackSize", "stackAnchor", "stackX", "stackY", "sortMethod", "sortReverse",
}

local function CaptureGroupAuraStyleFallback(kind)
    local conf = GroupConfig(kind)
    local srcAuras = conf and type(conf.auras) == "table" and conf.auras or {}
    local snapshot = { root = {}, lanes = {} }
    for i = 1, #GROUP_AURA_STYLE_ROOT_KEYS do
        local key = GROUP_AURA_STYLE_ROOT_KEYS[i]
        snapshot.root[key] = DeepCopyGroupValue(srcAuras[key])
    end
    for _, lane in ipairs({ "buff", "debuff", "externals" }) do
        local source = type(srcAuras[lane]) == "table" and srcAuras[lane] or {}
        local values = {}
        snapshot.lanes[lane] = values
        for i = 1, #GROUP_AURA_STYLE_LANE_KEYS do
            local key = GROUP_AURA_STYLE_LANE_KEYS[i]
            values[key] = DeepCopyGroupValue(source[key])
        end
    end
    return snapshot
end

local function ApplyGroupAuraStyleFallback(dstKind, snapshot)
    local dstConf = GroupConfig(dstKind)
    if not (type(dstConf) == "table" and type(snapshot) == "table") then return false end
    dstConf.auras = type(dstConf.auras) == "table" and dstConf.auras or {}
    local dstAuras = dstConf.auras
    for i = 1, #GROUP_AURA_STYLE_ROOT_KEYS do
        local key = GROUP_AURA_STYLE_ROOT_KEYS[i]
        dstAuras[key] = DeepCopyGroupValue(snapshot.root and snapshot.root[key])
    end
    for _, lane in ipairs({ "buff", "debuff", "externals" }) do
        local destination = type(dstAuras[lane]) == "table" and dstAuras[lane] or {}
        dstAuras[lane] = destination
        local source = type(snapshot.lanes) == "table" and snapshot.lanes[lane] or nil
        for i = 1, #GROUP_AURA_STYLE_LANE_KEYS do
            local key = GROUP_AURA_STYLE_LANE_KEYS[i]
            destination[key] = DeepCopyGroupValue(source and source[key])
        end
    end
    return true
end

local function CopyGroupAuraStyleFallback(srcKind, dstKind)
    return ApplyGroupAuraStyleFallback(dstKind, CaptureGroupAuraStyleFallback(srcKind))
end

local function CopyGroupSpellIndicatorStyleFallback(srcKind, dstKind)
    local srcConf, dstConf = GroupConfig(srcKind), GroupConfig(dstKind)
    local gf = MSUF and (MSUF.GF or MSUF.GroupFrames)
    if gf and type(gf.EnsureSpellIndicatorStyle) == "function" then gf.EnsureSpellIndicatorStyle(srcConf) end
    local src = srcConf and type(srcConf.spellIndicators) == "table" and srcConf.spellIndicators or nil
    if not (src and type(dstConf) == "table") then return false end
    dstConf.spellIndicators = type(dstConf.spellIndicators) == "table" and dstConf.spellIndicators or {}
    dstConf.spellIndicators.iconZoom = DeepCopyGroupValue(src.iconZoom)
    dstConf.spellIndicators.iconScale = DeepCopyGroupValue(src.iconScale)
    dstConf.spellIndicators.style = DeepCopyGroupValue(src.style)
    if type(dstConf.spellIndicators.style) == "table" then
        dstConf.spellIndicators.style.iconShape = nil
    end
    if gf and type(gf.EnsureSpellIndicatorStyle) == "function" then gf.EnsureSpellIndicatorStyle(dstConf) end
    return true
end

local function CopyGroupSettingsFallback(srcKind, dstKind, scopes)
    local srcConf = GroupConfig(srcKind)
    local dstConf = GroupConfig(dstKind)
    if not (srcConf and dstConf and srcKind and dstKind) or srcKind == dstKind then return false end
    scopes = (type(scopes) == "table") and scopes or NewGroupCopyScopesFallback()
    local retainedAuraStyle = scopes.auras and CaptureGroupAuraStyleFallback(dstKind) or nil
    local retainedSpellStyle
    if scopes.features and not scopes.aurastyle then
        local gf = MSUF and (MSUF.GF or MSUF.GroupFrames)
        if gf and type(gf.EnsureSpellIndicatorStyle) == "function" then gf.EnsureSpellIndicatorStyle(dstConf) end
        local current = type(dstConf.spellIndicators) == "table" and dstConf.spellIndicators or nil
        retainedSpellStyle = current and {
            iconZoom = DeepCopyGroupValue(current.iconZoom),
            iconScale = DeepCopyGroupValue(current.iconScale),
            style = DeepCopyGroupValue(current.style),
        } or nil
        if retainedSpellStyle and type(retainedSpellStyle.style) == "table" then
            retainedSpellStyle.style.iconShape = nil
        end
    end
    local allowKeys, allowPrefixes, allowTables = {}, {}, {}
    for i = 1, #GROUP_COPY_CATEGORIES do
        local cat = GROUP_COPY_CATEGORIES[i]
        if scopes[cat.key] == true then
            for j = 1, #(cat.keys or {}) do allowKeys[cat.keys[j]] = true end
            for j = 1, #(cat.prefix or {}) do allowPrefixes[#allowPrefixes + 1] = cat.prefix[j] end
            for j = 1, #(cat.tables or {}) do allowTables[cat.tables[j]] = true end
        end
    end
    for key, value in pairs(srcConf) do
        if not GROUP_COPY_EXCLUDE[key] and not GROUP_SHARED_COLOR_KEYS[key] then
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
            if copy then dstConf[key] = DeepCopyGroupValue(value) end
        end
    end
    if retainedSpellStyle and type(dstConf.spellIndicators) == "table" then
        dstConf.spellIndicators.iconZoom = retainedSpellStyle.iconZoom
        dstConf.spellIndicators.iconScale = retainedSpellStyle.iconScale
        dstConf.spellIndicators.style = retainedSpellStyle.style
    end
    if retainedAuraStyle then ApplyGroupAuraStyleFallback(dstKind, retainedAuraStyle) end
    if scopes.aurastyle then
        CopyGroupAuraStyleFallback(srcKind, dstKind)
        CopyGroupSpellIndicatorStyleFallback(srcKind, dstKind)
    end
    RefreshGroupCopyRuntime(dstKind, scopes)
    return true
end
Registry:RegisterAction({
    key = "copy_group",
    label = "Copy Group Frame Options",
    type = "copy",
    combatSafe = false,
    captureSnapshot = true,
    aliases = { "copy party to raid", "copy group frame settings", "copy group settings", "copy raid settings" },
    run = function(args)
        local GP = M and M.GroupPage
        local copyFn = GP and type(GP.CopyGroupSettings) == "function" and GP.CopyGroupSettings or CopyGroupSettingsFallback
        if type(copyFn) ~= "function" then
            return false, "I could not find the Group Frames copy helper."
        end        local src = args and args.source
        if src ~= "raid" and src ~= "mythicraid" then src = "party" end
        local targets = args and args.targets
        if type(targets) ~= "table" or #targets == 0 then
            local target = args and args.target
            targets = target and { target } or {}
        end
        if #targets == 0 then return false, "Which group frame should receive the copied options?" end
        local scopes = args and args.scopes
        if type(scopes) ~= "table" then
            if GP and type(GP.NewGFCopyScopes) == "function" then
                scopes = GP.NewGFCopyScopes()
            else
                scopes = NewGroupCopyScopesFallback()
            end
        end
        local count = 0
        local copiedLabels = {}
        for i = 1, #targets do
            local dst = targets[i]
            if dst ~= "raid" and dst ~= "mythicraid" then dst = "party" end
            if dst ~= src and copyFn(src, dst, scopes) then
                count = count + 1
                copiedLabels[#copiedLabels + 1] = GroupLabel(dst)
            end
        end
        if count == 0 then return false, "I did not copy any group-frame options. Pick a different source and destination." end
        return true, "Done. I copied " .. GroupLabel(src) .. " group-frame options to " .. table.concat(copiedLabels, ", ") .. "." .. GroupCopyScopeSummary(scopes)
    end,
})
