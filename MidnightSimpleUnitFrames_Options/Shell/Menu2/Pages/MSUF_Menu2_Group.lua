local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_Group.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
-- Functions this page calls by their global names: required once at load (a missing
-- one is a wiring bug) and kept in upvalues, so no setting change or drag step resolves them.
M.RequireGlobals(FILE, {
    "MSUF_ShowGroupFrameReloadRequiredPopup",
    "MSUF_GF_EM2_SetActivePreviewKind",
})
local ShowGroupFrameReloadRequiredPopup = MSUF.Require("MSUF_ShowGroupFrameReloadRequiredPopup", FILE)
local SetActivePreviewKind = MSUF.Require("MSUF_GF_EM2_SetActivePreviewKind", FILE)
local ApplyService = MSUF.Require("MSUF_Menu2_ApplyService", FILE)
local C_Timer = M.MenuTimer or C_Timer

-- Menu2 Group page foundation.
-- Owns party/raid/mythicraid option binding and preview sync. Apply work is routed through
-- the shared Menu2 ApplyService.
local W = M.Widgets
local Schema = M.ControlSchema
local T = M.Theme
local ControlGates = M.ControlGates or {}
local Shared = M.UnitSectionsShared or {}
local VT = M.ValueTextList
local WL = M.WordList
local floor = math.floor
local max = math.max
local min = math.min
local Specs = M.GroupSpecs or {}
-- Keep every option domain bound by name. A positional multi-return here made
-- one omitted key shift every following Group dropdown onto the next domain.
-- Explicit reads make additions/removals local and impossible to cascade. The
-- domains this page uses itself are read here; the others are republished on
-- GroupPage by name (SPEC_DOMAINS, at the end of the file).
local SCOPE_VALUES = Specs.SCOPE_VALUES or {}
local GROWTH_VALUES = Specs.GROWTH_VALUES or {}
local GF_STATUS_ICON_SPECS = Specs.GF_STATUS_ICON_SPECS or {}
local GROUP_FRAME_PROVIDER_VALUES = Specs.GROUP_FRAME_PROVIDER_VALUES or {
    { value = "MSUF", text = "MSUF frames" },
    { value = "AUTO", text = "Blizzard frames (WoW settings)" },
    { value = "SHOW", text = "Force Blizzard frames" },
    { value = "NONE", text = "Hide all group frames" },
}
local GROUP_RAID_MANAGER_VALUES = Specs.GROUP_RAID_MANAGER_VALUES or {
    { value = "AUTO", text = "Automatic" },
    { value = "SHOW", text = "Always visible" },
    { value = "MOUSEOVER", text = "Show on mouseover" },
    { value = "HIDDEN", text = "Always hidden" },
}
local SCOPE_LABELS = { party = "Party", raid = "Raid", mythicraid = "Mythic Raid" }
local SCOPE_SHORT_LABELS = { mythicraid = "Mythic" }
local GROUP_SECTION_HEADER_BG = { 0.060, 0.070, 0.130, 0.48 }
local GROUP_SECTION_HEADER_TINTED_BG = { 0, 0, 0, 0.48 }
local function GroupSectionHeaderColor()
    -- Preset headers keep the builder's palette and opacity after lazy build.
    if T.classicAtlas or T.menuAppearancePreset == "midnightDark" then return nil end
    if T.MenuAccentSurfacesTinted and T.MenuAccentSurfacesTinted() then
        local color = T.colors and T.colors.coreSurface
        if color then
            GROUP_SECTION_HEADER_TINTED_BG[1] = color[1]
            GROUP_SECTION_HEADER_TINTED_BG[2] = color[2]
            GROUP_SECTION_HEADER_TINTED_BG[3] = color[3]
            return GROUP_SECTION_HEADER_TINTED_BG
        end
    end
    return GROUP_SECTION_HEADER_BG
end
local PortableControlToken = M.PortableControlToken
-- The Party portrait is fixed to the Party row (never CurrentScope), so its key is exact. Scope-resolved
-- group controls declare none: the catalog rejects a release link whose key names another scope.
-- History stays whole-profile (historyScope = false), as before the key existed.
local function DeclarePartySetting(meta, field)
    meta.settingKey, meta.historyScope = "gf_party." .. field, false
    return meta
end
local function GroupControlMeta(ctx, semanticPath, classification)
    local pageKey = PortableControlToken(ctx and ctx.key or M.activeKey, "gf_unknown")
    local pageDomain = pageKey:gsub("^gf_", "")
    local path = PortableControlToken(semanticPath, "control")
    local identity = "group." .. pageDomain .. "." .. path
    local meta = {
        controlId = "menu2." .. pageKey .. ".group." .. path,
        pageKey = pageKey,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        classification = classification or "setting",
    }
    local field = tostring(semanticPath or ""):match("^field%.(.+)$")
    if field and field:match("^growth%.option%.") then field = "growth" end
    if field and meta.classification == "setting" then meta.setting = M.ControlSchema.GroupKeys(field) end
    local schema = M.ControlSchema
    if semanticPath == "basics.frame_provider" then
        local keys = schema.GroupKeys("enabled").keys
        for _, key in ipairs(schema.GroupKeys("blizzardFallbackMode").keys) do keys[#keys + 1] = key end
        meta.setting = schema.Family(keys)
    elseif semanticPath == "basics.raid_manager" then meta.setting = schema.GroupKeys("raidManagerMode")
    elseif semanticPath == "text.power.show" then
        local keys = schema.GroupKeys("showPowerText").keys
        for _, key in ipairs(schema.GroupKeys("showPower").keys) do keys[#keys + 1] = key end
        meta.setting = schema.Family(keys)
    elseif tostring(semanticPath):match("^sorting%.class_priority%.row%.") then meta.setting = schema.GroupKeys("classOrder")
    elseif tostring(semanticPath):match("^sorting%.role_priority%.row%.") then meta.setting = schema.GroupKeys("roleOrder") end
    -- The control identity describes the visible role. Its command resolves the
    -- currently selected Group scope at runtime, so it is not a static
    -- Search Registry action.
    return meta
end
local function RegisterGroupControl(widget, ctx, semanticPath, label, kind, classification, extra)
    if not widget then return widget end
    local meta = GroupControlMeta(ctx, semanticPath, classification)
    meta.label, meta.kind = label, kind
    if type(extra) == "table" then
        for key, value in pairs(extra) do meta[key] = value end
    end
    if type(M.RegisterSearchWidget) == "function" then M.RegisterSearchWidget(widget, meta) end
    if meta.command and meta.command.write then M.RegisterRuntimeControl(widget, meta, "schema-command") end
    return widget
end
local function ResolveGroupControlMeta(ctx, semanticPath, fallbackPath)
    if type(semanticPath) == "table" then return semanticPath end
    return GroupControlMeta(ctx, semanticPath or fallbackPath)
end
--- Every status icon, not a hand-picked five. The old list named only pvpIcon and the
--- four status texts, so the enable toggle, size, anchor, offset and layer of the role,
--- leader, assist, raid-marker, ready-check, summon, resurrect and phase icons never
--- copied -- only their icon style did, via the seed below. Deriving the value list
--- from the specs keeps a newly added status icon copyable without another edit here.
local GF_STATUS_ICON_COPY_VALUES = {}
for i = 1, #GF_STATUS_ICON_SPECS do
    GF_STATUS_ICON_COPY_VALUES[i] = GF_STATUS_ICON_SPECS[i].value
end
local GF_INDICATOR_COPY_FIELDS = M.CopyFieldsFromSpecs(GF_STATUS_ICON_SPECS, table.concat(GF_STATUS_ICON_COPY_VALUES, " "),
    [[showGroupNumber groupNumberStyle groupNumberSize groupNumberAnchor groupNumberX groupNumberY groupNumberLayer
            groupBorderEnabled groupBorderSize groupBorderPadding groupBorderR groupBorderG groupBorderB groupBorderA
            iconStyle useMidnightIcons roleIconShowTank roleIconShowHealer roleIconShowDPS roleIconStyle
            leaderIconStyle assistIconStyle raidMarkerStyle readyCheckIconStyle summonIconStyle resurrectIconStyle
            pvpIconStyle phaseIconStyle roleIconCustomIcon leaderIconCustomIcon assistIconCustomIcon
            raidMarkerCustomIcon readyCheckIconCustomIcon summonIconCustomIcon resurrectIconCustomIcon
            pvpIconCustomIcon phaseIconCustomIcon levelTextDifficultyColor threatTextColorCurve threatTextBackground]],
    "enabled iconStyle customIcon size anchor x y layer")
local function GF()
    return MSUF and MSUF.GF
end
local function RequestGFPagePreview()
    if type(M.RequestGFPagePreviewForKey) == "function" then
        return M.RequestGFPagePreviewForKey(M.activeKey)
    end
    if type(M.SyncGFPagePreviewForKey) == "function" then
        return M.SyncGFPagePreviewForKey(M.activeKey)
    end
end
local function RefreshGFPreview(kind, opts)
    -- Preview and live group frames have separate render paths. Refresh both when controls
    -- change so the page does not hide a stale runtime configuration.
    local gf = GF()
    if opts and opts.auraOnly == true and gf and type(gf.RefreshPreviewAuras) == "function" then
        gf.RefreshPreviewAuras(kind)
    elseif opts and opts.spellOnly == true and gf and type(gf.RefreshPreviewSpellIndicators) == "function" then
        gf.RefreshPreviewSpellIndicators(kind)
    elseif gf and type(gf.RefreshPreviewLayout) == "function" then
        gf.RefreshPreviewLayout(kind)
    end
    if type(M.RefreshGFNativePreviews) == "function" then
        M.RefreshGFNativePreviews("GF_PAGE_REFRESH")
    end
    -- Targeted Aura/Spell drag refreshes already update the active Edit Mode
    -- dummies directly. Do not queue the page-preview ownership settle too;
    -- that would perform a delayed full ShowPreview for every slider stream.
    if not (opts and (opts.auraOnly == true or opts.spellOnly == true))
        and (type(M.RequestGFPagePreviewForKey) == "function" or type(M.SyncGFPagePreviewForKey) == "function")
    then
        RequestGFPagePreview()
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
local function QueueGF(kind, mode)
    return ApplyService.RequestGroup(kind, mode or "visual", "GF_PAGE")
end
local function QueueGFDirtyMask(kind, dirtyMask)
    if not dirtyMask then return QueueGF(kind, "visual") end
    return ApplyService.RequestGroupDirtyMask(kind, dirtyMask, "GF_PAGE_DIRTY")
end
local function Set(kind, key, value, mode)
    local function Write()
        local conf = Conf(kind)
        local textureKey = key == "barTexture" or key == "barBackgroundTexture" or key == "barBgTexture"
        local activatesTextureOverride = textureKey and type(value) == "string" and value ~= "" and (conf.barTextureOverride ~= true or conf.hlOverride ~= true)
        if conf[key] == value and not activatesTextureOverride then return false end
        conf[key] = value
        if activatesTextureOverride then
            conf.barTextureOverride = true
            conf.hlOverride = true
        end
        QueueGF(kind, mode or "visual")
        if key == "enabled" then ShowGroupFrameReloadRequiredPopup() end
        return true
    end
    return M.RunWithHistory(M.TranslatedHistoryLabel(M.Format("Group %s", tostring(key))),
        "group:" .. tostring(kind) .. ":" .. tostring(key), Write)
end
local function Bool(kind, key, default)
    local value = Val(kind, key, default and true or false)
    return value and true or false
end
local function Num(kind, key, default)
    return tonumber(Val(kind, key, default)) or default or 0
end
local function CurrentScope()
    local scope = M.gfScope or "party"
    return M.NormalizeGroupScope and M.NormalizeGroupScope(scope) or scope
end
local function ScopeLabel(kind)
    return M.Tr(SCOPE_LABELS[kind] or "Party")
end
-- Scope bars, Copy To targets and tooltips translate their label themselves.
local function ScopeShortKey(kind)
    return SCOPE_SHORT_LABELS[kind] or SCOPE_LABELS[kind] or "Party"
end
local function ScopeShortLabel(kind)
    return M.Tr(ScopeShortKey(kind))
end
-- The status line names the scope just selected; the message is translated here.
local function ShowScopeFeedback()
    if M.ShowStatusFeedback then
        M.ShowStatusFeedback(M.Format("%s scope", ScopeShortLabel(M.gfScope)), "info", 1.1, true)
    end
end
local function NormalizeFrameProvider(value)
    if value == "MSUF" then return "MSUF" end
    if value == true or value == "SHOW" or value == "BLIZZARD" then return "SHOW" end
    if value == false or value == "NONE" or value == "HIDE" then return "NONE" end
    return "AUTO"
end
local function FrameProvider(kind)
    if Bool(kind, "enabled", false) then return "MSUF" end
    return NormalizeFrameProvider(Val(kind, "blizzardFallbackMode", "AUTO"))
end
local function FrameProviderInfo(value)
    value = NormalizeFrameProvider(value)
    for i = 1, #GROUP_FRAME_PROVIDER_VALUES do
        local info = GROUP_FRAME_PROVIDER_VALUES[i]
        if info and info.value == value then return info end
    end
end
local function FrameProviderLabel(kind)
    local info = FrameProviderInfo(FrameProvider(kind))
    return M.Tr((info and info.text) or "Blizzard frames (WoW settings)")
end
local function FrameProviderShortLabel(kind)
    local provider = FrameProvider(kind)
    if provider == "MSUF" then return "MSUF" end
    if provider == "SHOW" then return M.Tr("Blizzard forced") end
    if provider == "NONE" then return M.Tr("Hidden") end
    return M.Tr("Blizzard")
end
local function FrameProviderTooltip(kind)
    local info = FrameProviderInfo(FrameProvider(kind))
    return info and (info.tooltip or info.description) or ""
end
--- Scope-synchronized settings. A few options do not describe a scope's own frames but a
--- single shared piece of Blizzard chrome, so there is exactly one of them for Party,
--- Raid and Mythic Raid together. They still live in the three gf_* rows -- profiles,
--- import/export and reset all walk those -- but every write hits all three at once, the
--- same shape the shared group colors on the Colors page use.
local GF_SYNC_KINDS = { "party", "raid", "mythicraid" }
local function SyncedVal(key, default)
    for i = 1, #GF_SYNC_KINDS do
        local conf = Conf(GF_SYNC_KINDS[i])
        if conf and conf[key] ~= nil then return conf[key] end
    end
    return default
end
local function SetSyncedValue(key, value, apply)
    local function Write()
        local changed = false
        for i = 1, #GF_SYNC_KINDS do
            local conf = Conf(GF_SYNC_KINDS[i])
            if conf and conf[key] ~= value then
                conf[key] = value
                changed = true
            end
        end
        if changed and type(apply) == "function" then apply() end
        return changed
    end
    return M.RunWithHistory(M.TranslatedHistoryLabel(M.Format("Group %s", tostring(key))), "group:synced:" .. tostring(key), Write)
end
--- "DEFAULT" is the pre-release spelling of AUTO; map it so a profile from an in-between
--- build keeps its choice instead of resetting. Mirrors the engine normalizer.
local NormalizeRaidManagerMode = MSUF.Require("MSUF_NormalizeRaidManagerMode", FILE)
local function RaidManagerMode()
    return NormalizeRaidManagerMode(SyncedVal("raidManagerMode", "AUTO"))
end
--- No QueueGF: nothing about MSUF's own frames changes, only Blizzard's tab.
local function SetRaidManagerMode(value)
    value = NormalizeRaidManagerMode(value)
    return SetSyncedValue("raidManagerMode", value, function()
        local gf = GF()
        if gf and type(gf.ApplyBlizzardRaidManagerMode) == "function" then
            gf.ApplyBlizzardRaidManagerMode()
        end
    end)
end
local function SetFrameProvider(kind, provider)
    kind = kind or CurrentScope()
    provider = NormalizeFrameProvider(provider)
    local function Write()
        local conf = Conf(kind)
        local nextEnabled = provider == "MSUF"
        local enabledChanged = conf.enabled ~= nextEnabled
        local fallbackChanged = not nextEnabled and NormalizeFrameProvider(conf.blizzardFallbackMode) ~= provider
        if not enabledChanged and not fallbackChanged then return false end
        conf.enabled = nextEnabled
        if not nextEnabled then conf.blizzardFallbackMode = provider end
        QueueGF(kind, "rebuild")
        if enabledChanged or fallbackChanged then ShowGroupFrameReloadRequiredPopup() end
        return true
    end
    return M.RunWithHistory("Group frame provider", "group:" .. tostring(kind) .. ":frameProvider", Write)
end
--- Placement never travels through Copy To: two group headers sharing a placement
--- land on top of each other and the covered one can no longer be dragged. Frames are
--- positioned in MSUF Edit Mode. The anchor family belongs here for the same reason --
--- it decides WHERE the header sits, not what it looks like.
--- raidManagerMode joins them for a different reason: it is already identical in all
--- three scopes by construction (see SetSyncedValue), so copying it would only ever be
--- a no-op that pretends the value is per scope.
--- enabled and blizzardFallbackMode switch a header on or off and need the reload
--- prompt SetFrameProvider shows, so they are set per scope on the page, never copied.
local GF_COPY_EXCLUDE = M.KeySetFromWords [[
    offsetX offsetY point positionMode positionMigrationCount _hlMigrated
    anchorMode anchorPoint anchorToFrame customAnchorFrame attachGap attachOffset
    raidManagerMode enabled blizzardFallbackMode
]]
local GF_SHARED_COLOR_KEYS = M.KeySetFromWords [[
    gfBarMode healthColorMode healthCustomR healthCustomG healthCustomB gfDarkR gfDarkG gfDarkB
    gfUnifiedR gfUnifiedG gfUnifiedB bgR bgG bgB deadBgEnabled deadBgOffline deadBgR deadBgG deadBgB deadBgA
    debuffStripeAlpha debuffStripeColorR debuffStripeColorG debuffStripeColorB targetR targetG targetB
    hlFocusColorR hlFocusColorG hlFocusColorB groupBorderR groupBorderG groupBorderB groupBorderA
    ciAggroColorR ciAggroColorG ciAggroColorB
]]
local GF_COPY_CATEGORIES = {
    { key = "general", label = "Basics", keys = WL [[showPlayer showSolo clickCastEnabled width height spacing growth
            groupFilter sortMode sortByRole roleOrder playerFirstInRole sortRolesAcrossRaid sortAlphabeticalWithinRole
            sortClassPriority classOrder unitsPerColumn maxColumns maxFrames autoTanks preserveRaidGroups reverseFill
            smoothFill chunkedFill frameBarShape slantedBarDirection hideInClientScene hideInHousing
            hideOfflineEnabled hideOfflineInCombat hideOfflineDelay frameScaleEnabled frameScaleMode frameScaleManual
            scaleAt10 scaleAt20 scaleAt25 scaleOver25 layoutTiersEnabled excludeHiddenGroups collapseEmptyGroups
            hideMythicGroupsFiveToEight centerSolo tier10Width tier10Height tier10Position tier10X tier10Y
            tier10Growth tier20Width tier20Height tier20Position tier20X tier20Y tier20Growth tier25Width tier25Height
            tier25Position tier25X tier25Y tier25Growth tier40Width tier40Height tier40Position tier40X tier40Y
            tier40Growth targetsEnabled targetsWidth targetsHeight targetsX targetsY targetsTextSize targetsColumns
            petsEnabled petsWidth petsHeight petsX petsY petsTextSize petsColumns petsMaxCount friendlyBossEnabled
            friendlyBossWidth friendlyBossHeight friendlyBossX friendlyBossY friendlyBossTextSize friendlyBossColumns
            healerManaEnabled healerManaWidth healerManaHeight healerManaX healerManaY healerManaTextSize
            targetsIncludePlayer friendlyBossHealerOnly healerManaShowValue healerManaTextR healerManaTextG
            healerManaTextB nameBarEnabled nameBarHeight nameBarR nameBarG nameBarB nameBarAlpha
            autoScaleIndicatorsOnResize autoScaleAurasOnResize autoScaleTrackedOnResize smallRaidAsParty
            buffCoverageEnabled buffCoverageWild buffCoverageThorns buffCoverageIntellect buffCoverageBlessings
            buffCoverageBlessingPriorities buffCoverageBlessingTank1 buffCoverageBlessingTank2
            buffCoverageBlessingTank3 buffCoverageBlessingHealer1 buffCoverageBlessingHealer2
            buffCoverageBlessingHealer3 buffCoverageBlessingDPS1 buffCoverageBlessingDPS2 buffCoverageBlessingDPS3
            buffCoverageBlessingWARRIOR buffCoverageBlessingPALADIN buffCoverageBlessingHUNTER
            buffCoverageBlessingROGUE buffCoverageBlessingPRIEST buffCoverageBlessingSHAMAN buffCoverageBlessingMAGE
            buffCoverageBlessingWARLOCK buffCoverageBlessingDRUID buffCoverageStamina buffCoverageSpirit
            buffCoverageThornsTankOnly buffCoverageGlow buffCoverageCombat buffCoverageSize buffCoverageAnchor
            buffCoverageX buffCoverageY buffCoverageLayer]] },
    { key = "health", label = "Health & Bars", keys = WL [[gfBarMode healthColorMode healthCustomR healthCustomG
            healthCustomB gfDarkR gfDarkG gfDarkB gfUnifiedR gfUnifiedG gfUnifiedB barTextureOverride barTexture
            barBackgroundTexture barBgTexture hpBarAlpha hpBgAlpha alphaExcludeTextPortrait alphaExcludePredictionBars
            powerBarEnabled powerHeight showPower showPowerText powerTextLeft powerTextCenter powerTextRight
            powerTextLeftHidePercentSymbol powerTextCenterHidePercentSymbol powerTextRightHidePercentSymbol
            powerTextDelimiter powerFontSize powerOffsetX powerOffsetY powerTextLayer powerSmoothFill powerChunkedFill
            powerShowTank powerShowHealer powerShowDamager powerBarDetached powerBarBorderEnabled
            powerBarBorderThickness embedPowerBarIntoHealth barOutlineTexture oocFadeEnabled oocFadeAlpha
            healthFadeEnabled healthFadeThreshold healthFadeAlpha deadBgEnabled deadBgOffline deadBgR deadBgG deadBgB
            deadBgA powerTextLeftFontSize powerTextCenterFontSize powerTextRightFontSize powerTextLeftOffsetX
            powerTextLeftOffsetY powerTextCenterOffsetX powerTextCenterOffsetY powerTextRightOffsetX
            powerTextRightOffsetY]], prefix = WL [[detachedPower]] },
    { key = "dispel", label = "Dispel Overlay", keys = WL [[dispelOverlayEnabled dispelOverlayStyle
            dispelOverlayOnHealth dispelOverlayAlpha dispelOverlayTrigger dispelOverlayLayer dispelOverlayStrata]], prefix = WL [[dispelSymbol]] },
    { key = "text", label = "Text & Name", keys = WL [[showName hideNameOnDeadOffline nameFontSize nameAnchor
            nameOffsetX nameOffsetY nameTextLayer nameColorMode nameColorR nameColorG nameColorB nameShortenEnabled
            nameClipSide nameMaxChars nameNoEllipsis showHPText hpFontSize textLeft textCenter textRight
            hpTextLeftHidePercentSymbol hpTextCenterHidePercentSymbol hpTextRightHidePercentSymbol
            hpTextLeftAbsorbIcon hpTextCenterAbsorbIcon hpTextRightAbsorbIcon textDelimiter hpTextReverse
            healthTextDecimals hpTextDecimals hpFullValueShort hpAbsorbIcon hpOffsetX hpOffsetY textLayer
            hpTextLeftFontSize hpTextCenterFontSize hpTextRightFontSize hpTextLeftOffsetX hpTextLeftOffsetY
            hpTextCenterOffsetX hpTextCenterOffsetY hpTextRightOffsetX hpTextRightOffsetY]] },
    -- Every key the group font override resolves (GroupFrames/MSUF_GroupFrames_DB_Text.lua).
    { key = "font", label = "Font Override", keys = WL [[fontOverride fontOutline fontMonochrome fontSlug fontTextAlpha fontBaselineOffset
        textBackdrop fontShadowOpacity fontShadowDistance fontShadowStrength useGlobalFontColor fontR fontG fontB
        colorHealthTextByHealth colorPowerTextByType powerTextColorByType]] },
    { key = "range", label = "Range Fade", keys = WL [[rangeFadeEnabled rangeFadeAlpha rangeFadeLayerMode offlineFadeEnabled offlineAlpha]] },
    { key = "indicators", label = "Status & Indicators", keys = GF_INDICATOR_COPY_FIELDS, prefix = WL [[si_ statusIcon indicator]] },
    --- No portrait category on purpose: party is the only group scope that owns portrait
    --- settings (CompilePortrait returns a disabled spec for every other kind, and the
    --- Search only registers them for party). There is no second scope to copy them
    --- to, and pushing them into raid/mythicraid would plant exactly the stale imported
    --- keys the engine guards against.
    { key = "auras", label = "Aura Options", description = "Copies Group Aura visibility, layout, filters, exact/category blacklists, Strata " ..
        "and dispel options. Aura Style and the global Appearance theme remain unchanged.", tables = WL [[auras]] },
    { key = "aurastyle", label = "Aura Style", default = true, description = "Copies Buff, Debuff, External Defensive and Spell Icon presentation, " ..
        "including icon zoom, text, swipe, duration bars and ordering. Aura Options, tracked Spell Icons and the global Appearance theme remain unchanged." },
    { key = "highlight", label = "Highlight & Aggro", keys = WL [[targetIndicator targetR targetG targetB aggroEnabled
            aggroMode dispelEnabled dispelOutlineMode dispelBorderEnabled dispelBorderMode dispelBorderTrigger
            dispelBorderShowOn dispelTrigger]], prefix = WL [[hl]] },
    { key = "dstripe", label = "Debuff Stripe", prefix = WL [[debuffStripe]] },
    { key = "features", label = "Corner/Spell", keys = WL [[ciEnabled ciAlpha]], tables = WL [[spellIndicators]], prefix = WL [[ci]] },
}
local function DeepCopy(value)
    local gf = GF()
    if gf and type(gf._DeepCopyTable) == "function" then return gf._DeepCopyTable(value) end
    return M.DeepCopy(value)
end
local function NewGFCopyScopes()
    local scopes = {}
    for i = 1, #GF_COPY_CATEGORIES do
        local category = GF_COPY_CATEGORIES[i]
        scopes[category.key] = category.default ~= false
    end
    return scopes
end
local function GroupCopyDirtyMask(scopes)
    local gf = GF()
    if not gf or type(scopes) ~= "table" then return nil end
    if scopes.general then return nil end
    if scopes.health or scopes.dispel or scopes.text or scopes.range or scopes.indicators or scopes.highlight or scopes.dstripe or scopes.features then
        return gf.DIRTY_CONFIG or gf.DIRTY_ALL or gf.DIRTY_VISUAL
    end
    local dirty
    if scopes.font then dirty = M.ApplyService.AddDirty(dirty, gf.DIRTY_FONT) end
    if scopes.auras or scopes.aurastyle then dirty = M.ApplyService.AddDirty(dirty, gf.DIRTY_AURAS) end
    return dirty or gf.DIRTY_VISUAL
end
local GROUP_AURA_STYLE_ROOT_KEYS = { "dynamicScale", "showTooltip", "iconZoom" }
local GROUP_AURA_STYLE_LANE_KEYS = {
    "iconZoom",
    "showCooldown", "showCooldownSwipe", "showTooltip",
    "dispelBorderMode", "showDispelBorder", "showDispelSymbol",
    "cooldownSize", "cooldownAnchor", "cooldownX", "cooldownY",
    "cooldownSwipeReverse", "cooldownDecimalSeconds",
    "showDurationBar", "durationBarHeight", "durationBarDisplay", "durationBarPosition", "durationBarDirection",
    "showStacks", "stackSize", "stackAnchor", "stackX", "stackY",
    "sortMethod", "sortReverse",
}

local function CaptureGroupAuraStyle(kind)
    local srcAuras = Conf(kind).auras
    if type(srcAuras) ~= "table" then srcAuras = {} end
    local snapshot = { root = {}, lanes = {} }
    for i = 1, #GROUP_AURA_STYLE_ROOT_KEYS do
        local key = GROUP_AURA_STYLE_ROOT_KEYS[i]
        snapshot.root[key] = DeepCopy(srcAuras[key])
    end
    for _, lane in ipairs({ "buff", "debuff", "externals" }) do
        local source = type(srcAuras[lane]) == "table" and srcAuras[lane] or {}
        local values = {}
        snapshot.lanes[lane] = values
        for i = 1, #GROUP_AURA_STYLE_LANE_KEYS do
            local key = GROUP_AURA_STYLE_LANE_KEYS[i]
            values[key] = DeepCopy(source[key])
        end
    end
    return snapshot
end

local function ApplyGroupAuraStyleSnapshot(dstKind, snapshot, activate)
    if type(snapshot) ~= "table" then return false end
    local dstConf = Conf(dstKind)
    dstConf.auras = type(dstConf.auras) == "table" and dstConf.auras or {}
    local dstAuras = dstConf.auras
    if activate == true then dstAuras.renderer = "CUSTOM" end
    for i = 1, #GROUP_AURA_STYLE_ROOT_KEYS do
        local key = GROUP_AURA_STYLE_ROOT_KEYS[i]
        dstAuras[key] = DeepCopy(snapshot.root and snapshot.root[key])
    end
    for _, lane in ipairs({ "buff", "debuff", "externals" }) do
        local destination = type(dstAuras[lane]) == "table" and dstAuras[lane] or {}
        dstAuras[lane] = destination
        local source = type(snapshot.lanes) == "table" and snapshot.lanes[lane] or nil
        for i = 1, #GROUP_AURA_STYLE_LANE_KEYS do
            local key = GROUP_AURA_STYLE_LANE_KEYS[i]
            destination[key] = DeepCopy(source and source[key])
        end
    end
    return true
end

local function CopyGroupAuraStyle(srcKind, dstKind)
    return ApplyGroupAuraStyleSnapshot(dstKind, CaptureGroupAuraStyle(srcKind), true)
end
local function CopyGroupSpellIndicatorStyle(srcKind, dstKind)
    local srcConf = Conf(srcKind)
    local dstConf = Conf(dstKind)
    local gf = GF()
    if gf and type(gf.EnsureSpellIndicatorStyle) == "function" then gf.EnsureSpellIndicatorStyle(srcConf) end
    local src = type(srcConf.spellIndicators) == "table" and srcConf.spellIndicators or nil
    if not src then return false end
    dstConf.spellIndicators = type(dstConf.spellIndicators) == "table" and dstConf.spellIndicators or {}
    dstConf.spellIndicators.iconZoom = DeepCopy(src.iconZoom)
    dstConf.spellIndicators.iconScale = DeepCopy(src.iconScale)
    dstConf.spellIndicators.style = DeepCopy(src.style)
    if type(dstConf.spellIndicators.style) == "table" then
        dstConf.spellIndicators.style.iconShape = nil
    end
    if gf and type(gf.EnsureSpellIndicatorStyle) == "function" then gf.EnsureSpellIndicatorStyle(dstConf) end
    return true
end
--- The Highlight & Aggro category copies the scope's Custom settings flag (hlOverride,
--- prefix hl). The Bars values that flag gates (heal prediction, absorb, outline and
--- highlight thickness, gradients) have to arrive with it: the destination otherwise
--- reads its own seeded values under the new flag. Texture, fill and shape keys belong
--- to the Health & Bars and Basics categories. A source without the flag changes none
--- of the destination's stored values; they are inert under the flag it copies.
local GF_BARS_GATED_COPY_SKIP = M.KeySetFromWords [[
    hpPowerTextOverride barTextureOverride barTexture barBackgroundTexture barBgTexture
    frameBarShape slantedBarDirection powerSmoothFill powerChunkedFill
]]
-- Read through the same hlOverride gate (UF.ConfigScopedValue) but not part of the Bars scope reset set.
local GF_BARS_GATED_COPY_EXTRA = WL [[absorbBarTexture healAbsorbBarTexture]]
local GF_GRADIENT_OWNERSHIP_KEYS = WL [[gradientOverride gradientOverrideVersion gradientOverrideKeys]]
local function CopyGroupBarsGatedValues(srcConf, dstConf)
    if srcConf.hlOverride ~= true then return end
    for key in pairs(M.BarsScopeKeys) do
        if not GF_BARS_GATED_COPY_SKIP[key] then dstConf[key] = DeepCopy(srcConf[key]) end
    end
    for i = 1, #GF_BARS_GATED_COPY_EXTRA do
        local key = GF_BARS_GATED_COPY_EXTRA[i]
        dstConf[key] = DeepCopy(srcConf[key])
    end
    for i = 1, #GF_GRADIENT_OWNERSHIP_KEYS do
        local key = GF_GRADIENT_OWNERSHIP_KEYS[i]
        dstConf[key] = DeepCopy(srcConf[key])
    end
    -- The gradient marks name every value the scope's gradient owns (power directions, gradient colours, ...):
    -- exactly those travel, whatever else the source stores.
    local owned = srcConf.gradientOverrideKeys
    if type(owned) ~= "table" then return end
    for key in pairs(owned) do
        if type(key) == "string" and not GF_COPY_EXCLUDE[key] then dstConf[key] = DeepCopy(srcConf[key]) end
    end
end
local function CopyGroupSettings(srcKind, dstKind, scopes)
    local srcConf = Conf(srcKind)
    local dstConf = Conf(dstKind)
    if not (srcConf and dstConf and srcKind and dstKind) or srcKind == dstKind then return false end
    scopes = (type(scopes) == "table") and scopes or NewGFCopyScopes()
    local retainedAuraStyle = scopes.auras and CaptureGroupAuraStyle(dstKind) or nil
    local retainedSpellStyle
    if scopes.features and not scopes.aurastyle then
        local gf = GF()
        if gf and type(gf.EnsureSpellIndicatorStyle) == "function" then gf.EnsureSpellIndicatorStyle(dstConf) end
        local current = type(dstConf.spellIndicators) == "table" and dstConf.spellIndicators or nil
        retainedSpellStyle = current and {
            iconZoom = DeepCopy(current.iconZoom),
            iconScale = DeepCopy(current.iconScale),
            style = DeepCopy(current.style),
        } or nil
        if retainedSpellStyle and type(retainedSpellStyle.style) == "table" then
            retainedSpellStyle.style.iconShape = nil
        end
    end
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
        if not GF_COPY_EXCLUDE[key] and not GF_SHARED_COLOR_KEYS[key] then
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
    if scopes.general then
        -- Nil means inherit; pairs(srcConf) cannot clear an old destination override.
        dstConf.frameBarShape = srcConf.frameBarShape
        dstConf.slantedBarDirection = srcConf.slantedBarDirection
        local gf = GF()
        local policy = gf and gf.BlessingPriorities
        if policy and (srcKind == "party" or srcKind == "raid") and (dstKind == "party" or dstKind == "raid") then
            for key in pairs(policy.Defaults) do dstConf[key] = srcConf[key] end
        end
    end
    if scopes.highlight then CopyGroupBarsGatedValues(srcConf, dstConf) end
    if scopes.health then
        -- Texture ownership as GF.ResolveBarTexture reads it: an explicit flag travels as is,
        -- a texture the source shows through Custom settings becomes explicit, and no flag
        -- stays no flag, so the destination's Bars page switch keeps governing its textures.
        local override = srcConf.barTextureOverride
        if override == nil and srcConf.hlOverride == true then override = true end
        dstConf.barTextureOverride = override
        -- Copy the effective texture choice without enabling unrelated highlight overrides.
        dstConf.barTexture = override and DeepCopy(srcConf.barTexture) or nil
        dstConf.barBackgroundTexture = override and DeepCopy(srcConf.barBackgroundTexture) or nil
        dstConf.barBgTexture = override and DeepCopy(srcConf.barBgTexture) or nil
    end
    if retainedSpellStyle and type(dstConf.spellIndicators) == "table" then
        dstConf.spellIndicators.iconZoom = retainedSpellStyle.iconZoom
        dstConf.spellIndicators.iconScale = retainedSpellStyle.iconScale
        dstConf.spellIndicators.style = retainedSpellStyle.style
    end
    if retainedAuraStyle then ApplyGroupAuraStyleSnapshot(dstKind, retainedAuraStyle) end
    if scopes.aurastyle then
        CopyGroupAuraStyle(srcKind, dstKind)
        CopyGroupSpellIndicatorStyle(srcKind, dstKind)
    end
    if scopes.features or scopes.aurastyle then
        local gf = GF()
        local spellIndicators = gf and gf.SpellIndicators
        if spellIndicators and type(spellIndicators.InvalidateRuntimeCaches) == "function" then
            spellIndicators.InvalidateRuntimeCaches()
        end
    end
    if scopes.general then
        QueueGF(dstKind, "rebuild")
    else
        QueueGFDirtyMask(dstKind, GroupCopyDirtyMask(scopes))
    end
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
    if not (opts and opts.bg) then opts = M.Assign({ bg = GroupSectionHeaderColor() }, opts) end
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
local function AttachGroupSectionUX(ctx)
    local function Number(n, fallback) return tostring(floor((tonumber(n) or fallback or 0) + 0.5)) end
    local function Word(v, fallback)
        local text = tostring(v or fallback or "")
        return M.Tr(text:sub(1, 1):upper() .. text:sub(2):lower())
    end
    local sections = {
        general = { fields = "showPlayer showSolo clickCastEnabled reverseFill smoothFill chunkedFill frameBarShape slantedBarDirection hideInHousing " ..
            "hideInClientScene hideOfflineEnabled hideOfflineInCombat hideOfflineDelay",
            summary = function(c) return Number(c.width, 120) .. " x " .. Number(c.height, 40) .. " px" end },
        portrait = { prefixes = "portrait", noCopy = true },
        text = { },
        power = { fields = "powerBarEnabled powerHeight powerSmoothFill powerChunkedFill powerShowTank powerShowHealer powerShowDamager " ..
            "powerBarDetached powerBarBorderEnabled powerBarBorderThickness embedPowerBarIntoHealth", prefixes = "detachedPower" },
        range = { fields = "rangeFadeEnabled rangeFadeAlpha rangeFadeLayerMode offlineFadeEnabled offlineAlpha", summary = function(c) return c.rangeFadeEnabled
            and (Number((c.rangeFadeAlpha or 0.4) * 100) .. "%") or "" end },
        transparency = { fields = "hpBarAlpha hpBgAlpha oocFadeEnabled oocFadeAlpha healthFadeEnabled healthFadeThreshold healthFadeAlpha " ..
            "alphaExcludeTextPortrait alphaExcludePredictionBars", summary = function(c) return Number((c.hpBarAlpha or 1) * 100) .. "%" end },
        dispel = { prefixes = "dispelOverlay" },
        dispelSymbol = { prefixes = "dispelSymbol" },
        dstripe = { prefixes = "debuffStripe" },
        layout_advanced = { fields = "growth unitsPerColumn maxColumns preserveRaidGroups collapseEmptyGroups " ..
            "hideMythicGroupsFiveToEight centerSolo smallRaidAsParty" },
        party_targets = { prefixes = "targets" },
        group_pets = { prefixes = "pets" },
        friendly_bosses = { prefixes = "friendlyBoss" },
        healer_mana = { prefixes = "healerMana" },
        buff_coverage = { prefixes = "buffCoverage" },
        blessing_priorities = { fields = [[
            buffCoverageBlessingPriorities buffCoverageBlessingTank1 buffCoverageBlessingTank2
            buffCoverageBlessingTank3 buffCoverageBlessingHealer1 buffCoverageBlessingHealer2
            buffCoverageBlessingHealer3 buffCoverageBlessingDPS1 buffCoverageBlessingDPS2
            buffCoverageBlessingDPS3 buffCoverageBlessingWARRIOR buffCoverageBlessingPALADIN
            buffCoverageBlessingHUNTER buffCoverageBlessingROGUE buffCoverageBlessingPRIEST
            buffCoverageBlessingSHAMAN buffCoverageBlessingMAGE buffCoverageBlessingWARLOCK
            buffCoverageBlessingDRUID
        ]] },
        name_bar = { prefixes = "nameBar" },
        sorting = { fields = "sortMode sortByRole roleOrder playerFirstInRole sortRolesAcrossRaid sortAlphabeticalWithinRole sortClassPriority " ..
            "classOrder autoTanks preserveRaidGroups",
            summary = function(c)
                return Word(c.sortMode, "GROUP") .. (c.playerFirstInRole and (" / " .. M.Tr("Player first")) or "")
            end },
        scaling = { prefixes = "frameScale tier10 tier20 tier25 tier40", fields = "width height spacing scaleAt10 scaleAt20 scaleAt25 scaleOver25 " ..
            "layoutTiersEnabled excludeHiddenGroups autoScaleIndicatorsOnResize autoScaleAurasOnResize autoScaleTrackedOnResize" },
        anchor = { fields = "anchorToFrame anchorPoint x y", noCopy = true },
        auras = { summary = function(c)
            local a = c.auras or {}
            if a.enabled == false then return M.Tr("Disabled") end
            return M.Tr("Buffs") .. " " .. Number(a.buff and a.buff.max, 6) .. " / " .. M.Tr("Debuffs") .. " " .. Number(a.debuff and a.debuff.max, 6)
        end },
    }
    local targets = {}
    for _, scope in ipairs(SCOPE_VALUES) do targets[#targets + 1] = { value = scope.value, text = ScopeShortKey(scope.value) } end
    Shared.AttachSectionUX(ctx, {
        sections = sections, scope = CurrentScope, conf = Conf, label = ScopeShortLabel, targets = targets,
        -- The same switch ApplyScopeEnabledGate greys the scope's page with.
        targetOff = function(scope) return not Bool(scope, "enabled", false) end,
        defaults = function(scope)
            local profile = Shared.FactoryProfile()
            local defaults = profile and profile["gf_" .. scope]
            if defaults then
                -- Authored factory profiles predate the optional blessing policy.
                local gf = GF()
                for key in sections.blessing_priorities.fields:gmatch("%S+") do
                    if defaults[key] == nil then defaults[key] = gf.GetDefault(scope, key) end
                end
                return defaults
            end
            local gf = GF()
            if not (gf and gf.GetDefault) then return nil end
            defaults = {}
            for _, spec in pairs(sections) do
                for _, key in ipairs(Shared.SectionFieldKeys(spec, Conf(scope), {})) do defaults[key] = gf.GetDefault(scope, key) end
            end
            return defaults
        end,
        apply = function(scope, section)
            local fields = section == "dstripe" and "debuffStripeColorR debuffStripeColorG debuffStripeColorB debuffStripeAlpha"
                or section == "healer_mana" and "healerManaTextR healerManaTextG healerManaTextB"
            if fields then
                local current = Conf(scope)
                for _, target in ipairs(SCOPE_VALUES) do
                    local conf = Conf(target.value)
                    for key in fields:gmatch("%S+") do conf[key] = current[key] end
                    QueueGF(target.value, "visual")
                end
            end
            QueueGF(scope, "rebuild")
            RefreshGFPreview()
        end,
    })
end
local function FinalizeScopePage(ctx, builder)
    if ctx.key ~= "gf_priority" then AttachGroupSectionUX(ctx) end
    if type(ApplyScopeEnabledGate) == "function" then M.TrackRefresh(ctx, function() ApplyScopeEnabledGate(ctx) end) end
    if ctx and ctx.SetContentHeight and builder then ctx:SetContentHeight(math.abs(builder.y) + 42) end
end
local OnOffBadge, BadgeNumber, OptionText = M.OnOffBadge, M.BadgeNumber, M.OptionText
local function CreateSectionNotice(sec, topY, buttonLabel, buttonWidth)
    return Shared.CreateSectionNotice(sec, topY, buttonLabel, buttonWidth, "_msuf2GroupFrameGateAlwaysEnabled")
end
local NAV_SUBPAGE_LABELS = M.navSubpageLabels or {}
local GROUP_PAGE_TABS = {
    { key = "gf_layout", label = NAV_SUBPAGE_LABELS.gf_layout or "Layout", width = 64 },
    { key = "gf_bars", label = NAV_SUBPAGE_LABELS.gf_bars or "Dispel Overlay", width = 108 },
    { key = "gf_indicators", label = NAV_SUBPAGE_LABELS.gf_indicators or "Status & Indicators", width = 138 },
    { key = "gf_auras", label = NAV_SUBPAGE_LABELS.gf_auras or "Auras", width = 58 },
    { key = "gf_priority", label = NAV_SUBPAGE_LABELS.gf_priority or "Priority", width = 72 },
}


local function RefreshScopeContext(ctx, previousScope)
    if previousScope ~= M.gfScope and ctx.key == "gf_layout" then
        M.RebuildPageKeepingScroll(ctx.key)
    else
        RefreshContext(ctx)
    end
end
local function AttachStickyScopeHeader(ctx, builder, sec)
    Shared.AttachStickyHeader(ctx, builder, sec)
end
local function PriorityScopeNote(ctx, builder, sec, layout)
    local note = Schema.Build(ctx, sec, {
        { "text", "note", nil, { "Profile-wide · follows the active Party, Raid, or Mythic Raid frame appearance",
            16, layout.noteY, layout.pageW - 32, T.colors.muted },
            meta = GroupControlMeta(ctx, "scope.priority_note"), scope = "group", domain = "layout" },
    }).note
    if note and note.SetJustifyH then note:SetJustifyH("LEFT") end
    AttachStickyScopeHeader(ctx, builder, sec)
end
-- Measures the Page bar and the scope bar; the panel height, the note row and both bars derive from it.
local function ScopeHeaderLayout(builder, priorityMode)
    local pageW = tonumber(builder.width) or 720
    local pageValues = {}
    for i = 1, #GROUP_PAGE_TABS do
        local tab = GROUP_PAGE_TABS[i]
        pageValues[i] = { value = tab.key, text = tab.label, width = tonumber(tab.width) or 72 }
    end
    local pageOpts = {
        values = pageValues,
        width = pageW,
        maxRight = priorityMode and (pageW - 16) or (pageW - 112),
        label = "Page:",
        labelWidth = 64,
        centerY = priorityMode and -24 or -28,
    }
    local pageMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(pageValues, pageOpts)
    local pageBottomY = (pageMetrics and pageMetrics.bottomY) or -40
    local scopeCenterY = min(-60, pageBottomY - 20)
    local scopeValues = {}
    if not priorityMode then
        for i = 1, #SCOPE_VALUES do
            local info = SCOPE_VALUES[i]
            scopeValues[i] = {
                value = info.value,
                text = ScopeShortKey(info.value),
                width = (info.value == "mythicraid") and 86 or 64,
            }
        end
    end
    local scopeMetrics = not priorityMode and W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(scopeValues, {
        width = pageW,
        label = "",
        labelWidth = 0,
        startX = 16,
        centerY = scopeCenterY,
    })
    local noteY = min(-50, pageBottomY - 10)
    local scopeBottomY = (scopeMetrics and scopeMetrics.bottomY) or -72
    return {
        pageW = pageW, pageOpts = pageOpts, scopeValues = scopeValues, scopeCenterY = scopeCenterY, noteY = noteY,
        height = priorityMode and max(70, math.abs(noteY) + 20) or max(92, math.abs(scopeBottomY) + 14),
    }
end
-- The status panel holding the Page bar, the scope bar and Copy To; it takes its slot in the page flow.
local function NewScopePanel(ctx, builder, layout, priorityMode)
    local sec = T.Panel(builder.parent, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    T.ApplySurface(sec, "status")
    sec:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    sec:SetSize(layout.pageW, layout.height)
    sec._msuf2Width = layout.pageW
    if W.RegisterGuidedRegion then
        W.RegisterGuidedRegion(ctx, sec, priorityMode and "Priority Frames workspace" or "Party frame and Copy To", "group_scope")
    end
    builder.y = builder.y - layout.height - 8
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(builder.y) + 28) end
    return sec
end
local function NewScopeSelector(ctx)
    return function(kind)
        if M.NormalizeGroupScope then kind = M.NormalizeGroupScope(kind) end
        local previousScope = M.gfScope
        M.SetMenuStateValue("gfScope", kind or "party")
        if previousScope ~= M.gfScope and W.CloseTextQuickSettings then W.CloseTextQuickSettings() end
        if previousScope ~= M.gfScope then ShowScopeFeedback() end
        local gf = GF()
        SetActivePreviewKind(M.gfScope)
        RequestGFPagePreview()
        if gf and type(gf.PreviewScopeChanged) == "function" then
            gf.PreviewScopeChanged()
        else
            RefreshGFPreview()
        end
        RefreshScopeContext(ctx, previousScope)
    end
end
-- The Copy To popup; its target click copies the selected scope's settings to that scope, in one history step.
local function NewScopeCopyPopup(ctx, copy)
    return Shared.MakeScopeCopyPopup(copy, {
        controlDomain = "group",
        controlPageKey = ctx and ctx.key,
        controlPath = "copy",
        declareControl = function(widget) Schema.Owned(widget, "group", "copy") end,
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
        onPopupCreated = function(popup)
            popup._msuf2GuidedNoScroll = true
            if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, popup, "Copy Party settings", "group_copy_popup") end
        end,
        onTargetClick = function(kind, api, popup)
            local function RunCopy()
                if CopyGroupSettings(CurrentScope(), kind, M.gfCopyScopes) then
                    RefreshContext(ctx)
                    if M.ShowStatusFeedback then M.ShowStatusFeedback(M.Format("Copied to %s", ScopeShortLabel(kind)), "ok", 1.3, true) end
                end
            end
            M.RunWithHistory("Copy Group Settings", "group:copy:" .. tostring(CurrentScope()) .. ":" .. tostring(kind), RunCopy)
            popup:Hide()
        end,
    })
end
local function ScopeSection(ctx, builder, opts)
    opts = opts or {}
    local priorityMode = opts.priorityMode == true
    local layout = ScopeHeaderLayout(builder, priorityMode)
    local sec = NewScopePanel(ctx, builder, layout, priorityMode)
    local SelectScope = NewScopeSelector(ctx)
    sec._msuf2GuidedSelectScope = SelectScope

    local command = sec
    local pageOpts = layout.pageOpts
    pageOpts.getValue = function() return ctx and ctx.key end
    pageOpts.setValue = function(pageKey) if pageKey and pageKey ~= ctx.key then M.SelectPage(pageKey) end end
    Schema.Build(ctx, command, {
        { "scopebar", "page", nil, { pageOpts }, scope = "group", domain = "navigation",
            beforeBind = function(widget) RegisterGroupControl(widget, ctx, "navigation.section.selector", "Page", "segment", "ephemeral") end },
    })

    if priorityMode then
        PriorityScopeNote(ctx, builder, sec, layout)
        return sec
    end

    local copyPopup
    local copy = Schema.Build(ctx, sec, {
        { W.RoleButton and "roleButton" or "topButton", "copy", nil,
            W.RoleButton and { "Copy To", "success", 86, 24 } or { "Copy To", 86, 24, {} },
            anchor = { "TOPRIGHT", sec, "TOPRIGHT", -16, -16 },
            action = function(self) if copyPopup then copyPopup.Show(self) end end,
            meta = GroupControlMeta(ctx, "copy.open", "ephemeral"), scope = "group", domain = "copy" },
    }).copy
    local scopeBtns = {}
    local scopeBar = Schema.Build(ctx, command, {
        { "scopebar", "scope", nil, { { values = layout.scopeValues, width = layout.pageW, label = "", labelWidth = 0,
            startX = 16, centerY = layout.scopeCenterY, getValue = CurrentScope, setValue = SelectScope } },
            scope = "group", domain = "scope",
            beforeBind = function(widget) RegisterGroupControl(widget, ctx, "scope.selector", "Editing", "segment", "ephemeral") end },
    }).scope
    for i = 1, #SCOPE_VALUES do scopeBtns[SCOPE_VALUES[i].value] = scopeBar and scopeBar.buttons and scopeBar.buttons[i] end
    M.gfCopyScopes = (type(M.gfCopyScopes) == "table") and M.gfCopyScopes or NewGFCopyScopes()
    copyPopup = Shared.MakeScopeCopyPopup and NewScopeCopyPopup(ctx, copy)
    RegisterGroupControl(copy, ctx, "copy.open", "Copy To", "button", "ephemeral", { searchIndexed = true }) -- searchable opener
    if type(M.RegisterGuidedCopyPopup) == "function" then
        M.RegisterGuidedCopyPopup("group", ctx.key, M.CreateGuidedCopyOpener(copyPopup, copy))
    end
    sec:SetScript("OnHide", function() if copyPopup then copyPopup.Hide() end end)
    AttachStickyScopeHeader(ctx, builder, sec)
    local function RefreshTop()
        local current = CurrentScope()
        for i = 1, #SCOPE_VALUES do
            local info = SCOPE_VALUES[i]
            if scopeBtns[info.value] and scopeBtns[info.value].SetActive then scopeBtns[info.value]:SetActive(current == info.value) end
        end

    end
    M.TrackRefresh(ctx, RefreshTop)
end
local GroupPage = M.GroupPage or {}
M.GroupPage = GroupPage
M.Assign(GroupPage, {
    Conf = Conf, Val = Val, Set = Set, Bool = Bool, Num = Num, CurrentScope = CurrentScope,
    GROUP_FRAME_PROVIDER_VALUES = GROUP_FRAME_PROVIDER_VALUES,
    GROUP_RAID_MANAGER_VALUES = GROUP_RAID_MANAGER_VALUES,
    FrameProvider = FrameProvider, FrameProviderLabel = FrameProviderLabel, FrameProviderShortLabel = FrameProviderShortLabel,
    FrameProviderTooltip = FrameProviderTooltip, SetFrameProvider = SetFrameProvider,
    SyncedVal = SyncedVal, SetSyncedValue = SetSyncedValue,
    RaidManagerMode = RaidManagerMode, SetRaidManagerMode = SetRaidManagerMode,
    GF_COPY_CATEGORIES = GF_COPY_CATEGORIES, NewGFCopyScopes = NewGFCopyScopes, CopyGroupSettings = CopyGroupSettings,
    ResolveControlMeta = ResolveGroupControlMeta,
})
local function BindScopeToggle(ctx, widget, key, default, mode, semanticPath)
    local args = { "" }
    return Schema.GroupBinding(ctx, widget, { "toggle", key, default, args,
        domain = mode, meta = ResolveGroupControlMeta(ctx, semanticPath, "field." .. tostring(key)) }, "toggle")
end
--- Binds one of two mutually exclusive fill toggles (smooth vs chunked):
--- turning key on turns peerKey off, in one history step named historyField.
local function BindExclusiveScopeToggle(ctx, control, key, peerKey, historyLabel, historyField, refresh)
    M.BindBoolWidget(ctx, control,
        function() return Bool(CurrentScope(), key, false) end,
        function(value)
            value = value == true
            local scope = CurrentScope()
            local function Write()
                local conf = Conf(scope)
                local peerOn = value and conf[peerKey] ~= false
                if conf[key] == value and not peerOn then return false end
                conf[key] = value
                if peerOn then conf[peerKey] = false end
                QueueGF(scope, "visual")
                refresh()
                return true
            end
            if type(M.RunWithHistory) == "function" then
                return M.RunWithHistory(historyLabel, "group:" .. tostring(scope) .. ":" .. historyField, Write)
            end
            return Write()
        end,
        GroupControlMeta(ctx, "field." .. tostring(key)))
    return control
end
local function BindScopeSlider(ctx, widget, key, default, mode, semanticPath)
    local low, high = widget:GetMinMaxValues()
    local args = { "", low, high, widget._msuf2Step or 1 }
    return Schema.GroupBinding(ctx, widget, { "slider", key, default, args,
        domain = mode, meta = ResolveGroupControlMeta(ctx, semanticPath, "field." .. tostring(key)) }, "slider")
end
local function BindScopeDropdown(ctx, widget, key, default, mode, semanticPath)
    local args = { "" }
    return Schema.GroupBinding(ctx, widget, { "dropdown", key, default, args,
        domain = mode, meta = ResolveGroupControlMeta(ctx, semanticPath, "field." .. tostring(key)) }, "dropdown")
end
local function ScopeDropdown(ctx, parent, label, values, width, key, default, mode, x, y, placeWidth, justify, semanticPath)
    local row = { "dropdown", key, default, { label, values, width },
        x and { x, y, placeWidth or width, justify or "LEFT" }, domain = mode }
    -- Callers may supply their complete metadata, including search keys.
    local options = { bind = function(c, widget, spec)
        BindScopeDropdown(c, widget, spec[2], spec[3], spec.domain, semanticPath)
        Schema.Owned(widget, "group", spec.domain or "visual")
    end }
    return Schema.Build(ctx, parent, { row }, options)[key]
end
local function ScopeSlider(ctx, parent, label, minValue, maxValue, step, width, key, default, mode, x, y, placeWidth, justify, semanticPath)
    local row = { "slider", key, default, { label, minValue, maxValue, step, width },
        x and { x, y, placeWidth or width, justify or "CENTER" }, domain = mode }
    local options = { bind = function(c, widget, spec)
        BindScopeSlider(c, widget, spec[2], spec[3], spec.domain, semanticPath)
        Schema.Owned(widget, "group", spec.domain or "visual")
    end }
    return Schema.Build(ctx, parent, { row }, options)[key]
end
local function ScopeColor(ctx, parent, label, width, rKey, gKey, bKey, defaults, mode, x, y, placeWidth, justify, semanticPath)
    defaults = defaults or {}
    local options = { bind = function(c, widget)
        M.BindColor(c, widget,
            function()
                return Num(CurrentScope(), rKey, defaults[1] or 1),
                    Num(CurrentScope(), gKey, defaults[2] or 1), Num(CurrentScope(), bKey, defaults[3] or 1)
            end,
            function(r, g, b)
                local conf = Conf(CurrentScope())
                conf[rKey], conf[gKey], conf[bKey] = r, g, b
                QueueGF(CurrentScope(), mode or "visual")
            end,
            ResolveGroupControlMeta(c, semanticPath, "color." .. tostring(rKey):gsub("[Rr]$", "")))
        Schema.Owned(widget, "group", mode or "visual")
    end }
    return Schema.Build(ctx, parent, {
        { "color", rKey, defaults, { label },
            x and { x, y, placeWidth or width or 220, justify or "LEFT" } },
    }, options)[rKey]
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
    local gateKey = "groupFrameEnabled"
    local enabled = Bool(CurrentScope(), "enabled", false)
    -- Hover reason for every control the turned-off scope locks.
    if W.SetGateDisabledReason and not (W._msuf2GateReasons and W._msuf2GateReasons[gateKey]) then
        W.SetGateDisabledReason(gateKey, function()
            return M.Tr("Frame disabled") .. "\n" .. M.Format("Turn on \"%s\" to change this.", M.Tr("Enable"))
        end)
    end
    if ControlGates.ApplySections then
        ControlGates.ApplySections(ctx, gateKey, enabled, { alwaysEnabledFlag = "_msuf2GroupFrameGateAlwaysEnabled" })
        return
    end
    if wrapper._msuf2GroupFrameGateKey == gateKey and wrapper._msuf2GroupFrameGateEnabled == enabled then return end
    wrapper._msuf2GroupFrameGateKey = gateKey
    wrapper._msuf2GroupFrameGateEnabled = enabled
    ForEachGroupPageControl(wrapper, function(control)
        W.SetControlGateEnabled(control, gateKey, enabled)
    end)
end
-- Spec catalogue domains this page only republishes; each is bound by name.
local SPEC_DOMAINS = WL [[
    BLIZZARD_FALLBACK_VALUES HEALTH_MODES TEXT_MODES DELIMITER_VALUES ANCHORS AURA_ANCHORS SORT_MODES
    GF_BAR_MODES GF_ANCHOR_TO GF_ANCHOR_POINTS STATUS_ICON_ANCHORS GF_STATUS_ICON_VALUES PLACED_INDICATOR_TYPES
    FRAME_EFFECT_TYPES ICON_EFFECT_TYPES SPELL_GROWTH_VALUES CI_SLOT_VALUES CI_SLOT_DEFAULTS
    DISPEL_OVERLAY_STYLES DEBUFF_STRIPE_EDGES
]]
for i = 1, #SPEC_DOMAINS do GroupPage[SPEC_DOMAINS[i]] = Specs[SPEC_DOMAINS[i]] or {} end
M.Assign(GroupPage, {
    SCOPE_VALUES = SCOPE_VALUES,
    GROWTH_VALUES = GROWTH_VALUES,
    GROUP_FRAME_PROVIDER_VALUES = GROUP_FRAME_PROVIDER_VALUES,
    HEALTH_TEXT_MODES = Specs.HEALTH_TEXT_MODES or GroupPage.TEXT_MODES,
    SIMPLE_TEXTURES = Specs.SimpleTextures,
    GF_STATUS_ICON_SPECS = GF_STATUS_ICON_SPECS,
    GF = GF,
    ControlMeta = GroupControlMeta,
    RegisterControl = RegisterGroupControl,
    RefreshGFPreview = RefreshGFPreview,
    QueueGF = QueueGF,
    QueueGFDirtyMask = QueueGFDirtyMask,
    RefreshContext = RefreshContext,
    ScopeSection = ScopeSection,
    BindScopeToggle = BindScopeToggle,
    BindExclusiveScopeToggle = BindExclusiveScopeToggle,
    BindScopeSlider = BindScopeSlider,
    BindScopeDropdown = BindScopeDropdown,
    ScopeDropdown = ScopeDropdown,
    ScopeSlider = ScopeSlider,
    ScopeColor = ScopeColor,
    ScopeLabel = ScopeLabel,
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

-- Lexical collaborators shared by the responsibility modules below this load site.
M.GroupPageParts = {
    PixelLayoutRegion = PixelLayoutRegion,
    W = W,
    Schema = Schema,
    T = T,
    Shared = Shared,
    VT = VT,
    floor = floor,
    max = max,
    min = min,
    GROWTH_VALUES = GROWTH_VALUES,
    DeclarePartySetting = DeclarePartySetting,
    GroupControlMeta = GroupControlMeta,
    RegisterGroupControl = RegisterGroupControl,
    Conf = Conf,
    Val = Val,
    QueueGF = QueueGF,
    Set = Set,
    Bool = Bool,
    Num = Num,
    CurrentScope = CurrentScope,
    RefreshContext = RefreshContext,
    SetSectionHeaderStatus = SetSectionHeaderStatus,
    GroupPage = GroupPage,
}
